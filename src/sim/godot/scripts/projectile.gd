class_name SimProjectile
extends Node3D

signal resolved(hit: bool, victim_id: int)

const ArmorHitFxScript := preload("res://scripts/armor_hit_fx.gd")

var velocity := Vector3.ZERO
var age := 0.0
var max_age := 5.0  # ~10 m/s needs longer life to cross arena
var gravity := 0.0
var owner_team := -1
var owner_robot_id := -1
const RAY_SUBSTEPS := 8
## Armor plate hit only (meters). No hull proximity scoring.
const ARMOR_HIT_RADIUS := 0.38


func _ready() -> void:
	add_to_group("sim_projectile")
	# Compact bright tracer — readable at ~10 m/s.
	var tracer := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.04
	mesh.height = 0.22
	tracer.mesh = mesh
	tracer.rotation_degrees = Vector3(90, 0, 0)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.92, 0.25)
	material.emission_enabled = true
	material.emission = Color(1.0, 0.65, 0.08)
	material.emission_energy_multiplier = 5.5
	tracer.material_override = material
	add_child(tracer)
	var core := MeshInstance3D.new()
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 0.055
	core_mesh.height = 0.11
	core.mesh = core_mesh
	var cm := StandardMaterial3D.new()
	cm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cm.albedo_color = Color(1.0, 1.0, 0.75)
	cm.emission_enabled = true
	cm.emission = Color(1.0, 0.9, 0.35)
	cm.emission_energy_multiplier = 7.0
	core.material_override = cm
	add_child(core)


func setup(origin: Vector3, direction: Vector3, speed: float) -> void:
	global_position = origin
	var d := direction
	if d.length_squared() < 1e-8:
		d = Vector3(0, 0, -1)
	velocity = d.normalized() * speed


func setup_team(origin: Vector3, direction: Vector3, speed: float, team: int, robot_id: int) -> void:
	setup(origin, direction, speed)
	owner_team = team
	owner_robot_id = robot_id


func _score_hit(hit_pos: Vector3, victim_id: int = -1) -> void:
	_spawn_armor_hit_fx(hit_pos)
	resolved.emit(true, victim_id)
	queue_free()


func _miss() -> void:
	resolved.emit(false, -1)
	queue_free()


func _is_enemy_armor(col: Object) -> bool:
	if col == null or not col.is_in_group("armor"):
		return false
	if col.has_meta("dead") and bool(col.get_meta("dead")):
		return false  # wreck armor out of combat
	if col.has_meta("alive") and not bool(col.get_meta("alive")):
		return false
	var armor_team := int(col.get_meta("team", -1)) if col.has_meta("team") else -1
	var armor_owner := int(col.get_meta("robot_id", -1)) if col.has_meta("robot_id") else -1
	if armor_team < 0 or armor_team == owner_team:
		return false  # never score friendly
	if armor_owner == owner_robot_id:
		return false
	return true


func _is_obstacle(col: Object) -> bool:
	if col == null:
		return false
	if col.is_in_group("obstacle"):
		return true
	if col is CollisionObject3D and (col as Node).has_meta("is_obstacle"):
		return bool((col as Node).get_meta("is_obstacle"))
	return false


func _check_armor_proximity(pos: Vector3) -> bool:
	## Only the 4 armor plates count (not hull).
	for node in get_tree().get_nodes_in_group("armor"):
		if not (node is Node3D):
			continue
		if not _is_enemy_armor(node):
			continue
		var n3 := node as Node3D
		if n3.global_position.distance_to(pos) <= ARMOR_HIT_RADIUS:
			var vid2 := -1
			if n3.has_meta("robot_id"):
				vid2 = int(n3.get_meta("robot_id"))
			elif n3.get_child_count() > 0:
				for c in n3.get_children():
					if c is Node and c.has_meta("robot_id"):
						vid2 = int(c.get_meta("robot_id"))
						break
			_score_hit(pos, vid2)
			return true
	return false


func _spawn_armor_hit_fx(pos: Vector3) -> void:
	## 火光四射: color by shooter team (red=orange, blue=pale blue).
	var root := get_tree().current_scene
	if root == null:
		root = get_parent()
	if root == null:
		return
	var fx := Node3D.new()
	fx.set_script(ArmorHitFxScript)
	root.add_child(fx)
	if fx.has_method("setup_at"):
		fx.setup_at(pos, owner_team)
	else:
		fx.global_position = pos


func _physics_process(delta: float) -> void:
	if gravity != 0.0:
		velocity.y -= gravity * delta
	if velocity.length_squared() > 1e-6:
		var look := global_position + velocity.normalized()
		look_at(look, Vector3.UP)
	var remaining := velocity * delta
	var pos := global_position
	var space := get_world_3d().direct_space_state
	for _i in range(RAY_SUBSTEPS):
		var step := remaining / float(RAY_SUBSTEPS)
		var finish := pos + step
		var query := PhysicsRayQueryParameters3D.create(pos, finish)
		query.collide_with_areas = true
		query.collide_with_bodies = true
		query.collision_mask = 0xFFFFFFFF
		var collision := space.intersect_ray(query)
		if not collision.is_empty():
			var col: Object = collision.get("collider")
			# 1) Enemy armor plate only => score + fire FX
			if _is_enemy_armor(col):
				var hp: Vector3 = collision.get("position", finish)
				global_position = hp
				var vid := -1
				if col is Node and (col as Node).has_meta("robot_id"):
					vid = int((col as Node).get_meta("robot_id"))
				_score_hit(hp, vid)
				return
			# 2) Obstacle / wall
			if _is_obstacle(col):
				global_position = collision.get("position", finish)
				_miss()
				return
			# 3) Floor
			if col is StaticBody3D and not _is_obstacle(col):
				var hit_pos: Vector3 = collision.get("position", finish)
				if hit_pos.y < 0.12:
					global_position = hit_pos
					_miss()
					return
			# Hull CharacterBody3D ignored
		if _check_armor_proximity(finish):
			return
		pos = finish
	global_position = pos
	age += delta
	if age >= max_age or global_position.length() > 60.0:
		_miss()
