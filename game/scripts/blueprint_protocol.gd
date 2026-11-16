extends RefCounted
## Pure helpers for the blueprint quote/apply transport
## (docs/blueprint-integration.md「第三段傳輸 API 固定介面」).
## No World/Session dependency: callers pass the current item-name table.

const MAX_JSON_BYTES := 131072
const MAX_REQUEST_ID := 1000000000
const QUOTE_LIMIT := 2
const QUOTE_WINDOW_MS := 1000
const APPLY_LIMIT := 1
const APPLY_WINDOW_MS := 1500
const MAX_PROBLEMS := 32
const MAX_MESSAGE := 512
const MAX_KIND := 64
const MAX_REASON := 256
const MAX_COUNT := 1000000000
const COORD_LIMIT := 10000
## Absolute problem coordinates: origin (±COORD_LIMIT) plus a ≤16 offset.
const PROBLEM_COORD_LIMIT := COORD_LIMIT + 64
const NONCE_LENGTH := 32
const HASH_LENGTH := 64
## Boolean flags the frontend needs; any other key is dropped.
const FLAGS: Array[String] = ["requote", "stale_context", "rate_limited", "blueprint", "not_sent"]
const MATERIAL_FIELDS: Array[String] = ["cost", "mine_refund", "others_refund"]
const COUNT_FIELDS: Array[String] = ["other_people", "roof_add", "roof_remove", "pieces"]

static func valid_request_id(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and int(value) >= 1 and int(value) <= MAX_REQUEST_ID

## Integer-typed 0..3 only; bool, float and everything else are rejected.
static func valid_turns(value: Variant) -> bool:
	return typeof(value) == TYPE_INT and int(value) >= 0 and int(value) <= 3

static func valid_origin(origin: Vector2i) -> bool:
	return absi(origin.x) <= COORD_LIMIT and absi(origin.y) <= COORD_LIMIT

static func lower_hex(value: Variant, length: int) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var text: String = value
	if text.length() != length:
		return false
	for i in length:
		var ch := text.unicode_at(i)
		if not ((ch >= 48 and ch <= 57) or (ch >= 97 and ch <= 102)):
			return false
	return true

static func valid_nonce(value: Variant) -> bool:
	return lower_hex(value, NONCE_LENGTH)

static func valid_hash(value: Variant) -> bool:
	return lower_hex(value, HASH_LENGTH)

## Characters are checked before encoding so an oversized string is never
## re-encoded; a String's UTF-8 size is always >= its character count.
static func json_within_limit(text: String) -> bool:
	return text.length() <= MAX_JSON_BYTES and text.to_utf8_buffer().size() <= MAX_JSON_BYTES

static func encode_design(raw: Variant) -> String:
	return JSON.stringify(raw)

## {ok:true, raw} or {ok:false}. Normalization is World's job (BLUEPRINT_DESIGN).
static func parse_design(text: String) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(text) != OK:
		return {"ok": false}
	return {"ok": true, "raw": parser.data}

## "" when origin/turns/JSON size are acceptable, else a player-facing reason.
static func bounds_problem(design_json: String, origin: Vector2i, turns: Variant) -> String:
	if not valid_origin(origin):
		return "藍圖位置超出範圍。"
	if not valid_turns(turns):
		return "藍圖旋轉只能是 0 到 3 次。"
	if not json_within_limit(design_json):
		return "藍圖資料太大，沒有送出施工。"
	return ""

## Sliding-window limiter over an Array of tick stamps (mutated in place).
## Entries at least `window_ms` old, or newer than `now` (a clock moved
## backwards), are discarded. Rejected attempts do not consume capacity.
static func take(stamps: Array, now: int, limit: int, window_ms: int) -> bool:
	var kept: Array = []
	for stamp in stamps:
		if typeof(stamp) == TYPE_INT and int(stamp) <= now and now - int(stamp) < window_ms:
			kept.append(stamp)
	stamps.clear()
	stamps.append_array(kept)
	if stamps.size() >= limit:
		return false
	stamps.append(now)
	return true

static func failure(message: String, flag: String = "") -> Dictionary:
	var out := {"ok": false, "message": message}
	if not flag.is_empty():
		out[flag] = true
	return out

## Whitelist copy of a World quote / apply / receipt result. Only present,
## well-typed allowed fields survive; nested `quote` is sanitized one level.
static func sanitize(result: Variant, item_names: Dictionary, nested: bool = true) -> Dictionary:
	var out := {"ok": false, "message": ""}
	if not result is Dictionary:
		out.message = "伺服器回覆無效。"
		return out
	var source: Dictionary = result
	out.ok = source.get("ok") == true
	out.message = _text(source.get("message"), MAX_MESSAGE)
	for flag in FLAGS:
		if source.get(flag) == true:
			out[flag] = true
	for field in MATERIAL_FIELDS:
		if source.has(field):
			out[field] = _materials(source[field], item_names)
	for field in COUNT_FIELDS:
		if source.has(field):
			out[field] = _count(source[field])
	if source.has("problems"):
		out.problems = _problems(source.problems)
	if source.has("hash"):
		out.hash = str(source.hash) if valid_hash(source.hash) else ""
	if source.has("undoable"):
		out.undoable = source.undoable == true
	if nested and source.get("quote") is Dictionary:
		out.quote = sanitize(source.quote, item_names, false)
	return out

static func _text(value: Variant, limit: int) -> String:
	return str(value).left(limit) if typeof(value) == TYPE_STRING else ""

static func _count(value: Variant) -> int:
	# Saved receipts pass through JSON, whose whole numbers reload as floats.
	# Accept those exact integers, but never coerce bools, strings or fractions.
	if typeof(value) not in [TYPE_INT,TYPE_FLOAT]:return 0
	var amount:=float(value)
	return int(amount) if is_finite(amount) and amount>=0 and amount<=MAX_COUNT and amount==floorf(amount) else 0

static func _materials(value: Variant, item_names: Dictionary) -> Dictionary:
	var out := {}
	if not value is Dictionary:
		return out
	var source: Dictionary = value
	var names: Array = []
	for item in source:
		if typeof(item) == TYPE_STRING and item_names.has(item):
			names.append(item)
	names.sort()
	for item in names:
		var amount:=_count(source[item])
		if amount>0:out[item]=amount
	return out

static func _problems(value: Variant) -> Array:
	var out: Array = []
	if not value is Array:
		return out
	for entry in value:
		if out.size() >= MAX_PROBLEMS:
			break
		if not entry is Dictionary:
			continue
		var x: Variant = entry.get("x")
		var y: Variant = entry.get("y")
		if typeof(x) != TYPE_INT or typeof(y) != TYPE_INT or absi(int(x)) > PROBLEM_COORD_LIMIT or absi(int(y)) > PROBLEM_COORD_LIMIT:
			continue
		out.append({"x": int(x), "y": int(y), "kind": _text(entry.get("kind"), MAX_KIND),
			"reason": _text(entry.get("reason"), MAX_REASON)})
	return out
