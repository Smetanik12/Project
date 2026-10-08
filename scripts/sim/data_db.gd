class_name DataDB
extends RefCounted
## Игровые данные из res://data/*.json.
## Новый контент (фразы, черты, роли, поселения) добавляется правкой JSON, без кода.

static var goods: Dictionary = {}
static var traits: Dictionary = {}
static var roles: Dictionary = {}
static var names: Dictionary = {}
static var phrases: Dictionary = {}
static var factions: Dictionary = {}
static var settlements: Dictionary = {}
static var _loaded := false


static func ensure_loaded() -> void:
	if _loaded:
		return
	goods = _load("goods")
	traits = _load("traits")
	roles = _load("roles")
	names = _load("names")
	phrases = _load("phrases")
	factions = _load("factions")
	settlements = _load("settlements")
	_loaded = true


static func _load(file: String) -> Dictionary:
	var path := "res://data/%s.json" % file
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Не удалось открыть " + path)
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Ошибка в JSON: " + path)
		return {}
	return parsed


## Случайная фраза по ключу из phrases.json с подстановкой {переменных}.
static func phrase(key: String, rng: RandomNumberGenerator, vars: Dictionary = {}) -> String:
	var list: Array = phrases.get(key, [])
	if list.is_empty():
		push_warning("Нет фраз для ключа " + key)
		return ""
	var s: String = list[rng.randi() % list.size()]
	return s.format(vars)


static func good_ids() -> Array:
	return goods.keys()


static func good_name(g: String) -> String:
	return str(goods.get(g, {}).get("name", g))


static func role_data(role: String) -> Dictionary:
	return roles.get(role, {})


static func faction_ids() -> Array:
	var out := []
	for k in factions.keys():
		if not str(k).begins_with("_"):
			out.append(k)
	return out
