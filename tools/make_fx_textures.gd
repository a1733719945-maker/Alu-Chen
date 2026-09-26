extends SceneTree
## 生成特效贴图（全部程序算出来，不用下载素材），存到 game/assets/fx/*.png。
## 用法（在 game 目录）：godot --headless --path . --script ../tools/make_fx_textures.gd
## 发光贴图的 RGB = 透明度（贴花的发光只看 RGB，不然整块方片都亮），烟和焦痕带一点明暗。材质里再上色。

var out := ""
var noise := FastNoiseLite.new()
var noise2 := FastNoiseLite.new()


func _init() -> void:
	out = ProjectSettings.globalize_path("res://assets/fx")
	DirAccess.make_dir_recursive_absolute(out)
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 5
	noise.frequency = 0.012
	noise2.noise_type = FastNoiseLite.TYPE_CELLULAR
	noise2.frequency = 0.02
	noise2.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	var t0 := Time.get_ticks_msec()
	_glow()
	_flare()
	_spark()
	_smoke()
	_ring()
	_halo()
	_warn()
	_scorch()
	_crack()
	_noise_tex()
	_swirl()
	_slash()
	_magic()
	print("fx textures done in %d ms -> %s" % [Time.get_ticks_msec() - t0, out])
	quit()


func _save(name: String, w: int, h: int, px: PackedByteArray) -> void:
	var img := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, px)
	img.save_png(out + "/" + name + ".png")
	print("  ", name, " ", w, "x", h)


func _put(px: PackedByteArray, i: int, v: float, a: float) -> void:
	var c := int(clampf(v, 0.0, 1.0) * 255.0)
	px[i * 4] = c
	px[i * 4 + 1] = c
	px[i * 4 + 2] = c
	px[i * 4 + 3] = int(clampf(a, 0.0, 1.0) * 255.0)


func _ss(e0: float, e1: float, x: float) -> float:
	return smoothstep(e0, e1, x)


## 圆形柔光
func _glow() -> void:
	var n := 128
	var px := PackedByteArray()
	px.resize(n * n * 4)
	for y in n:
		for x in n:
			var p := Vector2(x + 0.5, y + 0.5) / n * 2.0 - Vector2.ONE
			var r := p.length()
			var a := exp(-r * r * 5.0) * _ss(1.0, 0.75, r)
			_put(px, x + y * n, a, a)
	_save("glow", n, n, px)


## 星芒：亮核 + 四道长光 + 四道短光 + 一圈淡光晕（枪口火光、命中、闪光）
func _flare() -> void:
	var n := 256
	var px := PackedByteArray()
	px.resize(n * n * 4)
	for y in n:
		for x in n:
			var p := Vector2(x + 0.5, y + 0.5) / n * 2.0 - Vector2.ONE
			var r := p.length()
			var core := exp(-r * r * 30.0)
			var fall := pow(maxf(1.0 - r, 0.0), 2.0)
			var rays := (exp(-absf(p.x) * 60.0) + exp(-absf(p.y) * 60.0)) * fall
			var d1 := absf(p.x - p.y) * 0.7071
			var d2 := absf(p.x + p.y) * 0.7071
			rays += (exp(-d1 * 90.0) + exp(-d2 * 90.0)) * pow(maxf(1.0 - r * 1.6, 0.0), 2.0) * 0.5
			var halo := exp(-r * 5.0) * 0.35
			var a := clampf(core + rays + halo, 0.0, 1.0) * _ss(1.0, 0.9, r)
			_put(px, x + y * n, a, a)
	_save("flare", n, n, px)


## 火花：细长的光条（配合按速度拉长的粒子）
func _spark() -> void:
	var w := 32
	var h := 128
	var px := PackedByteArray()
	px.resize(w * h * 4)
	for y in h:
		for x in w:
			var u := (x + 0.5) / w * 2.0 - 1.0
			var v := (y + 0.5) / h * 2.0 - 1.0
			var across := exp(-u * u * 14.0)
			var along := pow(maxf(1.0 - absf(v), 0.0), 1.2)
			# 头（v < 0）亮一点
			along *= 1.0 if v < 0.0 else 0.75
			_put(px, x + y * w, across * along, across * along)
	_save("spark", w, h, px)


## 烟：2×2 四种形状的烟团，边缘被噪声吃掉，上亮下暗
func _smoke() -> void:
	var f := 256
	var n := f * 2
	var px := PackedByteArray()
	px.resize(n * n * 4)
	for fy in 2:
		for fx in 2:
			var seed := fx + fy * 2
			var ox := seed * 731.0
			var oy := seed * 417.0
			for y in f:
				for x in f:
					var p := Vector2(x + 0.5, y + 0.5) / f * 2.0 - Vector2.ONE
					var r := p.length()
					var nz := noise.get_noise_2d(x * 0.9 + ox, y * 0.9 + oy) * 0.5 + 0.5
					var nz2 := noise.get_noise_2d(x * 2.2 + oy, y * 2.2 + ox) * 0.5 + 0.5
					var shape := _ss(1.0, 0.25, r + (nz - 0.5) * 0.7)
					var dens := shape * (0.45 + nz * 0.55) * (0.7 + nz2 * 0.3)
					var light := 0.62 + (-p.y) * 0.22 + (nz2 - 0.5) * 0.25
					_put(px, (fx * f + x) + (fy * f + y) * n, light, dens)
	_save("smoke", n, n, px)


## 冲击波环：一圈亮边，往里淡淡一层，边上被噪声打碎
func _ring() -> void:
	var n := 512
	var px := PackedByteArray()
	px.resize(n * n * 4)
	for y in n:
		for x in n:
			var p := Vector2(x + 0.5, y + 0.5) / n * 2.0 - Vector2.ONE
			var r := p.length()
			var ang := atan2(p.y, p.x)
			var nz := noise.get_noise_2d(cos(ang) * 90.0 + 300.0, sin(ang) * 90.0 + r * 60.0) * 0.5 + 0.5
			var band := exp(-pow((r - 0.86) / 0.035, 2.0))
			var inner := pow(_ss(0.2, 0.86, r), 3.0) * 0.35 * _ss(0.9, 0.86, r)
			var a := (band * (0.55 + nz * 0.7) + inner * (0.6 + nz * 0.4)) * _ss(1.0, 0.94, r)
			_put(px, x + y * n, a, a)
	_save("ring", n, n, px)


## 红圈预警：淡淡的底，越往外越亮，外圈一圈警戒斜纹和亮边
func _warn() -> void:
	var n := 512
	var px := PackedByteArray()
	px.resize(n * n * 4)
	for y in n:
		for x in n:
			var p := Vector2(x + 0.5, y + 0.5) / n * 2.0 - Vector2.ONE
			var r := p.length()
			var ang := atan2(p.y, p.x)
			var fill := 0.16 + 0.45 * pow(_ss(0.3, 0.95, r), 2.0)
			var edge := exp(-pow((r - 0.965) / 0.018, 2.0))
			var stripe_zone := _ss(0.84, 0.86, r) * _ss(0.94, 0.92, r)
			var stripe := _ss(0.45, 0.55, fposmod(ang / TAU * 40.0 + r * 6.0, 1.0)) * stripe_zone
			var inner := exp(-pow((r - 0.83) / 0.01, 2.0)) * 0.7
			var a := clampf(fill + edge + stripe * 0.55 + inner, 0.0, 1.0) * _ss(1.0, 0.985, r)
			_put(px, x + y * n, a, a)
	_save("warn", n, n, px)


## 焦痕：黑色一块，边缘碎、带放射状的条纹（爆炸、陨石落地）
func _scorch() -> void:
	var n := 512
	var px := PackedByteArray()
	px.resize(n * n * 4)
	for y in n:
		for x in n:
			var p := Vector2(x + 0.5, y + 0.5) / n * 2.0 - Vector2.ONE
			var r := p.length()
			var ang := atan2(p.y, p.x)
			var nz := noise.get_noise_2d(x * 1.2, y * 1.2) * 0.5 + 0.5
			var streak := noise.get_noise_2d(cos(ang) * 60.0, sin(ang) * 60.0) * 0.5 + 0.5
			var shape := _ss(0.95, 0.25, r + (nz - 0.5) * 0.5 - (streak - 0.5) * 0.35 * r)
			var a := shape * (0.55 + nz * 0.45)
			_put(px, x + y * n, 0.04 + nz * 0.08, a)
	_save("scorch", n, n, px)


## 地面裂纹：九道从中心裂开的缝，弯弯曲曲、越往外越细，还有分叉
func _crack() -> void:
	var n := 512
	var px := PackedByteArray()
	px.resize(n * n * 4)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var cracks: Array = []
	for k in 9:
		cracks.append({"a": TAU * k / 9.0 + rng.randf_range(-0.25, 0.25), "len": rng.randf_range(0.6, 0.95), "o": rng.randf() * 100.0})
	for k in 8:
		cracks.append({"a": rng.randf() * TAU, "len": rng.randf_range(0.25, 0.5), "o": rng.randf() * 100.0, "start": rng.randf_range(0.2, 0.45)})
	for y in n:
		for x in n:
			var p := Vector2(x + 0.5, y + 0.5) / n * 2.0 - Vector2.ONE
			var r := p.length()
			var ang := atan2(p.y, p.x)
			var best := 0.0
			for c in cracks:
				var st := float(c.get("start", 0.0))
				if r < st or r > float(c["len"]):
					continue
				var wig := noise.get_noise_2d(r * 220.0, float(c["o"]) * 10.0) * 0.22
				var da := wrapf(ang - float(c["a"]) - wig, -PI, PI)
				var dist := absf(da) * r
				var width := 0.012 * (1.0 - (r - st) / (float(c["len"]) - st)) + 0.002
				best = maxf(best, _ss(width, width * 0.3, dist))
			var center := _ss(0.12, 0.0, r) * 0.8
			var a := clampf(best + center, 0.0, 1.0)
			_put(px, x + y * n, a, a)
	_save("crack", n, n, px)


## 可平铺的噪声（着色器里用：火、光柱、光束、魂灵）
func _noise_tex() -> void:
	var nl := FastNoiseLite.new()
	nl.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	nl.fractal_type = FastNoiseLite.FRACTAL_FBM
	nl.fractal_octaves = 5
	nl.frequency = 0.02
	var img := nl.get_seamless_image(256, 256, false, false, 0.1, true)
	img.convert(Image.FORMAT_RGBA8)
	img.save_png(out + "/noise.png")
	print("  noise 256x256")


## 漩涡：三条旋臂（黑洞吸积盘、牵引）
func _swirl() -> void:
	var n := 512
	var px := PackedByteArray()
	px.resize(n * n * 4)
	for y in n:
		for x in n:
			var p := Vector2(x + 0.5, y + 0.5) / n * 2.0 - Vector2.ONE
			var r := maxf(p.length(), 0.001)
			var ang := atan2(p.y, p.x)
			var arm := pow(0.5 + 0.5 * sin(ang * 3.0 + log(r) * 6.0), 3.0)
			var nz := noise.get_noise_2d(x * 2.0, y * 2.0) * 0.5 + 0.5
			var a := arm * (0.5 + nz * 0.8) * _ss(1.0, 0.55, r) * _ss(0.08, 0.3, r)
			a += exp(-pow((r - 0.22) / 0.04, 2.0)) * 0.8
			_put(px, x + y * n, clampf(a, 0.0, 1.0), clampf(a, 0.0, 1.0))
	_save("swirl", n, n, px)


## 月牙斩：一道弧光，头亮尾淡（爪击、镰刀）
func _slash() -> void:
	var n := 512
	var px := PackedByteArray()
	px.resize(n * n * 4)
	for y in n:
		for x in n:
			var p := Vector2(x + 0.5, y + 0.5) / n * 2.0 - Vector2.ONE
			var r := p.length()
			var ang := atan2(p.y, p.x)
			# 弧在 -110° ~ 110°（右半边），头在上面
			var t := clampf((ang + 1.9) / 3.8, 0.0, 1.0)
			var inside := _ss(-2.0, -1.8, ang) * _ss(2.0, 1.8, ang)
			var thick := 0.02 + 0.09 * sin(t * PI)
			var band := _ss(thick, thick * 0.2, absf(r - 0.78))
			var nz := noise.get_noise_2d(x * 3.0, y * 3.0) * 0.5 + 0.5
			var a := band * inside * pow(t, 0.7) * (0.75 + nz * 0.4)
			_put(px, x + y * n, clampf(a, 0.0, 1.0), clampf(a, 0.0, 1.0))
	_save("slash", n, n, px)


## 法阵：几圈同心圆、外圈刻度、一圈符文、六芒星、八角星、六个小圆
func _magic() -> void:
	var n := 1024
	var px := PackedByteArray()
	px.resize(n * n * 4)
	var pw := 2.0 / n   # 一个像素的宽度（抗锯齿）
	# 六芒星：两个三角形的边
	var hexa: Array = []
	for t in 2:
		var pts: Array = []
		for k in 3:
			var a := -PI / 2.0 + TAU * k / 3.0 + (PI if t == 1 else 0.0)
			pts.append(Vector2(cos(a), sin(a)) * 0.64)
		for k in 3:
			hexa.append([pts[k], pts[(k + 1) % 3]])
	# 八角星（内圈）
	var star: Array = []
	var sp: Array = []
	for k in 8:
		var a := TAU * k / 8.0
		sp.append(Vector2(cos(a), sin(a)) * 0.33)
	for k in 8:
		star.append([sp[k], sp[(k + 3) % 8]])
	var small: Array = []
	for k in 6:
		var a := -PI / 2.0 + TAU * k / 6.0
		small.append(Vector2(cos(a), sin(a)) * 0.64)
	for y in n:
		for x in n:
			var p := Vector2(x + 0.5, y + 0.5) / n * 2.0 - Vector2.ONE
			var r := p.length()
			if r > 1.0:
				_put(px, x + y * n, 0.0, 0.0)
				continue
			var ang := atan2(p.y, p.x)
			var v := 0.0
			# 同心圆
			for ring in [[0.965, 0.010], [0.915, 0.004], [0.75, 0.007], [0.715, 0.003], [0.40, 0.006], [0.355, 0.003], [0.12, 0.004]]:
				v = maxf(v, _ss(ring[1] + pw, ring[1] - pw * 0.5, absf(r - ring[0])))
			# 外圈刻度：72 格，每 6 格一根长的
			if r > 0.915 and r < 0.965:
				var cell := ang / TAU * 72.0
				var dc := absf(fposmod(cell, 1.0) - 0.5)
				var long := int(floor(cell)) % 6 == 0
				if long or r > 0.94:
					v = maxf(v, _ss(0.16, 0.07, dc) * (1.0 if long else 0.7))
			# 符文带：36 格，每格三四笔，笔画按格子号哈希出来
			if r > 0.765 and r < 0.9:
				var cell2 := ang / TAU * 36.0
				var ci := int(floor(fposmod(cell2, 36.0)))
				var u := fposmod(cell2, 1.0) - 0.5          # 格子里的横向 -0.5..0.5
				var w := (r - 0.8325) / 0.0675              # 径向 -1..1
				var h := hash(ci * 7 + 3)
				var g := 0.0
				var lw := 0.07
				if h & 1:
					g = maxf(g, _ss(lw, lw * 0.4, absf(u)) * _ss(0.85, 0.75, absf(w)))            # 竖
				if h & 2:
					g = maxf(g, _ss(lw * 1.4, lw * 0.5, absf(w - 0.55)) * _ss(0.32, 0.26, absf(u)))  # 上横
				if h & 4:
					g = maxf(g, _ss(lw * 1.4, lw * 0.5, absf(w + 0.5)) * _ss(0.32, 0.26, absf(u)))   # 下横
				if h & 8:
					g = maxf(g, _ss(lw, lw * 0.4, absf(u - w * 0.3)) * _ss(0.8, 0.7, absf(w)))     # 斜
				if h & 16:
					var cr := Vector2(u * 2.2, w).length()
					g = maxf(g, _ss(0.1, 0.03, absf(cr - 0.42)))                                    # 小圈
				if h & 32:
					g = maxf(g, _ss(0.16, 0.08, Vector2(u * 2.2, w - 0.1).length()))                 # 点
				if g == 0.0:
					g = _ss(lw, lw * 0.4, absf(u)) * _ss(0.85, 0.75, absf(w))
				v = maxf(v, g * 0.95)
			# 六芒星、八角星
			if r < 0.72:
				for s in hexa:
					v = maxf(v, _ss(0.006 + pw, 0.006 - pw * 0.5, _seg(p, s[0], s[1])) * 0.9)
				for c in small:
					v = maxf(v, _ss(0.006 + pw, 0.004, absf(p.distance_to(c) - 0.055)))
			if r < 0.36:
				for s in star:
					v = maxf(v, _ss(0.005 + pw, 0.005 - pw * 0.5, _seg(p, s[0], s[1])) * 0.85)
			# 中间一点光，整体淡淡一层底
			v = maxf(v, exp(-r * r * 60.0) * 0.8)
			var base := 0.06 * _ss(0.97, 0.9, r)
			_put(px, x + y * n, clampf(v + base, 0.0, 1.0), clampf(v + base, 0.0, 1.0))
	_save("magic", n, n, px)


func _seg(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return p.distance_to(a + ab * t)


## 魂环：一圈亮的细环 + 外面一层柔光（魂兽脚下的魂环、掉在地上的魂环）
func _halo() -> void:
	var n := 512
	var px := PackedByteArray()
	px.resize(n * n * 4)
	for y in n:
		for x in n:
			var p := Vector2(x + 0.5, y + 0.5) / n * 2.0 - Vector2.ONE
			var r := p.length()
			var core := exp(-pow((r - 0.8) / 0.022, 2.0))
			var halo := exp(-pow((r - 0.8) / 0.09, 2.0)) * 0.45
			var a := clampf(core + halo, 0.0, 1.0) * _ss(1.0, 0.96, r)
			_put(px, x + y * n, a, a)
	_save("halo", n, n, px)