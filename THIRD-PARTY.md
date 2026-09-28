# Third-party components

## Project license: GPL-3.0-or-later

The strictest dependency obligates it: jotego's `jt03` (YM2203) is
GPL-3.0-or-later. GPL-2.0-or-later dependencies (the Template_MiSTer
framework) permit relicensing the combined work under GPL-3.0. The one open
question — the M6801 core's own license — is below.

## Template_MiSTer / `sys/`

- Upstream: https://github.com/MiSTer-devel/Template_MiSTer
- Commit: `3ea1134cf05d62c2b1db30362277a823d739ced2` (2026-08-26)
- License: GPL-2.0-or-later (file headers: "either version 2 of the
  License, or (at your option) any later version")
- Taken: `sys/` entirely, unmodified. Top-level project files
  (`Template.*`) renamed and re-templated per project convention; `sys/`
  itself never edited.
- Obliges: source availability, same license (or later) on redistribution.

## tv80 (Z80 CPU core)

- Upstream: https://github.com/MiSTer-devel/Arcade-KickAndRun_MiSTer
  (`rtl/tv80/`), itself vendoring Guy Hutchison's TV80
- Commit: `4ab435aaf3e9319a5703911b4f43f0a38f5de7d8` (2026-09-10)
- License: MIT-style permissive (per-file headers)
- Taken: `tv80_alu.v`, `tv80_core.v`, `tv80_mcode.v`, `tv80_reg.v`,
  `tv80n.v`, `tv80s.v`, unmodified.
- Obliges: attribution (license text retained in each file). No copyleft.
- See `rtl/cpu/tv80/PROVENANCE.md`.

## jt03 / JT12 family (YM2203 sound core)

- Upstream: jotego (Jose Tejada), JT12 project, via
  `MiSTer-devel/Arcade-KickAndRun_MiSTer` (`rtl/ym2203/`)
- Commit: `4ab435aaf3e9319a5703911b4f43f0a38f5de7d8` (2026-09-10)
- License: GPL-3.0-or-later (per-file headers)
- Taken: the whole `rtl/ym2203/` directory (as `rtl/sound/jt03/` here),
  unmodified, to avoid missing a shared dependency; only `jt03.v` and its
  true dependency subset are actually instantiated.
- Obliges: this is the dependency that sets the project's overall license
  to GPL-3.0.
- See `rtl/sound/jt03/PROVENANCE.md`.

## M6801 CPU core (protection/IO MCU)

- Upstream: `MiSTer-devel/Arcade-KickAndRun_MiSTer` (`rtl/mcu/`)
- Commit: `4ab435aaf3e9319a5703911b4f43f0a38f5de7d8` (2026-09-10)
- License: GPL-2.0, per that repository's top-level `LICENSE` file (plain
  FSF boilerplate text). **Open question**: `M6801_core.sv` carries no
  separate per-file header granting "or later" — unlike Template_MiSTer's
  files, which state that grant explicitly. If this component is GPL-2.0
  **only** (not "or later"), combining it with jt03's GPL-3.0-or-later code
  in one program is the well-known GPLv2-only/GPLv3 incompatibility. This
  project proceeds on the same basis KickAndRun itself already does
  (vendoring both GPL-2.0 and GPL-3.0-or-later modules under one blanket
  repo license) — standard, if not rigorously resolved, practice across
  MiSTer-devel arcade cores. Revisit if it ever matters (e.g. upstream
  clarifies the license, or this component is rewritten from scratch).
- Taken: `M6801_core.sv` + `mcu.v`, unmodified, kept pristine as a reference
  baseline; a new peripheral wrapper for this game is written from scratch
  against it.
- See `rtl/mcu/vendor/PROVENANCE.md`.

## screen_rotate_two (HDMI rotation)

- Upstream: `MiSTer-devel/Arcade-Psikyo_MiSTer` (`rtl/video/screen_rotate_two.sv`),
  itself from Sorgelig's `Arcade-SKNS_MiSTer`
- Commit: `4ca386b4eeea95c649c485801452385419d3b5e6`
- License: GPL-2.0-or-later (file header: "either version 2 of the
  License, or (at your option) any later version")
- Taken: unmodified.
- Obliges: source availability, same license (or later) on redistribution.
- See `rtl/video/PROVENANCE.md`.

## Reference material (not code)

- **MAME** (`src/mame/taito/kikikai.cpp` and the devices it instantiates,
  including `cpu/m6800/m6801.cpp`): the accuracy reference this whole
  project is built against. No MAME source is compiled into this core;
  it's read as a specification. BSD-3-Clause (MAME's own license), not
  redistributed here beyond citation.

## Release checklist

- [ ] Every vendored directory's `PROVENANCE.md` current (commit, license,
      local changes)
- [ ] `sys/` unmodified (diff against `Template_MiSTer` at the pinned
      commit)
- [ ] `LICENSE` text matches the stated project license
- [ ] Every file of this project's own RTL carries an
      `SPDX-License-Identifier` header
- [ ] Open license question above (M6801 core) revisited, or explicitly
      accepted as-is
