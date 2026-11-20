extends SceneTree
## Standalone regression suite for res://scripts/livestock.gd and its World
## integration: timer boundaries, the seven-slot feed/ready capacity, collector
## box (chest) behaviour, independent multi-animal records and atomic rollback
## when the world cannot be saved.
const World = preload("res://scripts/world.gd")
const L = preload("res://scripts/livestock.gd")
const CAP := 1000000000
var checks := 0
var failures := 0
var _cleanup: Array[String] = []

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func finish() -> void:
	for file in _cleanup:
		for suffix in ["", ".bak", ".tmp"]:
			if FileAccess.file_exists(file + suffix):DirAccess.remove_absolute(file + suffix)
	print("LIVESTOCK_CORE_TESTS checks=%d failures=%d" % [checks, failures])
	quit(int(failures > 0 or checks == 0))

static func rec(feed: int, ready: int, next: float) -> Dictionary:
	return {"feed":feed, "ready":ready, "next":next}

## Type-tolerant compare (JSON reload turns ints into floats).
static func same(animal, feed: int, ready: int, next: float) -> bool:
	if not animal is Dictionary:return false
	return int(animal.get("feed", -99)) == feed and int(animal.get("ready", -99)) == ready and float(animal.get("next", -99.0)) == next

static func animal_of(world, id: String) -> Dictionary:
	return world.state.livestock.get(id, {})

static func temp_path(tag: String) -> String:
	return OS.get_environment("TEMP").path_join("livestock-core-%s-%s.json" % [tag, Crypto.new().generate_random_bytes(8).hex_encode()])

func _initialize() -> void:
	var day := L.DAY
	expect(L.LIMIT == 7, "Livestock capacity is seven slots")
	expect(L.ANIMALS.has("cow") and int(L.ANIMALS.cow.days) == 1 and L.ANIMALS.cow.item == "milk", "Cow produces milk every day")
	expect(L.ANIMALS.has("sheep") and int(L.ANIMALS.sheep.days) == 2 and L.ANIMALS.sheep.item == "wool", "Sheep produces wool every two days")
	if failures > 0:
		finish()
		return
	test_timer_boundaries(day)
	test_bond_bonus(day)
	test_quality_routes(day)
	test_seven_slot_capacity(day)
	test_full_box(day)
	test_full_equipment(day)
	test_pen_construction()
	test_multiple_animals(day)
	test_world_and_atomic_save(day)
	test_ranch_income()
	test_pen_collector()
	test_pen_collector_rejoin()
	test_pen_collector_chicken()
	test_pen_collector_schema()
	finish()

# ---- T069 C24: pen-bound collector -------------------------------------------------
const C := World.AnimalCollector
const PEN_WEST := Vector2i(48, 36)  # below the cow
const PEN_EAST := Vector2i(50, 36)  # below the sheep
const PEN_DIVIDER: Array[Vector2i] = [Vector2i(49, 35), Vector2i(49, 36)]

## One 3x2 enclosure holding the cow (48,35) and the sheep (50,35), with a gate above each
## animal. `divided` adds a wall column that splits it into two valid 1x2 pens.
static func seed_pen(world, token: String, divided: bool) -> void:
	var walls: Array[Vector2i] = [Vector2i(47, 35), Vector2i(47, 36), Vector2i(51, 35), Vector2i(51, 36), Vector2i(49, 34),
		Vector2i(48, 37), Vector2i(49, 37), Vector2i(50, 37)]
	if divided:walls.append_array(PEN_DIVIDER)
	for tile: Vector2i in walls:world.state.objects[World.key(tile)] = {"type":"wall", "owner":token, "items":{}}
	for tile: Vector2i in [Vector2i(48, 34), Vector2i(50, 34)]:
		world.state.objects[World.key(tile)] = {"type":"door", "owner":token, "items":{}, "open":false}

static func machine(owner_token: String) -> Dictionary:
	return {"type":"animal_collector", "owner":owner_token, "items":{}}

static func basket(world, tile: Vector2i) -> Dictionary:
	return world.state.objects.get(World.key(tile), {})

static func held(world, tile: Vector2i, item: String) -> int:
	return int(basket(world, tile).get("collector_items", {}).get(item, 0))

## Everything a pen product can be in: both animals' `ready` plus every basket total.
static func pen_total(world) -> int:
	var total := 0
	for id: String in ["cow", "sheep"]:total += int(world.state.livestock.get(id, {}).get("ready", 0))
	for obj: Dictionary in world.state.objects.values():total += int(obj.get("collector_count", 0))
	return total

## Order- and type-insensitive picture of the pen for live/reloaded comparisons.
static func pen_signature(world) -> String:
	var parts: PackedStringArray = []
	for tile: Vector2i in [PEN_WEST, PEN_EAST]:
		var obj := basket(world, tile)
		parts.append("%s=%s/%d%s" % [World.key(tile), str(obj.get("collector_animal", "")), int(obj.get("collector_count", 0)), JSON.stringify(obj.get("collector_items",{}))])
	for id: String in ["cow", "sheep"]:
		var animal: Dictionary = world.state.livestock.get(id, {})
		parts.append("%s=%d/%d" % [id, int(animal.get("ready", 0)), int(animal.get("ready_quality", 0))])
	return ";".join(parts)

func pen_world(tag: String, token: String, divided: bool) -> World:
	var world := World.new()
	world.add_player(token, "圈舍")
	world.state.picnic = true
	var path := temp_path(tag)
	_cleanup.append(path)
	world.save_path = path
	var actor: Dictionary = world.state.players[token]
	actor.x = 49.5
	actor.y = 36.5
	actor.inventory.egg_basket = 2
	world.state.objects[World.key(PEN_WEST)] = machine(token)
	world.state.objects[World.key(PEN_EAST)] = machine(token)
	seed_pen(world, token, divided)
	return world

func test_pen_collector() -> void:
	var token := "pen-owner"
	var world := pen_world("pen-collector", token, false)
	var actor: Dictionary = world.state.players[token]
	var west := World.key(PEN_WEST)
	var gap := World.key(Vector2i(47, 35))
	var gap_wall: Dictionary = world.state.objects[gap]
	# Enclosure helper agrees with the registration rule, open or closed.
	world.state.objects.erase(gap)
	expect(L.pen_cells(world.state.objects, L.ANIMALS.cow.cell).is_empty() and not L.pen_status(world.state.objects, "cow"), "An open enclosure has no pen cells")
	expect(C.pen_species(world.state.objects, PEN_WEST).is_empty(), "A collector in an open enclosure serves nobody")
	var before := world.state.duplicate(true)
	expect(not world.act(token, "pen-open-bind", "collector_bind", PEN_WEST, C.PEN).ok and world.state == before, "An open enclosure cannot be bound and keeps the basket")
	world.state.objects[gap] = gap_wall
	var cells := L.pen_cells(world.state.objects, L.ANIMALS.cow.cell)
	expect(cells.size() == 6 and cells.has(PEN_WEST) and cells.has(L.ANIMALS.sheep.cell) and L.pen_status(world.state.objects, "cow") and L.pen_status(world.state.objects, "sheep"),
		"The closed enclosure lists its six interior cells and matches pen_status")
	expect(C.pen_species(world.state.objects, PEN_WEST) == ["cow", "sheep"] and C.pen_species(world.state.objects, Vector2i(46, 35)).is_empty(),
		"Only a collector inside the walls sees the penned species")
	# Binding: one basket, per-item storage, shared capacity of six.
	expect(world.act(token, "pen-bind", "collector_bind", PEN_WEST, C.PEN).ok and int(actor.inventory.egg_basket) == 1
		and basket(world, PEN_WEST).get("collector_animal") == C.PEN, "Binding the enclosure installs exactly one basket")
	expect(not world.act(token, "pen-bind-again", "collector_bind", PEN_WEST, C.PEN).ok and int(actor.inventory.egg_basket) == 1, "Binding the same enclosure twice is refused")
	expect(not world.act(token, "pen-second", "collector_bind", PEN_EAST, C.PEN).ok and not world.act(token, "pen-second-single", "collector_bind", PEN_EAST, "cow").ok
		and int(actor.inventory.egg_basket) == 1 and not basket(world, PEN_EAST).has("collector_animal"), "A served enclosure accepts no second pen or single binding")
	world.state.livestock.cow = rec(0, 4, -1.0)
	world.state.livestock.cow.ready_quality = 1
	world.state.livestock.sheep = rec(0, 3, -1.0)
	world.state.livestock.sheep.ready_quality = 1
	var total := pen_total(world)
	expect(C.step(world) == [west] and held(world, PEN_WEST, "milk") == 3 and held(world, PEN_WEST, "quality_milk") == 1
		and held(world, PEN_WEST, "wool") == 1 and held(world, PEN_WEST, "quality_wool") == 1, "Both species and both grades are stored under their own item IDs")
	expect(int(basket(world, PEN_WEST).collector_count) == C.CAPACITY and int(world.state.livestock.sheep.ready) == 1
		and int(world.state.livestock.sheep.ready_quality) == 0 and pen_total(world) == total, "The basket stops at six and the seventh product waits with the sheep")
	expect(C.step(world).is_empty() and world.step(1.0, true) and int(basket(world, PEN_WEST).collector_count) == C.CAPACITY
		and int(world.state.livestock.sheep.ready) == 1 and pen_total(world) == total, "A full basket takes nothing on later ticks")
	var reloaded := World.new()
	expect(world.save() and reloaded.load_world(world.save_path) and pen_signature(reloaded) == pen_signature(world)
		and typeof(basket(reloaded, PEN_WEST).collector_items.milk) == TYPE_INT, "The mixed basket survives save and reload as whole numbers")
	# Authority and loaded-basket guards.
	world.add_player("pen-guest", "訪客")
	var guest: Dictionary = world.state.players["pen-guest"]
	guest.x = actor.x
	guest.y = actor.y
	guest.inventory.egg_basket = 1
	before = world.state.duplicate(true)
	expect(not world.act("pen-guest", "guest-take", "collector_collect", PEN_WEST).ok and not world.act("pen-guest", "guest-bind", "collector_bind", PEN_EAST, C.PEN).ok
		and not world.act("pen-guest", "guest-unbind", "collector_unbind", PEN_WEST).ok and world.state == before, "A guest cannot take, bind or unbind the owner's collectors")
	expect(not world.act(token, "pen-unbind-full", "collector_unbind", PEN_WEST).ok and not world.act(token, "pen-remove-full", "remove", PEN_WEST).ok
		and not world.act(token, "pen-rebind-full", "collector_bind", PEN_WEST, "cow").ok and world.state == before, "A loaded basket cannot be taken back, dismantled or rebound")
	# Per-item backpack limit: only what fits moves, the rest stays for later.
	for item: String in ["milk", "quality_milk", "wool", "quality_wool"]:actor.inventory[item] = CAP
	before = world.state.duplicate(true)
	expect(not world.act(token, "pen-take-none", "collector_collect", PEN_WEST).ok and world.state == before, "A backpack full of every product takes nothing and loses nothing")
	actor.inventory.milk = CAP - 1
	actor.inventory.quality_milk = 0
	actor.inventory.wool = 0
	actor.inventory.quality_wool = 0
	expect(world.act(token, "pen-take-part", "collector_collect", PEN_WEST).ok and int(actor.inventory.milk) == CAP and int(actor.inventory.quality_milk) == 1
		and int(actor.inventory.wool) == 1 and int(actor.inventory.quality_wool) == 1, "A partial pickup gives each item up to its own limit")
	expect(int(basket(world, PEN_WEST).collector_count) == 2 and held(world, PEN_WEST, "milk") == 2 and basket(world, PEN_WEST).collector_items.size() == 1,
		"Milk that did not fit stays in the basket")
	expect(C.step(world) == [west] and held(world, PEN_WEST, "wool") == 1 and int(world.state.livestock.sheep.ready) == 0, "Freed room collects the waiting wool exactly once")
	actor.inventory.milk = 0
	expect(world.act(token, "pen-take-rest", "collector_collect", PEN_WEST).ok and int(actor.inventory.milk) == 2 and int(actor.inventory.wool) == 2
		and int(basket(world, PEN_WEST).collector_count) == 0 and basket(world, PEN_WEST).collector_items.is_empty(), "The retained products are handed over once")
	expect(not world.act(token, "pen-take-empty", "collector_collect", PEN_WEST).ok, "An empty basket has nothing to take")
	# Broken wall: collection pauses without loss; repair resumes it.
	world.state.livestock.cow = rec(0, 2, -1.0)
	world.state.objects.erase(gap)
	total = pen_total(world)
	expect(C.step(world).is_empty() and world.step(1.0, true) and int(world.state.livestock.cow.ready) == 2 and int(basket(world, PEN_WEST).collector_count) == 0,
		"A gap in the wall stops collection and leaves the milk with the cow")
	world.state.objects[gap] = gap_wall
	expect(C.step(world) == [west] and held(world, PEN_WEST, "milk") == 2 and int(world.state.livestock.cow.ready) == 0 and pen_total(world) == total,
		"Repairing the wall resumes collection of the same two products")
	expect(C.step(world).is_empty() and pen_total(world) == total, "Nothing is collected twice after the repair")
	expect(world.act(token, "pen-take-repair", "collector_collect", PEN_WEST).ok and int(actor.inventory.milk) == 4, "The repaired pen's milk reaches the owner")
	# Mode changes reuse the same basket and never leave stale fields behind.
	expect(world.act(token, "pen-to-single", "collector_bind", PEN_WEST, "cow").ok and int(actor.inventory.egg_basket) == 1
		and not basket(world, PEN_WEST).has("collector_items"), "Switching an empty pen basket to one animal is free and drops the item table")
	expect(not world.act(token, "pen-vs-single", "collector_bind", PEN_EAST, C.PEN).ok and int(actor.inventory.egg_basket) == 1,
		"A species already bound to another machine blocks binding its enclosure")
	# Forced coexistence (as after remodelling): the single machine keeps sole service.
	world.state.objects[World.key(PEN_EAST)] = machine(token).merged({"collector_animal":C.PEN, "collector_count":0, "collector_items":{}})
	world.state.livestock.cow = rec(0, 3, -1.0)
	world.state.livestock.sheep = rec(0, 2, -1.0)
	total = pen_total(world)
	var changed := C.step(world)
	changed.sort()
	expect(changed == [west, World.key(PEN_EAST)] and int(basket(world, PEN_WEST).collector_count) == 3 and held(world, PEN_EAST, "wool") == 2
		and held(world, PEN_EAST, "milk") == 0 and pen_total(world) == total, "Legacy single binding collects its animal; the pen basket takes only the other species")
	basket(world, PEN_WEST).collector_count = C.CAPACITY
	world.state.livestock.cow = rec(0, 2, -1.0)
	expect(C.step(world).is_empty() and int(world.state.livestock.cow.ready) == 2 and held(world, PEN_EAST, "milk") == 0,
		"A full single machine keeps its animal's products pending instead of leaking them to the pen basket")
	expect(world.save() and reloaded.load_world(world.save_path) and pen_signature(reloaded) == pen_signature(world), "Single and pen machines reload side by side")
	basket(world, PEN_WEST).collector_count = 0
	world.state.livestock.cow = rec(0, 0, -1.0)
	expect(world.act(token, "single-back-to-pen", "collector_unbind", PEN_WEST).ok and int(actor.inventory.egg_basket) == 2, "Unbinding returns the basket")

## Two legitimately bound pens that are later joined: exactly one basket serves each
## species, chosen by cell order, identically before and after a JSON reload.
func test_pen_collector_rejoin() -> void:
	var token := "pen-joiner"
	var world := pen_world("pen-rejoin", token, true)
	var actor: Dictionary = world.state.players[token]
	var west := World.key(PEN_WEST)
	var east := World.key(PEN_EAST)
	expect(C.pen_species(world.state.objects, PEN_WEST) == ["cow"] and C.pen_species(world.state.objects, PEN_EAST) == ["sheep"], "A dividing wall makes two separate pens")
	expect(world.act(token, "join-bind-west", "collector_bind", PEN_WEST, C.PEN).ok and world.act(token, "join-bind-east", "collector_bind", PEN_EAST, C.PEN).ok
		and int(actor.inventory.egg_basket) == 0, "Separate pens each take their own basket")
	world.state.livestock.cow = rec(0, 2, -1.0)
	world.state.livestock.sheep = rec(0, 2, -1.0)
	var changed := C.step(world)
	changed.sort()
	expect(changed == [west, east] and held(world, PEN_WEST, "milk") == 2 and held(world, PEN_EAST, "wool") == 2 and held(world, PEN_WEST, "wool") == 0,
		"Each pen basket collects only its own enclosure")
	# Break the west pen, then rejoin both pens into one by removing the divider.
	var gap := World.key(Vector2i(47, 35))
	var gap_wall: Dictionary = world.state.objects[gap]
	world.state.objects.erase(gap)
	world.state.livestock.cow = rec(0, 3, -1.0)
	world.state.livestock.sheep = rec(0, 3, -1.0)
	var total := pen_total(world)
	expect(C.step(world) == [east] and int(world.state.livestock.cow.ready) == 3 and held(world, PEN_EAST, "wool") == 5 and held(world, PEN_EAST, "milk") == 0,
		"A broken pen pauses alone while its neighbour keeps collecting")
	world.state.livestock.sheep = rec(0, 3, -1.0)
	world.state.objects[gap] = gap_wall
	for tile: Vector2i in PEN_DIVIDER:world.state.objects.erase(World.key(tile))
	total = pen_total(world)
	expect(C.pen_species(world.state.objects, PEN_WEST) == ["cow", "sheep"] and C.pen_species(world.state.objects, PEN_EAST) == ["cow", "sheep"], "Without the divider both baskets stand in one pen")
	expect(world.save(), "Save the joined pen before the deciding tick")
	var snapshot: Dictionary = world.state.duplicate(true)
	var reloaded := World.new()
	expect(reloaded.load_world(world.save_path), "Reload the joined pen")
	# Same state with the two machines inserted in the opposite dictionary order.
	var flipped := World.new()
	var objects: Dictionary = {}
	var keys: Array = snapshot.objects.keys()
	keys.reverse()
	for key in keys:objects[key] = snapshot.objects[key]
	snapshot.objects = objects
	flipped.state = snapshot
	expect(flipped.state.objects.keys().find(east) < flipped.state.objects.keys().find(west), "Control: the flipped world really iterates the east machine first")
	expect(C.step(world) == [west] and C.step(reloaded) == [west] and C.step(flipped) == [west], "The west machine (lowest cell) serves the joined pen in every ordering")
	# West had 2 milk: room for 4 -> 3 milk + 1 wool. East keeps its 5 wool and gains nothing.
	expect(held(world, PEN_WEST, "milk") == 5 and held(world, PEN_WEST, "wool") == 1 and int(basket(world, PEN_EAST).collector_count) == 5
		and int(world.state.livestock.sheep.ready) == 2 and int(world.state.livestock.cow.ready) == 0 and pen_total(world) == total,
		"Joined pens split nothing: one basket fills, the rest waits with the sheep")
	expect(pen_signature(reloaded) == pen_signature(world) and pen_signature(flipped) == pen_signature(world), "Live, reloaded and reordered worlds agree exactly")
	expect(C.step(world).is_empty() and C.step(reloaded).is_empty() and int(world.state.livestock.sheep.ready) == 2 and int(basket(world, PEN_EAST).collector_count) == 5
		and pen_total(world) == total, "With the serving basket full the second basket does not take the pending wool")
	expect(world.act(token, "join-take", "collector_collect", PEN_WEST).ok and C.step(world) == [west] and held(world, PEN_WEST, "wool") == 2
		and int(world.state.livestock.sheep.ready) == 0 and int(basket(world, PEN_EAST).collector_count) == 5, "Emptying the serving basket collects the pending wool once")
	expect(int(actor.inventory.milk) == 5 and int(actor.inventory.wool) == 1 and pen_total(world) + 6 == total, "Every product is accounted for after the join")

## The hen's single cycle and her deferred quality egg behave as in single mode.
func test_pen_collector_chicken() -> void:
	var token := "pen-hen"
	var world := World.new()
	world.add_player(token, "雞舍")
	world.state.picnic = true
	var hen: Vector2i = C.CHICKEN_CELL
	var site := hen + Vector2i.DOWN
	var key := World.key(site)
	for tile: Vector2i in [hen + Vector2i.LEFT, hen + Vector2i.RIGHT, site + Vector2i.LEFT, site + Vector2i.RIGHT, site + Vector2i.DOWN]:
		world.state.objects[World.key(tile)] = {"type":"wall", "owner":token, "items":{}}
	world.state.objects[World.key(hen + Vector2i.UP)] = {"type":"door", "owner":token, "items":{}, "open":false}
	world.state.objects[key] = machine(token)
	var actor: Dictionary = world.state.players[token]
	actor.x = site.x + 0.5
	actor.y = site.y + 0.5
	actor.inventory.egg_basket = 1
	expect(C.pen_species(world.state.objects, site) == ["chicken"] and world.act(token, "hen-bind", "collector_bind", site, C.PEN).ok, "The hen's enclosure can be bound")
	var animal: Dictionary = world.state.animal
	var now := float(world.state.time)
	animal.bond = L.BONUS_BOND
	animal.bonus_progress = L.BONUS_INTERVAL - 1
	animal.egg_ready = now
	var obj: Dictionary = world.state.objects[key]
	obj.collector_items = {"egg":5}
	obj.collector_count = 5
	expect(C.step(world) == [key] and held(world, site, "egg") == 6 and held(world, site, "quality_egg") == 0 and float(animal.egg_ready) < 0.0
		and int(animal.bonus_progress) == L.BONUS_INTERVAL, "The last free slot takes the egg and defers the earned quality egg")
	animal.egg_ready = now
	expect(C.step(world).is_empty() and L.chicken_egg_due(animal, now) and int(obj.collector_count) == C.CAPACITY, "A full basket leaves the due egg with the hen")
	var eggs_before := int(actor.inventory.get("egg", 0))
	expect(world.act(token, "hen-take", "collector_collect", site).ok and int(actor.inventory.egg) == eggs_before + 6, "Take the six eggs")
	expect(C.step(world) == [key] and held(world, site, "egg") == 1 and held(world, site, "quality_egg") == 1 and int(animal.bonus_progress) == 0
		and float(animal.egg_ready) < 0.0, "The waiting egg and its deferred quality egg arrive exactly once")
	expect(C.step(world).is_empty() and int(obj.collector_count) == 2, "One cycle is never collected twice")

func loads(state: Dictionary, path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:return false
	file.store_string(JSON.stringify(state))
	file.close()
	return World.new().load_world(path)

func test_pen_collector_schema() -> void:
	var token := "pen-schema"
	var world := pen_world("pen-schema", token, false)
	var west := World.key(PEN_WEST)
	var probe := temp_path("pen-schema-probe")
	_cleanup.append(probe)
	world.state.objects[west] = machine(token).merged({"collector_animal":C.PEN, "collector_count":3, "collector_items":{"milk":2, "quality_wool":1}})
	expect(world.save(), "Save a pen basket fixture")
	var good: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(world.save_path))
	expect(loads(good, probe), "Control: the pen basket fixture loads")
	# A pen basket stays loadable after its walls are gone: topology is not part of the save.
	var bare: Dictionary = good.duplicate(true)
	for tile: String in bare.objects.keys():
		if bare.objects[tile].type in ["wall", "door"]:bare.objects.erase(tile)
	expect(loads(bare, probe), "A pen basket whose walls were removed still loads")
	var cases := {
		"a total that differs from the item sum":{"collector_count":4},
		"an unknown item ID":{"collector_items":{"milk":2, "feed":1}},
		"a zero item count":{"collector_items":{"milk":3, "wool":0}},
		"a fractional item count":{"collector_items":{"milk":2.5, "wool":0.5}},
		"more than six products":{"collector_count":7, "collector_items":{"milk":7}},
		"a single-mode quality field":{"collector_count_quality":1},
		"a missing item table":{"collector_items":null},
		"single mode carrying an item table":{"collector_animal":"cow"},
	}
	for label: String in cases:
		var bad: Dictionary = good.duplicate(true)
		for field: String in cases[label]:
			if cases[label][field] == null:bad.objects[west].erase(field)
			else:bad.objects[west][field] = cases[label][field]
		expect(not loads(bad, probe), "Load rejects a pen basket with " + label)
	# Existing single-species saves are untouched by the new mode.
	var legacy: Dictionary = good.duplicate(true)
	legacy.objects[west] = {"type":"animal_collector", "owner":token, "items":{}, "collector_animal":"cow", "collector_count":2, "collector_count_quality":1}
	var old := World.new()
	file_write(probe, legacy)
	expect(old.load_world(probe) and old.state.objects[west].collector_animal == "cow" and int(old.state.objects[west].collector_count) == 2
		and int(old.state.objects[west].collector_count_quality) == 1 and not old.state.objects[west].has("collector_items"), "A legacy single-species collector loads unchanged")
	old.state.livestock.cow = rec(0, 3, -1.0)
	expect(C.step(old) == [west] and int(old.state.objects[west].collector_count) == 5 and not old.state.objects[west].has("collector_items"),
		"A legacy collector keeps collecting in its original fields")

static func file_write(path: String, state: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(state))
	file.close()

func test_bond_bonus(day:float)->void:
	var cow:=rec(5,3,day)
	cow.bond=L.BONUS_BOND
	cow.last_pet=0
	var records:Dictionary={"cow":cow}
	expect(L.step(records,4*day) and cow.ready==L.LIMIT and cow.bonus_progress==L.BONUS_INTERVAL,"A full station defers an earned bonus")
	var world:=World.new()
	var path:=temp_path("bond-bonus")
	_cleanup.append(path)
	world.save_path=path
	world.state.time=4*day
	world.state.livestock=records
	expect(world.save() and world.load_world(path),"Full station with a deferred bonus survives save and reload")
	records=world.state.livestock
	cow=records.cow
	expect(int(cow.bonus_progress)==L.BONUS_INTERVAL,"The pending bonus is still owed after reload")
	var bag:Dictionary={}
	for i in range(2):expect(L.perform(records,bag,"cow","livestock_collect",4*day).ok,"Clear room for regular and bonus output")
	expect(L.step(records,5*day) and cow.ready==L.LIMIT and cow.bonus_progress==0,"The next cycle awards exactly one deferred bonus")
	expect(not L.step(records,5*day),"Retrying the completed tick grants nothing")
	cow.collector=0
	expect(L.collect_into_equipment(records,5*day) and cow.collector==L.LIMIT and cow.ready==0,"Bonus and regular output share the same collector")
	expect(int(cow.collector_quality)==1,"Station collector preserves the quality grade")
	expect(L.perform(records,bag,"cow","livestock_empty",5*day).ok and int(bag.quality_milk)==1 and int(bag.milk)==8,
		"Emptying the station collector grants one premium and six ordinary units")

func test_quality_routes(day:float)->void:
	var world:=World.new()
	var token:="quality-ranch"
	world.add_player(token,"牧場")
	world.state.picnic=true
	var actor:Dictionary=world.state.players[token]
	var cow:=rec(4,0,day)
	cow.bond=L.BONUS_BOND
	cow.last_pet=0.0
	world.state.livestock.cow=cow
	var sheep:=rec(4,0,day*2)
	sheep.bond=L.BONUS_BOND
	sheep.last_pet=0.0
	world.state.livestock.sheep=sheep
	var site:=L.collector_cell("cow")
	var box_key:=World.key(L.collector_cell("sheep"))
	world.state.objects[box_key]={"type":"chest","owner":token,"items":{}}
	var key:=World.key(site)
	world.state.objects[key]={"type":"animal_collector","owner":token,"items":{},"collector_animal":"cow","collector_count":0}
	world.state.time=day*8
	expect(L.step(world.state.livestock,float(world.state.time)),"Both bonded animals produce four ordinary products and their quality bonus")
	expect(World.AnimalCollector.step(world)==[key] and int(world.state.objects[key].collector_count_quality)==1,
		"The buildable collector drains both grades")
	expect(L.collect_into_chests(world)==[box_key] and int(world.state.objects[box_key].items.quality_wool)==1
		and int(world.state.objects[box_key].items.wool)==4,"Shared box receives ordinary and premium wool separately")
	var path:=temp_path("quality-routes")
	_cleanup.append(path)
	world.save_path=path
	expect(world.save() and world.load_world(path),"Mixed-grade chest and collector survive reloading")
	actor=world.state.players[token]
	actor.x=site.x+0.5
	actor.y=site.y+0.5
	actor.inventory.quality_milk=CAP
	expect(world.act(token,"ordinary","collector_collect",site).ok and int(actor.inventory.milk)==4
		and int(world.state.objects[key].collector_count)==1,"A full quality stack leaves only the quality product in the machine")
	actor.inventory.quality_milk=0
	expect(world.act(token,"premium","collector_collect",site).ok and int(actor.inventory.quality_milk)==1
		and int(world.state.objects[key].collector_count)==0,"The second pickup gives the retained quality milk exactly once")
	var stall:=Vector2i(43,29)
	actor.x=stall.x+0.5
	actor.y=stall.y+0.5
	var coins:=int(actor.coins)
	expect(world.act(token,"sell-quality","sell",stall,"quality_milk").ok and int(actor.coins)==coins+45,
		"Quality milk sells for 45 at the seed stall")
	var records:Dictionary={"sheep":rec(0,2,-1)}
	records.sheep.ready_quality=1
	var bag:Dictionary={}
	expect(L.perform(records,bag,"sheep","livestock_collect",8*day).ok and int(bag.get("quality_wool",0))==1
		and int(records.sheep.ready_quality)==0 and int(records.sheep.ready)==1,"Manual collection preserves the grade and leaves ordinary wool behind")

func test_timer_boundaries(day: float) -> void:
	expect(L.fresh() == rec(0, 0, -1.0), "Fresh record is idle")
	var r := {"cow":rec(1, 0, day)}
	expect(not L.step(r, day - 0.001) and r.cow == rec(1, 0, day), "Just before the due time nothing is produced")
	expect(L.step(r, day) and r.cow == rec(0, 1, -1.0), "Exactly at the due time one product appears; last feed stops the timer")
	expect(not L.step(r, day * 1000.0) and r.cow == rec(0, 1, -1.0), "A stopped timer never produces")
	r = {"cow":rec(3, 0, day)}
	expect(L.step(r, 2.0 * day - 0.001) and r.cow == rec(2, 1, 2.0 * day), "Just short of a second interval counts only one product")
	expect(not L.step(r, 2.0 * day - 0.001) and r.cow == rec(2, 1, 2.0 * day), "Repeating the same instant is idempotent")
	expect(L.step(r, 2.0 * day) and r.cow == rec(1, 2, 3.0 * day), "Second interval boundary produces again")
	r = {"cow":rec(5, 0, day)}
	expect(L.step(r, 4.0 * day - 0.001) and r.cow == rec(2, 3, 4.0 * day), "Catch-up counts whole elapsed intervals and keeps the phase")
	expect(L.step(r, 4.0 * day) and r.cow == rec(1, 4, 5.0 * day), "Phase after catch-up stays on the original grid")
	r = {"sheep":rec(2, 0, 2.0 * day)}
	expect(not L.step(r, 2.0 * day - 0.001), "Sheep waits its full two-day interval")
	expect(L.step(r, 4.0 * day - 0.001) and r.sheep == rec(1, 1, 4.0 * day), "Sheep uses a two-day interval for catch-up")
	expect(L.step(r, 4.0 * day) and r.sheep == rec(0, 2, -1.0), "Sheep stops after its last feed")
	var recs := {"cow": L.fresh()}
	var inv := {"feed":3}
	expect(L.perform(recs, inv, "cow", "livestock_feed", 100.0).ok and recs.get("cow", {}) == rec(1, 0, 100.0 + day) and inv.feed == 2, "First feed starts the timer at now + interval")
	expect(L.perform(recs, inv, "cow", "livestock_feed", 500.0).ok and recs.cow == rec(2, 0, 100.0 + day), "Feeding a running animal does not reset its timer")
	expect(L.perform(recs, inv, "sheep", "livestock_feed", 100.0).ok and recs.get("sheep", {}) == rec(1, 0, 100.0 + 2.0 * day), "Sheep timer starts two days out")
	var inv_before := inv.duplicate(true)
	expect(not L.perform(recs, inv, "cow", "livestock_collect", 200.0).ok and inv == inv_before and recs.cow == rec(2, 0, 100.0 + day), "Collecting before production fails without changes")

func test_seven_slot_capacity(day: float) -> void:
	var recs := {"cow": L.fresh()}
	var inv := {"feed":10}
	for i in range(L.LIMIT):
		expect(L.perform(recs, inv, "cow", "livestock_feed", 0.0).ok, "Feed slot %d accepts feed" % (i + 1))
	expect(not L.perform(recs, inv, "cow", "livestock_feed", 0.0).ok and recs.cow == rec(7, 0, day) and inv.feed == 3, "Eighth feed is refused and keeps the backpack feed")
	var empty := {}
	expect(not L.perform(empty, {}, "sheep", "livestock_feed", 0.0).ok and empty.is_empty(), "Feeding without feed fails and creates no record")
	var r := {"cow":rec(7, 5, day)}
	expect(L.step(r, day * 100.0) and r.cow == rec(5, 7, -1.0), "Ready products cap at seven and only consume the feed used")
	expect(not L.step(r, day * 200.0) and r.cow == rec(5, 7, -1.0), "A full pen stays stopped")
	r = {"cow":rec(7, 0, day)}
	expect(L.step(r, day * 101.0) and r.cow == rec(0, 7, -1.0), "A huge backlog produces at most seven")
	r = {"cow":rec(5, 7, -1.0)}
	inv = {"feed":3}
	expect(L.perform(r, inv, "cow", "livestock_feed", 10000.0).ok and r.cow == rec(6, 7, -1.0), "Feeding a full pen keeps the timer stopped")
	expect(L.perform(r, inv, "cow", "livestock_feed", 10000.0).ok and r.cow == rec(7, 7, -1.0), "Feeder can reach seven while the pen is full")
	expect(not L.perform(r, inv, "cow", "livestock_feed", 10000.0).ok and inv.feed == 1 and r.cow == rec(7, 7, -1.0), "Both seven-slot stores full refuses feed")
	expect(L.perform(r, inv, "cow", "livestock_collect", 10000.0).ok and inv.get("milk", 0) == 1 and r.cow == rec(7, 6, 10000.0 + day), "Collecting from a full pen restarts the timer from now")
	expect(not L.step(r, 10000.0 + day - 0.001) and r.cow == rec(7, 6, 10000.0 + day), "Time spent full earns no backlog credit")
	expect(L.step(r, 10000.0 + day) and r.cow == rec(6, 7, -1.0), "Refilled slot produces once and stops again at seven")
	r = {"cow":rec(1, 1, 50.0)}
	inv = {"milk":CAP}
	expect(not L.perform(r, inv, "cow", "livestock_collect", 0.0).ok and inv.milk == CAP and r.cow == rec(1, 1, 50.0), "Backpack at the item cap refuses collection")

func test_full_box(day: float) -> void:
	var world := World.new()
	world.state.time = 2000.0
	var cow_key := World.key(L.collector_cell("cow"))
	var sheep_key := World.key(L.collector_cell("sheep"))
	expect(L.collector_cell("cow") == L.ANIMALS.cow.cell + Vector2i.DOWN and not world.protected(L.collector_cell("cow")), "The collector remains below the cow pen and outside public reservations")
	world.state.livestock = {"cow":rec(3, 7, -1.0), "sheep":rec(1, 4, 9000.0)}
	world.state.objects[cow_key] = {"type":"chest", "items":{"milk":CAP - 2}}
	world.state.objects[sheep_key] = {"type":"fence", "items":{}}
	var changed := L.collect_into_chests(world)
	expect(changed.size() == 1 and changed[0] == cow_key, "Only the real collector chest reports a change")
	expect(int(world.state.objects[cow_key].items.milk) == CAP, "Nearly full box fills exactly to the cap")
	expect(same(animal_of(world, "cow"), 3, 5, 2000.0 + day), "Overflow stays in the pen and a freed slot restarts the timer")
	expect(same(animal_of(world, "sheep"), 1, 4, 9000.0), "A non-chest object at the collector is ignored")
	changed = L.collect_into_chests(world)
	expect(changed.is_empty() and same(animal_of(world, "cow"), 3, 5, 2000.0 + day) and int(world.state.objects[cow_key].items.milk) == CAP, "A full box takes nothing and reports nothing")
	world.state.objects.erase(sheep_key)
	expect(L.collect_into_chests(world).is_empty() and same(animal_of(world, "sheep"), 1, 4, 9000.0), "No box means products wait in the pen")
	world.state.objects[cow_key].items.milk = 0
	changed = L.collect_into_chests(world)
	expect(changed.size() == 1 and int(world.state.objects[cow_key].items.milk) == 5 and same(animal_of(world, "cow"), 3, 0, 2000.0 + day), "Empty box drains the pen without moving the running timer")
	world.state.livestock.cow = rec(0, 7, -1.0)
	world.state.objects[cow_key].items.milk = 0
	changed = L.collect_into_chests(world)
	expect(changed.size() == 1 and int(world.state.objects[cow_key].items.milk) == 7 and same(animal_of(world, "cow"), 0, 0, -1.0), "Draining an unfed full pen keeps the timer stopped")

func test_pen_construction()->void:
	var world:=World.new()
	var token:="pen-builder"
	world.add_player(token,"牧場測試")
	var cow:Vector2i=L.ANIMALS.cow.cell
	var gate:=cow+Vector2i.UP
	var builder:Dictionary=world.state.players[token]
	world.state.picnic=true
	var path:=temp_path("managed-pen")
	_cleanup.append(path)
	world.save_path=path
	builder.x=cow.x+0.5
	builder.y=cow.y+0.5
	builder.inventory.wood=80
	builder.inventory.fiber=8
	builder.inventory.feed=1
	expect(world.act(token,"pen-adopt","livestock_adopt",cow,"cow").ok,"D07: adopt the cow before registering its pen")
	expect(not L.pen_status(world.state.objects,"cow"),"Open pasture is not a player-built enclosure")
	expect(not world.act(token,"pen-premature","livestock_pen",cow,"cow").ok,"An open pasture cannot be registered")
	for offset:Vector2i in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i(0,2),Vector2i.UP,Vector2i(-1,1),Vector2i(1,1)]:
		var tile:=cow+offset
		if world.resource(tile)=="tree":
			for hit in range(3):world.act(token,"pen-axe-%s-%d"%[World.key(tile),hit],"axe",tile)
		elif world.resource(tile)=="rock":
			for hit in range(2):world.act(token,"pen-pick-%s-%d"%[World.key(tile),hit],"pick",tile)
		elif world.resource(tile)=="grass":
			world.act(token,"pen-grass-"+World.key(tile),"axe",tile)
		expect(world.act(token,"pen-build-"+World.key(tile),"build",tile,"door" if tile==gate else "wall").ok,"Build the ranch boundary through World.act")
	expect(L.pen_status(world.state.objects,"cow"),"Built walls and a gate form an enclosure")
	expect(world.act(token,"pen-open","door",gate).ok and not world.blocked(gate),"The gate allows walking through")
	expect(L.pen_status(world.state.objects,"cow"),"Passing through the gate preserves its enclosure")
	expect(world.act(token,"pen-register","livestock_pen",cow,"cow").ok,"Built enclosure can be registered")
	expect(world.act(token,"pen-feed","livestock_feed",cow,"cow").ok,"Registered cow can be fed")
	expect(world.step(300,true),"Advance part of the original production cycle")
	var remaining:=float(world.state.livestock.cow.next)-float(world.state.time)
	expect(world.act(token,"pen-remove","remove",cow+Vector2i.RIGHT).ok,"Players can remodel the existing enclosure")
	expect(not L.pen_status(world.state.objects,"cow"),"Removing a boundary leaves the enclosure open")
	expect(world.step(L.DAY,true),"Advance a day while the enclosure is open")
	expect(world.load_world(path),"Reload the paused enclosure")
	var cow_record:Dictionary=world.state.livestock.cow
	expect(cow_record.managed_pen and int(cow_record.ready)==0 and int(cow_record.feed)==1,"Paused cow retains feed and registration with no new product")
	expect(is_equal_approx(float(cow_record.next)-float(world.state.time),remaining),"Paused production preserves the remaining timer")
	expect(world.act(token,"pen-repair","build",cow+Vector2i.RIGHT,"wall").ok,"Rebuild the missing boundary")
	expect(world.step(remaining-1,true) and int(world.state.livestock.cow.ready)==0,"Repair resumes the old timer without awarding early")
	expect(world.step(1,true) and int(world.state.livestock.cow.ready)==1,"Production finishes exactly once on the original schedule")

func test_full_equipment(day:float)->void:
	var world:=World.new()
	var cow:=rec(2,L.LIMIT,-1.0)
	cow.collector=L.COLLECTOR_CAPACITY
	world.state.livestock={"cow":cow}
	var key:=World.key(L.collector_cell("cow"))
	world.state.objects[key]={"type":"chest","items":{"milk":1}}
	expect(not L.collect_into_equipment(world.state.livestock,100.0) and L.collect_into_chests(world).is_empty(),"Full equipment leaves all overflow at the station even with a legacy chest")
	var bag:Dictionary={"milk":CAP-2}
	expect(L.perform(world.state.livestock,bag,"cow","livestock_empty",100.0).ok and bag.milk==CAP,"The backpack can accept a partial pickup")
	expect(int(cow.collector)==L.COLLECTOR_CAPACITY and same(cow,2,L.LIMIT-2,100.0+day),"Freed capacity immediately receives overflow and resumes production")
	expect(not L.perform(world.state.livestock,bag,"cow","livestock_empty",100.0).ok,"A full backpack cannot remove extra products")
	bag={}
	expect(L.perform(world.state.livestock,bag,"cow","livestock_empty",110.0).ok and bag.milk==L.COLLECTOR_CAPACITY,"Remaining collector products are available")
	expect(int(cow.collector)==L.LIMIT-2 and same(cow,2,0,100.0+day),"Remaining overflow moves once and keeps the running timer")
	expect(int(world.state.objects[key].items.milk)==1,"The legacy box keeps its original contents")

func test_multiple_animals(day: float) -> void:
	var r := {"cow":rec(3, 0, day), "sheep":rec(2, 0, 2.0 * day)}
	expect(L.step(r, 2.0 * day) and r.cow == rec(1, 2, 3.0 * day) and r.sheep == rec(1, 1, 4.0 * day), "Cow and sheep advance on their own intervals in one step")
	expect(L.step(r, 3.0 * day) and r.cow == rec(0, 3, -1.0) and r.sheep == rec(1, 1, 4.0 * day), "Cow finishing does not touch the sheep")
	expect(L.step(r, 4.0 * day) and r.sheep == rec(0, 2, -1.0) and r.cow == rec(0, 3, -1.0), "Sheep finishing does not touch the cow")
	var inv := {}
	expect(L.perform(r, inv, "cow", "livestock_collect", 5.0 * day).ok and inv == {"milk":1} and r.sheep == rec(0, 2, -1.0), "Collecting milk leaves wool in the sheep pen")
	r = {"cow":rec(2, 7, -1.0), "sheep":rec(1, 0, 2.0 * day)}
	expect(L.step(r, 2.0 * day) and r.cow == rec(2, 7, -1.0) and r.sheep == rec(0, 1, -1.0), "A full cow pen does not block the sheep")
	var world := World.new()
	world.state.time = 100.0
	world.state.livestock = {"cow":rec(1, 3, 500.0), "sheep":rec(1, 2, 600.0)}
	var cow_key := World.key(L.collector_cell("cow"))
	world.state.objects[cow_key] = {"type":"chest", "items":{}}
	world.state.objects.erase(World.key(L.collector_cell("sheep")))
	var changed := L.collect_into_chests(world)
	expect(changed.size() == 1 and changed[0] == cow_key and int(world.state.objects[cow_key].items.get("milk", 0)) == 3 and not world.state.objects[cow_key].items.has("wool"), "Each collector box only receives its own animal's product")
	expect(same(animal_of(world, "sheep"), 1, 2, 600.0), "Sheep without a box keeps its products")

func test_world_and_atomic_save(day: float) -> void:
	var path := temp_path("world")
	var corrupt := temp_path("corrupt")
	_cleanup.append(path)
	_cleanup.append(corrupt)
	var world := World.new()
	var token := "livestock-player"
	world.add_player(token, "Player")
	var p: Dictionary = world.state.players[token]
	p.x = 39.5
	p.y = 30.5
	p.inventory.soup = 2
	p.inventory.bread = 1
	world.state.board = true
	world.state.objects["39,31"] = {"type":"chair", "owner":token, "items":{}}
	world.save_path = path
	expect(world.act(token, "picnic", "picnic", Vector2i(40, 29)).ok and world.state.picnic == true, "Picnic unlocks the ranch")
	if failures > 0:return
	var cow_cell: Vector2i = L.ANIMALS.cow.cell
	var sheep_cell: Vector2i = L.ANIMALS.sheep.cell
	p = world.state.players[token]
	p.x = 49.5
	p.y = 36.5
	p.inventory["feed"] = 6
	expect(world.act(token,"adopt-cow","livestock_adopt",cow_cell,"cow").ok,"The cow can join the ranch after the picnic")
	expect(world.act(token,"pet-cow","livestock_pet",cow_cell,"cow").ok,"Cow can be petted at the station")
	expect(not world.act(token,"pet-cooldown","livestock_pet",cow_cell,"cow").ok,"A repeat pet respects the world clock cooldown")
	expect(world.act(token,"pet-sheep","livestock_pet",sheep_cell,"sheep").ok,"Sheep has an independent cooldown")
	expect(int(world.state.livestock.cow.bond)==1 and int(world.state.livestock.sheep.bond)==1,"Each animal has its own bond total")
	expect(not world.act(token, "wrong-cell", "livestock_feed", sheep_cell, "cow").ok, "Feeding needs the animal's own pen cell")
	expect(world.act(token, "feed-cow-1", "livestock_feed", cow_cell, "cow").ok, "Feed cow once")
	expect(world.act(token, "feed-cow-2", "livestock_feed", cow_cell, "cow").ok, "Feed cow twice")
	expect(world.act(token, "feed-sheep-1", "livestock_feed", sheep_cell, "sheep").ok, "Feed sheep once")
	var t0 := float(world.state.time)
	expect(same(animal_of(world, "cow"), 2, 0, t0 + day) and same(animal_of(world, "sheep"), 1, 0, t0 + 2.0 * day), "World feeding starts independent timers")
	expect(world.step(day - 0.5, true) and same(animal_of(world, "cow"), 2, 0, t0 + day), "World tick half a minute early produces nothing")
	expect(world.step(0.5, true) and same(animal_of(world, "cow"), 1, 1, t0 + 2.0 * day) and same(animal_of(world, "sheep"), 1, 0, t0 + 2.0 * day), "World tick at the boundary produces cow milk only")
	expect(world.load_world(path) and same(animal_of(world, "cow"), 1, 1, t0 + 2.0 * day) and same(animal_of(world, "sheep"), 1, 0, t0 + 2.0 * day), "Livestock records survive reload")
	expect(int(world.state.livestock.cow.bond)==1 and int(world.state.livestock.sheep.bond)==1,"Both bond records survive reloading")
	expect(world.act(token,"pet-after-day","livestock_pet",cow_cell,"cow").ok and int(world.state.livestock.cow.bond)==2,"Later care increases the same bond after reloading")
	if failures > 0:return

	# Atomic save failure: an unreachable save path must roll back every change.
	var before := world.state.duplicate(true)
	var bad := OS.get_environment("TEMP").path_join("livestock-core-missing-%s" % Crypto.new().generate_random_bytes(8).hex_encode()).path_join("world.json")
	world.save_path = bad
	expect(not world.act(token,"fail-pet","livestock_pet",sheep_cell,"sheep").ok and world.state==before,"Failed save rolls back bond and pet time")
	expect(not world.act(token, "fail-feed", "livestock_feed", cow_cell, "cow").ok and world.state == before, "Failed save rolls back feeding (feed, record and receipt)")
	expect(not world.act(token, "fail-collect", "livestock_collect", cow_cell, "cow").ok and world.state == before, "Failed save rolls back collection")
	expect(int(world.state.players[token].inventory.get("milk", 0)) == 0 and same(animal_of(world, "cow"), 1, 1, t0 + 2.0 * day), "No product is duplicated or lost by the failed collect")
	expect(not world.step(day, true) and world.step_error == World.STEP_FAIL_SAVE and world.state == before, "Failed save rolls back a producing tick including time")
	expect(not FileAccess.file_exists(bad) and not FileAccess.file_exists(bad + ".tmp"), "Nothing is written at the unreachable path")
	var disk := World.new()
	expect(disk.load_world(path) and same(animal_of(disk, "cow"), 1, 1, t0 + 2.0 * day) and same(animal_of(disk, "sheep"), 1, 0, t0 + 2.0 * day), "Last good save on disk is untouched")
	world.save_path = path
	expect(world.act(token, "fail-feed", "livestock_feed", cow_cell, "cow").ok and same(animal_of(world, "cow"), 2, 1, t0 + 2.0 * day), "Retrying the failed request after repair applies exactly once")
	expect(world.act(token, "fail-collect", "livestock_collect", cow_cell, "cow").ok and int(world.state.players[token].inventory.get("milk", 0)) == 1 and same(animal_of(world, "cow"), 2, 0, t0 + 2.0 * day), "Retrying the failed collect after repair gives one milk")
	expect(world.step(day, true) and same(animal_of(world, "cow"), 1, 1, t0 + 3.0 * day) and same(animal_of(world, "sheep"), 0, 1, -1.0), "Repaired tick produces both animals on schedule")
	expect(world.load_world(path) and same(animal_of(world, "cow"), 1, 1, t0 + 3.0 * day) and same(animal_of(world, "sheep"), 0, 1, -1.0), "Repaired tick is durable")

	# Schema guard: an out-of-range livestock record is never loaded.
	var bad_state := world.state.duplicate(true)
	var file := FileAccess.open(corrupt, FileAccess.WRITE)
	expect(file != null, "Write control fixture")
	if file == null:return
	file.store_string(JSON.stringify(bad_state))
	file.close()
	var probe := World.new()
	expect(probe.load_world(corrupt) and same(animal_of(probe, "cow"), 1, 1, t0 + 3.0 * day), "Control: the unmodified fixture loads")
	bad_state.livestock.cow = {"feed":0, "ready":L.LIMIT + 1, "next":-1.0}
	file = FileAccess.open(corrupt, FileAccess.WRITE)
	file.store_string(JSON.stringify(bad_state))
	file.close()
	probe = World.new()
	var probe_before := probe.state.duplicate(true)
	expect(not probe.load_world(corrupt) and probe.state == probe_before, "Eight ready products are rejected on load")
	bad_state.livestock.cow = {"feed":1, "ready":0, "next":-1.0}
	file = FileAccess.open(corrupt, FileAccess.WRITE)
	file.store_string(JSON.stringify(bad_state))
	file.close()
	probe = World.new()
	expect(not probe.load_world(corrupt), "A fed, non-full animal without a timer is rejected on load")

## Timed production and actual sales, fixed batch of four feed, without bond bonuses.
## The stove and ingredients are seeded; travel, station setup and gathering are outside the timing window.
func test_ranch_income() -> void:
	for spec:Array in [["egg","",World.CHICKEN_CELL,World.CHICKEN_EGG_SECONDS,30],["milk","cow",L.ANIMALS.cow.cell,L.DAY,36],["wool","sheep",L.ANIMALS.sheep.cell,2.0*L.DAY,48]]:
		var item:String=spec[0]
		var animal:String=spec[1]
		var site:Vector2i=spec[2]
		var interval:float=spec[3]
		var price:int=spec[4]
		var world:=World.new()
		var token:="ranch-income"
		world.add_player(token,"牧場試算")
		world.state.picnic=true
		var actor:Dictionary=world.state.players[token]
		actor.x=site.x+0.5
		actor.y=site.y+0.5
		actor.inventory.wheat=1
		actor.inventory.fiber=2
		if animal=="cow":expect(world.act(token,"adopt-cow","livestock_adopt",site,"cow").ok,"D07: the cow is adopted before the income run")
		var stove:=site+Vector2i.UP
		world.state.objects[World.key(stove)]={"owner":token,"type":"stove","items":{}}
		expect(world.act(token,"feed-cook","cook",stove,"feed").ok,item+" begins with one feed recipe")
		expect(world.step(float(World.RECIPES.feed.time),true),item+" feed cooks")
		expect(world.act(token,"feed-take","claim_cook",stove).ok and int(actor.inventory.get("feed",0))==4,item+" gets exactly four feed")
		var started:=float(world.state.time)
		for i in range(4):
			var feed_action:="feed" if animal.is_empty() else "livestock_feed"
			var collect_action:="egg" if animal.is_empty() else "livestock_collect"
			expect(world.act(token,"feed-%d"%i,feed_action,site,animal).ok,"Feed "+item)
			expect(world.step(interval,true),item+" reaches production deadline")
			expect(world.act(token,"collect-%d"%i,collect_action,site,animal).ok,"Collect "+item)
		expect(int(actor.inventory.get(item,0))==4 and int(actor.inventory.get("feed",-1))==0,item+" converts four feed into four products")
		var elapsed:=float(world.state.time)-started
		var coins:=int(actor.coins)
		var stall:=Vector2i(43,29)
		actor.x=stall.x+0.5
		actor.y=stall.y+0.5
		expect(world.act(token,"sell","sell",stall,item).ok,item+" can be sold at Xiaoli's stall")
		var earned:=int(actor.coins)-coins
		expect(elapsed==4.0*interval and earned==4*price,item+" pays the listed price after the expected production time")
		print("RANCH_INCOME item=%s produced=4 world_seconds=%.0f gross=%d wheat_opportunity_cost=%d fiber_used=2"%[item,elapsed,earned,World.CROPS.wheat.price])
