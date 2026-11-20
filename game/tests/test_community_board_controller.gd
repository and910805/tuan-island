extends SceneTree

const World=preload("res://scripts/world.gd")
const Board=preload("res://scripts/life_ui_tasks.gd")
const OPTIONS:={"FishingMeetEntry":"FishMeetRule","ShowcaseEntry":"ShowcaseRule","HarvestRelayBoardEntry":"HarvestRule"}

var app
var checks:=0
var failures:=0
var output:=""

func _initialize()->void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-output="):output=arg.trim_prefix("--qa-output=")
	create_timer(60.0).timeout.connect(func():quit(2))
	run.call_deferred()

func run()->void:
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
	if not output.is_empty():DirAccess.make_dir_recursive_absolute(output)
	app=preload("res://main.tscn").instantiate()
	root.add_child(app)
	app.set_process(false)
	app.session.set_physics_process(false)
	var world:=World.new()
	world.add_player("board-qa","試玩島民")
	world.state.board=true
	var position:=Vector2(Board.BOARD_CELL)+Vector2(0.5,1.5)
	world.state.players["board-qa"].x=position.x
	world.state.players["board-qa"].y=position.y
	app.session.world=world
	app.session.peers={1:"board-qa"}
	app.session._send_snapshot(1)
	app.playing=true
	app.menu.hide()
	app.hud.show()
	app._controller_connection_changed(0,true)
	app.sound.preferred_text_scale=3
	app._apply_font_scale_tree()
	assert(app.font_scale_factor()==1.25)
	for extent in [Vector2i(1024,640),Vector2i(1280,800)]:
		root.size=extent
		await settle()
		for picnic in [false,true]:
			world.state.picnic=picnic
			app.session._send_snapshot(1)
			await settle()
			for id:String in OPTIONS:
				if not picnic and id=="HarvestRelayBoardEntry":continue
				await check_activity(id,extent,picnic)
	app.session.world=null
	app.queue_free()
	await settle()
	print("BOARD_CONTROLLER_QA checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func check_activity(id:String,extent:Vector2i,picnic:bool)->void:
	var label:="%s %s picnic=%s"%[id,extent,picnic]
	await tap(JOY_BUTTON_A)
	var board:Control=app.modal
	if not expect(board!=null and board.get_meta("life_modal_layout","")=="community_board",label+" opens board from the island"):
		if board!=null:await tap(JOY_BUTTON_B)
		return
	var scroll:=board.find_child("ModalScroll",true,false) as ScrollContainer
	var target:=board.find_child(id,true,false) as Button
	if not expect(scroll!=null and target!=null,label+" appears on the activity board"):
		await tap(JOY_BUTTON_B)
		return
	var taps:=0
	while root.gui_get_focus_owner()!=target and taps<48:
		var previous:=root.gui_get_focus_owner()
		await tap(JOY_BUTTON_DPAD_DOWN)
		taps+=1
		if root.gui_get_focus_owner()==previous:break
	var selected:=root.gui_get_focus_owner()==target
	expect(selected,label+" d-pad selects the activity in %d presses"%taps)
	var bounds:=scroll.get_global_rect().grow(0.5)
	expect(bounds.encloses(target.get_global_rect()),label+" scroll follows the selection (y=%d)"%scroll.scroll_vertical)
	var text_width:=target.get_theme_font("font").get_string_size(target.text,HORIZONTAL_ALIGNMENT_LEFT,-1,target.get_theme_font_size("font_size")).x
	var styles:=target.get_theme_stylebox("normal").get_minimum_size().x
	expect(target.size.x+0.5>=text_width+styles,label+" caption fits at 125%")
	if selected:
		await tap(JOY_BUTTON_DPAD_UP)
		expect(root.gui_get_focus_owner()!=target,label+" d-pad moves back up")
		await tap(JOY_BUTTON_DPAD_DOWN)
		expect(root.gui_get_focus_owner()==target,label+" d-pad reselects the activity")
		if not output.is_empty() and DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output.path_join("%s-%d-%s.png"%[id,extent.x,picnic]))
		await tap(JOY_BUTTON_A)
		expect(is_instance_valid(app.modal) and app.modal!=board and app.modal.find_child(OPTIONS[id],true,false)!=null,label+" A opens the activity")
	await tap(JOY_BUTTON_B)
	expect(app.modal==null,label+" B returns to the island")

func tap(button:JoyButton)->void:
	for pressed in [true,false]:
		var event:=InputEventJoypadButton.new()
		event.button_index=button
		event.pressed=pressed
		event.pressure=1.0 if pressed else 0.0
		root.push_input(event)
	await settle()

func settle()->void:
	for frame in 3:await process_frame

func expect(condition:bool,message:String)->bool:
	checks+=1
	if not condition:
		failures+=1
		push_error(message)
	return condition
