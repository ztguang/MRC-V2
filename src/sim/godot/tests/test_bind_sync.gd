extends SceneTree

## Verify chassis mesh, armors and gimbal share a rigid assembly pivot.
## godot --path sim/godot --script res://tests/test_bind_sync.gd

func _initialize() -> void:
	change_scene_to_file("res://main.tscn")
	call_deferred("_run")

func _run() -> void:
	await process_frame
	await physics_frame
	await physics_frame
	var sim = current_scene
	if sim == null:
		push_error("no scene")
		quit(1)
		return
	sim.overview_mode = true
	sim.ai_enabled = true
	if sim.has_method("_set_active_camera"):
		sim._set_active_camera()

	var ok := true
	var reasons: PackedStringArray = []

	for robot in sim.robots:
		var body: Node3D = robot["body"]
		var assembly: Node3D = robot.get("assembly", null)
		var yaw_axis: Node3D = robot["yaw_axis"]
		var armors: Array = robot["armors"]

		if assembly == null:
			ok = false
			reasons.append("robot %d missing assembly" % robot["id"])
			continue

		# Hierarchy: body -> assembly -> (ChassisVisual, armors, yaw_axis)
		if assembly.get_parent() != body:
			ok = false
			reasons.append("robot %d assembly not under body" % robot["id"])
		if yaw_axis.get_parent() != assembly:
			ok = false
			reasons.append("robot %d yaw_axis not under assembly" % robot["id"])
		for armor in armors:
			if armor.get_parent() != assembly:
				ok = false
				reasons.append("robot %d armor not under assembly" % robot["id"])
				break

		# Capture local offsets
		var armor0: Node3D = armors[0]
		var local_armor0: Vector3 = armor0.position
		var local_yaw: Vector3 = yaw_axis.position
		var visual: Node = assembly.get_node_or_null("ChassisVisual")
		if visual == null:
			ok = false
			reasons.append("robot %d missing ChassisVisual under assembly" % robot["id"])
			continue

		# Move/rotate body and ensure relative poses unchanged
		body.position += Vector3(1.5, 0, -1.0)
		body.rotation.y += 0.7
		await physics_frame
		await process_frame

		if armor0.get_parent() != assembly:
			ok = false
			reasons.append("robot %d armor reparented after move" % robot["id"])
		if not armor0.position.is_equal_approx(local_armor0):
			ok = false
			reasons.append("robot %d armor local pos changed after body move: %s -> %s" % [
				robot["id"], str(local_armor0), str(armor0.position)])
		if not yaw_axis.position.is_equal_approx(local_yaw):
			ok = false
			reasons.append("robot %d yaw local pos changed after body move" % robot["id"])

		# World delta of armor should match body delta (rigid)
		# After rotation, check assembly children still have fixed local xforms
		var chassis_aligned = visual.get_node_or_null("ChassisAligned")
		if chassis_aligned == null:
			# model may be direct child after fallback
			pass
		else:
			if not is_zero_approx(chassis_aligned.position.length()):
				# holder should sit at assembly origin
				if chassis_aligned.position.length() > 0.05:
					ok = false
					reasons.append("robot %d ChassisAligned not at origin: %s" % [
						robot["id"], str(chassis_aligned.position)])

		print("robot %d assembly_ok parent(yaw)=%s armor_local=%s yaw_local=%s body=%s" % [
			robot["id"],
			str(yaw_axis.get_parent().name),
			str(local_armor0),
			str(local_yaw),
			str(body.global_position)])

	# screenshot
	for i in range(20):
		await process_frame
	var img: Image = get_root().get_viewport().get_texture().get_image()
	var path := "user://bind_sync_overview.png"
	img.save_png(path)
	print("Saved ", ProjectSettings.globalize_path(path))

	if ok:
		print("BIND SYNC TEST PASSED")
		quit(0)
	else:
		print("BIND SYNC TEST FAILED:")
		for r in reasons:
			print(" - ", r)
		quit(1)
