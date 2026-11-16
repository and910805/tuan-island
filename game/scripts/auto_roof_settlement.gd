extends RefCounted
## Pure aggregate inventory settlement validation for an auto-roof transaction.
## World.act applies the staged inventories within its atomic roof transaction.
##
## prepare(players, actor, plan) takes the FULL persistent server players map
## (online and offline), already reflecting the base build/remove cost and
## refund, plus an auto_roof_plan.reconcile() result. It stages replacement
## inventories for every affected owner:
##   actor:          inventory + own roof refunds - roof cost
##   other owners:   inventory + own roof refunds
## Another owner's refund is never available to pay the actor's cost.
##
## Returns {ok, message, inventories}; `inventories` maps affected owner =>
## full fresh copy of that owner's inventory (all unrelated entries retained,
## counts normalized to int). It is empty on failure. Every check runs before
## anything is returned, so a failure never yields a partial set.
##
## This is VALIDATION ONLY. It never mutates its inputs, never touches World,
## buildings, roofs or saves, and does not make anything atomic by itself: the
## caller must apply the staged inventories together with the roof add/remove
## and base action, and roll ALL of them back if persisting fails.

const LIMIT := 1000000000
const MAX_KEY_LEN := 64

const MSG_PLAN := "屋頂施工計畫有誤，這次沒有施工"
const MSG_PAYER := "無法確認付款者，這次沒有施工"
const MSG_OWNER := "無法確認退款對象，這次沒有施工"
const MSG_DATA := "背包資料有誤，這次沒有施工"
const MSG_MISSING := "屋頂材料不足，這次沒有施工"
const MSG_CAP := "退還的屋頂材料會超過背包上限，這次沒有施工"
const MSG_NOOP := "屋頂材料不需要調整"
const MSG_OK := "屋頂材料結算檢查通過"

static func prepare(players: Dictionary, actor: String, plan: Dictionary) -> Dictionary:
	# --- plan shape -------------------------------------------------------
	var plan_ok = plan.get("ok")
	if typeof(plan_ok) != TYPE_BOOL or not plan_ok:return _fail(MSG_PLAN)
	if plan.has("message") and typeof(plan.message) != TYPE_STRING:return _fail(MSG_PLAN)
	if not (plan.get("add") is Dictionary):return _fail(MSG_PLAN)
	var remove = plan.get("remove")
	if not (remove is Array):return _fail(MSG_PLAN)
	for k in remove:
		if typeof(k) != TYPE_STRING:return _fail(MSG_PLAN)
	var raw_cost = plan.get("cost")
	var raw_refunds = plan.get("refunds")
	if not (raw_cost is Dictionary) or not (raw_refunds is Dictionary):return _fail(MSG_PLAN)
	var cost := _counts(raw_cost)
	if not cost.ok:return _fail(MSG_PLAN)
	# --- payer ------------------------------------------------------------
	if not _valid_owner(actor):return _fail(MSG_PAYER)
	var actor_inv := _inventory(players, actor)
	if actor_inv.state == "missing":return _fail(MSG_PAYER)
	if actor_inv.state == "bad":return _fail(MSG_DATA)
	# --- refund owners ----------------------------------------------------
	var staged := {}  # owner => normalized inventory copy
	staged[actor] = actor_inv["counts"]
	var refunds := {}  # owner => normalized refund counts
	for owner in raw_refunds:
		if typeof(owner) != TYPE_STRING or not _valid_owner(owner):return _fail(MSG_OWNER)
		if not (raw_refunds[owner] is Dictionary):return _fail(MSG_PLAN)
		var back := _counts(raw_refunds[owner])
		if not back.ok:return _fail(MSG_PLAN)
		if not staged.has(owner):
			var inv := _inventory(players, owner)
			if inv.state == "missing":return _fail(MSG_OWNER)
			if inv.state == "bad":return _fail(MSG_DATA)
			staged[owner] = inv["counts"]
		refunds[owner] = back["counts"]
	# --- compute: each owner only sees its own refunds (+ actor's cost) ---
	var affected := {}
	var cost_values: Dictionary = cost["counts"]
	if not cost_values.is_empty():affected[actor] = true
	for owner in refunds:
		if not refunds[owner].is_empty():affected[owner] = true
	if affected.is_empty():return {"ok": true, "message": MSG_NOOP, "inventories": {}}
	var missing := false
	var capped := false
	var out := {}
	for owner in affected:
		var inv: Dictionary = staged[owner]
		var back: Dictionary = refunds.get(owner, {})
		var items := {}
		for item in back:items[item] = true
		if owner == actor:
			for item in cost_values:items[item] = true
		for item in items:
			var value: int = int(inv.get(item, 0)) + int(back.get(item, 0))
			if owner == actor:value -= int(cost_values.get(item, 0))
			if value < 0:missing = true
			elif value > LIMIT:capped = true
			elif value != 0 or inv.has(item):inv[item] = value
		out[owner] = inv
	if missing:return _fail(MSG_MISSING)
	if capped:return _fail(MSG_CAP)
	return {"ok": true, "message": MSG_OK, "inventories": out}

## Fresh normalized copy of players[owner].inventory.
## state: "ok" | "missing" (no such persistent player) | "bad" (malformed).
static func _inventory(players: Dictionary, owner: String) -> Dictionary:
	if not players.has(owner):return {"state": "missing"}
	var player = players[owner]
	if not (player is Dictionary):return {"state": "bad"}
	var inv = player.get("inventory")
	if not (inv is Dictionary):return {"state": "bad"}
	# GDScript dot assignment can create StringName inventory keys. JSON saves
	# normalize them to strings; accept and normalize the same runtime form here.
	var parsed := _counts(inv, true)
	if not parsed.ok:return {"state": "bad"}
	return {"state": "ok", "counts": parsed["counts"]}

## Validates a resource=>count map without mutating it; returns a fresh copy
## with int values. Counts must be finite non-negative whole numbers <= LIMIT
## (int or integer-valued float, never bool/string); keys non-empty Strings.
static func _counts(source: Dictionary, allow_names:bool=false) -> Dictionary:
	var values := {}
	for item in source:
		if typeof(item) != TYPE_STRING and not (allow_names and typeof(item)==TYPE_STRING_NAME):return {"ok": false}
		var key:=String(item)
		if key == "" or key.length() > MAX_KEY_LEN:return {"ok": false}
		var n := _whole(source[item])
		if n < 0:return {"ok": false}
		values[key] = n
	return {"ok": true, "counts": values}

## Returns the integer count, or -1 when the value is not a valid count.
static func _whole(value) -> int:
	match typeof(value):
		TYPE_INT:
			return value if value >= 0 and value <= LIMIT else -1
		TYPE_FLOAT:
			var f: float = value
			if is_nan(f) or is_inf(f) or f != floorf(f) or f < 0.0 or f > float(LIMIT):return -1
			return int(f)
	return -1

static func _valid_owner(owner: String) -> bool:
	if owner == "" or owner.length() > MAX_KEY_LEN or owner.strip_edges() != owner:return false
	for i in owner.length():
		var ch := owner.unicode_at(i)
		if ch < 32 or ch == 127:return false
	return true

static func _fail(message: String) -> Dictionary:
	return {"ok": false, "message": message, "inventories": {}}
