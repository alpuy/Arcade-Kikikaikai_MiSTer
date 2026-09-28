# Kiki KaiKai core for MiSTer

A MiSTer FPGA core for Taito's Kiki KaiKai (1986) arcade hardware (MAME's
`src/mame/taito/kikikai.cpp`), built with Quartus Prime 17.0.2 Lite for the DE10-nano.

**Status: playable on real hardware.**

## Contents

- [Games](#games)
- [Hardware](#hardware)
- [Installation](#installation)
- [Controls](#controls)
- [Features](#features)
- [Compiling](#compiling)
- [Layout](#layout)
- [Acknowledgements](#acknowledgements)
- [License](#license)

## Games

| Name | Year | Manufacturer |
|-|-|-|
| KiKi KaiKai (Japan) — `kikikai` | 1986 | Taito |

Targets one board (Taito A85) and one set. Kick and Run/Mexico 86 (a related but different
board) is already covered by a separate MiSTer-devel project. The Knight Boy bootlegs
(`knightb`/`knightba`, a different protection chip) are not supported.

## Hardware

| Chip | Function |
|-|-|
| Z80 (×2) | main CPU, sound CPU (`tv80`) |
| YM2203C | FM + SSG sound (`jt03`) |
| MC6801U4 ("PS4", Taito A85-01) | protection + coin/input IO, real chip, not simulated |
| Sprite pipeline (no tilemap, no CRTC) | video, per-scanline rendering |

256×224 visible, 6 MHz pixel clock, HTOTAL 384, VTOTAL 264, 15.625 kHz/59.19 Hz, `ROT90`
(vertical cabinet).

## Installation

- Copy the `.rbf` from `releases/` to `_Arcade/cores`.
- Copy `releases/KiKi KaiKai.mra` to `_Arcade`.
- Put the MAME `kikikai` ROM set (your own dump, not included) at `games/mame/kikikai.zip`.

## Controls

8-way joystick, button 1 (Ofuda — talisman throw), button 2 (Oharai-bo — rod swing), start,
coin, service, pause. DIP switches are set from the `.mra`'s OSD `DIP` page.

## Features

- DIP switches and inputs from the `.mra`
- Audio: FM and SSG mixed to match the reference chip's own balance
- HDMI rotation (Orientation: Auto/Off/CW/CCW)
- HDMI scaling (integer scale, crop, crop offset)
- Audio mix (Mono, None, 25%, 50%)
- Pause, CPU suspended (video and sound keep running)

Not yet implemented: CRT offset (no on-chip RAM budget left for the line buffer it needs), flip
screen, hiscore saving, savestates.

## Compiling

Quartus Prime 17.0.2 Lite:

```
python scripts/build_staged.py
```

builds a clean out-of-tree snapshot of the current commit and reports fit and timing.
`scripts/deploy.py` copies the result to a MiSTer over the network (needs a `mister.env`, see
that script). `scripts/validate_mra.py` checks a `.mra` file's structure.

## Layout

Standard [Template_MiSTer](https://github.com/MiSTer-devel/Template_MiSTer) structure:

| path | contents |
| - | - |
| `sys` | MiSTer framework, vendored from the template, never edited |
| `rtl` | core source; vendored modules carry a `PROVENANCE.md` |
| `releases` | `.rbf` and `.mra` files |
| `scripts` | build and deploy tooling |

## Acknowledgements

- **Sorgelig** and the **MiSTer-devel team** for the
  [Template_MiSTer](https://github.com/MiSTer-devel/Template_MiSTer) framework, and for
  `screen_rotate_two` (from `Arcade-SKNS_MiSTer`, via `Arcade-Psikyo_MiSTer`).
- The **MAMEdev team** — Ernesto Corvi (original driver author) and contributors, including
  mamehaze's MC6801U4 hookup and Raki's firmware dump — for `src/mame/taito/kikikai.cpp` and the
  device emulations that are this core's specification.
- **Guy Hutchison** (TV80) and **Daniel Wallner** (original T80) for the vendored Z80 core.
- **Jose Tejada (jotego)** for the vendored `jt03` YM2203 core.
- The **`Arcade-KickAndRun_MiSTer`** project, whose repository is the source this project
  vendored `tv80`, `jt03`, and the M6801 CPU core from.
- **Claude** (Anthropic), used as a development assistant throughout this project.
- **ppriest**'s [MiSTer-CoreSkill](https://github.com/ppriest/MiSTer-CoreSkill), the skill this
  core was built with.

## License

GPL-3.0-or-later (see `LICENSE`). Imported components keep their own licenses; `THIRD-PARTY.md`
has the detail and every modified vendored file states the change in its header.

Game ROMs contain copyrighted material and are not included. Obtaining them is your
responsibility.
