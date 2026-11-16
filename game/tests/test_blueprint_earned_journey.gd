extends "res://tests/test_house_journey.gd"

# Earned-resource blueprint journey (end to end, no seeded resources).
#
# Provenance: starts from a FRESH World in a unique temp save. The source house is
# earned by the inherited house journey (starter supplies + natural gathering via
# world.act, movement via world.move_player along BFS routes, automatic roofs on the
# closing wall). No previously saved artifact is read, copied or modified; in
# particular work/house-rooms/auto-journey-complete.json is never opened.
#
# Then, through the real host Session (peer 1) and the real BlueprintController:
#   capture own house from the PUBLIC snapshot -> save to personal library ->
#   dispose controller + free Session -> reload World from disk -> clear a second
#   site and gather the full quoted materials by ordinary actions -> walk to a legal
#   stand -> new Session + controller (library reloaded from disk) -> choose saved
#   design -> pin -> real authoritative quote -> confirm via controller ->
#   verify layout incl. 9 automatic roofs, exact material debit, original house
#   untouched -> reload World again -> persistence, single receipt, no duplicate.
#
# Fixture / automation disclosure (NOT human play):
#  * HostSession overrides _ready so user://profile.json is never read/written and
#    disables physics ticking (the world is never stepped: world_steps=0, no
#    simulated waiting is needed for this route).
#  * Movement and actions use the scripted World API (move_player / act), like the
#    other journeys. Each Session is attached (Session._attach_registered(1, token),
#    the host-registration path) only AFTER the scripted movement of its phase, so its
#    own snapshot is current; every later snapshot is sent by the Session itself.
#  * Blueprint rate limits and controller timeouts use real clocks (one quote and one
#    apply per Session; no fake clock is injected).
#  * No inventory, position, flag, unlock or progress field is written directly.
#  * Library, pending record and world save live in unique TEMP paths removed at the
#    end. Evidence is kept ONLY when --blueprint-output=<existing dir> is given; files
#    there are never overwritten.

const BP_DESIGN := preload("res://scripts/blueprint_design.gd")
const BP_LIBRARY := preload("res://scripts/blueprint_library.gd")
const BP_PENDING := preload("res://scripts/blueprint_pending.gd")
const BP_CONTROLLER := preload("res://scripts/blueprint_controller.gd")
const BP_NAME := "親手蓋的小屋"
const BP_PIECES := 26
const BP_BASE_COST := {"wood":87, "fiber":12, "stone":1}
# Cell the builder stands on for placement: west of the footprint, within BLUEPRINT_RANGE.
const BP_STAND := Vector2i(-1,2)
const BP_SITE_RING := 26
const MAX_ACTIONS := 400
const MAX_WALK_TILES := 3000
const REPORT_FILES := ["blueprint-earned-complete.json", "blueprint-earned-library.json", "blueprint-earned-report.json"]

class HostSession extends "res://scripts/session.gd":
	func _ready() -> void:
		name = "BlueprintJourneySession"
		session_nonce = Crypto.new().generate_random_bytes(16).hex_encode()
		set_physics_process(false)

var run_id := ""
var library_path := ""
var scope := ""
var output_dir := ""
var original_site := NO_CELL
var placed := NO_CELL
var session = null
var controller = null
var applied_events: Array = []
var library_id := ""
var original_record := {}
var earned := {}
var phase_actions := {}
var phase_walk := {}
var cleared2 := 0
var quote_seen := {}
var receipt_nonce := ""
var world_reloads := 0

func _initialize() -> void:
	run_blueprint_journey.call_deferred()

func settle(frames: int = 3) -> void:
	for i in frames:
		await process_frame

func run_blueprint_journey() -> void:
	run_id = Crypto.new().generate_random_bytes(8).hex_encode()
	var temp := OS.get_environment("TEMP")
	var path := temp.path_join("blueprint-earned-%s.json" % run_id)
	library_path = temp.path_join("blueprint-earned-%s-library.json" % run_id)
	scope = "blueprint-earned-journey-" + run_id
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--blueprint-output="):output_dir = argument.trim_prefix("--blueprint-output=")
	for file in [path, path+".bak", library_path, BP_PENDING.path_for(library_path, scope)]:
		if FileAccess.file_exists(file):
			expect(false, "Temp path already exists, refusing to adopt it: " + file)
	if not output_dir.is_empty():
		expect(DirAccess.dir_exists_absolute(output_dir), "Explicit output directory exists: " + output_dir)
		for report_name in REPORT_FILES:
			expect(not FileAccess.file_exists(output_dir.path_join(report_name)), "Output evidence is never overwritten: " + report_name)
	if failed:
		# Nothing was created by this run: never delete pre-existing files.
		library_path = ""
		finish("")
		return
	world.save_path = path
	world.add_player(TOKEN, "Island")
	rooms = load("res://scripts/house_rooms.gd")
	expect(rooms != null, "HouseRooms helper loads")
	# Phase 1: earn the source house from a fresh world (inherited journey).
	if not failed:mark("house")
	if not failed:build_house()
	if not failed:reload_and_verify()
	if not failed:
		world_reloads += 1
		original_site = site
		original_record = footprint_record(world, original_site)
		mark_end("house")
	# Phase 2: capture through the controller from the public snapshot and save.
	if not failed:await capture_and_save()
	# Phase 3: reload the World from disk, earn the materials, place via controller.
	if not failed:reload_world("before placement")
	if not failed:prepare_second_site()
	if not failed:await place_from_library()
	# Phase 4: persistence and no duplicate.
	if not failed:await verify_persistence()
	expect(actions <= MAX_ACTIONS, "Action budget respected (%d <= %d)" % [actions, MAX_ACTIONS])
	expect(walking <= MAX_WALK_TILES, "Walk budget respected (%d <= %d)" % [walking, MAX_WALK_TILES])
	if not failed:keep_evidence(path)
	print("BLUEPRINT_EARNED_JOURNEY source_site=%s placed_origin=%s actions=%d walk_tiles=%d phase_actions=%s phase_walk=%s site_resources_cleared=%d second_site_cleared=%d gather_hits=%d inspections=%d earned_for_placement=%s quote_cost=%s roof_add=%d world_steps=0 world_seconds=%.1f world_reloads=%d scripted_world_api=true seeded_resources=false artifact_inputs=none coins=%d inventory=%s passed=%s" % [original_site, placed, actions, walking, JSON.stringify(phase_actions), JSON.stringify(phase_walk), cleared, cleared2, gather_hits, inspections, JSON.stringify(earned), JSON.stringify(quote_seen.get("cost",{})), int(quote_seen.get("roof_add",0)), float(world.state.time), world_reloads, int(person().coins), JSON.stringify(bag()), not failed])
	finish(path)

func finish(path: String) -> void:
	if controller != null and is_instance_valid(controller):
		controller.dispose()
		controller.free()
	controller = null
	if session != null and is_instance_valid(session):session.free()
	session = null
	var files := []
	if not path.is_empty():files += [path, path+".bak", path+".tmp"]
	if not library_path.is_empty():
		files += [library_path, BP_PENDING.path_for(library_path, scope)]
		var folder := library_path.get_base_dir()
		var prefix := library_path.get_file() + ".stage-"
		for staged in DirAccess.get_files_at(folder):
			if staged.begins_with(prefix):files.append(folder.path_join(staged))
	for file in files:
		if not file.is_empty() and FileAccess.file_exists(file):DirAccess.remove_absolute(file)
	print("BLUEPRINT_EARNED_JOURNEY_TESTS checks=%d failures=%d" % [checks, failures])
	quit(int(failed))

# ------------------------------------------------------------------ bookkeeping

func mark(label: String) -> void:
	phase_actions[label] = actions
	phase_walk[label] = walking

func mark_end(label: String) -> void:
	phase_actions[label] = actions - int(phase_actions.get(label,0))
	phase_walk[label] = walking - int(phase_walk.get(label,0))

func same_json(a: Variant, b: Variant) -> bool:
	return JSON.parse_string(JSON.stringify(a)) == JSON.parse_string(JSON.stringify(b))

func ints(value: Variant) -> Dictionary:
	var out := {}
	if value is Dictionary:
		for item in value:
			if int(value[item]) != 0:out[str(item)] = int(value[item])
	return out

func cells_of(base: Vector2i) -> Array:
	var out := []
	for offset in footprint():out.append(base + offset)
	return out

# Every built entry on a site's footprint (incl. the front step), home region.
func footprint_record(target, base: Vector2i) -> Dictionary:
	var snap: Dictionary = target.region_snapshot(World.REGIONS.HOME)
	var out := {}
	for tile in cells_of(base):
		var tile_key := World.key(tile)
		for layer in ["ground","objects","roofs"]:
			if snap[layer].has(tile_key):out[layer+":"+tile_key] = snap[layer][tile_key]
	return out

# Run a house-journey helper (spot()-based) against another origin.
func at_site(base: Vector2i, check: Callable) -> Variant:
	var keep := site
	site = base
	var result = check.call()
	site = keep
	return result

func owned_tally(target) -> Dictionary:
	var snap: Dictionary = target.region_snapshot(World.REGIONS.HOME)
	var tally := {}
	for layer in ["ground","objects","roofs"]:
		for entry in snap[layer].values():
			if entry is Dictionary and entry.get("owner","") == TOKEN:
				var label := str(entry.get("type",""))
				if layer == "roofs" and is_auto_roof(entry):label = "auto_roof"
				tally[label] = int(tally.get(label,0)) + 1
	return tally

func blueprint_receipts(target) -> Array:
	var out := []
	for receipt in target.state.players[TOKEN].receipts:
		if str(receipt).begins_with("blueprint:"):out.append(str(receipt))
	return out

func expected_quote_cost() -> Dictionary:
	var cost := BP_BASE_COST.duplicate()
	for item in World.BUILD.roof:
		if item == "name":continue
		cost[item] = int(cost.get(item,0)) + int(World.BUILD.roof[item]) * INTERIOR.size()
	return cost

# ------------------------------------------------------------------ session / controller

func open_session() -> void:
	session = HostSession.new()
	root.add_child(session)
	session.world = world
	session._attach_registered(1, TOKEN)
	expect(session.own_id == TOKEN.sha256_text().left(16), "Host Session delivers the public own_id")
	expect(not var_to_str(session.snapshot).contains(TOKEN), "Public snapshot carries no raw token")

func open_controller() -> void:
	controller = BP_CONTROLLER.new()
	controller.name = "BlueprintJourneyController"
	root.add_child(controller)
	controller.applied.connect(func(result):applied_events.append(result))
	controller.setup(session, library_path, scope)
	expect(controller.mode == "idle" and str(controller.library_error) == "" and str(controller.pending_error) == "", "Controller set up idle with a readable library")

func close_all(label: String) -> void:
	if controller != null and is_instance_valid(controller):
		controller.dispose()
		controller.free()
	controller = null
	if session != null and is_instance_valid(session):session.free()
	session = null
	expect(true, label + ": controller disposed and Session freed")

# ------------------------------------------------------------------ phases

func capture_and_save() -> void:
	mark("capture")
	var world_sha := FileAccess.get_sha256(world.save_path)
	open_session()
	open_controller()
	if failed:return
	expect((controller.entries as Array).is_empty() and not FileAccess.file_exists(library_path), "Fresh personal library is empty and unwritten")
	var area := Rect2i(original_site, Vector2i(5,5))
	var public_snap: Dictionary = (session.snapshot as Dictionary).duplicate(true)
	var direct: Dictionary = BP_DESIGN.capture(public_snap, session.own_id, area, BP_NAME, World.BUILD, World.NAMES)
	expect(controller.begin_capture() and controller.mode == "capture", "Controller enters capture mode")
	var got: Dictionary = controller.capture_area(area, BP_NAME)
	expect(got.get("ok") == true, "Capture own earned house through the controller: " + str(got.get("reason","")))
	if failed:return
	var design: Dictionary = controller.captured
	expect(direct.get("ok") == true and same_json(design, direct.blueprint), "Controller capture equals Design.capture of the public snapshot")
	expect((design.pieces as Array).size() == BP_PIECES and int(design.width) == 5 and int(design.height) == 5, "Captured 9 floors + 14 walls + window + door + bed in 5x5")
	expect(int(controller.auto_roofs_omitted) == INTERIOR.size(), "Nine automatic roofs omitted from the design")
	var kinds := {}
	for piece in design.pieces:kinds[str(piece.kind)] = int(kinds.get(str(piece.kind),0)) + 1
	expect(same_json(kinds, {"floor":9,"wall":14,"window":1,"door":1,"bed":1}), "Captured piece kinds %s" % JSON.stringify(kinds))
	var base: Dictionary = BP_DESIGN.base_cost(design, World.BUILD, World.NAMES)
	expect(base.get("ok") == true and ints(base.cost) == BP_BASE_COST, "Design base cost %s excludes automatic roofs" % JSON.stringify(base.get("cost",{})))
	var encoded := JSON.stringify(design)
	expect(not encoded.contains(TOKEN) and not encoded.contains(str(session.own_id)) and not encoded.contains("\"owner\"") and not encoded.contains("\"auto\""), "Design carries no owner/token/auto flag")
	expect(not FileAccess.file_exists(library_path), "Capture alone writes nothing")
	var saved: Dictionary = controller.save_capture(BP_NAME)
	expect(saved.get("ok") == true and BP_LIBRARY.valid_id(saved.get("id","")), "Saved to the personal library: " + str(saved.get("reason","")))
	library_id = str(saved.get("id",""))
	var disk: Dictionary = BP_LIBRARY.load_library(library_path, World.BUILD, World.NAMES)
	expect(disk.get("ok") == true and (disk.entries as Array).size() == 1 and str(disk.entries[0].id) == library_id and same_json(disk.entries[0].design.pieces, design.pieces), "Library on disk holds exactly the captured design")
	expect(FileAccess.get_sha256(world.save_path) == world_sha, "Capture/save never wrote the world save")
	close_all("after library save")
	mark_end("capture")

func reload_world(label: String) -> void:
	var path := world.save_path
	var expected_player: Dictionary = person().duplicate(true)
	var reopened := World.new()
	expect(reopened.load_world(path) and not reopened.recovered_from_backup and reopened.state.players.has(TOKEN), label + ": World reloads from the primary save")
	if failed:return
	reopened.add_player(TOKEN, str(expected_player.name))
	var again: Dictionary = reopened.state.players[TOKEN]
	for field in ["x","y","coins","inventory","receipts","builds"]:
		expect(same_json(again.get(field), expected_player.get(field)), label + ": %s preserved (no grant or teleport)" % field)
	expect(same_json(footprint_record(reopened, original_site), original_record), label + ": original house intact")
	world = reopened
	world_reloads += 1

func blueprint_site_work(origin: Vector2i) -> int:
	var work := site_work(origin)
	if work < 0:return -1
	var around := Rect2i(origin - Vector2i(1,1), Vector2i(7,8))
	if around.intersects(Rect2i(original_site - Vector2i(1,1), Vector2i(7,8))):return -1
	for y in range(around.position.y, around.end.y):
		for x in range(around.position.x, around.end.x):
			var tile_key := World.key(Vector2i(x,y))
			for layer in ["objects","ground","roofs"]:
				if world.state[layer].has(tile_key):return -1
	var stand: Vector2i = origin + BP_STAND
	if not world.is_land(stand) or world.water(stand) or world.protected(stand):return -1
	for layer in ["crops","forest"]:
		if world.state[layer].has(World.key(stand)):return -1
	var kind := world.resource(stand)
	if kind == "":
		if world.blocked(stand):return -1
	elif kind in ["tree","rock","grass"]:
		work += 1
	else:
		return -1
	return work

func find_blueprint_site() -> Vector2i:
	var center := here()
	for distance in range(0, BP_SITE_RING + 1):
		for y in range(center.y-distance, center.y+distance+1):
			for x in range(center.x-distance, center.x+distance+1):
				if maxi(absi(x-center.x), absi(y-center.y)) != distance:continue
				var candidate := Vector2i(x,y) - CENTER
				if blueprint_site_work(candidate) < 0:continue
				if not site_reachable(candidate):continue
				var stand: Vector2i = candidate + BP_STAND
				if world.resource(stand) in ["tree","rock"]:
					if route(stand).is_empty():continue
				elif route(stand, 1.0).is_empty():continue
				return candidate
	return NO_CELL

func prepare_second_site() -> void:
	mark("earn")
	placed = find_blueprint_site()
	if placed == NO_CELL:
		expect(false, "No reachable buildable 5x5 blueprint site with a legal west stand")
		return
	print("BLUEPRINT_SITE origin=%s stand=%s resources_to_clear=%d" % [placed, placed + BP_STAND, blueprint_site_work(placed)])
	var start := counts(person())
	for tile in cells_of(placed) + [placed + BP_STAND]:
		var kind := world.resource(tile)
		if kind == "":continue
		harvest_resource(tile, kind)
		cleared2 += 1
		if failed:return
	expect(blueprint_site_work(placed) == 0, "Blueprint site cleared by ordinary gathering")
	var need := expected_quote_cost()
	gather_item("wood", int(need.wood), ["tree"])
	gather_item("fiber", int(need.fiber), ["grass","tree"])
	gather_item("stone", int(need.get("stone",0)), ["rock"])
	if failed:return
	var after := counts(person())
	earned = {"wood":after.wood - start.wood, "fiber":after.fiber - start.fiber, "stone":after.stone - start.stone, "start":start, "after":after}
	expect(after.coins == start.coins, "No coins spent or granted while earning materials")
	go_to(placed + BP_STAND)
	if failed:return
	expect(here() == placed + BP_STAND, "Builder walked to the placement stand")
	expect(Vector2(person().x, person().y).distance_to(Vector2(placed) + Vector2(0.5,0.5)) <= World.BLUEPRINT_RANGE, "Origin within blueprint range of the builder")
	expect(blueprint_site_work(placed) == 0 and at_site(placed, func(): return roof_tally(world)).any == 0, "Placement site is empty before confirm")
	mark_end("earn")

func place_from_library() -> void:
	mark("place")
	open_session()
	open_controller()
	if failed:return
	expect((controller.entries as Array).size() == 1 and str(controller.entries[0].id) == library_id, "Reopened controller reloads the saved design from disk")
	expect((controller.pending as Dictionary).is_empty() and not FileAccess.file_exists(controller.pending_path()), "No pending record before placement")
	expect(controller.choose(library_id) and controller.mode == "placing", "Choose the saved design")
	if failed:return
	controller.move_origin(placed)
	expect(controller.origin == placed and int(controller.turns) == 0, "Placement origin moved onto the cleared site")
	expect(controller.pin_origin(placed) and controller.quote_waiting, "Pin requests an authoritative quote")
	await settle()
	var q: Dictionary = controller.quote
	var direct: Dictionary = world.quote_blueprint(TOKEN, controller.draft, placed, 0)
	quote_seen = q.duplicate(true)
	print("BLUEPRINT_QUOTE ok=%s cost=%s roof_add=%d pieces=%d undoable=%s message=%s" % [q.get("ok"), JSON.stringify(q.get("cost",{})), int(q.get("roof_add",0)), int(q.get("pieces",0)), q.get("undoable"), q.get("message","")])
	expect(not controller.quote_waiting and q.get("ok") == true and q.get("hash") == direct.get("hash"), "Controller holds the authoritative World quote: " + str(q.get("message","")))
	expect(ints(q.get("cost")) == expected_quote_cost() and ints(q.get("cost")) == EXPECTED_COST, "Quote cost %s = base %s + 9 automatic roofs" % [JSON.stringify(q.get("cost",{})), JSON.stringify(BP_BASE_COST)])
	expect(int(q.get("roof_add",0)) == INTERIOR.size() and int(q.get("roof_remove",-1)) == 0 and int(q.get("pieces",0)) == BP_PIECES and ints(q.get("mine_refund",{})).is_empty(), "Quote adds 9 roofs, 26 pieces, no refunds")
	if failed:return
	var before := counts(person())
	var inventory_before: Dictionary = bag().duplicate(true)
	var builds_before := int(person().get("builds",0))
	var receipts_before := blueprint_receipts(world).size()
	applied_events.clear()
	expect(controller.confirm() and controller.mode == "submitting", "Confirm through the controller")
	expect(FileAccess.file_exists(controller.pending_path()), "Pending record written before the World applies")
	await settle()
	expect(applied_events.size() == 1 and (applied_events[0] as Dictionary).get("ok") == true, "Controller reports one successful application")
	if failed:return
	var result: Dictionary = applied_events[0]
	expect(int(result.get("pieces",0)) == BP_PIECES and int(result.get("roof_add",0)) == INTERIOR.size() and ints(result.get("cost")) == ints(q.cost) and result.get("hash") == q.hash, "Applied result matches the confirmed quote")
	expect(controller.mode == "idle" and (controller.pending as Dictionary).is_empty() and not FileAccess.file_exists(controller.pending_path()), "Pending cleared on success")
	var after := counts(person())
	var spent := {"wood":before.wood - after.wood, "fiber":before.fiber - after.fiber, "stone":before.stone - after.stone}
	expect(ints(spent) == ints(q.cost) and after.coins == before.coins, "Inventory debited exactly the quoted materials %s" % JSON.stringify(spent))
	var expected_inventory := inventory_before.duplicate(true)
	for item in q.cost:expected_inventory[item] = int(expected_inventory.get(item,0)) - int(q.cost[item])
	expect(same_inventory(bag(), expected_inventory), "No other inventory change")
	expect(int(person().get("builds",0)) == builds_before + BP_PIECES, "Exactly 26 builds credited")
	var receipts := blueprint_receipts(world)
	expect(receipts.size() == receipts_before + 1, "Exactly one blueprint receipt stored")
	if receipts.size() == 1:receipt_nonce = receipts[0].trim_prefix("blueprint:")
	verify_layouts(world, "after confirm")
	# A second confirm without a new quote must not build again.
	expect(not controller.confirm() and not controller.retry_pending(), "No second construction without a fresh quote")
	await settle()
	expect(applied_events.size() == 1 and blueprint_receipts(world).size() == receipts_before + 1 and counts(person()) == after, "No duplicate charge or receipt")
	close_all("after placement")
	mark_end("place")

func verify_layouts(target, label: String) -> void:
	var keep = world
	world = target
	expect(at_site(placed, func(): return layout_owned(world)), label + ": placed floors/walls/window/door/bed and 9 automatic roofs owned by the builder")
	var tally: Dictionary = at_site(placed, func(): return roof_tally(world))
	expect(tally.any == INTERIOR.size() and tally.auto == INTERIOR.size(), label + ": placed house has exactly 9 automatic roofs (%s)" % JSON.stringify(tally))
	at_site(placed, func(): assert_complete(inspect_home(spot(CENTER), label + " placed"), label + ": placed home"))
	expect(same_json(footprint_record(world, original_site), original_record), label + ": original house unchanged")
	expect(at_site(original_site, func(): return layout_owned(world)), label + ": original house still owned and auto-roofed")
	at_site(original_site, func(): assert_complete(inspect_home(spot(CENTER), label + " original"), label + ": original home"))
	var owned := owned_tally(world)
	expect(int(owned.get("floor",0)) == 18 and int(owned.get("wall",0)) == 28 and int(owned.get("window",0)) == 2 and int(owned.get("door",0)) == 2 and int(owned.get("bed",0)) == 2 and int(owned.get("auto_roof",0)) == 18 and not owned.has("roof"), label + ": exactly two houses exist, no duplicate (%s)" % JSON.stringify(owned))
	world = keep

func verify_persistence() -> void:
	mark("persist")
	var expected_player: Dictionary = person().duplicate(true)
	reload_world("after placement")
	if failed:return
	verify_layouts(world, "after reload")
	var receipts := blueprint_receipts(world)
	expect(receipts.size() == 1 and receipt_nonce != "" and receipts[0] == "blueprint:" + receipt_nonce, "Single blueprint receipt persisted")
	expect(world.blueprint_receipt(TOKEN, receipt_nonce).get("ok") == true, "Receipt readable after reload")
	expect(same_json(person().inventory, expected_player.inventory), "Post-construction inventory persisted")
	open_session()
	open_controller()
	if failed:return
	expect((controller.entries as Array).size() == 1 and str(controller.entries[0].id) == library_id, "Library still holds exactly one design after reload")
	expect(controller.mode == "idle" and (controller.pending as Dictionary).is_empty() and not FileAccess.file_exists(controller.pending_path()), "No pending construction after reload")
	expect(not controller.retry_pending(), "Nothing to retry after reload")
	await settle()
	expect(owned_tally(world).get("bed",0) == 2 and blueprint_receipts(world).size() == 1, "Reopening never rebuilds")
	close_all("after persistence check")
	mark_end("persist")

func keep_evidence(path: String) -> void:
	if output_dir.is_empty():return
	var save_out := output_dir.path_join(REPORT_FILES[0])
	var library_out := output_dir.path_join(REPORT_FILES[1])
	var report_out := output_dir.path_join(REPORT_FILES[2])
	expect(DirAccess.copy_absolute(path, save_out) == OK, "Kept completion save")
	expect(DirAccess.copy_absolute(library_path, library_out) == OK, "Kept personal library")
	var report := {
		"journey":"test_blueprint_earned_journey.gd",
		"provenance":{"source":"fresh World created by this run; house earned via world.act/move_player from starter supplies and natural gathering",
			"artifact_inputs":[], "seeded_resources":false, "direct_state_edits":false, "teleports":false, "unlock_edits":false,
			"fixtures":["HostSession._ready override (no profile, no physics tick)", "Session._attach_registered(1, token) after scripted movement", "scripted World API movement/actions (not human input)"]},
		"source_site":[original_site.x, original_site.y], "placed_origin":[placed.x, placed.y],
		"actions":actions, "walk_tiles":walking, "phase_actions":phase_actions, "phase_walk":phase_walk,
		"site_resources_cleared":cleared, "second_site_cleared":cleared2, "gather_hits":gather_hits, "inspections":inspections,
		"earned_for_placement":earned, "quote":{"cost":ints(quote_seen.get("cost",{})), "roof_add":int(quote_seen.get("roof_add",0)), "pieces":int(quote_seen.get("pieces",0)), "hash":str(quote_seen.get("hash",""))},
		"base_cost":BP_BASE_COST, "world_steps":0, "world_seconds":float(world.state.time), "world_reloads":world_reloads,
		"save_sha256":FileAccess.get_sha256(save_out), "library_sha256":FileAccess.get_sha256(library_out),
		"checks":checks, "failures":failures}
	var file := FileAccess.open(report_out, FileAccess.WRITE)
	expect(file != null, "Open evidence report")
	if file == null:return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("BLUEPRINT_EARNED_EVIDENCE save=%s sha256=%s library_sha256=%s report=%s" % [save_out, report.save_sha256, report.library_sha256, report_out])
