# Testing VRT on a Quest 2 / Quest 3

You need a headset in developer mode and SideQuest (or `adb`).

1. **Install** the APK: drag `VRT-<version>.apk` onto SideQuest, or run `adb install -r VRT-<version>.apk`.
2. **Add content** with SideQuest's file manager (or `adb push`):
   - ROMs go in `/sdcard/VRT/roms/<System>/`. The folder names are `NES`, `SNES`, `Genesis`,
     `Master System`, `Game Gear` or `PC Engine`. Zips are fine.
   - DVD images (`.iso`) go in `/sdcard/VRT/video/`.
3. **Launch** VRT from Library → Unknown Sources. On first start, allow **All files access**, then return to VRT.

## Controls
- The menu panel appears in front of you. Aim the right-controller laser and pull the trigger to pick things;
  either thumbstick scrolls the lists.
- **Left Menu button** opens and closes the menu during play. On a Bluetooth pad, hold Select+Start.
- In-game, the left stick is the d-pad. A/B/X/Y are game buttons, the triggers are L/R, the grips are L2/R2,
  a left-stick click is Select and a right-stick click is Start.
- With the menu open, pull the trigger on the floor to move the TV. **VR / AR** switches to passthrough on Quest 3.

## What to report
- The readout at the top right of the menu: **fps / Hz** and whether it says "Quest 2 profile". Note it in the menu
  and during play (open the menu briefly to see it).
- Stutter, audio crackle, overheating warnings, crashes.
- How the TV looks from 1–2 m and up close: shimmer or moiré, sharpness.
