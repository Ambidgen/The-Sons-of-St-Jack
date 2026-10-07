extends Node
## Headless checks. Run:  godot --headless --path . res://tests/smoke.tscn
## Exit code 0 = pass. Prints the balance table (each fight at the age Derrick
## meets it) and the Act One pacing report. Runtime SCRIPT ERRORs do not change
## the exit code -- always grep the log too.

## Which stage (and so which Derrick) each encounter belongs to.
const ENCOUNTER_STAGE := {"spar": "s01_harrowgate", "dog": "s05_butchers_steps", "ostry": "s06_ostry_farm",
		"looter": "s08_wendmere", "wolves": "s10_thornwake", "alley": "s12_st_ordrics", "hopeless": "s12_st_ordrics"}

var failures: Array[String] = []


func _ready() -> void:
	_check_data()
	_check_rigs()
	_check_levels()
	_check_scenes()
	_check_rules()
	_check_story_rules()
	_check_save_roundtrip()
	_check_linearity()
	_balance_table()
	_pacing_report()
	if failures.is_empty():
		print("SMOKE OK")
		get_tree().quit(0)
	else:
		for f in failures:
			printerr("FAIL: ", f)
		get_tree().quit(1)


func _check_data() -> void:
	for e in Data.validate():
		failures.append("data: " + e)
	# "wait" is also a modifier; it must never shadow the real command.
	for c in [{"show": "x", "wait": false}, {"tint": "#000", "wait": true}, {"zoom": 1.3, "wait": true}]:
		if Data.command_name(c) == "wait":
			failures.append("command_name read %s as 'wait'" % str(c))
	if Data.command_name({"wait": 1.0}) != "wait":
		failures.append("plain wait not recognised")


## Every body the game moves must be an articulated rig, and every rig must be sound.
func _check_rigs() -> void:
	var keys := {}
	for id in Data.actors:
		for form in Data.actors[id].get("forms", {}):
			for k in ["sprite", "field"]:
				keys[Data.actors[id]["forms"][form][k]] = "actor %s" % id
	for id in Data.enemies:
		keys[Data.enemies[id]["sprite"]] = "enemy %s" % id
	for id in Data.cast:
		keys[Data.cast[id].get("field", "")] = "cast %s" % id
	for sid in Data.stages:
		var st: Dictionary = Data.stages[sid]
		for letter in st.get("cast", {}):
			if st["cast"][letter].has("art"):
				keys[st["cast"][letter]["art"]] = "stage %s cast" % sid
		for script_id in st.get("scripts", {}):
			for c in st["scripts"][script_id]:
				if c is Dictionary and c.has("pose") and c.get("art", "") != "":
					keys[c["art"]] = "stage %s pose" % sid
	for k in keys:
		var living: bool = k.begins_with("char/") or k in ["prop/horse", "prop/crow"]   # props stay props
		if k == "" or not living:
			continue
		if not Rig.has_rig(k):
			failures.append("%s: %s has no articulated rig" % [keys[k], k])
	for name in Rig.db():
		var d: Dictionary = Rig.db()[name]
		if not Data._has_art(d["sheet"]):
			failures.append("rig %s: missing sheet %s" % [name, d["sheet"]])
		var seen := {"": true}
		for b in d["bones"]:
			if not seen.has(b[1]):
				failures.append("rig %s: bone %s hangs from %s, which comes later or not at all" % [name, b[0], b[1]])
			seen[b[0]] = true
		for part in d["cells"]:
			if not seen.has(part):
				failures.append("rig %s: part %s has no bone" % [name, part])
		if d["kind"] == "biped" and not (d["cells"].has("arm_l") and d["cells"].has("arm_r") and d["cells"].has("head")):
			failures.append("rig %s: a person without arms or a head" % name)
	if Rig.db().size() < 80:
		failures.append("only %d rigs in rigs.json" % Rig.db().size())


## Level stages: the pixel detection must give every stage a playable shape. The
## start stands on open ground, the exit and every beat's line exist, there is
## real road to follow, the walkable area stays a corridor (no sandbox), and what
## the stage places (cast, props) sits inside the painting.
func _check_levels() -> void:
	var lines: Array[String] = []
	for id in Data.act_order():
		var st: Dictionary = Data.stages[id]
		if not st.has("level"):
			continue
		var m := StageMap.new(st)
		if m.sense == null:
			failures.append("%s: level art did not load" % id)
			continue
		if not m.open_ground(m.start):
			failures.append("%s: start %s is not on open ground" % [id, m.start])
		if st.has("exit") and not st["exit"].is_empty() and m.exits.is_empty():
			failures.append("%s: exit %s covers no open ground" % [id, st["exit"]])
		for k in m.triggers:
			if m.triggers[k].is_empty():
				failures.append("%s: line %s (%s) covers no open ground" % [id, k, st["triggers"].get(k, "")])
		var walk := m.sense.walk_count
		var road := m.sense.road_count
		if road * 4 < walk:
			failures.append("%s: only %d of %d walkable tiles are road" % [id, road, walk])
		if walk > m.w * m.h * 0.45:
			failures.append("%s: %d of %d tiles walkable -- too open for a linear stage" % [id, walk, m.w * m.h])
		for letter in st.get("cast", {}):
			var at: Array = st["cast"][letter].get("at", [])
			if not at.is_empty() and not m.in_bounds(Vector2i(int(at[0]), int(at[1]))):
				failures.append("%s: cast %s at %s is outside the painting" % [id, letter, at])
		for c in m.prop_cells:
			if not m.in_bounds(c):
				failures.append("%s: prop at %s is outside the painting" % [id, c])
		lines.append("%-22s %-18s %2dx%-2d  walkable %3d  road %3d  %4d ms" % [id, st["level"]["art"], m.w, m.h, walk, road, m.sense.ms])
	print("--- pixel detection ---")
	for l in lines:
		print(l)


func _check_scenes() -> void:
	for path in ["res://scenes/title/title.tscn", "res://scenes/stage/stage.tscn", "res://scenes/battle/battle.tscn"]:
		var packed: PackedScene = load(path)
		if packed == null or not packed.can_instantiate():
			failures.append("scene does not load: " + path)
	# every script must compile (a broken one still lets its scene "load")
	for dir in ["res://autoload", "res://battle", "res://scenes/actor", "res://scenes/battle", "res://scenes/stage",
			"res://scenes/title", "res://ui", "res://tests"]:
		for file in DirAccess.get_files_at(dir):
			if file.ends_with(".gd"):
				var s: Script = load(dir + "/" + file)
				if s == null or not s.can_instantiate():
					failures.append("script does not compile: %s/%s" % [dir, file])


func _grow_for(enc: String) -> void:
	var st: Dictionary = Data.stages[ENCOUNTER_STAGE.get(enc, "s12_st_ordrics")]
	Game.wounds = []
	Game.set_growth(st["derrick"]["form"], int(st["derrick"]["level"]))
	Game.inventory = {"rag": 1}


func _check_rules() -> void:
	var enc: String = Data.cfg("default_encounter", "dog")
	_grow_for(enc)
	for mode in [TurnQueue.Mode.CTB, TurnQueue.Mode.ROUND, TurnQueue.Mode.ATB]:
		var r := BattleRules.for_encounter(enc, mode, true, 7)
		var order := r.queue.preview(6)
		if mode != TurnQueue.Mode.ATB and order.size() != 6:
			failures.append("preview size %d in mode %d" % [order.size(), mode])
		var s := BattleSim.run(enc, 20, mode)
		if s["avg_turns"] <= 0:
			failures.append("sim produced no turns in mode %d" % mode)
	var r2 := BattleRules.for_encounter(enc, TurnQueue.Mode.CTB, true, 1)
	var hit := r2.calc_damage(r2.allies[0], r2.enemies[0], Data.skills["attack"])
	if hit["amount"] < 1:
		failures.append("attack did %d damage" % hit["amount"])


func _check_story_rules() -> void:
	# Maiming: one heavy blow leaves a wound; a light one doesn't.
	_grow_for("dog")
	var r := BattleRules.for_encounter("dog", TurnQueue.Mode.CTB, true, 3)
	var derrick: Battler = r.allies[0]
	var ev := r._apply_damage(derrick, int(derrick.max_hp() * 0.1), {})
	if _has(ev, "maim"):
		failures.append("a 10% hit maimed")
	ev = r._apply_damage(derrick, int(ceil(derrick.max_hp() * 0.45)), {"by": "test"})
	if not _has(ev, "maim") or derrick.new_wounds != 1:
		failures.append("a 45% hit did not maim")
	# Wounds are permanent: max HP drops after one is recorded.
	var before: int = Game.stats_of(Game.hero())["hp"]
	Game.add_wound("test wound")
	if Game.stats_of(Game.hero())["hp"] >= before:
		failures.append("a wound did not lower max HP")
	Game.wounds = []
	# Healing is halved.
	derrick.hp = 1
	var heal := r._heal(derrick, 40)
	if int(heal[0]["amount"]) != int(round(40 * float(Data.cfg("heal_mult", 0.5)))):
		failures.append("healing not scaled by heal_mult (got %d)" % heal[0]["amount"])
	# Yield: the sparring partner stops before he's hurt, and that's a win.
	_grow_for("spar")
	r = BattleRules.for_encounter("spar", TurnQueue.Mode.CTB, true, 3)
	var g: Battler = r.enemies[0]
	ev = r._apply_damage(g, int(g.max_hp() * 0.6), {})
	if not _has(ev, "yield") or r.outcome() != "win":
		failures.append("sparring partner did not yield (outcome %s)" % r.outcome())
	# Jack's Impunity: every blow is evaded, and the fight ends as a story beat.
	_grow_for("hopeless")
	r = BattleRules.for_encounter("hopeless", TurnQueue.Mode.CTB, true, 3)
	derrick = r.allies[0]
	var evaded := 0
	for i in 3:
		ev = r.resolve(derrick, {"kind": "skill", "id": "attack", "targets": [r.enemies[i % 2]]})
		if _has(ev, "evade"):
			evaded += 1
	if evaded != 3:
		failures.append("impunity: %d/3 attacks evaded" % evaded)
	if r.outcome() != "scripted":
		failures.append("hopeless fight ended '%s', expected 'scripted'" % r.outcome())
	if derrick.new_wounds != 0:
		failures.append("the scripted put-down left a wound (Jack says nothing is broken)")
	r = BattleRules.for_encounter("hopeless", TurnQueue.Mode.CTB, true, 4)
	r.resolve(r.allies[0], {"kind": "flee"})
	if r.outcome() != "scripted":
		failures.append("running from the hopeless fight did not end it")
	var s := BattleSim.run("hopeless", 50)
	if s["scripted_rate"] < 1.0:
		failures.append("hopeless fight: only %d%% scripted endings in the sim" % int(s["scripted_rate"] * 100))
	_check_alley()


## Coldharbour: one move. Only the man at his arm can be hit; the headbutt drops
## him, and then an unseen fist ends the fight in a blackout.
func _check_alley() -> void:
	_grow_for("alley")
	var r := BattleRules.for_encounter("alley", TurnQueue.Mode.CTB, true, 5)
	var derrick: Battler = r.allies[0]
	if r.attack_id != "headbutt" or not derrick.skills.is_empty():
		failures.append("alley: attack should be Headbutt and no other skills")
	var targets := r.candidates(derrick, Data.skills["headbutt"])
	if targets.size() != 1 or targets[0].key != "grabber":
		failures.append("alley: only the man at his arm should be targetable (got %d)" % targets.size())
	r.resolve(derrick, {"kind": "flee"})
	if r.outcome() != "":
		failures.append("alley: running ended the fight (%s)" % r.outcome())
	var ev := r.resolve(derrick, {"kind": "skill", "id": "headbutt", "targets": [r.enemies[1]]})  # aims at the bearded man
	if not _has(ev, "yield"):
		failures.append("alley: the headbutt did not drop the man at his arm")
	if r.outcome() != "scripted" or derrick.new_wounds != 0:
		failures.append("alley: expected a scripted blackout with no wound (got %s)" % r.outcome())
	if not Data.encounters["alley"].get("end_black", false):
		failures.append("alley: should end in black")


func _has(events: Array[Dictionary], type: String) -> bool:
	for e in events:
		if e["type"] == type:
			return true
	return false


func _check_save_roundtrip() -> void:
	Game.new_game()
	Game.add_wound("Bitten, for the test")
	Game.add_var("complicity", 2)
	var before := JSON.stringify(Game.to_dict())
	if not Game.save_game() or not Game.load_game():
		failures.append("save/load failed")
	elif JSON.stringify(Game.to_dict()) != before:
		failures.append("save/load changed state:\n%s\n%s" % [before, JSON.stringify(Game.to_dict())])
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Game.SAVE_PATH))
	Game.new_game()


## No sandbox: every beat must stand between Derrick and the way out.
func _check_linearity() -> void:
	for id in Data.act_order():
		var r := Pacing.analyze(Data.stages[id], 5)
		for p in r["problems"]:
			if not String(p).contains("walking with nothing"):
				failures.append("stage %s: %s" % [id, p])


func _balance_table() -> void:
	var mode := TurnQueue.mode_from_string(Data.cfg("turn_mode", "atb"))
	print("--- balance (each fight at Derrick's age for it, 200 sims, %s) ---" % Data.cfg("turn_mode", "atb"))
	for enc in Data.encounters:
		_grow_for(enc)
		print(BattleSim.report(BattleSim.run(enc, 200, mode)))
	Game.new_game()


func _pacing_report() -> void:
	print("--- Act One pacing ---")
	var total := 0.0
	for r in Pacing.analyze_all(40):
		print(Pacing.report(r))
		total += r["total_sec"]
	print("Act One total: %s" % Pacing.clock(total))
