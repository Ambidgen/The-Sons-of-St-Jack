extends CanvasLayer
## Scene changes with a fade, parameters for the next scene, global debug keys,
## and command-line hooks used for automated verification:
##   -- --shot=/tmp/a.png --shot-after=2.5   screenshot then quit
##   -- --auto                                auto-battle for Derrick
##   -- --turn-mode=ctb --encounter=hopeless  battle setup when running battle.tscn
##   -- --stage=s04_ashford                   read by stage.tscn when run directly
##   -- --quit-after-sec=20                   hard stop (smoke runs)

var params: Dictionary = {}
var _fade: ColorRect
var _debug_label: Label
var _speeds := [1.0, 2.0, 4.0]


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_fade)
	_debug_label = Label.new()
	_debug_label.position = Vector2(1160, 4)
	_debug_label.add_theme_font_size_override("font_size", 13)
	_debug_label.modulate = Color(1, 1, 1, 0.5)
	add_child(_debug_label)
	Engine.time_scale = float(Data.cfg("battle_speed", 1.0))
	_update_debug_label()
	_parse_cmdline()


## Change scene with a fade. `p` is readable by the next scene via Router.take_params().
func goto(scene_path: String, p: Dictionary = {}, fade_time := 0.35) -> void:
	params = p
	await fade_out(fade_time)
	get_tree().change_scene_to_file(scene_path)
	await get_tree().process_frame
	await get_tree().process_frame
	await fade_in(fade_time)


func fade_out(t := 0.35, color := Color.BLACK) -> void:
	_fade.color = Color(color, _fade.color.a)
	var tw := create_tween().set_ignore_time_scale(true)
	tw.tween_property(_fade, "color:a", 1.0, t)
	await tw.finished


func fade_in(t := 0.35) -> void:
	var tw := create_tween().set_ignore_time_scale(true)
	tw.tween_property(_fade, "color:a", 0.0, t)
	await tw.finished


func is_faded() -> bool:
	return _fade.color.a > 0.5


func take_params() -> Dictionary:
	var p := params
	params = {}
	return p


## Right click = cancel / back / field menu, everywhere: it becomes a ui_cancel
## action before any menu or the stage sees it.
func _input(event: InputEvent) -> void:
	var mb := event as InputEventMouseButton
	if mb and mb.button_index == MOUSE_BUTTON_RIGHT:
		get_viewport().set_input_as_handled()
		var a := InputEventAction.new()
		a.action = "ui_cancel"
		a.pressed = mb.pressed
		Input.parse_input_event(a)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F5:
				var i := _speeds.find(Engine.time_scale)
				Engine.time_scale = _speeds[(i + 1) % _speeds.size()]
				_update_debug_label()
			KEY_F1:
				Game.auto_battle = not Game.auto_battle
				_update_debug_label()
			KEY_F6:  # re-read data/*.json -- tune numbers and words without restarting
				Data.reload()
				_debug_label.text = "data reloaded"


func _update_debug_label() -> void:
	var parts: Array[String] = []
	if Engine.time_scale != 1.0:
		parts.append("x%d" % int(Engine.time_scale))
	if Game.auto_battle:
		parts.append("AUTO")
	_debug_label.text = "  ".join(parts)


func _parse_cmdline() -> void:
	var shot := ""
	var after := 1.5
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			shot = arg.trim_prefix("--shot=")
		elif arg.begins_with("--shot-after="):
			after = float(arg.trim_prefix("--shot-after="))
		elif arg == "--auto":
			Game.auto_battle = true
		elif arg.begins_with("--turn-mode="):      # ctb | round | atb
			Game.turn_mode = arg.trim_prefix("--turn-mode=")
		elif arg.begins_with("--encounter="):      # read by battle.tscn via take_params()
			params["encounter"] = arg.trim_prefix("--encounter=")
		elif arg.begins_with("--stage="):          # read by stage.tscn via take_params()
			params["stage"] = arg.trim_prefix("--stage=")
		elif arg.begins_with("--quit-after-sec="):
			_quit_later(float(arg.trim_prefix("--quit-after-sec=")))
	if shot != "":
		_screenshot_later(shot, after)


func _screenshot_later(path: String, seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("SHOT ", path)
	get_tree().quit()


func _quit_later(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout
	get_tree().quit()
