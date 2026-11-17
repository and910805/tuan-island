extends SceneTree

const World:=preload("res://scripts/world.gd")
const Industry:=World.INDUSTRY

var app
var world:World
var token:String
var person:Dictionary
var checks:=0
var failures:=0

func _initialize() -> void:run.call_deferred()

func expect(ok:bool,message:String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)

func stand(cell:Vector2i) -> void:
	person.x=cell.x+0.5
	person.y=cell.y+0.5
	app.session.rates[1].clear()
	app.session._send_snapshot(1)

func button(id:String) -> Button:
	return app.modal.find_child(id,true,false) as Button if is_instance_valid(app.modal) else null

func press(id:String) -> void:
	var node:=button(id)
	expect(node!=null and not node.disabled,"Enabled action: "+id)
	if node!=null and not node.disabled:node.pressed.emit()
	await process_frame
	await process_frame

func capture(file_name:String) -> void:
	if DisplayServer.get_name()=="headless":return
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--capture-dir="):continue
		await RenderingServer.frame_post_draw
		expect(root.get_texture().get_image().save_png(arg.trim_prefix("--capture-dir=").path_join(file_name))==OK,"Capture "+file_name)

func run() -> void:
	root.size=Vector2i(1024,640)
	app=load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	var path:="user://assembly-%d.json"%OS.get_process_id()
	if app.session.host(0,"裝配島民",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	world=app.session.world
	token=app.session.profile.token
	person=world.state.players[token]
	var bench:=Vector2i(37,34)
	var site:=Vector2i(40,34)
	var end:=site+Vector2i.RIGHT
	var table_key:=World.key(site)
	world.state.objects[World.key(bench)]={"type":"bench","owner":token,"items":{}}
	person.inventory.merge({"hardwood":20,"iron_ingot":21,"woodwork_parts":8,"glass":4,"copper_ingot":6,"stone":4},true)
	stand(end+Vector2i.DOWN)
	expect(not world.act(token,"no-workshop","build",site,Industry.ASSEMBLY_TABLE).ok,
		"Assembly table needs the workshop upgrade")
	stand(bench+Vector2i.DOWN)
	expect(not world.act(token,"low-workshop","upgrade_workshop",bench).ok,"Workshop promotion requires crafting level six")
	person.crafting_points=World.CRAFTING_LEVEL_THRESHOLDS[World.WORKSHOP_LEVEL-1]
	stand(bench+Vector2i.DOWN)
	app._interact()
	await process_frame
	await press("UpgradeWorkshop")
	expect(person.get("workshop_upgraded",false),"Workbench performs the actual upgrade")
	app._close_modal()
	stand(end+Vector2i.DOWN)
	app._perform_build_action("build",site,Industry.ASSEMBLY_TABLE)
	await process_frame
	expect(world.state.objects.get(table_key,{}).get("type")==Industry.ASSEMBLY_TABLE,"Build the assembly table")
	if not world.state.objects.has(table_key):
		quit(1)
		return
	expect(person.inventory.hardwood==0 and person.inventory.iron_ingot==15 and person.inventory.woodwork_parts==4,
		"Build costs twenty hardwood, six iron, and four woodworking parts")
	expect(world.blocked(site) and world.blocked(end) and World.station_anchor(world.state.objects,end)==site,
		"Two blocked cells resolve to one station")
	stand(end+Vector2i.DOWN)
	await create_timer(0.35).timeout
	await capture("assembly-field.png")
	app._interact()
	await process_frame
	var medium:=button("Assemble_medium_sprinkler")
	expect(medium!=null and medium.disabled,"Farming gate appears in the assembly menu")
	person.harvests=World.FARMING_LEVEL_THRESHOLDS[World.LARGE_SPRINKLER_LEVEL-1]
	stand(end+Vector2i.DOWN)
	await create_timer(0.3).timeout
	await capture("assembly-recipes.png")
	for kind:String in Industry.SPRINKLER_KITS:
		await press("Assemble_"+kind)
		expect(int(person.inventory.get(Industry.SPRINKLER_KITS[kind],0))==1,"Assembled exactly one "+kind)
	expect(person.inventory.stone==0 and person.inventory.copper_ingot==0 and person.inventory.iron_ingot==0
		and person.inventory.glass==0 and person.inventory.woodwork_parts==0,"Assembly debits the same material counts as direct construction")
	var journal:=world.ledger_view(token)
	expect(journal.filter(func(entry):return entry.get("act")=="assemble" and entry.get("kind")=="craft").size()==3,
		"The transaction journal records the three assemblies once")
	app._close_modal()
	var plots:=[Vector2i(39,35),Vector2i(40,36),Vector2i(42,36)]
	var index:=0
	for kind:String in Industry.SPRINKLER_KITS:
		var plot:Vector2i=plots[index]
		stand(plot+Vector2i.DOWN)
		expect(world.act(token,"place-"+kind,"build",plot,kind).ok,"The kit can be placed through normal construction")
		var obj:Dictionary=world.state.objects.get(World.key(plot),{})
		expect(obj.get("sprinkler_daily",false) and obj.get("assembled_sprinkler",false),"Kit yields the daily sprinkler model")
		index+=1
	var reloaded:=World.new()
	expect(reloaded.load_world(path) and reloaded.state.players[token].workshop_upgraded,
		"Workshop promotion and assembly table survive restart")
	var large:Vector2i=plots[2]
	stand(large+Vector2i.DOWN)
	expect(world.act(token,"refund-kit","remove",large).ok and person.inventory.large_sprinkler_kit==1 and person.inventory.iron_ingot==0,
		"Dismantle returns the assembled kit without producing raw materials")
	expect(reloaded.load_world(path) and int(reloaded.state.players[token].inventory.large_sprinkler_kit)==1,
		"Refunded kit and undo entry both survive reload")
	var design:=World.BLUEPRINT_DESIGN
	var snapshot:={"objects":world.state.objects}
	var blueprint:=design.capture(snapshot,token,Rect2i(site,Vector2i(2,1)),"裝配桌",World.BUILD,World.NAMES)
	expect(blueprint.ok and blueprint.blueprint.pieces.size()==1,"Capture the two-cell station as one blueprint piece")
	if blueprint.ok:
		var rotated:=design.rotate(blueprint.blueprint,1,World.BUILD,World.NAMES)
		expect(rotated.ok and rotated.blueprint.pieces[0].settings.vertical,"Blueprint rotates the assembly table")
	app.session.shutdown()
	for file:String in [path,path+".bak",path+".tmp"]:
		if FileAccess.file_exists(file):DirAccess.remove_absolute(file)
	app.sound.close()
	await create_timer(0.15).timeout
	print("ASSEMBLY_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
