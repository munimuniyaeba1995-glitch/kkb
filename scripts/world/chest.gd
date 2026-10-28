class_name Chest
extends Interactable
## 宝箱。一度開けると GameState に記録され、復活後も開いたまま。
## reward: "flask"（回復薬の所持上限+1） / "ash:<数>"（残灰を獲得）

var chest_id := ""
var reward := "flask"
var lid: Node3D


func _init(id: String = "", reward_kind: String = "flask") -> void:
	chest_id = id
	reward = reward_kind


func _ready() -> void:
	super._ready()
	prompt = "宝箱を開ける"
	radius = 1.8
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.35, 0.22, 0.12)
	Surface.apply(wood, "wood")
	var trim := StandardMaterial3D.new()
	trim.albedo_color = Color(0.7, 0.55, 0.25)
	trim.metallic = 0.8
	var body := StaticBody3D.new()
	body.collision_layer = Actor.LAYER_WORLD
	add_child(body)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.0, 0.6, 0.65)
	mesh.mesh = bm
	mesh.material_override = wood
	mesh.position.y = 0.3
	body.add_child(mesh)
	var col := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = bm.size
	col.shape = bs
	col.position.y = 0.3
	body.add_child(col)
	lid = Node3D.new()
	lid.position = Vector3(0, 0.6, 0.32)
	add_child(lid)
	var lid_mesh := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(1.05, 0.15, 0.68)
	lid_mesh.mesh = lm
	lid_mesh.material_override = trim
	lid_mesh.position = Vector3(0, 0.07, -0.34)
	lid.add_child(lid_mesh)
	if GameState.is_claimed(chest_id):
		_set_opened()


func _set_opened() -> void:
	enabled = false
	lid.rotation_degrees.x = -100.0


func interact(_player: Player) -> void:
	if not enabled:
		return
	GameState.claim(chest_id)
	_set_opened()
	if reward == "flask":
		GameState.add_flask_capacity()
		GameState.notify.emit("「灰硝子の小瓶」を手に入れた（回復薬の所持数+1）")
	elif reward.begins_with("ash:"):
		var amount := int(reward.get_slice(":", 1))
		GameState.add_ash(amount)
		GameState.notify.emit("「古い残灰の塊」を手に入れた（残灰 +%d）" % amount)
