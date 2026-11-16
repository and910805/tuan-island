extends RefCounted
## T013 item definitions and data validation: the one authoritative check for
## item IDs and per-item stack limits.
##
## Source data stays where it already lives: World.NAMES (world.gd) is the item
## registry, item_id -> display name. This script does not copy, rename or
## reorder it; current_definitions() reads it at runtime and load_definitions()
## validates it. Every current item gets the existing per-item ceiling of
## 1,000,000,000 (= SaveSchema.whole default, the LIMIT/ITEM_CAP constants in
## the feature scripts), so nothing about inventories, saves or protocol changes.
##
## load_definitions() is all-or-nothing: one bad record rejects the whole set
## and returns an empty catalog plus a list of {index,id,code} errors. It never
## calls push_error (callers decide how to surface errors).
##
## Rejected: non-Array input, non-Dictionary records, unknown fields, IDs that
## are not String / empty / over 64 chars (SaveSchema.counts key limit) / not
## [a-z0-9_], duplicate IDs, missing or empty names, and stack limits that are
## negative, zero, fractional, non-numeric, non-finite or above the ceiling.
## A missing stack_limit means STACK_CEILING.
##
## Runtime path: SaveSchema.counts (every player inventory, object/chest items
## and job ingredients on load) checks each count against saved_count_limit().
## If the shipped catalog fails validation, counts() rejects every dictionary.
##
## Legacy saves: SaveSchema.counts still accepts any String key <= 64 chars, so
## an inventory holding an ID that is not in the catalog keeps loading.
## stack_limit()/saved_count_limit() give such IDs the same STACK_CEILING they
## already had, and inventory_report() lists them as "unknown" without failing.

const STACK_CEILING := 1000000000
const ID_MAX_LENGTH := 64
const FIELDS := ["id", "name", "stack_limit"]

const CODE_NOT_ARRAY := "definitions_not_array"
const CODE_NOT_RECORD := "record_not_dictionary"
const CODE_UNKNOWN_FIELD := "unknown_field"
const CODE_INVALID_ID := "invalid_id"
const CODE_DUPLICATE_ID := "duplicate_id"
const CODE_INVALID_NAME := "invalid_name"
const CODE_LIMIT_NOT_WHOLE := "stack_limit_not_whole"
const CODE_NEGATIVE_LIMIT := "negative_stack_limit"
const CODE_ZERO_LIMIT := "zero_stack_limit"
const CODE_LIMIT_OVER_CEILING := "stack_limit_over_ceiling"
const CODE_EMPTY_CATALOG := "shipped_catalog_empty"

static var _current: Dictionary = {}

static func valid_id(id) -> bool:
	if not id is String or id.is_empty() or id.length() > ID_MAX_LENGTH:
		return false
	for i in id.length():
		var c: int = id.unicode_at(i)
		if not ((c >= 97 and c <= 122) or (c >= 48 and c <= 57) or c == 95):
			return false
	return true

## "" when value is an acceptable stack limit, otherwise the error code.
static func stack_limit_error(value) -> String:
	if value is bool or not (value is int or value is float):
		return CODE_LIMIT_NOT_WHOLE
	if value is float and (not is_finite(value) or floorf(value) != value):
		return CODE_LIMIT_NOT_WHOLE
	if value < 0:
		return CODE_NEGATIVE_LIMIT
	if value == 0:
		return CODE_ZERO_LIMIT
	if value > STACK_CEILING:
		return CODE_LIMIT_OVER_CEILING
	return ""

## Validate an Array of {"id","name","stack_limit"?} records. Input is never
## mutated. Result: {"ok", "errors", "items": {id: {"name","stack_limit"}},
## "order": [ids in input order]}; items/order are empty unless ok.
static func load_definitions(records) -> Dictionary:
	var errors: Array = []
	var items: Dictionary = {}
	var order: Array = []
	if not records is Array:
		errors.append({"index": -1, "id": "", "code": CODE_NOT_ARRAY})
		return {"ok": false, "errors": errors, "items": {}, "order": []}
	var seen: Dictionary = {}
	for index in records.size():
		var record = records[index]
		if not record is Dictionary:
			errors.append({"index": index, "id": "", "code": CODE_NOT_RECORD})
			continue
		var id = record.get("id")
		var label: String = id if id is String else ""
		var before := errors.size()
		for field in record:
			if not field is String or not field in FIELDS:
				errors.append({"index": index, "id": label, "code": CODE_UNKNOWN_FIELD})
				break
		if not valid_id(id):
			errors.append({"index": index, "id": label, "code": CODE_INVALID_ID})
		elif seen.has(id):
			errors.append({"index": index, "id": label, "code": CODE_DUPLICATE_ID})
		else:
			seen[id] = index
		var name = record.get("name")
		if not name is String or name.is_empty():
			errors.append({"index": index, "id": label, "code": CODE_INVALID_NAME})
		var limit = record.get("stack_limit", STACK_CEILING)
		var limit_code := stack_limit_error(limit)
		if not limit_code.is_empty():
			errors.append({"index": index, "id": label, "code": limit_code})
		if errors.size() == before:
			items[id] = {"name": name, "stack_limit": int(limit)}
			order.append(id)
	if not errors.is_empty():
		return {"ok": false, "errors": errors, "items": {}, "order": []}
	return {"ok": true, "errors": [], "items": items, "order": order}

## The shipped item definitions, read from World.NAMES in its declared order.
## World is loaded at call time (not preloaded): world.gd preloads
## save_schema.gd, which preloads this script, so a preload here would be a
## cycle. This script has no preloads at all.
static func current_definitions() -> Array:
	var records: Array = []
	var world = load("res://scripts/world.gd")
	if not world is Script:
		return records
	var names = world.get_script_constant_map().get("NAMES", {})
	if not names is Dictionary:
		return records
	for id in names:
		records.append({"id": id, "name": names[id], "stack_limit": STACK_CEILING})
	return records

## Validated shipped catalog (cached). ok=false here means shipped data is broken;
## every limit lookup then fails closed (stack_limit 0, saved_count_limit -1).
## An empty shipped catalog (World.NAMES missing/unreadable) is also broken:
## otherwise every ID would look "unknown legacy" and get the full ceiling.
static func current() -> Dictionary:
	if _current.is_empty():
		var result: Dictionary = load_definitions(current_definitions())
		if result.ok and result.order.is_empty():
			result = {"ok": false, "errors": [{"index": -1, "id": "", "code": CODE_EMPTY_CATALOG}], "items": {}, "order": []}
		_current = result
	return _current

## Test-only: replace the cached shipped catalog with a load_definitions()
## result (e.g. a rejected one, to prove SaveSchema.counts fails closed).
## Always pair with reset_current().
static func override_current(result: Dictionary) -> void:
	_current = result.duplicate(true)

## Drop the cache; the next current() re-validates World.NAMES.
static func reset_current() -> void:
	_current = {}

static func is_known(id) -> bool:
	return id is String and current().items.has(id)

## Catalog limit for known IDs; STACK_CEILING for legacy/unknown String IDs so
## existing saves keep their current ceiling. 0 for keys no save could hold,
## and 0 for every ID when the shipped catalog is invalid (fail closed).
static func stack_limit(id) -> int:
	if not id is String or id.is_empty() or id.length() > ID_MAX_LENGTH:
		return 0
	var catalog := current()
	if not catalog.ok:
		return 0
	var item = catalog.items.get(id)
	return int(item.stack_limit) if item is Dictionary else STACK_CEILING

## Count ceiling used by SaveSchema.counts for a key it has already accepted
## (String, <= ID_MAX_LENGTH). Same as stack_limit() except it keeps the
## legacy behaviour for keys stack_limit() calls unholdable (the empty String):
## SaveSchema.counts has always accepted them up to STACK_CEILING. Returns -1
## when the shipped catalog is invalid so the caller rejects (fail closed).
static func saved_count_limit(id) -> int:
	var catalog := current()
	if not catalog.ok:
		return -1
	var item = catalog.items.get(id)
	return int(item.stack_limit) if item is Dictionary else STACK_CEILING

static func can_hold(id, count) -> bool:
	if count is bool or not (count is int or count is float):
		return false
	if count is float and (not is_finite(count) or floorf(count) != count):
		return false
	return count >= 0 and count <= stack_limit(id)

## Read-only check of an item-count Dictionary (inventory, chest items...).
## ok is false only for entries SaveSchema.counts would also refuse (bad key,
## bad count) or counts above the item's limit. Unknown-but-valid legacy IDs
## are listed, not refused.
static func inventory_report(bag) -> Dictionary:
	var report := {"ok": false, "invalid": [], "over": [], "unknown": []}
	if not bag is Dictionary:
		return report
	for key in bag:
		if stack_limit(key) == 0 or bag[key] is bool or not (bag[key] is int or bag[key] is float):
			report.invalid.append(str(key))
		elif not can_hold(key, bag[key]):
			var count := float(bag[key])
			if is_finite(count) and floorf(count) == count and count > float(stack_limit(key)):
				report.over.append(key)
			else:
				report.invalid.append(key)
		if key is String and stack_limit(key) > 0 and not is_known(key):
			report.unknown.append(key)
	report.ok = report.invalid.is_empty() and report.over.is_empty()
	return report
