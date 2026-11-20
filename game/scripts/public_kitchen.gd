extends RefCounted
## Section 18 Q04 / T042 public kitchen (save v23, protocol 41).
##
## state.public_kitchen = {
##   "stove":  ""            | canonical home cell "x,y" of the donated stove
##   "seats":  []            | [cell, cell] two distinct long_bench cells, sorted
##   "meals":  {"soup":n,"bread":n,"salad":n}  whole, capped by REQUIREMENTS
##   "opened": bool          true exactly when every requirement is filled
## }
## No actor/player ids are stored. Donated objects keep their original owner
## field; World refuses move/remove/undo on site cells (HOME only).
##
## This module never preloads World. Authority functions receive the live World
## instance; pure helpers take a home-oriented state Dictionary (live state or a
## region_snapshot(HOME) copy).

const COMMUNITY := preload("res://scripts/community.gd")

const HOME := "home"
const VERSION := 23
const REGISTER := "kitchen_register"
const CONTRIBUTE := "kitchen_contribute"
const ACTIONS := [REGISTER, CONTRIBUTE]
const MEALS := ["soup", "bread", "salad"]
const REQUIREMENTS := {"soup":4, "bread":2, "salad":2}
const NAMES := {"soup":"蘿蔔湯", "bread":"麵包", "salad":"菜園沙拉"}
const KEYS := ["meals", "opened", "seats", "stove"]
const STOVE_RANGE := 8.0
const SEAT_RANGE := 3.0
const MAX_EXTRA := 32
const EXTRA_CHARS := "0123456789,|"
const MAX_COORD := 100000
const PATH_LIMIT := 8192
const NO_CELL := Vector2i(-1, -1)
const DIRS: Array[Vector2i] = [Vector2i(0,-1), Vector2i(1,0), Vector2i(0,1), Vector2i(-1,0)]

const MSG_CORRUPT := "公共廚房資料有誤，這次沒有變更"
const MSG_LOCKED := "這是捐給公共廚房的設施，已永久公用，無法搬移、拆除或復原"

## Immutable story pages. `npc` is a resident id the UI maps to a portrait.
const EVENT_INVITATION := {
	"id":"kitchen_invitation",
	"title":"長桌邊的邀請",
	"lines":[
		{"npc":"milu", "text":"野餐那天，大家把湯碗傳來傳去，我才發現渡口少的不是菜，是一口大家都能用的灶。"},
		{"npc":"aru", "text":"桌子已經有了。要是誰願意把自己的小石灶和兩張長椅借給大家，這裡就能天天開飯。"},
		{"npc":"milu", "text":"不用新蓋，也不用花錢。只是捐出去之後就是大家的，不能再搬走或拆掉喔。"},
		{"npc":"aru", "text":"想清楚了再到共用餐桌登記。灶要離桌子近一點，椅子要靠著灶，路也得走得過去。"},
	],
}
const EVENT_REGISTRATION := {
	"id":"kitchen_registration",
	"title":"一個屋簷、一張桌子",
	"lines":[
		{"npc":"aru", "text":"灶和長椅都登記好了。從今天起，誰來都能在這口灶煮飯，誰都能坐下來吃。"},
		{"npc":"milu", "text":"共用餐桌加上兩張長椅，正好圍成一個小飯廳。屋頂的事我們慢慢商量。"},
		{"npc":"aru", "text":"開張前先備料：四份蘿蔔湯、兩份麵包、兩份沙拉。誰手上有就放一點，不夠的別人會補上。"},
		{"npc":"milu", "text":"不在線上的朋友也算數。等他們回來，翻開手冊就看得到今天這一頁。"},
	],
}
const EVENT_OPENING := {
	"id":"kitchen_opening",
	"title":"公共廚房開飯了",
	"lines":[
		{"npc":"milu", "text":"湯、麵包和沙拉都齊了！今晚渡口第一次為所有人開伙。"},
		{"npc":"aru", "text":"每一份都是大家各自帶來的。沒有誰多拿，也沒有誰少給，這樣的飯最香。"},
		{"npc":"milu", "text":"灶還是照常可以煮，煮好的料理任何人都能領。下次換我教大家新的配菜。"},
		{"npc":"milu", "text":"大家說想吃點甜的。蓋一座麵粉磨坊，自己種的小麥就能磨成麵粉。"},
		{"npc":"aru", "text":"磨坊用木材、石頭和工作台做的木工零件就能蓋，記得留一格入口。麵粉配南瓜和雞蛋放進灶裡烤成派，切開正好分給長桌邊的大家。"},
		{"npc":"aru", "text":"吃飽了再看看渡口：舊棧板和倉庫的屋頂也該修了。我們下一回一起動手。"},
	],
}

## Q05 next steps once the kitchen has opened: build the 3x3 mill straight from materials (C13, no kit
## step any more) -> mill wheat -> bake pie on a stove. `table` names the caller-supplied recipe table;
## no quantities live here (see mill_guide).
const MILL_STEPS := [
	{"id":"mill", "table":"build", "where":"建造目錄「生活」"},
	{"id":"flour", "table":"process", "where":"麵粉磨坊"},
	{"id":"pumpkin_pie", "table":"recipes", "where":"小石灶"},
]

# ---------------------------------------------------------------------------
# pure helpers
# ---------------------------------------------------------------------------

static func fresh() -> Dictionary:
	return {"stove":"", "seats":[], "meals":{"soup":0, "bread":0, "salad":0}, "opened":false}

static func key(c: Vector2i) -> String:
	return "%d,%d" % [c.x, c.y]

## Strict canonical non-negative "x,y" cell, NO_CELL otherwise.
static func parse_cell(value) -> Vector2i:
	if not value is String:return NO_CELL
	var parts: PackedStringArray = value.split(",")
	if parts.size() != 2:return NO_CELL
	for part in parts:
		if part.is_empty() or part.length() > 6:return NO_CELL
		for ch in part:
			if ch < "0" or ch > "9":return NO_CELL
	var c := Vector2i(int(parts[0]), int(parts[1]))
	if c.x > MAX_COORD or c.y > MAX_COORD or value != key(c):return NO_CELL
	return c

## Canonical wire order matches Session and SaveSchema: sorted cell strings.
static func seat_extra(a: Vector2i, b: Vector2i) -> String:
	return key(a) + "|" + key(b) if key(a) < key(b) else key(b) + "|" + key(a)

static func _whole(value, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= 0.0 and float(value) <= float(maximum) and floorf(float(value)) == float(value)

static func _full(meals: Dictionary) -> bool:
	for item in MEALS:
		if int(meals.get(item, 0)) < int(REQUIREMENTS[item]):return false
	return true

## Exact persisted shape plus internal invariants (no world lookups).
static func shape_ok(data) -> bool:
	if not data is Dictionary or data.size() != KEYS.size():return false
	for field in KEYS:
		if not data.has(field):return false
	if not data.stove is String or not data.seats is Array or not data.meals is Dictionary or not data.opened is bool:return false
	var meals: Dictionary = data.meals
	if meals.size() != MEALS.size():return false
	for item in MEALS:
		if not meals.has(item) or not _whole(meals[item], int(REQUIREMENTS[item])):return false
	if data.stove == "":
		if not data.seats.is_empty() or data.opened:return false
		for item in MEALS:
			if int(meals[item]) != 0:return false
		return true
	var stove := parse_cell(data.stove)
	if stove == NO_CELL or data.seats.size() != 2:return false
	var a := parse_cell(data.seats[0])
	var b := parse_cell(data.seats[1])
	if a == NO_CELL or b == NO_CELL or not (str(data.seats[0]) < str(data.seats[1])) or a == stove or b == stove:return false
	return data.opened == _full(meals)

static func _data(state: Dictionary) -> Dictionary:
	var data = state.get("public_kitchen")
	return data if shape_ok(data) else {}

static func registered(state: Dictionary) -> bool:
	return not _data(state).get("stove", "").is_empty()

## "locked" (no picnic / shared table), "register", "collect", "open";
## "invalid" when the stored field is malformed.
static func stage(state: Dictionary) -> String:
	var data := _data(state)
	if data.is_empty():return "invalid"
	if data.opened:return "open"
	if data.stove != "":return "collect"
	if not _table_ready(state):return "locked"
	return "register"

## [stove, seat, seat] cells once registered, else [].
static func site_cells(state: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var data := _data(state)
	if data.is_empty() or data.stove == "":return out
	out.append(parse_cell(data.stove))
	for seat in data.seats:out.append(parse_cell(seat))
	# C12: a donated 2x2 stove protects its other three cells too (appended: [stove, seat, seat] first).
	var footprint := stove_footprint(state, out[0])
	for index in range(1, footprint.size()):out.append(footprint[index])
	return out

static func is_site_cell(state: Dictionary, c: Vector2i) -> bool:
	return c in site_cells(state)

## Remaining need per meal ({} when malformed).
static func outstanding(state: Dictionary) -> Dictionary:
	var data := _data(state)
	if data.is_empty():return {}
	var out := {}
	for item in MEALS:out[item] = int(REQUIREMENTS[item]) - int(data.meals[item])
	return out

static func _table_ready(state: Dictionary) -> bool:
	return state.get("picnic") is bool and state.picnic and COMMUNITY.table_cell(state) != NO_CELL

static func _home_view(state: Dictionary) -> bool:
	var region = state.get("region_id", HOME)
	return region == HOME and state.get("objects") is Dictionary

## Mirrors World.cooking_idle plus "no legacy job": nothing active, queued or
## waiting to be claimed. Malformed queues count as busy.
static func stove_idle(stove: Dictionary) -> bool:
	if stove.has("job"):return false
	if not stove.has("cooking"):return true
	var queue = stove.cooking
	if not queue is Dictionary:return false
	var active = queue.get("active")
	var waiting = queue.get("waiting")
	var ready = queue.get("ready")
	return active is Dictionary and active.is_empty() and waiting is Array and waiting.is_empty() and ready is Array and ready.is_empty()

static func _object(state: Dictionary, c: Vector2i, kind: String) -> Dictionary:
	var obj = state.get("objects", {}).get(key(c))
	return obj if obj is Dictionary and obj.get("type") == kind else {}

# ---- C12: the donated stove may be the early 1x1 小石灶 or the 2x2 公共廚房灶台 ------------------
# Literals, not an Industry preload: this module stays free of the construction scripts.
const STOVE_TYPES := ["stove", "kitchen_stove"]
const BIG_STOVE := "kitchen_stove"
const BIG_STOVE_PART := "kitchen_stove_part"
const BIG_OFFSETS: Array[Vector2i] = [Vector2i(0,0), Vector2i(1,0), Vector2i(0,1), Vector2i(1,1)]

## The stove (either kind) whose ANCHOR is `c`; {} for nothing, another kind or a far-end cell.
static func _stove_at(state: Dictionary, c: Vector2i) -> Dictionary:
	var obj = state.get("objects", {}).get(key(c))
	if not obj is Dictionary or not STOVE_TYPES.has(obj.get("type")):return {}
	if obj.type == BIG_STOVE and int(obj.get(BIG_STOVE_PART, 0)) != 0:return {}
	return obj

## Every cell the stove anchored at `c` occupies: [c] for the early stove, four cells for C12.
static func stove_footprint(state: Dictionary, c: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = [c]
	if _stove_at(state, c).get("type") == BIG_STOVE:
		for index in range(1, BIG_OFFSETS.size()):out.append(c + BIG_OFFSETS[index])
	return out

## A 2x2 stove must still be whole: all four cells, same type and owner, parts 0..3 in order.
static func _footprint_intact(state: Dictionary, c: Vector2i) -> bool:
	var anchor := _stove_at(state, c)
	if anchor.is_empty():return false
	if anchor.type != BIG_STOVE:return true
	for index in BIG_OFFSETS.size():
		var part = state.get("objects", {}).get(key(c + BIG_OFFSETS[index]))
		if not part is Dictionary or part.get("type") != BIG_STOVE or part.get("owner") != anchor.get("owner"):return false
		if int(part.get(BIG_STOVE_PART, 0)) != index:return false
	return true

static func _sorted_keys(cells: Array[Vector2i]) -> Array[String]:
	cells.sort()
	var out: Array[String] = []
	for c in cells:out.append(key(c))
	out.sort()
	return out

## UI preview from a home snapshot (region_snapshot(HOME) or live home state):
## the caller's own idle stoves within STOVE_RANGE of the shared table, sorted.
## Ownership/range/idle only — World re-validates reach/path on submit.
static func candidate_stoves(state: Dictionary, token: String) -> Array[String]:
	var cells: Array[Vector2i] = []
	if token.is_empty() or not _home_view(state) or not _table_ready(state) or stage(state) != "register":return _sorted_keys(cells)
	var table := COMMUNITY.table_cell(state)
	for k in state.objects:
		var c := parse_cell(k)
		if c == NO_CELL:continue
		var obj = state.objects[k]
		if not obj is Dictionary or not STOVE_TYPES.has(obj.get("type")) or obj.get("owner") != token or not stove_idle(obj):continue
		if obj.type == BIG_STOVE and (int(obj.get(BIG_STOVE_PART, 0)) != 0 or not _footprint_intact(state, c)):continue
		if Vector2(c).distance_to(Vector2(table)) <= STOVE_RANGE:cells.append(c)
	return _sorted_keys(cells)

## The caller's own long benches within SEAT_RANGE of `stove`, sorted; [] when
## `stove` is not itself a candidate. Pick two and submit seat_extra(a, b).
static func candidate_seats(state: Dictionary, token: String, stove: Vector2i) -> Array[String]:
	var cells: Array[Vector2i] = []
	if not key(stove) in candidate_stoves(state, token):return _sorted_keys(cells)
	for k in state.objects:
		var c := parse_cell(k)
		if c == NO_CELL:continue
		var obj = state.objects[k]
		if not obj is Dictionary or obj.get("type") != "long_bench" or obj.get("owner") != token:continue
		if Vector2(c).distance_to(Vector2(stove)) <= SEAT_RANGE:cells.append(c)
	return _sorted_keys(cells)

## Unlocked story pages (deep copies), oldest first. Read-only; depends only on
## shared milestones, so every current or late-joining member sees the same list.
static func events(state: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not (state.get("picnic") is bool and state.picnic):return out
	out.append(EVENT_INVITATION.duplicate(true))
	var data := _data(state)
	if data.is_empty() or data.stove == "":return out
	out.append(EVENT_REGISTRATION.duplicate(true))
	if data.opened:out.append(EVENT_OPENING.duplicate(true))
	return out

## Read-only mill guidance, [] unless stage(state) == "open". Every quantity
## comes from `tables` supplied by the caller so this module never preloads
## World: {"craft":World.CRAFT, "build":World.BUILD, "process":INDUSTRY.PROCESS,
## "recipes":World.RECIPES, "names":World.NAMES}. Any missing/malformed entry
## returns [] rather than partial or stale guidance.
## Each step: {id, where, inputs:{item:int}, yield:int, time:int, text}.
static func mill_guide(state: Dictionary, tables: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if stage(state) != "open":return out
	var names = tables.get("names", {})
	if not names is Dictionary:names = {}
	for step in MILL_STEPS:
		var source = tables.get(step.table)
		var entry = source.get(step.id) if source is Dictionary else null
		if not entry is Dictionary:
			out.clear()
			return out
		var raw = entry if step.table == "build" else entry.get("ingredients")
		if not raw is Dictionary:
			out.clear()
			return out
		var inputs := {}
		var parts: PackedStringArray = []
		for item in raw:
			if item == "name":continue
			if not _whole(raw[item], 1000000) or int(raw[item]) <= 0:
				out.clear()
				return out
			inputs[item] = int(raw[item])
			parts.append("%s×%d" % [str(names.get(item, item)), int(raw[item])])
		if inputs.is_empty():
			out.clear()
			return out
		if not _whole(entry.get("yield",1),1000000) or int(entry.get("yield",1))<1 or not _whole(entry.get("time",0),1000000):return []
		var amount := int(entry.get("yield",1))
		var seconds := int(entry.get("time",0))
		var title:=str(entry.get("name",names.get(step.id,step.id)))
		var text := "%s：%s → %s×%d" % [step.where, "、".join(parts), title, amount]
		if seconds > 0:text += "（%d 秒）" % seconds
		out.append({"id":step.id, "where":step.where, "inputs":inputs, "yield":amount, "time":seconds, "text":text})
	return out

# ---------------------------------------------------------------------------
# save schema
# ---------------------------------------------------------------------------

## Call BEFORE valid() at the top level of SaveSchema.validate (never inside
## validate_region / region projections). Pre-23 saves must not carry the field
## and receive fresh() only — no auto-donation, no completion.
static func migrate(state: Dictionary, version) -> bool:
	if not _whole(version, 1000000):return false
	if int(version) >= VERSION:return true
	if state.has("public_kitchen"):return false
	state.public_kitchen = fresh()
	return true

## Top-level, home-oriented save state only. Validates exact shape, canonical
## cells, live stove/long_bench objects with existing owners in the HOME layer,
## range invariants, picnic + shared table prerequisite. Normalises meal counts
## to int. Path access is NOT re-checked here (see report): later neighbouring
## construction may legitimately close a path and must not brick the save.
static func valid(state: Dictionary, version) -> bool:
	if not _whole(version, 1000000):return false
	var data = state.get("public_kitchen")
	if not shape_ok(data):return false
	for item in MEALS:data.meals[item] = int(data.meals[item])
	if data.stove == "":return true
	if int(version) < VERSION:return false
	if state.has("region_id") or not state.get("objects") is Dictionary or not state.get("players") is Dictionary:return false
	if not _table_ready(state):return false
	var table := COMMUNITY.table_cell(state)
	var stove := parse_cell(data.stove)
	var stove_obj := _stove_at(state, stove)
	if stove_obj.is_empty() or not state.players.has(stove_obj.get("owner")) or not _footprint_intact(state, stove):return false
	if Vector2(stove).distance_to(Vector2(table)) > STOVE_RANGE:return false
	for seat in data.seats:
		var c := parse_cell(seat)
		var bench := _object(state, c, "long_bench")
		if bench.is_empty() or bench.get("owner") != stove_obj.get("owner") or not state.players.has(bench.get("owner")):return false
		if Vector2(c).distance_to(Vector2(stove)) > SEAT_RANGE:return false
	return true

# ---------------------------------------------------------------------------
# authority (called by World._apply, HOME orientation, after the 3.2 reach gate)
# ---------------------------------------------------------------------------

static func _fail(message: String) -> Dictionary:
	return {"ok":false, "message":message}

## True when every target has a passable cardinal neighbour connected to a
## passable cardinal neighbour of the table through passable cells
## (world.blocked, current = HOME orientation; closed doors block).
static func reachable(world, table: Vector2i, targets: Array[Vector2i]) -> bool:
	var remaining := {}
	for t in targets:remaining[t] = true
	var seen := {}
	var queue: Array[Vector2i] = []
	for d in DIRS:
		var n: Vector2i = table + d
		if not seen.has(n) and not world.blocked(n):
			seen[n] = true
			queue.append(n)
	var head := 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		for d in DIRS:
			remaining.erase(c + d)
		if remaining.is_empty():return true
		for d in DIRS:
			var n: Vector2i = c + d
			if seen.has(n) or n.x < 0 or n.y < 0:continue
			seen[n] = true
			if world.blocked(n):continue
			queue.append(n)
		if seen.size() > PATH_LIMIT:return false
	return remaining.is_empty()

static func perform(world, token: String, action: String, p: Vector2i, extra: String) -> Dictionary:
	var state: Dictionary = world.state
	if not state.get("players", {}).has(token):return _fail("尚未加入世界")
	if world.player_region(token) != HOME:return _fail("請回到風鈴渡口使用公共廚房。")
	var data = state.get("public_kitchen")
	if not shape_ok(data):return _fail(MSG_CORRUPT)
	match action:
		REGISTER:return _register(world, state, data, token, p, extra)
		CONTRIBUTE:return _contribute(state, data, token, p, extra)
	return _fail("請選擇工具後再試一次")

static func _register(world, state: Dictionary, data: Dictionary, token: String, p: Vector2i, extra: String) -> Dictionary:
	if data.stove != "":return _fail("渡口已經有公共廚房了，不需要再捐一次。")
	if not _table_ready(state):return _fail("先完成渡口野餐並擺好共用餐桌，再登記公共廚房。")
	if extra.is_empty() or extra.length() > MAX_EXTRA:return _fail("請重新選擇兩張長椅。")
	for ch in extra:
		if not EXTRA_CHARS.contains(ch):return _fail("請重新選擇兩張長椅。")
	var parts := extra.split("|")
	if parts.size() != 2:return _fail("請重新選擇兩張長椅。")
	var a := parse_cell(parts[0])
	var b := parse_cell(parts[1])
	if a == NO_CELL or b == NO_CELL or a == b or extra != seat_extra(a, b):return _fail("請選擇兩張不同的長椅。")
	var table := COMMUNITY.table_cell(state)
	var stove := _stove_at(state, p)
	if stove.is_empty():return _fail("請選擇一座已經蓋好的小石灶或公共廚房灶台。")
	if not _footprint_intact(state, p):return _fail(MSG_CORRUPT)
	if stove.get("owner") != token:return _fail("只能捐出自己蓋的小石灶。")
	if not stove_idle(stove):return _fail("石灶還有料理排程或待領取的料理，請先領取或取消再登記。")
	if Vector2(p).distance_to(Vector2(table)) > STOVE_RANGE:return _fail("小石灶要在共用餐桌 8 格以內。")
	for seat in [a, b]:
		var bench := _object(state, seat, "long_bench")
		if bench.is_empty():return _fail("請選擇兩張已經蓋好的雙人長椅。")
		if bench.get("owner") != token:return _fail("只能捐出自己蓋的長椅。")
		if Vector2(seat).distance_to(Vector2(p)) > SEAT_RANGE:return _fail("兩張長椅都要在小石灶 3 格以內。")
	# The two benches must be reachable; of a stove only ONE side has to be (any of its cells), so a 2x2
	# stove pushed against a wall is still a valid donation as long as one face stays walkable.
	var seat_targets: Array[Vector2i] = [a, b]
	var stove_reachable := false
	for cell in stove_footprint(state, p):
		var single: Array[Vector2i] = [cell]
		if reachable(world, table, single):
			stove_reachable = true
			break
	if not stove_reachable or not reachable(world, table, seat_targets):return _fail("從共用餐桌走不到小石灶或長椅，請先清出通道（關著的門也會擋路）。")
	data.stove = key(p)
	data.seats = [key(a), key(b)]
	var result := {"ok":true, "message":"公共廚房登記完成！小石灶和兩張長椅已永久捐給渡口，大家都能使用。", "kitchen_stage":"collect"}
	result.stove = data.stove
	result.seats = data.seats.duplicate()
	return result

static func _contribute(state: Dictionary, data: Dictionary, token: String, p: Vector2i, extra: String) -> Dictionary:
	if data.stove == "":return _fail("公共廚房還沒有登記。")
	if key(p) != data.stove:return _fail("請到公共廚房的小石灶放料理。")
	if not extra.is_empty():return _fail("請重新打開公共廚房面板。")
	if data.opened:return _fail("公共廚房已經開張了，謝謝大家！")
	if _stove_at(state, p).is_empty():return _fail(MSG_CORRUPT)
	var inv = state.players[token].get("inventory")
	if not inv is Dictionary:return _fail(MSG_CORRUPT)
	var contributed := {}
	var parts: PackedStringArray = []
	for item in MEALS:
		var have := int(data.meals[item])
		var held = inv.get(item, 0)
		if not _whole(held, 2000000000):continue
		var take := mini(int(REQUIREMENTS[item]) - have, int(held))
		if take <= 0:continue
		inv[item] = int(held) - take
		data.meals[item] = have + take
		contributed[item] = take
		parts.append("%s ×%d" % [NAMES[item], take])
	if contributed.is_empty():return _fail("背包裡沒有公共廚房還缺的料理（蘿蔔湯、麵包、菜園沙拉）。")
	data.opened = _full(data.meals)
	var message := "已放上公共廚房：" + "、".join(parts)
	message += "。公共廚房開張了！" if data.opened else "。還差的料理等大家一起補齊。"
	var result := {"ok":true, "message":message, "contributed":contributed, "meals":data.meals.duplicate(), "opened":data.opened, "kitchen_stage":"open" if data.opened else "collect"}
	return result
