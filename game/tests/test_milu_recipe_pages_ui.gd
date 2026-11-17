extends SceneTree
## Uses the normal interaction pages in a local game with the picnic and bond stage preset.
const World:=preload("res://scripts/world.gd")
const Goals:=World.RESIDENT_GOALS
const Tasks:=preload("res://scripts/life_ui_tasks.gd")
var checks:=0
var failures:=0

func _initialize() -> void:run.call_deferred()

func expect(ok:bool,message:String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)

func capture(filename:String) -> void:
	if DisplayServer.get_name()=="headless":return
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--capture-dir="):continue
		await RenderingServer.frame_post_draw
		expect(root.get_texture().get_image().save_png(arg.trim_prefix("--capture-dir=").path_join(filename))==OK,"Capture "+filename)

func run() -> void:
	root.size=Vector2i(1024,640)
	var app=load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	var path:="user://milu-recipe-pages-%d.json"%OS.get_process_id()
	if app.session.host(0,"渡口島民",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	var world:World=app.session.world
	var token:String=app.session.profile.token
	var person:Dictionary=world.state.players[token]
	world.state.board=true
	world.state.picnic=true
	world.state.community={"table":World.COMMUNITY.choose_table(world.state)}
	var board:=World.milu_recipe_cell(world.state,"board")
	person.x=board.x+0.5
	person.y=board.y+0.5
	expect(not world.act(token,"too-early",Goals.RECIPE_PAGE_ACTION,board,"board").ok,"Paper requires stage two")
	person.bonds={"milu":{"points":6,"talk_day":-1,"gift_day":-1}}
	expect(not world.act(token,"wrong-cell",Goals.RECIPE_PAGE_ACTION,board,"shop").ok,"Forged landmark rejected")
	app.session._send_snapshot(1)
	Tasks.resident(app,"milu")
	await process_frame
	var book:=app.modal.find_child("MiluRecipeBook",true,false) as Button
	expect(book!=null,"Milu opens the search book")
	if book!=null:book.pressed.emit()
	await process_frame
	await capture("01-plaza-clues.png")
	app._close_modal()
	for site:String in ["table","board","shop"]:
		var cell:=World.milu_recipe_cell(world.state,site)
		person.x=cell.x+0.5
		person.y=cell.y+0.5
		app.session.rates[1].clear()
		app.session._send_snapshot(1)
		app._interact()
		await process_frame
		var marker:=app.modal.find_child("MiluRecipePage",true,false) as Button if is_instance_valid(app.modal) else null
		expect(marker!=null,"Ordinary interaction shows the paper at "+site)
		if marker!=null:marker.pressed.emit()
		await process_frame
		expect((int(app.session.snapshot.own_milu_recipe_pages)&int(Goals.RECIPE_PAGES[site].bit))!=0,"Collected "+site)
		expect(not world.act(token,"repeat-"+site,Goals.RECIPE_PAGE_ACTION,cell,site).ok,"Duplicate rejected at "+site)
		expect(not app.session.snapshot.players[app.session.own_id].has(Goals.RECIPE_PAGE_KEY),"Private progress stays out of public players")
		if is_instance_valid(app.modal):app._close_modal()
	var milu:Vector2i=World.bond_place(world.state,"milu")[1]
	person.x=milu.x+0.5
	person.y=milu.y+0.5
	app.session.rates[1].clear()
	app.session._send_snapshot(1)
	app._interact()
	await process_frame
	Tasks.bond_events(app,"milu",1)
	await process_frame
	Tasks.bond_goal(app,"milu",2)
	await process_frame
	var submit:=app.modal.find_child("BondGoalDo",true,false) as Button
	expect(submit!=null and not submit.disabled,"Complete through the event's normal submit button")
	if submit!=null:submit.pressed.emit()
	await process_frame
	expect(app.session.snapshot.resident_goals.milu["2"].state=="done","Milu accepts the three pages")
	var table:=World.milu_recipe_cell(world.state,"table")
	person.x=table.x+0.5
	person.y=table.y+0.5
	app.session._send_snapshot(1)
	app._close_modal()
	app._interact()
	await process_frame
	book=app.modal.find_child("MiluRecipeBook",true,false) as Button
	expect(book!=null,"Completed guide can be read at the table")
	if book!=null:book.pressed.emit()
	await process_frame
	await capture("02-table-guide.png")
	var enter:Button
	for candidate:Node in app.modal.find_children("*","Button",true,false):
		if candidate.text=="打開共餐桌":enter=candidate
	expect(enter!=null,"Guide opens real sharing controls when near the table")
	if enter!=null:enter.pressed.emit()
	await process_frame
	expect(app.modal.has_meta("community_body"),"Sharing controls opened")
	expect(app.session.shutdown(),"Save and close")
	var loaded:=World.new()
	expect(loaded.load_world(path),"Reload the saved island")
	expect(int(loaded.state.players[token].get(Goals.RECIPE_PAGE_KEY,0))==Goals.RECIPE_PAGE_MASK,"Three pages survive reload")
	expect(Goals.done(loaded.state.players[token],"milu").has(2),"Handbook unlock survives reload")
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	app.sound.close()
	await create_timer(0.15).timeout
	print("MILU_RECIPE_PAGE_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
