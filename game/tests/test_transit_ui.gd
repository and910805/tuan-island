extends SceneTree
const World=preload("res://scripts/world.gd")
const Transit=preload("res://scripts/transit.gd")
const TravelUI=preload("res://scripts/travel_ui.gd")
var app
var checks:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(message)
func visible(control:Control)->bool:
	if not control.is_visible_in_tree() or not root.get_visible_rect().encloses(control.get_global_rect()):return false
	var parent:=control.get_parent()
	while parent:
		if parent is ScrollContainer and not parent.get_global_rect().encloses(control.get_global_rect()):return false
		parent=parent.get_parent()
	return true
func frames()->void:
	for i in range(5):await process_frame
	app._layout_preview();await process_frame
func layout()->void:
	await frames()
	check(root.get_visible_rect().encloses(app.modal.get_global_rect()),"Ticket panel fits viewport")
	for c in app.modal.find_children("*","Control",true,false):
		if c is BaseButton or c is Label:check(visible(c),"Visible ticket control "+str(c.name))
func press(id:String)->void:
	var button=app.modal.find_child(id,true,false)
	check(button!=null,"Action exists "+id)
	if button==null:return
	check(not button.disabled and visible(button),"Action accessible "+id)
	if button.disabled:return
	await create_timer(0.13).timeout
	button.pressed.emit();await frames()
func tap_joy(button:JoyButton)->void:
	for pressed in [true,false]:
		var event:=InputEventJoypadButton.new()
		event.button_index=button
		event.pressed=pressed
		root.push_input(event)
	await frames()
func position_at(region:String,station:String,side:=Vector2i.DOWN)->void:
	var person:Dictionary=app.session.world.state.players[app.session.profile.token]
	var cell:Vector2i=Transit.points(region)[station].cell+side
	person.x=cell.x+0.5;person.y=cell.y+0.5
	app.session._send_snapshot(1)
func check_arrival_motion()->void:
	var original:bool=app.sound.reduced_motion
	for reduced in [false,true]:
		app.sound.reduced_motion=reduced
		TravelUI.arrived(app,"home","toucheng")
		var ribbon:=app.hud.get_node("TravelArrival") as Control
		var art:=ribbon.find_child("ArrivalArt",true,false) as TextureRect
		check(is_equal_approx(art.position.x,16.0 if reduced else -20.0),"Arrival art starts in the correct position")
		check(is_equal_approx(ribbon.modulate.a,1.0 if reduced else 0.4),"Reduced motion shows the ribbon immediately")
		await create_timer(0.65).timeout
		check(is_equal_approx(art.position.x,16.0) and is_equal_approx(ribbon.modulate.a,1.0),"Arrival settles at full visibility")
		if reduced:
			for pressed in [true,false]:
				var event:=InputEventKey.new()
				event.keycode=KEY_ESCAPE
				event.physical_keycode=KEY_ESCAPE
				event.pressed=pressed
				root.push_input(event)
			await frames()
		else:
			await tap_joy(JOY_BUTTON_B)
		check(app.hud.get_node_or_null("TravelArrival")==null and app.modal==null,"Esc or B dismisses the arrival without opening the pause menu")
		await tap_joy(JOY_BUTTON_B)
		check(is_instance_valid(app.modal),"B opens the menu once the arrival is gone")
		app._close_modal()
	app.sound.reduced_motion=original
func run()->void:
	var path:=OS.get_environment("TEMP").path_join("transit-ui-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	app=preload("res://main.tscn").instantiate();app.village_art_preview=true;root.add_child(app)
	app.set_process(false);app.session.set_physics_process(false)
	if app.session.host(0,"北部旅人",path)!=OK:check(false,"Host starts");quit(1);return
	var world=app.session.world
	var id:String=app.session.profile.token
	for dimensions in [Vector2i(1024,640),Vector2i(1280,800),Vector2i(1920,1080)]:
		root.size=dimensions
		var person:Dictionary=world.state.players[id]
		person.region="home";person.travel_book=Transit.fresh()
		world.state.picnic=false;position_at("home","ferry")
		app._travel_menu();await frames()
		check(app.modal.find_child("TravelDepart",true,false).disabled,"Picnic remains prerequisite")
		await tap_joy(JOY_BUTTON_X)
		check(root.gui_get_focus_owner()!=app.modal.find_child("TravelDepart",true,false) and person.region=="home","X cannot focus or activate a locked departure")
		world.state.picnic=true;app.session._send_snapshot(1);await frames()
		check(not app.modal.find_child("TravelDepart",true,false).disabled,"Open ticket refreshes after unlock")
		await layout()
		check(app.modal.find_child("SelectRoute_jinguashi",true,false)==null,"New player cannot skip first route")
		await press("SelectRoute_toucheng")
		await press("TravelLocalMap")
		check(is_instance_valid(app.modal) and app.modal.get_meta("life_modal_layout","")=="island_map","Ticket action opens the island route map")
		await tap_joy(JOY_BUTTON_B)
		var returned:bool=is_instance_valid(app.modal) and app.modal.get_meta("travel_station","")=="ferry" and app.modal.get_meta("travel_selected","")=="toucheng"
		check(returned and person.region=="home","B returns to the same station and selected ticket without travelling")
		await tap_joy(JOY_BUTTON_B)
		check(app.modal==null and person.region=="home","B from the ticket closes it without travelling")
		app._travel_menu("ferry")
		await frames()
		var inventory:Dictionary=person.inventory.duplicate(true)
		var coins:=int(person.coins)
		var time:=float(world.state.time)
		await press("SelectRoute_toucheng")
		check(person.region=="home","Choosing ticket alone does not depart")
		await tap_joy(JOY_BUTTON_X)
		var depart:=app.modal.find_child("TravelDepart",true,false) as Button
		check(root.gui_get_focus_owner()==depart and visible(depart) and person.region=="home","X focuses the visible departure without travelling")
		await create_timer(0.13).timeout
		await tap_joy(JOY_BUTTON_A)
		check(person.region=="toucheng" and app.modal==null,"Departure changes actual region and closes ticket")
		var location:=app.hud.find_child("RegionTitle",true,false) as Label
		check(location.text=="宜蘭・頭城車站","Arrival snapshot updates the HUD without waiting for a frame refresh")
		check(app.hud.get_node_or_null("TravelArrival")!=null,"Confirmed arrival shows brief transport feedback")
		var ribbon:Control=app.hud.get_node("TravelArrival")
		check(ribbon.size.y<=120 and root.get_visible_rect().encloses(ribbon.get_global_rect()),"Arrival ribbon stays compact and inside viewport")
		check(not app.toast.visible and is_zero_approx(app.toast_time),"The route ribbon replaces the success toast received before the snapshot")
		app.session.receive_notice(World.REGIONS.arrival_notice("toucheng"),true)
		check(not app.toast.visible and is_zero_approx(app.toast_time),"A matching success toast received after the snapshot also stays hidden")
		app.session.receive_notice(World.REGIONS.arrival_notice(World.REGIONS.LANYANG),true)
		check(app.toast.visible and app.toast.text==World.REGIONS.arrival_notice(World.REGIONS.LANYANG),"An arrival outside the ribbon's route retains its success toast")
		app._travel_menu("rail");await frames()
		check(app.modal.find_child("TravelDepart",true,false).disabled,"Street arrival must walk to train platform")
		app.session.perform("transit",Transit.points("toucheng").rail.cell,"ruifang")
		await frames()
		check(person.region=="toucheng" and not app.toast_success and app.modal_feedback.text.contains("靠近指定出口"),"A refused departure keeps its error on the ticket")
		position_at("toucheng","rail");app._interact();await layout()
		check(app.modal.get_meta("travel_station","")=="rail","Nearest rail gate opens the correct ticket")
		await press("TravelDepart")
		check(person.region=="ruifang","Rail ticket reaches Ruifang")
		check(location.text=="新北・瑞芳轉乘廣場","Rail arrival updates the HUD")
		app._travel_menu("rail");await frames()
		check(app.modal.find_child("SelectRoute_jiufen",true,false)==null,"Ruifang rail gate does not teleport to unvisited mountain bus route")
		position_at("ruifang","bus");app._interact();await layout()
		await press("TravelDepart")
		check(person.region=="jiufen","Bus ticket reaches Jiufen")
		position_at("jiufen","shuttle");app._interact();await layout()
		check(app.modal.find_child("SelectRoute_jinguashi",true,false)!=null,"Jiufen shuttle offers first Jinguashi visit")
		await press("TravelDepart")
		check(person.region=="jinguashi","Shuttle ticket reaches working mine region")
		position_at("jinguashi","shuttle");app._interact();await layout()
		await press("SelectRoute_home")
		check(app.modal.find_children("*","Label",true,false).any(func(label):return label.text.contains("九份") and label.text.contains("瑞芳") and label.text.contains("頭城")),"Return itinerary displays intermediate stations in combined transfer")
		await press("TravelDepart")
		check(person.region=="home" and person.inventory==inventory and int(person.coins)==coins,"Free return preserves every item and coin")
		check(location.text=="風鈴渡口","Return restores the home HUD title")
		check(float(world.state.time)==time,"Travel UI never advances shared world time")
		check(person.travel_book.visited.size()==5,"Only genuinely reached stations recorded")
		position_at("home","ferry",Vector2i.UP);app._interact();await layout()
		check(app.modal.get_meta("travel_station","")=="ferry","Home station opens the ferry tickets")
		await press("SelectRoute_jinguashi")
		var selector=app.modal.find_child("SelectRoute_jinguashi",true,false)
		if selector==null:
			app._close_modal()
			continue
		selector.grab_focus()
		app.session._send_snapshot(1);await frames()
		check(root.gui_get_focus_owner()==selector,"Unchanged snapshots preserve ticket selection focus")
		await press("TravelDepart")
		check(person.region=="jinguashi","Known route supports one confirmed combined transfer")
		app._close_modal()
	await check_arrival_motion()
	app.session.shutdown();await create_timer(0.3).timeout
	app.queue_free();await process_frame;await process_frame
	for suffix in ["",".bak",".writer-lock"]:DirAccess.remove_absolute(path+suffix)
	print("TRANSIT_UI_TESTS checks=%d failures=%d"%[checks,failures]);quit(int(failures>0))
