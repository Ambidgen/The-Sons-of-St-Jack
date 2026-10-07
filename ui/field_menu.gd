class_name FieldMenu
extends Control
## Pause menu between beats: Items (used on Derrick), Status (stats, tricks and
## the scars he carries across the years), Close. Saving is automatic at every
## stage start, so there is no Save command.
##     await field_menu.open()

signal closed

var _cmds: VBoxContainer
var _card: PanelContainer
var _detail: PanelContainer
var _detail_box: VBoxContainer
var _note: Label
var _mode := ""          # "", "items", "status"


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UIStyle.theme()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var left := UIStyle.panel()
	left.position = Vector2(40, 40)
	left.custom_minimum_size = Vector2(240, 0)
	add_child(left)
	var lcol := VBoxContainer.new()
	left.add_child(lcol)
	_cmds = VBoxContainer.new()
	lcol.add_child(_cmds)
	for c in [["Items", "item"], ["Status", "skill"], ["Close", "flee"]]:
		var b := UIStyle.menu_button(c[0], Data.icon(c[1]))
		b.pressed.connect(_on_cmd.bind(c[0]))
		_cmds.add_child(b)
	lcol.add_child(HSeparator.new())
	_note = UIStyle.label("", 16, UIStyle.DIM)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD
	_note.custom_minimum_size.x = 210
	lcol.add_child(_note)

	_card = UIStyle.panel()
	_card.position = Vector2(300, 40)
	_card.custom_minimum_size = Vector2(560, 0)
	add_child(_card)

	_detail = UIStyle.panel()
	_detail.position = Vector2(880, 40)
	_detail.custom_minimum_size = Vector2(360, 0)
	add_child(_detail)
	_detail_box = VBoxContainer.new()
	_detail.add_child(_detail_box)
	MenuCursor.attach(self)
	hide()


func open() -> void:
	show()
	_mode = ""
	_note.text = "Checkpoints save at the start of every chapter."
	_refresh()
	_detail.hide()
	_cmds.get_child(0).grab_focus()
	await closed
	hide()


func _refresh() -> void:
	for c in _card.get_children():
		c.queue_free()
	var m: Dictionary = Game.hero()
	var a: Dictionary = Data.actors[m["id"]]
	var s := Game.stats_of(m)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	_card.add_child(row)
	row.add_child(UIStyle.icon_rect(Data.tex(Game.actor_art(m, "portrait")), 120))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	row.add_child(col)
	var age: String = Data.stages.get(Game.stage_id, {}).get("age", "")
	col.add_child(UIStyle.label("%s   %s" % [a["name"], age], 24, UIStyle.ATB))
	for stat in ["hp", "mp"]:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		var tag := UIStyle.label("HP" if stat == "hp" else "GRIT", 16, UIStyle.DIM)
		tag.custom_minimum_size.x = 44
		line.add_child(tag)
		var bar := UIStyle.bar(UIStyle.HP if stat == "hp" else UIStyle.MP, 200, 10)
		bar.max_value = s[stat]
		bar.value = m[stat]
		line.add_child(bar)
		line.add_child(UIStyle.label("%d/%d" % [m[stat], s[stat]], 18))
		col.add_child(line)
	var scars := Game.wounds.size()
	col.add_child(UIStyle.label("No scars that matter." if scars == 0 else "%d wound%s that never closed." % [scars, "" if scars == 1 else "s"], 17, UIStyle.DIM))


func _on_cmd(cmd: String) -> void:
	match cmd:
		"Items":
			_show_items()
		"Status":
			_mode = "status"
			_show_status()
		"Close":
			closed.emit()


func _show_items() -> void:
	_mode = "items"
	_detail.show()
	for c in _detail_box.get_children():
		c.queue_free()
	_detail_box.add_child(UIStyle.label("Items", 22, UIStyle.ATB))
	var first: Button = null
	for id in Game.inventory:
		var d: Dictionary = Data.items[id]
		var b := UIStyle.menu_button(d["name"], Data.icon(d.get("icon", "item")), "x%d" % Game.inventory[id])
		b.disabled = not (d["kind"] in ["heal", "restore_mp", "cure"])
		b.pressed.connect(_use.bind(id))
		b.focus_entered.connect(func() -> void: _note.text = d.get("desc", ""))
		_detail_box.add_child(b)
		if first == null:
			first = b
	if first:
		first.grab_focus()
	else:
		_detail_box.add_child(UIStyle.label("Nothing. Not even crumbs.", 18, UIStyle.DIM))


func _use(id: String) -> void:
	var d: Dictionary = Data.items[id]
	var m: Dictionary = Game.hero()
	var s := Game.stats_of(m)
	var key := "mp" if d["kind"] == "restore_mp" else "hp"
	if d["kind"] == "cure" or m[key] >= s[key]:
		_note.text = "No need. Save it."
		return
	var amount := int(d["amount"])
	if key == "hp":
		amount = int(amount * float(Data.cfg("heal_mult", 0.5)))
	m[key] = mini(s[key], int(m[key]) + amount)
	Game.add_item(id, -1)
	_note.text = "%s. It helps, a little." % d["name"]
	_refresh()
	await get_tree().process_frame
	_show_items()


func _show_status() -> void:
	_detail.show()
	for c in _detail_box.get_children():
		c.queue_free()
	var m: Dictionary = Game.hero()
	var s := Game.stats_of(m)
	_detail_box.add_child(UIStyle.label("Derrick", 22, UIStyle.ATB))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 40)
	for k in [["atk", "Strength"], ["def", "Toughness"], ["spd", "Speed"]]:
		grid.add_child(UIStyle.label(k[1], 19, UIStyle.DIM))
		grid.add_child(UIStyle.label(str(s[k[0]]), 19))
	_detail_box.add_child(grid)
	_detail_box.add_child(HSeparator.new())
	_detail_box.add_child(UIStyle.label("What he knows", 18, UIStyle.DIM))
	for sk in Game.skills_of(m):
		_detail_box.add_child(UIStyle.label("  " + Data.skills[sk]["name"], 18))
	if not Game.wounds.is_empty():
		_detail_box.add_child(HSeparator.new())
		_detail_box.add_child(UIStyle.label("Scars", 18, UIStyle.DIM))
		for w in Game.wounds:
			var l := UIStyle.label("  %s (%s)" % [w["what"], w["where"]], 16, UIStyle.HP_LOW)
			l.autowrap_mode = TextServer.AUTOWRAP_WORD
			l.custom_minimum_size.x = 320
			_detail_box.add_child(l)
	_cmds.get_child(1).grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("menu"):
		get_viewport().set_input_as_handled()
		match _mode:
			"items", "status":
				var focus_index := 0 if _mode == "items" else 1
				_mode = ""
				_detail.hide()
				_cmds.get_child(focus_index).grab_focus()
			_:
				closed.emit()
