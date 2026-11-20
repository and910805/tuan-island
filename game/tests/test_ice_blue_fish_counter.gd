extends SceneTree

const World=preload("res://scripts/world.gd")
const Industry=World.INDUSTRY
const KIND:=Industry.COAST_FISH_COUNTER
const SITE:=Vector2i(40,34)
const NEXT:=Vector2i(40,35)
var app
var world:World
var owner:String
var serial:=0
var checks:=0
var failures:=0
var directory:String

func _initialize()->void:
	run.call_deferred()

func expect(ok:bool,label:String)->void:
	checks+=1
	if not ok:
		failures+=1
		push_error(label)

func act(action:String,tile:Vector2i,extra:="",actor:="")->Dictionary:
	serial+=1
	return world.act(owner if actor.is_empty() else actor,"fish-counter-%d"%serial,action,tile,extra)

func stock(tile:Vector2i)->Dictionary:
	return world.state.objects.get(World.key(tile),{}).get("items",{})

func run()->void:
	app=preload("res://main.tscn").instantiate()
	root.add_child(app)
	root.size=Vector2i(1024,640) if app.arg_value("qa-size","")=="1024" else Vector2i(1280,800)
	app.session.profile.token="fish-counter-owner"
	directory=app.arg_value("fish-counter-preview","")
	var path:="user://ice-blue-counter-%d.json"%Time.get_ticks_usec()
	if app.session.host(0,"冰藍魚貨台測試",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	app.WanganUI.dismiss(app)
	world=app.session.world
	owner=app.session.peers[1]
	var person:Dictionary=world.state.players[owner]
	person.inventory.merge({"wood":60,"stone":36,"minnow":2,"redfish":2,"flounder":2,"loach":2},true)
	world.state.time=720.0
	person.x=50.5
	person.y=58.5
	var water:=Vector2i(50,59)
	expect(act("fish_start",water).ok and world.step(3.0,true) and act("fish_catch",water).ok,"Catch an actual fish on the Wangan south shore")
	expect(person.inventory.get("sardine",0)==1,"The first fish on display comes from a real cast")
	person.x=40.5
	person.y=33.5
	app.session._send_snapshot(1)
	app._build_menu()
	var tab:Button
	for candidate:Button in app.modal.find_children("BuildTab*","Button",true,false):
		if candidate.text=="海邊":tab=candidate
	expect(tab!=null,"The coastal shelf is reachable")
	if tab!=null:
		tab.pressed.emit()
		var slot:=app.modal.find_child("BuildSlot_"+KIND+"_"+str(tab.name).trim_prefix("BuildTab"),true,false) as Button
		expect(slot!=null and slot.is_visible_in_tree(),"The native coastal item is visible in the build tab")
		if slot!=null:slot.pressed.emit()
	await capture("workshop")
	var place:=app.modal.find_child("BuildPlace",true,false) as Button
	expect(place!=null and not place.disabled,"Build action is enabled with the stated recipe")
	if place!=null:place.pressed.emit()
	expect(app.building==KIND and app.building_style=="","Coastal shelf selects the standalone item with its own art")
	app._perform_build_action("build",SITE,KIND)
	var key:=World.key(SITE)
	expect(world.state.objects.get(key,{}).get("type")==KIND and person.inventory.wood==48 and person.inventory.stone==30,"The workshop choice builds and charges 12 wood and 6 stone")
	expect(World.station_anchor(world.state.objects,SITE+Vector2i.RIGHT)==SITE and not world.can_stand(Vector2(41.5,34.5)),"The second tile has collision and shares the counter anchor")
	app._interact()
	var picker:=app.modal.find_child("FishCounterPicker",true,false) as OptionButton if is_instance_valid(app.modal) else null
	var put:=app.modal.find_child("FishCounterPut",true,false) as Button if is_instance_valid(app.modal) else null
	expect(picker!=null and put!=null,"Island interaction opens the three-slot display")
	if picker!=null and put!=null:
		for fish in ["sardine","minnow","redfish"]:
			for index in picker.item_count:
				if picker.get_item_metadata(index)==fish:
					picker.select(index)
					break
			put.pressed.emit()
		expect(put.disabled,"All three slots fill and the live UI disables another deposit")
	else:
		for fish in ["sardine","minnow","redfish"]:act(Industry.COUNTER_PUT,SITE,fish)
	var fish_stock:={"sardine":1,"minnow":1,"redfish":1}
	expect(stock(SITE)==fish_stock and person.inventory.get("sardine",0)==0,"The three real fish have moved from the bag to the shelf")
	expect(not act(Industry.COUNTER_PUT,SITE,"minnow").ok and int(person.inventory.minnow)==1,"Fish kinds are unique")
	expect(not act(Industry.COUNTER_PUT,SITE,"flounder").ok and int(person.inventory.flounder)==2,"The fourth kind stays in the bag")
	expect(not act(Industry.COUNTER_PUT,SITE,"wood").ok,"A non-fish item is rejected")
	world.add_player("counter-guest","觀賞訪客")
	var guest:Dictionary=world.state.players["counter-guest"]
	guest.x=41.5
	guest.y=33.5
	expect(not act(Industry.COUNTER_TAKE,SITE+Vector2i.RIGHT,"redfish","counter-guest").ok,"A nearby visitor cannot take another islander's fish")
	expect(not act("remove",SITE+Vector2i.RIGHT).ok and stock(SITE)==fish_stock,"Demolition cannot destroy the contents")
	for day in 3:expect(world.step(World.WEATHER.DAY_SECONDS,true),"Advance a normal world day")
	expect(stock(SITE)==fish_stock,"No ice refills, spoilage or fish consumption after three days")
	app.session._send_snapshot(1)
	await capture("display")
	if is_instance_valid(app.modal):app._close_modal()
	app.view.zoom=2.0
	app.view.camera=Vector2(41.0,34.0)*32.0-Vector2(root.size)/4.0
	await capture("island")
	var loaded:=World.new()
	expect(loaded.load_world(path) and not loaded.recovered_from_backup and loaded.state.objects[key].items==fish_stock,"All items and the footprint survive a real reload")
	var corrupted:=world.state.duplicate(true)
	corrupted.objects[World.key(SITE+Vector2i.RIGHT)].items={"carp":1}
	expect(not World.SAVE_SCHEMA.validate(corrupted,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME),"A secondary tile cannot secretly store another fish")
	var copy:=World.BLUEPRINT_DESIGN.capture(world.state,owner,Rect2i(SITE,Vector2i(2,1)),"魚貨台",World.BUILD,World.NAMES)
	expect(copy.ok and copy.blueprint.pieces.size()==1 and not copy.blueprint.pieces[0].has("items"),"Blueprint only captures the cabinet, without fish")
	expect(act("move_object",SITE+Vector2i.RIGHT,World.key(NEXT)).ok and stock(NEXT)==fish_stock and not world.state.objects.has(key),"Move the two-tile display from its far end with all three fish")
	person.inventory.minnow=1000000000
	expect(not act(Industry.COUNTER_TAKE,NEXT,"minnow").ok and stock(NEXT).has("minnow"),"Full inventory keeps the fish safe on the display")
	person.inventory.minnow=1
	for fish in fish_stock:
		expect(act(Industry.COUNTER_TAKE,NEXT+Vector2i.RIGHT,fish).ok,"Retrieve "+fish+" from the second tile")
	expect(stock(NEXT).is_empty() and person.inventory.get("sardine",0)==1 and not act(Industry.COUNTER_TAKE,NEXT,"sardine").ok,"Fish can leave the display exactly once")
	expect(act("remove",NEXT+Vector2i.RIGHT).ok and person.inventory.wood==60 and person.inventory.stone==36,"Demolition of the empty counter refunds the recipe")
	if copy.ok:
		var quote:=world.quote_blueprint(owner,copy.blueprint,SITE,1)
		expect(quote.ok,"Quote a rotated fish counter")
		if quote.ok:
			var result:=world.apply_blueprint(owner,"d".repeat(32),copy.blueprint,SITE,1,quote.hash)
			var vertical:Dictionary=world.state.objects.get(key,{})
			expect(result.ok and Industry.is_vertical(vertical) and stock(SITE).is_empty() and World.station_anchor(world.state.objects,NEXT)==SITE,"Rotated blueprint builds an empty two-tile cabinet")
			expect(act(Industry.COUNTER_PUT,NEXT,"sardine").ok,"A rotated cabinet accepts fish from its secondary tile")
			app.session._send_snapshot(1)
			await capture("rotated")
	app.session.shutdown()
	for suffix:String in ["",".bak",".writer-lock"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("ICE_BLUE_FISH_COUNTER_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func capture(name:String)->void:
	if directory.is_empty() or DisplayServer.get_name()=="headless":return
	DirAccess.make_dir_recursive_absolute(directory)
	await create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	expect(root.get_texture().get_image().save_png(directory.path_join(name+".png"))==OK,"Capture "+name)
