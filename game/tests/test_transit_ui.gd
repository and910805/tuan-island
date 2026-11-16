extends SceneTree
const World=preload("res://scripts/world.gd")
const Transit=preload("res://scripts/transit.gd")
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
func position_at(region:String,station:String)->void:
	var person:Dictionary=app.session.world.state.players[app.session.profile.token]
	var cell:Vector2i=Transit.points(region)[station].cell
	person.x=cell.x+0.5;person.y=cell.y+1.5
	app.session._send_snapshot(1)
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
		world.state.picnic=true;app.session._send_snapshot(1);await frames()
		check(not app.modal.find_child("TravelDepart",true,false).disabled,"Open ticket refreshes after unlock")
		await layout()
		check(app.modal.find_child("SelectRoute_jinguashi",true,false)==null,"New player cannot skip first route")
		var inventory:Dictionary=person.inventory.duplicate(true)
		var coins:=int(person.coins)
		var time:=float(world.state.time)
		await press("SelectRoute_toucheng")
		check(person.region=="home","Choosing ticket alone does not depart")
		await press("TravelDepart")
		check(person.region=="toucheng" and app.modal==null,"Departure changes actual region and closes ticket")
		check(app.hud.get_node_or_null("TravelArrival")!=null,"Confirmed arrival shows brief transport feedback")
		var ribbon:Control=app.hud.get_node("TravelArrival")
		check(ribbon.size.y<=120 and root.get_visible_rect().encloses(ribbon.get_global_rect()),"Arrival ribbon stays compact and inside viewport")
		app._travel_menu("rail");await frames()
		check(app.modal.find_child("TravelDepart",true,false).disabled,"Street arrival must walk to train platform")
		position_at("toucheng","rail");app._interact();await layout()
		check(app.modal.get_meta("travel_station","")=="rail","Nearest rail gate opens the correct ticket")
		await press("TravelDepart")
		check(person.region=="ruifang","Rail ticket reaches Ruifang")
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
		check(float(world.state.time)==time,"Travel UI never advances shared world time")
		check(person.travel_book.visited.size()==5,"Only genuinely reached stations recorded")
		position_at("home","ferry");app._interact();await layout()
		await press("SelectRoute_jinguashi")
		var selector=app.modal.find_child("SelectRoute_jinguashi",true,false);selector.grab_focus()
		app.session._send_snapshot(1);await frames()
		check(root.gui_get_focus_owner()==selector,"Unchanged snapshots preserve ticket selection focus")
		await press("TravelDepart")
		check(person.region=="jinguashi","Known route supports one confirmed combined transfer")
		app._close_modal()
	app.session.shutdown();await create_timer(0.3).timeout
	app.queue_free();await process_frame;await process_frame
	for suffix in ["",".bak",".writer-lock"]:DirAccess.remove_absolute(path+suffix)
	print("TRANSIT_UI_TESTS checks=%d failures=%d"%[checks,failures]);quit(int(failures>0))
