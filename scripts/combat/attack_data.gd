class_name AttackData
extends Resource
## 1つの攻撃の定義。予備動作(windup) → 判定(active) → 硬直(recovery) の3段階で進む。
## 敵もプレイヤーも同じ形式で攻撃を持つので、数値調整はここの値を変えるだけで済む。

@export var id := ""
@export var damage := 20.0
## 怯み値。相手の強靭度(poise)をこの分だけ削る
@export var poise_damage := 10.0
@export var stamina_cost := 0.0
## 予備動作の秒数。長いほど見てから回避しやすい
@export var windup := 0.4
## 当たり判定が出ている秒数
@export var active := 0.15
## 攻撃後の硬直（反撃される隙）
@export var recovery := 0.5
## 硬直中、次の行動を受け付け始めるまでの秒数（プレイヤーのコンボ用）
@export var cancel_after := 0.2
## 判定球の半径と、判定中に移動する位置（ローカル座標、-Zが正面）
@export var hit_radius := 0.9
@export var hit_offset_start := Vector3(0, 1.0, -1.2)
@export var hit_offset_end := Vector3(0, 1.0, -1.2)
## 判定中の前進速度（突進攻撃）
@export var lunge_speed := 0.0
## true なら判定開始時の相手との距離に合わせて突進速度を調整する（飛びかかり）
@export var homing_lunge := false
## 予備動作のうち、相手の方向へ向き直る割合 (0〜1)
@export var tracking := 0.7
## AIが選ぶ距離
@export var min_range := 0.0
@export var max_range := 2.5
@export var weight := 1.0
@export var cooldown := 0.0
## 次につながる攻撃とその確率（敵のコンボ）
@export var followup_id := ""
@export var followup_chance := 0.0
@export var knockback := 3.0
@export var hitstun := 0.45
@export var unblockable := false
## 見た目のモーション名（CharacterRig.POSES のキー）
@export var anim := "slash_r"
## 判定中に体が跳ねる高さ（跳躍攻撃の見た目）
@export var hop_height := 0.0


static func create(props: Dictionary) -> AttackData:
	var a := AttackData.new()
	for key: String in props:
		a.set(key, props[key])
	return a


func total_time() -> float:
	return windup + active + recovery
