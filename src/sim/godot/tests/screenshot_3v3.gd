extends SceneTree

## Quick visual dump of the 3v3 arena with GLB chassis.
## godot --path sim/godot --script res://tests/screenshot_3v3.gd

func _initialize() -> void:
	change_scene_to_file("res://main.tscn")
	call_deferred("_snap")

func _snap() -> void:
	await process_frame
	await physics_frame
	await physics_frame
	var sim = current_scene
	if sim == null:
		push_error("no scene")
		quit(1)
		return
	sim.overview_mode = true
	if sim.has_method("_set_active_camera"):
		sim._set_active_camera()
	# Let a few frames render with models
	for i in range(30):
		await process_frame
	var img: Image = get_root().get_viewport().get_texture().get_image()
	var path := "user://glb_3v3_overview.png"
	img.save_png(path)
	print("Saved ", ProjectSettings.globalize_path(path))
	# also count children with chassis
	var n := 0
	for r in sim.robots:
		if r["body"].has_node("ChassisVisual"):
			n += 1
	print("robots with ChassisVisual: ", n, "/", sim.robots.size())
	for r in sim.robots:
		print(" robot ", r["id"], " team=", r["team"], " number=", r.get("number", -1),
			" armors=", r["armors"].size(), " name=", r["body"].name)
	quit(0)
