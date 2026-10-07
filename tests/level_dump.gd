extends Node
## Dumps what the pixel detection made of each level stage, for review sheets.
##   godot --headless --path . res://tests/level_dump.tscn -- --out=/tmp/levels [--stage=id]
## Writes <out>/<stage>.json (tiles, cells, lines, cast, props, exits) and
## <out>/<stage>_cells.png (one pixel per 16 px cell, coloured by class).

func _ready() -> void:
	var out := "user://level_dump"
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--stage="):
			only = a.substr(8)
	DirAccess.make_dir_recursive_absolute(out)
	for id in Data.stages:
		if only != "" and id != only:
			continue
		var st: Dictionary = Data.stages[id]
		if not st.has("level"):
			continue
		var m := StageMap.new(st)
		if m.sense == null:
			printerr("%s: no level art" % id)
			continue
		var cells := PackedStringArray()
		for cy in m.sense.ch:
			var r := ""
			for cx in m.sense.cw:
				r += str(m.sense.cell_class(cx, cy))
			cells.append(r)
		var lines := {}
		for k in m.triggers:
			var arr := []
			for c in m.triggers[k]:
				arr.append([c.x, c.y])
			lines[k] = arr
		var cast := {}
		for k in st.get("cast", {}):
			var d: Dictionary = st["cast"][k]
			cast[d.get("id", k)] = d.get("at", [])
		var props := {}
		for c in m.prop_cells:
			props["%d,%d" % [c.x, c.y]] = m.prop_cells[c]
		var ex := []
		for c in m.exits:
			ex.append([c.x, c.y])
		var gates := {}
		for g in m.gates:
			var arr := []
			for c in m.gates[g]["cells"]:
				arr.append([c.x, c.y])
			gates[g] = arr
		var d := {"id": id, "art": st["level"]["art"], "show": st["level"].get("show", st["level"]["art"]),
				"scale": float(st["level"].get("scale", 1.0)), "w": m.w, "h": m.h,
				"tiles": Array(m.sense.ascii()), "cells": Array(cells), "start": [m.start.x, m.start.y],
				"exits": ex, "lines": lines, "cast": cast, "props": props, "gates": gates,
				"ms": m.sense.ms, "walk": m.sense.walk_count, "road": m.sense.road_count}
		var f := FileAccess.open(out.path_join(id + ".json"), FileAccess.WRITE)
		f.store_string(JSON.stringify(d))
		f.close()
		m.sense.overlay_image(1.0).save_png(out.path_join(id + "_cells.png"))
		print("%s  %dx%d  walk %d  road %d  %d ms" % [id, m.w, m.h, m.sense.walk_count, m.sense.road_count, m.sense.ms])
	get_tree().quit()
