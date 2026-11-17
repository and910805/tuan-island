extends SceneTree
## Exercises the mine doors, both station jobs, reporting, crafting and building in a local host.
const World:=preload("res://scripts/world.gd")
const Goals:=World.RESIDENT_GOALS
const Tasks:=preload("res://scripts/life_ui_tasks.gd")
const Folio:=preload("res://scripts/build_folio.gd")
const BENCH:=Vector2i(48,24)

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

func button(node_name:String) -> Button:
	if not is_instance_valid(app.modal):return null
	return app.modal.find_child(node_name,true,false) as Button

func press(node_name:String) -> void:
	var choice:=button(node_name)
	expect(choice!=null and not choice.disabled,"Enabled action: "+node_name)
	if choice!=null and not choice.disabled:choice.pressed.emit()
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
	var path:="user://bobo-rest-kit-%d.json"%OS.get_process_id()
	if app.session.host(0,"礦場旅人",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	world=app.session.world
	token=app.session.profile.token
	person=world.state.players[token]
	world.state.board=true
	world.state.picnic=true
	world.state.community={"table":World.COMMUNITY.choose_table(world.state)}
	person.region="jinguashi"
	var bobo:Vector2i=World.bond_place(world.state,"bobo")[1]
	stand(bobo)
	expect(not world.act(token,"early-kit",Goals.REST_KIT_ACTION,bobo,"sign").ok,"Cannot work outside B1")
	stand(World.MINES.ENTRY)
	app._interact()
	await process_frame
	await press("MineEnter")
	expect(world.player_region(token)=="mine_1","Mine entrance enters floor one")
	app._close_modal()
	stand(World.MINES.REST)
	expect(not world.act(token,"no-trust",Goals.REST_KIT_ACTION,World.MINES.REST,"sign").ok,"Unmet trust blocks both jobs")
	person.bonds={"bobo":{"points":14,"talk_day":-1,"gift_day":-1}}
	person.inventory.merge({"wood":2,"plank":0,"fiber":0},true)
	stand(World.MINES.REST)
	app._interact()
	await process_frame
	var crate:=button("BoboRest_box")
	expect(crate!=null and crate.disabled,"Box shows its material gate")
	expect(button("MineRest")!=null,"Existing rest action stays available")
	expect(not world.act(token,"no-materials",Goals.REST_KIT_ACTION,World.MINES.REST,"box").ok,"Server refuses an empty inventory")
	await press("BoboRest_sign")
	expect(int(person.inventory.wood)==0 and int(app.session.snapshot.own_bobo_rest_kit)==1,"Wood and first step are recorded exactly once")
	expect(int(app.session.snapshot.bobo_rest_fixtures)==1 and not app.session.snapshot.players[app.session.own_id].has(Goals.REST_KIT_KEY),"Fixtures are shared without exposing the player's personal record")
	expect(not world.act(token,"repeat-sign",Goals.REST_KIT_ACTION,World.MINES.REST,"sign").ok,"Repeated sign is denied")
	expect(not World.supply_box_unlocked(person),"Supply box still requires the event report")
	person.inventory.merge({"plank":6,"fiber":3},true)
	stand(World.MINES.REST)
	await capture("01-rest-station.png")
	await press("BoboRest_box")
	expect(person.inventory.plank==4 and person.inventory.fiber==2 and int(app.session.snapshot.own_bobo_rest_kit)==3,"Box consumes exactly its materials")
	expect(int(app.session.snapshot.bobo_rest_fixtures)==3,"Both station fixtures are shared")
	app._close_modal()
	var arrival:=app.hud.find_child("TravelArrival",true,false) as Control
	if arrival!=null:
		for candidate:Node in arrival.find_children("*","Button",true,false):
			if candidate.text=="略過":candidate.pressed.emit()
	await process_frame
	await capture("02-trail-fixtures.png")
	stand(World.MINES.UP)
	app._interact()
	await process_frame
	await press("MineUp")
	expect(world.player_region(token)=="jinguashi","B1 return reaches Jinguashi")
	app._close_modal()
	stand(bobo)
	Tasks.bond_goal(app,"bobo",3)
	await process_frame
	await press("BondGoalDo")
	expect(app.session.snapshot.resident_goals.bobo["3"].state=="done","Bobo accepts completed work")
	expect(World.exploration_level(World.exploration_points(person))<World.SUPPLY_BOX_LEVEL and World.supply_box_unlocked(person),"The event is an independent blueprint unlock")
	await capture("03-blueprint.png")
	app._close_modal()
	person.region=World.REGIONS.HOME
	world.state.objects[World.key(BENCH)]={"type":"bench","owner":token,"items":{}}
	stand(BENCH)
	app.automation_ui.workbench(app,BENCH)
	await process_frame
	var recipe:Button
	for candidate:Node in app.modal.find_children("*","Button",true,false):
		if candidate.text==World.CRAFT.supply_box_kit.name:recipe=candidate
	expect(recipe!=null,"Portable box recipe is on the workbench")
	if recipe!=null:recipe.pressed.emit()
	await process_frame
	await press("CraftRecipe")
	expect(int(person.inventory.get("supply_box_kit",0))==1,"Workbench crafts the newly unlocked box")
	var view:Dictionary=app.session.snapshot.players[app.session.own_id]
	expect(Folio.unlocked(app,view,"supply_box"),"The build catalogue also knows the blueprint")
	var spot:=BENCH+Vector2i(1,0)
	expect(world.act(token,"place-box","build",spot,"supply_box").ok,"Build action accepts the newly unlocked box")
	expect(world.state.objects.get(World.key(spot),{}).get("type")=="supply_box","Portable box is placed")
	expect(app.session.shutdown(),"Save and close")
	var loaded:=World.new()
	expect(loaded.load_world(path),"Reload the saved island")
	expect(int(loaded.state.players[token].get(Goals.REST_KIT_KEY,0))==Goals.REST_KIT_MASK,"Station steps survive reload")
	expect(World.supply_box_unlocked(loaded.state.players[token]),"Blueprint survives reload")
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	app.sound.close()
	await create_timer(0.15).timeout
	print("BOBO_REST_KIT_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
