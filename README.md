# VRT

A single, faithfully emulated CRT television in VR and AR, for Meta Quest 3 (primary) and Quest 2.
Games and video come from [libretro](https://www.libretro.com/) cores. The CRT is VRT's own:
signal, raster, phosphor and glass emulation designed for a headset, where you can put your face
against the glass and see the phosphors.

Inspired by EmuVR, without the physical consoles and media: one TV, in an empty virtual room or
placed in your real room with passthrough (Quest 3), and it lights up its surroundings.

> **Status: alpha.** The CRT, signal stage, on-TV guide and menu, TV placement, VR room and Quest 3
> AR are in. Expect rough edges; settings and save formats may still change.

## Features
- A CRT built for a headset: band-limited phosphor masks (slot, dot, aperture grille) you can put
  your face against, beam and scanlines, real field-by-field interlace for DVDs, halation, glass.
- Accurate NTSC signal stage (composite, S-Video, RF) with each console's own subcarrier timing,
  plus TV picture controls.
- TV types defined in JSON, with your own 3D models; four built in.
- On-screen TV menu and a 90s-style programme guide, drawn by the TV itself.
- VR room or passthrough AR on Quest 3: the TV is pinned to your real room with a spatial anchor,
  real objects occlude it, and its light spills onto your walls.
- The sound comes from the TV's speakers in 3D. Save states, recents and favourites.

## Install (Quest 2 or Quest 3)
1. Download the APK from [Releases](https://github.com/willho89/VRT/releases). One APK works on both
   headsets; VRT detects a Quest 2 and picks lighter defaults.
2. Your headset needs developer mode. Sideload with [SideQuest](https://sidequestvr.com/) (drag the
   APK onto it) or `adb install VRT-*.apk`.
3. Open VRT from *Unknown sources* in your app library. Allow "All files access" when asked, then
   return to VRT.
4. The headset needs internet the first time each system is used. VRT downloads emulator cores from
   the official [libretro buildbot](https://buildbot.libretro.com/), just as RetroArch does (see
   *Cores* below).

## Content on the headset
VRT ships with no games or videos. Use your own:
- `/sdcard/VRT/roms/<System>/...`, e.g. `roms/NES/`, `roms/SNES/`, `roms/Genesis/`, `roms/Master System/`,
  `roms/PC Engine/`, `roms/PlayStation/` (zipped ROMs work; PS1 discs as .chd/.cue/.pbp)
- `/sdcard/VRT/vhs/` for ordinary video files (mp4, mkv, avi…), played on the **VHS** channel
- **Live TV** needs nothing: the **TV** channel's LIVE TV finds an HDHomeRun tuner on your network, else
  plays [iptv-org](https://github.com/iptv-org/iptv)'s free channels. Your own channel lists (`.m3u`) or single
  stream URLs (`.strm` files) go in `/sdcard/VRT/tv/`
- `/sdcard/VRT/video/` for DVD images (`.iso`, `.chd`) or `VIDEO_TS` folders
- `/sdcard/VRT/system/<core>/` for files a core asks for (BIOS images). Optional: DeeVee plays
  CSS-encrypted DVD images only if you put `libdvdcss.so.2` in `/sdcard/VRT/system/deevee/`.
  Decrypted rips (e.g. MakeMKV) need nothing.
- `/sdcard/VRT/tvs/` for extra TV types (see [docs/tv-types.md](docs/tv-types.md))
- `/sdcard/VRT/rooms/` for your own VR rooms, as a glTF model plus JSON (see [docs/rooms.md](docs/rooms.md); try
  [examples/rooms/den](examples/rooms/den))

## Using it
- **Menu button** (left controller), **Select+Start** on a gamepad, or **Esc** opens the **TV guide**
  on the screen: channels for each system, recent and favourites. Up/down picks, left/right
  changes channel, L/R jumps by letter, X stars, A plays. You can also point at the TV and pull the
  trigger.
- The guide's **VRT** channel has Resume, the **TV menu** (volume, picture, TV type, input, signal,
  overscan, detail, resolution, refresh rate…), Move TV, save/load state, VR/AR and Recenter.
- **Move the TV:** point at it and hold the **right grip**. Use the sticks to push/pull, turn and tilt,
  and add the left grip to scale. Fine steps are under TV menu → PLACE TV.
- **Walk** (VR room): hold the **left grip** and use the sticks. This works mid-game too.
- Bluetooth gamepads and the Touch controllers both play.

## Cores
VRT bundles only its own cores: [X-Streemly](https://github.com/willho89/X-Streemly) (live TV, GPL-2.0+)
and [DeeVee](https://github.com/willho89/DeeVee) (DVD-Video, GPL-2.0+, built without
CSS decryption). FCEUmm (NES), Snes9x (SNES), Genesis Plus GX (Sega 8/16-bit), Mednafen PCE Fast
(PC Engine), PCSX ReARMed (PlayStation) and FFmpeg (video files) are downloaded on first use from the
libretro buildbot. Each keeps its own license, and
some (Snes9x, Genesis Plus GX) are non-commercial.

## Building
Developed on a Steam Deck (Linux). You need Godot 4.7.2 with the Android export templates, JDK 17,
and the Android SDK/NDK (see `docs/m0-results.md` for the exact versions). C++ is built with SCons.

```sh
git clone --recursive https://github.com/willho89/VRT.git
cd VRT
tools/fetch_deps.sh        # Meta OpenXR vendors plugin
tools/fetch_cores.sh       # libretro cores (DeeVee, X-Streemly from local checkouts)
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
