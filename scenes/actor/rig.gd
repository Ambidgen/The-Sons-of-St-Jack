class_name Rig
extends Node2D
## An articulated body. Each part of a character (legs, skirt, cloak, torso, arms,
## head; a hound's four legs, tail and head; a horse and its rider) is a textured
## mesh (Polygon2D) cut from a rig sheet -- assets/placeholder/rig/<name>.svg, laid
## out by tools/make_placeholders.py and described in rigs.json -- and hung on a
## bone at its joint. The rig animates itself: idle breathing, a walk cycle with
## swinging limbs, bending knees and swaying hems, plus one-shot actions (attack,
## hurt, cast, nod, yield). Art without a rig (props) falls back to a flat sprite
## with the same API. Position = feet. Stage actors keep it as their "Sprite" child.
##
##   var r := Rig.make("char/derrick_man_field")
##   r.flip_h = true            # face left
##   r.step(0.2)                # walking one tile over 0.2 s (call per tile)
##   r.play("attack")           # one-shot; await r.play(...) waits for it

signal action_finished(name: String)

## When the blow lands in each one-shot, in seconds (used to time the lunge).
const HIT_TIME := {"attack": 0.28}
const ACTION_LEN := {"attack": 0.62, "hurt": 0.45, "cast": 0.7, "nod": 0.55, "shake": 0.9, "point": 1.3,
		"peck": 0.5, "yield": 0.35, "cower": 0.35, "raise": 0.4, "guard": 0.3}
const HOLD := ["yield", "cower", "raise", "guard"]   # these stay until reset_pose() (or new art)

static var _db: Dictionary = {}                 # sheet name -> description (rigs.json)
static var _rects: Dictionary = {}              # sheet name -> Array of Rect2 (used area per cell)

var art_key := ""
var kind := ""              # biped | hound | horse | bird | "" (flat sprite)
var flip_h := false: set = set_flip_h
var tint := Color.WHITE: set = set_tint
var height := 64.0          # frame height in px: the top of the drawing is at y = -height
var width := 64.0
var sit := false
var animate := true

var _desc: Dictionary = {}
var _s := 1.0               # px per art unit
var _flip: Node2D
var _bones: Dictionary = {}       # name -> Node2D
var _rest: Dictionary = {}        # name -> Vector2 rest position
var _meshes: Dictionary = {}      # part name -> Polygon2D
var _mesh_rest: Dictionary = {}   # part name -> PackedVector2Array
var _mesh_box: Dictionary = {}    # part name -> Rect2 (bone-local)
var _flat: Sprite2D
var _t := 0.0
var _seed := 0.0
var _phase := 0.0
var _walk := 0.0
var _walk_left := 0.0
var _stride := 2.5                # walk cycles per second
var _action := ""
var _action_t := 0.0
var _action_len := 0.0
var _held := ""                   # a held pose (yield, cower, raise)
var _held_k := 0.0


static func make(key: String) -> Rig:
	var r := Rig.new()
	r.name = "Sprite"
	r.set_art(key)
	return r


static func db() -> Dictionary:
	if _db.is_empty():
		var path := Data.ART_ROOT + "rigs.json"
		if FileAccess.file_exists(path):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if parsed is Dictionary:
				_db = parsed.get("rigs", {})
	return _db


## The rig description for an art key ("char/jack_field" -> rigs["jack_field"]), or {}.
static func find(key: String) -> Dictionary:
	if key == "":
		return {}
	return db().get(key.get_file(), {})


static func has_rig(key: String) -> bool:
	return not find(key).is_empty()


# ------------------------------------------------------------------ building
func set_art(key: String) -> void:
	art_key = key
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_bones.clear()
	_rest.clear()
	_meshes.clear()
	_mesh_rest.clear()
	_mesh_box.clear()
	_flat = null
	_held = ""
	_held_k = 0.0
	_action = ""
	_seed = float(hash(key) % 1000) / 100.0
	_flip = Node2D.new()
	_flip.name = "Flip"
	add_child(_flip)
	_desc = find(key)
	var sheet: Texture2D = Data.tex(_desc.get("sheet", "")) if not _desc.is_empty() else null
	if sheet == null:
		_build_flat(key)
	else:
		_build_rig(sheet)
	set_flip_h(flip_h)
	set_tint(tint)
	_apply_pose(0.0)


func _build_flat(key: String) -> void:
	kind = ""
	_flat = Sprite2D.new()
	_flat.texture = Data.tex(key)
	height = _flat.texture.get_height() if _flat.texture else 64.0
	width = _flat.texture.get_width() if _flat.texture else 64.0
	_flat.offset = Vector2(0, -height / 2.0)
	_flip.add_child(_flat)


func _build_rig(sheet: Texture2D) -> void:
	kind = _desc.get("kind", "biped")
	sit = _desc.get("sit", false)
	_s = float(_desc["s"])
	var frame: Array = _desc["frame"]
	width = float(frame[0]) * _s
	height = float(frame[1]) * _s
	var rects := _used_rects(sheet)
	var cells: Dictionary = _desc.get("cells", {})
	var mesh_div: Dictionary = _desc.get("mesh", {})
	for b in _desc["bones"]:
		var bname: String = b[0]
		var parent_name: String = b[1]
		var at := _px(b[2])
		var parent: Node2D = _bones.get(parent_name, _flip)
		var parent_at: Vector2 = _bone_at(parent_name)
		var bone := Node2D.new()
		bone.name = bname
		bone.position = at - parent_at
		bone.set_meta("at", at)
		parent.add_child(bone)
		_bones[bname] = bone
		_rest[bname] = bone.position
		if cells.has(bname):
			var i := int(cells[bname])
			var r: Rect2 = rects[i] if i < rects.size() else Rect2()
			if r.size.x < 1.0 or r.size.y < 1.0:
				continue
			var div: Array = mesh_div.get(bname, [1, 1])
			_add_mesh(bone, bname, sheet, i, r, int(div[0]), int(div[1]), at)


## Art units -> rig-local px (feet at the origin, frame centred on x).
func _px(u: Array) -> Vector2:
	var frame: Array = _desc["frame"]
	return (Vector2(float(u[0]), float(u[1])) - Vector2(float(frame[0]) / 2.0, float(frame[1]))) * _s


func _bone_at(bname: String) -> Vector2:
	if _bones.has(bname):
		return _bones[bname].get_meta("at")
	return Vector2.ZERO


## Sheet pixel -> rig-local px for cell i.
func _sheet_to_local(p: Vector2, i: int) -> Vector2:
	var cell: Array = _desc["cell"]
	var pad := float(_desc["pad"])
	var u := (p - Vector2(i * float(cell[0]), 0.0)) / _s - Vector2(pad, pad)
	return _px([u.x, u.y])


func _add_mesh(bone: Node2D, part: String, sheet: Texture2D, i: int, r: Rect2, cols: int, rows: int, at: Vector2) -> void:
	var verts := PackedVector2Array()
	var uvs := PackedVector2Array()
	for y in rows + 1:
		for x in cols + 1:
			var p := r.position + Vector2(r.size.x * x / cols, r.size.y * y / rows)
			uvs.append(p)
			verts.append(_sheet_to_local(p, i) - at)
	var polys: Array = []
	for y in rows:
		for x in cols:
			var a := y * (cols + 1) + x
			polys.append(PackedInt32Array([a, a + 1, a + cols + 2, a + cols + 1]))
	var m := Polygon2D.new()
	m.name = "Mesh"
	m.texture = sheet
	m.polygon = verts
	m.uv = uvs
	m.polygons = polys
	bone.add_child(m)
	bone.move_child(m, 0)        # the part draws before any bones hung from it
	_meshes[part] = m
	_mesh_rest[part] = verts
	var box := Rect2(verts[0], Vector2.ZERO)
	for v in verts:
		box = box.expand(v)
	_mesh_box[part] = box


## The drawn area of every cell in a sheet (cached per sheet). Trimming keeps the
## meshes tight so hems and knees bend where the cloth is, not in empty space.
func _used_rects(sheet: Texture2D) -> Array:
	var name_key: String = _desc["sheet"]
	if _rects.has(name_key):
		return _rects[name_key]
	var cell: Array = _desc["cell"]
	var cw := int(cell[0])
	var ch := int(cell[1])
	var n := int(_desc.get("cells", {}).size())
	var out: Array = []
	var img: Image = sheet.get_image() if DisplayServer.get_name() != "headless" else null
	for i in n:
		var full := Rect2(i * cw, 0, cw, ch)
		if img == null or img.is_empty():
			out.append(full)
			continue
		if img.is_compressed():
			img.decompress()
		var cell_rect := Rect2i(i * cw, 0, mini(cw, img.get_width() - i * cw), mini(ch, img.get_height()))
		var used := img.get_region(cell_rect).get_used_rect()
		if used.size == Vector2i.ZERO:
			out.append(Rect2())
		else:
			var grown := Rect2(used).grow(1.0).intersection(Rect2(0, 0, cell_rect.size.x, cell_rect.size.y))
			out.append(Rect2(grown.position + Vector2(i * cw, 0), grown.size))
	_rects[name_key] = out
	return out


# ------------------------------------------------------------------ API
func set_flip_h(v: bool) -> void:
	flip_h = v
	if _flip:
		_flip.scale.x = -1.0 if v else 1.0


func set_tint(c: Color) -> void:
	tint = c
	if _flip:
		_flip.modulate = c


func has_bones() -> bool:
	return kind != ""


## Walking for `duration` seconds (one tile). Call again each tile; the cycle keeps
## running between tiles and eases back to standing when the calls stop.
func step(duration: float) -> void:
	_walk_left = duration + 0.07
	_stride = 0.5 / maxf(0.08, duration)


func stop() -> void:
	_walk_left = 0.0


func is_walking() -> bool:
	return _walk > 0.01


## One-shot (or held) action. Returns when it's over (held ones: when in place).
func play(action: String) -> void:
	# a hidden body doesn't animate (see _process), so waiting on it would hang the script
	if kind == "" or not animate or not is_inside_tree() or not is_visible_in_tree():
		if HOLD.has(action):
			_held = action
		return
	if HOLD.has(action):
		_held = action
		await get_tree().create_timer(ACTION_LEN.get(action, 0.35)).timeout
		return
	_action = action
	_action_t = 0.0
	_action_len = ACTION_LEN.get(action, 0.5)
	await action_finished


func reset_pose() -> void:
	_held = ""


func _process(delta: float) -> void:
	if kind == "":
		_hop_flat(delta)
		return
	if not animate or not is_visible_in_tree():
		return
	_t += delta
	var want := 1.0 if _walk_left > 0.0 else 0.0
	_walk_left = maxf(0.0, _walk_left - delta)
	_walk = move_toward(_walk, want, delta * (8.0 if want > 0.0 else 5.0))
	if _walk > 0.0:
		_phase = fmod(_phase + delta * TAU * _stride, TAU)
	else:
		_phase = 0.0
	_held_k = move_toward(_held_k, 1.0 if _held != "" else 0.0, delta * 4.0)
	if _action != "":
		_action_t += delta
		if _action_t >= _action_len:
			var done := _action
			_action = ""
			action_finished.emit(done)
	_apply_pose(delta)


## A flat sprite (a prop that walks, say) just hops along.
func _hop_flat(delta: float) -> void:
	if _flat == null:
		return
	if _walk_left > 0.0:
		_walk_left = maxf(0.0, _walk_left - delta)
		_phase = fmod(_phase + delta * TAU * _stride, TAU)
		_flat.position.y = -absf(sin(_phase)) * 3.0
	elif _flat.position.y != 0.0:
		_flat.position.y = move_toward(_flat.position.y, 0.0, delta * 30.0)
		_phase = 0.0


# ------------------------------------------------------------------ poses
## Envelope of the current one-shot at normalised time e: rises, holds, falls.
func _env(rise: float, fall_start: float) -> float:
	if _action == "":
		return 0.0
	var e := _action_t / maxf(0.01, _action_len)
	if e < rise:
		return smoothstep(0.0, rise, e)
	if e < fall_start:
		return 1.0
	return 1.0 - smoothstep(fall_start, 1.0, e)


func _apply_pose(_delta: float) -> void:
	if kind == "":
		return
	var rot := {}
	var off := {}
	var scl := {}
	var bend := {}
	var sway := 0.0
	match kind:
		"biped":
			sway = _pose_biped(rot, off, scl, bend)
		"hound":
			_pose_hound(rot, off, scl)
		"horse":
			_pose_horse(rot, off, scl)
		"bird":
			_pose_bird(rot, off)
	for bname in _bones:
		var b: Node2D = _bones[bname]
		b.rotation = rot.get(bname, 0.0)
		b.position = _rest[bname] + off.get(bname, Vector2.ZERO)
		b.scale = scl.get(bname, Vector2.ONE)
	for part in ["leg_l", "leg_r"]:
		if _meshes.has(part) and not sit:
			_bend_leg(part, bend.get(part, 0.0))
	for part in ["skirt", "cloak"]:
		if _meshes.has(part):
			_sway_cloth(part, sway)


func _pose_biped(rot: Dictionary, off: Dictionary, scl: Dictionary, bend: Dictionary) -> float:
	var w := _walk if not sit else 0.0
	var idle := 1.0 - w
	var sw := sin(_phase)
	var cw := cos(_phase)
	var breath := sin(_t * 2.1 + _seed)
	var s := _s
	# walking: legs swing from the hips, the lifted leg bends at the knee
	var leg_a := 0.36 * w
	rot["leg_l"] = -leg_a * sw
	rot["leg_r"] = leg_a * sw
	var lift_l := maxf(0.0, cw) * w
	var lift_r := maxf(0.0, -cw) * w
	off["leg_l"] = Vector2(0, -lift_l * 1.6 * s)
	off["leg_r"] = Vector2(0, -lift_r * 1.6 * s)
	bend["leg_l"] = lift_l * 0.75
	bend["leg_r"] = lift_r * 0.75
	off["body"] = Vector2(0, -absf(cw) * 1.4 * s * w)
	rot["upper"] = 0.07 * w
	scl["upper"] = Vector2(1.0, 1.0 + 0.014 * breath * idle)
	rot["arm_l"] = 0.42 * w * sw + 0.035 * breath * idle
	rot["arm_r"] = -0.42 * w * sw - 0.035 * breath * idle
	rot["head"] = -0.04 * w + 0.035 * sin(_t * 0.8 + _seed) * idle + 0.03 * sin(2.0 * _phase) * w
	off["head"] = Vector2(0, -0.35 * s * breath * idle)
	scl["shadow"] = Vector2(1.0 - 0.06 * absf(cw) * w, 1.0)
	var sway := (-2.6 * w + 0.9 * sin(_t * 1.6 + _seed) * idle + 1.3 * sin(2.0 * _phase) * w) * s
	# one-shots
	match _action:
		"attack":
			# raise the arm high, chop forward and down, recover. The weapon turns at
			# the wrist: back over the shoulder in the wind-up, out in front at the blow.
			var e := _action_t / _action_len
			var arm := 0.0
			var blade := 0.0
			var lean := 0.0
			if e < 0.36:
				var k := smoothstep(0.0, 0.36, e)
				arm = lerpf(0.0, -2.5, k)
				blade = lerpf(0.0, -0.7, k)
				lean = -0.1 * k
			elif e < 0.5:
				var k := smoothstep(0.36, 0.5, e)
				arm = lerpf(-2.5, -0.75, k)
				blade = lerpf(-0.7, 1.8, k)
				lean = lerpf(-0.1, 0.24, k)
			else:
				var k := smoothstep(0.5, 1.0, e)
				arm = lerpf(-0.75, 0.0, k)
				blade = lerpf(1.8, 0.0, k)
				lean = lerpf(0.24, 0.0, k)
			var push := clampf(lean * 4.0, 0.0, 1.0)
			rot["arm_r"] = arm
			rot["held_r"] = blade - arm
			rot["arm_l"] = rot["arm_l"] + 0.35 * push
			rot["upper"] = rot["upper"] + lean
			rot["leg_l"] = rot["leg_l"] - 0.25 * push
			rot["leg_r"] = rot["leg_r"] + 0.18 * push
			sway -= 2.0 * s * push
		"hurt":
			var k := _env(0.18, 0.4)
			rot["upper"] = rot["upper"] - 0.28 * k
			rot["head"] = rot["head"] - 0.3 * k
			rot["arm_l"] = rot["arm_l"] + 0.6 * k
			rot["arm_r"] = rot["arm_r"] + 0.6 * k
			bend["leg_l"] = bend["leg_l"] + 0.3 * k
			sway += 2.5 * s * k
		"cast":
			var k := _env(0.3, 0.65)
			rot["arm_l"] = rot["arm_l"] - 1.5 * k
			rot["arm_r"] = rot["arm_r"] - 1.7 * k
			rot["head"] = rot["head"] + 0.12 * k
			rot["upper"] = rot["upper"] + 0.06 * k
		"nod":
			var k := sin(PI * clampf(_action_t / _action_len, 0.0, 1.0))
			rot["head"] = rot["head"] + 0.28 * k
		"shake":   # no
			var e := clampf(_action_t / _action_len, 0.0, 1.0)
			rot["head"] = rot["head"] + 0.2 * sin(e * TAU * 3.0) * (1.0 - e)
		"point":   # at him
			var k := _env(0.18, 0.75)
			rot["arm_r"] = lerpf(rot["arm_r"], -1.5, k)
			rot["upper"] = rot["upper"] + 0.08 * k
			rot["head"] = rot["head"] - 0.06 * k
	if _held_k > 0.0:
		var k := _held_k
		match _held:
			"yield":      # sinks, knees giving, hands up and open
				off["body"] = off.get("body", Vector2.ZERO) + Vector2(0, 5.0 * s * k)
				rot["leg_l"] = rot["leg_l"] + 0.32 * k
				rot["leg_r"] = rot["leg_r"] - 0.32 * k
				bend["leg_l"] = bend["leg_l"] - 0.55 * k
				bend["leg_r"] = bend["leg_r"] + 0.55 * k
				rot["upper"] = rot["upper"] + 0.12 * k
				rot["arm_l"] = lerpf(rot["arm_l"], 2.4, k)
				rot["arm_r"] = lerpf(rot["arm_r"], -2.4, k)
				rot["head"] = rot["head"] + 0.22 * k
			"cower":      # hunched, arms up over the head
				off["body"] = off.get("body", Vector2.ZERO) + Vector2(0, 3.0 * s * k)
				bend["leg_l"] = bend["leg_l"] + 0.5 * k
				bend["leg_r"] = bend["leg_r"] + 0.5 * k
				rot["upper"] = rot["upper"] + 0.3 * k
				rot["arm_l"] = lerpf(rot["arm_l"], -2.2, k)
				rot["arm_r"] = lerpf(rot["arm_r"], -2.5, k)
				rot["head"] = rot["head"] + 0.35 * k
			"guard":      # backed up, knife out, shaking at no one in particular
				var shiver := sin(_t * 31.0) * 0.045 + sin(_t * 17.0) * 0.03
				off["body"] = off.get("body", Vector2.ZERO) + Vector2(0, 1.5 * s * k)
				bend["leg_l"] = bend["leg_l"] + 0.3 * k
				bend["leg_r"] = bend["leg_r"] + 0.3 * k
				rot["upper"] = rot["upper"] - 0.12 * k
				rot["arm_r"] = lerpf(rot["arm_r"], -1.25 + shiver, k)
				rot["held_r"] = lerpf(0.0, 1.45 - (-1.25 + shiver), k)
				rot["arm_l"] = lerpf(rot["arm_l"], -0.55 + shiver, k)
				rot["head"] = rot["head"] - 0.1 * k + shiver * 0.5 * k
			"raise":      # arms out: a showman's welcome
				rot["arm_l"] = lerpf(rot["arm_l"], 1.3, k)
				rot["arm_r"] = lerpf(rot["arm_r"], -1.3, k)
				rot["head"] = rot["head"] - 0.12 * k
	for side in ["l", "r"]:
		if not rot.has("held_" + side):
			rot["held_" + side] = -0.45 * float(rot.get("arm_" + side, 0.0))
	return sway


func _pose_hound(rot: Dictionary, off: Dictionary, scl: Dictionary) -> void:
	var w := _walk
	var idle := 1.0 - w
	var breath := sin(_t * 3.2 + _seed)
	var a := 0.5 * w
	var p := _phase
	# trot: diagonal pairs move together
	rot["leg_hn"] = -a * sin(p)
	rot["leg_ff"] = -a * sin(p)
	rot["leg_hf"] = a * sin(p)
	rot["leg_fn"] = a * sin(p)
	off["body"] = Vector2(0, -absf(cos(p)) * 1.5 * _s * w)
	rot["body"] = 0.03 * sin(p) * w
	scl["torso"] = Vector2(1.0, 1.0 + 0.03 * breath * idle)
	rot["head"] = 0.08 * sin(2.0 * p) * w + 0.05 * sin(_t * 0.7 + _seed) * idle
	rot["tail"] = 0.25 * sin(_t * (9.0 if w > 0.1 else 2.5) + _seed)
	scl["shadow"] = Vector2(1.0 - 0.05 * absf(cos(p)) * w, 1.0)
	match _action:
		"attack":
			var e := _action_t / _action_len
			var k := smoothstep(0.0, 0.4, e) * (1.0 - smoothstep(0.55, 1.0, e))
			rot["body"] = rot["body"] + 0.12 * k
			rot["head"] = rot["head"] + 0.45 * k
			rot["leg_ff"] = rot["leg_ff"] - 0.7 * k
			rot["leg_fn"] = rot["leg_fn"] - 0.8 * k
			rot["leg_hn"] = rot["leg_hn"] + 0.35 * k
			off["body"] = off["body"] + Vector2(3.0 * _s * k, -2.0 * _s * k)
		"hurt":
			var k := _env(0.2, 0.4)
			rot["body"] = rot["body"] - 0.1 * k
			rot["head"] = rot["head"] - 0.4 * k
			rot["tail"] = rot["tail"] + 0.6 * k
		"cast":   # a howl
			var k := _env(0.3, 0.7)
			rot["head"] = rot["head"] - 0.7 * k
			rot["body"] = rot["body"] - 0.08 * k


func _pose_horse(rot: Dictionary, off: Dictionary, scl: Dictionary) -> void:
	var w := _walk
	var idle := 1.0 - w
	var p := _phase
	var a := 0.32 * w
	var breath := sin(_t * 1.6 + _seed)
	# four-beat walk
	rot["leg_hf"] = -a * sin(p)
	rot["leg_ff"] = -a * sin(p + PI * 0.5)
	rot["leg_hn"] = -a * sin(p + PI)
	rot["leg_fn"] = -a * sin(p + PI * 1.5)
	off["body"] = Vector2(0, -absf(sin(2.0 * p)) * 1.0 * _s * w)
	scl["torso"] = Vector2(1.0, 1.0 + 0.02 * breath * idle)
	rot["head"] = 0.07 * sin(2.0 * p) * w + 0.06 * sin(_t * 0.5 + _seed) * idle
	rot["tail"] = 0.12 * sin(_t * 1.3 + _seed) + 0.1 * sin(2.0 * p) * w
	off["rider"] = Vector2(0, absf(sin(2.0 * p + 0.4)) * 1.2 * _s * w)
	rot["rider_torso"] = 0.0
	rot["rider_head"] = 0.04 * sin(_t * 0.9 + _seed) * idle - 0.03 * sin(2.0 * p) * w
	rot["rider_arm_l"] = 0.06 * sin(2.0 * p) * w + 0.03 * breath * idle
	rot["rider_arm_r"] = -0.06 * sin(2.0 * p) * w - 0.03 * breath * idle
	rot["rider_held_l"] = -0.45 * float(rot["rider_arm_l"])
	rot["rider_held_r"] = -0.45 * float(rot["rider_arm_r"])
	scl["shadow"] = Vector2(1.0 - 0.03 * absf(sin(2.0 * p)) * w, 1.0)
	match _action:
		"attack", "cast":   # rears
			var k := _env(0.3, 0.6)
			rot["body"] = -0.22 * k
			rot["leg_ff"] = rot["leg_ff"] - 0.9 * k
			rot["leg_fn"] = rot["leg_fn"] - 1.1 * k
			rot["head"] = rot["head"] - 0.25 * k
			rot["rider"] = 0.12 * k
		"hurt":
			var k := _env(0.2, 0.4)
			rot["head"] = rot["head"] - 0.3 * k


func _pose_bird(rot: Dictionary, off: Dictionary) -> void:
	var w := _walk
	off["body"] = Vector2(0, -absf(sin(_phase)) * 3.0 * _s * w)
	# now and then, a peck at whatever is on the ground
	var cycle := fmod(_t + _seed * 3.0, 4.5)
	var peck := 0.0
	if cycle > 3.7:
		peck = sin(PI * (cycle - 3.7) / 0.8)
	rot["body"] = 0.55 * peck
	if _action == "hurt" or _action == "cast":
		off["body"] = off["body"] + Vector2(0, -6.0 * _s * _env(0.2, 0.5))


## Rotate the vertices below the knee (the middle row) about the knee.
func _bend_leg(part: String, angle: float) -> void:
	var m: Polygon2D = _meshes[part]
	var rest: PackedVector2Array = _mesh_rest[part]
	if rest.size() < 6:
		return
	if absf(angle) < 0.001:
		if m.polygon != rest:
			m.polygon = rest
		return
	var knee := (rest[2] + rest[3]) / 2.0
	var out := rest.duplicate()
	for i in range(4, rest.size()):
		out[i] = knee + (rest[i] - knee).rotated(angle)
	m.polygon = out


## Push a hem sideways (most at the bottom) and flare it a touch.
func _sway_cloth(part: String, amount: float) -> void:
	var m: Polygon2D = _meshes[part]
	var rest: PackedVector2Array = _mesh_rest[part]
	var box: Rect2 = _mesh_box[part]
	if box.size.y <= 0.0:
		return
	var out := rest.duplicate()
	var cx := box.get_center().x
	for i in rest.size():
		var f := clampf((rest[i].y - box.position.y) / box.size.y, 0.0, 1.0)
		var k := f * f
		out[i] = rest[i] + Vector2(amount * k + (rest[i].x - cx) * 0.06 * _walk * k, 0.0)
	m.polygon = out
