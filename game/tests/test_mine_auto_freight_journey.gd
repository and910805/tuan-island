extends "res://tests/test_mine_drill_journey.gd"

func ship_drill_output() -> void:
	var service: Vector2i = World.MINES.SERVICE
	var rule := {"source":World.key(DRILL_OUT_BOX),"target":World.key(ORE_CHEST),"item":"copper_ore","reserve":0,"batch":4}
	var copper_in_bag := int(bag().get("copper_ore",0))
	act("mine_auto_config",service,JSON.stringify(rule))
	expect(not own_route().enabled and int(own_route().batch)==4,"Saved route starts disabled with a four-ore batch")
	checkpoint("mine-auto-freight-configured")
	act("mine_auto_toggle",service)
	expect(own_route().enabled and drill_ore_count()==8,"Enabling the route keeps both batches in the mine chest until the world ticks")
	checkpoint("mine-auto-freight-enabled")
	act("mine_travel",World.MINES.DOWN,"mine_5")
	expect(world.step(World.LOGISTICS.INTERVAL,true),"Clock advances the enabled route while resident is on another floor")
	expect(freight_job().get("status")=="transit" and drill_ore_count()==4 and home_ore_count()==0,"First batch automatically reserves exactly four units without crediting the destination early")
	checkpoint("mine-auto-freight-first")
	expect(world.step(DELIVERY_TIME,true),"World clock completes the first automated shipment")
	expect(freight_job().get("status")=="transit" and drill_ore_count()==0 and home_ore_count()==4,"First delivery frees the single freight slot and the next batch dispatches automatically")
	checkpoint("mine-auto-freight-second")
	expect(world.step(DELIVERY_TIME,true),"World clock completes the second automated shipment")
	expect(world.player_region(TOKEN)=="mine_5" and freight_job().get("status")=="delivered" and home_ore_count()+belt_ore_count()==8,"Both automatic consignments reach the home intake while resident stays underground")
	expect(int(bag().get("copper_ore",0))==copper_in_bag,"Automatic shipping never debits or credits the resident inventory")
	checkpoint("mine-auto-freight-delivered")
	act("mine_travel",World.MINES.UP,"mine_4")

func after_chapter() -> void:
	super.after_chapter()
	if failed:return
	expect(own_route().enabled and own_route().region=="mine_4" and int(own_route().batch)==4 and int(own_route().reserve)==0,"Primary save preserves the enabled route and batch settings after downstream irrigation")
	expect(drill_ore_count()==0 and freight_job().get("status")=="delivered","Reload preserves the source debit and final delivered receipt")
	checkpoint("mine-auto-freight-reloaded")
	print("MINE_AUTO_FREIGHT_NATURAL_LOOP actions=%d walking=%d no_fixture_grants=true accelerated_world_seconds=%.1f" % [actions,walking,world.state.time])

func own_route() -> Dictionary:
	return world.state.mine_auto_freight.routes.get(TOKEN,{})

func drill_ore_count() -> int:
	return int(mine_object(DRILL_OUT_BOX).items.get("copper_ore",0))

func home_ore_count() -> int:
	return int(world.state.objects[World.key(ORE_CHEST)].items.get("copper_ore",0))

func belt_ore_count() -> int:
	return int(world.state.objects[World.key(ORE_BELT)].items.get("copper_ore",0)) + int(workbench().input.get("copper_ore",0))
