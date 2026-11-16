extends "res://tests/test_bakery_journey.gd"
## Pays for seeds with earned coins, grows the ingredients, and gives the
## resulting toast to Xiaoli through normal World actions.

func after_chapter()->void:
	super.after_chapter()
	if failed:return
	var price:=0
	for crop in ["strawberry","sugar_beet","wheat"]:
		var count:=2 if crop=="sugar_beet" else 1
		price+=maxi(0,count-held(crop+"_seed"))*int(World.CROPS[crop].seed_price)
	bk_ensure_coins(price)
	for crop:String in ["strawberry","sugar_beet","wheat"]:
		var count:=2 if crop=="sugar_beet" else 1
		bk_buy(crop,count)
		var plots:=bk_sow(crop,count)
		bk_harvest(plots,"grow toast ingredients")
	if failed:return
	cook_and_claim("sugar",2)
	cook_and_claim("strawberry_jam",2)
	cook_and_claim("bread",1)
	cook_and_claim("strawberry_toast",2)
	if failed:return
	var before:=World.RESIDENT_BOND.points(person(),"xiaoli")
	var stall:Vector2i=World.bond_place(world.state,"xiaoli")[1]
	bk_run("resident_gift",stall,"xiaoli:strawberry_toast")
	expect(held("strawberry_toast")==1 and World.RESIDENT_BOND.points(person(),"xiaoli")==before+3,"Xiaoli receives one favourite gift")
	var reopened:=World.new()
	var loaded:=reopened.load_world(world.save_path) and not reopened.recovered_from_backup
	expect(loaded,"reload primary save after the gift")
	if loaded:
		var player:Dictionary=reopened.state.players[TOKEN]
		expect(player.inventory.strawberry_toast==1 and player.collection.meals.has("strawberry_toast"),"save retains the remaining portion and recipe discovery")
		expect(World.RESIDENT_BOND.points(player,"xiaoli")==before+3,"save retains Xiaoli's gained affinity")
	print("STRAWBERRY_TOAST_JOURNEY checks=%d failures=%d"%[checks,failures])

func cook_and_claim(recipe:String,amount:int)->void:
	if failed:return
	var before:=held(recipe)
	bk_run("queue_cook",stove,recipe)
	bk_step(float(World.RECIPES[recipe].time),"cook "+recipe)
	bk_run("claim_cook",stove)
	expect(held(recipe)==before+amount,"claim the expected amount of "+recipe)
