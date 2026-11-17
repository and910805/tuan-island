extends RefCounted
## Pure, deterministic material supply planner used by MaterialSources for
## explicit backpack/chest confirmation and atomic World action staging.
##
## Allocates one recipe's costs across the player's backpack FIRST and then a
## single chest that the caller has already chosen AND authorised. This helper
## does no chest discovery, access/permission checks, clocks, source linking,
## refunds, saving or UI. It never mutates its arguments.
##
## plan(cost, backpack, chest = {}) -> Dictionary
##   cost:     {item: count >= 1}, non-empty, at most COST_ENTRIES_MAX entries
##   backpack: {item: count >= 0}
##   chest:    {item: count >= 0}
##   Keys must be non-empty Strings or StringNames of at most ITEM_KEY_MAX characters; counts
##   must be whole finite int/float values within 0..ITEM_CAP (bool, String
##   and other variants are rejected). JSON whole floats (2.0) normalise to int.
##   Backpack and chest are validated separately: their combined stock may
##   exceed ITEM_CAP and is never summed into a capped inventory.
##
## Success:
##   {ok:true, from_backpack, from_chest, missing:{}, backpack_after,
##    chest_after, supplied_inventory}
##   - from_backpack / from_chest list only positive debits.
##   - backpack_after: normalised copy of the backpack (unrelated and zero
##     entries kept) minus from_backpack; every cost item is present (0 when it
##     came entirely from the chest), matching CookingQueue.enqueue output.
##   - chest_after: normalised copy of the chest (unrelated and zero entries
##     kept) minus from_chest.
##   - supplied_inventory: normalised backpack plus only the from_chest top-ups.
##     Passing it to CookingQueue.enqueue (which deducts the full cost) yields
##     exactly backpack_after. Top-ups only cover the shortage up to the cost,
##     so each supplied count stays <= the cost (<= ITEM_CAP) or the original.
##   All returned dictionaries are freshly built and independent.
##
## Insufficient stock:
##   {ok:false, message, missing:{positive shortages}, from_backpack, from_chest}
##   (the debits that would have been drawn; no *_after / supplied output).
## Malformed input:
##   {ok:false, message}

const ITEM_CAP := 1000000000 # Match CookingQueue.ITEM_CAP.
const ITEM_KEY_MAX := 64 # Match CookingQueue.ITEM_KEY_MAX.
const COST_ENTRIES_MAX := 64 # Match CookingQueue ingredient snapshot limit.

const MSG_COST := "材料需求資料無效"
const MSG_BACKPACK := "背包資料無效"
const MSG_CHEST := "儲物箱資料無效"
const MSG_SAME_SOURCE := "背包與儲物箱不可為同一份資料"
const MSG_SHORT := "材料不足"


static func plan(cost: Variant, backpack: Variant, chest: Variant = {}) -> Dictionary:
	var parsed_cost: Variant = _parse(cost, 1)
	if not parsed_cost is Dictionary:
		return _fail(MSG_COST)
	var need: Dictionary = parsed_cost
	if need.is_empty() or need.size() > COST_ENTRIES_MAX:
		return _fail(MSG_COST)
	var parsed_bag: Variant = _parse(backpack, 0)
	if not parsed_bag is Dictionary:
		return _fail(MSG_BACKPACK)
	var bag: Dictionary = parsed_bag
	var parsed_box: Variant = _parse(chest, 0)
	if not parsed_box is Dictionary:
		return _fail(MSG_CHEST)
	var box: Dictionary = parsed_box
	# The same non-empty dictionary passed twice would double count its stock.
	if is_same(backpack, chest) and not bag.is_empty():
		return _fail(MSG_SAME_SOURCE)

	var items: Array = need.keys()
	items.sort() # Stable lexical traversal independent of input order.
	var from_backpack: Dictionary = {}
	var from_chest: Dictionary = {}
	var missing: Dictionary = {}
	for item: Variant in items:
		var want: int = need[item]
		var take_bag: int = mini(want, int(bag.get(item, 0)))
		var rest: int = want - take_bag
		var take_box: int = mini(rest, int(box.get(item, 0)))
		var short: int = rest - take_box
		if take_bag > 0:
			from_backpack[item] = take_bag
		if take_box > 0:
			from_chest[item] = take_box
		if short > 0:
			missing[item] = short

	if not missing.is_empty():
		return {
			"ok": false, "message": MSG_SHORT, "missing": missing,
			"from_backpack": from_backpack, "from_chest": from_chest,
		}

	var backpack_after: Dictionary = bag.duplicate()
	var supplied: Dictionary = bag.duplicate()
	var chest_after: Dictionary = box.duplicate()
	for item: Variant in items:
		var held: int = int(bag.get(item, 0))
		var topup: int = int(from_chest.get(item, 0))
		var used: int = int(from_backpack.get(item, 0))
		backpack_after[item] = held - used
		if topup > 0:
			supplied[item] = held + topup
			chest_after[item] = int(box[item]) - topup
	return {
		"ok": true, "from_backpack": from_backpack, "from_chest": from_chest,
		"missing": {}, "backpack_after": backpack_after, "chest_after": chest_after,
		"supplied_inventory": supplied,
	}


# ---------------------------------------------------------------- internals

static func _fail(message: String) -> Dictionary:
	return {"ok": false, "message": message}


## Returns a fresh {item: int} dictionary, or null when anything is malformed.
static func _parse(raw: Variant, minimum: int) -> Variant:
	if not raw is Dictionary:
		return null
	var source: Dictionary = raw
	var out: Dictionary = {}
	for key: Variant in source:
		if not _item_key(key) or not _is_count(source[key], minimum):
			return null
		out[str(key)] = int(source[key])
	return out


static func _item_key(value: Variant) -> bool:
	if not (value is String or value is StringName):
		return false
	var text := str(value)
	return not text.is_empty() and text.length() <= ITEM_KEY_MAX


static func _is_count(value: Variant, minimum: int) -> bool:
	if not (value is int or value is float):
		return false
	var number: float = float(value)
	if not is_finite(number):
		return false
	return number >= minimum and number <= ITEM_CAP and floorf(number) == number
