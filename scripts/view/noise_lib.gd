class_name NoiseLib
extends RefCounted
## Бесшовные шумовые текстуры для шейдеров (рельеф, вода, листва, облака).
## Создаются один раз синхронно, чтобы первый кадр уже был с текстурами.

static var _cache: Dictionary = {}


## RGBA: четыре разных fbm-шума (низкие частоты).
static func noise_a() -> Texture2D:
	return _cached("a", func() -> Texture2D:
		return _rgba([_fbm(11, 0.012, 4), _fbm(23, 0.018, 4), _fbm(37, 0.01, 3), _fbm(41, 0.025, 4)]))


## Ячеистый шум: R — расстояние до ближайшей точки, G — до второй (трещины, камешки).
static func noise_b() -> Texture2D:
	return _cached("b", func() -> Texture2D:
		return _rgba([_cell(5, 0.03, FastNoiseLite.RETURN_DISTANCE), _cell(5, 0.03, FastNoiseLite.RETURN_DISTANCE2),
			_cell(9, 0.05, FastNoiseLite.RETURN_DISTANCE), _fbm(77, 0.05, 2)]))


## Высокие частоты: зерно, травинки, блёстки.
static func noise_c() -> Texture2D:
	return _cached("c", func() -> Texture2D:
		return _rgba([_fbm(101, 0.06, 3), _fbm(113, 0.12, 2), _value(127, 0.2), _fbm(131, 0.09, 3)]))


static func _cached(key: String, make: Callable) -> Texture2D:
	if not _cache.has(key):
		_cache[key] = make.call()
	return _cache[key]


static func _fbm(s: int, freq: float, oct: int) -> Image:
	var n := FastNoiseLite.new()
	n.seed = s
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_octaves = oct
	return n.get_seamless_image(256, 256)


static func _cell(s: int, freq: float, ret: int) -> Image:
	var n := FastNoiseLite.new()
	n.seed = s
	n.noise_type = FastNoiseLite.TYPE_CELLULAR
	n.frequency = freq
	n.cellular_return_type = ret
	n.fractal_type = FastNoiseLite.FRACTAL_NONE
	return n.get_seamless_image(256, 256)


static func _value(s: int, freq: float) -> Image:
	var n := FastNoiseLite.new()
	n.seed = s
	n.noise_type = FastNoiseLite.TYPE_VALUE
	n.frequency = freq
	n.fractal_type = FastNoiseLite.FRACTAL_NONE
	return n.get_seamless_image(256, 256)


## Собирает четыре одноканальных изображения в RGBA с мип-картами.
static func _rgba(chans: Array) -> Texture2D:
	var w := 256
	var data := PackedByteArray()
	data.resize(w * w * 4)
	for c in 4:
		var img: Image = chans[c]
		img.convert(Image.FORMAT_L8)
		var src := img.get_data()
		for i in w * w:
			data[i * 4 + c] = src[i]
	var out := Image.create_from_data(w, w, false, Image.FORMAT_RGBA8, data)
	out.generate_mipmaps()
	return ImageTexture.create_from_image(out)
