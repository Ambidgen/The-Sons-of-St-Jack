class_name BattleSim
extends RefCounted
## Runs whole battles instantly with AI on both sides -- no nodes, no waiting.
## BattleSim.run("dog", 200) -> win rate, turns, HP left, and how often Derrick
## walks away with a wound that never heals.

const MAX_TURNS := 400


static func run(encounter_id: String, count: int, mode: TurnQueue.Mode = TurnQueue.Mode.CTB) -> Dictionary:
	var wins := 0
	var scripted := 0
	var turns := 0
	var hp_left := 0.0
	var ko := 0
	var maims := 0
	var actions := 0
	for i in count:
		var r := BattleRules.for_encounter(encounter_id, mode, true, i)
		while r.outcome() == "" and r.turns < MAX_TURNS:
			var actor := r.next_actor(0.1)
			if actor == null:
				continue
			r.begin_turn(actor)
			if r.can_act(actor):
				r.resolve(actor, r.ai_choose(actor))
			else:
				r.pass_turn(actor)
		match r.outcome():
			"win":
				wins += 1
			"scripted":
				scripted += 1
		turns += r.turns
		actions += r.player_actions
		var hp := 0.0
		for a in r.allies:
			hp += float(a.hp) / a.max_hp()
			ko += 0 if a.hp > 0 else 1
			maims += a.new_wounds
		hp_left += hp / r.allies.size()
	return {
		"encounter": encounter_id, "battles": count,
		"win_rate": float(wins) / count,
		"scripted_rate": float(scripted) / count,
		"avg_turns": float(turns) / count,
		"avg_actions": float(actions) / count,
		"avg_party_hp": hp_left / count,
		"avg_kos": float(ko) / count,
		"maim_rate": float(maims) / count,
	}


static func report(stats: Dictionary) -> String:
	var head := "win %3d%%" % int(stats["win_rate"] * 100)
	if stats["scripted_rate"] > 0.0:
		head = "scripted %3d%%" % int(stats["scripted_rate"] * 100)
	return "%-15s %s  turns %4.1f  HP %3d%%  maimed %3d%%" % [
		stats["encounter"], head, stats["avg_turns"],
		int(stats["avg_party_hp"] * 100), int(stats["maim_rate"] * 100)]
