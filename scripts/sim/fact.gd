class_name Fact
extends RefCounted
## Факт о событии в мире. NPC узнают факты (свидетели или слухи), фракции на них реагируют.
## Ложь игрока — тоже факт, только truth = false.

const SAVE_KEYS := ["id", "type", "day", "tick", "pos", "data", "truth", "importance", "origin"]

var id := 0
var type := ""
var day := 0
var tick := 0
var pos := Vector2i.ZERO
var data: Dictionary = {}
var truth := true
## 1 — бытовое, 2 — важное, 3 — громкое
var importance := 1
## "player", если это выдумка игрока
var origin := ""


func to_dict() -> Dictionary:
	var d := {}
	for k in SAVE_KEYS:
		d[k] = get(k)
	return d


static func from_dict(d: Dictionary) -> Fact:
	var f := Fact.new()
	for k in SAVE_KEYS:
		if d.has(k):
			f.set(k, d[k])
	return f
