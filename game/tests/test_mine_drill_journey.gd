extends "res://tests/test_waterworks_journey.gd"

const DRILL := Vector2i(28,24)
const FUEL_BELT := Vector2i(28,25)
const FUEL_BOX := Vector2i(28,26)
const DRILL_OUT_BELT := Vector2i(27,24)
const DRILL_OUT_BOX := Vector2i(26,24)
const EXTRA_SPRINKLER := Vector2i(52,25)
const EXTRA_FIELD := Vector2i(52,24)

func after_chapter() -> void:
	super.after_chapter()
	if failed:return
	prepare_drill_materials()
	if failed:return
	act("transit",World.REGIONS.exit_cell("home"),"jinguashi")
	act("mine_travel",World.MINES.ENTRY,"mine_1")
	for level in range(2,5):act("mine_travel",World.MINES.DOWN,"mine_%d"%level)
	build_clear(DRILL,"mine_drill")
	build_clear(FUEL_BOX,"private_chest")
	build_clear(DRILL_OUT_BOX,"private_chest")
	configure_belt(FUEL_BELT,0,"charcoal")
	configure_belt(DRILL_OUT_BELT,3,"copper_ore")
	for unit in range(2):act("deposit",FUEL_BOX,"charcoal")
	if failed:return
	checkpoint("mine-drill-before")
	act("mine_drill_toggle",DRILL)
	for tick in range(6):
		expect(world.step(World.LOGISTICS.INTERVAL,true),"Fuel conveyor advances on the world clock")
		if mine_object(DRILL).has("job"):break
	expect(mine_object(DRILL).has("job"),"Belt-fed charcoal starts the drill")
	if failed:return
	checkpoint("mine-drill-running")
	act("mine_travel",World.MINES.DOWN,"mine_5")
	for tick in range(44):
		expect(world.step(World.LOGISTICS.INTERVAL,true),"Unattended drilling and output belt advance")
		if int(mine_object(DRILL_OUT_BOX).items.get("copper_ore",0))==8:break
	expect(world.player_region(TOKEN)=="mine_5" and int(mine_object(DRILL_OUT_BOX).items.get("copper_ore",0))==8 and not mine_object(DRILL).has("job"),"Two automatic batches complete in floor four while the resident is in floor five")
	act("mine_travel",World.MINES.UP,"mine_4")
	if failed:return
	checkpoint("mine-drill-output")
	ship_drill_output()
	if failed:return
	walk_home(4)
	if failed:return
	checkpoint("mine-drill-home")
	for unit in range(4):act("deposit",WOOD_CHEST,"wood")
	for tick in range(48):
		expect(world.step(World.LOGISTICS.INTERVAL,true),"Home waterworks consumes the delivered ore via its intake belt")
		if output_count()==4:break
	expect(output_count()==4 and int(bag().get("copper_joint",0))==0,"The existing waterworks produces four joints from the drill shipment")
	for unit in range(2):act("withdraw",OUT_CHEST,"copper_joint")
	act("craft",BENCH,"sprinkler_kit")
	build_clear(EXTRA_SPRINKLER,"sprinkler")
	if world.resource(EXTRA_FIELD)=="grass":act("axe",EXTRA_FIELD)
	act("hoe",EXTRA_FIELD)
	act("seed",EXTRA_FIELD,"radish")
	act("toggle_sprinkler",EXTRA_SPRINKLER)
	if failed:return
	expect(world.step(World.INDUSTRY.INTERVAL,true) and world.state.crops[World.key(EXTRA_FIELD)].wet,"Two automated joints build a second irrigated expansion")
	checkpoint("mine-drill-expansion")
	var reopened := World.new()
	expect(reopened.load_world(world.save_path) and not reopened.recovered_from_backup,"Drill and downstream production reload from the primary save")
	if failed:return
	world=reopened
	expect(mine_object(DRILL).type=="mine_drill" and output_count()==2 and world.state.crops[World.key(EXTRA_FIELD)].wet,"Reload preserves the drill, two remaining joints and new irrigated field")
	checkpoint("mine-drill-reloaded")
	print("MINE_DRILL_NATURAL_LOOP actions=%d walking=%d no_fixture_grants=true accelerated_world_seconds=%.1f" % [actions,walking,world.state.time])

func ship_drill_output() -> void:
	for unit in range(8):act("withdraw",DRILL_OUT_BOX,"copper_ore")
	act("freight_load",World.MINES.SERVICE,"copper_ore:8")
	act("freight_target",World.MINES.SERVICE,World.key(ORE_CHEST))
	act("freight_dispatch",World.MINES.SERVICE)
	if failed:return
	checkpoint("mine-drill-freight")
	expect(world.step(DELIVERY_TIME,true),"World clock delivers the explicitly loaded consignment")
	expect(world.player_region(TOKEN)=="mine_4" and freight_job().get("status")=="delivered","The consignment arrives while the resident stays in floor four")

func prepare_drill_materials() -> void:
	act("transit",World.REGIONS.exit_cell("home"),"jinguashi")
	for pass_index in range(3):
		for node: Vector2i in World.JINGUASHI.NODES:act("pick",node)
		if pass_index<2:expect(world.step(World.JINGUASHI.COOLDOWN,true),"Surface copper replenishes on the normal clock")
	act("transit",World.REGIONS.exit_cell("jinguashi"),"home")
	gather("wood","tree","axe",115,3)
	gather("stone","rock","pick",24,2)
	for batch in range(9):mill_batch(MILL)
	act("start_processing",KILN,"charcoal")
	expect(world.step(World.INDUSTRY.PROCESS.charcoal.time,true),"Existing charcoal kiln produces drill fuel")
	act("claim_processing",KILN)
	for unit in range(13):act("craft",BENCH,"copper_joint")
	act("craft",BENCH,"mine_drill_kit")
	act("craft",BENCH,"conveyor_kit")

func mine_object(cell: Vector2i) -> Dictionary:
	return world.state.regions.mine_4.objects.get(World.key(cell),{})
