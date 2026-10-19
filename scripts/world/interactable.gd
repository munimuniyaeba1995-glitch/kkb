class_name Interactable
extends Node3D
## 「[E] 調べる」系オブジェクトの基底。プレイヤーが radius 以内にいると操作できる。
## 一番近いものを Main が選び、HUDに prompt を表示する。

var prompt := "調べる"
var radius := 2.0
var enabled := true


func _ready() -> void:
	add_to_group("interactables")


func can_interact(_player: Player) -> bool:
	return enabled


func interact(_player: Player) -> void:
	pass
