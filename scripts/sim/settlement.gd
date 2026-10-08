class_name Settlement
extends RefCounted
## Поселение: владелец, склад товаров, производство. Обломки корабля — тоже «поселение» без владельца.

const SAVE_KEYS := ["id", "name", "where", "from", "near", "kind", "faction", "center", "radius",
	"stock", "passive", "buildings", "lootable"]

var id := ""
var name := ""
## Формы названия для текстов: «в деревне Родник», «из деревни Родник», «у деревни Родник».
var where := ""
var from := ""
var near := ""
var kind := ""
var faction := ""
var center := Vector2i.ZERO
var radius := 4
var stock: Dictionary = {}
## Пассивное производство в час: good -> float
var passive: Dictionary = {}
## Для отрисовки: [{"t": "house", "r": Rect2i}]
var buildings: Array = []
var lootable := false


func contains(p: Vector2i) -> bool:
	return (p - center).length_squared() <= radius * radius


func kind_desc() -> String:
	return str(DataDB.settlements.get("kinds", {}).get(kind, kind))


func to_dict() -> Dictionary:
	var d := {}
	for k in SAVE_KEYS:
		d[k] = get(k)
	return d


static func from_dict(d: Dictionary) -> Settlement:
	var s := Settlement.new()
	for k in SAVE_KEYS:
		if d.has(k):
			s.set(k, d[k])
	return s
