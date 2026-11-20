extends SceneTree
## T067 headless UI test: B6–B15 station cards, hoist (升降台) buttons, badge strip,
## deep commissions and the 15-page survey journal. Run with `-- --village-art-preview`.
const World=preload("res://scripts/world.gd")
const UI=preload("res://scripts/mine_ui.gd")
const SurveyUI=preload("res://scripts/mine_survey_ui.gd")
const Catalog=preload("res://scripts/mine_expansion_catalog.gd")
var app
var w
var id:String
var checks:=0
var failures:=0

func _initialize()->void:run.call_deferred()

func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;push_error(message)

func visible(c:Control)->bool:
	if c==null or not c.is_visible_in_tree() or not root.get_visible_rect().encloses(c.get_global_rect()):return false
	var parent:=c.get_parent()
	while parent:
		if parent is ScrollContainer and not parent.get_global_rect().encloses(c.get_global_rect()):return false
		parent=parent.get_parent()
	return true

func control(name:String)->Control:
	return app.modal.find_child(name,true,false) as Control

func texts()->String:
	var out:=PackedStringArray()
	for label in app.modal.find_children("*","Label",true,false):out.append(label.text)
	return "\n".join(out)

func place(region:String,p:Vector2i)->void:
	var person:Dictionary=w.state.players[id]
	person.region=region
	person.x=p.x-0.5;person.y=p.y+0.5
	app.session._send_snapshot(1)

## PRESET mine progress. Q07: the surface hoist counts as repaired whenever B6+
## is open, so these checks keep covering the post-repair landing buttons
## (the pre-repair card is covered by test_mine_hoist_ui.gd).
func progress(unlocked:int)->void:
	w.state.mine_depths={"unlocked":unlocked,"ready":{},"pumped":24,"hoist":unlocked>=6}
	app.session._send_snapshot(1)

func settle()->void:
	for i in range(5):await process_frame
	app._layout_preview();await process_frame

func fits(label:String)->void:
	check(root.get_visible_rect().encloses(app.modal.get_global_rect()),"Modal fits viewport: "+label)
	var scroll:=control("ModalScroll") as ScrollContainer
	if scroll:check(not scroll.get_v_scroll_bar().visible,"Content fits without scrolling: "+label)
	for c in app.modal.find_children("*","BaseButton",true,false):check(visible(c),"Button fully visible: %s (%s)"%[c.name,label])

func open(site:String,label:String)->void:
	UI.open(app,site)
	await settle()
	await fits("%s %s %s"%[site,label,root.size])

func enabled(name:String)->bool:
	var button:=control(name) as BaseButton
	return button!=null and visible(button) and not button.disabled

func press(name:String)->bool:
	var button:=control(name) as BaseButton
	check(button!=null and visible(button) and not button.disabled,"Enabled visible "+name)
	if button==null or button.disabled:return false
	await create_timer(0.12).timeout
	button.pressed.emit()
	await process_frame
	return true

func region()->String:
	return str(app.session.snapshot.region_id)

func run()->void:
	var path:=OS.get_environment("TEMP").path_join("deep-ui-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	app=preload("res://main.tscn").instantiate();app.village_art_preview=true;root.add_child(app)
	app.set_process(false);app.session.set_physics_process(false)
	if app.session.host(0,"深層旅人",path)!=OK:check(false,"Host starts");print("MINE_DEEP_UI_TESTS checks=%d failures=%d"%[checks,failures]);quit(1);return
	w=app.session.world;id=app.session.profile.token
	w.state.picnic=true;w.state.board=true
	for size in [Vector2i(1024,640),Vector2i(1280,800)]:
		root.size=size
		progress(15)
		w.state.players[id].mine_energy=60
		# Surface entry sign: first floor plus every opened hoist landing.
		place("jinguashi",World.MINES.ENTRY)
		await open("entry","unlocked 15")
		for name in ["MineEnter","MineLift6","MineLift10","MineLift15"]:check(enabled(name),"Surface entry offers "+name)
		check((control("MineLift15") as Button).text=="搭升降台到第 15 層","Hoist button uses 升降台 wording")
		check(control("MineFictionNote")!=null and "深層地質為遊戲設定。" in texts(),"Entry shows deep-geology fiction note")
		check(control("MineHoistReady")!=null and control("MineHoistRepair")==null,"Repaired hoist shows ready caption, no repair section")
		var badges:Array=app.modal.find_children("MineBadge*","PanelContainer",true,false)
		check(badges.size()==World.MINES.MAX_DEPTH,"Badge strip shows all 15 floors")
		for badge:Control in badges:check(visible(badge),"Badge fully visible "+badge.name)
		await press("MineLift15")
		check(region()=="mine_15","Surface hoist lowers to B15")
		# B15: no further descent, no further commission.
		place("mine_15",World.MINES.DOWN)
		await open("down","B15")
		check(control("MineDown")==null,"B15 has no descent button")
		check("這裡是最深的提燈大廳。" in texts(),"B15 down sign explains the bottom")
		place("mine_15",World.MINES.SERVICE)
		await open("service","B15")
		check(control("MineCommission")==null,"B15 has no sixteenth-floor project")
		check("深層地質為遊戲設定。" in texts(),"Deep service shows fiction note")
		check(control("MineFreight")==null,"Freight stays limited to B4–B5")
		place("mine_15",World.MINES.LIFT)
		await open("lift","B15")
		await press("MineLiftUp")
		check(region()=="jinguashi","B15 hoist returns to the surface")
		place("jinguashi",World.MINES.ENTRY)
		await open("entry","return")
		await press("MineLift10")
		check(region()=="mine_10","Surface hoist lowers to B10")
		# B12 lift card, zone/hazard captions, remote disabled state.
		place("mine_12",World.MINES.LIFT)
		await open("lift","B12")
		check(enabled("MineLiftUp"),"B12 hoist is usable nearby")
		check((control("MineLiftUp") as Button).text=="搭升降台回山城","Return hoist uses 升降台 wording")
		var zone:=control("MineZone") as Label
		check(zone!=null and zone.text.contains(Catalog.ZONES.warm_rock.name) and zone.text.contains(Catalog.HAZARDS.warm_air.name),"B12 shows zone and hazard")
		check(Catalog.HAZARDS.warm_air.note in texts(),"B12 shows hazard note")
		check(control("MineBadge12").tooltip_text=="第 12 層 · 所在樓層","Current-floor badge tooltip")
		check(control("MineFictionNote")!=null,"Deep lift shows fiction note")
		for label:Label in app.modal.find_children("*","Label",true,false):
			check(label.get_minimum_size().x<=560.0,"Caption stays under 560px: "+label.text)
		place("mine_12",Vector2i(32,26))
		await open("lift","B12 remote")
		check(control("MineLiftUp")!=null and (control("MineLiftUp") as Button).disabled,"Remote hoist is disabled")
		place("mine_12",World.MINES.DOWN)
		await open("down","B12")
		check(enabled("MineDown"),"B12 descends while deeper floors are open")
		# B14 commission (three materials) at the frontier.
		progress(14)
		place("mine_14",World.MINES.SERVICE)
		await open("service","B14 frontier")
		var title:=control("MineCommissionTitle") as Label
		check(title!=null and title.text.contains(Catalog.COMMISSIONS[14].title),"B14 shows catalog commission title")
		check(control("MineRequirements")!=null and control("MineRequirements").get_child_count()==World.MINES.COSTS[13].size(),"B14 lists every material")
		var commission:=control("MineCommission") as Button
		check(commission!=null and commission.disabled,"B14 project waits for materials")
		w.state.players[id].inventory.merge(World.MINES.COSTS[13],true)
		app.session._send_snapshot(1);UI.refresh(app);await settle()
		await fits("B14 stocked %s"%size)
		await press("MineCommission")
		check(int(w.state.mine_depths.unlocked)==15,"B14 commission opens B15")
		# B5 now carries the B5→B6 project; freight stays.
		progress(5)
		place("mine_5",World.MINES.SERVICE)
		await open("service","B5 frontier")
		check(control("MineCommission")!=null,"B5 offers the B6 project")
		check(control("MineCommissionTitle")!=null and (control("MineCommissionTitle") as Label).text.contains(Catalog.COMMISSIONS[5].title),"B5 shows catalog title")
		check(control("DrillUnlockNote")!=null,"Drill unlock note stays at B5")
		if app.has_method("_freight_menu"):check(control("MineFreight")!=null,"B5 keeps freight loading")
		check(control("MineBadge6").tooltip_text=="第 6 層 · 整備中","Locked badge tooltip")
		place("mine_8",World.MINES.SERVICE)
		progress(9)
		await open("service","B8")
		check(control("MineFreight")==null and control("MineAutoFreight")==null,"No freight on B8")
		# Partial landings.
		place("jinguashi",World.MINES.ENTRY)
		await open("entry","unlocked 9")
		check(enabled("MineLift6") and control("MineLift10")==null and control("MineLift15")==null,"Only opened landings are offered")
		progress(5)
		await open("entry","unlocked 5")
		check(control("MineLift6")==null,"No hoist before B6 opens")
		check(control("MineHoistRepair")==null and control("MineHoistReady")==null,"No hoist repair section before B6 opens")
		app._close_modal()
	# Survey journal: 15 pages, reward still counts B1–B5 only.
	root.size=Vector2i(1024,640)
	progress(15)
	w.state.mine_survey.players[id]={"seen":{},"claimed":false}
	place("mine_12",World.MINES.REST)
	check(SurveyUI.guidance(app.session.snapshot)=="深層 0／10\n往北找觀察點","Deep guidance gives B12 progress and the side-cave direction on different lines")
	for size in [Vector2i(1024,640),Vector2i(1280,800)]:
		root.size=size
		SurveyUI.open(app,12)
		await settle()
		await fits("survey %s"%size)
		for page in range(1,16):check(control("SurveyPage%d"%page)!=null,"Survey page button B%d"%page)
		check((control("SurveyTitle") as Label).text=="B12 · 尚未觀察","Unseen deep page hides its title")
		check((control("SurveyDetail") as Label).text==World.MINE_SURVEY.entry(12).hint,"Unseen deep page shows catalog hint")
		app._close_modal()
	root.size=Vector2i(1024,640)
	w.state.mine_survey.players[id]={"seen":{"1":true,"2":true,"3":true,"4":true,"5":true,"7":true},"claimed":false}
	app.session._send_snapshot(1)
	SurveyUI.open(app,7)
	await settle()
	await fits("survey reward ready")
	check((control("SurveyTitle") as Label).text==Catalog.DEPTHS[7].survey.title,"Seen deep page shows its title")
	check(control("SurveyClaim")!=null,"Five shallow pages make the reward claimable")
	var deep_note:=control("SurveyDeepProgress") as Label
	check(deep_note!=null and deep_note.text.contains("側洞 5／5") and deep_note.text.contains("深層 1／10"),"Deep progress counted separately")
	check(app.modal_feedback.text.contains("深層 1／10"),"Feedback line shows deep count")
	app._close_modal()
	app.session.shutdown();await create_timer(0.3).timeout
	app.queue_free();await process_frame;await process_frame
	for suffix in ["",".bak",".writer-lock"]:DirAccess.remove_absolute(path+suffix)
	if checks==0:failures+=1
	print("MINE_DEEP_UI_TESTS checks=%d failures=%d"%[checks,failures]);quit(int(failures>0))
