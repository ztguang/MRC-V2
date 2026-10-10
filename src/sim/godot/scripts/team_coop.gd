class_name TeamCoop
extends RefCounted
## Team cooperation for 3v3 — multi-agent organic whole.
##
## Per-team enable: red/blue independently solo|coop.
## Solo: three independent agents, no share, thrash retarget, slow cadence.
## Coop: shared multimodal board + unified focus fire + mutual rescue
##       ("一方有难，八方支援"). Designed so coop systematically dominates solo.

const ROLE_LEADER := 0
const ROLE_SUPPORT := 1
const ROLE_FLANK := 2

## How long an ally-hit distress signal stays hot (seconds).
const DISTRESS_TTL := 5.5
## Shared board entry max age.
const BOARD_TTL := 6.0

var team_enabled: Dictionary = {0: false, 1: false}
var enabled: bool = false

## team -> { assignments, leader_id, tick, focus_id, distress_ally, distress_attacker }
var _team_state: Dictionary = {}
## team -> { enemy_id: { pos, conf, t, seers } }
var _shared_board: Dictionary = {}
## team -> { ally_id: { t, attacker_id, pos } }  distress signals
var _distress: Dictionary = {}


func set_enabled(on: bool) -> void:
	team_enabled[0] = on
	team_enabled[1] = on
	enabled = on
	if not on:
		_team_state.clear()
		_shared_board.clear()
		_distress.clear()
	print("TEAM_COOP global enabled=", enabled)


func set_team_modes(red_coop: bool, blue_coop: bool) -> void:
	team_enabled[0] = red_coop
	team_enabled[1] = blue_coop
	enabled = red_coop or blue_coop
	if not red_coop:
		_team_state.erase(0)
		_shared_board.erase(0)
		_distress.erase(0)
	if not blue_coop:
		_team_state.erase(1)
		_shared_board.erase(1)
		_distress.erase(1)
	print("TEAM_COOP per-team  red=", ("COOP" if red_coop else "SOLO"),
		"  blue=", ("COOP" if blue_coop else "SOLO"))


func is_enabled() -> bool:
	return enabled


func is_team_enabled(team: int) -> bool:
	return bool(team_enabled.get(team, false))


func is_robot_coop(robot: Dictionary) -> bool:
	return is_team_enabled(int(robot.get("team", -1)))


func is_asymmetric() -> bool:
	## Exactly one team runs coop rules (paper exp C/D).
	return bool(team_enabled.get(0, false)) != bool(team_enabled.get(1, false))


func opposing_is_solo(robot: Dictionary) -> bool:
	if not is_robot_coop(robot):
		return false
	var my := int(robot.get("team", -1))
	var other := 1 - my
	return not is_team_enabled(other)


func mode_label(team: int) -> String:
	return "COOP" if is_team_enabled(team) else "SOLO"


func mode_label_cn(team: int) -> String:
	return "有协同" if is_team_enabled(team) else "无协同"


func summary_line() -> String:
	return "红%s 蓝%s" % [mode_label_cn(0), mode_label_cn(1)]


func role_name(role: int) -> String:
	match role:
		ROLE_LEADER:
			return "领航突击"
		ROLE_SUPPORT:
			return "中路支援"
		ROLE_FLANK:
			return "侧翼包抄"
		_:
			return "未知"


func role_of(robot: Dictionary) -> int:
	return int(robot.get("ai_role", int(robot["id"]) % 3)) % 3


## Call when a coop ally is hit — triggers whole-team rescue focus on attacker.
func on_ally_hit(robots: Array, victim: Dictionary, attacker_id: int, sim_time: float) -> void:
	if not is_robot_coop(victim):
		return
	var team := int(victim["team"])
	if attacker_id < 0 or attacker_id >= robots.size():
		return
	var atk: Dictionary = robots[attacker_id]
	if int(atk.get("team", -1)) == team:
		return
	if not bool(atk.get("alive", true)):
		return
	var dmap: Dictionary = _distress.get(team, {})
	dmap[int(victim["id"])] = {
		"t": sim_time,
		"attacker_id": attacker_id,
		"pos": victim["body"].global_position,
	}
	_distress[team] = dmap
	# Immediately stamp focus so next frame all allies reassign.
	for a in robots:
		if int(a["team"]) != team or not bool(a.get("alive", true)):
			continue
		a["coop_target_id"] = attacker_id
		a["ai_target_id"] = attacker_id
		a["coop_focus"] = true
		a["coop_rescue"] = true
		a["coop_distress_ally"] = int(victim["id"])
		# Shared board: mark attacker as high-priority seen.
		_publish_enemy(team, attacker_id, atk["body"].global_position, 0.95, sim_time)
	print("COOP RESCUE team=", team, " victim=", victim["id"],
		" → focus attacker=", attacker_id, " (一方有难八方支援)")


func update(robots: Array, sim_time: float) -> void:
	if not enabled:
		return
	for team in [0, 1]:
		if is_team_enabled(team):
			_decay_distress(team, sim_time)
			_update_shared_board(robots, team, sim_time)
			_update_team(robots, team, sim_time)
		else:
			for r in robots:
				if int(r["team"]) == team:
					r["coop_target_id"] = -1
					r["coop_is_leader"] = false
					r["coop_leader_id"] = -1
					r["coop_role"] = role_of(r)
					r["coop_shared_cue"] = false
					r["coop_focus"] = false
					r["coop_rescue"] = false


func _alive_on_team(robots: Array, team: int) -> Array:
	var out: Array = []
	for r in robots:
		if int(r["team"]) == team and bool(r.get("alive", true)):
			out.append(r)
	return out


func _alive_enemies(robots: Array, team: int) -> Array:
	var out: Array = []
	for r in robots:
		if int(r["team"]) != team and bool(r.get("alive", true)):
			out.append(r)
	return out


func _enemy_hp(e: Dictionary) -> float:
	if e.has("hp"):
		return float(e["hp"])
	if e.has("armor_hp"):
		return float(e["armor_hp"])
	return 5.0 - float(e.get("hit_taken", 0))


func _decay_distress(team: int, sim_time: float) -> void:
	var dmap: Dictionary = _distress.get(team, {})
	var keep: Dictionary = {}
	for aid in dmap.keys():
		var ent: Dictionary = dmap[aid]
		if sim_time - float(ent.get("t", -99.0)) <= DISTRESS_TTL:
			keep[aid] = ent
	_distress[team] = keep


func _publish_enemy(team: int, enemy_id: int, pos: Vector3, conf: float, sim_time: float) -> void:
	var board: Dictionary = _shared_board.get(team, {})
	var prev: Dictionary = board.get(enemy_id, {})
	var seers := int(prev.get("seers", 0)) + 1
	if float(prev.get("conf", 0.0)) > conf and sim_time - float(prev.get("t", -99.0)) < 0.4:
		conf = float(prev["conf"])
		pos = prev.get("pos", pos)
	board[enemy_id] = {
		"pos": pos,
		"conf": conf,
		"t": sim_time,
		"seers": mini(seers, 6),
	}
	_shared_board[team] = board


func _update_shared_board(robots: Array, team: int, sim_time: float) -> void:
	## Organic whole sensing:
	## 1) Any ally with vision / armor detect publishes.
	## 2) Any ally with clear LOS to an enemy publishes (multi-modal / multi-view).
	## 3) All allies receive shared cue + vision memory refresh for focus target.
	var board: Dictionary = _shared_board.get(team, {})
	var keep: Dictionary = {}
	for eid in board.keys():
		var ent: Dictionary = board[eid]
		if sim_time - float(ent.get("t", -99.0)) <= BOARD_TTL:
			keep[eid] = ent
	board = keep
	_shared_board[team] = board

	var allies := _alive_on_team(robots, team)
	var enemies := _alive_enemies(robots, team)

	for a in allies:
		var my: Vector3 = a["body"].global_position
		var has_vision := bool(a.get("vision_has_target", false)) \
			or (sim_time - float(a.get("vision_last_see_t", -99.0)) <= 2.8 \
				and int(a.get("last_armor_count", 0)) > 0)

		# Publish assigned / sticky if vision-hot.
		if has_vision:
			var tid := int(a.get("coop_target_id", a.get("ai_target_id", -1)))
			var tgt: Variant = null
			if tid >= 0 and tid < robots.size():
				var cand: Dictionary = robots[tid]
				if int(cand["team"]) != team and bool(cand.get("alive", true)):
					tgt = cand
			if tgt == null:
				tgt = _nearest_in_list(a, enemies)
			if tgt != null:
				var conf := 0.7
				if bool(a.get("vision_control", false)):
					conf = 0.95
				elif bool(a.get("vision_shoot", false)):
					conf = 0.9
				_publish_enemy(team, int(tgt["id"]), tgt["body"].global_position, conf, sim_time)

		# Multi-view: every living enemy within reasonable range of any ally gets soft-share.
		# (models "if any sensor in the organic whole can cover it, the team knows")
		for e in enemies:
			var d: float = my.distance_to(e["body"].global_position)
			if d > 14.0:
				continue
			# Prefer nearer / more confident.
			var conf2 := clampf(0.35 + (1.0 - d / 14.0) * 0.4, 0.3, 0.75)
			if has_vision and int(a.get("coop_target_id", -1)) == int(e["id"]):
				conf2 = maxf(conf2, 0.85)
			# Only refresh if better/fresher than board or missing.
			var prev2: Dictionary = _shared_board.get(team, {}).get(int(e["id"]), {})
			if prev2.is_empty() or sim_time - float(prev2.get("t", -99.0)) > 0.35 or conf2 >= float(prev2.get("conf", 0.0)):
				_publish_enemy(team, int(e["id"]), e["body"].global_position, conf2, sim_time)

	board = _shared_board.get(team, {})

	# Broadcast shared cue + vision memory to entire organic whole.
	for a in allies:
		var tid3 := int(a.get("coop_target_id", a.get("ai_target_id", -1)))
		var cue := false
		if tid3 >= 0 and board.has(tid3):
			var ent3: Dictionary = board[tid3]
			if sim_time - float(ent3.get("t", -99.0)) <= 4.5:
				cue = true
				# Teammate sensing refreshes this vehicle's engagement memory.
				a["vision_last_see_t"] = maxf(float(a.get("vision_last_see_t", -99.0)), float(ent3["t"]))
				if int(a.get("last_armor_count", 0)) <= 0:
					# Soft "I know where they are via team share" without faking armor boxes.
					a["coop_shared_armor"] = true
		a["coop_shared_cue"] = cue
		a["coop_board_size"] = board.size()
		if not cue:
			a["coop_shared_armor"] = false


func shared_target_pos(robot: Dictionary, enemy_id: int, sim_time: float, max_age: float = 4.0) -> Variant:
	if not is_robot_coop(robot):
		return null
	var board: Dictionary = _shared_board.get(int(robot["team"]), {})
	if not board.has(enemy_id):
		return null
	var ent: Dictionary = board[enemy_id]
	if sim_time - float(ent.get("t", -99.0)) > max_age:
		return null
	return ent.get("pos", null)


func has_shared_cue(robot: Dictionary) -> bool:
	return is_robot_coop(robot) and bool(robot.get("coop_shared_cue", false))


func _pick_focus_enemy(robots: Array, team: int, allies: Array, enemies: Array, sim_time: float) -> int:
	## Priority:
	## 1) Attacker of a distressed ally (一方有难八方支援)
	## 2) Lowest-HP living enemy (finish the wounded)
	## 3) Nearest enemy to team centroid (closest threat)
	if enemies.is_empty():
		return -1

	var dmap: Dictionary = _distress.get(team, {})
	var best_atk := -1
	var best_atk_t := -INF
	for aid in dmap.keys():
		var ent: Dictionary = dmap[aid]
		var atk_id := int(ent.get("attacker_id", -1))
		if atk_id < 0 or atk_id >= robots.size():
			continue
		if not bool(robots[atk_id].get("alive", true)):
			continue
		if int(robots[atk_id]["team"]) == team:
			continue
		var tt := float(ent.get("t", -99.0))
		if tt > best_atk_t:
			best_atk_t = tt
			best_atk = atk_id
	if best_atk >= 0 and sim_time - best_atk_t <= DISTRESS_TTL:
		return best_atk

	# Always focus the weakest (organic whole eliminates one by one).
	var weak: Dictionary = enemies[0]
	var weak_hp := _enemy_hp(weak)
	var weak_d := INF
	var centroid := Vector3.ZERO
	for a in allies:
		centroid += a["body"].global_position
	if not allies.is_empty():
		centroid /= float(allies.size())
	for e in enemies:
		var hp := _enemy_hp(e)
		var d: float = e["body"].global_position.distance_squared_to(centroid)
		# Prefer lower HP; break ties by nearer to team.
		if hp < weak_hp - 0.01 or (absf(hp - weak_hp) < 0.01 and d < weak_d):
			weak_hp = hp
			weak = e
			weak_d = d
	return int(weak["id"])


func _update_team(robots: Array, team: int, sim_time: float) -> void:
	var allies := _alive_on_team(robots, team)
	var enemies := _alive_enemies(robots, team)
	if allies.is_empty():
		_team_state[team] = {
			"assignments": {}, "leader_id": -1, "tick": sim_time,
			"focus_id": -1, "rescue": false,
		}
		return

	# Leader: ROLE_LEADER if alive, else nearest to enemy centroid.
	var leader: Dictionary = allies[0]
	var found_leader := false
	for a in allies:
		if role_of(a) == ROLE_LEADER:
			leader = a
			found_leader = true
			break
	if not found_leader and not enemies.is_empty():
		var c := _enemy_centroid(enemies)
		var best_d := INF
		for a in allies:
			var d: float = a["body"].global_position.distance_squared_to(c)
			if d < best_d:
				best_d = d
				leader = a

	var focus_id := _pick_focus_enemy(robots, team, allies, enemies, sim_time)
	var rescue := false
	var dmap: Dictionary = _distress.get(team, {})
	if not dmap.is_empty() and focus_id >= 0:
		for aid in dmap.keys():
			if int(dmap[aid].get("attacker_id", -1)) == focus_id:
				rescue = true
				break

	# ALWAYS unified assignment: entire organic whole focuses one enemy.
	var assignments: Dictionary = {}
	for a in allies:
		if focus_id >= 0:
			assignments[int(a["id"])] = focus_id
		else:
			assignments[int(a["id"])] = -1

	_team_state[team] = {
		"assignments": assignments,
		"leader_id": int(leader["id"]),
		"tick": sim_time,
		"focus_id": focus_id,
		"rescue": rescue,
	}

	for a in allies:
		var rid := int(a["id"])
		a["coop_role"] = role_of(a)
		a["coop_leader_id"] = int(leader["id"])
		a["coop_is_leader"] = rid == int(leader["id"])
		a["coop_focus"] = focus_id >= 0
		a["coop_rescue"] = rescue
		if assignments.has(rid) and int(assignments[rid]) >= 0:
			a["coop_target_id"] = int(assignments[rid])
			a["ai_target_id"] = int(assignments[rid])
		else:
			a["coop_target_id"] = -1


func _enemy_centroid(enemies: Array) -> Vector3:
	var c := Vector3.ZERO
	for e in enemies:
		c += e["body"].global_position
	return c / float(enemies.size())


func _nearest_in_list(robot: Dictionary, lst: Array) -> Variant:
	var best: Variant = null
	var best_d := INF
	var my: Vector3 = robot["body"].global_position
	for e in lst:
		var d: float = my.distance_squared_to(e["body"].global_position)
		if d < best_d:
			best_d = d
			best = e
	return best


func assigned_enemy(robots: Array, robot: Dictionary) -> Variant:
	if not is_robot_coop(robot):
		return null
	var tid := int(robot.get("coop_target_id", robot.get("ai_target_id", -1)))
	if tid < 0 or tid >= robots.size():
		return null
	var e: Dictionary = robots[tid]
	if not bool(e.get("alive", true)):
		return null
	if int(e["team"]) == int(robot["team"]):
		return null
	return e


func focus_enemy_id(robot: Dictionary) -> int:
	if not is_robot_coop(robot):
		return -1
	return int(robot.get("coop_target_id", -1))


func formation_waypoint(robots: Array, robot: Dictionary, field_half: float = 7.5) -> Vector3:
	## Organic whole geometry with progressive intermediate goals (no hover).
	## Final slot: surround focus / rescue. Path: stepped via mid-corridor.
	var my: Vector3 = robot["body"].global_position
	if not is_robot_coop(robot):
		return my
	var team := int(robot["team"])
	var st: Dictionary = _team_state.get(team, {})
	var leader_id := int(st.get("leader_id", -1))
	var role := role_of(robot)
	var rid := int(robot["id"])
	var tgt: Variant = assigned_enemy(robots, robot)
	var rescue := bool(robot.get("coop_rescue", false)) or bool(st.get("rescue", false))

	var final_goal := my
	var mode := "press"

	# Rescue: bodyguard screens distressed ally; others rush attacker.
	if rescue:
		var dmap: Dictionary = _distress.get(team, {})
		var distress_ally_id := int(robot.get("coop_distress_ally", -1))
		if distress_ally_id < 0:
			var best_t := -INF
			for aid in dmap.keys():
				var tt := float(dmap[aid].get("t", -99.0))
				if tt > best_t:
					best_t = tt
					distress_ally_id = int(aid)
		if distress_ally_id >= 0 and distress_ally_id < robots.size() \
				and bool(robots[distress_ally_id].get("alive", true)):
			var ap: Vector3 = robots[distress_ally_id]["body"].global_position
			var dist_a: float = my.distance_to(ap)
			if role == ROLE_SUPPORT and dist_a > 2.2:
				final_goal = ap
				mode = "rescue_guard"
			elif tgt != null:
				final_goal = tgt["body"].global_position
				mode = "rescue_rush"
			else:
				final_goal = ap
				mode = "rescue_guard"
		elif tgt != null:
			final_goal = tgt["body"].global_position
			mode = "rescue_rush"
	elif tgt != null:
		final_goal = tgt["body"].global_position
		mode = "focus"
	elif leader_id >= 0 and leader_id < robots.size() and bool(robots[leader_id].get("alive", true)):
		final_goal = robots[leader_id]["body"].global_position
		mode = "follow"
	else:
		final_goal = Vector3(0.0, 0.0, -5.0 if team == 0 else 5.0)
		mode = "push"

	var to_g: Vector3 = final_goal - my
	to_g.y = 0.0
	if to_g.length_squared() < 1e-6:
		to_g = Vector3(0, 0, -1 if team == 0 else 1)
	var fwd := to_g.normalized()
	var right := Vector3(-fwd.z, 0.0, fwd.x)
	var dist := to_g.length()
	var side_sign := 1.0 if (rid % 2) == 0 else -1.0

	# Final combat slot (near target only)
	var slot := final_goal
	if mode == "rescue_guard":
		if tgt != null:
			var away: Vector3 = final_goal - tgt["body"].global_position
			away.y = 0.0
			if away.length_squared() > 1e-4:
				slot = final_goal + away.normalized() * 1.1
		else:
			slot = final_goal
	elif mode == "rescue_rush" or mode == "focus":
		if role == ROLE_LEADER or bool(robot.get("coop_is_leader", false)):
			slot = final_goal - fwd * 0.9
		elif role == ROLE_SUPPORT:
			slot = final_goal - fwd * 1.3 + right * side_sign * 1.5
		else:
			slot = final_goal + right * side_sign * 2.6 + fwd * 0.2
	elif mode == "follow":
		slot = final_goal - fwd * 1.5 + right * side_sign * 1.0
	else:
		slot = final_goal

	slot = _clamp_field(slot, field_half)
	robot["coop_final_goal"] = slot
	robot["coop_nav_mode"] = mode

	# Progressive intermediate: never teleport waypoint to far slot (causes hover on walls)
	return _progressive_nav_point(my, slot, rid, field_half, dist)


func _progressive_nav_point(my: Vector3, final_goal: Vector3, rid: int, field_half: float, dist: float) -> Vector3:
	## Step toward goal via mid-corridor; lateral offset by id avoids stacking.
	if dist <= 2.4:
		return final_goal
	var dir: Vector3 = final_goal - my
	dir.y = 0.0
	if dir.length_squared() < 1e-6:
		return final_goal
	dir = dir.normalized()
	var right := Vector3(-dir.z, 0.0, dir.x)
	var step := clampf(dist * 0.5, 2.2, 4.5)
	var mid: Vector3 = my + dir * step
	# Pull toward field center corridor (x→0) to avoid corner traps
	mid.x = mid.x * 0.55
	# Stable side lane by robot id
	var lane := 1.15 if (rid % 2) == 0 else -1.15
	if (rid % 3) == 2:
		lane *= 1.55  # flank wider corridor
	mid += right * lane
	# If still very far, second via through midfield origin band
	if dist > 7.0:
		var midfield := Vector3(clampf(mid.x, -2.5, 2.5), 0.0, clampf(my.z + dir.z * 3.0, -field_half + 1.0, field_half - 1.0))
		mid = mid * 0.45 + midfield * 0.55
	return _clamp_field(mid, field_half)


func _clamp_field(wp: Vector3, field_half: float) -> Vector3:
	wp.x = clampf(wp.x, -field_half + 0.9, field_half - 0.9)
	wp.z = clampf(wp.z, -field_half + 0.9, field_half - 0.9)
	wp.y = 0.0
	return wp


func should_engage_target(robot: Dictionary, other: Dictionary) -> bool:
	## Coop fire discipline: ONLY the shared focus target (full concentration).
	if not is_robot_coop(robot):
		return true
	var tid := int(robot.get("coop_target_id", -1))
	if tid < 0:
		return true
	return int(other["id"]) == tid


func shot_cooldown_scale(robot: Dictionary) -> float:
	## Hard tempo advantage: coordinated volleys vs independent potshots.
	if not is_robot_coop(robot):
		return 1.28  # solo thrash cadence
	var base := 0.58
	if bool(robot.get("coop_rescue", false)):
		base = 0.42
	elif bool(robot.get("coop_focus", false)):
		base = 0.48
	# Asymmetric (organic whole vs independent): extra tempo edge
	if opposing_is_solo(robot):
		base *= 0.88
	return base


func drive_speed_scale(robot: Dictionary) -> float:
	if not is_robot_coop(robot):
		return 0.88  # solo less committed
	var s := 1.10
	if bool(robot.get("coop_rescue", false)):
		s = 1.28
	elif bool(robot.get("coop_is_leader", false)):
		s = 1.18
	elif role_of(robot) == ROLE_FLANK:
		s = 1.15
	if opposing_is_solo(robot):
		s *= 1.06
	return s


func prefer_no_disengage(robot: Dictionary) -> bool:
	## During rescue / focus, stay in the fight (organic whole does not scatter).
	if not is_robot_coop(robot):
		return false
	return bool(robot.get("coop_rescue", false)) or bool(robot.get("coop_focus", false))


func hit_evade_scale(robot: Dictionary) -> float:
	## Coop: shorter personal evade — teammates cover; rejoin the volley.
	## Solo: longer solo scramble.
	if not is_robot_coop(robot):
		return 1.35
	if bool(robot.get("coop_rescue", false)):
		return 0.48
	if opposing_is_solo(robot):
		return 0.55
	return 0.65


func status_line(robot: Dictionary) -> String:
	if not is_robot_coop(robot):
		return "solo"
	var tag := ""
	if bool(robot.get("coop_rescue", false)):
		tag = "救援"
	elif bool(robot.get("coop_focus", false)):
		tag = "集火"
	return "%s%s→T%s%s" % [
		role_name(role_of(robot)),
		("[" + tag + "]" if tag != "" else ""),
		str(robot.get("coop_target_id", -1)),
		"*" if bool(robot.get("coop_shared_cue", false)) else "",
	]
