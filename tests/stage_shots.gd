extends Node
## Clean screenshots of stages at several camera positions, with scripts, cards
## and dialogue held back: for reviewing the level paintings and their depth layers.
##   xvfb-run -a godot --path . --rendering-driver opengl3 res://tests/stage_shots.tscn -- \
##       --out=/tmp/shots [--stages=s01_harrowgate,s12_st_ordrics] [--zoom=1.9 --at=11,2] [--sense]
## Each stage gets left / middle / right shots at zoom 1, plus one zoomed shot on
## --at (or the stage's start) when --zoom is given.

var out_dir := "/tmp/shots"
var only: Array = []
var zoom := 0.0
var at := Vector2(-1, -1)
var sense := false          # also shoot with the F7 detection overlay on


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
		elif a.begins_with("--stages="):
			only = Array(a.trim_prefix("--stages=").split(","))
		elif a.begins_with("--zoom="):
			zoom = float(a.trim_prefix("--zoom="))
		elif a.begins_with("--at="):
			var p := a.trim_prefix("--at=").split(",")
			at = Vector2(float(p[0]), float(p[1]))
		elif a == "--sense":
			sense = true
	DirAccess.make_dir_recursive_absolute(out_dir)
	reparent.call_deferred(get_tree().root)
	await get_tree().process_frame
	for id in Data.act_order():
		if not only.is_empty() and not only.has(id):
			continue
		await _shoot(id)
	get_tree().quit()


func _shoot(id: String) -> void:
	Game.new_game()
	var packed: PackedScene = load("res://scenes/stage/stage.tscn")
	Router.params = {"stage": id, "fresh": true}
	var sc: Node = packed.instantiate()
	get_tree().root.add_child(sc)
	await get_tree().process_frame
	sc.director.halted = true            # hold every script
	sc.set_process(true)
	sc.cinema.visible = false
	sc.dialogue.visible = false
	sc.hint_label.visible = false
	sc.cinema.set_black(0.0)
	await get_tree().create_timer(0.4).timeout
	sc._follow = null
	sc.camera.zoom = Vector2.ONE
	var mw: float = sc.map.w * 64.0
	var mid_y: float = sc.player.global_position.y - 28.0
	var key := id
	if sense:
		sc.toggle_sense_view()
		sc.hint_label.visible = false
	var spots := [["left", 0.0], ["mid", 0.5], ["right", 1.0]] if mw > 1400.0 else [["mid", 0.5]]
	for pos in spots:
		sc.camera.global_position = Vector2(lerpf(640.0, mw - 640.0, pos[1]), mid_y)
		sc.camera.reset_smoothing()
		await _settle()
		await _save("%s_%s" % [key, pos[0]])
	if zoom > 0.0:
		var p: Vector2 = at if at.x >= 0 else Vector2(sc.map.start)
		sc.camera.zoom = Vector2(zoom, zoom)
		sc.camera.global_position = p * 64.0 + Vector2(32, 32)
		sc.camera.reset_smoothing()
		await _settle()
		await _save("%s_zoom" % key)
	sc.queue_free()
	await get_tree().process_frame


func _settle() -> void:
	for i in 4:
		await get_tree().process_frame


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out_dir, name])
	print("shot ", name)
