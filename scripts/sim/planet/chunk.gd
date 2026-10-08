class_name Chunk
extends RefCounted
## Квадрат 32×32 тайла: высоты вершин, поверхность, вода, проходимость, деревья и постройки.
## Создаётся ChunkGen детерминированно из сида: один и тот же чанк всегда одинаковый.

const N := Planet.CHUNK
const NO_WATER := -10000.0

## Флаги тайла.
const F_ROAD := 1
const F_BRIDGE := 2
const F_SETTLE := 4
const F_SOLID := 8
const F_FIELD := 16
const F_TREE := 32
const F_SHORE := 64
const F_PAVED := 128
const F_PATH := 256
const F_TRENCH := 512
const F_WIRE := 1024
const F_INDOOR := 2048
const F_FURNITURE := 4096
const F_GATE := 8192
const F_PIER := 16384

var cx := 0
var cy := 0
var ox := 0
var oy := 0
## Высоты вершин (N+1)×(N+1), м.
var hgt := PackedFloat32Array()
var ground := PackedByteArray()
## Уровень воды по тайлам, NO_WATER — суша.
var water := PackedFloat32Array()
## Стоимость шага ×10, 0 — непроходимо.
var cost := PackedByteArray()
var flags := PackedInt32Array()
## Стены на гранях тайлов первого этажа (биты N=1, E=2, S=4, W=8, как в InteriorGen).
var walls := PackedByteArray()
## Все постройки, задевающие чанк: пары [Site, словарь постройки].
var structures: Array = []
## Постройки, чей угол лежит в этом чанке (их рисует этот чанк): пары [Site, постройка].
var own: Array = []
## Деревья: по 5 чисел (x, y в тайлах, масштаб, вид, поворот).
var trees := PackedFloat32Array()
## Мелочь без коллизий (трава, цветы, камешки, кусты): по 5 чисел.
var decor := PackedFloat32Array()
var has_water := false
var has_land := false
var min_h := 0.0
var max_h := 0.0


func li(tx: int, ty: int) -> int:
	return (ty - oy) * N + (tx - ox)


func vi(vx: int, vy: int) -> int:
	return vy * (N + 1) + vx


## Высота в точке (тайлы, мировые) — билинейно по вершинам, как у меша рельефа.
func height_at(x: float, y: float) -> float:
	var lx := clampf(x - ox, 0.0, N - 0.001)
	var ly := clampf(y - oy, 0.0, N - 0.001)
	var x0 := int(lx)
	var y0 := int(ly)
	var ax := lx - x0
	var ay := ly - y0
	var a := hgt[vi(x0, y0)]
	var b := hgt[vi(x0 + 1, y0)]
	var c := hgt[vi(x0, y0 + 1)]
	var d := hgt[vi(x0 + 1, y0 + 1)]
	return lerpf(lerpf(a, b, ax), lerpf(c, d, ax), ay)


func tile_height(tx: int, ty: int) -> float:
	var lx := tx - ox
	var ly := ty - oy
	return (hgt[vi(lx, ly)] + hgt[vi(lx + 1, ly)] + hgt[vi(lx, ly + 1)] + hgt[vi(lx + 1, ly + 1)]) * 0.25
