extends SceneTree

const World=preload("res://scripts/world.gd")
const Industry=World.INDUSTRY
const Art=preload("res://scripts/vine_arch_art.gd")
const KIND:=Industry.VINE_ARCH
const PLOT:=Vector2i(38,34)
const PASSAGE:=PLOT+Vector2i.RIGHT
const POST:=PLOT+Vector2i(2,0)
const ROTATED:=Vector2i(42,33)
const MOVED:=Vector2i(38,36)
const GUEST:="vine-arch-guest"
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
	return world.act(owner if actor.is_empty() else actor,"vine-arch-qa-%d"%serial,action,cell,extra)

func set_pos(person:Dictionary,point:Vector2)->void:
	person.x=point.x
	person.y=point.y

func walk(direction:Vector2)->void:
	for step in range(15):world.move_player(owner,direction,0.04)

func has_arch(cell:Vector2i)->bool:
	return world.state.objects.get(World.key(cell),{}).get("type")==KIND

func capture(name:String)->void:
	if directory.is_empty() or DisplayServer.get_name()=="headless":return
	await create_timer(0.27).timeout
	await RenderingServer.frame_post_draw
	expect(root.get_texture().get_image().save_png(directory.path_join(name+".png"))==OK,"Saved "+name)

func run()->void:
	app=preload("res://main.tscn").instantiate()
	root.add_child(app)
	root.size=Vector2i(1280,800)
	directory=app.arg_value("vine-preview","")
	var path:="user://vine-arch-%d.json"%Time.get_ticks_usec()
	app.session.profile.token="vine-arch-owner"
	if app.session.host(0,"藤蔓花門驗收",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	app.WanganUI.dismiss(app)
	world=app.session.world
	owner=app.session.peers[1]
	var person:Dictionary=world.state.players[owner]
	var bag:Dictionary=person.inventory
	world.state.time=590.0
	bag.wood=24
	bag.copper_ingot=8
	bag.chime_herb=12
	set_pos(person,World.SPAWN)
	world.add_player(GUEST,"鄰居",Vector2(41.5,33.5))
	var guest:Dictionary=world.state.players[GUEST]
	app.session._send_snapshot(1)
	app._build_menu()
	var greenhouse:Button
	for tab:Button in app.modal.find_children("BuildTab*","Button",true,false):
		if tab.text=="星砂溫室":greenhouse=tab
	expect(greenhouse!=null,"The workshop contains the greenhouse shelf")
	if greenhouse!=null:
		greenhouse.pressed.emit()
		var slot:=app.modal.find_child("BuildSlot_"+KIND+"_"+str(greenhouse.name).trim_prefix("BuildTab"),true,false) as Button
		expect(slot!=null and slot.is_visible_in_tree(),"The arch has an illustrated recipe")
		if slot!=null:slot.pressed.emit()
		app._layout_preview()
		await capture("vine-arch-workshop")
	var place:=app.modal.find_child("BuildPlace",true,false) as Button
	expect(place!=null and not place.disabled,"The recipe can be placed")
	if place!=null:place.pressed.emit()
	expect(app.building==KIND and app.view.build_placement_offsets(KIND).size()==3,"Placement preview reserves all three tiles")
	app.session.perform("build",PLOT,KIND)
	expect(has_arch(PLOT) and has_arch(PASSAGE) and has_arch(POST) and World.station_anchor(world.state.objects,POST)==PLOT,"Both posts and the passage refer to one build")
	expect(bag.wood==12 and bag.copper_ingot==4 and bag.chime_herb==6,"The arch charges 12 wood, 4 copper and 6 herb")
	expect(world.blocked(PLOT) and not world.blocked(PASSAGE) and world.blocked(POST),"Only the two posts block movement")
	walk(Vector2.DOWN)
	expect(person.y>35.5,"Ordinary movement walks south through the horizontal opening")
	walk(Vector2.UP)
	expect(person.y<34.0,"Ordinary movement walks north through the horizontal opening")
	for post:Vector2i in [PLOT,POST]:
		set_pos(person,Vector2(post)+Vector2(0.5,-0.5))
		walk(Vector2.DOWN)
		expect(person.y<34.0,"Ordinary movement stops at post "+World.key(post))
	var rooms:=preload("res://scripts/house_rooms.gd")
	expect(rooms._walkable({PASSAGE:true},world.state.objects,PASSAGE) and not rooms._walkable({POST:true},world.state.objects,POST),"The room navigation uses the same passage")
	set_pos(person,Vector2(PASSAGE)+Vector2(0.5,0.5))
	app.session._send_snapshot(1)
	app.view.show_target=false
	app.view.zoom=2.0
	app.view.camera=Vector2(40.5,34.5)*32-Vector2(root.size)/4.0
	await capture("vine-arch-pink")
	app._interact()
	var purple:=app.modal.find_child("VineColor_lavender",true,false) as Button if app.modal!=null else null
	expect(purple!=null and not purple.disabled,"The central tile opens all current color choices")
	await capture("vine-arch-colors")
	if purple!=null:purple.pressed.emit()
	expect(world.state.objects.get(World.key(PLOT),{}).get("vine_color")=="lavender" and bag.chime_herb==6,"The real color control swaps flowers without charging a second recipe")
	expect(not act(Industry.VINE_COLOR_ACTION,POST,"cream",GUEST).ok and not act(Industry.VINE_COLOR_ACTION,POST,"unknown").ok,"Visitor edits and invalid palettes are rejected")
	var partial:=World.BLUEPRINT_DESIGN.capture(world.state,owner,Rect2i(PLOT,Vector2i(2,1)),"截到一半",World.BUILD,World.NAMES)
	expect(not partial.ok,"Blueprint selection cannot split the arch")
	var design:=World.BLUEPRINT_DESIGN.capture(world.state,owner,Rect2i(PLOT,Vector2i(3,1)),"藤蔓花門",World.BUILD,World.NAMES)
	expect(design.ok and design.blueprint.pieces[0].settings.vine_color=="lavender","The full blueprint keeps the selected flower palette")
	if design.ok:
		set_pos(person,Vector2(41.5,34.5))
		var quote:=world.quote_blueprint(owner,design.blueprint,ROTATED,1)
		if quote.ok:
			var applied:=world.apply_blueprint(owner,"a".repeat(32),design.blueprint,ROTATED,1,quote.hash)
			expect(applied.ok and Industry.is_vertical(world.state.objects.get(World.key(ROTATED),{})) and world.state.objects[World.key(ROTATED)].vine_color=="lavender","Rotated blueprint reconstructs the palette and orientation")
		else:expect(false,"The rotated arch fits its site: "+str(quote.get("problems",[])))
		expect(world.blocked(ROTATED) and not world.blocked(ROTATED+Vector2i.DOWN) and world.blocked(ROTATED+Vector2i(0,2)),"The vertical arch reserves two posts and an east-west passage")
		walk(Vector2.RIGHT)
		expect(person.x>43.5,"Ordinary movement walks through the vertical opening")
	set_pos(person,Vector2(PASSAGE)+Vector2(0.5,0.5))
	app.session._send_snapshot(1)
	await capture("vine-arch-placed")
	var loaded:=World.new()
	expect(loaded.load_world(path) and not loaded.recovered_from_backup and loaded.state.objects.get(World.key(PLOT),{}).get("vine_color")=="lavender" and not loaded.blocked(PASSAGE),"Primary save retains the finish and walkable middle")
	var corrupted:=loaded.state.duplicate(true)
	corrupted.objects[World.key(POST)].vine_color="cream"
	expect(not World.SAVE_SCHEMA.validate(corrupted,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME),"The finish cannot be stored on a non-anchor part")
	expect(act("remove",POST).ok and not has_arch(PASSAGE) and int(person.inventory.wood)==12 and int(person.inventory.chime_herb)==6,"Dismantling by the far post refunds exactly one recipe")
	set_pos(guest,Vector2(PASSAGE)+Vector2(0.5,0.5))
	var undo:String=world.state.construction.last.get(owner,{}).get("id","")
	expect(not undo.is_empty() and act(World.UNDO_ACTION,PASSAGE,undo).ok and not world.blocked(PASSAGE) and has_arch(POST),"Restoring the arch allows a visitor to remain inside the opening")
	expect(act("move_object",POST,World.key(MOVED)).ok and not has_arch(POST) and not world.blocked(MOVED+Vector2i.RIGHT)
		and world.state.objects.get(World.key(MOVED),{}).get("vine_color")=="lavender","Moving the arch from the far post retains its palette and open middle")
	for vertical in [false,true]:
		var atlas:Texture2D=Art.TALL if vertical else Art.WIDE
		var texture:=atlas.get_image()
		var normal:=texture.get_region(Rect2i(Art.region("pink",vertical)))
		var lavender:=texture.get_region(Rect2i(Art.region("lavender",vertical)))
		var cream:=texture.get_region(Rect2i(Art.region("cream",vertical)))
		var changed:=0
		var same_alpha:=true
		for y in normal.get_height():
			for x in normal.get_width():
				var original:=normal.get_pixel(x,y)
				var purple_pixel:=lavender.get_pixel(x,y)
				var cream_pixel:=cream.get_pixel(x,y)
				if original!=purple_pixel and purple_pixel!=cream_pixel:changed+=1
				if original.a!=purple_pixel.a or original.a!=cream_pixel.a:same_alpha=false
		expect(changed>=60 and same_alpha,"The atlas changes flower colors while preserving the transparent opening")
	app.session.shutdown()
	for suffix:String in ["",".bak",".writer-lock"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("VINE_ARCH_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
