extends SceneTree

const World=preload("res://scripts/world.gd")
const Life=preload("res://scripts/lanyang_life.gd")
const ORDER:="lanyang_rice"
const PADDY:=Vector2i(32,26)
var app
var world:World
var actor:String
var count:=0
var failures:=0

func _initialize()->void:
	run.call_deferred()

func check(ok:bool,reason:String)->void:
	count+=1
	if not ok:
		failures+=1
		push_error(reason)

func align(cell:Vector2i)->void:
	world.state.players[actor].x=cell.x+0.5
	world.state.players[actor].y=cell.y-0.5
	app.session._send_snapshot(1)

func act(action:String,cell:Vector2i,extra:="")->void:
	app.session.rates[1]=[]
	app.session.perform(action,cell,extra)

func press(button:Button)->void:
	check(button!=null and not button.disabled,"Enabled order button exists")
	if button==null or button.disabled:return
	app.session.rates[1]=[]
	button.pressed.emit()

func open_board()->void:
	app._gardener_menu()
	press(app.modal.find_child("LanyangOrders",true,false))

func row_status()->String:
	return str(app.session.snapshot.lanyang_order_board.rows[0].status)

func open_journal()->Control:
	app._journal()
	var bookmark:=app.modal.find_child("ActiveOrderJournal",true,false) as Button
	check(bookmark!=null,"The resident journal has an order bookmark")
	if bookmark!=null:bookmark.pressed.emit()
	return app.modal

func journal_route()->Button:
	return app.modal.find_child("OrderRoute",true,false) as Button

func run()->void:
	app=preload("res://main.tscn").instantiate()
	root.add_child(app)
	var directory:String=app.arg_value("lanyang-order-preview","")
	var save_path:="user://lanyang-orders-%d.json"%Time.get_ticks_usec()
	app.session.profile.token="lanyang-order-qa"
	if app.session.host(0,"試作田測試",save_path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	app.WanganUI.dismiss(app)
	world=app.session.world
	actor=app.session.peers[1]
	var summer:=World.WEATHER.DAYS_PER_SEASON*World.WEATHER.DAY_SECONDS+600.0
	var winter:=World.WEATHER.DAYS_PER_SEASON*3*World.WEATHER.DAY_SECONDS
	world.state.picnic=true # Earlier chapter fixture, followed by real travel and field work.
	world.state.board=true
	var player:Dictionary=world.state.players[actor]
	align(Vector2i(43,29))
	var seed_before:int=player.inventory.get("rice_seed",0)
	act("buy",Vector2i(43,29),"rice")
	check(int(player.inventory.get("rice_seed",0))==seed_before+1,"Rice seed purchased at Xiaoli's stall")
	act("buy",Vector2i(43,29),"rice")
	align(World.REGIONS.exit_cell("home"))
	act("travel",World.REGIONS.exit_cell("home"),"lanyang")
	check(world.player_region(actor)=="lanyang","Actual travel changes region")
	align(Life.SERVICE)
	check(not app.session.snapshot.has("lanyang_order_board"),"No order board before repaired canal")
	check(not world.act(actor,"locked-rice","order_accept",Life.SERVICE,ORDER).ok,"Server rejects locked seasonal order")
	player.inventory.plank=6
	player.inventory.stone=8
	player.inventory.resin=2
	for blockage:Vector2i in Life.BLOCKAGES:
		align(blockage)
		act("lanyang_clear",blockage)
	align(Life.SERVICE)
	act("lanyang_donate",Life.SERVICE)
	check(row_status()=="unavailable","No unstocked rice offer in spring")
	world.state.time=summer
	app.session._send_snapshot(1)
	check(row_status()=="open","Rice order opens during its sowing window")
	open_board()
	check(app.modal.get_meta("life_modal_layout","")=="orders_board","Waterway notes link to the regional board")
	var board:Control=app.modal
	align(Vector2i(12,20))
	var accept:=board.find_child("OrderAccept",true,false) as Button
	press(accept)
	check(app.modal==board and row_status()=="open" and accept!=null and not accept.disabled,
		"Refused acceptance leaves the board open and the action available for retry")
	align(Life.SERVICE)
	press(app.modal.find_child("OrderAccept",true,false))
	check(row_status()=="active","Accept commits in the real session")
	var deliver_after_accept:=app.modal.find_child("OrderDeliver",true,false) as Button if is_instance_valid(app.modal) else null
	check(deliver_after_accept!=null and deliver_after_accept.disabled and deliver_after_accept.text=="材料不足",
		"Accept keeps the real board open and shows the missing material")
	var reopened:=World.new()
	check(reopened.load_world(save_path) and reopened.state.players[actor].orders.active.has(ORDER),"Active regional order survives a primary save reload")
	check(not world.act(actor,"wrong-site","order",PADDY,ORDER).ok,"Delivery elsewhere is refused")
	check(not world.act(actor,"missing-rice","order",Life.SERVICE,ORDER).ok and row_status()=="active","Incomplete delivery keeps the order active")
	align(World.REGIONS.exit_cell("lanyang"))
	act("travel",World.REGIONS.exit_cell("lanyang"),"home")
	check(world.player_region(actor)=="home" and not app.session.snapshot.has("lanyang_order_board"),"Local order board stays in Lanyang")
	var journal:=open_journal()
	check(journal_route()!=null and journal_route().text=="查看轉乘路線","The personal Lanyang order is visible at home")
	var sequence:int=app.session.counter
	press(journal_route())
	check(app.modal.get_meta("travel_selected","")=="lanyang" and int(app.session.counter)==sequence,"Order journal shows the Lanyang route without travelling")
	align(World.REGIONS.exit_cell("home"))
	act("travel",World.REGIONS.exit_cell("home"),"lanyang")
	journal=open_journal()
	check(journal_route()!=null and journal_route().text=="查看交件位置","In Lanyang the journal links to the local map when far away")
	press(journal_route())
	var map_back:=app.modal.find_child("LocalMapTravel",true,false) as Button
	check(map_back!=null and map_back.text=="返回訂單簿","Map can return to the order journal")
	press(map_back)
	check(app.modal.has_meta("order_journal"),"Map returns to the live order list")
	align(PADDY)
	act("hoe",PADDY)
	act("seed",PADDY,"rice")
	act("water",PADDY)
	check(world.step(float(World.CROPS.rice.time),true),"World grows the planted rice")
	act("harvest",PADDY)
	check(int(player.inventory.get("rice",0))==2,"Exactly two rice from the actual harvest")
	align(Life.SERVICE)
	for extent in [Vector2i(1024,640),Vector2i(1280,800)]:
		root.size=extent
		journal=open_journal()
		var tracked:Dictionary=journal.get_meta("order_journal").rows[ORDER]
		check(tracked.materials.rice.text.ends_with("2／2") and tracked.status.text.contains("可交件"),"Journal shows live inventory and ready status")
		check(journal_route().text=="打開交件看板","Nearby order links directly to the real board")
		app._layout_preview()
		await process_frame
		await process_frame
		var button:=journal_route()
		check(button!=null and not button.disabled and app.modal.get_global_rect().encloses(button.get_global_rect()),"Journal route button fits at %s"%str(extent))
		var body:Control=journal.get_meta("order_journal").list.get_parent()
		var back:Control=body.get_child(-1)
		var viewport:Control=body.get_parent()
		check(viewport.get_global_rect().encloses(back.get_global_rect()),"Journal back button stays in view at %s"%str(extent))
		if not directory.is_empty() and DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png(directory.path_join("journal-%d.png"%extent.x))==OK,"Save native order journal screenshot")
	var before:=int(player.coins)
	press(journal_route())
	check(app.modal.get_meta("life_modal_layout","")=="orders_board","Nearby route opens the ordinary delivery board")
	press(app.modal.find_child("OrderDeliver",true,false))
	check(int(player.inventory.get("rice",0))==0 and int(player.coins)==before+82 and row_status()=="done","Delivery consumes two rice, pays once and finishes")
	check(app.modal.has_meta("order_journal") and app.modal.get_meta("order_journal").rows.is_empty(),"Delivery returns to the journal and removes the finished entry")
	check(not world.act(actor,"repeat-rice","order",Life.SERVICE,ORDER).ok and int(player.coins)==before+82,"Repeated delivery sends no additional reward")
	check(reopened.load_world(save_path) and ORDER in reopened.state.players[actor].orders.done,"Completed regional order survives reload")
	var rice_time:=float(World.CROPS.rice.time)
	world.state.time=winter-rice_time-20.0
	align(PADDY)
	act("seed",PADDY,"rice")
	act("water",PADDY)
	check(world.step(rice_time-10.0,true),"Grow the second rice crop almost to maturity in late autumn")
	app.session._send_snapshot(1)
	check(row_status()=="open","An almost mature personal rice crop can fulfill the order with thirty seconds of autumn left")
	check(world.step(30.0,true),"Ripen the rice across the change of season")
	act("harvest",PADDY)
	check(int(player.inventory.get("rice",0))==2,"The projected batch can be harvested in winter")
	align(Life.SERVICE)
	player.inventory.rice=1
	app.session._send_snapshot(1)
	check(row_status()=="unavailable","One stored rice cannot unlock a complete winter order")
	player.inventory.rice=2
	app.session._send_snapshot(1)
	check(row_status()=="open","A complete stored batch allows winter delivery")
	act("order_accept",Life.SERVICE,ORDER)
	journal=open_journal()
	world.state.time=float(player.orders.active[ORDER].due)
	app.session._send_snapshot(1)
	check(ORDER in app.session.snapshot.lanyang_order_board.expired,"Orders expire after three world days")
	check(app.modal==journal and not journal_route().visible and journal.get_meta("order_journal").rows[ORDER].status.text.contains("已過期"),"An open journal updates to expired without giving a delivery action")
	check(not world.act(actor,"expired-rice","order",Life.SERVICE,ORDER).ok and int(player.inventory.rice)==2 and int(player.coins)==before+82,"Expired order preserves all materials and money")
	app.session.shutdown()
	for suffix:String in ["", ".bak", ".writer-lock"]:
		if FileAccess.file_exists(save_path+suffix):DirAccess.remove_absolute(save_path+suffix)
	print("LANYANG_ORDER_TESTS checks=%d failures=%d"%[count,failures])
	quit(int(failures>0))
