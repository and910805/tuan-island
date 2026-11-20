extends SceneTree

const World=preload("res://scripts/world.gd")
const Design=preload("res://scripts/blueprint_design.gd")
const Bed=World.INDUSTRY
const SEAT=World.RESIDENT_GOALS.MASTER_BENCH_SEAT
const SITE:=Vector2i(40,34)
const MOVED:=Vector2i(43,34)
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
	print("MUSHROOM_TABLE_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func run()->void:
	app=preload("res://main.tscn").instantiate()
	root.add_child(app)
	root.size=Vector2i(1024,640) if app.arg_value("qa-size","")=="1024" else Vector2i(1280,800)
	output=app.arg_value("qa-dir","")
	path="user://mushroom-table-%d.json"%Time.get_ticks_usec()
	app.session.profile.token="mushroom-table-owner"
	if app.session.host(0,"森林廚師",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	app.WanganUI.dismiss(app)
	world=app.session.world
	owner=app.session.peers[1]
	var person:Dictionary=world.state.players[owner]
	person.x=41.5
	person.y=33.5
	person.mine_energy=34
	person.inventory.merge({"hardwood":24,"star_mushroom":8,"soup":4,"bread":2,"feed":2},true)
	world.state.time=720.0
	for origin in [SITE,MOVED]:
		for offset:Vector2i in Bed.SQUARE_CELLS:world.state.removed[World.key(origin+offset)]=true
	app.session._send_snapshot(1)
	app._build_menu()
	for entry:Button in app.modal.find_children("BuildTab*","Button",true,false):
		if entry.text=="蘑菇森林":
			entry.pressed.emit()
			press("BuildSlot_"+Bed.MUSHROOM_TABLE+"_"+str(entry.name).trim_prefix("BuildTab"))
			break
	press("BuildPlace")
	expect(app.building==Bed.MUSHROOM_TABLE and app.view.build_placement_offsets(Bed.MUSHROOM_TABLE)==Bed.SQUARE_CELLS,"Build mode previews the table's 2x2 footprint")
	app._perform_build_action("build",SITE,Bed.MUSHROOM_TABLE)
	var key:=World.key(SITE)
	if not expect(world.state.objects.get(key,{}).get("type")==Bed.MUSHROOM_TABLE,"Build places the table"):
		finish()
		return
	expect(person.inventory.hardwood==12 and person.inventory.star_mushroom==5,"Build charges twelve hardwood and three mushrooms")
	for offset:Vector2i in Bed.SQUARE_CELLS:
		expect(world.blocked(SITE+offset) and World.station_anchor(world.state.objects,SITE+offset)==SITE,"Each solid tile identifies the same table")
	app._select_tool("hoe")
	app._interact()
	var picker:=app.modal.find_child("MushroomTableMeal",true,false) as OptionButton if is_instance_valid(app.modal) else null
	if not expect(picker!=null,"Interact from the second column opens the dining menu"):
		finish()
		return
	for item:String in ["soup","bread","soup","bread"]:
		for index in picker.item_count:
			if picker.get_item_metadata(index)==item:picker.select(index)
		press("MushroomTableServe")
	expect(world.state.objects[key].items=={"soup":2,"bread":2} and person.inventory.soup==2 and person.inventory.bread==0,"Four portions move from the backpack to the shared table")
	expect(not world.act(owner,"full","mushroom_table_serve",SITE,"soup").ok,"A fifth portion is refused without consuming inventory")
	expect(not world.act(owner,"eat-before-seat","mushroom_table_eat",SITE,"soup").ok,"Eating requires sitting at this table")
	await capture("dining-menu")
	press("MushroomTableSeat0")
	expect(person.get(SEAT,{})=={"cell":key,"side":0},"Owner takes first seat through UI")
	var guests:=["mushroom-guest-one","mushroom-guest-two","mushroom-guest-three"]
	for index in guests.size():
		var guest:String=guests[index]
		world.add_player(guest,"旅客 %d"%(index+1),Vector2(39.5+index,32.75))
		world.state.players[guest].mine_energy=30
		world.state.players[guest].blue_outfit=index%2==0
		expect(not world.act(guest,"taken","mushroom_table_sit",SITE+Vector2i.RIGHT,"0").ok,"Occupied seat refuses a guest")
		expect(world.act(guest,"seat","mushroom_table_sit",SITE+Vector2i.ONE,str(index+1)).ok,"Each remaining seat can be taken")
		app.session.peers[index+2]=guest
	app.session._send_snapshot(1)
	for index in guests.size():app.session.peers.erase(index+2)
	expect(app.session.snapshot.players.values().filter(func(p):return p.get(SEAT,{}).get("cell")==key).size()==4,"All four seated players appear in the snapshot")
	expect(not world.act(guests[0],"guest-take","mushroom_table_take",SITE,"bread").ok,"The guest cannot withdraw food into their backpack")
	expect(not world.act(owner,"busy-move","move_object",SITE+Vector2i.RIGHT,World.key(MOVED)).ok,"Someone seated prevents moving")
	await capture("four-player-menu")
	app._close_modal()
	await capture("four-players-at-table")
	var loaded:=World.new()
	expect(loaded.load_world(path) and loaded.state.objects[key].items=={"soup":2,"bread":2} and loaded.state.players[guests[2]][SEAT].side==3,"Food and occupied seats survive saving")
	var invalid:Dictionary=world.state.duplicate(true)
	invalid.objects[key].items.soup=3
	expect(not World.SAVE_SCHEMA.validate(invalid,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME),"Save validation rejects overflow meals")
	var cut:=Design.capture(world.region_snapshot("home"),owner,Rect2i(SITE,Vector2i(2,2)),"森林餐桌",World.BUILD,World.NAMES)
	expect(cut.ok and not JSON.stringify(cut.blueprint).contains("soup"),"Blueprint captures the entire assembly without food")
	expect(world.act(guests[0],"eat","mushroom_table_eat",SITE,"soup").ok and world.state.players[guests[0]].mine_energy==42,"Seated guest eats one serving and recovers twelve energy")
	app._interact()
	press("MushroomTableEat_soup")
	expect(int(person.mine_energy)==46 and not world.state.objects[key].items.has("soup"),"Owner eats at the table, consuming the final soup")
	press("MushroomTableSeat0")
	expect(not person.has(SEAT),"The occupied seat button lets its user stand")
	app._close_modal()
	for guest:String in guests:world.move_player(guest,Vector2.UP,0.1)
	expect(not world.act(owner,"loaded-remove","remove",SITE).ok,"Remaining food prevents dismantling")
	var moved:=world.act(owner,"move","move_object",SITE+Vector2i.ONE,World.key(MOVED))
	expect(moved.ok and world.state.objects.get(World.key(MOVED),{}).get("items")=={"bread":2},"Moving a free table preserves the remaining meal portions")
	for index in range(2):
		expect(world.act(owner,"take-bread-%d"%index,"mushroom_table_take",MOVED,"bread").ok,"Owner can recover each uneaten portion")
	expect(world.act(owner,"remove","remove",MOVED+Vector2i.RIGHT).ok and person.inventory.hardwood==24 and person.inventory.star_mushroom==8,"Empty table refunds one recipe")
	finish()
