class_name Faction
extends RefCounted
## Фракция: отношения, репутация игрока, награды за головы, известные ей факты.
## Тексты и цвет берутся из data/factions.json.

const SAVE_KEYS := ["id", "relations", "player_rep", "bounties", "known_facts", "wealth", "capital", "defeated"]
const HOSTILE := -50

var id := ""
var relations: Dictionary = {}
var player_rep := 0
## "player" или id NPC (int) -> сумма награды
var bounties: Dictionary = {}
var known_facts: Dictionary = {}
var wealth := 100
var capital := ""
var defeated := false


func info() -> Dictionary:
	return DataDB.factions.get(id, {})


func title() -> String:
	return str(info().get("name", id))


func short() -> String:
	return str(info().get("short", id))


func gen() -> String:
	return str(info().get("gen", id))


func members() -> String:
	return str(info().get("members", id))


func color() -> Color:
	var c: Array = info().get("color", [0.7, 0.7, 0.7])
	return Color(c[0], c[1], c[2])


func rel(other: String) -> int:
	if other == id:
		return 100
	return int(relations.get(other, 0))


func to_dict() -> Dictionary:
	var d := {}
	for k in SAVE_KEYS:
		d[k] = get(k)
	return d


static func from_dict(d: Dictionary) -> Faction:
	var f := Faction.new()
	for k in SAVE_KEYS:
		if d.has(k):
			f.set(k, d[k])
	return f
