# M0 results (2026-10-19)

All checks ran on a Quest 3 (Horizon OS, OpenXR runtime Oculus 207.218.0), the primary target.
Quest 2 hasn't been tested yet; builds will go to a tester periodically.

## Toolchain
- Godot 4.7.2-stable (Mobile renderer, Vulkan), godot_openxr_vendors 5.1.0-stable
- JDK 17 (Temurin 17.0.20.1), Android SDK: build-tools 36.1.0, platform 36, NDK 29.0.14206865
- Everything lives in `~/Applications/vrt-tools/`. C++ builds run in the `vrtbuild` distrobox (Ubuntu 24.04, g++ 13, SCons 4.5)
- `tools/deploy.sh`: export, install and launch. Note: Godot's export restarts the adb server, so don't run
  `adb push` while an export is running.

## XR shell spike (`godot/scenes/hello_xr.tscn`)
| Check | Result |
|---|---|
| OpenXR session, Vulkan, Mobile renderer | OK |
| Refresh rates | 72 / 80 / 90 / 120 available; runs 120/120 fps, 0 stale frames |
| Passthrough (alpha blend) | OK; toggles at runtime |
| Meta scene (room setup) anchors + global mesh | OK; walls, floor, ceiling, tables, etc. load |
| Screen light on the virtual room | OK |
| Screen light on real surfaces in AR | OK: premultiplied main layer (`composition_layer_settings` ONE / ONE_MINUS_SRC_ALPHA) and an `ALPHA = 0` additive material |
| TV placement on a real table via scene collision | OK |

## libretro host spike (`~/.claude/projects/VRT-spikes/libretro-spike`)
RetroXR/libretro-godot @ `ffb6533` (MIT), built for linux.x86_64 and android.arm64 (NDK r29).

| Core | Desktop (Deck) | Quest 3 |
|---|---|---|
| Genesis Plus GX (Sonic 2) | 60 fps, audio OK | 60 fps emu at 120 Hz display, worst `retro_run` ≈ 1.5 ms; user: no A/V issues, controls responsive |
| FCEUmm (SMB3) | — | OK per user |
| DeeVee 0.6.1 (Chrimbus Special ISO) | 720×480 @ 59.94, 48 kHz | Menus, playback and subtitles all correct; user: "audio & video are perfect" |

Notes:
- Cores load from app-private storage (`user://retro/cores`). libretro-godot copies each core to a temp
  file before `dlopen`. `/sdcard` is noexec, so cores can't live there; large content (DVD ISOs) can.
- Content in `/sdcard/Android/data/<pkg>/files/` is readable with no storage permission.
- About 20 frames are dropped in the first second after a core starts (startup transient). Look at this in M1.
- Not implemented by the host (logged): `SET_CORE_OPTIONS_DISPLAY`, `SET_CONTENT_INFO_OVERRIDE`,
  `GET_GAME_INFO_EXT`, `SET_SERIALIZATION_QUIRKS`. None blocks the cores tested.
- DeeVee on Android: first ever device run; the CSS-static build was used. Loading libdvdcss from the
  system folder on Android is still untested.

## Decision: fork libretro-godot
It meets every M1 host requirement or nearly does: an emulation thread, audio-paced timing with a sinc
resampler, NEON tuned on Quest 3, pointer and joypad APIs, SRAM and save states, and HW-render paths
(GLES/Vulkan) for the Quest 3 next-gen cores later. It's actively maintained and MIT licensed.
VRT will carry it as a submodule fork and add:
- the field-info environment extension (`include/vrt_libretro_ext.h`), with the field parity on each frame
- direct access to the frame texture through RenderingDevice for the CRT pipeline (it currently exposes an
  `ImageTexture` that gets recreated on resolution change)
