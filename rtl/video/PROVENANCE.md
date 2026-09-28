# screen_rotate_two provenance

Vendored from `MiSTer-devel/Arcade-Psikyo_MiSTer` (`rtl/video/screen_rotate_two.sv`),
commit `4ca386b4eeea95c649c485801452385419d3b5e6`. Unmodified.

Original author per file header: Sorgelig, 2020, first shipped in
`Arcade-SKNS_MiSTer`. License: GPL-2.0-or-later (file header: "either
version 2 of the License, or (at your option) any later version").

Taps `VGA_R/G/B/HS/VS/DE` after the video pipeline and writes a rotated
(optionally 180-flipped) copy into DDR3 for the HDMI framebuffer; the
analog/CRT output keeps the native raster untouched. Owns `DDRAM_*` and
`FB_*` — no other DDR3 client exists in this core, so no arbitration is
needed.
