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
	var path:="user://luoluo-letter-%d.json"%OS.get_process_id()
	if app.session.host(0,"送信島民",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	world=app.session.world
	token=app.session.profile.token
	person=world.state.players[token]
	world.state.board=true
	world.state.picnic=true
	world.state.community={"table":World.COMMUNITY.choose_table(world.state)}
	var post:Vector2i=World.bond_place(world.state,"luoluo")[1]
	stand(post)
	expect(not world.act(token,"before-intro",Goals.ADDRESS_ACTION,post,"take").ok,"Letter needs introduction")
	app._interact()
	await process_frame
	await press("BondTalk")
	expect(World.RESIDENT_BOND.stage(person,"luoluo")==1,"Meet Luoluo through normal dialogue")
	app._close_modal()
	stand(post)
	app._interact()
	await process_frame
	await press("LuoluoTakeLetter")
	expect(app.session.snapshot.own_luoluo_address==Goals.ADDRESS_CARRIED,"Letter is recorded on the host")
	expect(not app.session.snapshot.players[app.session.own_id].has(Goals.ADDRESS_KEY),"Player's letter is private")
	expect(not world.act(token,"duplicate-letter",Goals.ADDRESS_ACTION,post,"take").ok,"Only one pending letter is issued")
	expect(not world.act(token,"early-report",Goals.ACTION,post,"luoluo:1::").ok,"Cannot report before delivering")
	stand(post)
	app._interact()
	await process_frame
	await press("LuoluoReadLetter")
	var clue:=app.modal.find_child("AddressClue1",true,false) as Label
	var initial:=clue.get_theme_font_size("font_size")
	var zoom:=app.modal.find_child("LuoluoAddressZoom",true,false) as CheckButton
	expect(zoom!=null and app.modal.find_child("AddressClue3",true,false)!=null,"Letter shows all three clues and a personal zoom control")
	if zoom!=null:zoom.button_pressed=true
	await process_frame
	expect(clue.get_theme_font_size("font_size")>initial,"Clue zoom enlarges the text")
	await capture("01-enlarged-letter.png")
	if zoom!=null:zoom.button_pressed=false
	expect(clue.get_theme_font_size("font_size")==initial,"Zoom can also be reset")
	app._close_modal()
	var milu:Vector2i=World.bond_place(world.state,"milu")[1]
	stand(milu)
	app._interact()
	await process_frame
	await press("LuoluoDeliverLetter")
	expect(app.session.snapshot.own_luoluo_address==Goals.ADDRESS_CARRIED,"Wrong recipient leaves the letter intact")
	expect(not world.act(token,"spoof-delivery",Goals.ADDRESS_ACTION,milu,"aru").ok,"Server checks the actual recipient's position")
	var aru:Vector2i=World.bond_place(world.state,"aru")[1]
	stand(aru)
	app._interact()
	await process_frame
	await press("LuoluoDeliverLetter")
	expect(app.session.snapshot.own_luoluo_address==Goals.ADDRESS_DELIVERED,"The intended recipient accepts")
	stand(post)
	Tasks.bond_goal(app,"luoluo",1)
	await process_frame
	await press("BondGoalDo")
	expect(app.session.snapshot.resident_goals.luoluo["1"].state=="done","Report unlocks the mailbox")
	var mailbox:=Vector2i(48,24)
	world.state.removed[World.key(mailbox)]=true
	stand(mailbox+Vector2i(1,0))
	expect(Folio.unlocked(app,app.session.snapshot.players[app.session.own_id],Goals.MAILBOX_KIND),"Mailbox unlocked in furniture catalogue")
	expect(world.act(token,"mailbox-build","build",mailbox,Goals.MAILBOX_KIND).ok,"Build the mailbox using the new plan")
	expect(world.state.objects.get(World.key(mailbox),{}).get("type")==Goals.MAILBOX_KIND and world.blocked(mailbox),"Built mailbox has normal collision")
	stand(mailbox+Vector2i(1,0))
	app._interact()
	await process_frame
	expect(app.modal.find_child("AddressClue1",true,false)!=null,"World mailbox reopens the completed letter")
	await capture("02-mailbox-letter.png")
	expect(app.session.shutdown(),"Save and close")
	var loaded:=World.new()
	expect(loaded.load_world(path),"Reload the saved island")
	var record:Dictionary=loaded.state.players[token]
	expect(record.get(Goals.ADDRESS_KEY,0)==Goals.ADDRESS_DELIVERED and Goals.done(record,"luoluo").has(1),"Letter and completion survive reload")
	expect(loaded.state.objects.get(World.key(mailbox),{}).get("type")==Goals.MAILBOX_KIND,"Mailbox survives reload")
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	app.sound.close()
	await create_timer(0.15).timeout
	print("LUOLUO_ADDRESS_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
