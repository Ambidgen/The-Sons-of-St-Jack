extends Node
## Mutable run state: Derrick (a party of one), his age/form, the wounds he
## carries across the years, inventory, story flags, Complicity/Defiance, and
## the current stage. Checkpoints save at the start of every stage.

const SAVE_PATH := "user://save.json"
const STATS := ["hp", "mp", "atk", "def", "mag", "res", "spd"]

var party: Array[Dictionary] = []      # {id, level, exp, hp, mp}
var form := "child"                    # which drawing of Derrick: tot | small | child | youth | lad | man
var wounds: Array = []                 # [{"what": "Mauled by a starving dog", "where": "Ashford"}]
var inventory: Dictionary = {}         # item_id -> qty
var gold := 0
var flags: Dictionary = {}
var vars: Dictionary = {"complicity": 0, "defiance": 0}
var stage_id := ""
var known_affinity: Dictionary = {}

# Session settings (not saved)
var auto_battle := false
var turn_mode := ""                    # "" = use config.turn_mode


func _ready() -> void:
	_bind_inputs()
	if party.is_empty():
		new_game()


func new_game() -> void:
	var start: Dictionary = Data.cfg("start", {})
	party.clear()
	for id in start.get("party", []):
		var m := {"id": id, "level": 1, "exp": 0, "hp": 0, "mp": 0}
		party.append(m)
	form = start.get("form", "child")
	wounds = []
	inventory = {}
	for k in start.get("items", {}):
		inventory[k] = int(start["items"][k])  # JSON numbers arrive as floats
	gold = int(start.get("gold", 0))
	flags = {}
	vars = {"complicity": 0, "defiance": 0}
	known_affinity = {}
	stage_id = Data.act_order()[0] if not Data.act_order().is_empty() else ""
	heal_party()


func hero() -> Dictionary:
	return party[0]


## Art for a party member in Derrick's current form: "sprite" | "field" | "portrait".
func actor_art(member: Dictionary, key: String) -> String:
	var a: Dictionary = Data.actors[member["id"]]
	var forms: Dictionary = a.get("forms", {})
	if forms.has(form):
		return forms[form].get(key, "")
	if not forms.is_empty():
		return forms.values()[0].get(key, "")
	return a.get(key, "")


## How big Derrick is drawn in his current form (the little ones share the child drawing).
func actor_scale() -> float:
	var forms: Dictionary = Data.actors[party[0]["id"]].get("forms", {})
	return float(forms.get(form, {}).get("scale", 1.0))


## Max stats: base + growth * (level - 1), then permanent wounds bite into them.
func stats_of(member: Dictionary) -> Dictionary:
	var a: Dictionary = Data.actors[member["id"]]
	var out := {}
	var w := wounds.size() if (not party.is_empty() and member["id"] == party[0]["id"]) else 0
	var hp_loss := float(Data.cfg("wound_max_hp", 0.08))
	var atk_loss := float(Data.cfg("wound_atk", 0.05))
	for s in STATS:
		var v: float = a["stats"][s] + a.get("growth", {}).get(s, 0.0) * (member["level"] - 1)
		if s == "hp":
			v *= maxf(0.4, 1.0 - hp_loss * w)
		elif s == "atk":
			v *= maxf(0.5, 1.0 - atk_loss * w)
		out[s] = int(round(v))
	return out


func skills_of(member: Dictionary) -> Array[String]:
	var a: Dictionary = Data.actors[member["id"]]
	var out: Array[String] = []
	for s in a.get("skills", []):
		out.append(s)
	var learn: Dictionary = a.get("learn", {})
	for lv in learn:
		if int(lv) <= member["level"]:
			out.append(learn[lv])
	return out


## Skills learned between two levels (for the time-skip growth caption).
func skills_between(member: Dictionary, from_level: int, to_level: int) -> Array[String]:
	var out: Array[String] = []
	var learn: Dictionary = Data.actors[member["id"]].get("learn", {})
	for lv in learn:
		if int(lv) > from_level and int(lv) <= to_level:
			out.append(learn[lv])
	return out


func exp_to_next(member: Dictionary) -> int:
	return int(Data.cfg("exp_per_level", 30)) * int(member["level"])


## Years pass between stages: set Derrick's age and level, heal what heals.
func set_growth(new_form: String, level: int) -> void:
	form = new_form
	for m in party:
		m["level"] = level
		m["exp"] = 0
	heal_party()


## Battles add a little experience, but time skips do most of the growing.
func gain_exp(amount: int) -> Array[String]:
	var lines: Array[String] = []
	for m in party:
		if m["hp"] <= 0:
			continue
		m["exp"] += amount
		while m["exp"] >= exp_to_next(m):
			m["exp"] -= exp_to_next(m)
			var before := stats_of(m)
			var old_skills := skills_of(m)
			m["level"] += 1
			var after := stats_of(m)
			m["hp"] += after["hp"] - before["hp"]
			m["mp"] += after["mp"] - before["mp"]
			lines.append("%s is harder now." % Data.actors[m["id"]]["name"])
			for s in skills_of(m):
				if not old_skills.has(s):
					lines.append("%s learned %s." % [Data.actors[m["id"]]["name"], Data.skills[s]["name"]])
	return lines


func add_wound(what: String) -> void:
	var stage: Dictionary = Data.stages.get(stage_id, {})
	wounds.append({"what": what, "where": stage.get("name", "the road")})
	for m in party:  # the wound lowers max HP right away
		var s := stats_of(m)
		m["hp"] = mini(int(m["hp"]), s["hp"])


func heal_party() -> void:
	for m in party:
		var s := stats_of(m)
		m["hp"] = s["hp"]
		m["mp"] = s["mp"]


func add_item(id: String, qty := 1) -> void:
	inventory[id] = int(inventory.get(id, 0)) + qty
	if inventory[id] <= 0:
		inventory.erase(id)


func add_var(key: String, n: int) -> void:
	vars[key] = int(vars.get(key, 0)) + n


func learn_affinity(enemy_id: String, element: String, mult: float) -> void:
	if not known_affinity.has(enemy_id):
		known_affinity[enemy_id] = {}
	known_affinity[enemy_id][element] = mult


# ------------------------------------------------------------------ save / load
func to_dict() -> Dictionary:
	return {"party": party, "form": form, "wounds": wounds, "inventory": inventory, "gold": gold,
			"flags": flags, "vars": vars, "stage_id": stage_id, "known_affinity": known_affinity}


func save_game() -> bool:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(to_dict(), " "))
	return true


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func load_game() -> bool:
	if not has_save():
		return false
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if not d is Dictionary:
		return false
	party.clear()
	for m in d["party"]:
		# JSON turns ints into floats; normalise so "%d" and == comparisons behave.
		party.append({"id": m["id"], "level": int(m["level"]), "exp": int(m["exp"]),
				"hp": int(m["hp"]), "mp": int(m["mp"])})
	form = d.get("form", "child")
	wounds = d.get("wounds", [])
	inventory = {}
	for k in d["inventory"]:
		inventory[k] = int(d["inventory"][k])
	gold = int(d.get("gold", 0))
	flags = d.get("flags", {})
	vars = {}
	for k in d.get("vars", {}):
		vars[k] = int(d["vars"][k])
	stage_id = d.get("stage_id", "")
	known_affinity = d.get("known_affinity", {})
	return true


# ------------------------------------------------------------------ input
## Adds keyboard + gamepad bindings in code so project.godot stays readable.
func _bind_inputs() -> void:
	_add_keys("ui_accept", [KEY_Z, KEY_J])
	_add_keys("ui_cancel", [KEY_X, KEY_K, KEY_BACKSPACE])
	_add_keys("ui_up", [KEY_W])
	_add_keys("ui_down", [KEY_S])
	_add_keys("ui_left", [KEY_A])
	_add_keys("ui_right", [KEY_D])
	_add_action("menu", [KEY_C, KEY_TAB], [JOY_BUTTON_START, JOY_BUTTON_Y])
	# Mouse: left click moves / talks / picks / advances text (polled as "click");
	# right click is turned into ui_cancel by the Router, so it backs out of anything.
	if not InputMap.has_action("click"):
		InputMap.add_action("click")
		var lmb := InputEventMouseButton.new()
		lmb.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("click", lmb)


## Confirm this frame, from keys, pad or a left click (for "press to continue" waits).
func confirm_pressed() -> bool:
	return Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("click")


func _add_keys(action: String, keys: Array) -> void:
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


func _add_action(action: String, keys: Array, pad_buttons: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	_add_keys(action, keys)
	for b in pad_buttons:
		var ev := InputEventJoypadButton.new()
		ev.button_index = b
		InputMap.action_add_event(action, ev)
