class_name UIStyle
extends RefCounted
## One place for the look of every menu: ink panels, parchment text, blood and
## ochre bars, a serif face. Built in code so it needs no .tres, and assigned to
## each UI root: `root.theme = UIStyle.theme()`.

const INK := Color("#16120e")
const PAPER := Color("#e9dfc7")
const PAPER_DK := Color("#b9aa88")
const BG := Color("#1c1712")
const BORDER := Color("#b9aa88")
const TEXT := Color("#e9dfc7")
const DIM := Color("#8f8469")
const HILITE := Color(0.91, 0.87, 0.78, 0.13)
const HP := Color("#a8322a")          # blood
const HP_LOW := Color("#e0502e")
const MP := Color("#c49a3a")          # grit (ochre)
const ATB := Color("#d8b24a")         # gold: names, highlights, gauges
const ALLY := Color("#cfc3a3")
const ENEMY := Color("#a8322a")
const JACK := Color("#d8b24a")

static var _theme: Theme
static var _serif: SystemFont


## Serif face: Palatino/Georgia on Windows, DejaVu Serif on Linux.
static func serif() -> Font:
	if _serif == null:
		_serif = SystemFont.new()
		_serif.font_names = PackedStringArray(["Palatino Linotype", "Book Antiqua", "Georgia",
				"Times New Roman", "DejaVu Serif", "Liberation Serif", "FreeSerif", "serif"])
		_serif.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	return _serif


static func italic() -> Font:
	var v := FontVariation.new()
	v.base_font = serif()
	v.variation_transform = Transform2D(Vector2(1, 0), Vector2(0.2, 1), Vector2.ZERO)
	return v


static func theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	t.default_font = serif()
	t.default_font_size = 20
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(BG, 0.94)
	panel.border_color = BORDER
	panel.set_border_width_all(2)
	panel.set_corner_radius_all(2)
	panel.set_content_margin_all(14)
	panel.shadow_color = Color(0, 0, 0, 0.45)
	panel.shadow_size = 6
	t.set_stylebox("panel", "PanelContainer", panel)
	t.set_stylebox("panel", "Panel", panel)

	var empty := StyleBoxFlat.new()
	empty.bg_color = Color(0, 0, 0, 0)
	empty.set_content_margin_all(4)
	empty.content_margin_left = 30  # room for the menu cursor
	var focus := empty.duplicate() as StyleBoxFlat
	focus.bg_color = HILITE
	focus.set_corner_radius_all(2)
	for s in ["normal", "disabled", "pressed"]:
		t.set_stylebox(s, "Button", empty)
	t.set_stylebox("hover", "Button", focus)
	t.set_stylebox("focus", "Button", focus)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_focus_color", "Button", Color("#fff6e0"))
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color(DIM, 0.7))
	t.set_constant("h_separation", "Button", 8)
	t.set_color("font_color", "Label", TEXT)
	t.set_color("default_color", "RichTextLabel", TEXT)

	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0, 0, 0, 0.6)
	bar_bg.border_color = Color(BORDER, 0.5)
	bar_bg.set_border_width_all(1)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = HP
	t.set_stylebox("background", "ProgressBar", bar_bg)
	t.set_stylebox("fill", "ProgressBar", bar_fill)
	var sep := StyleBoxLine.new()
	sep.color = Color(BORDER, 0.5)
	sep.thickness = 1
	t.set_stylebox("separator", "HSeparator", sep)
	_theme = t
	return t


## A thin coloured bar without the percentage text.
static func bar(color: Color, width := 160.0, height := 10.0) -> ProgressBar:
	var b := ProgressBar.new()
	b.show_percentage = false
	b.custom_minimum_size = Vector2(width, height)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	b.add_theme_stylebox_override("fill", fill)
	return b


static func set_bar_color(b: ProgressBar, color: Color) -> void:
	var fill := b.get_theme_stylebox("fill") as StyleBoxFlat
	if fill and fill.bg_color != color:
		fill = fill.duplicate()
		fill.bg_color = color
		b.add_theme_stylebox_override("fill", fill)


static func label(text: String, size := 20, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", serif())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func icon_rect(tex: Texture2D, px := 24.0) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = Vector2(px, px)
	return r


## A left-aligned menu button with an optional icon and right-hand detail text.
static func menu_button(text: String, icon: Texture2D = null, detail := "") -> Button:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	# the pointer and the keyboard share one cursor: hovering moves focus
	b.mouse_entered.connect(func() -> void:
		if b.is_visible_in_tree() and b.focus_mode != Control.FOCUS_NONE:
			b.grab_focus())
	if icon:
		b.icon = icon
		b.expand_icon = false
		b.add_theme_constant_override("icon_max_width", 24)
	if detail != "":
		var d := label(detail, 18, DIM)
		d.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
		d.position.x -= 8
		d.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(d)
	return b


static func panel() -> PanelContainer:
	return PanelContainer.new()
