extends SceneTree
## T066 N07-2 星禾「空花圃的圖紙」: choose two flowers, arrange four cells, tutorial seedlings out of season,
## report, rewards (flower rack, garden cookie recipe), reload. Optional args: --capture-dir=DIR, --size=WxH, --large-text.
const World:=preload("res://scripts/world.gd")
const Goals:=World.RESIDENT_GOALS
const Weather:=preload("res://scripts/weather.gd")
const Tasks:=preload("res://scripts/life_ui_tasks.gd")

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

func fits(node:Control,tag:String) -> void:
	var screen:=Rect2(Vector2.ZERO,app.get_viewport_rect().size).grow(1.0)
	expect(node!=null and node.is_visible_in_tree() and screen.encloses(node.get_global_rect()),"On screen: "+tag)

func outer_scroll() -> bool:
	for node:Node in app.modal.find_children("*","ScrollContainer",true,false):
		var scroll:=node as ScrollContainer
		if scroll.is_visible_in_tree() and scroll.get_v_scroll_bar().max_value>scroll.size.y+1.0:return true
	return false

func day_in(season:String) -> float:
	for day in range(0,120):
		if Weather.season_on_day(day)==season:return float(day)*Weather.DAY_SECONDS+30.0
	return -1.0

func cell_texts() -> Array:
	var texts:Array=[]
	for index in 4:texts.append(button("BondGoalBedCell_%d"%index).text)
	return texts

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
	var path:="user://xinghe-bed-%d.json"%OS.get_process_id()
	if app.session.host(0,"星禾花圃",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	app.session.notice.connect(func(message:String,_ok:bool):last_notice=message)
	world=app.session.world
	token=app.session.profile.token
	person=world.state.players[token]
	world.state.picnic=true
	var where:Array=World.bond_place(app.session.snapshot,"xinghe")
	var place:Vector2i=where[1]
	person.region=str(where[0])
	person.bonds={"xinghe":{"points":6,"talk_day":-1,"gift_day":-1}}
	for key in ["bluebell","orange_blossom","chime_herb"]:person.inventory.erase(key)
	var spring:=day_in("spring")
	at_time(spring)
	stand(place)
	expect(not Goals.flower_rack_unlocked(person),"Rack is locked before the plan")
	Tasks.bond_goal(app,"xinghe",2)
	await process_frame
	var bed:=app.modal.find_child("BondGoalBed",true,false) as GridContainer
	expect(bed!=null and bed.columns==2 and button("BondGoalBedCell_3")!=null,"The flower bed is a two-by-two grid")
	expect(button("BondGoalBedCell_0").disabled and button("BondGoalDo").disabled,"Cells and report wait for a pair of flowers")
	await capture("01-bed-empty-%s.png"%tag)
	await press("BondGoalOption_bluebell_orange")
	expect(cell_texts()==["鈴蘭藍花","鈴蘭藍花","蜜橙花・教學苗","蜜橙花・教學苗"],"Spring: orange cells are tutorial seedlings: %s"%str(cell_texts()))
	await press("BondGoalBedCell_0")
	expect(cell_texts()[0].begins_with("蜜橙花") and button("BondGoalDo").disabled,"Three of one flower breaks the rule and blocks the report")
	expect(visible_text(app.modal).contains("兩種花各放兩格"),"The reason says each flower takes two cells")
	await press("BondGoalBedCell_3")
	expect(cell_texts()==["蜜橙花・教學苗","鈴蘭藍花","蜜橙花・教學苗","鈴蘭藍花"],"A valid two-column layout: %s"%str(cell_texts()))
	expect(visible_text(app.modal).contains("還差") or button("BondGoalDo").disabled,"Missing bluebell blocks the report")
	await capture("02-bed-short-%s.png"%tag)
	fits(button("BondGoalDo"),"report button")
	expect(not outer_scroll(),"The plan page needs no outer scrolling")
	person.inventory.bluebell=2
	person.inventory.orange_blossom=2
	app.session.rates[1].clear()
	app.session._send_snapshot(1)
	await process_frame
	await process_frame
	expect(not button("BondGoalDo").disabled,"Two bluebells plus seedlings are enough in spring")
	await capture("03-bed-ready-%s.png"%tag)
	await press("BondGoalDo")
	var choice:="bluebell_orange-1010"
	expect(Goals.done(person,"xinghe").get(2,"")==choice,"Reporting records the selected two-column layout")
	expect(int(person.inventory.get("bluebell",0))==0 and int(person.inventory.get("orange_blossom",0))==2,"Only the in-season flower was spent")
	expect("教學苗" in last_notice,"The reply mentions tutorial seedlings: "+last_notice)
	expect(not world.act(token,"again",Goals.ACTION,place,"xinghe:2:%s:"%choice).ok,"Second report of the same plan refused")
	# Done page: layout and rewards.
	Tasks.bond_goal(app,"xinghe",2)
	await process_frame
	expect(button("XingheRackPattern")!=null and app.modal.find_child("XingheBedLayout",true,false)!=null,"Done page shows the layout and the rack pattern")
	expect(visible_text(app.modal).contains("花園餅乾"),"Done page names the garden cookie")
	fits(button("XingheRackPattern"),"rack button")
	expect(not outer_scroll(),"The done page needs no outer scrolling")
	await capture("04-bed-done-%s.png"%tag)
	await press("XingheRackPattern")
	await capture("05-rack-pattern-%s.png"%tag)
	app._close_modal()
	expect(Goals.flower_rack_unlocked(person),"The flower rack is unlocked by the plan")
	# Reload.
	expect(app.session.shutdown(),"Save and close")
	var loaded:=World.new()
	expect(loaded.load_world(path),"Reload the saved island")
	if loaded.state.players.has(token):
		var saved:Dictionary=loaded.state.players[token]
		expect(Goals.done(saved,"xinghe").get(2,"")==choice and Goals.flower_rack_unlocked(saved),"The selected layout and rack unlock survive reload")
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	app.sound.close()
	await create_timer(0.15).timeout
	print("XINGHE_BED_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
