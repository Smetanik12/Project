class_name NameGen
extends RefCounted
## Названия поселений по культурам и их формы для текстов («в деревне Берёзовка»).

var data: Dictionary = {}
var forms: Dictionary = {}
var used: Dictionary = {}
var rng := RandomNumberGenerator.new()


func _init(world_seed: int) -> void:
	rng.seed = world_seed * 31 + 7
	data = DataDB.place_names
	forms = DataDB.settlement_kinds.get("forms", {})


## Задаёт поселению имя и три формы. Учитывает вид, культуру и уже занятые имена.
func name_site(st: Site) -> void:
	var base := ""
	match st.kind:
		"capital", "city", "town":
			base = _pick_city(st.culture)
			_apply(st, base, st.noun, false)
		"village":
			base = _village_name()
			_apply(st, base, st.noun, true)
		"hamlet":
			base = _village_name()
			_apply(st, base, st.noun, true)
		"mine", "fort", "trench", "ruins", "camp", "hideout", "cave":
			var list: Array = data.get("quoted", {}).get(st.kind, ["Безымянный"])
			base = "«%s»" % _unique(list)
			_apply(st, base, st.noun, true)
		_:
			_apply(st, "Безымянное место", st.noun, false)


func _apply(st: Site, base: String, noun: String, noun_in_name: bool) -> void:
	var f: Array = forms.get(noun, ["в", "из", "у"])
	st.name = (U.cap(noun) + " " + base) if noun_in_name else base
	st.where = "%s %s" % [f[0], base]
	st.from = "%s %s" % [f[1], base]
	st.near = "%s %s" % [f[2], base]
	used[st.name] = true


func _pick_city(culture: String) -> String:
	var lists: Dictionary = data.get("cities", {})
	var list: Array = lists.get(culture, lists.get("free", []))
	var name := _unique(list)
	if name == "":
		name = _village_name().trim_suffix("ка") + "ск"
	return name


func _unique(list: Array) -> String:
	for i in 40:
		var n: String = list[rng.randi() % list.size()]
		if not used.has(n) and not used.has("«%s»" % n):
			used[n] = true
			return n
	# все заняты — добавляем номер
	var n2: String = "%s-%d" % [list[rng.randi() % list.size()], rng.randi_range(2, 99)]
	used[n2] = true
	return n2


func _village_name() -> String:
	for i in 60:
		var n := ""
		if rng.randf() < 0.72:
			var roots: Array = data["village_roots"]
			var suf: Array = data["village_suffix"]
			n = str(roots[rng.randi() % roots.size()]) + str(suf[rng.randi() % suf.size()])
		else:
			var pairs: Array = data["pairs_m"] if rng.randf() < 0.6 else data["pairs_f"]
			var p: Array = pairs[rng.randi() % pairs.size()]
			n = "%s %s" % [p[0], p[1]]
		if not used.has(n):
			used[n] = true
			return n
	return "Выселки-%d" % rng.randi_range(2, 999)
