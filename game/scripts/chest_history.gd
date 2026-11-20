extends RefCounted

const FIELD := "recent_transfers"
const READ_ACTION := "read_chest_history"
const MAX_ENTRIES := 200
const BOXES := ["chest", "private_chest"]
const MAX_AMOUNT := 1000000000
const MAX_TIME := 1000000000000.0

## Keep the display history on the box so that moving it preserves its entries.
## Store the displayed name at the time of the transfer without account tokens.
## The town clock displays whole game minutes, stored here as whole world seconds.
static func record(box: Dictionary, actor: String, item: String, amount: int, depositing: bool, time: float) -> void:
	if box.get("type") not in BOXES:
		return
	# Replace the list so a synchronous world-step checkpoint may retain it.
	var recent: Array = box.get(FIELD, []).duplicate()
	recent.push_back({"actor": actor.left(12), "item": item, "amount": amount, "depositing": depositing, "time": floori(time)})
	if recent.size() > MAX_ENTRIES:
		recent.pop_front()
	box[FIELD] = recent

static func valid(box: Dictionary, known_item: Callable) -> bool:
	if not box.has(FIELD):
		return true
	var recent: Variant = box[FIELD]
	if box.get("type") not in BOXES or not recent is Array or recent.size() > MAX_ENTRIES:
		return false
	for row: Variant in recent:
		if not row is Dictionary or row.size() != 5:
			return false
		var actor: Variant = row.get("actor")
		var item: Variant = row.get("item")
		if not actor is String or actor.length() > 12 or not item is String or not known_item.call(item):
			return false
		if not row.get("depositing") is bool or not _in_bounds(row.get("time"), 0, MAX_TIME):
			return false
		var amount: Variant = row.get("amount")
		if not _in_bounds(amount, 1, MAX_AMOUNT) or floorf(float(amount)) != float(amount):
			return false
	return true

static func normalize(box: Dictionary) -> void:
	for row: Dictionary in box[FIELD]:
		row.amount = int(row.amount)
		row.time = floori(float(row.time))

static func _in_bounds(value: Variant, minimum: float, maximum: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= minimum and value <= maximum
