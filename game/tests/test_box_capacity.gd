extends SceneTree

## C06/C07 共用木箱 / 私人木箱: 16 slots, one item ID per slot (real World, no mocks).
##
## Disclosed fixture presets (written straight into world.state, not earned in play):
##   chest/private_chest/supply_box/acorn cabinet objects, backpack counts, box
##   contents including legacy saves with more than 16 entries, a transit freight
##   job, a livestock record, conveyors, and the player pose.

const World = preload("res://scripts/world.gd")
const Schema = preload("res://scripts/save_schema.gd")
const Cap = preload("res://scripts/box_capacity.gd")
const Freight = preload("res://scripts/mine_freight.gd")
const Livestock = preload("res://scripts/livestock.gd")
const SaltPan = preload("res://scripts/salt_pan.gd")
const CELL := Vector2i(38, 33)
const PRIVATE_CELL := Vector2i(37, 34)
const SUPPLY_CELL := Vector2i(40, 34)
const CABINET_CELL := Vector2i(41, 33)
const SPOT := Vector2(39.5, 33.5)
var checks := 0
var failures := 0
var sequence := 0
var fixture_paths: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL " + message)

func ids(count: int, skip: Array = []) -> Array:
	var out: Array = []
	for id in World.NAMES:
		if id in skip or id in ["wood", "stone", "wool", "quality_wool", "copper_ore", "gold_ore", "sea_salt"]:continue
		out.append(id)
		if out.size() == count:break
	return out

func fill(count: int) -> Dictionary:
	var out := {}
	for id in ids(count):out[id] = 3
	return out

func fresh() -> World:
	var w := World.new()
	w.save_path = OS.get_environment("TEMP").path_join("box-capacity-%s.json" % Crypto.new().generate_random_bytes(6).hex_encode())
	fixture_paths.append(w.save_path)
	w.add_player("alice", "阿米")
	w.add_player("bob", "小豆")
	for token in ["alice", "bob"]:
		var p: Dictionary = w.state.players[token]
		p.region = World.REGIONS.HOME
		p.x = SPOT.x
		p.y = SPOT.y
	return w

func place(w: World, cell: Vector2i, kind: String, owner: String, contents: Dictionary, extra: Dictionary = {}) -> Dictionary:
	var box := {"type": kind, "owner": owner, "items": contents.duplicate(true)}
	box.merge(extra, true)
	w.state.objects[World.key(cell)] = box
	return box

func act(w: World, token: String, action: String, cell: Vector2i, extra: String = "") -> Dictionary:
	sequence += 1
	return w.act(token, "cap-%d" % sequence, action, cell, extra)

func bag(w: World, token: String) -> Dictionary:
	return w.state.players[token].inventory

func box_items(w: World, cell: Vector2i) -> Dictionary:
	return w.state.objects[World.key(cell)].items

func valid(w: World) -> bool:
	return Schema.validate(w.state, World.CROPS, World.BUILD, World.RECIPES, World.SIZE, World.TREE_TIME)

## A refusal must leave state byte-for-byte equal and store no receipt.
func refused(w: World, label: String, token: String, action: String, cell: Vector2i, extra: String, message: String) -> void:
	var before: Dictionary = w.state.duplicate(true)
	sequence += 1
	var request := "cap-%d" % sequence
	var result: Dictionary = w.act(token, request, action, cell, extra)
	expect(not bool(result.get("ok", true)), label + ": refused")
	expect(str(result.get("message", "")) == message, label + ": message '" + str(result.get("message", "")) + "'")
	expect(w.state == before, label + ": state unchanged, input retained")
	expect(not w.state.players[token].get("receipts", {}).has(request), label + ": no receipt for a refusal")

# ------------------------------------------------------------------ rule ----

func test_rule() -> void:
	expect(Cap.SLOTS == 16 and World.BUILD.chest.wood == 20 and World.BUILD.private_chest.wood == 20, "16 slots, wood 20 each")
	for kind: String in Cap.KINDS:
		var w := fresh()
		w.state.removed[World.key(CELL)] = true
		bag(w,"alice").wood = 20
		expect(act(w,"alice","build",CELL,kind).ok and w.state.objects.size()==1 and w.state.objects[World.key(CELL)].type==kind,"%s builds a single tile"%kind)
	expect(World.BUILD.chest.name == "共用木箱" and World.BUILD.private_chest.name == "私人木箱", "content-book names, same IDs")
	expect(Cap.applies("chest") and Cap.applies("private_chest") and not Cap.applies("supply_box") and not Cap.applies(World.INDUSTRY.ACORN_CABINET), "only the two wooden boxes")
	var sixteen := fill(16)
	var s := Cap.summary(sixteen)
	expect(s.used == 16 and s.full and s.overflow == 0, "16 entries is full, no overflow")
	expect(Cap.slot_ok(sixteen, {ids(1)[0]: 5}), "stacking into an existing slot is fine")
	expect(not Cap.slot_ok(sixteen, {"wood": 1}), "a new ID is refused at 16")
	expect(Cap.slot_ok(fill(15), {"wood": 1}) and not Cap.slot_ok(fill(15), {"wood": 1, "stone": 1}), "15 entries take exactly one new ID")
	var legacy := fill(20)
	expect(Cap.summary(legacy).overflow == 4 and not Cap.slot_ok(legacy, {"wood": 1}) and Cap.slot_ok(legacy, {ids(20)[19]: 1}), "legacy 20 entries: overflow 4, stack ok, new refused")
	expect(Cap.occupied({"wood": 0, "stone": 2}) == 1, "a zero count does not occupy a slot")
	expect(Cap.refused(fill(15), ["wood", "stone"]) == ["stone"], "refused() keeps priority order")

# ---------------------------------------------------------------- manual ----

func test_manual() -> void:
	for action in ["deposit", "deposit_half", "deposit_all", "deposit_exact"]:
		var w := fresh()
		place(w, CELL, "chest", "alice", fill(16))
		bag(w, "alice").wood = 4
		var extra := "wood:2" if action == "deposit_exact" else "wood"
		refused(w, "shared " + action, "alice", action, CELL, extra, Cap.FULL_MESSAGE)
		var stack: String = ids(1)[0]
		bag(w, "alice")[stack] = 4
		var extra2 := "%s:2" % stack if action == "deposit_exact" else stack
		expect(bool(act(w, "alice", action, CELL, extra2).ok), action + " stacks into an existing slot while full")
		expect(box_items(w, CELL).size() == 16, action + " still 16 entries")
	# legacy overflow: everything visible and withdrawable, stacking only
	var w := fresh()
	var legacy := fill(20)
	place(w, CELL, "chest", "alice", legacy)
	expect(valid(w), "a save with 20 chest entries still validates")
	refused(w, "legacy new category", "alice", "deposit_all", CELL, "wood", Cap.FULL_MESSAGE)
	var first: String = ids(1)[0]
	bag(w, "alice")[first] = 2
	expect(bool(act(w, "alice", "deposit_all", CELL, first).ok) and box_items(w, CELL).size() == 20, "legacy stacking works, nothing truncated")
	for id in legacy:
		expect(bool(act(w, "alice", "withdraw_all", CELL, id).ok), "legacy entry withdrawable: " + id)
	expect(Cap.occupied(box_items(w, CELL)) == 0, "all legacy entries withdrawn")
	bag(w, "alice").wood = 1
	expect(bool(act(w, "alice", "deposit", CELL, "wood").ok), "a freed box takes a new category again")
	# a withdrawn slot (count 0) frees its slot
	w = fresh()
	place(w, CELL, "chest", "alice", fill(16))
	var gone: String = ids(1)[0]
	expect(bool(act(w, "alice", "withdraw_all", CELL, gone).ok), "withdraw one full stack")
	bag(w, "alice").wood = 1
	expect(bool(act(w, "alice", "deposit", CELL, "wood").ok), "freed slot accepts a new ID")
	# distinct semantics: supply box and cabinet keep their own rules
	w = fresh()
	place(w, SUPPLY_CELL, "supply_box", "alice", fill(20))
	bag(w, "alice").wood = 1
	expect(bool(act(w, "alice", "deposit", SUPPLY_CELL, "wood").ok), "supply_box has no 16-slot cap")
	w = fresh()
	place(w, CABINET_CELL, World.INDUSTRY.ACORN_CABINET, "alice", fill(16))
	bag(w, "alice").wood = 1
	refused(w, "cabinet keeps its own message", "alice", "deposit", CABINET_CELL, "wood", "收納櫃的 16 格已滿，請先取出一種物品。")

func test_private_roles() -> void:
	var w := fresh()
	place(w, PRIVATE_CELL, "private_chest", "alice", fill(16))
	bag(w, "bob").wood = 3
	refused(w, "stranger", "bob", "deposit", PRIVATE_CELL, "wood", "這是另一位島民的私人箱")
	w.state.objects[World.key(PRIVATE_CELL)].guest_deposit = true
	refused(w, "deposit-only guest hits the full rule", "bob", "deposit", PRIVATE_CELL, "wood", Cap.FULL_MESSAGE)
	var stack: String = ids(1)[0]
	bag(w, "bob")[stack] = 1
	expect(bool(act(w, "bob", "deposit", PRIVATE_CELL, stack).ok), "deposit-only guest can stack")
	refused(w, "deposit-only guest cannot withdraw", "bob", "withdraw", PRIVATE_CELL, stack, "這是另一位島民的私人箱")
	w.state.objects[World.key(PRIVATE_CELL)].withdraw_guest = "bob"
	expect(bool(act(w, "bob", "withdraw", PRIVATE_CELL, stack).ok), "explicit withdraw delegate can withdraw")

# ------------------------------------------------------------- automation ----

func belt(w: World, cell: Vector2i, filter: String, items: Dictionary) -> void:
	place(w, cell, "conveyor", "alice", items, {"enabled": true, "dir": 1, "filter": filter})

func test_conveyor() -> void:
	var w := fresh()
	place(w, Vector2i(41, 34), "private_chest", "alice", fill(16))
	belt(w, Vector2i(40, 34), "wood", {"wood": 1})
	var reason: String = World.LOGISTICS.delivery_block(w.state.objects["40,34"], w.state.objects["41,34"], w.state.objects["41,34"])
	expect(reason == Cap.BELT_FULL, "belt reports the 16-slot reason")
	var before: Dictionary = w.state.objects["41,34"].items.duplicate(true)
	expect(w.step(2, true) and w.state.objects["40,34"].items.get("wood", 0) == 1 and w.state.objects["41,34"].items == before, "belt keeps its item, chest unchanged")
	var stack: String = ids(1)[0]
	w.state.objects["40,34"].filter = stack
	w.state.objects["40,34"].items = {stack: 1}
	expect(w.step(2, true) and w.state.objects["40,34"].items.is_empty() and int(w.state.objects["41,34"].items[stack]) == 4, "belt stacks into an existing slot")
	# a 15-entry chest takes one new ID from the belt, then blocks a second new ID (same tick copy)
	w = fresh()
	place(w, Vector2i(41, 34), "private_chest", "alice", fill(15))
	belt(w, Vector2i(40, 34), "wood", {"wood": 1})
	var tick: Dictionary = World.LOGISTICS.plan(w, 0.0, true)
	expect(tick.has("41,34") and tick["41,34"].items.get("wood", 0) == 1 and not tick["41,34"].items.has("stone"), "one new ID takes the last slot")
	expect(World.LOGISTICS.delivery_block({"owner": "alice", "filter": "stone"}, tick["41,34"], tick["41,34"]) == Cap.BELT_FULL, "reserved copy blocks a second new ID in the same tick")

func test_freight() -> void:
	var w := fresh()
	w.state.mine_depths = {"unlocked": 5, "ready": {}, "pumped": 24, "hoist": false}
	var target := "42,35"
	var box := place(w, Vector2i(42, 35), "private_chest", "alice", fill(15), {"freight_id": "a".repeat(32)})
	w.state.mine_freight.jobs["alice"] = {"status": "transit", "items": {"copper_ore": 2, "gold_ore": 2}, "target": {"cell": target, "id": "a".repeat(32)}, "ready": float(w.state.time) + 1}
	var original: Dictionary = box.items.duplicate(true)
	expect(w.step(1, true) and w.state.mine_freight.jobs["alice"].status == "held" and box.items == original, "two new ore kinds with one free slot: whole job held, no partial credit")
	expect(w.state.mine_freight.jobs["alice"].items == {"copper_ore": 2, "gold_ore": 2}, "held cargo keeps every item")
	box.items = fill(16)
	box.items.copper_ore = 1
	w.state.mine_freight.jobs["alice"] = {"status": "transit", "items": {"copper_ore": 2}, "target": {"cell": target, "id": "a".repeat(32)}, "ready": float(w.state.time) + 1}
	expect(w.step(1, true) and w.state.mine_freight.jobs["alice"].status == "delivered" and int(box.items.copper_ore) == 3 and box.items.size() == 17, "stacking into the existing ore slot delivers (legacy 17 entries kept)")
	expect(Freight.can_fit({}, {"copper_ore": 1}) and not Freight.can_fit_chest(fill(16), {"copper_ore": 1}), "backpack rule unchanged, chest rule slot-aware")
	# auto freight status
	var route := {"region": "mine_4", "source": {"cell": "1,1", "id": "b".repeat(32)}, "target": {"cell": target, "id": "a".repeat(32)}, "item": "copper_ore", "reserve": 0, "batch": 1, "enabled": true}
	w.state.mine_auto_freight.routes["alice"] = route
	w.state.regions.mine_4.objects["1,1"] = {"type": "private_chest", "owner": "alice", "freight_id": "b".repeat(32), "items": {"copper_ore": 5}}
	w.state.mine_freight.jobs.erase("alice")
	box.items = fill(16)
	expect(World.MINE_AUTO_FREIGHT.status(w.state, "alice").id == "target_full", "auto freight reports a slot-full destination")
	box.items = fill(15)
	expect(World.MINE_AUTO_FREIGHT.status(w.state, "alice").id == "ready", "auto freight goes once a slot is free")

func test_livestock() -> void:
	var w := fresh()
	w.state.picnic = true
	var animal := Livestock.fresh()
	animal.ready = 3
	animal.ready_quality = 1
	animal.feed = 0
	animal.next = -1.0
	w.state.livestock.sheep = animal
	var key := World.key(Livestock.collector_cell("sheep"))
	var box := {"type": "chest", "owner": "alice", "items": fill(15)}
	w.state.objects[key] = box
	expect(Livestock.collect_into_chests(w) == [key], "one free slot: something moves")
	expect(box.items.has("quality_wool") and not box.items.has("wool") and int(w.state.livestock.sheep.ready) == 2, "premium takes the last slot, ordinary stays in the pen")
	box.items = fill(16)
	var pen_before: Dictionary = w.state.livestock.sheep.duplicate(true)
	expect(Livestock.collect_into_chests(w).is_empty() and w.state.livestock.sheep == pen_before and box.items == fill(16), "a full box takes nothing, pen keeps product")

func test_salt() -> void:
	expect(SaltPan._has_slot(fill(15)) and not SaltPan._has_slot(fill(16)), "salt collector uses the shared rule")
	var sixteen := fill(15)
	sixteen.sea_salt = 4
	expect(SaltPan._has_slot(sixteen), "salt collector may keep stacking sea_salt in a full box")

func test_snapshot_and_names() -> void:
	var w := fresh()
	place(w, CELL, "chest", "alice", fill(20))
	expect(valid(w), "legacy overflow save validates")
	var reloaded := World.new()
	if w.save() and reloaded.load_world(w.save_path):
		expect(not reloaded.recovered_from_backup and box_items(reloaded,CELL)==fill(20),"Reload keeps all 20 old stacks")
	else:
		expect(false,"The legacy overflow save can reload")

func run() -> void:
	test_rule()
	test_manual()
	test_private_roles()
	test_conveyor()
	test_freight()
	test_livestock()
	test_salt()
	test_snapshot_and_names()
	for path: String in fixture_paths:
		for suffix: String in ["", ".bak", ".tmp", ".writer-lock"]:
			if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("BOX_CAPACITY_TESTS checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 or checks == 0 else 0)
