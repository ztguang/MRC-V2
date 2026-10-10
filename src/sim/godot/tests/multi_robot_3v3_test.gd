extends SceneTree

## Automated 3v3 multi-engine smoke test.
## Requires a display (SubViewport capture is skipped headless).
##
##   godot --path sim/godot --script res://tests/multi_robot_3v3_test.gd
##
## Pass criteria:
##   - AutoAimBridge online
##   - every robot_id 0..5 receives >= MIN_RESULTS frames
##   - at least MIN_DETECTING_ROBOTS robots get >=1 armor detection
##   - worker processed count grows (engines are multiplexed, not stuck)

const WARMUP_FRAMES := 240
const TEST_FRAMES := 1800
const MIN_RESULTS := 8
const MIN_DETECTING_ROBOTS := 2
const ROBOT_COUNT := 6

func _initialize() -> void:
	change_scene_to_file("res://main.tscn")
	call_deferred("_run")

func _run() -> void:
	await process_frame
	await physics_frame
	await physics_frame
	var simulation = current_scene
	if simulation == null:
		_fail("main scene missing")
		return

	# Force AI + auto-aim on all robots including former player.
	simulation.overview_mode = true
	simulation.gameplay_controls_enabled = false
	simulation.ai_enabled = true
	simulation.auto_fire_all = false  # focus on perception engines
	if simulation.has_method("_set_active_camera"):
		simulation._set_active_camera()
	for robot in simulation.robots:
		robot["auto_aim_enabled"] = true

	if not bool(simulation.extension_ready):
		_fail("AutoAimBridge failed to initialize (extension offline)")
		return

	print("3v3 test: extension online, running %d physics frames..." % TEST_FRAMES)
	for frame in range(TEST_FRAMES):
		await physics_frame
		if frame == WARMUP_FRAMES:
			print("3v3 test: warmup done")

	var snap: Dictionary = simulation.get_verification_snapshot()
	print("=== 3v3 TEST SNAPSHOT ===")
	print(JSON.stringify(snap, "  "))

	var robots: Array = snap.get("robots", [])
	if robots.size() != ROBOT_COUNT:
		_fail("expected %d robots, got %d" % [ROBOT_COUNT, robots.size()])
		return

	var robots_with_results := 0
	var robots_with_detection := 0
	var result_total := 0
	for robot in robots:
		var results := int(robot.get("results", 0))
		var detections := int(robot.get("detections", 0))
		result_total += results
		if results >= MIN_RESULTS:
			robots_with_results += 1
		if detections > 0:
			robots_with_detection += 1
		print("robot %d team=%s results=%d det=%d ctrl=%d tracker=%s" % [
			int(robot.get("id", -1)),
			str(robot.get("team", "?")),
			results, detections,
			int(robot.get("controls", 0)),
			str(robot.get("tracker", "?"))])

	var stats: Dictionary = snap.get("runtime_stats", {})
	var processed := int(stats.get("processed", 0))
	var submitted := int(stats.get("submitted", 0))
	print("runtime submitted=%d processed=%d dropped=%s" % [
		submitted, processed, str(stats.get("dropped", 0))])

	var fusion_valid_total := 0
	var fusion_nb_max := 0
	var fusion_assist_total := 0
	for robot in robots:
		fusion_valid_total += int(robot.get("fusion_valid", 0))
		fusion_nb_max = maxi(fusion_nb_max, int(robot.get("fusion_neighbors_max", 0)))
		fusion_assist_total += int(robot.get("fusion_assist", 0))
	print("fusion valid_frames=%d neighbor_max=%d assist=%d" % [
		fusion_valid_total, fusion_nb_max, fusion_assist_total])

	var ok := true
	var reasons: PackedStringArray = []
	if robots_with_results < ROBOT_COUNT:
		ok = false
		reasons.append("only %d/%d robots reached %d results" % [
			robots_with_results, ROBOT_COUNT, MIN_RESULTS])
	if robots_with_detection < MIN_DETECTING_ROBOTS:
		ok = false
		reasons.append("only %d robots detected armor (need >=%d)" % [
			robots_with_detection, MIN_DETECTING_ROBOTS])
	if processed < ROBOT_COUNT * MIN_RESULTS:
		ok = false
		reasons.append("worker processed=%d too low" % processed)
	if submitted <= 0:
		ok = false
		reasons.append("no frames submitted")

	var report_path := "user://3v3_test_report.json"
	var report := {
		"ok": ok,
		"reasons": reasons,
		"robots_with_results": robots_with_results,
		"robots_with_detection": robots_with_detection,
		"result_total": result_total,
		"snapshot": snap,
	}
	var f := FileAccess.open(report_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(report, "  "))
		f.close()
		print("Wrote ", ProjectSettings.globalize_path(report_path))

	if ok:
		print("3v3 MULTI-ENGINE TEST PASSED")
		quit(0)
	else:
		_fail("; ".join(reasons))

func _fail(message: String) -> void:
	printerr("3v3 MULTI-ENGINE TEST FAILED: ", message)
	quit(1)
