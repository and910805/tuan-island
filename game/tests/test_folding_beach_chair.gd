extends SceneTree

const World=preload("res://scripts/world.gd")
const I=World.INDUSTRY
const SEAT=World.RESIDENT_GOALS.MASTER_BENCH_SEAT
const SITE:=Vector2i(40,34)
const FRONT:=SITE+Vector2i.DOWN
const MOVED:=Vector2i(42,34)
var app
var world:World
var owner:String
var path:String
var output:String
var checks:=0
var failures:=0
var serial:=0

func _initialize()->void:
	run.call_deferred()

func expect(ok:bool,label:String)->void:
	checks+=1
	if not ok:
		failures+=1
		push_error(label)

func action(actor:String,verb:String,tile:Vector2i,extra:="")->Dictionary:
	serial+=1
	return world.act(actor,"chair-%d"%serial,verb,tile,extra)

func capture(name:String)->void:
	if output.is_empty() or DisplayServer.get_name()=="headless":return
	DirAccess.make_dir_recursive_absolute(output)
	await create_timer(0.25).timeout
	await RenderingServer.frame_post_draw
	expect(root.get_texture().get_image().save_png(output.path_join(name+".png"))==OK,"Capture "+name)

func finish()->void:
	app.session.shutdown()
	for suffix in ["",".bak",".writer-lock"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("FOLDING_BEACH_CHAIR_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func run()->void:
	app=preload("res://main.tscn").instantiate()
	root.add_child(app)
	root.size=Vector2i(1024,640) if app.arg_value("qa-size","")=="1024" else Vector2i(1280,800)
	output=app.arg_value("qa-dir","")
	path="user://beach-chair-%d.json"%Time.get_ticks_usec()
	app.session.profile.token="beach-chair-owner"
	if app.session.host(0,"海邊木匠",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	app.WanganUI.dismiss(app)
	world=app.session.world
	owner=app.session.peers[1]
	var player:Dictionary=world.state.players[owner]
	player.x=40.5
	player.y=33.5
	player.inventory.merge({"wood":24,"cotton_cloth":12},true)
	world.state.time=720.0
	for tile:Vector2i in [SITE,FRONT,SITE+Vector2i.RIGHT,MOVED,MOVED+Vector2i.DOWN]:world.state.removed[World.key(tile)]=true
	app.session._send_snapshot(1)
	app._build_menu()
	var shelf:Button
	for entry:Button in app.modal.find_children("BuildTab*","Button",true,false):
		if entry.text=="海邊":shelf=entry
	if shelf:shelf.pressed.emit()
	var recipe:=app.modal.find_child("BuildSlot_"+I.BEACH_CHAIR+"_"+str(shelf.name).trim_prefix("BuildTab"),true,false) as Button if shelf else null
	expect(recipe!=null and recipe.is_visible_in_tree(),"The coastal shelf shows the chair")
	if recipe:recipe.pressed.emit()
	var place:=app.modal.find_child("BuildPlace",true,false) as Button
	if place:place.pressed.emit()
	expect(app.building==I.BEACH_CHAIR and app.view.build_placement_offsets(I.BEACH_CHAIR)==[Vector2i.ZERO,Vector2i.DOWN],"The normal build selector previews a 1x2 chair")
	app._perform_build_action("build",SITE,I.BEACH_CHAIR)
	if world.state.objects.get(World.key(SITE),{}).get("type")!=I.BEACH_CHAIR:
		expect(false,"Build places the chair")
		finish()
		return
	expect(world.station_anchor(world.state.objects,FRONT)==SITE and world.blocked(FRONT) and player.inventory.wood==16 and player.inventory.cotton_cloth==8,"Two solid pieces cost one recipe")
	app._select_tool("hoe")
	app._interact()
	var sit:=app.modal.find_child("BeachChairSit",true,false) as Button if is_instance_valid(app.modal) else null
	expect(sit!=null and not sit.disabled,"Interacting opens the chair panel")
	if sit:sit.pressed.emit()
	expect(player.get(SEAT,{}).get("cell")==World.key(SITE),"Sit uses the existing seated state")
	await capture("seated")
	app._interact()
	expect(not player.has(SEAT),"Interacting again stands up")
	var guest:="beach-chair-guest"
	world.add_player(guest,"旅客")
	var other:Dictionary=world.state.players[guest]
	other.x=41.5
	other.y=35.5
	expect(action(guest,I.BEACH_SIT,FRONT).ok,"Guest can use the other tile to take the seat")
	expect(not action(owner,I.BEACH_SIT,SITE).ok and not action(owner,I.BEACH_FOLD,SITE).ok,"One seat, and the owner cannot fold while used")
	expect(not action(owner,"move_object",FRONT,World.key(MOVED)).ok and not action(owner,"remove",SITE).ok,"Occupied chair cannot move or be removed")
	world.move_player(guest,Vector2.RIGHT,0.12)
	expect(not other.has(SEAT),"Movement leaves the seat")
	expect(not action(guest,I.BEACH_FOLD,FRONT).ok,"Guest cannot fold the owner's chair")
	app.session._send_snapshot(1)
	app._beach_chair_menu(FRONT)
	var fold:=app.modal.find_child("BeachChairFold",true,false) as Button
	expect(fold!=null and not fold.disabled,"The free chair presents a working Fold button")
	if fold and not fold.disabled:fold.pressed.emit()
	expect(world.state.objects[World.key(SITE)].get("beach_chair_folded",false) and world.blocked(SITE) and not world.blocked(FRONT),"Folding frees the footrest tile")
	await capture("folded")
	expect(not action(guest,I.BEACH_SIT,SITE).ok,"Folded chair cannot be occupied")
	other.x=40.5
	other.y=35.5
	expect(not action(owner,I.BEACH_FOLD,SITE).ok and not world.blocked(FRONT),"Opening never traps a player on the footrest tile")
	other.x=41.5
	expect(action(owner,I.BEACH_FOLD,FRONT).ok and world.blocked(FRONT),"Opening restores the full footprint")
	expect(action(owner,I.BEACH_SIT,FRONT).ok,"Opened chair is usable again")
	var saved:=World.new()
	expect(saved.load_world(path) and not saved.recovered_from_backup and saved.state.players[owner].get(SEAT,{}).get("cell")==World.key(SITE),"Primary save restores the seated player and chair")
	expect(action(owner,I.BEACH_SIT,SITE).ok and action(owner,I.BEACH_FOLD,SITE).ok,"Owner can stand and fold again")
	expect(saved.load_world(path) and not saved.blocked(FRONT),"Primary save restores the folded walkway")
	var damaged:=world.state.duplicate(true)
	damaged.objects[World.key(FRONT)].erase("beach_chair_folded")
	expect(not World.SAVE_SCHEMA.validate(damaged,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME),"Mismatched footprint state is rejected on load")
	var design:=World.BLUEPRINT_DESIGN.capture(world.state,owner,Rect2i(SITE,Vector2i(1,2)),"海邊座位",World.BUILD,World.NAMES)
	expect(design.ok and design.blueprint.pieces==[{"kind":I.BEACH_CHAIR,"x":0,"y":0,"settings":{"vertical":true}}],"Blueprint captures geometry without folding or occupancy")
	expect(action(owner,"move_object",FRONT,World.key(MOVED)).ok and not world.blocked(MOVED+Vector2i.DOWN),"Moving from the second tile retains the folded state")
	expect(action(owner,"remove",MOVED+Vector2i.DOWN).ok and player.inventory.wood==24 and player.inventory.cotton_cloth==12,"Dismantling returns a single recipe")
	if design.ok:
		var quote:=world.quote_blueprint(owner,design.blueprint,SITE,1)
		expect(quote.ok,"Rotated plan quotes a horizontal chair")
		if quote.ok:
			var laid:=world.apply_blueprint(owner,"c".repeat(32),design.blueprint,SITE,1,quote.hash)
			var wide:Dictionary=world.state.objects.get(World.key(SITE),{})
			expect(laid.ok and not I.is_vertical(wide) and not wide.get("beach_chair_folded",false) and world.blocked(SITE+Vector2i.RIGHT),"Rotated plan builds the horizontal chair open")
			app.session._send_snapshot(1)
			await capture("rotated")
	finish()
