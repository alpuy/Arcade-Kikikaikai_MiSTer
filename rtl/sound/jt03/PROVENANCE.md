# jt03 (YM2203) provenance

Vendored from `MiSTer-devel/Arcade-KickAndRun_MiSTer/rtl/ym2203/`, commit
`4ab435aaf3e9319a5703911b4f43f0a38f5de7d8` (2026-09-10) — the whole
directory, since `jt03` (the YM2203-compatible wrapper) shares building
blocks with the rest of jotego's JT12 chip family and cherry-picking risked
missing a dependency.

Same chip and same upstream module (jotego's JT12/JT03) the sibling family
already uses for Fuuki's YM2203 (`references/cpus_and_vendored.md`, Sound
table). **Not yet re-copied from Fuuki's own tree** — Fuuki isn't checked
out on this machine (unlike Psikyo at `/home/seba/mister_skills/repo`), so
this vendoring came from KickAndRun instead, which carries the same
upstream module. Re-pointing to Fuuki's copy (which "carries integration
fixes" per convention) is an open item, not yet done — flagged in
`docs/ROADMAP.md`.

Upstream: jotego (Jose Tejada, `@topapate`), JT12 project. License:
GPL-3.0-or-later, stated in full in each file header (e.g. `jt03.v`: "GNU
General Public License as published by the Free Software Foundation,
either version 3 of the License, or (at your option) any later version").
This is why the project's own `LICENSE` is GPL-3.0 — see `THIRD-PARTY.md`.

Only `jt03.v` (+ its `jt12_*` dependencies) will actually be instantiated.
`jt10.v`/`jt10_acc.v`/`jt10.yaml` (the YM2610 wrapper, used by Psikyo, not
this project) and the `adpcm/` directory (YM2610-only ADPCM, not present on
the YM2203) came along unpruned rather than risk missing a shared
dependency; pruning to the exact `jt03` dependency graph is deferred to
Phase 3 (Sound) once the real instantiation is known to build clean.

## Status

- [x] Source vendored
- [~] Elaborates clean under `iverilog` once the full dependency set is
      included (`jt03.v` alone is missing `mixer/jt12_interpol.v` →
      `mixer/jt12_comb.v`; the whole `mixer/` directory is needed, not just
      the top-level files — noted here since it wasn't obvious from `jt03.v`
      alone).
- [x] **Smoke test passes, root cause found and understood**:
      `sim/jt03_spike/` resets, issues FM register writes, and sees 16,692
      `snd_sample` pulses over the run. Initially saw *zero* pulses — traced
      by hierarchical signal monitoring to `jt12_reg.v`'s operator
      round-robin counter (`cur_ch`/`cur_op`, feeding the `zero`/
      `snd_sample` strobe): it has **no reset branch**, only a
      self-referential next-state function
      (`always @(posedge clk) if (clk_en) {cur_op,cur_ch} <= {next_op,
      next_ch};`, `jt12_reg.v:213-217`), so a 4-state simulator's X
      power-up state for those registers never resolves to a real value —
      `next` is computed from `cur_ch`/`cur_op` themselves, so X propagates
      forever. This is **not a hardware defect**: real silicon/an FPGA
      powers up to a real (if arbitrary) 0 or 1, never a symbolic unknown,
      and this project's own `scripts/run_sim.sh` already documents needing
      `+initreg=r+0` for exactly this jotego-core pattern ("their un-reset
      pipelines are X in ModelSim and zero on the board"). Fixed for this
      spike with a simulation-only hierarchical initializer in the
      testbench (not a change to any vendored file); the real project
      tooling's `+initreg=r+0`/`+initmem=r+0` `vlog` flags are expected to
      cover this the same way once run under ModelSim.
- [ ] Own testbench run unchanged (jotego ships none in this subset)
- [ ] Exact `jt03` dependency subset confirmed and unused files pruned
- [ ] Verified against MAME's `ym2203_device` output for this game's
      register-write stream (Phase 3)
- [x] **Synthesizes on the real Cyclone V, standalone Fmax measured**
      (`synth_check/`, Phase 0 exit criterion 4): same wrapper pattern as
      `tv80`'s and the M6801 core's, every port passed straight through,
      full unpruned dependency set (see above) included. **Fmax 99.36 MHz
      (Slow 1100mV 100°C), 94.13 MHz (Slow 1100mV -40°C, worst case)** —
      against the 3 MHz target, no danger of being the Fmax-limiting block.
      686 ALMs, 1,485 registers, 4 RAM blocks, 1 DSP block — the only one of
      the three vendored components using either.
