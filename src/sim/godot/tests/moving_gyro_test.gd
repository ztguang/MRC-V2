extends SceneTree

const WARMUP_FRAMES := 180
const AIM_SWITCH_DISTANCE_METERS := 0.12

func _initialize() -> void:
	change_scene_to_file("res://main.tscn")
	call_deferred("_run")

func _wrap_angle(value: float) -> float:
	return wrapf(value, -PI, PI)

func _environment_float(name: String, fallback: float) -> float:
	var value := OS.get_environment(name)
	return float(value) if not value.is_empty() else fallback

func _environment_int(name: String, fallback: int) -> int:
	var value := OS.get_environment(name)
	return int(value) if not value.is_empty() else fallback

func _run() -> void:
	await process_frame
	await physics_frame
	var simulation = current_scene
	var spin := _environment_float("SP_GYRO_SPIN", 4.0)
	var travel_speed := _environment_float("SP_GYRO_TRAVEL_SPEED", 1.2)
	var test_frames := _environment_int("SP_GYRO_FRAMES", 1500)
	var expected_switch_period_usec := int((PI * 0.5 / maxf(absf(spin), 0.01)) * 1e6)
	var rapid_switch_limit_usec := int(expected_switch_period_usec * 0.5)

	simulation._reset_simulation()
	simulation.target_time = 0.0
	simulation.target_mode = 2
	simulation.target_speed = travel_speed
	simulation.target_spin = spin
	simulation.gameplay_controls_enabled = false
	simulation.auto_aim_enabled = true

	var result_count := 0
	var detection_count := 0
	var control_count := 0
	var two_armor_count := 0
	var aim_switch_count := 0
	var rapid_switch_count := 0
	var large_capture_gap_count := 0
	var yaw_error_sum := 0.0
	var pitch_error_sum := 0.0
	var last_timestamp := -1
	var last_switch_timestamp := -1
	var last_relative_aim := Vector3.ZERO
	var have_last_aim := false
	var state_counts := {}

	for frame in range(test_frames):
		await physics_frame
		if frame < WARMUP_FRAMES:
			continue
		# 3v3 scene: poll player robot (id 0). Legacy single-robot API removed.
		var robot_id := 0
		if "player_robot_id" in simulation:
			robot_id = int(simulation.player_robot_id)
		var result: Dictionary = simulation.bridge.poll_result(robot_id)
		var timestamp := int(result.get("capture_timestamp_usec", -1))
		if not result.get("ready", false) or timestamp <= last_timestamp:
			continue
		if last_timestamp > 0 and timestamp - last_timestamp > 500000:
			large_capture_gap_count += 1
		last_timestamp = timestamp
		result_count += 1
		var armor_count := int(result.get("armor_count", 0))
		if armor_count > 0:
			detection_count += 1
		if armor_count >= 2:
			two_armor_count += 1
		var state := str(result.get("tracker_state", "unknown"))
		state_counts[state] = int(state_counts.get(state, 0)) + 1
		if not result.get("control", false):
			continue

		control_count += 1
		var command_yaw := float(result.get("yaw_rad", 0.0))
		var command_pitch := float(result.get("pitch_rad", 0.0))
		var player = simulation.robots[robot_id] if "robots" in simulation else null
		if player != null:
			yaw_error_sum += absf(_wrap_angle(simulation._gimbal_world_yaw(player) - command_yaw))
			pitch_error_sum += absf(_wrap_angle(-player["pitch_axis"].rotation.x - command_pitch))
		else:
			yaw_error_sum += absf(command_yaw)
			pitch_error_sum += absf(command_pitch)

		var aim_point: Vector3 = result.get("aim_point", Vector3.ZERO)
		var target_position: Vector3 = result.get("target_position", Vector3.ZERO)
		var relative_aim := aim_point - target_position
		if have_last_aim and relative_aim.distance_to(last_relative_aim) > \
				AIM_SWITCH_DISTANCE_METERS:
			aim_switch_count += 1
			if last_switch_timestamp > 0 and \
					timestamp - last_switch_timestamp < rapid_switch_limit_usec:
				rapid_switch_count += 1
			last_switch_timestamp = timestamp
		last_relative_aim = relative_aim
		have_last_aim = true

	var result_divisor := maxf(1.0, result_count)
	var control_divisor := maxf(1.0, control_count)
	var report := {
		"spin_rad_s": spin,
		"travel_speed": travel_speed,
		"results": result_count,
		"detection_rate": detection_count / result_divisor,
		"control_rate": control_count / result_divisor,
		"two_armor_results": two_armor_count,
		"aim_switches": aim_switch_count,
		"rapid_switches": rapid_switch_count,
		"large_capture_gaps": large_capture_gap_count,
		"mean_yaw_servo_error_deg": rad_to_deg(yaw_error_sum / control_divisor),
		"mean_pitch_servo_error_deg": rad_to_deg(pitch_error_sum / control_divisor),
		"states": state_counts
	}
	print("MOVING_GYRO_TEST ", JSON.stringify(report))

	var failures: Array[String] = []
	if result_count < 120:
		failures.append("too few processed frames")
	if detection_count / result_divisor < 0.85:
		failures.append("detection rate below 85%")
	if control_count / result_divisor < 0.80:
		failures.append("control rate below 80%")
	if two_armor_count < 10:
		failures.append("scenario did not exercise two visible armors")
	if aim_switch_count < 3:
		failures.append("scenario did not exercise armor switching")
	if rapid_switch_count > 0:
		failures.append("detected rapid A-B-A armor switching")
	if large_capture_gap_count > 0:
		failures.append("capture gap exceeded 500 ms")
	if yaw_error_sum / control_divisor > deg_to_rad(8.0):
		failures.append("mean yaw servo error exceeded 8 degrees")

	if not failures.is_empty():
		push_error("MOVING_GYRO_TEST failed: " + "; ".join(failures))
		quit(1)
		return
	quit(0)
