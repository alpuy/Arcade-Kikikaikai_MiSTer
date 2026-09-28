# M6801 core provenance

Vendored from `MiSTer-devel/Arcade-KickAndRun_MiSTer/rtl/mcu/`
(`M6801_core.sv` + `mcu.v`), commit `4ab435aaf3e9319a5703911b4f43f0a38f5de7d8`
(2026-09-10). `mcu.v` is kept locally as `mcu_upstream_reference.v` (the
`*_upstream_reference.*` naming this project uses for pristine copies kept
beside a local rewrite, and excluded from the general RTL sweep for the
same reason — it has external dependencies, KickAndRun's own `rtl/fw/`
helpers, that were never vendored since nothing here builds on it directly).

No sibling core (Psikyo/Fuuki/Seta/MS32/KonamiGX) has ever vendored an
MC6801-family part — the one prior precedent in `cpus_and_vendored.md`
("small MCUs... reimplemented as an RTL FSM from MAME's high-level
simulation") doesn't apply here: Kiki KaiKai's MC6801U4 has a real dumped
mask ROM (Raki, January 2024) that MAME now runs as actual CPU code, not a
software simulation of its responses, so a real CPU core is needed, not an
FSM. KickAndRun is the only existing MiSTer core with a synthesizable
MC6801, for the *same chip family* (Taito A85/A87-era MC6801U4).

`M6801_core.sv` carries no separate per-file license header; governed by
KickAndRun's repository-level `LICENSE` (GPL-2.0, plain FSF text, no
"or-later" grant in that file). See `THIRD-PARTY.md` for what this implies
for the project's overall license.

**Kept pristine in `vendor/` — not built on directly.** Kiki KaiKai's MCU
speaks a different port protocol than KickAndRun's own game (edge-sensitive
address/data/strobe handshake on ports 2-4, detailed in
`docs/HARDWARE_NOTES.md`), so `vendor/mcu.v`'s peripheral wrapper doesn't
fit as-is. A new wrapper (`rtl/mcu/kikikai_mcu.sv`, not yet written)
instantiates `vendor/M6801_core.sv` directly and implements Kiki KaiKai's
own handshake from scratch, against the MAME driver's `mcu_port1/2/3/4_w/r`
handlers as literal spec. This mirrors the sibling convention "instantiate
the CPU kernel directly and own the bus interface" (TG68K.vhd's async
wrapper is unused for the same reason in every 68k core).

`vendor/M6801_core.sv`'s own instruction timing is exercised by exactly one
other project (KickAndRun) and only for a different MCU firmware — treat as
unproven until this project's own boot spike validates it independently
(same discipline `mister-core-cpu-spike` applies to any vendored CPU core).

## Status

- [x] Source vendored, pristine
- [x] Minimal boot spike written and run (`sim/m6801_spike/`, plain
      LDAA/STAA/BRA, reset vector at `$FFFE`): PASS. Originally run only
      under `iverilog`/`vvp`, which printed ~90 "sorry: constant selects in
      always_* processes are not currently supported (all bits will be
      included)" warnings compiling this file (lines 182, 217, 269, 583,
      892 — status-register/flag bit extraction inside the ALU and
      condition-code logic) — Icarus was *approximating* some of the
      core's own logic, not simulating it exactly, so the pass was weaker
      evidence than it looked. **Re-run under Verilator 5.020** (installed
      this session, `scripts/run_verilator.sh m6801_spike`,
      `sim/m6801_spike/verilator.files`): same PASS, **zero warnings of any
      kind** in the build log — Verilator does not share `iverilog`'s
      constant-select limitation. This properly closes that caveat for what
      this spike actually exercises.
- [x] **Flag-setting arithmetic and conditional branching** (Phase 0 exit
      criterion 1, the gap flagged above): extended the same spike with
      `ADDA`/`SUBA` (setting `Z`) and two `BEQ`s — one that must NOT branch
      (`Z=0` after `5+3=8`), one that must (`Z=1` after `8-8=0`) — landing
      on one of three distinct memory markers so a wrong decision in either
      direction is unambiguous, not just "didn't crash". **PASS under both
      `iverilog` and Verilator** (still zero warnings under Verilator): both
      `BEQ`s decided correctly. Condition-code logic and conditional
      branching are no longer untested.
- [ ] Full opcode/timing coverage beyond `LDAA`/`STAA`/`ADDA`/`SUBA`/`BEQ`/
      `BRA` — the 6801-specific `MUL`/`ABX`/`PSH X`/`PUL X` and the rest of
      the flag-setting paths the `iverilog` constant-select warnings touch
      remain unexercised. Not pursued further this session: proportionate
      next step, not a blocker for anything currently planned (Phase 3's
      MCU wrapper only needs the port-handshake opcodes the real dumped
      firmware actually uses, which a disassembly pass would identify
      precisely rather than guessing which of the 82 opcodes to test).
- [x] **New peripheral wrapper written for Kiki KaiKai's port 1-4
      handshake** (`rtl/mcu/kikikai_mcu.sv` — the chip's own register block:
      ports 1-4 with real DDR-gated in/out, the P3CSR/IS3 latch-on-strobe
      mechanism, `$40-$ff` internal RAM gated by the RAM Control Register's
      enable bit, `$f000-$ffff` ROM; `rtl/mcu/kikikai_handshake.sv` — the
      game-specific board glue reimplemented from `mcu_port1/2/3/4_w/r` as
      literal spec, per this file's own plan above).
- [x] **Real dumped MC6801U4 ROM (Taito A85-01,
      `a85-01_jph1020p.h8`) loads and boots** (`sim/kikikai_mcu_boot/`).
      **The main-CPU↔MCU shared-RAM handshake matches a MAME trace
      access-by-access for the first 22,117 of 23,997 captured accesses**
      (every access the RTL made in that window; the run just ended there),
      compared the same way as the main CPU's own boot trace — writes and
      non-ROM reads strictly in order, ROM fetches as a superset. Two real
      bugs found and fixed this way, not assumed correct: the register-file
      write `case` wasn't gated by the I/O address range, so RAM writes to
      any address whose low 5 bits happened to alias a port register (e.g.
      `$83`, `$a3` — ordinary firmware RAM use) silently corrupted that
      register; and the IS3 latch and the main register file were two
      separate `always_ff` blocks both driving `port3_latched`/`p3csr[7]`,
      an undefined multi-driver conflict once merged into one block. A
      third, unrelated bug was in the *testbench*, not the RTL: `p1_in` was
      tied to `8'hFF` assuming "idle", without accounting for
      `in_p1_cb().invert()` on the real port — idle is `8'h00` once
      inverted.
- [x] **Synthesizes on the real Cyclone V, standalone Fmax measured**
      (`synth_check/`, Phase 0 exit criterion 4): same wrapper pattern as
      `tv80`'s, every port passed straight through, same device settings.
      **Fmax 90.44 MHz (Slow 1100mV 100°C), 89.23 MHz (Slow 1100mV -40°C,
      worst case)** — against the 3 MHz target, no danger of being the
      Fmax-limiting block. 579 ALMs, 175 registers, 0 block RAM, 0 DSP.
- [x] **Runs on `clk_sys` with a clock enable, source unchanged.** The
      core's own `hold` input already gates every clocked block (reset
      still takes priority), so `kikikai_mcu.sv` drives `hold` with
      `~cen` and the core stays pristine — no derived MCU clock.
      `sim/kikikai_mcu_clk/` runs the real ROM at a 1-in-8 enable with a
      registered ROM read: its trace is byte-identical to the
      single-clock boot trace, and all 275 writes still match MAME's in
      order.
