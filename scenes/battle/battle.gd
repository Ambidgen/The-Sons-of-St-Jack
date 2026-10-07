extends Node2D
## Battle scene: owns a BattleRules, spawns a BattlerView per combatant, runs the
## turn loop, and turns rule events into animation.
##
## Two ways in:
##   * Standalone (F6, Battle Lab, --encounter=...): reads Router params and
##     returns to `return_to` when done.
##   * Embedded by a stage (story fights): the stage sets `embedded = true` and
##     `params`, adds it under an overlay layer and awaits `finished(outcome)`:
##     "win" | "lose" (only for lose_ok fights) | "scripted" | "fled".
## Debug: F1 auto-battle, F2 win now (or trigger the scripted end), F3 heal, F5 speed.

signal finished(outcome: String)

const ENEMY_SLOTS := {   # feet positions; keep y < 540 so the HUD never covers them
	1: [Vector2(380, 470)],
	2: [Vector2(260, 430), Vector2(500, 490)],
	3: [Vector2(200, 400), Vector2(440, 450), Vector2(260, 520)],
	4: [Vector2(180, 380), Vector2(410, 400), Vector2(220, 510), Vector2(460, 525)],
}
const PARTY_SLOTS := [Vector2(1000, 480)]

@onready var background: Sprite2D = $Background
@onready var enemy_root: Node2D = $Enemies
@onready var party_root: Node2D = $Party
@onready var hud: BattleHUD = $UI/HUD
@onready var ui_layer: CanvasLayer = $UI

var embedded := false
var params: Dictionary = {}
var rules: BattleRules
var views: Dictionary = {}           # Battler -> BattlerView
var encounter_id := ""
var return_scene := ""
var _party_snapshot: Array = []      # for "Get up" after a loss


func _ready() -> void:
	if not embedded:
		params = Router.take_params()
	encounter_id = params.get("encounter", Data.cfg("default_encounter", Data.encounters.keys()[0]))
	return_scene = params.get("return_to", "res://scenes/title/title.tscn")
	var mode_name: String = Game.turn_mode if Game.turn_mode != "" else Data.cfg("turn_mode", "atb")
	_party_snapshot = Game.party.duplicate(true)
	rules = BattleRules.for_encounter(encounter_id, TurnQueue.mode_from_string(mode_name))
	var enc: Dictionary = Data.encounters[encounter_id]
	background.texture = Data.tex(enc.get("bg", "bg/green"))
	_spawn_views()
	hud.setup(rules, views)
	_run()


func _spawn_views() -> void:
	var slots: Array = ENEMY_SLOTS.get(rules.enemies.size(), ENEMY_SLOTS[4])
	for i in rules.enemies.size():
		_add_view(rules.enemies[i], enemy_root, slots[i % slots.size()])
	for i in rules.allies.size():
		_add_view(rules.allies[i], party_root, PARTY_SLOTS[i % PARTY_SLOTS.size()])


func _add_view(b: Battler, parent: Node2D, pos: Vector2) -> void:
	var v := BattlerView.new()
	parent.add_child(v)
	v.setup(b, bool(Data.cfg("show_enemy_hp", true)))
	v.position = pos
	v.home = pos
	views[b] = v
	if not b.is_alive():
		v.die()


# ------------------------------------------------------------------ loop
func _run() -> void:
	await _intro()
	while rules.outcome() == "":
		var actor := rules.next_actor(get_process_delta_time())
		if actor == null:                       # ATB: gauges still filling
			hud.refresh_gauges()
			await get_tree().process_frame
			continue
		hud.current = actor
		hud.refresh()
		await _play(rules.begin_turn(actor))
		if not rules.can_act(actor):
			if rules.outcome() == "":
				rules.pass_turn(actor)
			continue
		var action: Dictionary
		if actor.is_ally and not Game.auto_battle:
			action = await hud.choose_action(actor)
		else:
			await get_tree().create_timer(0.35).timeout
			action = rules.ai_choose(actor)
		await _play(rules.resolve(actor, action))
		hud.current = null
		hud.refresh()
	await _finish(rules.outcome())


func _intro() -> void:
	for v in enemy_root.get_children():
		var bv := v as BattlerView
		bv.position.x = bv.home.x - 500
		create_tween().tween_property(bv, "position:x", bv.home.x, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	var enc: Dictionary = Data.encounters[encounter_id]
	await hud.show_message(enc.get("name", "Fight"), 1.2)
	await _play(rules.intro_barks())


# ------------------------------------------------------------------ events -> animation
func _play(events: Array[Dictionary]) -> void:
	if events.is_empty():
		return
	for e in events:
		var t: Battler = e.get("target")
		var v: BattlerView = views.get(t) if t else null
		match e["type"]:
			"use":
				var user: Battler = e["actor"]
				var d: Dictionary = e["def"]
				if d.has("narrate") and user.is_ally:   # a move with prose of its own
					await hud.show_message(d["narrate"], 1.2 + d["narrate"].length() / 40.0)
				hud.set_help(("%s: %s" % [user.display_name, e["name"]]) if not (e["name"] in ["Strike", ""]) else "")
				if d.get("kind") in ["physical", "fixed"]:
					await views[user].lunge()
				else:
					await views[user].cast(Color("#e9dfc7"))
			"damage":
				v.flash()
				v.shake(12.0 if e.get("crit", false) else 6.0)
				var text := str(e["amount"])
				var color := Color("#f4efe1")
				if e.get("crit", false):
					text += "!"
					color = UIStyle.ATB
				if e.has("status"):
					color = UIStyle.HP_LOW
				v.popup(text, color, 40 if e.get("crit", false) else 32)
				await _wait(0.28)
			"maim":
				v.flash(Color(3, 0.4, 0.3))
				v.popup("MAIMED", UIStyle.HP_LOW, 26, 0.2, 1.05)
				await _wait(0.6)
			"heal":
				v.popup("+%d" % e["amount"], Color("#9fd08a"), 30)
				await _wait(0.25)
			"mp":
				v.popup("+%d grit" % e["amount"], UIStyle.MP, 24)
				await _wait(0.25)
			"miss":
				v.popup(e.get("text", "Missed"), Color("#c0b8a0"), 24)
				await _wait(0.28)
			"evade":
				v.sidestep()
				v.popup(e.get("text", "Evaded"), UIStyle.PAPER, 26)
				await _wait(0.45)
			"status_on":
				v.popup(Data.statuses[e["status"]]["name"], Color("#e0a080"), 22, 0.3, 1.0)
				await _wait(0.2)
			"status_off":
				if e["status"] != "guard":
					v.popup(Data.statuses[e["status"]]["name"] + " fades", Color("#a8987a"), 18, 0.3, 1.0)
			"skip":
				v.popup("Reeling", Color("#e9dfc7"), 24)
				await _wait(0.4)
			"yield":
				v.yield_pose()
				var yt: String = e.get("text", "Yields!")
				await hud.show_message(yt, 1.2 + yt.length() / 40.0)
			"ko":
				v.die()
				await _wait(0.3)
			"revive":
				v.revive()
				v.popup("+%d" % e["amount"], UIStyle.HP, 30)
				await _wait(0.25)
			"bark":
				await hud.bark(e["who"], e["text"])
			"scripted":
				await _wait(0.8)
			"flee":
				await hud.show_message("He runs.", 0.8)
			"flee_fail":
				await hud.show_message(e.get("text", "Can't get away!"), 0.9)
		hud.refresh()
	await _wait(0.3)
	hud.set_help("")


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


# ------------------------------------------------------------------ end
func _finish(result: String) -> void:
	var enc: Dictionary = Data.encounters[encounter_id]
	var derrick: Battler = rules.allies[0]
	for b in rules.allies:              # write HP/grit back to Derrick
		b.member["hp"] = maxi(b.hp, 1)
		b.member["mp"] = b.mp
	var wound_lines: Array[String] = []
	if result != "lose" or enc.get("lose_ok", false):
		for i in derrick.new_wounds:
			var by: String = derrick.wound_by if derrick.wound_by != "" else "a blow"
			Game.add_wound(enc.get("wound_text", "A wound from %s" % by))
			wound_lines.append("A wound that will not close. (%s)" % enc.get("wound_text", by))
	match result:
		"win":
			var rw := rules.rewards()
			var lines: Array[String] = []
			for l in enc.get("win_text", []):
				lines.append(l)
			for item in rw["drops"]:
				Game.add_item(item, rw["drops"][item])
				lines.append("Took: %s x%d" % [Data.items[item]["name"], rw["drops"][item]])
			lines.append_array(wound_lines)
			lines.append_array(Game.gain_exp(int(rw["exp"])))
			Game.flags["won_" + encounter_id] = true
			if not lines.is_empty() or not enc.get("quiet_win", false):
				await hud.show_results(enc.get("win_title", "He is still standing."), lines)
			_leave("win")
		"fled":
			_leave("fled")
		"scripted":
			await get_tree().create_timer(0.6).timeout
			_leave("scripted")
		"lose":
			if enc.get("lose_ok", false):
				var lines: Array[String] = []
				for l in enc.get("lose_text", []):
					lines.append(l)
				lines.append_array(wound_lines)
				if not lines.is_empty() or not enc.get("quiet_win", false):
					await hud.show_results(enc.get("lose_title", "He goes down."), lines, UIStyle.HP_LOW)
				_leave("lose")
				return
			var pick := await hud.ask("Derrick does not get up.", ["Get up", "Return to title"] as Array[String])
			Game.party.assign(_party_snapshot)
			if pick == "Get up":
				_leave("retry")
			else:
				_leave("title")


func _leave(outcome: String) -> void:
	if embedded:
		finished.emit(outcome)
		return
	match outcome:
		"retry":
			Router.goto(scene_file_path, params)
		"title":
			Router.goto("res://scenes/title/title.tscn")
		_:
			Router.goto(return_scene)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_F2:  # win now (or trigger the scripted ending)
			hud.force({"kind": "debug_win"})
		KEY_F3:  # full heal
			for b in rules.living(rules.allies):
				b.hp = b.max_hp()
				b.mp = b.max_mp()
			hud.refresh()
