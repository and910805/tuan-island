extends SceneTree

const World=preload("res://scripts/world.gd")
const Design=preload("res://scripts/blueprint_design.gd")
const Table=World.INDUSTRY
const SEAT=World.RESIDENT_GOALS.MASTER_BENCH_SEAT
const SITE:=Vector2i(40,34)
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

func act(actor:String,verb:String,tile:Vector2i,extra:="")->Dictionary:
	serial+=1
	return world.act(actor,"shell-%d"%serial,verb,tile,extra)

func capture(name:String)->void:
	if output.is_empty() or DisplayServer.get_name()=="headless":return
	DirAccess.make_dir_recursive_absolute(output)
	await create_timer(0.27).timeout
	await RenderingServer.frame_post_draw
	expect(root.get_texture().get_image().save_png(output.path_join(name+".png"))==OK,"Capture "+name)

func finish()->void:
	app.session.shutdown()
	for suffix in ["",".bak",".writer-lock"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("SHELL_TABLE_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func valid_save(snapshot:Dictionary)->bool:
	return World.SAVE_SCHEMA.validate(snapshot,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)

func run()->void:
	app=preload("res://main.tscn").instantiate()
	root.add_child(app)
	root.size=Vector2i(1024,640) if app.arg_value("qa-size","")=="1024" else Vector2i(1280,800)
	output=app.arg_value("qa-dir","")
	path="user://shell-table-%d.json"%Time.get_ticks_usec()
	app.session.profile.token="shell-table-owner"
	if app.session.host(0,"海邊木匠",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	app.WanganUI.dismiss(app)
	world=app.session.world
	owner=app.session.peers[1]
	var person:Dictionary=world.state.players[owner]
	person.x=40.5
	person.y=33.5
	person.inventory.merge({"wood":24,"seashell":10,"flower_pot":2},true)
	world.state.time=720.0
	for tile:Vector2i in [SITE,MOVED]:world.state.removed[World.key(tile)]=true
	app.session._send_snapshot(1)
	app._build_menu()
	var shelf:Button
	for entry:Button in app.modal.find_children("BuildTab*","Button",true,false):
		if entry.text=="海邊":shelf=entry
	if shelf:shelf.pressed.emit()
	var recipe:Button=app.modal.find_child("BuildSlot_"+Table.SHELL_TABLE+"_"+str(shelf.name).trim_prefix("BuildTab"),true,false) if shelf else null
	expect(recipe!=null and recipe.is_visible_in_tree(),"The coastal shelf lists the shell table")
	if recipe:recipe.pressed.emit()
	var place:Button=app.modal.find_child("BuildPlace",true,false)
	if place:place.pressed.emit()
	expect(app.building==Table.SHELL_TABLE and app.view.build_placement_offsets(Table.SHELL_TABLE)==[Vector2i.ZERO],"Normal placement previews one tile")
	app._perform_build_action("build",SITE,Table.SHELL_TABLE)
	var key:=World.key(SITE)
	expect(world.state.objects.get(key,{}).get("type")==Table.SHELL_TABLE and world.blocked(SITE),"The table occupies one solid tile")
	expect(person.inventory.wood==16 and person.inventory.seashell==6,"Build charges the specified recipe")
	app._select_tool("hoe")
	app._interact()
	var picker:=app.modal.find_child("ShellTablePicker",true,false) as OptionButton if is_instance_valid(app.modal) else null
	expect(picker!=null,"Interact opens the owner's display picker")
	if picker==null:
		finish()
		return
	for index in picker.item_count:
		if picker.get_item_metadata(index)=="flower_pot":picker.select(index)
	(app.modal.find_child("ShellTablePut",true,false) as Button).pressed.emit()
	expect(person.inventory.flower_pot==1 and world.state.objects[key].items=={"flower_pot":1},"Displaying moves one real item into the table")
	await capture("table-menu")
	var guest:="shell-table-guest"
	world.add_player(guest,"旅客")
	var other:Dictionary=world.state.players[guest]
	other.x=41.5
	other.y=34.5
	other.blue_outfit=true
	expect(not act(guest,Table.SHELL_TAKE,SITE,"flower_pot").ok,"Guest cannot take someone else's display")
	expect(not act(owner,Table.SHELL_PUT,SITE,"seashell").ok,"The table has exactly one display spot")
	var cut:=Design.capture(world.region_snapshot("home"),owner,Rect2i(SITE,Vector2i.ONE),"桌子",World.BUILD,World.NAMES)
	expect(cut.ok and not JSON.stringify(cut).contains("flower_pot"),"Blueprint captures furniture without its displayed inventory")
	(app.modal.find_child("ShellTableSeat0",true,false) as Button).pressed.emit()
	expect(person.get(SEAT,{})=={"cell":key,"side":0},"Left seat works through the normal menu")
	expect(not act(guest,Table.SHELL_SIT,SITE,"0").ok and act(guest,Table.SHELL_SIT,SITE,"1").ok,"A guest can take the other seat, and each seat is exclusive")
	expect(not act(owner,"move_object",SITE,World.key(MOVED)).ok and not act(owner,"remove",SITE).ok,"Occupied table cannot move or be dismantled")
	app.session.peers[2]=guest
	app.session._send_snapshot(1)
	app.session.peers.erase(2)
	expect(app.session.snapshot.players.has(guest.sha256_text().left(16)),"Both seated avatars are present in the rendered snapshot")
	await capture("table-two-seats")
	var loaded:=World.new()
	expect(loaded.load_world(path) and loaded.state.objects[key].items=={"flower_pot":1},"Saved display and both seated records reload")
	var invalid:Dictionary=world.state.duplicate(true)
	invalid.players[guest][SEAT].side=0
	expect(not valid_save(invalid),"Save validation rejects two players sharing one seat")
	invalid=world.state.duplicate(true)
	invalid.objects[key].items.seashell=1
	expect(not valid_save(invalid),"Save validation rejects a second displayed item")
	app._interact()
	expect(not person.has(SEAT),"Interact stands up from a seated position")
	world.move_player(guest,Vector2.DOWN,0.25)
	expect(not other.has(SEAT),"Moving leaves the other seat")
	expect(not act(owner,"remove",SITE).ok,"Dismantling requires retrieving the display first")
	expect(act(owner,"move_object",SITE,World.key(MOVED)).ok and world.state.objects[World.key(MOVED)].items=={"flower_pot":1},"Moving the empty seats preserves the displayed item")
	expect(not act(owner,Table.SHELL_TAKE,MOVED,"seashell").ok,"A mismatched item cannot take the display")
	expect(act(owner,Table.SHELL_TAKE,MOVED,"flower_pot").ok and person.inventory.flower_pot==2,"Owner takes the exact item back")
	expect(act(owner,"remove",MOVED).ok and person.inventory.wood==24 and person.inventory.seashell==10,"Empty table dismantles with the correct refund")
	finish()
