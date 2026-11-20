extends "res://tests/test_mining_pick_tiers_journey.gd"

const NEIGHBOR:="hand-hoe-neighbor"

func craft_and_try_tiers()->void:
	if failed:return
	var single:=available_field()
	if failed:return
	refuse_deep("hoe",single,"spread","把銅鋤或更高階的鋤頭放在背包，就能範圍整地。","Base hoe cannot send a range action")
	obtain_all({"wood":3,"fiber":2})
	smelt_tier_metal("copper_ingot",2)
	smelt_tier_metal("iron_ingot",3)
	deep_craft("copper_hoe")
	till_pattern(single,"",[Vector2i.ZERO])
	till_pattern(available_field(),"spread",[Vector2i.LEFT,Vector2i.ZERO,Vector2i.RIGHT])
	deep_craft("iron_hoe")
	till_pattern(available_field(),"spread",[Vector2i.UP,Vector2i.LEFT,Vector2i.ZERO,Vector2i.RIGHT,Vector2i.DOWN])
	deep_craft("precision_hoe")
	till_pattern(available_field(),"spread",World.TILLER.SQUARE)
	verify_neighbor_field()
	if failed:return
	var loaded:=World.new()
	if not expect(loaded.load_world(save_path) and not loaded.recovered_from_backup,"Read the upgraded hoe and fields from the primary save"):return
	expect(World.gathering_tool_upgrade("hoe",loaded.state.players[tok].inventory)=="precision_hoe","The last hoe survives reload")
	var expected:Dictionary=world.state.crops.duplicate(true)
	for plot:Dictionary in expected.values():
		if not plot.has("remaining"):plot.remaining=0 if plot.kind.is_empty() else 1
	expect_same(loaded.state.crops,expected,"Both farmers' crops persisted with normalized harvest counts")

func available_field()->Vector2i:
	if failed:return Vector2i(-1,-1)
	var candidates:Array[Vector2i]=[]
	var current:=Vector2i(floori(person().x),floori(person().y))
	for y in range(26,43):
		for x in range(25,53):candidates.append(Vector2i(x,y))
	candidates.sort_custom(func(a:Vector2i,b:Vector2i):return current.distance_squared_to(a)<current.distance_squared_to(b))
	for center:Vector2i in candidates:
		var clear:=World.TILLER.SQUARE.all(func(offset):
			var tile:Vector2i=center+offset
			var key:=World.key(tile)
			return world.is_land(tile) and not world.water(tile) and not world.protected(tile) and world.resource(tile).is_empty() and not world.state.crops.has(key) and not world.state.objects.has(key) and not world.state.ground.has(key) and not world.state.roofs.has(key))
		if clear and not route(center,1.0).is_empty():return center
	expect(false,"Find a reachable patch of nine clear tiles")
	return Vector2i(-1,-1)

func till_pattern(center:Vector2i,mode:String,offsets:Array)->void:
	if failed:return
	walk_to(center,1.0)
	var crops_before:Dictionary=world.state.crops.duplicate(true)
	var bag_before:=bag().duplicate(true)
	act("hoe",center,mode)
	if failed:return
	for offset:Vector2i in offsets:
		crops_before[World.key(center+offset)]={"kind":"","growth":0.0,"wet":false,"owner":tok}
	expect_same(world.state.crops,crops_before,"Only the expected %d cells were tilled"%offsets.size())
	expect_same(bag(),bag_before,"A hand hoe does not consume fuel or materials")
	print("HAND_HOE_TIER id=%s tiles=%d mode=%s"%[World.gathering_tool_upgrade("hoe",bag()),offsets.size(),mode])

func verify_neighbor_field()->void:
	if failed:return
	var center:=available_field()
	if failed:return
	var shared_edge:=center+Vector2i.LEFT
	world.add_player(NEIGHBOR,"Neighbor")
	var person_nearby:Dictionary=world.state.players[NEIGHBOR]
	person_nearby.x=shared_edge.x+0.5
	person_nearby.y=shared_edge.y+0.5
	expect(world.act(NEIGHBOR,"neighbor-till","hoe",shared_edge).ok and world.act(NEIGHBOR,"neighbor-sow","seed",shared_edge,"radish").ok,"The second player's border crop is planted")
	if failed:return
	var before:Dictionary=world.state.crops.duplicate(true)
	refuse_deep("hoe",shared_edge,"spread","中央格需是可開墾的空地。","Do not apply a spread when aimed at someone else's crop")
	expect_same(world.state.crops,before,"Refused spread has no side effects")
	var open_offsets:Array=World.TILLER.SQUARE.filter(func(offset):return offset!=Vector2i.LEFT)
	till_pattern(center,"spread",open_offsets)
