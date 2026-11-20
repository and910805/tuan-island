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

func scene_of(data:Dictionary) -> Dictionary:
	return data.get("aru_bench_scene",{})

func settle() -> void:
	app.session.rates[1].clear()
	app.session._send_snapshot(1)
	app.view.queue_redraw()
	await process_frame
	await process_frame

func sit_primary(aru:Vector2i) -> bool:
	person.erase(Goals.ARU_REST_KEY)
	stand(aru)
	var result:Dictionary=world.act(token,"sit-%d"%checks,Goals.ARU_REST_ACTION,aru)
	await settle()
	return result.ok

func run() -> void:
	var tag:="1024x640"
	var size:=Vector2i(1024,640)
	if OS.get_cmdline_user_args().has("--wide"):
		size=Vector2i(1280,800)
		tag="1280x800"
	root.size=size
	app=load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	var path:="user://aru-bench-%d.json"%OS.get_process_id()
	if app.session.host(0,"渡口島民",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	world=app.session.world
	token=app.session.profile.token
	person=world.state.players[token]
	var aru:=World.Village.resident_cell(world.state,"aru")
	stand(aru)
	var leave_action:=Goals.ARU_REST_LEAVE
	expect(leave_action=="aru_bench_leave","Leave action id matches the shared contract")
	expect(not world.act(token,"locked",Goals.ARU_REST_ACTION,aru).ok,"Cannot start before trust")
	await settle()
	expect(scene_of(app.session.snapshot).is_empty() and not person.has(Goals.ARU_REST_KEY),"Locked attempt shows no scene")
	person.bonds={"aru":{"points":14,"talk_day":-1,"gift_day":-1}}
	stand(aru)
	var mine:String=app.session._public_actor(token)
	app._interact()
	await press("AruRest")
	expect(button("AruRise")==null,"New flow does not use the old AruRise popup")
	await settle()
	var solo:Dictionary=scene_of(app.session.snapshot)
	expect(person.has(Goals.ARU_REST_KEY),"Primary sitting is accepted by the server")
	expect(not solo.is_empty() and solo.get("sitters",{}).get(mine,-1)==0,"Snapshot shows the primary seat in slot 0")
	var anchor_key:String=str(solo.get("anchor",""))
	expect(anchor_key!="" and world.state.objects.has(anchor_key)==false and world.state.crops.has(anchor_key)==false,"Anchor is a free server-chosen tile")
	expect(not app.modal.visible if is_instance_valid(app.modal) else true,"World display is not covered by a modal")
	expect(not app._tool_hint_visible() and not app.preview_toolbar.visible,"The rest scene keeps farm prompts out of view")
	var spent_key:float=float(person[Goals.ARU_REST_KEY])
	await capture("01-rest-solo-%s.png"%tag)
	# A visiting friend joins by choice, in a distinct seat, with no story prerequisite.
	var friend:="friend-at-aru"
	world.add_player(friend,"來訪的朋友")
	var guest:Dictionary=world.state.players[friend]
	guest.blue_outfit=true
	app.session.peers[2]=friend
	guest.x=person.x
	guest.y=person.y
	var theirs:String=app.session._public_actor(friend)
	expect(not guest.has(Goals.ARU_REST_KEY) and scene_of(app.session.snapshot).get("sitters",{}).size()==1,"Nobody is moved into the seat automatically")
	expect(not world.act(friend,"wrong-cell",Goals.ARU_REST_ACTION,aru+Vector2i(1,0)).ok,"Joining needs the real Aru cell")
	expect(world.act(friend,"join",Goals.ARU_REST_ACTION,aru).ok and not guest.has(Goals.ARU_REST_KEY),"Friend opts in without gaining the quest prerequisite")
	expect(float(person[Goals.ARU_REST_KEY])==spent_key,"Joining does not renew the primary reward timer")
	app.session.rates[1].clear()
	var shared:Dictionary=scene_of(app.session.public_state("home",token))
	expect(shared.get("anchor","")==anchor_key and shared.get("sitters",{}).get(mine,-1)==0 and shared.get("sitters",{}).get(theirs,-1)==1,"Shared state has distinct slots 0 and 1 under public ids")
	var seen:=JSON.stringify(app.session.public_state("home",friend).get("aru_bench_scene",{}))
	expect(not seen.contains(token) and not seen.contains(friend),"Shared scene carries no raw token")
	expect(not JSON.stringify(shared).contains(friend),"Shared scene leaves out the guest's raw id")
	await settle()
	await capture("02-rest-shared-%s.png"%tag)
	# Stopping ends the scene; an old/unconfirmed invitation cannot revive it.
	app._interact()
	await settle()
	expect(scene_of(app.session.snapshot).is_empty(),"The interact key stands up and clears the scene")
	expect(app._tool_hint_visible() and app.preview_toolbar.visible,"Standing restores the outdoor tools")
	guest.x=person.x
	guest.y=person.y
	expect(not world.act(friend,"late-join",Goals.ARU_REST_ACTION,aru).ok,"Invitation exists only while a primary is seated")
	await settle()
	expect(scene_of(app.session.snapshot).is_empty(),"A rejected stale join shows nothing")
	# Walking away also ends it.
	expect(await sit_primary(aru) and not scene_of(app.session.snapshot).is_empty(),"Primary can sit again")
	world.move_player(token,Vector2.RIGHT,0.4)
	world.step(0.1,true,false)
	await settle()
	expect(scene_of(app.session.snapshot).is_empty(),"Moving away ends the scene")
	expect(not world.act(token,"far",leave_action,aru).ok or scene_of(app.session.snapshot).is_empty(),"Leaving from afar stays idle")
	# Persisted data contains no ephemeral seats.
	var dumped:=JSON.stringify(world.state)
	expect(not dumped.contains("aru_bench_scene") and not dumped.contains("sitters"),"Seats are not stored in world state")
	app.session.peers.erase(2)
	stand(aru)
	Tasks.bond_goal(app,"aru",3)
	await press("AruRestFromGoal")
	await settle()
	expect(not scene_of(app.session.snapshot).is_empty() and person.has(Goals.ARU_REST_KEY),"The relationship page can also seat the player and grant report progress")
	Tasks.bond_goal(app,"aru",3)
	await process_frame
	await press("BondGoalDo")
	expect(app.session.snapshot.resident_goals.aru["3"].state=="done","Report unlocks engraving")
	expect(World.Village.unlocked(person,"sign"),"Report unlocks the sign pattern via relationship")
	Tasks.bond_goal(app,"aru",3)
	await press("AruSignPattern")
	var title:=app.modal.find_child("BuildTitle",true,false) as Label if is_instance_valid(app.modal) else null
	expect(title!=null and title.text.contains(World.BUILD.sign.name),"The completed story opens the real sign recipe")
	app._close_modal()
	var mark:=Vector2i(38,32)
	person.inventory.wood=100
	person.inventory.fiber=100
	stand(mark+Vector2i(0,1))
	expect(world.act(token,"build-sign","build",mark,"sign").ok,"Normal building accepts the unlocked sign")
	stand(mark)
	app._interact()
	await process_frame
	var field:=app.modal.find_child("AruInscription",true,false) as LineEdit
	expect(field!=null,"Owner can enter text after interacting in the world")
	if field!=null:field.text="風鈴小屋"
	await press("AruSaveInscription")
	expect(app.session.snapshot.objects.get(World.key(mark),{}).get("inscription")=="風鈴小屋","Carving is visible in world data")
	app._interact()
	await process_frame
	await capture("03-inscription-%s.png"%tag)
	guest.x=person.x
	guest.y=person.y
	expect(not world.act(friend,"overwrite",Goals.INSCRIBE_ACTION,mark,"路過").ok,"Visitors cannot overwrite someone else's furniture")
	expect(not world.act(token,"bad",Goals.INSCRIBE_ACTION,mark,"錯誤\n換行").ok,"Invalid characters are rejected")
	var bench:=Vector2i(37,32)
	person.stories.aru=2
	stand(bench+Vector2i(0,1))
	expect(world.act(token,"build-bench","build",bench,"long_bench").ok,"Build the regular two-person bench")
	stand(bench)
	app._interact()
	await process_frame
	field=app.modal.find_child("AruInscription",true,false) as LineEdit
	expect(field!=null,"Two-person bench is interactable")
	if field!=null:field.text="留位給你"
	await press("AruSaveInscription")
	expect(world.state.objects.get(World.key(bench),{}).get("inscription")=="留位給你","Bench carving persists separately from the sign")
	expect(app.session.shutdown(),"Save and close")
	var saved:=FileAccess.get_file_as_string(path)
	expect(not saved.contains("aru_bench_scene") and not saved.contains("sitters"),"Save file never contains ephemeral seats")
	var loaded:=World.new()
	expect(loaded.load_world(path),"Reload old and new records together")
	expect(loaded.state.objects.get(World.key(mark),{}).get("inscription")=="風鈴小屋" and Goals.done(loaded.state.players[token],"aru").has(3),"Carving and reward persist")
	expect(loaded.state.objects.get(World.key(bench),{}).get("inscription")=="留位給你","Bench inscription also survives reload")
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	app.sound.close()
	await create_timer(0.15).timeout
	print("ARU_BENCH_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
