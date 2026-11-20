extends SceneTree
## T066 N06-1 棉棉「先讓牠聞聞」: feed once, wait, local chicken approach, report, notes page, reload.
## Optional user args: --capture-dir=DIR (native only), --size=WxH, --large-text.
const World:=preload("res://scripts/world.gd")
const Goals:=World.RESIDENT_GOALS
const Tasks:=preload("res://scripts/life_ui_tasks.gd")
const Approach:=preload("res://scripts/mianmian_chicken_approach.gd")
const Notes:=preload("res://scripts/mianmian_animal_notes.gd")

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
		await create_timer(0.3).timeout
		await RenderingServer.frame_post_draw
		expect(root.get_texture().get_image().save_png(arg.trim_prefix("--capture-dir=").path_join(file_name))==OK,"Capture "+file_name)

func window_size() -> Vector2i:
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--size="):continue
		var parts:=arg.trim_prefix("--size=").to_lower().split("x")
		if parts.size()==2 and parts[0].is_valid_int() and parts[1].is_valid_int():
			var wanted:=Vector2i(int(parts[0]),int(parts[1]))
			if wanted.x>=640 and wanted.y>=480:return wanted
	return Vector2i(1024,640)

func visible_text(node:Node) -> String:
	var lines:PackedStringArray=[]
	if not is_instance_valid(node):return ""
	for candidate:Node in node.find_children("*","Label",true,false):
		if (candidate as Label).is_visible_in_tree():lines.append((candidate as Label).text)
	for candidate:Node in node.find_children("*","Button",true,false):
		if (candidate as Button).is_visible_in_tree():lines.append((candidate as Button).text)
	return "\n".join(lines)

func within_screen(node:Control,tag:String) -> void:
	var screen:=Rect2(Vector2.ZERO,app.get_viewport_rect().size).grow(1.0)
	expect(node!=null and node.is_visible_in_tree() and screen.encloses(node.get_global_rect()),"On screen: "+tag)

func run() -> void:
	var size_tag:="%dx%d"%[window_size().x,window_size().y]
	root.size=window_size()
	app=load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	var large_text:="--large-text" in OS.get_cmdline_user_args()
	if large_text:
		app.sound.preferred_text_scale=3
		app._apply_font_scale_tree()
		await process_frame
		expect(app.font_scale_factor()>=1.2,"Large text is active")
	var tag:=size_tag+("-large" if large_text else "")
	AudioServer.set_bus_mute(0,true)
	var path:="user://mianmian-notes-%d.json"%OS.get_process_id()
	if app.session.host(0,"棉棉島民",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	world=app.session.world
	token=app.session.profile.token
	person=world.state.players[token]
	world.state.picnic=true
	person.bonds={"mianmian":{"points":6,"talk_day":-1,"gift_day":-1}}
	var chicken:Vector2i=World.CHICKEN_CELL

	# Before feeding: no private time, no notes, no approach.
	stand(chicken)
	expect(not app.session.snapshot.has("own_mianmian_feed_time"),"No feed time before the first feed")
	expect(not Notes.available(app.session.snapshot),"Notes are locked before the event")
	expect(not Goals.need_met("chicken_fed",world.state,token),"Need unmet before feeding")

	# One normal feed.
	person.inventory.feed=1
	stand(chicken)
	var fed_at:=float(world.state.time)
	app.session.perform("feed",chicken)
	await process_frame
	await process_frame
	expect(int(person.inventory.get("feed",0))==0,"Exactly one feed is spent")
	expect(is_equal_approx(float(person.get(Goals.CHICKEN_FED_KEY,-1.0)),fed_at),"Feed time recorded once")
	stand(chicken)
	var snap:Dictionary=app.session.snapshot
	expect(snap.has("own_mianmian_feed_time") and is_equal_approx(float(snap.own_mianmian_feed_time),fed_at),"Own snapshot carries only the viewer's feed time")
	expect(not Goals.need_met("chicken_fed",world.state,token),"Goal is not ready on the feeding frame")

	# Approach timeline (draw-only helper).
	var rest:=Vector2(45.7,33.8)
	person.x=chicken.x+2.5
	person.y=chicken.y+0.5
	stand(Vector2i(floori(person.x),floori(person.y)))
	snap=app.session.snapshot
	expect(Approach.shift(snap,app.session.own_id,rest,false,fed_at+0.4)==Vector2.ZERO,"Brief pause before moving")
	var mid:=Approach.shift(snap,app.session.own_id,rest,false,fed_at+3.5)
	expect(mid.length()>1.0 and mid.length()<=17.0 and mid.x>0.0,"Mid-walk offset is small and toward the viewer")
	expect(Approach.shift(snap,app.session.own_id,rest,true,fed_at+3.5)==Vector2.ZERO,"Reduced motion keeps the usual place")
	expect(Approach.shift(snap,"someone-else",rest,false,fed_at+3.5)==Vector2.ZERO,"Other viewers get no offset from this time")
	expect(Approach.shift(snap,app.session.own_id,rest,false,fed_at+30.0)==Vector2.ZERO,"Offset ends after the short walk")
	var stripped:=snap.duplicate()
	stripped.erase("own_mianmian_feed_time")
	expect(Approach.shift(stripped,app.session.own_id,rest,false,fed_at+3.5)==Vector2.ZERO,"Absent time means no offset")
	var before_pos:=Vector2(float(person.x),float(person.y))
	world.state.time=fed_at+3.5
	app.session._send_snapshot(1)
	await process_frame
	await capture("01-chicken-approach-%s.png"%tag)

	# Goal becomes ready after the original five seconds, with no further feeding or petting.
	world.state.time=fed_at+5.1
	expect(Goals.need_met("chicken_fed",world.state,token),"Ready after five seconds")
	expect(Vector2(float(person.x),float(person.y))==before_pos,"Presentation never moves the player")
	stand(World.bond_place(app.session.snapshot,"mianmian")[1])
	Tasks.bond_goal(app,"mianmian",1)
	await process_frame
	await capture("02-goal-ready-%s.png"%tag)
	await press("BondGoalDo")
	expect(app.session.snapshot.resident_goals.mianmian["1"].state=="done","Reporting completes the event")
	expect(Notes.available(app.session.snapshot),"Notes unlock after completion")

	# Goal page entry, notes page, back, reopen.
	Tasks.bond_goal(app,"mianmian",1)
	await process_frame
	expect(button("MianmianNotesGoalEntry")!=null,"Completed goal offers the notes")
	await capture("03-goal-done-%s.png"%tag)
	await press("MianmianNotesGoalEntry")
	var art:=app.modal.find_child("MianmianNotesArt",true,false) as Control
	within_screen(art,"notes art")
	within_screen(button("MianmianNotesBack"),"notes back")
	var text:=visible_text(app.modal)
	expect(text.contains("糯米雞的偏好筆記") and text.contains("一份飼料就夠") and text.contains("退後等一下"),"Notes carry the helpful zh-TW text")
	for index in 3:
		var tip:=app.modal.find_child("MianmianNotesTip_%d"%index,true,false) as Control
		within_screen(tip,"tip %d fully visible"%index)
		var body_label:=tip.get_child(1) as Label if tip!=null else null
		expect(body_label!=null and body_label.get_visible_line_count()>=body_label.get_line_count(),"Tip %d body is not clipped"%index)
	var tips_box:=app.modal.find_child("MianmianNotesTips",true,false) as Control
	expect(tips_box!=null and tips_box.get_theme_constant("margin_left")>=16,"Tips keep horizontal padding")
	expect(art.size.y<=100.0,"Header art stays compact")
	var last_tip:=app.modal.find_child("MianmianNotesTip_2",true,false) as Control
	within_screen(last_tip,"third tip visible with the back button")
	var viewport:Control=last_tip.get_parent()
	while viewport!=null and not viewport is ScrollContainer:viewport=viewport.get_parent() as Control
	if viewport!=null:
		expect((viewport as Control).get_global_rect().grow(1.0).encloses(last_tip.get_global_rect()),"All three tips fit the scroll viewport without scrolling")
	await capture("04-notes-%s.png"%tag)
	await press("MianmianNotesBack")
	expect(button("MianmianNotesGoalEntry")!=null,"Back returns to the goal page")
	await press("MianmianNotesGoalEntry")
	await press("MianmianNotesBack")

	# Bond dialogue entry.
	Tasks.bond_dialogue(app,"mianmian")
	await process_frame
	expect(button("MianmianNotesEntry")!=null,"Bond dialogue offers the notes")
	await capture("05-resident-entry-%s.png"%tag)
	await press("MianmianNotesEntry")
	expect(app.modal.find_child("MianmianNotesArt",true,false)!=null,"Bond dialogue opens the notes")
	await press("MianmianNotesBack")
	expect(button("MianmianNotesEntry")!=null,"Back returns to the bond dialogue")

	# Save, reload, reopen.
	expect(app.session.shutdown(),"Save and close")
	var loaded:=World.new()
	expect(loaded.load_world(path),"Reload the saved island")
	if loaded.state.players.has(token):
		var saved:Dictionary=loaded.state.players[token]
		expect(Goals.done(saved,"mianmian").has(1) and is_equal_approx(float(saved.get(Goals.CHICKEN_FED_KEY,-1.0)),fed_at),"Completion and feed time survive reload")
		var view:Dictionary=Goals.view(saved,loaded.state,token)
		expect(Notes.available({"resident_goals":view}),"Notes are available again after reload")
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	app.sound.close()
	await create_timer(0.15).timeout
	print("MIANMIAN_NOTES_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
