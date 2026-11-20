extends "res://tests/test_tea_ceramics.gd"

func _initialize() -> void:
	world.add_player(ALPHA,"Alpha")
	world.state.chapter_one.shipped=true
	world.state.chapter_one.watered=true
	world.state.board=true
	world.state.picnic=true
	expect(act("tea_intro","home",Tea.RECEIVER).ok,"Read introduction")
	expect(act("tea_potter",Tea.YINGGE,Tea.POTTER).ok,"Get two clay")
	expect(act("tea_potter_story",Tea.YINGGE,Tea.POTTER).ok and not act("tea_potter_story",Tea.YINGGE,Tea.POTTER).ok,"Potter story records once")
	expect(act("tea_fire",Tea.YINGGE,Tea.KILN).ok and world.step(Tea.KILN_SECONDS,true) and act("tea_fire_take",Tea.YINGGE,Tea.KILN).ok,"Fire a new jar")
	expect(act("tea_discuss",Tea.MAOKONG,Tea.TEA_NPC).ok and not own().comparison_complete,"Initial discussion cannot complete comparison")
	var inputs:=["tea_jar","tea_returned_jar","tea_worn_jar"]
	var outputs:=["tea_returned_jar","tea_worn_jar","tea_spent_jar"]
	for index in range(3):
		expect(int(bag().get(inputs[index],0))==1,"Exactly one jar enters this cycle")
		prepare("jar")
		expect(own().outbound.return_item==outputs[index] and int(bag()[inputs[index]])==0,"Dispatch consumes current grade and assigns the next grade")
		expect(world.step(Tea.SHIPPING_SECONDS,true),"Let tea arrive")
		var coins:=int(world.state.players[ALPHA].coins)
		expect(act("tea_sell","home",Tea.RECEIVER).ok and int(world.state.players[ALPHA].coins)==coins+Tea.price_for("light","jar"),"Every grade receives the full tea price")
		expect(own().empty_items=={outputs[index]:1},"Settlement produces the exact empty grade")
		expect(act("tea_return","home",Tea.RECEIVER).ok and world.step(Tea.RETURN_SECONDS,true),"Empty jar reaches tea garden")
		expect(act("tea_reclaim",Tea.MAOKONG,Tea.PACKER).ok and int(bag()[outputs[index]])==1,"Recover the next grade")
		expect(not act("tea_reclaim",Tea.MAOKONG,Tea.PACKER).ok,"Return cannot be reclaimed twice")
	expect(not act("tea_discuss",Tea.MAOKONG,Tea.TEA_NPC).ok,"Jar trials and reclaim alone do not finish comparison")
	expect(act("tea_clay",Tea.YINGGE,Tea.CLAY).ok and bag().clay==1,"Acquire one unit for repair")
	expect(act("tea_repair",Tea.YINGGE,Tea.KILN).ok and bag().clay==0 and bag().tea_spent_jar==0 and own().kiln.repair,"Repair consumes spent jar and one clay")
	expect(not act("tea_fire_take",Tea.YINGGE,Tea.KILN).ok,"Repair is timed")
	expect(world.step(Tea.KILN_SECONDS,true) and act("tea_fire_take",Tea.YINGGE,Tea.KILN).ok and bag().tea_jar==1,"Repair restores a three-use jar")
	prepare("fiber")
	expect(not own().trials.fiber and not act("tea_discuss",Tea.MAOKONG,Tea.TEA_NPC).ok,"Shipping fiber does not record a completed trial")
	expect(world.step(Tea.SHIPPING_SECONDS,true) and act("tea_sell","home",Tea.RECEIVER).ok and own().trials.fiber and own().empty_items.is_empty(),"Fiber sale records its trial with no empties")
	expect(act("tea_discuss",Tea.MAOKONG,Tea.TEA_NPC).ok and own().comparison_complete and not act("tea_discuss",Tea.MAOKONG,Tea.TEA_NPC).ok,"Only two settled trials and a reclaim complete the comparison once")
	prepare("jar")
	expect(own().outbound.return_item=="tea_returned_jar","The repaired jar can start another three-use cycle")
	check_buckets()
	check_migration()
	print("TEA_CONTAINER_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func prepare(wrap:String) -> void:
	expect(act("tea_pick",Tea.MAOKONG,Tea.TEA_NODES[0]).ok,"Pick leaves for the batch")
	expect(act("tea_roast",Tea.MAOKONG,Tea.ROASTER,"light").ok and world.step(Tea.ROAST_SECONDS.light,true) and act("tea_take",Tea.MAOKONG,Tea.ROASTER).ok,"Roast and take a batch")
	expect(act("tea_pack",Tea.MAOKONG,Tea.PACKER,"light:"+wrap).ok and act("tea_ship",Tea.MAOKONG,Tea.PACKER).ok,"Pack and dispatch the batch")

func check_buckets() -> void:
	var record:Dictionary=world.state.tea_ceramics.players[ALPHA]
	record.returning={"count":2,"ready":world.state.time,"items":{"tea_worn_jar":1,"tea_spent_jar":1}}
	bag().tea_spent_jar=Tea.LIMIT
	expect(not act("tea_reclaim",Tea.MAOKONG,Tea.PACKER).ok and int(bag().get("tea_worn_jar",0))==0 and own().returning.count==2,"One overflowing grade preserves the entire return")
	bag().tea_spent_jar=0
	var path:=OS.get_environment("TEMP").path_join("missing-tea-container-save").path_join("world.json")
	world.save_path=path
	expect(not act("tea_reclaim",Tea.MAOKONG,Tea.PACKER).ok and int(bag().get("tea_worn_jar",0))==0 and own().returning.count==2,"Failed save preserves both grades")
	world.save_path=""
	expect(act("tea_reclaim",Tea.MAOKONG,Tea.PACKER).ok and bag().tea_worn_jar==1 and bag().tea_spent_jar==1,"Claim all mixed grades together")

func check_migration() -> void:
	var legacy:=world.state.duplicate(true)
	legacy.version=15;legacy.erase("public_kitchen")
	# Historical fixture predates the v25 flower chapter.
	legacy.erase("flower_nursery")
	legacy.regions.erase("tianwei")
	legacy.erase("salt_pan")
	legacy.regions.erase("beimen")
	var record:Dictionary=legacy.tea_ceramics.players[ALPHA]
	for field in ["empty_items","trials","tea_discussed","potter_story","comparison_complete"]:record.erase(field)
	record.empties=3
	record.returning={"count":4,"ready":world.state.time+5.0}
	record.kiln={"ready":world.state.time+5.0}
	record.packed={"style":"deep","wrap":"jar","reused_jar":false}
	record.outbound={"style":"light","wrap":"jar","reused_jar":true,"ready":world.state.time+5.0}
	expect(valid(legacy) and legacy.version==preload("res://scripts/save_schema.gd").VERSION,"Legacy v15 jobs migrate to current schema")
	expect(record.empty_items=={"tea_returned_jar":3} and record.returning.items=={"tea_returned_jar":4},"Migrated buckets preserve every empty and in-flight jar")
	expect(record.packed.return_item=="tea_returned_jar" and record.outbound.return_item=="tea_worn_jar" and not record.kiln.repair,"Legacy packed and outbound jars keep the proper grade")
	expect(record.trials=={"jar":false,"fiber":false} and not record.comparison_complete,"Old data cannot invent trial completion")
	record.returning.items.tea_returned_jar=3
	expect(not valid(legacy),"Reject aggregate and grade mismatch")
