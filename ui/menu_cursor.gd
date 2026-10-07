class_name MenuCursor
extends TextureRect
## The pointing cursor. Follows keyboard/gamepad focus inside `scope` and hides
## when focus leaves it. Add one per menu root:  MenuCursor.attach(my_menu_root)

var scope: Control
var _bob := 0.0


static func attach(root: Control) -> MenuCursor:
	var c := MenuCursor.new()
	c.scope = root
	root.add_child(c)
	return c


func _ready() -> void:
	texture = Data.icon("cursor")
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	custom_minimum_size = Vector2(24, 24)
	size = Vector2(24, 24)
	top_level = true           # ignore parent containers / layout
	z_index = 50
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	get_viewport().gui_focus_changed.connect(_on_focus)


func _on_focus(c: Control) -> void:
	visible = c != null and is_instance_valid(scope) and scope.is_visible_in_tree() and scope.is_ancestor_of(c)


func _process(delta: float) -> void:
	var f := get_viewport().gui_get_focus_owner()
	if f == null or not scope.is_ancestor_of(f) or not f.is_visible_in_tree():
		visible = false
		return
	visible = true
	_bob += delta * 8.0
	var r := f.get_global_rect()
	global_position = Vector2(r.position.x + 2 + sin(_bob) * 3.0, r.position.y + r.size.y * 0.5 - 12)
