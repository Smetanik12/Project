class_name MapData
extends RefCounted
## Сетка тайлов, дороги и поиск пути. Только данные, без графики.

enum T { WATER, SAND, GRASS, DIRT, ASH, ROCK, MOUNTAIN, FLOOR }
const PASSABLE := [false, true, true, true, true, true, false, true]
const MOVE_COST := [1.0, 1.4, 1.0, 1.0, 1.2, 1.6, 1.0, 1.0]

var w := 0
var h := 0
var tiles := PackedByteArray()
var road := PackedByteArray()
var astar: AStarGrid2D


func _init(width := 0, height := 0) -> void:
	w = width
	h = height
	tiles.resize(w * h)
	road.resize(w * h)


func idx(p: Vector2i) -> int:
	return p.y * w + p.x


func in_bounds(p: Vector2i) -> bool:
	return p.x >= 0 and p.y >= 0 and p.x < w and p.y < h


func get_t(p: Vector2i) -> int:
	return tiles[idx(p)]


func set_t(p: Vector2i, t: int) -> void:
	tiles[idx(p)] = t


func is_road(p: Vector2i) -> bool:
	return road[idx(p)] == 1


func is_passable(p: Vector2i) -> bool:
	if not in_bounds(p):
		return false
	var i := idx(p)
	return PASSABLE[tiles[i]] or road[i] == 1


func build_astar() -> void:
	astar = AStarGrid2D.new()
	astar.region = Rect2i(0, 0, w, h)
	astar.cell_size = Vector2(1, 1)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	for y in h:
		for x in w:
			var p := Vector2i(x, y)
			if not is_passable(p):
				astar.set_point_solid(p, true)
			elif is_road(p):
				astar.set_point_weight_scale(p, 0.6)
			else:
				astar.set_point_weight_scale(p, MOVE_COST[get_t(p)])


## Путь по тайлам (без стартовой клетки). Пустой массив — пути нет или уже на месте.
func find_path(from: Vector2i, to: Vector2i) -> Array:
	var out: Array = []
	if from == to:
		return out
	if not is_passable(to):
		to = nearest_passable(to)
	if not is_passable(from) or not is_passable(to):
		return out
	out.assign(astar.get_id_path(from, to))
	if not out.is_empty() and out[0] == from:
		out.pop_front()
	return out


func nearest_passable(p: Vector2i, max_r := 8) -> Vector2i:
	if is_passable(p):
		return p
	for r in range(1, max_r + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var q := p + Vector2i(dx, dy)
				if is_passable(q):
					return q
	return p


func to_dict() -> Dictionary:
	return {"w": w, "h": h, "tiles": tiles, "road": road}


static func from_dict(d: Dictionary) -> MapData:
	var m := MapData.new(int(d["w"]), int(d["h"]))
	m.tiles = d["tiles"]
	m.road = d["road"]
	m.build_astar()
	return m
