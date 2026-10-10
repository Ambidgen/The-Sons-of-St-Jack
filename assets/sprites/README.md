# Character sprite sheets

AI-generated replacements for the 40 base character models in `assets/placeholder/char/` (38 people, plus the dog and the wolf). Each sheet holds four characters, and every character faces the viewer. **The 32 finished sprites are in the game:** each one is cut into body parts and rebuilt as an animated 2D mesh rig, and it replaces the placeholder of the same name in battle, on the map and in the portraits.

**Status: 8 of 10 sheets are done.** Sheets 09 and 10 are still to generate. Their prompts are in `manifest.json` with `"status": "pending"`.

| Sheet | Theme | Status |
|---|---|---|
| 01 | Derrick through the years | generated |
| 02 | Derrick at rest, and his parents | generated |
| 03 | Harrowgate children, a neighbour and the dog | generated |
| 04 | The village and the market | generated |
| 05 | Ser Gauntley and the levy | generated |
| 06 | The Ostry farm and the roadside | generated |
| 07 | Saint Jack and his lieutenants | generated |
| 08 | The Sons of St. Jack | generated |
| 09 | The Sons in the field, and the winter wolf | pending |
| 10 | The alley in Coldharbour | pending |

## What's here

- `sheets/`: the generated sheets. Each is a 1254 × 1254 px RGB PNG. Godot skips this folder (`.gdignore`); only the files below are game assets.
- `manifest.json`: for each sheet, the four sprites, the SVG model each one replaces (`assets/placeholder/char/<key>.svg`), and the exact prompt used.
- `rig/<key>.png`: the rig sheet, one cell per body part (shadow, legs or feet, robe, torso, arms, head; the dog's four legs and tail).
- `rigs.json`: how each rig sheet is cut and boned, plus how the figure moves (which hand strikes, chop or thrust). Entries replace the placeholder rigs of the same name in `assets/placeholder/rigs.json`. Each sprite has a battle rig (`<key>`, 1.75 px per art unit) and a map rig (`<key>_field`, 1 px per unit) from the same drawing.
- `char/<key>.png`: the whole figure, flat (turn-order thumbnails and anything else that wants one picture).
- `portrait/<key>.png`: head and shoulders in the round frame used by the dialogue box, the battle HUD and the field menu.

## Format

- 2 × 2 grid. Slots are top-left, top-right, bottom-left and bottom-right, with one full-body character per slot.
- The background is exactly `#FF00FF` (255, 0, 255). The generator's background was close to that colour, about (249, 3, 246), so pixels within 40 of pure magenta were set to exact magenta. No figure pixels were changed.
- No ground shadow. The game's rig draws its own shadow.
- The style follows the placeholders: woodcut ink on parchment, with colour only for blood, fire and gold. Ser Gauntley (sheet 05) is the only fully coloured figure, as in the design notes.

## From sheet to game

Two scripts in `tools/sprites/`, run from the project folder:

```bash
python3 tools/sprites/extract_sprites.py     # sheets -> tools/sprites/work/cut/<key>.png (keyed, one per figure)
python3 tools/sprites/rig_sprites.py [key…]  # cut sprites -> rig/, char/, portrait/, rigs.json
godot --headless --path . --import           # then reimport (new PNGs need mipmaps on: see below)
```

1. **Extract.** Key out the magenta (soft edge, spill removed), label the figures as blobs across the whole sheet and give each to its slot by its centre, so a neighbour's hat or elbow never comes along.
2. **Scale.** Each figure is resampled to 4 px per art unit at the height of the placeholder it replaces (an adult is about 53 units), so scenes keep their proportions. Seated figures use their standing self's scale. Edge pixels take the colour of the nearest solid pixel, which removes the last of the magenta.
3. **Cut.** `tools/sprites/rig_overrides.json` holds the hand-drawn outline of each arm (with whatever the hand holds: sword, spear, axe, lantern, bowl), the neck line, the hem or robe waist, and the shoes under a robe. The head is above the neck; the legs are split below the hem with a watershed that follows the ink; everything else is torso. Clasped hands and seated figures keep their arms in the torso.
4. **Fill what a moving part uncovers.** The torso continues a little way under each arm and under the chin, the legs continue up under the hem, and a blade drawn across a leg leaves no hole. Cut edges that can come into view get a line of ink.
5. **Bone.** Joints at the shoulders, the neck, the waist and the top of each leg; the feet are the origin. The weapon hand (the bigger arm part, or the override) decides which way the figure faces and whether it chops or thrusts.

`tools/sprites/work/review/<key>.png` (not committed) colours each part over the sprite with the joints marked, for checking a cut. `tests/rig_gallery.tscn -- --only=sprite` shows every flat drawing beside its rig, and walking or acting.

**Import settings.** The PNGs in `rig/`, `char/` and `portrait/` are imported with mipmaps (`mipmaps/generate=true` in their `.import` files), and the game draws them with linear-mipmap filtering, so a battle-size drawing stays smooth at map size. Set the same on any new PNG added here.

## In the game

- `Data.tex("char/x")` and `Data.tex("portrait/x")` return `assets/sprites/char|portrait/x.png` when it exists, else the placeholder SVG; `char/x_field` uses the same drawing.
- `Rig` loads `assets/sprites/rigs.json` over the placeholder rigs. Sprite rigs are marked `"view": "front"` and use a front-facing set of moves: the weight shifts from foot to foot while the free foot lifts and foreshortens, arms swing out from the sides, robes sway, strikes come from the weapon hand, plus hurt, cast, nod, shake, point and the held poses (yield, cower, guard, raise). The dog (`"kind": "frontdog"`) trots on diagonal pairs and wags.
- A front-facing drawing "faces" the side its weapon hand is on: flipping a figure to face left or right mirrors it so the weapon is towards the enemy.

## Known limits

- **Still placeholders:** Osric, Nora, Daryl and the wolf (sheet 09), the bearded man, the wiry man and the grabber (sheet 10), and the horses, mounted riders and crow. Generate sheets 09 and 10, add their keys to `HEIGHT` in `rig_sprites.py`, draw their arm outlines in `rig_overrides.json`, and run the two scripts.
- **Ser Gauntley in his helm** (`gauntley_helm`) is rigged but no scene uses him yet.
- **Dog (sheet 03).** The head and chest face the viewer, but the hindquarters turn slightly. The placeholder dog and wolf were drawn in profile; these are front-facing as requested.
- **Front-facing only.** Every sprite faces the viewer, so a figure walking up or down the screen looks the same as one walking across it. Back and side views would need sheets of their own.
