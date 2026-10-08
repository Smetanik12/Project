class_name GroundAtlas
extends RefCounted
## Атлас поверхности 512×512 тайлов вокруг камеры (адресация по модулю 512).
## R — тип поверхности, G — флаги (дорога, мостовая, поле, тропа, пол, окоп, берег, поселение).
## Шейдер рельефа читает соседние тайлы отсюда, поэтому смешивание на стыках чанков без швов.

const SIZE := 512

var image: Image
var texture: ImageTexture
var dirty := false


func _init() -> void:
	image = Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(3.0 / 255.0, 0, 0, 1))
	texture = ImageTexture.create_from_image(image)


## Байты блока чанка (можно готовить в рабочем потоке).
static func chunk_bytes(c: Chunk) -> PackedByteArray:
	var n := Chunk.N
	var data := PackedByteArray()
	data.resize(n * n * 4)
	for i in n * n:
		var f := c.flags[i]
		var g := 0
		if f & Chunk.F_ROAD:
			g |= 1
		if f & Chunk.F_PAVED:
			g |= 2
		if f & Chunk.F_FIELD:
			g |= 4
		if f & Chunk.F_PATH:
			g |= 8
		if f & Chunk.F_INDOOR:
			g |= 16
		if f & Chunk.F_TRENCH:
			g |= 32
		if f & Chunk.F_SHORE:
			g |= 64
		if f & Chunk.F_SETTLE:
			g |= 128
		data[i * 4] = c.ground[i]
		data[i * 4 + 1] = g
		data[i * 4 + 2] = 0
		data[i * 4 + 3] = 255
	return data


func put(c: Chunk, data: PackedByteArray) -> void:
	var n := Chunk.N
	var block := Image.create_from_data(n, n, false, Image.FORMAT_RGBA8, data)
	image.blit_rect(block, Rect2i(0, 0, n, n), Vector2i(posmod(c.ox, SIZE), posmod(c.oy, SIZE)))
	dirty = true


func flush() -> void:
	if dirty:
		texture.update(image)
		dirty = false
