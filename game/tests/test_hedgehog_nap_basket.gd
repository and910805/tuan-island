extends SceneTree

const World=preload("res://scripts/world.gd")
const Hedgehog=World.Hedgehog
const KIND:=World.INDUSTRY.HEDGEHOG_BASKET
const PRIMARY:=Vector2i(44,40)
const BACKUP:=Vector2i(42,40)
const FAR:=Vector2i(44,45)
var app
var world:World
var owner:String
var path:String
var output:String
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

func press(name:String)->bool:
	var control:=app.modal.find_child(name,true,false) as Button if is_instance_valid(app.modal) else null
	if not expect(control!=null and not control.disabled,"Available button "+name):return false
	control.pressed.emit()
	return true

func press_text(caption:String)->bool:
	var buttons:Array=app.modal.find_children("*","Button",true,false) if is_instance_valid(app.modal) else []
	for control:Button in buttons:
		if control.text==caption and not control.disabled:
			control.pressed.emit()
			return true
	return expect(false,"Find wildlife action "+caption)

func at(position:Vector2)->void:
	world.state.players[owner].x=position.x
	world.state.players[owner].y=position.y
	app.session._send_snapshot(1)

func frame(name:String)->Image:
	if DisplayServer.get_name()=="headless":return null
	await create_timer(0.35).timeout
	await RenderingServer.frame_post_draw
	var image:=root.get_texture().get_image()
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
		expect(image.save_png(output.path_join(name+".png"))==OK,"Screenshot "+name)
	return image

func finish()->void:
	app.session.shutdown()
	app.sound.close()
	app.queue_free()
	await create_timer(0.2).timeout
	for suffix in ["",".bak",".writer-lock"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("HEDGEHOG_NAP_BASKET_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func chosen()->Vector2i:
	return Hedgehog.nap_cell(world.region_snapshot("home"),world.state.players[owner])

func center(tile:Vector2i)->Vector2:
	return Vector2(tile)+Vector2(0.5,0.5)

func pixel_on_basket()->Vector2i:
	var at_pixel:Vector2=app.view.screen(Vector2(PRIMARY)+Vector2(0.5,0.66))
	return Vector2i((at_pixel*app.view.view_zoom()).round())

func run()->void:
	app=preload("res://main.tscn").instantiate()
	root.add_child(app)
	root.size=Vector2i(1024,640) if app.arg_value("qa-size","")=="1024" else Vector2i(1280,800)
	output=app.arg_value("qa-dir","")
	path="user://hedgehog-nap-basket-%d.json"%Time.get_ticks_usec()
	app.session.profile.token="nap-basket-owner"
	if app.session.host(0,"庭院觀察員",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	app.WanganUI.dismiss(app)
	world=app.session.world
	owner=app.session.peers[1]
	var person:Dictionary=world.state.players[owner]
	person.inventory.merge({"wood":18,"fiber":30,"radish":1},true)
	world.state.time=720.0
	var dish:=Hedgehog.site(world.state)
	for tile in [PRIMARY,BACKUP,FAR]:world.state.removed[World.key(tile)]=true
	at(Vector2(44.5,39.1))
	app._build_menu()
	for entry:Button in app.modal.find_children("BuildTab*","Button",true,false):
		if entry.text=="蘑菇森林":
			entry.pressed.emit()
			press("BuildSlot_"+KIND+"_"+str(entry.name).trim_prefix("BuildTab"))
			break
	press("BuildPlace")
	expect(app.building==KIND and app.view.build_placement_offsets(KIND)==[Vector2i.ZERO],"Catalogue selects a one-tile basket")
	app._perform_build_action("build",PRIMARY,KIND)
	if not expect(world.state.objects.get(World.key(PRIMARY),{}).get("type")==KIND,"The normal build flow places the nap basket"):
		await finish()
		return
	expect(person.inventory.wood==12 and person.inventory.fiber==20 and not world.blocked(PRIMARY),"Recipe is correct and the basket is passable")
	expect(chosen()==Hedgehog.NO_BASKET and not person.has("hedgehog_visit_day"),"Building a basket cannot schedule a visit")
	world.move_player(owner,Vector2.DOWN,0.35)
	expect(Vector2i(Vector2(person.x,person.y).floor())==PRIMARY,"Normal movement steps onto the basket tile")
	app._select_tool("hoe")
	at(center(dish))
	expect(not world.act(owner,"cover","move_object",PRIMARY,World.key(dish)).ok,"The food dish remains accessible")
	app._interact()
	if not press_text("留一顆奶白蘿蔔"):
		await finish()
		return
	expect(person.inventory.radish==0 and chosen()==Hedgehog.NO_BASKET,"Only the usual food action schedules a visit")
	world.state.time=World.WEATHER.DAY_SECONDS+359.0
	expect(Hedgehog.phase(person,world.state.time)=="waiting" and chosen()==Hedgehog.NO_BASKET,"No visitor before 06:00")
	world.state.time+=1.0
	app.session._send_snapshot(1)
	expect(Hedgehog.phase(person,world.state.time)=="visiting" and chosen()==Hedgehog.NO_BASKET,"Arrives at the food plate first")
	var before:=await frame("basket-before-observation")
	app._interact()
	if not press_text("靜靜觀察"):
		await finish()
		return
	expect(chosen()==PRIMARY and Hedgehog.phase(person,world.state.time)=="visited","Observed hedgehog chooses the nearest basket")
	var after:=await frame("basket-hedgehog-nap")
	if after!=null:
		expect(app.view.hedgehog_nap_cell==PRIMARY,"The drawn world places the napping visitor on the basket")
		var pixel:=pixel_on_basket()
		expect(not before.get_pixelv(pixel).is_equal_approx(after.get_pixelv(pixel)),"Rendered body covers the previously empty cushion")
	var plan:=World.BLUEPRINT_DESIGN.capture(world.region_snapshot("home"),owner,Rect2i(PRIMARY,Vector2i.ONE),"午睡籃",World.BUILD,World.NAMES)
	expect(plan.ok and plan.blueprint.pieces==[{"kind":KIND,"x":0,"y":0}],"A blueprint captures the basket without an animal")
	var invalid:Dictionary=world.state.duplicate(true)
	invalid.objects[World.key(PRIMARY)].items.wood=1
	expect(not World.SAVE_SCHEMA.validate(invalid,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME),"The basket cannot hold inventory in a save")
	var visitor:=World.new()
	expect(visitor.load_world(path) and Hedgehog.nap_cell(visitor.region_snapshot("home"),visitor.state.players[owner])==PRIMARY,"Reopening the save restores the active visit and basket")
	world.add_player("nap-visitor","來訪居民",Vector2(43.5,39.5))
	expect(Hedgehog.nap_cell(world.region_snapshot("home"),world.state.players["nap-visitor"])==Hedgehog.NO_BASKET,"A neighbour without a scheduled visit does not see an extra animal")
	expect(world.act(owner,"backup","build",BACKUP,KIND).ok and chosen()==PRIMARY,"A further basket does not replace the nearest one")
	expect(world.act(owner,"remove","remove",PRIMARY).ok and chosen()==BACKUP,"Removing the nearest basket sends the already arrived visitor to the next basket")
	expect(world.act(owner,"remove-backup","remove",BACKUP).ok and chosen()==Hedgehog.NO_BASKET,"With no basket, the existing visit stays at the plate")
	at(center(FAR+Vector2i.UP))
	expect(world.act(owner,"build-far","build",FAR,KIND).ok and chosen()==Hedgehog.NO_BASKET,"A decoration outside six tiles does not draw the visitor away")
	world.state.time=World.WEATHER.DAY_SECONDS+660.0
	expect(chosen()==Hedgehog.NO_BASKET and Hedgehog.phase(person,world.state.time)=="empty","The scheduled visit ends at 11:00")
	await finish()
