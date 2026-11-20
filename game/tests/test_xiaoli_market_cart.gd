extends SceneTree

const World=preload("res://scripts/world.gd")
const Design=preload("res://scripts/blueprint_design.gd")
const Cart=World.INDUSTRY
const SITE:=Vector2i(40,34)
const MOVED:=Vector2i(43,34)
const OFFSETS:=[Vector2i.ZERO,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.ONE]
var app
var world:World
var owner:String
var output:String
var path:String
var checks:=0
var failures:=0

func _initialize()->void:
	run.call_deferred()

func expect(ok:bool,label:String)->bool:
	checks+=1
	if not ok:
		failures+=1
		push_error(label)
	return ok

func press(name:String)->bool:
	var button:=app.modal.find_child(name,true,false) as Button if is_instance_valid(app.modal) else null
	if not expect(button!=null and not button.disabled,"Button is available: "+name):return false
	button.pressed.emit()
	return true

func capture(name:String)->void:
	if output.is_empty() or DisplayServer.get_name()=="headless":return
	DirAccess.make_dir_recursive_absolute(output)
	await create_timer(0.25).timeout
	await RenderingServer.frame_post_draw
	expect(root.get_texture().get_image().save_png(output.path_join(name+".png"))==OK,"Capture "+name)

func finish()->void:
	app.session.shutdown()
	app.sound.close()
	app.queue_free()
	await create_timer(0.25).timeout
	for suffix in ["",".bak",".writer-lock"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("MARKET_CART_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func valid_save(snapshot:Dictionary)->bool:
	return World.SAVE_SCHEMA.validate(snapshot,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)

func run()->void:
	app=preload("res://main.tscn").instantiate()
	root.add_child(app)
	root.size=Vector2i(1024,640) if app.arg_value("qa-size","")=="1024" else Vector2i(1280,800)
	output=app.arg_value("qa-dir","")
	path="user://market-cart-%d.json"%Time.get_ticks_usec()
	app.session.profile.token="market-cart-owner"
	if app.session.host(0,"渡口攤主",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	app.WanganUI.dismiss(app)
	world=app.session.world
	owner=app.session.peers[1]
	var person:Dictionary=world.state.players[owner]
	person.x=41.5
	person.y=33.5
	world.state.time=720.0
	person.inventory.merge({"wood":60,"copper_ingot":8,"cotton_cloth":8,"radish":8,"soup":6},true)
	for origin in [SITE,MOVED]:
		for offset:Vector2i in OFFSETS:world.state.removed[World.key(origin+offset)]=true
	expect(not world.act(owner,"locked-cart","build",SITE,Cart.COAST_CART).ok,"Cart construction requires the picnic")
	world.state.picnic=true
	app.session._send_snapshot(1)
	app._build_menu()
	for entry:Button in app.modal.find_children("BuildTab*","Button",true,false):
		if entry.text=="海邊":
			entry.pressed.emit()
			press("BuildSlot_"+Cart.COAST_CART+"_"+str(entry.name).trim_prefix("BuildTab"))
			break
	press("BuildPlace")
	expect(app.building==Cart.COAST_CART and app.view.build_placement_offsets(Cart.COAST_CART)==OFFSETS,"Build mode previews a 2x2 cart")
	app._perform_build_action("build",SITE,Cart.COAST_CART)
	if not expect(world.state.objects.get(World.key(SITE),{}).get("type")==Cart.COAST_CART,"The build tool places the cart"):
		finish()
		return
	expect(person.inventory.wood==36 and person.inventory.copper_ingot==4 and person.inventory.cotton_cloth==4,"Recipe charges wood 24, copper ingots 4, and cloth 4")
	for offset:Vector2i in OFFSETS:
		expect(world.blocked(SITE+offset) and World.station_anchor(world.state.objects,SITE+offset)==SITE,"Each part blocks movement and leads to the anchor")
	person.x=SITE.x+2.15
	person.y=SITE.y+0.5
	app.session._send_snapshot(1)
	app._select_tool("hoe")
	app._interact()
	var opened:=str(app.modal.name) if is_instance_valid(app.modal) else "none"
	expect(opened=="MarketStallPanel","Interact from the second column opens the cart panel (got %s)"%opened)
	if not press("MarketStock_radish_5") or not press("MarketStock_soup_5"):
		finish()
		return
	expect(person.market.stock=={"radish":5,"soup":5},"Two chosen items are stocked in the personal stall")
	press("MarketTake_soup_1")
	expect(int(person.market.stock.soup)==4 and int(person.inventory.soup)==2,"Taking a single unit back updates the cart and backpack")
	await capture("cart-stock")
	press("MarketOpen")
	var key:=World.key(SITE)
	expect(person.market.pending and world.state.objects[key].get("market_cart_open",false),"Opening binds the operating shift to this cart")
	var guests:Array=app.view.market_guests()
	expect(guests.size()==2 and guests.all(func(visitor):return Vector2(visitor.position).distance_to(Vector2(SITE))<4.0),"Market visitors gather at the open cart")
	expect(app.view.market_shelf_tags(World.MARKET.active_cell(world.state)).is_empty(),"The cart stock is not displayed twice at the plaza")
	app._close_modal()
	await capture("cart-open")
	var guest:="market-cart-guest"
	world.add_player(guest,"旅客",Vector2(41.5,32.5))
	var guest_view:Dictionary=app.session.public_state("home",guest)
	expect(guest_view.objects[key].get("market_cart_goods")==["radish","soup"] and guest_view.objects[key].items.is_empty(),"Visitors see displayed goods without stock counts")
	expect(not world.act(guest,"guest-collect","market_collect",SITE+Vector2i.RIGHT).ok,"Guests cannot operate the owner's cart from a child tile")
	expect(world.act(owner,"open-move","move_object",SITE+Vector2i.RIGHT,World.key(MOVED)).message==Cart.CART_BUSY,"Cannot move a trading cart")
	expect(world.act(owner,"open-remove","remove",SITE).message==Cart.CART_BUSY,"Cannot dismantle a trading cart")
	expect(World.MARKET.stalls_on(world.state,0)==1,"Cart contributes exactly one stall to the island market")
	var plaza:=World.MARKET.active_cell(world.state)
	expect(World.MARKET.record(person).stock.size()==2 and plaza!=World.MARKET.NO_CELL,"The plaza and cart keep using the same owner stock")
	var captured:=Design.capture(world.region_snapshot("home"),owner,Rect2i(SITE,Vector2i(2,2)),"海邊攤車",World.BUILD,World.NAMES)
	expect(captured.ok and not JSON.stringify(captured).contains("market_cart_open"),"Blueprint captures cart furniture without its operating shift")
	var loaded:=World.new()
	expect(loaded.load_world(path) and loaded.state.objects[key].get("market_cart_open",false) and loaded.state.players[owner].market.pending,"Active operation survives save and reload")
	var malformed:Dictionary=world.state.duplicate(true)
	malformed.objects[World.key(SITE+Vector2i.RIGHT)].market_cart_open=true
	expect(not valid_save(malformed),"Save validation rejects an open flag on a secondary tile")
	world.state.time=World.WEATHER.DAY_SECONDS-0.15
	expect(world.step(0.30,true),"Run the normal midnight market settlement")
	var till:=int(person.market.till)
	expect(till>0 and not person.market.pending and not world.state.objects[key].has("market_cart_open"),"Midnight credits sales and closes the cart")
	var result:=world.act(owner,"closed-move","move_object",SITE+Vector2i.RIGHT,World.key(MOVED))
	expect(result.ok,"Closed cart moves with its full footprint: "+str(result.get("message","")))
	for offset:Vector2i in OFFSETS:
		expect(not world.state.objects.has(World.key(SITE+offset)) and World.station_anchor(world.state.objects,MOVED+offset)==MOVED,"Moving transfers each part to its new position")
	var old_coins:=int(person.coins)
	expect(world.act(owner,"collect-after-moving","market_collect",MOVED+Vector2i.RIGHT).ok and person.coins==old_coins+till,"Moving preserves the exact settlement and allows collection from another part")
	expect(not world.act(owner,"collect-again","market_collect",MOVED).ok,"Revenue may only be collected once")
	expect(world.act(owner,"closed-remove","remove",MOVED+Vector2i.DOWN).ok and person.inventory.wood==60 and person.inventory.copper_ingot==8 and person.inventory.cotton_cloth==8,"Closed removal refunds exactly one recipe")
	finish()
