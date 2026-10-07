extends Node2D
## Lays out placeholder SVGs with their file names. Run it to review art:
##   godot --path . res://tests/gallery.tscn -- --folders=char,prop --shot=/tmp/gallery.png
const ROOT := "res://assets/placeholder"

func _ready() -> void:
	RenderingServer.set_default_clear_color(Color("#3a332c"))
	var folders := ["char", "portrait", "tile", "prop", "icon", "fx"]
	var skip_field := false
	var only_field := false
	var max_cell := 120.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--folders="):
			folders = Array(a.trim_prefix("--folders=").split(","))
		elif a == "--no-field":
			skip_field = true
		elif a == "--only-field":
			only_field = true
		elif a.begins_with("--cell="):
			max_cell = float(a.trim_prefix("--cell="))
	var x := 12.0
	var y := 12.0
	var row_h := 0.0
	for folder in folders:
		for file in DirAccess.get_files_at("%s/%s" % [ROOT, folder]):
			if not file.ends_with(".svg"):
				continue
			if skip_field and file.ends_with("_field.svg"):
				continue
			if only_field and folder == "char" and not file.ends_with("_field.svg"):
				continue
			var tex: Texture2D = load("%s/%s/%s" % [ROOT, folder, file])
			var size := tex.get_size()
			var scale_f := minf(1.0, max_cell / maxf(size.x, size.y))
			var cell_w := maxf(size.x * scale_f, 78.0) + 8.0
			if x + cell_w > 1272.0:
				x = 12.0
				y += row_h + 18.0
				row_h = 0.0
			var s := Sprite2D.new()
			s.texture = tex
			s.centered = false
			s.scale = Vector2(scale_f, scale_f)
			s.position = Vector2(x, y)
			add_child(s)
			var l := Label.new()
			l.text = file.get_basename().replace("_field", "_f")
			l.add_theme_font_size_override("font_size", 10)
			l.position = Vector2(x, y + size.y * scale_f)
			add_child(l)
			x += cell_w
			row_h = maxf(row_h, size.y * scale_f)
	_maybe_shot()

func _maybe_shot() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shot="):
			await get_tree().create_timer(0.3).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(arg.trim_prefix("--shot="))
			get_tree().quit()
