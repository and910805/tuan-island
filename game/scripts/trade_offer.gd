extends RefCounted
## T058 雙方確認交易 — pure helper, no World/Node access.
##
## Plan ch.20: 選物品與鈴幣 → 顯示兩邊內容 → 任一修改就取消雙方確認 →
## 兩人確認後原子交換；斷線或背包不足則全部取消，不部分扣款。
## Plan ch.40: 有人正交易時不可跳時 (see `blocks_sleep`).
##
## Every mutator works on a deep copy and returns {"ok", "message", "offer", ...};
## the caller replaces its stored offer only on ok (or when "cancelled" is set).
## Settlement never mutates inventories: `stage_settlement` returns complete
## replacement inventories/wallets for BOTH parties, or nothing at all.

const STATUS_OPEN := "open"
const STATUS_SETTLED := "settled"
const STATUS_CANCELLED := "cancelled"
const STATUSES := [STATUS_OPEN, STATUS_SETTLED, STATUS_CANCELLED]

const REASON_PLAYER := "player"
const REASON_DISCONNECT := "disconnect"
const REASON_SHORTAGE := "shortage"
const REASON_EXPIRED := "expired"
const REASON_RELOAD := "reload"
const REASON_REGION := "region"
const REASONS := [REASON_PLAYER, REASON_DISCONNECT, REASON_SHORTAGE, REASON_EXPIRED, REASON_RELOAD, REASON_REGION]

const UNCONFIRMED := -1
const MAX_LINES := 12
const MAX_ITEM_ID := 64
const MAX_ID := 80
const MAX_TOKEN := 128
const MAX_QUANTITY := 1000000
const ITEM_LIMIT := 1000000000 # Same per-item bag ceiling as World helpers.
const MAX_COINS := 1000000000 # Same wallet ceiling as Shipping.MAX_COINS.
const MAX_REVISION := 1000000000
const MAX_UTC := 1000000000000.0
const MAX_EXTRA_BYTES := 2048
const OPEN_TTL := 600.0

const MSG_BAD := "交易資料無效。"
const MSG_CLOSED := "這筆交易已結束。"
const MSG_NOT_PARTY := "你不是這筆交易的參與者。"
const MSG_SELF := "不能和自己交易。"
const MSG_LINES := "交易明細無效。"
const MSG_DUP := "交易項目重複。"
const MSG_UNTRADABLE := "這項物品不能交易。"
const MSG_OWN := "持有數量不足，請重新選擇。"
const MSG_WALLET := "鈴幣不足。"
const MSG_EMPTY := "雙方都還沒放入物品或鈴幣。"
const MSG_STALE := "交易內容已變更，請重新檢查後再確認。"
const MSG_REVISION := "這筆交易修改次數過多，請重新開啟。"
const MSG_NOT_READY := "雙方尚未確認同一版內容。"
const MSG_SHORT := "交換時持有物品或鈴幣不足，交易已取消，雙方都沒有扣款。"
const MSG_FULL := "交換後背包或錢包超出上限，交易已取消，雙方都沒有扣款。"
const MSG_SETTLED := "交易完成。"
const MSG_CANCELLED := "交易已取消，雙方都沒有扣款。"


# ---------------------------------------------------------------- basics

static func integer_in(value: Variant, minimum: int, maximum: int) -> bool:
	# Accepts whole floats: JSON reload turns ints into floats.
	return (value is int or value is float) and is_finite(float(value)) and floorf(float(value)) == float(value) \
		and float(value) >= float(minimum) and float(value) <= float(maximum)

static func _text_ok(value: Variant, maximum: int) -> bool:
	return (value is String or value is StringName) and str(value).length() >= 1 and str(value).length() <= maximum

static func _result(ok: bool, message: String, offer: Dictionary = {}) -> Dictionary:
	var r := {"ok": ok, "message": message}
	if not offer.is_empty():
		r["offer"] = offer
	return r

static func _empty_side() -> Dictionary:
	return {"items": {}, "coins": 0}

static func _sorted_items(items: Dictionary) -> Dictionary:
	# Canonical String keys in sorted order so live and JSON-reloaded copies compare equal.
	var values := {}
	for k in items:
		values[str(k)] = int(items[k])
	var keys: Array = values.keys()
	keys.sort()
	var out := {}
	for k in keys:
		out[k] = values[k]
	return out

static func other_party(offer: Dictionary, token: String) -> String:
	if str(offer.get("a", "")) == token:
		return str(offer.get("b", ""))
	if str(offer.get("b", "")) == token:
		return str(offer.get("a", ""))
	return ""

static func involves(offer: Dictionary, token: String) -> bool:
	return token != "" and (str(offer.get("a", "")) == token or str(offer.get("b", "")) == token)

static func is_open(offer: Dictionary) -> bool:
	return str(offer.get("status", "")) == STATUS_OPEN

static func _side_empty(side: Dictionary) -> bool:
	return (side.get("items", {}) as Dictionary).is_empty() and int(side.get("coins", 0)) == 0

static func is_ready(offer: Dictionary) -> bool:
	if not is_open(offer):
		return false
	var rev := int(offer.get("revision", 0))
	var conf: Dictionary = offer.get("confirmed", {})
	var a := str(offer.get("a", ""))
	var b := str(offer.get("b", ""))
	if int(conf.get(a, UNCONFIRMED)) != rev or int(conf.get(b, UNCONFIRMED)) != rev:
		return false
	var sides: Dictionary = offer.get("sides", {})
	return not (_side_empty(sides.get(a, {})) and _side_empty(sides.get(b, {})))


# ---------------------------------------------------------------- schema

## Structural check for an offer from storage or another component.
## Does NOT check ownership/tradability (those depend on live state).
static func validate(offer: Variant) -> bool:
	if not offer is Dictionary:
		return false
	var o: Dictionary = offer
	for field in ["id", "a", "b", "status", "revision", "sides", "confirmed", "created_utc", "reason"]:
		if not o.has(field):
			return false
	if not _text_ok(o.id, MAX_ID) or not _text_ok(o.a, MAX_TOKEN) or not _text_ok(o.b, MAX_TOKEN):
		return false
	if str(o.a) == str(o.b) or not str(o.status) in STATUSES:
		return false
	if not integer_in(o.revision, 0, MAX_REVISION):
		return false
	var created: Variant = o.created_utc
	if not (created is int or created is float) or not is_finite(float(created)) or float(created) < 0.0 or float(created) > MAX_UTC:
		return false
	if not (o.reason is String) or (str(o.reason) != "" and not str(o.reason) in REASONS):
		return false
	if (str(o.status) == STATUS_CANCELLED) != (str(o.reason) != ""):
		return false
	if not o.sides is Dictionary or not o.confirmed is Dictionary:
		return false
	var sides: Dictionary = o.sides
	var conf: Dictionary = o.confirmed
	if sides.size() != 2 or conf.size() != 2:
		return false
	for party in [str(o.a), str(o.b)]:
		if not sides.has(party) or not conf.has(party):
			return false
		if not integer_in(conf[party], UNCONFIRMED, int(o.revision)):
			return false
		var side: Variant = sides[party]
		if not side is Dictionary or side.size() != 2 or not side.has("items") or not side.has("coins"):
			return false
		if not integer_in(side.coins, 0, MAX_COINS) or not side.items is Dictionary or side.items.size() > MAX_LINES:
			return false
		for item in side.items:
			if not _text_ok(item, MAX_ITEM_ID) or not integer_in(side.items[item], 1, MAX_QUANTITY):
				return false
	if str(o.status) == STATUS_SETTLED and not is_ready(_with_status(o, STATUS_OPEN)):
		return false
	return true

static func _with_status(o: Dictionary, status: String) -> Dictionary:
	var c := o.duplicate(true)
	c.status = status
	return c

## Normalise numeric types/key order after JSON reload (call after `validate`).
static func canonical(offer: Dictionary) -> Dictionary:
	var o := offer.duplicate(true)
	var sides := {}
	var conf := {}
	for party in [str(o.a), str(o.b)]:
		var side: Dictionary = o.sides[party]
		sides[party] = {"items": _sorted_items(side.items), "coins": int(side.coins)}
		conf[party] = int(o.confirmed[party])
	return {"id": str(o.id), "a": str(o.a), "b": str(o.b), "status": str(o.status),
		"revision": int(o.revision), "sides": sides, "confirmed": conf,
		"created_utc": float(o.created_utc), "reason": str(o.reason)}


# ---------------------------------------------------------------- input parsing

## Parses an edit payload (e.g. act() `extra`):
## {"offer": id, "items": [[item, count], ...], "coins": n}
static func parse_edit(extra: String) -> Dictionary:
	if extra.to_utf8_buffer().size() > MAX_EXTRA_BYTES:
		return _result(false, MSG_LINES)
	var parser := JSON.new()
	if parser.parse(extra) != OK or not parser.data is Dictionary:
		return _result(false, MSG_LINES)
	var d: Dictionary = parser.data
	if d.size() != 3 or not _text_ok(d.get("offer"), MAX_ID) or not d.has("items") or not d.has("coins"):
		return _result(false, MSG_LINES)
	return {"ok": true, "message": "", "offer_id": str(d.offer), "lines": d.items, "coins": d.coins}

## Parses a confirm payload: {"offer": id, "revision": n}
static func parse_confirm(extra: String) -> Dictionary:
	if extra.to_utf8_buffer().size() > MAX_EXTRA_BYTES:
		return _result(false, MSG_BAD)
	var parser := JSON.new()
	if parser.parse(extra) != OK or not parser.data is Dictionary:
		return _result(false, MSG_BAD)
	var d: Dictionary = parser.data
	if d.size() != 2 or not _text_ok(d.get("offer"), MAX_ID) or not integer_in(d.get("revision"), 0, MAX_REVISION):
		return _result(false, MSG_BAD)
	return {"ok": true, "message": "", "offer_id": str(d.offer), "revision": int(d.revision)}

## Validates lines [[item, count], ...] against tradable set and current holdings.
## `tradable` is item_id -> anything (only keys are used); caller owns the policy
## (e.g. exclude quest/story keepsakes, tools in use, region-bound items).
static func parse_lines(lines: Variant, tradable: Dictionary, inventory: Dictionary) -> Dictionary:
	if not lines is Array or lines.size() > MAX_LINES:
		return _result(false, MSG_LINES)
	var items := {}
	for line in lines:
		if not line is Array or line.size() != 2 or not _text_ok(line[0], MAX_ITEM_ID) or not integer_in(line[1], 1, MAX_QUANTITY):
			return _result(false, MSG_LINES)
		var item := str(line[0])
		if items.has(item):
			return _result(false, MSG_DUP)
		if not tradable.has(item):
			return _result(false, MSG_UNTRADABLE)
		if int(inventory.get(item, 0)) < int(line[1]):
			return _result(false, MSG_OWN)
		items[item] = int(line[1])
	return {"ok": true, "message": "", "items": _sorted_items(items)}


# ---------------------------------------------------------------- lifecycle

static func open(id: String, a: String, b: String, now_utc: float) -> Dictionary:
	if not _text_ok(id, MAX_ID) or not _text_ok(a, MAX_TOKEN) or not _text_ok(b, MAX_TOKEN):
		return _result(false, MSG_BAD)
	if a == b:
		return _result(false, MSG_SELF)
	if not is_finite(now_utc) or now_utc < 0.0 or now_utc > MAX_UTC:
		return _result(false, MSG_BAD)
	var offer := {"id": id, "a": a, "b": b, "status": STATUS_OPEN, "revision": 0,
		"sides": {a: _empty_side(), b: _empty_side()},
		"confirmed": {a: UNCONFIRMED, b: UNCONFIRMED},
		"created_utc": now_utc, "reason": ""}
	return _result(true, "", offer)

## Replaces `token`'s side. Any real change bumps revision and clears BOTH
## confirmations. Identical content returns ok with "unchanged": true.
static func set_side(offer: Dictionary, token: String, lines: Variant, coins: Variant,
		tradable: Dictionary, inventory: Dictionary, wallet: Variant) -> Dictionary:
	if not validate(offer):
		return _result(false, MSG_BAD)
	if not is_open(offer):
		return _result(false, MSG_CLOSED)
	if not involves(offer, token):
		return _result(false, MSG_NOT_PARTY)
	if not integer_in(coins, 0, MAX_COINS):
		return _result(false, MSG_LINES)
	if not integer_in(wallet, 0, MAX_COINS) or int(wallet) < int(coins):
		return _result(false, MSG_WALLET)
	var parsed := parse_lines(lines, tradable, inventory)
	if not parsed.ok:
		return parsed
	var o := canonical(offer)
	var next := {"items": parsed.items, "coins": int(coins)}
	if o.sides[token] == next:
		var same := _result(true, "", o)
		same["unchanged"] = true
		return same
	if int(o.revision) >= MAX_REVISION:
		return _result(false, MSG_REVISION)
	o.sides[token] = next
	o.revision = int(o.revision) + 1
	for party in o.confirmed:
		o.confirmed[party] = UNCONFIRMED
	var r := _result(true, "", o)
	r["unchanged"] = false
	return r

## Confirms exactly `revision`. A stale revision is rejected, so a confirm sent
## before the partner's edit can never accept the edited content.
static func confirm(offer: Dictionary, token: String, revision: Variant) -> Dictionary:
	if not validate(offer):
		return _result(false, MSG_BAD)
	if not is_open(offer):
		return _result(false, MSG_CLOSED)
	if not involves(offer, token):
		return _result(false, MSG_NOT_PARTY)
	var o := canonical(offer)
	if not integer_in(revision, 0, MAX_REVISION) or int(revision) != int(o.revision):
		return _result(false, MSG_STALE, o)
	if _side_empty(o.sides[o.a]) and _side_empty(o.sides[o.b]):
		return _result(false, MSG_EMPTY)
	o.confirmed[token] = int(o.revision)
	var r := _result(true, "", o)
	r["ready"] = is_ready(o)
	return r

static func unconfirm(offer: Dictionary, token: String) -> Dictionary:
	if not validate(offer):
		return _result(false, MSG_BAD)
	if not is_open(offer):
		return _result(false, MSG_CLOSED)
	if not involves(offer, token):
		return _result(false, MSG_NOT_PARTY)
	var o := canonical(offer)
	o.confirmed[token] = UNCONFIRMED
	return _result(true, "", o)

## Either party (token) or the server (token == "") may cancel an open offer.
static func cancel(offer: Dictionary, token: String, reason: String) -> Dictionary:
	if not validate(offer):
		return _result(false, MSG_BAD)
	if not is_open(offer):
		return _result(false, MSG_CLOSED)
	if token != "" and not involves(offer, token):
		return _result(false, MSG_NOT_PARTY)
	if not reason in REASONS:
		return _result(false, MSG_BAD)
	var o := canonical(offer)
	o.status = STATUS_CANCELLED
	o.reason = reason
	for party in o.confirmed:
		o.confirmed[party] = UNCONFIRMED
	var r := _result(true, MSG_CANCELLED, o)
	r["cancelled"] = true
	return r

static func expired(offer: Dictionary, now_utc: float) -> bool:
	if not is_open(offer) or not is_finite(now_utc):
		return false
	var created := float(offer.get("created_utc", 0.0))
	return now_utc < created or now_utc - created >= OPEN_TTL

## Server-side sweep for disconnect / region change / reload: cancels every open
## offer involving `token` ("" = all open offers). Returns {"offers", "cancelled": [ids]}.
static func cancel_involving(offers: Dictionary, token: String, reason: String) -> Dictionary:
	var out := {}
	var ids: Array = []
	for id in offers:
		var o: Variant = offers[id]
		if o is Dictionary and is_open(o) and (token == "" or involves(o, token)):
			var c := cancel(o, "", reason)
			if c.ok:
				out[id] = c.offer
				ids.append(str(id))
				continue
		out[id] = o
	return {"offers": out, "cancelled": ids}

## Sleep vote / time skip must refuse while this is true (plan ch.40).
static func blocks_sleep(offers: Dictionary) -> bool:
	for id in offers:
		var o: Variant = offers[id]
		if o is Dictionary and is_open(o):
			return true
	return false


# ---------------------------------------------------------------- settlement

## Stages an all-or-nothing swap. `state_a`/`state_b` are {"inventory": Dictionary,
## "coins": int} snapshots of offer.a / offer.b taken inside the same server step.
## Never mutates inputs. On success returns full replacement values:
##   {"ok": true, "offer": settled, "a": {"inventory", "coins"}, "b": {...}}
## On holdings/capacity failure returns {"ok": false, "cancelled": true, "offer": cancelled}
## so the caller can persist the cancellation; nobody is charged.
static func stage_settlement(offer: Dictionary, state_a: Dictionary, state_b: Dictionary, tradable: Dictionary) -> Dictionary:
	if not validate(offer):
		return _result(false, MSG_BAD)
	if not is_open(offer):
		return _result(false, MSG_CLOSED)
	var o := canonical(offer)
	if not is_ready(o):
		return _result(false, MSG_NOT_READY)
	for st in [state_a, state_b]:
		if not st.get("inventory") is Dictionary or not integer_in(st.get("coins"), 0, MAX_COINS):
			return _result(false, MSG_BAD)
	var give_a: Dictionary = o.sides[o.a]
	var give_b: Dictionary = o.sides[o.b]
	# Tradability may have changed since editing (e.g. item became a keepsake).
	for side in [give_a, give_b]:
		for item in side.items:
			if not tradable.has(item):
				return _cancel_with(o, REASON_SHORTAGE, MSG_UNTRADABLE)
	var inv_a: Dictionary = (state_a.inventory as Dictionary).duplicate(true)
	var inv_b: Dictionary = (state_b.inventory as Dictionary).duplicate(true)
	var coins_a := int(state_a.coins)
	var coins_b := int(state_b.coins)
	# Phase 1: debit both givers (pre-swap holdings only; incoming goods never fund outgoing).
	if not _debit(inv_a, give_a.items) or not _debit(inv_b, give_b.items):
		return _cancel_with(o, REASON_SHORTAGE, MSG_SHORT)
	if coins_a < int(give_a.coins) or coins_b < int(give_b.coins):
		return _cancel_with(o, REASON_SHORTAGE, MSG_SHORT)
	coins_a -= int(give_a.coins)
	coins_b -= int(give_b.coins)
	# Phase 2: credit receivers with ceiling checks.
	if not _credit(inv_a, give_b.items) or not _credit(inv_b, give_a.items):
		return _cancel_with(o, REASON_SHORTAGE, MSG_FULL)
	if coins_a > MAX_COINS - int(give_b.coins) or coins_b > MAX_COINS - int(give_a.coins):
		return _cancel_with(o, REASON_SHORTAGE, MSG_FULL)
	coins_a += int(give_b.coins)
	coins_b += int(give_a.coins)
	o.status = STATUS_SETTLED
	return {"ok": true, "message": MSG_SETTLED, "offer": o,
		"a": {"inventory": inv_a, "coins": coins_a},
		"b": {"inventory": inv_b, "coins": coins_b}}

static func _debit(inv: Dictionary, items: Dictionary) -> bool:
	for item in items:
		var have: Variant = inv.get(item, 0)
		if not integer_in(have, 0, ITEM_LIMIT) or int(have) < int(items[item]):
			return false
	for item in items:
		# World keeps zero-count keys; mirror that rather than erasing.
		inv[item] = int(inv[item]) - int(items[item])
	return true

static func _credit(inv: Dictionary, items: Dictionary) -> bool:
	for item in items:
		var have: Variant = inv.get(item, 0)
		if not integer_in(have, 0, ITEM_LIMIT) or int(have) > ITEM_LIMIT - int(items[item]):
			return false
	for item in items:
		inv[item] = int(inv.get(item, 0)) + int(items[item])
	return true

static func _cancel_with(o: Dictionary, reason: String, message: String) -> Dictionary:
	var c := cancel(o, "", reason)
	c.ok = false
	c.message = message
	return c


# ---------------------------------------------------------------- presentation

## Both sides' contents for either party's UI (plan: 顯示兩邊內容).
static func view(offer: Dictionary, viewer: String) -> Dictionary:
	if not validate(offer) or not involves(offer, viewer):
		return {}
	var o := canonical(offer)
	var partner := other_party(o, viewer)
	var rev := int(o.revision)
	return {"id": o.id, "status": o.status, "reason": o.reason, "revision": rev,"incoming":viewer==o.b,
		"partner": partner,
		"mine": o.sides[viewer].duplicate(true), "theirs": o.sides[partner].duplicate(true),
		"i_confirmed": int(o.confirmed[viewer]) == rev,
		"they_confirmed": int(o.confirmed[partner]) == rev,
		"ready": is_ready(o)}
