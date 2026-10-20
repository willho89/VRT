# TV types

A TV type is one JSON file describing a set: its name, cabinet, tube, mask, phosphors, beam and glass. VRT
shows one TV at a time, and you choose which in the TV's own menu (**TV TYPE**). The choice is saved.

## Where they live
| Folder | Notes |
|---|---|
| `res://tvs/` (`godot/tvs/` in the repo) | Bundled with VRT. |
| `/sdcard/VRT/tvs/` | Quest. Add your own without rebuilding. |
| `/sdcard/Android/data/io.github.willho89.vrt/files/tvs/` | Quest, needs no storage permission. |
| `user://tvs/` | Desktop (`~/.local/share/godot/app_userdata/VRT/tvs/` on Linux). |

A model file (`.glb` / `.gltf`) sits next to its JSON. A user file with the same `id` as a bundled one
replaces it. Types are listed by `order`, then file order.

## Format
Every section is optional. Anything left out keeps the generic consumer-set default (`scripts/crt/crt_profile.gd`),
so a file only needs to state what differs. Lengths are millimetres unless the key says `_m`.

```jsonc
{
  "id": "my_tv",                       // required, unique
  "name": "20-inch bedroom TV",
  "short_name": "BEDROOM 20",          // shown in the TV menu, max 12 characters
  "order": 50,
  "description": "free text",

  "cabinet": { ... },                  // see Cabinets below

  "tube": {
    "visible_mm": [400, 300],          // picture area on the glass (not the nominal diagonal)
    "curvature": "spherical",          // spherical | cylindrical (aperture grille sets) | flat
    "radius_mm": 1600,                 // faceplate radius; larger is flatter
    "corner_radius_mm": 18,
    "glass_thickness_mm": 12           // parallax between the glass and the phosphors
  },
  "mask": {
    "type": "slot",                    // slot (most TVs) | dot (delta) | aperture (grille stripes)
    "pitch_mm": 1.0,                   // same-colour phosphor spacing; real sets 0.25-0.8, more reads better in VR
    "vpitch_mm": 1.0,                  // slot/dot row period (slot and dot)
    "phosphor_duty": 0.70,             // lit fraction of each stripe
    "slot_duty": 0.78                  // open fraction of each slot row
  },
  "phosphors": {
    "red_xy": [0.625, 0.340], "green_xy": [0.280, 0.595], "blue_xy": [0.155, 0.070],
    "white_xy": [0.2831, 0.2971],      // 9300 K here; D65 is [0.3127, 0.3290]
    "persistence": [0.02, 0.06, 0.01], // light left one frame later, per channel
    "peak_nits": 180
  },
  "gun": {
    "gamma": 2.4,
    "beam_sigma": [0.13, 0.25],        // vertical spot, scanline heights, dark..bright (smaller = stronger scanlines)
    "beam_sigma_h": [0.25, 0.40],      // horizontal spot, 1/320ths of picture width
    "convergence_r_mm": [0.35, -0.2],  // red/blue misconvergence at the corners
    "convergence_b_mm": [-0.3, 0.25]
  },
  "geometry": { "overscan": [0.06, 0.05], "pincushion": 0.004 },   // overscan is overridden by the OVERSCAN setting
  "glass": { "tint": "#6b706e", "roughness": 0.06, "halation": 0.14, "corner_falloff": 0.78 },
  "default_input": "composite"         // rgb | svideo | composite | rf (until the user picks one)
}
```

## Cabinets
Every cabinet uses the same convention: metres, origin at the **bottom centre of the front face**, front facing
**+Z**. The TV is placed, grabbed and stood on things by that origin.

**Built-in:** `{ "builtin": "vcr_combo" }`, the procedural 25" TV/VCR combo.

**Procedural box:** sized around the tube automatically. Good for monitors and placeholders.
```jsonc
{ "builtin": "box",
  "bezel_mm": [45, 45, 70],            // side, top, bottom
  "depth_mm": 450,
  "color": "#1c1c1e", "front_color": "#9a9a9e",
  "speakers": "below" }                // below | sides | none
```

**Your own model:** glTF 2.0, loaded at runtime.
```jsonc
{ "model": "my_tv.glb",
  "scale": 1.0,                        // model units to metres
  "offset": [0, 0, 0],                 // move the model onto the origin convention
  "rotation_deg": [0, 0, 0],
  "screen_center": [0, 0.30, -0.01],   // where the glass centre goes, metres, after offset/scale
  "speakers": [[-0.2, 0.05, 0], [0.2, 0.05, 0]],
  "power_led": [0.18, 0.04, 0.005], "led_color": "#20ff40",
  "bounds": { "center": [0, 0.25, -0.2], "size": [0.6, 0.5, 0.45] } }   // optional; else measured from the meshes
```
The model provides the cabinet and VRT provides the tube, so leave the screen area **open** (no glass mesh) and
size `tube.visible_mm` to the opening. VRT's tube extends 6% past the picture under the bezel. If the model fails
to load, VRT falls back to a box cabinet.

Licensing: models you add stay on your device. Only bundle models whose licence allows redistribution under
VRT's GPLv3, and never ones tagged NoAI.

## Bundled examples
| id | Shows |
|---|---|
| `vcr_combo_25` | The reference: slot mask, spherical tube, composite |
| `aperture_27` | Aperture grille on a cylindrical tube, silver front |
| `monitor_14` | Broadcast-monitor style: grille, small spot (strong scanlines), SMPTE-C at D65, RGB |
| `portable_13` | Delta (dot) mask, bulgy tube, soft beam, RF |
