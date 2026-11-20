extends SceneTree

const World=preload("res://scripts/world.gd")
const Industry=World.INDUSTRY
const Design=preload("res://scripts/blueprint_design.gd")
const KIND:="bamboo_tea_table"
const SEAT=World.RESIDENT_GOALS.MASTER_BENCH_SEAT
const SITE:=Vector2i(40,34)
const MOVED:=Vector2i(42,35)
const TURNED:=Vector2i(40,38)
const MUSH:=Vector2i(42,39)
var app
var world:World
var owner:String
var output:String
var path:String
var checks:=0
var failures:=0

func _initialize()->void:
	create_timer(70.0).timeout.connect(func():quit(1))
	run.call_deferred()

func expect(ok:bool,label:String)->bool:
	checks+=1
	if not ok:
		failures+=1
		push_error(label)
	return ok

func capture(name:String)->void:
	if output.is_empty() or DisplayServer.get_name()=="headless":return
	DirAccess.make_dir_recursive_absolute(output)
	await create_timer(0.3).timeout
	app.view.queue_redraw()
	await RenderingServer.frame_post_draw
	expect(root.get_texture().get_image().save_png(output.path_join(name+".png"))==OK,"Capture "+name)

func finish()->void:
	app.session.shutdown()
	app.sound.close()
	app.queue_free()
	await create_timer(0.25).timeout
	for suffix in ["",".bak",".writer-lock",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("BAMBOO_TEA_TABLE_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func obj(tile:=SITE)->Dictionary:
	return world.state.objects.get(World.key(tile),{})

func stand(token:String,tile:Vector2i,dx:=1.5,dy:=1.5)->void:
	world.state.players[token].x=float(tile.x)+dx
	world.state.players[token].y=float(tile.y)+dy

func widget(id:String)->Control:
	return app.modal.find_child(id,true,false) as Control if is_instance_valid(app.modal) else null

func act(who:String,verb:String,tile:Vector2i,extra:="")->bool:
	return world.act(who,"%s-%d"%[verb,checks],verb,tile,extra).ok

func open_as(token:String,tile:Vector2i)->void:
	stand(token,tile)
	app._close_modal()
	app.session._send_snapshot(1)
	app._interact()

func run()->void:
	app=preload("res://main.tscn").instantiate()
	root.add_child(app)
	root.size=Vector2i(1024,640) if app.arg_value("qa-size","")=="1024" else Vector2i(1280,800)
	output=app.arg_value("qa-dir","")
	path="user://bamboo-tea-table-%d.json"%Time.get_ticks_usec()
	app.session.profile.token="bamboo-tea-owner-%d"%Time.get_ticks_usec()
	if app.session.host(0,"竹林茶師",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	app.WanganUI.dismiss(app)
	world=app.session.world
	owner=app.session.peers[1]
	var person:Dictionary=world.state.players[owner]
	var guests:=["tea-guest-one","tea-guest-two","tea-guest-three"]
	for origin in [SITE,MOVED,TURNED,MUSH]:
		for offset:Vector2i in Industry.SQUARE_CELLS:world.state.removed[World.key(origin+offset)]=true
	person.inventory.merge({"bamboo":30,"wood":20,"hardwood":12,"star_mushroom":3,"feed":1,"soup":1,"mist_tea_brew":2,"ginger_tea":2,"tea_pudding":1,"garden_cookie":1,"strawberry_toast":1},true)
	person.mine_energy=40
	world.state.time=720.0
	stand(owner,SITE)
	for index in guests.size():
		world.add_player(guests[index],"茶客 %d"%(index+1),Vector2(SITE.x+0.5+index,SITE.y+2.5))
		world.state.players[guests[index]].mine_energy=[30,95,50][index]
	app.session._send_snapshot(1)

	# --- Contract and build ---------------------------------------------------------------------------
	expect(Industry.BAMBOO_TEA_TABLE==KIND,"INDUSTRY.BAMBOO_TEA_TABLE is bamboo_tea_table")
	if not expect(World.BUILD.has(KIND),"The tea table has a recipe"):
		await finish()
		return
	expect(World.BUILD[KIND].get("bamboo")==12 and World.BUILD[KIND].get("wood")==4 and World.BUILD[KIND].size()==3,"Recipe is exactly 12 bamboo and 4 wood plus the name")
	app._select_tool("hoe")
	app._perform_build_action("build",SITE,KIND)
	if not expect(obj().get("type")==KIND and obj().get("owner")==owner,"Real build action places the table"):
		await finish()
		return
	expect(person.inventory.bamboo==18 and person.inventory.wood==16,"Building spends 12 bamboo and 4 wood")
	expect(not Industry.is_vertical(obj()) and obj(SITE+Vector2i.RIGHT).get("type")==KIND,"Default is a horizontal 2x1")
	expect(world.blocked(SITE) and world.blocked(SITE+Vector2i.RIGHT) and not world.blocked(SITE+Vector2i.DOWN) and not world.blocked(SITE+Vector2i(2,0)),"Exactly two solid cells")
	expect(World.station_anchor(world.state.objects,SITE+Vector2i.RIGHT)==SITE,"The second half resolves to the anchor")
	expect(not act(owner,"build",SITE+Vector2i.RIGHT,KIND),"Overlapping builds are refused")

	# --- Serving: allowlist, real items, four-portion cap, recovery -------------------------------------
	for bad in ["soup","feed","bamboo","nonsense"]:
		expect(not act(owner,Industry.MUSHROOM_SERVE,SITE,bad),"Not allowed on the tea table: "+bad)
	expect(obj().items.is_empty() and person.inventory.soup==1 and person.inventory.feed==1,"Refusals consume nothing")
	open_as(owner,SITE)
	var picker:=widget("BambooTeaTableMeal") as OptionButton
	if expect(picker!=null and picker.item_count==5,"The owner sees only the five tea snacks in the picker"):
		for index in picker.item_count:
			if picker.get_item_metadata(index)=="garden_cookie":picker.select(index)
		(widget("BambooTeaTableServe") as Button).pressed.emit()
		expect(obj().items=={"garden_cookie":1} and int(person.inventory.get("garden_cookie",0))==0,"The picker puts one actual cookie on the table")
		(widget("BambooTeaTableTake_garden_cookie") as Button).pressed.emit()
		expect(obj().items.is_empty() and person.inventory.garden_cookie==1,"Taking back through the menu returns it")
	app._close_modal()
	for item in ["mist_tea_brew","ginger_tea","tea_pudding","garden_cookie"]:
		expect(act(owner,Industry.MUSHROOM_SERVE,SITE+Vector2i.RIGHT,item),"Owner stages "+item)
	expect(obj().items=={"mist_tea_brew":1,"ginger_tea":1,"tea_pudding":1,"garden_cookie":1} and person.inventory.get("tea_pudding",0)==0,"Real portions leave the backpack")
	expect(not act(owner,Industry.MUSHROOM_SERVE,SITE,"strawberry_toast") and person.inventory.strawberry_toast==1,"A fifth portion is refused and kept")
	expect(not act(guests[0],Industry.MUSHROOM_SERVE,SITE,"soup") and not act(guests[0],Industry.MUSHROOM_TAKE,SITE,"ginger_tea"),"Visitors cannot stage or take back")
	expect(act(owner,Industry.MUSHROOM_TAKE,SITE,"garden_cookie") and person.inventory.garden_cookie==1 and not obj().items.has("garden_cookie"),"The owner recovers a portion")
	expect(act(owner,Industry.MUSHROOM_SERVE,SITE,"strawberry_toast"),"A freed slot accepts an allowed item")
	expect(world.save() and World.SAVE_SCHEMA.validate(world.state,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME),"State with stock validates")
	var invalid:Dictionary=world.state.duplicate(true)
	invalid.objects[World.key(SITE)].items.ginger_tea=3
	expect(not World.SAVE_SCHEMA.validate(invalid,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME),"Save validation rejects five portions")
	invalid=world.state.duplicate(true)
	invalid.objects[World.key(SITE)].items={"soup":1}
	expect(not World.SAVE_SCHEMA.validate(invalid,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME),"Save validation rejects a disallowed stock item")

	# --- Seats: four sides, exclusive, eating the true item ----------------------------------------------
	expect(not act(owner,Industry.MUSHROOM_EAT,SITE,"ginger_tea") and person.mine_energy==40,"Eating requires a seat")
	for index in guests.size():
		app.session.peers[index+2]=guests[index]
		world.active_tokens[guests[index]]=true
	open_as(owner,SITE)
	for side in 4:expect(widget("BambooTeaTableSeat%d"%side) is Button,"UI offers seat %d"%side)
	expect(widget("BambooTeaTableMeal") is OptionButton and widget("BambooTeaTableServe") is Button,"Owner sees the meal picker and serve button")
	await capture("tea-table-owner-menu")
	(widget("BambooTeaTableSeat0") as Button).pressed.emit()
	expect(person.get(SEAT,{})=={"cell":World.key(SITE),"side":0},"Owner sits on side 0 through the UI")
	for index in guests.size():
		stand(guests[index],SITE)
		expect(not act(guests[index],Industry.MUSHROOM_SIT,SITE,"0"),"Occupied side 0 refuses guest %d"%index)
		expect(not act(guests[index],Industry.MUSHROOM_SIT,SITE,"4") and not act(guests[index],Industry.MUSHROOM_SIT,SITE,"-1"),"Only sides 0 to 3 exist")
		expect(act(guests[index],Industry.MUSHROOM_SIT,SITE+Vector2i.RIGHT,str(index+1)) and world.state.players[guests[index]][SEAT].side==index+1,"Guest %d takes side %d"%[index,index+1])
	app.session._send_snapshot(1)
	expect(app.session.snapshot.players.values().filter(func(p):return p.get(SEAT,{}).get("cell")==World.key(SITE)).size()==4,"Four seated players appear in the snapshot")
	app._close_modal()
	app.view.set_process(false)
	app.view.camera=(Vector2(SITE)+Vector2(1.0,0.5))*32.0-Vector2(root.size)/(2.0*app.view.view_zoom())
	await capture("tea-table-four-seated")
	var eat:Dictionary=world.state.players[guests[0]]
	expect(act(guests[0],Industry.MUSHROOM_EAT,SITE,"ginger_tea") and eat.mine_energy==42 and not obj().items.has("ginger_tea"),"A visitor eats the true item for 12 energy")
	expect(act(guests[1],Industry.MUSHROOM_EAT,SITE,"mist_tea_brew") and world.state.players[guests[1]].mine_energy==100,"Energy is capped at 100")
	open_as(owner,SITE)
	var owner_eat:=widget("BambooTeaTableEat_tea_pudding") as Button
	if expect(owner_eat!=null and not owner_eat.disabled and widget("BambooTeaTableTake_tea_pudding") is Button,"Seated owner sees Eat and Take for staged stock"):
		owner_eat.pressed.emit()
		expect(person.mine_energy==52 and obj().items=={"strawberry_toast":1},"Owner eats at the table: 40 + 12")
	app._close_modal()
	expect(not act(guests[2],Industry.MUSHROOM_EAT,MOVED,"ginger_tea"),"Eating far from a table is refused")

	# --- Occupied/loaded tables cannot be removed or moved -----------------------------------------------
	expect(not act(owner,"remove",SITE+Vector2i.RIGHT) and not act(owner,"move_object",SITE+Vector2i.RIGHT,World.key(MOVED)) and obj().get("type")==KIND,"Occupied table cannot be removed or moved")
	for token in [owner]+guests:act(token,Industry.MUSHROOM_SIT,SITE,"leave")
	expect(not world.state.players[guests[2]].has(SEAT),"Everyone can stand")
	expect(not world.act(owner,"loaded","remove",SITE).ok and obj().get("type")==KIND,"Remaining stock blocks removal")
	var moved:=world.act(owner,"move","move_object",SITE+Vector2i.RIGHT,World.key(MOVED))
	if expect(moved.ok,"Unoccupied table moves: "+str(moved.get("message",""))):
		expect(obj().is_empty() and obj(MOVED).get("items")=={"strawberry_toast":1} and World.station_anchor(world.state.objects,MOVED+Vector2i.RIGHT)==MOVED,"Move retains items and both halves resolve")
		expect(world.save(),"Saves after the move")
		var loaded:=World.new()
		expect(loaded.load_world(path) and loaded.state.objects[World.key(MOVED)].items=={"strawberry_toast":1},"Stock survives reload")
	stand(owner,MOVED)
	expect(act(owner,Industry.MUSHROOM_TAKE,MOVED,"strawberry_toast") and world.act(owner,"remove","remove",MOVED+Vector2i.RIGHT).ok,"An empty table is dismantled by either half")
	expect(obj(MOVED).is_empty() and obj(MOVED+Vector2i.RIGHT).is_empty() and not world.blocked(MOVED+Vector2i.RIGHT) and person.inventory.bamboo==30 and person.inventory.wood==20,"Both cells clear and the recipe is refunded")

	# --- Blueprint: capture horizontal, rotate to 1x2 ----------------------------------------------------
	stand(owner,SITE)
	app._perform_build_action("build",SITE,KIND)
	var cut:=Design.capture(world.region_snapshot("home"),owner,Rect2i(SITE,Vector2i(2,1)),"低腳竹茶桌",World.BUILD,World.NAMES)
	if expect(cut.ok and cut.blueprint.pieces.size()==1 and cut.blueprint.pieces[0].kind==KIND and cut.blueprint.width==2 and cut.blueprint.height==1,"Blueprint captures one 2x1 piece"):
		expect(not JSON.stringify(cut.blueprint).contains("strawberry"),"Blueprint carries no food")
		var turned:=Design.rotate(cut.blueprint,1,World.BUILD,World.NAMES)
		expect(turned.get("ok")==true and turned.blueprint.width==1 and turned.blueprint.height==2,"One quarter turn gives a 1x2 blueprint")
		stand(owner,TURNED)
		var quote:=world.quote_blueprint(owner,cut.blueprint,TURNED,1)
		if expect(quote.get("ok")==true,"Quote for the turned placement succeeds: "+str(quote.get("problems",[]))):
			var applied:=world.apply_blueprint(owner,"%016x%016x"%[Time.get_ticks_usec(),randi()],cut.blueprint,TURNED,1,str(quote.hash))
			expect(applied.get("ok")==true and Industry.is_vertical(obj(TURNED)) and obj(TURNED).items.is_empty(),"Turned placement is vertical and empty")
			expect(world.blocked(TURNED) and world.blocked(TURNED+Vector2i.DOWN) and World.station_anchor(world.state.objects,TURNED+Vector2i.DOWN)==TURNED,"The vertical halves are solid and share an anchor")
			expect(act(owner,Industry.MUSHROOM_SIT,TURNED+Vector2i.DOWN,"3") and act(owner,Industry.MUSHROOM_SERVE,TURNED,"garden_cookie"),"The vertical table seats and serves")
			app.session._send_snapshot(1)
			app.view.camera=(Vector2(TURNED)+Vector2(0.5,1.0))*32.0-Vector2(root.size)/(2.0*app.view.view_zoom())
			await capture("tea-table-vertical")
			act(owner,Industry.MUSHROOM_SIT,TURNED,"leave")

	# --- Ordinary mushroom table: past recipes accepted, still itself ------------------------------------
	person.inventory.hardwood=12
	person.inventory.star_mushroom=3
	person.inventory.garden_cookie=1
	stand(owner,MUSH,0.5,2.5)
	if not expect(act(owner,"build",MUSH,Industry.MUSHROOM_TABLE) and obj(MUSH).get("type")==Industry.MUSHROOM_TABLE,"Mushroom table still builds"):
		await finish()
		return
	for item in ["soup","ginger_tea","garden_cookie"]:expect(act(owner,Industry.MUSHROOM_SERVE,MUSH,item),"Mushroom table accepts "+item)
	expect(not act(owner,Industry.MUSHROOM_SERVE,MUSH,"feed") and obj(MUSH).items=={"soup":1,"ginger_tea":1,"garden_cookie":1},"It still rejects feed")
	expect(act(owner,Industry.MUSHROOM_SIT,MUSH,"0") and act(owner,Industry.MUSHROOM_EAT,MUSH,"soup"),"Seat and eat work on the mushroom table")
	await finish()
