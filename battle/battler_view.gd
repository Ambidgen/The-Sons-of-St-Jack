class_name BattlerView
extends Node2D
## On-screen body for one Battler: an articulated Rig (breathing, wind-up and
## strike, flinch, yield), optional name + HP bar, status icons, and the "juice"
## (flash, shake, lunge, sidestep, popups, death fade). Position = feet.

var battler: Battler
var sprite: Rig
var hp_bar: ProgressBar
var status_row: HBoxContainer
var info: VBoxContainer
var home := Vector2.ZERO
var height := 96.0


func setup(b: Battler, show_hp: bool) -> void:
	battler = b
	sprite = Rig.make(b.sprite)
	sprite.flip_h = b.is_ally          # the party stands on the right, facing left
	height = sprite.height
	add_child(sprite)
	info = VBoxContainer.new()
	info.position = Vector2(-70, -height - 44)
	info.custom_minimum_size = Vector2(140, 0)
	info.add_theme_constant_override("separation", 2)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(info)
	status_row = HBoxContainer.new()
	status_row.alignment = BoxContainer.ALIGNMENT_CENTER
	status_row.custom_minimum_size = Vector2(140, 20)
	info.add_child(status_row)
	if not b.is_ally:
		var name_label := UIStyle.label(b.display_name, 17)
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.add_theme_color_override("font_outline_color", Color.BLACK)
		name_label.add_theme_constant_override("outline_size", 5)
		info.add_child(name_label)
		if show_hp and not b.impunity:
			hp_bar = UIStyle.bar(UIStyle.HP, 120, 8)
			hp_bar.theme = UIStyle.theme()
			hp_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			info.add_child(hp_bar)
	refresh()
	info.position.y = -height - info.get_combined_minimum_size().y - 4


func refresh() -> void:
	if hp_bar:
		hp_bar.max_value = battler.max_hp()
		hp_bar.value = battler.hp
		UIStyle.set_bar_color(hp_bar, UIStyle.HP if battler.hp > battler.max_hp() * 0.3 else UIStyle.HP_LOW)
	for c in status_row.get_children():
		c.queue_free()
	for s in battler.statuses:
		status_row.add_child(UIStyle.icon_rect(Data.icon(Data.statuses[s]["icon"]), 20))


func head() -> Vector2:
	return global_position + Vector2(0, -height)


func flash(color := Color(4, 4, 4)) -> void:
	var tw := create_tween()
	tw.tween_property(sprite, "tint", color, 0.04)
	tw.tween_property(sprite, "tint", Color.WHITE, 0.14)


func shake(strength := 8.0) -> void:
	sprite.play("hurt")
	var tw := create_tween()
	for i in 4:
		tw.tween_property(sprite, "position:x", strength * (1 if i % 2 == 0 else -1), 0.03)
	tw.tween_property(sprite, "position:x", 0.0, 0.03)


## Wind up, step in and strike, step back. Returns when the blow lands, so the
## caller shows the hit on time.
func lunge() -> void:
	var dir := -1.0 if battler.is_ally else 1.0
	var hit: float = Rig.HIT_TIME["attack"] if sprite.has_bones() else 0.1
	sprite.play("attack")
	var tw := create_tween()
	tw.tween_interval(maxf(0.0, hit - 0.1))
	tw.tween_property(self, "position:x", home.x + 46.0 * dir, 0.1).set_trans(Tween.TRANS_QUAD)
	tw.tween_property(self, "position:x", home.x, 0.18).set_delay(0.08)
	await get_tree().create_timer(hit).timeout


## A short wind-up for non-attack actions (bracing, binding a wound, a word).
func cast(color: Color) -> void:
	sprite.play("cast")
	var tw := create_tween()
	tw.tween_property(sprite, "tint", color.lightened(0.3), 0.12)
	tw.tween_property(sprite, "tint", Color.WHITE, 0.2)
	await get_tree().create_timer(0.3).timeout


## Unhurried step aside -- the Impunity tell.
func sidestep() -> void:
	var tw := create_tween()
	tw.tween_property(sprite, "position:y", -4.0, 0.08)
	tw.parallel().tween_property(self, "position:x", home.x - 26.0, 0.12).set_trans(Tween.TRANS_SINE)
	tw.tween_interval(0.12)
	tw.tween_property(self, "position:x", home.x, 0.3).set_trans(Tween.TRANS_SINE)
	tw.parallel().tween_property(sprite, "position:y", 0.0, 0.3)


func popup(text: String, color: Color, size := 32, delay := 0.0, y_frac := 0.6) -> void:
	var l := UIStyle.label(text, size, color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 7)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(240, 0)
	l.position = Vector2(-120, -height * y_frac)
	l.z_index = 20
	l.modulate.a = 0.0
	add_child(l)
	var tw := l.create_tween()
	tw.tween_interval(delay)
	tw.tween_property(l, "modulate:a", 1.0, 0.05)
	tw.parallel().tween_property(l, "position:y", l.position.y - 40, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.55)
	tw.tween_property(l, "modulate:a", 0.0, 0.25)
	tw.tween_callback(l.queue_free)


func die() -> void:
	sprite.animate = false
	var tw := create_tween()
	if battler.is_ally:
		tw.tween_property(sprite, "modulate", Color(0.5, 0.45, 0.42, 0.9), 0.35)
		tw.parallel().tween_property(sprite, "rotation_degrees", -84.0, 0.35).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
		tw.parallel().tween_property(sprite, "position:y", 24.0, 0.35)
	else:
		tw.tween_property(sprite, "modulate", Color(0.6, 0.15, 0.1, 0.0), 0.6)
		tw.parallel().tween_property(sprite, "scale", Vector2(1.05, 0.7), 0.6)
		tw.tween_callback(info.hide)


## Sparring partner sinks, hands up.
func yield_pose() -> void:
	if sprite.has_bones():
		sprite.play("yield")
		info.hide()
		return
	var tw := create_tween()
	tw.tween_property(sprite, "scale", Vector2(1.0, 0.82), 0.25).set_trans(Tween.TRANS_BACK)
	tw.parallel().tween_property(sprite, "position:y", height * 0.09, 0.25)
	tw.tween_callback(info.hide)


func revive() -> void:
	sprite.animate = true
	sprite.reset_pose()
	var tw := create_tween()
	tw.tween_property(sprite, "modulate", Color.WHITE, 0.3)
	tw.parallel().tween_property(sprite, "rotation_degrees", 0.0, 0.3)
	tw.parallel().tween_property(sprite, "scale", Vector2.ONE, 0.3)
