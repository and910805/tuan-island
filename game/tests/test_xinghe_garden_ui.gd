extends SceneTree

const World:=preload("res://scripts/world.gd")
const Goals:=World.RESIDENT_GOALS
const Tasks:=preload("res://scripts/life_ui_tasks.gd")

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

func open_garden() -> void:
	app._interact()
	await process_frame
	await press("BondOpen")
	await press("XingheSharedGarden")

func test_three_players() -> void:
	var garden:=World.new()
	var cell:=World.LANYANG_LIFE.SERVICE
	for account:String in ["alice","bob","carol"]:
		garden.add_player(account,account.capitalize())
		var actor:Dictionary=garden.state.players[account]
		actor.region=World.REGIONS.LANYANG
		actor.x=cell.x+0.5
		actor.y=cell.y+0.5
	garden.state.players.alice.bonds={"xinghe":{"points":24,"talk_day":-1,"gift_day":-1}}
	expect(garden.act("alice","first",Goals.GARDEN_ACTION,cell,"bluebell").ok,"A friend of Xinghe starts the shared garden")
	expect(garden.act("bob","second",Goals.GARDEN_ACTION,cell,"orange_blossom").ok,"A visitor can choose their own flower")
	expect(not garden.act("bob","not-again",Goals.GARDEN_ACTION,cell,"chime_herb").ok,"One choice per participant")
	expect(garden.act("carol","third",Goals.GARDEN_ACTION,cell,"chime_herb").ok,"A third player finishes the same garden")
	expect(garden.state[Goals.GARDEN_KEY].map(func(pot):return pot.author)==["alice","bob","carol"],"All three actual contributors are attributed")

func run() -> void:
	root.size=Vector2i(1024,640)
	app=load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	var path:="user://xinghe-garden-test-%d.json"%OS.get_process_id()
	if app.session.host(0,"園藝島民",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	world=app.session.world
	token=app.session.profile.token
	person=world.state.players[token]
	var service:=World.LANYANG_LIFE.SERVICE
	person.region=World.REGIONS.LANYANG
	stand(service)
	expect(not world.act(token,"locked",Goals.GARDEN_ACTION,service,"bluebell").ok,"Garden creation requires friendship")
	person.bonds={"xinghe":{"points":24,"talk_day":-1,"gift_day":-1}}
	stand(service)
	await open_garden()
	await press("XinghePlant_bluebell")
	expect(world.state[Goals.GARDEN_KEY].size()==1,"First pot is placed")
	expect(app.session.snapshot[Goals.GARDEN_KEY][0].author==app.session.own_id and app.session.snapshot[Goals.GARDEN_KEY][0].name=="園藝島民","Snapshot projects the public author, not their profile token")
	var checkpoint:=World.new()
	expect(checkpoint.load_world(path) and checkpoint.state[Goals.GARDEN_KEY].size()==1,"Partial garden is already saved")
	await open_garden()
	await press("XingheInvite_milu")
	await open_garden()
	await press("XingheInvite_xinghe")
	await open_garden()
	await capture("01-garden-authors.png")
	expect(app.session.snapshot[Goals.GARDEN_KEY].map(func(pot):return pot.name)==["園藝島民","米露","星禾"],"The three chosen pots display their authors")
	await press("XingheGardenReport")
	await press("BondGoalDo")
	var sign_kind:="keepsake_xinghe_sign"
	expect(int(person.inventory.get(Goals.keepsake_item(sign_kind),0))==1,"Reporting awards one garden sign")
	stand(service+Vector2i(1,1))
	await create_timer(0.35).timeout
	await capture("02-lanyang-pots.png")
	person.region=World.REGIONS.HOME
	var spot:=Vector2i(38,33)
	stand(spot)
	expect(world.act(token,"display-sign","build",spot,sign_kind).ok,"The garden sign can be displayed at home")
	expect(app.session.shutdown(),"Save and close")
	var loaded:=World.new()
	expect(loaded.load_world(path),"Reload the saved island")
	expect(Goals.done(loaded.state.players[token],"xinghe").has(4) and loaded.state.objects.get(World.key(spot),{}).get("type")==sign_kind,"Event and placed sign survive reload")
	expect(loaded.state[Goals.GARDEN_KEY].map(func(pot):return pot.author)==[token,"milu","xinghe"],"All author records survive reload")
	for file:String in [path,path+".bak",path+".tmp"]:
		if FileAccess.file_exists(file):DirAccess.remove_absolute(file)
	test_three_players()
	app.sound.close()
	await create_timer(0.15).timeout
	print("XINGHE_GARDEN_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
