class_name StageMap
extends RefCounted
## The walkable shape of a stage. Shared by the stage scene (to build it), the
## pacing report and the smoke test (to prove every beat is unavoidable).
##
## Level stages (every stage in Act One): "level" names a painting in
## res://assets/levels/, and TerrainSense reads its pixels to find the road, the
## ground you may cross, water, obstacles and the edge of the playable area. The
## stage JSON then places things by tile coordinates:
##   "start": [x, y]                  where Derrick begins
##   "exit": {"edge": "right"}        every walkable tile on that edge (or "cells": [[x, y], ...])
##   "lines": {"a": {"x": 12}}        trigger a: every walkable tile in column 12
##            {"y": 8} | {"x": 12, "y0": 3, "y1": 9} | {"rect": [x, y, w, h]} | {"cells": [...]}
##   "triggers": {"a": "script"}      what stepping on a line plays (once)
##   "cast": {"G": {"id": "gauntley", "at": [x, y]}}
##   "props": {"1": {"art": "prop/hatch", "at": [[x, y], ...], "solid": true}}
##   "gates": {"west": {"rect": [x, y, w, h], "on": false}}   closed by the "gate" command
## A full-height line can't be walked around, so beats on lines are unavoidable
## by construction; the smoke test proves it anyway.
##
## Legacy ASCII stages ("rows", no "level") still work for quick blockouts:
##   ground  .  stage ground   ,  road   =  wood floor   _  cobbles   :  crops   ;  stubble   '  mud
##   solid   ~  water   #  stone wall   |  timber wall   ^  roof   [  house wall   ]  lit window
##           {  burned roof   }  burned wall   (space)  nothing
##   props   &  tree   %  bush   $  dead tree   !  snowy pine   +  fence   0-9 stage props
##   special @  start   >  exit   a-z  trigger   A-Z  cast
## A level stage gets the same kind of rows generated from its detection (see
## synth_rows), so everything that reads letters keeps working.

const GROUND := {".": "", ",": "", "=": "floor", "_": "cobble", ":": "crops", ";": "stubble", "'": "mud"}
const SOLID_TILES := {"~": "water", "#": "wall_stone", "|": "wall_timber", "^": "roof", "[": "house_wall",
		"]": "house_window", "{": "roof_burned", "}": "house_burned"}
const SOLID_PROPS := {"&": "prop/tree", "%": "prop/bush", "$": "prop/dead_tree", "!": "prop/pine_snow", "+": "prop/fence"}
const DIRS := [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]
const LEVEL_ROOT := "res://assets/levels/"
## Click-walks and scripted walks prefer the road: a step off it costs this much more.
const OFFROAD_COST := 1.6

var stage: Dictionary
var rows: Array = []
var w := 0
var h := 0
var start := Vector2i.ZERO
var exits: Array[Vector2i] = []
var triggers: Dictionary = {}     # letter -> Array[Vector2i]
var cast_cells: Dictionary = {}   # letter -> Vector2i
var prop_cells: Dictionary = {}   # Vector2i -> digit
var level: Dictionary = {}        # stage["level"] on a painted level, else {}
var sense: TerrainSense = null
var prop_solid: Dictionary = {}   # Vector2i -> true
var gates: Dictionary = {}        # id -> {"cells": Array[Vector2i], "on": bool}
var _gate_cells: Dictionary = {}  # Vector2i -> count of closed gates covering it


func _init(p_stage: Dictionary) -> void:
	stage = p_stage
	if stage.has("level"):
		_build_level()
	else:
		_parse_rows(stage.get("rows", []))
	for gid in stage.get("gates", {}):
		var g: Dictionary = stage["gates"][gid]
		var cells: Array[Vector2i] = []
		var r: Array = g.get("rect", [0, 0, 0, 0])
		for y in range(int(r[1]), int(r[1]) + int(r[3])):
			for x in range(int(r[0]), int(r[0]) + int(r[2])):
				cells.append(Vector2i(x, y))
		gates[gid] = {"cells": cells, "on": false}
		set_gate(gid, g.get("on", false))


func is_level() -> bool:
	return not level.is_empty()


# ------------------------------------------------------------------ levels
## The painting a level stage is drawn from: "art" (what detection reads) or a
## variant shown instead ("show", e.g. the burned village at dawn).
static func level_image(st: Dictionary, which := "art") -> Image:
	var lv: Dictionary = st.get("level", {})
	var key: String = lv.get(which, lv.get("art", ""))
	var path := LEVEL_ROOT + key + ".png"
	if key == "" or not ResourceLoader.exists(path):
		push_warning("Missing level art: " + path)
		return null
	var res: Resource = load(path)
	if res is Image:
		return res
	if res is Texture2D:
		return (res as Texture2D).get_image()
	return null


static func has_level_art(key: String) -> bool:
	return key != "" and ResourceLoader.exists(LEVEL_ROOT + key + ".png")


func _build_level() -> void:
	level = stage["level"]
	start = _v(stage.get("start", [1, 1]))
	var img := level_image(stage, "art")
	if img == null:
		w = 1
		h = 1
		return
	sense = TerrainSense.analyze(img, float(level.get("scale", 1.0)), stage.get("sense", {}), start, level.get("art", ""))
	w = sense.w
	h = sense.h
	var props: Dictionary = stage.get("props", {})
	for digit in props:
		var d: Dictionary = props[digit]
		for at in _at_list(d):
			prop_cells[at] = digit
			if d.get("solid", true):
				prop_solid[at] = true
	var ex: Dictionary = stage.get("exit", {})
	exits = _exit_cells(ex)
	var lines: Dictionary = stage.get("lines", {})
	for letter in lines:
		triggers[letter] = _line_cells(lines[letter])
	var cast: Dictionary = stage.get("cast", {})
	for letter in cast:
		if cast[letter].has("at"):
			cast_cells[letter] = _v(cast[letter]["at"])
	rows = synth_rows()


static func _v(a: Variant) -> Vector2i:
	return Vector2i(int(a[0]), int(a[1]))


## A prop's "at" may be one cell [x, y] or a list of them.
static func _at_list(d: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var at: Variant = d.get("at", [])
	if at is Array and not at.is_empty():
		if at[0] is Array:
			for a in at:
				out.append(_v(a))
		else:
			out.append(_v(at))
	return out


## Walkable on the painting, ignoring cast and gates (what lines and exits cover).
func open_ground(c: Vector2i) -> bool:
	return in_bounds(c) and sense != null and sense.walkable(c) and not prop_solid.has(c)


func _exit_cells(ex: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if ex.has("cells"):
		for a in ex["cells"]:
			out.append(_v(a))
		return out
	match ex.get("edge", ""):
		"right":
			for y in h:
				if open_ground(Vector2i(w - 1, y)):
					out.append(Vector2i(w - 1, y))
		"left":
			for y in h:
				if open_ground(Vector2i(0, y)):
					out.append(Vector2i(0, y))
		"top":
			for x in w:
				if open_ground(Vector2i(x, 0)):
					out.append(Vector2i(x, 0))
		"bottom":
			for x in w:
				if open_ground(Vector2i(x, h - 1)):
					out.append(Vector2i(x, h - 1))
	return out


func _line_cells(spec: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var cand: Array[Vector2i] = []
	if spec.has("cells"):
		for a in spec["cells"]:
			out.append(_v(a))
		return out
	if spec.has("x"):
		for y in range(int(spec.get("y0", 0)), int(spec.get("y1", h - 1)) + 1):
			cand.append(Vector2i(int(spec["x"]), y))
	elif spec.has("y"):
		for x in range(int(spec.get("x0", 0)), int(spec.get("x1", w - 1)) + 1):
			cand.append(Vector2i(x, int(spec["y"])))
	elif spec.has("rect"):
		var r: Array = spec["rect"]
		for y in range(int(r[1]), int(r[1]) + int(r[3])):
			for x in range(int(r[0]), int(r[0]) + int(r[2])):
				cand.append(Vector2i(x, y))
	for c in cand:
		if open_ground(c):
			out.append(c)
	return out


## Rows of letters generated from the detection, for code that reads letters:
## '@' start, '>' exit, a-z triggers, ',' road, '.' ground, '~' water, '#' obstacle, ' ' out.
func synth_rows() -> Array:
	var grid: Array = []
	var art := sense.ascii() if sense else PackedStringArray()
	for y in h:
		var r := art[y] if y < art.size() else " ".repeat(w)
		var chars: Array = []
		for x in w:
			chars.append(r[x])
		grid.append(chars)
	for c in prop_cells:
		if in_bounds(c):
			grid[c.y][c.x] = String(prop_cells[c])
	for letter in triggers:
		for c in triggers[letter]:
			if in_bounds(c):
				grid[c.y][c.x] = letter
	for c in exits:
		if in_bounds(c):
			grid[c.y][c.x] = ">"
	if in_bounds(start):
		grid[start.y][start.x] = "@"
	var out: Array = []
	for chars in grid:
		out.append("".join(chars))
	return out


# ------------------------------------------------------------------ legacy rows
func _parse_rows(p_rows: Array) -> void:
	rows = p_rows
	h = rows.size()
	w = rows[0].length() if h > 0 else 0
	for y in h:
		var r: String = rows[y]
		for x in r.length():
			var ch := r[x]
			var c := Vector2i(x, y)
			if ch == "@":
				start = c
			elif ch == ">":
				exits.append(c)
			elif _is_lower(ch):
				if not triggers.has(ch):
					triggers[ch] = [] as Array[Vector2i]
				triggers[ch].append(c)
			elif _is_upper(ch):
				cast_cells[ch] = c
			elif ch >= "0" and ch <= "9":
				prop_cells[c] = ch
				if stage.get("props", {}).get(ch, {}).get("solid", true):
					prop_solid[c] = true


static func _is_lower(ch: String) -> bool:
	return ch >= "a" and ch <= "z"


static func _is_upper(ch: String) -> bool:
	return ch >= "A" and ch <= "Z"


func ch(c: Vector2i) -> String:
	if not in_bounds(c):
		return " "
	return rows[c.y][c.x]


func in_bounds(c: Vector2i) -> bool:
	return c.y >= 0 and c.y < h and c.x >= 0 and c.x < w


# ------------------------------------------------------------------ gates
## A gate is a strip of tiles the story can shut (behind a time skip, say).
func set_gate(id: String, on: bool) -> void:
	if not gates.has(id) or gates[id]["on"] == on:
		return
	gates[id]["on"] = on
	for c in gates[id]["cells"]:
		var n: int = _gate_cells.get(c, 0) + (1 if on else -1)
		if n <= 0:
			_gate_cells.erase(c)
		else:
			_gate_cells[c] = n


# ------------------------------------------------------------------ queries
## Solid because of the map itself (obstacles, water, out of bounds, solid props,
## closed gates). Cast are separate.
func terrain_solid(c: Vector2i) -> bool:
	if not in_bounds(c) or _gate_cells.has(c):
		return true
	if is_level():
		return not open_ground(c)
	return ascii_solid(c)


## What the letters alone say (legacy stages).
func ascii_solid(c: Vector2i) -> bool:
	var k := ch(c)
	if k == " " or SOLID_TILES.has(k) or SOLID_PROPS.has(k):
		return true
	if prop_cells.has(c):
		return stage.get("props", {}).get(k, {}).get("solid", true)
	return false


func is_road(c: Vector2i) -> bool:
	if is_level():
		return sense.is_road(c)
	return ch(c) == ","


## What the detection made of a tile: TerrainSense.ROAD / GROUND / WATER / SOLID / OUT.
func terrain_class(c: Vector2i) -> int:
	if is_level():
		return sense.tile(c)
	if not in_bounds(c) or ch(c) == " ":
		return TerrainSense.OUT
	if ascii_solid(c):
		return TerrainSense.WATER if ch(c) == "~" else TerrainSense.SOLID
	return TerrainSense.ROAD if ch(c) == "," else TerrainSense.GROUND


## Ground tile art under a cell (legacy stages). Letters, digits, @ and > borrow from a neighbour.
func ground_key(c: Vector2i) -> String:
	var k := ch(c)
	if GROUND.has(k):
		return _ground_art(k)
	if SOLID_TILES.has(k):
		return "tile/" + SOLID_TILES[k]
	if k == " ":
		return ""
	if SOLID_PROPS.has(k):
		return _ground_art(".")
	if prop_cells.has(c) and stage.get("props", {}).get(k, {}).has("ground"):
		return _ground_art(stage["props"][k]["ground"])
	for dirs in [[Vector2i.LEFT, Vector2i.RIGHT], [Vector2i.UP, Vector2i.DOWN]]:
		for d in 4:
			for dir in dirs:
				var n: Vector2i = c + dir * (d + 1)
				if GROUND.has(ch(n)):
					return _ground_art(ch(n))
	return "tile/" + stage.get("ground", "grass")


func _ground_art(k: String) -> String:
	if k == ".":
		return "tile/" + stage.get("ground", "grass")
	if k == ",":
		return "tile/" + stage.get("road", "road")
	return "tile/" + GROUND[k]


## Cells occupied by cast that start visible.
func cast_blockers() -> Dictionary:
	var out := {}
	var defs: Dictionary = stage.get("cast", {})
	for letter in cast_cells:
		var d: Dictionary = defs.get(letter, {})
		# "steps_aside": the script moves them off the path once their beat has played.
		if not d.get("hidden", false) and d.get("solid", true) and not d.get("steps_aside", false) \
				and not d.get("down", false):
			out[cast_cells[letter]] = true
	return out


func walkable(c: Vector2i, blocked: Dictionary) -> bool:
	return in_bounds(c) and not terrain_solid(c) and not blocked.has(c)


## Breadth-first shortest path (inclusive of both ends), or [] if unreachable.
func path(from: Vector2i, to: Vector2i, blocked: Dictionary = {}) -> Array[Vector2i]:
	var prev := {from: from}
	var queue: Array[Vector2i] = [from]
	var head := 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		if c == to:
			return _unwind(prev, from, c)
		for d in DIRS:
			var n: Vector2i = c + d
			if not prev.has(n) and (walkable(n, blocked) or n == to):
				prev[n] = c
				queue.append(n)
	var none: Array[Vector2i] = []
	return none


## Cheapest path that keeps to the road where it can (Dijkstra: road steps cost 1,
## other ground OFFROAD_COST). Used for click-walks and scripted walks.
func route(from: Vector2i, to: Vector2i, blocked: Dictionary = {}) -> Array[Vector2i]:
	var cost := {from: 0.0}
	var prev := {from: from}
	var open: Array = [[0.0, from]]
	while not open.is_empty():
		var best := 0
		for i in open.size():
			if open[i][0] < open[best][0]:
				best = i
		var cur: Array = open[best]
		open.remove_at(best)
		var c: Vector2i = cur[1]
		if c == to:
			return _unwind(prev, from, c)
		if float(cur[0]) > float(cost.get(c, INF)):
			continue
		for d in DIRS:
			var n: Vector2i = c + d
			if not (walkable(n, blocked) or n == to):
				continue
			var nc: float = float(cost[c]) + (1.0 if is_road(n) else OFFROAD_COST)
			if nc < float(cost.get(n, INF)):
				cost[n] = nc
				prev[n] = c
				open.append([nc, n])
	var none: Array[Vector2i] = []
	return none


func _unwind(prev: Dictionary, from: Vector2i, c: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var p := c
	while p != from:
		out.push_front(p)
		p = prev[p]
	out.push_front(from)
	return out


func reachable(from: Vector2i, blocked: Dictionary = {}) -> Dictionary:
	var seen := {from: true}
	var queue: Array[Vector2i] = [from]
	var head := 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		for d in DIRS:
			var n: Vector2i = c + d
			if not seen.has(n) and walkable(n, blocked):
				seen[n] = true
				queue.append(n)
	return seen


func walkable_count(blocked: Dictionary = {}) -> int:
	var n := 0
	for y in h:
		for x in w:
			if walkable(Vector2i(x, y), blocked):
				n += 1
	return n
