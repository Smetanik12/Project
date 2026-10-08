class_name PlayerState
extends RefCounted
## Состояние игрока в симуляции. Ввод и отрисовка — в scripts/game.

const SAVE_KEYS := ["name", "female", "pos", "hp", "money", "inv", "hunger", "faction", "flags",
	"knowledge", "journal", "known_people", "kills", "alive", "attack_tick"]

var name := ""
var female := false
## Позиция в тайлах, дробная (игрок ходит плавно).
var pos := Vector2.ZERO
var hp := 100.0
var money := 0
var inv: Dictionary = {}
var hunger := 0.0
var faction := ""
var flags: Dictionary = {}
var knowledge: Dictionary = {}
## [{"tick": int, "text": String}]
var journal: Array = []
var known_people: Dictionary = {}
var kills := 0
var alive := true
var attack_tick := -100


func tile() -> Vector2i:
	return Vector2i(floori(pos.x), floori(pos.y))


func a() -> String:
	return U.a(female)


func power() -> float:
	var p := 5.0
	if int(inv.get("weapons", 0)) > 0:
		p += 3.0
	return p + mini(kills, 10) * 0.2


func learn(fid: int, acc: float) -> bool:
	if knowledge.has(fid) and float(knowledge[fid]["acc"]) >= acc:
		return false
	knowledge[fid] = {"acc": acc}
	return true


func add_item(g: String, q: int) -> void:
	inv[g] = int(inv.get(g, 0)) + q
	if int(inv[g]) <= 0:
		inv.erase(g)


func to_dict() -> Dictionary:
	var d := {}
	for k in SAVE_KEYS:
		d[k] = get(k)
	return d


static func from_dict(d: Dictionary) -> PlayerState:
	var p := PlayerState.new()
	for k in SAVE_KEYS:
		if d.has(k):
			p.set(k, d[k])
	return p
