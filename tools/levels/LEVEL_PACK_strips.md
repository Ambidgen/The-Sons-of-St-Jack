# THE WANDERER'S ROAD — 3-Level Strip Pack
**3 levels × 3 images each.** Each level is a single horizontal scene built from three
stitchable tiles: a high-angle JRPG view with a detailed near **foreground** at the
bottom, an identifiable **background** receding at the top, and a **road band running
horizontally across every image at about one quarter of the frame height**, entering and
leaving each tile at the same height and width so the three tiles line up as one
scrollable level.

Characters are excluded everywhere — no people, bodies, creatures, animals, statues of
people, or humanoid silhouettes. No text, labels, arrows, or UI baked in.

```
grimdark_levels_3part/
├── L1_T1_village_road_west.png     ┐  tile 1 · 1408×768
├── L1_T2_village_road_core.png     ├  tile 2 · 1408×768
├── L1_T3_village_road_east.png     ┘  tile 3 · 1376×768
├── L2_T1_forest_road_west.png ...  L3_T1_city_road_west.png ...   (same pattern)
└── composites/
    ├── L1_village_road_strip.png         stitched level · 4364×855
    ├── L2_forest_road_strip.png          stitched level · 4364×817
    ├── L3_city_road_strip.png            stitched level · 4364×855
    ├── *_strip_preview.png               web-sized previews · 2400 px wide
    └── 00_master_sheet_three_levels.png  all three levels, labelled
```

---

## The three levels

| # | Level | Tiles (W → E) | Environment |
|---|-------|---------------|-------------|
| 1 | **The Village Road** | western approach → hamlet core → eastern exit | linear village, overcast late afternoon |
| 2 | **The Forest Road** | treeline at dusk → deep-wood stream crossing → ravine | forest road, dim dusk |
| 3 | **The City Road** | muster ground outside the gate → market street → citadel plaza | medieval city, cold dawn |

Story beat: the orphan's road out of the hamlet, through the wood where the gang finds
them, and into the city that finishes the job.

---

## Layout contract (what makes the tiles stitch)

| Property | Value |
|----------|-------|
| Road orientation | perfectly horizontal, edge to edge, parallel to frame top/bottom |
| Road band height | ≈25% of frame height (≈190 px in a 768-px tile) |
| Road centreline | aligned to 50% of frame height (see shift table below) |
| Side edges | road enters and exits at identical height + width → flush neighbours |
| Foreground | bottom ≈¼ of frame — high-detail, nearest to camera |
| Background | top of frame — terrain/rooftops/canopy receding into mist |
| Camera | steep high angle (≈55–60° pitch), no vanishing-point skew in the road |

**Alignment shifts applied when stitching** (`stitch_levels.py`):

| Level | Tile 1 | Tile 2 | Tile 3 |
|-------|--------|--------|--------|
| L1 Village | road @ 0.505 → −4 px | @ 0.535 → −27 px | @ 0.465 → +29 px |
| L2 Forest  | @ 0.505 → −31 px | @ 0.470 → −2 px | @ 0.425 → +35 px |
| L3 City    | @ 0.500 → −3 px | @ 0.500 → −3 px | @ 0.490 → +6 px |

Shifts are centred on each level's mean road position, so the correction is split across
tiles and the exposed edge strip stays minimal. Re-run `python3 stitch_levels.py` after
editing the road fractions at the top of the script if you re-generate a tile.

Stitching uses a **170-px feathered (gradient) blend** at each seam plus a 45% mean-tone
match of tiles 2–3 toward tile 1, so the street's keystone line and tone read continuous.
Exposed edge strips from vertical shifting are filled with a **mirrored** (not stretched)
copy of the opposite edge; the one band that read as an artifact was trimmed off the top
of the forest strip.

---

## Detection notes (obstacle / boundary pipeline)

- **Road surface** is the mid-value, low-saturation band across the vertical middle —
  track it as its own walkable region and require it to stay continuous along X.
- **Water**: the forest stream (L2 tile 2) only crosses *under* the road at the stone
  culvert — treat the dark band either side as blocked, not the culvert. The city
  gutters in L3 tile 2 are shallow and walkable; only the cellar hatches and fountain
  basin are solid.
- **Height layers**: this pack is high-angle, not pure plan view, so tall objects
  (rooftops, walls, canopies, ravine cliff) project *upward* in frame. For collision,
  use the object's **base line** at its bottom edge, not its silhouette centroid.
- **Foreground band** (bottom ≈¼) is dense by design — expect it to be mostly blocked
  props (fallen fences, stumps, ravine cliff, market crates) with a walkable strip where
  the road shoulders meet it.
- **Background band** (top) is non-walkable dressing: treat the whole band above the
  road's north shoulder as occlusion, except where the tiles show ground continuing
  (village yards, church steps, the plaza reach in L3).
- Same palette discipline as the previous pack: walkable 0.30–0.62 luma / sat < 0.35,
  rust-red accents are decor only, shadows fall lower-right and are a solid secondary
  signal.

---

## Known compromises

- **L1 tile 2 seam**: the middle tile's plaster/earth texture is slightly more
  brick-like in the village core; the feathered blend hides most of it but a careful eye
  can find the transition in the roadway.
- **L3 tiles 1 → 2 → 3**: tile 3's plaza is deliberately brighter and cleaner than the
  mud-soaked muster ground — read it as the cold-dawn light opening up at the citadel,
  not a lighting error. Tone-matching pulls them 45% together; adjust that factor in
  `stitch_levels.py` if you want them flatter.
- Road **cross-slope**: a few tiles have the road verge sloping a few degrees across the
  band (e.g. L1 tile 3). The centrelines still align; if you need the shoulders perfectly
  level for tile collision, flatten via the mask rather than re-painting.

The earlier pure top-down 10-level pack is untouched in `../grimdark_jrpg_levels/` if you
want plan-view tiles for a different camera mode.
