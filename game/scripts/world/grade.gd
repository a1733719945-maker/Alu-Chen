class_name Grade
## 调色（2026-09-29，学《通往东方之路》Road to Vostok）：那个游戏的贴图全是照片、连 PBR 都没用，
## 好看在"克制"——颜色不鲜艳、暗部压得住、一张图一个统一的色调、四角压暗、一层胶片颗粒。
## 我们以前的毛病是颜色太卡通：草绿得发荧光、天蓝得发紫、海水青得发亮、土路黄得发橙。
##
## 1. lut(biome)：一张 3D 颜色查找表挂到 Environment.adjustment_color_correction
##    （Godot 在色调映射、转 sRGB、亮度对比度饱和度之后查表，所以这里的输入输出都是 sRGB）：
##    太饱和的颜色压下去（本来就淡的不动）→ 绿往橄榄色偏 → 天蓝 / 海青再压一点 → 暗部偏冷、亮部偏暖 → 一点 S 曲线 → 黑位抬一点点
## 2. overlay()：屏幕后处理（在 HUD 下面一层）：一点锐化、四角压暗、胶片颗粒

const N := 33

## desat：高饱和压多少；green / blue：绿、蓝青额外压多少；olive：绿往黄偏多少；
## sh / hi：暗部 / 亮部加的颜色；curve：S 曲线强度；lift：黑位
const LOOK := {
	"island": {"desat": 0.3, "green": 0.2, "olive": 0.3, "blue": 0.3,
		"sh": Color(-0.006, 0.0, 0.014), "hi": Color(0.024, 0.012, -0.016), "curve": 0.16, "lift": 0.012},
	# 落霞：秋天傍晚，荧光绿的草丛最扎眼——绿压狠、往枯黄偏
	"forest": {"desat": 0.28, "green": 0.4, "olive": 0.55, "blue": 0.2,
		"sh": Color(-0.004, 0.0, 0.012), "hi": Color(0.03, 0.014, -0.02), "curve": 0.16, "lift": 0.014},
	"deepforest": {"desat": 0.32, "green": 0.3, "olive": 0.15, "blue": 0.3,
		"sh": Color(-0.004, 0.004, 0.016), "hi": Color(0.006, 0.004, 0.0), "curve": 0.12, "lift": 0.014},
	"snow": {"desat": 0.25, "green": 0.45, "olive": 0.35, "blue": 0.2,
		"sh": Color(-0.004, 0.002, 0.016), "hi": Color(0.012, 0.006, -0.004), "curve": 0.12, "lift": 0.01},
	# 归墟：海水青得像泳池、草绿得像塑料
	"sea": {"desat": 0.26, "green": 0.3, "olive": 0.35, "blue": 0.18,
		"sh": Color(-0.004, 0.002, 0.012), "hi": Color(0.024, 0.012, -0.016), "curve": 0.16, "lift": 0.012},
}

static var _cache := {}


static func lut(biome: String) -> ImageTexture3D:
	if _cache.has(biome):
		return _cache[biome]
	var p: Dictionary = LOOK.get(biome, LOOK["island"])
	var imgs: Array[Image] = []
	# Godot 查表不做半个格子的偏移（坐标 0 落在第一格边上），所以第 i 格存的是 (i + 0.5) / N 这个颜色调完的结果
	for b in N:
		var img := Image.create(N, N, false, Image.FORMAT_RGB8)
		for g in N:
			for r in N:
				img.set_pixel(r, g, grade(Color((r + 0.5) / N, (g + 0.5) / N, (b + 0.5) / N), p))
		imgs.append(img)
	var t := ImageTexture3D.new()
	t.create(Image.FORMAT_RGB8, N, N, N, false, imgs)
	_cache[biome] = t
	return t


static func grade(c: Color, p: Dictionary) -> Color:
	var v := Vector3(c.r, c.g, c.b)
	var lum := v.dot(Vector3(0.2126, 0.7152, 0.0722))
	var hd := c.h * 360.0
	var s := c.s
	# 绿（草、树叶）和蓝青（天、海）
	var gw := smoothstep(55.0, 85.0, hd) * (1.0 - smoothstep(150.0, 172.0, hd))
	var bw := smoothstep(168.0, 190.0, hd) * (1.0 - smoothstep(245.0, 265.0, hd))
	# 绿往橄榄色偏：红往绿那边拉（黄绿、枯草色）
	v.x += (v.y - v.x) * gw * float(p["olive"]) * 0.45 * s
	# 饱和度：往亮度拉
	var k := 1.0 - float(p["desat"]) * smoothstep(0.22, 0.85, s)
	k *= 1.0 - float(p["green"]) * gw * smoothstep(0.15, 0.5, s) - float(p["blue"]) * bw * smoothstep(0.15, 0.5, s)
	v = Vector3(lum, lum, lum).lerp(v, clampf(k, 0.0, 1.0))
	# 暗部冷、亮部暖
	var sh: Color = p["sh"]
	var hi: Color = p["hi"]
	var ws := 1.0 - smoothstep(0.0, 0.45, lum)
	var wh := smoothstep(0.45, 1.0, lum)
	v += Vector3(sh.r, sh.g, sh.b) * ws + Vector3(hi.r, hi.g, hi.b) * wh
	# S 曲线
	var cv := float(p["curve"])
	for i in 3:
		var x := clampf(v[i], 0.0, 1.0)
		v[i] = lerpf(x, x * x * (3.0 - 2.0 * x), cv)
	var lift := float(p["lift"])
	v = v * (1.0 - lift) + Vector3(lift, lift, lift)
	return Color(clampf(v.x, 0.0, 1.0), clampf(v.y, 0.0, 1.0), clampf(v.z, 0.0, 1.0))


const POST := """shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;
uniform float sharpen = 0.3;
uniform float vignette = 0.22;
uniform float grain = 0.028;
void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE;
	vec3 c = texture(screen_tex, SCREEN_UV).rgb;
	vec3 n = texture(screen_tex, SCREEN_UV + vec2(px.x, 0.0)).rgb + texture(screen_tex, SCREEN_UV - vec2(px.x, 0.0)).rgb
		+ texture(screen_tex, SCREEN_UV + vec2(0.0, px.y)).rgb + texture(screen_tex, SCREEN_UV - vec2(0.0, px.y)).rgb;
	c = max(c + (c - n * 0.25) * sharpen, vec3(0.0));
	vec2 d = (SCREEN_UV - 0.5) * vec2(1.0, 0.75);
	c *= 1.0 - smoothstep(0.2, 0.62, length(d)) * vignette;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	float g = fract(sin(dot(FRAGCOORD.xy + fract(TIME * 7.13) * 91.7, vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
	c += g * grain * (1.0 - clamp(abs(l - 0.45) * 1.6, 0.0, 0.8));
	COLOR = vec4(c, 1.0);
}"""


## 屏幕后处理层：锐化、四角压暗、胶片颗粒（HUD 在它上面，不受影响）
static func overlay() -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.name = "Grade"
	layer.layer = -1
	var r := ColorRect.new()
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	var m := ShaderMaterial.new()
	m.shader = Shader.new()
	m.shader.code = POST
	r.material = m
	layer.add_child(r)
	return layer
