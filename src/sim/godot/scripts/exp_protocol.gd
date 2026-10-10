extends RefCounted
## Revision experiment protocol (2026-09-24).
## Perception and team decision use vision tracks and one-shot hit reports.
## True enemy positions are read only inside eval_* for logged errors.

var active: bool = false
var fusion: Dictionary = {0: false, 1: false}
var focus: Dictionary = {0: false, 1: false}
var formation: Dictionary = {0: false, 1: false}
var rescue: Dictionary = {0: false, 1: false}
var fusion_mode_team: Dictionary = {0: "proposed", 1: "proposed"}
var gate_team: Dictionary = {0: true, 1: true}
var delay_sec: float = 0.0
var loss_p: float = 0.0
var extra_process_ms: int = 0
var fov_scale: float = 1.0
var cam_w: int = -1
var cam_h: int = -1
var match_seconds: float = 180.0
var seed_value: int = 1
var alpha: float = 0.5
var beta: float = 0.3
var gamma: float = 0.2
var lambda: float = 1.0
var d_ref: float = 5.0
var r_gate: float = 1.5
var age_max: float = 2.5
var calib: Dictionary = {0: false, 1: false}
var blend_aim: bool = false
var age_ema: Dictionary = {0: 0.0, 1: 0.0}
var proc_ema: float = 0.0
var lambda_sum: Dictionary = {0: 0.0, 1: 0.0}
var lambda_n: Dictionary = {0: 0, 1: 0}
var queue_ema: float = 0.0
var formation_scale_sum: Dictionary = {0: 0.0, 1: 0.0}
var formation_scale_n: Dictionary = {0: 0, 1: 0}
var capture_scale_sum: Dictionary = {0: 0.0, 1: 0.0}
var capture_scale_n: Dictionary = {0: 0, 1: 0}
var commit_n: Dictionary = {0: 0, 1: 0}
var nav_n: Dictionary = {0: 0, 1: 0}
var rng := RandomNumberGenerator.new()

var local_tracks: Dictionary = {}
var team_tracks: Dictionary = {0: [], 1: []}
var pending: Array = []
var distress: Dictionary = {}
var focus_hold: Dictionary = {}
var sweep_back: Dictionary = {}

var assist_count: Dictionary = {0: 0, 1: 0}
var focus_fire: Dictionary = {0: 0, 1: 0}
var rescue_count: Dictionary = {0: 0, 1: 0}
var pos_err_sum: float = 0.0
var pos_err_n: int = 0
var aim_err_sum: float = 0.0
var aim_err_n: int = 0
var ghost_n: int = 0
var fusion_out_n: int = 0
var blend_n: int = 0
var blend_multi_n: int = 0
var raw_dir: String = ""
var raw_lines: Array = []
var eval_lines: Array = []
var raw_flushed: bool = false
var slot_err_sum: float = 0.0
var slot_err_n: int = 0
var process_ms: Array = []
var queue_samples: Array = []
var dropped_seen: int = 0
var all_tracked_t: Dictionary = {0: -1.0, 1: -1.0}
var truth_blocked: int = 0
var samples: Array = []
var sample_cap: int = 80
var last_sample_t: float = -10.0
var spread_log_t: float = -10.0


func configure() -> void:
	active = OS.get_environment("SIM_EXP_PROTOCOL").strip_edges() == "1"
	if not active:
		return
	fusion[0] = _flag("SIM_FUSION_RED")
	fusion[1] = _flag("SIM_FUSION_BLUE")
	focus[0] = _flag("SIM_FOCUS_RED")
	focus[1] = _flag("SIM_FOCUS_BLUE")
	formation[0] = _flag("SIM_FORMATION_RED")
	formation[1] = _flag("SIM_FORMATION_BLUE")
	rescue[0] = _flag("SIM_RESCUE_RED")
	rescue[1] = _flag("SIM_RESCUE_BLUE")
	var mode_both := OS.get_environment("SIM_FUSION_MODE").strip_edges()
	if mode_both == "":
		mode_both = "proposed"
	fusion_mode_team[0] = _or_env("SIM_FUSION_MODE_RED", mode_both)
	fusion_mode_team[1] = _or_env("SIM_FUSION_MODE_BLUE", mode_both)
	var gate_both := OS.get_environment("SIM_GATE").strip_edges() != "0"
	gate_team[0] = _gate_env("SIM_GATE_RED", gate_both)
	gate_team[1] = _gate_env("SIM_GATE_BLUE", gate_both)
	delay_sec = _f("SIM_DELAY_MS", 0.0) / 1000.0
	loss_p = _f("SIM_LOSS", 0.0)
	extra_process_ms = int(_f("SIM_EXTRA_MS", 0.0))
	fov_scale = _f("SIM_FOV_SCALE", 1.0)
	cam_w = int(_f("SIM_CAM_W", -1.0))
	cam_h = int(_f("SIM_CAM_H", -1.0))
	match_seconds = _f("SIM_MATCH_SECONDS", 180.0)
	seed_value = int(_f("SIM_RUN_INDEX", 1.0))
	if seed_value <= 0:
		seed_value = 1
	alpha = _f("SIM_ALPHA", 0.5)
	beta = _f("SIM_BETA", 0.3)
	gamma = _f("SIM_GAMMA", 0.2)
	lambda = _f("SIM_LAMBDA", 1.0)
	d_ref = _f("SIM_D_REF", 5.0)
	calib[0] = _flag("SIM_CALIB_RED")
	calib[1] = _flag("SIM_CALIB_BLUE")
	blend_aim = OS.get_environment("SIM_BLEND_AIM").strip_edges() == "1"
	rng.seed = seed_value
	print("EXP_PROTOCOL seed=", seed_value, " ", summary_line())
	raw_dir = OS.get_environment("SIM_RAW_DIR").strip_edges()
	raw_lines = []
	eval_lines = []
	raw_flushed = false


func summary_line() -> String:
	return "R[f%d o%d m%d s%d/%s/g%d] B[f%d o%d m%d s%d/%s/g%d] delay=%.0fms loss=%.2f fov=%.2f cam=%dx%d extra=%d match=%.0f" % [
		int(fusion[0]), int(focus[0]), int(formation[0]), int(rescue[0]), str(fusion_mode_team[0]), int(gate_team[0]),
		int(fusion[1]), int(focus[1]), int(formation[1]), int(rescue[1]), str(fusion_mode_team[1]), int(gate_team[1]),
		delay_sec * 1000.0, loss_p, fov_scale, cam_w, cam_h, extra_process_ms, match_seconds,
	]


func apply_camera(host) -> void:
	if not active:
		return
	if cam_w > 0 and cam_h > 0:
		host.camera_size = Vector2i(cam_w, cam_h)
	if absf(fov_scale - 1.0) > 0.001:
		host.camera_fov = clampf(host.camera_fov * fov_scale, 10.0, 140.0)
	for robot in host.robots:
		robot["viewport"].size = host.camera_size
		robot["sim_camera"].fov = host.camera_fov
	if host.player_camera != null:
		host.player_camera.fov = host.camera_fov
	if host.camera_hz < 2.0:
		host.camera_hz = 2.0
	print("EXP_CAM ", host.camera_size.x, "x", host.camera_size.y, " fov ", snappedf(host.camera_fov, 0.1))


func block_truth() -> void:
	truth_blocked += 1


func ingest_result(robot: Dictionary, result: Dictionary, sim_time: float, robots: Array = []) -> void:
	if not active:
		return
	var ms := float(result.get("total_ms", 0.0))
	if ms > 0.0:
		_push_cap(process_ms, ms, 400)
		proc_ema = 0.9 * proc_ema + 0.1 * ms if proc_ema > 0.0 else ms
	if int(robot.get("id", -1)) == 0:
		var stats: Dictionary = {}
		if robot.has("bridge_stats"):
			stats = robot["bridge_stats"]
		if stats.has("queue_depth"):
			var qd := float(stats["queue_depth"])
			_push_cap(queue_samples, qd, 400)
			queue_ema = 0.9 * queue_ema + 0.1 * qd
		if stats.has("dropped"):
			dropped_seen = int(stats["dropped"])
	if extra_process_ms > 0:
		OS.delay_msec(extra_process_ms)
	var armor := int(result.get("armor_count", 0))
	if armor <= 0:
		return
	var tp: Vector3 = result.get("target_position", Vector3.ZERO)
	if tp.length_squared() < 1e-8:
		return
	var world: Vector3 = robot["body"].global_position + tp
	var conf := float(result.get("lock_quality", 0.0))
	if conf <= 0.05:
		conf = 0.6
	conf = clampf(conf, 0.05, 1.0)
	var team := int(robot["team"])
	var rid := int(robot["id"])
	var dist: float = robot["body"].global_position.distance_to(world)
	_note_raw(robot, world, conf, sim_time, robots)
	return
	_upsert(local_tracks, rid, world, conf, sim_time, true)
	if not _shares(team):
		return
	if loss_p > 0.0 and rng.randf() < loss_p:
		return
	pending.append({
		"deliver": sim_time + delay_sec,
		"t_obs": sim_time,
		"team": team,
		"from": rid,
		"pos": world,
		"conf": conf,
		"dist": dist,
	})


func update(host, sim_time: float) -> void:
	if not active:
		return
	var robots: Array = host.robots
	var keep: Array = []
	for item in pending:
		if float(item["deliver"]) <= sim_time:
			var team := int(item["team"])
			_upsert(team_tracks, team, item["pos"], float(item["conf"]), float(item["t_obs"]), bool(gate_team[team]))
		else:
			keep.append(item)
	pending = keep
	for team in [0, 1]:
		team_tracks[team] = _drop_old(team_tracks[team], sim_time, _age_limit(int(team)))
		var covered := _covered_enemies(team, robots, sim_time)
		if covered >= 3 and float(all_tracked_t[team]) < 0.0:
			all_tracked_t[team] = sim_time
	for rid in local_tracks.keys():
		local_tracks[rid] = _drop_old(local_tracks[rid], sim_time)
	if samples.size() < sample_cap and sim_time - last_sample_t >= 3.0:
		last_sample_t = sim_time
		_maybe_sample(robots, sim_time)
		if sim_time - spread_log_t >= 5.0:
			spread_log_t = sim_time
			var spread_msg: String = "SPREAD t=%.1f" % snappedf(sim_time, 0.1)
			for spread_r in robots:
				if not bool(spread_r.get("alive", true)):
					continue
				var spread_p: Vector3 = spread_r["body"].global_position
				spread_msg += " %d:(%.1f,%.1f)" % [int(spread_r["id"]), spread_p.x, spread_p.z]
			print(spread_msg)


func share_sight(robot: Dictionary, world_pos: Vector3, sim_time: float) -> void:
	if not active:
		return
	var team: int = int(robot["team"])
	if not _shares(team):
		return
	var pos: Vector3 = world_pos
	pos.y = 0.0
	var my: Vector3 = robot["body"].global_position
	var seen_d: float = my.distance_to(pos)
	if seen_d < 0.4 or seen_d > 12.0:
		return
	var rid: int = int(robot["id"])
	_upsert(local_tracks, rid, pos, 0.9, sim_time, true)
	if loss_p > 0.0 and rng.randf() < loss_p:
		return
	pending.append({
		"deliver": sim_time + delay_sec,
		"t_obs": sim_time,
		"team": team,
		"from": rid,
		"pos": pos,
		"conf": 0.9,
		"dist": seen_d,
	})
	if sim_time - float(robot.get("share_log_t", -10.0)) > 1.0:
		robot["share_log_t"] = sim_time
		print("COOP_SHARE id=", rid, " team=", team)


func team_look_dir(robot: Dictionary, sim_time: float, robots: Array) -> Vector3:
	if not active:
		return Vector3.ZERO
	var tr: Dictionary = _select_track(robot, sim_time, robots)
	if tr.is_empty() or not tr.has("pos"):
		return Vector3.ZERO
	var age: float = sim_time - float(tr.get("t", -10.0))
	if age > 2.2:
		return Vector3.ZERO
	var to: Vector3 = tr["pos"] - robot["body"].global_position
	to.y = 0.0
	if to.length_squared() < 0.25:
		return Vector3.ZERO
	return to.normalized()


func focus_point(robot: Dictionary, sim_time: float, robots: Array) -> Vector3:
	## Shared aim point for a focusing team. Zero when this team does not focus.
	if not active:
		return Vector3.ZERO
	if not bool(focus[int(robot["team"])]):
		return Vector3.ZERO
	var tr: Dictionary = _select_track(robot, sim_time, robots)
	if tr.is_empty() or not tr.has("pos"):
		return Vector3.ZERO
	if sim_time - float(tr.get("t", -10.0)) > 2.2:
		return Vector3.ZERO
	var pos: Vector3 = tr["pos"]
	pos.y = 0.0
	return pos


func _attack_ring(robot: Dictionary, my: Vector3, anchor: Vector3, robots: Array) -> Vector3:
	## Near-side standoff. A wide flank point walked robots past the armor.
	var away: Vector3 = my - anchor
	away.y = 0.0
	if away.length_squared() < 1e-4:
		away = Vector3(0.0, 0.0, 1.0)
	else:
		away = away.normalized()
	var right: Vector3 = Vector3(-away.z, 0.0, away.x)
	var my_proj: float = my.dot(right)
	var lower: int = 0
	var higher: int = 0
	for mate in robots:
		if int(mate.get("team", -1)) != int(robot.get("team", -2)):
			continue
		if not bool(mate.get("alive", true)):
			continue
		if int(mate.get("id", -1)) == int(robot.get("id", -2)):
			continue
		var mate_pos: Vector3 = mate["body"].global_position
		mate_pos.y = 0.0
		var mate_proj: float = mate_pos.dot(right)
		if mate_proj < my_proj - 0.2:
			lower += 1
		elif mate_proj > my_proj + 0.2:
			higher += 1
	var side: float = 0.0
	if lower > higher:
		side = 1.0
	elif higher > lower:
		side = -1.0
	return anchor + away * 3.3 + right * side * 1.2


func _sweep_key(robot: Dictionary) -> String:
	return "r%d" % int(robot["id"])


func _at_enemy_wall(team: int, z: float) -> bool:
	if team == 0:
		return z < -6.2
	return z > 6.2


func _sweep_done_z(team: int, z: float) -> bool:
	if team == 0:
		return z > 2.0
	return z < -2.0


func _all_living_at_wall(team: int, robots: Array) -> bool:
	var alive_n: int = 0
	for mate in robots:
		if int(mate.get("team", -1)) != team or not bool(mate.get("alive", true)):
			continue
		alive_n += 1
		var mz: float = mate["body"].global_position.z
		if not _at_enemy_wall(team, mz):
			return false
	return alive_n > 0


func _update_sweep(robot: Dictionary, robots: Array, fresh_nav: bool) -> void:
	var key: String = _sweep_key(robot)
	var team: int = int(robot["team"])
	if fresh_nav:
		sweep_back[key] = false
		return
	if bool(sweep_back.get(key, false)):
		if _sweep_done_z(team, robot["body"].global_position.z):
			sweep_back[key] = false
		return
	if _all_living_at_wall(team, robots):
		sweep_back[key] = true


func _wants_sweep(robot: Dictionary) -> bool:
	return bool(sweep_back.get(_sweep_key(robot), false))


func nav_goal(robot: Dictionary, sim_time: float, field_half: float, robots: Array) -> Vector3:
	var my: Vector3 = robot["body"].global_position
	var tr: Dictionary = _select_track(robot, sim_time, robots)
	var track_age: float = 99.0
	if not tr.is_empty() and tr.has("t"):
		track_age = sim_time - float(tr["t"])
	var fresh_nav: bool = (not tr.is_empty()) and track_age <= 2.2
	_update_sweep(robot, robots, fresh_nav)
	var goal: Vector3 = search_goal(robot, sim_time)
	var behind: bool = false
	if int(robot["team"]) == 0 and my.z > 4.85:
		behind = true
	elif int(robot["team"]) == 1 and my.z < -4.85:
		behind = true
	if fresh_nav and not behind:
		goal = _attack_ring(robot, my, tr["pos"], robots)
		var team_nav: int = int(robot["team"])
		var applied_scale: float = 1.0
		if blend_aim and bool(calib.get(team_nav, false)):
			applied_scale = _formation_scale(team_nav)
			var anchor_nav: Vector3 = tr["pos"]
			goal = anchor_nav + (goal - anchor_nav) * applied_scale
		if blend_aim:
			formation_scale_sum[team_nav] = float(formation_scale_sum.get(team_nav, 0.0)) + applied_scale
			formation_scale_n[team_nav] = int(formation_scale_n.get(team_nav, 0)) + 1
	elif _shares(int(robot["team"])) and not behind and not _wants_sweep(robot):
		var lead_z: float = my.z
		var team_i: int = int(robot["team"])
		for mate in robots:
			if int(mate.get("team", -1)) != team_i or not bool(mate.get("alive", true)):
				continue
			var mz: float = mate["body"].global_position.z
			if team_i == 0:
				lead_z = minf(lead_z, mz)
			else:
				lead_z = maxf(lead_z, mz)
		if team_i == 0:
			goal.z = minf(goal.z, lead_z)
		else:
			goal.z = maxf(goal.z, lead_z)
	if not _wants_sweep(robot):
		if int(robot["team"]) == 0 and my.z > 4.2:
			goal.z = minf(goal.z, my.z)
		elif int(robot["team"]) == 1 and my.z < -4.2:
			goal.z = maxf(goal.z, my.z)
	var slot_d: float = my.distance_to(goal)
	slot_err_sum += slot_d
	slot_err_n += 1
	goal.y = 0.0
	var dist: float = my.distance_to(goal)
	if dist > 2.4:
		var step: float = clampf(dist * 0.5, 2.2, 4.5)
		var dir: Vector3 = goal - my
		dir.y = 0.0
		if dir.length_squared() > 1e-6:
			goal = my + dir.normalized() * step
	goal.x = clampf(goal.x, -field_half + 0.9, field_half - 0.9)
	goal.z = clampf(goal.z, -field_half + 0.9, field_half - 0.9)
	goal.y = 0.0
	return goal


func search_goal(robot: Dictionary, sim_time: float) -> Vector3:
	## Gaps between the opening shields. A sharing team uses one depth clock.
	var team: int = int(robot["team"])
	var slot: int = int(robot.get("id", 0)) % 3
	var lane_x: float = -4.7
	if slot == 1:
		lane_x = -1.6
	elif slot == 2:
		lane_x = 1.6
	var depth: float = clampf(sim_time / 14.0, 0.0, 1.0)
	if not _shares(team):
		depth = clampf((sim_time + float(slot) * 1.5) / 14.0, 0.0, 1.0)
	var lane_z: float = lerpf(-2.0, -4.6, depth)
	if team == 1:
		lane_x = -lane_x
		lane_z = -lane_z
	var my: Vector3 = robot["body"].global_position
	if team == 0 and my.z > 4.85:
		if absf(my.x - lane_x) > 0.55:
			return Vector3(lane_x, 0.0, 6.15)
		return Vector3(lane_x, 0.0, 4.2)
	if team == 1 and my.z < -4.85:
		if absf(my.x - lane_x) > 0.55:
			return Vector3(lane_x, 0.0, -6.15)
		return Vector3(lane_x, 0.0, -4.2)
	if _wants_sweep(robot):
		var home_z: float = 2.2
		if team == 1:
			home_z = -2.2
		return Vector3(lane_x, 0.0, home_z)
	return Vector3(lane_x, 0.0, lane_z)


func search_heading(robot: Dictionary, sim_time: float) -> Vector3:
	## Look along the corridor. At the goal, keep facing the enemy camp.
	var goal: Vector3 = search_goal(robot, sim_time)
	var toward: Vector3 = goal - robot["body"].global_position
	toward.y = 0.0
	if toward.length_squared() >= 0.16:
		return toward.normalized()
	if _wants_sweep(robot):
		if int(robot["team"]) == 0:
			return Vector3(0.0, 0.0, 1.0)
		return Vector3(0.0, 0.0, -1.0)
	if int(robot["team"]) == 0:
		return Vector3(0.0, 0.0, -1.0)
	return Vector3(0.0, 0.0, 1.0)

func _spread_hold(robot: Dictionary, my: Vector3, pos: Vector3) -> Vector3:
	## Standoff around a fresh track so teammates do not share one point.
	var away: Vector3 = my - pos
	away.y = 0.0
	if away.length_squared() < 0.09:
		if int(robot["team"]) == 0:
			away = Vector3(0.0, 0.0, 1.0)
		else:
			away = Vector3(0.0, 0.0, -1.0)
	else:
		away = away.normalized()
	var right: Vector3 = Vector3(-away.z, 0.0, away.x)
	var slot: int = int(robot.get("id", 0)) % 3
	var side: float = 0.0
	if slot == 0:
		side = -1.0
	elif slot == 2:
		side = 1.0
	return pos + away * 3.2 + right * side * 1.8

func has_aim(robot: Dictionary, sim_time: float) -> bool:
	if not active:
		return false
	var fused: Dictionary = _aim_track(robot, sim_time)
	return not fused.is_empty()


func aim_is_fresh(robot: Dictionary, sim_time: float) -> bool:
	var fused: Dictionary = _aim_track(robot, sim_time)
	if fused.is_empty():
		return false
	return float(fused.get("age", 99.0)) <= 1.0

func can_fire(host, robot: Dictionary, sim_time: float) -> bool:
	## Shoot the held camera lock once the barrel has settled. A team track cannot authorize a shot.
	if not active:
		return false
	var aim_dir: Vector3 = Vector3.ZERO
	var dist: float = 0.0
	if float(robot.get("fire_lock_until", -1.0)) > sim_time:
		aim_dir = robot.get("fire_lock_dir", Vector3.ZERO)
		dist = float(robot.get("fire_lock_dist", 0.0))
	else:
		return false
	if aim_dir.length_squared() < 0.25:
		return false
	aim_dir = aim_dir.normalized()
	if dist < 0.35 or dist > 12.0:
		return false
	var seen_age: float = sim_time - float(robot.get("vision_last_see_t", -10.0))
	if seen_age > 0.85:
		return false
	var muzzle: Vector3 = host._muzzle_world_dir(robot)
	var align: float = muzzle.dot(aim_dir)
	if align < 0.97:
		return false
	var cmd_yaw: float = float(robot.get("command_yaw", robot["body"].rotation.y))
	var cmd_dir: Vector3 = Vector3(-sin(cmd_yaw), 0.0, -cos(cmd_yaw))
	if cmd_dir.dot(aim_dir) < 0.90:
		return false
	var eye: Vector3 = robot["pitch_axis"].global_position
	var flat: Vector3 = Vector3(muzzle.x, 0.0, muzzle.z)
	if flat.length_squared() < 1e-6:
		return false
	var dest: Vector3 = eye + flat.normalized() * dist
	dest.y = eye.y
	var excl: Array = [robot["body"].get_rid()]
	if host._cover_blocks_barrel(eye, dest, excl):
		return false
	robot["last_aim_align"] = align
	return true


func _blend_selected(robot: Dictionary, sim_time: float, selected: Vector3) -> Dictionary:
	var team := int(robot["team"])
	var rid := int(robot["id"])
	var own: Array = _fresh(local_tracks.get(rid, []), sim_time)
	var shared: Array = []
	if bool(fusion[team]):
		shared = _fresh(team_tracks.get(team, []), sim_time, _age_limit(team))
	var use_gate := bool(gate_team.get(team, true))
	var cands: Array = []
	for tr in own:
		var own_pos: Vector3 = tr["pos"]
		if (not use_gate) or own_pos.distance_to(selected) <= r_gate:
			cands.append({"pos": own_pos, "conf": tr["conf"], "age": maxf(0.0, sim_time - float(tr["t"])), "neighbor": false})
	var neighbor_n := 0
	for tr2 in shared:
		var sh_pos: Vector3 = tr2["pos"]
		if (not use_gate) or sh_pos.distance_to(selected) <= r_gate:
			cands.append({"pos": sh_pos, "conf": tr2["conf"], "age": maxf(0.0, sim_time - float(tr2["t"])), "neighbor": true})
			neighbor_n += 1
	if cands.is_empty():
		return {"pos": selected, "used_neighbor": false}
	_feedback_age(team, cands)
	var use_lambda := _lambda_eff(team)
	lambda_sum[team] = float(lambda_sum.get(team, 0.0)) + use_lambda
	lambda_n[team] = int(lambda_n.get(team, 0)) + 1
	blend_n += 1
	if cands.size() >= 2:
		blend_multi_n += 1
	var blended: Dictionary = _blend(robot["body"].global_position, cands, str(fusion_mode_team[team]), use_lambda)
	blended["used_neighbor"] = neighbor_n > 0
	return blended


func apply_aim(host, robot: Dictionary, sim_time: float) -> void:
	if not active:
		return
	if float(robot.get("fire_lock_until", -1.0)) > sim_time:
		return
	if bool(robot.get("vision_has_target", false)) and float(robot.get("vision_age", 99.0)) < 0.8:
		return
	var team: int = int(robot["team"])
	var pos: Vector3 = Vector3.ZERO
	var used_neighbor: bool = false
	if _shares(team):
		var picked: Dictionary = _select_track(robot, sim_time, host.robots)
		if picked.is_empty():
			return
		var picked_age: float = sim_time - float(picked.get("t", sim_time - 99.0))
		if picked_age > 2.2:
			return
		pos = picked["pos"]
		used_neighbor = true
		if blend_aim and bool(fusion[team]):
			var blended: Dictionary = _blend_selected(robot, sim_time, pos)
			if not blended.is_empty() and blended.has("pos"):
				pos = blended["pos"]
				used_neighbor = bool(blended.get("used_neighbor", used_neighbor))
	else:
		var fused: Dictionary = _aim_track(robot, sim_time)
		if fused.is_empty():
			return
		if float(fused.get("age", 99.0)) > 1.0:
			return
		pos = fused["pos"]
		used_neighbor = bool(fused.get("used_neighbor", false))
	var my: Vector3 = robot["body"].global_position
	var to: Vector3 = pos - my
	to.y = 0.0
	if to.length_squared() < 0.04:
		return
	robot["command_yaw"] = host._yaw_from_dir(to)
	robot["command_pitch"] = 0.0
	if sim_time - float(robot.get("exp_assist_t", -10.0)) > 0.5:
		robot["exp_assist_t"] = sim_time
		if bool(fusion[team]) and used_neighbor:
			assist_count[team] = int(assist_count[team]) + 1
	_score_output(pos, robot, host.robots, sim_time, to)


func note_hit(robots: Array, victim: Dictionary, attacker_id: int, sim_time: float) -> void:
	if not active:
		return
	var team := int(victim["team"])
	if not bool(rescue[team]):
		return
	if attacker_id < 0 or attacker_id >= robots.size():
		return
	var atk: Dictionary = robots[attacker_id]
	if int(atk.get("team", -1)) == team or not bool(atk.get("alive", true)):
		return
	var pos: Vector3 = atk["body"].global_position
	distress[team] = {"pos": pos, "until": sim_time + 5.5}
	if not team_tracks.has(team):
		team_tracks[team] = []
	_upsert(team_tracks, team, pos, 0.95, sim_time, true)
	rescue_count[team] = int(rescue_count[team]) + 1


func note_shot(robot: Dictionary, _sim_time: float) -> void:
	if not active:
		return
	var team := int(robot["team"])
	if bool(focus[team]):
		focus_fire[team] = int(focus_fire[team]) + 1


func metrics() -> Dictionary:
	var raw_n := raw_lines.size()
	_flush_raw()
	var pos_mean := pos_err_sum / float(pos_err_n) if pos_err_n > 0 else -1.0
	var aim_mean := aim_err_sum / float(aim_err_n) if aim_err_n > 0 else -1.0
	var slot_mean := slot_err_sum / float(slot_err_n) if slot_err_n > 0 else -1.0
	var ghost_rate := float(ghost_n) / float(fusion_out_n) if fusion_out_n > 0 else -1.0
	return {
		"protocol": 1,
		"raw_n": raw_n,
		"fusion_red": int(fusion[0]),
		"fusion_blue": int(fusion[1]),
		"focus_red": int(focus[0]),
		"focus_blue": int(focus[1]),
		"formation_red": int(formation[0]),
		"formation_blue": int(formation[1]),
		"rescue_red": int(rescue[0]),
		"rescue_blue": int(rescue[1]),
		"fusion_mode_red": str(fusion_mode_team[0]),
		"fusion_mode_blue": str(fusion_mode_team[1]),
		"gate_red": int(gate_team[0]),
		"gate_blue": int(gate_team[1]),
		"delay_ms": snappedf(delay_sec * 1000.0, 0.1),
		"loss": loss_p,
		"fov_scale": fov_scale,
		"cam_w": cam_w,
		"cam_h": cam_h,
		"extra_ms": extra_process_ms,
		"alpha": alpha,
		"beta": beta,
		"gamma": gamma,
		"lambda": lambda,
		"calib_red": int(calib[0]),
		"calib_blue": int(calib[1]),
		"blend_aim": int(blend_aim),
		"blend_n": blend_n,
		"blend_multi_n": blend_multi_n,
		"lambda_n_red": int(lambda_n[0]),
		"lambda_n_blue": int(lambda_n[1]),
		"lambda_eff_red": snappedf(_lambda_mean(0), 0.01),
		"lambda_eff_blue": snappedf(_lambda_mean(1), 0.01),
		"age_ema_red": snappedf(float(age_ema[0]), 0.01),
		"age_ema_blue": snappedf(float(age_ema[1]), 0.01),
		"proc_ema_ms": snappedf(proc_ema, 0.01),
		"queue_ema": snappedf(queue_ema, 0.01),
		"formation_scale_red": snappedf(_scale_mean(0), 0.01),
		"formation_scale_blue": snappedf(_scale_mean(1), 0.01),
		"capture_scale_red": snappedf(_capture_mean(0), 0.01),
		"capture_scale_blue": snappedf(_capture_mean(1), 0.01),
		"commit_frac_red": snappedf(_commit_frac(0), 0.01),
		"commit_frac_blue": snappedf(_commit_frac(1), 0.01),
		"d_ref": d_ref,
		"r_gate": r_gate,
		"pos_err_mean_m": snappedf(pos_mean, 0.001) if pos_mean >= 0.0 else -1.0,
		"pos_err_n": pos_err_n,
		"aim_err_mean_deg": snappedf(rad_to_deg(aim_mean), 0.01) if aim_mean >= 0.0 else -1.0,
		"aim_err_n": aim_err_n,
		"ghost_n": ghost_n,
		"fusion_out_n": fusion_out_n,
		"ghost_rate": snappedf(ghost_rate, 0.001) if ghost_rate >= 0.0 else -1.0,
		"slot_err_mean_m": snappedf(slot_mean, 0.001) if slot_mean >= 0.0 else -1.0,
		"assist_red": int(assist_count[0]),
		"assist_blue": int(assist_count[1]),
		"focus_fire_red": int(focus_fire[0]),
		"focus_fire_blue": int(focus_fire[1]),
		"rescue_events_red": int(rescue_count[0]),
		"rescue_events_blue": int(rescue_count[1]),
		"process_ms_p50": snappedf(_pct(process_ms, 0.50), 0.01),
		"process_ms_p95": snappedf(_pct(process_ms, 0.95), 0.01),
		"queue_p95": snappedf(_pct(queue_samples, 0.95), 0.01),
		"dropped": dropped_seen,
		"all_tracked_t_red": snappedf(float(all_tracked_t[0]), 0.01),
		"all_tracked_t_blue": snappedf(float(all_tracked_t[1]), 0.01),
		"truth_blocked": truth_blocked,
		"samples": samples,
	}


func _shares(team: int) -> bool:
	return bool(fusion[team]) or bool(focus[team]) or bool(formation[team]) or bool(rescue[team])


func _select_track(robot: Dictionary, sim_time: float, robots: Array) -> Dictionary:
	var team := int(robot["team"])
	var rid := int(robot["id"])
	var own: Array = _fresh(local_tracks.get(rid, []), sim_time)
	var shared: Array = []
	if _shares(team):
		shared = _fresh(team_tracks.get(team, []), sim_time, _age_limit(team))
	var pool: Array = own if not bool(focus[team]) else shared
	if pool.is_empty():
		pool = own
	if pool.is_empty():
		return {}
	if bool(rescue[team]) and distress.has(team):
		var dst: Dictionary = distress[team]
		if sim_time <= float(dst["until"]):
			return _nearest_track(pool, dst["pos"])
	if bool(focus[team]) and not shared.is_empty():
		var shared_best: Dictionary = _nearest_track(shared, _centroid(robots, team))
		if focus_hold.has(team):
			var held: Dictionary = focus_hold[team]
			var held_age: float = sim_time - float(held.get("t", -10.0))
			if held_age < 4.0 and held.has("pos"):
				var stuck: Dictionary = _nearest_track(shared, held["pos"])
				if not stuck.is_empty() and stuck.has("pos"):
					var stuck_pos: Vector3 = stuck["pos"]
					var held_pos: Vector3 = held["pos"]
					if stuck_pos.distance_to(held_pos) < 1.8:
						shared_best = stuck
		var next_pos: Vector3 = shared_best["pos"]
		var switched: bool = true
		if focus_hold.has(team) and focus_hold[team].has("pos"):
			var prev_pos: Vector3 = focus_hold[team]["pos"]
			switched = prev_pos.distance_to(next_pos) > 1.8
		if switched:
			print("FOCUS_TARGET team=", team, " t=", snappedf(sim_time, 0.1))
		focus_hold[team] = {"pos": shared_best["pos"], "t": sim_time}
		if bool(calib[team]) and not own.is_empty():
			var own_best := _nearest_track(own, robot["body"].global_position)
			var shared_age := sim_time - float(shared_best.get("t", sim_time))
			var own_age := sim_time - float(own_best.get("t", sim_time))
			if shared_age > own_age + 0.6:
				return own_best
		return shared_best
	return _nearest_track(pool, robot["body"].global_position)


func _aim_track(robot: Dictionary, sim_time: float) -> Dictionary:
	var team := int(robot["team"])
	var rid := int(robot["id"])
	var own: Array = _fresh(local_tracks.get(rid, []), sim_time)
	var shared: Array = []
	if bool(fusion[team]):
		shared = _fresh(team_tracks.get(team, []), sim_time, _age_limit(team))
	if not bool(fusion[team]):
		if own.is_empty():
			return {}
		var only: Dictionary = _nearest_track(own, robot["body"].global_position)
		only["used_neighbor"] = false
		only["age"] = maxf(0.0, sim_time - float(only.get("t", sim_time - 99.0)))
		return only
	var cands: Array = []
	for tr in own:
		cands.append({"pos": tr["pos"], "conf": tr["conf"], "age": maxf(0.0, sim_time - float(tr["t"])), "neighbor": false})
	for tr in shared:
		cands.append({"pos": tr["pos"], "conf": tr["conf"], "age": maxf(0.0, sim_time - float(tr["t"])), "neighbor": true})
	if cands.is_empty():
		return {}
	_feedback_age(team, cands)
	var use_lambda := _lambda_eff(team)
	lambda_sum[team] = float(lambda_sum[team]) + use_lambda
	lambda_n[team] = int(lambda_n[team]) + 1
	var blended := _blend(robot["body"].global_position, cands, str(fusion_mode_team[team]), use_lambda)
	blended["used_neighbor"] = not shared.is_empty()
	var youngest: float = 99.0
	for cand in cands:
		youngest = minf(youngest, float(cand["age"]))
	blended["age"] = youngest
	return blended


func _blend(origin: Vector3, cands: Array, mode: String, use_lambda: float = -1.0) -> Dictionary:
	if mode == "nearest":
		var best: Dictionary = cands[0]
		var best_d: float = origin.distance_to(best["pos"])
		for c in cands:
			var d: float = origin.distance_to(c["pos"])
			if d < best_d:
				best_d = d
				best = c
		return {"pos": best["pos"], "conf": best["conf"]}
	var scores: Array = []
	var max_s := -1.0e30
	for c in cands:
		var d := maxf(origin.distance_to(c["pos"]), 0.15)
		var s := 0.0
		if mode == "legacy":
			s = 0.5 * float(c["conf"]) + 0.3 / d + 0.2 * exp(-0.1 * float(c["age"]))
		elif mode == "uniform":
			s = 1.0
		else:
			var d_tilde := exp(-d / maxf(d_ref, 0.5))
			var lam := lambda if use_lambda < 0.0 else use_lambda
			var f_tilde := exp(-lam * float(c["age"]))
			s = alpha * float(c["conf"]) + beta * d_tilde + gamma * f_tilde
		scores.append(s)
		max_s = maxf(max_s, s)
	var sum_e := 0.0
	var weights: Array = []
	for s in scores:
		var e := exp(float(s) - max_s)
		weights.append(e)
		sum_e += e
	var pos := Vector3.ZERO
	var conf := 0.0
	if sum_e <= 1.0e-12:
		return {"pos": cands[0]["pos"], "conf": cands[0]["conf"]}
	for i in range(cands.size()):
		var w := float(weights[i]) / sum_e
		pos += cands[i]["pos"] * w
		conf += float(cands[i]["conf"]) * w
	return {"pos": pos, "conf": conf}


func _score_output(pos: Vector3, robot: Dictionary, robots: Array, _sim_time: float, aim_dir: Vector3) -> void:
	var team := int(robot["team"])
	var err := _nearest_enemy_dist(pos, robots, team)
	if err < 1.0e8:
		pos_err_sum += err
		pos_err_n += 1
		fusion_out_n += 1
		if err > r_gate:
			ghost_n += 1
	var truth_dir := _nearest_enemy_dir(robot["body"].global_position, robots, team)
	if truth_dir.length_squared() > 1e-6 and aim_dir.length_squared() > 1e-6:
		var ang := acos(clampf(aim_dir.normalized().dot(truth_dir.normalized()), -1.0, 1.0))
		aim_err_sum += ang
		aim_err_n += 1


func _upsert(bucket: Dictionary, key, pos: Vector3, conf: float, t: float, gate: bool) -> void:
	if not bucket.has(key):
		bucket[key] = []
	var list: Array = bucket[key]
	if not gate:
		if list.is_empty():
			list.append({"pos": pos, "conf": conf, "t": t, "n": 1})
		else:
			var tr: Dictionary = list[0]
			var n := int(tr["n"])
			tr["pos"] = (tr["pos"] * float(n) + pos) / float(n + 1)
			tr["conf"] = conf
			tr["t"] = t
			tr["n"] = n + 1
			list[0] = tr
		bucket[key] = list
		return
	var best_i := -1
	var best_d := r_gate
	for i in range(list.size()):
		var d := (list[i]["pos"] as Vector3).distance_to(pos)
		if d < best_d:
			best_d = d
			best_i = i
	if best_i < 0:
		list.append({"pos": pos, "conf": conf, "t": t, "n": 1})
	else:
		var tr2: Dictionary = list[best_i]
		tr2["pos"] = pos
		tr2["conf"] = maxf(float(tr2["conf"]), conf)
		tr2["t"] = t
		tr2["n"] = int(tr2["n"]) + 1
		list[best_i] = tr2
	bucket[key] = list


func _drop_old(list: Array, now: float, limit: float = -1.0) -> Array:
	var lim := age_max if limit < 0.0 else limit
	var out: Array = []
	for tr in list:
		if now - float(tr["t"]) <= lim:
			out.append(tr)
	return out


func _fresh(list: Array, now: float, limit: float = -1.0) -> Array:
	return _drop_old(list, now, limit)


func _feedback_age(team: int, cands: Array) -> void:
	var acc := 0.0
	var n := 0
	for c in cands:
		if bool(c.get("neighbor", false)):
			acc += float(c["age"])
			n += 1
	if n == 0:
		return
	var mean_age := acc / float(n)
	var prev := float(age_ema[team])
	age_ema[team] = mean_age if prev <= 0.0 else 0.8 * prev + 0.2 * mean_age


func _lambda_eff(team: int) -> float:
	if not bool(calib.get(team, false)):
		return lambda
	var age := float(age_ema.get(team, 0.0))
	var extra := maxf(0.0, age - 0.25) / 0.25
	var lam := lambda * (1.0 + extra)
	if proc_ema > 40.0:
		lam *= 1.25
	return clampf(lam, 0.5, 4.0)


func _age_limit(team: int) -> float:
	if not bool(calib.get(team, false)):
		return age_max
	var age := float(age_ema.get(team, 0.0))
	if age > 1.0 or proc_ema > 40.0:
		return 1.5
	return age_max


func capture_period_scale(team: int) -> float:
	if not bool(calib.get(team, false)):
		return 1.0
	var scale := 1.0
	if proc_ema > 32.0 or queue_ema > 0.5:
		scale = 2.0
	capture_scale_sum[team] = float(capture_scale_sum.get(team, 0.0)) + scale
	capture_scale_n[team] = int(capture_scale_n.get(team, 0)) + 1
	return scale


func _standoff(my: Vector3, enemy_pos: Vector3, radius: float) -> Vector3:
	var away := my - enemy_pos
	away.y = 0.0
	if away.length_squared() < 0.09:
		away = Vector3(1.0, 0.0, 0.0)
	return enemy_pos + away.normalized() * radius


func _track_fresh(tr: Dictionary, sim_time: float) -> bool:
	if tr.is_empty():
		return false
	var age := sim_time - float(tr.get("t", sim_time))
	var conf := float(tr.get("conf", 0.0))
	return age < 0.9 and conf >= 0.35


func _commit_frac(team: int) -> float:
	var n := int(nav_n.get(team, 0))
	if n <= 0:
		return 0.0
	return float(commit_n.get(team, 0)) / float(n)


func _formation_scale(team: int) -> float:
	var age := float(age_ema.get(team, 0.0))
	if age <= 0.4 and proc_ema <= 32.0:
		return 1.0
	return 0.45


func _scale_mean(team: int) -> float:
	var n := int(formation_scale_n.get(team, 0))
	if n <= 0:
		return _formation_scale(team)
	return float(formation_scale_sum.get(team, 0.0)) / float(n)


func _capture_mean(team: int) -> float:
	var n := int(capture_scale_n.get(team, 0))
	if n <= 0:
		return 1.0
	return float(capture_scale_sum.get(team, 0.0)) / float(n)


func team_rule_text(team: int) -> String:
	var coop := bool(fusion.get(team, false)) or bool(focus.get(team, false)) or bool(formation.get(team, false)) or bool(rescue.get(team, false))
	var name := "有协同" if coop else "无协同"
	if bool(calib.get(team, false)):
		name += "+校准"
	return name


func _lambda_mean(team: int) -> float:
	var n := int(lambda_n.get(team, 0))
	if n <= 0:
		return _lambda_eff(team)
	return float(lambda_sum.get(team, 0.0)) / float(n)


func _nearest_track(list: Array, pos: Vector3) -> Dictionary:
	if list.is_empty():
		return {}
	var best: Dictionary = list[0]
	var best_d := (best["pos"] as Vector3).distance_to(pos)
	for tr in list:
		var d := (tr["pos"] as Vector3).distance_to(pos)
		if d < best_d:
			best_d = d
			best = tr
	return best


func _centroid(robots: Array, team: int) -> Vector3:
	var c := Vector3.ZERO
	var n := 0
	for a in robots:
		if int(a["team"]) != team or not bool(a.get("alive", true)):
			continue
		c += a["body"].global_position
		n += 1
	if n == 0:
		return Vector3.ZERO
	return c / float(n)


func _center_push(my: Vector3, _team: int) -> Vector3:
	var to := Vector3.ZERO - my
	to.y = 0.0
	if to.length_squared() < 1.0:
		return Vector3(clampf(my.x, -3.0, 3.0), 0.0, clampf(my.z, -3.0, 3.0))
	return my + to.normalized() * minf(to.length(), 3.0)


func _slot(robot: Dictionary, my: Vector3, goal: Vector3) -> Vector3:
	var role := int(robot.get("id", 0)) % 3
	var to := goal - my
	to.y = 0.0
	var fwd := Vector3(0, 0, -1 if int(robot["team"]) == 0 else 1)
	if to.length_squared() > 1e-4:
		fwd = to.normalized()
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var side := 1.0 if (int(robot.get("id", 0)) % 2) == 0 else -1.0
	if role == 0:
		return goal - fwd * 0.9
	if role == 1:
		return goal - fwd * 1.3 + right * side * 1.5
	return goal + right * side * 2.6


func _nearest_enemy_dist(pos: Vector3, robots: Array, team: int) -> float:
	var best := 1.0e9
	for e in robots:
		if int(e["team"]) == team or not bool(e.get("alive", true)):
			continue
		best = minf(best, pos.distance_to(e["body"].global_position))
	return best


func _nearest_enemy_dir(origin: Vector3, robots: Array, team: int) -> Vector3:
	var best := Vector3.ZERO
	var best_d := 1.0e9
	for e in robots:
		if int(e["team"]) == team or not bool(e.get("alive", true)):
			continue
		var p: Vector3 = e["body"].global_position
		var d: float = origin.distance_to(p)
		if d < best_d:
			best_d = d
			best = p - origin
			best.y = 0.0
	return best


func _covered_enemies(team: int, robots: Array, sim_time: float) -> int:
	var tracks: Array = _fresh(team_tracks.get(team, []), sim_time)
	if tracks.is_empty():
		return 0
	var n := 0
	for e in robots:
		if int(e["team"]) == team or not bool(e.get("alive", true)):
			continue
		var ep: Vector3 = e["body"].global_position
		for tr in tracks:
			if (tr["pos"] as Vector3).distance_to(ep) <= r_gate:
				n += 1
				break
	return n


func _maybe_sample(robots: Array, sim_time: float) -> void:
	if samples.size() >= sample_cap:
		return
	for team in [0, 1]:
		if samples.size() >= sample_cap:
			return
		var obs: Array = []
		for tr in _fresh(team_tracks.get(team, []), sim_time):
			obs.append({
				"x": snappedf(tr["pos"].x, 0.01),
				"y": snappedf(tr["pos"].y, 0.01),
				"z": snappedf(tr["pos"].z, 0.01),
				"c": snappedf(float(tr["conf"]), 0.01),
				"age": snappedf(maxf(0.0, sim_time - float(tr["t"])), 0.01),
			})
		if obs.is_empty():
			continue
		var enemies: Array = []
		for e in robots:
			if int(e["team"]) == team or not bool(e.get("alive", true)):
				continue
			var p: Vector3 = e["body"].global_position
			enemies.append({"x": snappedf(p.x, 0.01), "y": snappedf(p.y, 0.01), "z": snappedf(p.z, 0.01)})
		samples.append({"t": snappedf(sim_time, 0.1), "team": team, "obs": obs, "enemies": enemies})


func _push_cap(arr: Array, value: float, cap: int) -> void:
	if arr.size() < cap:
		arr.append(value)
		return
	var idx := rng.randi_range(0, cap - 1)
	if rng.randf() < float(cap) / float(cap + pos_err_n + 1):
		arr[idx] = value


func _pct(arr: Array, p: float) -> float:
	if arr.is_empty():
		return 0.0
	var s: Array = arr.duplicate()
	s.sort()
	var idx := clampi(int(round(float(s.size() - 1) * p)), 0, s.size() - 1)
	return float(s[idx])



func _note_raw(robot: Dictionary, world: Vector3, conf: float, sim_time: float, robots: Array) -> void:
	# Raw line stores position, confidence, timestamp and observer id.
	# Enemy ids are appended only to eval_lines and are never written onto tracks.
	if raw_dir == "":
		return
	var team := int(robot["team"])
	var rid := int(robot["id"])
	var friends: String = ""
	var enemies: String = ""
	var friend_first := true
	var enemy_first := true
	for other in robots:
		if not (other is Dictionary):
			continue
		if not other.has("body"):
			continue
		if not bool(other.get("alive", true)):
			continue
		var oid := int(other["id"])
		var oteam := int(other["team"])
		var p: Vector3 = other["body"].global_position
		if oteam == team:
			if not friend_first:
				friends += ","
			friend_first = false
			friends += '{"id":%d,"x":%.3f,"y":%.3f,"z":%.3f}' % [oid, p.x, p.y, p.z]
		else:
			if not enemy_first:
				enemies += ","
			enemy_first = false
			enemies += '{"id":%d,"x":%.3f,"y":%.3f,"z":%.3f}' % [oid, p.x, p.y, p.z]
	raw_lines.append('{"t":%.3f,"team":%d,"obs":%d,"x":%.3f,"y":%.3f,"z":%.3f,"c":%.3f,"friends":[%s]}' % [sim_time, team, rid, world.x, world.y, world.z, conf, friends])
	eval_lines.append('{"t":%.3f,"team":%d,"obs":%d,"enemies":[%s]}' % [sim_time, team, rid, enemies])


func _flush_raw() -> void:
	if raw_flushed or raw_dir == "":
		return
	raw_flushed = true
	var run_id := OS.get_environment("SIM_RUN_ID").strip_edges()
	if run_id == "":
		run_id = "match"
	DirAccess.make_dir_recursive_absolute(raw_dir)
	var raw_path := raw_dir.path_join("%s.raw.jsonl" % run_id)
	var eval_path := raw_dir.path_join("%s.eval.jsonl" % run_id)
	var rf := FileAccess.open(raw_path, FileAccess.WRITE)
	if rf:
		for line in raw_lines:
			rf.store_line(str(line))
		rf.close()
	var ef := FileAccess.open(eval_path, FileAccess.WRITE)
	if ef:
		for line in eval_lines:
			ef.store_line(str(line))
		ef.close()
	print("RAW_CANDIDATES ", raw_lines.size(), " ", raw_path)

func _flag(name: String) -> bool:
	var v := OS.get_environment(name).strip_edges().to_lower()
	return v == "1" or v == "true" or v == "yes" or v == "on"


func _f(name: String, default_value: float) -> float:
	var v := OS.get_environment(name).strip_edges()
	if v == "":
		return default_value
	return float(v)


func _or_env(name: String, fallback: String) -> String:
	var v := OS.get_environment(name).strip_edges()
	if v == "":
		return fallback
	return v


func _gate_env(name: String, fallback: bool) -> bool:
	var v := OS.get_environment(name).strip_edges()
	if v == "":
		return fallback
	return v != "0" and v != "false" and v != "off"
