class_name AshDrop
extends Node3D
## 死亡時に落とした残灰。触れると回収できる。

const PICKUP_RADIUS := 1.4

var player: Player
var orb: MeshInstance3D


func _ready() -> void:
	orb = MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radial_segments = 16
	sph.rings = 8
	sph.radius = 0.25
	sph.height = 0.5
	orb.mesh = sph
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.9, 0.7)
	mat.emission_enabled = true
	mat.emission = Color(0.4, 1.0, 0.6)
	mat.emission_energy_multiplier = 4.0
	orb.material_override = mat
	orb.position.y = 0.6
	add_child(orb)
	var light := OmniLight3D.new()
	light.light_color = Color(0.4, 1.0, 0.6)
	light.light_energy = 1.5
	light.omni_range = 4.0
	light.position.y = 0.8
	add_child(light)


func _physics_process(_delta: float) -> void:
	orb.position.y = 0.6 + sin(Time.get_ticks_msec() * 0.004) * 0.12
	if player == null or player.is_dead or not GameState.has_dropped_ash:
		return
	if player.global_position.distance_to(global_position) < PICKUP_RADIUS:
		var amount := GameState.recover_dropped_ash()
		GameState.notify.emit("残灰 %d を取り戻した" % amount)
		queue_free()
