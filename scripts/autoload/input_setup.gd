extends Node
## キーボード/マウス/ゲームパッドの操作割り当てを起動時に登録する（Autoload: InputSetup）。
## project.godot を手書きせずに済むよう、ここで InputMap を構成する。

const STICK_DEADZONE := 0.2


func _ready() -> void:
	_bind("move_forward", [_key(KEY_W), _axis(JOY_AXIS_LEFT_Y, -1.0)])
	_bind("move_back", [_key(KEY_S), _axis(JOY_AXIS_LEFT_Y, 1.0)])
	_bind("move_left", [_key(KEY_A), _axis(JOY_AXIS_LEFT_X, -1.0)])
	_bind("move_right", [_key(KEY_D), _axis(JOY_AXIS_LEFT_X, 1.0)])
	_bind("cam_left", [_key(KEY_LEFT), _axis(JOY_AXIS_RIGHT_X, -1.0)])
	_bind("cam_right", [_key(KEY_RIGHT), _axis(JOY_AXIS_RIGHT_X, 1.0)])
	_bind("cam_up", [_key(KEY_UP), _axis(JOY_AXIS_RIGHT_Y, -1.0)])
	_bind("cam_down", [_key(KEY_DOWN), _axis(JOY_AXIS_RIGHT_Y, 1.0)])
	# 短押し=回避 / 長押し=ダッシュ
	_bind("dodge", [_key(KEY_SPACE), _joy(JOY_BUTTON_B)])
	_bind("jump", [_key(KEY_F), _joy(JOY_BUTTON_A)])
	_bind("attack_light", [_mouse(MOUSE_BUTTON_LEFT), _joy(JOY_BUTTON_RIGHT_SHOULDER)])
	# 強攻撃: キーボードは Shift+左クリック（player.gd で判定）、パッドは RT
	_bind("attack_heavy", [_key(KEY_C), _axis(JOY_AXIS_TRIGGER_RIGHT, 1.0)])
	_bind("guard", [_mouse(MOUSE_BUTTON_RIGHT), _joy(JOY_BUTTON_LEFT_SHOULDER)])
	_bind("lock_on", [_key(KEY_Q), _mouse(MOUSE_BUTTON_MIDDLE), _joy(JOY_BUTTON_RIGHT_STICK)])
	_bind("use_item", [_key(KEY_R), _joy(JOY_BUTTON_X)])
	_bind("interact", [_key(KEY_E), _joy(JOY_BUTTON_Y)])
	_bind("pause", [_key(KEY_ESCAPE), _joy(JOY_BUTTON_START)])
	_bind("toggle_help", [_key(KEY_F1), _joy(JOY_BUTTON_BACK)])


func _bind(action: StringName, events: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, STICK_DEADZONE)
	for ev: InputEvent in events:
		InputMap.action_add_event(action, ev)


func _key(code: Key) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = code
	return ev


func _mouse(button: MouseButton) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	return ev


func _joy(button: JoyButton) -> InputEventJoypadButton:
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	return ev


func _axis(axis: JoyAxis, value: float) -> InputEventJoypadMotion:
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = value
	return ev
