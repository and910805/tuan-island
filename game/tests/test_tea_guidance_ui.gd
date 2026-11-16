extends SceneTree
const World=preload("res://scripts/world.gd")
const Tea=World.TEA_CERAMICS
var app
var world
var actor:String
var checks:=0
var failures:=0
var output:=""
func _initialize()->void:run.call_deferred()
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(message)
func settle()->void:
	app.session._send_snapshot(1)
	app._refresh_hud()
	for i in range(5):await process_frame
	app._layout_preview()
	await process_frame
func place(region:String,cell:Vector2i)->void:
	world.state.players[actor].region=region
	world.state.players[actor].x=cell.x+0.5
	world.state.players[actor].y=cell.y+1.5
func shot(name:String)->void:
	if output.is_empty():return
	app.toast.hide()
	var arrival:=app.hud.get_node_or_null("TravelArrival") as Control
	if arrival:arrival.hide()
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(output.path_join(name+".png"))==OK,"Save "+name)
func working_frames()->void:
	if output.is_empty():return
	var old_motion:bool=app.view.reduced_motion
	for mode in ["normal","reduced"]:
		app.view.reduced_motion=mode=="reduced"
		for index in range(16):
			await create_timer(0.12).timeout
			await shot("roast-"+mode+"-%02d"%index)
	app.view.reduced_motion=old_motion
func run()->void:
	root.size=Vector2i(1024,640)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-preview="):output=arg.trim_prefix("--qa-preview=")
	if not output.is_empty():
		check(DisplayServer.get_name()!="headless","Native capture required")
		DirAccess.make_dir_recursive_absolute(output)
	app=preload("res://main.tscn").instantiate()
	app.village_art_preview=true
	root.add_child(app)
	app.set_process(false)
	var path:=OS.get_environment("TEMP").path_join("tea-guidance-ui-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	check(app.session.host(0,"茶園回訪",path)==OK,"Host starts")
	app.session.set_physics_process(false)
	world=app.session.world
	actor=app.session.peers[1]
	world.state.chapter_one.shipped=true
	world.state.chapter_one.watered=true
	world.state.board=true
	world.state.picnic=true
	place("home",Tea.RECEIVER)
	world.state.chapter_one.watered=false
	await settle()
	check(not app._tea_guidance_active() and app.objective.text.contains("灑水"),"Early picnic does not hide unfinished irrigation")
	var tracker:Button=app.hud.find_child("TrackerNext",true,false)
	tracker.pressed.emit()
	await settle()
	check(app.modal.has_meta("chapter_content"),"Early picnic tracker opens unfinished chapter")
	app._close_modal()
	world.state.chapter_one.watered=true
	await settle()
	check(app._tea_guidance_active() and app.objective.text.contains("介紹信"),"Complete chapter directs player to accept actual introduction")
	await shot("chapter-handoff")
	tracker.pressed.emit()
	await settle()
	check(app.modal.get_meta("tea_site")=="home","Handoff tracker opens Xiaoli tea order before intro")
	app._close_modal()
	app._resident_menu("xiaoli")
	await settle()
	var letter:=app.modal.find_child("ChapterNpcTeaLetter",true,false) as Button
	check(letter!=null,"Xiaoli conversation exposes actual introduction entry")
	if letter:letter.pressed.emit()
	await settle()
	check(app.modal.get_meta("tea_site")=="home","NPC introduction opens actionable tea order")
	var accept:=app.modal.find_child("TeaIntro",true,false) as Button
	check(accept!=null and not accept.disabled,"Nearby player can accept letter")
	if accept:accept.pressed.emit()
	await settle()
	check(app.session.snapshot.tea_ceramics.own_record.intro,"Accepting UI letter commits actual intro")
	app._close_modal()
	check(app._tea_guidance_active() and app.objective.text.contains("陶師"),"Introduction leads to pottery from home")
	tracker.pressed.emit()
	await settle()
	check(app.modal.has_meta("travel_body"),"Cross-region next step opens real travel UI")
	app._close_modal()
	place("yingge",Tea.POTTER)
	app.session.perform("tea_potter",Tea.POTTER)
	await settle()
	check(app.objective.text.contains("燒") and app.selected_label.text.contains("公共工坊"),"Starter clay leads to firing and contextual tools")
	place("yingge",Tea.KILN)
	app.session.perform("tea_fire",Tea.KILN)
	await settle()
	world.step(Tea.KILN_SECONDS,true)
	await settle()
	check(app.objective.text.contains("取出陶罐"),"Actual completed kiln updates HUD")
	await shot("kiln-ready-hud")
	tracker.pressed.emit()
	await settle()
	check(app.modal.get_meta("tea_site")=="kiln","Local next step opens the correct station")
	app._close_modal()
	app.session.perform("tea_fire_take",Tea.KILN)
	place("maokong",Tea.TEA_NODES[0])
	app.session.perform("tea_pick",Tea.TEA_NODES[0])
	place("maokong",Tea.ROASTER)
	app.session.perform("tea_roast",Tea.ROASTER,"light")
	await settle()
	await working_frames()
	world.step(Tea.ROAST_SECONDS.light,true)
	await settle()
	check(app.objective.text.contains("取出淺焙茶"),"Roast completion becomes next action")
	await shot("roast-ready-hud")
	app.session.perform("tea_take",Tea.ROASTER)
	place("maokong",Tea.PACKER)
	app.session.perform("tea_pack",Tea.PACKER,"light:jar")
	app.session.perform("tea_ship",Tea.PACKER)
	world.step(Tea.SHIPPING_SECONDS,true)
	place("home",Tea.RECEIVER)
	await settle()
	check(app.objective.text.contains("收款"),"Delivered parcel updates home HUD")
	check(not app.selected_label.text.contains("公共工坊") and app.selected_label.text.contains("鋤頭"),"Returning home restores the selected tool hint")
	await shot("delivered-hud")
	tracker.pressed.emit()
	await settle()
	check(app.modal.get_meta("tea_site")=="home","Next step opens Xiaoli tea order instead of generic map")
	app._close_modal()
	app.session.perform("tea_sell",Tea.RECEIVER)
	await settle()
	check(app.objective.text.contains("寄回"),"Settlement switches to manual return")
	for size in [Vector2i(1024,640),Vector2i(1280,800)]:
		root.size=size
		await settle()
		check(root.get_visible_rect().encloses(app.preview_tracker.get_global_rect()),"Tracker fits "+str(size))
		check(app.preview_tracker.get_global_rect().encloses(app.objective.get_global_rect()),"Guidance wraps inside tracker "+str(size))
	world.state.festival.active=true
	await settle()
	check(not app._tea_guidance_active() and app.objective.text.contains("風鈴"),"Home festival keeps priority")
	app.session.shutdown()
	app.queue_free()
	await process_frame
	for suffix in ["",".bak",".writer-lock"]:DirAccess.remove_absolute(path+suffix)
	print("TEA_GUIDANCE_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
