extends Node
## The corners a straight playthrough never visits. Needs a renderer for the
## mouse (positions come from the camera):
##   xvfb-run -a godot --path . --rendering-driver opengl3 res://tests/edge.tscn
##  1. Mouse on a stage: click-walk, a click on water, keys cancelling a click-walk,
##     right-click menu, click-to-talk (on the head as well as the feet), the
##     pointing hand, clicks during a cutscene not moving him, hold-to-steer.
##  2. Losing a story fight, clicking "Get up", and winning the retry.
##  3. Battle mouse: right click backs out of aiming; clicking an enemy at the
##     command menu strikes it.
##  4. Continue from the title, and Chapter Select, by mouse.

var errors: Array[String] = []
var checks := 0


func _ready() -> void:
	reparent.call_deferred(get_tree().root)
	await wait(0.3)
	Engine.time_scale = 2.0
	await _mouse_on_stage()
	await _lose_and_get_up()
	await _title_by_mouse()
	Engine.time_scale = 1.0
	print("EDGE DONE checks=%d errors=%s" % [checks, errors])
	get_tree().quit(0 if errors.is_empty() else 1)


# ------------------------------------------------------------------ helpers
func wait(s: float) -> void:
	await get_tree().create_timer(s, true, false, true).timeout


func expect(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		errors.append(what)
		printerr("EDGE EXPECT FAILED: ", what)
	else:
		print("  ok: ", what)


func press(action: String, hold := 0.05) -> void:
	var down := InputEventAction.new()
	down.action = action
	down.pressed = true
	Input.parse_input_event(down)
	await wait(hold)
	var up := InputEventAction.new()
	up.action = action
	up.pressed = false
	Input.parse_input_event(up)


func move_mouse(p: Vector2) -> void:
	var mm := InputEventMouseMotion.new()
	mm.position = p
	mm.global_position = p
	Input.parse_input_event(mm)
	await wait(0.05)


func mouse_button(p: Vector2, down: bool, button := MOUSE_BUTTON_LEFT) -> void:
	var e := InputEventMouseButton.new()
	e.button_index = button
	e.pressed = down
	e.button_mask = (MOUSE_BUTTON_MASK_LEFT if button == MOUSE_BUTTON_LEFT else MOUSE_BUTTON_MASK_RIGHT) if down else 0
	e.position = p
	e.global_position = p
	Input.parse_input_event(e)


func click_at(p: Vector2, button := MOUSE_BUTTON_LEFT) -> void:
	await move_mouse(p)
	mouse_button(p, true, button)
	await wait(0.05)
	mouse_button(p, false, button)
	await wait(0.05)


func screen_of(sc: Node, c: Vector2i, y := 40.0) -> Vector2:
	return sc.get_viewport().get_canvas_transform() * (Vector2(c) * 64.0 + Vector2(32, y))


func click_cell(sc: Node, c: Vector2i, button := MOUSE_BUTTON_LEFT) -> void:
	await click_at(screen_of(sc, c), button)


func scene() -> Node:
	return get_tree().current_scene


func wait_for(cond: Callable, timeout := 20.0) -> bool:
	var t := 0.0
	while not cond.call():
		await wait(0.05)
		t += 0.05 * Engine.time_scale
		if t > timeout:
			return false
	return true


func open_stage(id: String) -> Node:
	Game.new_game()
	Game.stage_id = id
	print("  goto ", id)
	Router.goto("res://scenes/stage/stage.tscn", {"stage": id, "fresh": true}, 0.1)
	print("  waiting for the stage")
	var ok := await wait_for(func() -> bool: return scene() != null and scene().name == "Stage" and scene().stage_id == id)
	print("  stage up: ", ok, " ", scene())
	var sc := scene()
	await wait(0.4)
	return sc


## Click through whatever script is running until Derrick is free.
func settle(sc: Node) -> void:
	var guard := 0
	while (sc.busy or sc.moving) and guard < 400:
		guard += 1
		if sc.busy and not sc.dialogue.choosing():
			await press("ui_accept")
		await wait(0.1)


# ------------------------------------------------------------------ 1. stage mouse
func _mouse_on_stage() -> void:
	print("-- mouse on a stage (Harrowgate)")
	var sc := await open_stage("s01_harrowgate")
	print("  stage open, settling")
	await settle(sc)
	print("  settled at ", sc.cell)
	for k in sc.map.triggers:      # mouse mechanics only: keep the story's beats out of the way
		sc.fired[k] = true
	var start: Vector2i = sc.cell
	# a plain click-walk
	await click_cell(sc, start + Vector2i(4, 0))
	await wait_for(func() -> bool: return not sc.moving and sc._click_path.is_empty())
	await wait(0.2)
	expect(sc.cell == start + Vector2i(4, 0), "click-walk arrives on the clicked tile (at %s)" % sc.cell)
	# the walk animates the rig
	await click_cell(sc, sc.cell + Vector2i(-2, 0))
	var walked := await wait_for(func() -> bool: return sc.rig(sc.player).is_walking(), 3.0)
	expect(walked, "Derrick's rig plays its walk cycle while he moves")
	await wait_for(func() -> bool: return not sc.moving and sc._click_path.is_empty())
	# the hedge is not ground (the pixel detection says so): he stops at its edge
	var hedge := Vector2i(4, 4)
	expect(sc.map.terrain_solid(hedge) and not sc.map.terrain_solid(Vector2i(4, 5)), "the painted hedge reads as solid, the verge below it as ground")
	await click_cell(sc, hedge)
	await wait_for(func() -> bool: return not sc.moving and sc._click_path.is_empty())
	await wait(0.2)
	expect(sc.cell != hedge and Vector2(sc.cell - hedge).length() <= 1.5, "clicking the hedge walks to its edge (at %s)" % sc.cell)
	# keys take over from a click-walk at once
	await click_cell(sc, Vector2i(9, 7))
	await wait(0.1)
	Input.action_press("ui_up")
	await wait(0.12)
	Input.action_release("ui_up")
	await wait_for(func() -> bool: return not sc.moving)
	await wait(0.3)
	expect(sc._click_path.is_empty() and sc.cell != Vector2i(9, 7), "a key press cancels the click-walk")
	# right click: the field menu, and right click again to close it
	await click_at(Vector2(640, 300), MOUSE_BUTTON_RIGHT)
	await wait(0.3)
	expect(sc.menu.visible, "right click opens the field menu")
	await click_at(Vector2(640, 300), MOUSE_BUTTON_RIGHT)
	await wait(0.3)
	expect(not sc.menu.visible, "right click closes it")
	await wait_for(func() -> bool: return not sc.busy)
	# click-to-talk: give a child something to say and click her head
	sc.teleport("kid_a", Vector2i(8, 5))
	sc.cast_hidden.erase("kid_a")
	sc.node_of("kid_a").visible = true
	sc.stage["scripts"]["edge_talk"] = [{"say": "kid_a", "text": "You're it."}]
	sc.cast_defs["kid_a"]["talk"] = "edge_talk"
	await move_mouse(screen_of(sc, Vector2i(8, 4), 50))
	await wait(0.15)
	expect(sc._pointing, "the pointer turns to a hand over someone to talk to")
	expect(sc._hover.visible and sc._hover.color == TileCursor.TALK, "the tile under her is marked gold")
	await click_cell(sc, Vector2i(8, 4))   # her head, one tile above her feet
	var talked := await wait_for(func() -> bool: return sc.dialogue.visible, 10.0)
	expect(talked, "clicking someone walks up to them and starts the conversation")
	expect((sc.cell - Vector2i(8, 5)).length_squared() == 1, "he stopped beside her (at %s)" % sc.cell)
	await settle(sc)
	sc.cast_defs["kid_a"].erase("talk")
	# clicks during a cutscene don't move him
	sc.fired["e"] = true
	sc.run_script("summer_kids")
	await wait(0.3)
	var held_at: Vector2i = sc.cell
	for i in 4:
		await click_cell(sc, held_at + Vector2i(0, 1))
		await wait(0.2)
	expect(sc.cell == held_at and sc._click_path.is_empty(), "clicks during a scene advance it and never walk him")
	await settle(sc)
	# hold to steer: press, drag two tiles down-left, keep holding
	var from: Vector2i = sc.cell
	var p1 := screen_of(sc, from + Vector2i(3, 0))
	await move_mouse(p1)
	mouse_button(p1, true)
	await wait(0.25)
	var p2 := screen_of(sc, from + Vector2i(1, 2))
	await move_mouse(p2)
	await wait(1.6)
	mouse_button(p2, false)
	await wait_for(func() -> bool: return not sc.moving and sc._click_path.is_empty())
	expect(sc.cell == from + Vector2i(1, 2) or (sc.cell - (from + Vector2i(1, 2))).length_squared() <= 1,
			"holding the button steers him to where the pointer went (at %s, wanted %s)" % [sc.cell, from + Vector2i(1, 2)])


# ------------------------------------------------------------------ 2+3. losing, battle mouse
func _lose_and_get_up() -> void:
	print("-- losing a story fight and getting up (Ashford)")
	var sc := await open_stage("s04_ashford")
	await settle(sc)
	# field menu by mouse: use a heel of bread on a hungry boy
	Game.inventory["bread"] = 2
	var hero: Dictionary = Game.hero()
	hero["hp"] = 10
	await click_at(Vector2(640, 300), MOUSE_BUTTON_RIGHT)
	await wait(0.4)
	await click_at(_find_button(sc.menu, "Items").get_global_rect().get_center())
	await wait(0.3)
	var bread_btn := _find_button(sc.menu, Data.items["bread"]["name"])
	expect(bread_btn != null, "the field menu lists the bread")
	if bread_btn:
		await click_at(bread_btn.get_global_rect().get_center())
		await wait(0.3)
		var healed := 10 + int(40 * float(Data.cfg("heal_mult", 0.5)))
		expect(int(hero["hp"]) == mini(healed, Game.stats_of(hero)["hp"]), "bread heals half its worth (hp %d)" % hero["hp"])
		expect(int(Game.inventory.get("bread", 0)) == 1, "and is eaten")
	await click_at(Vector2(640, 300), MOUSE_BUTTON_RIGHT)
	await wait(0.2)
	await click_at(Vector2(640, 300), MOUSE_BUTTON_RIGHT)
	await wait(0.4)
	expect(not sc.menu.visible and not sc.busy, "two right clicks put the menu away")
	Game.heal_party()
	var result := [""]
	var run := func() -> void: result[0] = await sc.run_battle("dog")
	run.call()
	var ok := await wait_for(func() -> bool: return (sc.battle_layer.get_child_count() > 0
			and sc.battle_layer.get_child(0).hud.mode == BattleHUD.Mode.COMMAND), 30.0)
	expect(ok, "the dog fight opens to the command menu")
	if not ok:
		return
	var b: Node = sc.battle_layer.get_child(0)
	var hud: BattleHUD = b.hud
	# battle mouse: Strike, then right click backs out of aiming
	await click_at(hud._cmd_grid.get_node("attack").get_global_rect().get_center())
	await wait(0.2)
	expect(hud.mode == BattleHUD.Mode.TARGET, "clicking Strike starts aiming")
	await click_at(Vector2(640, 420), MOUSE_BUTTON_RIGHT)
	await wait(0.2)
	expect(hud.mode == BattleHUD.Mode.COMMAND, "right click backs out of aiming")
	# now lose on purpose: one hit point left, and let the dog have the next turn
	b.rules.allies[0].hp = 1
	hud.refresh()
	var dog: Battler = b.rules.enemies[0]
	var dv: BattlerView = hud.views[dog]
	await click_at(dv.global_position - Vector2(0, dv.height * 0.5))   # click the dog: strike it
	await wait(0.3)
	expect(hud.mode == BattleHUD.Mode.IDLE, "clicking an enemy at the command menu strikes it")
	Game.auto_battle = true
	await wait_for(func() -> bool: return b.rules.allies[0].hp <= 0, 60.0)
	Game.auto_battle = false
	var asked := await wait_for(func() -> bool: return _find_button(hud, "Get up") != null, 30.0)
	expect(asked, "losing asks whether Derrick gets up")
	if not asked:
		return
	await wait(0.4)      # the panel centres itself a frame after it appears
	await click_at(_find_button(hud, "Get up").get_global_rect().get_center())
	var old_id := b.get_instance_id()
	var again := await wait_for(func() -> bool: return (sc.battle_layer.get_child_count() > 0
			and sc.battle_layer.get_child(sc.battle_layer.get_child_count() - 1).get_instance_id() != old_id), 20.0)
	expect(again, "Get up starts the fight again")
	var b2: Node = sc.battle_layer.get_child(sc.battle_layer.get_child_count() - 1) if sc.battle_layer.get_child_count() > 0 else null
	if b2:
		expect(b2.rules.allies[0].hp == b2.rules.allies[0].max_hp(), "he gets up with the HP he went in with")
		b2.rules.enemies[0].hp = 1      # make the rematch quick
	Game.auto_battle = true
	await wait_for(func() -> bool: return result[0] != "", 90.0)
	Game.auto_battle = false
	expect(result[0] == "win", "the retry can be won (outcome '%s')" % result[0])


func _find_button(root: Node, text: String) -> Button:
	for c in root.get_children():
		if c is Button and c.text == text and c.is_visible_in_tree():
			return c
		var f := _find_button(c, text)
		if f:
			return f
	return null


# ------------------------------------------------------------------ 4. title
func _title_by_mouse() -> void:
	print("-- the title screen by mouse")
	Game.new_game()
	Game.stage_id = "s08_wendmere"
	Game.save_game()
	Router.goto("res://scenes/title/title.tscn", {}, 0.1)
	await wait_for(func() -> bool: return scene() != null and scene().name == "Title")
	await wait(0.5)
	var cont := _find_button(scene(), "Continue")
	expect(cont != null and not cont.disabled, "Continue is offered when there's a save")
	await move_mouse(cont.get_global_rect().get_center())
	await wait(0.1)
	expect(cont.has_focus(), "hovering a title button moves the menu cursor to it")
	await click_at(cont.get_global_rect().get_center())
	var loaded := await wait_for(func() -> bool: return scene() != null and scene().name == "Stage")
	expect(loaded and scene().stage_id == "s08_wendmere", "Continue loads the saved chapter")
	Router.goto("res://scenes/title/title.tscn", {}, 0.1)
	await wait_for(func() -> bool: return scene() != null and scene().name == "Title")
	await wait(0.5)
	await click_at(_find_button(scene(), "Chapter Select").get_global_rect().get_center())
	await wait(0.3)
	var ch := _find_button(scene(), Data.stages["s09_coldharbour_road"]["chapter"])
	expect(ch != null, "the chapter list shows the Coldharbour road")
	if ch:
		await click_at(ch.get_global_rect().get_center())
		var jumped := await wait_for(func() -> bool: return scene() != null and scene().name == "Stage")
		expect(jumped and scene().stage_id == "s09_coldharbour_road" and Game.form == "man", "Chapter Select starts that chapter at that age")
	# the Battle Lab: fight from the title, come back to the title
	Router.goto("res://scenes/title/title.tscn", {}, 0.1)
	await wait_for(func() -> bool: return scene() != null and scene().name == "Title")
	await wait(0.5)
	await click_at(_find_button(scene(), "Battle Lab").get_global_rect().get_center())
	await wait(0.3)
	var lab_fight := _find_button(scene(), Data.encounters["wolves"]["name"])
	expect(lab_fight != null, "the Battle Lab lists the wolves")
	if lab_fight:
		await click_at(lab_fight.get_global_rect().get_center())
		var in_fight := await wait_for(func() -> bool: return scene() != null and scene().name == "Battle")
		expect(in_fight, "a Battle Lab fight starts")
		Game.auto_battle = true
		var back := await wait_for(func() -> bool: return scene() != null and scene().name == "Title", 120.0)
		Game.auto_battle = false
		expect(back, "and returns to the title when it's over")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.SAVE_PATH))
