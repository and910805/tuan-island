extends SceneTree

const World = preload("res://scripts/world.gd")
const Village = preload("res://scripts/village.gd")
const Board := Vector2i(40, 29)

var checks := 0
var failures := 0

func expect(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func _initialize() -> void:
	verify_field_supply()
	verify_station_changes()
	var world := World.new()
	var path := "user://order-board-%d.json" % Time.get_ticks_usec()
	world.save_path = path
	for token in ["alice", "bob"]:
		world.add_player(token, token)
		var player: Dictionary = world.state.players[token]
		player.x = 40.5
		player.y = 30.5
		player.inventory.radish = 3
	world.state.time = 100.0
	expect(not world.act("alice", "board-1", "order_accept", Board, "radish").ok, "Unrepaired board refuses orders")
	world.state.board = true
	var last_spring:=World.WEATHER.DAYS_PER_SEASON*Village.DAY
	world.state.time=last_spring-30.0
	var offers:=func(token:String,id:String)->bool:
		return world.order_board(token).rows.any(func(row):return row.id==id and row.status=="open")
	world.state.players.bob.inventory.radish=2
	expect(offers.call("alice","radish") and not offers.call("bob","radish"),"Only a full personal batch covers a crop that cannot grow before season ends")
	expect(not world.act("bob","late-spring","order_accept",Board,"radish").ok,"Server refuses the same late-season order shown as unavailable")
	world.state.time=last_spring-World.CROPS.radish.time
	expect(offers.call("bob","radish"),"A crop that matures at the season boundary can still be delivered within three days")
	world.state.time=World.WEATHER.DAYS_PER_SEASON*Village.DAY*4-Village.DAY
	expect(offers.call("bob","radish"),"The next growing season counts when it starts before the delivery deadline")
	world.state.time=World.WEATHER.DAYS_PER_SEASON*Village.DAY*3+60.0
	world.state.players.bob.inventory.bread=1
	world.state.players.bob.inventory.wheat=1
	expect(not offers.call("bob","bread"),"Partial bread and insufficient wheat cannot make the winter batch")
	world.state.players.bob.inventory.wheat=2
	expect(offers.call("bob","bread"),"Use stored bread and enough wheat for the remaining loaf")
	world.state.time=100.0
	expect(not world.act("alice","jam-locked","order_accept",Board,"market_jam").ok,"Jam commission is gated without a pot")
	expect(not world.act("alice", "board-2", "order", Board, "radish").ok, "Delivery requires prior acceptance")
	expect(world.act("alice", "board-3", "order_accept", Board, "radish").ok, "Acceptance commits")
	expect(not world.act("bob", "board-4", "order", Board, "radish").ok, "A different player cannot deliver an accepted order")
	var reopened := World.new()
	var loaded := reopened.load_world(path)
	expect(loaded, "Saved active order can be loaded")
	if loaded:
		var alice: Dictionary = reopened.state.players.alice
		var before := int(alice.coins)
		expect(alice.orders.get("active", {}).has("radish"), "Active order survives a fresh World instance")
		expect(reopened.act("alice", "board-5", "order", Board, "radish").ok, "Accepted order can be delivered after reload")
		expect(alice.inventory.radish == 0 and alice.coins == before + 90, "Exact materials and reward commit together")
		expect(not reopened.act("alice", "board-6", "order", Board, "radish").ok, "Successful order cannot pay twice")
		reopened.state.time += Village.DAY
		alice.inventory.radish = 3
		expect(reopened.act("alice", "board-7", "order_accept", Board, "radish").ok, "A later day permits another order")
		reopened.state.time = float(alice.orders.active.radish.due)
		expect(not reopened.act("alice", "board-8", "order", Board, "radish").ok, "Delivery expires by world time")
		expect(alice.inventory.radish == 3 and alice.coins == before + 90, "Expired order preserves materials and coins")
		var pot:=Vector2i(41,35)
		reopened.state.objects[World.key(pot)]={"type":"jam_pot","owner":"alice","items":{}}
		alice.inventory.strawberry_jam=2
		reopened.state.players.bob.inventory.strawberry_jam=2
		var catalog=World.ORDER_CATALOG
		expect(not catalog.obtainable("strawberry_jam",catalog.context_from_world(reopened,"bob")),"Another player's pot does not unlock the order")
		var offered:=false
		for offset in range(14):
			var ctx:Dictionary=catalog.context_from_world(reopened,"alice")
			if "market_jam" in catalog.candidate_ids(ctx.day,ctx):
				offered=true
				break
			expect(reopened.step(Village.DAY,true),"advance to next board refresh")
		expect(offered,"Jam enters the rotating order pool")
		expect(reopened.act("alice","jam-accept","order_accept",Board,"market_jam").ok,"Accept jam commission after stocking a batch")
		var jam_coins:=int(alice.coins)
		expect(reopened.act("alice","jam-deliver","order",Board,"market_jam").ok,"Deliver the market's two jars")
		expect(int(alice.coins)==jam_coins+135 and int(alice.inventory.strawberry_jam)==0,"Jam order debits and pays exactly once")
		expect(not reopened.act("alice","jam-repeat","order",Board,"market_jam").ok,"Jam cannot pay again")
		var after_jam:=World.new()
		expect(after_jam.load_world(path) and "market_jam" in after_jam.state.players.alice.orders.done,"Completed market commission survives reload")
		var dock:=World.WANGAN_COAST.DOCK_ORDERS
		expect(not reopened.act("alice","dock-wrong-board","order_accept",Board,"dock_glassmakers").ok,"Coastal orders cannot be accepted at the village board")
		alice.x=dock.x+0.5
		alice.y=dock.y+0.5
		expect(not reopened.act("alice","dock-closed","order_accept",dock,"dock_glassmakers").ok,"The dock orders require a repaired coastal route")
		reopened.state.wangan_star_walk=true
		expect(reopened.order_board("alice","dock").rows.size()==2 and reopened.order_board("alice").rows.size()==4,"The dock and village retain distinct sets of orders")
		expect(reopened.act("alice","dock-accept","order_accept",dock,"dock_glassmakers").ok,"The repaired dock dispatches the crystal sand commission")
		expect(not reopened.act("alice","dock-missing","order",dock,"dock_glassmakers").ok,"Missing supplies leave the order active")
		alice.inventory.crystal_sand=2
		alice.inventory.seashell=1
		var coastal_coins:=int(alice.coins)
		expect(reopened.act("alice","dock-deliver","order",dock,"dock_glassmakers").ok and int(alice.coins)==coastal_coins+92,"The coastal commission pays once")
		expect(not reopened.act("alice","dock-duplicate","order",dock,"dock_glassmakers").ok,"The dock refuses duplicate delivery")
		expect(after_jam.load_world(path) and "dock_glassmakers" in after_jam.state.players.alice.orders.done,"Coastal completion survives reload with the existing order book")
	for suffix in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(path + suffix)
	print("ORDER BOARD WORLD checks=%d failures=%d" % [checks, failures])
	quit(1 if failures else 0)

func verify_field_supply() -> void:
	var world:=World.new()
	var plot:=Vector2i(45,28)
	var boundary:=World.WEATHER.DAYS_PER_SEASON*Village.DAY
	var growing:float=World.CROPS.radish.time
	world.state.time=boundary-growing-10.0
	world.state.board=true
	for token:String in ["grower","neighbor"]:
		world.add_player(token,token)
		world.state.players[token].inventory.radish=2
	var grower:Dictionary=world.state.players.grower
	grower.x=45.5
	grower.y=30.5
	expect(world.act("grower","hoe","hoe",plot).ok and world.act("grower","seed","seed",plot,"radish").ok and world.act("grower","water","water",plot).ok,"Prepare an owned parcel through the normal farm actions")
	expect(world.step(growing-20.0,true),"Move into the final crop window")
	var open:=func(token:String)->bool:
		return world.order_board(token).rows.any(func(row):return row.id=="radish" and row.status=="open")
	expect(open.call("grower") and not open.call("neighbor"),"Forecast fills the owner's missing radish only")
	var channels:Array[String]=["village","dock","lanyang"]
	var contexts:=World.ORDER_CATALOG.contexts_from_world(world,"grower",channels)
	expect(contexts.village.pantry.radish==3 and contexts.dock.pantry.radish==2 and contexts.lanyang.pantry.radish==2,"The village's forecast does not leak into other boards")
	expect(contexts.lanyang.has("rice_window") and not contexts.village.has("rice_window"),"Rice availability is evaluated for Lanyang separately")
	expect(World.ORDER_CATALOG.contexts_from_world(world,"grower",["lanyang","dock","village"])==contexts,"Channel order does not affect crop forecasts")
	var boards:=world.order_boards("grower",channels)
	for channel in channels:
		expect(boards[channel]==world.order_board("grower",channel),"Combined and standalone order boards agree for "+channel)
	grower.x=40.5
	grower.y=30.5
	expect(world.act("grower","accept","order_accept",Board,"radish").ok,"Accept a late order backed by an almost mature crop")
	expect(not world.act("grower","early","order",Board,"radish").ok and int(grower.inventory.radish)==2,"Forecast never grants items or bypasses delivery")
	expect(world.step(35.0,true),"Let the crop mature just before the season changes")
	grower.x=45.5
	grower.y=30.5
	expect(world.act("grower","harvest","harvest",plot).ok,"Gather the ripe crop after changing seasons")
	grower.x=40.5
	grower.y=30.5
	expect(world.act("grower","deliver","order",Board,"radish").ok and int(grower.inventory.radish)==0,"Deliver the crop and stored radishes together")

func verify_station_changes() -> void:
	var world:=World.new()
	world.add_player("owner","島主")
	world.add_player("guest","訪客")
	world.state.objects={
		"20,20":{"type":"stove","owner":"owner"},
		"21,20":{"type":"bench","owner":"guest"},
		"22,20":{"type":"mill","owner":"guest"},
		"23,20":{"type":"jam_pot","owner":"owner"},
	}
	var channels:Array[String]=["village","dock","lanyang"]
	var owner:=World.ORDER_CATALOG.contexts_from_world(world,"owner",channels)
	var guest:=World.ORDER_CATALOG.contexts_from_world(world,"guest",channels)
	expect(owner.dock.stations==["bench","jam_pot","mill","stove"],"All discovered station types are sorted and the owner sees the jam pot")
	expect(guest.village.stations==["bench","mill","stove"],"A guest sees shared workstations without the owner's jam pot")
	world.state.objects.erase("23,20")
	world.state.objects.erase("22,20")
	var updated:=World.ORDER_CATALOG.contexts_from_world(world,"owner",channels)
	expect(updated.village.stations==["bench","stove"] and updated.lanyang.stations==updated.village.stations,"Removed stations are absent from the next evaluation for all boards")
