class_name Surface
extends RefCounted
## 材質の質感（模様と凹凸）をコードで生成する。画像ファイルは使わない。
## 模様は白〜灰のノイズ画像で、材質の色（albedo_color）に掛け合わせる。
## 凹凸はノーマルマップ。UVの無い箱や円柱にも貼れるよう三面投影（triplanar）で貼る。
## 同じ種類の画像は1回だけ作って使い回す（スマホのメモリ節約）。
##
## 種類: "stone" 石材 / "ground" 地面 / "wood" 木 / "metal" 鉄 / "skin" 皮膚 / "cloth" 布

const SIZE := 256

## 種類ごとの作り方: 模様の細かさ・濃淡、凹凸の細かさ・強さ、凹凸のノイズの形
const KINDS := {
	"stone": {"freq": 0.018, "lo": 0.55, "oct": 5, "nfreq": 0.03, "bump": 7.0, "cell": true, "scale": 0.35},
	"ground": {"freq": 0.04, "lo": 0.5, "oct": 6, "nfreq": 0.06, "bump": 4.0, "cell": false, "scale": 0.25},
	"wood": {"freq": 0.05, "lo": 0.55, "oct": 3, "nfreq": 0.08, "bump": 3.0, "cell": false, "scale": 0.9},
	"metal": {"freq": 0.06, "lo": 0.72, "oct": 4, "nfreq": 0.09, "bump": 1.5, "cell": true, "scale": 1.6},
	"skin": {"freq": 0.05, "lo": 0.7, "oct": 4, "nfreq": 0.07, "bump": 3.5, "cell": false, "scale": 1.4},
	"cloth": {"freq": 0.14, "lo": 0.7, "oct": 2, "nfreq": 0.2, "bump": 1.5, "cell": false, "scale": 2.2},
}

static var _albedo: Dictionary = {}
static var _normal: Dictionary = {}
## 凹凸を付けた材質の一覧（画質「低」でまとめて凹凸を切るため）
static var _bumped: Array[WeakRef] = []
static var detail_enabled := true


static func _noise(freq: float, octaves: int, cellular: bool, seed_value: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed_value
	n.frequency = freq
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = octaves
	if cellular:
		n.noise_type = FastNoiseLite.TYPE_CELLULAR
		n.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	else:
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	return n


static func _albedo_tex(kind: String) -> NoiseTexture2D:
	if not _albedo.has(kind):
		var k: Dictionary = KINDS[kind]
		var t := NoiseTexture2D.new()
		t.width = SIZE
		t.height = SIZE
		t.seamless = true
		t.noise = _noise(k["freq"], k["oct"], false, kind.hash())
		var g := Gradient.new()
		var lo: float = k["lo"]
		g.set_color(0, Color(lo, lo, lo))
		g.set_color(1, Color(1, 1, 1))
		t.color_ramp = g
		_albedo[kind] = t
	return _albedo[kind]


static func _normal_tex(kind: String) -> NoiseTexture2D:
	if not _normal.has(kind):
		var k: Dictionary = KINDS[kind]
		var t := NoiseTexture2D.new()
		t.width = SIZE
		t.height = SIZE
		t.seamless = true
		t.as_normal_map = true
		t.bump_strength = k["bump"]
		t.noise = _noise(k["nfreq"], 3, k["cell"], kind.hash() + 7)
		_normal[kind] = t
	return _normal[kind]


## 材質に質感を付ける。色は模様の明るい部分に合わせて少し明るくする（平均の明るさを保つ）
static func apply(mat: StandardMaterial3D, kind: String, world_space: bool = false) -> StandardMaterial3D:
	var k: Dictionary = KINDS[kind]
	var lo: float = k["lo"]
	var c := mat.albedo_color
	var gain := 2.0 / (1.0 + lo)
	mat.albedo_color = Color(minf(c.r * gain, 1.0), minf(c.g * gain, 1.0), minf(c.b * gain, 1.0), c.a)
	mat.albedo_texture = _albedo_tex(kind)
	mat.normal_texture = _normal_tex(kind)
	mat.normal_enabled = detail_enabled
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = world_space
	var s: float = k["scale"]
	mat.uv1_scale = Vector3(s, s, s) if kind != "wood" else Vector3(s * 0.3, s * 2.5, s * 0.3)
	mat.uv1_triplanar_sharpness = 2.0
	_bumped.append(weakref(mat))
	return mat


## 画質「低」では凹凸（ノーマルマップ）を切って軽くする
static func set_detail(on: bool) -> void:
	detail_enabled = on
	var alive: Array[WeakRef] = []
	for w in _bumped:
		var m := w.get_ref() as StandardMaterial3D
		if m:
			m.normal_enabled = on
			alive.append(w)
	_bumped = alive
