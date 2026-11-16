extends RefCounted
## T055 生活訂單：每日可派發訂單與材料來源閘門（純函式輔助；World 的
## order / order_accept / order_cancel 與 World.order_board 使用）。
##
## Plan source (outputs/糰糰島_完整遊戲規劃書.html, 任務與訂單段):
##   「生活訂單每個遊戲日更新少量候選，玩家接單後給 3 個遊戲日完成；沒有完成只
##    取消，不扣錢。世界暫停時期限也暫停。若朋友持續在線導致訂單過期，原料留在
##    背包，不造成失去物品。」
##   Economy table: 居民訂單 = 每日有限訂單，獎金不無限重複。
## T055 acceptance (docs/plan-completion-ledger.md): 不派發無法取得的材料要求.
##
## Purity: no IO, no randomness, no wall clock, never preloads World, never
## mutates its arguments. Every "book" helper returns a NEW dictionary; the
## caller (World._apply) decides whether to commit it. Only Village (static
## ORDERS data) and Weather (calendar math) are preloaded.
##
## ----------------------------------------------------------------------------
## ORDER IDS ARE STABLE. Definitions are read from Village.ORDERS ("radish",
## "fish", "bread"); this file never renames, re-prices or duplicates them, so
## saved player.orders.done lists and client wire IDs stay valid. New orders
## are added to Village.ORDERS AND to ORDER_NOTES/SOURCES below; an order whose
## items have no SOURCES entry is fail-closed (never dispatched), see
## validate_catalog() for the test hook.
## ----------------------------------------------------------------------------
##
## INTEGRATION CONTRACT (for the World / UI owner; not wired by this file)
##
## 1. Context. Build once per request, at home, inside World._apply:
##        var ctx := OrderCatalog.context_from_world(self, token)
##    or construct it by hand with the same keys (see context_from_world).
##    Materials gating reads ONLY ctx, so tests can pass synthetic contexts.
##
## 2. Player book. player.orders keeps its legacy keys and gains one:
##        {"day":int, "done":[id...], "active":{id:{"accepted":float, "due":float}}}
##    normalize_book(player.orders, now) migrates the legacy {"day","done"}
##    shape (and the ensure_player default {"day":-1,"done":[]}) without
##    losing today's completions. No save-schema bump is needed for reading
##    old saves; writing "active" is an additive field (bump only if the save
##    validator rejects unknown keys).
##
## 3. Board view: daily_candidates(day, ctx) -> [order dicts] (<= MAX_DAILY_CANDIDATES),
##    deterministic per world day, already filtered by materials gating and by
##    today's done list via board_view(book, now, ctx).
##
## 4. Actions (suggested wire; extra = order id):
##      "order_accept": r = accept(book, id, now, ctx); if r.ok: player.orders = r.book
##      "order"       : r = check_delivery(book, id, now, inv, ctx)
##                      if r.ok: deduct order.items from inv, add order.coins,
##                           player.orders = r.book   (r.book = delivered)
##      "order_cancel": r = cancel(book, id, now) -> never touches items/coins.
##    Keep the existing World guards first (home region, p == board cell 40,29,
##    state.board repaired). check_delivery(..., direct=true) reproduces the
##    current no-accept behaviour for a transitional release.
##
## 5. Deadline. due = accept time + DEADLINE_DAYS * Village.DAY in WORLD time
##    (state.time), so a paused world pauses the deadline. expire_book() just
##    drops overdue entries: no coin penalty, inventory untouched (materials
##    stay in the backpack). Call it lazily at the start of every order action
##    and when building the snapshot; no per-tick work is required.
##
## 6. Gating is applied when an order is DISPATCHED (shown / accepted). An
##    accepted order is never revoked because a season ended mid-deadline;
##    delivery only checks the inventory.
##
## Materials gating model: reachability, not supply. An item is obtainable if
## some route in SOURCES has all its requirement tags satisfied and all its
## inputs are themselves obtainable (cycle-safe recursion). Quantities in
## `inputs` document the recipe but are not stock-checked.

const VILLAGE := preload("res://scripts/village.gd")
const WEATHER := preload("res://scripts/weather.gd")

const SCHEMA := 1
## 接單後給 3 個遊戲日完成.
const DEADLINE_DAYS := 3
## 少量候選. Today the catalog has 3 orders; the cap matters once it grows.
const MAX_DAILY_CANDIDATES := 3
## Upper bound on route recursion depth (defensive; real chains are <= 4).
const MAX_DEPTH := 16

const MSG_UNKNOWN := "沒有這張訂單"
const MSG_NOT_TODAY := "這張訂單今天不在公告板上"
const MSG_DONE := "今天已完成這張訂單，下一個世界日再來看看"
const MSG_ACTIVE := "已經接下這張訂單了"
const MSG_NOT_ACTIVE := "請先在公告板接下這張訂單"
const MSG_EXPIRED := "這張訂單已過期取消，材料仍留在背包，不扣鈴幣"
const MSG_SHORT := "這張訂單還缺少"

## Acquisition routes per item. Tags:
##   "board"         公告板已修好 (state.board): unlocks the public quarry (stone).
##   "shop"          小栗的種子攤 (home buy; sells every CROPS seed except gated flowers).
##   "season:<crop>" crop grows on ctx.day per ctx.crop_seasons, or ctx.greenhouse.
##   "station:<k>"   ctx.stations contains <k> (a usable placed station).
## Items whose id starts with "@" are pseudo-items (stations), never inventory.
## Evidence (world.gd at authoring time): home fishing returns
## FRESHWATER_FISH[total % 4] with no gate, so carp and minnow are both always
## reachable at home; radish/wheat seeds are shop items (CROPS seed_price);
## bread = RECIPES.bread {wheat:2} at a stove; stove = BUILD {wood:12, stone:15};
## stone comes from the quarry at 54,25 which requires the repaired board.
const SOURCES := {
	"radish": [{"via":"farm", "requires":["season:radish"], "inputs":{"radish_seed":1}}],
	"radish_seed": [{"via":"shop", "requires":["shop"], "inputs":{}}],
	"wheat": [{"via":"farm", "requires":["season:wheat"], "inputs":{"wheat_seed":1}}],
	"wheat_seed": [{"via":"shop", "requires":["shop"], "inputs":{}}],
	"carp": [{"via":"home_river_fishing", "requires":[], "inputs":{}}],
	"minnow": [{"via":"home_river_fishing", "requires":[], "inputs":{}}],
	"bread": [{"via":"cook", "requires":[], "inputs":{"wheat":2, "@stove":1}}],
	"strawberry_jam": [
		{"via":"stocked", "requires":["stock:jam_batch","station:jam_pot"], "inputs":{}},
		{"via":"jam_pot", "requires":["station:jam_pot","stock:sugar"], "inputs":{"strawberry":3}},
	],
	"strawberry": [
		{"via":"stocked", "requires":["stock:strawberry_batch"], "inputs":{}},
		{"via":"farm", "requires":["season:strawberry","shop"], "inputs":{}},
	],
	"@stove": [
		{"via":"existing", "requires":["station:stove"], "inputs":{}},
		{"via":"build", "requires":[], "inputs":{"wood":12, "stone":15}},
	],
	"wood": [{"via":"chop", "requires":[], "inputs":{}}],
	"stone": [{"via":"quarry", "requires":["board"], "inputs":{}}],
}


# ------------------------------------------------------------------ catalog

## Deep copy of the authoritative order list (Village.ORDERS), in its order.
static func orders() -> Array:
	return (VILLAGE.ORDERS as Array).duplicate(true)


static func find(id: String) -> Dictionary:
	for order: Variant in VILLAGE.ORDERS:
		if order is Dictionary and str(order.get("id", "")) == id:
			return (order as Dictionary).duplicate(true)
	return {}


## Problems with the catalog (empty = OK). Intended for a headless test:
## unique ids, positive int quantities/coins, and every item has a source.
static func validate_catalog() -> Array:
	var problems: Array = []
	var seen := {}
	for order: Variant in VILLAGE.ORDERS:
		if not order is Dictionary:
			problems.append("non-dictionary order")
			continue
		var id := str(order.get("id", ""))
		if id.is_empty():problems.append("order without id")
		elif seen.has(id):problems.append("duplicate id " + id)
		seen[id] = true
		if not (order.get("coins") is int) or int(order.coins) <= 0:problems.append(id + ": coins")
		var items: Variant = order.get("items")
		if not items is Dictionary or (items as Dictionary).is_empty():
			problems.append(id + ": items")
			continue
		for item: Variant in items:
			if not (items[item] is int) or int(items[item]) <= 0:problems.append(id + ": qty " + str(item))
			if not SOURCES.has(str(item)):problems.append(id + ": no source for " + str(item))
	for item: Variant in SOURCES:
		for route: Variant in SOURCES[item]:
			for input: Variant in (route as Dictionary).get("inputs", {}):
				if not SOURCES.has(str(input)):problems.append(str(item) + ": input without source " + str(input))
	return problems


# ---------------------------------------------------------------- context

## Read-only snapshot of what gating needs. Never mutates `world`. Reads the
## HOME layers through world.home_layer(field), so it is valid whichever region
## layer World currently has swapped in (Session snapshots call it too).
##   day          zero-based world day (Weather.day_index(state.time))
##   board        state.board repaired
##   shop         seed stall usable (always true at home today)
##   greenhouse   own_greenhouse(): the requesting player owns a greenhouse_roof
##                standing on a home crop plot that player also owns (so they
##                can actually plant under it). Other players' glass never counts.
##   stations     sorted unique station types placed in the home layer
##   crop_seasons World.CROP_SEASONS (empty list = year-round, as in World)
static func context_from_world(world, token: String) -> Dictionary:
	var state: Dictionary = world.state
	return context_from_layers(state, world.home_layer("roofs"), world.home_layer("crops"),
		world.home_layer("objects"), token, world.CROP_SEASONS)


static func context_from_layers(state: Dictionary, roofs: Variant, crops: Variant, objects: Variant,
		token: String, crop_seasons: Dictionary) -> Dictionary:
	var stations := {}
	if objects is Dictionary:
		for obj: Variant in (objects as Dictionary).values():
			if obj is Dictionary and obj.get("type")=="jam_pot" and obj.get("owner")==token:
				stations["jam_pot"]=true
			if obj is Dictionary and str(obj.get("type", "")) in ["stove", "bench", "mill"]:
				stations[str(obj.type)] = true
	var station_list: Array = stations.keys()
	station_list.sort()
	var context:=make_context(int(WEATHER.day_index(state.get("time", 0.0))), state.get("board", false) == true,
		own_greenhouse(roofs, crops, token), station_list, crop_seasons)
	var bag:Dictionary=state.get("players",{}).get(token,{}).get("inventory",{})
	context.stock={
		"jam_batch":int(bag.get("strawberry_jam",0))>=2,
		"sugar":int(bag.get("sugar",0))>=1,
		"strawberry_batch":int(bag.get("strawberry",0))>=3,
	}
	return context


## True when `token` owns a greenhouse_roof whose tile is a crop plot also owned
## by `token`. Empty tokens never match (fail closed).
static func own_greenhouse(roofs: Variant, crops: Variant, token: String) -> bool:
	if token.is_empty() or not roofs is Dictionary or not crops is Dictionary:return false
	for tile: Variant in roofs:
		var roof: Variant = roofs[tile]
		if not roof is Dictionary or str(roof.get("type", "")) != "greenhouse_roof":continue
		if str(roof.get("owner", "")) != token:continue
		var plot: Variant = (crops as Dictionary).get(tile)
		if plot is Dictionary and str(plot.get("owner", "")) == token:return true
	return false


static func make_context(day: int, board: bool, greenhouse := false, stations: Array = [],
		crop_seasons: Dictionary = {}, shop := true) -> Dictionary:
	return {"day":maxi(day, 0), "board":board, "shop":shop, "greenhouse":greenhouse,
		"stations":stations.duplicate(), "crop_seasons":crop_seasons.duplicate(true)}


# ------------------------------------------------------------ gating

static func obtainable(item: String, ctx: Dictionary) -> bool:
	return _reachable(item, ctx, {}, 0)


## Sorted list of order items that cannot currently be obtained.
static func missing_sources(order: Dictionary, ctx: Dictionary) -> Array:
	var out: Array = []
	var items: Variant = order.get("items")
	if not items is Dictionary:return ["?"]
	for item: Variant in items:
		if not obtainable(str(item), ctx):out.append(str(item))
	out.sort()
	return out


static func is_eligible(order: Dictionary, ctx: Dictionary) -> bool:
	return not order.is_empty() and missing_sources(order, ctx).is_empty()


## All orders whose materials are obtainable under ctx, in catalog order.
static func eligible(ctx: Dictionary) -> Array:
	var out: Array = []
	for order: Variant in VILLAGE.ORDERS:
		if order is Dictionary and is_eligible(order, ctx):out.append((order as Dictionary).duplicate(true))
	return out


## Deterministic daily selection: eligible orders ranked by
## sha256("<day>|<id>"), first MAX_DAILY_CANDIDATES, returned in catalog order
## (stable UI). Same day + same ctx => same list on every peer and reload.
static func daily_candidates(day: int, ctx: Dictionary) -> Array:
	var pool := eligible(ctx)
	if pool.size() > MAX_DAILY_CANDIDATES:
		var ranked := pool.duplicate()
		ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return _rank(day, str(a.id)) < _rank(day, str(b.id)))
		var keep := {}
		for i in MAX_DAILY_CANDIDATES:keep[str(ranked[i].id)] = true
		pool = pool.filter(func(o: Dictionary) -> bool: return keep.has(str(o.id)))
	return pool


static func candidate_ids(day: int, ctx: Dictionary) -> Array:
	return daily_candidates(day, ctx).map(func(o: Dictionary) -> String: return str(o.id))


# ------------------------------------------------------------- player book

static func day_of(now: float) -> int:
	return int(WEATHER.day_index(now))


## Migrates/sanitises player.orders. Legacy {"day","done"} keeps today's done
## list; a new day clears "done" (once-per-day rule). Unknown active ids and
## malformed entries are dropped. Returns a new dictionary.
static func normalize_book(book: Variant, now: float) -> Dictionary:
	var today := day_of(now)
	var src: Dictionary = book if book is Dictionary else {}
	var out := {"day":today, "done":[], "active":{}}
	if int(src.get("day", -1)) == today and src.get("done") is Array:
		for id: Variant in src.done:
			if id is String and not find(id).is_empty() and not (out.done as Array).has(id):out.done.append(id)
	var active: Variant = src.get("active")
	if active is Dictionary:
		for id: Variant in active:
			var entry: Variant = active[id]
			if not (id is String) or find(id).is_empty() or not entry is Dictionary:continue
			var accepted: Variant = entry.get("accepted")
			var due: Variant = entry.get("due")
			if not _finite(accepted) or not _finite(due) or float(due) <= float(accepted):continue
			out.active[id] = {"accepted":float(accepted), "due":float(due)}
	return out


## Drops overdue active orders. {book, expired:[ids]}. No penalty of any kind.
static func expire_book(book: Variant, now: float) -> Dictionary:
	var out := normalize_book(book, now)
	var expired: Array = []
	for id: Variant in (out.active as Dictionary).keys():
		if now >= float(out.active[id].due):expired.append(id)
	expired.sort()
	for id: Variant in expired:(out.active as Dictionary).erase(id)
	return {"book":out, "expired":expired}


## Board snapshot for the UI: today's candidates with per-order status
## ("open" | "active" | "done") plus remaining seconds for active orders.
## Active orders that rotated off today's board are still listed.
static func board_view(book: Variant, now: float, ctx: Dictionary) -> Array:
	var b: Dictionary = expire_book(book, now).book
	var rows: Array = []
	var listed := {}
	for order: Dictionary in daily_candidates(day_of(now), ctx):
		var id := str(order.id)
		listed[id] = true
		rows.append(_row(order, b, now))
	var extra_ids: Array = (b.active as Dictionary).keys()
	extra_ids.sort()
	for id: Variant in extra_ids:
		if not listed.has(id):rows.append(_row(find(id), b, now))
	return rows


## Self-only snapshot payload (Session sends it as `order_board` to its owner
## only). One row per catalog order, in catalog order:
##   status "open" | "active" | "done" from board_view, or "unavailable" when the
##   order is not dispatched today (its `missing` lists unobtainable items; empty
##   means it simply rotated off today's board).
## `expired` lists active orders whose deadline has passed (not yet committed).
static func snapshot(book: Variant, now: float, ctx: Dictionary) -> Dictionary:
	var rows := {}
	for row: Dictionary in board_view(book, now, ctx):rows[str(row.id)] = row
	var out: Array = []
	for order: Variant in VILLAGE.ORDERS:
		if not order is Dictionary:continue
		var id := str(order.get("id", ""))
		var row: Dictionary = rows.get(id, {})
		if row.is_empty():
			row = (order as Dictionary).duplicate(true)
			row.status = "done" if _done_today(book, now, id) else "unavailable"
			row.missing = missing_sources(order, ctx)
		out.append(row)
	return {"day":day_of(now), "deadline_days":DEADLINE_DAYS, "rows":out,
		"expired":expire_book(book, now).expired}


static func _done_today(book: Variant, now: float, id: String) -> bool:
	return (normalize_book(book, now).done as Array).has(id)


static func accept(book: Variant, id: String, now: float, ctx: Dictionary) -> Dictionary:
	var b: Dictionary = expire_book(book, now).book
	if find(id).is_empty():return _fail(MSG_UNKNOWN, b)
	if (b.done as Array).has(id):return _fail(MSG_DONE, b)
	if (b.active as Dictionary).has(id):return _fail(MSG_ACTIVE, b)
	if not candidate_ids(day_of(now), ctx).has(id):return _fail(MSG_NOT_TODAY, b)
	b.active[id] = {"accepted":now, "due":now + DEADLINE_DAYS * VILLAGE.DAY}
	return {"ok":true, "message":"接下訂單，%d 個世界日內交貨；沒完成只會取消，不扣鈴幣" % DEADLINE_DAYS, "book":b}


## Player-initiated cancel: removes the active entry only.
static func cancel(book: Variant, id: String, now: float) -> Dictionary:
	var b: Dictionary = expire_book(book, now).book
	if not (b.active as Dictionary).has(id):return _fail(MSG_NOT_ACTIVE, b)
	(b.active as Dictionary).erase(id)
	return {"ok":true, "message":"已取消訂單，材料留在背包", "book":b}


## Delivery check. On ok, r.book is the post-delivery book (active removed,
## id appended to done) and r.order is the definition; the CALLER deducts
## r.order.items from the inventory and pays r.order.coins atomically.
## direct=true: legacy no-accept delivery, allowed only for today's candidates.
## inv is only read.
static func check_delivery(book: Variant, id: String, now: float, inv: Dictionary, ctx: Dictionary, direct := false) -> Dictionary:
	var before: Variant = book.get("active", {}) if book is Dictionary else {}
	var swept := expire_book(book, now)
	var b: Dictionary = swept.book
	var order := find(id)
	if order.is_empty():return _fail(MSG_UNKNOWN, b)
	if (b.done as Array).has(id):return _fail(MSG_DONE, b)
	if not (b.active as Dictionary).has(id):
		if (swept.expired as Array).has(id) or (before is Dictionary and (before as Dictionary).has(id)):
			return _fail(MSG_EXPIRED, b)
		if not direct:return _fail(MSG_NOT_ACTIVE, b)
		if not candidate_ids(day_of(now), ctx).has(id):return _fail(MSG_NOT_TODAY, b)
	var names: Array = (order.items as Dictionary).keys()
	names.sort()
	for item: Variant in names:
		if int(inv.get(item, 0)) < int(order.items[item]):
			var r := _fail(MSG_SHORT, b)
			r.missing_item = str(item)
			return r
	(b.active as Dictionary).erase(id)
	(b.done as Array).append(id)
	return {"ok":true, "order":order, "book":b,
		"message":"訂單完成！鈴幣 +%d；每天最多各交一次，不接單也不扣錢" % int(order.coins)}


# --------------------------------------------------------------- internals

static func _reachable(item: String, ctx: Dictionary, visiting: Dictionary, depth: int) -> bool:
	if depth > MAX_DEPTH or visiting.has(item):return false
	var routes: Variant = SOURCES.get(item)
	if not routes is Array:return false
	visiting[item] = true
	var found := false
	for route: Variant in routes:
		if not route is Dictionary:continue
		var ok := true
		for tag: Variant in (route as Dictionary).get("requires", []):
			if not _tag(str(tag), ctx):
				ok = false
				break
		if ok:
			for input: Variant in (route as Dictionary).get("inputs", {}):
				if not _reachable(str(input), ctx, visiting, depth + 1):
					ok = false
					break
		if ok:
			found = true
			break
	visiting.erase(item)
	return found


static func _tag(tag: String, ctx: Dictionary) -> bool:
	if tag == "board":return ctx.get("board", false) == true
	if tag == "shop":return ctx.get("shop", false) == true
	if tag.begins_with("stock:"):return ctx.get("stock",{}).get(tag.substr(6),false)==true
	if tag.begins_with("station:"):
		var stations: Variant = ctx.get("stations", [])
		return stations is Array and (stations as Array).has(tag.substr(8))
	if tag.begins_with("season:"):
		if ctx.get("greenhouse", false) == true:return true
		var table: Variant = ctx.get("crop_seasons")
		if not table is Dictionary or (table as Dictionary).is_empty():return false # fail closed
		var crop := tag.substr(7)
		var seasons: Variant = (table as Dictionary).get(crop, [])
		if not seasons is Array or (seasons as Array).is_empty():return true # World: empty = year-round
		return WEATHER.season_on_day(float(int(ctx.get("day", 0)))) in seasons
	return false # unknown tag: fail closed


static func _rank(day: int, id: String) -> String:
	return ("%d|%s" % [day, id]).sha256_text()


static func _row(order: Dictionary, book: Dictionary, now: float) -> Dictionary:
	var id := str(order.get("id", ""))
	var row := order.duplicate(true)
	row.status = "open"
	if (book.done as Array).has(id):row.status = "done"
	elif (book.active as Dictionary).has(id):
		row.status = "active"
		row.remaining = maxf(0.0, float(book.active[id].due) - now)
	return row


static func _fail(message: String, book: Dictionary) -> Dictionary:
	return {"ok":false, "message":message, "book":book}


static func _finite(v: Variant) -> bool:
	return (v is float or v is int) and is_finite(float(v))
