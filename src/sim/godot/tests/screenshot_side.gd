extends SceneTree

func _initialize() -> void:
	change_scene_to_file("res://main.tscn")
	call_deferred("_snap")

func _snap() -> void:
	await process_frame
	await physics_frame
	for i in range(10):
		await process_frame
	var sim = current_scene
	if sim == null:
		quit(1)
		return
	sim.overview_mode = false
	if sim.has_method("_set_active_camera"):
		sim._set_active_camera()
	# Side camera looking at red robot 1
	var r1: Dictionary = sim.robots[1]
	var body: Node3D = r1["body"]
	var cam := Camera3D.new()
	cam.name = "SideShotCam"
	sim.add_child(cam)
	cam.global_position = body.global_position + Vector3(1.2, 0.55, 0.9)
	cam.look_at(body.global_position + Vector3(0, 0.25, 0), Vector3.UP)
	cam.current = true
	for i in range(25):
		await process_frame
	var img: Image = get_root().get_viewport().get_texture().get_image()
	img.save_png("user://turret_side_view.png")
	print("Saved side view ", ProjectSettings.globalize_path("user://turret_side_view.png"))
	# count meshes under pitch_axis
	var pitch: Node3D = r1["pitch_axis"]
	var meshes := 0
	var stack: Array = [pitch]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is MeshInstance3D:
			meshes += 1
	print("pitch_axis mesh count=", meshes, " children=", pitch.get_child_count())
	for c in pitch.get_children():
		print("  pitch child: ", c.name, " type=", c.get_class())
	quit(0)
