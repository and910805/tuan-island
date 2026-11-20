extends SceneTree

const World=preload("res://scripts/world.gd")
const Kind:=World.INDUSTRY.ACORN_CABINET
const Access:=World.INDUSTRY.CABINET_ACCESS
const SITE:=Vector2i(42,34)
const MOVED:=Vector2i(43,34)
const FILL:=["wood","stone","fiber","hardwood","glass","chime_herb","star_mushroom","wheat","radish","sapling","clay","copper_ore","iron_ore","plank","flour","charcoal"]
const EXTRA:="copper_ingot"
var app
var world:World
var owner:String
var output:String
var path:String
var checks:=0
var failures:=0

func _initialize()->void:
	run.call_deferred()

func expect(success:bool,label:String)->bool:
	checks+=1
	if not success:
		failures+=1
		push_error(label)
	return success

func widget(name:String)->Node:
	return app.modal.find_child(name,true,false) if is_instance_valid(app.modal) else null

func press(name:String)->bool:
	var control:=widget(name) as Button
	if not expect(control!=null and not control.disabled,"Available button "+name):return false
	control.pressed.emit()
	return true

func choose(item:String)->void:
	var control:=widget("CabinetInventory") as OptionButton
	if not expect(control!=null,"Backpack picker is visible"):return
	for index in control.item_count:
		if control.get_item_metadata(index)==item:
			control.select(index)
			control.item_selected.emit(index)
			return
	expect(false,"Backpack option "+item)

func frame(name:String)->void:
	if output.is_empty() or DisplayServer.get_name()=="headless":return
	await create_timer(0.28).timeout
	await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute(output)
	expect(root.get_texture().get_image().save_png(output.path_join(name+".png"))==OK,"Screenshot "+name)

func finish()->void:
	app.session.shutdown()
	app.sound.close()
	app.queue_free()
	await create_timer(0.18).timeout
	for suffix in ["",".bak",".writer-lock"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("ACORN_CABINET_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func box(at:=SITE)->Dictionary:
	return world.state.objects.get(World.key(at),{})

func valid_save(state:Dictionary)->bool:
	return World.SAVE_SCHEMA.validate(state,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)

func run()->void:
	app=preload("res://main.tscn").instantiate()
	root.add_child(app)
	root.size=Vector2i(1024,640) if app.arg_value("qa-size","")=="1024" else Vector2i(1280,800)
	output=app.arg_value("qa-dir","")
	path="user://acorn-cabinet-%d.json"%Time.get_ticks_usec()
	app.session.profile.token="acorn-cabinet-owner"
	if app.session.host(0,"森林木匠",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	app.WanganUI.dismiss(app)
	world=app.session.world
	owner=app.session.peers[1]
	var person:Dictionary=world.state.players[owner]
	person.x=42.5
	person.y=33.1
	person.inventory.merge({"hardwood":19,"fiber":7},true)
	for item in FILL:
		if item not in ["hardwood","fiber"]:person.inventory[item]=3
	person.inventory[EXTRA]=4
	world.state.time=720.0
	for tile in [SITE,MOVED]:world.state.removed[World.key(tile)]=true
	app.session._send_snapshot(1)
	app._build_menu()
	for entry:Button in app.modal.find_children("BuildTab*","Button",true,false):
		if entry.text=="蘑菇森林":
			entry.pressed.emit()
			press("BuildSlot_"+Kind+"_"+str(entry.name).trim_prefix("BuildTab"))
			break
	press("BuildPlace")
	app._perform_build_action("build",SITE,Kind)
	if not expect(box().get("type")==Kind,"Build menu places the cabinet"):
		await finish()
		return
	expect(person.inventory.hardwood==3 and person.inventory.fiber==3 and world.blocked(SITE),"Charges the correct recipe and occupies one tile")
	app._select_tool("hoe")
	await frame("cabinet-in-world")
	app._interact()
	var grid:=widget("CabinetSlots") as GridContainer
	if not expect(grid!=null and grid.columns==4 and grid.get_child_count()==16,"Interact opens 4×4 storage"):
		await finish()
		return
	choose("wood")
	press("CabinetDeposit")
	expect(box().items.get("wood")==1 and person.inventory.wood==2,"Deposit uses actual inventory and refreshes the grid")
	for item:String in FILL:
		if item=="wood":continue
		expect(world.act(owner,"fill-"+item,"deposit_exact",SITE,item+":1").ok,"Stores a stack of "+item)
	app.session._send_snapshot(1)
	var summary:=widget("CabinetSummary") as Label
	var deadline:=Time.get_ticks_msec()+1500
	while summary.text!="已用 16 / 16 格" and Time.get_ticks_msec()<deadline:
		await create_timer(0.05).timeout
	expect(summary.text=="已用 16 / 16 格","Counter counts sixteen occupied slots: "+summary.text)
	await frame("cabinet-private")
	choose(EXTRA)
	expect(widget("CabinetDeposit").disabled,"UI refuses a new stack at capacity")
	expect(not world.act(owner,"overflow","deposit",SITE,EXTRA).ok and person.inventory[EXTRA]==4,"Server independently rejects a seventeenth stack")
	choose("wood")
	press("CabinetDeposit")
	expect(box().items.wood==2 and box().items.size()==16,"Existing stacks still accept items at capacity")
	var guest:="acorn-cabinet-guest"
	world.add_player(guest,"訪客",Vector2(43.5,33.5))
	var key:=World.key(SITE)
	var guest_box:Dictionary=app.session.public_state("home",guest).objects[key]
	expect(guest_box.locked and guest_box.items.is_empty() and box().items.size()==16,"Private snapshots redact every stack from a guest")
	expect(not world.act(guest,"locked","withdraw",SITE,"wood").ok,"Private access also blocks guest requests")
	expect(not world.act(guest,"toggle",Access,SITE,"island").ok,"Only the owner can change the policy")
	press("CabinetAccess")
	expect(box().cabinet_shared and not app.session.public_state("home",guest).objects[key].get("locked",false),"Owner opens both reading and transfers to the island")
	expect(world.act(guest,"take","withdraw_all",SITE,"wood").ok and not box().items.has("wood"),"Removing an entire stack frees its slot")
	expect(world.act(owner,"fill-extra","deposit_all",SITE,EXTRA).ok and box().items.size()==16,"A different item can now use the freed slot")
	app.session._send_snapshot(1)
	await frame("cabinet-shared")
	var reload:=World.new()
	expect(reload.load_world(path) and reload.state.objects[key].cabinet_shared and reload.state.objects[key].items.size()==16,"Sharing, quantities, and contents survive reload")
	var invalid:=world.state.duplicate(true)
	invalid.objects[key].items.wood=1
	expect(not valid_save(invalid),"Save validator rejects over capacity")
	invalid=world.state.duplicate(true)
	invalid.objects[key].cabinet_shared="true"
	expect(not valid_save(invalid),"Save validator rejects invalid share settings")
	press("CabinetAccess")
	expect(app.session.public_state("home",guest).objects[key].items.is_empty() and not world.act(guest,"revoked","withdraw",SITE,EXTRA).ok,"Closing access immediately redacts and denies")
	var plan:=World.BLUEPRINT_DESIGN.capture(world.region_snapshot("home"),owner,Rect2i(SITE,Vector2i.ONE),"橡果櫃",World.BUILD,World.NAMES)
	expect(plan.ok and plan.blueprint.pieces==[{"kind":Kind,"x":0,"y":0}],"Blueprint captures the cabinet without any stored items or sharing preferences")
	expect(not world.act(owner,"remove-full","remove",SITE).ok,"A stocked cabinet cannot be dismantled")
	expect(world.act(owner,"move","move_object",SITE,World.key(MOVED)).ok and box(MOVED).items.size()==16 and not box(MOVED).get("cabinet_shared",false),"Moving an occupied cabinet preserves its inventory and policy")
	for item:String in box(MOVED).items.keys():
		expect(world.act(owner,"empty-"+item,"withdraw_all",MOVED,item).ok,"Retrieves all of "+item)
	expect(world.act(owner,"remove-empty","remove",MOVED).ok and box(MOVED).is_empty(),"Owner can dismantle the empty cabinet")
	await finish()
