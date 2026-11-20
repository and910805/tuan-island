extends "res://tests/test_mine_deep_journey.gd"

func persistence()->void:
	super.persistence()
	if failed:return
	# The earlier route commissioned the floors and built the furnace. Earn the
	# additional ore and quartz in the same world through the existing lifts.
	ride_to_mine_town()
	hoist(6)
	for strike_index in range(6):
		if int(bag().get("iron_ore",0))>=6:break
		strike(6,World.MINES.NODES[strike_index%World.MINES.NODES.size()],"pick")
	lift_up()
	hoist(10)
	for node:Vector2i in World.MINES.NODES:
		if int(bag().get("vein_quartz",0))>=2:break
		strike(10,node,"pick")
	expect(int(bag().get("iron_ore",0))>=6 and int(bag().get("vein_quartz",0))>=2,"B6 and B10 furnish the upgrade materials")
	lift_up()
	travel(World.TRANSIT.STATIONS.jinguashi.cell,"home")
	obtain_all({"copper_ore":4,"charcoal":5,"resin":1,"plank":2})
	if not failed:craft_and_try_tiers()

func craft_and_try_tiers()->void:
	if failed:return
	smelt_tier_metal("copper_ingot",2)
	smelt_tier_metal("iron_ingot",3)
	deep_craft("copper_pick")
	deep_craft("iron_pick")
	if failed:return
	expect(World.active_mining_pick(bag())=="iron_pick" and int(bag().get("copper_pick",0))==0,"Iron upgrade consumes the copper pick")
	verify_tier_at_b6("iron_pick",8.0,0.8)
	deep_craft("precision_pick")
	if failed:return
	expect(World.active_mining_pick(bag())=="precision_pick" and int(bag().get("iron_pick",0))==0,"Precision upgrade consumes the iron pick")
	verify_tier_at_b6("precision_pick",7.0,0.65)
	if failed:return
	var reloaded:=World.new()
	if not expect(reloaded.load_world(save_path) and not reloaded.recovered_from_backup,"The final pick loads from the main save"):return
	expect(World.active_mining_pick(reloaded.state.players[tok].inventory)=="precision_pick","The best pick is retained after a full save reload")

func smelt_tier_metal(item:String,batches:int)->void:
	if failed:return
	var name_in_game:String=World.NAMES[item]
	for batch in batches:
		furnace_queue(item,"開始加工："+name_in_game if batch==0 else "已排入加工：%s（共 %d 份）"%[name_in_game,batch+1])
	furnace_wait(float(World.INDUSTRY.PROCESS[item].time)*batches+0.1)
	for _batch in batches:furnace_claim(item)

func verify_tier_at_b6(pick:String,cooldown:float,energy_factor:float)->void:
	if failed:return
	ride_to_mine_town()
	hoist(6)
	act("mine_rest",World.MINES.REST)
	var node:Vector2i=World.MINES.NODES[0]
	var ready:=float(world.state.mine_depths.ready.get("mine_6",{}).get(World.key(node),0.0))
	if ready>now():wait(ready-now()+0.1)
	var before:=bag().duplicate(true)
	var energy:=World.MEAL_BUFF.energy(person())
	var started:=now()
	act("pick",node)
	if failed:return
	expect_delta(before,{"copper_ore":4,"iron_ore":1,"stone":1,"ochre_earth":1},"%s keeps B6 ore yield and vein finds"%pick)
	var due:=float(world.state.mine_depths.ready.mine_6[World.key(node)])
	expect(is_equal_approx(due-started,cooldown),"%s sets a %.0f second recovery"%[pick,cooldown])
	var spent:=energy-World.MEAL_BUFF.energy(person())
	expect(spent==roundi(World.MINES.energy_cost(6)*energy_factor),"%s spent %d energy after hazard and tier rounding"%[pick,spent])
	print("MINING_PICK_TIER id=%s ore=%d cooldown=%.1f energy=%d"%[pick,int(bag().get("copper_ore",0))-int(before.get("copper_ore",0)),due-started,spent])
	lift_up()
	travel(World.TRANSIT.STATIONS.jinguashi.cell,"home")
