extends SceneTree

const World = preload("res://scripts/world.gd")
const Schema = preload("res://scripts/save_schema.gd")
const CENTER := Vector2i(42, 36)
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

func act(world, center: Vector2i = CENTER, action: String = "harvest_area", id: String = "") -> Dictionary:
	sequence += 1
	return world.act("farmer", "harvester-%d" % sequence if id.is_empty() else id, action, center)

func valid(state: Dictionary) -> bool:
	return Schema.validate(state, World.CROPS, World.BUILD, World.RECIPES, World.SIZE, World.TREE_TIME)

func denied_unchanged(world, message: String, center: Vector2i = CENTER) -> void:
	var before: Dictionary = world.state.duplicate(true)
	expect(not act(world, center).ok and world.state == before, message)

func _initialize() -> void:
	var world = fresh()
	var player: Dictionary = world.state.players.farmer
	var yields := {"radish": 1, "lettuce": 1, "wheat": 2, "carrot": 1, "potato": 2, "tomato": 2}
	var positions := [Vector2i(41,35), Vector2i(42,35), Vector2i(43,35), Vector2i(41,36), Vector2i(42,36), Vector2i(43,36)]
	for index in positions.size():
		plant(world, positions[index], yields.keys()[index])
	var foreign := plant(world, Vector2i(41,37), "radish", "other")
	var unripe := plant(world, Vector2i(42,37), "wheat")
	unripe.growth = 1.0
	world.state.crops["43,37"] = {"kind": "", "owner": "farmer", "growth": 0.0, "wet": false, "remaining": 0}
	var plan: Dictionary = World.HARVESTER.plan(world, "farmer", CENTER)
	expect(plan.yields == yields and plan.cells.size() == 6 and plan.skipped.size() == 3, "mixed preview aggregates six known yields")
	expect(act(world, CENTER, "harvest_area", "retry").ok, "mixed harvest succeeds")
	for item in yields:
		expect(player.inventory[item] == yields[item] and player.collection.crops[item], "payout and discovery for " + item)
	expect(player.harvests == 6 and player.inventory.charcoal == 4, "six plots charge one charcoal and count six harvests")
	expect(not world.can_harvest_plot(foreign,"farmer",true),"Existing plots remain private to other harvesters")
	foreign.harvest_access="friend"
	foreign.harvest_friend="farmer"
	expect(world.can_harvest_plot(foreign,"farmer",true) and not world.can_harvest_plot(foreign,"guest",true),"Only the designated guest gets machine access")
	foreign.harvest_access="island"
	foreign.erase("harvest_friend")
	expect(world.can_harvest_plot(foreign,"farmer",true),"Explicit island access allows a guest harvester")
	foreign.erase("harvest_access")
	expect(foreign.kind == "radish" and unripe.kind == "wheat" and unripe.growth == 1.0, "foreign and unripe plots preserved")
	for index in range(5):
		var plot: Dictionary = world.state.crops[World.key(positions[index])]
		expect(plot.kind == "" and plot.remaining == 0 and not plot.wet and plot.growth == 0, "single-harvest crop returns to dry soil")
	var after: Dictionary = world.state.duplicate(true)
	expect(act(world, CENTER, "harvest_area", "retry").ok and world.state == after, "same receipt cannot charge or harvest twice")
	denied_unchanged(world, "cooldown rejects a distinct request")
	var tomato: Dictionary = world.state.crops["43,36"]
	expect(tomato.kind == "tomato" and tomato.remaining == 2 and not tomato.wet, "first tomato harvest preserves two remaining")
	for remaining in [1, 0]:
		world.step(1.0, true)
		tomato.growth = World.CROPS.tomato.time
		tomato.wet = true
		expect(act(world).ok and tomato.remaining == remaining and not tomato.wet and tomato.growth == (World.regrow_start("tomato") if remaining > 0 else 0.0), "tomato regrowth restarts at regrow_start after harvest")
	expect(tomato.kind == "" and player.inventory.tomato == 6 and player.harvests == 8, "three tomato harvests yield six fruit")
	world.step(1.0, true)
	denied_unchanged(world, "no eligible plants costs nothing")

	world = fresh()
	for index in positions.size():
		plant(world, positions[index], "radish")
	world.state.objects["41,35"] = {"type": "chair"}
	world.state.ground["42,35"] = {"type": "path"}
	world.state.roofs["43,35"] = {"type": "roof"}
	world.state.forest["41,36"] = {"owner": "farmer", "mature": false}
	plan = World.HARVESTER.plan(world, "farmer", CENTER)
	expect(plan.cells == ["42,36", "43,36"], "objects, paving, roof and trees exclude otherwise ripe plots")
	denied_unchanged(world, "distant center costs nothing", Vector2i(50,36))
	world.state.players.farmer.y = 39.5
	plant(world, Vector2i(42,35), "radish")
	world.state.ground.clear()
	plan = World.HARVESTER.plan(world, "farmer", CENTER)
	expect(plan.skipped["42,35"] == "距離太遠" and plan.cells.has("42,36"), "reach checked for every plot")
	for center in [Vector2i(40,30), Vector2i(55,36)]:
		world = fresh(center)
		plant(world, center, "radish")
		denied_unchanged(world, "public and river plots protected", center)
	for reason in ["harvester", "charcoal", "inventory limit", "harvest limit"]:
		world = fresh()
		plant(world, CENTER, "radish")
		plant(world, Vector2i(43,36), "radish")
		player = world.state.players.farmer
		match reason:
			"inventory limit": player.inventory.radish = 999999999
			"harvest limit": player.harvests = 999999999
			_: player.inventory[reason] = 0
		denied_unchanged(world, reason + " cannot partially mutate")

	world = fresh()
	plant(world, CENTER, "wheat")
	world.save_path = "user://missing-harvester-%d/world.json" % Time.get_ticks_usec()
	denied_unchanged(world, "save failure restores crops, fuel, discoveries and receipt")
	world.save_path = "user://harvester-%d.json" % Time.get_ticks_usec()
	expect(act(world).ok, "save succeeds after storage recovers")
	var loaded = World.new()
	expect(loaded.load_world(world.save_path) and loaded.state.players.farmer.last_harvest == world.state.players.farmer.last_harvest, "reload preserves harvest event")
	expect(loaded.state.players.farmer.inventory.wheat == 2 and loaded.state.crops["42,36"].kind == "", "reload preserves reward and cleared crop")
	for variant in ["future", "duplicate", "far", "type"]:
		after = world.state.duplicate(true)
		var event: Dictionary = after.players.farmer.last_harvest
		match variant:
			"future": event.at = 1
			"duplicate": event.cells = ["42,36", "42,36"]
			"far": event.cells = ["50,36"]
			"type": event.x = "42"
		expect(not valid(after), "schema rejects malformed event " + variant)
	after = world.state.duplicate(true)
	after.players.farmer.erase("last_harvest")
	expect(valid(after), "legacy save without visual event is legal")
	DirAccess.remove_absolute(world.save_path)
	world = fresh()
	var single := plant(world, CENTER, "wheat", "other")
	player = world.state.players.farmer
	expect(act(world, CENTER, "harvest").ok and single.kind == "" and player.inventory.wheat == 2, "legacy manual harvest still works on shared field")
	expect(player.inventory.charcoal == 5 and player.harvests == 1 and player.collection.crops.wheat, "manual harvest still records one plot without fuel")
	expect(World.farming_level(player)==1,"Starter farming level")
	player.harvests=9
	plant(world,CENTER,"wheat")
	expect(act(world,CENTER,"harvest").ok and World.farming_level(player)==3,"Actual manual harvest grants the point for level three")
	expect(World.farming_level({"harvests":1000000000})==10,"Farming level caps at ten")
	world=fresh()
	var shared:=plant(world,CENTER,"wheat","other")
	shared.harvest_access="friend"
	shared.harvest_friend="farmer"
	var permitted:Dictionary=World.HARVESTER.plan(world,"farmer",CENTER)
	expect(permitted.cells==[World.key(CENTER)],"Preview includes designated shared plot")
	expect(act(world,CENTER,"harvest_area").ok and shared.kind=="","Machine harvests the explicitly shared crop")
	check_hand_harvest()
	print("HARVESTER_TESTS checks=%d failures=%d" % [checks, failures])
	quit(int(failures > 0))

func check_hand_harvest()->void:
	var world:World=fresh()
	var player:Dictionary=world.state.players.farmer
	player.inventory.copper_sickle=1
	player.crop_care=World.CROP_CATALOG.CARE_TARGET
	var shared:=plant(world,CENTER,"tomato","other")
	shared.harvest_access="friend"
	shared.harvest_friend="farmer"
	var own:=plant(world,CENTER+Vector2i.LEFT,"radish")
	var private_plot:=plant(world,CENTER+Vector2i.RIGHT,"radish","other")
	world.state.roofs[World.key(CENTER)]={"type":World.GREENHOUSE_GLASS.LEGACY_ROOF,"owner":"other"}
	player.inventory.tomato=999999999
	var before:Dictionary=world.state.duplicate(true)
	expect(not world.act("farmer","hand-full","harvest",CENTER,"spread").ok and world.state==before,"Full produce stack rejects the entire hand harvest")
	player.inventory.tomato=0
	var plan:=world.hand_harvest_plan("farmer",CENTER,"copper_sickle")
	expect(plan.cells==[World.key(CENTER+Vector2i.LEFT),World.key(CENTER)] and plan.skipped.get(World.key(CENTER+Vector2i.RIGHT))=="無採收權限","Hand harvest honors shared permission under glass and skips private crops")
	expect(world.act("farmer","hand-ripe","harvest",CENTER,"spread").ok and own.kind.is_empty() and private_plot.kind=="radish","The authorized hand harvest matches the preview")
	expect(shared.remaining==2 and not shared.wet and int(player.inventory.quality_radish)==1 and int(player.crop_care)==0 and player.inventory.charcoal==5,"Regrowth and the one-shot quality guarantee match existing harvest rules")
