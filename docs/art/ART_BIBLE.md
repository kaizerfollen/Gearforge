# Gearforge Art Bible

All art is original and procedurally generated (Python + Pillow + numpy + pycairo). Never imitate another game's
look, icons, logos or UI.

## Regenerate

```sh
pip install --break-system-packages pillow numpy pycairo
python3 tools/art/generate.py              # cleans App/Resources/Sprites.atlas, writes all PNGs (~20 s),
                                           # App/Resources/sprite_manifest.json and the app icon / asset catalog
python3 tools/art/generate.py --only items,ui   # partial (manifest not rewritten)
python3 tools/art/check_contract.py        # verifies every contract name + pixel size exists
python3 tools/art/contact_sheet.py --all   # review sheets -> docs/art/contact_*.png
```

Output is deterministic: noise is seeded from sprite names (CRC32), so a re-run is byte-identical.
Generators live in `tools/art/gfart/` (one module per category; `common.py` + `base.py` are shared helpers).

## Style

- **Scale:** 64 px per tile; must read at 32 px/tile (check `contact_scene.png`, which is rendered at 50 %).
- **View:** top-down. Bevelled metal plates, rivets, recessed panels, subtle grit noise, dark outline (`#14171a`).
- **Light:** from the top-left. Gradients are computed in screen space even for rotated entities, so every
  direction is lit the same way. Drop shadows are soft, offset to the bottom-right and **inside the footprint**
  (bodies are inset ~2 px top/left, ~5 px bottom/right).
- **Silhouettes first:** each machine has one big, unique centre feature (assembler manipulator, furnace fire,
  drill cutter, lab dome, radar antenna, refinery column...).

## Palette

| Use | Colours |
|---|---|
| Steel | `#2a2f34` `#4d565e` `#6b757e` `#97a1a9` `#d0d7dc` |
| Machine body | `#5d666f` (dark `#3a4148`, light `#7d8790`) |
| Tier 1 / 2 / 3 (belts, undergrounds, splitters) | ochre `#e0a526` / red `#d2402e` / blue `#2f86d6` |
| Assemblers 1 / 2 / 3 deck + corner accent | grey `#6e747b`+ochre / blue-grey `#5a7590`+red / green-grey `#5f826d`+blue |
| Inserters | burner `#7a6048`, basic `#e2a823`, long `#cc3f2e`, fast `#3a7fd2`, filter `#9150c8`, stack `#45a83c`, stack-filter `#8a7fa0` |
| Fire / glow | `#ff7a1a` `#ffc44d` `#fff2b0`; status lamp green `#6dff8a` |
| Cards | mechanics red, motion green, reaction blue, fabrication purple, systems yellow, orbital white (defense black) |
| Modules | speed `#3a7fe0`, efficiency `#3fbf4a`, productivity `#f08a24`; tier = 1-3 pips |
| Character | suit `#e8792a`, trousers/visor teal `#1f8f8a`/`#2fd0c6`, white helmet |
| Accent colour (UI) | warm orange `#F08A24` |

## Naming (renderer contract)

Directions `n/e/s/w` = the direction items move / the entity faces.

- `e_<id>` footprint×64, north/idle. Directional: `e_<id>_<dir>` (non-square entities rotate their footprint).
  Working animation: `e_<id>[_<dir>]_w0..w3`. Extra: `e_small_lamp_on`.
- Belts `belt_<id>_<straight|curve_l|curve_r>_<dir>_f0..f7` (dir = output; tread scrolls 8 px/frame;
  `curve_l` = items turn left: for output `n`, `curve_l` enters from the west, `curve_r` from the east).
- Undergrounds `e_<id>_in_<dir>`, `e_<id>_out_<dir>`; splitters `e_<id>_<dir>` (128×64 n/s, 64×128 e/w, belts baked in).
- Inserters `ins_<id>_base` (64×64), `ins_<id>_arm` (64×16, points +x, pivot at (0, 8)), `ins_<id>_hand`
  (24×24, fingers point +x, centred; rotate with the arm). `e_<id>` is a composited still.
- Pipes `pipe_<mask>` (N=1 E=2 S=4 W=8); `e_pipe_to_ground_<dir>` (dir = side of the above-ground connection).
- Poles `e_small/medium/big_electric_pole`, `e_substation`; `wire` = 8×8 copper pixel (stretch/tint it).
- Natural `e_tree_01..03`, `e_dead_tree`, `e_big_rock`, `e_huge_rock`. Ores `ore_<res>_0..7`, `ore_crude_oil`.
- Character `char_<dir>_f0..f3`, `char_<dir>_idle` (48×64, feet at (24, 58)).
- Icons `i_<item>`, `f_<fluid>` (64×64); UI templates `ui_<name>` (white, 64×64); `status_<name>` (32×32).
- Terrain `tile_<id>_v0..v3` (seamless, interchangeable variants).

`App/Resources/sprite_manifest.json` lists every sprite as `{"name": {"w": px, "h": px}}`.

## Budget

852 PNGs, ~17 MB (limit 25 MB). Working frames are the bulk (~9.6 MB); prefer fewer frames over more.
