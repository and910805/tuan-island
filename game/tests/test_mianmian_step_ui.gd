extends SceneTree
## T066 N06-4 棉棉「自己走出屋簷」: quiet sheep watch, local step-out, report, journal, wool hat, reload.
## Optional user args: --capture-dir=DIR, --size=WxH, --large-text.
const World:=preload("res://scripts/world.gd")
const Goals:=World.RESIDENT_GOALS
const Weather:=preload("res://scripts/weather.gd")
const Tasks:=preload("res://scripts/life_ui_tasks.gd")
const Journal:=preload("res://scripts/mianmian_care_journal.gd")
const Step:=preload("res://scripts/mianmian_sheep_step.gd")

var app
var world:World
var token:String
var person:Dictionary
var checks:=0
var failures:=0
var last_notice:=""

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
	app.session.rates[1].clear()
	app.session._send_snapshot(1)

func at_time(seconds:float) -> void:
	world.state.time=seconds
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

func day_time(rainy:bool,after:float=0.0) -> float:
	for day in range(int(after/Weather.DAY_SECONDS)+1,int(after/Weather.DAY_SECONDS)+80):
		if Weather.rains(float(day),"home")==rainy:return float(day)*Weather.DAY_SECONDS+30.0
	return -1.0

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
	var tag:=size_tag+("-large" if large_text else "")
	AudioServer.set_bus_mute(0,true)
	var path:="user://mianmian-step-%d.json"%OS.get_process_id()
	if app.session.host(0,"棉棉走出屋簷",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	app.session.notice.connect(func(message:String,_ok:bool):last_notice=message)
	world=app.session.world
	token=app.session.profile.token
	person=world.state.players[token]
	world.state.picnic=true
	person.bonds={"mianmian":{"points":24,"talk_day":-1,"gift_day":-1}}
	var sheep:Vector2i=World.LIVESTOCK.ANIMALS.sheep.cell
	var mm:Vector2i=World.bond_place(app.session.snapshot,"mianmian")[1]
	var dry:=day_time(false)
	var wet:=day_time(true)
	at_time(dry)
	stand(sheep)
	# Entry is hidden until the shelter exists.
	app._interact()
	await process_frame
	await press("SheepCorner")
	var early_watch:=button("SheepStepWatch")
	expect(early_watch==null or not early_watch.is_visible_in_tree(),"No visible watch button before the shelter is built")
	app._close_modal()
	person[Goals.SHEEP_SHELTER_KEY]=Goals.SHEEP_COMFORT_MASK
	stand(sheep)
	app._interact()
	await process_frame
	await press("SheepCorner")
	var ready_watch:=button("SheepStepWatch")
	expect(ready_watch!=null and ready_watch.is_visible_in_tree(),"Shelter built: watch button is offered")
	await capture("01-sheep-corner-%s.png"%tag)
	# Rain without reduced motion is refused and records nothing.
	at_time(wet)
	await press("SheepStepWatch")
	expect(not person.has(Goals.SHEEP_STEP_KEY) and "下雨" in last_notice,"Rain refuses the watch with a gentle message: "+last_notice)
	# Clear day: start the watch.
	at_time(dry)
	app._interact()
	await process_frame
	await press("SheepCorner")
	await press("SheepStepWatch")
	expect(is_equal_approx(float(person.get(Goals.SHEEP_STEP_KEY,-1.0)),dry) and app.session.snapshot.has("own_mianmian_step_time"),"The watch is recorded once and sent only to its owner")
	var walk:=Vector2i(sheep.x-3,sheep.y+1)
	stand(walk)
	at_time(dry+Step.WALK_IN+0.4)
	await capture("02-sheep-walking-in-%s.png"%tag)
	at_time(dry+Step.WALK_IN+Step.PAUSE+0.5)
	await capture("03-sheep-under-eave-%s.png"%tag)
	at_time(dry+Step.TOTAL-1.0)
	expect(Step.offset(app.session.snapshot,false,float(world.state.time))==Vector2(Step.ONE_STEP,0),"One step out of the eave")
	await capture("04-sheep-one-step-out-%s.png"%tag)
	# Not ready until six seconds; the report page says so.
	stand(mm)
	at_time(dry+3.0)
	Tasks.bond_goal(app,"mianmian",4)
	await process_frame
	var report:=button("BondGoalDo")
	expect(report!=null and report.disabled,"Report is disabled at three seconds")
	await capture("05-goal-waiting-%s.png"%tag)
	at_time(dry+Goals.SHEEP_STEP_SECONDS+0.1)
	Tasks.bond_goal(app,"mianmian",4)
	await process_frame
	await capture("06-goal-ready-%s.png"%tag)
	await press("BondGoalDo")
	expect(app.session.snapshot.resident_goals.mianmian["4"].state=="done","Reporting completes the event")
	expect(not world.act(token,"again",Goals.ACTION,mm,"mianmian:4::").ok,"Second report refused")
	# Journal from the goal page and from the talk page.
	Tasks.bond_goal(app,"mianmian",4)
	await process_frame
	expect(button("MianmianJournalGoalEntry")!=null,"Goal page offers the care journal")
	await press("MianmianJournalGoalEntry")
	within_screen(app.modal.find_child("MianmianHatArt",true,false) as Control,"hat art")
	within_screen(button("MianmianJournalBack"),"journal back")
	within_screen(button("MianmianHatToggle"),"hat toggle")
	var last_line:=app.modal.find_child("MianmianJournalLine_3",true,false) as Control
	for index in 4:within_screen(app.modal.find_child("MianmianJournalLine_%d"%index,true,false) as Control,"journal line %d"%index)
	var viewport:Control=last_line.get_parent() if last_line!=null else null
	while viewport!=null and not viewport is ScrollContainer:viewport=viewport.get_parent() as Control
	if viewport!=null:expect(viewport.get_global_rect().grow(1.0).encloses(last_line.get_global_rect()),"All four journal lines fit without scrolling")
	expect(visible_text(app.modal).contains("自己走出屋簷") and visible_text(app.modal).contains("戴上羊毛帽"),"Journal names the event and offers the hat")
	await capture("07-journal-%s.png"%tag)
	await press("MianmianHatToggle")
	expect(person.get(Goals.WOOL_HAT_KEY)==true,"Hat goes on through the existing action")
	stand(sheep+Vector2i(-2,1))
	await capture("08-hat-in-world-%s.png"%tag)
	Tasks.bond_dialogue(app,"mianmian")
	await process_frame
	expect(button("MianmianJournalEntry")!=null,"Talk page offers the journal")
	await press("MianmianJournalEntry")
	expect(visible_text(app.modal).contains("脫下羊毛帽"),"Journal now offers to take the hat off")
	await press("MianmianJournalBack")
	# Replay with reduced motion on a rainy day: calm mode is accepted and shows the finished pose.
	app.sound.reduced_motion=true
	app.view.reduced_motion=true
	var wet2:=day_time(true,dry+100.0)
	at_time(wet2)
	stand(sheep)
	app._interact()
	await process_frame
	await press("SheepCorner")
	expect(visible_text(app.modal).contains("再安靜看小羊走出屋簷"),"Replay wording after completion")
	await press("SheepStepWatch")
	expect(is_equal_approx(float(person.get(Goals.SHEEP_STEP_KEY,-1.0)),wet2),"Reduced motion allows the watch in rain and restarts it")
	stand(Vector2i(sheep.x-3,sheep.y+1))
	at_time(wet2+1.0)
	expect(Step.offset(app.session.snapshot,true,wet2+1.0)==Vector2(Step.ONE_STEP,0),"Reduced motion shows the finished pose at once")
	await capture("09-reduced-motion-%s.png"%tag)
	# Save and reload.
	expect(app.session.shutdown(),"Save and close")
	var loaded:=World.new()
	expect(loaded.load_world(path),"Reload the saved island")
	if loaded.state.players.has(token):
		var saved:Dictionary=loaded.state.players[token]
		expect(Goals.done(saved,"mianmian").has(4) and saved.get(Goals.WOOL_HAT_KEY)==true and saved.has(Goals.SHEEP_STEP_KEY),"Completion, hat and watch time survive reload")
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	app.sound.close()
	await create_timer(0.15).timeout
	print("MIANMIAN_STEP_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
