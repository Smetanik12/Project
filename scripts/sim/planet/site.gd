class_name Site
extends RefCounted
## Поселение на планете. Статичная часть (место, размер, планировка) выводится из сида планеты,
## изменчивая (хозяин, население по профессиям, склад, деньги) — состояние мира и сохраняется.
## Планировка (дома, стены, поля, причалы) генерируется лениво: у малых поселений целиком,
## у городов — по кварталам вокруг игрока (LayoutGen).

const SAVE_KEYS := ["id", "faction", "pops", "stock", "money", "flags", "lootable"]

var id := ""
var name := ""
## Формы названия для текстов: «в деревне Родник», «из деревни Родник», «у деревни Родник».
var where := ""
var from := ""
var near := ""
## capital, city, town, village, hamlet, mine, fort, camp, hideout, ruins, trench, wreck
var kind := ""
var noun := ""
## Культура названий и архитектуры (фракция-основатель).
var culture := ""
var faction := ""
## Уровень техники: 0 племя … 4 столица империи.
var tech := 1
var center := Vector2i.ZERO
var radius := 20
## Радиус застройки (дальше — поля и выпасы).
var core := 10
## Высота выровненной площадки (м).
var base_h := 0.0
var site_seed := 0
var coastal := false
var river := false
var landmark := false
## Куда смотрит (окопы — на врага, причалы — к воде).
var dir := Vector2.DOWN
## Население на момент генерации.
var pop0 := 0

# --- изменчивое ---
## Профессия -> число людей.
var pops: Dictionary = {}
## Товар -> количество.
var stock: Dictionary = {}
var money := 0.0
var flags: Dictionary = {}
var lootable := false

# --- кэш планировки ---
var layout: Array = []
var layout_ready := false
var blocks: Dictionary = {}
## Планы этажей зданий: Vector3i(x, y, этаж) -> план (InteriorGen).
var plans: Dictionary = {}
var mutex := Mutex.new()


func population() -> int:
	var total := 0
	for r in pops:
		total += int(pops[r])
	return total


func is_city() -> bool:
	return kind == "capital" or kind == "city" or kind == "town"


func contains(p: Vector2) -> bool:
	return (p - Vector2(center)).length() <= radius


func kind_desc() -> String:
	return str(DataDB.settlement_kinds.get("desc", {}).get(kind, noun))


func to_dict() -> Dictionary:
	var d := {}
	for k in SAVE_KEYS:
		d[k] = get(k)
	return d


func apply_dict(d: Dictionary) -> void:
	for k in SAVE_KEYS:
		if d.has(k):
			set(k, d[k])
