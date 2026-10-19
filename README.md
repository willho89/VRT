# VRT

A single, faithfully emulated CRT television in VR and AR, for Meta Quest 3 (primary) and Quest 2.
Games and video come from [libretro](https://www.libretro.com/) cores. The CRT is VRT's own:
signal, raster, phosphor and glass emulation designed for a headset, where you can put your face
against the glass and see the phosphors.

Inspired by EmuVR, without the physical consoles and media: one TV, in an empty virtual room or
placed in your real room with passthrough (Quest 3), and it lights up its surroundings.

> **Status: early development.** Milestones M0 (toolchain + XR/libretro spikes) and M1 (libretro
> host, library, input, menu) are done; M2 (the CRT pipeline) is in progress.

## Features so far
- Quest 3 at 120 Hz, VR room or passthrough AR. The screen's light falls on the virtual room and,
  through Meta's room setup data, on your real walls and furniture.
- Place the TV on the floor or on a real table.
- Content library for NES, SNES, Sega 8/16-bit (Genesis Plus GX), PC Engine and DVD-Video (via
  [DeeVee](https://github.com/willho89/DeeVee)). Zipped ROMs work. Point at the screen to click
  DVD menus.
- Save/load states, Bluetooth gamepads and Touch controllers.
- Flat desktop mode (Linux) for development, with an orbit camera.

## Content on the headset
- `/sdcard/VRT/roms/<System>/...`, e.g. `roms/Genesis/`, `roms/NES/`, `roms/SNES/`, `roms/Master System/`
- `/sdcard/VRT/video/` for DVD images (`.iso`, `.chd`)

VRT asks for "All files access" on first start so it can read `/sdcard/VRT`.

## Building
Developed on a Steam Deck (Linux). You need Godot 4.7.2 with the Android export templates, JDK 17,
and the Android SDK/NDK (see `docs/m0-results.md` for the exact versions). C++ is built with SCons.

```sh
git clone --recursive https://github.com/willho89/VRT.git
cd VRT
tools/fetch_deps.sh        # Meta OpenXR vendors plugin
tools/fetch_cores.sh       # libretro cores (DeeVee from a local checkout)
tools/build_extension.sh   # libretro host GDExtension, Linux + Android
tools/deploy.sh            # export the APK, install on the headset, launch, log
```

## Layout
- `godot/`: the Godot project (scripts, shaders, scenes)
- `extension/libretro-godot/`: libretro host GDExtension, a fork of
  [RetroXR/libretro-godot](https://github.com/RetroXR/libretro-godot) (MIT)
- `include/vrt_libretro_ext.h`: VRT's libretro extensions (field-accurate interlace), CC0 for cores
- `tools/`: build and deploy scripts
- `docs/`: milestone notes

## License
GPLv3; see [LICENSE](LICENSE). Bundled and fetched components keep their own licenses.
