class_name DialogueBox
extends Control
## Bottom-of-screen dialogue: name tag, portrait, typewriter text, choices.
##   await box.play([{"who": "Mother", "portrait": "portrait/mother", "text": "..."}])
##   var i: int = await box.ask([{"text": "Take his hand."}, {"text": "Spit.", "defiant": true}])
## Per-line options: "speed" (chars/sec), "beat" (seconds before the line can be
## dismissed), "unskippable" (confirm can't rush the typewriter) -- this is how
## Saint Jack's lines make the player parse him at his own pace.

signal _advance
signal _picked(index: int)

const CHARS_PER_SEC := 48.0

var _panel: PanelContainer
var _name: Label
var _portrait: TextureRect
var _text: RichTextLabel
var _next: TextureRect
var _choices: VBoxContainer
var _help: Label
var _typing := false
var _waiting := false
var _unskippable := false
var _tween: Tween
var _jitter: Array = []         # [Button, strength] for degrading defiant options
var _t := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UIStyle.theme()
	_panel = UIStyle.panel()
	_panel.position = Vector2(130, 486)
	_panel.custom_minimum_size = Vector2(1020, 176)
	_panel.size = _panel.custom_minimum_size
	add_child(_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	_panel.add_child(row)
	_portrait = UIStyle.icon_rect(null, 146)
	row.add_child(_portrait)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 4)
	row.add_child(col)
	_name = UIStyle.label("", 22, UIStyle.ATB)
	col.add_child(_name)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.add_theme_font_override("normal_font", UIStyle.serif())
	_text.add_theme_font_override("italics_font", UIStyle.italic())
	_text.add_theme_font_size_override("normal_font_size", 23)
	_text.add_theme_font_size_override("italics_font_size", 23)
	col.add_child(_text)
	_next = UIStyle.icon_rect(Data.icon("cursor_down"), 20)
	_next.position = Vector2(1116, 636)
	_next.visible = false
	add_child(_next)
	_choices = VBoxContainer.new()
	add_child(_choices)
	_help = UIStyle.label("", 17, UIStyle.DIM)
	_help.visible = false
	add_child(_help)
	MenuCursor.attach(self)
	hide()


func _process(delta: float) -> void:
	_t += delta
	if _next.visible:
		_next.position.y = 636 + sin(_t * 6.0) * 3.0
	for j in _jitter:
		var b: Button = j[0]
		if is_instance_valid(b):
			var s: float = j[1]
			b.position.x = randf_range(-s, s) * 3.0
			b.modulate.a = 1.0 - s * 0.45 + sin(_t * 23.0) * s * 0.15


## Plays lines one by one. Returns when the last one is dismissed.
func play(lines: Array) -> void:
	show()
	_panel.show()
	for line in lines:
		await _show_line(line)
		_waiting = true
		_next.visible = true
		await _advance
		_next.visible = false
		_waiting = false
	hide()


func _show_line(line: Dictionary) -> void:
	_name.text = line.get("who", "")
	_name.visible = _name.text != ""
	_name.add_theme_color_override("font_color", Color(line.get("color", UIStyle.ATB.to_html())))
	_portrait.texture = Data.tex(line.get("portrait", ""))
	_portrait.visible = _portrait.texture != null
	var text: String = line.get("text", "")
	_text.text = text if _name.visible else "[i]%s[/i]" % text
	_text.visible_ratio = 0.0
	_typing = true
	_unskippable = line.get("unskippable", false)
	var speed: float = line.get("speed", CHARS_PER_SEC)
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_text, "visible_ratio", 1.0, maxf(0.05, _text.get_total_character_count() / speed))
	await _tween.finished
	_typing = false
	var beat: float = line.get("beat", 0.0)
	if beat > 0.0:
		await get_tree().create_timer(beat).timeout


## Shows a line (optional) and a choice list; returns the picked index.
## Option fields: text, disabled, defiant, help.
func ask(options: Array, prompt: Dictionary = {}) -> int:
	show()
	if prompt.is_empty():
		_panel.hide()
	else:
		_panel.show()
		await _show_line(prompt)
	for c in _choices.get_children():
		c.queue_free()
	_jitter.clear()
	var box := UIStyle.panel()
	_choices.add_child(box)
	var list := VBoxContainer.new()
	box.add_child(list)
	var complicity := int(Game.vars.get("complicity", 0))
	var glitch := int(Data.cfg("glitch_threshold", 40))
	var disable := int(Data.cfg("disable_threshold", 75))
	var first: Button = null
	for i in options.size():
		var o: Dictionary = options[i]
		var b := UIStyle.menu_button(o["text"])
		b.custom_minimum_size.x = 340
		var off: bool = o.get("disabled", false)
		if o.get("defiant", false):
			# Accomplice degradation: defiant options jitter and fade as Complicity rises.
			if complicity >= disable:
				off = true
			elif complicity >= glitch:
				_jitter.append([b, clampf(float(complicity - glitch) / float(disable - glitch), 0.2, 1.0)])
		b.disabled = off
		b.focus_mode = Control.FOCUS_ALL          # disabled options still explain themselves
		var help: String = o.get("help", "")
		b.focus_entered.connect(func() -> void:
			_help.text = help
			_help.visible = help != "")
		b.pressed.connect(func() -> void:
			if not b.disabled:
				_picked.emit(i))
		list.add_child(b)
		if first == null and not off:
			first = b
	if first == null:
		first = list.get_child(0)
	await get_tree().process_frame
	var bottom := 476.0 if _panel.visible else 420.0
	_choices.position = Vector2(1150 - box.size.x, bottom - box.size.y)
	_help.position = Vector2(_choices.position.x + 8, _choices.position.y - 28)
	first.grab_focus()
	var result: int = await _picked
	_jitter.clear()
	box.queue_free()
	_help.visible = false
	hide()
	return result


## True while a choice list is up (used by the tour).
func choosing() -> bool:
	return visible and _choices.get_child_count() > 0


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	var click: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel") or click:
		if _typing:
			get_viewport().set_input_as_handled()
			if _unskippable:
				return  # Saint Jack is not to be hurried
			_tween.custom_step(99.0)  # first press finishes the line
		elif _waiting:
			get_viewport().set_input_as_handled()
			_advance.emit()
