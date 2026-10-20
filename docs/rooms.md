# Rooms

A room is the virtual space around the TV in VR mode (AR uses your real room). VRT ships an empty room;
you can add your own as a **glTF model plus a small JSON file**. Choose one in the TV menu (**ROOM**). The
choice is saved, and each room remembers where you put the TV in it.

## Quick start
1. Build or download a room in Blender (or any 3D tool), in **metres** with the **floor at Y = 0**.
2. Export **glTF 2.0 binary (.glb)**. Embed textures in it.
3. Write a JSON file next to it (example below).
4. Copy both to the headset:
   - Quest: `/sdcard/VRT/rooms/` (or `/sdcard/Android/data/io.github.willho89.vrt/files/rooms/`)
   - Desktop: `user://rooms/` (`~/.local/share/godot/app_userdata/VRT/rooms/` on Linux)
5. Restart VRT, then open the TV menu and change **ROOM**.

A complete example is in [`examples/rooms/den/`](../examples/rooms/den): `den.glb`, a small den made of boxes, plus
`den.json`. Copy both to `/sdcard/VRT/rooms/` to try it, or open the .glb in Blender as a template.

## Format
```jsonc
{
  "id": "my_den",                 // required, unique
  "name": "My den",
  "short_name": "MY DEN",         // shown in the TV menu, max 12 characters
  "order": 50,                    // list position (built-in empty room is 0)

  "model": "my_den.glb",          // next to this JSON
  "scale": 1.0,                   // model units to metres
  "offset": [0, 0, 0],            // move the model (metres)
  "rotation_deg": [0, 0, 0],

  "tv": {                         // where the TV starts (until you move it)
    "position": [0, 0.62, -2.3],  // centre of the TV's footprint, on the surface it stands on
    "yaw_deg": 0                  // 0 = screen faces +Z
  },
  "spawn": { "position": [0, 0.6] },  // optional [x, z] where Recenter puts you; default 1.5 m in front of the TV

  "lighting": {
    "ambient_color": "#8c8c99",   // dim fill so dark corners don't go fully black
    "ambient_energy": 0.2,
    "fill_energy": 0.35,          // soft directional fill on the TV cabinet and controllers
    "fill_color": "#fff2e0",
    "surface_ambient": 0.07       // how bright room surfaces are without the CRT
  },
  "screen_light": true,           // re-light the model's surfaces with the CRT's glow (recommended)
  "collision": true               // let the pointer place the TV on your tables and shelves
}
```
Only `id` and `model` are needed; everything else has defaults. Without a `model`, you get the built-in empty room.

## How rooms are lit
VRT is about the TV, so a room is lit mainly **by the CRT itself**: its picture spills coloured light onto the
walls, floor and furniture as the image changes. With `"screen_light": true`, VRT replaces each material in your
model with one that keeps its **base colour, base colour texture, alpha cut-out and emission**, and adds the CRT's
light plus a dim ambient fill. The model's own lights, normal maps, roughness and baked lighting are ignored. An
emissive lamp shade still glows, but it doesn't light the room. Set `"screen_light": false` to use the model's
materials unchanged (the CRT won't light it then).

## Tips
- **Performance:** keep rooms modest, roughly under 100k triangles and a few 1–2K textures. Quest 2 has much less
  headroom than Quest 3.
- **Collision** is generated from every mesh. With very dense models, set `"collision": false` and include a
  simple floor mesh instead (the floor plane at Y = 0 always exists).
- **TV spot:** `tv.position` is the centre of the TV's footprint, so put it on your table top. Every TV type
  stands correctly there whatever its size.
- **Licensing:** rooms you add stay on your headset. Only share or contribute models whose licence allows it,
  and never ones tagged NoAI.
