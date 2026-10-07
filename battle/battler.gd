class_name Battler
extends RefCounted
## One combatant. Plain data + stat maths, no nodes -- the headless simulator
## uses these directly. The battle scene keeps a separate BattlerView per Battler.

var key: String                 # actor or enemy id ("derrick", "dog")
var display_name: String
var is_ally := false
var sprite := ""
var base: Dictionary = {}       # max stats: hp mp atk def mag res spd
var hp := 0
var mp := 0
var skills: Array[String] = []
var affinity: Dictionary = {}   # element -> damage multiplier
var statuses: Dictionary = {}   # status id -> turns left
var member: Dictionary = {}     # the Game.party entry (allies only), written back after battle
var skip_turn := false          # set by BattleRules.begin_turn
var exp_reward := 0
var gold_reward := 0
var drops: Dictionary = {}
# Story-fight fields
var impunity := false           # every attack against it is evaded (Jack's Impunity)
var untargetable := false       # can't be picked as a target (the men you can't reach)
var yield_below := 0.0          # yields (ends the fight) under this HP fraction -- sparring
var yield_text := ""
var yielded := false
var new_wounds := 0             # wounds taken this battle (allies: become Game.wounds)
var wound_by := ""              # who dealt the last wounding blow


static func from_member(m: Dictionary, stats: Dictionary, skill_ids: Array[String]) -> Battler:
	var a: Dictionary = Data.actors[m["id"]]
	var b := Battler.new()
	b.key = m["id"]
	b.display_name = a["name"]
	b.is_ally = true
	b.sprite = Game.actor_art(m, "sprite")
	b.base = stats
	b.hp = clampi(int(m["hp"]), 0, int(stats["hp"]))
	b.mp = clampi(int(m["mp"]), 0, int(stats["mp"]))
	b.skills = skill_ids
	b.member = m   # old wounds are already in `stats` (Game.stats_of)
	return b


static func from_enemy(id: String, suffix := "") -> Battler:
	var e: Dictionary = Data.enemies[id]
	var b := Battler.new()
	b.key = id
	b.display_name = e["name"] + suffix
	b.sprite = e["sprite"]
	for s in e["stats"]:
		b.base[s] = int(e["stats"][s])
	b.hp = b.base["hp"]
	b.mp = b.base["mp"]
	for s in e.get("skills", ["attack"]):
		b.skills.append(s)
	b.affinity = e.get("affinity", {})
	b.exp_reward = int(e.get("exp", 0))
	b.gold_reward = int(e.get("gold", 0))
	b.drops = e.get("drops", {})
	b.impunity = e.get("impunity", false)
	b.untargetable = e.get("untargetable", false)
	b.yield_below = float(e.get("yield_below", 0.0))
	b.yield_text = e.get("yield_text", "%s yields." % e["name"])
	return b


## Standing and fighting. A yielded or downed battler is out of the fight.
func is_alive() -> bool:
	return hp > 0 and not yielded


func max_hp() -> int:
	return int(base["hp"])


func max_mp() -> int:
	return int(base["mp"])


## Current value of a stat after status modifiers ("mods": {"atk": 1.35}).
func stat(name: String) -> float:
	var v: float = base.get(name, 0)
	for s in statuses:
		v *= float(Data.statuses[s].get("mods", {}).get(name, 1.0))
	return maxf(v, 1.0)


func has_status(id: String) -> bool:
	return statuses.has(id)


## Multiplier applied to incoming damage by statuses such as Guard.
func damage_taken_mult() -> float:
	var m := 1.0
	for s in statuses:
		m *= float(Data.statuses[s].get("damage_taken", 1.0))
	return m
