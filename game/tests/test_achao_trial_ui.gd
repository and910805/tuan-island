extends SceneTree

const World:=preload("res://scripts/world.gd")
const Goals:=World.RESIDENT_GOALS
const Tasks:=preload("res://scripts/life_ui_tasks.gd")
const Music:=preload("res://scripts/scene_music.gd")

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

func open_voyage() -> void:
	app._interact()
	await process_frame
	await press("AchaoVoyage")

func check_voyage_audio(aboard:bool)->void:
	if DisplayServer.get_name()=="headless":return
	var snapshot:Dictionary=app.session.snapshot
	var audio=app.sound
	if aboard:
		expect(audio.music.scene_id=="island_voyage" and audio.music.current.playing,"Departure starts the voyage music")
		expect(audio.ambience_kind=="surf" and audio.ambience.playing,"The voyage plays its own swell")
		return
	var track:=Music.local_track(snapshot,"home",snapshot.players[app.session.own_id])
	if track.is_empty():track=Music.track_for("home",float(snapshot.time))
	expect(audio.music.scene_id==track and audio.music.current.playing,"Return resumes the destination music")
	expect(audio.ambience_kind!="surf" and audio.ambience.playing,"Return restores shore ambience")

func run() -> void:
	root.size=Vector2i(1024,640)
	app=load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	var path:="user://achao-voyage-test-%d.json"%OS.get_process_id()
	if app.session.host(0,"試航島民",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	world=app.session.world
	token=app.session.profile.token
	person=world.state.players[token]
	world.state.dock_stage=1
	var dock:=World.RESIDENT_BOND.dock_cell(world.state)
	stand(dock)
	expect(not world.act(token,"before-trust",Goals.VOYAGE_ACTION,dock,"repair").ok,"Requires trust")
	person.bonds={"achao":{"points":14,"talk_day":-1,"gift_day":-1}}
	expect(not world.act(token,"before-ship",Goals.VOYAGE_ACTION,dock,"repair").ok,"Requires the cooperative dock project")
	world.state.dock_stage=2
	person.inventory.wood=4
	person.inventory.copper_ore=1
	stand(dock)
	await open_voyage()
	await press("AchaoVoyage_repair")
	expect(world.state.get(Goals.DOCK_LIGHT,false) and int(person.inventory.wood)==0 and int(person.inventory.copper_ore)==0,"Repair is shared and charges its exact materials")
	await open_voyage()
	await capture("01-dock-lamp.png")
	await press("AchaoVoyage_depart")
	expect(app.session.snapshot.players[app.session.own_id].get("at_sea",false) and app.voyage_return.visible and not app.hud.visible,"Departure enters sailing mode and keeps the return control accessible")
	check_voyage_audio(true)
	var physical:=Vector2(person.x,person.y)
	world.move_player(token,Vector2.RIGHT,2.0)
	expect(Vector2(person.x,person.y)==physical,"Walking cannot override the route")
	app._cancel_navigation()
	await process_frame
	expect(not person.has(Goals.VOYAGE_START) and not person.has(Goals.VOYAGE_DONE),"Early return lands without granting completion")
	check_voyage_audio(false)
	await open_voyage()
	await press("AchaoVoyage_depart")
	var first:Dictionary=app.session.snapshot.players[app.session.own_id]
	expect(world.step(4.0,true),"Travel advances on the simulation clock")
	app.session._send_snapshot(1)
	await create_timer(0.35).timeout
	var at:Dictionary=app.session.snapshot.players[app.session.own_id]
	expect(float(at.y)>float(first.y) and world.water(Vector2i(int(at.x),int(at.y))),"The animated player is farther down the waterway")
	await capture("02-trial-voyage.png")
	app.session.set_physics_process(true)
	await create_timer(Goals.VOYAGE_SECONDS-3.0).timeout
	app.session.set_physics_process(false)
	expect(person.get(Goals.VOYAGE_DONE,false) and not app.session.snapshot.players[app.session.own_id].get("at_sea",false),"Completed trial automatically returns to dock")
	check_voyage_audio(false)
	expect(not World.has_recipe(person,Goals.SEAFOOD_RICE),"Voyage reward requires reporting")
	Tasks.bond_goal(app,"achao",3)
	await process_frame
	await press("BondGoalDo")
	expect(World.has_recipe(person,Goals.SEAFOOD_RICE),"Reporting unlocks the seafood rice recipe")
	await open_voyage()
	await press("AchaoVoyagePaint")
	expect(person.get(Goals.VOYAGE_PAINT,false),"Blue-white hull can be selected")
	await open_voyage()
	await press("AchaoVoyage_depart")
	expect(world.step(5.0,true),"Blue hull sails the same route")
	app.session._send_snapshot(1)
	await create_timer(0.35).timeout
	await capture("03-blue-white-hull.png")
	app._interact()
	await process_frame
	expect(not person.has(Goals.VOYAGE_START),"Interact also returns to port")
	var stove:=Vector2i(38,32)
	stand(stove)
	world.state.objects[World.key(stove)]={"type":"stove","owner":token,"items":{}}
	person.inventory.rice=2
	person.inventory.sardine=1
	person.inventory.seaweed=1
	stand(stove)
	app._interact()
	await process_frame
	expect(button("CookingRecipe_seafood_rice")!=null,"The stone stove shows the unlocked dish")
	await press("CookingRecipe_seafood_rice")
	await capture("04-stone-stove-recipe.png")
	expect(world.act(token,"cook-new-dish","queue_cook",stove,Goals.SEAFOOD_RICE).ok,"Normal stove queue accepts the new recipe")
	expect(world.step(41.0,true),"Dish finishes in the queue")
	var queued:Dictionary=world.state.objects[World.key(stove)].cooking
	expect(world.act(token,"claim-dish","claim_cook",stove,str(queued.ready[0].id)).ok and int(person.inventory.get(Goals.SEAFOOD_RICE,0))==2,"Cook and claim two servings")
	expect(app.session.shutdown(),"Save and close")
	var loaded:=World.new()
	var reloaded:=loaded.load_world(path)
	expect(reloaded,"Reload the saved island")
	if reloaded:
		expect(loaded.state.players[token].get(Goals.VOYAGE_PAINT,false) and World.has_recipe(loaded.state.players[token],Goals.SEAFOOD_RICE),"Boat appearance and recipe survive reload")
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	app.sound.close()
	await create_timer(0.15).timeout
	print("ACHAO_TRIAL_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
