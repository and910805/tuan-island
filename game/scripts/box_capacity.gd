extends RefCounted
## C06/C07 共用木箱 (chest) and 私人木箱 (private_chest): 16 storage slots.
##
## One slot = one item ID in the existing `items` count map ({item_id: count}); a
## stack is still bounded only by LIMIT. This is the single capacity rule that every
## real insertion path asks before it writes into a chest:
##   manual deposit/deposit_half/deposit_all/deposit_exact (World.act), conveyor
##   delivery (Logistics), mine freight + auto freight (MineFreight), livestock
##   collector chests (Livestock) and salt-pan collectors (SaltPan).
## Not covered on purpose: supply_box (own semantics), acorn cabinet (its own
## Industry.CABINET_SLOTS rule), machine buffers and display furniture.
##
## Legacy saves may hold more than SLOTS entries. Nothing is truncated or migrated:
## those entries stay visible/withdrawable, stacking into an entry that already
## holds items is still allowed, and any NEW item ID is refused while the box has
## SLOTS or more occupied entries. An entry whose count is 0 (left behind by a
## withdraw) is not occupying a slot.
const SLOTS := 16
const KINDS := ["chest", "private_chest"]
const LIMIT := 1000000000
const FULL_MESSAGE := "箱子的 16 格已滿，請先取出一種物品，或改存箱內已有的物品。"
const BELT_FULL := "前方儲物箱的 16 格已滿"

static func applies(kind: Variant) -> bool:
	return (kind is String or kind is StringName) and str(kind) in KINDS

static func occupied(items: Variant) -> int:
	if not items is Dictionary:return 0
	var used := 0
	for id in items:
		if int(items[id]) > 0:used += 1
	return used

## Entries beyond SLOTS in a legacy save (0 when within capacity).
static func overflow(items: Variant) -> int:
	return maxi(0, occupied(items) - SLOTS)

static func is_full(items: Variant) -> bool:
	return occupied(items) >= SLOTS

static func has_item(items: Variant, id: String) -> bool:
	return items is Dictionary and int(items.get(id, 0)) > 0

## Distinct IDs in `additions` (positive amounts only) that would need a new slot.
static func new_kinds(items: Variant, additions: Dictionary) -> int:
	var count := 0
	for id in additions:
		if int(additions[id]) > 0 and not has_item(items, str(id)):count += 1
	return count

## Slot rule only (no stack limit): true when every new ID still gets a slot.
static func slot_ok(items: Variant, additions: Dictionary) -> bool:
	var fresh := new_kinds(items, additions)
	return fresh == 0 or occupied(items) + fresh <= SLOTS

## Slot rule plus the per-stack LIMIT.
static func can_accept(items: Variant, additions: Dictionary) -> bool:
	if not slot_ok(items, additions):return false
	var held: Dictionary = items if items is Dictionary else {}
	for id in additions:
		var amount := int(additions[id])
		if amount > 0 and int(held.get(id, 0)) > LIMIT - amount:return false
	return true

## Of `ordered` ids (each about to receive at least one unit, most important first)
## the ones that must be skipped because no slot is left for them.
static func refused(items: Variant, ordered: Array) -> Array:
	var free := maxi(0, SLOTS - occupied(items))
	var out: Array = []
	for id in ordered:
		if has_item(items, str(id)):continue
		if free > 0:free -= 1
		else:out.append(id)
	return out

## {used, slots, overflow, full} for UI text and tests.
static func summary(items: Variant) -> Dictionary:
	var used := occupied(items)
	return {"used": used, "slots": SLOTS, "overflow": maxi(0, used - SLOTS), "full": used >= SLOTS}

static func usage_text(capacity: Dictionary) -> String:
	var text:="已用 %d / %d 格" % [capacity.used, capacity.slots]
	if capacity.overflow>0:
		return text+"  ·  舊存檔超出 %d 格，物品可照常取出"%capacity.overflow
	if capacity.full:
		return text+"  ·  已滿，可繼續存入已有的物品"
	return text
