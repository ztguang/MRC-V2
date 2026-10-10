extends Node3D
## 装甲板命中火光：红方炮弹=橙黄火光，蓝方炮弹=淡蓝火光

const TEAM_RED := 0
const TEAM_BLUE := 1

var _age := 0.0
var _life := 0.65
var _flash: MeshInstance3D
var _fire: MeshInstance3D
var _spark_meshes: Array = []
var _team := TEAM_RED
var _flash_energy := 14.0
var _fire_energy := 11.0
var _dying := false


func setup_at(world_pos: Vector3, shooter_team: int = TEAM_RED) -> void:
	add_to_group("armor_hit_fx")
	_team = shooter_team
	global_position = world_pos + Vector3(0.0, 0.05, 0.0)
	_build_visuals()


func _palette() -> Dictionary:
	## Colors driven by who fired the shell (owner team).
	if _team == TEAM_BLUE:
		return {
			"flash_albedo": Color(0.75, 0.92, 1.0, 1.0),
			"flash_emission": Color(0.45, 0.8, 1.0),
			"fire_albedo": Color(0.35, 0.7, 1.0, 0.72),
			"fire_emission": Color(0.2, 0.55, 1.0),
			"grad": PackedColorArray([
				Color(0.9, 0.98, 1.0, 1.0),
				Color(0.4, 0.75, 1.0, 1.0),
				Color(0.15, 0.35, 0.9, 0.0),
			]),
			"spark_hsv_h0": 0.52,
			"spark_hsv_h1": 0.62,
			"spark_emission_g": 0.65,
			"spark_emission_b": 1.0,
			"flash_energy": 13.0,
			"fire_energy": 10.0,
		}
	# Red team (default): keep current orange/yellow fire look
	return {
		"flash_albedo": Color(1.0, 0.9, 0.3, 1.0),
		"flash_emission": Color(1.0, 0.55, 0.05),
		"fire_albedo": Color(1.0, 0.35, 0.05, 0.75),
		"fire_emission": Color(1.0, 0.2, 0.0),
		"grad": PackedColorArray([
			Color(1.0, 1.0, 0.75, 1.0),
			Color(1.0, 0.5, 0.05, 1.0),
			Color(0.85, 0.08, 0.0, 0.0),
		]),
		"spark_hsv_h0": 0.0,
		"spark_hsv_h1": 0.1,
		"spark_emission_g": 0.4,
		"spark_emission_b": 0.0,
		"flash_energy": 14.0,
		"fire_energy": 11.0,
	}


func _build_visuals() -> void:
	var pal: Dictionary = _palette()
	_flash_energy = float(pal["flash_energy"])
	_fire_energy = float(pal["fire_energy"])

	_flash = MeshInstance3D.new()
	var flash_mesh := SphereMesh.new()
	flash_mesh.radius = 0.12
	flash_mesh.height = 0.24
	_flash.mesh = flash_mesh
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.albedo_color = pal["flash_albedo"]
	fm.emission_enabled = true
	fm.emission = pal["flash_emission"]
	fm.emission_energy_multiplier = _flash_energy
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_flash.material_override = fm
	add_child(_flash)

	_fire = MeshInstance3D.new()
	var fire_mesh := SphereMesh.new()
	fire_mesh.radius = 0.22
	fire_mesh.height = 0.44
	_fire.mesh = fire_mesh
	var fmat := StandardMaterial3D.new()
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.albedo_color = pal["fire_albedo"]
	fmat.emission_enabled = true
	fmat.emission = pal["fire_emission"]
	fmat.emission_energy_multiplier = _fire_energy
	fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_fire.material_override = fmat
	add_child(_fire)

	var sparks := CPUParticles3D.new()
	sparks.emitting = true
	sparks.one_shot = true
	sparks.explosiveness = 1.0
	sparks.amount = 56
	sparks.lifetime = 0.6
	sparks.randomness = 0.65
	sparks.spread = 180.0
	sparks.direction = Vector3(0, 1, 0)
	sparks.gravity = Vector3(0, -10.0, 0)
	sparks.initial_velocity_min = 3.8
	sparks.initial_velocity_max = 9.5
	sparks.scale_amount_min = 0.035
	sparks.scale_amount_max = 0.085
	var grad := Gradient.new()
	grad.colors = pal["grad"]
	grad.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	sparks.color_ramp = grad
	add_child(sparks)

	var h0: float = float(pal["spark_hsv_h0"])
	var h1: float = float(pal["spark_hsv_h1"])
	var is_blue := _team == TEAM_BLUE

	var rng := RandomNumberGenerator.new()
	rng.randomize()
	for _i in range(22):
		var spark := MeshInstance3D.new()
		var sm := SphereMesh.new()
		var r := rng.randf_range(0.018, 0.042)
		sm.radius = r
		sm.height = r * 2.0
		spark.mesh = sm
		var smat := StandardMaterial3D.new()
		smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		smat.albedo_color = Color.from_hsv(rng.randf_range(h0, h1), 0.55 if is_blue else 0.95, 1.0)
		smat.emission_enabled = true
		if is_blue:
			# Pale / light blue sparks
			smat.emission = Color(
				rng.randf_range(0.35, 0.75),
				rng.randf_range(0.7, 0.95),
				1.0
			)
		else:
			smat.emission = Color(1.0, rng.randf_range(0.15, 0.65), 0.0)
		smat.emission_energy_multiplier = rng.randf_range(7.0, 14.0)
		spark.material_override = smat
		add_child(spark)
		var dir := Vector3(
			rng.randf_range(-1.0, 1.0),
			rng.randf_range(0.15, 1.0),
			rng.randf_range(-1.0, 1.0)
		).normalized()
		_spark_meshes.append({
			"node": spark,
			"vel": dir * rng.randf_range(3.0, 8.0),
			"life": rng.randf_range(0.28, 0.6),
		})


func _process(delta: float) -> void:
	if _dying or not is_inside_tree():
		return
	_age += delta
	var u := clampf(_age / _life, 0.0, 1.0)

	# Use untyped refs first — typed assignment from a freed Object errors in Godot 4.
	if _flash != null and is_instance_valid(_flash):
		var s := 1.0 + u * 2.0
		_flash.scale = Vector3(s, s, s)
		var mat := _flash.material_override as StandardMaterial3D
		if mat:
			mat.albedo_color.a = 1.0 - u
			mat.emission_energy_multiplier = _flash_energy * (1.0 - u)

	if _fire != null and is_instance_valid(_fire):
		var s2 := 1.0 + u * 2.6
		_fire.scale = Vector3(s2, s2, s2)
		var mat2 := _fire.material_override as StandardMaterial3D
		if mat2:
			mat2.albedo_color.a = 0.75 * (1.0 - u)
			mat2.emission_energy_multiplier = _fire_energy * (1.0 - u)

	var alive_sparks: Array = []
	for item in _spark_meshes:
		if typeof(item) != TYPE_DICTIONARY:
			continue
		var raw = item.get("node", null)
		# Never assign a potentially freed Object into a typed MeshInstance3D var.
		if raw == null or not is_instance_valid(raw):
			continue
		var n := raw as MeshInstance3D
		if n == null:
			continue
		var v: Vector3 = item.get("vel", Vector3.ZERO)
		v.y -= 14.0 * delta
		item["vel"] = v
		n.global_position += v * delta
		var lf: float = float(item.get("life", 0.0)) - delta
		item["life"] = lf
		var sc := maxf(0.04, lf * 1.8)
		n.scale = Vector3(sc, sc, sc)
		if lf <= 0.0:
			item["node"] = null
			n.queue_free()
			continue
		alive_sparks.append(item)
	_spark_meshes = alive_sparks

	if _age >= _life:
		_dying = true
		_spark_meshes.clear()
		_flash = null
		_fire = null
		queue_free()
