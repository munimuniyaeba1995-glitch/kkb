class_name Checkpoint
extends Interactable
## チェックポイント「残り火の篝（かがり）」。
## 休息すると: HP・スタミナ全回復 / 回復薬の補充 / 復活地点の更新 / 敵の再配置。

signal rested(checkpoint: Checkpoint)

var checkpoint_name := "残り火の篝"
var flame: OmniLight3D


func _init(cp_name: String = "残り火の篝") -> void:
	checkpoint_name = cp_name


func _ready() -> void:
	super._ready()
	prompt = "休息する（%s）" % checkpoint_name
	radius = 2.2
	var base := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.45
	cyl.bottom_radius = 0.6
	cyl.height = 0.5
	base.mesh = cyl
	base.position.y = 0.25
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.25, 0.24, 0.23)
	base.material_override = stone
	add_child(base)
	var ember := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 0.28
	sph.height = 0.56
	ember.mesh = sph
	ember.position.y = 0.75
	var em := StandardMaterial3D.new()
	em.albedo_color = Color(1.0, 0.5, 0.15)
	em.emission_enabled = true
	em.emission = Color(1.0, 0.45, 0.1)
	em.emission_energy_multiplier = 5.0
	ember.material_override = em
	add_child(ember)
	flame = OmniLight3D.new()
	flame.light_color = Color(1.0, 0.55, 0.25)
	flame.light_energy = 2.5
	flame.omni_range = 9.0
	flame.position.y = 1.2
	flame.shadow_enabled = true
	add_child(flame)


func _process(_delta: float) -> void:
	flame.light_energy = 2.3 + sin(Time.get_ticks_msec() * 0.011) * 0.25 \
		+ sin(Time.get_ticks_msec() * 0.027) * 0.15


func interact(_player: Player) -> void:
	rested.emit(self)


## 復活時に立つ位置（篝火の手前）
func spawn_point() -> Vector3:
	return global_position + global_transform.basis.z * 1.6
