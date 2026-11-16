extends SceneTree

const World=preload("res://scripts/world.gd")
const Tea=World.TEA_CERAMICS
const Art=preload("res://scripts/tea_ceramics_art.gd")
const Residents=preload("res://scripts/tea_resident_art.gd")
var app
var world
var actor:String
var checks:=0
var failures:=0
var preview_dir:=""

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
	person.x=cell.x+0.5
	person.y=cell.y+1.5
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
		await create_timer(0.11).timeout
		button.pressed.emit()
	await process_frame

func worksite(region:String,cell:Vector2i,id:String)->void:
	app._close_modal()
	place(region,cell)
	check(app.view.interaction_focus()==id,"World focus "+id)
	app._interact()
	await settle()
	check(app.modal and app.modal.has_meta("tea_site"),"Opens tea worksite "+id)

func advance(seconds:float)->void:
	world.state.time+=seconds
	app.session._send_snapshot(1)

func record()->Dictionary:
	return Tea.own_record(world.state,actor)

func capture(name:String)->void:
	if preview_dir.is_empty():return
	var arrival:=app.hud.get_node_or_null("TravelArrival") as Control
	if arrival:arrival.hide()
	app._refresh_hud()
	for size in [Vector2i(1024,640),Vector2i(1280,800)]:
		root.size=size
		await settle()
		app.toast.hide()
		app.view.queue_redraw()
		await RenderingServer.frame_post_draw
		var path:=preview_dir.path_join("%s-%dx%d.png"%[name,size.x,size.y])
		check(root.get_texture().get_image().save_png(path)==OK,"Saved "+path)
	root.size=Vector2i(1024,640)

func run()->void:
	root.size=Vector2i(1024,640)
	var host_portrait:=Residents.portrait("host")
	var potter_portrait:=Residents.portrait("potter")
	check(host_portrait!=null and potter_portrait!=null,"Both resident portraits load from project resources")
	check(host_portrait.get_size()==Vector2(64,64) and potter_portrait.get_size()==Vector2(64,64),"Portrait cells have consistent 64px dimensions")
	check(host_portrait.get_image().get_data()!=potter_portrait.get_image().get_data(),"Tea host and potter have different original portraits")
	check(Residents.portrait("unknown")==null,"Unknown resident cannot borrow another identity")
	var path:=OS.get_environment("TEMP").path_join("tea-ui-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	app=preload("res://main.tscn").instantiate()
	app.village_art_preview=true
	root.add_child(app)
	preview_dir=app.arg_value("qa-preview","")
	if not preview_dir.is_empty():
		check(DisplayServer.get_name()!="headless" and DirAccess.make_dir_recursive_absolute(preview_dir)==OK,"Native tea preview directory ready")
	app.set_process(false)
	app.session.set_physics_process(false)
	if app.session.host(0,"茶陶旅人",path)!=OK:
		check(false,"Host starts")
		quit(1)
		return
	world=app.session.world
	actor=app.session.peers[1]
	place("home",Tea.RECEIVER)
	app._shop()
	await settle()
	check(control("XiaoliTeaOrder")==null,"Tea order hidden until first chapter completed")
	world.state.picnic=true
	world.state.board=true
	world.state.chapter_one.shipped=true
	world.state.chapter_one.watered=true
	app.session._send_snapshot(1)
	app._chapter_menu()
	await press("ChapterTeaLetter")
	await press("TeaHome")
	await press("TeaIntro")
	check(record().intro,"Introduction letter committed")
	app._shop()
	await press("XiaoliTeaOrder")
	check(app.modal.get_meta("tea_site")=="home","Original stall links to tea order")
	app._close_modal()
	place("yingge",Tea.POTTER)
	await capture("potter-world")
	await worksite("yingge",Tea.POTTER,"tea:potter")
	await capture("potter-intro")
	control("TeaPotter").grab_focus()
	await key_event(KEY_ENTER)
	check(record().potter,"Keyboard Enter accepts the potter introduction")
	await press("TeaPotterStory")
	check(record().potter_story,"Potter advice is saved")
	await inspect_worksite("potter-advice")
	app._close_modal()
	place("yingge",Tea.KILN)
	await capture("yingge")
	await worksite("yingge",Tea.KILN,"tea:kiln")
	await inspect_worksite("kiln-idle")
	await press("TeaFire")
	await inspect_worksite("kiln-firing")
	control("TeaJournal").grab_focus()
	advance(1.0)
	await settle()
	check(root.gui_get_focus_owner()==control("TeaJournal"),"Countdown rebuild preserves focused journal action")
	check((control("TeaFireTake") as Button).disabled,"Cannot collect from active kiln")
	advance(Tea.KILN_SECONDS)
	await inspect_worksite("kiln-ready")
	await press("TeaFireTake")
	app._close_modal()
	place("maokong",Tea.ROASTER)
	await capture("maokong")
	await worksite("maokong",Tea.TEA_NODES[0],"tea:pick:"+World.key(Tea.TEA_NODES[0]))
	await press("TeaPick")
	check((control("TeaPick") as Button).disabled,"Picked bush shows cooldown")
	await worksite("maokong",Tea.ROASTER,"tea:roast")
	await capture("roast-options")
	await press("TeaLight")
	await capture("roast")
	check((control("TeaTake") as Button).disabled,"Cannot collect tea early")
	advance(Tea.ROAST_SECONDS.light)
	await press("TeaTake")
	await worksite("maokong",Tea.PACKER,"tea:pack")
	await capture("pack")
	await press("TeaPackJar")
	check(record().packed.is_empty(),"Choosing packaging does not spend materials")
	await press("TeaPackConfirm")
	await press("TeaShip")
	check(record().outbound.wrap=="jar","Actual parcel uses ceramic jar")
	place("home",Tea.RECEIVER)
	app._shop()
	await press("XiaoliTeaOrder")
	check(control("TeaSell")==null,"Transit blocks early sale")
	advance(Tea.SHIPPING_SECONDS)
	await capture("sell")
	await press("TeaSell")
	check(record().empties==1 and control("TeaAuto")==null,"First delivery requires manual return")
	await press("TeaReturn")
	await worksite("maokong",Tea.PACKER,"tea:pack")
	check((control("TeaReclaim") as Button).disabled,"Return waits for arrival")
	advance(Tea.RETURN_SECONDS)
	await capture("reclaim")
	world.state.players[actor].inventory.tea_light=1
	world.state.players[actor].inventory.tea_deep=1
	app.session._send_snapshot(1)
	await capture("pack-crowded")
	await settle()
	for button in app.modal.find_children("*","Button",true,false):
		check(visible(button),"Crowded pack keeps visible "+button.name)
	await press("TeaReclaim")
	check(record().reused,"Reclaim unlocks automation")
	app._close_modal()
	place("maokong",Tea.TEA_NPC)
	await capture("chacha-world")
	if not preview_dir.is_empty():
		var has_resident_name:=false
		var has_local_name:=false
		for entry in app.view.world_labels:
			if entry.id=="tea:host":has_resident_name=true
			if entry.title==world.state.players[actor].name:has_local_name=true
		check(has_resident_name and not has_local_name,"Near tea host, keep NPC hint without player-name occlusion")
	await worksite("maokong",Tea.TEA_NPC,"tea:host")
	await press("TeaDiscuss")
	check(record().tea_discussed and not record().comparison_complete,"Initial discussion does not complete comparison")
	var current:Dictionary=world.state.tea_ceramics.players[actor]
	var inventory:Dictionary=world.state.players[actor].inventory
	current.returning={"count":300000000,"ready":world.state.time,"items":{"tea_returned_jar":100000000,"tea_worn_jar":100000000,"tea_spent_jar":100000000}}
	inventory.tea_worn_jar=1
	await worksite("maokong",Tea.PACKER,"tea:pack")
	check("送後 0 次" in (control("TeaPackJar") as Button).accessibility_name,"Worn jar is chosen first and can safely make its last delivery")
	check(control("TeaJarCounts").get_child_count()==6,"Three returned conditions are distinguishable")
	await capture("pack-mixed-return-max")
	for size in [Vector2i(1024,640),Vector2i(1280,800)]:
		root.size=size
		await settle()
		for button in app.modal.find_children("*","Button",true,false):
			check(visible(button),"Mixed return %s keeps visible %s"%[size,button.name])
	root.size=Vector2i(1024,640)
	current.returning={}
	inventory.tea_jar=0
	inventory.tea_returned_jar=0
	inventory.tea_worn_jar=0
	inventory.tea_spent_jar=1
	inventory.clay=1
	app.session._send_snapshot(1)
	check((control("TeaPackJar") as Button).disabled,"Spent jar cannot be packed")
	await press("TeaPackFiber")
	await press("TeaPackConfirm")
	await press("TeaShip")
	place("home",Tea.RECEIVER)
	app._shop()
	await press("XiaoliTeaOrder")
	advance(Tea.SHIPPING_SECONDS)
	await press("TeaSell")
	check(record().trials=={"jar":true,"fiber":true},"Two real deliveries complete both trials")
	await worksite("maokong",Tea.TEA_NPC,"tea:host")
	await press("TeaDiscuss")
	check(record().comparison_complete,"Discussing both deliveries completes comparison")
	await inspect_worksite("host-comparison")
	control("TeaJournal").grab_focus()
	await key_event(KEY_TAB)
	var tab_focus:=root.gui_get_focus_owner()
	check(tab_focus is BaseButton and visible(tab_focus) and not tab_focus.disabled,"Tab stays on a visible enabled modal control")
	await key_event(KEY_ESCAPE)
	check(not is_instance_valid(app.modal),"Escape dismisses tea dialogue")
	await worksite("maokong",Tea.TEA_NPC,"tea:host")
	for size in [Vector2i(1024,640),Vector2i(1280,800)]:
		root.size=size
		await settle()
		for wrap in ["jar","fiber"]:
			var status:=control("TeaTrial_"+wrap) as Label
			check(visible(status) and status.get_line_count()==1 and status.size.x>=status.get_minimum_size().x,"Comparison status stays readable on one line at "+str(size))
	await worksite("yingge",Tea.KILN,"tea:kiln")
	await settle()
	check((control("TeaFire") as Button).disabled and "還缺 1" in (control("TeaFireReason") as Label).text,"One clay explains why new firing is unavailable")
	check(not (control("TeaRepair") as Button).disabled,"One clay and spent jar permit repair")
	world.state.players[actor].inventory.clay=0
	app.session._send_snapshot(1)
	await settle()
	check((control("TeaRepair") as Button).disabled and "還缺 1" in (control("TeaRepairReason") as Label).text and visible(control("TeaRepairReason")),"Missing clay has a visible repair reason")
	world.state.players[actor].inventory.clay=1
	app.session._send_snapshot(1)
	await inspect_worksite("kiln-repair-ready")
	await press("TeaRepair")
	await inspect_worksite("kiln-repair-working")
	check(record().kiln.repair and (control("TeaFireTake") as Button).disabled,"Repair waits for kiln")
	advance(Tea.KILN_SECONDS)
	await press("TeaFireTake")
	check(int(world.state.players[actor].inventory.tea_jar)==1,"Repair restores fresh three-use jar")
	place("home",Tea.RECEIVER)
	app._shop()
	await press("XiaoliTeaOrder")
	await press("TeaAuto")
	check(record().auto,"Automatic return enabled")
	await press("TeaAuto")
	check(not record().auto,"Automatic return disabled")
	for size in [Vector2i(1024,640),Vector2i(1280,800)]:
		root.size=size
		await settle()
		check(root.get_visible_rect().encloses(app.modal.get_global_rect()),"Tea panel fits %s"%size)
		for button in app.modal.find_children("*","Button",true,false):
			check(visible(button),"Tea controls fit %s: %s"%[size,button.name])
	await press("TeaJournal")
	check(app.modal.get_meta("tea_site")=="journal","Journal remains available after first loop")
	for item in Art.ICONS:check(Art.icon(item)!=null,"Official atlas contains "+item)
	app._close_modal()
	app.session.shutdown()
	await create_timer(0.3).timeout
	app.queue_free()
	await process_frame
	for suffix in ["",".bak",".writer-lock"]:DirAccess.remove_absolute(path+suffix)
	print("TEA_CERAMICS_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func inspect_worksite(name:String)->void:
	for size in [Vector2i(1024,640),Vector2i(1280,800)]:
		root.size=size
		await settle()
		check(root.get_visible_rect().encloses(app.modal.get_global_rect()),name+" modal stays within "+str(size))
		if app.modal.get_meta("tea_site") in ["host","potter"]:
			var portrait:=control("TeaResidentPortrait") as TextureRect
			check(portrait!=null and portrait.texture==Residents.portrait(app.modal.get_meta("tea_site")),"Dialogue shows the matching resident")
			check(visible(portrait) and portrait.size==Vector2(128,128) and portrait.texture_filter==CanvasItem.TEXTURE_FILTER_NEAREST,"Portrait stays visible at exact nearest 2x scale")
		var scroll:=control("ModalScroll") as ScrollContainer
		var bar:=scroll.get_v_scroll_bar()
		check(bar.max_value<=bar.page+1.0,name+" fits without scrolling at "+str(size))
		for child in app.modal.find_children("*","Button",true,false):
			check(visible(child),name+" action visible: "+str(child.name))
	await capture(name)
	root.size=Vector2i(1024,640)

func key_event(code:Key)->void:
	var event:=InputEventKey.new()
	event.keycode=code
	event.physical_keycode=code
	event.pressed=true
	root.push_input(event)
	await process_frame
	event=event.duplicate()
	event.pressed=false
	root.push_input(event)
	await settle()
