extends SceneTree

const World=preload("res://scripts/world.gd")
const Market=World.MARKET
const Ui=preload("res://scripts/market_stall_ui.gd")
const KIND=World.INDUSTRY.COAST_REGISTER
const SITE:=Vector2i(40,34)
const MOVED:=Vector2i(43,35)
const ROTATED:=Vector2i(40,36)
var app
var world:World
var token:String
var save_path:String
var output:String
var checks:=0
var failures:=0
var serial:=0

func _initialize()->void:
	run.call_deferred()

func expect(ok:bool,reason:String)->void:
	checks+=1
	if not ok:
		failures+=1
		push_error(reason)

func act(action:String,tile:Vector2i,extra:="",actor:="")->Dictionary:
	serial+=1
	return world.act(token if actor.is_empty() else actor,"register-%d"%serial,action,tile,extra)

func stand(person:Dictionary,position:Vector2)->void:
	person.x=position.x
	person.y=position.y
	app.session._send_snapshot(1)

func button(node_name:String)->void:
	var control:=app.modal.find_child(node_name,true,false) as Button if is_instance_valid(app.modal) else null
	expect(control!=null and not control.disabled,"Enabled button "+node_name)
	if control!=null and not control.disabled:control.pressed.emit()

func capture(file:String)->void:
	if output.is_empty() or DisplayServer.get_name()=="headless":return
	DirAccess.make_dir_recursive_absolute(output)
	await create_timer(0.25).timeout
	await RenderingServer.frame_post_draw
	expect(root.get_texture().get_image().save_png(output.path_join(file+".png"))==OK,"Capture "+file)

func finish()->void:
	app.session.shutdown()
	for suffix:String in ["",".bak",".writer-lock"]:
		if FileAccess.file_exists(save_path+suffix):DirAccess.remove_absolute(save_path+suffix)
	print("WHITEWOOD_REGISTER_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func run()->void:
	app=preload("res://main.tscn").instantiate()
	root.add_child(app)
	root.size=Vector2i(1024,640) if app.arg_value("qa-size","")=="1024" else Vector2i(1280,800)
	output=app.arg_value("register-preview","")
	save_path="user://whitewood-register-%d.json"%Time.get_ticks_usec()
	app.session.profile.token="register-carpenter"
	if app.session.host(0,"渡口木匠",save_path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	app.WanganUI.dismiss(app)
	world=app.session.world
	token=app.session.peers[1]
	var person:Dictionary=world.state.players[token]
	person.inventory.merge({"wood":40,"copper_ingot":8,"radish":3},true)
	world.state.time=720.0
	for tile:Vector2i in [SITE,SITE+Vector2i.RIGHT,MOVED,MOVED+Vector2i.RIGHT,ROTATED,ROTATED+Vector2i.DOWN]:
		world.state.removed[World.key(tile)]=true
	stand(person,Vector2(41.5,33.5))
	app._build_menu()
	var shelf:Button
	for entry:Button in app.modal.find_children("BuildTab*","Button",true,false):
		if entry.text=="海邊":shelf=entry
	expect(shelf!=null,"The coastal shelf is available")
	if shelf==null:
		finish()
		return
	shelf.pressed.emit()
	button("BuildSlot_"+KIND+"_"+str(shelf.name).trim_prefix("BuildTab"))
	button("BuildPlace")
	app._perform_build_action("build",SITE,KIND)
	var near:=SITE+Vector2i.RIGHT
	var built:bool=world.state.objects.get(World.key(SITE),{}).get("type")==KIND
	expect(built and world.station_anchor(world.state.objects,near)==SITE and world.blocked(SITE) and world.blocked(near),"The 2x1 counter has collision and one anchor")
	if not built:
		finish()
		return
	expect(person.inventory.wood==24 and person.inventory.copper_ingot==6,"The normal build flow charges one recipe")
	app._select_tool("hoe")
	stand(person,Vector2(41.5,35.5))
	await capture("register")
	app._interact()
	expect(Ui.is_open(app) and Ui.cell(app)==near and app.modal.find_child("MarketLocked",true,false)!=null,"The normal E interaction opens the correct half and respects the picnic gate")
	expect(not act("market_stock",near,"radish:1").ok and not person.has("market"),"The server also rejects pre-picnic stock")
	app._close_modal()
	world.state.picnic=true
	for square:Vector2i in Market.CANDIDATES:
		world.state.ground[World.key(square)]={"type":"floor","owner":token,"items":{}}
	app.session._send_snapshot(1)
	expect(Market.active_cell(world.state)==Market.NO_CELL,"All four plaza stall sites are occupied in this fixture")
	app._interact()
	expect(Ui.is_open(app) and Ui.cell(app)==near and app.modal.find_child("MarketStock_radish_1",true,false)!=null,"A register works even without a plaza stall")
	if not Ui.is_open(app):
		finish()
		return
	button("MarketStock_radish_1")
	expect(Market.record(person).stock.get("radish",0)==1 and person.inventory.radish==2,"Pressing stock moves exactly one radish")
	button("MarketOpen")
	expect(Market.record(person).pending and Market.stalls_on(world.state,0)==1,"Opening via the register creates one NPC market round")
	expect(not act("market_open",SITE).ok and Market.stalls_on(world.state,0)==1,"The other half cannot open an extra round")
	await capture("market-open")
	world.add_player("register-visitor","來訪島民")
	var visitor:Dictionary=world.state.players["register-visitor"]
	visitor.inventory.radish=2
	visitor.x=48.5
	visitor.y=34.5
	expect(act("market_stock",near,"radish:1","register-visitor").message==Market.TOO_FAR,"Visitors still need to approach the register")
	visitor.x=41.5
	visitor.y=36.5
	expect(act("market_stock",near,"radish:2","register-visitor").ok and Market.record(visitor).stock.radish==2 and Market.record(person).stock.radish==1,"A visitor's stock stays in their own stall")
	expect(not act("remove",near,"","register-visitor").ok,"A visitor cannot take the register itself")
	var expected:=Market.price_for(int(Market.sale_prices().radish),"produce",0)
	world.state.time=1439.0
	expect(world.step(2.0,true) and Market.record(person).till==expected,"Midnight settles a stock unit at the existing NPC market price")
	app.session._send_snapshot(1)
	await capture("settlement")
	var coins:=int(person.coins)
	button("MarketCollect")
	expect(person.coins==coins+expected and Market.record(person).till==0 and Market.record(visitor).stock.radish==2,"Collection pays exactly once and leaves visitors' records independent")
	var restored:=World.new()
	expect(restored.load_world(save_path) and not restored.recovered_from_backup and restored.state.objects.get(World.key(near),{}).get("register_part")==1 and Market.record(restored.state.players[token]).total==expected,"Primary save restores both the counter and collected earnings")
	var design:=World.BLUEPRINT_DESIGN.capture(world.state,token,Rect2i(SITE,Vector2i(2,1)),"渡口收銀櫃",World.BUILD,World.NAMES)
	expect(design.ok and design.blueprint.pieces==[{"kind":KIND,"x":0,"y":0}],"Blueprint captures the empty furniture independently of market records")
	stand(person,Vector2(42.5,35.5))
	expect(act("move_object",near,World.key(MOVED)).ok and not world.state.objects.has(World.key(SITE)),"Moving the secondary square relocates the cabinet")
	app.session._send_snapshot(1)
	expect(Ui.cell(app)==Market.NO_CELL and app.modal.find_child("MarketLocked",true,false)!=null,"An open panel drops the removed entry after a snapshot")
	expect(act("remove",MOVED+Vector2i.RIGHT).ok and person.inventory.wood==40 and person.inventory.copper_ingot==8 and Market.record(person).total==expected,"Removal refunds one recipe and preserves market history")
	app._close_modal()
	stand(person,Vector2(40.5,35.5))
	if design.ok:
		var quote:=world.quote_blueprint(token,design.blueprint,ROTATED,1)
		expect(quote.ok,"A vertical blueprint quotes correctly")
		if quote.ok:
			var placed:=world.apply_blueprint(token,"b".repeat(32),design.blueprint,ROTATED,1,quote.hash)
			var half:=ROTATED+Vector2i.DOWN
			expect(placed.ok and world.station_anchor(world.state.objects,half)==ROTATED and world.state.objects.get(World.key(half),{}).get("register_vertical")==true,"Applying a vertical blueprint keeps two valid squares")
			expect(act("market_collect",half).message==Market.apply(world.state.duplicate(true),token,"market_collect","",World.NAMES).message,"The rotated register reaches the same empty till")
			app.session._send_snapshot(1)
			await capture("rotated")
	finish()
