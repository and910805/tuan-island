extends "res://tests/test_mining_pick_tiers_journey.gd"

const RIVER:=Vector2i(55,20)

func craft_and_try_tiers()->void:
	if failed:return
	obtain_all({"wood":3,"fiber":2})
	smelt_tier_metal("copper_ingot",2)
	smelt_tier_metal("iron_ingot",3)
	deep_craft("copper_rod")
	try_rod("copper_rod",2.6,0.26,false)
	deep_craft("iron_rod")
	try_rod("iron_rod",2.2,0.30,true)
	deep_craft("precision_rod")
	try_rod("precision_rod",1.8,0.34,true)
	try_rod("precision_rod",1.8,0.34,false)
	if failed:return
	var reloaded:=World.new()
	if not expect(reloaded.load_world(save_path) and not reloaded.recovered_from_backup,"Load the earned fishing rod and collection from the primary save"):return
	var restored:Dictionary=reloaded.state.players[tok]
	expect(World.gathering_tool_upgrade("fish",restored.inventory)=="precision_rod" and restored.fish_caught==person().fish_caught,"The upgraded rod and catches survive reload")

func try_rod(id:String,wait_time:float,width:float,standard:bool)->void:
	if failed:return
	var original_count:=int(person().fish_caught)
	var started:=now()
	act("fish_start",RIVER,"standard" if standard else "")
	if failed:return
	var cast:Dictionary=person().fishing
	expect(cast.get("rod")==id and is_equal_approx(float(cast.ready)-started,wait_time),"The cast uses the best carried rod and its shorter bite timer")
	expect(is_equal_approx(World.FishingTracking.band_half_width(cast),width) and cast.has("band")==standard,"The wider band applies only to the chosen tracking mode")
	if id=="precision_rod" and standard:
		var resume:=World.new()
		if not expect(resume.load_world(save_path) and not resume.recovered_from_backup,"An active upgraded cast is accepted by the save schema"):return
		var restored:Dictionary=resume.state.players[tok].get("fishing",{})
		expect(restored.get("rod")==id and is_equal_approx(float(restored.get("ready",-1)),float(cast.ready)),"The primary save preserves the cast tier and bite deadline")
	refuse_deep("fish_catch",RIVER,"","魚還沒咬鉤，再稍等一下","A better rod still cannot catch before a bite")
	wait(wait_time+0.01)
	act("fish_catch",RIVER)
	if standard:
		expect(int(person().fish_caught)==original_count and person().has("fishing"),"The standard mode still needs tracking before it awards a fish")
		for _attempt in range(12):
			if failed or not person().has("fishing"):break
			wait(0.8)
			act("fish_catch",RIVER)
	expect(not person().has("fishing") and int(person().fish_caught)==original_count+1,"The cast awards exactly one actual catch")
	print("FISHING_ROD_TIER rod=%s bite=%.1f band=%.2f standard=%s"%[id,wait_time,width,standard])
