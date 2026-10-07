class_name Pacing
extends RefCounted
## The narrative equivalent of the battle simulator. For every stage it:
##   * walks the route the story wants (start -> each beat -> exit) with BFS,
##   * proves every beat is unavoidable (block a trigger's cells: the exit must
##     become unreachable -- otherwise a player could wander past the story),
##   * estimates runtime from dialogue length, text speed, holds, walks and
##     simulated fight lengths,
##   * reports the longest stretch of walking with nothing happening.
## Tune the reading speed etc. in config.json -> "pacing".

static func analyze_all(sim_battles := 40) -> Array[Dictionary]:
	var saved := Game.to_dict().duplicate(true)
	var out: Array[Dictionary] = []
	for id in Data.act_order():
		var st: Dictionary = Data.stages[id]
		var c: Dictionary = st.get("derrick", {})
		Game.wounds = []
		Game.set_growth(c.get("form", "child"), int(c.get("level", 1)))
		Game.inventory = {"rag": 1}
		out.append(analyze(st, sim_battles))
	_restore(saved)
	return out


static func _restore(d: Dictionary) -> void:
	Game.party.clear()
	for m in d["party"]:
		Game.party.append(m)
	Game.form = d["form"]
	Game.wounds = d["wounds"]
	Game.inventory = d["inventory"]
	Game.flags = d["flags"]
	Game.vars = d["vars"]
	Game.stage_id = d["stage_id"]


static func analyze(st: Dictionary, sim_battles := 40) -> Dictionary:
	var p: Dictionary = Data.cfg("pacing", {})
	var step_t := float(Data.cfg("step_time", 0.2))
	var map := StageMap.new(st)
	var blk := map.cast_blockers()
	var problems: Array[String] = []

	# --- the story's route: nearest unplayed beat each time, then the exit
	var pos := map.start
	var remaining := map.triggers.keys()
	var route_steps := 0
	var gaps: Array[float] = []
	var order: Array[String] = []
	while not remaining.is_empty():
		var best := ""
		var best_path: Array[Vector2i] = []
		for letter in remaining:
			for c in map.triggers[letter]:
				var pth := map.path(pos, c, blk)
				if not pth.is_empty() and (best_path.is_empty() or pth.size() < best_path.size()):
					best_path = pth
					best = letter
		if best == "":
			problems.append("beats %s unreachable" % str(remaining))
			break
		route_steps += best_path.size() - 1
		gaps.append((best_path.size() - 1) * step_t)
		pos = best_path[best_path.size() - 1]
		remaining.erase(best)
		order.append(best)
	if not map.exits.is_empty():
		var best_exit: Array[Vector2i] = []
		for e in map.exits:
			var pth := map.path(pos, e, blk)
			if not pth.is_empty() and (best_exit.is_empty() or pth.size() < best_exit.size()):
				best_exit = pth
		if best_exit.is_empty():
			problems.append("exit unreachable after the last beat")
		else:
			route_steps += best_exit.size() - 1
			gaps.append((best_exit.size() - 1) * step_t)

	# --- linearity: every beat must stand between the start and the goal
	var goal_cells: Array[Vector2i] = map.exits.duplicate()
	if goal_cells.is_empty() and not order.is_empty():
		goal_cells = map.triggers[order[order.size() - 1]].duplicate()
	for letter in map.triggers:
		if goal_cells.size() > 0 and map.triggers[letter].has(goal_cells[0]):
			continue
		var cut := blk.duplicate()
		for c in map.triggers[letter]:
			cut[c] = true
		var seen := map.reachable(map.start, cut)
		for g in goal_cells:
			if seen.has(g):
				problems.append("beat '%s' (%s) can be walked around" % [letter, st.get("triggers", {}).get(letter, "")])
				break

	# --- runtime of the scripts that will play
	var t := {"scene": 0.0, "battle": 0.0}
	var scripts: Dictionary = st.get("scripts", {})
	for key in ["on_enter", "on_exit"]:
		if st.has(key):
			_script_time(scripts.get(st[key], []), scripts, t, p, sim_battles)
	for letter in order:
		_script_time(scripts.get(st["triggers"][letter], []), scripts, t, p, sim_battles)

	var walk_sec := route_steps * step_t
	var max_gap := 0.0
	for g in gaps:
		max_gap = maxf(max_gap, g)
	if max_gap > float(p.get("max_beat_gap_sec", 15.0)):
		problems.append("%.0fs of walking with nothing happening" % max_gap)
	var walkable := map.reachable(map.start, blk).size()
	return {
		"id": st["id"], "name": st.get("chapter", st.get("name", st["id"])), "beats": order.size(),
		"walk_sec": walk_sec, "scene_sec": t["scene"], "battle_sec": t["battle"],
		"total_sec": walk_sec + t["scene"] + t["battle"], "max_gap_sec": max_gap,
		"route_steps": route_steps, "open_ratio": float(walkable) / maxf(1.0, route_steps),
		"problems": problems,
	}


static func _script_time(cmds: Array, scripts: Dictionary, t: Dictionary, p: Dictionary, sims: int) -> void:
	var read_cps := float(p.get("read_chars_per_sec", 17.0))
	var overhead := float(p.get("line_overhead", 0.7))
	for c in cmds:
		var op := Data.command_name(c)
		match op:
			"card":
				t["scene"] += float(c.get("hold", 2.6)) + 2.7
			"caption":
				var hold := float(c.get("hold", 0.0))
				t["scene"] += (hold if hold > 0.0 else c["caption"].length() / read_cps + overhead) + 0.8
			"say":
				t["scene"] += _line_time(c["say"], c["text"], read_cps, overhead)
			"talk":
				for l in c["talk"]:
					t["scene"] += _line_time(l[0], l[1], read_cps, overhead)
			"choice":
				t["scene"] += 3.0
				_script_time(c["choice"][0].get("then", []), scripts, t, p, sims)
			"walk":
				if c.get("wait", true):
					var steps := 0
					var wps: Array = c.get("path", [c.get("to", [0, 0])])
					steps = 6 * wps.size()  # rough: legs average ~6 tiles
					t["scene"] += steps / float(c.get("speed", 4.0))
			"camera":
				if c.get("wait", true):
					t["scene"] += float(c.get("time", 1.0))
			"wait":
				t["scene"] += float(c["wait"])
			"fade":
				t["scene"] += float(c.get("time", 0.8))
			"slats":
				t["scene"] += 1.4
			"slats_shadow":
				t["scene"] += float(c["slats_shadow"])
			"title_drop":
				t["scene"] += 11.0
			"growth":
				t["scene"] += 4.0
			"show", "hide", "fall", "rise":
				t["scene"] += 0.4
			"act":
				if c.get("wait", false):
					t["scene"] += float(Rig.ACTION_LEN.get(c.get("do", ""), 0.4))
			"battle":
				var s := BattleSim.run(c["battle"], sims, TurnQueue.mode_from_string(Data.cfg("turn_mode", "atb")))
				t["battle"] += s["avg_turns"] * float(p.get("sec_per_battle_turn", 2.4)) + 5.0
				_script_time(c.get("win", c.get("then", [])), scripts, t, p, sims)
			"if":
				_script_time(c.get("then", []), scripts, t, p, sims)
			"run":
				_script_time(scripts.get(c["run"], []), scripts, t, p, sims)


static func _line_time(who: String, text: String, read_cps: float, overhead: float) -> float:
	var c: Dictionary = Data.cast.get(who, {})
	var typing := text.length() / float(c.get("text_speed", 48.0))
	return maxf(typing, text.length() / read_cps) + overhead + float(c.get("beat", 0.0))


static func clock(sec: float) -> String:
	return "%d:%02d" % [int(sec) / 60, int(sec) % 60]


static func report(r: Dictionary) -> String:
	var ok := "OK" if r["problems"].is_empty() else "CHECK: " + "; ".join(r["problems"])
	return "%-27s %s  walk %s  scenes %s  fights %s  beats %d  longest quiet walk %4.1fs  %s" % [
		r["name"], clock(r["total_sec"]), clock(r["walk_sec"]), clock(r["scene_sec"]),
		clock(r["battle_sec"]), r["beats"], r["max_gap_sec"], ok]
