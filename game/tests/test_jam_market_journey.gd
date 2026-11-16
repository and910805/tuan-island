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
	bk_gather("stone",8,["rock"])
	bk_gather("wood",1,["tree"])
	bk_step(maxf(0.0,float(world.state.copper.ready)-float(world.state.time)),"restock copper")
	bk_run("mine_copper",World.COPPER_CELL)
	bk_craft("copper_joint",1)
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
