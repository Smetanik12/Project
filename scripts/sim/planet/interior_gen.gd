class_name InteriorGen
extends RefCounted
## Внутренности зданий: комнаты, внутренние стены и двери (по граням тайлов), окна, лестница,
## мебель. В любой дом можно зайти. Стены лежат на гранях тайлов, поэтому их можно рушить
## по одной (взрыв, огонь, таран), а внутри остаётся полноценная площадь.
##
## Грани тайла — биты: N=1 (верх, -y), E=2 (+x), S=4 (+y), W=8 (-x).
## План этажа (кэшируется в постройке, ключ "bp0" для первого этажа):
##   walls     Dictionary Vector2i -> int (биты стен тайла)
##   doors     Dictionary Vector2i -> int (биты дверей тайла: проём в стене)
##   windows   Dictionary Vector2i -> int (биты окон на внешних стенах)
##   rooms     Array [{"r": Rect2i, "kind": String}]
##   furniture Array [{"t": String, "p": Vector2i, "rot": int, "block": bool}]
##   stairs    Vector2i или (-1, -1)

const N := 1
const E := 2
const S := 4
const W := 8
const DIRS := {N: Vector2i(0, -1), E: Vector2i(1, 0), S: Vector2i(0, 1), W: Vector2i(-1, 0)}
const OPP := {N: S, S: N, E: W, W: E}

## Здания, в которые можно войти (у остальных — сплошной объём: вышки, отвалы, стены).
const ENTERABLE := ["house", "granary", "tavern", "smithy", "hall", "clinic", "workshop", "chapel", "barn",
	"woodyard", "warehouse", "barracks", "messhall", "hq", "armory", "bunker", "shack", "scrapyard", "tent",
	"apartment", "shopfront", "skyscraper", "factory", "palace", "city_hall", "school", "police", "hospital",
	"bank", "temple", "hotel", "bar", "fire_station", "prison", "power_plant", "water_works", "comm_center",
	"depot", "garrison", "theater", "guild_hall", "market_hall", "mine_entrance", "cave_mouth"]

## Комнаты по виду здания: первая — «главная» (с входом).
const ROOMS := {
	"house": ["living", "kitchen", "bedroom", "bedroom", "storage"],
	"shack": ["living", "bedroom"],
	"tent": ["bedroom"],
	"tavern": ["hall", "kitchen", "storage", "bedroom"],
	"bar": ["hall", "storage"],
	"smithy": ["forge", "storage"],
	"workshop": ["workroom", "storage"],
	"granary": ["storage"],
	"barn": ["stable", "storage"],
	"woodyard": ["storage"],
	"warehouse": ["storage", "office"],
	"depot": ["storage", "storage", "office"],
	"scrapyard": ["storage", "workroom"],
	"barracks": ["dorm", "dorm", "armory_room"],
	"messhall": ["hall", "kitchen"],
	"hq": ["office", "command", "radio", "bedroom"],
	"armory": ["armory_room", "storage"],
	"bunker": ["dorm"],
	"clinic": ["ward", "office", "storage"],
	"hospital": ["hall", "ward", "ward", "office", "surgery"],
	"hall": ["hall", "office", "bedroom"],
	"city_hall": ["hall", "office", "office", "council", "archive"],
	"palace": ["throne", "hall", "office", "office", "council", "archive", "bedroom"],
	"chapel": ["nave"],
	"temple": ["nave", "office"],
	"school": ["classroom", "classroom", "office"],
	"police": ["office", "cells", "armory_room"],
	"prison": ["cells", "cells", "office", "hall"],
	"bank": ["hall", "vault", "office"],
	"hotel": ["hall", "bedroom", "bedroom", "bedroom"],
	"theater": ["nave", "storage"],
	"guild_hall": ["hall", "office", "council", "vault"],
	"market_hall": ["shop_floor"],
	"shopfront": ["shop_floor", "storage"],
	"apartment": ["hall", "living", "bedroom", "kitchen"],
	"skyscraper": ["hall", "shop_floor", "office"],
	"factory": ["workroom", "storage", "office"],
	"power_plant": ["machine", "office"],
	"water_works": ["machine", "office"],
	"comm_center": ["radio", "office", "machine"],
	"fire_station": ["garage", "dorm"],
	"garrison": ["dorm", "armory_room", "office"],
	"mine_entrance": ["tunnel"],
	"cave_mouth": ["tunnel"],
}

## Мебель по комнатам: [вид, у стены?, блокирует проход?]
const FURNITURE := {
	"living": [["table", false, true], ["chair", false, false], ["chair", false, false], ["shelf", true, true], ["rug", false, false]],
	"kitchen": [["stove", true, true], ["table", false, true], ["barrel", true, true], ["shelf", true, true]],
	"bedroom": [["bed", true, true], ["bed", true, true], ["chest", true, true], ["rug", false, false]],
	"storage": [["crate", true, true], ["crate", true, true], ["barrel", true, true], ["sack", true, true], ["shelf", true, true]],
	"hall": [["table", false, true], ["table", false, true], ["bench", false, false], ["bench", false, false], ["counter", true, true]],
	"forge": [["forge", true, true], ["anvil", false, true], ["rack", true, true]],
	"workroom": [["workbench", true, true], ["workbench", true, true], ["shelf", true, true]],
	"stable": [["hay", true, true], ["trough", true, true]],
	"office": [["desk", true, true], ["chair", false, false], ["shelf", true, true], ["cabinet", true, true]],
	"dorm": [["bunk", true, true], ["bunk", true, true], ["bunk", true, true], ["locker", true, true]],
	"armory_room": [["rack", true, true], ["rack", true, true], ["crate", true, true]],
	"command": [["map_table", false, true], ["radio", true, true], ["chair", false, false]],
	"radio": [["radio", true, true], ["console", true, true], ["chair", false, false]],
	"ward": [["bed", true, true], ["bed", true, true], ["bed", true, true], ["cabinet", true, true]],
	"surgery": [["op_table", false, true], ["cabinet", true, true]],
	"council": [["long_table", false, true], ["chair", false, false], ["chair", false, false], ["banner", true, false]],
	"archive": [["shelf", true, true], ["shelf", true, true], ["shelf", true, true]],
	"throne": [["throne", true, true], ["banner", true, false], ["banner", true, false], ["rug", false, false]],
	"nave": [["altar", true, true], ["bench", false, false], ["bench", false, false], ["bench", false, false]],
	"classroom": [["desk", false, true], ["desk", false, true], ["board", true, false]],
	"cells": [["cot", true, true], ["bucket", true, false]],
	"vault": [["safe", true, true], ["safe", true, true], ["crate", true, true]],
	"shop_floor": [["counter", true, true], ["shelf", true, true], ["shelf", true, true], ["crate", true, true]],
	"machine": [["generator", false, true], ["console", true, true], ["pipe", true, true]],
	"garage": [["vehicle", false, true], ["rack", true, true]],
	"tunnel": [["crate", true, true], ["lamp", true, false]],
}


static func enterable(s: Dictionary) -> bool:
	return str(s["t"]) in ENTERABLE


## План первого этажа (с кэшем в постройке). mutex — чей кэш защищать (мьютекс поселения).
static func ground_floor(s: Dictionary, mutex: Mutex) -> Dictionary:
	mutex.lock()
	var bp: Dictionary = s.get("bp0", {})
	mutex.unlock()
	if not bp.is_empty():
		return bp
	bp = _plan(s, 0)
	mutex.lock()
	if s.has("bp0"):
		bp = s["bp0"]
	else:
		s["bp0"] = bp
	mutex.unlock()
	return bp


static func _plan(s: Dictionary, floor_i: int) -> Dictionary:
	var r: Rect2i = s["r"]
	var rng := RandomNumberGenerator.new()
	rng.seed = U.hash3(int(s.get("id", 0)), int(s["v"]), floor_i + r.position.x * 7 + r.position.y * 13)
	var walls := {}
	var doors := {}
	var windows := {}
	# внешние стены по периметру
	for x in range(r.position.x, r.end.x):
		_add(walls, Vector2i(x, r.position.y), N)
		_add(walls, Vector2i(x, r.end.y - 1), S)
	for y in range(r.position.y, r.end.y):
		_add(walls, Vector2i(r.position.x, y), W)
		_add(walls, Vector2i(r.end.x - 1, y), E)
	# вход: грань между тайлом у двери (внутри) и дверью снаружи
	var face: int = s["face"]
	var door_out: Vector2i = s["door"]
	var entry := Vector2i(-1, -1)
	if floor_i == 0 and door_out.x >= 0:
		var inward: Vector2i = [Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(1, 0)][face]
		entry = door_out + inward
		if r.has_point(entry):
			var bit: int = [S, E, N, W][face]
			_open(walls, doors, entry, bit)
	# комнаты: делим площадь по очереди (BSP), каждая перегородка с проёмом-дверью
	var kinds: Array = ROOMS.get(str(s["t"]), ["hall"])
	var rooms: Array = [r]
	var target := clampi(kinds.size(), 1, maxi(1, r.get_area() / 6))
	var guard := 0
	while rooms.size() < target and guard < 20:
		guard += 1
		# режем самую большую комнату
		var bi := 0
		for k in rooms.size():
			if (rooms[k] as Rect2i).get_area() > (rooms[bi] as Rect2i).get_area():
				bi = k
		var room: Rect2i = rooms[bi]
		var along_x := room.size.x >= room.size.y
		var long := room.size.x if along_x else room.size.y
		if long < 4:
			break
		var cut := clampi(int(long * rng.randf_range(0.4, 0.6)), 2, long - 2)
		var a: Rect2i
		var b: Rect2i
		if along_x:
			a = Rect2i(room.position, Vector2i(cut, room.size.y))
			b = Rect2i(room.position + Vector2i(cut, 0), Vector2i(room.size.x - cut, room.size.y))
			for y in range(room.position.y, room.end.y):
				_add(walls, Vector2i(a.end.x - 1, y), E)
				_add(walls, Vector2i(b.position.x, y), W)
			# дверь в перегородке
			var dy := rng.randi_range(room.position.y, room.end.y - 1)
			_open(walls, doors, Vector2i(a.end.x - 1, dy), E)
		else:
			a = Rect2i(room.position, Vector2i(room.size.x, cut))
			b = Rect2i(room.position + Vector2i(0, cut), Vector2i(room.size.x, room.size.y - cut))
			for x in range(room.position.x, room.end.x):
				_add(walls, Vector2i(x, a.end.y - 1), S)
				_add(walls, Vector2i(x, b.position.y), N)
			var dx := rng.randi_range(room.position.x, room.end.x - 1)
			_open(walls, doors, Vector2i(dx, a.end.y - 1), S)
		rooms[bi] = a
		rooms.append(b)
	# главная комната — та, где вход
	var plan_rooms: Array = []
	var main := 0
	for k in rooms.size():
		if entry.x >= 0 and (rooms[k] as Rect2i).has_point(entry):
			main = k
	for k in rooms.size():
		var ki := 0 if k == main else (k + (1 if k < main else 0))
		plan_rooms.append({"r": rooms[k], "kind": kinds[mini(ki, kinds.size() - 1)]})
	# окна на внешних стенах, через тайл, не на двери
	for x in range(r.position.x + 1, r.end.x - 1, 2):
		_add_if_wall(windows, walls, Vector2i(x, r.position.y), N)
		_add_if_wall(windows, walls, Vector2i(x, r.end.y - 1), S)
	for y in range(r.position.y + 1, r.end.y - 1, 2):
		_add_if_wall(windows, walls, Vector2i(r.position.x, y), W)
		_add_if_wall(windows, walls, Vector2i(r.end.x - 1, y), E)
	var stairs := Vector2i(-1, -1)
	if int(s["fl"]) > 1 and r.get_area() >= 9:
		stairs = _stairs_spot(plan_rooms, walls, doors, entry)
	var furniture := _furnish(plan_rooms, walls, doors, entry, stairs, rng)
	return {"walls": walls, "doors": doors, "windows": windows, "rooms": plan_rooms, "furniture": furniture,
		"stairs": stairs, "entry": entry}


static func _add(d: Dictionary, t: Vector2i, bit: int) -> void:
	d[t] = int(d.get(t, 0)) | bit


static func _add_if_wall(win: Dictionary, walls: Dictionary, t: Vector2i, bit: int) -> void:
	if int(walls.get(t, 0)) & bit:
		_add(win, t, bit)


## Проём в стене: убираем стену с обеих сторон грани, отмечаем дверь.
static func _open(walls: Dictionary, doors: Dictionary, t: Vector2i, bit: int) -> void:
	walls[t] = int(walls.get(t, 0)) & ~bit
	_add(doors, t, bit)
	var o: Vector2i = t + DIRS[bit]
	var ob: int = OPP[bit]
	if walls.has(o):
		walls[o] = int(walls[o]) & ~ob
		_add(doors, o, ob)


static func blocked(walls: Dictionary, t: Vector2i, bit: int) -> bool:
	return (int(walls.get(t, 0)) & bit) != 0


## Лестница — в углу дальней от входа комнаты.
static func _stairs_spot(rooms: Array, walls: Dictionary, doors: Dictionary, entry: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_d := -1.0
	for rm: Dictionary in rooms:
		var r: Rect2i = rm["r"]
		if r.get_area() < 4:
			continue
		for c: Vector2i in [r.position, Vector2i(r.end.x - 1, r.position.y), Vector2i(r.position.x, r.end.y - 1), r.end - Vector2i.ONE]:
			if doors.has(c) or c == entry:
				continue
			var d := Vector2(c).distance_to(Vector2(entry))
			if d > best_d:
				best_d = d
				best = c
	return best


## Мебель по комнатам. После расстановки — проверка: все свободные клетки достижимы от входа,
## иначе мешающая мебель убирается. Поэтому в доме никогда не бывает отрезанных углов.
static func _furnish(rooms: Array, walls: Dictionary, doors: Dictionary, entry: Vector2i, stairs: Vector2i,
		rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var taken := {}
	if stairs.x >= 0:
		taken[stairs] = true
	for rm: Dictionary in rooms:
		var r: Rect2i = rm["r"]
		var list: Array = FURNITURE.get(str(rm["kind"]), [])
		for item: Array in list:
			for attempt in 8:
				var t := Vector2i(rng.randi_range(r.position.x, r.end.x - 1), rng.randi_range(r.position.y, r.end.y - 1))
				if taken.has(t) or doors.has(t) or t == entry:
					continue
				var near_door := false
				for bit in [N, E, S, W]:
					if doors.has(t + DIRS[bit]):
						near_door = true
				if near_door and bool(item[2]):
					continue
				var w := int(walls.get(t, 0))
				if bool(item[1]) and w == 0:
					continue
				var rot := 0
				for bit in [S, W, N, E]:
					if w & bit:
						rot = [N, E, S, W].find(bit)
				taken[t] = true
				out.append({"t": item[0], "p": t, "rot": rot, "block": bool(item[2])})
				break
	# проверка связности
	var guard := 0
	while guard < 30:
		guard += 1
		var cut := _isolating(rooms, walls, out, entry)
		if cut < 0:
			break
		out.remove_at(cut)
	return out


## Индекс мебели, которая отрезает часть дома от входа, или -1.
static func _isolating(rooms: Array, walls: Dictionary, furn: Array, entry: Vector2i) -> int:
	var blocked_t := {}
	for k in furn.size():
		if furn[k]["block"]:
			blocked_t[furn[k]["p"]] = k
	var cells := {}
	for rm: Dictionary in rooms:
		var r: Rect2i = rm["r"]
		for y in range(r.position.y, r.end.y):
			for x in range(r.position.x, r.end.x):
				cells[Vector2i(x, y)] = true
	var start := entry
	if not cells.has(start) or blocked_t.has(start):
		for c in cells:
			if not blocked_t.has(c):
				start = c
				break
	var seen := {start: true}
	var q: Array = [start]
	while not q.is_empty():
		var c: Vector2i = q.pop_back()
		for bit in [N, E, S, W]:
			if blocked(walls, c, bit):
				continue
			var nb: Vector2i = c + DIRS[bit]
			if cells.has(nb) and not seen.has(nb) and not blocked_t.has(nb):
				seen[nb] = true
				q.append(nb)
	for c in cells:
		if seen.has(c) or blocked_t.has(c):
			continue
		# недостижимая свободная клетка: убираем ближайшую мешающую мебель
		var best := -1
		var best_d := INF
		for k in furn.size():
			if furn[k]["block"]:
				var d := Vector2(furn[k]["p"]).distance_to(Vector2(c))
				if d < best_d:
					best_d = d
					best = k
		return best
	return -1
