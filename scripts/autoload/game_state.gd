extends Node
## ゲーム全体の進行状態（Autoload: GameState）。
## 経験値（残灰）、回復薬、チェックポイント、死亡時ドロップ、取得済みアイテムを保持する。
##
## 死亡ドロップのルール:
##   - 死亡すると所持している残灰をすべてその場（最後に立っていた安全な地点）に落とす。
##   - 落とした残灰に触れると全額回収できる。
##   - 回収する前に再び死亡すると、前回落とした残灰は消滅し、今回の所持分が新たに落ちる。

signal ash_changed(value: int)
signal flasks_changed(current: int, max_value: int)
signal notify(text: String)

const FLASK_HEAL := 140.0

var ash: int = 0
var flask_max: int = 3
var flasks: int = 3
var respawn_position := Vector3.ZERO
var respawn_yaw := 0.0
var has_dropped_ash := false
var dropped_ash: int = 0
var dropped_ash_position := Vector3.ZERO
var boss_defeated := false
## 一度だけ取得できる宝箱・隠し壁などのID
var claimed: Dictionary = {}
var deaths: int = 0


func new_game(spawn: Vector3, yaw: float) -> void:
	ash = 0
	flask_max = 3
	flasks = flask_max
	respawn_position = spawn
	respawn_yaw = yaw
	has_dropped_ash = false
	dropped_ash = 0
	boss_defeated = false
	claimed.clear()
	deaths = 0
	ash_changed.emit(ash)
	flasks_changed.emit(flasks, flask_max)


func add_ash(amount: int) -> void:
	ash += amount
	ash_changed.emit(ash)


func use_flask() -> bool:
	if flasks <= 0:
		return false
	flasks -= 1
	flasks_changed.emit(flasks, flask_max)
	return true


func refill_flasks() -> void:
	flasks = flask_max
	flasks_changed.emit(flasks, flask_max)


func add_flask_capacity() -> void:
	flask_max += 1
	flasks += 1
	flasks_changed.emit(flasks, flask_max)


func set_checkpoint(pos: Vector3, yaw: float) -> void:
	respawn_position = pos
	respawn_yaw = yaw


## 死亡時に呼ぶ。前回の未回収ドロップは上書きされて消える。
func on_player_died(drop_pos: Vector3) -> void:
	deaths += 1
	if has_dropped_ash and dropped_ash > 0:
		notify.emit("回収されなかった残灰 %d は失われた" % dropped_ash)
	dropped_ash = ash
	has_dropped_ash = ash > 0
	dropped_ash_position = drop_pos
	ash = 0
	ash_changed.emit(ash)


func recover_dropped_ash() -> int:
	var amount := dropped_ash
	ash += amount
	dropped_ash = 0
	has_dropped_ash = false
	ash_changed.emit(ash)
	return amount


func is_claimed(id: String) -> bool:
	return claimed.has(id)


func claim(id: String) -> void:
	claimed[id] = true
