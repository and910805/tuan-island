extends SceneTree

const Main=preload("res://main.tscn")
const World=preload("res://scripts/world.gd")
const Sign=World.WELCOME_SIGN
const Tasks=preload("res://scripts/life_ui_tasks.gd")
var checks:=0
var failures:=0

func _initialize() -> void:
	run.call_deferred()

func expect(condition:bool,message:String) -> void:
	checks+=1
	if condition:return
	failures+=1
	push_error(message)

func run() -> void:
	var app=Main.instantiate()
	root.add_child(app)
	root.size=Vector2i(1024,640)
	await process_frame
	var path:="user://inn-welcome-%d.json"%OS.get_process_id()
	if app.session.host(0,"暖泉旅舍島民",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	var world:World=app.session.world
	var token:String=app.session.profile.token
	var person:Dictionary=world.state.players[token]
	var at:=Vector2i(41,36)
	var key:=World.key(at)
	person.x=41.5
	person.y=37.5
	person.inventory.hardwood=8
	person.inventory.clay=2
	app.session._send_snapshot(1)
	app._build_menu()
	await process_frame
	var tab:=app.modal.find_child("BuildTab2",true,false) as Button
	if tab:tab.pressed.emit()
	var slot:=app.modal.find_child("BuildSlot_inn_welcome_sign_2",true,false) as Button
	expect(slot!=null and slot.is_visible_in_tree(),"The welcome sign is in the furniture list")
	app._close_modal()
	expect(not world.act(token,"early-sign","build",at,Sign.KIND).ok
		and world.state.players[token].inventory.hardwood==8,"Before the story the server refuses placement without charging materials")
	person=world.state.players[token]
	var resident:=World.RESIDENT_BOND.SPRING_CELL
	person.region=World.RESIDENT_BOND.SPRING_REGION
	person.x=resident.x+0.5
	person.y=resident.y+1.5
	person.bonds={"nuannuan":{"points":1,"talk_day":-1,"gift_day":-1}}
	person.inventory.stone=8
	person.inventory.wood=8
	expect(not world.act(token,"skip-cleanup",World.RESIDENT_GOALS.ACTION,resident,"nuannuan:1::").ok,
		"The story refuses materials before cleanup")
	app.session._send_snapshot(1)
	Tasks.bond_goal(app,"nuannuan",1)
	await process_frame
	var cleanup:=app.modal.find_child("NuannuanClearEntrance",true,false) as Button
	expect(cleanup!=null and not cleanup.disabled,"The entrance can be cleaned through the native story panel")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir=") and DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			expect(root.get_texture().get_image().save_png(arg.trim_prefix("--capture-dir=").path_join("inn-entrance-cleanup.png"))==OK,"Capture the entrance cleanup panel")
	if cleanup:cleanup.pressed.emit()
	await process_frame
	person=world.state.players[token]
	expect(person.get(World.RESIDENT_GOALS.INN_CLEAR_KEY,false) and person.inventory.stone==8 and person.inventory.wood==8,
		"Cleanup is recorded independently without charging materials")
	expect(cleanup!=null and cleanup.disabled,"The story panel marks cleanup complete")
	var reward:=world.act(token,"earn-sign",World.RESIDENT_GOALS.ACTION,resident,"nuannuan:1::")
	expect(reward.ok and "旅舍迎賓牌圖樣" in reward.message,"Reporting the first story earns the blueprint")
	person=world.state.players[token]
	expect(person.inventory.stone==0 and person.inventory.wood==0,"Reporting the story spends the planned materials")
	person.region=World.REGIONS.HOME
	person.x=41.5
	person.y=37.5
	app.session._send_snapshot(1)
	Tasks.bond_goal(app,"nuannuan",1)
	await process_frame
	var pattern:=app.modal.find_child("NuannuanWelcomeSignPattern",true,false) as Button
	expect(pattern!=null,"The completed story offers a link to the blueprint")
	if pattern:pattern.pressed.emit()
	await process_frame
	app._close_modal()
	app.session.perform("build",at,Sign.KIND)
	expect(world.state.objects.get(key,{}).get("type")==Sign.KIND and person.inventory.hardwood==0
		and person.inventory.clay==0 and not world.blocked(at),"The exact recipe places one walkable sign")
	app._interact()
	var copy:=["蒸氣小旅舍","走累了就在這裡歇一下。","歡迎一起喝熱茶！"]
	for i in copy.size():
		var field:=app.modal.find_child("WelcomeSignField%d"%i,true,false) as LineEdit
		expect(field!=null and field.max_length==Sign.LIMITS[i],"The owner can edit each bounded line")
		if field:field.text=copy[i]
	var save:=app.modal.find_child("WelcomeSignSave",true,false) as Button
	if save:save.pressed.emit()
	expect(world.state.objects.get(key,{}).get("welcome")==copy,"The owner saves all three fields through the real action")
	world.add_player("visitor","訪客")
	var visitor:Dictionary=world.state.players.visitor
	visitor.x=person.x
	visitor.y=person.y
	expect(not world.act("visitor","overwrite",Sign.WRITE,at,JSON.stringify(["改名","",""])).ok,"A nearby visitor cannot edit")
	for data in [["太".repeat(13),"",""],["","跨\n行",""],["","長".repeat(25),""],["缺欄位"]]:
		expect(not world.act(token,"invalid-%d"%checks,Sign.WRITE,at,JSON.stringify(data)).ok,"Invalid text or shape is refused")
	expect(world.state.objects[key].welcome==copy,"Invalid requests leave the original message intact")
	var original_id:String=app.session.own_id
	app.session.own_id="visitor"
	Tasks.welcome_sign(app,at,app.session.snapshot.objects[key])
	var name_label:=app.modal.find_child("WelcomeInnName",true,false) as Label
	var guest_line:=app.modal.find_child("WelcomeInnLine2",true,false) as Label
	expect(name_label!=null and name_label.text==copy[0] and guest_line!=null and guest_line.text==copy[2]
		and app.modal.find_child("WelcomeSignSave",true,false)==null,"Visitors can read the saved sign without editor controls")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-dir=") and DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			expect(root.get_texture().get_image().save_png(arg.trim_prefix("--capture-dir=").path_join("inn-welcome-sign.png"))==OK,"Capture the visitor view")
	app.session.own_id=original_id
	var loaded:=World.new()
	expect(loaded.load_world(path) and not loaded.recovered_from_backup and loaded.state.objects.get(key,{}).get("welcome")==copy,
		"The sign reloads from the primary world save")
	expect(loaded.state.players.get(token,{}).get(World.RESIDENT_GOALS.INN_CLEAR_KEY,false),"Entrance cleanup survives reloading")
	expect(world.act(token,"remove","remove",at).ok and person.inventory.hardwood==8 and person.inventory.clay==2,"Removing the sign refunds the recipe")
	app.session.shutdown()
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("INN_WELCOME_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
