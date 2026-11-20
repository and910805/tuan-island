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
		await create_timer(0.25).timeout
		await RenderingServer.frame_post_draw
		expect(root.get_texture().get_image().save_png(arg.trim_prefix("--capture-dir=").path_join(file_name))==OK,"Capture "+file_name)

func visible_text(value:String) -> bool:
	if not is_instance_valid(app.modal):return false
	for label:Node in app.modal.find_children("*","Label",true,false):
		if label.text.contains(value):return true
	return false

func notebook_node(id:String) -> Control:
	if not is_instance_valid(app.modal):return null
	if app.modal.name==id:return app.modal as Control
	return app.modal.find_child(id,true,false) as Control

func open_notebook() -> bool:
	Tasks.journal(app)
	await process_frame
	var book:Button
	for candidate:Node in app.modal.find_children("*","Button",true,false):
		if candidate.text=="星禾的作物觀察簿":book=candidate
	expect(book!=null,"Journal bookmark opens the growth notebook")
	if book==null:return false
	book.pressed.emit()
	await process_frame
	await process_frame
	expect(notebook_node("XingheGrowthNotebook")!=null,"Growth notebook modal exists")
	return notebook_node("XingheGrowthNotebook")!=null

func inside(inner:Rect2,outer:Rect2) -> bool:
	return inner.position.x>=outer.position.x-1.0 and inner.position.y>=outer.position.y-1.0 and inner.end.x<=outer.end.x+1.0 and inner.end.y<=outer.end.y+1.0

func verify_fit(tag:String) -> void:
	var view:=Rect2(Vector2.ZERO,Vector2(root.size))
	var book:=notebook_node("XingheGrowthNotebook")
	if book==null:return
	var frame:=book.get_global_rect()
	expect(inside(frame,view),tag+": notebook fits the window")
	var back:=notebook_node("XingheGrowthBack")
	var scroll:=notebook_node("ModalScroll")
	expect(back!=null and scroll!=null and not scroll.is_ancestor_of(back) and inside(back.get_global_rect(),frame),tag+": return button stays outside the scrollable page")
	for id in ["XingheGrowthEarly","XingheGrowthMature","XingheGrowthSelected"]:
		var node:=notebook_node(id)
		expect(node!=null and node.is_visible_in_tree(),tag+": visible "+id)
		if node==null:continue
		var rect:=node.get_global_rect()
		expect(rect.size.x>=24.0 and rect.size.y>=24.0,tag+": usable size "+id)
		expect(inside(rect,frame) and inside(rect,view),tag+": "+id+" fits")
	for node:Node in book.find_children("*","Control",true,false):
		var control:=node as Control
		if not control.is_visible_in_tree():continue
		if control is Label and (control as Label).text!="":
			expect(inside(control.get_global_rect(),view),tag+": label on screen "+(control as Label).text.left(12))
		if control is Button:
			expect(inside(control.get_global_rect(),view),tag+": button on screen "+control.name)

func world_digest() -> int:
	return hash(JSON.stringify([world.state.players[token],world.state.crops]))

func check_species_filter(tag:String) -> void:
	var picks:Array[Button]=[]
	for node:Node in app.modal.find_children("XingheGrowthSpecies_*","Button",true,false):picks.append(node as Button)
	expect(picks.size()>=2,tag+": species filters exist")
	var title:=notebook_node("XingheGrowthSelected") as Label
	if picks.size()<2 or title==null:return
	var before:=world_digest()
	var seen:=[title.text]
	for pick in picks:
		expect(pick.name.begins_with("XingheGrowthSpecies_") and World.CROPS.has(String(pick.name).trim_prefix("XingheGrowthSpecies_")),tag+": filter id is a crop "+pick.name)
		pick.pressed.emit()
		await process_frame
		title=notebook_node("XingheGrowthSelected") as Label
		expect(title!=null and not seen.has(title.text) or pick==picks[0],tag+": filter changes selected title")
		if title!=null:seen.append(title.text)
	expect(world_digest()==before,tag+": filters only change the notebook")
	expect(notebook_node("XingheGrowthNotebook")!=null,tag+": notebook stays open")

func check_pending_page(tag:String) -> void:
	var tracking:=notebook_node("XingheGrowthTracking")
	expect(tracking!=null and tracking.is_visible_in_tree(),tag+": tracking note visible")
	if tracking is Label:expect((tracking as Label).text.strip_edges()!="",tag+": tracking note has text")
	var early:=notebook_node("XingheGrowthEarly")
	expect(early!=null and early.is_visible_in_tree() and early.get_global_rect().size.x>=24.0,tag+": illustrated seedling shown")

func check_both_sizes(stage:String,pending:bool,filter:bool) -> void:
	for size in [Vector2i(1024,640),Vector2i(1280,800)]:
		var tag:="%s %dx%d"%[stage,size.x,size.y]
		root.size=size
		await process_frame
		await process_frame
		if not await open_notebook():continue
		verify_fit(tag)
		if pending:check_pending_page(tag)
		await capture("notebook-%s-%d.png"%[stage,size.x])
		if filter:await check_species_filter(tag)
		app._close_modal()
		await process_frame
	root.size=Vector2i(1024,640)
	await process_frame

func run() -> void:
	root.size=Vector2i(1024,640)
	app=load("res://main.tscn").instantiate()
	root.add_child(app)
	await process_frame
	var path:="user://xinghe-growth-%d.json"%OS.get_process_id()
	if app.session.host(0,"觀察島民",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	world=app.session.world
	token=app.session.profile.token
	person=world.state.players[token]
	var waterway:Vector2i=World.bond_place(world.state,"xinghe")[1]
	person.region=World.REGIONS.LANYANG
	stand(waterway)
	app._interact()
	await process_frame
	await press("BondOpen")
	await press("BondTalk")
	expect(World.RESIDENT_BOND.stage(person,"xinghe")==1,"Meet Xinghe through the normal waterway panel")
	app._close_modal()
	person.region=World.REGIONS.HOME
	# East of the reserved public mill site (47..49,23..26), clear of base resources.
	var first:=Vector2i(50,24)
	var second:=Vector2i(51,24)
	stand(first)
	for tile in [first,second]:
		world.state.removed[World.key(tile)]=true
		expect(world.act(token,"hoe-"+World.key(tile),"hoe",tile).ok,"Tilled "+World.key(tile))
		expect(world.act(token,"seed-"+World.key(tile),"seed",tile,"radish").ok,"Sowed "+World.key(tile))
		expect(world.act(token,"water-"+World.key(tile),"water",tile).ok,"Watered "+World.key(tile))
	stand(first)
	app._interact()
	await process_frame
	await press("XingheGrowthObservation")
	expect(app.session.snapshot.own_xinghe_growth.tile==World.key(first),"Seedling record references the chosen plot")
	expect(not app.session.snapshot.players[app.session.own_id].has(Goals.GROWTH_KEY),"Only the owner sees their tracked plant")
	expect(not world.act(token,"repeat-first",Goals.GROWTH_ACTION,first).ok,"Cannot repeat the seedling observation")
	stand(first+Vector2i.UP)
	await capture("00-marked-seedling.png")
	var pending_digest:=world_digest()
	await check_both_sizes("pending",true,false)
	expect(world_digest()==pending_digest,"Reading the pending notebook before the first report changes nothing")
	stand(first)
	var seedling_save:=World.new()
	expect(seedling_save.load_world(path) and seedling_save.state.players[token].get(Goals.GROWTH_KEY,{}).get("tile")==World.key(first),"Seedling progress persists before maturity")
	expect(world.step(float(World.CROPS.radish.time)+2.0,true),"Advance the ordinary growth clock")
	expect(float(world.state.crops[World.key(first)].growth)==float(World.CROPS.radish.time),"Observed seedling matured through growth")
	stand(second)
	expect(not world.act(token,"wrong-plant",Goals.GROWTH_ACTION,second).ok,"Same species at a different tile does not count")
	stand(first)
	app._interact()
	await process_frame
	await capture("01-grown-plot.png")
	await press("XingheGrowthObservation")
	expect(app.session.snapshot.own_xinghe_growth.is_empty() and app.session.snapshot.own_xinghe_growth_log.get("radish",false),"Two stages archive the species")
	expect(float(world.state.crops[World.key(first)].growth)==float(World.CROPS.radish.time),"Observing leaves the mature crop untouched")
	person.region=World.REGIONS.LANYANG
	stand(waterway)
	Tasks.bond_goal(app,"xinghe",1)
	await process_frame
	await press("BondGoalDo")
	expect(app.session.snapshot.resident_goals.xinghe["1"].state=="done","Report unlocks the growth book")

	person.region=World.REGIONS.HOME
	stand(first)
	expect(world.act(token,"harvest-first","harvest",first).ok,"Harvest normally after completing the observation")
	expect(world.act(token,"seed-lettuce","seed",first,"lettuce").ok,"Start another species after reporting")
	stand(first)
	app._interact()
	await process_frame
	await press("XingheGrowthObservation")
	expect(app.session.snapshot.own_xinghe_growth.get("kind")=="lettuce","Unlocked feature supports another crop")
	expect(world.act(token,"water-lettuce","water",first).ok,"Watered the second specimen")
	expect(world.step(float(World.CROPS.lettuce.time)+2.0,true),"Advance the second specimen")
	expect(world.act(token,"harvest-lettuce","harvest",first).ok,"Harvesting before recording maturity can require a new observation")
	expect(world.act(token,"reseed-lettuce","seed",first,"lettuce").ok,"Replant the same species at the same tile")
	expect(not person.has(Goals.GROWTH_KEY),"Replacement planting clears the old seedling observation")
	stand(first)
	app._interact()
	await process_frame
	await press("XingheGrowthObservation")
	expect(world.act(token,"water-lettuce-again","water",first).ok,"Watered the replanted specimen")
	expect(world.step(float(World.CROPS.lettuce.time)+2.0,true),"Advance the replanted specimen")
	stand(first)
	app._interact()
	await process_frame
	await press("XingheGrowthObservation")
	expect(app.session.snapshot.own_xinghe_growth_log.get("lettuce",false),"A second species can be archived")

	if await open_notebook():
		await press("XingheGrowthSpecies_radish")
		expect(visible_text(str(World.CROPS.radish.name)) and visible_text("幼苗") and visible_text("成熟"),"The observations are readable in the book")
		await capture("02-growth-book.png")
		app._close_modal()
		await process_frame
	await check_both_sizes("final",false,true)
	expect(app.session.shutdown(),"Save and close")
	var loaded:=World.new()
	expect(loaded.load_world(path),"Reload the saved island")
	var record:Dictionary=loaded.state.players[token]
	var saved_archive:Dictionary=record.get(Goals.GROWTH_LOG_KEY,{})
	expect(saved_archive.get("radish",false) and saved_archive.get("lettuce",false) and Goals.done(record,"xinghe").has(1),"Both species and completion survive reload")
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	app.sound.close()
	await create_timer(0.15).timeout
	print("XINGHE_GROWTH_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
