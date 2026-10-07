class_name BattleHUD
extends Control
## Battle UI: turn-order bar, help/message line, Derrick's status panel, command
## menu, skill/item list, target cursor, and "barks" -- lines spoken mid-fight
## (Saint Jack's at his own slow pace). choose_action() drives the
## Command -> List -> Target flow and returns the finished action.

signal chosen(action: Dictionary)

enum Mode { IDLE, COMMAND, LIST, TARGET }

const CMD_HELP := {"attack": "Hit them with whatever's in your hand.", "skill": "Things the years have taught you.",
		"item": "What little you carry.", "flee": "Run. There's no shame left to lose."}

var mode := Mode.IDLE
var rules: BattleRules
var views: Dictionary              # Battler -> BattlerView
var actor: Battler                 # whose menu is open
var current: Battler               # whose turn it is (set by the battle scene)

var _help: Label
var _help_panel: PanelContainer
var _order_row: HBoxContainer
var _party_rows: Dictionary = {}   # Battler -> {panel, hp, hp_bar, mp, mp_bar, atb, status}
var _party_panel: PanelContainer
var _wound_label: Label
var _cmd_panel: PanelContainer
var _cmd_grid: GridContainer
var _list_panel: PanelContainer
var _list: GridContainer
var _list_kind := ""
var _pending: Dictionary = {}      # action waiting for a target
var _targets: Array[Battler] = []
var _target_i := 0
var _cursors: Array[TextureRect] = []
var _bob := 0.0
var _bark_panel: PanelContainer
var _bark_name: Label
var _bark_text: RichTextLabel
var _bark_portrait: TextureRect
var _pointing := false


func setup(p_rules: BattleRules, p_views: Dictionary) -> void:
	rules = p_rules
	views = p_views
	theme = UIStyle.theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_top()
	_build_party_panel()
	_build_menus()
	_build_bark()
	MenuCursor.attach(self)
	refresh()


# ------------------------------------------------------------------ layout
func _build_top() -> void:
	_order_row = HBoxContainer.new()
	_order_row.position = Vector2(16, 12)
	_order_row.add_theme_constant_override("separation", 4)
	add_child(_order_row)
	_help_panel = UIStyle.panel()
	_help_panel.position = Vector2(390, 96)
	_help_panel.custom_minimum_size = Vector2(500, 0)
	add_child(_help_panel)
	_help = UIStyle.label("", 21)
	_help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_help.autowrap_mode = TextServer.AUTOWRAP_WORD     # long narration lines wrap
	_help.custom_minimum_size.x = 470
	_help_panel.add_child(_help)
	_help_panel.hide()


func _build_party_panel() -> void:
	var panel := UIStyle.panel()
	panel.position = Vector2(318, 560)
	panel.custom_minimum_size = Vector2(946, 144)
	add_child(panel)
	_party_panel = panel
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)
	var atb := rules.queue.mode == TurnQueue.Mode.ATB
	for b in rules.allies:
		var row_panel := PanelContainer.new()
		var hl := StyleBoxFlat.new()
		hl.bg_color = Color(0, 0, 0, 0)
		hl.set_content_margin_all(6)
		row_panel.add_theme_stylebox_override("panel", hl)
		col.add_child(row_panel)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		row_panel.add_child(row)
		row.add_child(UIStyle.icon_rect(Data.tex(Game.actor_art(b.member, "portrait")), 64))
		var name_label := UIStyle.label(b.display_name, 24, UIStyle.ATB)
		name_label.custom_minimum_size.x = 110
		row.add_child(name_label)
		var r := {"panel": hl}
		for stat in ["hp", "mp"]:
			row.add_child(UIStyle.label("HP" if stat == "hp" else "GRIT", 16, UIStyle.DIM))
			var bar := UIStyle.bar(UIStyle.HP if stat == "hp" else UIStyle.MP, 190 if stat == "hp" else 100, 12)
			row.add_child(bar)
			var num := UIStyle.label("", 21)
			num.custom_minimum_size.x = 92 if stat == "hp" else 60
			row.add_child(num)
			r[stat] = num
			r[stat + "_bar"] = bar
		var gauge := UIStyle.bar(UIStyle.ATB, 90, 8)
		gauge.visible = atb
		gauge.max_value = 1.0
		gauge.step = 0.0
		row.add_child(gauge)
		r["atb"] = gauge
		var status := HBoxContainer.new()
		row.add_child(status)
		r["status"] = status
		_party_rows[b] = r
	_wound_label = UIStyle.label("", 16, UIStyle.DIM)
	col.add_child(_wound_label)


func _build_menus() -> void:
	_cmd_panel = UIStyle.panel()
	_cmd_panel.position = Vector2(16, 560)
	_cmd_panel.custom_minimum_size = Vector2(286, 144)
	add_child(_cmd_panel)
	_cmd_grid = GridContainer.new()
	_cmd_grid.columns = 2
	_cmd_panel.add_child(_cmd_grid)
	var cmds := [["Strike", "attack"], ["Skills", "skill"], ["Items", "item"], ["Brace", "defend"], ["Run", "flee"]]
	for c in cmds:
		var b := UIStyle.menu_button(c[0], Data.icon(c[1]))
		b.custom_minimum_size = Vector2(128, 40)
		b.name = c[1]
		b.pressed.connect(_on_command.bind(c[1]))
		b.focus_entered.connect(_on_command_focus.bind(c[1]))
		_cmd_grid.add_child(b)
	_cmd_panel.hide()

	_list_panel = UIStyle.panel()
	_list_panel.position = Vector2(318, 560)
	_list_panel.custom_minimum_size = Vector2(946, 144)
	add_child(_list_panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	scroll.custom_minimum_size = Vector2(920, 118)
	_list_panel.add_child(scroll)
	_list = GridContainer.new()
	_list.columns = 2
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	_list_panel.hide()


func _build_bark() -> void:
	_bark_panel = UIStyle.panel()
	_bark_panel.position = Vector2(250, 150)
	_bark_panel.custom_minimum_size = Vector2(780, 0)
	add_child(_bark_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	_bark_panel.add_child(row)
	_bark_portrait = UIStyle.icon_rect(null, 84)
	row.add_child(_bark_portrait)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(col)
	_bark_name = UIStyle.label("", 20, UIStyle.ATB)
	col.add_child(_bark_name)
	_bark_text = RichTextLabel.new()
	_bark_text.fit_content = true
	_bark_text.scroll_active = false
	_bark_text.custom_minimum_size = Vector2(640, 0)
	_bark_text.add_theme_font_override("normal_font", UIStyle.serif())
	_bark_text.add_theme_font_size_override("normal_font_size", 22)
	col.add_child(_bark_text)
	_bark_panel.hide()


# ------------------------------------------------------------------ refresh
func refresh() -> void:
	for b in _party_rows:
		var r: Dictionary = _party_rows[b]
		r["hp"].text = "%d/%d" % [b.hp, b.max_hp()]
		r["hp_bar"].max_value = b.max_hp()
		r["hp_bar"].value = b.hp
		UIStyle.set_bar_color(r["hp_bar"], UIStyle.HP if b.hp > b.max_hp() * 0.3 else UIStyle.HP_LOW)
		r["hp"].add_theme_color_override("font_color", UIStyle.TEXT if b.hp > 0 else UIStyle.HP_LOW)
		r["mp"].text = "%d/%d" % [b.mp, b.max_mp()]
		r["mp_bar"].max_value = b.max_mp()
		r["mp_bar"].value = b.mp
		r["panel"].bg_color = UIStyle.HILITE if b == current else Color(0, 0, 0, 0)
		var status: HBoxContainer = r["status"]
		for c in status.get_children():
			c.queue_free()
		for s in b.statuses:
			status.add_child(UIStyle.icon_rect(Data.icon(Data.statuses[s]["icon"]), 24))
		var old: int = Game.wounds.size()
		var fresh: int = b.new_wounds
		if old + fresh > 0:
			_wound_label.text = "Old wounds: %d%s   (each one costs max HP and strength for good)" % [
					old, "   New today: %d" % fresh if fresh > 0 else ""]
		else:
			_wound_label.text = "Any single blow over %d%% of your HP leaves a wound that never heals." % int(float(Data.cfg("maim_threshold", 0.4)) * 100)
	for v in views.values():
		v.refresh()
	refresh_gauges()
	show_order()


func refresh_gauges() -> void:
	if rules.queue.mode != TurnQueue.Mode.ATB:
		return
	for b in _party_rows:
		_party_rows[b]["atb"].value = rules.queue.gauge(b)


## Turn-order strip. In CTB, pass the actor + a delay to preview an action.
func show_order(preview_actor: Battler = null, delay := 1.0) -> void:
	for c in _order_row.get_children():
		c.queue_free()
	if rules.queue.mode == TurnQueue.Mode.ATB:
		return
	var order: Array[Battler] = []
	var head: Battler = preview_actor if preview_actor else current
	var rest := rules.queue.preview(9, preview_actor, delay)
	if head and head.is_alive() and (rest.is_empty() or rest[0] != head):
		order.append(head)
	order.append_array(rest)
	order = order.slice(0, 9)
	for i in order.size():
		var b := order[i]
		var box := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(UIStyle.BG, 0.9)
		sb.border_color = UIStyle.ALLY if b.is_ally else UIStyle.ENEMY
		sb.set_border_width_all(3 if i == 0 else 2)
		sb.set_content_margin_all(2)
		if preview_actor and b == preview_actor and i > 0:
			sb.bg_color = Color(UIStyle.ATB, 0.45)   # where your next turn lands
		box.add_theme_stylebox_override("panel", sb)
		box.add_child(UIStyle.icon_rect(Data.tex(b.sprite), 56 if i == 0 else 42))
		_order_row.add_child(box)


func set_help(text: String) -> void:
	_help.text = text
	_help_panel.visible = text != ""
	_help_panel.reset_size()
	_help_panel.position.x = 640 - _help_panel.size.x / 2


func show_message(text: String, seconds := 0.8) -> void:
	set_help(text)
	await get_tree().create_timer(seconds).timeout
	set_help("")


## A line spoken mid-fight. Uses the speaker's text speed and parse beat.
func bark(who: String, text: String) -> void:
	var c: Dictionary = Data.cast.get(who, {})
	_bark_name.visible = who != ""          # who == "": narration, no speaker
	_bark_portrait.visible = who != ""
	_bark_name.text = c.get("name", who)
	_bark_name.add_theme_color_override("font_color", Color(c.get("color", UIStyle.ATB.to_html())))
	_bark_portrait.texture = Data.tex(c.get("portrait", ""))
	_bark_text.text = text
	_bark_text.visible_ratio = 0.0
	_bark_panel.show()
	_bark_panel.reset_size()
	var speed: float = c.get("text_speed", 48.0)
	var tw := create_tween()
	tw.tween_property(_bark_text, "visible_ratio", 1.0, maxf(0.1, text.length() / speed))
	var skippable: bool = not c.get("unskippable", false)
	while tw.is_running():
		await get_tree().process_frame
		if skippable and Game.confirm_pressed():
			tw.custom_step(99.0)
	await get_tree().create_timer(float(c.get("beat", 0.0)) + 0.5).timeout
	var t := 0.0
	var hold := 1.2 + text.length() / 40.0
	while t < hold:
		await get_tree().process_frame
		t += get_process_delta_time()
		if Game.confirm_pressed():
			break
	_bark_panel.hide()


# ------------------------------------------------------------------ choosing
func choose_action(p_actor: Battler) -> Dictionary:
	actor = p_actor
	refresh()
	_open_commands()
	var action: Dictionary = await chosen
	_close_all()
	return action


## Abort the menus with a given action (debug keys use this).
func force(action: Dictionary) -> void:
	if mode != Mode.IDLE:
		chosen.emit(action)


func _open_commands(focus_name := "attack") -> void:
	mode = Mode.COMMAND
	_list_panel.hide()
	_party_panel.show()
	_clear_cursors()
	_cmd_panel.show()
	var atk: Button = _cmd_grid.get_node("attack")
	atk.text = rules.encounter.get("attack_label", "Strike")
	atk.icon = Data.icon(Data.skills[rules.attack_id].get("icon", "attack"))
	(_cmd_grid.get_node("skill") as Button).disabled = actor.skills.is_empty()
	(_cmd_grid.get_node("item") as Button).disabled = rules.inventory.is_empty() or rules.encounter.get("no_items", false)
	var f: Button = _cmd_grid.get_node(focus_name)
	if f.disabled:
		f = _cmd_grid.get_node("attack")
	f.grab_focus()


func _on_command_focus(cmd: String) -> void:
	var text: String = CMD_HELP.get(cmd, "")
	if cmd == "defend":
		text = Data.skills["defend"]["desc"]
	elif cmd == "item" and rules.inventory.is_empty():
		text = "You have nothing."
	elif cmd == "flee" and not rules.can_flee and not rules.is_hopeless():
		text = "No running from this one. You can try."
	text = rules.encounter.get("help", {}).get(cmd, text)   # an encounter can reword any command
	set_help(text)
	match cmd:
		"attack":
			show_order(actor, 1.0)
		"defend":
			show_order(actor, float(Data.skills["defend"].get("delay", 1.0)))
		_:
			show_order()


func _on_command(cmd: String) -> void:
	match cmd:
		"attack":
			_begin_target({"kind": "skill", "id": rules.attack_id})
		"skill", "item":
			_open_list(cmd)
		"defend":
			chosen.emit({"kind": "skill", "id": "defend", "targets": [actor]})
		"flee":
			chosen.emit({"kind": "flee"})


func _open_list(kind: String) -> void:
	mode = Mode.LIST
	_list_kind = kind
	_cmd_panel.hide()
	for c in _list.get_children():
		c.queue_free()
	var ids: Array = actor.skills if kind == "skill" else rules.inventory.keys()
	var first: Button = null
	for id in ids:
		var d: Dictionary = Data.action_def(kind, id)
		var cost := int(d.get("cost", 0))
		var detail := ("%d grit" % cost if cost > 0 else "") if kind == "skill" else ("x%d" % rules.inventory[id])
		var b := UIStyle.menu_button(d["name"], Data.icon(d.get("icon", "skill")), detail)
		b.custom_minimum_size = Vector2(450, 40)
		var usable := rules.can_use(actor, kind, id)
		b.disabled = not usable
		b.focus_mode = Control.FOCUS_ALL  # disabled entries still explain themselves
		b.pressed.connect(func() -> void:
			if rules.can_use(actor, kind, id):
				_begin_target({"kind": kind, "id": id}))
		b.focus_entered.connect(func() -> void:
			set_help(d.get("desc", "") if rules.can_use(actor, kind, id) else rules.why_not(actor, kind, id))
			show_order(actor, float(d.get("delay", 1.0))))
		_list.add_child(b)
		if first == null:
			first = b
	_list_panel.show()
	_party_panel.hide()
	if first:
		first.grab_focus.call_deferred()


func _begin_target(pending: Dictionary) -> void:
	var d := Data.action_def(pending["kind"], pending["id"])
	_pending = pending
	var t: String = d.get("target", "enemy")
	var cands := rules.candidates(actor, d)
	# Solo fights: self-targets and single obvious targets skip the cursor step.
	if t == "self" or (t in ["ally", "all_allies"] and cands.size() == 1) or rules.is_multi(d):
		_pending["targets"] = cands if rules.is_multi(d) else [actor if t == "self" else cands[0]]
		chosen.emit(_pending)
		return
	_targets = cands
	if _targets.is_empty():
		return
	mode = Mode.TARGET
	_list_panel.hide()
	_party_panel.show()
	_target_i = 0
	get_viewport().gui_release_focus()
	_show_target_cursors()
	show_order(actor, float(d.get("delay", 1.0)))


func _show_target_cursors() -> void:
	_clear_cursors()
	var b := _targets[_target_i]
	var c := UIStyle.icon_rect(Data.icon("cursor_down"), 32)
	c.set_meta("battler", b)
	add_child(c)
	_cursors.append(c)
	set_help(_describe(b))


func _describe(b: Battler) -> String:
	if b.impunity:
		return "%s   HP ???" % b.display_name
	return "%s   HP %d/%d" % [b.display_name, b.hp, b.max_hp()]


func _clear_cursors() -> void:
	for c in _cursors:
		c.queue_free()
	_cursors.clear()


func _close_all() -> void:
	mode = Mode.IDLE
	_cmd_panel.hide()
	_list_panel.hide()
	_party_panel.show()
	_clear_cursors()
	set_help("")
	get_viewport().gui_release_focus()
	actor = null


func _process(delta: float) -> void:
	if mode != Mode.IDLE and Game.auto_battle:   # F1 pressed while a menu is open
		chosen.emit(rules.ai_choose(actor))
		return
	_bob += delta * 8.0
	for c in _cursors:
		var v: BattlerView = views[c.get_meta("battler")]
		c.position = v.head() + Vector2(-16, -52 + sin(_bob) * 5.0)
	# a pointing hand over anyone a click would hit
	var over := false
	if mode == Mode.COMMAND or mode == Mode.TARGET:
		over = _battler_at(get_viewport().get_mouse_position(), _clickable()) != null
	if over != _pointing:
		_pointing = over
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if over else Input.CURSOR_ARROW)


## Who a left click can pick right now: the targets, or (at the command menu) anyone
## a plain attack could hit -- clicking them strikes them.
func _clickable() -> Array[Battler]:
	if mode == Mode.TARGET:
		return _targets
	if mode == Mode.COMMAND and actor:
		return rules.candidates(actor, Data.skills[rules.attack_id])
	var none: Array[Battler] = []
	return none


## The battler whose body is under a screen point (nearest if they overlap).
func _battler_at(p: Vector2, among: Array[Battler]) -> Battler:
	var best: Battler = null
	var best_d := INF
	for b in among:
		var v: BattlerView = views.get(b)
		if v == null or not b.is_alive():
			continue
		var w := maxf(70.0, v.sprite.width * 0.75)
		var r := Rect2(v.global_position.x - w / 2.0, v.global_position.y - v.height, w, v.height + 12.0)
		if r.has_point(p):
			var d := p.distance_to(r.get_center())
			if d < best_d:
				best_d = d
				best = b
	return best


func _exit_tree() -> void:
	if _pointing:
		Input.set_default_cursor_shape(Input.CURSOR_ARROW)


func _unhandled_input(event: InputEvent) -> void:
	# mouse: hover a target to aim, click to confirm; at the command menu, clicking
	# someone strikes them. (Right click arrives as ui_cancel.)
	if event is InputEventMouseMotion and mode == Mode.TARGET:
		var hovered := _battler_at(event.position, _targets)
		if hovered and _targets.find(hovered) != _target_i:
			_target_i = _targets.find(hovered)
			_show_target_cursors()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var picked := _battler_at(event.position, _clickable())
		if picked == null:
			return
		get_viewport().set_input_as_handled()
		if mode == Mode.TARGET:
			_pending["targets"] = [picked]
			chosen.emit(_pending)
		elif mode == Mode.COMMAND:
			chosen.emit({"kind": "skill", "id": rules.attack_id, "targets": [picked]})
		return
	match mode:
		Mode.LIST:
			if event.is_action_pressed("ui_cancel"):
				get_viewport().set_input_as_handled()
				_open_commands(_list_kind)
		Mode.TARGET:
			if event.is_action_pressed("ui_accept"):
				get_viewport().set_input_as_handled()
				_pending["targets"] = [_targets[_target_i]]
				chosen.emit(_pending)
			elif event.is_action_pressed("ui_cancel"):
				get_viewport().set_input_as_handled()
				_clear_cursors()
				if _pending["kind"] == "skill" and _pending["id"] == rules.attack_id:
					_open_commands("attack")
				else:
					_open_list(_pending["kind"])
			elif event.is_action_pressed("ui_left") or event.is_action_pressed("ui_up"):
				get_viewport().set_input_as_handled()
				_target_i = posmod(_target_i - 1, _targets.size())
				_show_target_cursors()
			elif event.is_action_pressed("ui_right") or event.is_action_pressed("ui_down"):
				get_viewport().set_input_as_handled()
				_target_i = posmod(_target_i + 1, _targets.size())
				_show_target_cursors()


# ------------------------------------------------------------------ end screens
## Aftermath panel. Waits for confirm.
func show_results(title: String, lines: Array[String], title_color := UIStyle.ATB) -> void:
	var panel := UIStyle.panel()
	panel.custom_minimum_size = Vector2(560, 0)
	add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	panel.add_child(col)
	var head := UIStyle.label(title, 32, title_color)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(head)
	for l in lines:
		var lab := UIStyle.label(l, 21)
		lab.autowrap_mode = TextServer.AUTOWRAP_WORD
		lab.custom_minimum_size.x = 530
		lab.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(lab)
	var hint := UIStyle.label("Confirm or click", 15, UIStyle.DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	col.add_child(hint)
	await get_tree().process_frame
	panel.position = Vector2(640 - panel.size.x / 2, 260 - panel.size.y / 2)
	await get_tree().create_timer(0.4).timeout
	var shown := 0.0
	while true:
		await get_tree().process_frame
		shown += get_process_delta_time()
		if Game.confirm_pressed() or (Game.auto_battle and shown > 1.5):
			break
	panel.queue_free()


## Returns the picked option text.
func ask(title: String, options: Array[String]) -> String:
	var panel := UIStyle.panel()
	add_child(panel)
	var col := VBoxContainer.new()
	panel.add_child(col)
	var head := UIStyle.label(title, 30, UIStyle.HP_LOW)
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(head)
	var picked := [""]
	for o in options:
		var b := UIStyle.menu_button(o)
		b.pressed.connect(func() -> void: picked[0] = o)
		col.add_child(b)
	await get_tree().process_frame
	panel.position = Vector2(640 - panel.size.x / 2, 260 - panel.size.y / 2)
	col.get_child(1).grab_focus()
	while picked[0] == "":
		await get_tree().process_frame
		if Game.auto_battle:
			await get_tree().create_timer(1.0).timeout
			picked[0] = options[0]
	panel.queue_free()
	return picked[0]
