extends Node
## Plays Act One with synthetic input and saves screenshots along the way.
## Needs a real renderer (not --headless):
##   xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 \
##       res://tests/tour.tscn -- --out=/tmp/tour [--stage=s05_butchers_steps --only] [--scale=3] [--mouse]
## Without --stage it starts at the title and plays the whole act. With
## --stage --only it plays that one stage and stops when the next one loads.
## Walking follows the stage's own "next beat" route; dialogue is advanced with
## confirm; fights are handed to the AI after a screenshot of the command menu;
## at the final offer it spits once (to test the degrading defiant option).
## --mouse plays the same route with the mouse only: clicks to walk (and to talk),
## clicks to advance text, clicks choices, opens the field menu with right click,
## and picks the first fight's attack and target by clicking.

var out_dir := "/tmp/tour"
var only_stage := ""
var start_stage := ""
var scale := 3.0
var errors: Array[String] = []
var shots_this_stage := 0
var max_shots_per_stage := 9
var _pending_shot := ""
var _shot_at := 0.0
var _t := 0.0
var _hooked: Object = null
var _choice_pending: Array = []
var _spat := false
var _battle_seen: Dictionary = {}
var _menu_done := false
var _stage_seen: Array[String] = []
var mouse := false
var clicks_to_walk := 0
var _progress_key := ""
var _progress_t := 0.0
var _stuck_reported := false
var trace := false
var nod := false          # take the compliant option at every choice
var _iter := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
		elif a.begins_with("--stage="):
			start_stage = a.trim_prefix("--stage=")
		elif a == "--only":
			only_stage = "yes"
		elif a.begins_with("--scale="):
			scale = float(a.trim_prefix("--scale="))
		elif a == "--mouse":
			mouse = true
		elif a == "--trace":
			trace = true
		elif a == "--nod":
			nod = true
		elif a.begins_with("--max-shots="):
			max_shots_per_stage = int(a.trim_prefix("--max-shots="))
	DirAccess.make_dir_recursive_absolute(out_dir)
	reparent.call_deferred(get_tree().root)
	await get_tree().process_frame
	await get_tree().process_frame
	await _run()
	print("TOUR DONE ", out_dir, " errors=", errors)
	get_tree().quit(0 if errors.is_empty() else 1)


# ------------------------------------------------------------------ helpers
func wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


func press(action: String) -> void:
	var down := InputEventAction.new()
	down.action = action
	down.pressed = true
	Input.parse_input_event(down)
	await wait(0.04)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)


func click_at(p: Vector2, button := MOUSE_BUTTON_LEFT) -> void:
	var mm := InputEventMouseMotion.new()
	mm.position = p
	mm.global_position = p
	Input.parse_input_event(mm)
	await wait(0.03)
	var down := InputEventMouseButton.new()
	down.button_index = button
	down.button_mask = MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT
	down.pressed = true
	down.position = p
	down.global_position = p
	Input.parse_input_event(down)
	await wait(0.05)
	var up := down.duplicate() as InputEventMouseButton
	up.pressed = false
	up.button_mask = 0
	Input.parse_input_event(up)


func click_control(c: Control) -> void:
	await click_at(c.get_global_rect().get_center())


func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out_dir, name])
	print("shot ", name)


func scene() -> Node:
	return get_tree().current_scene


func expect(cond: bool, what: String) -> void:
	if not cond:
		errors.append(what)
		printerr("TOUR EXPECT FAILED: ", what)


# ------------------------------------------------------------------ script
func _run() -> void:
	Engine.time_scale = 1.0
	get_tree().change_scene_to_file("res://scenes/title/title.tscn")
	await wait(1.2)
	if start_stage == "":
		await shot("00_title")
		await press("ui_accept")                     # Begin Act One
	else:
		Game.new_game()
		Game.stage_id = start_stage
		Router.goto("res://scenes/stage/stage.tscn", {"stage": start_stage, "fresh": true})
	await wait(1.5)
	Engine.time_scale = scale
	var deadline := 900.0
	var elapsed := 0.0
	while elapsed < deadline:
		await wait(0.05)
		elapsed += 0.05
		_t += 0.05
		var sc := scene()
		if sc == null:
			continue
		if sc.name == "Title":
			if Game.flags.get("act_one_complete", false):
				Engine.time_scale = 1.0
				await wait(1.5)
				await shot("99_title_after")
				break
			continue
		if sc.name != "Stage":
			continue
		if not _stage_seen.has(sc.stage_id):
			if only_stage != "" and not _stage_seen.is_empty():
				break                                 # --only: the next stage has loaded
			_stage_seen.append(sc.stage_id)
			shots_this_stage = 0
			_spat = false
			_hook(sc)
			print("stage ", sc.stage_id)
		_watchdog(sc)
		_iter += 1
		if trace and _iter % 40 == 0:
			print("TRACE t=%.1f cell=%s busy=%s moving=%s path=%s cmd=%s dlg=%s" % [_t, sc.cell, sc.busy, sc.moving,
					sc._click_path, str(sc.director.current).left(80), sc.dialogue.visible])
		await _drive(sc)
	Engine.time_scale = 1.0
	_final_checks()


## If nothing changes for 40 s of game time, say exactly what the stage is doing.
func _watchdog(sc: Node) -> void:
	var cmd: Dictionary = sc.director.current
	var key := "%s|%s|%s|%s|%s|%d" % [sc.stage_id, sc.cell, sc.busy, sc.fired.size(), sc.dialogue.visible, _pending_shot.length()]
	if key != _progress_key:
		_progress_key = key
		_progress_t = _t
		_stuck_reported = false
	elif _t - _progress_t > 40.0 and not _stuck_reported:
		_stuck_reported = true
		errors.append("stuck in %s" % sc.stage_id)
		printerr("TOUR STUCK: stage=%s cell=%s busy=%s moving=%s leaving=%s fired=%s click_path=%s goal=%s next_goal=%s dialogue=%s choosing=%s cmd=%s" % [
				sc.stage_id, sc.cell, sc.busy, sc.moving, sc.leaving, sc.fired.keys(), sc._click_path, sc._click_goal,
				sc.next_goal(), sc.dialogue.visible, sc.dialogue.choosing(), str(cmd)])
		shot("stuck_%s" % sc.stage_id)


func _hook(sc: Node) -> void:
	if _hooked == sc.director:
		return
	_hooked = sc.director
	sc.director.command_started.connect(_on_command)
	sc.director.choice_shown.connect(func(opts: Array) -> void: _choice_pending = opts)


## Decide which moments get a screenshot.
func _on_command(c: Dictionary) -> void:
	if trace:
		print("CMD ", str(c).left(100))
	if shots_this_stage >= max_shots_per_stage or _pending_shot != "":
		return
	var op := Data.command_name(c)
	var delay := -1.0
	match op:
		"card":
			delay = 1.1
		"talk", "say":
			delay = 0.9
		"title_drop":
			delay = 3.0
		"slats":
			delay = 3.5
		"caption":
			if c.get("center", false) or randf() < 0.25:
				delay = 0.6
		"battle":
			delay = 2.2
	if delay > 0.0:
		_pending_shot = "%s_%02d_%s" % [scene().stage_id.substr(0, 3), shots_this_stage, op]
		_shot_at = _t + delay
		shots_this_stage += 1


func _drive(sc: Node) -> void:
	if _pending_shot != "":
		if _t >= _shot_at:
			var n := _pending_shot
			_pending_shot = ""
			await shot(n)
		return   # hold input while waiting for a screenshot
	# fights: let the command menu show, then hand over to the AI
	if sc.battle_layer.get_child_count() > 0:
		var b: Node = sc.battle_layer.get_child(0)
		if not _battle_seen.has(b):
			_battle_seen[b] = _t
			Game.auto_battle = false
		if not Game.auto_battle and _t - _battle_seen[b] > 3.0:
			if b.hud.mode == BattleHUD.Mode.COMMAND:
				await shot("%s_battle_menu" % sc.stage_id.substr(0, 3))
				if mouse and _battle_seen.size() == 1:
					await _mouse_battle_turn(sc, b)
					return
			Game.auto_battle = true
		return
	Game.auto_battle = false
	if sc.dialogue.choosing():
		await _choose(sc)
		return
	if sc.busy or sc.leaving:
		if mouse:
			if trace:
				print("DBG busy click; busy=%s leaving=%s cmd=%s" % [sc.busy, sc.leaving, str(sc.director.current).left(60)])
			await click_at(Vector2(640, 300))
		else:
			await press("ui_accept")
		await wait(0.12)
		return
	if sc.moving:
		return
	if not _menu_done and sc.stage_id == "s04_ashford" and sc.fired.size() >= 1:
		_menu_done = true
		if mouse:
			await _field_menu_mouse(sc)
		else:
			await _field_menu(sc)
		return
	if mouse:
		await _mouse_step(sc)
	else:
		await _step(sc)


func _choose(sc: Node) -> void:
	await wait(0.3)
	var opts := _choice_pending
	var target := 0
	for i in opts.size():
		if opts[i].get("defiant", false) and not opts[i].get("disabled", false) and not _spat and not nod:
			target = i
			_spat = true
	if nod:
		for i in opts.size():
			if not opts[i].get("defiant", false) and not opts[i].get("disabled", false):
				target = i
				break
	if target == 0:
		for i in opts.size():
			if not opts[i].get("disabled", false):
				target = i
				break
	if mouse:
		var list: Node = sc.dialogue._choices.get_child(0).get_child(0)
		var b: Button = list.get_child(target)
		var mm := InputEventMouseMotion.new()
		mm.position = b.get_global_rect().get_center()
		mm.global_position = mm.position
		Input.parse_input_event(mm)
		await wait(0.15)
		expect(b.has_focus(), "hovering a choice moves the cursor to it")
		await shot("%s_choice_%d" % [sc.stage_id.substr(0, 3), target])
		await click_control(b)
		await wait(0.3)
		return
	for i in target:
		await press("ui_down")
		await wait(0.1)
	await shot("%s_choice_%d" % [sc.stage_id.substr(0, 3), target])
	await press("ui_accept")
	await wait(0.3)


func _step(sc: Node) -> void:
	var goal: Vector2i = sc.next_goal()
	if goal.x < 0:
		return
	var path: Array[Vector2i] = sc.map.path(sc.cell, goal, sc._blockers())
	if path.size() < 2:
		return
	var d: Vector2i = path[1] - path[0]
	var action := "ui_right"
	if d == Vector2i.LEFT:
		action = "ui_left"
	elif d == Vector2i.UP:
		action = "ui_up"
	elif d == Vector2i.DOWN:
		action = "ui_down"
	Input.action_press(action)
	var t := 0.0
	while not sc.moving and t < 0.4:
		await wait(0.02)
		t += 0.02
	Input.action_release(action)


## Click toward the next beat: the farthest tile of the route that's on screen.
func _mouse_step(sc: Node) -> void:
	if not sc._click_path.is_empty():
		return
	var goal: Vector2i = sc.next_goal()
	if goal.x < 0:
		return
	var path: Array[Vector2i] = sc.map.path(sc.cell, goal, sc._blockers())
	if path.size() < 2:
		return
	var xf: Transform2D = sc.get_viewport().get_canvas_transform()
	var pick := path[1]
	for i in range(path.size() - 1, 0, -1):
		var p: Vector2 = xf * (Vector2(path[i]) * 64.0 + Vector2(32, 34))
		if p.x > 60 and p.x < 1220 and p.y > 60 and p.y < 470:
			pick = path[i]
			break
	if trace:
		print("DBG tour click ", pick, " at ", xf * (Vector2(pick) * 64.0 + Vector2(32, 34)), " goal ", goal, " path ", path)
	await click_at(xf * (Vector2(pick) * 64.0 + Vector2(32, 34)))
	clicks_to_walk += 1
	if clicks_to_walk == 2:
		await wait(0.25)
		await shot("%s_click_walk" % sc.stage_id.substr(0, 3))
	var t := 0.0
	while not sc.moving and t < 0.4:
		await wait(0.02)
		t += 0.02


## First fight, by mouse: click Strike, hover and click the target.
func _mouse_battle_turn(sc: Node, b: Node) -> void:
	var hud: BattleHUD = b.hud
	await click_control(hud._cmd_grid.get_node("attack"))
	await wait(0.3)
	if hud.mode == BattleHUD.Mode.TARGET:
		var target: Battler = hud._targets[hud._targets.size() - 1]
		var v: BattlerView = hud.views[target]
		var p := v.global_position - Vector2(0, v.height * 0.5)
		var mm := InputEventMouseMotion.new()
		mm.position = p
		mm.global_position = p
		Input.parse_input_event(mm)
		await wait(0.2)
		expect(hud._targets[hud._target_i] == target, "hovering an enemy aims at it")
		await shot("%s_battle_target_mouse" % sc.stage_id.substr(0, 3))
		await click_at(p)
		await wait(0.2)
		expect(hud.mode != BattleHUD.Mode.TARGET, "clicking the aimed enemy confirms the attack")
	else:
		expect(hud.mode == BattleHUD.Mode.IDLE, "a lone target is struck straight from the Strike button")


func _field_menu_mouse(sc: Node) -> void:
	Engine.time_scale = 1.0
	await click_at(Vector2(640, 300), MOUSE_BUTTON_RIGHT)
	await wait(0.5)
	expect(sc.menu.visible, "right click opens the field menu")
	await click_control(sc.menu._cmds.get_child(1))     # Status
	await wait(0.4)
	await shot("s04_field_menu_status_mouse")
	await click_at(Vector2(640, 300), MOUSE_BUTTON_RIGHT)
	await wait(0.2)
	await click_at(Vector2(640, 300), MOUSE_BUTTON_RIGHT)
	await wait(0.4)
	expect(not sc.menu.visible, "right click closes the field menu")
	Engine.time_scale = scale


func _field_menu(sc: Node) -> void:
	Engine.time_scale = 1.0
	await press("menu")
	await wait(0.5)
	await press("ui_down")                           # Status
	await press("ui_accept")
	await wait(0.4)
	await shot("s04_field_menu_status")
	await press("ui_cancel")
	await wait(0.2)
	await press("ui_cancel")
	await wait(0.4)
	expect(not sc.menu.visible, "field menu closes with cancel")
	Engine.time_scale = scale


func _final_checks() -> void:
	var seen := ", ".join(_stage_seen)
	print("stages played: ", seen)
	print("vars ", Game.vars)
	if mouse:
		print("walk clicks: ", clicks_to_walk)
		expect(clicks_to_walk > 0, "the mouse walked Derrick somewhere")
	if only_stage == "":
		expect(_stage_seen.size() == Data.act_order().size(), "all stages played (%s)" % seen)
		expect(Game.flags.get("act_one_complete", false), "Act One reaches the title drop")
		expect(Game.flags.get("trial_by_dogs", false), "the Tall Man sent for the dogs")
		expect(Game.flags.get("won_spar", false), "the spar was won")
		expect(Game.flags.get("won_dog", false), "the dog fight was won")
		var pinky := false
		for w in Game.wounds:
			if String(w["what"]).contains("pinky"):
				pinky = true
		expect(pinky, "the snapped pinky is on the scar list")
		expect(int(Game.vars.get("defiance", 0)) >= 1, "refusing to plead guilty counted as Defiance")
		print("vars ", Game.vars, "  wounds ", Game.wounds)
