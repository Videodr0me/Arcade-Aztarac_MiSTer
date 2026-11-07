# Aztarac Video Profiles

[Back to the README](../README.md#video-profiles--effects)

Five fixed presets offer different balances of sharp vectors, glow and phosphor
persistence. Their settings adapt to the output resolution. **80s Cruise
Control** is the default; **Custom 1** and **Custom 2** are independently editable.

## Choosing and Saving a Profile

The menu and keyboard shortcuts follow this cycle:

**80s Cruise Control -> 80s Overdrive -> Plasmarac -> Negative Shield ->
Custom 1 -> Custom 2 -> A Touch of CRT -> 80s Cruise Control.**

With the OSD closed, **US -** selects the previous profile and **US =/+** the
next. **F6** copies the current profile to Custom 1; **F7** copies it to Custom 2.
An on-screen message confirms the action, and copying leaves the source profile
selected. Ctrl+Shift+1/2 are alternative copy shortcuts.

Empty custom slots start from **Cruise Control** and **Overdrive**, respectively,
at the resolution active during initialization. Existing saved settings are
preserved. Custom settings do not automatically change when you switch
resolution; copy a fixed preset again if you want its tuning for the new mode.
Custom controls stay greyed out until their settings are ready. Copy a fixed
preset after video startup has completed; an early key press is ignored.
Use MiSTer's **Save Settings** to retain your choices.

## What the Controls Do

| Control | Purpose |
|---|---|
| **Dot Scale** | Sets the footprint of point primitives: 1x, 2x, 2.5x or 3x. |
| **Tone Mapping** | Sets vector brightness at readout. Off uses 1x gain, Standard 1.125x, Bright about 1.21x and Boost about 1.52x. |
| **Bloom Width** | Sets the close glow around bright vectors: Off, Thin, Tight, Soft, Normal, Broad, Wide- or Wide. |
| **Bloom Curve** | Adjusts how strongly bright pixels feed bloom, from Minimal through Strong. |
| **Halo** | Sets the broad glow strength: Off, 0.25x, 0.33x, 0.5x, 0.75x, 1.0x, 1.25x or 1.5x. |
| **Halo Curve** | Adjusts how strongly bright pixels feed the halo, from Minimal through Strong. |
| **Halo Spread** | Selects Original, Wide 1, Wide 2 or Focus for the halo's spatial distribution. |
| **Halo Grid** | Chooses 16x16 or the finer 8x8 sampling grid used to build the halo. |
| **Halo Compression** | Controls compression of strong halo values: Off, 2, 4, 6, 8, 16, 24 or 32. |
| **Inter-Frame Decay** | Keeps phosphor trails between frames: Off, Short, Medium or Long. |
| **Intra-Frame Decay** | Selects Off or LUT A/B/C for fading within the vector drawing sequence. |
| **Color Space** | Native keeps the original channel balance. G08 to Rec.709 applies a Sega-inspired blue lift, adding a small share of blue to red and green for paler blue highlights. |
| **Color Effect** | Keeps Original colors, swaps RGB channels, or selects B/W or Negative. |
| **Slot Mask** | Adds a CRT-style mask to the final image. |

**Negative Shield** uses Negative at every resolution.
Halo Grid follows each preset's table below. Grid and color-space
choices are independently editable in each custom slot.

The curve choices, in menu order, are **Minimal, Min+, Mild, Mild+, Moderate,
Mod+, Strong-, Strong**. The tables use these same menu labels.

### Global Halo Interpolation

**Diagnostics / Halo Interpolation** applies to every profile. It defaults to
**B=2.00** and offers these cubic reconstruction shapes:

| Menu Choice | B | C |
|---|---:|---:|
| **B=2.00 (default)** | 2.00 | -0.50 |
| **Normal** | 1.00 | 0.00 |
| **B=1.50** | 1.50 | -0.25 |
| **B=1.75** | 1.75 | -0.375 |

This controls how the coarse halo samples blend into the final pixels.
It is separate from Halo Spread and Halo Curve. Normal is the standard
cubic B-spline; the other choices alter its shape.

Switching Halo Grid at 1080p can briefly resynchronize the display. This is
a known switching limitation; it does not change the selected video timing.

## Preset Values

Each row below lists the current fixed preset. 480i uses the 480p settings.
Artwork brightness, overlay mode, orientation and global halo interpolation
are separate settings and are not copied into custom profiles.

## 240p

| Profile | Dot | Tone Mapping | Bloom Width / Curve | Halo Strength / Curve / Spread / Compression | Halo Grid | Inter- / Intra-Frame Decay | Color Space | Color Effect | Slot Mask |
|---|---|---|---|---|---|---|---|---|---|
| **80s Cruise Control** | 2x | Standard | Thin / Mild | 0.25x / Mild / Focus / 32 | 8x8 | Off / Off | Native | Original | Off |
| **80s Overdrive** | 2x | Standard | Thin / Moderate | 0.33x / Mild / Focus / 32 | 8x8 | Short / Off | Native | Original | Off |
| **Plasmarac** | 3x | Standard | Tight / Moderate | 0.33x / Moderate / Focus / 8 | 16x16 | Medium / LUT A | Native | Original | Off |
| **Negative Shield** | 2.5x | Bright | Thin / Moderate | 0.33x / Mild / Focus / 8 | 16x16 | Medium / LUT C | Native | Negative | Off |
| **A Touch of CRT** | 2x | Off | Thin / Mild | 0.25x / Mild / Focus / 8 | 8x8 | Off / Off | Native | Original | Off |

## 480p / 480i

| Profile | Dot | Tone Mapping | Bloom Width / Curve | Halo Strength / Curve / Spread / Compression | Halo Grid | Inter- / Intra-Frame Decay | Color Space | Color Effect | Slot Mask |
|---|---|---|---|---|---|---|---|---|---|
| **80s Cruise Control** | 2x | Standard | Thin / Mild | 0.5x / Minimal / Focus / 24 | 8x8 | Off / Off | Native | Original | Off |
| **80s Overdrive** | 2.5x | Standard | Tight / Mild | 0.5x / Min+ / Original / 32 | 8x8 | Short / Off | Native | Original | Off |
| **Plasmarac** | 3x | Standard | Tight / Moderate | 0.5x / Mild+ / Wide 1 / 24 | 16x16 | Medium / LUT A | Native | Original | Off |
| **Negative Shield** | 2.5x | Bright | Tight / Mild+ | 0.5x / Mild+ / Original / 24 | 16x16 | Medium / LUT C | Native | Negative | Off |
| **A Touch of CRT** | 2x | Off | Thin / Mild | 0.25x / Mild / Focus / 32 | 8x8 | Off / Off | Native | Original | Off |

## 720p

| Profile | Dot | Tone Mapping | Bloom Width / Curve | Halo Strength / Curve / Spread / Compression | Halo Grid | Inter- / Intra-Frame Decay | Color Space | Color Effect | Slot Mask |
|---|---|---|---|---|---|---|---|---|---|
| **80s Cruise Control** | 3x | Standard | Tight / Mild+ | 0.5x / Min+ / Focus / 4 | 16x16 | Short / Off | G08 to Rec.709 | Original | On |
| **80s Overdrive** | 3x | Standard | Tight / Mod+ | 0.5x / Min+ / Original / 24 | 16x16 | Medium / Off | G08 to Rec.709 | Original | On |
| **Plasmarac** | 3x | Standard | Soft / Mild+ | 0.75x / Mod+ / Wide 2 / 16 | 16x16 | Medium / LUT A | Native | Original | Off |
| **Negative Shield** | 3x | Off | Soft / Mild+ | 0.5x / Mild+ / Original / 16 | 16x16 | Long / LUT C | Native | Negative | Off |
| **A Touch of CRT** | 2.5x | Off | Thin / Moderate | 0.25x / Mod+ / Wide 1 / 2 | 8x8 | Short / Off | Native | Original | Off |

## 1080p

| Profile | Dot | Tone Mapping | Bloom Width / Curve | Halo Strength / Curve / Spread / Compression | Halo Grid | Inter- / Intra-Frame Decay | Color Space | Color Effect | Slot Mask |
|---|---|---|---|---|---|---|---|---|---|
| **80s Cruise Control** | 3x | Standard | Soft / Mild | 0.5x / Mild / Wide 2 / 16 | 16x16 | Short / Off | G08 to Rec.709 | Original | On |
| **80s Overdrive** | 3x | Standard | Normal / Mild | 0.5x / Mild+ / Wide 2 / 16 | 16x16 | Medium / Off | G08 to Rec.709 | Original | On |
| **Plasmarac** | 3x | Standard | Soft / Mild+ | 1.5x / Mild / Wide 2 / 8 | 16x16 | Medium / LUT A | Native | Original | Off |
| **Negative Shield** | 3x | Off | Soft / Mod+ | 1.0x / Mild+ / Wide 2 / 24 | 16x16 | Long / LUT C | Native | Negative | Off |
| **A Touch of CRT** | 3x | Off | Tight / Moderate | 1.0x / Minimal / Focus / 8 | 16x16 | Short / Off | Native | Original | Off |

The source of these values is
[`vfb_control_pkg.sv`](../rtl/videodr0me_fb/vfb_control_pkg.sv).
