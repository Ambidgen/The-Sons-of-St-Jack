class_name Cinema
extends Control
## Screen-space film grammar for the stage: letterbox bars, chapter cards,
## narration captions, sound captions (stand-ins for audio), flashes, the
## cellar "slats" view and the act's title drop. Lives in a CanvasLayer above
## the world and below the dialogue box.

const BAR_H := 76.0

var _top: ColorRect
var _bottom: ColorRect
var _black: ColorRect
var _card_title: Label
var _card_sub: Label
var _caption: Label
var _sounds: VBoxContainer
var _flash: ColorRect
var _slats: Control
var _slits: Array[ColorRect] = []
var _shadow: ColorRect
var _slat_tween: Tween
var letterboxed := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UIStyle.theme()
	_top = _rect(Color.BLACK, Vector2(0, -BAR_H), Vector2(1280, BAR_H))
	_bottom = _rect(Color.BLACK, Vector2(0, 720), Vector2(1280, BAR_H))
	_black = _rect(Color(0, 0, 0, 0), Vector2.ZERO, Vector2(1280, 720))
	_build_slats()   # above the black, so it can fade in out of darkness
	_card_title = _centered_label(54, UIStyle.PAPER, 300)
	_card_sub = _centered_label(26, UIStyle.PAPER_DK, 380)
	_card_sub.add_theme_font_override("font", UIStyle.italic())
	_caption = _centered_label(27, UIStyle.PAPER, 560)
	_caption.add_theme_font_override("font", UIStyle.italic())
	_caption.autowrap_mode = TextServer.AUTOWRAP_WORD
	_caption.size.x = 1000
	_caption.position.x = 140
	_sounds = VBoxContainer.new()
	_sounds.position = Vector2(40, 96)
	add_child(_sounds)
	_flash = _rect(Color(1, 1, 1, 0), Vector2.ZERO, Vector2(1280, 720))


func _rect(c: Color, pos: Vector2, sz: Vector2) -> ColorRect:
	var r := ColorRect.new()
	r.color = c
	r.position = pos
	r.size = sz
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)
	return r


func _centered_label(size: int, color: Color, y: float) -> Label:
	var l := UIStyle.label("", size, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.position = Vector2(0, y)
	l.size = Vector2(1280, size * 1.6)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 8)
	l.modulate.a = 0.0
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


# ------------------------------------------------------------------ letterbox
func letterbox(on: bool, t := 0.6) -> void:
	letterboxed = on
	var tw := create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_top, "position:y", 0.0 if on else -BAR_H, t)
	tw.tween_property(_bottom, "position:y", 720.0 - BAR_H if on else 720.0, t)
	await tw.finished


# ------------------------------------------------------------------ cards
## Full-screen black card: TITLE / subtitle. Holds, then fades back to the world.
func card(title: String, sub: String, hold := 2.6, keep_black := false) -> void:
	_card_title.text = _spaced(title)
	_card_sub.text = sub
	var tw := create_tween()
	if _black.color.a < 1.0:
		tw.tween_property(_black, "color:a", 1.0, 0.5)
	tw.tween_property(_card_title, "modulate:a", 1.0, 0.7)
	tw.parallel().tween_property(_card_sub, "modulate:a", 1.0, 0.9).set_delay(0.35)
	tw.tween_interval(hold)
	tw.tween_property(_card_title, "modulate:a", 0.0, 0.6)
	tw.parallel().tween_property(_card_sub, "modulate:a", 0.0, 0.6)
	if not keep_black:
		tw.tween_property(_black, "color:a", 0.0, 0.9)
	await tw.finished


## Start fully black (a stage that opens on a chapter card must not flash the world first).
func set_black(a: float) -> void:
	_black.color.a = a


func black(on: bool, t := 0.8) -> void:
	var tw := create_tween()
	tw.tween_property(_black, "color:a", 1.0 if on else 0.0, t)
	await tw.finished


func _spaced(s: String) -> String:
	var out := ""
	for ch in s.to_upper():
		out += ch + " "
	return out.strip_edges()


# ------------------------------------------------------------------ captions
## Narration. hold > 0: auto-advance; hold == 0: wait for confirm.
func caption(text: String, hold := 0.0, center := false) -> void:
	_caption.text = text
	_caption.position.y = 318.0 if (center or _black.color.a > 0.5 or _slats.visible) else 548.0
	if _slats.visible:
		_caption.position.y = 470.0
	var tw := create_tween()
	tw.tween_property(_caption, "modulate:a", 1.0, 0.45)
	await tw.finished
	if hold > 0.0:
		await get_tree().create_timer(hold).timeout
	else:
		await get_tree().create_timer(0.35).timeout
		await _confirm()
	var tw2 := create_tween()
	tw2.tween_property(_caption, "modulate:a", 0.0, 0.35)
	await tw2.finished


func _confirm() -> void:
	while true:
		await get_tree().process_frame
		if Game.confirm_pressed() or Input.is_action_just_pressed("ui_cancel"):
			get_viewport().set_input_as_handled()
			return


## A subtitle for a sound we don't have yet: "[ Church bells, far off. ]"
func sound(text: String) -> void:
	var l := UIStyle.label("[ %s ]" % text, 19, UIStyle.PAPER_DK)
	l.add_theme_font_override("font", UIStyle.italic())
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 6)
	l.modulate.a = 0.0
	_sounds.add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "modulate:a", 1.0, 0.3)
	tw.tween_interval(3.4)
	tw.tween_property(l, "modulate:a", 0.0, 0.8)
	tw.tween_callback(l.queue_free)


func flash(color: Color, t := 0.5) -> void:
	_flash.color = Color(color, 0.85)
	var tw := create_tween()
	tw.tween_property(_flash, "color:a", 0.0, t)


# ------------------------------------------------------------------ cellar slats
func _build_slats() -> void:
	_slats = Control.new()
	_slats.set_anchors_preset(Control.PRESET_FULL_RECT)
	_slats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_slats.visible = false
	add_child(_slats)
	var bg := ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_slats.add_child(bg)
	for i in 6:
		var s := ColorRect.new()
		s.position = Vector2(200, 170 + i * 42)
		s.size = Vector2(880, 7 if i % 2 == 0 else 5)
		s.color = Color("#6b2c10")
		_slats.add_child(s)
		_slits.append(s)
	_shadow = ColorRect.new()
	_shadow.color = Color.BLACK
	_shadow.size = Vector2(160, 280)
	_shadow.position = Vector2(-300, 160)
	_slats.add_child(_shadow)


## The view up through the cellar boards: black, with firelight in the cracks.
func slats(on: bool) -> void:
	if on:
		_slats.visible = true
		_slats.modulate.a = 0.0
		var tw := create_tween()
		tw.tween_property(_slats, "modulate:a", 1.0, 1.2)
		_flicker()
		await tw.finished
	else:
		var tw := create_tween()
		tw.tween_property(_slats, "modulate:a", 0.0, 1.5)
		await tw.finished
		_slats.visible = false
		if _slat_tween:
			_slat_tween.kill()


func _flicker() -> void:
	if not _slats.visible:
		return
	_slat_tween = create_tween().set_parallel()
	for s in _slits:
		var c := Color("#e0701f").lerp(Color("#5a200a"), randf_range(0.0, 0.8))
		_slat_tween.tween_property(s, "color", c, randf_range(0.12, 0.35))
	_slat_tween.chain().tween_callback(_flicker)


## Someone crosses the floor above: a shadow wipes over the cracks.
func slats_shadow(seconds := 1.4, left_to_right := true) -> void:
	_shadow.position.x = -300.0 if left_to_right else 1300.0
	var tw := create_tween()
	tw.tween_property(_shadow, "position:x", 1300.0 if left_to_right else -300.0, seconds)
	await tw.finished


# ------------------------------------------------------------------ title drop
func title_drop(title: String, sub: String) -> void:
	await black(true, 1.2)
	_card_title.add_theme_font_size_override("font_size", 64)
	_card_title.text = _spaced(title)
	_card_title.position.y = 290
	_card_title.pivot_offset = Vector2(640, 40)
	_card_title.scale = Vector2(1.08, 1.08)
	_card_sub.text = sub
	var tw := create_tween()
	tw.tween_interval(0.8)
	tw.tween_property(_card_title, "modulate:a", 1.0, 2.2)
	tw.parallel().tween_property(_card_title, "scale", Vector2.ONE, 4.0).set_trans(Tween.TRANS_SINE)
	tw.tween_property(_card_sub, "modulate:a", 1.0, 1.4)
	tw.tween_interval(3.5)
	await tw.finished
