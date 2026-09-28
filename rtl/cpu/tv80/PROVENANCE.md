# tv80 provenance

Vendored from `MiSTer-devel/Arcade-KickAndRun_MiSTer/rtl/tv80/`, commit
`4ab435aaf3e9319a5703911b4f43f0a38f5de7d8` (2026-09-10). KickAndRun is not
one of this project's sibling cores (Psikyo/Fuuki/Seta/MS32/KonamiGX) — it's
the closest existing MiSTer core for the same MAME driver family
(`src/mame/taito/kikikai.cpp`), used as the source per
`cpus_and_vendored.md`'s "no sibling has this module" fallback.

Upstream origin (per file headers): TV80, Guy Hutchison, 2004
(`ghutchis@opencores.org`), itself a Verilog port of Daniel Wallner's VHDL
T80 (the same core the sibling cores vendor directly as VHDL — see
`references/cpus_and_vendored.md`'s CPU table). MIT-style permissive
license, stated in full in each file header. No copyleft obligation.

**Deliberate deviation from "copy from the sibling that last proved the
module"**: the sibling family's Z80 source is T80.vhd (VHDL), not this
Verilog port. Kept as tv80 anyway — decision recorded in
`docs/ROADMAP.md`'s component reuse map, open to revisiting if the VHDL/
Verilog mix becomes awkward in this project's toolchain.

Files kept as vendored (`TV80.qip` lists the compile set): `tv80_alu.v`,
`tv80_core.v`, `tv80_mcode.v`, `tv80_reg.v`, `tv80n.v`, `tv80s.v`. Both
`tv80n` and `tv80s` wrap the same `tv80_core` and expose the same external
`wait_n`; the difference is output registration (`tv80n`: negedge-triggered,
glitch-free without an explicit clock enable; `tv80s`: posedge-triggered,
takes an explicit `cen` input) — not wait-state capability, corrected here
after reading the source (see "Status" below; the project's earlier guess
that only one variant supported wait states was wrong).

Two instances needed (main + sound CPU), unmodified upstream source, distinct
instantiations.

## Status

- [x] Source vendored
- [x] `wait_n` confirmed to gate the core's own T-state advance, not just be
      wired through: `tv80_core.v:1253,1263` — `tstate[2] && wait_n==1'b0`
      holds (the state-advance branch is skipped) and is resampled every
      `cen`-qualified clock; `tstate[2] && wait_n==1'b1` is what allows data
      capture and the state machine to proceed to T3. Level-sensitive,
      resampled every cycle, driven off internal state — matches real Z80
      WAIT semantics and the project's own "derive WAIT_n timing from
      internal T-state behaviour" lesson (`docs/LESSONS_LEARNED.md`,
      `[Kikikaikai]`).
- [x] Minimal boot/WAIT spike written and run (`sim/tv80_spike/`, `tv80s`):
      boots from reset, executes a memory write, executes a read held with
      `wait_n=0` for one cycle by the testbench, and writes the captured
      value back — PASS, correct data survives the stall. Run with
      `iverilog`/`vvp` (ModelSim not available in this environment — see
      `docs/LESSONS_LEARNED.md`, `[Kikikaikai]`), not yet re-run under the
      project's normal ModelSim toolchain.
- [x] **Boots the real `kikikai` program ROM and matches MAME's own Z80
      execution** (`sim/maincpu_boot/`, Phase 0 exit criterion 2): `tv80s`
      wired to a real `main_map` bus model (fixed ROM + 6-bank window +
      mainram/sharedram/plain RAM, MAME-behavior-accurate — not yet
      hardware-exact, no sound-CPU WAIT contention modeled, that's Phase 2),
      loaded from the actual verified `kikikai` romset. Diffed against a real
      `mame_boot_trace.py` capture over 20,000 bus accesses via
      `compare_boot_trace.py`: **4,993/4,993 writes match in address, lanes,
      data and order; 4,989/4,989 non-ROM reads match in order; all 42
      distinct ROM reads in the window were also made by the RTL.** No
      divergence found — real, strong evidence, not just a smoke test.
- [ ] Full opcode/timing coverage beyond what this boot sequence exercises
      (no upstream testbench ships with this file set)
- [x] **Measured CPI on real game code** (`sim/cpi_check/`, Phase 0 exit
      criterion 3): the boot sequence runs correctly (matching MAME, see
      above) until roughly PC `$4820`, where it enters a tight 2-instruction
      polling loop and never leaves — **not a bug**: this bus model has no
      MCU yet (Phase 3), and the loop is genuinely the board's own code
      waiting on the MC6801U4's shared-RAM handshake
      (`docs/HARDWARE_NOTES.md`, "Protection / IO MCU"), which real hardware
      and MAME's MCU emulation satisfy and this simplified model cannot. A
      diagnostic run (PC sampled every 100,000 cycles, all clustered in
      `$4820-$4837`) confirmed this before spending further time on it —
      the process looked hung at 99.9% CPU for 13 minutes; it was, in a
      real infinite loop, not merely slow. The loop body is itself real
      game code (exactly what the board executes every time it polls the
      MCU), so it's a legitimate, self-contained CPI sample: **measured
      over iterations 100-200, CPI = 10.5 (21 cycles / 2 instructions per
      iteration)**. 100% execution, 0% memory-stall, because this bus model
      has no WAIT contention yet — that split only becomes meaningful once
      Phase 2's real shared-RAM arbiter exists. A gameplay-representative
      CPI (not a 2-instruction poll loop) needs Phase 3's MCU wrapper to
      get the boot sequence past this point at all.
      Narrows Phase 3's scope usefully: the MCU dependency kicks in by
      `$4820`, early in the boot sequence. The exact address the loop polls
      (very likely inside `sharedram`, `E800-E8FF`) wasn't pinned down
      exactly; worth confirming with a disassembly pass before Phase 3
      starts.
- [x] **Synthesizes on the real Cyclone V, standalone Fmax measured**
      (`synth_check/`, Phase 0 exit criterion 4): a bare wrapper passing
      every `tv80s` port straight through (nothing optimized away as
      unused), same FAMILY/DEVICE/package/pin-count/speed-grade as the
      DE10-nano (5CSEBA6U23I7), compiled via the Docker Quartus fallback —
      no `.sdc` needed, Quartus's default Fmax Summary derives a clock from
      the `CLK` port on its own. **Fmax 82.61 MHz (Slow 1100mV 100°C), 80.63
      MHz (Slow 1100mV -40°C, worst case)** — against the actual 6 MHz
      target this project needs, `tv80` alone has no realistic chance of
      being the Fmax-limiting block. 924 ALMs, 358 registers, 0 block RAM,
      0 DSP. Isolated measurement — says nothing about Fmax once integrated
      with the rest of the design and its routing congestion.
