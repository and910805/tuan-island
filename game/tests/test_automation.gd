extends SceneTree

const World = preload("res://scripts/world.gd")
const Bench := Vector2i(38, 34)
const Device := Vector2i(42, 34)
var world := World.new()
var checks := 0
var failures := 0

func check(condition: bool, detail: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(detail)

func action(who: String, id: String, verb: String, cell: Vector2i, extra := "") -> bool:
	return world.act(who, id, verb, cell, extra).ok

func near(who: String, tile: Vector2i) -> void:
	world.state.players[who].x = tile.x + 0.5
	world.state.players[who].y = tile.y + 1.5

func crop(tile: Vector2i, owner: String, wet: bool, kind := "radish") -> void:
	world.state.crops[World.key(tile)] = {"owner":owner,"wet":wet,"kind":kind,"growth":0.0,"remaining":1}

func write(path: String, state: Dictionary) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(state))

func _initialize() -> void:
	world.add_player("a", "甲")
	world.add_player("b", "乙")
	world.state.objects[World.key(Bench)] = {"type":"bench","owner":"b","items":{}}
	near("a", Bench)
	var inv: Dictionary = world.state.players.a.inventory
	inv.wood = 30
	inv.stone = 12
	check(not action("a","bad-bench","craft",Bench+Vector2i.LEFT,"reinforced_pick"), "craft needs the bench cell")
	check(action("a","pick","craft",Bench,"reinforced_pick"), "shared bench crafts the reinforced pick")
	check(inv.reinforced_pick==1 and inv.wood==24 and inv.stone==8 and inv.fiber==8, "exact reinforced pick cost")
	check(action("a","pick","craft",Bench,"reinforced_pick") and inv.reinforced_pick==1, "craft retry does not duplicate")
	check(not action("a","pick2","craft",Bench,"reinforced_pick"), "second reinforced pick denied")
	var chest:=Bench+Vector2i.LEFT
	world.state.objects[World.key(chest)]={"type":"private_chest","owner":"a","items":{}}
	check(action("a","stash","deposit",chest,"reinforced_pick") and inv.reinforced_pick==0,
		"crafted pick can be stored")
	check(not action("a","pick-stashed","craft",Bench,"reinforced_pick"), "stashing the pick does not permit duplicates")
	check(action("a","recover","withdraw",chest,"reinforced_pick") and inv.reinforced_pick==1,
		"stored pick can be recovered")
	check(not action("a","no-ore","craft",Bench,"copper_joint") and inv.wood==24, "insufficient materials unchanged")
	check(not action("a","far","mine_copper",World.COPPER_CELL), "mining checks distance")
	for who in ["a","b"]:near(who,World.COPPER_CELL)
	check(world.protected(World.COPPER_CELL) and world.blocked(World.COPPER_CELL), "vein protected and blocking")
	check(not action("b","no-pick","pick",World.COPPER_CELL), "ordinary pick cannot mine copper")
	check(action("a","ore","pick",World.COPPER_CELL) and inv.copper_ore==2 and inv.reinforced_pick==1, "vein yields two ore and preserves pick")
	world.state.players.b.inventory.reinforced_pick = 1
	check(not action("b","race","mine_copper",World.COPPER_CELL), "second miner loses the race")
	world.step(12.0,false)
	check(not action("b","offline","mine_copper",World.COPPER_CELL), "empty world does not cool down vein")
	world.step(12.0,true)
	check(action("a","ore2","mine_copper",World.COPPER_CELL) and inv.copper_ore==4, "vein regrows online")
	near("a",Bench)
	check(action("a","joint1","craft",Bench,"copper_joint") and action("a","joint2","craft",Bench,"copper_joint"), "craft copper joints")
	check(action("a","kit","craft",Bench,"sprinkler_kit") and inv.copper_joint==0 and inv.sprinkler_kit==1, "craft kit")
	near("a",Device)
	near("b",Device+Vector2i.LEFT)
	var key := World.key(Device)
	check(action("a","build","build",Device,"sprinkler") and world.blocked(Device) and inv.sprinkler_kit==0, "device costs exactly one kit and blocks")
	var source_field:String=World.INDUSTRY.STARTER_SPRINKLER_FIELD
	check(world.state.objects[key].sprinkler_daily and world.state.objects[key].get(source_field)==true,
		"The workbench kit builds a daily sprinkler and remembers its source")
	check(not action("b","intrude","refill_sprinkler",Device) and not action("b","switch","toggle_sprinkler",Device), "non-owner cannot refill or toggle")
	check(action("a","fill","refill_sprinkler",Device) and action("a","enable","toggle_sprinkler",Device), "owner refills and enables")
	var own := Device + Vector2i.UP
	var other := Device + Vector2i.RIGHT
	var wet := Device + Vector2i.LEFT
	var empty := Device + Vector2i.DOWN
	crop(own,"a",false)
	crop(other,"b",false)
	crop(wet,"a",true)
	crop(empty,"a",false,"")
	var before: Dictionary = world.state.duplicate(true)
	world.save_path="user://missing-automation-dir/device.json"
	check(not world.step(1.0,true), "disk failure returns false")
	check(world.state==before, "disk failure restores entire tick including time and growth")
	var path := "user://automation-%d.json" % Time.get_ticks_usec()
	world.save_path=path
	check(world.step(1.0,true), "automatic watering commits")
	check(world.state.crops[World.key(own)].wet and not world.state.crops[World.key(other)].wet
		and not world.state.crops[World.key(empty)].wet and world.state.objects[key].water==11, "only dry owned planted crop costs water")
	var loaded := World.new()
	check(loaded.load_world(path) and loaded.state.objects[key].water==11 and loaded.state.crops[World.key(own)].wet
		and loaded.state.objects[key].get(source_field)==true, "Water, crop, and the kit source are saved together")
	var wall_key:=World.EDGE_GRID.key(Device,World.EDGE_GRID.DIRS.find(Vector2i.DOWN),World.SIZE)
	world.state.crops.erase(World.key(own))
	world.state.crops.erase(World.key(wet))
	crop(empty,"a",false)
	world.state.edges[wall_key]={"type":"edge_wall","owner":"a"}
	var dawn:float=world.state.objects[key].next_water
	check(dawn==World.WEATHER.DAY_SECONDS and world.step(dawn-float(world.state.time),true)
		and not world.state.crops[World.key(empty)].wet and float(world.state.objects[key].next_water)==dawn,
		"A wall across the only eligible crop blocks the kit sprinkler without spending its daily pass")
	world.state.edges.erase(wall_key)
	check(world.step(1.0,true) and world.state.crops[World.key(empty)].wet,
		"An unspent daily pass can water after the wall is removed")
	world.state.crops[World.key(empty)].wet=false
	check(world.step(World.SPRINKLER_INTERVAL+1.0,true) and not world.state.crops[World.key(empty)].wet
		and float(world.state.objects[key].next_water)==2.0*World.WEATHER.DAY_SECONDS,
		"The successful pass prevents a second watering on the same day")
	var new_tile := Device + Vector2i(2,0)
	var saved_device: Dictionary = world.state.objects[key].duplicate(true)
	check(action("a","move","move_object",Device,World.key(new_tile)) and world.state.objects[World.key(new_tile)]==saved_device, "moving preserves all sprinkler fields")
	near("a",new_tile)
	check(action("a","remove","remove",new_tile) and world.state.players.a.inventory.sprinkler_kit==1
		and not world.state.objects.has(World.key(new_tile)), "removal refunds only the kit")
	check(not action("a","again","remove",new_tile) and world.state.players.a.inventory.sprinkler_kit==1, "cannot refund a second time")
	for index in range(World.SPRINKLER_LIMIT):
		world.state.objects["%d,36"%(index+1)]={"type":"sprinkler","owner":"a","items":{},
			"water":0,"enabled":false,"next_water":0,"last_water":-1}
	check(not action("a","cap","build",new_tile,"sprinkler") and world.state.players.a.inventory.sprinkler_kit==1,
		"per-owner cap rejects the seventeenth placement without charging")
	var fixture := "user://automation-fixture-%d.json" % Time.get_ticks_usec()
	var saved: Dictionary = loaded.state.duplicate(true)
	for field in ["water","enabled","next_water","last_water"]:
		var bad: Dictionary = saved.duplicate(true)
		bad.objects[key][field] = 13 if field=="water" else "invalid"
		write(fixture,bad)
		check(not loaded.load_world(fixture), "invalid sprinkler field rejected: "+field)
	for invalid in [{source_field:false},{source_field:1},{"assembled_sprinkler":true}]:
		var bad:Dictionary=saved.duplicate(true)
		bad.objects[key].merge(invalid,true)
		write(fixture,bad)
		check(not loaded.load_world(fixture),"Invalid or conflicting kit provenance is rejected")
	var legacy:Dictionary=saved.duplicate(true)
	legacy.objects[key].erase(source_field)
	legacy.objects[key].erase("sprinkler_daily")
	legacy.objects[key].next_water=legacy.time
	legacy.crops[World.key(own)].wet=false
	write(fixture,legacy)
	check(loaded.load_world(fixture) and not loaded.state.objects[key].has("sprinkler_daily"),
		"Already placed legacy kit sprinklers still load on their existing interval")
	check(loaded.step(1.0,true) and loaded.state.crops[World.key(own)].wet
		and float(loaded.state.objects[key].next_water)==float(loaded.state.time)+World.SPRINKLER_INTERVAL,
		"Legacy sprinkler still schedules the eight-second interval")
	saved.objects.erase(key)
	saved.erase("copper")
	saved.players.a.erase("crafted_reinforced_pick")
	write(fixture,saved)
	check(loaded.load_world(fixture) and loaded.state.copper.ready==0.0 and loaded.state.players.a.crafted_reinforced_pick,
		"legacy fields restored additively")
	for file in [fixture,fixture+".bak",path,path+".bak"]:
		if FileAccess.file_exists(file):DirAccess.remove_absolute(file)
	print("AUTOMATION_TESTS checks=%d failures=%d" % [checks, failures])
	quit(0 if failures==0 else 1)
