extends SceneTree
## T093: four three-delivery runs through the actual tea and pottery actions.
## Unlocks and locations are fixtures. Each job runs serially, with the final
## empty jar returned. The timing excludes travel and material collection.
const World:=preload("res://scripts/world.gd")
const Tea=World.TEA_CERAMICS
const TOKEN:="tea-income-benchmark"
const BATCHES:=3
var checks:=0
var failures:=0
var request:=0

func expect(ok:bool,message:String) -> bool:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)
	return ok

func use(world:World,action:String,extra:String="",node:Vector2i=Vector2i.ZERO) -> bool:
	var site:Array=Tea.SITES[action]
	var player:Dictionary=world.state.players[TOKEN]
	var cell:Vector2i=node if action=="tea_pick" else site[1]
	player.region=site[0]
	player.x=cell.x+1.5
	player.y=cell.y+0.5
	if player.region in World.TRANSIT.ROUTE:player.travel_book.visited[player.region]=true
	request+=1
	var result:=world.act(TOKEN,"tea-income-%d"%request,action,cell,extra)
	return expect(result.ok,"%s %s: %s"%[action,extra,result.message])

func advance(world:World,seconds:float) -> bool:
	return expect(world.step(seconds,true),"Advance the world shipment or processing clock")

func measure(style:String,wrap:String,expected_gross:int,expected_seconds:float) -> void:
	var world:=World.new()
	world.add_player(TOKEN,"茶貨試算")
	world.state.chapter_one.shipped=true
	world.state.chapter_one.watered=true
	world.state.board=true
	world.state.picnic=true
	if not use(world,"tea_intro"):return
	var person:Dictionary=world.state.players[TOKEN]
	var initial_coins:=int(person.coins)
	var initial_fiber:=int(person.inventory.fiber)
	var started:=float(world.state.time)
	var ceramic:=wrap=="jar"
	if ceramic:
		if not use(world,"tea_potter") or not use(world,"tea_fire"):return
		if not advance(world,Tea.KILN_SECONDS) or not use(world,"tea_fire_take"):return
	for i in range(BATCHES):
		if not use(world,"tea_pick","",Tea.TEA_NODES[0]) or not use(world,"tea_roast",style):return
		if not advance(world,float(Tea.ROAST_SECONDS[style])) or not use(world,"tea_take"):return
		if not use(world,"tea_pack",style+":"+wrap) or not use(world,"tea_ship"):return
		if not advance(world,Tea.SHIPPING_SECONDS) or not use(world,"tea_sell"):return
		if ceramic:
			if not use(world,"tea_return") or not advance(world,Tea.RETURN_SECONDS) or not use(world,"tea_reclaim"):return
	var gross:=int(person.coins)-initial_coins
	var elapsed:=float(world.state.time)-started
	var fiber_used:=initial_fiber-int(person.inventory.fiber)
	var record:=Tea.own_record(world.state,TOKEN)
	expect(gross==expected_gross and is_equal_approx(elapsed,expected_seconds),"Measured sale proceeds and elapsed seconds match the contract")
	expect(fiber_used==(0 if ceramic else 3),"Only fiber parcels use one fiber each")
	expect(int(person.inventory.get("tea_leaf",0))==0 and int(person.inventory.get("tea_"+style,0))==0,"All six harvested leaves become three delivered packages")
	if ceramic:
		expect(int(person.inventory.get("tea_spent_jar",0))==1 and int(person.inventory.get("clay",-1))==0,"One jar fired from two clay serves three deliveries")
		expect(int(record.reuse_count)==2 and int(record.empties)==0 and record.returning.is_empty(),"Exactly two reuses and no unclaimed returns")
	else:
		expect(int(record.empties)==0 and record.returning.is_empty(),"Fiber wrapping creates no return leg")
	print("TEA_INCOME style=%s wrap=%s deliveries=%d seconds=%.0f gross=%d fiber=%d clay=%d"%[
		style,wrap,BATCHES,elapsed,gross,fiber_used,2 if ceramic else 0])

func _initialize() -> void:
	measure("light","fiber",108,84.0)
	measure("deep","fiber",132,96.0)
	measure("light","jar",144,154.0)
	measure("deep","jar",168,166.0)
	print("TEA_INCOME_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
