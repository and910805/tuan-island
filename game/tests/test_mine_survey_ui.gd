extends SceneTree

const World=preload("res://scripts/world.gd")
var app
var world
var actor:String
var checks:=0
var failures:=0

func _initialize()->void:
	run.call_deferred()

func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)

func place(region:String,cell:Vector2i)->void:
	var person:Dictionary=world.state.players[actor]
	person.region=region
	person.x=cell.x-0.5
	person.y=cell.y+0.5
	app.session._send_snapshot(1)

func settle()->void:
	for i in range(5):await process_frame
	app._layout_preview()
	await process_frame

func control(id:String)->Control:
	return app.modal.find_child(id,true,false) as Control

func visible(item:Control)->bool:
	if not item or not item.is_visible_in_tree() or not root.get_visible_rect().encloses(item.get_global_rect()):return false
	var parent:=item.get_parent()
	while parent:
		if parent is ScrollContainer and not parent.get_global_rect().encloses(item.get_global_rect()):return false
		parent=parent.get_parent()
	return true

func press(id:String)->void:
	await settle()
	var button:=control(id) as Button
	check(visible(button) and not button.disabled,"Enabled and visible "+id)
	if button and not button.disabled:
		await create_timer(0.15).timeout
		button.pressed.emit()
	await process_frame

func unseen(depth:int)->void:
	var entry:Dictionary=World.MINE_SURVEY.ENTRIES[depth-1]
	check((control("SurveyTitle") as Label).text!=entry.title,"Unseen page hides discovery title")
	check((control("SurveyDetail") as Label).text!=entry.text,"Unseen page hides discovery text")

func fits_live(message:String)->void:
	app.set_process(true)
	await create_timer(0.3).timeout
	var scroll:=control("ModalScroll") as ScrollContainer
	check(not scroll.get_v_scroll_bar().visible,message)
	for button in app.modal.find_children("*","Button",true,false):
		check(visible(button),"Fully shows "+button.name)
	app.set_process(false)

func run()->void:
	root.size=Vector2i(1024,640)
	var path:=OS.get_environment("TEMP").path_join("survey-ui-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	app=preload("res://main.tscn").instantiate()
	app.village_art_preview=true
	root.add_child(app)
	app.set_process(false)
	app.session.set_physics_process(false)
	if app.session.host(0,"側洞旅人",path)!=OK:
		check(false,"Host starts")
		quit(1)
		return
	world=app.session.world
	actor=app.session.profile.token
	world.state.picnic=true
	world.state.board=true
	world.state.mine_depths.unlocked=5
	world.state.mine_depths.pumped=24

	var first:Vector2i=World.MINE_SURVEY.POINTS[1]
	place("mine_1",first)
	check(app.view.interaction_focus()=="mine_survey","Empty side cave point offers the observation interaction")
	app._refresh_hud()
	check("往北找觀察點" in app.objective.text and "休息站補水\n礦務站整備下層" in app.objective.text,"Mine HUD guides the undiscovered side cave and keeps the two station hints on separate lines")
	for size in [Vector2i(1024,640),Vector2i(1280,800)]:
		root.size=size
		app._interact()
		await settle()
		check(app.modal.get_meta("survey_observe",false),"World interaction opens the observation card")
		unseen(1)
		await fits_live("Unobserved card fits under live HUD refresh at %s"%size)
		app._close_modal()
	root.size=Vector2i(1024,640)
	world.state.players[actor].inventory.wood=20
	var built:Dictionary=world.act(actor,"survey-ui-chest","build",first,"chest")
	check(built.ok,"A chest can occupy an observation cell")
	app.session._send_snapshot(1)
	check(app.view.interaction_focus()==World.key(first),"Existing chest retains its interaction")
	app._journal()
	await settle()
	unseen(1)
	check(not app.modal.get_meta("survey_observe",true),"Mine journal shortcut opens five-page handout")
	await press("SurveyPage2")
	unseen(2)
	check(control("SurveyObserve")==null,"Other floors cannot be observed remotely")
	await press("SurveyPage1")
	await press("SurveyObserve")
	check(world.state.mine_survey.players[actor].seen=={"1":true},"Occupied point records via actual journal button")
	app._refresh_hud()
	check("翻手帳" in app.objective.text and "往北找觀察點" not in app.objective.text,"Recorded floor shows progress without repeating directions")
	check(app.modal.get_meta("survey_page")==1,"Saving observation keeps page selection")
	check((control("SurveyDetail") as Label).text==World.MINE_SURVEY.ENTRIES[0].text,"Saved page displays its discovery")
	await press("SurveyPage2")
	app.session._send_snapshot(1)
	check(app.modal.get_meta("survey_page")==2,"Snapshot refresh keeps chosen page")

	for depth in range(2,6):
		place("mine_%d"%depth,World.MINE_SURVEY.POINTS[depth])
		app._interact()
		await press("SurveyObserve")
		check(world.state.mine_survey.players[actor].seen.has(str(depth)),"Observed B%d through its card"%depth)
		check((control("SurveyDetail") as Label).text==World.MINE_SURVEY.ENTRIES[depth-1].text,"Observation card updates in place")
		for size in [Vector2i(1024,640),Vector2i(1280,800)]:
			root.size=size
			await settle()
			await fits_live("Recorded B%d card fits under live HUD refresh at %s"%[depth,size])
	root.size=Vector2i(1024,640)
	await press("SurveyJournal")
	check((control("SurveyClaim") as Button).disabled,"Completed journal cannot claim underground")
	var table:Vector2i=World.BOBO_WORKSHOP.sites(app.session.snapshot).table
	place("jinguashi",table)
	app._refresh_hud()
	check("回波波整理桌領獎" in app.objective.text and "查看礦點與回程" in app.objective.text,"Surface HUD adds reward return while preserving route")
	app._bobo_sort_menu()
	await press("SortSurveyJournal")
	await fits_live("Complete journal fits under live HUD refresh")
	await press("SurveyPage4")
	await press("SurveyClaim")
	check(world.state.mine_survey.players[actor].claimed,"Bobo reward is saved")
	check(world.state.players[actor].inventory.get("gold_sample",0)==1,"Exactly one collection sample awarded")
	app._refresh_hud()
	check("回波波整理桌領獎" not in app.objective.text,"Claimed reward clears the contextual reminder")
	check(app.modal.get_meta("survey_page")==4 and control("SurveyClaim")==null,"Reward confirmation preserves page and removes claim")
	await press("SurveyBack")
	check(control("SortStart")!=null,"Original sorting flow remains accessible")

	app._close_modal()
	app.session.shutdown()
	await create_timer(0.3).timeout
	app.queue_free()
	await process_frame
	for suffix in ["",".bak",".writer-lock"]:DirAccess.remove_absolute(path+suffix)
	print("MINE_SURVEY_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
