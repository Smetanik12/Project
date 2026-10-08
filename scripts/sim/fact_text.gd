class_name FactText
extends RefCounted
## Превращает факт в фразу. Чем ниже точность слуха, тем сильнее он искажён:
## путаются виновники, места и цифры. Так слухи «портятся», пока идут от человека к человеку.

const FACTION_KEYS := ["attacker", "defender", "prev", "spy_for", "issuer", "faction"]
const NAME_KEYS := ["victim", "killer", "who", "merchant", "general", "target"]


static func describe(w: World, f: Fact, acc := 1.0) -> String:
	var d := f.data.duplicate()
	var r := RandomNumberGenerator.new()
	r.seed = hash(str(f.id) + ":" + str(snappedf(acc, 0.1)))
	if acc < 0.6:
		_distort(w, d, r, acc)
	var key := "fact." + f.type
	if f.type == "raid_village" and str(d.get("victim", "")) != "":
		key = "fact.raid_village_kidnap"
	return DataDB.phrase(key, r, _vars(w, d))


static func _vars(w: World, d: Dictionary) -> Dictionary:
	var v := {}
	for k in FACTION_KEYS:
		if d.has(k) and w.factions.has(d[k]):
			var f: Faction = w.factions[d[k]]
			v[k] = f.members()
			v[k + "_cap"] = U.cap(f.members())
			v[k + "_gen"] = f.gen()
	for k in NAME_KEYS:
		if d.has(k):
			v[k] = str(d[k])
			var female := bool(d.get(k + "_f", false))
			v[k + "_a"] = U.a(female)
			v[k + "_la"] = U.la(female)
	var where := str(d.get("where", ""))
	v["where"] = where
	v["where_cap"] = U.cap(where)
	if w.settlements.has(d.get("place", "")):
		var s: Settlement = w.settlements[d["place"]]
		v["from"] = s.from
		v["place_name"] = s.name
		v["place_cap"] = U.cap(s.name)
	if d.has("good"):
		v["good"] = DataDB.good_name(str(d["good"])).to_lower()
	if d.has("amount"):
		v["amount"] = str(d["amount"])
	return v


static func _distort(w: World, d: Dictionary, r: RandomNumberGenerator, acc: float) -> void:
	var fids := w.factions.keys()
	if d.has("attacker") and r.randf() < 0.6:
		d["attacker"] = fids[r.randi() % fids.size()]
	if d.has("killer") and r.randf() < 0.5:
		var f: Faction = w.factions[fids[r.randi() % fids.size()]]
		d["killer"] = "кто-то из людей " + f.gen()
	if d.has("amount"):
		d["amount"] = int(d["amount"]) * r.randi_range(2, 5)
	if acc < 0.4 and r.randf() < 0.6:
		var sids := w.settlements.keys()
		var s: Settlement = w.settlements[sids[r.randi() % sids.size()]]
		d["where"] = s.near
		d["place"] = s.id
