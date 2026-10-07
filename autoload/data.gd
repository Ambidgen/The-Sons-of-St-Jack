extends Node
## Read-only game database. Every table is a JSON file in res://data/ so story,
## pacing and balance changes never touch code. Stages live one-per-file in
## res://data/stages/. Access: Data.skills["gouge"], Data.cfg("heal_mult", 0.5).

const ART_ROOT := "res://assets/placeholder/"
const TABLES := ["config", "actors", "enemies", "skills", "items", "statuses", "encounters", "cast"]

## Every director command the stage understands, with the field that names it.
const COMMANDS := ["card", "caption", "sound", "say", "talk", "choice", "letterbox", "camera", "walk",
		"face", "wait", "tint", "weather", "shake", "flash", "fade", "show", "hide", "teleport", "emote",
		"battle", "set", "add", "if", "give", "fall", "rise", "slats", "slats_shadow", "next",
		"title_drop", "end_act", "run", "heal", "control", "growth", "light", "checkpoint", "hint", "pose",
		"retile", "zoom", "wound", "act", "age", "gate"]

var config: Dictionary = {}
var actors: Dictionary = {}
var enemies: Dictionary = {}
var skills: Dictionary = {}
var items: Dictionary = {}
var statuses: Dictionary = {}
var encounters: Dictionary = {}
var cast: Dictionary = {}
var stages: Dictionary = {}

var _tex_cache: Dictionary = {}


func _ready() -> void:
	reload()


func reload() -> void:
	for table in TABLES:
		set(table, _load_json("res://data/%s.json" % table))
	stages = {}
	for file in DirAccess.get_files_at("res://data/stages"):
		if file.ends_with(".json"):
			var s := _load_json("res://data/stages/" + file)
			if s.has("id"):
				stages[s["id"]] = s


func cfg(key: String, fallback: Variant = null) -> Variant:
	return config.get(key, fallback)


## Stage ids in play order.
func act_order() -> Array:
	return cfg("act_one", [])


func next_stage(id: String) -> String:
	var order := act_order()
	var i := order.find(id)
	if i < 0 or i + 1 >= order.size():
		return ""
	return order[i + 1]


## "char/gauntley" -> Texture2D for res://assets/placeholder/char/gauntley.svg
func tex(key: String) -> Texture2D:
	if key == "":
		return null
	if not _tex_cache.has(key):
		var path := ART_ROOT + key + ".svg"
		_tex_cache[key] = load(path) if ResourceLoader.exists(path) else null
		if _tex_cache[key] == null:
			push_warning("Missing art: " + path)
	return _tex_cache[key]


func icon(name: String) -> Texture2D:
	return tex("icon/" + name)


func action_def(kind: String, id: String) -> Dictionary:
	var table: Dictionary = items if kind == "item" else skills
	return table.get(id, {})


func _has_art(key: String) -> bool:
	return key != "" and ResourceLoader.exists(ART_ROOT + key + ".svg")


## Cross-checks every reference between tables. Returns a list of problems.
func validate() -> Array[String]:
	var errs: Array[String] = []
	for id in actors:
		var a: Dictionary = actors[id]
		for form in a.get("forms", {}):
			for key in ["sprite", "field", "portrait"]:
				if not _has_art(a["forms"][form].get(key, "")):
					errs.append("actor %s form %s: missing art %s" % [id, form, a["forms"][form].get(key, "")])
		var learned: Array = a.get("learn", {}).values()
		for s in a.get("skills", []) + learned:
			if not skills.has(s):
				errs.append("actor %s: unknown skill %s" % [id, s])
	for id in enemies:
		var e: Dictionary = enemies[id]
		if not _has_art(e.get("sprite", "")):
			errs.append("enemy %s: missing art %s" % [id, e.get("sprite", "")])
		for s in e.get("skills", []):
			if not skills.has(s):
				errs.append("enemy %s: unknown skill %s" % [id, s])
		for it in e.get("drops", {}):
			if not items.has(it):
				errs.append("enemy %s: unknown drop %s" % [id, it])
	for table in [skills, items]:
		for id in table:
			var d: Dictionary = table[id]
			if d.has("status") and not statuses.has(d["status"]):
				errs.append("action %s: unknown status %s" % [id, d["status"]])
			for c in d.get("cure", []):
				if not statuses.has(c):
					errs.append("action %s: unknown cure %s" % [id, c])
			if not _has_art("icon/" + d.get("icon", "skill")):
				errs.append("action %s: missing icon %s" % [id, d.get("icon", "")])
	for id in statuses:
		if not _has_art("icon/" + statuses[id].get("icon", "")):
			errs.append("status %s: missing icon" % id)
	for id in encounters:
		var enc: Dictionary = encounters[id]
		for e in enc.get("enemies", []):
			if not enemies.has(e):
				errs.append("encounter %s: unknown enemy %s" % [id, e])
		if not _has_art(enc.get("bg", "")):
			errs.append("encounter %s: missing bg %s" % [id, enc.get("bg", "")])
		var h: Dictionary = enc.get("hopeless", {})
		if not h.is_empty() and not skills.has(h.get("skill", "")):
			errs.append("encounter %s: hopeless counter skill %s unknown" % [id, h.get("skill", "")])
		for sid in [enc.get("attack_as", "attack")] + enc.get("only_skills", []):
			if not skills.has(sid):
				errs.append("encounter %s: unknown skill %s" % [id, sid])
		for b in enc.get("barks", []) + enc.get("intro", []) + h.get("lines", []):
			if b.get("who", "") != "" and not cast.has(b.get("who", "")):
				errs.append("encounter %s: bark by unknown cast %s" % [id, b.get("who", "")])
	for id in cast:
		var c: Dictionary = cast[id]
		if c.get("player", false):
			continue
		if not _has_art(c.get("field", "")):
			errs.append("cast %s: missing field art %s" % [id, c.get("field", "")])
		if c.has("portrait") and not _has_art(c["portrait"]):
			errs.append("cast %s: missing portrait %s" % [id, c["portrait"]])
	for id in act_order():
		if not stages.has(id):
			errs.append("config.act_one: unknown stage %s" % id)
	for id in stages:
		errs.append_array(_validate_stage(stages[id]))
	return errs


func _validate_stage(s: Dictionary) -> Array[String]:
	var errs: Array[String] = []
	var id: String = s["id"]
	var letters := {}
	if s.has("level"):
		var lv: Dictionary = s["level"]
		for key in ["art", "show", "glow"]:
			if lv.has(key) and not StageMap.has_level_art(lv[key]):
				errs.append("stage %s: level %s '%s' has no painting in %s" % [id, key, lv[key], StageMap.LEVEL_ROOT])
		if not s.has("start"):
			errs.append("stage %s: no start" % id)
		if not s.get("sense", {}).has("road"):
			errs.append("stage %s: sense has no road sample tiles" % id)
		for ch in s.get("lines", {}):
			letters[ch] = true
			if not s.get("triggers", {}).has(ch):
				errs.append("stage %s: line %s triggers nothing" % [id, ch])
		for d in s.get("depth", []):
			if not ResourceLoader.exists(StageMap.LEVEL_ROOT + String(d.get("art", "")) + ".png"):
				errs.append("stage %s: depth layer %s missing" % [id, d.get("art", "")])
	else:
		var rows: Array = s.get("rows", [])
		if rows.is_empty():
			return ["stage %s: no rows and no level" % id] as Array[String]
		var width: int = rows[0].length()
		var has_start := false
		for r in rows:
			if r.length() != width:
				errs.append("stage %s: ragged row '%s' (%d, expected %d)" % [id, r, r.length(), width])
			for ch in r:
				if ch == "@":
					has_start = true
				letters[ch] = true
		if not has_start:
			errs.append("stage %s: no @ start" % id)
	var scripts: Dictionary = s.get("scripts", {})
	var cast_ids := {"player": true, "derrick": true}
	for ch in s.get("cast", {}):
		var placement: Dictionary = s["cast"][ch]
		var cast_key: String = placement.get("cast", placement.get("id", ""))
		cast_ids[placement.get("id", "")] = true
		if not cast.has(cast_key):
			errs.append("stage %s: cast %s refers to unknown cast %s" % [id, ch, cast_key])
		if not letters.has(ch) and not placement.has("at"):
			errs.append("stage %s: cast %s placed nowhere" % [id, ch])
		if placement.has("talk") and not scripts.has(placement["talk"]):
			errs.append("stage %s: cast %s talk script %s missing" % [id, ch, placement["talk"]])
	for ch in s.get("triggers", {}):
		if not scripts.has(s["triggers"][ch]):
			errs.append("stage %s: trigger %s -> missing script %s" % [id, ch, s["triggers"][ch]])
		if not letters.has(ch):
			errs.append("stage %s: trigger %s not on the map" % [id, ch])
	for ch in s.get("props", {}):
		if not _has_art(s["props"][ch].get("art", "")):
			errs.append("stage %s: prop %s missing art %s" % [id, ch, s["props"][ch].get("art", "")])
	for key in ["on_enter", "on_exit"]:
		if s.has(key) and not scripts.has(s[key]):
			errs.append("stage %s: %s script %s missing" % [id, key, s[key]])
	for sid in scripts:
		_validate_cmds(scripts[sid], "stage %s script %s" % [id, sid], scripts, cast_ids, errs, s.get("gates", {}))
	return errs


func _validate_cmds(cmds: Array, where: String, scripts: Dictionary, cast_ids: Dictionary, errs: Array[String],
		gate_ids: Dictionary = {}) -> void:
	for c in cmds:
		if not c is Dictionary:
			errs.append("%s: command is not an object: %s" % [where, str(c)])
			continue
		var op := command_name(c)
		if op == "":
			errs.append("%s: unknown command %s" % [where, str(c)])
			continue
		match op:
			"say", "emote", "show", "hide", "fall", "rise", "teleport", "face", "walk", "pose", "act":
				if not cast_ids.has(c[op]):
					errs.append("%s: %s refers to cast '%s' not in this stage" % [where, op, c[op]])
				if op == "act" and not (Rig.ACTION_LEN.has(c.get("do", "")) or c.get("do", "") == "reset"):
					errs.append("%s: act '%s' is not a body action (%s, reset)" % [where, c.get("do", ""), ", ".join(Rig.ACTION_LEN.keys())])
			"talk":
				for line in c["talk"]:
					if not cast_ids.has(line[0]) and line[0] != "":
						errs.append("%s: talk line by '%s' not in this stage" % [where, line[0]])
			"battle":
				if not encounters.has(c["battle"]):
					errs.append("%s: unknown encounter %s" % [where, c["battle"]])
			"give":
				if not items.has(c["give"]):
					errs.append("%s: unknown item %s" % [where, c["give"]])
			"run":
				if not scripts.has(c["run"]):
					errs.append("%s: run unknown script %s" % [where, c["run"]])
			"camera":
				if c["camera"] is String and not cast_ids.has(c["camera"]):
					errs.append("%s: camera on unknown cast %s" % [where, c["camera"]])
			"age":
				if not actors.get("derrick", {}).get("forms", {}).has(c["age"]):
					errs.append("%s: age '%s' is not one of Derrick's forms" % [where, c["age"]])
			"gate":
				if not gate_ids.has(c["gate"]):
					errs.append("%s: unknown gate %s" % [where, c["gate"]])
		for branch in ["then", "else", "win", "lose"]:
			if c.has(branch):
				_validate_cmds(c[branch], where, scripts, cast_ids, errs, gate_ids)
		if op == "choice":
			for o in c["choice"]:
				_validate_cmds(o.get("then", []), where, scripts, cast_ids, errs, gate_ids)


## The command keyword of a director command dictionary, or "".
## "wait" doubles as a modifier ({"show": "x", "wait": false}), so it only
## names the command when nothing else does.
static func command_name(c: Dictionary) -> String:
	for k in COMMANDS:
		if k != "wait" and c.has(k):
			return k
	return "wait" if c.has("wait") else ""


func _load_json(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text == "":
		push_error("Data: cannot read " + path)
		return {}
	var json := JSON.new()
	if json.parse(text) != OK:
		push_error("Data: %s line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return {}
	if json.data is Dictionary:
		return json.data
	push_error("Data: %s is not a JSON object" % path)
	return {}
