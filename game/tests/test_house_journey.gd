extends "res://tests/test_chapter_journey.gd"

# Structural-house slice (not complete housing): from a fresh world, with starter
# supplies and natural gathering only, clear a real site, build a 3x3-floor home
# enclosed by walls/window/door, place a bed, and let World.act roof it automatically
# when the last structural piece seals the room (no manual roof action), then check it
# with HouseRooms.inspect on the current region snapshot. Driven through the scripted
# World API (world.act / move_player) with normal costs, reach and collision.
const NO_CELL := Vector2i(-1,-1)
const INTERIOR := [Vector2i(1,1),Vector2i(2,1),Vector2i(3,1),Vector2i(1,2),Vector2i(2,2),Vector2i(3,2),Vector2i(1,3),Vector2i(2,3),Vector2i(3,3)]
const CORNERS := [Vector2i(0,0),Vector2i(4,0),Vector2i(0,4),Vector2i(4,4)]
const WALLS := [Vector2i(0,0),Vector2i(1,0),Vector2i(3,0),Vector2i(4,0),Vector2i(0,1),Vector2i(0,2),Vector2i(0,3),Vector2i(4,1),Vector2i(4,2),Vector2i(4,3),Vector2i(0,4),Vector2i(1,4),Vector2i(3,4),Vector2i(4,4)]
# Interior cell the builder stands on for each wall: within act()'s reach, so the
# automatic approach never parks the builder on a future wall cell. (0,0) is built from
# the bed cell (1,1) before the bed exists; all others from non-bed interior cells.
const WALL_STANDS := {Vector2i(0,0):Vector2i(1,1), Vector2i(1,0):Vector2i(2,1), Vector2i(3,0):Vector2i(3,1), Vector2i(4,0):Vector2i(3,1), Vector2i(0,1):Vector2i(1,2), Vector2i(0,2):Vector2i(1,2), Vector2i(0,3):Vector2i(1,3), Vector2i(4,1):Vector2i(3,1), Vector2i(4,2):Vector2i(3,2), Vector2i(4,3):Vector2i(3,3), Vector2i(0,4):Vector2i(1,3), Vector2i(1,4):Vector2i(1,3), Vector2i(3,4):Vector2i(3,3), Vector2i(4,4):Vector2i(3,3)}
const BED_CORNER := Vector2i(0,0)
const EXPECTED_COST := {"wood":96, "fiber":39, "stone":1}
const WINDOW := Vector2i(2,0)
const DOOR := Vector2i(2,4)
const FRONT := Vector2i(2,5)
const CENTER := Vector2i(2,2)
const BED := Vector2i(1,1)
const REMOVED_WALL := Vector2i(1,4)
# Material budget. "roof":9 is NOT built by hand: the closer of the room pays the normal
# roof recipe for each of the 9 interior tiles automatically, so the gathering budget
# must still include them.
const PLAN := {"floor":9,"roof":9,"bed":1,"door":1,"window":1,"wall":14}
const MIN_SCHEMA := 17
const MAX_GATHER := 60
const MAX_SITE_RING := 18
var site := NO_CELL
var rooms = null
var cleared := 0
var gather_hits := 0
var inspections := 0

func _initialize() -> void:
	run_house_journey()

func run_house_journey() -> void:
	var path := OS.get_environment("TEMP").path_join("house-journey-%s.json" % Crypto.new().generate_random_bytes(8).hex_encode())
	# Never adopt or later delete a save this run did not create.
	if FileAccess.file_exists(path) or FileAccess.file_exists(path+".bak"):
		expect(false, "House journey save path already exists: " + path)
		finish("")
		return
	world.save_path = path
	world.add_player(TOKEN, "Island")
	rooms = load("res://scripts/house_rooms.gd")
	expect(rooms != null, "HouseRooms helper loads")
	if not failed:build_house()
	if not failed:reload_and_verify()
	if not failed:remove_and_rebuild()
	print("HOUSE_JOURNEY site=%s actions=%d walk_tiles=%d site_resources_cleared=%d gather_hits=%d inspections=%d world_steps=0 world_seconds=%.1f scripted_world_api=true coins=%d inventory=%s passed=%s" % [site, actions, walking, cleared, gather_hits, inspections, float(world.state.time), int(person().coins), JSON.stringify(bag()), not failed])
	finish(path)

func finish(path: String) -> void:
	if not path.is_empty():
		for file in [path, path+".bak", path+".tmp"]:
			if FileAccess.file_exists(file):DirAccess.remove_absolute(file)
	print("HOUSE_JOURNEY_TESTS checks=%d failures=%d" % [checks, failures])
	quit(int(failed))

func spot(offset: Vector2i) -> Vector2i:
	return site + offset

func here() -> Vector2i:
	return Vector2i(floori(person().x), floori(person().y))

func counts(record: Dictionary) -> Dictionary:
	var inv: Dictionary = record.inventory
	return {"wood":int(inv.get("wood",0)), "fiber":int(inv.get("fiber",0)), "stone":int(inv.get("stone",0)), "coins":int(record.coins)}

func plan_cost() -> Dictionary:
	var cost := {"wood":0, "fiber":0, "stone":0}
	for kind in PLAN:
		for item in cost.keys():
			cost[item] = int(cost[item]) + int(World.BUILD[kind].get(item,0)) * int(PLAN[kind])
	return cost

func footprint() -> Array:
	var cells := []
	for y in range(5):
		for x in range(5):
			cells.append(Vector2i(x,y))
	cells.append(FRONT)
	return cells

# -1 = unusable; otherwise number of natural resources that must be cleared by hand.
func site_work(origin: Vector2i) -> int:
	var work := 0
	for offset in footprint():
		var tile: Vector2i = origin + offset
		var tile_key := World.key(tile)
		if not world.is_land(tile) or world.water(tile) or world.protected(tile):return -1
		for layer in ["objects","ground","roofs","crops","forest"]:
			if world.state[layer].has(tile_key):return -1
		var kind := world.resource(tile)
		if kind == "":
			if world.blocked(tile):return -1
		elif kind in ["tree","rock","grass"]:
			work += 1
		else:
			return -1
	return work

func site_reachable(origin: Vector2i) -> bool:
	if route(origin + FRONT, 1.0).is_empty():return false
	for offset in footprint():
		var tile: Vector2i = origin + offset
		if world.resource(tile) in ["tree","rock"] and route(tile).is_empty():return false
	return true

# Deterministic ring search around the player; prefers a site that needs real clearing.
func find_site() -> Vector2i:
	var origin := here() - CENTER
	var fallback := NO_CELL
	for distance in range(0, MAX_SITE_RING + 1):
		for y in range(origin.y-distance, origin.y+distance+1):
			for x in range(origin.x-distance, origin.x+distance+1):
				if maxi(absi(x-origin.x), absi(y-origin.y)) != distance:continue
				var candidate := Vector2i(x,y)
				var work := site_work(candidate)
				if work < 0:continue
				if work == 0:
					if fallback == NO_CELL and site_reachable(candidate):fallback = candidate
					continue
				if site_reachable(candidate):return candidate
	return fallback

func harvest_resource(target: Vector2i, kind: String) -> void:
	var tool := "pick" if kind == "rock" else "axe"
	var hits := 2 if kind == "rock" else (3 if kind == "tree" else 1)
	for hit in range(hits):
		act(tool, target)
		if failed:return
	gather_hits += hits
	expect(world.resource(target) == "", "Natural %s at %s fully gathered" % [kind, target])

func gather_item(item: String, minimum: int, kinds: Array) -> void:
	var rounds := 0
	while int(bag().get(item,0)) < minimum and not failed:
		rounds += 1
		if rounds > MAX_GATHER:
			expect(false, "Gathering %s exceeded %d sources" % [item, MAX_GATHER])
			return
		var target := NO_CELL
		var kind := ""
		for candidate in kinds:
			target = find_resource(candidate)
			if target != NO_CELL:
				kind = candidate
				break
		if target == NO_CELL:
			expect(false, "No reachable natural source for " + item)
			return
		harvest_resource(target, kind)

func go_to(tile: Vector2i) -> void:
	if failed or here() == tile:return
	walk_to(tile, 1.0)
	if failed:return
	var direction := Vector2(tile - here())
	if not is_equal_approx(direction.length(), 1.0):
		expect(false, "No cardinal approach onto %s" % tile)
		return
	for step in range(4):
		world.move_player(TOKEN, direction, 0.25/3.6)
	walking += 1
	expect(Vector2(person().x,person().y).distance_to(Vector2(tile)+Vector2(0.5,0.5)) <= 0.001, "Stepped onto %s through passable tiles" % tile)

func inspect_home(at: Vector2i, label: String) -> Dictionary:
	if failed or rooms == null:return {}
	var region := world.player_region(TOKEN)
	expect(region == World.REGIONS.HOME, "Inspecting the region the builder is in (%s)" % label)
	var result = rooms.inspect(world.region_snapshot(region), at)
	inspections += 1
	if typeof(result) != TYPE_DICTIONARY:
		expect(false, "HouseRooms.inspect returns a Dictionary (%s)" % label)
		return {}
	print("HOUSE_INSPECT %s at=%s found=%s complete=%s area=%d doors=%d gaps=%d roof_missing=%d beds=%d reachable_bed=%s contributors=%s missing=%s" % [label, at, result.get("found",false), result.get("complete",false), int(result.get("area",0)), int(result.get("door_count",0)), int(result.get("gap_count",0)), int(result.get("roof_missing",0)), int(result.get("bed_count",0)), result.get("reachable_bed",false), JSON.stringify(result.get("contributors",[])), JSON.stringify(result.get("missing",[]))])
	return result

func same_interior(result: Dictionary) -> bool:
	var cells: Array = result.get("cells", [])
	if cells.size() != INTERIOR.size():return false
	for offset in INTERIOR:
		if not cells.has(spot(offset)):return false
	return true

func assert_complete(result: Dictionary, label: String) -> void:
	if result.is_empty():
		expect(false, label + ": no inspection result")
		return
	var contributors: Array = result.get("contributors", [])
	var missing: Array = result.get("missing", [])
	expect(bool(result.get("found",false)) and bool(result.get("complete",false)), label + ": structurally complete")
	expect(same_interior(result) and int(result.get("area",0)) == INTERIOR.size(), label + ": component is exactly the 3x3 interior")
	expect(int(result.get("door_count",0)) == 1 and int(result.get("gap_count",-1)) == 0 and int(result.get("roof_missing",-1)) == 0 and int(result.get("bed_count",0)) == 1 and bool(result.get("reachable_bed",false)), label + ": door, sealed edges, full roof, reachable bed")
	expect(contributors.size() == 1 and str(contributors[0]) == TOKEN and missing.is_empty(), label + ": sole builder credited, nothing missing")

func is_auto_roof(roof) -> bool:
	if typeof(roof) != TYPE_DICTIONARY:return false
	var flag = roof.get("auto")
	return roof.get("type","") == "roof" and roof.get("owner","") == TOKEN and typeof(flag) == TYPE_BOOL and flag

# Number of footprint tiles carrying a roof of any kind, and how many of those are the
# builder's automatic roofs over the exact 3x3 interior.
func roof_tally(target) -> Dictionary:
	var state: Dictionary = target.state
	var any := 0
	var auto := 0
	for offset in footprint():
		var tile_key := World.key(spot(offset))
		if not state.roofs.has(tile_key):continue
		any += 1
		if INTERIOR.has(offset) and is_auto_roof(state.roofs[tile_key]):auto += 1
	return {"any":any, "auto":auto}

func roof_receipt(count: int) -> Dictionary:
	return {"wood":int(World.BUILD.roof.get("wood",0))*count, "fiber":int(World.BUILD.roof.get("fiber",0))*count, "stone":int(World.BUILD.roof.get("stone",0))*count}

func layout_owned(target) -> bool:
	var state: Dictionary = target.state
	for offset in INTERIOR:
		var tile_key := World.key(spot(offset))
		if state.ground.get(tile_key,{}).get("type","") != "floor" or state.ground[tile_key].get("owner","") != TOKEN:return false
		if not is_auto_roof(state.roofs.get(tile_key)):return false
	if roof_tally(target).any != INTERIOR.size():return false
	var expected := {BED:"bed", WINDOW:"window", DOOR:"door"}
	for offset in WALLS:expected[offset] = "wall"
	for offset in expected:
		var tile_key := World.key(spot(offset))
		if state.objects.get(tile_key,{}).get("type","") != expected[offset] or state.objects[tile_key].get("owner","") != TOKEN:return false
	return true

func same_inventory(a: Dictionary, b: Dictionary) -> bool:
	for item in a:
		if int(a[item]) != int(b.get(item,0)):return false
	for item in b:
		if int(b[item]) != int(a.get(item,0)):return false
	return true

func build_house() -> void:
	var start := counts(person())
	expect(start.wood == 12 and start.fiber == 10 and start.stone == 4 and start.coins == 120, "Fresh player holds only starter supplies")
	site = find_site()
	if site == NO_CELL:
		expect(false, "No reachable buildable 5x5 site near spawn")
		return
	print("HOUSE_SITE origin=%s door=%s front=%s resources_to_clear=%d" % [site, spot(DOOR), spot(FRONT), site_work(site)])
	var empty := inspect_home(spot(CENTER), "bare site")
	expect(not bool(empty.get("found",true)) and not Array(empty.get("missing",[])).is_empty(), "Bare site reports no home with a reason")
	for offset in footprint():
		var tile: Vector2i = site + offset
		var kind := world.resource(tile)
		if kind == "":continue
		harvest_resource(tile, kind)
		cleared += 1
		if failed:return
	expect(site_work(site) == 0, "Site cleared by ordinary gathering actions")
	var cost := plan_cost()
	var ring := {}
	for offset in WALLS + [WINDOW, DOOR]:ring[offset] = true
	var full_ring := ring.size() == 16 and WALLS.size() == int(PLAN.wall)
	for y in range(5):
		for x in range(5):
			var edge := x == 0 or y == 0 or x == 4 or y == 4
			if edge != ring.has(Vector2i(x,y)):full_ring = false
	for offset in CORNERS:
		if not WALLS.has(offset):full_ring = false
	expect(full_ring, "Plan rings the 3x3 interior with 14 walls (incl. 4 corners), window and door")
	expect(int(cost.wood) == int(EXPECTED_COST.wood) and int(cost.fiber) == int(EXPECTED_COST.fiber) and int(cost.stone) == int(EXPECTED_COST.stone), "Recipe-derived plan cost %s equals 96 wood, 39 fiber, 1 stone" % JSON.stringify(cost))
	print("HOUSE_PLAN plan=%s cost=%s" % [JSON.stringify(PLAN), JSON.stringify(cost)])
	if failed:return
	gather_item("wood", cost.wood, ["tree"])
	gather_item("fiber", cost.fiber, ["grass","tree"])
	gather_item("stone", cost.stone, ["rock"])
	if failed:return
	var before := counts(person())
	var actions_before := actions
	# Build actions, derived from the plan: one floor build_area, door + opening it, one
	# action per wall, bed and window. No roof action: with automatic roofs this is one
	# operation fewer than the old manual-roof journey (which had a roof build_area).
	var expected_ops := 1 + int(PLAN.door) + 1 + int(PLAN.wall) + int(PLAN.bed) + int(PLAN.window)
	# Build everything from inside; the door goes in first and is opened so the builder is never sealed in.
	go_to(spot(CENTER))
	var a := spot(Vector2i(1,1))
	var b := spot(Vector2i(3,3))
	act("build_area", a, "floor|%d|%d" % [b.x, b.y])
	act("build", spot(DOOR), "door")
	act("door", spot(DOOR))
	expect(failed or bool(world.state.objects[World.key(spot(DOOR))].get("open",false)), "Door opened before closing the walls")
	# The (0,0) corner is only within reach from the future bed cell, so it goes in first.
	go_to(spot(WALL_STANDS[BED_CORNER]))
	act("build", spot(BED_CORNER), "wall")
	if failed:return
	go_to(spot(CENTER))
	# The bed is interior furnishing, not a roof prerequisite; placing it early is fine.
	act("build", spot(BED), "bed")
	act("build", spot(WINDOW), "window")
	var remaining := []
	for offset in WALLS:
		if offset != BED_CORNER:remaining.append(offset)
	# Cardinal enclosure does not depend on diagonal corner blocks. Build all
	# corners first, then close the final south-side edge from its legal stand.
	var closer := Vector2i(3,4)
	remaining.erase(closer)
	remaining.append(closer)
	expect(not CORNERS.has(closer) and remaining.has(Vector2i(4,4)), "All corners precede the final cardinal wall")
	for offset in remaining:
		go_to(spot(WALL_STANDS[offset]))
		if failed:return
		var closing: bool = offset == closer
		var pre := counts(person())
		if closing:
			expect(roof_tally(world).any == 0, "No roof exists anywhere on the site before the last wall closes the room")
		act("build", spot(offset), "wall")
		if failed:return
		var post := counts(person())
		var paid_roofs := roof_receipt(INTERIOR.size()) if closing else roof_receipt(0)
		var wall_wood := int(World.BUILD.wall.get("wood",0))
		var wall_fiber := int(World.BUILD.wall.get("fiber",0))
		var wall_stone := int(World.BUILD.wall.get("stone",0))
		expect(pre.wood - post.wood == wall_wood + int(paid_roofs.wood) and pre.fiber - post.fiber == wall_fiber + int(paid_roofs.fiber) and pre.stone - post.stone == wall_stone + int(paid_roofs.stone) and pre.coins == post.coins, "Wall at %s deducted wall cost plus roofs %s" % [offset, JSON.stringify(paid_roofs)])
		var tally := roof_tally(world)
		if closing:
			expect(tally.any == INTERIOR.size() and tally.auto == INTERIOR.size(), "Closing wall auto-roofed exactly the 9 interior tiles, owned by the closer (%s)" % JSON.stringify(tally))
		else:
			expect(tally.any == 0, "No automatic roof while the room is still open (after wall %s)" % offset)
	expect(actions - actions_before == expected_ops, "House built in %d operations with no manual roofing (got %d)" % [expected_ops, actions - actions_before])
	go_to(spot(FRONT))
	if failed:return
	expect(here() == spot(FRONT), "Builder walked out through the open door")
	var after := counts(person())
	expect(before.wood - after.wood == cost.wood and before.fiber - after.fiber == cost.fiber and before.stone - after.stone == cost.stone and before.coins == after.coins, "House consumed exactly the normal build costs %s" % JSON.stringify(cost))
	expect(layout_owned(world), "Every floor, automatic roof, wall (incl. 4 corners), window, door and bed is owned by the builder")
	var corners_owned := true
	for offset in CORNERS:
		var corner: Dictionary = world.state.objects.get(World.key(spot(offset)), {})
		if corner.get("type","") != "wall" or corner.get("owner","") != TOKEN:corners_owned = false
	expect(corners_owned, "All four corner walls built and owned by the builder")
	assert_complete(inspect_home(spot(CENTER), "door open"), "Finished home with open door")
	act("door", spot(DOOR))
	expect(failed or not bool(world.state.objects[World.key(spot(DOOR))].get("open",true)), "Door closed from outside")
	assert_complete(inspect_home(spot(CENTER), "door closed"), "Finished home with closed door")
	var near := inspect_home(spot(FRONT), "from front step")
	expect(bool(near.get("complete",false)) and same_interior(near), "Inspecting from the front step selects the nearest interior")
	expect(not route(Vector2i(43,29)).is_empty(), "Village stall still reachable from the new home")

func reload_and_verify() -> void:
	var path := world.save_path
	var expected := counts(person())
	var inventory: Dictionary = bag().duplicate(true)
	var position := Vector2(person().x, person().y)
	expect(FileAccess.file_exists(path), "Primary save exists")
	var reload := World.new()
	expect(reload.load_world(path) and not reload.recovered_from_backup and reload.state.players.has(TOKEN), "Home reloads from the primary save")
	if failed:return
	reload.add_player(TOKEN, "Island")
	var again: Dictionary = reload.state.players[TOKEN]
	expect(counts(again) == expected and same_inventory(inventory, again.inventory), "Inventory and coins retained after reload")
	expect(Vector2(again.x, again.y).distance_to(position) <= 0.001 and reload.player_region(TOKEN) == World.REGIONS.HOME, "Re-registered player keeps position and region")
	expect(int(reload.state.get("version",0)) >= MIN_SCHEMA, "Reloaded save uses the automatic-roof schema (>= %d)" % MIN_SCHEMA)
	var tally := roof_tally(reload)
	expect(tally.any == INTERIOR.size() and tally.auto == INTERIOR.size(), "Automatic roof flags and ownership survive reload/rejoin (%s)" % JSON.stringify(tally))
	expect(layout_owned(reload), "Ownership retained after reload")
	world = reload
	assert_complete(inspect_home(spot(CENTER), "after reload"), "Reloaded home")

func remove_and_rebuild() -> void:
	var wall_key := World.key(spot(REMOVED_WALL))
	var before := counts(person())
	var inventory_before: Dictionary = bag().duplicate(true)
	act("remove", spot(REMOVED_WALL))
	if failed:return
	var refunded := counts(person())
	expect(not world.state.objects.has(wall_key), "Owner removed one wall")
	# Opening the room refunds the wall plus all 9 automatic roofs to their payer (the builder).
	var roofs_back := roof_receipt(INTERIOR.size())
	var want := {"wood":int(World.BUILD.wall.get("wood",0)) + int(roofs_back.wood), "fiber":int(World.BUILD.wall.get("fiber",0)) + int(roofs_back.fiber), "stone":int(World.BUILD.wall.get("stone",0)) + int(roofs_back.stone)}
	expect(want.wood == 12 and want.fiber == 27 and want.stone == 0, "Expected opening refund is 3 wood wall + 9 wood/27 fiber roofs (%s)" % JSON.stringify(want))
	expect(refunded.wood - before.wood == want.wood and refunded.fiber - before.fiber == want.fiber and refunded.stone - before.stone == want.stone and refunded.coins == before.coins, "Wall removal refunds the wall plus the automatic roofs %s" % JSON.stringify(want))
	expect(roof_tally(world).any == 0, "Opening the room removed every automatic roof")
	var gap := inspect_home(spot(CENTER), "wall removed")
	expect(bool(gap.get("found",false)) and not bool(gap.get("complete",true)) and int(gap.get("gap_count",0)) >= 1 and not Array(gap.get("missing",[])).is_empty(), "Removed wall makes the home incomplete with a reason")
	act("build", spot(REMOVED_WALL), "wall")
	if failed:return
	expect(counts(person()) == before and same_inventory(bag(), inventory_before), "Re-closing costs exactly the refund; inventory identical to before the cycle")
	var tally := roof_tally(world)
	expect(tally.any == INTERIOR.size() and tally.auto == INTERIOR.size(), "Re-closing restored the 9 automatic roofs owned by the builder (%s)" % JSON.stringify(tally))
	expect(layout_owned(world), "Rebuilt wall and restored roofs owned by the builder")
	assert_complete(inspect_home(spot(CENTER), "wall rebuilt"), "Rebuilt home")
	var reload := World.new()
	expect(reload.load_world(world.save_path) and not reload.recovered_from_backup and layout_owned(reload), "Rebuilt home persists in the primary save")
