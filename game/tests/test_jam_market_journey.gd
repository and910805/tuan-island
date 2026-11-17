extends "res://tests/test_bakery_journey.gd"
## Earn the ingredients and equipment, then fulfil the rotating market order.

const JAM_ORDER:="market_jam"
const BOARD_CELL:=Vector2i(40,29)

func after_chapter()->void:
	super.after_chapter()
	if failed:return
	var price:=int(World.CROPS.strawberry.seed_price)*2+int(World.CROPS.sugar_beet.seed_price)*2
	bk_ensure_coins(price)
	for crop:String in ["strawberry","sugar_beet"]:
		var count:=2
		bk_buy(crop,count)
		bk_harvest(bk_sow(crop,count),"grow market jam ingredients")
	if failed:return
	bk_run("queue_cook",stove,"sugar")
	bk_step(float(World.RECIPES.sugar.time),"cook beet sugar")
	bk_run("claim_cook",stove)
	# The market regression starts at the end of the bakery route. Prefund
	# clay from the separate Yingge route, then manufacture the copper here.
	bag()["clay"]=10
	bk_gather("stone",33,["rock"])
	bk_gather("wood",8,["tree"])
	while held("copper_ore")<9 and not failed:
		bk_step(maxf(0.0,float(world.state.copper.ready)-float(world.state.time)),"restock copper")
		bk_run("mine_copper",World.COPPER_CELL)
	var occupied:=bk_reserved()
	var furnace:=hoe_cell(occupied)
	while furnace.x>=0 and not World.INDUSTRY.SMELTER_CELLS.all(func(offset):return free_cell(furnace+offset)):
		occupied[furnace]=true
		furnace=hoe_cell(occupied)
	expect(furnace.x>=0,"open area for a small smelter")
	if failed:return
	bk_run("build",furnace,"small_smelter")
	bk_craft("kiln_kit",1)
	var kiln:=hoe_cell(bk_reserved())
	expect(kiln.x>=0,"open tile for the charcoal kiln")
	if failed:return
	bk_run("build",kiln,"charcoal_kiln")
	bk_run("queue_processing",kiln,"charcoal")
	bk_step(16.0,"make fuel for both copper batches")
	bk_run("claim_processing",kiln)
	for batch in range(2):bk_run("queue_processing",furnace,"copper_ingot")
	bk_step(90.0,"smelt the four copper ingots")
	for batch in range(2):bk_run("claim_processing",furnace)
	expect(held("copper_ingot")==4,"copper comes from the rebuilt equipment chain")
	var site:=hoe_cell(bk_reserved())
	expect(site.x>=0,"open tile for a jam pot")
	if failed:return
	bk_run("build",site,"jam_pot")
	var catalog=World.ORDER_CATALOG
	var offered:=false
	for day in range(14):
		var context:Dictionary=catalog.context_from_world(world,TOKEN)
		if JAM_ORDER in catalog.candidate_ids(context.day,context):
			offered=true
			break
		bk_step(World.Village.DAY,"wait for market order rotation")
	expect(offered and held("strawberry_jam")==0,"owned pot and ingredients offer the order before cooking")
	bk_run("order_accept",BOARD_CELL,JAM_ORDER)
	bk_run("queue_processing",site,"strawberry_jam")
	expect(held("strawberry")==1 and held("sugar")==1,"pot consumes three of four berries and one of two sugar")
	bk_step(180.0,"preserve berries in the jam pot")
	bk_run("claim_processing",site)
	expect(held("strawberry_jam")==2,"pot produces two jars")
	var before:=int(person().coins)
	bk_run("order",BOARD_CELL,JAM_ORDER)
	expect(int(person().coins)==before+135 and held("strawberry_jam")==0,"delivery exchanges two jars for 135 coins")
	bk_probe("order",BOARD_CELL,JAM_ORDER,"repeat jam delivery")
	if failed:return
	var reopened:=World.new()
	var loaded:=reopened.load_world(world.save_path) and not reopened.recovered_from_backup
	expect(loaded,"reload market delivery from primary save")
	if loaded:
		var player:Dictionary=reopened.state.players[TOKEN]
		expect(JAM_ORDER in player.orders.done and player.coins==before+135,"reloaded completion and reward agree")
	print("JAM_MARKET_JOURNEY checks=%d failures=%d"%[checks,failures])
