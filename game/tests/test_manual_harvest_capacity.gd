extends SceneTree

## T018 manual harvest capacity regression (real World, no mocks).
##
## Disclosed fixture presets (written directly into world.state, not earned in play):
##   - player.inventory.<crop> counts near the 1,000,000,000 SaveSchema cap
##     (999999998 / 999999999 / 1000000000).
##   - player.harvests set to 999999999 / 1000000000.
##   - player.inventory harvester=1, charcoal=5 (merged by fresh()).
##   - Ripe crops written straight into state.crops via plant() (growth=time, wet=true).
##   - A second player "guest" is added for the shared-plot case; crop
##     harvest_access="island" is written directly on the owner's plot.
## chapter_one is left at its defaults (shipped=false) so CHAPTER_ONE.record_harvest
## is actively tracking, and rejections must leave chapter_one.harvests untouched.
##
## Receipt note: World.act stores player.receipts[request_id] only when the result
## is ok (rejected results return before the receipt is written), so case 6 retries
## a rejected request with the SAME request id after making room.

const World = preload("res://scripts/world.gd")
const Schema = preload("res://scripts/save_schema.gd")
const CENTER := Vector2i(42, 36)
const CAP := 1000000000
var checks := 0
var failures := 0
var sequence := 0

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("FAIL " + message)

func fresh(center: Vector2i = CENTER):
	var world = World.new()
	world.add_player("farmer", "農夫")
	var player: Dictionary = world.state.players.farmer
	player.x = center.x + 0.5
	player.y = center.y + 0.5
	player.inventory.merge({"harvester": 1, "charcoal": 5}, true)
	return world

func plant(world, cell: Vector2i, kind: String, owner: String = "farmer") -> Dictionary:
	var recipe: Dictionary = World.CROPS[kind]
	var crop := {"kind": kind, "owner": owner, "growth": recipe.time, "wet": true, "remaining": recipe.get("cycles", 1)}
	world.state.crops[World.key(cell)] = crop
	return crop

func person(world, token: String = "farmer") -> Dictionary:
	var players = world.state.get("players", {})
	if not players is Dictionary:
		return {}
	var found = players.get(token, {})
	return found if found is Dictionary else {}

func inv(world, token: String = "farmer") -> Dictionary:
	var bag = person(world, token).get("inventory", {})
	return bag if bag is Dictionary else {}

func plot(world, cell: Vector2i) -> Dictionary:
	var found = world.state.crops.get(World.key(cell), {})
	return found if found is Dictionary else {}

func count(world, item: String, token: String = "farmer") -> int:
	return int(inv(world, token).get(item, 0))

func chapter(world) -> Dictionary:
	var found = world.state.get("chapter_one", {})
	return found if found is Dictionary else {}

func act(world, action: String = "harvest", cell: Vector2i = CENTER, token: String = "farmer", id: String = "") -> Dictionary:
	sequence += 1
	var request := "cap-%d" % sequence if id.is_empty() else id
	var result = world.act(token, request, action, cell)
	return result if result is Dictionary else {"ok": false, "message": ""}

func valid(state: Dictionary) -> bool:
	return Schema.validate(state, World.CROPS, World.BUILD, World.RECIPES, World.SIZE, World.TREE_TIME)

## Runs one request that must be rejected and proves the complete canonical
## state is unchanged, with explicit field checks for the harvest side effects.
func rejected_unchanged(world, label: String, action: String, cells: Array, token: String = "farmer", id: String = "", needle: String = "") -> Dictionary:
	var before: Dictionary = world.state.duplicate(true)
	var before_text := var_to_str(world.state)
	var before_player: Dictionary = person(world, token).duplicate(true)
	var before_plots: Array = []
	for c in cells:
		before_plots.append(plot(world, c).duplicate(true))
	var request := id
	if request.is_empty():
		sequence += 1
		request = "cap-%d" % sequence
	var raw = world.act(token, request, action, cells[0])
	var result: Dictionary = raw if raw is Dictionary else {"ok": true, "message": ""}
	var message := str(result.get("message", ""))
	expect(not bool(result.get("ok", true)), label + ": request rejected")
	expect(message.contains("已達上限"), label + ": message names the cap (got '" + message + "')")
	if not needle.is_empty():
		expect(message.contains(needle), label + ": message mentions " + needle + " (got '" + message + "')")
	expect(world.state == before, label + ": deep state equality")
	expect(var_to_str(world.state) == before_text, label + ": canonical var_to_str equality")
	for index in cells.size():
		var now := plot(world, cells[index])
		var was: Dictionary = before_plots[index]
		for field in ["kind", "owner", "growth", "wet", "remaining"]:
			expect(str(now.get(field, "<missing>")) == str(was.get(field, "<missing>")), label + ": plot %s %s unchanged" % [World.key(cells[index]), field])
	var player := person(world, token)
	expect(player.get("inventory", {}) == before_player.get("inventory", {}), label + ": inventory unchanged")
	expect(player.get("collection", {}) == before_player.get("collection", {}), label + ": collection unchanged")
	expect(int(player.get("harvests", -1)) == int(before_player.get("harvests", -2)), label + ": player.harvests unchanged")
	expect(player.get("crops_discoveries", {}) == before_player.get("crops_discoveries", {}), label + ": player crop discoveries unchanged")
	expect(player.get("last_harvest", {}) == before_player.get("last_harvest", {}), label + ": last_harvest unchanged")
	expect(chapter(world) == before.get("chapter_one", {}), label + ": chapter_one harvests unchanged")
	expect(world.state.get("island_crops_discoveries", {}) == before.get("island_crops_discoveries", {}), label + ": island crop discoveries unchanged")
	var receipts = player.get("receipts", {})
	expect(receipts is Dictionary and not receipts.has(request), label + ": rejection stored no receipt")
	return result

func _initialize() -> void:
	expect(int(World.CROPS.radish.yield) == 1 and int(World.CROPS.wheat.yield) == 2, "catalog yields radish 1 / wheat 2")
	expect(int(World.CROPS.tomato.yield) == 2 and int(World.CROPS.tomato.get("cycles", 1)) == 3, "catalog tomato yield 2 with three cycles")

	# 1. Below limit: radish yield 1 from CAP-2 lands at CAP-1.
	var world = fresh()
	expect(chapter(world).get("shipped", true) == false, "first-session chapter tracking is active")
	plant(world, CENTER, "radish")
	inv(world).radish = CAP - 2
	var result := act(world)
	expect(bool(result.get("ok", false)), "below-limit radish harvest succeeds")
	expect(count(world, "radish") == CAP - 1, "below-limit radish lands at 999999999")
	expect(plot(world, CENTER).get("kind", "x") == "", "below-limit radish plot cleared")
	expect(int(person(world).get("harvests", 0)) == 1, "below-limit harvest counted once")
	var tracked = chapter(world).get("harvests", {}).get("farmer", {})
	expect(tracked is Dictionary and int(tracked.get("radish", 0)) == 1, "chapter one recorded the radish harvest")

	# 2. Exact limit: wheat yield 2 from CAP-2 lands exactly on CAP, then save/load.
	world = fresh()
	plant(world, CENTER, "wheat")
	inv(world).wheat = CAP - 2
	world.save_path = "user://manual-harvest-capacity-%d.json" % Time.get_ticks_usec()
	result = act(world)
	expect(bool(result.get("ok", false)), "exact-limit wheat harvest succeeds")
	expect(count(world, "wheat") == CAP, "exact-limit wheat equals 1000000000")
	expect(plot(world, CENTER).get("kind", "x") == "", "exact-limit wheat plot cleared")
	# Validate the exact form World.save() persists (JSON.stringify(state)). The raw
	# in-memory Dictionary is not a SaveSchema input: a DIAG run showed it fails
	# validate() even with wheat lowered to 5, while its JSON round trip passes.
	var persisted = JSON.parse_string(JSON.stringify(world.state))
	expect(persisted is Dictionary and int(persisted.players.farmer.inventory.wheat) == CAP and valid(persisted), "state at exact cap passes SaveSchema in its saved JSON form")
	expect(FileAccess.file_exists(world.save_path), "exact-limit harvest saved to disk")
	var loaded = World.new()
	var loaded_ok: bool = loaded.load_world(world.save_path)
	expect(loaded_ok, "exact-cap save reloads")
	if loaded_ok:
		expect(count(loaded, "wheat") == CAP, "reloaded wheat stays at 1000000000")
		expect(plot(loaded, CENTER).get("kind", "x") == "", "reloaded wheat plot is cleared")
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(world.save_path + suffix):
			DirAccess.remove_absolute(world.save_path + suffix)

	# 3. Over limit: wheat at CAP-1 (yield 2) and radish at CAP (yield 1).
	world = fresh()
	plant(world, CENTER, "wheat")
	inv(world).wheat = CAP - 1
	rejected_unchanged(world, "wheat over cap", "harvest", [CENTER], "farmer", "cap-retry", str(World.CROPS.wheat.name))
	# 6. Same request id retried after making room must succeed (no receipt was stored).
	inv(world).wheat = CAP - 2
	result = act(world, "harvest", CENTER, "farmer", "cap-retry")
	expect(bool(result.get("ok", false)), "same request id succeeds after making room")
	expect(count(world, "wheat") == CAP and plot(world, CENTER).get("kind", "x") == "", "retry pays wheat up to the cap and clears plot")
	var receipts = person(world).get("receipts", {})
	expect(receipts is Dictionary and receipts.has("cap-retry"), "successful retry stores the receipt")

	world = fresh()
	plant(world, CENTER, "radish")
	inv(world).radish = CAP
	rejected_unchanged(world, "radish at cap", "harvest", [CENTER], "farmer", "", str(World.CROPS.radish.name))

	# 4. Regrowing tomato over limit keeps remaining cycles and growth.
	world = fresh()
	plant(world, CENTER, "tomato")
	inv(world).tomato = CAP - 1
	rejected_unchanged(world, "tomato over cap", "harvest", [CENTER])
	expect(int(plot(world, CENTER).get("remaining", 0)) == 3, "tomato remaining cycles untouched")
	expect(float(plot(world, CENTER).get("growth", 0.0)) == float(World.CROPS.tomato.time), "tomato growth untouched")

	# 5. Harvest record at cap blocks even with bag room; one below reaches the cap.
	world = fresh()
	plant(world, CENTER, "radish")
	person(world).harvests = CAP
	rejected_unchanged(world, "harvest record at cap", "harvest", [CENTER])
	person(world).harvests = CAP - 1
	result = act(world)
	expect(bool(result.get("ok", false)), "harvest record one below cap succeeds")
	expect(int(person(world).get("harvests", 0)) == CAP, "harvest record lands exactly on the cap")
	expect(count(world, "radish") == 1, "radish paid when record has room")

	# 7. harvest_area regression: aggregate preflight is all-or-nothing.
	var second := Vector2i(43, 36)
	world = fresh()
	plant(world, CENTER, "radish")
	plant(world, second, "radish")
	inv(world).radish = CAP - 1
	rejected_unchanged(world, "harvest_area over cap", "harvest_area", [CENTER, second])
	expect(count(world, "charcoal") == 5, "harvest_area rejection keeps charcoal")
	inv(world).radish = CAP - 2
	result = act(world, "harvest_area", CENTER)
	expect(bool(result.get("ok", false)), "harvest_area reaching the cap exactly succeeds")
	expect(count(world, "radish") == CAP, "harvest_area radish lands on 1000000000")
	expect(count(world, "charcoal") == 4, "harvest_area charges one charcoal")
	expect(plot(world, CENTER).get("kind", "x") == "" and plot(world, second).get("kind", "x") == "", "harvest_area cleared both plots")

	# 8. Shared island-access crop: guest at cap is rejected, owner's crop untouched.
	world = fresh()
	world.add_player("guest", "客人")
	var guest := person(world, "guest")
	expect(not guest.is_empty(), "guest player joined")
	guest.x = CENTER.x + 0.5
	guest.y = CENTER.y + 0.5
	var shared := plant(world, CENTER, "wheat", "farmer")
	shared.harvest_access = "island"
	inv(world, "guest").wheat = CAP - 1
	var owner_bag: Dictionary = inv(world, "farmer").duplicate(true)
	rejected_unchanged(world, "guest over cap on shared plot", "harvest", [CENTER], "guest")
	expect(plot(world, CENTER).get("kind", "") == "wheat" and plot(world, CENTER).get("owner", "") == "farmer", "owner's shared wheat untouched")
	expect(inv(world, "farmer") == owner_bag, "owner inventory untouched by guest rejection")
	inv(world, "guest").wheat = CAP - 2
	result = act(world, "harvest", CENTER, "guest")
	expect(bool(result.get("ok", false)), "guest with room harvests the shared plot")
	expect(count(world, "wheat", "guest") == CAP, "guest wheat lands exactly on the cap")
	expect(inv(world, "farmer") == owner_bag, "owner inventory still untouched after guest harvest")

	print("MANUAL_HARVEST_CAPACITY checks=%d failures=%d" % [checks, failures])
	quit(int(failures > 0))
