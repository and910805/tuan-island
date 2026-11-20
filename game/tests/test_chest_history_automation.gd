extends SceneTree

## T021 wooden chest history for AUTOMATIC transfers and chest-sourced material withdrawals
## (belt both ways, MineFreight + auto freight, livestock, salt collector, MaterialSources),
## through the real World.step / World.act / SaltPan.step paths.
##
## Disclosed fixtures (written straight into world.state, not earned in play): conveyors,
## chests, freight jobs/routes, livestock records, salt lots/pans and the bench site.
## Out of scope on purpose (not wooden chest transfers, so nothing is logged and nothing is
## tested as logged): AnimalCollector baskets, manual freight load/unload/claim (backpack
## <-> freight cargo), the salt apprentice coop_box counter, hand raking, and
## cancel/refund of a sourced queue job (it refunds to the backpack, never a chest).

const World = preload("res://scripts/world.gd")
const ChestHistory = preload("res://scripts/chest_history.gd")
const ItemCatalog = preload("res://scripts/item_catalog.gd")
const Livestock = preload("res://scripts/livestock.gd")
const SaltPan = preload("res://scripts/salt_pan.gd")
const Sources = preload("res://scripts/material_sources.gd")
const Supply = preload("res://scripts/material_supply.gd")

const KIT := "sawmill_kit" # bench recipe: wood 8 + stone 4
const BELT := "輸送帶"
const FREIGHT := "礦務貨運"
const PEN := "畜牧"
const SALT := "收鹽台"

var checks := 0
var failures := 0
var serial := 0
var dir := ""
var here := Vector2.ZERO
var used: Array = []

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL " + message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var base := OS.get_environment("TEMP")
	if base.is_empty():
		base = OS.get_user_data_dir()
	dir = base.path_join("chest-history-automation-" + Crypto.new().generate_random_bytes(8).hex_encode())
	expect(DirAccess.make_dir_recursive_absolute(dir) == OK, "isolated TEMP directory created")
	test_belt()
	test_freight()
	test_livestock()
	test_salt()
	test_material_sources()
	for file in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(file))
	DirAccess.remove_absolute(dir)
	print("CHEST_HISTORY_AUTOMATION_TESTS checks=%d failures=%d" % [checks, failures])
	quit(int(failures > 0))

# ------------------------------------------------------------------ helpers --

func fresh() -> World:
	var w := World.new()
	serial += 1
	w.save_path = dir.path_join("world-%d.json" % serial)
	w.add_player("alice", "阿米")
	w.add_player("bob", "小豆")
	for token in ["alice", "bob"]:
		w.state.players[token].inventory = {}
	return w

func ids(count: int) -> Array:
	var out: Array = []
	for id in World.NAMES:
		if id in ["wood", "stone", "wool", "quality_wool", "copper_ore", "gold_ore", "sea_salt", "plank"]:
			continue
		out.append(id)
		if out.size() == count:
			break
	return out

func fill(count: int) -> Dictionary:
	var out := {}
	for id in ids(count):
		out[id] = 3
	return out

func put(w: World, cell: Vector2i, kind: String, owner: String, contents: Dictionary, extra: Dictionary = {}) -> Dictionary:
	var box := {"type": kind, "owner": owner, "items": contents.duplicate(true)}
	box.merge(extra, true)
	w.state.objects[World.key(cell)] = box
	return box

func belt(w: World, cell: Vector2i, dir_index: int, filter: String, owner: String = "alice", contents: Dictionary = {}) -> void:
	put(w, cell, "conveyor", owner, contents, {"enabled": true, "dir": dir_index, "filter": filter})

## Always re-read live objects: a rolled-back tick replaces the state dictionaries.
func box_at(w: World, cell: Vector2i) -> Dictionary:
	return w.state.objects[World.key(cell)]

func rows(box: Dictionary) -> Array:
	return box.get(ChestHistory.FIELD, [])

func row(actor: String, item: String, amount: int, depositing: bool, time: float) -> Dictionary:
	return {"actor": actor, "item": item, "amount": amount, "depositing": depositing, "time": time}

func same_rows(actual: Array, expected: Array) -> bool:
	if actual.size() != expected.size():
		return false
	for i in actual.size():
		var a: Dictionary = actual[i]
		var e: Dictionary = expected[i]
		if a.size() != 5 or a.actor != e.actor or a.item != e.item or int(a.amount) != int(e.amount) or a.depositing != e.depositing or float(a.time) != float(e.time):
			return false
	return true

func valid_history(box: Dictionary) -> bool:
	return ChestHistory.valid(box, ItemCatalog.is_known)

func net(list: Array, item: String) -> int:
	var total := 0
	for r in list:
		if r.item == item:
			total += int(r.amount) * (1 if r.depositing else -1)
	return total

func no_tokens(list: Array, label: String) -> void:
	for r in list:
		expect(not str(r.actor).contains("alice") and not str(r.actor).contains("bob") and not str(r.actor).contains("tok-"), label + ": actor is a display label, never an account token")

# --------------------------------------------------------------------- belt --

func test_belt() -> void:
	var w := fresh()
	# Line 1+3 share chest B: A -> belt1 -> B <- belt3 <- F (two deposits can land in one tick).
	var a := put(w, Vector2i(40, 34), "private_chest", "alice", {"wood": 5}, {"freight_id": "a".repeat(32)})
	belt(w, Vector2i(41, 34), 1, "wood")
	var b := put(w, Vector2i(42, 34), "private_chest", "alice", {})
	belt(w, Vector2i(43, 34), 3, "wood")
	var f := put(w, Vector2i(44, 34), "private_chest", "alice", {"wood": 4})
	# Line 2 runs concurrently on another row with another item.
	put(w, Vector2i(40, 38), "private_chest", "alice", {"stone": 4})
	belt(w, Vector2i(41, 38), 1, "stone")
	put(w, Vector2i(42, 38), "private_chest", "alice", {})
	# Refused deliveries: full destination (belt holds an item); a foreign chest on both ends.
	put(w, Vector2i(40, 42), "private_chest", "alice", {"wood": 2})
	belt(w, Vector2i(41, 42), 1, "wood", "alice", {"wood": 1})
	var full := put(w, Vector2i(42, 42), "private_chest", "alice", fill(16))
	put(w, Vector2i(40, 44), "private_chest", "bob", {"wood": 3})
	belt(w, Vector2i(41, 44), 1, "wood")
	put(w, Vector2i(42, 44), "private_chest", "bob", {})
	expect(a.has("freight_id"), "fixture: belt source keeps its freight id")

	# Preview / audit: calling plan directly (with or without a log) never writes history.
	var preview_log: Array = []
	var planned: Dictionary = World.LOGISTICS.plan(w, 0.0, true, preview_log)
	expect(not planned.is_empty() and not preview_log.is_empty(), "premise: the plan finds belt moves")
	World.LOGISTICS.plan(w, 0.0, true)
	for cell in [Vector2i(40, 34), Vector2i(42, 34), Vector2i(44, 34), Vector2i(40, 38), Vector2i(42, 38)]:
		expect(not box_at(w, cell).has(ChestHistory.FIELD), "plan/preview writes no history at %s" % str(cell))

	var t0 := float(w.state.time)
	for i in 8:
		expect(w.step(2, true), "belt tick %d commits" % i)
	var end := float(w.state.time)
	a = box_at(w, Vector2i(40, 34))
	b = box_at(w, Vector2i(42, 34))
	f = box_at(w, Vector2i(44, 34))
	var rows_a := rows(a)
	var rows_b := rows(b)
	var rows_f := rows(f)
	expect(rows_a.size() > 0 and rows_f.size() > 0 and rows_b.size() > 0, "both directions are logged")
	for r in rows_a + rows_f:
		expect(r.actor == BELT and r.item == "wood" and r.amount == 1 and not r.depositing, "withdrawal row: 輸送帶, wood, 1, out")
	for r in rows_b:
		expect(r.actor == BELT and r.item == "wood" and r.amount == 1 and r.depositing, "deposit row: 輸送帶, wood, 1, in")
	var belts_holding := 0
	for cell in [Vector2i(41, 34), Vector2i(43, 34)]:
		belts_holding += int(box_at(w, cell).items.get("wood", 0))
	expect(rows_a.size() + rows_f.size() == rows_b.size() + belts_holding, "every withdrawal is either delivered (one deposit row) or still on a belt")
	expect(int(b.items.get("wood", 0)) == rows_b.size() and int(a.items.get("wood", 0)) == 5 - rows_a.size() and int(f.items.get("wood", 0)) == 4 - rows_f.size(), "history counts equal the real item movement in all three chests")
	expect(net(rows_b, "wood") == int(b.items.get("wood", 0)) and net(rows_a, "wood") == int(a.items.get("wood", 0)) - 5 and net(rows_f, "wood") == int(f.items.get("wood", 0)) - 4, "net per chest matches its contents")
	var last := t0
	for r in rows_a + rows_b + rows_f:
		expect(float(r.time) > t0 and float(r.time) <= end and fposmod(float(r.time) - t0, 2.0) == 0.0, "row time is a real simulation tick (%.1f)" % float(r.time))
	for list in [rows_a, rows_b, rows_f]:
		last = t0
		for r in list:
			expect(float(r.time) >= last, "rows stay in committed order")
			last = float(r.time)
	var pickups := rows_a + rows_f
	for i in rows_b.size():
		var delivered_at: float = rows_b[i].time
		var picked_up := pickups.filter(func(row: Dictionary) -> bool: return float(row.time) < delivered_at).size()
		expect(picked_up >= i + 1, "each delivery has a prior pickup across both source lines (row %d)" % i)
	# Two belts delivering into B on the same tick give two rows with the same stamp.
	var doubled := false
	for i in range(1, rows_b.size()):
		if float(rows_b[i].time) == float(rows_b[i - 1].time):
			doubled = true
	expect(doubled, "concurrent belts into one chest log one row each, same tick")
	# Independent concurrent line: identical timeline, its own item and chests.
	var c_rows := rows(box_at(w, Vector2i(40, 38)))
	var d_rows := rows(box_at(w, Vector2i(42, 38)))
	expect(c_rows.size() > 0 and d_rows.size() > 0 and net(c_rows, "stone") == int(box_at(w, Vector2i(40, 38)).items.get("stone", 0)) - 4 and net(d_rows, "stone") == int(box_at(w, Vector2i(42, 38)).items.get("stone", 0)), "second line's counts are independent and exact")
	no_tokens(rows_a + rows_b + c_rows + d_rows, "belt")
	for cell in [Vector2i(40, 34), Vector2i(42, 34), Vector2i(44, 34), Vector2i(40, 38), Vector2i(42, 38)]:
		expect(valid_history(box_at(w, cell)), "belt history validates (known ids, bounds) at %s" % str(cell))
	expect(not box_at(w, Vector2i(41, 34)).has(ChestHistory.FIELD) and not box_at(w, Vector2i(43, 34)).has(ChestHistory.FIELD), "belts themselves get no history")
	# Refused moves.
	expect(not box_at(w, Vector2i(42, 42)).has(ChestHistory.FIELD) and box_at(w, Vector2i(42, 42)).items == full.items, "a full destination logs nothing")
	expect(not box_at(w, Vector2i(40, 42)).has(ChestHistory.FIELD), "a chest whose belt is already loaded logs nothing")
	expect(not box_at(w, Vector2i(40, 44)).has(ChestHistory.FIELD) and not box_at(w, Vector2i(42, 44)).has(ChestHistory.FIELD), "another islander's chests are never logged by a belt that cannot use them")
	expect(box_at(w, Vector2i(40, 34)).freight_id == "a".repeat(32) and box_at(w, Vector2i(40, 34)).owner == "alice", "private ownership and ids are preserved")

	# Rolled back tick: the injected salt fault fails the whole step, so nothing is logged.
	var before_a := var_to_str(rows(box_at(w, Vector2i(40, 34))))
	var before_b := var_to_str(rows(box_at(w, Vector2i(42, 34))))
	var before_items := var_to_str(box_at(w, Vector2i(42, 34)).items)
	w.state.salt_pan.pans[3].s = "mud"
	expect(not w.step(2, true), "fault: the tick is rejected")
	expect(var_to_str(rows(box_at(w, Vector2i(40, 34)))) == before_a and var_to_str(rows(box_at(w, Vector2i(42, 34)))) == before_b and var_to_str(box_at(w, Vector2i(42, 34)).items) == before_items, "a rolled-back tick leaves history and items untouched")
	w.state.salt_pan.pans[3].s = "empty"
	expect(w.step(2, true), "after the fault is cleared the belts continue")
	expect(rows(box_at(w, Vector2i(42, 34))).size() >= rows_b.size(), "history keeps growing after the rollback")

# ------------------------------------------------------------------ freight --

func test_freight() -> void:
	var w := fresh()
	w.state.mine_depths = {"unlocked": 5, "ready": {}, "pumped": 24, "hoist": false}
	var ida := "a".repeat(32)
	var idb := "b".repeat(32)
	put(w, Vector2i(42, 35), "private_chest", "alice", {"wood": 1}, {"freight_id": ida})
	put(w, Vector2i(42, 37), "private_chest", "bob", {}, {"freight_id": idb})
	var ready := float(w.state.time) + 1.0
	w.state.mine_freight.jobs["alice"] = {"status": "transit", "items": {"gold_ore": 2, "copper_ore": 3}, "target": {"cell": "42,35", "id": ida}, "ready": ready}
	w.state.mine_freight.jobs["bob"] = {"status": "transit", "items": {"stone": 4}, "target": {"cell": "42,37", "id": idb}, "ready": ready}
	expect(not box_at(w, Vector2i(42, 35)).has(ChestHistory.FIELD), "nothing is logged while the cargo is in transit")
	expect(w.step(0.5, true) and not box_at(w, Vector2i(42, 35)).has(ChestHistory.FIELD), "a tick before arrival logs nothing")
	expect(w.step(0.5, true), "arrival tick commits")
	var arrived := float(w.state.time)
	expect(w.state.mine_freight.jobs.alice.status == "delivered" and w.state.mine_freight.jobs.bob.status == "delivered", "both jobs delivered")
	expect(same_rows(rows(box_at(w, Vector2i(42, 35))), [row(FREIGHT, "copper_ore", 3, true, arrived), row(FREIGHT, "gold_ore", 2, true, arrived)]), "alice: one net row per ore, sorted, at the arrival clock")
	expect(same_rows(rows(box_at(w, Vector2i(42, 37))), [row(FREIGHT, "stone", 4, true, arrived)]), "bob's concurrent delivery is counted in his own chest only")
	expect(box_at(w, Vector2i(42, 35)).items == {"wood": 1, "copper_ore": 3, "gold_ore": 2}, "chest contents match the log")
	expect(valid_history(box_at(w, Vector2i(42, 35))) and box_at(w, Vector2i(42, 35)).freight_id == ida, "history valid, id preserved")
	expect(w.state.players.alice.inventory.is_empty(), "no worker/cargo is added to the player's backpack")

	# Held job (no free slot): the cargo stays on the board and nothing is logged.
	var full_items := fill(16)
	put(w, Vector2i(42, 39), "private_chest", "alice", full_items, {"freight_id": "c".repeat(32)})
	w.state.mine_freight.jobs["alice"] = {"status": "transit", "items": {"copper_ore": 2}, "target": {"cell": "42,39", "id": "c".repeat(32)}, "ready": float(w.state.time) + 1.0}
	expect(w.step(1, true) and w.state.mine_freight.jobs.alice.status == "held", "no free slot: the job is held")
	expect(not box_at(w, Vector2i(42, 39)).has(ChestHistory.FIELD) and box_at(w, Vector2i(42, 39)).items == full_items, "a held job logs nothing")

	# Auto freight: source pickup is a withdrawal at the source chest, delivery a deposit later.
	w.state.mine_freight.jobs.erase("alice")
	var target := put(w, Vector2i(42, 41), "private_chest", "alice", {}, {"freight_id": "d".repeat(32)})
	w.state.regions.mine_4.objects["1,1"] = {"type": "private_chest", "owner": "alice", "freight_id": idb, "items": {"copper_ore": 5}}
	w.state.mine_auto_freight.routes["alice"] = {"region": "mine_4", "source": {"cell": "1,1", "id": idb}, "target": {"cell": "42,41", "id": "d".repeat(32)}, "item": "copper_ore", "reserve": 1, "batch": 2, "enabled": true}
	target.items = fill(16)
	expect(World.MINE_AUTO_FREIGHT.status(w.state, "alice").id == "target_full", "premise: target is full")
	expect(not World.MINE_AUTO_FREIGHT.step(w.state) and not w.state.regions.mine_4.objects["1,1"].has(ChestHistory.FIELD), "a refused auto batch logs nothing")
	target.items = {}
	expect(World.MINE_AUTO_FREIGHT.status(w.state, "alice").id == "ready", "premise: route is ready")
	var picked := float(w.state.time)
	expect(World.MINE_AUTO_FREIGHT.step(w.state), "auto freight dispatches a batch")
	var source: Dictionary = w.state.regions.mine_4.objects["1,1"]
	expect(same_rows(rows(source), [row(FREIGHT, "copper_ore", 2, false, picked)]) and int(source.items.copper_ore) == 3, "source chest logs the withdrawn batch at the dispatch clock")
	expect(not target.has(ChestHistory.FIELD), "target is untouched until the cargo arrives")
	w.state.mine_auto_freight.routes.alice.enabled = false
	expect(w.step(60, true), "the transit tick commits")
	var delivered := float(w.state.time)
	expect(w.state.mine_freight.jobs.alice.status == "delivered", "auto cargo delivered")
	expect(same_rows(rows(box_at(w, Vector2i(42, 41))), [row(FREIGHT, "copper_ore", 2, true, delivered)]), "target logs the delivery at the arrival clock")
	expect(same_rows(rows(w.state.regions.mine_4.objects["1,1"]), [row(FREIGHT, "copper_ore", 2, false, picked)]), "source row is not duplicated")
	expect(w.state.regions.mine_4.objects["1,1"].freight_id == idb and valid_history(w.state.regions.mine_4.objects["1,1"]), "source id preserved, history valid")

# ---------------------------------------------------------------- livestock --

func animal(ready: int, quality: int) -> Dictionary:
	var record := Livestock.fresh()
	record.ready = ready
	record.ready_quality = quality
	record.feed = 0
	record.next = -1.0
	return record

func test_livestock() -> void:
	var w := fresh()
	w.state.picnic = true
	w.state.time = 1234.5
	w.state.livestock.sheep = animal(3, 1)
	w.state.livestock.cow = animal(2, 0)
	w.state.livestock.duck = animal(1, 0)
	var sheep_key := World.key(Livestock.collector_cell("sheep"))
	var cow_key := World.key(Livestock.collector_cell("cow"))
	var duck_key := World.key(Livestock.collector_cell("duck"))
	var sheep_box := {"type": "chest", "owner": "alice", "items": {}}
	var cow_box := {"type": "chest", "owner": "alice", "items": {"milk": 1}}
	var duck_box := {"type": "private_chest", "owner": "alice", "items": {}}
	w.state.objects[sheep_key] = sheep_box
	w.state.objects[cow_key] = cow_box
	w.state.objects[duck_key] = duck_box
	var cow_item: String = Livestock.ANIMALS.cow.item
	var duck_item: String = Livestock.ANIMALS.duck.item
	cow_box.items = {cow_item: 1}
	var moved: Array = Livestock.collect_into_chests(w)
	expect(sheep_key in moved and cow_key in moved and not duck_key in moved, "premise: shared chests are filled, the private chest is not")
	expect(same_rows(rows(sheep_box), [row(PEN, "quality_wool", 1, true, 1234.0), row(PEN, "wool", 2, true, 1234.0)]), "sheep: premium then ordinary, net per item, at the authoritative whole second")
	expect(same_rows(rows(cow_box), [row(PEN, cow_item, 2, true, 1234.0)]), "cow: logs only what moved, not the 1 already there")
	expect(not duck_box.has(ChestHistory.FIELD) and duck_box.items.is_empty() and int(w.state.livestock.duck.ready) == 1, "a private chest is not a livestock destination: no transfer, no row")
	expect(valid_history(sheep_box) and valid_history(cow_box), "livestock history validates")
	expect(w.state.players.alice.inventory.is_empty(), "livestock never touches a backpack")
	# Nothing left to move / nothing committed: no extra rows.
	expect(Livestock.collect_into_chests(w).is_empty() and rows(sheep_box).size() == 2 and rows(cow_box).size() == 1, "a second pass with nothing ready adds no rows")
	# A full box refuses everything: the pen keeps the product and no row is written.
	w.state.livestock.sheep = animal(2, 1)
	sheep_box.items = fill(16)
	var rows_before := var_to_str(rows(sheep_box))
	expect(Livestock.collect_into_chests(w).is_empty() and var_to_str(rows(sheep_box)) == rows_before and int(w.state.livestock.sheep.ready) == 2, "a full box logs nothing and the pen keeps its product")
	# Premium takes the last free slot; only the item that really moved is logged.
	sheep_box.items = fill(15)
	w.state.time = 2000.0
	expect(Livestock.collect_into_chests(w).has(sheep_key), "one free slot: premium moves")
	var tail: Dictionary = rows(sheep_box).back()
	expect(rows(sheep_box).size() == 3 and tail.item == "quality_wool" and tail.amount == 1 and float(tail.time) == 2000.0, "only the premium that fit is logged")
	# A pen using collector equipment never writes to chests.
	var equipped := animal(2, 0)
	equipped.collector = 0
	w.state.livestock.sheep = equipped
	expect(Livestock.collect_into_chests(w).is_empty() and rows(sheep_box).size() == 3, "equipment-bound pens leave the chest alone")

# --------------------------------------------------------------------- salt --

func salt_world(chest_contents: Dictionary) -> Array:
	var w := fresh()
	var data: Dictionary = w.state.salt_pan
	var cell := SaltPan.chest_sockets(0)[0]
	var key := SaltPan.key(cell)
	var box_id := "b".repeat(32)
	data.players["alpha"] = SaltPan.RECORD.duplicate()
	var lot: Dictionary = data.lots[0]
	lot.owner = "alpha"
	lot.rake = true
	lot.on = true
	lot.chest = key
	lot.box = box_id
	data.pans[0] = {"s": "salt", "p": SaltPan.NEED, "t": 100.0, "f": ""}
	data.pans[1] = {"s": "salt", "p": SaltPan.NEED, "t": 150.0, "f": ""}
	var chest := {"type": "chest", "owner": "alpha", "items": chest_contents.duplicate(true), "box_id": box_id}
	w.state.regions[SaltPan.REGION].objects[key] = chest
	return [w, chest, key]

func test_salt() -> void:
	var made := salt_world({})
	var w: World = made[0]
	var chest: Dictionary = made[1]
	var objects: Dictionary = w.state.regions[SaltPan.REGION].objects
	var result: Dictionary = SaltPan.step(w.state, 200.0, 300.0, objects)
	expect(result.ok and result.changed, "salt: the collector step commits")
	expect(int(chest.items.sea_salt) == 2 * SaltPan.YIELD, "salt: both pans were raked into the chest")
	expect(same_rows(rows(chest), [row(SALT, "sea_salt", 3, true, 200.0), row(SALT, "sea_salt", 3, true, 200.0)]), "salt: one row per rake at its event time, net equals chest content")
	expect(net(rows(chest), "sea_salt") == int(chest.items.sea_salt) and valid_history(chest) and chest.box_id == "b".repeat(32), "salt: history valid, id preserved")
	expect(w.state.players.alice.inventory.is_empty() and w.state.players.bob.inventory.is_empty(), "salt: nothing is added to any backpack")
	# One long step logs the same rows as many short ones (the simulation stays exact).
	var split := salt_world({})
	var w2: World = split[0]
	var objects2: Dictionary = w2.state.regions[SaltPan.REGION].objects
	expect(SaltPan.step(w2.state, 200.0, 250.0, objects2).ok and SaltPan.step(w2.state, 250.0, 300.0, objects2).ok, "salt: split steps succeed")
	expect(var_to_str(rows(split[1])) == var_to_str(rows(chest)), "salt: a long step and short steps log identically")
	# Later raked pan: the event time is the crystallisation time, not the step end.
	var late := salt_world({})
	late[0].state.salt_pan.pans[0].t = 260.0
	late[0].state.salt_pan.pans[1].t = 280.0
	var late_objects: Dictionary = late[0].state.regions[SaltPan.REGION].objects
	expect(SaltPan.step(late[0].state, 200.0, 300.0, late_objects).ok, "salt: late step succeeds")
	expect(same_rows(rows(late[1]), [row(SALT, "sea_salt", 3, true, 260.0), row(SALT, "sea_salt", 3, true, 280.0)]), "salt: rows are ordered by their real event times")
	# Refused: a chest without a free slot takes no salt and logs nothing.
	var blocked := salt_world(fill(16))
	var blocked_objects: Dictionary = blocked[0].state.regions[SaltPan.REGION].objects
	SaltPan.step(blocked[0].state, 200.0, 300.0, blocked_objects)
	expect(not blocked[1].has(ChestHistory.FIELD) and not blocked[1].items.has("sea_salt"), "salt: a full chest logs nothing")
	# Rejected simulation (invalid pan): nothing committed, nothing logged.
	var broken := salt_world({})
	broken[0].state.salt_pan.pans[3].s = "mud"
	var rejected: Dictionary = SaltPan.step(broken[0].state, 200.0, 300.0, broken[0].state.regions[SaltPan.REGION].objects)
	expect(not rejected.ok and not broken[1].has(ChestHistory.FIELD) and broken[1].items.is_empty(), "salt: a rejected step logs nothing")
	# Collector off: nothing raked, nothing logged.
	var off := salt_world({})
	off[0].state.salt_pan.lots[0].on = false
	SaltPan.step(off[0].state, 200.0, 300.0, off[0].state.regions[SaltPan.REGION].objects)
	expect(not off[1].has(ChestHistory.FIELD) and off[1].items.is_empty(), "salt: a switched-off collector logs nothing")

# ---------------------------------------------------------- material sources --

func site_clear(w: World, a: Vector2i, size: Vector2i) -> bool:
	for y in range(a.y, a.y + size.y):
		for x in range(a.x, a.x + size.x):
			var c := Vector2i(x, y)
			var k := World.key(c)
			if not w.is_land(c) or w.water(c) or w.protected(c):
				return false
			for field in ["objects", "ground", "roofs", "crops", "forest"]:
				if w.state[field].has(k):
					return false
			var had: bool = w.state.removed.has(k)
			w.state.removed[k] = true
			var blocked: bool = w.blocked(c)
			if not had:
				w.state.removed.erase(k)
			if blocked:
				return false
	return true

func find_site(w: World) -> Vector2i:
	for oy in range(5, 55):
		for ox in range(5, 75):
			var c := Vector2i(ox, oy)
			if Vector2(c).distance_to(World.SPAWN) < 9.0:
				continue
			var far := true
			for u in used:
				if Vector2(c).distance_to(Vector2(u)) < 9.0:
					far = false
					break
			if far and site_clear(w, c - Vector2i(3, 3), Vector2i(7, 7)):
				used.append(c)
				for y in range(c.y - 3, c.y + 4):
					for x in range(c.x - 3, c.x + 4):
						var cell := Vector2i(x, y)
						if w.resource(cell) != "":
							w.state.removed[World.key(cell)] = true
				return c
	expect(false, "fixture: found a legal empty 7x7 home site")
	return Vector2i(-1, -1)

func do(w: World, token: String, action: String, p: Vector2i, extra: String = "", rid: String = "") -> Dictionary:
	for t in w.state.players:
		var person: Dictionary = w.state.players[t]
		person.region = "home"
		person.x = here.x
		person.y = here.y
	serial += 1
	if rid == "":
		rid = "req-%d" % serial
	return w.act(token, rid, action, p, extra)

func quote(w: World, token: String, station: Vector2i, chest: Vector2i, recipe_id: String) -> String:
	var def: Dictionary = World.CRAFT.get(recipe_id, {})
	var box: Dictionary = box_at(w, chest)
	var plan: Dictionary = Supply.plan(def.get("ingredients", {}), w.state.players[token].inventory, box.items)
	var alloc := {"from_backpack": plan.get("from_backpack", {}), "from_chest": plan.get("from_chest", {})}
	var digest: String = Sources.digest("craft", "bench", World.key(station), recipe_id, def, World.key(chest), str(box.get("box_id", "")), alloc)
	return Sources.encode(recipe_id, World.key(chest), str(box.get("box_id", "")), digest)

func test_material_sources() -> void:
	var w := fresh()
	var o := find_site(w)
	if o.x < 0:
		return
	here = Vector2(o) + Vector2(1.5, 1.6)
	w.state.objects[World.key(o)] = {"type": "bench", "owner": "alice", "items": {}}
	var e := o + Vector2i(1, 0)
	var chest := put(w, e, "chest", "alice", {"wood": 10, "stone": 5})
	var prep: Dictionary = do(w, "bob", "prepare_material_box", o, World.key(e))
	expect(prep.get("ok", false) == true, "prepare the shared chest: " + str(prep.get("message", "")))
	expect(not box_at(w, e).has(ChestHistory.FIELD), "preparing (quote/identity) is never a transfer")
	var id: String = str(box_at(w, e).get("box_id", ""))

	# Quote-only and refused calls leave the history alone.
	w.state.players.bob.inventory = {"wood": 5, "stone": 4}
	var extra := quote(w, "bob", o, e, KIT)
	var stale := extra.left(extra.length() - 1) + ("0" if not extra.ends_with("0") else "1")
	var before := var_to_str(w.state)
	var refused: Dictionary = do(w, "bob", "craft", o, stale)
	expect(not refused.ok and var_to_str(w.state) == before, "a stale digest is refused without any change")
	expect(not box_at(w, e).has(ChestHistory.FIELD), "refused sourced craft logs nothing")
	var plain: Dictionary = do(w, "bob", "craft", o, KIT)
	expect(not plain.ok and not box_at(w, e).has(ChestHistory.FIELD), "an unaffordable backpack-only craft logs nothing")

	# Save failure rolls the whole craft back, including its history row.
	var good := w.save_path
	w.save_path = dir.path_join("missing-dir").path_join("world.json")
	var failed: Dictionary = do(w, "bob", "craft", o, extra)
	expect(not failed.ok, "unwritable save: the craft is reported as failed")
	expect(not box_at(w, e).has(ChestHistory.FIELD) and int(box_at(w, e).items.wood) == 10, "a rolled-back craft leaves no history row and keeps the chest stock")
	w.save_path = good

	# Committed: the exact chest share (3 wood) is logged once, under the crafter's display name.
	var request := "craft-history"
	var made: Dictionary = do(w, "bob", "craft", o, extra, request)
	expect(made.get("ok", false) == true, "sourced craft commits: " + str(made.get("message", "")))
	var stamp := float(w.state.time)
	expect(same_rows(rows(box_at(w, e)), [row("小豆", "wood", 3, false, stamp)]) and int(box_at(w, e).items.wood) == 7, "one withdrawal row = the exact chest debit, authoritative clock")
	var replay: Dictionary = do(w, "bob", "craft", o, extra, request)
	expect(replay == made and rows(box_at(w, e)).size() == 1 and int(box_at(w, e).items.wood) == 7, "a replayed request logs and debits once")
	expect(w.state.players.bob.inventory.get(KIT, 0) == 1, "the crafter still receives the product in the backpack")
	no_tokens(rows(box_at(w, e)), "material")

	# Two items drawn from the chest: one row each, sorted, never the backpack share.
	w.state.players.bob.inventory = {}
	box_at(w, e).items = {"wood": 20, "stone": 10}
	var second := quote(w, "bob", o, e, KIT)
	expect(do(w, "bob", "craft", o, second).get("ok", false) == true, "chest-only craft commits")
	var list := rows(box_at(w, e))
	expect(list.size() == 3 and list[1].item == "stone" and int(list[1].amount) == 4 and list[2].item == "wood" and int(list[2].amount) == 8 and not list[1].depositing and not list[2].depositing, "each chest-drawn item is its own net row")
	expect(int(box_at(w, e).items.wood) == 12 and int(box_at(w, e).items.stone) == 6 and net(list, "wood") == -11 and net(list, "stone") == -4, "net withdrawals equal the real chest debits (3 + 8 wood, 4 stone)")
	expect(valid_history(box_at(w, e)) and box_at(w, e).box_id == id, "history valid, box id preserved")

	# Private chest: the owner's withdrawal is logged; another member is refused and logs nothing.
	var pe := o + Vector2i(0, -1)
	put(w, pe, "private_chest", "alice", {"wood": 9, "stone": 4})
	expect(do(w, "alice", "prepare_material_box", o, World.key(pe)).get("ok", false) == true, "owner prepares a private chest")
	w.state.players.alice.inventory = {}
	expect(do(w, "alice", "craft", o, quote(w, "alice", o, pe, KIT)).get("ok", false) == true, "owner crafts from the private chest")
	expect(rows(box_at(w, pe)).size() == 2 and rows(box_at(w, pe))[0].actor == "阿米" and int(box_at(w, pe).items.get("wood", 0)) == 1, "private chest rows carry the owner's display name")
	var denied: Dictionary = do(w, "bob", "prepare_material_box", o, World.key(pe))
	expect(not denied.ok and rows(box_at(w, pe)).size() == 2, "a non-owner can neither use nor log a private chest")
	expect(valid_history(box_at(w, pe)) and box_at(w, pe).owner == "alice", "private ownership preserved")
