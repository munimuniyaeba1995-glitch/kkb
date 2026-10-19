class_name CameraRig
extends Node3D
## 三人称カメラ。プレイヤーを追従し、マウス/右スティックで回転。
## ロックオン中は対象の方向へ自動で向く。SpringArm3Dで壁へのめり込みを防ぐ。

const HEIGHT := 1.55
const DISTANCE := 4.3
const PITCH_MIN := -1.2
const PITCH_MAX := 0.6

var target: Node3D
var lock_target: Node3D
var yaw := 0.0
var pitch := -0.25
var mouse_sensitivity := 0.0025
var stick_sensitivity := 2.6
var camera: Camera3D
var spring: SpringArm3D
var _shake := 0.0


func _ready() -> void:
	top_level = true
	spring = SpringArm3D.new()
	spring.spring_length = DISTANCE
	spring.collision_mask = Actor.LAYER_WORLD
	spring.margin = 0.2
	var probe := SphereShape3D.new()
	probe.radius = 0.25
	spring.shape = probe
	add_child(spring)
	camera = Camera3D.new()
	camera.fov = 70.0
	camera.far = 140.0
	spring.add_child(camera)
	camera.current = true
	add_child(FX.ambient_ash(GameSettings.PARTICLE_AMOUNT[GameSettings.quality]))


## タッチのカメラ操作など、マウス以外からの回転入力（ラジアン）
func add_look(delta: Vector2) -> void:
	if lock_target == null:
		yaw -= delta.x
	pitch = clampf(pitch - delta.y, PITCH_MIN, PITCH_MAX)


## 画面を揺らす（被弾・重い攻撃）。amount はおおよその揺れ幅（m）
func shake(amount: float) -> void:
	_shake = maxf(_shake, amount)


func snap_to_target() -> void:
	if target:
		global_position = target.global_position + Vector3.UP * HEIGHT
		rotation = Vector3(pitch, yaw, 0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := event as InputEventMouseMotion
		if lock_target == null:
			yaw -= motion.relative.x * mouse_sensitivity
		pitch = clampf(pitch - motion.relative.y * mouse_sensitivity, PITCH_MIN, PITCH_MAX)


func _process(delta: float) -> void:
	if target == null:
		return
	var follow := target.global_position + Vector3.UP * HEIGHT
	global_position = global_position.lerp(follow, 1.0 - exp(-14.0 * delta))

	var stick := Input.get_vector("cam_left", "cam_right", "cam_up", "cam_down")
	if lock_target and is_instance_valid(lock_target):
		var to_target := lock_target.global_position - target.global_position
		var flat := Vector2(to_target.x, to_target.z)
		if flat.length() > 0.3:
			var desired_yaw := atan2(-to_target.x, -to_target.z)
			yaw = lerp_angle(yaw, desired_yaw, 1.0 - exp(-9.0 * delta))
			# 大きな敵ほど少し見上げる
			var desired_pitch := clampf(-0.22 - 0.6 / maxf(flat.length(), 1.0), PITCH_MIN, PITCH_MAX)
			pitch = lerpf(pitch, desired_pitch, 1.0 - exp(-4.0 * delta))
	else:
		yaw -= stick.x * stick_sensitivity * delta
		pitch = clampf(pitch - stick.y * stick_sensitivity * delta, PITCH_MIN, PITCH_MAX)
	rotation = Vector3(pitch, yaw, 0)
	if _shake > 0.001:
		camera.h_offset = randf_range(-_shake, _shake)
		camera.v_offset = randf_range(-_shake, _shake)
		_shake = move_toward(_shake, 0.0, delta * 0.8)
	else:
		camera.h_offset = 0.0
		camera.v_offset = 0.0


## カメラ基準の前方向・右方向（水平）
func flat_forward() -> Vector3:
	return Vector3(-sin(yaw), 0, -cos(yaw))


func flat_right() -> Vector3:
	return Vector3(cos(yaw), 0, -sin(yaw))
