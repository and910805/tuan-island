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
		await create_timer(0.35).timeout
		await RenderingServer.frame_post_draw
		expect(root.get_texture().get_image().save_png(arg.trim_prefix("--capture-dir=").path_join(file_name))==OK,"Capture "+file_name)

func contains_text(value:String) -> bool:
	if not is_instance_valid(app.modal):return false
	for label:Node in app.modal.find_children("*","Label",true,false):
		if label.text.contains(value):return true
	return false

func visit(id:String) -> void:
	var spot:=World.bond_place(world.state,id)
	person.region=spot[0]
	stand(spot[1])
	app._interact()
	await process_frame
	if id in ["xinghe","chacha"]:await press("BondOpen")

func run() -> void:
	root.size=Vector2i(1280,800) if "--wide" in OS.get_cmdline_user_args() else Vector2i(1024,640)
	app=load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	var path:="user://diandian-painting-%d.json"%OS.get_process_id()
	if app.session.host(0,"合畫島民",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	world=app.session.world
	token=app.session.profile.token
	person=world.state.players[token]
	var aru:Vector2i=World.bond_place(world.state,"aru")[1]
	stand(aru)
	expect(not world.act(token,"too-soon",Goals.PAINT_INVITE_ACTION,aru,"aru").ok,"Invitation requires trust")
	person.bonds={"diandian":{"points":14,"talk_day":-1,"gift_day":-1}}
	expect(not world.act(token,"before-pose",Goals.PAINT_INVITE_ACTION,aru,"aru").ok,"Trust alone cannot skip the pond story")
	await visit("aru")
	expect(app.modal.find_child("DiandianInvite",true,false)==null,"Unready residents do not show an invitation")
	person[Goals.RECORD_KEY]={"diandian":{"1":"","2":"knees"}}
	await visit("diandian")
	await press("DiandianPainting")
	expect(contains_text("已邀請 0／3"),"Sketch opens with three available places")
	app._close_modal()
	await visit("aru")
	await press("DiandianInvite")
	expect(app.session.snapshot.own_diandian_invites==["aru"],"Aru occupies the first place")
	Tasks.journal(app)
	await process_frame
	await press("DiandianPaintingBookmark")
	expect(contains_text("已邀請 1／3"),"The handbook reopens an unfinished draft away from Diandian")
	app._close_modal()
	expect(not app.session.snapshot.players[app.session.own_id].has(Goals.PAINT_INVITES_KEY),"Invitation list is private")
	expect(not world.act(token,"repeat",Goals.PAINT_INVITE_ACTION,aru,"aru").ok,"Same resident does not take another place")
	var partial:=World.new()
	expect(partial.load_world(path) and partial.state.players[token][Goals.PAINT_INVITES_KEY]==["aru"],"First invitation saves before the others")
	await visit("diandian")
	await press("DiandianPainting")
	expect(contains_text("已邀請 1／3") and contains_text("留給下一位"),"Sketch shows one portrait and remaining places")
	await capture("01-draft.png")
	app._close_modal()
	await visit("xinghe")
	await press("DiandianInvite")
	await visit("nuannuan")
	await press("DiandianInvite")
	expect(app.session.snapshot.own_diandian_invites==["aru","xinghe","nuannuan"],"Residents from different maps can contribute separately")
	person.region="home"
	var milu:Vector2i=World.bond_place(world.state,"milu")[1]
	stand(milu)
	var fourth:=world.act(token,"fourth",Goals.PAINT_INVITE_ACTION,milu,"milu")
	expect(not fourth.ok and str(fourth.message).contains("三個位置"),"Fourth resident cannot overwrite the painting")
	await visit("diandian")
	Tasks.bond_goal(app,"diandian",3)
	await process_frame
	await press("BondGoalDo")
	expect(app.session.snapshot.resident_goals.diandian["3"].state=="done","Report marks the composition complete")
	var revealed=app.modal.find_child("ResidentPainting",true,false)
	expect(revealed!=null and revealed.finished,"Reporting immediately reveals the finished painting")
	Tasks.journal(app)
	await process_frame
	var book:Button
	for candidate:Node in app.modal.find_children("*","Button",true,false):
		if candidate.text=="點點的第一幅合畫":book=candidate
	expect(book!=null,"Handbook reopens the finished painting")
	if book!=null:book.pressed.emit()
	await process_frame
	var drawing=app.modal.find_child("ResidentPainting",true,false)
	expect(drawing!=null and drawing.subjects==["aru","xinghe","nuannuan"],"Composition preserves the selected portrait order")
	expect(contains_text("阿榆") and contains_text("星禾") and contains_text("暖暖"),"Every portrait has its own readable name")
	await capture("02-finished.png")
	await press("DiandianPaintingBack")
	expect(button("DiandianPaintingBookmark")!=null,"Back returns to the handbook")
	expect(app.session.shutdown(),"Save and close")
	var loaded:=World.new()
	expect(loaded.load_world(path),"Reload the saved island")
	var record:Dictionary=loaded.state.players[token]
	expect(record.get(Goals.PAINT_INVITES_KEY,[])==["aru","xinghe","nuannuan"] and Goals.done(record,"diandian").has(3),"Composition and completion survive reload")
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	app.sound.close()
	await create_timer(0.15).timeout
	print("DIANDIAN_PAINTING_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
