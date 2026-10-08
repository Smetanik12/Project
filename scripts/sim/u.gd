class_name U
extends RefCounted
## Мелкие помощники для текста на русском.

const DIRS := ["восток", "юго-восток", "юг", "юго-запад", "запад", "северо-запад", "север", "северо-восток"]


static func cap(s: String) -> String:
	if s.is_empty():
		return s
	return s.substr(0, 1).to_upper() + s.substr(1)


static func low(s: String) -> String:
	if s.is_empty():
		return s
	return s.substr(0, 1).to_lower() + s.substr(1)


## Окончание глагола прошедшего времени: «сказал» / «сказала».
static func a(female: bool) -> String:
	return "а" if female else ""


## «умер» / «умерла».
static func la(female: bool) -> String:
	return "ла" if female else ""


static func female_surname(s: String) -> String:
	if s.ends_with("ов") or s.ends_with("ев") or s.ends_with("ин"):
		return s + "а"
	if s.ends_with("ый") or s.ends_with("ий"):
		return s.substr(0, s.length() - 2) + "ая"
	return s


## Направление по сторонам света (y растёт вниз = юг).
static func direction(from: Vector2i, to: Vector2i) -> String:
	var v := Vector2(to - from)
	if v.length() < 1.0:
		return "здесь"
	var i := int(round(v.angle() / (PI / 4.0))) % 8
	if i < 0:
		i += 8
	return DIRS[i]


## Целочисленный хэш (детерминированный, без знака): для генерации без общего RandomNumberGenerator.
static func ihash(x: int) -> int:
	x = ((x >> 16) ^ x) * 0x45d9f3b
	x = ((x >> 16) ^ x) * 0x45d9f3b
	x = (x >> 16) ^ x
	return x & 0x7fffffff


static func hash3(a: int, b: int, c: int) -> int:
	return ihash(a * 73856093 ^ ihash(b * 19349663 ^ c * 83492791))


## Случайное число 0..1 из трёх целых.
static func rnd3(a: int, b: int, c: int) -> float:
	return float(hash3(a, b, c) % 1000003) / 1000003.0


## Путь для файла вывода (скриншот, карта): относительный — от папки проекта, недостающие
## папки создаются. Работает и с путями Windows (C:\...).
static func out_path(path: String) -> String:
	var p := path.replace("\\", "/")
	if p.is_relative_path():
		p = "res://" + p
	p = ProjectSettings.globalize_path(p)
	DirAccess.make_dir_recursive_absolute(p.get_base_dir())
	return p
