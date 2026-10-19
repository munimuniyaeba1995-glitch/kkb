class_name TouchControls
extends Control
## スマートフォン用のタッチ操作。
##   左半分: 触れた場所に出る仮想スティック（移動）
##   右半分: ドラッグでカメラ回転
##   右下:   攻撃・強攻撃・回避（長押しでダッシュ）・ガード・ジャンプ・ロックオン・回復・調べる
## ボタンは InputMap のアクションをそのまま押すので、ゲーム本体はPCと同じコードで動く。
## マルチタッチ対応: 指（index）ごとにどの操作を担当しているかを記録する。

signal look(relative: Vector2)

## ボタン画像を描くための部品。描いた結果は画像として使い回す（毎フレーム描かない）
class ButtonPainter extends Control:
	var controls: TouchControls

	func _draw() -> void:
		controls.draw_buttons(self)

## 720p基準のボタン配置（右下隅からの距離, 半径, ラベル）。画面サイズに合わせて拡大縮小する
const LAYOUT := {
	"attack_light": {"offset": Vector2(150, 150), "r": 74.0, "label": "攻撃", "icon": "sword"},
	"attack_heavy": {"offset": Vector2(305, 100), "r": 50.0, "label": "強攻撃", "icon": "heavy"},
	"dodge": {"offset": Vector2(135, 320), "r": 56.0, "label": "回避", "icon": "dodge"},
	"guard": {"offset": Vector2(290, 245), "r": 50.0, "label": "ガード", "icon": "shield"},
	"jump": {"offset": Vector2(435, 85), "r": 40.0, "label": "跳躍", "icon": "jump"},
	"lock_on": {"offset": Vector2(105, 465), "r": 42.0, "label": "ロック", "icon": "lock"},
	"use_item": {"offset": Vector2(440, 210), "r": 42.0, "label": "回復", "icon": "flask"},
	"interact": {"offset": Vector2(430, 355), "r": 48.0, "label": "調べる", "icon": "interact"},
}
const PAUSE_OFFSET := Vector2(60, 60)
const STICK_RADIUS := 100.0
const LOOK_SENSITIVITY := 0.006
const BASE_HEIGHT := 720.0

var ui_scale := 1.0
var safe_margin := Vector2.ZERO
var centers: Dictionary = {}
var radii: Dictionary = {}
var pressed_by: Dictionary = {}   # action -> touch index
var stick_index := -1
var stick_origin := Vector2.ZERO
var stick_pos := Vector2.ZERO
var look_index := -1
var interact_available := false
## ボタンは SubViewport に一度だけ描いて画像として表示する（Godot 4.3 のモバイル描画は
## 2D図形をまとめて描けず、ボタンだけで描画命令が100回以上になるため）
var _cache_vp: SubViewport
var _painter: ButtonPainter
var _cache_rect: TextureRect


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cache_vp = SubViewport.new()
	_cache_vp.transparent_bg = true
	_cache_vp.disable_3d = true
	_cache_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_cache_vp)
	_painter = ButtonPainter.new()
	_painter.controls = self
	_cache_vp.add_child(_painter)
	_cache_rect = TextureRect.new()
	_cache_rect.texture = _cache_vp.get_texture()
	_cache_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cache_rect.stretch_mode = TextureRect.STRETCH_SCALE
	# 画像の画素数が画面より大きくても枠を広げない（高解像度の端末でボタンが画面外にずれるのを防ぐ）
	_cache_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_cache_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cache_rect)
	get_viewport().size_changed.connect(_layout)
	_layout()


## 画面サイズとノッチ（セーフエリア）に合わせてボタン位置を計算する
func _layout() -> void:
	var vp := get_viewport_rect().size
	ui_scale = clampf(vp.y / BASE_HEIGHT, 0.75, 2.0)
	safe_margin = Vector2.ZERO
	if GameSettings.is_mobile():
		var safe := DisplayServer.get_display_safe_area()
		var screen := DisplayServer.screen_get_size()
		if screen.x > 0 and safe.size.x > 0:
			var k := vp.x / float(screen.x)
			safe_margin.x = maxf(screen.x - safe.end.x, safe.position.x) * k
	for action: String in LAYOUT:
		var def: Dictionary = LAYOUT[action]
		var off: Vector2 = def["offset"]
		centers[action] = vp - (off * ui_scale) - Vector2(safe_margin.x, 0)
		radii[action] = float(def["r"]) * ui_scale
	centers["pause"] = Vector2(vp.x - PAUSE_OFFSET.x * ui_scale - safe_margin.x, PAUSE_OFFSET.y * ui_scale)
	radii["pause"] = 34.0 * ui_scale
	# 画像の解像度は実際の画面の画素数に合わせる（拡大でぼやけないように）
	var px := maxf(1.0, get_viewport().get_final_transform().get_scale().x)
	_cache_vp.size = Vector2i(ceili(vp.x * px), ceili(vp.y * px))
	_painter.scale = Vector2(px, px)
	_painter.size = vp
	_refresh_buttons()
	queue_redraw()


## ボタンの見た目が変わった時だけ画像を描き直す
func _refresh_buttons() -> void:
	if _painter:
		_painter.queue_redraw()
		_cache_vp.render_target_update_mode = SubViewport.UPDATE_ONCE


func button_center(action: String) -> Vector2:
	return centers[action]


func set_interact_available(on: bool) -> void:
	if interact_available != on:
		interact_available = on
		_refresh_buttons()


func _button_at(pos: Vector2) -> String:
	for action: String in centers:
		if action == "interact" and not interact_available:
			continue
		# 見た目より少し大きく反応させる（押し損じ対策）
		if pos.distance_to(centers[action]) <= float(radii[action]) * 1.15:
			return action
	return ""


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		if t.pressed:
			_on_touch_down(t.index, t.position)
		else:
			_on_touch_up(t.index)
	elif event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		if d.index == stick_index:
			stick_pos = d.position
			_update_stick()
		elif d.index == look_index:
			look.emit(d.relative * LOOK_SENSITIVITY * GameSettings.look_sensitivity)


func _on_touch_down(index: int, pos: Vector2) -> void:
	var action := _button_at(pos)
	if action != "":
		if action == "pause" or not get_tree().paused:
			pressed_by[action] = index
			_send_action(action, true)
			_refresh_buttons()
		return
	if get_tree().paused:
		return
	if pos.x < get_viewport_rect().size.x * 0.45:
		if stick_index == -1:
			stick_index = index
			stick_origin = pos
			stick_pos = pos
			_update_stick()
	elif look_index == -1:
		look_index = index


func _on_touch_up(index: int) -> void:
	for action: String in pressed_by.keys():
		if pressed_by[action] == index:
			pressed_by.erase(action)
			_send_action(action, false)
	if index == stick_index:
		stick_index = -1
		_set_move(Vector2.ZERO)
	if index == look_index:
		look_index = -1
	_refresh_buttons()
	queue_redraw()


## すべての指を離した扱いにする（ポーズ時・画面を消した時）
func release_all() -> void:
	for action: String in pressed_by.keys():
		_send_action(action, false)
	pressed_by.clear()
	stick_index = -1
	look_index = -1
	_set_move(Vector2.ZERO)
	_refresh_buttons()
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		release_all()


func _send_action(action: String, pressed: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	ev.strength = 1.0 if pressed else 0.0
	Input.parse_input_event(ev)


func _update_stick() -> void:
	var r := STICK_RADIUS * ui_scale
	var v := (stick_pos - stick_origin) / r
	if v.length() > 1.0:
		# 指が大きく離れたらスティックの中心を追従させる
		stick_origin = stick_pos - v.normalized() * r
		v = v.normalized()
	_set_move(v)
	queue_redraw()


func _set_move(v: Vector2) -> void:
	InputSetup.virtual_move = v


## ボタン一式を描く（ButtonPainter から呼ばれる）
func draw_buttons(ci: CanvasItem) -> void:
	var fs := int(14 * ui_scale)
	for action: String in centers:
		if action == "interact" and not interact_available:
			continue
		var c: Vector2 = centers[action]
		var r: float = radii[action]
		if action == "pause":
			UITheme.draw_round_button(ci, c, r, "pause", "", pressed_by.has(action), fs)
			continue
		var def: Dictionary = LAYOUT[action]
		UITheme.draw_round_button(ci, c, r, def["icon"], def["label"], pressed_by.has(action), fs,
			action == "attack_light" or action == "interact")


## 毎フレーム変わるもの（仮想スティック）だけ直接描く
func _draw() -> void:
	var fs := int(14 * ui_scale)
	# 仮想スティック（触れている間だけ表示）
	var r := STICK_RADIUS * ui_scale
	if stick_index != -1:
		draw_circle(stick_origin, r, Color(0, 0, 0, 0.3))
		draw_arc(stick_origin, r, 0, TAU, 48, UITheme.GOLD_DIM, 2.0 * ui_scale, true)
		draw_arc(stick_origin, r * 0.92, 0, TAU, 48, Color(UITheme.GOLD_DIM, 0.3), 1.0, true)
		draw_circle(stick_pos, r * 0.42, Color(0.1, 0.08, 0.06, 0.8))
		draw_arc(stick_pos, r * 0.42, 0, TAU, 32, UITheme.GOLD, 2.5 * ui_scale, true)
		UITheme.draw_icon(self, "ember", stick_pos, r * 0.14, UITheme.GOLD)
	else:
		# 触れていない時は左下に薄くガイドを出す
		var vp := get_viewport_rect().size
		var g := Vector2(200 * ui_scale + safe_margin.x, vp.y - 170 * ui_scale)
		draw_arc(g, r, 0, TAU, 48, Color(UITheme.GOLD_DIM, 0.35), 2.0 * ui_scale, true)
		var f := UITheme.serif()
		var sz := f.get_string_size("移動", HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
		draw_string(f, g + Vector2(-sz.x * 0.5, sz.y * 0.3), "移動", HORIZONTAL_ALIGNMENT_CENTER, -1, fs,
			Color(UITheme.TEXT, 0.4))
