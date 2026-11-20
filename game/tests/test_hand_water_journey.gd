extends "res://tests/test_hand_hoe_journey.gd"

func craft_and_try_tiers()->void:
	if failed:return
	obtain_all({"resin":1,"fiber":2})
	smelt_tier_metal("copper_ingot",2)
	smelt_tier_metal("iron_ingot",3)
	deep_craft("copper_can")
	var center:=plant_pattern(World.TILLER.ROW+[Vector2i(-1,-1)])
	if failed:return
	var corner:=center+Vector2i(-1,-1)
	var before:Dictionary=world.state.crops.duplicate(true)
	act("water",corner)
	if failed:return
	verify_wet_cells(before,[World.key(corner)])
	water_pattern(center,World.TILLER.ROW)
	deep_craft("iron_can")
	water_pattern(plant_pattern(World.TILLER.CROSS),World.TILLER.CROSS)
	deep_craft("precision_can")
	fund_final_field()
	center=plant_pattern(World.TILLER.SQUARE)
	water_pattern(center,World.TILLER.SQUARE)
	refuse_deep("water",center,"spread","請對可澆水的作物使用，範圍內需有乾燥作物。","A second pass over the wet field earns no care")
	if failed:return
	var loaded:=World.new()
	if not expect(loaded.load_world(save_path) and not loaded.recovered_from_backup,"Read the upgraded watering can from the primary save"):return
	var restored:Dictionary=loaded.state.players[tok]
	expect(World.gathering_tool_upgrade("water",restored.inventory)=="precision_can","The last watering can survives reload")
	expect(restored.get("crop_care",0)==person().get("crop_care",0) and bool(loaded.state.crops[World.key(center)].wet),"Wet soil and the earned care count survive reload")

func plant_pattern(offsets:Array)->Vector2i:
	if failed:return Vector2i(-1,-1)
	while int(bag().get("radish_seed",0))<offsets.size() and not failed:
		act("buy",World.Village.NPCS.xiaoli.cell,"radish")
	var center:=available_field()
	if failed:return center
	for offset:Vector2i in offsets:
		var tile:=center+offset
		act("hoe",tile)
		act("seed",tile,"radish")
	return center

func fund_final_field()->void:
	if failed:return
	var cost:=maxi(0,9-int(bag().get("radish_seed",0)))*int(World.CROPS.radish.seed_price)
	if int(person().coins)>=cost:return
	wait(float(World.CROPS.radish.time)+0.1)
	for tile:String in world.state.crops.keys():
		if failed or int(person().coins)>=cost:break
		var crop:Dictionary=world.state.crops[tile]
		if crop.owner!=tok or crop.kind!="radish" or float(crop.growth)<float(World.CROPS.radish.time):continue
		act("harvest",World.cell(tile))
		act("sell",World.Village.NPCS.xiaoli.cell,"radish")
	expect(int(person().coins)>=cost,"Selling the crop watered with the earlier tools funds the final seeds")

func water_pattern(center:Vector2i,offsets:Array)->void:
	if failed:return
	walk_to(center,1.0)
	var before:Dictionary=world.state.crops.duplicate(true)
	var inventory_before:=bag().duplicate(true)
	var care_before:=int(person().get("crop_care",0))
	act("water",center,"spread")
	if failed:return
	var keys:Array=offsets.map(func(offset):return World.key(center+offset))
	verify_wet_cells(before,keys)
	expect(int(person().get("crop_care",0))==mini(World.CROP_CATALOG.CARE_TARGET,care_before+keys.size()),"Hand watering reuses the crop care cap")
	expect_same(bag(),inventory_before,"Watering has no fuel or material charge")
	print("HAND_WATER_TIER id=%s tiles=%d"%[World.gathering_tool_upgrade("water",bag()),keys.size()])

func verify_wet_cells(before:Dictionary,expected:Array)->void:
	var changed:Array=[]
	for tile:String in world.state.crops:
		if world.state.crops[tile].wet!=before[tile].wet:changed.append(tile)
	changed.sort()
	expected.sort()
	expect_same(changed,expected,"Only the intended crop cells were watered")
