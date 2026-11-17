extends SceneTree

const World=preload("res://scripts/world.gd")
const TOKEN:="night-rest-resident"
const FIELD:=Vector2i(41,36)
const MILL:=Vector2i(42,36)
var checks:=0
var failures:=0

class SaveProbe extends World:
	var writes:=0
	var reject_save:=false

	func save() -> bool:
		writes+=1
		return not reject_save

func _initialize() -> void:
	run.call_deferred()

func expect(condition:bool,message:String) -> void:
	checks+=1
	if not condition:
		failures+=1
		push_error(message)

func setup(world:World) -> void:
	world.state.time=300.0
	world.add_player(TOKEN,"望安島民")
	var resident:Dictionary=world.state.players[TOKEN]
	resident.x=42.5
	resident.y=35.5
	world.state.crops[World.key(FIELD)]={"owner":TOKEN,"kind":"radish","wet":true,"growth":float(World.CROPS.radish.time)-30.0}
	world.state.objects[World.key(MILL)]={"owner":TOKEN,"type":"sawmill","items":{}}
	for index in 2:
		expect(world.act(TOKEN,"mill-%d"%index,"queue_processing",MILL,"plank").ok,"A real sawmill request prepares the overnight order")

func rollback_checks() -> void:
	var probe:=SaveProbe.new()
	setup(probe)
	var before:=probe.state.duplicate(true)
	probe.writes=0
	probe.reject_save=true
	expect(not probe.rest_until_dawn(TOKEN).ok and probe.writes==1,"A failed final save is the only write attempted")
	expect(probe.state==before,"Failed rest restores time, crop progress, queue, and commit count")
	probe.reject_save=false
	probe.writes=0
	expect(probe.rest_until_dawn(TOKEN).ok and probe.writes==1,"Successful rest commits exactly once")
	expect(int(probe.state.committed)==int(before.committed)+1,"One rest is one committed operation")
	expect(not probe.rest_until_dawn(TOKEN).ok and probe.writes==1,"Trying again after dawn makes no write")
	probe.state.time=300.0
	probe.state.players[TOKEN].region="mine_1"
	expect(not probe.rest_until_dawn(TOKEN).ok and probe.state.time==300.0,"Rest cannot skip time in a mine")
	probe.state.players[TOKEN].region="home"
	probe.state.players[TOKEN].fishing={"x":55,"y":34,"ready":301.0}
	expect(not probe.rest_until_dawn(TOKEN).ok,"Rest cannot skip an active cast")
	var midnight:=SaveProbe.new()
	midnight.add_player(TOKEN,"望安島民")
	var started:=Time.get_ticks_msec()
	expect(midnight.rest_until_dawn(TOKEN).ok and midnight.state.time==360.0 and midnight.writes==1,"A full midnight-to-dawn interval commits once without queued work")
	print("NIGHT_REST_FULL_INTERVAL_MS ",Time.get_ticks_msec()-started)

func run() -> void:
	rollback_checks()
	var path:="user://night-rest-%d.json"%Time.get_ticks_usec()
	var seeded:=World.new()
	setup(seeded)
	seeded.save_path=path
	expect(seeded.save(),"The initial night and queued batches are on disk")
	var app=preload("res://main.tscn").instantiate()
	app.village_art_preview=true
	root.add_child(app)
	app.session.profile.token=TOKEN
	app.session.set_physics_process(false)
	app.local_mode=true
	expect(app.session.host(0,"望安島民",path,"","127.0.0.1",false,"enet",true)==OK,"An actual local game hosts the isolated save")
	app._pause_menu()
	var rest:=app.modal.find_child("PauseNightRest",true,false) as Button
	expect(rest!=null,"The normal solo pause menu exposes the rest action")
	if rest!=null:rest.pressed.emit()
	var confirm:=app.modal.find_child("NightRestConfirm",true,false) as Button
	expect(confirm!=null and not confirm.disabled,"05:00 allows confirmation")
	var preview:String=app.arg_value("night-rest-preview","")
	if not preview.is_empty() and DisplayServer.get_name()!="headless":
		await create_timer(0.30).timeout
		await RenderingServer.frame_post_draw
		expect(root.get_texture().get_image().save_png(preview)==OK,"The native confirmation screen was captured")
	if confirm!=null:confirm.pressed.emit()
	expect(app.modal==null and float(app.session.snapshot.time)==360.0,"The button advances the running game to 06:00")
	var reopened:=World.new()
	expect(reopened.load_world(path) and float(reopened.state.time)==360.0,"06:00 survives immediate reopening")
	var plot:Dictionary=reopened.state.crops[World.key(FIELD)]
	expect(float(plot.growth)==float(World.CROPS.radish.time),"The crop matures during rest")
	var person:Dictionary=reopened.state.players[TOKEN]
	var original_planks:int=person.inventory.get("plank",0)
	for index in 2:
		expect(reopened.act(TOKEN,"claim-%d"%index,"claim_processing",MILL).ok,"A completed overnight batch remains claimable after reopening")
	expect(not reopened.act(TOKEN,"claim-extra","claim_processing",MILL).ok and int(person.inventory.get("plank",0))==original_planks+4,"Two batches award four planks exactly once")
	app._night_rest_menu()
	confirm=app.modal.find_child("NightRestConfirm",true,false) as Button
	expect(confirm!=null and confirm.disabled,"The UI disables another rest after dawn")
	app._close_modal()
	await verify_vote_panel(app)
	expect(app.session.shutdown(),"The test game shuts down cleanly")
	app.queue_free()
	await process_frame
	for file:String in [path,path+".bak",path+".tmp"]:
		if FileAccess.file_exists(file):DirAccess.remove_absolute(file)
	print("NIGHT_REST_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func verify_vote_panel(app) -> void:
	app.local_mode=false
	app.session.solo_rest_enabled=false
	app.session.world.state.time=350.0
	app.session.world.add_player("other-voter","另一位島民")
	app.session.peers[2]="other-voter"
	app.session._send_snapshot(1)
	app._pause_menu()
	var entry:=app.modal.find_child("PauseNightRest",true,false) as Button
	expect(entry!=null,"The shared island pause menu exposes the ballot")
	if entry!=null:entry.pressed.emit()
	var yes:=app.modal.find_child("NightVoteYes",true,false) as Button
	expect(yes!=null and not yes.disabled,"The night vote can be proposed")
	if yes!=null:yes.pressed.emit()
	var status:=app.modal.find_child("NightVoteStatus",true,false) as Label
	expect(status!=null and status.text.contains("1／2") and yes.disabled,"The waiting ballot shows one affirmative vote without skipping")
	var preview:String=app.arg_value("night-vote-preview","")
	if not preview.is_empty() and DisplayServer.get_name()!="headless":
		await create_timer(0.30).timeout
		await RenderingServer.frame_post_draw
		expect(root.get_texture().get_image().save_png(preview)==OK,"The native ballot screen was captured")
	app._close_modal()
	expect(app.modal==null and app.session.night_vote.is_empty() and app.session.world.state.time==350.0,"Closing after voting withdraws consent before allowing other actions")
	app.session.peers.erase(2)
