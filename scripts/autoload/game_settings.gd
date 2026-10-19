extends Node
## 端末ごとの設定（Autoload: GameSettings）。画質プリセット・タッチ操作・性能表示を管理し、
## user://settings.cfg に保存する。プラットフォームの判定はこのファイルに集約する。

signal changed

enum Quality { LOW, MEDIUM, HIGH }

const PATH := "user://settings.cfg"
const QUALITY_NAMES := ["低", "中", "高"]
## 3D描画の解像度倍率（低いほど軽い。UIは常にフル解像度）
const RENDER_SCALE := [0.6, 0.8, 1.0]
const SHADOW_ATLAS := [1024, 2048, 4096]
const SHADOW_DISTANCE := [30.0, 50.0, 80.0]
const MAX_FPS := [30, 60, 0]
## 環境の粒子（舞う灰）の量
const PARTICLE_AMOUNT := [40, 110, 220]

var quality: Quality = Quality.HIGH
var touch_controls := false
var show_stats := false
var look_sensitivity := 1.0
## テストなどで保存を止める
var persist := true


func _ready() -> void:
	quality = Quality.MEDIUM if is_mobile() else Quality.HIGH
	touch_controls = is_mobile()
	_load()
	# PCでタッチUIを試す: godot --path . -- --touch
	if "--touch" in OS.get_cmdline_user_args():
		touch_controls = true
	if "--low" in OS.get_cmdline_user_args():
		quality = Quality.LOW
	_apply_input_mode()


## スマホ・タブレットか（アプリ版、またはスマホのブラウザで開いたWeb版）
func is_mobile() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("web_ios") or OS.has_feature("web_android")


func is_web() -> bool:
	return OS.has_feature("web")


func set_quality(q: int) -> void:
	quality = clampi(q, 0, 2) as Quality
	_save()
	changed.emit()


func set_touch_controls(on: bool) -> void:
	touch_controls = on
	_apply_input_mode()
	_save()
	changed.emit()


func set_show_stats(on: bool) -> void:
	show_stats = on
	_save()
	changed.emit()


## タッチ操作中はマウスのボタン割り当てを外す（タッチから生成される疑似マウスで誤爆しないため）。
## PCでタッチUIを試す時はマウスをタッチとして扱う。
func _apply_input_mode() -> void:
	InputSetup.set_mouse_buttons_enabled(not touch_controls)
	Input.emulate_touch_from_mouse = touch_controls and not is_mobile()


## 現在の画質をシーンに反映する。レベル生成後と設定変更時に Main から呼ばれる。
func apply_graphics(tree: SceneTree) -> void:
	var q := int(quality)
	var vp := tree.root
	vp.scaling_3d_scale = RENDER_SCALE[q]
	vp.msaa_3d = Viewport.MSAA_2X if quality == Quality.HIGH else Viewport.MSAA_DISABLED
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA if quality == Quality.MEDIUM \
		else Viewport.SCREEN_SPACE_AA_DISABLED
	vp.positional_shadow_atlas_size = SHADOW_ATLAS[q]
	RenderingServer.directional_shadow_atlas_set_size(SHADOW_ATLAS[q], true)
	Engine.max_fps = MAX_FPS[q]
	for node in tree.get_nodes_in_group("sun"):
		var sun := node as DirectionalLight3D
		sun.directional_shadow_max_distance = SHADOW_DISTANCE[q]
		# 「低」は月光の影を切る（影の描画は描画命令が倍近くになるため）
		sun.shadow_enabled = quality != Quality.LOW
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL if quality == Quality.LOW \
			else DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	# 点光源の影は重いので「高」だけ
	for node in tree.get_nodes_in_group("shadow_lights"):
		(node as Light3D).shadow_enabled = quality == Quality.HIGH
	for node in tree.get_nodes_in_group("world_env"):
		var env := (node as WorldEnvironment).environment
		env.glow_enabled = quality != Quality.LOW
	for node in tree.get_nodes_in_group("ambient_particles"):
		(node as CPUParticles3D).amount = PARTICLE_AMOUNT[q]


func _load() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	quality = cfg.get_value("graphics", "quality", quality)
	touch_controls = cfg.get_value("input", "touch_controls", touch_controls)
	show_stats = cfg.get_value("debug", "show_stats", show_stats)
	look_sensitivity = cfg.get_value("input", "look_sensitivity", look_sensitivity)


func _save() -> void:
	if not persist:
		return
	var cfg := ConfigFile.new()
	cfg.set_value("graphics", "quality", int(quality))
	cfg.set_value("input", "touch_controls", touch_controls)
	cfg.set_value("input", "look_sensitivity", look_sensitivity)
	cfg.set_value("debug", "show_stats", show_stats)
	cfg.save(PATH)
