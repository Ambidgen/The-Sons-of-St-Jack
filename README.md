# The Sons of St. Jack: Act One (Godot prototype)

A playable vertical slice of Act One. It runs from Derrick's childhood in Harrowgate, through the years he spends alone, to the night he first meets the Sons of St. Jack. The act ends on the title card.

This build remakes the act on the new level paintings. Every stage is now drawn from one of them, and **where Derrick can walk is worked out from the painting's pixels**: road, ground he may cross, water, obstacles and the edge of the playable area. The opening is longer: the idyllic Harrowgate childhood now plays at **five, seven and nine**, with two time skips inside the one stage.

## Question

**Can Act One carry the player from a childhood trauma to the moment the Sons of St. Jack take hold of him, as a chain of short, linear, cinematic stages, where every stage exists for one story beat and the player never wanders?**

Three smaller questions sit underneath it:

- **Does a longer, happier childhood make the loss land harder?** The player now lives through three ages in Harrowgate before the raid.
- **Does fighting alone, with wounds that never heal, make the lost years feel desperate?** Derrick is a party of one for the whole act, and his scars carry across the time skips.
- **Can painted levels drive the game directly?** No walk masks, no hand-drawn collision: a stage names a few sample tiles, and pixel detection does the rest.

## How to run

1. Open Godot 4.7.2 (`Godot_v4.7.2-stable_win64.exe`).
2. In the Project Manager, click **Import**, pick this folder's `project.godot`, then **Import & Edit**.
3. Press **F5**. On the title screen, choose **Begin Act One**, or use **Chapter Select** to jump to any stage.

The first import takes a little while: Godot imports the level paintings and rasterises the SVG placeholders.

## Act One at a glance

| # | Stage | Painting | Derrick | What happens | Fight |
|---|---|---|---|---|---|
| I | Harrowgate | Village Road strip | 5, 7, 9 | **Spring, five:** his mother on the road, Patch the dog, the plough he can't push. **Two summers later, seven:** he's always the dragon, his mother lets his sleeves out, the village talks about Ser Gauntley, his father gives him an ash stick. **The autumn he's nine:** the knight on the green, the spar, "Shield up. Chin down.", supper. | Sparring (Gauntley yields) |
| II | That Night | Ashfen Hamlet Outskirts | 9 | Raiders with no banners come up the road with torches. His father turns back to face them. His mother takes him across the yards to the old cellar by the well and tells him to count to a thousand. | none |
| III | Dawn | Village Road, burned | 9 | The same village, burned, walked right to left. His stick; the shrouds on the green where the knight let him win; Gauntley arrives too late and promises to come back. Three days of waiting. | none |
| IV | Ashford | Mirewatch Gate | 13 | Four winters later. The bridge over black water, the Brother at the gate ("There's no Harrowgate."), a family through a window. | none |
| V | The Butcher's Steps | Butcher's Steps Market | 13 | Ashford's market in the rain, the empty ropes on the scaffold. He steals bread and fights a starving dog for it on the butchers' row. | Starving dog |
| VI | The Ostry Farm | The Sunk Furrows | 16 | Harvest on a causeway over flooded fields. He almost belongs. Accused of stealing a knife; the brawl can be won or lost, and changes nothing. | Ostry brothers (a loss is allowed) |
| VII | The Levy | Blackwood Camp | 20 | The night before Wendmere. Sergeant Pike gives him a spear. Soldiers say Gauntley rides with the lord. **Aldo** sits him by a fire: "Two's harder to kill than one." | none |
| VIII | Wendmere | Forest Road strip | 20 | The morning after, in fog. Aldo is dying on the road: sit with him or walk on. Gauntley rides past and doesn't recognise him. A corpse-picker wants his boots; Derrick takes his knife. | Corpse-picker |
| IX | The Coldharbour Road | Gallows-Bend Road | 21 | Snow. A Sons of St. Jack warrant nailed to a gallows. Eyes in the trees below the road. | none |
| X | The Thornwake | Thornwake Thicket | 21 | The wolves, the log bridge over the black brook, the collapse in the snow, and a city burning on the horizon. | Winter wolves |
| XI | Coldharbour | City Road strip | 21 | The gate full of abandoned carts, a street being emptied house by house, a clerk writing it all down, a coin-and-nail banner over the fire in the square. | none |
| XII | St. Ordric's Ward | St. Ordric's Ward | 21 | Into the alleys. Cornered at a dead end; one move, the headbutt; the blackout; the snapped pinky; the Tall Man's trial: "Fetch the dogs." (your scene, word for word) | The alley: one move |

The pacing report estimates the act at about **24½ minutes** at a normal reading speed, up from 18½ (table below). Most of the new time is the extended childhood.

Two paintings from the top-down pack aren't used: **Iron Vigil Chapterhouse** and **Pyre Yards** are the militant order and the citadel's execution yard, which belong to later acts. The pack's own notes also flag a statue in the Pyre Yards to fix first.

### The extended opening

Harrowgate is one stage played three times over, on the same road through the village:

- **Five (spring):** the western approach: the furrows, the hedges, his parents in the fields.
- **Seven (summer):** the village core: the children's game, the well, the church, the stick.
- **Nine (autumn):** the eastern green: Gauntley, the spar, home.

Each time skip is a line across the road. Stepping on it fades out, a **gate** shuts the road behind him (so the past can't be walked back into), the old cast leave and the new ones arrive, and the `age` command redraws Derrick older and taller (`tot` 0.72×, `small` 0.86×, `child` 1×) with a caption: "Derrick, seven." The furrows, hedges and houses he passes as a five-year-old are the ones the raiders burn four years later. Dawn walks him back through them.

## Levels and pixel detection

Every stage names a painting in `assets/levels/`:

```json
"level": {"art": "village_road", "scale": 1.0, "show": "village_burned", "glow": "village_embers"},
"start": [66, 7], "exit": {"edge": "left"},
"sense": {"road": [[2, 6], [6, 6], [10, 6]], "ground": [[4, 5]], "solid": [[5, 7]], "reach": 1.5, "block": [[41, 9, 4, 4]]}
```

`art` is the painting that detection reads; `show` is an optional variant drawn instead (the burned village at Dawn is the same painting, burned by `tools/levels/burn_village.py`, so its collision is the village's). `scale` maps painting pixels to world pixels: 1.0 for the 4364 px road strips, 1.25 or 1.5 for the 1024 px top-down maps. The map size in 64 px tiles follows from that.

**How the detection works** (`scenes/stage/terrain_sense.gd`):

1. The painting is sampled at one sample per 4 world pixels. Every 16 px cell (a quarter of a tile) gets six numbers: brightness, two colour axes (red–green, blue–yellow), texture (how much the brightness varies), and its darkest and brightest samples (ink outlines and highlights).
2. Each sample tile under `sense` becomes a small colour model. Think of them as magic-wand clicks: "this is road", "this is grass you may cross", "this is a roof".
3. **Road** grows out from the road samples, cell by cell, while the next cell looks like road, isn't ink-dark, doesn't jump in brightness (an outline), and doesn't look more like one of the solid samples.
4. **Ground** (verges, yards, grass) grows off the road the same way, but only `reach` tiles deep. That limit is the stage's boundary, so a wide painting still plays as a corridor and never as a sandbox.
5. **Water** is found by colour: pale cool reflections (puddles), and, where a stage opts in with `water_y`, dark smooth blue-greens (the flooded ditches at the Ostry farm).
6. A tile is walkable when most of its 16 cells are, and counts as road when half are road. Tiles the start can't reach are out of bounds; solid tiles that border the walkable area are the obstacles.

It takes 0.2 to 0.6 s a stage, once per session (the result is cached). `block` and `keep` rectangles are there for the few places where the story needs a way shut or open (a yard that would lead off the edge of the world, the open gate at Ashford that's painted darker than the road).

**Roads matter in play.** Derrick is 20% slower off the road (`config.offroad_step`). Click-walks and scripted walks take the road where they can (`StageMap.route`, which charges 1.6× for off-road steps), and a scripted walk that would cut through something the painting says is solid goes around it.

**Beats are lines.** A stage places its triggers as lines across the walkable area: `"lines": {"a": {"x": 12}}` is every walkable tile in column 12, and `{"y": 8}`, a range, a rectangle or a list of cells also work. A full-width line can't be walked around, and the smoke test proves it for every beat.

**To see what was detected**, press **F7** on any stage: amber is road, green ground, blue water, red obstacles, dark out of bounds. `tests/level_dump.tscn` writes the same thing to JSON and PNG for every stage.

**To use a new painting**, drop the PNG in `assets/levels/` (copy an existing `.import` so it imports as an Image), point a stage's `level.art` at it, set `start` and `exit`, and give `sense` five to ten road sample tiles spread along the route, plus a few ground and solid samples where the road meets them. Press F7 to check, then tune `reach`, `t_road` (how similar to road a cell must be; lower is stricter) or add a `block` rectangle.

### Parallax

The road strips are painted at a high angle, so their own top band already recedes into the distance. On top of the paintings:

- **Foreground silhouettes** (grass and branches in Harrowgate, the burned version at Dawn, rooftops in Coldharbour) hang from the bottom of the screen and slide at **1.3×** the camera.
- **Mist bands** drift over the far part of the painting at **0.55–0.6×** the camera, so the distance seems to stay put while the road passes underneath (Harrowgate, Dawn, Wendmere).
- **Glow** layers (Dawn's smouldering roofs) are added light that the time-of-day tint doesn't darken.

Stages list these under `"depth"` and `"mist"`.

## How the linear, cinematic design works

- **Every beat stands on the path.** Each story beat is a line across the corridor, so the player walks into the story rather than looking for it. The smoke test blocks each line in turn and checks that the exit becomes unreachable. If a beat could be walked around, the test fails.
- **Beats are packed close together.** No stretch of walking with nothing happening is longer than about 5 seconds; the test warns above 15 (`config.json > pacing.max_beat_gap_sec`).
- **There is no backtracking.** The road strips run left to right (Dawn right to left, back through the same village); the top-down maps run up the screen or across it. The childhood's time skips shut the road behind him.
- **Every scene uses film grammar.** Each script letterboxes automatically. Scripts can pan the camera, push in for close-ups, open with a chapter card, run narration captions, shift the time of day, add weather, fire light and fog, and shake the screen.
- **Sound captions stand in for audio.** Lines like `[ The church bell, far off. Six strokes. ]` mark where a sound cue belongs.
- **The Tall Man (Jack) can't be hurried.** His lines type at about 21 characters a second, cannot be skipped, and hold for a short beat (design doc §3).
- **The trial's choice might not matter.** When the Tall Man asks Derrick to plead guilty, the narration stays on screen over **Shake your head** or **Nod**. Nodding gets "He meant to nod. His head shook instead." Options marked `defiant` jitter and fade once Complicity passes 40, and disable at 75 (the Accomplice mechanic, §4.2).
- **Choices are counted.** Sitting with Aldo adds 1 to **Defiance** and walking on adds 1 to **Complicity**; so does refusing or agreeing to plead guilty. Aldo is now met the night before the battle, so the choice is about someone the player knows.
- **Scars can come from the story.** The snapped pinky is written into the script (`{"wound": "..."}`), so it goes on Derrick's scar list for good.

## Combat

The turn-based battle system from the `godot-jrpg-battle` skill, set to **ATB** timing by default as the closest stand-in for the real-time ABS combat the design doc calls for. The Battle Lab can switch to CTB or ROUND.

| Rule | Design doc | Tune in |
|---|---|---|
| **Maiming.** One hit of 40% or more of max HP leaves a permanent wound: −8% max HP, −5% strength, listed under Status → Scars with where it happened. | §4.3 | `config.maim_threshold`, `wound_max_hp`, `wound_atk` |
| **Healing is halved.** A rag stops bleeding; it doesn't mend you. | §4.3 | `config.heal_mult` |
| **Bleeding.** Damage every turn. Gouge, bites and knives cause it. | §4.3 | `statuses.json` |
| **The alley: one move.** Only the man gripping Derrick's arm can be targeted. Strike becomes **Headbutt**, there are no skills or items, and running fails. The headbutt drops him, an unseen fist ends the fight, and the script picks up in the dark. | §4.4 | `encounters.json > alley` |
| **Jack's Impunity.** Every blow is evaded, and after 3 actions a scripted counter ends the fight. Kept in the Battle Lab as a test of the rule. | §4.4 | `encounters.json > hopeless` |
| **Yield.** Gauntley stops the spar at 55% HP. It counts as a win. | new | `enemies.json > yield_below` |
| **Fights that can be lost.** The Ostry brawl continues the story either way. | new | `encounters.json > lose_ok` |
| **Growing up.** Each time skip sets Derrick's age and level (5 → 7 → 9 → 13 → 16 → 20 → 21) and teaches him a new skill: Gouge, Skull Crack, Riposte, Last Stand. There is no grinding. | new | `data/stages/*.json > derrick`, the `age` command |

There is no magic. **Grit** replaces MP: skills cost grit, and Brace gets 2 back.

### Balance

Each row simulates the fight 200 times with the AI playing Derrick at the age he is when he meets it (`tests/smoke.gd`, ATB):

```
spar            win 100%  turns  5.5  HP  83%  maimed   0%
dog             win  92%  turns  6.9  HP  49%  maimed   0%
ostry           win  96%  turns 12.4  HP  28%  maimed   0%
looter          win  99%  turns  6.1  HP  40%  maimed   0%
wolves          win  95%  turns  5.4  HP  52%  maimed  11%
alley           scripted 100%  turns  1.0  HP   0%  maimed   0%
hopeless        scripted 100%  turns  8.4  HP   0%  maimed   0%
```

### Pacing report (Battle Lab → Pacing report)

```
I.   Harrowgate             5:09  walk 0:13  scenes 4:38  fights 0:17  beats 12  longest quiet walk  1.8s  OK
II.  That Night             1:27  walk 0:02  scenes 1:25  fights 0:00  beats 3  longest quiet walk  1.0s  OK
III. Dawn                   2:10  walk 0:13  scenes 1:56  fights 0:00  beats 4  longest quiet walk  4.6s  OK
IV.  Ashford                0:51  walk 0:03  scenes 0:48  fights 0:00  beats 3  longest quiet walk  1.2s  OK
V.   The Butcher's Steps    1:09  walk 0:06  scenes 0:43  fights 0:20  beats 2  longest quiet walk  4.4s  OK
VI.  The Ostry Farm         2:30  walk 0:05  scenes 1:50  fights 0:33  beats 3  longest quiet walk  2.0s  OK
VII. The Levy               1:27  walk 0:04  scenes 1:23  fights 0:00  beats 3  longest quiet walk  1.2s  OK
VIII. Wendmere              2:05  walk 0:13  scenes 1:32  fights 0:19  beats 4  longest quiet walk  3.0s  OK
IX.  The Coldharbour Road   0:54  walk 0:04  scenes 0:50  fights 0:00  beats 3  longest quiet walk  1.6s  OK
X.   The Thornwake          1:15  walk 0:04  scenes 0:53  fights 0:17  beats 3  longest quiet walk  1.4s  OK
XI.  Coldharbour            1:13  walk 0:13  scenes 1:00  fights 0:00  beats 4  longest quiet walk  4.2s  OK
XII. St. Ordric's Ward      4:22  walk 0:02  scenes 4:12  fights 0:07  beats 3  longest quiet walk  1.0s  OK
Act One total: 24:36
```

## Controls

| | Keyboard | Mouse | Gamepad |
|---|---|---|---|
| Walk | Arrows or WASD | Click a tile: Derrick walks there, along the road where he can. Hold the button to steer. | D-pad / stick |
| Talk / look | Z, Enter, Space, J (facing it) | Click the person or thing (head or feet) | A |
| Advance text | Confirm | Left click anywhere | A |
| Menus and choices | Arrows + confirm | Point and click | D-pad + A |
| Fight: pick a target | Arrows + confirm | Point at an enemy and click. At the command menu, clicking an enemy strikes it. | D-pad + A |
| Cancel / back | X, Esc, Backspace, K | Right click | B |
| Field menu | C, Tab, or cancel | Right click | Start / Y |

A key press takes over from a click-walk at once, and cutscenes cancel one. The tile under the pointer is marked: gold over someone or something you can use, red where he can't go.

**Debug keys:**

- **F1:** auto-battle
- **F2:** win the fight now, or trigger the scripted ending
- **F3:** heal
- **F4:** jump to just before the next beat
- **F5:** speed ×1/×2/×4
- **F6:** reload every `data/*.json` without restarting
- **F7:** show what the pixel detection found on this stage

## Tuning and writing

The story, dialogue, levels and numbers are all JSON:

- `data/stages/<stage>.json` holds one stage: `level` and `sense` (the painting and its detection settings), `start`, `exit`, `lines` and `triggers` (the beats), `gates`, `cast` (each placed with `"at": [x, y]`), `props`, `lights`, `fx`, `depth`, `mist`, and `scripts`, the scenes as director commands. Tile coordinates are in 64 px tiles; F7 shows the grid's content.
- `data/cast.json` sets each speaker's name, portrait, name colour and text speed.
- `data/encounters.json`, `enemies.json`, `skills.json`, `items.json` and `statuses.json` hold the fights.
- `data/config.json` holds the act order, turn system, maiming and healing rules, off-road speed, the Complicity thresholds and the pacing constants.
- `data/actors.json` holds Derrick's forms (`tot`, `small`, `child`, `youth`, `lad`, `man`), with a drawing scale for the small ones.

**Director commands** (one per line, and `"wait": false` makes most of them run in the background):

- **Text:** `card`, `caption`, `sound`, `hint`, `say`, `talk` (a list of `[who, text]` pairs), `choice` (options can be `defiant`, `once` or `repeat`)
- **Camera:** `letterbox`, `camera` (cast id or `[x, y]`), `zoom`, `shake`, `flash`, `fade`
- **Actors:** `walk` (`to` or `path`; `"direct": true` walks the straight legs even through scenery, for riders and scripted chases), `face`, `show`, `hide`, `teleport`, `emote`, `pose`, `fall`, `rise` (the fallen can be stepped over), `act` (a body action: `nod`, `shake`, `point`, `attack`, `hurt`, `cast`, `peck`, and the held poses `raise`, `cower`, `guard`, `yield`, released with `"do": "reset"`)
- **World:** `tint`, `weather` (`rain`, `snow`, `ash`, `fog`), `light`, `retile` (`{"art": key}` swaps the painting), `gate` (`{"gate": "spring", "on": true}` shuts a strip of tiles), `slats`, `slats_shadow`
- **Game:** `battle` (with `win` and `lose` branches), `set`, `add`, `if`, `give`, `wound`, `heal`, `growth`, `age` (a time skip inside a stage: `{"age": "small", "level": 1, "text": "Derrick, seven."}`), `checkpoint`
- **Flow:** `wait`, `run`, `next`, `title_drop`, `end_act`

After editing, run the smoke test. It names any script that refers to a cast member, encounter, item or gate that doesn't exist, any line that covers no ground, and any beat that can be walked around.

`tools/levels/build_levels.py` is how the twelve stage files were first written, with `sense_params.py` holding each painting's sample tiles. The JSON files are the source of truth now; edit them directly.

## Verification

```bash
godot --headless --path . --import
godot --headless --path . res://tests/smoke.tscn            # data, rigs, pixel detection, scripts compile, rules, linearity, balance, pacing
godot --headless --path . res://tests/level_dump.tscn -- --out=/tmp/levels                                # what detection found, per stage
xvfb-run -a godot --path . --rendering-driver opengl3 res://tests/tour.tscn -- --out=/tmp/tour            # keyboard
xvfb-run -a godot --path . --rendering-driver opengl3 res://tests/tour.tscn -- --out=/tmp/tour --mouse    # mouse only
xvfb-run -a godot --path . --rendering-driver opengl3 res://tests/edge.tscn                              # corner cases
xvfb-run -a godot --path . --rendering-driver opengl3 res://tests/stage_shots.tscn -- --out=/tmp/shots --sense   # every stage, with the F7 overlay
```

The tour plays the whole act from the title screen with synthetic input and saves screenshots. It walks each stage's route, advances the dialogue, hands the fights to the AI, refuses to plead guilty, and checks that the snapped pinky ends up on the scar list. Use `-- --stage=s05_butchers_steps --only` to tour a single stage, `--nod` to take the compliant option at every choice, and `--mouse` to play with nothing but clicks. A watchdog reports exactly where it is if a stage stops making progress.

The edge test covers what a straight run doesn't: a click-walk, a click on the painted hedge (detected as solid), keys cancelling a click-walk, the right-click menu, click-to-talk, the pointing hand, clicks during a cutscene, hold-to-steer, bread by mouse, backing out of aiming, losing a fight and getting up, and the title screen's Continue, Chapter Select and Battle Lab.

### Playtest log (this build)

- **Runs:** the smoke test, a full keyboard playthrough, a full mouse-only playthrough (88 walk clicks), the Nod branch of the trial, and the 33 edge checks. Every run passes.
- **Pixel detection:** all twelve stages read their paintings in 0.2–0.6 s each. The smoke test checks that every start, exit and beat line lands on detected ground, that at least a quarter of the walkable tiles are road, and that no stage is more than 45% walkable (a sandbox guard). Two stages failed that guard on the first pass (Ashford and the market detected their whole towns as open ground); they now block off everything but the bridge-and-gate road and the run from the bread cart to the butchers' row.
- **Bug fixed: people parked in the way.** Two scripts left characters standing where the player had to go: Derrick's parents walked onto the exit at the end of Harrowgate, and the Ostrys stood across the causeway after the brawl. The parents now walk on home ahead of him and out of sight, and the Ostrys walk back down the causeway behind him. The route-finding used by F4 and the tests used to aim at a cell someone was standing on; it now picks a free cell of the same line.
- **Bug fixed: dead wolves blocked the Thornwake.** The fight's bodies fell across the only path. The fallen (dead wolves, the corpse-picker, Aldo) can now be stepped over.
- **Bug fixed: a script could hang on a hidden body.** Asking a hidden character to act (attack, nod) and waiting for it never finished, because hidden bodies don't animate. The edge test caught it; a hidden body now skips the action.
- **Fixed for clarity:** the F7 view now darkens everything outside the playable area and sits above the night tint; the Chapter Select list moved up so all twelve chapters fit.

## Structure

```
project.godot
autoload/   data.gd · game.gd (Derrick, forms, wounds, Complicity/Defiance, checkpoints, input) · router.gd
ui/         ui_style.gd · menu_cursor.gd · dialogue_box.gd · field_menu.gd · cinema.gd
battle/     battler.gd · turn_queue.gd · battle_rules.gd · battle_sim.gd · battler_view.gd · battle_hud.gd
scenes/     actor/rig.gd (articulated bodies) · title/ (title, Chapter Select, Battle Lab) · battle/
            stage/ stage.gd · stage_map.gd (walkable shape, lines, gates, road routing)
                   terrain_sense.gd (pixel detection) · director.gd · pacing.gd · tile_cursor.gd
data/       config · actors · cast · enemies · skills · items · statuses · encounters · stages/*.json
assets/levels/        the level paintings (imported as Images), village_burned + village_embers, fore/ silhouettes
assets/placeholder/   generated SVG art: char/ · rig/ (part sheets) · rigs.json · portraits · battle backdrops
tools/      make_placeholders.py · levels/ (the level packs' notes, stitch script, burn_village.py, build_levels.py)
tests/      smoke · tour (keyboard or --mouse) · edge · level_dump · stage_shots · rig_gallery · gallery
```

The earlier painted stages (`assets/stages/`) and their art guide files are gone from this build; the new paintings replace them. They are still in the older builds in your `_old` folder.

## Placeholder art

The characters, portraits, props and battle backdrops are still the generated woodcut placeholders from `tools/make_placeholders.py`: ink on parchment with hatched shading, colour kept for fire, blood, water and gold, and Ser Gauntley the only fully coloured person in the act. Every body is an articulated rig (legs that bend at the knee, swinging arms, swaying hems, hounds and horses with four legs), animated by `scenes/actor/rig.gd`. To regenerate, run `python3 tools/make_placeholders.py`; to review, run `tests/gallery.tscn` and `tests/rig_gallery.tscn`.

## Defaults you may want to change

- **Which painting plays which beat** is my call (table above). The Ashford beats moved to the palisade bridge (Mirewatch Gate) and the market (Butcher's Steps); the wolves moved from the snowy road to the Thornwake. Swapping a stage's painting is one line plus new sample tiles.
- **The new childhood scenes are a first draft:** spring at five (the plough, Patch), summer at seven (the dragon game, the sleeves, the stick). So are the levy camp, Sergeant Pike and Aldo's earlier scene, the gate at Ashford, the clerk in Coldharbour and the St. Ordric's lead-in. Cut or rewrite any of them.
- **The raid now has visible raiders:** three black shapes with torches on the road, still "men with no banners". The rest stays off screen, heard from the cellar.
- **The Coldharbour scene is your prose, word for word**, moved into the alleys of St. Ordric's Ward.
- **The road strips are high-angle paintings** played on a top-down grid. Characters walk the road band; the houses and hedges above it are scenery, as the pack's notes suggest.
- **Names I invented:** Maren and Hob, Patch, Elsbet and Tam, Brother Aldous, the Ostrys, Sergeant Pike, Aldo, Harrowgate, Ashford, Wendmere, Coldharbour and the Thornwake.

## Next steps

- **Re-roll the flagged paintings.** The pack's QA notes mark the Sunk Furrows and Gallows-Bend Road as partly oblique. Detection copes (both stages pass), but a true plan view would make their edges cleaner.
- **The trial by dogs.** "Fetch the dogs." is the obvious opening fight for Act Two, and it echoes the starving dog in Ashford.
- **Use the Pyre Yards and the Iron Vigil Chapterhouse** for Act Two.
- Wire in audio. Every `sound` caption marks where a cue goes.
- Carry Complicity, Defiance and the scar list into Act Two's War Table.
