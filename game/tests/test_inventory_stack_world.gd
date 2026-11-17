extends SceneTree

## T014 inventory stack moves between backpack and chests (real World, no mocks).
##
## Contract under test (World.act -> _apply chest branch):
##   deposit / withdraw            -> 1 unit, messages "已存入<名>" / "已取出<名>" (legacy)
##   deposit_half / withdraw_half  -> ceil(source/2) units, "已存入<名> ×n" / "已取出<名> ×n"
##   deposit_all / withdraw_all    -> whole source stack, same "×n" message
## Every refusal leaves BOTH sides (and the whole state) unchanged; no clamping.
##
## Disclosed fixture presets (written directly into world.state, not earned in play):
##   - chests / private_chest / supply_box / stove objects written into state.objects
##     with the same shape `build` creates ({"type","owner","items"}).
##   - player.inventory and box.items counts (including values near the
##     1,000,000,000 cap) and player x/y/region.
##   - a beimen chest written into the beimen object layer via switch_region.

const World = preload("res://scripts/world.gd")
const Schema = preload("res://scripts/save_schema.gd")
const Perm = preload("res://scripts/plot_permissions.gd")
const CELL := Vector2i(38, 33)
const PRIVATE_CELL := Vector2i(37, 34)
const SUPPLY_CELL := Vector2i(40, 34)
const STOVE_CELL := Vector2i(39, 32)
const EMPTY_CELL := Vector2i(41, 33)
const SPOT := Vector2(39.5, 33.5)
const LIMIT := 1000000000
const NEW_ACTIONS := ["deposit_half", "withdraw_half", "deposit_all", "withdraw_all"]
const ALL_ACTIONS := ["deposit", "withdraw", "deposit_half", "withdraw_half", "deposit_all", "withdraw_all"]
const NEAR_MSG := "靠近一點，才能和它互動"
var checks := 0
var failures := 0
var sequence := 0

func _initialize() -> void:
	call_deferred("run")

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL " + message)

# ------------------------------------------------------------------ helpers --

func fresh():
	var w = World.new()
	w.add_player("alice", "阿米")
	w.add_player("bob", "小豆")
	pose(w, "alice", SPOT)
	pose(w, "bob", SPOT)
	place(w, CELL, "chest", "alice", {})
	return w

func pose(w, token: String, at: Vector2) -> void:
	var p: Dictionary = w.state.players[token]
	p.region = World.REGIONS.HOME  # PRESET
	p.x = at.x  # PRESET
	p.y = at.y  # PRESET

func place(w, cell: Vector2i, kind: String, owner: String, contents: Dictionary) -> void:
	w.state.objects[World.key(cell)] = {"type": kind, "owner": owner, "items": contents.duplicate(true)}  # PRESET

func label_of(item: String) -> String:
	return str(World.NAMES[item])

func bag(w, token: String) -> Dictionary:
	var players = w.state.get("players", {})
	if not players is Dictionary:
		return {}
	var person = players.get(token, {})
	if not person is Dictionary:
		return {}
	var inv = person.get("inventory", {})
	return inv if inv is Dictionary else {}

func items(w, cell: Vector2i) -> Dictionary:
	var box = w.state.objects.get(World.key(cell), {})
	if not box is Dictionary:
		return {}
	var found = box.get("items", {})
	return found if found is Dictionary else {}

func held(w, token: String, item: String) -> int:
	return int(bag(w, token).get(item, 0))

func stored(w, cell: Vector2i, item: String) -> int:
	return int(items(w, cell).get(item, 0))

func set_held(w, token: String, item: String, amount: int) -> void:
	bag(w, token)[item] = amount  # PRESET

func set_stored(w, cell: Vector2i, item: String, amount: int) -> void:
	items(w, cell)[item] = amount  # PRESET

func total(w, item: String, tokens: Array, cells: Array) -> int:
	var sum := 0
	for t in tokens:
		sum += held(w, str(t), item)
	for c in cells:
		sum += stored(w, c, item)
	return sum

func receipts(w, token: String) -> Dictionary:
	var person = w.state.players.get(token, {})
	if not person is Dictionary:
		return {}
	var found = person.get("receipts", {})
	return found if found is Dictionary else {}

func next_id(id: String = "") -> String:
	if not id.is_empty():
		return id
	sequence += 1
	return "stack-%d" % sequence

func act(w, token: String, action: String, cell: Vector2i, extra: String = "", id: String = "") -> Dictionary:
	var raw = w.act(token, next_id(id), action, cell, extra)
	return raw if raw is Dictionary else {"ok": false, "message": ""}

func without(source: Dictionary, item: String) -> Dictionary:
	var copy: Dictionary = source.duplicate(true)
	copy.erase(item)
	return copy

func moved_message(action: String, item: String, n: int) -> String:
	var verb := "存入" if action.begins_with("deposit") else "取出"
	if action in ["deposit", "withdraw"]:
		return "已" + verb + label_of(item)
	return "已%s%s ×%d" % [verb, label_of(item), n]

## One accepted move: exact message, exact deltas on both sides, every other
## entry on both sides untouched, per-item conservation, plain int counts.
func moved(w, label: String, token: String, action: String, cell: Vector2i, item: String, n: int, id: String = "") -> Dictionary:
	var storing := action.begins_with("deposit")
	var bag_before := held(w, token, item)
	var box_before := stored(w, cell, item)
	var other_bag := without(bag(w, token), item)
	var other_box := without(items(w, cell), item)
	var result := act(w, token, action, cell, item, id)
	var message := str(result.get("message", ""))
	expect(bool(result.get("ok", false)), label + ": accepted (got '" + message + "')")
	expect(message == moved_message(action, item, n), label + ": message '" + message + "' == '" + moved_message(action, item, n) + "'")
	var delta := n if storing else -n
	expect(held(w, token, item) == bag_before - delta, label + ": backpack %d -> %d (expected %d)" % [bag_before, held(w, token, item), bag_before - delta])
	expect(stored(w, cell, item) == box_before + delta, label + ": box %d -> %d (expected %d)" % [box_before, stored(w, cell, item), box_before + delta])
	expect(held(w, token, item) + stored(w, cell, item) == bag_before + box_before, label + ": backpack+box total conserved")
	expect(without(bag(w, token), item) == other_bag, label + ": other backpack entries untouched")
	expect(without(items(w, cell), item) == other_box, label + ": other box entries untouched")
	expect(typeof(bag(w, token).get(item, 0)) == TYPE_INT and typeof(items(w, cell).get(item, 0)) == TYPE_INT, label + ": counts stay plain ints")
	return result

## One refused request: not ok, expected message, deep-equal state, both sides
## unchanged, no receipt stored for the request id.
func refused(w, label: String, token: String, action: String, cell: Vector2i, extra: String, message: String, id: String = "") -> Dictionary:
	var before: Dictionary = w.state.duplicate(true)
	var bag_before: Dictionary = bag(w, token).duplicate(true)
	var box_before: Dictionary = items(w, cell).duplicate(true)
	var request := next_id(id)
	var raw = w.act(token, request, action, cell, extra)
	var result: Dictionary = raw if raw is Dictionary else {"ok": true, "message": ""}
	var got := str(result.get("message", ""))
	expect(not bool(result.get("ok", true)), label + ": refused (got '" + got + "')")
	if not message.is_empty():
		expect(got == message, label + ": message '" + got + "' == '" + message + "'")
	expect(w.state == before, label + ": deep state equality")
	expect(bag(w, token) == bag_before, label + ": backpack unchanged")
	expect(items(w, cell) == box_before, label + ": box unchanged")
	expect(not receipts(w, token).has(request), label + ": refusal stored no receipt")
	return result

func valid(state: Dictionary) -> bool:
	return Schema.validate(state, World.CROPS, World.BUILD, World.RECIPES, World.SIZE, World.TREE_TIME)

## Key-order independent bytes (JSON sorts keys; live dictionaries keep
## insertion order). Same helper as test_salt_pan_world.
func sorted(v):
	if v is Dictionary:
		var keys: Array = v.keys().map(func(x): return str(x))
		keys.sort()
		var out := {}
		for k in keys:
			out[k] = sorted(v[k])
		return out
	if v is Array:
		return v.map(func(x): return sorted(x))
	return v

func canon(v) -> PackedByteArray:
	return var_to_bytes(sorted(v))

func json_form(v):
	return JSON.parse_string(JSON.stringify(v))

## Plain item_id -> whole-number count shape (JSON turns ints into floats).
func plain_counts(d: Dictionary) -> bool:
	for k in d:
		if typeof(k) != TYPE_STRING and typeof(k) != TYPE_STRING_NAME:
			return false
		var v = d[k]
		if typeof(v) == TYPE_INT:
			continue
		if typeof(v) == TYPE_FLOAT and float(v) == floorf(float(v)) and float(v) >= 0.0:
			continue
		return false
	return true

func same_counts(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for k in a:
		if not b.has(str(k)) and not b.has(k):
			return false
		var other = b.get(str(k), b.get(k, null))
		if other == null or int(a[k]) != int(other):
			return false
	return true

# -------------------------------------------------------------------- cases --

func test_half_and_all() -> void:
	var w = fresh()
	# Remove the other player's starter counts so the island-wide conservation
	# assertion below measures only the stacks moved by this case.
	set_held(w, "bob", "wood", 0)
	set_held(w, "bob", "stone", 0)
	set_held(w, "alice", "wood", 6)
	moved(w, "deposit_half even 6", "alice", "deposit_half", CELL, "wood", 3)
	moved(w, "deposit_half odd 3", "alice", "deposit_half", CELL, "wood", 2)
	moved(w, "deposit_half single 1", "alice", "deposit_half", CELL, "wood", 1)
	expect(held(w, "alice", "wood") == 0 and stored(w, CELL, "wood") == 6, "halves moved 3+2+1 into the chest")
	moved(w, "withdraw_half even 6", "alice", "withdraw_half", CELL, "wood", 3)
	moved(w, "withdraw_all 3", "alice", "withdraw_all", CELL, "wood", 3)
	expect(held(w, "alice", "wood") == 6 and stored(w, CELL, "wood") == 0, "withdraw half then all empties the chest stack")
	moved(w, "deposit_all 6", "alice", "deposit_all", CELL, "wood", 6)
	expect(held(w, "alice", "wood") == 0 and stored(w, CELL, "wood") == 6, "deposit_all moves the whole stack")
	set_held(w, "alice", "stone", 5)
	moved(w, "deposit_all 5", "alice", "deposit_all", CELL, "stone", 5)
	moved(w, "withdraw_half odd 5", "alice", "withdraw_half", CELL, "stone", 3)
	moved(w, "withdraw_half single 2->1", "alice", "withdraw_half", CELL, "stone", 1)
	moved(w, "withdraw_half single 1", "alice", "withdraw_half", CELL, "stone", 1)
	expect(held(w, "alice", "stone") == 5 and stored(w, CELL, "stone") == 0, "stone round trip conserved")
	expect(total(w, "wood", ["alice", "bob"], [CELL]) == 6 and total(w, "stone", ["alice", "bob"], [CELL]) == 5, "island totals unchanged by half/all moves")

func test_legacy() -> void:
	var w = fresh()
	set_held(w, "alice", "wood", 3)
	var r := moved(w, "legacy deposit", "alice", "deposit", CELL, "wood", 1)
	expect(str(r.get("message", "")) == "已存入" + label_of("wood"), "legacy deposit keeps the old message exactly")
	r = moved(w, "legacy withdraw", "alice", "withdraw", CELL, "wood", 1)
	expect(str(r.get("message", "")) == "已取出" + label_of("wood"), "legacy withdraw keeps the old message exactly")
	set_held(w, "alice", "wood", 3)
	refused(w, "deposit with quantity extra wood|5", "alice", "deposit", CELL, "wood|5", "無法存取這項物品")
	refused(w, "deposit_all with quantity extra wood|5", "alice", "deposit_all", CELL, "wood|5", "無法存取這項物品")
	expect(held(w, "alice", "wood") == 3 and stored(w, CELL, "wood") == 0, "quantity extras moved nothing")

func test_refusals() -> void:
	var w = fresh()
	set_held(w, "alice", "wood", 4)
	set_stored(w, CELL, "wood", 4)
	bag(w, "alice").erase("plank")  # PRESET item absent on both sides
	items(w, CELL).erase("plank")
	for action in ALL_ACTIONS:
		var storing: bool = str(action).begins_with("deposit")
		refused(w, action + ": item absent", "alice", action, CELL, "plank", "背包沒有這項物品" if storing else "箱子裡沒有這項物品")
		refused(w, action + ": unknown id", "alice", action, CELL, "not_an_item", "無法存取這項物品")
		refused(w, action + ": empty id", "alice", action, CELL, "", "無法存取這項物品")
	set_held(w, "alice", "plank", 0)
	set_stored(w, CELL, "plank", 0)
	for action in ALL_ACTIONS:
		var storing: bool = str(action).begins_with("deposit")
		refused(w, action + ": zero count entry", "alice", action, CELL, "plank", "背包沒有這項物品" if storing else "箱子裡沒有這項物品")
	# Wrong box type and empty cell.
	w.state.objects[World.key(STOVE_CELL)] = {"type": "stove"}  # PRESET
	w.state.objects.erase(World.key(EMPTY_CELL))
	for action in ALL_ACTIONS:
		refused(w, action + ": stove is not a box", "alice", action, STOVE_CELL, "wood", "這裡沒有箱子")
		refused(w, action + ": empty cell", "alice", action, EMPTY_CELL, "wood", "這裡沒有箱子")
	# Out of reach (same 3.2 gate as the legacy moves).
	pose(w, "alice", Vector2(30.5, 33.5))
	for action in ALL_ACTIONS:
		refused(w, action + ": out of reach", "alice", action, CELL, "wood", NEAR_MSG)
	pose(w, "alice", SPOT)
	expect(held(w, "alice", "wood") == 4 and stored(w, CELL, "wood") == 4, "no refusal moved any wood")

func test_limits() -> void:
	var w = fresh()
	expect(int(World.MINE_FREIGHT.LIMIT) == LIMIT, "single-item limit is 1000000000")
	# deposit_all of 4
	set_held(w, "alice", "wood", 4)
	set_stored(w, CELL, "wood", LIMIT)
	refused(w, "deposit_all: box at LIMIT", "alice", "deposit_all", CELL, "wood", "箱子中的物品已達上限")
	refused(w, "deposit legacy: box at LIMIT", "alice", "deposit", CELL, "wood", "箱子中的物品已達上限")
	set_stored(w, CELL, "wood", LIMIT - 3)
	refused(w, "deposit_all: box at LIMIT-n+1", "alice", "deposit_all", CELL, "wood", "箱子中的物品已達上限")
	set_stored(w, CELL, "wood", LIMIT - 4)
	moved(w, "deposit_all: box at LIMIT-n", "alice", "deposit_all", CELL, "wood", 4)
	expect(stored(w, CELL, "wood") == LIMIT and held(w, "alice", "wood") == 0, "deposit_all lands exactly on LIMIT")
	# deposit_half of 5 (n=3)
	set_held(w, "alice", "stone", 5)
	set_stored(w, CELL, "stone", LIMIT - 2)
	refused(w, "deposit_half: box at LIMIT-n+1", "alice", "deposit_half", CELL, "stone", "箱子中的物品已達上限")
	set_stored(w, CELL, "stone", LIMIT - 3)
	moved(w, "deposit_half: box at LIMIT-n", "alice", "deposit_half", CELL, "stone", 3)
	expect(stored(w, CELL, "stone") == LIMIT and held(w, "alice", "stone") == 2, "deposit_half lands exactly on LIMIT")
	# withdraw_all of 4
	set_stored(w, CELL, "fiber", 4)
	set_held(w, "alice", "fiber", LIMIT)
	refused(w, "withdraw_all: backpack at LIMIT", "alice", "withdraw_all", CELL, "fiber", "背包中的物品已達上限")
	refused(w, "withdraw legacy: backpack at LIMIT", "alice", "withdraw", CELL, "fiber", "背包中的物品已達上限")
	set_held(w, "alice", "fiber", LIMIT - 3)
	refused(w, "withdraw_all: backpack at LIMIT-n+1", "alice", "withdraw_all", CELL, "fiber", "背包中的物品已達上限")
	set_held(w, "alice", "fiber", LIMIT - 4)
	moved(w, "withdraw_all: backpack at LIMIT-n", "alice", "withdraw_all", CELL, "fiber", 4)
	expect(held(w, "alice", "fiber") == LIMIT and stored(w, CELL, "fiber") == 0, "withdraw_all lands exactly on LIMIT")
	# withdraw_half of 5 (n=3)
	set_stored(w, CELL, "plank", 5)
	set_held(w, "alice", "plank", LIMIT - 2)
	refused(w, "withdraw_half: backpack at LIMIT-n+1", "alice", "withdraw_half", CELL, "plank", "背包中的物品已達上限")
	set_held(w, "alice", "plank", LIMIT - 3)
	moved(w, "withdraw_half: backpack at LIMIT-n", "alice", "withdraw_half", CELL, "plank", 3)
	expect(held(w, "alice", "plank") == LIMIT and stored(w, CELL, "plank") == 2, "withdraw_half lands exactly on LIMIT")

func test_permissions() -> void:
	var w = fresh()
	place(w, PRIVATE_CELL, "private_chest", "alice", {"wood": 4})
	place(w, SUPPLY_CELL, "supply_box", "alice", {"wood": 5})
	set_held(w, "bob", "wood", 3)
	set_held(w, "alice", "wood", 0)
	for spec in [[PRIVATE_CELL, "private_chest"], [SUPPLY_CELL, "supply_box"]]:
		var cell: Vector2i = spec[0]
		var kind: String = spec[1]
		var verdict: Dictionary = Perm.can_take("bob", w.state.objects[World.key(cell)])
		expect(not bool(verdict.get("ok", true)), kind + ": module refuses the guest")
		for action in ALL_ACTIONS:
			refused(w, kind + " guest " + action, "bob", action, cell, "wood", str(verdict.get("message", "")))
	moved(w, "private_chest owner withdraw_half", "alice", "withdraw_half", PRIVATE_CELL, "wood", 2)
	moved(w, "private_chest owner deposit_all", "alice", "deposit_all", PRIVATE_CELL, "wood", 2)
	moved(w, "private_chest owner withdraw_all", "alice", "withdraw_all", PRIVATE_CELL, "wood", 4)
	moved(w, "supply_box owner withdraw_all", "alice", "withdraw_all", SUPPLY_CELL, "wood", 5)
	moved(w, "supply_box owner deposit_half", "alice", "deposit_half", SUPPLY_CELL, "wood", 5)
	# Shared chest is open to guests.
	set_stored(w, CELL, "wood", 5)
	moved(w, "shared chest guest withdraw_half", "bob", "withdraw_half", CELL, "wood", 3)
	moved(w, "shared chest guest deposit_all", "bob", "deposit_all", CELL, "wood", 6)
	expect(total(w, "wood", ["alice", "bob"], [CELL, PRIVATE_CELL, SUPPLY_CELL]) == 3 + 4 + 5 + 5, "wood conserved across all permission cases")
	set_held(w,"bob","wood",3)
	refused(w,"guest cannot open access","bob","box_deposit_access",PRIVATE_CELL,"island","只有私人箱的主人能調整存入權限。")
	refused(w,"supply box cannot grant access","alice","box_deposit_access",SUPPLY_CELL,"island","只有私人箱的主人能調整存入權限。")
	expect(w.act("alice","allow-deposits","box_deposit_access",PRIVATE_CELL,"island").ok,"Owner can allow deposits")
	moved(w,"guest can put half a stack into the private chest","bob","deposit_half",PRIVATE_CELL,"wood",2)
	refused(w,"guest still cannot take the deposit back","bob","withdraw",PRIVATE_CELL,"wood",Perm.MSG_FOREIGN_BOX)
	expect(w.act("alice","close-deposits","box_deposit_access",PRIVATE_CELL,"owner").ok,"Owner can close guest deposits")
	refused(w,"guest cannot deposit after access closes","bob","deposit",PRIVATE_CELL,"wood",Perm.MSG_FOREIGN_BOX)

func test_race() -> void:
	var w = fresh()
	set_held(w, "alice", "wood", 0)
	set_held(w, "bob", "wood", 0)
	set_stored(w, CELL, "wood", 5)
	var everyone := ["alice", "bob"]
	var cells := [CELL]
	var start := total(w, "wood", everyone, cells)
	moved(w, "race: alice withdraw_all first", "alice", "withdraw_all", CELL, "wood", 5)
	refused(w, "race: bob withdraw_all second", "bob", "withdraw_all", CELL, "wood", "箱子裡沒有這項物品")
	expect(held(w, "alice", "wood") == 5 and held(w, "bob", "wood") == 0 and stored(w, CELL, "wood") == 0, "race: only the first withdraw_all is paid")
	expect(total(w, "wood", everyone, cells) == start, "race: wood total conserved")
	# Interleaved half then all: both succeed on what is actually left.
	set_stored(w, CELL, "stone", 5)
	set_held(w, "alice", "stone", 0)
	set_held(w, "bob", "stone", 0)
	moved(w, "race: alice withdraw_half 5", "alice", "withdraw_half", CELL, "stone", 3)
	moved(w, "race: bob withdraw_all remaining 2", "bob", "withdraw_all", CELL, "stone", 2)
	refused(w, "race: alice withdraw_half on empty", "alice", "withdraw_half", CELL, "stone", "箱子裡沒有這項物品")
	expect(total(w, "stone", everyone, cells) == 5, "race: stone total conserved")
	# Two depositors racing into a nearly full box.
	set_stored(w, CELL, "fiber", LIMIT - 5)
	set_held(w, "alice", "fiber", 5)
	set_held(w, "bob", "fiber", 1)
	moved(w, "race: alice deposit_all fills to LIMIT", "alice", "deposit_all", CELL, "fiber", 5)
	refused(w, "race: bob deposit_all after LIMIT", "bob", "deposit_all", CELL, "fiber", "箱子中的物品已達上限")
	expect(total(w, "fiber", everyone, cells) == LIMIT + 1, "race: fiber total conserved")

func test_retry() -> void:
	var w = fresh()
	set_held(w, "alice", "wood", 6)
	var first := moved(w, "retry: first deposit_half", "alice", "deposit_half", CELL, "wood", 3, "t014-retry")
	var bag_after := held(w, "alice", "wood")
	var box_after := stored(w, CELL, "wood")
	expect(receipts(w, "alice").has("t014-retry"), "retry: success stored a receipt")
	var again := act(w, "alice", "deposit_half", CELL, "wood", "t014-retry")
	expect(again == first, "retry: same request id returns the identical result")
	expect(held(w, "alice", "wood") == bag_after and stored(w, CELL, "wood") == box_after, "retry: no second move")
	var other := act(w, "alice", "withdraw_all", CELL, "wood", "t014-retry")
	expect(other == first and held(w, "alice", "wood") == bag_after and stored(w, CELL, "wood") == box_after, "retry: reused id with another action replays the receipt, no move")
	# A refused request stores nothing, so the same id can succeed later.
	set_held(w, "alice", "stone", 0)
	refused(w, "retry: refused deposit_all", "alice", "deposit_all", CELL, "stone", "背包沒有這項物品", "t014-late")
	set_held(w, "alice", "stone", 2)
	moved(w, "retry: same id after refusal", "alice", "deposit_all", CELL, "stone", 2, "t014-late")
	var replay := act(w, "alice", "deposit_all", CELL, "stone", "t014-late")
	expect(bool(replay.get("ok", false)) and held(w, "alice", "stone") == 0 and stored(w, CELL, "stone") == 2, "retry: late success also deduplicates")

func beimen_items(w, cell: Vector2i) -> Dictionary:
	w.switch_region(World.SALT_PAN.REGION)
	var found = w.state.objects.get(World.key(cell), {})
	var copy: Dictionary = {}
	if found is Dictionary and found.get("items", {}) is Dictionary:
		copy = found.get("items", {}).duplicate(true)
	w.switch_region(World.REGIONS.HOME)
	return copy

func test_regions() -> void:
	# Tianwei flower region: rejected exactly like deposit/withdraw.
	var w = fresh()
	set_held(w, "alice", "wood", 4)
	set_stored(w, CELL, "wood", 4)
	w.state.players.alice.region = World.FLOWER_NURSERY.REGION  # PRESET standing in Tianwei
	for action in ALL_ACTIONS:
		refused(w, "tianwei " + action, "alice", action, CELL, "wood", World.FLOWER_REJECT_MSG)
	for action in NEW_ACTIONS:
		expect(action in World.FLOWER_REJECTED, "FLOWER_REJECTED lists " + action)
	# Beimen salt pans: allowed like deposit/withdraw.
	w = fresh()
	var arrival := Vector2(World.SALT_PAN.ARRIVAL)
	var cell := Vector2i(int(arrival.x) + 1, int(arrival.y))
	var alice: Dictionary = w.state.players.alice
	alice.region = World.SALT_PAN.REGION  # PRESET standing in Beimen
	alice.x = arrival.x
	alice.y = arrival.y
	w.switch_region(World.SALT_PAN.REGION)
	w.state.objects[World.key(cell)] = {"type": "chest", "owner": "alice", "items": {"sea_salt": 4}}  # PRESET
	w.switch_region(World.REGIONS.HOME)
	set_held(w, "alice", "wood", 5)
	set_held(w, "alice", "sea_salt", 0)
	var r := act(w, "alice", "deposit_half", cell, "wood")
	expect(bool(r.get("ok", false)) and str(r.get("message", "")) == moved_message("deposit_half", "wood", 3), "beimen deposit_half accepted: " + str(r.get("message", "")))
	expect(held(w, "alice", "wood") == 2 and int(beimen_items(w, cell).get("wood", 0)) == 3, "beimen deposit_half moved 3")
	r = act(w, "alice", "withdraw_all", cell, "sea_salt")
	expect(bool(r.get("ok", false)) and str(r.get("message", "")) == moved_message("withdraw_all", "sea_salt", 4), "beimen withdraw_all accepted: " + str(r.get("message", "")))
	expect(held(w, "alice", "sea_salt") == 4 and int(beimen_items(w, cell).get("sea_salt", 0)) == 0, "beimen withdraw_all moved 4")
	r = act(w, "alice", "deposit_all", cell, "wood")
	expect(bool(r.get("ok", false)) and held(w, "alice", "wood") == 0 and int(beimen_items(w, cell).get("wood", 0)) == 5, "beimen deposit_all accepted")
	r = act(w, "alice", "withdraw_half", cell, "wood")
	expect(bool(r.get("ok", false)) and held(w, "alice", "wood") == 3 and int(beimen_items(w, cell).get("wood", 0)) == 2, "beimen withdraw_half accepted")
	r = act(w, "alice", "deposit", cell, "wood")
	expect(bool(r.get("ok", false)) and str(r.get("message", "")) == "已存入" + label_of("wood"), "beimen legacy deposit still accepted")

func test_save_reload() -> void:
	var w = fresh()
	place(w, PRIVATE_CELL, "private_chest", "alice", {"stone": 2})
	set_held(w, "alice", "wood", 7)
	set_held(w, "alice", "stone", 3)
	set_stored(w, CELL, "fiber", 4)
	var path := "user://t014-inventory-stack-%d.json" % Time.get_ticks_usec()
	w.save_path = path
	moved(w, "save: deposit_half wood 7", "alice", "deposit_half", CELL, "wood", 4)
	moved(w, "save: deposit_all stone", "alice", "deposit_all", PRIVATE_CELL, "stone", 3)
	moved(w, "save: withdraw_half private stone 5", "alice", "withdraw_half", PRIVATE_CELL, "stone", 3)
	moved(w, "save: guest withdraw_all fiber", "bob", "withdraw_all", CELL, "fiber", 4)
	expect(w.act("alice","saved-deposit-access","box_deposit_access",PRIVATE_CELL,"island").ok,"Deposit access accepted before reload")
	expect(FileAccess.file_exists(path), "accepted moves saved to disk")
	expect(w.save(), "explicit save succeeds")
	for c in [CELL, PRIVATE_CELL]:
		expect(plain_counts(items(w, c)), "live box %s items are plain item_id -> count" % World.key(c))
		for k in items(w, c):
			expect(typeof(items(w, c)[k]) == TYPE_INT, "live box %s %s is an int" % [World.key(c), str(k)])
	for item in ["wood", "stone", "fiber"]:
		expect(typeof(bag(w, "alice").get(item, 0)) == TYPE_INT and typeof(bag(w, "bob").get(item, 0)) == TYPE_INT, "live backpack %s is an int" % item)
	var persisted = json_form(w.state)
	expect(persisted is Dictionary and valid(persisted), "state after stack moves passes SaveSchema in its saved JSON form")
	var loaded = World.new()
	var loaded_ok: bool = loaded.load_world(path)
	expect(loaded_ok and not loaded.recovered_from_backup, "save reloads into a new World")
	if loaded_ok and persisted is Dictionary:
		expect(canon(loaded.state) == canon(persisted), "reloaded state identical to the validated live JSON form")
		for t in ["alice", "bob"]:
			expect(plain_counts(bag(loaded, t)), "reloaded %s backpack keeps item_id -> count shape" % t)
			expect(same_counts(bag(w, t), bag(loaded, t)), "reloaded %s backpack has the same counts" % t)
		for c in [CELL, PRIVATE_CELL]:
			expect(plain_counts(items(loaded, c)), "reloaded box %s keeps item_id -> count shape" % World.key(c))
			expect(same_counts(items(w, c), items(loaded, c)), "reloaded box %s has the same counts" % World.key(c))
			expect(str(loaded.state.objects.get(World.key(c), {}).get("type", "")) == str(w.state.objects[World.key(c)].type), "reloaded box %s keeps its type" % World.key(c))
		expect(held(loaded, "alice", "wood") == 3 and stored(loaded, CELL, "wood") == 4, "reloaded wood split 3/4")
		expect(held(loaded, "alice", "stone") == 3 and stored(loaded, PRIVATE_CELL, "stone") == 2, "reloaded stone split 3/2")
		expect(held(loaded, "bob", "fiber") >= 4 and stored(loaded, CELL, "fiber") == 0, "reloaded fiber with bob")
		expect(Perm.can_deposit("bob",loaded.state.objects[World.key(PRIVATE_CELL)]).ok
			and not Perm.can_take("bob",loaded.state.objects[World.key(PRIVATE_CELL)]).ok,"Reload retains only permission to deposit")
		# Reloaded (JSON float) counts still move exactly and come back as ints.
		loaded.save_path = ""
		moved(loaded, "reloaded withdraw_all wood", "alice", "withdraw_all", CELL, "wood", 4)
		moved(loaded, "reloaded deposit_half stone", "alice", "deposit_half", PRIVATE_CELL, "stone", 2)
		var after = json_form(loaded.state)
		expect(after is Dictionary and valid(after), "reloaded world still validates after more moves")
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))

func run() -> void:
	test_half_and_all()
	test_legacy()
	test_refusals()
	test_limits()
	test_permissions()
	test_race()
	test_retry()
	test_regions()
	test_save_reload()
	print("INVENTORY_STACK_WORLD_TESTS checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 or checks == 0 else 0)
