extends "res://tests/test_chapter_journey.gd"

const Tea=World.TEA_CERAMICS

func _initialize() -> void:
	var path:=OS.get_environment("TEMP").path_join("tea-journey-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	world.save_path=path
	world.add_player(TOKEN,"Tea Journey")
	world.state.chapter_one.shipped=true
	world.state.chapter_one.watered=true
	world.state.board=true
	world.state.picnic=true
	run_tea_route()
	for file in [path,path+".bak"]:
		if FileAccess.file_exists(file):DirAccess.remove_absolute(file)
	print("TEA_CERAMICS_JOURNEY checks=%d failures=%d actions=%d walking=%d chapter_one_fixture=true tea_items_fixture=false manual_teleport=false"%[checks,failures,actions,walking])
	quit(int(failed))

func travel(gate:String,destination:String) -> void:
	if failed:return
	var source:=world.player_region(TOKEN)
	act("transit",World.TRANSIT.points(source)[gate].cell,destination)
	expect(world.player_region(TOKEN)==destination,"Arrive through "+destination)

func own() -> Dictionary:
	return Tea.own_record(world.state,TOKEN)

func run_tea_route() -> void:
	checkpoint("start")
	act("tea_intro",Tea.RECEIVER)
	travel("ferry","toucheng")
	travel("rail","ruifang")
	travel("rail",Tea.MAOKONG)
	travel("transfer",Tea.YINGGE)
	act("tea_potter",Tea.POTTER)
	act("tea_fire",Tea.KILN)
	expect(world.step(Tea.KILN_SECONDS,true),"Let the fired jar finish")
	act("tea_fire_take",Tea.KILN)
	expect(int(bag().get("tea_jar",0))==1,"The only jar was produced by this journey")
	checkpoint("fired")
	travel("transfer",Tea.MAOKONG)
	sell_batch("light")
	expect(own().empties==1 and own().reuse_count==0,"First sale produces one empty jar")
	act("tea_return",Tea.RECEIVER)
	checkpoint("manual-return")
	travel("ferry",Tea.MAOKONG)
	expect(world.step(Tea.RETURN_SECONDS,true),"Allow first return to arrive")
	act("tea_reclaim",Tea.PACKER)
	expect(int(bag().get("tea_returned_jar",0))==1,"Collect the same jar on the return leg")
	travel("transfer","home")
	act("tea_auto",Tea.RECEIVER,"on")
	travel("ferry",Tea.MAOKONG)
	sell_batch("deep")
	expect(own().reuse_count==1 and own().returning.get("count",0)==1 and own().empties==0,"Second sale uses the returned jar and schedules it automatically")
	checkpoint("automatic-return")
	if failed:return

	var reopened:=World.new()
	expect(reopened.load_world(world.save_path) and not reopened.recovered_from_backup,"Load the primary save while return is in flight")
	if failed:return
	world=reopened
	expect(world.player_region(TOKEN)=="home" and own().reuse_count==1 and own().auto and own().returning.get("count",0)==1,"Auto return survives reload")
	var before:=world.state.duplicate(true)
	actions+=1
	expect(not world.act(TOKEN,"journey-%d"%actions,"tea_sell",Tea.RECEIVER).ok and world.state==before,"Reopening does not permit duplicate settlement")
	travel("ferry",Tea.MAOKONG)
	expect(world.step(Tea.RETURN_SECONDS,true),"Wait for the reloaded automatic return")
	act("tea_reclaim",Tea.PACKER)
	expect(int(bag().get("tea_worn_jar",0))==1 and own().returning.is_empty(),"Second return delivers exactly one worn jar")
	checkpoint("complete")

func sell_batch(style:String) -> void:
	act("tea_pick",Tea.TEA_NODES[0])
	act("tea_roast",Tea.ROASTER,style)
	expect(world.step(Tea.ROAST_SECONDS[style],true),"Let the roast finish")
	act("tea_take",Tea.ROASTER)
	act("tea_pack",Tea.PACKER,style+":jar")
	act("tea_ship",Tea.PACKER)
	travel("transfer","home")
	expect(world.step(Tea.SHIPPING_SECONDS,true),"Let the tea shipment reach the ferry")
	var before:=int(person().coins)
	act("tea_sell",Tea.RECEIVER)
	expect(int(person().coins)==before+Tea.price_for(style,"jar"),"Settlement matches the selected roast and wrapping")
