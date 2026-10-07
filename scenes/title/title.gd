extends Control
## Title screen, Chapter Select and the Battle Lab.
## The lab is the workbench: fight any story encounter at any of Derrick's ages,
## switch turn systems, run the battle simulator, and run the pacing report
## (runtime per stage, longest quiet walk, and a check that no beat can be skipped).

const MODES := ["atb", "ctb", "round"]
const AGES := [["child", 1, "nine"], ["youth", 3, "thirteen"], ["lad", 5, "sixteen"], ["man", 7, "twenty"], ["man", 9, "twenty-one"]]

var _main: VBoxContainer
var _chapters: PanelContainer
var _chapter_list: VBoxContainer
var _lab: PanelContainer
var _lab_list: VBoxContainer
var _sim_out: Label
var _mode_btn: Button
var _age_btn: Button
var _age_i := 4


func _ready() -> void:
	theme = UIStyle.theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := TextureRect.new()
	bg.texture = Data.tex("bg/title")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var title := UIStyle.label("THE SONS OF ST. JACK", 64, UIStyle.INK)
	title.add_theme_color_override("font_outline_color", UIStyle.PAPER)
	title.add_theme_constant_override("outline_size", 10)
	title.position = Vector2(70, 60)
	add_child(title)
	var sub := UIStyle.label("Act One  -  a linear vertical slice (prototype, placeholder art)", 22, UIStyle.INK)
	sub.add_theme_font_override("font", UIStyle.italic())
	sub.add_theme_color_override("font_outline_color", UIStyle.PAPER)
	sub.add_theme_constant_override("outline_size", 6)
	sub.position = Vector2(76, 146)
	add_child(sub)

	var panel := UIStyle.panel()
	panel.position = Vector2(70, 300)
	panel.custom_minimum_size = Vector2(300, 0)
	add_child(panel)
	_main = VBoxContainer.new()
	panel.add_child(_main)
	_main.add_child(_button("Begin Act One", _new_game))
	var cont := _button("Continue", _continue)
	cont.disabled = not Game.has_save()
	_main.add_child(cont)
	_main.add_child(_button("Chapter Select", _open_chapters))
	_main.add_child(_button("Battle Lab", _open_lab))
	_main.add_child(_button("Quit", get_tree().quit))
	if Game.flags.get("act_one_complete", false):
		var done := UIStyle.label("Act One complete.  Complicity %d   Defiance %d" % [
				int(Game.vars.get("complicity", 0)), int(Game.vars.get("defiance", 0))], 18, UIStyle.INK)
		done.position = Vector2(76, 186)
		add_child(done)
	_build_chapters()
	_build_lab()
	MenuCursor.attach(self)
	_main.get_child(0).grab_focus()


func _button(text: String, cb: Callable) -> Button:
	var b := UIStyle.menu_button(text)
	b.pressed.connect(cb)
	return b


func _new_game() -> void:
	Game.new_game()
	Router.goto("res://scenes/stage/stage.tscn", {"stage": Game.stage_id, "fresh": true}, 1.0)


func _continue() -> void:
	if Game.load_game():
		Router.goto("res://scenes/stage/stage.tscn", {"stage": Game.stage_id, "fresh": false}, 1.0)


# ------------------------------------------------------------------ chapters
func _build_chapters() -> void:
	_chapters = UIStyle.panel()
	_chapters.position = Vector2(400, 56)
	_chapters.custom_minimum_size = Vector2(620, 0)
	add_child(_chapters)
	_chapter_list = VBoxContainer.new()
	_chapters.add_child(_chapter_list)
	_chapter_list.add_child(UIStyle.label("Start from any beat of Act One", 18, UIStyle.DIM))
	for id in Data.act_order():
		var st: Dictionary = Data.stages[id]
		var b := UIStyle.menu_button(st.get("chapter", id), null, st.get("age", ""))
		b.custom_minimum_size.x = 580
		b.pressed.connect(_jump.bind(id))
		_chapter_list.add_child(b)
	_chapter_list.add_child(_button("Back", _close_chapters))
	_chapters.hide()


func _open_chapters() -> void:
	_chapters.show()
	_chapter_list.get_child(1).grab_focus()


func _close_chapters() -> void:
	_chapters.hide()
	_main.get_child(2).grab_focus()


func _jump(id: String) -> void:
	Game.new_game()
	Game.stage_id = id
	Router.goto("res://scenes/stage/stage.tscn", {"stage": id, "fresh": true}, 0.8)


# ------------------------------------------------------------------ battle lab
func _build_lab() -> void:
	_lab = UIStyle.panel()
	_lab.position = Vector2(400, 200)
	_lab.custom_minimum_size = Vector2(860, 500)
	add_child(_lab)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	_lab.add_child(row)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(300, 470)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	row.add_child(scroll)
	_lab_list = VBoxContainer.new()
	_lab_list.custom_minimum_size.x = 290
	scroll.add_child(_lab_list)
	_lab_list.add_child(UIStyle.label("Fight an encounter", 18, UIStyle.DIM))
	for id in Data.encounters:
		var enc: Dictionary = Data.encounters[id]
		_lab_list.add_child(_button(enc.get("name", id), _fight.bind(id)))
	_lab_list.add_child(HSeparator.new())
	_mode_btn = _button("", _cycle_mode)
	_lab_list.add_child(_mode_btn)
	_age_btn = _button("", _cycle_age)
	_lab_list.add_child(_age_btn)
	_lab_list.add_child(_button("Simulate all x200", _simulate))
	_lab_list.add_child(_button("Pacing report", _pacing))
	_lab_list.add_child(_button("Back", _close_lab))
	_sim_out = UIStyle.label("Simulator output appears here.\n\nIn battle: F1 auto-battle, F2 win / end,\nF3 heal, F5 speed x1/x2/x4.\nOn a stage: F4 skip to the next beat.\nAnywhere: F6 reload data/*.json", 17, UIStyle.DIM)
	_sim_out.custom_minimum_size.x = 520
	_sim_out.autowrap_mode = TextServer.AUTOWRAP_WORD
	row.add_child(_sim_out)
	_refresh_lab()
	_lab.hide()


func _refresh_lab() -> void:
	var mode: String = Game.turn_mode if Game.turn_mode != "" else Data.cfg("turn_mode", "atb")
	_mode_btn.text = "Turn system: " + mode.to_upper()
	var a: Array = AGES[_age_i]
	_age_btn.text = "Derrick: age %s (Lv %d)" % [a[2], a[1]]


func _open_lab() -> void:
	_lab.show()
	_apply_age()
	_lab_list.get_child(1).grab_focus()


func _close_lab() -> void:
	_lab.hide()
	_main.get_child(3).grab_focus()


func _cycle_mode() -> void:
	var cur: String = Game.turn_mode if Game.turn_mode != "" else Data.cfg("turn_mode", "atb")
	Game.turn_mode = MODES[(MODES.find(cur) + 1) % MODES.size()]
	_refresh_lab()


func _cycle_age() -> void:
	_age_i = (_age_i + 1) % AGES.size()
	_apply_age()
	_refresh_lab()


func _apply_age() -> void:
	var a: Array = AGES[_age_i]
	Game.set_growth(a[0], a[1])
	if not Game.inventory.has("rag"):
		Game.add_item("rag", 2)


func _fight(id: String) -> void:
	Game.heal_party()
	Router.goto("res://scenes/battle/battle.tscn", {"encounter": id, "return_to": scene_file_path})


func _simulate() -> void:
	var mode := TurnQueue.mode_from_string(Game.turn_mode if Game.turn_mode != "" else Data.cfg("turn_mode", "atb"))
	var a: Array = AGES[_age_i]
	var lines: Array[String] = ["Derrick age %s (Lv %d), %s, 200 fights each:" % [a[2], a[1], ["ctb", "round", "atb"][mode]]]
	for id in Data.encounters:
		lines.append(BattleSim.report(BattleSim.run(id, 200, mode)))
	_show_mono("\n".join(lines))


func _pacing() -> void:
	var lines: Array[String] = ["Act One pacing (estimated at a normal reading speed):"]
	var total := 0.0
	for r in Pacing.analyze_all(30):
		lines.append(Pacing.report(r))
		total += r["total_sec"]
	lines.append("Act One total: %s" % Pacing.clock(total))
	_apply_age()
	_show_mono("\n".join(lines))


func _show_mono(text: String) -> void:
	_sim_out.text = text
	_sim_out.autowrap_mode = TextServer.AUTOWRAP_OFF
	_sim_out.add_theme_color_override("font_color", UIStyle.TEXT)
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Consolas", "DejaVu Sans Mono", "Menlo", "monospace"])
	_sim_out.add_theme_font_override("font", f)
	_sim_out.add_theme_font_size_override("font_size", 11)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if _lab.visible:
		get_viewport().set_input_as_handled()
		_close_lab()
	elif _chapters.visible:
		get_viewport().set_input_as_handled()
		_close_chapters()
