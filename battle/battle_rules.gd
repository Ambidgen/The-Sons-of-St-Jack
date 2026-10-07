class_name BattleRules
extends RefCounted
## All battle state and maths. Touches no nodes and never awaits: every call
## returns a list of event dictionaries that the battle scene animates (or the
## simulator ignores). Keep new mechanics in here so they are simulatable.
##
## Action:  {"kind": "skill"|"item"|"flee"|"debug_win", "id": "gouge", "targets": [Battler]}
## Events:  {"type": "use"|"damage"|"heal"|"mp"|"miss"|"evade"|"status_on"|"status_off"|"maim"|
##                   "yield"|"ko"|"revive"|"skip"|"flee"|"flee_fail"|"bark"|"scripted"|"message", ...}
##
## Sons of St. Jack rules on top of the classic set:
##   * Maiming  -- a single hit of >= maim_threshold x max HP leaves a permanent wound.
##   * Healing  -- every HP restore is multiplied by heal_mult: it slows the bleeding, no more.
##   * Accuracy -- wild swings can miss ("accuracy": 0.7).
##   * Yield    -- sparring partners stop at yield_below HP (the fight is won, nobody is hurt).
##   * Impunity -- attacks on an impunity enemy are always evaded.
##   * Hopeless -- after N player actions (or any flight) a scripted counter ends the fight
##                 with outcome "scripted": a story beat, not a Game Over.

const EVADE_TEXT := ["Evaded", "Parried", "Sidestepped", "Too slow", "Turned aside"]

var allies: Array[Battler] = []
var enemies: Array[Battler] = []
var queue: TurnQueue
var rng := RandomNumberGenerator.new()
var inventory: Dictionary          # item_id -> qty (Game.inventory in play, a copy in the sim)
var can_flee := true
var fled := false
var turns := 0
var encounter: Dictionary = {}
var player_actions := 0
var scripted_end := false
var attack_id := "attack"          # an encounter can swap the basic attack ("attack_as": "headbutt")
var _barked: Dictionary = {}
var _evades := 0


func _init(p_allies: Array[Battler], p_enemies: Array[Battler], p_inventory: Dictionary,
		mode: TurnQueue.Mode, seed := -1) -> void:
	allies = p_allies
	enemies = p_enemies
	inventory = p_inventory
	if seed >= 0:
		rng.seed = seed
	else:
		rng.randomize()
	queue = TurnQueue.new(mode, all(), rng)
	queue.atb_fill = float(Data.cfg("atb_fill", 0.12))


## Builds rules for an encounter from the current party. `sim` copies the
## inventory so simulated battles never spend real items.
static func for_encounter(encounter_id: String, mode: TurnQueue.Mode, sim := false, seed := -1) -> BattleRules:
	var a: Array[Battler] = []
	for m in Game.party:
		var member: Dictionary = m.duplicate() if sim else m
		if sim:  # simulate with a fresh, fully healed Derrick
			member["hp"] = Game.stats_of(m)["hp"]
			member["mp"] = Game.stats_of(m)["mp"]
		var skill_ids: Array[String] = Game.skills_of(m)
		var enc_def: Dictionary = Data.encounters[encounter_id]
		if enc_def.has("only_skills"):        # e.g. pinned against a wall: no room for tricks
			skill_ids.clear()
			for sid in enc_def["only_skills"]:
				skill_ids.append(sid)
		a.append(Battler.from_member(member, Game.stats_of(m), skill_ids))
	var e: Array[Battler] = []
	var ids: Array = Data.encounters[encounter_id]["enemies"]
	for i in ids.size():
		var dupes := ids.count(ids[i])
		var suffix := "" if dupes == 1 else " " + "ABCDEFG"[ids.slice(0, i).count(ids[i])]
		e.append(Battler.from_enemy(ids[i], suffix))
	var inv: Dictionary = Game.inventory.duplicate() if sim else Game.inventory
	var r := BattleRules.new(a, e, inv, mode, seed)
	r.encounter = Data.encounters[encounter_id]
	r.can_flee = r.encounter.get("can_flee", true)
	r.attack_id = r.encounter.get("attack_as", "attack")
	return r


func all() -> Array[Battler]:
	var out: Array[Battler] = []
	out.append_array(allies)
	out.append_array(enemies)
	return out


func living(list: Array[Battler]) -> Array[Battler]:
	var out: Array[Battler] = []
	for b in list:
		if b.is_alive():
			out.append(b)
	return out


func friends_of(b: Battler) -> Array[Battler]:
	return allies if b.is_ally else enemies


func foes_of(b: Battler) -> Array[Battler]:
	return enemies if b.is_ally else allies


func outcome() -> String:
	if scripted_end:
		return "scripted"
	if fled:
		return "fled"
	if living(enemies).is_empty():
		return "win"
	if living(allies).is_empty():
		return "lose"
	return ""


func is_hopeless() -> bool:
	return not encounter.get("hopeless", {}).is_empty()


## Lines spoken before the first turn.
func intro_barks() -> Array[Dictionary]:
	var ev: Array[Dictionary] = []
	for b in encounter.get("intro", []):
		ev.append({"type": "bark", "who": b["who"], "text": b["text"]})
	return ev


# ------------------------------------------------------------------ turn flow
func next_actor(delta: float) -> Battler:
	return queue.advance(delta)


## Start-of-turn upkeep: expire/tick statuses. Sets actor.skip_turn.
func begin_turn(actor: Battler) -> Array[Dictionary]:
	var ev: Array[Dictionary] = []
	turns += 1
	actor.skip_turn = false
	for id in actor.statuses.keys():
		var s: Dictionary = Data.statuses[id]
		if s.get("dot", 0.0) > 0.0 and actor.is_alive():
			var dmg := maxi(1, int(actor.max_hp() * float(s["dot"])))
			ev.append_array(_apply_damage(actor, dmg, {"status": id}))
			if not actor.is_alive():
				return ev  # KO clears statuses; nothing left to tick
		if s.get("skip_turn", false):
			actor.skip_turn = true
		if s.get("permanent", false):
			continue
		actor.statuses[id] -= 1
		if actor.statuses[id] <= 0:
			actor.statuses.erase(id)
			ev.append({"type": "status_off", "target": actor, "status": id})
	if actor.skip_turn:
		ev.append({"type": "skip", "target": actor})
	return ev


func can_act(actor: Battler) -> bool:
	return actor.is_alive() and not actor.skip_turn and outcome() == ""


## Ends a turn that had no action (dazed, died to bleeding).
func pass_turn(actor: Battler) -> void:
	queue.end_turn(actor, 1.0)


# ------------------------------------------------------------------ choosing
func def_of(action: Dictionary) -> Dictionary:
	return Data.action_def(action.get("kind", "skill"), action.get("id", ""))


func can_use(actor: Battler, kind: String, id: String) -> bool:
	if kind == "item":
		if encounter.get("no_items", false):
			return false
		return int(inventory.get(id, 0)) > 0 and not candidates(actor, Data.items[id]).is_empty()
	var d: Dictionary = Data.skills.get(id, {})
	if d.is_empty() or actor.mp < int(d.get("cost", 0)) or candidates(actor, d).is_empty():
		return false
	if d.has("requires_hp_below") and float(actor.hp) / actor.max_hp() >= float(d["requires_hp_below"]):
		return false
	return true


## Why an action is greyed out (for the help line).
func why_not(actor: Battler, kind: String, id: String) -> String:
	var d := Data.action_def(kind, id)
	if kind == "skill" and actor.mp < int(d.get("cost", 0)):
		return "Not enough grit. Brace to get your breath back."
	if d.has("requires_hp_below"):
		return "Only when you're nearly finished."
	return "Nothing to use it on."


## Who an action may target. "all_*" actions still return the full list.
func candidates(actor: Battler, d: Dictionary) -> Array[Battler]:
	match d.get("target", "enemy"):
		"self":
			var me: Array[Battler] = [actor]
			return me
		"ally", "all_allies":
			return living(friends_of(actor))
		"enemy", "all_enemies":
			var out: Array[Battler] = []
			for b in living(foes_of(actor)):
				if not (actor.is_ally and b.untargetable):
					out.append(b)
			return out
		"ally_ko":
			var dead: Array[Battler] = []
			for b in friends_of(actor):
				if b.hp <= 0:
					dead.append(b)
			return dead
	return living(foes_of(actor))


func is_multi(d: Dictionary) -> bool:
	return String(d.get("target", "")).begins_with("all_")


# ------------------------------------------------------------------ resolving
func resolve(actor: Battler, action: Dictionary) -> Array[Dictionary]:
	var ev: Array[Dictionary] = []
	var kind: String = action.get("kind", "skill")
	if kind == "debug_win":
		if is_hopeless():
			return _hopeless_counter()
		for e in living(enemies):
			ev.append_array(_apply_damage(e, e.hp, {}))
		return ev
	if kind == "flee":
		if is_hopeless() and encounter["hopeless"].get("after_yield", false):
			ev.append({"type": "flee_fail", "actor": actor, "text": encounter.get("flee_text", "Nowhere to run.")})
			queue.end_turn(actor, 1.0)
			return ev
		if is_hopeless():
			ev.append({"type": "flee_fail", "actor": actor, "text": "Nowhere to run."})
			ev.append_array(_hopeless_counter())
			return ev
		if can_flee and rng.randf() < float(Data.cfg("flee_chance", 0.6)):
			fled = true
			ev.append({"type": "flee", "actor": actor})
		else:
			ev.append({"type": "flee_fail", "actor": actor, "text": "Can't get away!" if can_flee else "No running from this."})
			queue.end_turn(actor, 1.0)
		return ev

	var d := def_of(action)
	if kind == "item":
		inventory[action["id"]] = int(inventory.get(action["id"], 0)) - 1
		if inventory[action["id"]] <= 0:
			inventory.erase(action["id"])
	else:
		actor.mp -= int(d.get("cost", 0))
	ev.append({"type": "use", "actor": actor, "name": d.get("name", "?"), "def": d, "kind": kind})

	var targets: Array[Battler] = []
	for t in action.get("targets", []):
		if actor.is_ally and t.untargetable:
			continue
		targets.append(t)
	if is_multi(d):
		targets = candidates(actor, d)
	elif targets.is_empty() or (d.get("target") != "ally_ko" and not targets[0].is_alive()):
		var c := candidates(actor, d)           # original target fell: retarget
		targets.clear()
		if not c.is_empty():
			targets.append(c[0])

	for t in targets:
		ev.append_array(_apply(actor, t, d))
	if d.has("grit") and actor.is_alive():
		var before := actor.mp
		actor.mp = mini(actor.max_mp(), actor.mp + int(d["grit"]))
		if actor.mp > before:
			ev.append({"type": "mp", "target": actor, "amount": actor.mp - before})
	queue.end_turn(actor, float(d.get("delay", 1.0)))

	if actor.is_ally:
		player_actions += 1
		ev.append_array(_barks_after(player_actions))
		var h: Dictionary = encounter.get("hopeless", {})
		if not h.is_empty() and outcome() == "":
			var due := player_actions >= int(h.get("after_actions", 3))
			if h.get("after_yield", false):       # the story beat lands only once the blow does
				due = false
				for en in enemies:
					if en.yielded:
						due = true
			if due:
				ev.append_array(_hopeless_counter())
	return ev


func _barks_after(count: int) -> Array[Dictionary]:
	var ev: Array[Dictionary] = []
	for i in encounter.get("barks", []).size():
		var b: Dictionary = encounter["barks"][i]
		if int(b.get("after", -1)) == count and not _barked.has(i):
			_barked[i] = true
			ev.append({"type": "bark", "who": b["who"], "text": b["text"]})
	return ev


## The scripted end of a hopeless fight: someone steps in and puts Derrick down.
func _hopeless_counter() -> Array[Dictionary]:
	var h: Dictionary = encounter.get("hopeless", {})
	var ev: Array[Dictionary] = []
	var by: Battler = null
	for e in enemies:
		if e.key == h.get("by", ""):
			by = e
	if by == null:
		by = enemies[0]
	var d: Dictionary = Data.skills[h.get("skill", "put_down")]
	for b in h.get("lines", []):
		ev.append({"type": "bark", "who": b["who"], "text": b["text"]})
	if h.get("by", "") != "":                 # "by": "" -- an unseen hand, no name on screen
		ev.append({"type": "use", "actor": by, "name": d.get("name", "?"), "def": d, "kind": "skill"})
	for a in living(allies):
		ev.append_array(_apply_damage(a, a.hp, {"no_maim": true}))
	scripted_end = true
	ev.append({"type": "scripted"})
	return ev


func _apply(actor: Battler, t: Battler, d: Dictionary) -> Array[Dictionary]:
	var ev: Array[Dictionary] = []
	var hostile: bool = d.get("kind", "") in ["physical", "magic", "fixed"] or (d.get("kind") == "status" and actor.is_ally != t.is_ally)
	if hostile and t.impunity:
		ev.append({"type": "evade", "target": t, "text": EVADE_TEXT[_evades % EVADE_TEXT.size()]})
		_evades += 1
		return ev
	if hostile and rng.randf() > float(d.get("accuracy", 1.0)):
		ev.append({"type": "miss", "target": t, "text": "Missed"})
		return ev
	match d.get("kind", ""):
		"physical", "magic":
			var r := calc_damage(actor, t, d)
			if r["mult"] == 0.0:
				ev.append({"type": "miss", "target": t, "text": "Immune"})
			elif r["amount"] < 0:
				ev.append_array(_heal(t, -int(r["amount"])))
			else:
				r["by"] = actor.display_name
				ev.append_array(_apply_damage(t, int(r["amount"]), r))
		"fixed":
			var mult: float = t.affinity.get(d.get("element", ""), 1.0)
			ev.append_array(_apply_damage(t, maxi(1, int(d["amount"] * mult)),
					{"element": d.get("element", ""), "mult": mult, "by": actor.display_name}))
		"heal":
			var amount: int = int(d["amount"]) if d.has("amount") else int(actor.stat("atk") * float(d.get("power", 100)) / 100.0)
			ev.append_array(_heal(t, amount))
		"restore_mp":
			var before := t.mp
			t.mp = mini(t.max_mp(), t.mp + int(d["amount"]))
			ev.append({"type": "mp", "target": t, "amount": t.mp - before})
		"revive":
			if t.hp <= 0:
				t.hp = maxi(1, int(t.max_hp() * float(d.get("power", 30)) / 100.0))
				queue.rejoin(t)
				ev.append({"type": "revive", "target": t, "amount": t.hp})
	for s in d.get("cure", []):
		if t.statuses.has(s):
			t.statuses.erase(s)
			ev.append({"type": "status_off", "target": t, "status": s})
	if d.has("status") and t.is_alive():
		if rng.randf() < float(d.get("chance", 1.0)):
			t.statuses[d["status"]] = int(Data.statuses[d["status"]]["turns"])
			ev.append({"type": "status_on", "target": t, "status": d["status"]})
		elif d.get("kind") == "status":
			ev.append({"type": "miss", "target": t, "text": "No effect"})
	return ev


## Damage formula. Tweak here (or via config) -- the sim will tell you the effect.
##   raw = power% * K * A^2 / (A + D)     A = attacker ATK, D = target DEF
func calc_damage(actor: Battler, t: Battler, d: Dictionary) -> Dictionary:
	var physical: bool = d["kind"] == "physical"
	var a := actor.stat("atk" if physical else "mag")
	var def := t.stat("def" if physical else "res")
	var raw := float(d.get("power", 100)) / 100.0 * float(Data.cfg("damage_k", 2.0)) * a * a / (a + def)
	var v := float(Data.cfg("damage_variance", 0.1))
	raw *= rng.randf_range(1.0 - v, 1.0 + v)
	var crit := physical and rng.randf() < float(Data.cfg("crit_chance", 0.05)) + float(d.get("crit", 0.0))
	if crit:
		raw *= float(Data.cfg("crit_mult", 1.5))
	var element: String = d.get("element", "")
	var mult: float = t.affinity.get(element, 1.0)
	raw *= mult * t.damage_taken_mult()
	var amount := int(round(raw))
	if mult > 0.0:
		amount = maxi(1, amount)
	return {"amount": amount, "crit": crit, "element": element, "mult": mult}


func _apply_damage(t: Battler, amount: int, info: Dictionary) -> Array[Dictionary]:
	var ev: Array[Dictionary] = []
	var max_before := t.max_hp()
	t.hp = maxi(0, t.hp - amount)
	if t.yield_below > 0.0 and not t.yielded and not info.has("status"):
		t.hp = maxi(1, t.hp)          # someone who yields goes down to his knees, not into the ground
	var e := {"type": "damage", "target": t, "amount": amount}
	e.merge(info)
	ev.append(e)
	for s in t.statuses.keys():
		if Data.statuses[s].get("break_on_hit", false) and not info.has("status"):
			t.statuses.erase(s)
			ev.append({"type": "status_off", "target": t, "status": s})
	# Maiming: one hit this heavy leaves something that never heals.
	var threshold := float(Data.cfg("maim_threshold", 0.4))
	if not info.has("status") and not info.get("no_maim", false) and threshold > 0.0 \
			and amount >= max_before * threshold and t.hp > 0:
		t.new_wounds += 1
		t.wound_by = info.get("by", "")
		if Data.statuses.has("maimed"):
			t.statuses["maimed"] = 999
		ev.append({"type": "maim", "target": t})
	if t.hp == 0:
		t.statuses.clear()
		ev.append({"type": "ko", "target": t})
	elif t.yield_below > 0.0 and not t.yielded and float(t.hp) / t.max_hp() < t.yield_below:
		t.yielded = true
		t.statuses.clear()
		ev.append({"type": "yield", "target": t, "text": t.yield_text})
	return ev


func _heal(t: Battler, amount: int) -> Array[Dictionary]:
	var before := t.hp
	var scaled := maxi(1, int(round(amount * float(Data.cfg("heal_mult", 0.5)))))
	t.hp = mini(t.max_hp(), t.hp + scaled)
	var ev: Array[Dictionary] = [{"type": "heal", "target": t, "amount": t.hp - before}]
	return ev


# ------------------------------------------------------------------ AI
## Enemy AI, also used for Derrick in auto-battle and the simulator.
func ai_choose(actor: Battler) -> Dictionary:
	if actor.is_ally:
		return _ally_ai(actor)
	var usable: Array[String] = []
	for s in actor.skills:
		if can_use(actor, "skill", s):
			usable.append(s)
	if usable.is_empty():
		usable.append("attack")
	var id: String = usable[rng.randi_range(0, usable.size() - 1)]
	return {"kind": "skill", "id": id, "targets": [_pick_target(actor, Data.skills[id])]}


func _pick_target(actor: Battler, d: Dictionary) -> Battler:
	var c := candidates(actor, d)
	if c.is_empty():
		return actor
	if d.get("target") == "ally":  # heal/buff: lowest HP first
		c.sort_custom(func(a: Battler, b: Battler) -> bool: return a.hp * b.max_hp() < b.hp * a.max_hp())
		return c[0]
	if rng.randf() < 0.3:          # sometimes focus the weakest
		c.sort_custom(func(a: Battler, b: Battler) -> bool: return a.hp < b.hp)
		return c[0]
	return c[rng.randi_range(0, c.size() - 1)]


## A survivor's instincts: bind a bleed, brace when out of grit, go all in when
## nearly finished, otherwise hit whatever will fall fastest.
func _ally_ai(actor: Battler) -> Dictionary:
	var foes := candidates(actor, Data.skills[attack_id])
	if foes.is_empty():
		return {"kind": "skill", "id": "defend", "targets": [actor]}
	if actor.has_status("bleeding") and actor.hp < actor.max_hp() * 0.6:
		for id in inventory:
			if Data.items[id].get("cure", []).has("bleeding"):
				return {"kind": "item", "id": id, "targets": [actor]}
	if actor.hp < actor.max_hp() * 0.3:
		for id in inventory:
			if Data.items[id].get("kind") == "heal":
				return {"kind": "item", "id": id, "targets": [actor]}
	for s in actor.skills:
		var d: Dictionary = Data.skills[s]
		if d.get("kind") == "status" and d.get("target") == "self" and d.has("requires_hp_below") \
				and can_use(actor, "skill", s) and not actor.has_status(d.get("status", "")):
			return {"kind": "skill", "id": s, "targets": [actor]}
	var best := {"kind": "skill", "id": attack_id, "targets": [foes[0]]}
	var best_score := -1.0
	for s in [attack_id] + Array(actor.skills):
		var d: Dictionary = Data.skills[s]
		if not (d["kind"] in ["physical", "magic"]) or not can_use(actor, "skill", s):
			continue
		for t in foes:
			var score := _expected(actor, t, d) * float(d.get("accuracy", 1.0)) / float(d.get("delay", 1.0))
			if d.has("status") and not t.has_status(d["status"]):
				score *= 1.25
			if score > best_score:
				best_score = score
				best = {"kind": "skill", "id": s, "targets": [t]}
	if actor.mp < 2 and actor.hp > actor.max_hp() * 0.5 and rng.randf() < 0.3:
		return {"kind": "skill", "id": "defend", "targets": [actor]}
	return best


func _expected(actor: Battler, t: Battler, d: Dictionary) -> float:
	var physical: bool = d["kind"] == "physical"
	var a := actor.stat("atk" if physical else "mag")
	var def := t.stat("def" if physical else "res")
	var mult: float = t.affinity.get(d.get("element", ""), 1.0)
	return float(d.get("power", 100)) * a * a / (a + def) * mult


# ------------------------------------------------------------------ rewards
func rewards() -> Dictionary:
	var xp := 0
	var gold := 0
	var drops := {}
	for e in enemies:
		xp += e.exp_reward
		gold += e.gold_reward
		for item in e.drops:
			if rng.randf() < float(e.drops[item]):
				drops[item] = int(drops.get(item, 0)) + 1
	return {"exp": xp, "gold": gold, "drops": drops}
