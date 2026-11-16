extends "res://tests/test_history_journey.gd"

func after_chapter() -> void:
	super.after_chapter()
	if failed:return
	act("travel",World.REGIONS.exit_cell("lanyang"),"home")
	var bench:=Vector2i(40,35)
	gather("wood","tree","axe",10,3)
	gather("stone","rock","pick",4,2)
	gather("fiber","grass","axe",2,1)
	act("craft",bench,"reinforced_pick")
	checkpoint("departure")
	var before:int=bag().get("copper_ore",0)
	var coins:int=person().coins
	first_mountain_trip()
	expect(world.player_region(TOKEN)=="jinguashi" and person().coins==coins,"First mountain route preserves money and inventory")
	checkpoint("arrival")
	for node:Vector2i in World.JINGUASHI.NODES:
		act("pick",node)
	expect(int(bag().copper_ore)==before+World.JINGUASHI.NODES.size()*World.JINGUASHI.YIELD,"Walking to all three work faces yields real copper")
	checkpoint("mined")
	var saved:=World.new()
	expect(saved.load_world(world.save_path) and saved.player_region(TOKEN)=="jinguashi" and saved.state.players[TOKEN].inventory.copper_ore==bag().copper_ore,"Reload in mountain retains ore and position")
	act("transit",World.REGIONS.exit_cell("jinguashi"),"home")
	var joint:int=bag().get("copper_joint",0)
	act("craft",bench,"copper_joint")
	expect(int(bag().copper_joint)==joint+1 and int(bag().copper_ore)==before+World.JINGUASHI.NODES.size()*World.JINGUASHI.YIELD-2,"Mountain ore becomes useful copper joint at original bench")
	checkpoint("crafted")
	var reload:=World.new()
	expect(reload.load_world(world.save_path) and reload.player_region(TOKEN)=="home" and reload.state.players[TOKEN].inventory==bag() and reload.state.history_memory.plaque and reload.state.lanyang_life.repaired,"Full old farming, forestry, history and new mining loop persist together")
	print("JINGUASHI_NATURAL_LOOP actions=%d walking=%d no_fixture_grants=true accelerated_world_seconds=%.1f"%[actions,walking,world.state.time])

func first_mountain_trip() -> void:
	for leg in [["home","ferry","toucheng"],["toucheng","rail","ruifang"],["ruifang","bus","jiufen"],["jiufen","shuttle","jinguashi"]]:
		act("transit",World.TRANSIT.points(leg[0])[leg[1]].cell,leg[2])
