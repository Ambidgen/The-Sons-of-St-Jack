class_name TurnQueue
extends RefCounted
## Decides who acts next. Three classic JRPG models behind one interface:
##   CTB   - conditional turn-based: every battler has a "next act" time; actions
##           have a delay multiplier, so fast/slow moves reshape the visible order.
##   ROUND - everyone acts once per round, sorted by speed (with a little jitter).
##   ATB   - gauges fill in real time with speed; full gauge = your turn.
## advance(delta) returns the next actor, or null while ATB gauges are filling.

enum Mode { CTB, ROUND, ATB }

const CTB_BASE := 100.0   # time units per action at speed 1

var mode: Mode
var battlers: Array[Battler] = []
var atb_fill := 0.12      # ATB gauge per second per speed point
var rng: RandomNumberGenerator
var _t: Dictionary = {}   # Battler -> next act time (CTB) or gauge 0..1 (ATB)
var _round: Array[Battler] = []
var round_number := 0


static func mode_from_string(s: String) -> Mode:
	match s.to_lower():
		"round":
			return Mode.ROUND
		"atb":
			return Mode.ATB
	return Mode.CTB


func _init(p_mode: Mode, p_battlers: Array[Battler], p_rng: RandomNumberGenerator) -> void:
	mode = p_mode
	battlers = p_battlers
	rng = p_rng
	for b in battlers:
		if mode == Mode.ATB:
			_t[b] = rng.randf_range(0.0, 0.4)
		else:
			_t[b] = CTB_BASE / b.stat("spd") * rng.randf_range(0.6, 1.0)


func advance(delta: float) -> Battler:
	match mode:
		Mode.CTB:
			return _soonest(_t)
		Mode.ROUND:
			while true:
				if _round.is_empty():
					_start_round()
				if _round.is_empty():
					return null
				var b: Battler = _round.pop_front()
				if b.is_alive():
					return b
		Mode.ATB:
			var ready: Battler = null
			for b in battlers:
				if not b.is_alive():
					continue
				_t[b] = minf(1.0, _t[b] + delta * atb_fill * b.stat("spd") / 10.0)
				if _t[b] >= 1.0 and (ready == null or b.stat("spd") > ready.stat("spd")):
					ready = b
			return ready
	return null


## Call once after the actor's action resolves. delay_mult comes from the action
## (Brace 0.6 = acts again sooner, heavy skills 1.3+ = later).
func end_turn(b: Battler, delay_mult := 1.0) -> void:
	match mode:
		Mode.CTB:
			_t[b] = _t[b] + CTB_BASE / b.stat("spd") * delay_mult
		Mode.ATB:
			_t[b] = clampf(1.0 - delay_mult, -0.5, 0.9)


## Revived battlers rejoin at the back.
func rejoin(b: Battler) -> void:
	if mode == Mode.CTB:
		var latest := 0.0
		for o in battlers:
			if o.is_alive() and o != b:
				latest = maxf(latest, _t[o])
		_t[b] = latest
	elif mode == Mode.ATB:
		_t[b] = 0.0


## ATB gauge 0..1 for the UI (CTB/ROUND report 0).
func gauge(b: Battler) -> float:
	return clampf(_t.get(b, 0.0), 0.0, 1.0) if mode == Mode.ATB else 0.0


## Upcoming actors, first = whoever acts next. If `actor` + `delay_mult` are given
## (CTB), shows the order as if `actor` had just used an action with that delay.
func preview(count: int, actor: Battler = null, delay_mult := 1.0) -> Array[Battler]:
	var out: Array[Battler] = []
	match mode:
		Mode.CTB:
			var t := _t.duplicate()
			if actor:
				t[actor] = t[actor] + CTB_BASE / actor.stat("spd") * delay_mult
			while out.size() < count:
				var b := _soonest(t)
				if b == null:
					break
				out.append(b)
				t[b] = t[b] + CTB_BASE / b.stat("spd")
		Mode.ROUND:
			for b in _round:
				if b.is_alive():
					out.append(b)
			var guard := 0
			while out.size() < count and guard < 20:   # following rounds, in speed order
				guard += 1
				for b in _sorted_by_speed():
					if out.size() >= count:
						break
					out.append(b)
		Mode.ATB:
			var alive := _living()
			alive.sort_custom(func(a: Battler, b: Battler) -> bool:
				return (1.0 - _t[a]) / a.stat("spd") < (1.0 - _t[b]) / b.stat("spd"))
			out = alive
	return out.slice(0, count)


func _soonest(times: Dictionary) -> Battler:
	var best: Battler = null
	for b in battlers:
		if b.is_alive() and (best == null or times[b] < times[best]):
			best = b
	return best


func _start_round() -> void:
	round_number += 1
	_round = _sorted_by_speed()


func _sorted_by_speed() -> Array[Battler]:
	var list := _living()
	var roll := {}
	for b in list:
		roll[b] = b.stat("spd") * rng.randf_range(0.85, 1.15)
	list.sort_custom(func(a: Battler, b: Battler) -> bool: return roll[a] > roll[b])
	return list


func _living() -> Array[Battler]:
	var out: Array[Battler] = []
	for b in battlers:
		if b.is_alive():
			out.append(b)
	return out
