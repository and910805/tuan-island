extends SceneTree

const World:=preload("res://scripts/world.gd")
const Goals:=World.RESIDENT_GOALS
const Tasks:=preload("res://scripts/life_ui_tasks.gd")
const Folio:=preload("res://scripts/build_folio.gd")

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
	var path:="user://chacha-tea-setup-%d.json"%OS.get_process_id()
	if app.session.host(0,"茶席島民",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	world=app.session.world
	token=app.session.profile.token
	person=world.state.players[token]
	var site:=World.TEA_CERAMICS.TEA_NPC
	stand(site)
	expect(not world.act(token,"wrong-region",Goals.TEA_SETUP_ACTION,site,"horizontal:2").ok,"Tea arrangement needs the actual teahouse")
	person.region=World.TEA_CERAMICS.MAOKONG
	stand(site)
	expect(not world.act(token,"not-known",Goals.TEA_SETUP_ACTION,site,"horizontal:2").ok,"Meet Chacha first")
	app._interact()
	await process_frame
	await press("BondOpen")
	await press("BondTalk")
	expect(World.RESIDENT_BOND.stage(person,"chacha")==1,"Ordinary conversation starts the event")
	stand(site)
	app._interact()
	await process_frame
	await press("BondOpen")
	await press("ChachaArrangement")
	expect(button("TeaPlaceCup").disabled and button("TeaConfirmArrangement").disabled,"The cups need a table first")
	await press("TeaAxis_horizontal")
	await press("TeaPlaceCup")
	expect(button("TeaConfirmArrangement").disabled,"One cup cannot complete the arrangement")
	await press("TeaAxis_vertical")
	await press("TeaPlaceCup")
	expect(button("TeaPlaceCup").disabled and not button("TeaConfirmArrangement").disabled,"Exactly two cups fit")
	var preview=app.modal.find_child("TeaArrangementPreview",true,false)
	expect(preview.axis=="vertical" and preview.cups==2,"The preview shows the current arrangement")
	await capture("01-tea-table.png")
	await press("TeaConfirmArrangement")
	expect(app.session.snapshot.own_chacha_tea_setup=="vertical","The preferred table direction saves")
	expect(not app.session.snapshot.players[app.session.own_id].has(Goals.TEA_SETUP_KEY),"Personal arrangement is not broadcast")
	expect(not world.act(token,"repeat",Goals.TEA_SETUP_ACTION,site,"horizontal:2").ok,"Duplicate confirmed arrangement cannot overwrite the record")
	Tasks.bond_goal(app,"chacha",1)
	await process_frame
	await press("BondGoalDo")
	expect(app.session.snapshot.resident_goals.chacha["1"].state=="done","Report unlocks basic tea set")

	person.region=World.REGIONS.HOME
	var tile:=Vector2i(48,24)
	world.state.removed[World.key(tile)]=true
	person.inventory.clay=2
	stand(tile+Vector2i.RIGHT)
	expect(Folio.unlocked(app,app.session.snapshot.players[app.session.own_id],Goals.BASIC_TEA_SET),"Home workshop catalogue unlocks the tea set")
	expect(world.act(token,"tea-set-build","build",tile,Goals.BASIC_TEA_SET).ok,"Build the tea set with clay and wood")
	expect(world.state.objects.get(World.key(tile),{}).get("type")==Goals.BASIC_TEA_SET and not world.blocked(tile),"New tea set is placed and does not block movement")
	expect(int(person.inventory.clay)==0,"Placement debits the specified clay")
	expect(app.session.shutdown(),"Save and close")
	var loaded:=World.new()
	expect(loaded.load_world(path),"Reload the saved island")
	expect(loaded.state.players[token].get(Goals.TEA_SETUP_KEY)=="vertical" and Goals.done(loaded.state.players[token],"chacha").has(1),"Arrangement and recipe unlock survive reload")
	expect(loaded.state.objects.get(World.key(tile),{}).get("type")==Goals.BASIC_TEA_SET,"Tea set survives reload")
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	app.sound.close()
	await create_timer(0.15).timeout
	print("CHACHA_TEA_ARRANGEMENT_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
