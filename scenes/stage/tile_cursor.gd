class_name TileCursor
extends Node2D
## Mouse feedback drawn on the ground. HOVER: four ink corners on the tile under
## the pointer (gold over someone to talk to or something to look at, red where
## Derrick can't go). GOAL: a ring pulsing where a click is taking him.

enum Kind { HOVER, GOAL }

const TILE := 64.0
const WALK := Color("#e9dfc7")
const TALK := Color("#d8b24a")
const NO := Color("#b8322a")

var kind := Kind.HOVER
var color := WALK
var _t := 0.0


func _ready() -> void:
	z_index = 1


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func show_at(c: Vector2i, col: Color) -> void:
	position = Vector2(c) * TILE
	if col != color or not visible:
		_t = 0.0
	color = col
	visible = true


func _draw() -> void:
	var ink_base := Color(0.08, 0.07, 0.06)
	if kind == Kind.GOAL:
		# ink under paper, so it reads on pale grass and dark cobbles alike
		var k := fmod(_t * 1.4, 1.0)
		draw_set_transform(Vector2(TILE / 2.0, TILE - 7.0), 0.0, Vector2(1.0, 0.42))
		draw_arc(Vector2.ZERO, 9.0 + k * 16.0, 0.0, TAU, 40, Color(ink_base, 0.5 * (1.0 - k)), 6.0, true)
		draw_arc(Vector2.ZERO, 9.0 + k * 16.0, 0.0, TAU, 40, Color(color, 0.95 * (1.0 - k)), 3.0, true)
		draw_arc(Vector2.ZERO, 9.0, 0.0, TAU, 40, Color(ink_base, 0.75), 6.0, true)
		draw_arc(Vector2.ZERO, 9.0, 0.0, TAU, 40, color, 3.0, true)
		return
	var a := 0.75 + 0.2 * sin(_t * 5.0)
	var c := Color(color, a)
	var ink := Color(ink_base, a * 0.85)
	var m := 4.0
	var l := 14.0
	for corner in [Vector2(m, m), Vector2(TILE - m, m), Vector2(m, TILE - m), Vector2(TILE - m, TILE - m)]:
		var sx := 1.0 if corner.x < TILE / 2.0 else -1.0
		var sy := 1.0 if corner.y < TILE / 2.0 else -1.0
		for pass_i in 2:
			var w := 5.0 if pass_i == 0 else 2.5
			var col := ink if pass_i == 0 else c
			draw_line(corner, corner + Vector2(l * sx, 0), col, w, true)
			draw_line(corner, corner + Vector2(0, l * sy), col, w, true)
