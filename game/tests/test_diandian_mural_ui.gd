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

func text_is_visible(value:String) -> bool:
	if not is_instance_valid(app.modal):return false
	for node:Node in app.modal.find_children("*","Label",true,false):
		if node.text.contains(value) and node.is_visible_in_tree() and node.size.y>0.0:return true
	return false

func open_mural() -> void:
	app._interact()
	await process_frame
	await press("PublicMural")

func run() -> void:
	root.size=Vector2i(1280,800) if "--wide" in OS.get_cmdline_user_args() else Vector2i(1024,640)
	app=load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	var path:="user://diandian-mural-%d.json"%OS.get_process_id()
	if app.session.host(0,"掛畫島民",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	world=app.session.world
	token=app.session.profile.token
	person=world.state.players[token]
	world.state.board=true
	world.state.picnic=true
	world.state.community={"table":World.COMMUNITY.choose_table(world.state)}
	var board:=Goals.MURAL_SITE
	stand(board)
	expect(not world.act(token,"locked",Goals.MURAL_HANG_ACTION,board).ok,"Cannot hang without prior painting")
	person.bonds={"diandian":{"points":24,"talk_day":-1,"gift_day":-1}}
	person.bond_goals={"diandian":{"3":""}}
	person[Goals.PAINT_INVITES_KEY]=["aru","xinghe","nuannuan"]
	stand(board)
	await open_mural()
	await capture("00-preview-before-hanging.png")
	await press("HangMural")
	var public_art:Dictionary=app.session.snapshot[Goals.MURAL_KEY]
	expect(public_art.get("subjects")==["aru","xinghe","nuannuan"] and public_art.get("author_name")=="掛畫島民","Mounted art has original portraits and public credit")
	expect(not public_art.has("author") and not public_art.has("signatures"),"Server never publishes contributor tokens")
	expect(public_art.get("names",[])==[] and app.session.snapshot.own_diandian_mural,"Mounting leaves the guest slot empty")
	expect(not world.act(token,"hang-twice",Goals.MURAL_HANG_ACTION,board).ok,"Another mount cannot replace the shared composition")
	expect(text_is_visible("留給下一位") and text_is_visible("你的名字已留在合畫上。"),"Hanging refreshes the current exhibit with credit and the spare place")
	await capture("01-ready-for-a-guest.png")
	app._close_modal()

	var visitor:="guest-mural-test"
	world.add_player(visitor,"晚到的島民")
	var visitor_record:Dictionary=world.state.players[visitor]
	visitor_record.x=board.x+0.5
	visitor_record.y=board.y+0.5
	expect(world.act(visitor,"sign",Goals.MURAL_SIGN_ACTION,board).ok,"A later resident can add their own portrait without a bond gate")
	expect(not world.act(visitor,"sign-twice",Goals.MURAL_SIGN_ACTION,board).ok,"A resident cannot sign twice")
	stand(board)
	await open_mural()
	expect(text_is_visible("入畫島民 1 位") and text_is_visible("留給下一位"),"After signing there is still a blank page for another resident")
	for node:Node in app.modal.find_children("*","Button",true,false):
		if node.text=="看上一位":node.pressed.emit();break
	await process_frame
	expect(text_is_visible("晚到的島民") and text_is_visible("掛畫島民"),"Guest portrait and author names are both visible")
	await capture("02-guest-and-credit.png")

	var spot:=World.bond_place(world.state,"diandian")
	person.region=spot[0]
	stand(spot[1])
	Tasks.bond_goal(app,"diandian",4)
	await process_frame
	await press("DiandianExhibitFromGoal")
	expect(text_is_visible("入畫島民 1 位") and button("SignMural")==null,"The exhibit can be read again from the story at the pond")
	for node:Node in app.modal.find_children("*","Button",true,false):
		if node.text=="返回":node.pressed.emit();break
	await process_frame
	await press("BondGoalDo")
	expect(app.session.snapshot.resident_goals.diandian["4"].state=="done","Report completes the public exhibition story")
	expect(app.session.shutdown(),"Save and close")
	var loaded:=World.new()
	expect(loaded.load_world(path),"Reload the saved island")
	var mural:Dictionary=Goals.mural_public(loaded.state)
	expect(mural.get("names")==["晚到的島民"] and mural.get("author_name")=="掛畫島民","Public names and credit survive reload")
	expect(Goals.done(loaded.state.players[token],"diandian").has(4) and Goals.mural_contributed(loaded.state,visitor),"Author and guest progression survive reload")
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	app.sound.close()
	await create_timer(0.15).timeout
	print("DIANDIAN_MURAL_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
