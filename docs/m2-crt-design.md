# M2: CRT pipeline design

## Reused open-source work
| Source | License | What we take |
|---|---|---|
| [TSUISHI/CRTshader](https://github.com/TSUISHI/CRTshader) (Godot 4) | MIT | Stage 1 composite/RF signal model, ported nearly verbatim as VRT's signal stage (M3). Stage 2 ideas: brightness-dependent beam width, per-channel convergence, halation. |
| [crt-guest-advanced](https://github.com/libretro/slang-shaders/tree/master/crt/shaders/guest/advanced) (guest.r) | GPL-2.0-or-later | Reference for the beam profile and scanline shape and their parameter ranges. |
| [crt-royale](https://github.com/libretro/slang-shaders/tree/master/crt/shaders/crt-royale) (TroggleMonkey) | GPL-2.0-or-later | Reference for physical phosphor masks and mask resampling (the same band-limiting problem we solve analytically), and for interlace "bob fields". |
| [CRT-Lottes](https://github.com/libretro/slang-shaders/blob/master/crt/shaders/crt-lottes-fast.slang) | Public domain | Mask and warp helpers. |
| [Blur Busters CRT beam simulator](https://github.com/blurbusters/crt-beam-simulator) | MIT | Rolling-scan / phosphor-decay simulation at 120 Hz (later, stretch goal). |
| [LMP88959/NTSC-CRT](https://github.com/LMP88959/NTSC-CRT) | Permissive ("use in any way") | Accurate NTSC encode/decode reference, including NES-specific signal generation (M3+). |
| [ntsc-rs](https://github.com/valadaptive/ntsc-rs) | MIT / ISC | VHS model reference (post-MVP). |

All of these are compatible with VRT's GPLv3. Ported files keep their original notices.

## Why the flat-screen shaders can't be used as-is
Desktop CRT shaders size the mask in *output pixels* (integer-scale or "pitch in px"). In VR the
pixel density on the tube changes continuously with distance and angle:

- 27" consumer TV, 508 mm visible width, 0.82 mm slot pitch: about 620 triads across.
- At 1.5 m on Quest 3 (about 25 px/°), the face spans about 19° ≈ 480 px. That's fewer pixels than
  triads, so an unfiltered mask turns into moiré.
- At 5 cm, one triad covers dozens of pixels and must look like real phosphors.

VRT evaluates everything in **physical tube coordinates (mm)** and **box-filters analytically over each
pixel's footprint** using screen-space derivatives:
- Mask: the integral of the periodic phosphor pulse train over the footprint (exact box filter). It's
  sharp up close and fades to the correct average color far away, with no texture and no mip levels.
- Scanlines: Gaussian beam profiles, widened by the footprint (σ² + w²), which is exact for Gaussians.

## Pipeline
```
libretro frame ─▶ [signal]   (M3; bypass in M2)                       source res
              ─▶ [raster]    gamma → linear, field placement,          frame-line res, RGBA16F,
                             per-channel phosphor persistence          ping-pong pair of SubViewports
              ─▶ [tube surface shader] on a curved mesh:               per headset pixel
                   geometry (overscan, pincushion), parallax through the glass,
                   per-channel convergence, beam reconstruction (Gaussian, width grows with
                   brightness), band-limited phosphor mask, P22 → Rec.709, halation, glass
                   (specular, tint, dark-tube look)
```

- **Raster** runs once per new core frame, not per display frame. For a field (VRT field extension),
  only that field's lines are refreshed and the other lines decay, the way a real tube behaves.
- **Profile** (`CrtProfile`): size, curvature, mask type/pitch/duty, phosphor primaries and decay,
  gamma, beam parameters, convergence, overscan, glass. M2 ships `generic_shadowmask_27`: a 27"
  consumer set with an in-line slot mask and spherical tube.

## Mask types
- `SLOT`: in-line R/G/B vertical slots in staggered rows (most consumer TVs, the M2 default)
- `DOT`: delta triads (monitors, older TVs)
- `APERTURE`: continuous vertical stripes (Trinitron), plus damper wires
