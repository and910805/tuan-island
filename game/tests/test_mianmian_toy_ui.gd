extends SceneTree
## T066 N06-3 棉棉「一個不太完美的玩具」: hand in cloth and fibre, choose a shape, reward page,
## play with companions, reload. Optional user args: --capture-dir=DIR, --size=WxH, --large-text.
const World:=preload("res://scripts/world.gd")
const Goals:=World.RESIDENT_GOALS
const Tasks:=preload("res://scripts/life_ui_tasks.gd")
const Page:=preload("res://scripts/mianmian_toy_page.gd")
const Art:=preload("res://scripts/mianmian_toy_art.gd")
const Almanac:=preload("res://scripts/life_ui_almanac.gd")

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

func button(id:String) -> Button:
	return app.modal.find_child(id,true,false) as Button if is_instance_valid(app.modal) else null

func press(id:String) -> void:
	var node:=button(id)
	expect(node!=null and not node.disabled,"Enabled action: "+id)
	if node!=null and not node.disabled:node.pressed.emit()
	await process_frame
	await process_frame

func press_text(text:String) -> bool:
	for node:Node in app.modal.find_children("*","Button",true,false):
		if (node as Button).text==text and not (node as Button).disabled:
			(node as Button).pressed.emit()
			await process_frame
			await process_frame
			return true
	return false

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
	var tag:=size_tag+("-large" if large_text else "")
	AudioServer.set_bus_mute(0,true)
	var path:="user://mianmian-toy-%d.json"%OS.get_process_id()
	if app.session.host(0,"棉棉玩具",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	world=app.session.world
	token=app.session.profile.token
	person=world.state.players[token]
	world.state.picnic=true
	person.bonds={"mianmian":{"points":14,"talk_day":-1,"gift_day":-1}}
	person.companion_dog={"following":true,"bond":0,"last_pet":-30.0}
	person.companion_cat={"following":false,"bond":0,"last_pet":-30.0}
	app.session.notice.connect(func(message:String,_ok:bool):last_notice=message)
	var place:Vector2i=World.bond_place(app.session.snapshot,"mianmian")[1]
	# Ordinary toys keep their own wording before the event.
	var plain_dog:Dictionary=world.act(token,"plain-dog","dog_toy",World.Dog.SITE)
	expect(plain_dog.ok and "布玩具" in str(plain_dog.message) and not "棉棉" in str(plain_dog.message),"Dog keeps its ordinary toy message: %s"%str(plain_dog.message))
	person.companion_cat.following=true
	var plain_cat:Dictionary=world.act(token,"plain-cat","cat_yarn",World.Dog.SITE)
	expect(plain_cat.ok and "毛線球" in str(plain_cat.message),"Cat keeps its ordinary yarn message: %s"%str(plain_cat.message))
	person.companion_cat.following=false
	person.companion_dog.bond=0
	person.companion_dog.last_pet=-30.0
	person.companion_cat.bond=0
	person.companion_cat.last_pet=-30.0
	person.companion_dog.erase("last_play")
	person.companion_cat.erase("last_play")
	stand(place)
	expect(not Page.available(app.session.snapshot),"No toy page before the event")
	person.inventory.cotton_cloth=2
	person.inventory.fiber=4
	expect(not world.act(token,"short",Goals.ACTION,place,"mianmian:3:doll:").ok,"Short on cloth is refused")
	expect(int(person.inventory.cotton_cloth)==2 and int(person.inventory.fiber)==4,"Refusal keeps the inventory")
	person.inventory.cotton_cloth=3
	stand(place)
	Tasks.bond_goal(app,"mianmian",3)
	await process_frame
	expect(not world.act(token,"no-choice",Goals.ACTION,place,"mianmian:3::").ok,"A shape must be chosen")
	await press("BondGoalOption_doll")
	await capture("01-goal-choice-%s.png"%tag)
	await press("BondGoalDo")
	expect(int(person.inventory.get("cotton_cloth",0))==0 and int(person.inventory.get("fiber",0))==0,"Exactly 3 cloth and 4 fiber are spent")
	expect(app.session.snapshot.resident_goals.mianmian["3"].choice=="doll" and Art.choice(app.session.snapshot)=="doll","The chosen shape is recorded for the owner")
	person.inventory.cotton_cloth=3
	person.inventory.fiber=4
	expect(not world.act(token,"again",Goals.ACTION,place,"mianmian:3:ball:").ok and int(person.inventory.cotton_cloth)==3,"Reporting twice is refused and costs nothing")
	stand(place)
	Tasks.bond_goal(app,"mianmian",3)
	await process_frame
	expect(button("MianmianToyGoalEntry")!=null,"Completed goal offers the toy page")
	await press("MianmianToyGoalEntry")
	within_screen(app.modal.find_child("MianmianToyArt",true,false) as Control,"toy art")
	within_screen(button("MianmianToyBack"),"toy back")
	var last_tip:=app.modal.find_child("MianmianToyTip_2",true,false) as Control
	for index in 3:within_screen(app.modal.find_child("MianmianToyTip_%d"%index,true,false) as Control,"toy tip %d"%index)
	var viewport:Control=last_tip.get_parent() if last_tip!=null else null
	while viewport!=null and not viewport is ScrollContainer:viewport=viewport.get_parent() as Control
	if viewport!=null:expect(viewport.get_global_rect().grow(1.0).encloses(last_tip.get_global_rect()),"All three toy tips fit without scrolling")
	expect(visible_text(app.modal).contains("布偶") and visible_text(app.modal).contains("抱得很緊"),"Page names the chosen toy and quotes Mianmian")
	await capture("02-toy-page-%s.png"%tag)
	await press("MianmianToyBack")
	expect(button("MianmianToyGoalEntry")!=null,"Back returns to the goal page")
	Tasks.bond_dialogue(app,"mianmian")
	await process_frame
	expect(button("MianmianToyEntry")!=null,"Talk page offers the toy page")
	await press("MianmianToyEntry")
	await press("MianmianToyBack")
	# The dog plays with the sewn toy through the existing action, cooldown and bond.
	stand(World.Dog.SITE)
	Almanac.companion_menu(app,"dog")
	await process_frame
	var before_bond:=int(person.companion_dog.bond)
	expect(await press_text("拿棉棉縫的布偶給小柴犬"),"Dog menu offers the sewn doll")
	expect(person.companion_dog.get("last_play")=="toy" and int(person.companion_dog.bond)==before_bond+1,"Playing raises bond once with the existing action")
	expect("布偶" in last_notice and not "布玩具" in last_notice,"Dog message names the chosen doll: "+last_notice)
	app._close_modal()
	stand(Vector2i(floori(person.x),floori(person.y)))
	await capture("03-dog-sewn-toy-%s.png"%tag)
	expect(not world.act(token,"cool","dog_toy",World.Dog.SITE).ok,"Existing cooldown still applies")
	# The cat uses the same toy.
	person.companion_dog.following=false
	person.companion_cat.following=true
	world.state.time+=40.0
	stand(World.Dog.SITE)
	Almanac.companion_menu(app,"cat")
	await process_frame
	expect(await press_text("拿棉棉縫的布偶陪牠玩"),"Cat menu offers the sewn doll")
	expect(person.companion_cat.get("last_play")=="yarn" and int(person.companion_cat.bond)==1,"Cat plays through the existing action")
	expect("布偶" in last_notice and not "毛線球" in last_notice,"Cat message names the chosen doll: "+last_notice)
	app._close_modal()
	stand(Vector2i(floori(person.x),floori(person.y)))
	await capture("04-cat-sewn-toy-%s.png"%tag)
	var ball:={"resident_goals":{"mianmian":{"3":{"state":"done","choice":"ball"}}}}
	expect(Art.choice(ball)=="ball" and Art.texture("ball").get_size()==Vector2(Art.SIZE,Art.SIZE),"Ball variant resolves with its own art")
	expect(Art.choice({"resident_goals":{"mianmian":{"3":{"state":"open","choice":""}}}}).is_empty(),"Open event has no toy")
	expect(app.session.shutdown(),"Save and close")
	var loaded:=World.new()
	expect(loaded.load_world(path),"Reload the saved island")
	if loaded.state.players.has(token):
		var view:Dictionary=Goals.view(loaded.state.players[token],loaded.state,token)
		expect(Art.choice({"resident_goals":view})=="doll","Choice survives reload")
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	app.sound.close()
	await create_timer(0.15).timeout
	print("MIANMIAN_TOY_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
