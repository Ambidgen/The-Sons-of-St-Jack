extends Node2D
## One linear story stage: built from data/stages/<id>.json, walked left-to-right
## (or wherever the road goes), with every beat placed on the path as a trigger
## that the player cannot walk around. The Director plays the scripts.
##
## Run on its own:  godot --path . res://scenes/stage/stage.tscn -- --stage=s05_butchers_steps
## Controls: arrows/WASD walk, confirm talks/looks, cancel or C opens the menu.
## Mouse: click a tile to walk there (along the road where it can), click someone
## or something to walk up and talk to it / look at it, hold the button to steer,
## right click for the menu. Keys take over from a click-walk at once.
## Level stages are drawn from one painting (assets/levels/<art>.png). Where
## characters can walk comes from that painting's pixels (TerrainSense, through
## StageMap): road, verges, water, obstacles and the edge of play are all detected,
## nothing is hand-masked. Derrick is a little slower off the road, and click-walks
## and scripted walks keep to it. Depth layers ("depth", "mist") slide at their own
## speed in front of or over the painting for parallax.
## Debug: F4 jumps to just before the next unplayed beat; F7 shows what the pixel
## detection found (amber road, green ground, blue water, red obstacles, black out
## of bounds). F1/F5/F6 as everywhere.

const TILE := 64
const BATTLE_SCENE := preload("res://scenes/battle/battle.tscn")
## Sideways scroll speed of each depth layer, relative to the camera, by name.
const DEPTH_SPEED := {"far": 0.2, "mid": 0.5, "near": 0.8, "fore": 1.3}

var stage: Dictionary = {}
var stage_id := ""
var map: StageMap
var world: Node2D
var ground: Node2D
var actors: Node2D
var fx_world: Node2D
var camera: Camera2D
var tint: CanvasModulate
var weather_layer: CanvasLayer
var weather_root: Node2D
var cinema: Cinema
var dialogue: DialogueBox
var menu: FieldMenu
var director: Director
var battle_layer: CanvasLayer
var hint_label: Label

var player: Node2D
var cell := Vector2i.ZERO
var facing := Vector2i.RIGHT
var busy := false
var moving := false
var leaving := false
var fired: Dictionary = {}            # trigger letter -> true
var cast_nodes: Dictionary = {}       # id -> Node2D
var cast_cells: Dictionary = {}       # id -> Vector2i
var cast_defs: Dictionary = {}        # id -> placement dict
var cast_hidden: Dictionary = {}      # id -> true
var cast_down: Dictionary = {}        # id -> true while lying on the ground (fall)
var ground_sprites: Dictionary = {}   # Vector2i -> Sprite2D
var lights: Dictionary = {}           # id -> PointLight2D
var learned_now: Array[String] = []   # skills gained in this stage's time skip
var _follow: Node2D = null
var _cam_tween: Tween
var _shake := 0.0
var _fog: Array[Sprite2D] = []
var _step_time := 0.2
var _base_zoom := 1.0
# level stages
var playfield: Sprite2D
var glow_layer: CanvasLayer
var _depth: Array = []                 # [Node2D, speed]: depth layers and mist bands
var _sense_view: Sprite2D              # F7 overlay
var _offroad := 1.2                    # step time multiplier off the road
# mouse
var _click_path: Array[Vector2i] = []
var _click_goal := Vector2i(-1, -1)
var _click_target := Vector2i(-1, -1)  # someone/something to use on arrival
var _steer := false                    # left button still held after a move click
var _hover: TileCursor
var _goal_mark: TileCursor
var _mouse_on := false                 # the pointer is being used (keys hide it)
var _mouse_screen := Vector2(-1, -1)   # last pointer position seen, in viewport pixels
var _pointing := false
const NO_CELL := Vector2i(-1, -1)


func _ready() -> void:
	var p := Router.take_params()
	stage_id = p.get("stage", Game.stage_id)
	if not Data.stages.has(stage_id):
		stage_id = Data.act_order()[0]
	Game.stage_id = stage_id
	stage = Data.stages[stage_id]
	_step_time = float(Data.cfg("step_time", 0.2))
	_offroad = float(Data.cfg("offroad_step", 1.2))
	if p.get("fresh", true):
		_enter_fresh()
	map = StageMap.new(stage)
	_build_nodes()
	_build_map()
	_build_cast()
	_build_lights()
	_build_fx()
	set_tint(Color(stage.get("tint", "#ffffff")), 0.0)
	set_weather(stage.get("weather", ""))
	_setup_camera()
	if stage.has("on_enter"):
		var first: Array = stage["scripts"].get(stage["on_enter"], [])
		if not first.is_empty() and first[0].has("card"):
			cinema.set_black(1.0)
		run_script(stage["on_enter"])


## Years pass between stages: Derrick's age, level and kit are set by the stage.
func _enter_fresh() -> void:
	var c: Dictionary = stage.get("derrick", {})
	var old_level := int(Game.hero()["level"])
	var new_level := int(c.get("level", old_level))
	learned_now = Game.skills_between(Game.hero(), old_level, new_level)
	Game.set_growth(c.get("form", Game.form), new_level)
	for item in stage.get("give", {}):
		Game.add_item(item, int(stage["give"][item]))
	Game.save_game()   # checkpoint


# ------------------------------------------------------------------ building
func _build_nodes() -> void:
	world = Node2D.new()
	world.name = "World"
	add_child(world)
	ground = Node2D.new()
	ground.z_index = -10
	world.add_child(ground)
	actors = Node2D.new()
	actors.y_sort_enabled = true
	world.add_child(actors)
	fx_world = Node2D.new()
	fx_world.z_index = 5
	world.add_child(fx_world)
	# mouse feedback lives on its own layer so night tints don't swallow it
	var cursor_layer := CanvasLayer.new()
	cursor_layer.layer = 1
	cursor_layer.follow_viewport_enabled = true
	add_child(cursor_layer)
	_goal_mark = TileCursor.new()
	_goal_mark.kind = TileCursor.Kind.GOAL
	_goal_mark.visible = false
	cursor_layer.add_child(_goal_mark)
	_hover = TileCursor.new()
	_hover.visible = false
	cursor_layer.add_child(_hover)
	camera = Camera2D.new()
	add_child(camera)
	camera.make_current()
	tint = CanvasModulate.new()
	add_child(tint)
	weather_layer = CanvasLayer.new()
	weather_layer.layer = 2
	add_child(weather_layer)
	weather_root = Node2D.new()
	weather_layer.add_child(weather_root)
	var cl := CanvasLayer.new()
	cl.layer = 5
	add_child(cl)
	cinema = Cinema.new()
	cl.add_child(cinema)
	hint_label = UIStyle.label("", 17, UIStyle.PAPER_DK)
	hint_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	hint_label.add_theme_constant_override("outline_size", 6)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hint_label.position = Vector2(540, 684)
	hint_label.size = Vector2(720, 24)
	hint_label.modulate.a = 0.0
	cl.add_child(hint_label)
	var ui := CanvasLayer.new()
	ui.layer = 6
	add_child(ui)
	dialogue = DialogueBox.new()
	ui.add_child(dialogue)
	menu = FieldMenu.new()
	ui.add_child(menu)
	battle_layer = CanvasLayer.new()
	battle_layer.layer = 10
	add_child(battle_layer)
	director = Director.new()
	director.stage = self
	director.cinema = cinema
	director.dialogue = dialogue
	add_child(director)


func _build_map() -> void:
	if map.is_level():
		_build_level()
	else:
		_build_tiles()
	player = _make_actor(Game.actor_art(Game.hero(), "field"))
	player.name = "Player"
	player.scale = Vector2.ONE * Game.actor_scale()
	cell = map.start
	player.position = feet(cell)
	cast_nodes["player"] = player
	cast_cells["player"] = cell
	var f: String = stage.get("start_facing", "right")
	face("player", f, "")


func _build_tiles() -> void:
	var props: Dictionary = stage.get("props", {})
	for y in map.h:
		for x in map.w:
			var c := Vector2i(x, y)
			var key := map.ground_key(c)
			if key != "":
				var s := Sprite2D.new()
				s.texture = Data.tex(key)
				s.centered = false
				s.position = Vector2(c * TILE)
				ground.add_child(s)
				ground_sprites[c] = s
			var k := map.ch(c)
			if StageMap.SOLID_PROPS.has(k):
				_place_prop(StageMap.SOLID_PROPS[k], c)
			elif map.prop_cells.has(c):
				var d: Dictionary = props.get(k, {})
				var n := _place_prop(d.get("art", ""), c)
				if d.has("flip"):
					n.get_node("Sprite").flip_h = true
			elif k == ">" and stage.has("exit_art"):
				_place_prop(stage["exit_art"], c)


## A level stage, back to front:
##   playfield   the painting (or its variant, e.g. the burned village), locked to the map
##   (characters)
##   mist        soft fog bands drifting over the far part of the painting at their own
##               speed (slower than the camera, so the distance seems to stay put)
##   depth       foreground silhouettes ("fore", 1.3x the camera) for parallax
##   glow        added light (flames), untouched by the tint
## "level": {"art": key, "scale": world px per painting px, "show": variant key}
func _build_level() -> void:
	var lv: Dictionary = stage["level"]
	var img := StageMap.level_image(stage, "show")
	if img == null:
		return
	var s := float(lv.get("scale", 1.0))
	playfield = Sprite2D.new()
	playfield.name = "Playfield"
	playfield.texture = ImageTexture.create_from_image(img)
	playfield.centered = false
	playfield.scale = Vector2(s, s)
	playfield.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	ground.add_child(playfield)
	for m in stage.get("mist", []):
		var band := Node2D.new()
		band.z_index = 3
		world.add_child(band)
		var tex := Data.tex("fx/fog")
		var span := maxf(0.0, map.w * TILE - 1280.0)
		var width := map.w * TILE + span + 1280.0
		var n := int(ceil(width / 900.0)) + 1
		for i in n:
			var f := Sprite2D.new()
			f.texture = tex
			f.centered = false
			f.scale = Vector2(900.0 / maxf(1.0, tex.get_width()), float(m.get("h", 220)) / maxf(1.0, tex.get_height()))
			f.position = Vector2(-640.0 + i * 900.0 - (i % 2) * 120.0, float(m.get("y", 40)))
			f.modulate = Color(m.get("color", "#ffffff"))
			f.modulate.a = float(m.get("alpha", 0.25))
			band.add_child(f)
		_depth.append([band, float(m.get("speed", 0.6))])
	for d in stage.get("depth", []):
		var t: Texture2D = load(StageMap.LEVEL_ROOT + String(d["art"]) + ".png")
		if t == null:
			continue
		var sp := Sprite2D.new()
		sp.texture = t
		sp.centered = false
		var ds := float(d.get("scale", 1.0))
		sp.scale = Vector2(ds, ds)
		sp.z_index = 6
		sp.modulate = Color(d.get("color", "#ffffff"))
		if d.get("anchor", "bottom") == "bottom":
			sp.position.y = map.h * TILE - t.get_height() * ds + float(d.get("y", 0))
		else:
			sp.position.y = float(d.get("y", 0))
		world.add_child(sp)
		_depth.append([sp, float(d.get("speed", DEPTH_SPEED["fore"]))])
	if lv.has("glow"):
		glow_layer = CanvasLayer.new()
		glow_layer.layer = 1
		glow_layer.follow_viewport_enabled = true   # moves with the camera, but outside the tint
		add_child(glow_layer)
		move_child(glow_layer, 0)
		var glow := Sprite2D.new()
		glow.texture = ImageTexture.create_from_image(StageMap.level_image(stage, "glow"))
		glow.centered = false
		glow.scale = Vector2(s, s)
		var add := CanvasItemMaterial.new()
		add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		glow.material = add
		glow_layer.add_child(glow)


## Depth layers slide sideways by their speed. The reference is where a 1x camera's
## left edge would be (clamped to the map), so zooming in never shows a layer's end.
func _update_depth() -> void:
	if _depth.is_empty():
		return
	var span := maxf(0.0, map.w * TILE - 1280.0)
	var c := clampf(camera.get_screen_center_position().x - 640.0, 0.0, span)
	for e in _depth:
		(e[0] as Node2D).position.x = c * (1.0 - float(e[1]))


## F7: what the pixel detection made of the painting, over the painting.
func toggle_sense_view() -> void:
	if map.sense == null:
		return
	if _sense_view == null:
		_sense_view = Sprite2D.new()
		_sense_view.texture = ImageTexture.create_from_image(map.sense.overlay_image(0.45))
		_sense_view.centered = false
		_sense_view.scale = Vector2(TerrainSense.CELL, TerrainSense.CELL)
		_sense_view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var layer := CanvasLayer.new()        # outside the time-of-day tint, so night stages read too
		layer.layer = 1
		layer.follow_viewport_enabled = true
		add_child(layer)
		layer.add_child(_sense_view)
		hint("Pixel detection: amber road, green ground, blue water, red obstacle, dark = out of bounds (F7 to hide)")
	else:
		_sense_view.visible = not _sense_view.visible


func _place_prop(art: String, c: Vector2i) -> Node2D:
	var n := _make_actor(art)
	n.position = feet(c)
	return n


## Every body on a stage -- people, animals, props -- is a Rig named "Sprite"
## under a holder node: articulated if the art has a rig sheet, flat if not.
func _make_actor(art: String) -> Node2D:
	var n := Node2D.new()
	n.add_child(Rig.make(art))
	actors.add_child(n)
	return n


func rig(n: Node2D) -> Rig:
	return n.get_node("Sprite") as Rig


func _build_cast() -> void:
	var defs: Dictionary = stage.get("cast", {})
	for letter in defs:
		var d: Dictionary = defs[letter]
		var id: String = d.get("id", letter)
		var c: Vector2i = map.cast_cells.get(letter, Vector2i(-1, -1))
		if d.has("at"):
			c = Vector2i(int(d["at"][0]), int(d["at"][1]))
		var art: String = d.get("art", Data.cast.get(d.get("cast", id), {}).get("field", ""))
		var n := _make_actor(art)
		n.name = id
		n.position = feet(c)
		if d.has("scale"):
			n.scale = Vector2.ONE * float(d["scale"])
		if d.has("tint"):            # e.g. near-black for men seen only as shapes against fire
			rig(n).tint = Color(d["tint"])
		cast_nodes[id] = n
		cast_cells[id] = c
		cast_defs[id] = d
		if d.get("hidden", false):
			n.visible = false
			cast_hidden[id] = true
		if d.has("facing"):
			face(id, d["facing"], "")
		if d.get("down", false):
			fall(id, true, true)


func _build_lights() -> void:
	for l in stage.get("lights", []):
		var light := PointLight2D.new()
		light.texture = _light_texture()
		light.texture_scale = float(l.get("scale", 3.0))
		light.color = Color(l.get("color", "#ffb060"))
		light.energy = float(l.get("energy", 1.0))
		light.position = Vector2(int(l["at"][0]) * TILE + TILE / 2.0, int(l["at"][1]) * TILE + TILE / 2.0)
		world.add_child(light)
		lights[l.get("id", "light%d" % lights.size())] = light
		if l.get("flicker", false):
			_flicker(light)
	if stage.get("window_lights", false):
		for y in map.h:
			for x in map.w:
				if map.ch(Vector2i(x, y)) == "]":
					var wl := PointLight2D.new()
					wl.texture = _light_texture()
					wl.texture_scale = 1.3
					wl.color = Color("#ffb060")
					wl.energy = 0.9
					wl.position = Vector2(x * TILE + 40, y * TILE + 28)
					world.add_child(wl)


var _light_tex: GradientTexture2D


func _light_texture() -> GradientTexture2D:
	if _light_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		_light_tex = GradientTexture2D.new()
		_light_tex.gradient = g
		_light_tex.fill = GradientTexture2D.FILL_RADIAL
		_light_tex.fill_from = Vector2(0.5, 0.5)
		_light_tex.fill_to = Vector2(1.0, 0.5)
		_light_tex.width = 256
		_light_tex.height = 256
	return _light_tex


func _flicker(light: PointLight2D) -> void:
	if not is_instance_valid(light):
		return
	var base: float = light.get_meta("base", light.energy)
	light.set_meta("base", base)
	var tw := light.create_tween()
	tw.tween_property(light, "energy", base * randf_range(0.75, 1.15), randf_range(0.08, 0.22))
	tw.tween_callback(_flicker.bind(light))


func _build_fx() -> void:
	for f in stage.get("fx", []):
		var pos := Vector2(int(f["at"][0]) * TILE + TILE / 2.0, int(f["at"][1]) * TILE + TILE / 2.0)
		var p := CPUParticles2D.new()
		p.position = pos
		match f["kind"]:
			"smoke":
				p.texture = Data.tex("fx/smoke")
				p.amount = 14
				p.lifetime = 5.0
				p.preprocess = 5.0
				p.direction = Vector2(0.2, -1)
				p.spread = 12
				p.gravity = Vector2(6, -4)
				p.initial_velocity_min = 18
				p.initial_velocity_max = 32
				p.scale_amount_min = 0.6
				p.scale_amount_max = 1.6
				p.color_ramp = _ramp(Color(1, 1, 1, 0.55), Color(1, 1, 1, 0))
			"embers":
				p.texture = Data.tex("fx/ember")
				p.amount = 18
				p.lifetime = 1.8
				p.preprocess = 2.0
				p.direction = Vector2(0, -1)
				p.spread = 25
				p.gravity = Vector2(0, -20)
				p.initial_velocity_min = 30
				p.initial_velocity_max = 70
				p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
				p.emission_rect_extents = Vector2(14, 4)
				p.color_ramp = _ramp(Color(1, 1, 1, 1), Color(1, 0.5, 0.2, 0))
		fx_world.add_child(p)


func _ramp(a: Color, b: Color) -> Gradient:
	var g := Gradient.new()
	g.set_color(0, a)
	g.set_color(1, b)
	return g


func _setup_camera() -> void:
	var mw := map.w * TILE
	var mh := map.h * TILE
	if mw < 1280:
		camera.limit_left = int((mw - 1280) / 2.0)
		camera.limit_right = camera.limit_left + 1280
	else:
		camera.limit_left = 0
		camera.limit_right = mw
	if mh < 720:
		camera.limit_top = int((mh - 720) / 2.0)
		camera.limit_bottom = camera.limit_top + 720
	else:
		camera.limit_top = 0
		camera.limit_bottom = mh
	_base_zoom = float(stage.get("zoom", 1.0))
	camera.zoom = Vector2(_base_zoom, _base_zoom)
	_follow = player
	camera.global_position = player.global_position
	camera.reset_smoothing()
	_update_depth()


func feet(c: Vector2i) -> Vector2:
	return Vector2(c.x * TILE + TILE / 2.0, c.y * TILE + TILE - 3.0)


# ------------------------------------------------------------------ frame
func _process(delta: float) -> void:
	if _follow and is_instance_valid(_follow) and (_cam_tween == null or not _cam_tween.is_running()):
		var target := _follow.global_position + Vector2(0, -28)
		camera.global_position = camera.global_position.lerp(target, clampf(delta * 6.0, 0.0, 1.0))
	if _shake > 0.0:
		camera.offset = Vector2(randf_range(-_shake, _shake), randf_range(-_shake, _shake))
		_shake = maxf(0.0, _shake - delta * 30.0)
	else:
		camera.offset = Vector2.ZERO
	_update_depth()
	for f in _fog:
		f.position.x += delta * f.get_meta("speed", 12.0)
		if f.position.x > 1280 + 600:
			f.position.x = -600
	_update_hover()
	if busy or moving or leaving:
		return
	var dir := Vector2i.ZERO
	if Input.is_action_pressed("ui_right"):
		dir = Vector2i.RIGHT
	elif Input.is_action_pressed("ui_left"):
		dir = Vector2i.LEFT
	elif Input.is_action_pressed("ui_up"):
		dir = Vector2i.UP
	elif Input.is_action_pressed("ui_down"):
		dir = Vector2i.DOWN
	if dir == Vector2i.ZERO:
		_follow_click()
		return
	_cancel_click()
	facing = dir
	if dir.x != 0:
		rig(player).flip_h = dir.x < 0
	if not blocked(cell + dir):
		_step(dir)


func blocked(c: Vector2i) -> bool:
	if map.terrain_solid(c) or not map.in_bounds(c):
		return true
	for id in cast_cells:
		if id != "player" and cast_cells[id] == c and _solid_cast(id):
			return true
	return false


## Someone who stands in the way: visible, not marked "solid": false, and not lying
## on the ground (the fallen -- a dead wolf, a dying man -- can be stepped over).
func _solid_cast(id: String) -> bool:
	return not cast_hidden.has(id) and not cast_down.has(id) and cast_defs.get(id, {}).get("solid", true)


func _step(dir: Vector2i) -> void:
	moving = true
	cell += dir
	cast_cells["player"] = cell
	# the road is the easy way: a step onto anything else takes a little longer
	var t := _step_time if (not map.is_level() or map.is_road(cell)) else _step_time * _offroad
	rig(player).step(t)
	var tw := create_tween()
	tw.tween_property(player, "position", feet(cell), t)
	await tw.finished
	moving = false
	_on_enter(cell)


func _on_enter(c: Vector2i) -> void:
	var k := map.ch(c)
	if StageMap._is_lower(k) and not fired.has(k):
		fired[k] = true
		var sid: String = stage.get("triggers", {}).get(k, "")
		if sid != "":
			await run_script(sid)
	elif k == ">":
		_leave()


# ------------------------------------------------------------------ scripts
func run_script(id: String) -> void:
	var cmds: Array = stage.get("scripts", {}).get(id, [])
	_cancel_click()
	busy = true
	var auto_lb: bool = Data.cfg("auto_letterbox", true) and not cinema.letterboxed
	if auto_lb:
		cinema.letterbox(true)
	await director.run(cmds)
	if director.halted:
		return
	if auto_lb:
		cinema.letterbox(false)
	camera_follow(player)
	if not is_equal_approx(camera.zoom.x, _base_zoom):
		zoom_to(_base_zoom, 0.8)
	busy = false


func _leave() -> void:
	_cancel_click()
	leaving = true
	busy = true
	if stage.has("on_exit"):
		await cinema.letterbox(true)
		await director.run(stage["scripts"][stage["on_exit"]])
		if director.halted:
			return
	goto_next()


func goto_next() -> void:
	leaving = true
	var nxt: String = stage.get("next", Data.next_stage(stage_id))
	if nxt == "":
		end_act()
		return
	Game.stage_id = nxt
	Router.goto("res://scenes/stage/stage.tscn", {"stage": nxt, "fresh": true}, 0.8)


func end_act() -> void:
	leaving = true
	Game.flags["act_one_complete"] = true
	Router.goto("res://scenes/title/title.tscn", {}, 1.2)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F4:
		_debug_skip()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F7:
		toggle_sense_view()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if not event.pressed:
			_steer = false
		elif not (busy or leaving):
			get_viewport().set_input_as_handled()
			_mouse_on = true
			_click(_cell_at((make_input_local(event) as InputEventMouseButton).position))
		return
	if event is InputEventMouseMotion:
		_mouse_on = true
		return
	if event is InputEventKey or event is InputEventJoypadButton:
		_mouse_on = false
	if busy or moving or leaving:
		return
	if event.is_action_pressed("ui_accept"):
		get_viewport().set_input_as_handled()
		_interact(cell + facing)
	elif event.is_action_pressed("ui_cancel") or event.is_action_pressed("menu"):
		get_viewport().set_input_as_handled()
		busy = true
		await menu.open()
		busy = false


func _interact(target: Vector2i) -> void:
	for id in cast_cells:
		if cast_cells[id] == target and not cast_hidden.has(id) and cast_defs.get(id, {}).has("talk"):
			await run_script(cast_defs[id]["talk"])
			return
	if map.prop_cells.has(target):
		var d: Dictionary = stage.get("props", {}).get(String(map.prop_cells[target]), {})
		if d.has("examine") and not fired.has("examine:" + str(target)):
			if d.get("once", false):
				fired["examine:" + str(target)] = true
			await run_script(d["examine"])


# ------------------------------------------------------------------ mouse
func _cell_at(world_pos: Vector2) -> Vector2i:
	return Vector2i(floori(world_pos.x / TILE), floori(world_pos.y / TILE))


## The tile under the pointer now (the camera may have moved under a still mouse).
func _pointer_cell() -> Vector2i:
	return _cell_at(get_canvas_transform().affine_inverse() * _mouse_screen)


## Track the pointer from its own events (not the OS cursor), so steering and the
## hover marker agree with what was clicked -- also for synthetic input in tests.
func _input(event: InputEvent) -> void:
	if event is InputEventMouse:
		_mouse_screen = event.position


## Someone to talk to or something to look at in this cell, or under the head of
## whoever stands in the cell below (clicking a body anywhere counts).
func _usable_near(c: Vector2i) -> Vector2i:
	for cc in [c, c + Vector2i.DOWN]:
		if _usable(cc):
			return cc
	return NO_CELL


func _usable(c: Vector2i) -> bool:
	for id in cast_cells:
		if id != "player" and cast_cells[id] == c and not cast_hidden.has(id) \
				and cast_defs.get(id, {}).has("talk"):
			return true
	return map.prop_cells.has(c) and stage.get("props", {}).get(String(map.prop_cells[c]), {}).has("examine") \
			and not fired.has("examine:" + str(c))


## A left click on the world while Derrick is free to move.
func _click(c: Vector2i) -> void:
	var target := _usable_near(c)
	if target != NO_CELL:
		if (target - cell).length_squared() == 1 and not moving:
			_cancel_click()
			_face_cell(target)
			_interact(target)
			return
		if _set_course(target, true):
			_click_target = target
			_steer = false
			return
	if _set_course(c, false):
		_steer = true
	else:
		_hover.show_at(c, TileCursor.NO)


## Plan a walk to c (to the tile beside it, if c is someone/something or a wall).
## Returns false if there's no way there.
func _set_course(c: Vector2i, to_use: bool) -> bool:
	if not map.in_bounds(c) or c == cell:
		return false
	var goal := c
	if not to_use and blocked(c):
		goal = _open_cell_near(c)
		if goal == NO_CELL or goal == cell:
			return false
	var p := map.route(cell, goal, _blockers())
	if p.size() < 2:
		return false
	_click_path = p.slice(1, p.size() - 1 if to_use else p.size())
	_click_target = NO_CELL
	_click_goal = goal if not to_use else (p[p.size() - 2] if p.size() >= 2 else cell)
	_goal_mark.color = TileCursor.TALK if to_use else TileCursor.WALK
	_goal_mark.show_at(_click_goal if not to_use else c, _goal_mark.color)
	return true


## The walkable tile nearest a blocked click (one ring out), if any.
func _open_cell_near(c: Vector2i) -> Vector2i:
	var best := NO_CELL
	var best_d := INF
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var n := c + Vector2i(dx, dy)
			if not blocked(n):
				var d := Vector2(n - c).length() + Vector2(n - cell).length() * 0.01
				if d < best_d:
					best_d = d
					best = n
	return best


## Each frame Derrick is free and not mid-step: take the next step of a click-walk
## (steering toward the pointer while the button is held), or arrive and act.
func _follow_click() -> void:
	if _steer and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		var mc := _pointer_cell()
		if mc != _click_goal and mc != cell and _usable_near(mc) == NO_CELL:
			_set_course(mc, false)
	elif _steer:
		_steer = false
	if not _click_path.is_empty():
		var nxt: Vector2i = _click_path.pop_front()
		var d := nxt - cell
		if d.length_squared() != 1 or blocked(nxt):
			# someone stepped into the way: find another way to the same place
			var tgt := _click_target
			if not _set_course(tgt if tgt != NO_CELL else _click_goal, tgt != NO_CELL):
				_cancel_click()
			else:
				_click_target = tgt
			return
		facing = d
		if d.x != 0:
			rig(player).flip_h = d.x < 0
		_step(d)
		return
	if _click_target != NO_CELL:
		var t := _click_target
		_cancel_click()
		_face_cell(t)
		_interact(t)
		return
	if _goal_mark.visible and not _steer:
		_goal_mark.visible = false


func _cancel_click() -> void:
	_click_path.clear()
	_click_target = NO_CELL
	_click_goal = NO_CELL
	_steer = false
	if _goal_mark:
		_goal_mark.visible = false


func _face_cell(t: Vector2i) -> void:
	var d := t - cell
	if d == Vector2i.ZERO:
		return
	facing = Vector2i(signi(d.x), 0) if absi(d.x) >= absi(d.y) else Vector2i(0, signi(d.y))
	if d.x != 0:
		rig(player).flip_h = d.x < 0


## Corners on the tile under the pointer, and a pointing hand over anything usable.
func _update_hover() -> void:
	var free := _mouse_on and not busy and not leaving and _hover != null
	var over_usable := false
	if free:
		var c := _pointer_cell()
		var target := _usable_near(c)
		over_usable = target != NO_CELL
		if over_usable:
			_hover.show_at(target, TileCursor.TALK)
		elif _hover.color == TileCursor.NO and _hover.visible and _hover.position == Vector2(c) * TILE:
			pass   # keep showing the "can't go" flash on this tile
		elif map.in_bounds(c) and (not blocked(c) or c == cell):
			_hover.show_at(c, TileCursor.WALK)
		else:
			_hover.visible = false
	elif _hover:
		_hover.visible = false
	if over_usable != _pointing:
		_pointing = over_usable
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if over_usable else Input.CURSOR_ARROW)


func _exit_tree() -> void:
	if _pointing:
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)


## F4: put Derrick just before the next beat he hasn't played yet (or the exit).
func _debug_skip() -> void:
	if busy or moving:
		return
	var target := next_goal()
	if target == Vector2i(-1, -1):
		return
	var p := map.path(cell, target, _blockers())
	if p.size() >= 2:
		cell = p[p.size() - 2]
		cast_cells["player"] = cell
		player.position = feet(cell)
		camera.global_position = player.global_position


## Where the story wants Derrick to go next: the nearest unplayed trigger, else the exit.
func next_goal() -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_len := 1 << 30
	var blk := _blockers()
	for letter in map.triggers:
		if fired.has(letter):
			continue
		for c in map.triggers[letter]:
			if blk.has(c):
				continue          # someone is standing there: aim for another cell of the line
			var p := map.path(cell, c, blk)
			if not p.is_empty() and p.size() < best_len:
				best_len = p.size()
				best = c
	if best.x >= 0:
		return best
	for e in map.exits:
		if blk.has(e):
			continue
		var p := map.path(cell, e, blk)
		if not p.is_empty() and p.size() < best_len:
			best_len = p.size()
			best = e
	return best


func _blockers() -> Dictionary:
	var out := {}
	for id in cast_cells:
		if id != "player" and _solid_cast(id):
			out[cast_cells[id]] = true
	return out


# ------------------------------------------------------------------ director API
func node_of(id: String) -> Node2D:
	if id == "derrick":
		id = "player"
	return cast_nodes.get(id)


func cast_key(id: String) -> String:
	if id == "player" or id == "derrick":
		return "derrick"
	var d: Dictionary = cast_defs.get(id, {})
	return d.get("cast", id)


func camera_to(target: Variant, t: float) -> void:
	var pos: Vector2
	var node: Node2D = null
	if target is String:
		node = node_of(target)
		if node == null:
			return
		pos = node.global_position + Vector2(0, -28)
	else:
		pos = Vector2(float(target[0]) * TILE + TILE / 2.0, float(target[1]) * TILE + TILE / 2.0)
	_follow = null
	if _cam_tween:
		_cam_tween.kill()
	if t <= 0.0:
		camera.global_position = pos
	else:
		_cam_tween = create_tween()
		_cam_tween.tween_property(camera, "global_position", pos, t).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		await _cam_tween.finished
	_follow = node


## Push in for a close-up (1.0 = normal). Scripts return to the stage zoom when they end.
func zoom_to(z: float, t: float) -> void:
	var tw := create_tween()
	tw.tween_property(camera, "zoom", Vector2(z, z), t).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tw.finished


func camera_follow(node: Node2D) -> void:
	if _cam_tween:
		_cam_tween.kill()
	_follow = node


## Walks an actor tile by tile through waypoints. Each leg goes x first, then y;
## if that would cut through something the painting says is solid, the actor
## takes the road-preferring route instead ("direct": true in the script skips this).
func walk(id: String, waypoints: Array, speed: float, direct := false) -> void:
	var n := node_of(id)
	if n == null:
		return
	var key := "player" if id == "derrick" else id
	var cur: Vector2i = cast_cells.get(key, Vector2i.ZERO)
	var s := rig(n)
	var step_t := 1.0 / maxf(0.5, speed)
	for wp in waypoints:
		var goal := Vector2i(int(wp[0]), int(wp[1]))
		var steps := _leg(cur, goal)
		if not direct and map.is_level():
			var clear := true
			for i in steps.size() - 1:
				if map.terrain_solid(steps[i]):
					clear = false
					break
			if not clear:
				var r := map.route(cur, goal)
				if r.size() >= 2:
					steps = r.slice(1)
		for nxt in steps:
			var d: Vector2i = nxt - cur
			if d.x != 0:
				s.flip_h = d.x < 0
			cur = nxt
			cast_cells[key] = cur
			if key == "player":
				cell = cur
				facing = Vector2i(signi(d.x), 0) if d.x != 0 else Vector2i(0, signi(d.y))
			s.step(step_t)
			var tw := n.create_tween()
			tw.tween_property(n, "position", feet(cur), step_t)
			await tw.finished


## The cells of a straight leg, x first then y (not including the start).
func _leg(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var cur := from
	while cur != to:
		if cur.x != to.x:
			cur += Vector2i(signi(to.x - cur.x), 0)
		else:
			cur += Vector2i(0, signi(to.y - cur.y))
		out.append(cur)
	return out


func face(id: String, dir: String, to: String) -> void:
	var n := node_of(id)
	if n == null:
		return
	var s := rig(n)
	if to != "":
		var other := node_of(to)
		if other:
			s.flip_h = other.position.x < n.position.x
		return
	match dir:
		"left":
			s.flip_h = true
			if n == player:
				facing = Vector2i.LEFT
		"right":
			s.flip_h = false
			if n == player:
				facing = Vector2i.RIGHT
		"up":
			if n == player:
				facing = Vector2i.UP
		"down":
			if n == player:
				facing = Vector2i.DOWN


func teleport(id: String, c: Vector2i) -> void:
	var n := node_of(id)
	if n == null:
		return
	var key := "player" if id == "derrick" else id
	cast_cells[key] = c
	n.position = feet(c)
	if key == "player":
		cell = c


func show_actor(id: String, on: bool) -> void:
	var n := node_of(id)
	if n == null:
		return
	if on:
		cast_hidden.erase(id)
		n.visible = true
		n.modulate.a = 0.0
		var tw := n.create_tween()
		tw.tween_property(n, "modulate:a", 1.0, 0.35)
		await tw.finished
	else:
		cast_hidden[id] = true
		var tw := n.create_tween()
		tw.tween_property(n, "modulate:a", 0.0, 0.35)
		await tw.finished
		n.visible = false


func fall(id: String, down: bool, instant := false) -> void:
	var n := node_of(id)
	if n == null:
		return
	var s := rig(n)
	var h := s.height
	if n != player:
		if down:
			cast_down[id] = true
		else:
			cast_down.erase(id)
	var tw := n.create_tween().set_parallel()
	var t := 0.0 if instant else 0.35
	s.animate = not down          # the fallen don't breathe for the camera
	if down:
		tw.tween_property(s, "rotation_degrees", -84.0 if not s.flip_h else 84.0, t).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		tw.tween_property(s, "position", Vector2(0, h * 0.35), t)
		tw.tween_property(s, "tint", Color(0.75, 0.72, 0.7), t)
	else:
		tw.tween_property(s, "rotation_degrees", 0.0, 0.4)
		tw.tween_property(s, "position", Vector2.ZERO, 0.4)
		tw.tween_property(s, "tint", Color.WHITE, 0.4)


func pose(id: String, art: String) -> void:
	var n := node_of(id)
	if n == null:
		return
	var s := rig(n)
	if art == "":
		if n == player:
			art = Game.actor_art(Game.hero(), "field")
		else:
			art = cast_defs.get(id, {}).get("art", Data.cast.get(cast_key(id), {}).get("field", ""))
	s.set_art(art)


## Play a body action on someone's rig (see Rig.ACTION_LEN); "reset" stands them
## back up from a held pose (cower, raise, yield).
func act(id: String, action: String) -> void:
	var n := node_of(id)
	if n == null:
		return
	if action == "reset":
		rig(n).reset_pose()
		return
	await rig(n).play(action)


func emote(id: String, text: String) -> void:
	var n := node_of(id)
	if n == null:
		return
	var s := rig(n)
	var l := UIStyle.label(text, 30, UIStyle.PAPER)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 8)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.size = Vector2(60, 40)
	l.position = Vector2(-30, -s.height - 36)
	l.z_index = 30
	n.add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "position:y", l.position.y - 12, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.0)
	tw.tween_property(l, "modulate:a", 0.0, 0.3)
	tw.tween_callback(l.queue_free)


func set_tint(c: Color, t: float) -> void:
	if t <= 0.0:
		tint.color = c
	else:
		var tw := create_tween()
		tw.tween_property(tint, "color", c, t)
	weather_root.modulate = c.lerp(Color.WHITE, 0.4)


func set_light(id: String, energy: float, t: float) -> void:
	var l: PointLight2D = lights.get(id)
	if l == null:
		return
	l.set_meta("base", energy)
	var tw := create_tween()
	tw.tween_property(l, "energy", energy, t)


func shake(strength: float, _t: float) -> void:
	_shake = strength


func retile(map_chars: Dictionary) -> void:
	if map.is_level():   # a level stage swaps in another painting: {"retile": {"art": "key"}}
		if map_chars.has("art") and StageMap.has_level_art(map_chars["art"]):
			var img: Image = load(StageMap.LEVEL_ROOT + String(map_chars["art"]) + ".png")
			playfield.texture = ImageTexture.create_from_image(img)
		return
	for c in ground_sprites:
		var k := map.ch(c)
		if map_chars.has(k):
			var nk: String = map_chars[k]
			ground_sprites[c].texture = Data.tex("tile/" + StageMap.GROUND.get(nk, nk))


func hint(text: String) -> void:
	hint_label.text = text
	var tw := hint_label.create_tween()
	tw.tween_property(hint_label, "modulate:a", 1.0, 0.4)
	tw.tween_interval(5.0)
	tw.tween_property(hint_label, "modulate:a", 0.0, 0.8)


## Time-skip caption: "Derrick, thirteen. ..." plus whatever he learned since.
func show_growth() -> void:
	var text: String = stage.get("growth_text", "")
	if not learned_now.is_empty():
		var names: Array[String] = []
		for s in learned_now:
			names.append(Data.skills[s]["name"])
		text += "\n(He has learned: %s)" % ", ".join(names)
	if text != "":
		await cinema.caption(text, 0.0, true)


## A time skip inside a stage: Derrick is older (form + level), drawn anew, and
## the caption says so. {"age": "small", "level": 1, "text": "Derrick, seven."}
func set_age(form: String, level: int, text: String) -> void:
	var old_level := int(Game.hero()["level"])
	var learned := Game.skills_between(Game.hero(), old_level, level)
	Game.set_growth(form, level)
	rig(player).set_art(Game.actor_art(Game.hero(), "field"))
	player.scale = Vector2.ONE * Game.actor_scale()
	face("player", "left" if rig(player).flip_h else "right", "")
	if not learned.is_empty():
		var names: Array[String] = []
		for s in learned:
			names.append(Data.skills[s]["name"])
		text += "\n(He has learned: %s)" % ", ".join(names)
	if text != "":
		await cinema.caption(text, 0.0, true)


## Shut or open one of the stage's gates (strips of tiles named in "gates").
func set_gate(id: String, on: bool) -> void:
	map.set_gate(id, on)


func set_weather(kind: String) -> void:
	for c in weather_root.get_children():
		c.queue_free()
	_fog.clear()
	match kind:
		"rain":
			var p := _screen_particles("fx/rain", 240, 0.8)
			p.direction = Vector2(-0.25, 1)
			p.spread = 3
			p.initial_velocity_min = 900
			p.initial_velocity_max = 1150
			p.particle_flag_align_y = true
			p.color = Color(1, 1, 1, 0.5)
		"snow":
			var p := _screen_particles("fx/snow", 170, 9.0)
			p.direction = Vector2(0.2, 1)
			p.spread = 25
			p.gravity = Vector2(0, 10)
			p.initial_velocity_min = 40
			p.initial_velocity_max = 95
			p.scale_amount_min = 0.35
			p.scale_amount_max = 1.1
		"ash":
			var p := _screen_particles("fx/ash", 90, 10.0)
			p.direction = Vector2(0.4, 1)
			p.spread = 40
			p.initial_velocity_min = 25
			p.initial_velocity_max = 60
			p.angular_velocity_min = -90
			p.angular_velocity_max = 90
			p.scale_amount_min = 0.6
			p.scale_amount_max = 1.4
		"fog":
			for i in 4:
				var f := Sprite2D.new()
				f.texture = Data.tex("fx/fog")
				f.scale = Vector2(3.2, 2.4)
				f.position = Vector2(-300 + i * 520, 180 + (i % 2) * 300)
				f.modulate.a = 0.34
				f.set_meta("speed", 10.0 + i * 5.0)
				weather_root.add_child(f)
				_fog.append(f)


func _screen_particles(tex: String, amount: int, lifetime: float) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.texture = Data.tex(tex)
	p.amount = amount
	p.lifetime = lifetime
	p.preprocess = lifetime
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(800, 10)
	p.position = Vector2(760, -30)
	p.gravity = Vector2.ZERO
	weather_root.add_child(p)
	return p


# ------------------------------------------------------------------ battles
## Story fights play as an overlay: the stage stays loaded underneath, so the
## script simply continues with the outcome. Returns win | lose | scripted | fled | title.
func run_battle(enc_id: String) -> String:
	cinema.flash(Color("#e9dfc7"), 0.4)
	await get_tree().create_timer(0.15).timeout
	await Router.fade_out(0.3)
	var b = BATTLE_SCENE.instantiate()
	b.embedded = true
	b.params = {"encounter": enc_id}
	battle_layer.add_child(b)
	b.get_node("UI").layer = 11
	world.visible = false
	weather_layer.visible = false
	cinema.visible = false
	if glow_layer:
		glow_layer.visible = false
	await Router.fade_in(0.3)
	var outcome: String = await b.finished
	await Router.fade_out(0.35)
	if Data.encounters[enc_id].get("end_black", false):
		cinema.set_black(1.0)       # the fight ends in a blackout: the script picks up in the dark
	b.queue_free()
	world.visible = true
	weather_layer.visible = true
	cinema.visible = true
	if glow_layer:
		glow_layer.visible = true
	await get_tree().process_frame
	await Router.fade_in(0.35)
	if outcome == "retry":
		return await run_battle(enc_id)
	if outcome == "title":
		leaving = true
		Router.goto("res://scenes/title/title.tscn")
	return outcome
