extends SceneTree

const World=preload("res://scripts/world.gd")
const Industry=World.INDUSTRY
const KIND:=Industry.SEED_CABINET
const FIELD:=Vector2i(38,34)
const PLOT:=Vector2i(40,34)
const SECOND:=PLOT+Vector2i.RIGHT
const ROTATED:=Vector2i(42,34)
const MOVED:=PLOT+Vector2i.DOWN
const GUEST:="cabinet-guest"
var app
var world:World
var owner:String
var path:String
var checks:=0
var failures:=0
var serial:=0

func _initialize()->void:
	run.call_deferred()

func expect(ok:bool,message:String)->void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)

func act(action:String,position:Vector2i,extra:="",actor:="")->Dictionary:
	serial+=1
	return world.act(owner if actor.is_empty() else actor,"cabinet-qa-%d"%serial,action,position,extra)

func samples(at:Vector2i)->Array:
	return world.state.objects.get(World.key(at),{}).get(Industry.SEED_SAMPLES,[])

func capture(image_name:String)->void:
	var directory:String=app.arg_value("cabinet-preview","")
	if directory.is_empty() or DisplayServer.get_name()=="headless":return
	await process_frame
	await RenderingServer.frame_post_draw
	expect(root.get_texture().get_image().save_png(directory.path_join(image_name+".png"))==OK,"Saved "+image_name)

func run()->void:
	app=preload("res://main.tscn").instantiate()
	root.add_child(app)
	root.size=Vector2i(1280,800)
	path="user://seed-cabinet-%d.json"%Time.get_ticks_usec()
	app.session.profile.token="cabinet-owner"
	if app.session.host(0,"種子標本櫃測試",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	app.WanganUI.dismiss(app)
	world=app.session.world
	owner=app.session.peers[1]
	var person:Dictionary=world.state.players[owner]
	person.x=World.SPAWN.x
	person.y=World.SPAWN.y
	person.inventory.wood=28
	person.inventory.glass=12
	person.inventory.carrot_seed=1
	world.add_player(GUEST,"朋友",Vector2(42.5,33.5))
	app.session._send_snapshot(1)
	app._build_menu()
	var greenhouse:Button
	for button:Button in app.modal.find_children("BuildTab*","Button",true,false):
		if button.text=="星砂溫室":greenhouse=button
	expect(greenhouse!=null,"The greenhouse workshop shelf is visible")
	if greenhouse!=null:
		greenhouse.pressed.emit()
		var slot:=app.modal.find_child("BuildSlot_"+KIND+"_"+str(greenhouse.name).trim_prefix("BuildTab"),true,false) as Button
		expect(slot!=null and slot.is_visible_in_tree(),"The cabinet has a visible workshop tile")
		if slot!=null:slot.pressed.emit()
		app._layout_preview()
		await capture("seed-cabinet-workshop")
	var place:=app.modal.find_child("BuildPlace",true,false) as Button
	expect(place!=null and not place.disabled,"The workshop accepts the cabinet recipe")
	if place!=null:place.pressed.emit()
	expect(app.building==KIND,"The recipe selects ordinary construction")
	app.session.perform("build",PLOT,KIND)
	expect(world.blocked(PLOT) and world.blocked(SECOND) and World.station_anchor(world.state.objects,SECOND)==PLOT,"The cabinet uses two solid cells with one anchor")
	expect(person.inventory.wood==14 and person.inventory.glass==6,"Construction consumes 14 wood and 6 glass")
	expect(not act(Industry.SEED_DISPLAY,PLOT,"radish").ok and not act(Industry.SEED_DISPLAY,PLOT,"keepsake_aru_bird_kit").ok,"Having seeds or supplying a story item cannot bypass the almanac requirement")
	expect(act("hoe",FIELD).ok,"Prepare a real field")
	for crop:String in ["radish","lettuce","wheat","carrot"]:
		expect(act("seed",FIELD,crop).ok and act("water",FIELD).ok,"Plant and water "+crop)
		world.step(151.0,true)
		expect(act("harvest",FIELD).ok and person.collection.crops.has(crop),"Harvest registers "+crop+" in the almanac")
	person.x=41.5
	person.y=33.5
	app.session._send_snapshot(1)
	app.view.show_target=false
	var bag:Dictionary=person.inventory.duplicate(true)
	app._interact()
	var picker:=app.modal.find_child("SeedCabinetPicker",true,false) as OptionButton if app.modal!=null else null
	expect(picker!=null and picker.item_count==4,"Interacting with the second cell offers only four registered crops")
	if picker!=null:
		picker.select(0)
		app.modal.find_child("SeedCabinetDisplay",true,false).pressed.emit()
	expect(samples(PLOT)==["radish"] and person.inventory==bag,"The normal display action consumes no seed or harvest")
	expect(not act(Industry.SEED_DISPLAY,SECOND,"radish").ok,"The cabinet rejects duplicate specimens")
	expect(not act(Industry.SEED_DISPLAY,SECOND,"lettuce",GUEST).ok,"A guest cannot change the cabinet")
	expect(act(Industry.SEED_DISPLAY,SECOND,"lettuce").ok and act(Industry.SEED_DISPLAY,SECOND,"wheat").ok,"Display can fill three specimen slots")
	expect(not act(Industry.SEED_DISPLAY,SECOND,"carrot").ok and person.inventory==bag,"A fourth specimen is rejected without consuming any inventory")
	var design:=World.BLUEPRINT_DESIGN.capture(world.state,owner,Rect2i(PLOT,Vector2i(2,1)),"種子標本櫃",World.BUILD,World.NAMES)
	expect(design.ok,"The furniture is captured by the blueprint system")
	if design.ok:
		var quote:=world.quote_blueprint(owner,design.blueprint,ROTATED,1)
		if quote.ok:
			var built:=world.apply_blueprint(owner,"e".repeat(32),design.blueprint,ROTATED,1,quote.hash)
			expect(built.ok and Industry.is_vertical(world.state.objects.get(World.key(ROTATED),{})) and samples(ROTATED).is_empty(),"A rotated blueprint builds an empty vertical cabinet")
			expect(act(Industry.SEED_DISPLAY,ROTATED,"carrot").ok,"A vertical cabinet displays a registered crop even after its last seed was planted")
		else:expect(false,"The rotated blueprint fits the reserved test plot")
	var loaded:=World.new()
	expect(loaded.load_world(path) and not loaded.recovered_from_backup and loaded.state.objects.get(World.key(PLOT),{}).get(Industry.SEED_SAMPLES)==samples(PLOT),"The primary save reloads the specimens")
	for malformed in [["carrot","carrot"],["not_a_crop"],["tomato"],["radish","lettuce","wheat","carrot"]]:
		var bad:=loaded.state.duplicate(true)
		if bad.objects.has(World.key(PLOT)):
			bad.objects[World.key(PLOT)][Industry.SEED_SAMPLES]=malformed
			expect(not World.SAVE_SCHEMA.validate(bad,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME),"The save rejects "+str(malformed))
	app.session._send_snapshot(1)
	app.view.zoom=2.0
	app.view.camera=Vector2(41,34.5)*32-Vector2(root.size)/4.0
	app.view.queue_redraw()
	await capture("seed-cabinet-placed")
	app._interact()
	expect(app.modal!=null and app.modal.find_child("SeedSample_wheat",true,false)!=null and app.modal.find_child("SeedCabinetPicker",true,false)==null,"A full cabinet shows the specimens and hides the picker")
	await capture("seed-cabinet-full")
	root.size=Vector2i(1024,640)
	app._layout_preview()
	await process_frame
	var rightmost:=app.modal.find_child("SeedClear_wheat",true,false) as Button
	expect(rightmost!=null and root.get_visible_rect().encloses(rightmost.get_global_rect()) and app.modal.get_global_rect().encloses(rightmost.get_global_rect()),"The last specimen and its controls fit the smaller viewport")
	app._close_modal()
	app.session.peers[1]=GUEST
	app.session._send_snapshot(1)
	app.LifeTasks.seed_specimen_cabinet(app,SECOND,app.session.snapshot.objects[World.key(PLOT)])
	expect(app.modal.find_child("SeedSample_radish",true,false)!=null and app.modal.find_children("SeedClear_*","Button",true,false).is_empty(),"A visitor sees the public samples without editing controls")
	app._close_modal()
	app.session.peers[1]=owner
	app.session._send_snapshot(1)
	app._interact()
	var clear:=app.modal.find_child("SeedClear_radish",true,false) as Button if app.modal!=null else null
	person.x=46.5
	expect(not act(Industry.SEED_CLEAR,SECOND,"radish").ok and "radish" in samples(PLOT),"Even the owner must be near the furniture to change the display")
	person.x=41.5
	if clear!=null:clear.pressed.emit()
	expect(samples(PLOT)==["lettuce","wheat"] and person.inventory.get("radish_seed")==bag.get("radish_seed"),"Removing a display reference never grants an item")
	expect(act("move_object",SECOND,World.key(MOVED)).ok and samples(MOVED)==["lettuce","wheat"],"Moving from the second cell keeps the display intact")
	expect(act("remove",MOVED).ok and person.inventory.wood==14 and person.inventory.glass==6,"Dismantling refunds only the building materials")
	app.session.shutdown()
	for suffix:String in ["",".bak",".writer-lock"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("SEED_CABINET_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
