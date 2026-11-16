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
	test_seven_slot_capacity(day)
	test_full_box(day)
	test_full_equipment(day)
	test_pen_construction()
	test_multiple_animals(day)
	test_world_and_atomic_save(day)
	test_ranch_income()
	finish()

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
	var recs := {}
	var inv := {"feed":3}
	expect(L.perform(recs, inv, "cow", "livestock_feed", 100.0).ok and recs.get("cow", {}) == rec(1, 0, 100.0 + day) and inv.feed == 2, "First feed starts the timer at now + interval")
	expect(L.perform(recs, inv, "cow", "livestock_feed", 500.0).ok and recs.cow == rec(2, 0, 100.0 + day), "Feeding a running animal does not reset its timer")
	expect(L.perform(recs, inv, "sheep", "livestock_feed", 100.0).ok and recs.get("sheep", {}) == rec(1, 0, 100.0 + 2.0 * day), "Sheep timer starts two days out")
	var inv_before := inv.duplicate(true)
	expect(not L.perform(recs, inv, "cow", "livestock_collect", 200.0).ok and inv == inv_before and recs.cow == rec(2, 0, 100.0 + day), "Collecting before production fails without changes")

func test_seven_slot_capacity(day: float) -> void:
	var recs := {}
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
	expect(L.collector_cell("cow") == L.ANIMALS.cow.cell + Vector2i.DOWN, "Collector sits directly below the pen")
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
