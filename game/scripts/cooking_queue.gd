extends RefCounted
## Pure, deterministic FIFO cooking queue helper (T036 groundwork).
##
## World uses this helper for stove.cooking actions, regional ticks and lazy
## conversion of a legacy stove.job. SaveSchema validates the stored records;
## Session publishes a display-only job projection for older presentation code.
##
## State shape (canonical, exactly three keys):
##   {"active": {} | ActiveRecord, "waiting": [WaitingRecord...], "ready": [ReadyRecord...]}
## WaitingRecord: id, kind, owner, ingredients, yield, recipe_version, duration
## ActiveRecord:  WaitingRecord + started, finish (using saved duration)
## ReadyRecord:   WaitingRecord + completed
##
## Rules:
## - Every operation validates all inputs, never mutates its arguments and
##   returns {ok:false, message} on failure. Successful results carry freshly
##   built (deep-owned) state / inventory with whole counts normalised to int.
## - No clocks, IO or global mutable state: callers pass `now` explicitly.
## - enqueue / cancel / claim never auto-advance; callers advance first.
##   enqueue and cancel refuse while the active job is already due.
## - Capacity counts active + waiting + ready jobs together.

const CAPACITY := 10
const RECIPE_VERSION := 1
const ITEM_CAP := 1000000000
const MAX_TIME := 1000000000000.0
const OWNER_MAX := 64 # Match production SaveSchema.owner.
const ITEM_KEY_MAX := 64
const ID_LENGTH := 32
const HEX_DIGITS := "0123456789abcdef"
const STATE_KEYS := ["active", "waiting", "ready"]
const BASE_KEYS := ["id", "kind", "owner", "ingredients", "yield", "recipe_version", "duration"]
const ACTIVE_KEYS := ["started", "finish"]
const READY_KEYS := ["completed"]
const LEGACY_REQUIRED := ["kind", "ready", "owner"]
const LEGACY_OPTIONAL := ["ingredients", "yield", "recipe_version"]
## Absolute floor for the finish == started + time check. Saves go through
## JSON.stringify (non-full precision), so stored doubles may drift by a few
## ulps; anything beyond this is treated as a contradiction.
const TIME_TOLERANCE := 0.000001
const TIME_RELATIVE_TOLERANCE := 0.000000000001

const MSG_TIME := "時間資料無效"
const MSG_RECIPES := "食譜資料無效"
const MSG_STATE := "料理佇列資料無效"
const MSG_INVENTORY := "背包資料無效"
const MSG_ADVANCE := "目前料理已完成，請先更新料理進度"


# ---------------------------------------------------------------- public API

static func empty_state() -> Dictionary:
	return {"active": {}, "waiting": [], "ready": []}


static func validate(state: Variant, recipes: Dictionary, now: float) -> bool:
	return not _load(state, recipes, now).has("error")


static func enqueue(state: Dictionary, recipes: Dictionary, now: float, owner: String, kind: String, id: String, inventory: Dictionary) -> Dictionary:
	var loaded: Dictionary = _load(state, recipes, now)
	if loaded.has("error"):
		return _fail(loaded["error"])
	var catalog: Dictionary = loaded["recipes"]
	var queue: Dictionary = loaded["state"]
	var parsed_inventory: Dictionary = _parse_inventory(inventory)
	if parsed_inventory.is_empty():
		return _fail(MSG_INVENTORY)
	var items: Dictionary = parsed_inventory["items"]
	if _overdue(queue, now):
		return _fail(MSG_ADVANCE)
	if not catalog.has(kind):
		return _fail("還沒有這份食譜")
	var recipe: Dictionary = catalog[kind]
	var ingredients: Dictionary = recipe["ingredients"]
	var record: Dictionary = {
		"id": id, "kind": kind, "owner": owner,
		"ingredients": ingredients.duplicate(), "yield": int(recipe["yield"]),
		"recipe_version": RECIPE_VERSION,
		"duration": float(recipe["time"]),
	}
	if _parse_record(record, "waiting", catalog, now).is_empty():
		return _fail("料理編號或擁有者無效")
	if _ids(queue).has(id):
		return _fail("料理編號重複")
	if _total(queue) >= CAPACITY:
		return _fail("石灶排程已滿（最多 %d 份）" % CAPACITY)
	for item: Variant in ingredients:
		var need: int = ingredients[item]
		if int(items.get(item, 0)) < need:
			return _fail("缺少%s %d" % [item, need])
	for item: Variant in ingredients:
		items[item] = int(items.get(item, 0)) - int(ingredients[item])
	var active: Dictionary = queue["active"]
	var started_now: bool = active.is_empty()
	if started_now:
		queue["active"] = _start(record, now, float(recipe["time"]))
	else:
		var waiting: Array = queue["waiting"]
		waiting.append(record)
	return _seal(queue, catalog, now, "料理時間超出範圍", {
		"ok": true, "inventory": items, "id": id, "kind": kind, "started": started_now,
	})


static func advance(state: Dictionary, recipes: Dictionary, now: float) -> Dictionary:
	var loaded: Dictionary = _load(state, recipes, now)
	if loaded.has("error"):
		return _fail(loaded["error"])
	var catalog: Dictionary = loaded["recipes"]
	var queue: Dictionary = loaded["state"]
	var active: Dictionary = queue["active"]
	var waiting: Array = queue["waiting"]
	var ready: Array = queue["ready"]
	var completed_ids: Array = []
	# Each iteration moves exactly one job to ready, so this is bounded by CAPACITY.
	while not active.is_empty() and now >= float(active["finish"]):
		var finish: float = active["finish"]
		ready.append(_complete(active, finish))
		completed_ids.append(active["id"])
		if waiting.is_empty():
			active = {}
		else:
			var next: Dictionary = waiting.pop_front()
			active = _start(next, finish, float(next["duration"]))
	queue["active"] = active
	return _seal(queue, catalog, now, "料理時間超出範圍", {
		"ok": true, "changed": not completed_ids.is_empty(), "completed": completed_ids,
	})


static func cancel(state: Dictionary, recipes: Dictionary, now: float, owner: String, id: String, inventory: Dictionary) -> Dictionary:
	var loaded: Dictionary = _load(state, recipes, now)
	if loaded.has("error"):
		return _fail(loaded["error"])
	var catalog: Dictionary = loaded["recipes"]
	var queue: Dictionary = loaded["state"]
	var parsed_inventory: Dictionary = _parse_inventory(inventory)
	if parsed_inventory.is_empty():
		return _fail(MSG_INVENTORY)
	var items: Dictionary = parsed_inventory["items"]
	if _overdue(queue, now):
		return _fail(MSG_ADVANCE)
	var active: Dictionary = queue["active"]
	var waiting: Array = queue["waiting"]
	var ready: Array = queue["ready"]
	var target: Dictionary = {}
	var waiting_index: int = -1
	if not active.is_empty() and active["id"] == id:
		target = active
	else:
		for index: int in waiting.size():
			var entry: Dictionary = waiting[index]
			if entry["id"] == id:
				target = entry
				waiting_index = index
				break
	if target.is_empty():
		for entry: Variant in ready:
			var done: Dictionary = entry
			if done["id"] == id:
				return _fail("料理已完成，無法取消，請直接領取")
		return _fail("找不到這份料理")
	if target["owner"] != owner:
		return _fail("只有投入食材的人可以取消")
	var refund: Dictionary = target["ingredients"]
	for item: Variant in refund:
		if int(items.get(item, 0)) > ITEM_CAP - int(refund[item]):
			return _fail("背包中的物品已達上限，無法退回食材")
	for item: Variant in refund:
		items[item] = int(items.get(item, 0)) + int(refund[item])
	var promoted: String = ""
	if waiting_index < 0:
		if waiting.is_empty():
			queue["active"] = {}
		else:
			var next: Dictionary = waiting.pop_front()
			queue["active"] = _start(next, now, float(next["duration"]))
			promoted = next["id"]
	else:
		waiting.remove_at(waiting_index)
	return _seal(queue, catalog, now, "料理時間超出範圍", {
		"ok": true, "inventory": items, "id": id, "kind": target["kind"],
		"refunded": refund.duplicate(), "promoted": promoted,
	})


static func claim(state: Dictionary, recipes: Dictionary, now: float, inventory: Dictionary) -> Dictionary:
	var loaded: Dictionary = _load(state, recipes, now)
	if loaded.has("error"):
		return _fail(loaded["error"])
	var catalog: Dictionary = loaded["recipes"]
	var queue: Dictionary = loaded["state"]
	var parsed_inventory: Dictionary = _parse_inventory(inventory)
	if parsed_inventory.is_empty():
		return _fail(MSG_INVENTORY)
	var items: Dictionary = parsed_inventory["items"]
	var ready: Array = queue["ready"]
	if ready.is_empty():
		return _fail("目前沒有完成的料理")
	var record: Dictionary = ready[0]
	var kind: String = record["kind"]
	var amount: int = record["yield"]
	if int(items.get(kind, 0)) > ITEM_CAP - amount:
		return _fail("背包中的物品已達上限")
	items[kind] = int(items.get(kind, 0)) + amount
	ready.remove_at(0)
	return _seal(queue, catalog, now, MSG_STATE, {
		"ok": true, "inventory": items, "id": record["id"], "kind": kind,
		"owner": record["owner"], "yield": amount, "completed": record["completed"],
	})


## Converts the legacy single `stove.job` record into queue state without
## charging, refunding or duplicating anything. A job that is already due is
## imported directly into ready. Old saves did not store a duration, so an
## unfinished import infers a bounded start while preserving its exact deadline.
static func import_legacy(job: Dictionary, recipes: Dictionary, now: float, id: String) -> Dictionary:
	var loaded: Dictionary = _load(empty_state(), recipes, now)
	if loaded.has("error"):
		return _fail(loaded["error"])
	var catalog: Dictionary = loaded["recipes"]
	if job.is_empty():
		return {"ok": true, "state": empty_state(), "imported": false}
	for key: Variant in job:
		if not key is String or not (LEGACY_REQUIRED.has(key) or LEGACY_OPTIONAL.has(key)):
			return _fail("舊料理資料含有未知欄位")
	for key: Variant in LEGACY_REQUIRED:
		if not job.has(key):
			return _fail("舊料理資料缺少欄位")
	var kind: Variant = job["kind"]
	if not kind is String or not catalog.has(kind):
		return _fail("舊料理的食譜無效")
	var recipe: Dictionary = catalog[kind]
	var saved_ingredients: Variant = job.get("ingredients",recipe["ingredients"])
	if not _valid_ingredients(saved_ingredients):return _fail("舊料理的食材記錄無效")
	var ingredients: Dictionary = saved_ingredients
	var saved_yield: Variant = job.get("yield",recipe["yield"])
	if not _is_count(saved_yield,1):return _fail("舊料理的產量無效")
	if job.has("recipe_version") and not _exact_count(job["recipe_version"], RECIPE_VERSION):
		return _fail("舊料理的食譜版本不符")
	var ready_at: Variant = job["ready"]
	if not _is_time(ready_at):
		return _fail("舊料理的完成時間無效")
	var finish: float = float(ready_at)
	# Old saves only stored the deadline, not duration/start. Preserve that
	# deadline even if today's recipe duration changed; never restart the job.
	var started: float = minf(now,maxf(0.0,finish-float(recipe["time"])))
	var duration: float = finish-started if finish>now else float(recipe["time"])
	var record: Dictionary = {
		"id": id, "kind": kind, "owner": job["owner"],
		"ingredients": ingredients.duplicate(), "yield": int(saved_yield),
		"recipe_version": RECIPE_VERSION, "duration": duration,
	}
	var queue: Dictionary = empty_state()
	if finish<=now:
		record["completed"]=finish
		queue.ready.append(record)
	else:
		record["started"]=started
		record["finish"]=finish
		queue.active=record
	return _seal(queue, catalog, now, "舊料理的編號或擁有者無效", {
		"ok": true, "imported": true, "overdue": now >= finish,
	})


# ---------------------------------------------------------------- internals

static func _fail(message: String) -> Dictionary:
	return {"ok": false, "message": message}


## Validates now, recipes and state together. Returns {"error": message} or
## {"recipes": normalised catalog, "state": freshly built canonical state}.
static func _load(state: Variant, recipes: Dictionary, now: float) -> Dictionary:
	if not _is_time(now):
		return {"error": MSG_TIME}
	var parsed_recipes: Dictionary = _parse_recipes(recipes)
	if parsed_recipes.is_empty():
		return {"error": MSG_RECIPES}
	var catalog: Dictionary = parsed_recipes["recipes"]
	var queue: Dictionary = _parse_state(state, catalog, now)
	if queue.is_empty():
		return {"error": MSG_STATE}
	return {"recipes": catalog, "state": queue}


## Re-validates a computed result so no operation can emit a non-canonical
## state (e.g. finish overflowing MAX_TIME, or a bad owner/id on import).
static func _seal(queue: Dictionary, catalog: Dictionary, now: float, message: String, result: Dictionary) -> Dictionary:
	var sealed: Dictionary = _parse_state(queue, catalog, now)
	if sealed.is_empty():
		return _fail(message)
	result["state"] = sealed
	return result


static func _is_number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))


static func _is_time(value: Variant) -> bool:
	return _is_number(value) and float(value) >= 0.0 and float(value) <= MAX_TIME


static func _is_count(value: Variant, minimum: int) -> bool:
	if not _is_number(value):
		return false
	var number: float = float(value)
	return number >= minimum and number <= ITEM_CAP and floorf(number) == number


static func _exact_count(value: Variant, expected: int) -> bool:
	return _is_count(value, 1) and int(value) == expected


static func _close(actual: float, expected: float) -> bool:
	return absf(actual - expected) <= maxf(TIME_TOLERANCE, absf(expected) * TIME_RELATIVE_TOLERANCE)


static func _item_key(value: Variant) -> bool:
	if not value is String:
		return false
	var text: String = value
	return not text.is_empty() and text.length() <= ITEM_KEY_MAX


static func _valid_id(value: Variant) -> bool:
	if not value is String:
		return false
	var text: String = value
	if text.length() != ID_LENGTH:
		return false
	for index: int in text.length():
		if HEX_DIGITS.find(text[index]) < 0:
			return false
	return true


static func _valid_owner(value: Variant) -> bool:
	if not value is String:
		return false
	var text: String = value
	return not text.is_empty() and text.length() <= OWNER_MAX


## Returns {} on failure, else {"recipes": {kind: {ingredients, time, yield}}}.
## The whole catalog must be valid (fail closed), extra recipe keys such as
## "name" are ignored.
static func _parse_recipes(recipes: Dictionary) -> Dictionary:
	var catalog: Dictionary = {}
	for kind: Variant in recipes:
		if not _item_key(kind):
			return {}
		var raw: Variant = recipes[kind]
		if not raw is Dictionary:
			return {}
		var recipe: Dictionary = raw
		var time: Variant = recipe.get("time")
		if not _is_number(time) or float(time) <= 0.0 or float(time) > MAX_TIME:
			return {}
		var amount: Variant = recipe.get("yield")
		if not _is_count(amount, 1):
			return {}
		var raw_ingredients: Variant = recipe.get("ingredients")
		if not raw_ingredients is Dictionary:
			return {}
		var source: Dictionary = raw_ingredients
		if source.is_empty():
			return {}
		var ingredients: Dictionary = {}
		for item: Variant in source:
			if not _item_key(item) or not _is_count(source[item], 1):
				return {}
			ingredients[item] = int(source[item])
		catalog[kind] = {"ingredients": ingredients, "time": float(time), "yield": int(amount)}
	return {"recipes": catalog}


## Returns {} on failure, else {"items": fresh inventory with int counts}.
static func _parse_inventory(inventory: Dictionary) -> Dictionary:
	var items: Dictionary = {}
	for item: Variant in inventory:
		if not (item is String or item is StringName) or str(item).is_empty() or not _is_count(inventory[item], 0):
			return {}
		items[str(item)] = int(inventory[item])
	return {"items": items}


static func _valid_ingredients(raw: Variant) -> bool:
	if not raw is Dictionary:
		return false
	var given: Dictionary = raw
	if given.is_empty() or given.size()>64:
		return false
	for item: Variant in given:
		if not _item_key(item):
			return false
		if not _is_count(given[item],1):
			return false
	return true


## Shared record validator. Returns a freshly built canonical record or {}.
static func _parse_record(raw: Variant, phase: String, catalog: Dictionary, now: float) -> Dictionary:
	if not raw is Dictionary:
		return {}
	var record: Dictionary = raw
	var keys: Array = []
	keys.append_array(BASE_KEYS)
	if phase == "active":
		keys.append_array(ACTIVE_KEYS)
	elif phase == "ready":
		keys.append_array(READY_KEYS)
	if record.size() != keys.size():
		return {}
	for key: Variant in record:
		if not key is String or not keys.has(key):
			return {}
	var id: Variant = record["id"]
	var kind: Variant = record["kind"]
	var owner: Variant = record["owner"]
	if not _valid_id(id) or not _valid_owner(owner):
		return {}
	if not kind is String or not catalog.has(kind):
		return {}
	# These are authoritative submitted snapshots, not today's recipe prices.
	# Only enqueue reads the current catalog; migration preserves old costs/yield.
	if not _valid_ingredients(record["ingredients"]):
		return {}
	var ingredients: Dictionary = {}
	for item: Variant in record["ingredients"]:ingredients[item]=int(record["ingredients"][item])
	if not _is_count(record["yield"],1):
		return {}
	var amount: int = int(record["yield"])
	if not _is_number(record["duration"]) or float(record["duration"])<=0.0 or float(record["duration"])>MAX_TIME:return {}
	if not _exact_count(record["recipe_version"], RECIPE_VERSION):
		return {}
	var out: Dictionary = {
		"id": id, "kind": kind, "owner": owner,
		"ingredients": ingredients.duplicate(), "yield": amount,
		"recipe_version": RECIPE_VERSION,
		"duration": float(record["duration"]),
	}
	if phase == "active":
		var raw_started: Variant = record["started"]
		var raw_finish: Variant = record["finish"]
		if not _is_time(raw_started) or not _is_time(raw_finish):
			return {}
		var started: float = float(raw_started)
		var finish: float = float(raw_finish)
		var duration: float = float(record["duration"])
		# started <= now plus finish == started + time also bounds a future
		# finish to now + duration; overdue (finish <= now) is allowed.
		if started > now or not _close(finish, started + duration):
			return {}
		out["started"] = started
		out["finish"] = finish
	elif phase == "ready":
		var raw_completed: Variant = record["completed"]
		if not _is_time(raw_completed) or float(raw_completed) > now:
			return {}
		out["completed"] = float(raw_completed)
	return out


## Returns {} on failure, else a freshly built canonical state.
static func _parse_state(raw: Variant, catalog: Dictionary, now: float) -> Dictionary:
	if not raw is Dictionary:
		return {}
	var state: Dictionary = raw
	if state.size() != STATE_KEYS.size():
		return {}
	for key: Variant in state:
		if not key is String or not STATE_KEYS.has(key):
			return {}
	var raw_active: Variant = state["active"]
	var raw_waiting: Variant = state["waiting"]
	var raw_ready: Variant = state["ready"]
	if not raw_active is Dictionary or not raw_waiting is Array or not raw_ready is Array:
		return {}
	var active_source: Dictionary = raw_active
	var waiting_source: Array = raw_waiting
	var ready_source: Array = raw_ready
	var active: Dictionary = {}
	if not active_source.is_empty():
		active = _parse_record(active_source, "active", catalog, now)
		if active.is_empty():
			return {}
	var total: int = (0 if active.is_empty() else 1) + waiting_source.size() + ready_source.size()
	if total > CAPACITY:
		return {}
	# Canonical: a waiting job is always promoted as soon as the stove frees up.
	if active.is_empty() and not waiting_source.is_empty():
		return {}
	var seen: Dictionary = {}
	if not active.is_empty():
		seen[active["id"]] = true
	var waiting: Array = []
	for entry: Variant in waiting_source:
		var record: Dictionary = _parse_record(entry, "waiting", catalog, now)
		if record.is_empty() or seen.has(record["id"]):
			return {}
		seen[record["id"]] = true
		waiting.append(record)
	var ready: Array = []
	var last_completed: float = -1.0
	for entry: Variant in ready_source:
		var record: Dictionary = _parse_record(entry, "ready", catalog, now)
		if record.is_empty() or seen.has(record["id"]):
			return {}
		var completed: float = record["completed"]
		# Ready is FIFO by completion; the oldest is claimed first.
		if completed < last_completed:
			return {}
		last_completed = completed
		seen[record["id"]] = true
		ready.append(record)
	# The active job can only have started at or after the latest completion.
	if not active.is_empty() and float(active["started"]) < last_completed:
		return {}
	return {"active": active, "waiting": waiting, "ready": ready}


static func _overdue(queue: Dictionary, now: float) -> bool:
	var active: Dictionary = queue["active"]
	return not active.is_empty() and now >= float(active["finish"])


static func _total(queue: Dictionary) -> int:
	var active: Dictionary = queue["active"]
	var waiting: Array = queue["waiting"]
	var ready: Array = queue["ready"]
	return (0 if active.is_empty() else 1) + waiting.size() + ready.size()


static func _ids(queue: Dictionary) -> Dictionary:
	var ids: Dictionary = {}
	var active: Dictionary = queue["active"]
	if not active.is_empty():
		ids[active["id"]] = true
	for list_key: String in ["waiting", "ready"]:
		var list: Array = queue[list_key]
		for entry: Variant in list:
			var record: Dictionary = entry
			ids[record["id"]] = true
	return ids


static func _base(record: Dictionary) -> Dictionary:
	var ingredients: Dictionary = record["ingredients"]
	return {
		"id": record["id"], "kind": record["kind"], "owner": record["owner"],
		"ingredients": ingredients.duplicate(), "yield": int(record["yield"]),
		"recipe_version": RECIPE_VERSION,
		"duration": float(record["duration"]),
	}


static func _start(record: Dictionary, at: float, duration: float) -> Dictionary:
	var out: Dictionary = _base(record)
	out["started"] = at
	out["finish"] = at + duration
	return out


static func _complete(record: Dictionary, at: float) -> Dictionary:
	var out: Dictionary = _base(record)
	out["completed"] = at
	return out
