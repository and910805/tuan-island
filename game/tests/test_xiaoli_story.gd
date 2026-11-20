extends SceneTree

const World = preload("res://scripts/world.gd")
const Village = preload("res://scripts/village.gd")
const Stall := Vector2i(43, 29)
var world := World.new()
var checks := 0
var failures := 0
var serial := 0

func expect(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL " + description)

func submit(stage: int, who: String = "alice", request: String = "") -> Dictionary:
	serial += 1
	return world.act(who, request if not request.is_empty() else "xiaoli-%d" % serial,
		"quest", Stall, "xiaoli:%d" % stage)

func write_fixture(path: String, data: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))

func _initialize() -> void:
	world.add_player("alice", "甲")
	world.add_player("bob", "乙")
	for player in world.state.players.values():
		player.x = 43.5
		player.y = 30.5
	var alice: Dictionary = world.state.players.alice
	var bob: Dictionary = world.state.players.bob
	expect(Village.NPCS.xiaoli.cell == Stall, "Xiaoli shares the seed stall cell")
	var wallet: int = alice.coins
	var first_seeds: int = alice.inventory.lettuce_seed
	alice.inventory.radish = 1
	expect(not submit(0).ok and alice.inventory.radish == 1 and alice.coins == wallet, "buying or receiving a radish cannot satisfy personal harvest")
	alice.harvests = 1
	alice.inventory.radish = 0
	expect(not submit(0).ok and alice.stories.xiaoli == 0, "first quest needs a radish as well as a personal harvest")
	alice.inventory.radish = 1
	expect(submit(0, "alice", "first-quest").ok and alice.stories.xiaoli == 1, "first quest completes")
	expect(alice.inventory.radish == 0 and alice.coins == wallet + 35 and alice.inventory.lettuce_seed == first_seeds + 2, "first quest pays and charges exact items")
	expect(submit(0, "alice", "first-quest").ok and alice.coins == wallet + 35, "request replay returns original result without reward")
	expect(not submit(0).ok, "stale stage cannot claim again")
	expect(not submit(1, "bob").ok and bob.stories.xiaoli == 0, "one player cannot skip using another player's story")
	alice.inventory.lettuce = 2
	alice.inventory.wheat = 1
	expect(not submit(1).ok and alice.inventory.lettuce == 2, "bridge required")
	world.state.board = true
	expect(not submit(1).ok and alice.inventory.lettuce == 2 and alice.inventory.wheat == 1, "partial materials are never deducted")
	alice.inventory.wheat = 2
	expect(submit(1).ok and alice.inventory.lettuce == 0 and alice.inventory.wheat == 0, "second quest consumes both requested quantities")
	expect(alice.coins == wallet + 105 and alice.inventory.carrot_seed == 2, "second quest pays exact rewards")
	alice.inventory.bread = 1
	expect(not submit(2).ok and alice.inventory.bread == 1, "third quest requires salad and bread atomically")
	alice.inventory.salad = 1
	expect(submit(2).ok and alice.inventory.bread == 0 and alice.inventory.salad == 0 and alice.inventory.tomato_seed == 2, "third quest consumes foods and awards tomato seeds")
	alice.trees_planted = 2
	expect(not submit(3).ok, "final quest needs picnic")
	world.state.picnic = true
	alice.trees_planted = 1
	expect(not submit(3).ok, "final quest needs two personal trees")
	alice.trees_planted = 2
	var saplings: int = alice.inventory.sapling
	expect(submit(3).ok and alice.stories.xiaoli == 4 and alice.coins == wallet + 295 and alice.inventory.sapling == saplings + 1, "final quest pays exact rewards")
	expect(not submit(4).ok and bob.stories.xiaoli == 0, "completed chain cannot pay again or affect a second player")
	bob.harvests = 1
	bob.inventory.radish = 1
	expect(submit(0, "bob").ok and bob.stories.xiaoli == 1 and alice.stories.xiaoli == 4, "second player advances independently")

	var path := "user://xiaoli-story-%d.json" % Time.get_ticks_usec()
	world.save_path = path
	expect(world.save(), "world saves Xiaoli progress")
	var restored := World.new()
	expect(restored.load_world(path) and restored.state.players.alice.stories.xiaoli == 4
		and restored.state.players.bob.stories.xiaoli == 1, "reload preserves both stages")
	var old: Dictionary = world.state.duplicate(true)
	old.version = 7;old.erase("public_kitchen")
	# Historical fixture predates the v25 flower chapter.
	old.erase("flower_nursery")
	old.regions.erase("tianwei")
	old.erase("salt_pan")
	old.regions.erase("beimen")
	for region in World.REGIONS.ANGLING_RESERVES:old.regions.erase(region)
	for region in World.TRANSIT.LOCAL:old.regions.erase(region)
	old.regions.erase(World.PARTY_CART.REGION) # v7 predates the cart gallery
	old.erase("bobo_workshop")
	old.players.alice.stories = {"aru": 2, "milu": 3}
	write_fixture(path, old)
	expect(restored.load_world(path) and restored.state.players.alice.stories == {"aru": 2, "milu": 3, "xiaoli": 0, "bobo": 0},
		"legacy save preserves two existing stages and initializes Xiaoli")
	old.players.alice.stories.xiaoli = 5
	write_fixture(path, old)
	expect(not restored.load_world(path), "out-of-range Xiaoli stage rejected")
	old.players.alice.stories.xiaoli = 0
	old.players.alice.stories.unknown = 0
	write_fixture(path, old)
	expect(not restored.load_world(path), "unknown resident stage rejected")
	DirAccess.remove_absolute(path)
	print("XIAOLI_STORY_TESTS checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
