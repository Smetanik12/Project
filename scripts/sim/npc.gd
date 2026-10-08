class_name NPC
extends RefCounted
## Житель мира. Характер (черты), потребности, память об игроке, знания о фактах.

const KNOWLEDGE_CAP := 40
const PLAYER := 0
const SAVE_KEYS := ["id", "first", "last", "female", "faction", "role", "home", "traits", "pos",
	"hp", "alive", "jailed", "money", "cargo", "hunger", "action", "action_until", "path",
	"target_pos", "target_settlement", "target_id", "follow_id", "engage_id", "trust", "fear",
	"met_player", "revealed", "memory", "grudges", "knowledge", "flatter_count", "bribed_day",
	"pending", "done"]

var id := 0
var first := ""
var last := ""
var female := false
var faction := ""
var role := ""
var home := ""
var traits: Array = []
var pos := Vector2i.ZERO
var prev_pos := Vector2i.ZERO
var hp := 100.0
var alive := true
var jailed := false
var money := 0
var cargo: Dictionary = {}
var hunger := 0.0
var action := "idle"
var action_until := 0
var path: Array = []
var target_pos := Vector2i.ZERO
var target_settlement := ""
var target_id := -1
## За кем идёт (0 — игрок).
var follow_id := -1
## С кем сейчас дерётся.
var engage_id := -1
var attack_cd := 0
## Отношение к игроку.
var trust := 0
var fear := 0
var met_player := false
var revealed := false
## Что помнит об игроке: [{"day": int, "key": String}]
var memory: Array = []
## Личные враги: id -> true
var grudges: Dictionary = {}
## fact_id -> {"acc": float, "day": int}
var knowledge: Dictionary = {}
var flatter_count := 0
var bribed_day := -100
## Незавершённая сделка в диалоге: {"type": "recruit", "price": 50}
var pending: Dictionary = {}
## Факты, по которым NPC уже действовал (например, ходил за кладом).
var done: Dictionary = {}


func full_name() -> String:
	return first + " " + last


func a() -> String:
	return U.a(female)


## Сумма модификаторов черт характера: courage, greed, honesty, talk, aggression, kindness,
## suspicion, vanity, loyalty.
func axis(stat: String) -> int:
	var total := 0
	for t in traits:
		total += int(DataDB.traits.get(t, {}).get(stat, 0))
	return total


func role_info() -> Dictionary:
	return DataDB.role_data(role)


func role_name() -> String:
	var titles: Dictionary = DataDB.factions.get(faction, {}).get("titles", {})
	if titles.has(role):
		return str(titles[role])
	if role == "slave" and faction == "":
		return "Беглая рабыня" if female else "Беглый раб"
	if female and role_info().has("name_f"):
		return str(role_info()["name_f"])
	return str(role_info().get("name", role))


func is_fighter() -> bool:
	if bool(role_info().get("fighter", false)):
		return true
	if axis("aggression") >= 30:
		return true
	return follow_id == PLAYER and float(role_info().get("combat", 0)) >= 4.0


func combat_power() -> float:
	var p := float(role_info().get("combat", 3))
	if int(cargo.get("weapons", 0)) > 0:
		p += 2.0
	p += axis("courage") / 40.0
	return p


func learn(fid: int, acc: float, day: int) -> bool:
	if knowledge.has(fid) and float(knowledge[fid]["acc"]) >= acc:
		return false
	knowledge[fid] = {"acc": acc, "day": day}
	if knowledge.size() > KNOWLEDGE_CAP:
		var oldest = null
		var oldest_day := 1 << 30
		for k in knowledge:
			var d: int = knowledge[k]["day"]
			if d < oldest_day:
				oldest_day = d
				oldest = k
		knowledge.erase(oldest)
	return true


func remember(day: int, key: String) -> void:
	memory.append({"day": day, "key": key})
	if memory.size() > 6:
		memory.pop_front()


func to_dict() -> Dictionary:
	var d := {}
	for k in SAVE_KEYS:
		d[k] = get(k)
	return d


static func from_dict(d: Dictionary) -> NPC:
	var n := NPC.new()
	for k in SAVE_KEYS:
		if d.has(k):
			n.set(k, d[k])
	n.prev_pos = n.pos
	return n
