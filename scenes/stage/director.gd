class_name Director
extends Node
## Plays a stage script: a JSON array of commands, one after another.
## Every command is one key naming it plus its fields, e.g.
##   {"say": "gauntley", "text": "Oi. You there, with the terrifying stick."}
##   {"walk": "gauntley_rider", "path": [[26, 5], [38, 5]], "speed": 5, "wait": false}
##   {"battle": "dog", "win": [...], "lose": [...]}
## The full command list with fields is in the README and in Data.COMMANDS.

signal command_started(cmd: Dictionary)
signal choice_shown(options: Array)

var stage          # the stage scene (scenes/stage/stage.gd)
var cinema: Cinema
var dialogue: DialogueBox
var halted := false
var current: Dictionary = {}   # the command being played (for debugging)


func run(cmds: Array) -> void:
	for c in cmds:
		if halted:
			return
		current = c
		command_started.emit(c)
		await _exec(c)


func _exec(c: Dictionary) -> void:
	var op := Data.command_name(c)
	match op:
		"card":
			await cinema.card(c["card"], c.get("sub", ""), float(c.get("hold", 2.6)))
		"caption":
			await cinema.caption(c["caption"], float(c.get("hold", 0.0)), c.get("center", false))
		"sound":
			cinema.sound(c["sound"])
		"hint":
			stage.hint(c["hint"])
		"say":
			await dialogue.play([line(c["say"], c["text"])])
		"talk":
			var lines: Array = []
			for l in c["talk"]:
				lines.append(line(l[0], l[1]))
			await dialogue.play(lines)
		"choice":
			await _choice(c)
		"letterbox":
			await cinema.letterbox(bool(c["letterbox"]))
		"camera":
			if c.get("wait", true):
				await stage.camera_to(c["camera"], float(c.get("time", 1.0)))
			else:
				stage.camera_to(c["camera"], float(c.get("time", 1.0)))
		"walk":
			var wps: Array = c.get("path", [c.get("to", [0, 0])])
			if c.get("wait", true):
				await stage.walk(c["walk"], wps, float(c.get("speed", 4.0)), c.get("direct", false))
			else:
				stage.walk(c["walk"], wps, float(c.get("speed", 4.0)), c.get("direct", false))
		"face":
			stage.face(c["face"], c.get("dir", ""), c.get("to", ""))
		"wait":
			await get_tree().create_timer(float(c["wait"])).timeout
		"tint":
			stage.set_tint(Color(c["tint"]), float(c.get("time", 1.0)))
			if c.get("wait", false):
				await get_tree().create_timer(float(c.get("time", 1.0))).timeout
		"weather":
			stage.set_weather(c["weather"])
		"shake":
			stage.shake(float(c["shake"]), float(c.get("time", 0.4)))
		"flash":
			cinema.flash(Color(c["flash"]), float(c.get("time", 0.5)))
		"fade":
			await cinema.black(c["fade"] == "out", float(c.get("time", 0.8)))
		"show":
			if c.get("wait", true):
				await stage.show_actor(c["show"], true)
			else:
				stage.show_actor(c["show"], true)
		"hide":
			if c.get("wait", true):
				await stage.show_actor(c["hide"], false)
			else:
				stage.show_actor(c["hide"], false)
		"teleport":
			stage.teleport(c["teleport"], Vector2i(int(c["to"][0]), int(c["to"][1])))
		"emote":
			stage.emote(c["emote"], c.get("text", "!"))
		"battle":
			var outcome: String = await stage.run_battle(c["battle"])
			if outcome == "title":
				halted = true
				return
			await run(c.get(outcome, c.get("then", [])))
		"set":
			Game.flags[c["set"]] = true
		"add":
			Game.add_var(c["add"], int(c.get("n", 1)))
		"if":
			var ok: bool = Game.flags.get(c["if"], false)
			await run(c.get("then", []) if ok else c.get("else", []))
		"give":
			var n := int(c.get("n", 1))
			Game.add_item(c["give"], n)
			if not c.get("quiet", false):
				cinema.sound("Took: %s%s" % [Data.items[c["give"]]["name"], "" if n == 1 else " x%d" % n])
		"fall":
			stage.fall(c["fall"], true)
			await get_tree().create_timer(0.4).timeout
		"rise":
			stage.fall(c["rise"], false)
			await get_tree().create_timer(0.4).timeout
		"pose":
			stage.pose(c["pose"], c.get("art", ""))
		"act":     # a body action: nod, cower, raise, yield, attack, hurt, cast, peck, reset
			if c.get("wait", false):
				await stage.act(c["act"], c.get("do", "nod"))
			else:
				stage.act(c["act"], c.get("do", "nod"))
		"slats":
			await cinema.slats(bool(c["slats"]))
		"slats_shadow":
			await cinema.slats_shadow(float(c["slats_shadow"]), c.get("dir", "right") != "left")
		"next":
			halted = true
			stage.goto_next()
		"title_drop":
			await cinema.title_drop(c["title_drop"], c.get("sub", ""))
		"end_act":
			halted = true
			stage.end_act()
		"run":
			await run(stage.stage["scripts"][c["run"]])
		"heal":
			Game.heal_party()
		"control":
			pass  # control always returns to the player when a script ends
		"growth":
			await stage.show_growth()
		"age":     # a time skip inside a stage: {"age": "small", "level": 1, "text": "..."}
			await stage.set_age(c["age"], int(c.get("level", Game.hero()["level"])), c.get("text", ""))
		"gate":    # shut (or open) a strip of tiles: {"gate": "west", "on": true}
			stage.set_gate(c["gate"], c.get("on", true))
		"light":
			stage.set_light(c["light"], float(c.get("energy", 1.0)), float(c.get("time", 1.0)))
		"checkpoint":
			Game.save_game()
		"retile":
			stage.retile(c["retile"])
		"wound":   # a scar written into the story: permanent, listed under Status
			Game.add_wound(c["wound"])
			cinema.sound("A wound that will not close: %s" % c["wound"])
		"zoom":
			if c.get("wait", false):
				await stage.zoom_to(float(c["zoom"]), float(c.get("time", 1.2)))
			else:
				stage.zoom_to(float(c["zoom"]), float(c.get("time", 1.2)))
		_:
			push_warning("Director: unknown command %s" % str(c))


## A dialogue line for a cast member (or narration when who == "").
func line(who: String, text: String) -> Dictionary:
	if who == "":
		return {"text": text}
	var key: String = stage.cast_key(who)
	var c: Dictionary = Data.cast.get(key, {})
	var portrait: String = c.get("portrait", "")
	if key == "derrick":
		portrait = Game.actor_art(Game.hero(), "portrait")
	return {"who": c.get("name", who), "portrait": portrait, "text": text,
			"speed": float(c.get("text_speed", 48.0)), "beat": float(c.get("beat", 0.0)),
			"unskippable": c.get("unskippable", false), "color": c.get("color", UIStyle.ATB.to_html())}


## Choices. Options can be "defiant" (degrade as Complicity rises), "once" (greyed
## out after being picked) and "repeat" (the question is asked again afterwards).
func _choice(c: Dictionary) -> void:
	var opts: Array = c["choice"]
	var used := {}
	while not halted:
		var shown: Array = []
		for i in opts.size():
			var o: Dictionary = opts[i]
			var off: bool = used.has(i) and o.get("once", false)
			shown.append({"text": o["text"], "defiant": o.get("defiant", false), "disabled": off,
					"help": o.get("disabled_help", "") if off else o.get("help", "")})
		var prompt := {}
		if c.has("prompt"):
			prompt = line(c["prompt"][0], c["prompt"][1])
		choice_shown.emit(shown)
		var pick: int = await dialogue.ask(shown, prompt)
		used[pick] = true
		await run(opts[pick].get("then", []))
		if not opts[pick].get("repeat", false):
			return
