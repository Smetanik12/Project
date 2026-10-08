class_name Economy
extends RefCounted
## Производство, потребление, цены и торговые маршруты.
## Цена растёт, когда товара мало относительно потребности. Торговцы сами возят товар туда, где дороже.

const STOCK_CAP := 200.0


static func hourly(w: World) -> void:
	for s: Settlement in w.settlements.values():
		if s.kind == "wreck":
			continue
		for g in s.passive:
			add(s, g, float(s.passive[g]))
	for n: NPC in w.npcs.values():
		if not n.alive or n.jailed or n.action != "work":
			continue
		var s := w.settlement_at(n.pos)
		if s == null or s.id != n.home:
			continue
		var g := str(n.role_info().get("work", ""))
		var rate := float(n.role_info().get("rate", 0.1))
		if g == "weapons":
			if float(s.stock.get("metal", 0.0)) >= rate * 2.0:
				add(s, "metal", -rate * 2.0)
				add(s, "weapons", rate * 0.5)
		elif g != "":
			add(s, g, rate)


static func daily(w: World) -> void:
	for s: Settlement in w.settlements.values():
		if s.kind == "wreck":
			continue
		var res := w.residents(s.id)
		if res >= 3 and float(s.stock.get("food", 0.0)) < res * 0.5:
			var key := "famine_" + s.id
			if w.day() - int(w.flags.get(key, -10)) >= 3:
				w.flags[key] = w.day()
				w.add_fact("famine", s.center, {}, 2, s.radius + 4.0)


static func add(s: Settlement, g: String, q: float) -> void:
	s.stock[g] = clampf(float(s.stock.get(g, 0.0)) + q, 0.0, STOCK_CAP)


static func price(w: World, s: Settlement, g: String) -> float:
	var base := float(DataDB.goods[g]["base_price"])
	var target := 10.0
	if g == "food" or g == "water":
		target = maxf(4.0, w.residents(s.id) * 3.0)
	var st := float(s.stock.get(g, 0.0))
	return base * clampf(pow(target / (st + 1.0), 0.6), 0.35, 4.0)


## Лучшая сделка для торговца: что купить здесь и куда отвезти.
static func plan_trade(w: World, n: NPC) -> Dictionary:
	return plan_from(w, n, w.settlement_at(n.pos), 20.0)


## Если здесь покупать нечего — куда сходить порожняком, чтобы там была выгодная сделка.
static func plan_restock(w: World, n: NPC) -> String:
	var here := w.settlement_at(n.pos)
	if here == null:
		return ""
	var best := ""
	var best_profit := 40.0
	for s: Settlement in w.settlements.values():
		if s == here or s.kind == "wreck" or w.faction_hostile(n.faction, s.faction):
			continue
		var trip := Vector2(s.center - here.center).length() * 0.25
		var plan := plan_from(w, n, s, 0.0)
		if not plan.is_empty() and float(plan["profit"]) - trip > best_profit:
			best_profit = float(plan["profit"]) - trip
			best = s.id
	return best


static func plan_from(w: World, n: NPC, here: Settlement, min_profit: float) -> Dictionary:
	if here == null or here.kind == "wreck" or w.faction_hostile(n.faction, here.faction):
		return {}
	var best := {}
	var best_profit := min_profit
	for g in DataDB.good_ids():
		var have := float(here.stock.get(g, 0.0))
		if have < 6.0:
			continue
		var buy := price(w, here, g)
		var qty := mini(mini(25, int(have) - 3), int(n.money / buy))
		if qty < 3:
			continue
		for s: Settlement in w.settlements.values():
			if s == here or s.kind == "wreck" or w.faction_hostile(n.faction, s.faction):
				continue
			var dist := Vector2(s.center - here.center).length()
			var profit := (price(w, s, g) * 0.9 - buy) * qty - dist * 0.25
			if profit > best_profit:
				best_profit = profit
				best = {"good": g, "dst": s.id, "qty": qty, "buy": buy, "profit": profit}
	return best


static func buy_for_trip(w: World, n: NPC, plan: Dictionary) -> void:
	var here := w.settlement_at(n.pos)
	var g: String = plan["good"]
	var qty: int = plan["qty"]
	add(here, g, -qty)
	n.money -= int(float(plan["buy"]) * qty)
	n.cargo[g] = int(n.cargo.get(g, 0)) + qty


static func sell_cargo(w: World, n: NPC) -> void:
	var s := w.settlement_at(n.pos)
	if s == null:
		return
	var sold := []
	for g in n.cargo.keys():
		var q := int(n.cargo[g])
		if g == "food":
			q -= 2  # себе на дорогу
		if q <= 0 or (g == "weapons" and n.is_fighter()):
			continue
		n.money += int(price(w, s, g) * 0.9 * q)
		add(s, g, q)
		n.cargo[g] = int(n.cargo[g]) - q
		sold.append(g)
	if not sold.is_empty() and w.rng.randf() < 0.35:
		w.add_fact("trade", n.pos, {"merchant": n.full_name(), "merchant_f": n.female, "good": sold[0]}, 1, 6.0)
