# THE WANDERER'S ROAD — Level Pack
**10 top-down, character-free grimdark JRPG levels** · village → forest road → medieval urban
Format: 1024 × 1024 PNG, square plan-view, painted dark-fantasy style.

Story spine: a wandering orphan is taken in by a road gang — the levels walk the
player from the hamlet they were cast out of, out along the forest roads, into the
city that will finish making them a killer.

---

## Files

| # | File | Environment | Route axis |
|---|------|-------------|------------|
| 01 | `L01_ashfen_hamlet_outskirts.png` | Linear village — dying hamlet outskirts | West → East |
| 02 | `L02_the_sunk_furrows.png` | Flooded farmland between village and wood | South → North |
| 03 | `L03_gallows_bend_road.png` | Forest road at a notorious bend | West → East |
| 04 | `L04_thornwake_thicket.png` | Deep thorn-forest interior trail | West → East |
| 05 | `L05_blackwood_camp.png` | Outlaw camp clearing (the gang's lair) | West → East |
| 06 | `L06_mirewatch_gate.png` | Palisaded frontier settlement + marsh bridge | South → North |
| 07 | `L07_st_ordrics_ward.png` | Crowded medieval slum ward | West → East |
| 08 | `L08_butchers_steps_market.png` | Great market square, butcher quarter | West → East |
| 09 | `L09_iron_vigil_chapterhouse.png` | Walled militant chapterhouse & cloister | West → East |
| 10 | `L10_pyre_yards_citadel.png` | Execution yard at the citadel — final arena | West → East |

`00_contact_sheet_all_levels.png` — labelled overview of all ten (not for in-game use).
`make_contact_sheet.py` — regenerates the sheet if you add or replace levels.

---

## Design decisions made for obstacle / boundary detection

- **True plan view, no parallax.** Every map is shot from directly overhead with a
  90° top-down, orthographic feel — tiles are square-on, not isometric. A 1-px
  collision grid can be lifted straight off the pixels without vanishing-point skew.
- **One consistent shadow direction.** All objects cast short soft shadows toward the
  **lower-right**. Keep this in mind when thresholding: shadow pixels sit
  lower-right of every blocker and are a reliable "solid" secondary signal.
- **Flat ambient lighting, no vignette.** Lighting does not roll off toward the edges,
  so edge tiles don't get falsely classified as walls by a brightness threshold.
- **High silhouette contrast.** Walkable ground (mud, road, cobbles, grass, ash) is
  mid-value and low-saturation; blockers (walls, roofs, canopies, wagons, water,
  boulders) read darker, cooler, and harder-edged.
- **No characters, no statues of people.** Confirmed visually across all ten — the
  scene is unpopulated, so nothing humanoid will be misread as an actor collider.
- **No text, arrows, grids, or map markers** baked into any level, so no glyphs get
  detected as props.

### Suggested detection pipeline
1. Sample readability at target tile scale (512² or 256² per screen) and blur 1–2 px
   before thresholding — the paint strokes are hand-inked and will alias otherwise.
2. Build a walkable mask from luminance + saturation (walkable ≈ 0.30–0.62 luma,
   sat < ~0.35); treat saturated rust/red pixels as decor, not walls.
3. **Blocked-by-water** (L02, L06) should be its own layer: floodwater and ditches are
   very dark, very low-saturation blue-greens. L04's black brook is impassable except
   at the log bridge; L06's river is impassable except at the stone-and-timber bridge.
4. **Blocked-by-canopy** (L03, L04, L05) is a special case — treetops are soft-edged
   circular blobs. Use an edge/contour pass rather than a luma threshold there.
5. Doorways and gates that are *open* (L06 gatehouse, L09 cloister entries, L10
   portcullis, L01 cottage doors) are painted darker than the road — don't let a naive
   "dark = solid" rule seal the level's only exits. Carve passages on the routes above.
6. Test route continuity along the stated axis per level: the entry edge must stay
   reachable from the exit edge after the mask is applied.

---

## QA notes (flagged, re-rolls pending)

Three frames came back with issues worth fixing before they enter the pipeline.
The generator's 10-images-per-turn cap was hit producing the set, so these are
queued for a re-roll on request:

- **L02 — The Sunk Furrows:** painted with oblique parallax (windmill, hedgerows and
  hoaricks show a tilted side view). Usable if you want a stylised map screen, but
  its collision grid will not map 1:1 to a flat grid. *Re-roll recommended.*
- **L03 — Gallows-Bend Road:** tree trunks are drawn in side view with a faint horizon
  rather than as overhead canopies, and the milestone carries carved-looking marks.
  The layout reads correctly, but the canopy layer will be awkward to threshold.
  *Re-roll recommended.*
- **L10 — Pyre Yards:** a pale robed **statue on a plinth** appears in the upper-right
  quadrant (the brief asked for a bare pedestal). It is a statue, not a character, but
  it is a humanoid silhouette and the sort of thing that reads as an actor collider.
  *Fix recommended* — either re-roll or mask that quadrant's plinth out in-editor.

Everything else (01, 04, 05, 06, 07, 08, 09) is clean: flat plan view, no figures,
consistent palette, routes readable edge to edge.

---

## Suggested use per level (encounter skeletons)

| # | Beat in the orphan's arc | Encounter hook |
|---|--------------------------|----------------|
| 01 | Cast out / scavenging the dead hamlet | Tutorial movement, first scavenge nodes |
| 02 | Fleeing across drowned fields in rain | Timed crossing while ditches flood |
| 03 | First sight of the gang's justice | Scripted ambush at the pinch point |
| 04 | Forced march through the deep wood | Stealth gauntlet, log-bridge chokepoint |
| 05 | Indoctrination — the camp | Safe hub with training yard, gang NPCs |
| 06 | First job: a frontier town | Gate infiltration, bridge defence |
| 07 | Cities make you into a knife | Alley pursuit maze, informant hunt |
| 08 | Public execution square | Crowd control / escape set-piece |
| 09 | The order that wants a weapon | Cloister infiltration, low combat |
| 10 | The yard where it ends | Boss arena, no retreats |

---

## Palette (for UI/tile tinting)

| Role | Hex | Use |
|------|-----|-----|
| Bog olive | `#5A6048` | grass, verge, farmland |
| Road mud | `#6B5F4B` | dirt, trampled ground |
| Cold slate | `#4A5058` | stone, cobbles, overcast sky-shadow |
| Deep canopy | `#2E3A31` | forest, hedgerow, blocker mass |
| Water black | `#232C2E` | floodwater, ditches, brooks |
| Bone | `#C9C2B4` | plaster, bone, graves, ash |
| Rust blood | `#7A3B2E` | accent only — banners, stains, gore |
