# Character sprite sheets

AI-generated replacements for the 40 base character models in `assets/placeholder/char/` (38 people, plus the dog and the wolf). Each sheet holds four characters, and every character faces the viewer.

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

- `sheets/`: the generated sheets. Each is a 1254 × 1254 px RGB PNG.
- `manifest.json`: for each sheet, the four sprites, the SVG model each one replaces (`assets/placeholder/char/<key>.svg`), and the exact prompt used.

## Format

- 2 × 2 grid. Slots are top-left, top-right, bottom-left and bottom-right, with one full-body character per slot.
- The background is exactly `#FF00FF` (255, 0, 255). The generator's background was close to that colour, about (249, 3, 246), so pixels within 40 of pure magenta were set to exact magenta. No figure pixels were changed.
- No ground shadow. The game's rig draws its own shadow.
- The style follows the placeholders: woodcut ink on parchment, with colour only for blood, fire and gold. Ser Gauntley (sheet 05) is the only fully coloured figure, as in the design notes.

## Known limits

- **Dog (sheet 03).** The head and chest face the viewer, but the hindquarters turn slightly. The placeholder dog and wolf were drawn in profile; these are front-facing as requested.
- **Not covered:** the 42 `_field` SVGs (`char/*_field.svg`), which are the on-map figures. They need their own sheets, or a decision to reuse these.
- **Scale:** sprites are not normalised to a common height. Children are smaller than adults, as in the placeholders.
- **Not wired into the game.** The game draws characters as articulated rigs (`assets/placeholder/rig/`, `rigs.json`). A flat sprite needs a flat-sprite path; `Rig` already has one for art without a rig.
- Opening the project in Godot creates the usual `.import` files for the new PNGs.

## Extracting (planned, not yet done)

1. Key out `#FF00FF` to alpha.
2. Split each sheet into its four slots, or into its four connected figures.
3. Trim each figure and anchor it at the feet (bottom centre).
