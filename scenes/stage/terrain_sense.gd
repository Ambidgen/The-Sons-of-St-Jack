class_name TerrainSense
extends RefCounted
## Programmatic pixel detection: reads a level painting and works out where the
## road is, what other ground can be walked, what is water, what is an obstacle
## and where the playable area ends. Nothing is hand-painted: no walk mask, no
## collision layer. The stage only names a few sample tiles, the way you'd click
## a magic wand ("this is road", "this is grass you may cross", "this is a roof"),
## and every 16 px cell of the picture is classified against them.
##
## How it works
##   1. The painting is box-sampled to one sample per 4 world px; every cell
##      (4 x 4 samples, a quarter of a tile) gets six numbers: brightness, two
##      colour axes (red-green, blue-yellow), texture (spread of brightness),
##      and its darkest and brightest samples (ink outlines, highlights).
##   2. Each sample tile becomes a little colour model (median + spread of those
##      numbers). A cell's distance to a class is its distance to the nearest model.
##   3. ROAD grows outward from the road samples, cell by cell, while the next cell
##      looks like road, is not darker ink, doesn't jump in brightness (an outline)
##      and doesn't look more like a solid sample than like road.
##   4. GROUND (verges, yards, grass) grows off the road the same way, but only
##      `reach` tiles deep: that limit is the level's boundary, so a wide painting
##      still plays as a corridor and never as a sandbox.
##   5. WATER is found by colour (dark, cool and smooth; or pale reflections).
##   6. A tile is walkable when most of its 16 cells are; it counts as road when
##      half are road. Tiles the start can't reach are out of bounds, and solid
##      tiles that border the walkable area are the obstacles.
## Tuning lives in the stage JSON under "sense" (see the README); `block` and
## `keep` rectangles exist for the few places the story needs a door shut or open.

enum {SOLID, GROUND, ROAD, WATER, OUT}

const TILE := 64
const CELL := 16                    # world px per cell (4 x 4 cells a tile)
const SUB := 4                      # world px per sample (4 x 4 samples a cell)
const NF := 6                       # features: y, cr, cb, std, p10, p90
const FLOOR := [0.035, 0.012, 0.012, 0.02, 0.05, 0.05]
const WEIGHT := [1.0, 1.0, 1.0, 0.5, 0.5, 0.5]
const CLASS_COLOR := {SOLID: Color(0.9, 0.16, 0.16), GROUND: Color(0.24, 0.86, 0.35),
		ROAD: Color(1.0, 0.67, 0.12), WATER: Color(0.16, 0.47, 1.0), OUT: Color(0, 0, 0)}

static var _cache: Dictionary = {}

var w := 0                          # map size in tiles
var h := 0
var cw := 0                         # map size in cells
var ch := 0
var feat: Array = []                # NF PackedFloat32Arrays, cw * ch
var ink := PackedFloat32Array()
var cells := PackedByteArray()      # class per cell
var tiles := PackedByteArray()      # class per tile
var road_count := 0
var walk_count := 0
var ms := 0                         # how long the analysis took


## Analyse once per painting + settings; later stage loads reuse the result.
static func analyze(img: Image, scale: float, p: Dictionary, start: Vector2i, cache_key := "") -> TerrainSense:
	var key := cache_key + "|" + JSON.stringify(p) + "|" + str(start) + "|" + str(scale)
	if cache_key != "" and _cache.has(key):
		return _cache[key]
	var s := TerrainSense.new()
	s._run(img, scale, p, start)
	if cache_key != "":
		_cache[key] = s
	return s


static func clear_cache() -> void:
	_cache.clear()


# ------------------------------------------------------------------ queries
func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < w and c.y < h


func tile(c: Vector2i) -> int:
	return tiles[c.y * w + c.x] if in_bounds(c) else OUT


func walkable(c: Vector2i) -> bool:
	var k := tile(c)
	return k == GROUND or k == ROAD


func is_road(c: Vector2i) -> bool:
	return tile(c) == ROAD


func cell_class(cx: int, cy: int) -> int:
	if cx < 0 or cy < 0 or cx >= cw or cy >= ch:
		return OUT
	return cells[cy * cw + cx]


## One pixel per cell, coloured by class (for the F7 overlay and the test sheets).
func overlay_image(alpha := 0.45) -> Image:
	var img := Image.create(cw, ch, false, Image.FORMAT_RGBA8)
	for cy in ch:
		for cx in cw:
			var tc := int(tiles[(cy / 4) * w + (cx / 4)])
			var col: Color
			if tc == OUT:      # beyond the playable area: darkened, so the corridor stands out
				col = Color(0, 0, 0, minf(1.0, alpha * 1.4))
			else:
				col = CLASS_COLOR[int(cells[cy * cw + cx])]
				col.a = alpha
			img.set_pixel(cx, cy, col)
	return img


## Text map, one character a tile: ',' road  '.' ground  '~' water  '#' obstacle  ' ' out.
func ascii() -> PackedStringArray:
	var out := PackedStringArray()
	for y in h:
		var r := ""
		for x in w:
			match int(tiles[y * w + x]):
				ROAD: r += ","
				GROUND: r += "."
				WATER: r += "~"
				SOLID: r += "#"
				_: r += " "
		out.append(r)
	return out


# ------------------------------------------------------------------ analysis
func _run(img: Image, scale: float, p: Dictionary, start: Vector2i) -> void:
	var t0 := Time.get_ticks_msec()
	w = int(floor(img.get_width() * scale / TILE))
	h = int(floor(img.get_height() * scale / TILE))
	if p.has("map"):
		w = int(p["map"][0])
		h = int(p["map"][1])
	cw = w * 4
	ch = h * 4
	var n := cw * ch
	_features(img, scale)
	var road_tiles: Array = p.get("road", [[start.x, start.y]])
	var road_m := _models(road_tiles)
	var ground_m := _models(p.get("ground", []))
	var solid_m := _models(p.get("solid", []))
	# ink: samples much darker than the road (outlines, deep shadow)
	var ry := 0.0
	for m in road_m:
		ry += m[0]
	ry = ry / maxf(1.0, road_m.size())
	_ink(minf(float(p.get("ink_level", 0.14)), ry * 0.5))
	var d_road := _dist_all(road_m)
	var d_ground := _dist_all(ground_m)
	var d_solid := _dist_all(solid_m)

	cells.resize(n)
	cells.fill(SOLID)
	var blocked := PackedByteArray()
	blocked.resize(n)
	blocked.fill(0)
	for r in p.get("block", []):
		_fill_rect(blocked, r, 1)
	if p.has("band"):   # rows outside the band are out of bounds (strips' sky and foreground)
		var b: Array = p["band"]
		for cy in ch:
			if cy < int(b[0]) * 4 or cy >= (int(b[1]) + 1) * 4:
				for cx in cw:
					blocked[cy * cw + cx] = 1

	# water: dark, cool, smooth (opt in with water_y), or pale cool reflections (puddles)
	var water_y := float(p.get("water_y", -1.0))
	var water_cb := float(p.get("water_cb", 0.0))
	var puddle_cb := float(p.get("puddle_cb", 0.06))
	var water := PackedByteArray()
	water.resize(n)
	for i in n:
		var y: float = feat[0][i]
		var cb: float = feat[2][i]
		var sd: float = feat[3][i]
		var sat := _sat(i)
		var wet := (y < water_y and cb > water_cb and sd < 0.06) or (cb > puddle_cb and y > 0.45 and sat > 0.12)
		water[i] = 1 if wet and p.get("water", true) else 0
		if water[i]:
			cells[i] = WATER

	# road: grow from the road samples
	var t_road := float(p.get("t_road", 6.0))
	var ink_road := float(p.get("ink_road", 0.35))
	var step := float(p.get("step", 0.09))
	var road := PackedByteArray()
	road.resize(n)
	road.fill(0)
	var q := PackedInt32Array()
	for t in road_tiles:
		for i in _tile_cells(int(t[0]), int(t[1])):
			if blocked[i] == 0 and road[i] == 0:
				road[i] = 1
				q.append(i)
	var head := 0
	while head < q.size():
		var c := q[head]
		head += 1
		var cx := c % cw
		var cy := c / cw
		for d in 4:
			var nx := cx + (1 if d == 0 else (-1 if d == 1 else 0))
			var ny := cy + (1 if d == 2 else (-1 if d == 3 else 0))
			if nx < 0 or ny < 0 or nx >= cw or ny >= ch:
				continue
			var ni := ny * cw + nx
			if road[ni] or blocked[ni] or water[ni]:
				continue
			if ink[ni] > ink_road or absf(feat[0][ni] - feat[0][c]) > step:
				continue
			if d_road[ni] < t_road and d_road[ni] < d_solid[ni]:
				road[ni] = 1
				q.append(ni)

	# ground: grows off the road (and the ground samples), at most `reach` tiles deep
	var t_g := float(p.get("t_ground", 6.0))
	var t_loose := float(p.get("t_road_loose", t_road * 1.6))
	var ink_g := float(p.get("ink_ground", 0.3))
	var reach := int(round(float(p.get("reach", 2.0)) * 4.0))
	var ground := PackedByteArray()
	ground.resize(n)
	ground.fill(0)
	var depth := PackedInt32Array()
	depth.resize(n)
	depth.fill(1 << 30)
	q = PackedInt32Array()
	for i in n:
		if road[i]:
			depth[i] = 0
			q.append(i)
	if not ground_m.is_empty():
		for t in p.get("ground", []):
			for i in _tile_cells(int(t[0]), int(t[1])):
				if road[i] == 0 and blocked[i] == 0 and ground[i] == 0:
					ground[i] = 1
					depth[i] = 0
					q.append(i)
	head = 0
	while head < q.size():
		var c := q[head]
		head += 1
		if depth[c] + 1 > reach:
			continue
		var cx := c % cw
		var cy := c / cw
		for d in 4:
			var nx := cx + (1 if d == 0 else (-1 if d == 1 else 0))
			var ny := cy + (1 if d == 2 else (-1 if d == 3 else 0))
			if nx < 0 or ny < 0 or nx >= cw or ny >= ch:
				continue
			var ni := ny * cw + nx
			if road[ni] or ground[ni] or blocked[ni] or water[ni]:
				continue
			if ink[ni] > ink_g or absf(feat[0][ni] - feat[0][c]) > step * 1.3:
				continue
			var dg := minf(d_ground[ni], d_road[ni] * t_g / t_loose)
			if dg < t_g and dg < d_solid[ni]:
				ground[ni] = 1
				depth[ni] = depth[c] + 1
				q.append(ni)

	for i in n:
		if road[i]:
			cells[i] = ROAD
		elif ground[i]:
			cells[i] = GROUND
	for r in p.get("keep", []):
		_fill_class(r, GROUND)
	for r in p.get("keep_road", []):
		_fill_class(r, ROAD)
	for r in p.get("block", []):
		_fill_class(r, OUT)

	# tiles
	var min_walk := int(p.get("min_walk", 9))
	var min_road := int(p.get("min_road", 8))
	tiles.resize(w * h)
	for ty in h:
		for tx in w:
			var nw := 0
			var nr := 0
			var nwat := 0
			for i in _tile_cells(tx, ty):
				var k := cells[i]
				if k == ROAD:
					nr += 1
					nw += 1
				elif k == GROUND:
					nw += 1
				elif k == WATER:
					nwat += 1
			var tc := SOLID
			if nw >= min_walk:
				tc = ROAD if nr >= min_road else GROUND
			elif nwat >= 8:
				tc = WATER
			tiles[ty * w + tx] = tc
	for c in p.get("keep_tiles", []) + [[start.x, start.y]]:
		var v := Vector2i(int(c[0]), int(c[1]))
		if in_bounds(v) and not walkable(v):
			tiles[v.y * w + v.x] = GROUND

	# boundary: what the start can't reach is out; solid tiles beside the walkable
	# area are the obstacles; everything further away is out too
	var seen := PackedByteArray()
	seen.resize(w * h)
	seen.fill(0)
	if in_bounds(start):
		var tq := PackedInt32Array([start.y * w + start.x])
		seen[start.y * w + start.x] = 1
		head = 0
		while head < tq.size():
			var c := tq[head]
			head += 1
			var x := c % w
			var y := c / w
			for d in 4:
				var nx := x + (1 if d == 0 else (-1 if d == 1 else 0))
				var ny := y + (1 if d == 2 else (-1 if d == 3 else 0))
				if nx < 0 or ny < 0 or nx >= w or ny >= h:
					continue
				var ni := ny * w + nx
				var k := tiles[ni]
				if seen[ni] == 0 and (k == GROUND or k == ROAD):
					seen[ni] = 1
					tq.append(ni)
	road_count = 0
	walk_count = 0
	for ty in h:
		for tx in w:
			var i := ty * w + tx
			var k := tiles[i]
			if k == GROUND or k == ROAD:
				if seen[i] == 0:
					tiles[i] = OUT
				else:
					walk_count += 1
					if k == ROAD:
						road_count += 1
	for ty in h:
		for tx in w:
			var i := ty * w + tx
			if tiles[i] != SOLID and tiles[i] != WATER:
				continue
			var near := false
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var nx := tx + dx
					var ny := ty + dy
					if nx >= 0 and ny >= 0 and nx < w and ny < h and seen[ny * w + nx]:
						near = true
			if not near:
				tiles[i] = OUT
	ms = Time.get_ticks_msec() - t0


## Box-sample the painting (one sample per 4 world px) and fill the cell features.
func _features(img: Image, scale: float) -> void:
	var src := img
	if src.is_compressed():
		src = src.duplicate()
		src.decompress()
	var iw := int(round(w * TILE / scale))
	var ih := int(round(h * TILE / scale))
	var region := src.get_region(Rect2i(0, 0, mini(iw, src.get_width()), mini(ih, src.get_height())))
	if region.get_format() != Image.FORMAT_RGB8:
		region.convert(Image.FORMAT_RGB8)
	var sw := cw * 4
	var sh := ch * 4
	region.resize(sw, sh, Image.INTERPOLATE_TRILINEAR)
	var data := region.get_data()
	var n := cw * ch
	feat = []
	for f in NF + 3:   # + mean r, g, b (for saturation)
		var a := PackedFloat32Array()
		a.resize(n)
		feat.append(a)
	_luma = PackedFloat32Array()
	_luma.resize(sw * sh)
	for sy in sh:
		var row := sy * sw
		for sx in sw:
			var o := (row + sx) * 3
			_luma[row + sx] = (0.299 * data[o] + 0.587 * data[o + 1] + 0.114 * data[o + 2]) / 255.0
	for cy in ch:
		for cx in cw:
			var sr := 0.0
			var sg := 0.0
			var sb := 0.0
			var sy_ := 0.0
			var syy := 0.0
			var lo1 := 9.0
			var lo2 := 9.0
			var hi1 := -9.0
			var hi2 := -9.0
			for j in 4:
				var row := (cy * 4 + j) * sw + cx * 4
				for i in 4:
					var o := (row + i) * 3
					sr += data[o]
					sg += data[o + 1]
					sb += data[o + 2]
					var y: float = _luma[row + i]
					sy_ += y
					syy += y * y
					if y < lo1:
						lo2 = lo1
						lo1 = y
					elif y < lo2:
						lo2 = y
					if y > hi1:
						hi2 = hi1
						hi1 = y
					elif y > hi2:
						hi2 = y
			var k := cy * cw + cx
			var r := sr / (16.0 * 255.0)
			var g := sg / (16.0 * 255.0)
			var b := sb / (16.0 * 255.0)
			var my := sy_ / 16.0
			feat[0][k] = my
			feat[1][k] = r - g
			feat[2][k] = b - 0.5 * (r + g)
			feat[3][k] = sqrt(maxf(0.0, syy / 16.0 - my * my))
			feat[4][k] = lo2
			feat[5][k] = hi2
			feat[6][k] = r
			feat[7][k] = g
			feat[8][k] = b


var _luma := PackedFloat32Array()


func _ink(level: float) -> void:
	var sw := cw * 4
	ink = PackedFloat32Array()
	ink.resize(cw * ch)
	for cy in ch:
		for cx in cw:
			var dark := 0
			for j in 4:
				var row := (cy * 4 + j) * sw + cx * 4
				for i in 4:
					if _luma[row + i] < level:
						dark += 1
			ink[cy * cw + cx] = dark / 16.0
	_luma = PackedFloat32Array()   # done with the samples


func _sat(i: int) -> float:
	var r: float = feat[6][i]
	var g: float = feat[7][i]
	var b: float = feat[8][i]
	var mx := maxf(r, maxf(g, b))
	var mn := minf(r, minf(g, b))
	return (mx - mn) / mx if mx > 0.0001 else 0.0


## One model per sample tile: [median x NF, spread x NF].
func _models(tile_list: Array) -> Array:
	var out := []
	for t in tile_list:
		var idx := _tile_cells(int(t[0]), int(t[1]))
		if idx.is_empty():
			continue
		var m := PackedFloat32Array()
		m.resize(NF * 2)
		for f in NF:
			var v: Array[float] = []
			for i in idx:
				v.append(feat[f][i])
			v.sort()
			var med := v[v.size() / 2]
			var dev: Array[float] = []
			for x in v:
				dev.append(absf(x - med))
			dev.sort()
			var sd := dev[dev.size() / 2] * 1.4826
			m[f] = med
			m[NF + f] = clampf(sd, FLOOR[f], FLOOR[f] * 3.0)
		out.append(m)
	return out


## Distance of every cell to the nearest of the models (1e9 if there are none).
func _dist_all(models: Array) -> PackedFloat32Array:
	var n := cw * ch
	var out := PackedFloat32Array()
	out.resize(n)
	out.fill(1e9)
	for m in models:
		var mm: PackedFloat32Array = m
		for i in n:
			var d := 0.0
			for f in NF:
				var z: float = (feat[f][i] - mm[f]) / mm[NF + f]
				d += WEIGHT[f] * z * z
			if d < out[i]:
				out[i] = d
	return out


func _tile_cells(tx: int, ty: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	if tx < 0 or ty < 0 or tx >= w or ty >= h:
		return out
	for j in 4:
		for i in 4:
			out.append((ty * 4 + j) * cw + tx * 4 + i)
	return out


func _fill_rect(arr: PackedByteArray, r: Array, v: int) -> void:
	for ty in range(int(r[1]), int(r[1]) + int(r[3])):
		for tx in range(int(r[0]), int(r[0]) + int(r[2])):
			for i in _tile_cells(tx, ty):
				arr[i] = v


func _fill_class(r: Array, k: int) -> void:
	for ty in range(int(r[1]), int(r[1]) + int(r[3])):
		for tx in range(int(r[0]), int(r[0]) + int(r[2])):
			for i in _tile_cells(tx, ty):
				if k == GROUND and cells[i] == ROAD:
					continue
				cells[i] = k
