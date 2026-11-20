extends SceneTree

const World=preload("res://scripts/world.gd")
const Industry=World.INDUSTRY
const KIND:=Industry.GLASS_FLOWER_TABLE
const PLOT:=Vector2i(38,34)
const PARTNER:=PLOT+Vector2i.RIGHT
const ROTATED:=Vector2i(42,34)
const MOVED:=Vector2i(39,35)
const GUEST:="glass-table-guest"
const ART=preload("res://assets/ui-life/glass-flower-table.png")
var app
var world:World
var owner:String
var directory:String
var serial:=0
var checks:=0
var failures:=0

func _initialize()->void:
	run.call_deferred()

func expect(ok:bool,message:String)->void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)

func act(action:String,cell:Vector2i,extra:="",actor:="")->Dictionary:
	serial+=1
	return world.act(owner if actor.is_empty() else actor,"glass-table-qa-%d"%serial,action,cell,extra)

func set_position(person:Dictionary,pos:Vector2)->void:
	person.x=pos.x
	person.y=pos.y

func has_table(cell:Vector2i)->bool:
	return world.state.objects.get(World.key(cell),{}).get("type")==KIND

func frame()->Image:
	if DisplayServer.get_name()=="headless":return null
	app.view.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func capture(output:Image,file_name:String)->void:
	if output==null or directory.is_empty():return
	expect(output.save_png(directory.path_join(file_name+".png"))==OK,"Saved "+file_name)

func compare_glass(before:Image,after:Image)->void:
	if before==null or after==null:return
	var sprite:=ART.get_image()
	var origin:Vector2=app.view.screen(Vector2(PLOT))+Vector2(0,-16)
	var zoom:float=app.view.view_zoom()
	var blended:=0
	var testable:=0
	for y in range(17,29):
		for x in range(8,56):
			var top:=sprite.get_pixel(x,y)
			if top.a<=0.1 or top.a>=0.85:continue
			var at:=Vector2i(((origin+Vector2(x+0.5,y+0.5))*zoom).floor())
			var ground:=before.get_pixelv(at)
			var observed:=after.get_pixelv(at)
			var expected:=ground.lerp(top,top.a)
			if absf(top.r-ground.r)+absf(top.g-ground.g)+absf(top.b-ground.b)<0.24:continue
			testable+=1
			if absf(expected.r-observed.r)+absf(expected.g-observed.g)+absf(expected.b-observed.b)<0.09:blended+=1
	expect(testable>=100 and blended>=testable*0.9,"%d of %d pixels blend the tinted tabletop over the real floor"%[blended,testable])

func run()->void:
	app=preload("res://main.tscn").instantiate()
	root.add_child(app)
	root.size=Vector2i(1280,800)
	directory=app.arg_value("glass-table-preview","")
	var path:="user://glass-flower-table-%d.json"%Time.get_ticks_usec()
	app.session.profile.token="glass-table-owner"
	if app.session.host(0,"玻璃花桌測試",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	app.WanganUI.dismiss(app)
	world=app.session.world
	owner=app.session.peers[1]
	var person:Dictionary=world.state.players[owner]
	set_position(person,World.SPAWN)
	world.state.time=540.0
	person.inventory.wood=24
	person.inventory.glass=12
	person.inventory.copper_ingot=8
	expect(act("build",PLOT,"floor").ok and act("build",PARTNER,"floor").ok,"Lay real wooden floorboards under both tiles")
	world.add_player(GUEST,"鄰居",Vector2(PARTNER)+Vector2(0.5,0.5))
	expect(not act("build",PLOT,KIND).ok and person.inventory.glass==12 and not has_table(PLOT),"A visitor on the second tile prevents placement without consuming glass")
	set_position(world.state.players[GUEST],Vector2(37.5,33.5))
	app.session._send_snapshot(1)
	app._build_menu()
	var greenhouse:Button
	for tab:Button in app.modal.find_children("BuildTab*","Button",true,false):
		if tab.text=="星砂溫室":greenhouse=tab
	expect(greenhouse!=null,"The greenhouse workshop has its own shelf")
	if greenhouse!=null:
		greenhouse.pressed.emit()
		var slot:=app.modal.find_child("BuildSlot_"+KIND+"_"+str(greenhouse.name).trim_prefix("BuildTab"),true,false) as Button
		expect(slot!=null and slot.is_visible_in_tree(),"The flower table appears in the workshop")
		if slot!=null:slot.pressed.emit()
	app._layout_preview()
	if DisplayServer.get_name()!="headless":await create_timer(0.24).timeout
	capture(await frame(),"glass-table-workshop")
	var place:=app.modal.find_child("BuildPlace",true,false) as Button
	expect(place!=null and not place.disabled,"The workshop enables the documented recipe")
	if place!=null:place.pressed.emit()
	expect(app.building==KIND,"The workshop selects normal construction")
	app.set_process(false)
	app.view.set_process(false)
	app.view.zoom=2.0
	app.view.camera=Vector2(39.5,34.5)*32-Vector2(root.size)/4.0
	app.view.show_target=false
	app.view.hide_interaction_prompt=true
	var clean:=await frame()
	app.session.perform("build",PLOT,KIND)
	expect(has_table(PLOT) and has_table(PARTNER) and World.station_anchor(world.state.objects,PARTNER)==PLOT,"The table is one real two-tile object")
	expect(person.inventory.glass==6 and person.inventory.copper_ingot==4,"Build charges six glass and four copper")
	compare_glass(clean,await frame())
	for approach:Vector2i in [PLOT,PARTNER]:
		set_position(person,Vector2(approach)+Vector2(0.5,-0.5))
		for tick in 15:world.move_player(owner,Vector2.DOWN,0.04)
		expect(person.y<float(PLOT.y),"Normal walk is stopped at the table on "+World.key(approach))
	set_position(person,Vector2(40.5,33.5))
	for tick in 15:world.move_player(owner,Vector2.DOWN,0.04)
	expect(person.y>34.5,"A player can move through the neighboring aisle")
	set_position(person,Vector2(40.5,33.5))
	var design:=World.BLUEPRINT_DESIGN.capture(world.state,owner,Rect2i(PLOT,Vector2i(2,1)),"玻璃花桌",World.BUILD,World.NAMES)
	expect(design.ok,"The blueprint captures the complete footprint over its floor")
	if design.ok:
		var quote:=world.quote_blueprint(owner,design.blueprint,ROTATED,1)
		if quote.ok:
			var built:=world.apply_blueprint(owner,"b".repeat(32),design.blueprint,ROTATED,1,quote.hash)
			expect(built.ok and Industry.is_vertical(world.state.objects.get(World.key(ROTATED),{})) and world.blocked(ROTATED+Vector2i.DOWN),"Rotated blueprint places the longitudinal table")
		else:expect(false,"The rotated blueprint fits the empty plot: "+str(quote.get("message","")))
	app.session._send_snapshot(1)
	capture(await frame(),"glass-table-placed")
	var loaded:=World.new()
	expect(loaded.load_world(path) and not loaded.recovered_from_backup and loaded.state.objects.get(World.key(PARTNER),{}).get("type")==KIND,"Both parts reload from the primary save")
	var broken:=loaded.state.duplicate(true)
	broken.objects.erase(World.key(PARTNER))
	expect(not World.SAVE_SCHEMA.validate(broken,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME),"A save cannot contain a table with a missing half")
	expect(not act("remove",PARTNER,"",GUEST).ok and has_table(PLOT),"A guest cannot dismantle the table")
	expect(act("move_object",PARTNER,World.key(MOVED)).ok and has_table(MOVED) and not has_table(PLOT),"Moving from the edge keeps both cells together")
	expect(act("remove",MOVED).ok and person.inventory.glass==6 and person.inventory.copper_ingot==4,"Removing returns exactly one recipe")
	expect(world.state.ground.get(World.key(PLOT),{}).get("type")=="floor","The original floor remains after moving and dismantling")
	app.view.set_process(true)
	app.set_process(true)
	app.session.shutdown()
	for suffix:String in ["",".bak",".writer-lock"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("GLASS_FLOWER_TABLE_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
