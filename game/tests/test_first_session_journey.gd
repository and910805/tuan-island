extends "res://tests/test_tea_ceramics_journey.gd"

var rejoined_reloads := 0

func _initialize() -> void:
	run_chapter_journey()

func after_chapter() -> void:
	expect(World.CHAPTER_ONE.phase(world.state)=="complete", "Fresh-save chapter completed before tea")
	resume_from_chapter_save()
	if failed:return
	run_tea_route()
	if failed:return
	# Complete the final delivery using the worn jar obtained from the preceding route.
	sell_batch("light")
	expect(own().reuse_count==2 and own().returning.get("count",0)==1,"Third jar delivery automatically returns a spent jar")
	travel("ferry",Tea.MAOKONG)
	expect(world.step(Tea.RETURN_SECONDS,true),"Wait for spent jar return")
	act("tea_reclaim",Tea.PACKER)
	expect(int(bag().get("tea_spent_jar",0))==1,"Third returned jar is spent")
	# A real fiber delivery supplies the other comparison, with no material grants.
	if int(bag().get("fiber",0))<1:
		travel("transfer","home")
		var tree:=find_resource("tree")
		expect(tree!=Vector2i(-1,-1),"Reachable tree for fiber")
		for hit in range(3):act("axe",tree)
		travel("ferry",Tea.MAOKONG)
	act("tea_pick",Tea.TEA_NODES[0])
	act("tea_roast",Tea.ROASTER,"deep")
	expect(world.step(Tea.ROAST_SECONDS.deep,true),"Wait for fiber batch roast")
	act("tea_take",Tea.ROASTER)
	act("tea_pack",Tea.PACKER,"deep:fiber")
	act("tea_ship",Tea.PACKER)
	travel("transfer","home")
	expect(world.step(Tea.SHIPPING_SECONDS,true),"Wait for fiber delivery")
	if failed:return
	var coins_before_fiber:=int(person().coins)
	act("tea_sell",Tea.RECEIVER)
	expect(int(person().coins)==coins_before_fiber+Tea.price_for("deep","fiber"),"Fiber settlement matches Tea.price_for(deep, fiber)")
	travel("ferry",Tea.MAOKONG)
	act("tea_discuss",Tea.TEA_NPC)
	expect(own().comparison_complete and own().trials.jar and own().trials.fiber,"Host comparison follows two actual delivery types and reclaim")
	# Exchange naturally gathered stone for repair clay.
	if int(bag().get("stone",0))<2:
		travel("transfer","home")
		while int(bag().get("stone",0))<2 and not failed:
			var rock:=find_resource("rock")
			expect(rock!=Vector2i(-1,-1),"Reachable rock for repair clay")
			if failed:return
			for hit in range(2):act("pick",rock)
		travel("ferry",Tea.MAOKONG)
	travel("transfer",Tea.YINGGE)
	act("tea_potter_story",Tea.POTTER)
	act("tea_clay",Tea.CLAY)
	if failed:return
	# Start the repair and verify exactly what it consumed and scheduled.
	var inventory_before_repair:Dictionary=bag().duplicate(true)
	var repair_started:=float(world.state.time)
	act("tea_repair",Tea.KILN)
	if failed:return
	var expected_inventory:=inventory_before_repair.duplicate(true)
	expected_inventory.clay=int(expected_inventory.get("clay",0))-1
	expected_inventory.tea_spent_jar=int(expected_inventory.get("tea_spent_jar",0))-1
	expect(int(inventory_before_repair.get("clay",0))>=1 and int(inventory_before_repair.get("tea_spent_jar",0))==1,"Repair prerequisites were earned before firing")
	expect(same(bag(),expected_inventory),"Repair consumes exactly one clay and one spent jar")
	expect(own().kiln.size()==2 and own().kiln.get("repair",false)==true and is_equal_approx(float(own().kiln.get("ready",-1.0)),repair_started+Tea.KILN_SECONDS),"Repair job is flagged with the kiln deadline")
	# Reload while the repair is still in the kiln, then finish on the loaded world.
	if not reload_and_rejoin("repair-in-kiln"):return
	expect(int(bag().get("tea_spent_jar",0))==0 and own().kiln.get("repair",false)==true and is_equal_approx(float(own().kiln.get("ready",-1.0)),repair_started+Tea.KILN_SECONDS),"Repair job and consumed resources survive reload")
	expect(world.step(Tea.KILN_SECONDS,true),"Wait for repair firing")
	act("tea_fire_take",Tea.KILN)
	expect(int(bag().get("tea_jar",0))==1 and int(bag().get("tea_spent_jar",0))==0 and own().kiln.is_empty(),"Repair restores one fresh jar")
	if failed:return
	if not reload_and_rejoin("after-repair"):return
	expect(own().kiln.is_empty() and int(bag().get("tea_spent_jar",0))==0 and int(bag().get("tea_jar",0))==1,"Reloaded kiln is empty with the repaired jar and no spent jar")
	expect(World.CHAPTER_ONE.phase(world.state)=="complete" and own().comparison_complete and own().potter_story,"Chapter, comparison and story survive reload")
	print("FIRST_SESSION_JOURNEY checks=%d failures=%d actions=%d walk_tiles=%d simulated_world_seconds=%.1f rejoined_reloads=%d scripted_world_api=true accelerated_waits=true"%[checks,failures,actions,walking,world.state.time,rejoined_reloads])

# Reload the persisted chapter-complete world and continue the tea route on it.
func resume_from_chapter_save() -> void:
	if not reload_and_rejoin("chapter-complete"):return
	expect(world.regional_tokens().has(TOKEN),"Rejoined player is active in their region")
	var tea_items:=bag().keys().filter(func(item): return str(item).begins_with("tea_") or str(item)=="clay")
	expect(World.CHAPTER_ONE.phase(world.state)=="complete" and own()==Tea.FRESH and tea_items.is_empty(),"Loaded chapter save has no tea progress before the tea route")

# Loads the primary save into a new World, re-registers the same player and switches
# the journey onto it only if every prerequisite holds. Returns false on failure.
func reload_and_rejoin(label:String) -> bool:
	if failed:return false
	expect(FileAccess.file_exists(world.save_path),label+": primary save exists")
	if failed:return false
	var expected_player:Dictionary=person().duplicate(true)
	var expected_tea:=own()
	var expected_chapter:=[world.state.chapter_one,world.state.board,world.state.picnic]
	var reopened:=World.new()
	expect(reopened.load_world(world.save_path) and not reopened.recovered_from_backup,label+": reload primary save")
	if failed:return false
	expect(reopened.state.get("players",{}).has(TOKEN) and reopened.state.has("tea_ceramics"),label+": saved world contains the journey player")
	if failed:return false
	reopened.add_player(TOKEN,str(expected_player.name))
	expect(reopened.active_tokens.has(TOKEN),label+": same player re-registered")
	var loaded:Dictionary=reopened.state.players[TOKEN]
	for field in ["region","x","y","coins","inventory","receipts"]:
		expect(same(loaded.get(field),expected_player.get(field)),label+": "+field+" preserved (no grants or teleport)")
	expect(same(Tea.own_record(reopened.state,TOKEN),expected_tea),label+": tea progress preserved")
	expect(same([reopened.state.chapter_one,reopened.state.board,reopened.state.picnic],expected_chapter),label+": chapter flags preserved")
	if failed:return false
	world=reopened
	rejoined_reloads+=1
	return true

# JSON round-trip both sides so int/float differences from save parsing do not matter.
func same(a:Variant,b:Variant) -> bool:
	return JSON.parse_string(JSON.stringify(a))==JSON.parse_string(JSON.stringify(b))
