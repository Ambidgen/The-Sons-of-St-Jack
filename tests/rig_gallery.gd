extends Node2D
## Every articulated rig next to its flat drawing, to check the parts line up, and
## then walking / acting. Needs a real renderer:
##   xvfb-run -a godot --path . --rendering-driver opengl3 res://tests/rig_gallery.tscn -- \
##       --shot=/tmp/rigs.png [--filter=_field] [--mode=rest|walk|attack|hurt|cast|yield] [--at=0.3] [--zoom=1]
## rest: flat sprite (left) vs rig at rest (right), which should look the same.

func _ready() -> void:
	RenderingServer.set_default_clear_color(Color("#5a5048"))
	var filter := ""
	var mode := "rest"
	var at := 0.4
	var shot := ""
	var zoom := 1.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--filter="):
			filter = a.trim_prefix("--filter=")
		elif a.begins_with("--mode="):
			mode = a.trim_prefix("--mode=")
		elif a.begins_with("--at="):
			at = float(a.trim_prefix("--at="))
		elif a.begins_with("--shot="):
			shot = a.trim_prefix("--shot=")
		elif a.begins_with("--zoom="):
			zoom = float(a.trim_prefix("--zoom="))
	scale = Vector2(zoom, zoom)
	var names: Array = Rig.db().keys()
	names.sort()
	var x := 10.0
	var y := 10.0
	var row_h := 0.0
	var rigs: Array[Rig] = []
	for n: String in names:
		if filter != "" and not n.contains(filter):
			continue
		var d: Dictionary = Rig.db()[n]
		var flat_key := ("prop/" if n in ["horse", "crow"] else "char/") + n
		var r := Rig.make(flat_key)
		var w := r.width
		var h := r.height
		var cell := w * (2.0 if mode == "rest" else 1.0) + 14.0
		if (x + cell) * zoom > 1270.0:
			x = 10.0
			y += row_h + 22.0
			row_h = 0.0
		if mode == "rest":
			var flat := Sprite2D.new()
			flat.texture = Data.tex(flat_key)
			flat.centered = false
			flat.position = Vector2(x, y)
			add_child(flat)
			r.position = Vector2(x + w * 1.5, y + h)
			r.animate = false
		else:
			r.position = Vector2(x + w * 0.5, y + h)
		add_child(r)
		rigs.append(r)
		var l := Label.new()
		l.text = n.replace("_field", "_f") + (" [%s]" % d.get("kind", "")) 
		l.add_theme_font_size_override("font_size", 10)
		l.position = Vector2(x, y + h)
		add_child(l)
		x += cell
		row_h = maxf(row_h, h)
	await get_tree().process_frame
	for r in rigs:
		match mode:
			"walk":
				r.set_process(true)
			"attack", "hurt", "cast", "nod":
				r.play(mode)
			"yield", "cower", "raise":
				r.play(mode)
	if mode == "walk":
		var t := 0.0
		while t < at:
			for r in rigs:
				r.step(0.2)
			await get_tree().process_frame
			t += get_process_delta_time()
	else:
		await get_tree().create_timer(at).timeout
	if shot != "":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(shot)
		get_tree().quit()
