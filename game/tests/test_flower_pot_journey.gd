extends "res://tests/test_chapter_journey.gd"
## From the earned chapter-one unlock, take ordinary transit to Yingge,
## barter for clay, fire a pot, and return it to the home island.

const Tea=World.TEA_CERAMICS
func held(item:String)->int:
	return int(bag().get(item,0))

func travel(gate:String,destination:String)->void:
	if failed:return
	var source:=world.player_region(TOKEN)
	act("transit",World.TRANSIT.points(source)[gate].cell,destination)
	expect(world.player_region(TOKEN)==destination,"arrived in "+destination)

func after_chapter()->void:
	super.after_chapter()
	if failed:return
	if held("stone")<4:
		var rock:=find_resource("rock")
		expect(rock.x>=0,"reachable stone for pottery exchange")
		if failed:return
		act("pick",rock)
		act("pick",rock)
	act("tea_intro",Tea.RECEIVER)
	travel("ferry","toucheng")
	travel("rail","ruifang")
	travel("rail",Tea.MAOKONG)
	travel("transfer",Tea.YINGGE)
	act("tea_potter",Tea.POTTER)
	act("tea_clay",Tea.CLAY)
	expect(world.step(Tea.COOLDOWN,true),"wait for the clay counter to restock")
	act("tea_clay",Tea.CLAY)
	expect(held("clay")==Tea.POT_CLAY,"potter gift and two exchanges yield four clay")
	act("tea_fire_pot",Tea.KILN)
	expect(held("clay")==0,"firing spends all four clay")
	expect(world.step(Tea.POT_SECONDS,true),"advance the kiln by sixty world seconds")
	act("tea_fire_take",Tea.KILN)
	expect(held("flower_pot")==1,"collect one finished pot")
	travel("transfer",Tea.MAOKONG)
	travel("transfer","home")
	var site:=Vector2i(-1,-1)
	for candidate in [Vector2i(41,35),Vector2i(41,36),Vector2i(42,36),Vector2i(43,36)]:
		var key:=World.key(candidate)
		if not world.protected(candidate) and world.resource(candidate).is_empty() and not world.state.crops.has(key) and not world.state.objects.has(key) and not world.state.ground.has(key):
			site=candidate
			break
	expect(site.x>=0,"find an empty home tile beside the farm")
	if failed:return
	act("build",site,"flower_pot")
	expect(held("flower_pot")==0 and world.state.objects.get(World.key(site),{}).get("type")=="flower_pot","place the earned pot at home")
	if failed:return
	var reopened:=World.new()
	var loaded:=reopened.load_world(world.save_path) and not reopened.recovered_from_backup
	expect(loaded,"reload the primary save after placement")
	if loaded:
		expect(reopened.state.objects.get(World.key(site),{}).get("type")=="flower_pot","placed pot persists at the same tile")
		expect(reopened.blocked(site),"placed pot has collision after reload")
	print("FLOWER_POT_JOURNEY checks=%d failures=%d"%[checks,failures])
