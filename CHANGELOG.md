# Changelog

## Initial Release - 2026-11-06

- **Aztarac (Centuri, 1983)** on MiSTer FPGA, with a **Motorola 68000 at
  8 MHz**, a **Z80 sound CPU at 2 MHz**, and **four AY-3-8910 sound chips
  at 2 MHz** each. The custom vector display-list system supplies two bits
  per RGB channel and eight-bit intensity, preserved through the core's
  vector rendering pipeline.

- **Authentic game timing at 45 fps:** to our knowledge, the first Aztarac
  emulation to reproduce the game's intended speed. The 45 Hz update rate
  is supported by the original ROM's internal timing logic and the durations
  displayed in the operator setup menu, and falls within the range indicated
  by timed footage of original cabinets.

- **HD vector rendering** at 1080p and 720p, with optional 120 Hz output at
  720p. CRT and Direct Video support 480p, 480i and 240p, with horizontal
  and vertical offsets to center the whole picture, including the artwork.

- **Adjustable CRT effects:** dwell size, bloom, halo, phosphor
  persistence, tone mapping, color controls and slot mask. Halo options
  include 8x8 and 16x16 grids and four interpolation shapes.

- **Five video presets and two custom profiles**, with resolution-specific
  settings, keyboard profile cycling, copy shortcuts and saved preferences.

- **Videodr0me's new plexidome artwork**, with a reflective finish inspired
  by the original cabinet. Artwork loads automatically from
  the supplied MRA, with full artwork, labels-only and off modes, and
  adjustable brightness.

- **Normal, clockwise and counterclockwise views**, with matching artwork
  for every supported resolution and physically rotated monitors.

- **Flexible controls:** analog joystick, D-pad, spinner, mouse and gamepad,
  with Directional Aim dual-stick controls by default and adjustable turret
  controls. Supports one player or two alternating players.

- **Original operator features:** cabinet service switch, setup menus and
  Slam/Tilt. The game saves operator settings and the three All Time
  Champions. Pause options include automatic screen dimming.

- **Selectable cabinet audio low-pass:** Off, 4 kHz, 6 kHz (default) or
  8 kHz, applied to the full mix with the original channel balance.

Requires a DE10-Nano MiSTer with a 32 MB or larger SDRAM module.
