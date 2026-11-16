extends SceneTree
const World=preload("res://scripts/world.gd")
var checks:=0
var failures:=0

func _initialize()->void:
	run.call_deferred()

func expect(ok:bool,message:String)->void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)

func unavailable(control:Control)->bool:
	return not is_instance_valid(control) or control.disabled

func visible(control:Control)->bool:
	if not is_instance_valid(control) or not control.is_visible_in_tree():return false
	var parent:=control.get_parent()
	while parent!=null:
		if parent is ScrollContainer and not parent.get_global_rect().encloses(control.get_global_rect()):return false
		parent=parent.get_parent()
	return root.get_visible_rect().encloses(control.get_global_rect())

func place(app, point:Vector2)->void:
	var person:Dictionary=app.session.world.state.players[app.session.profile.token]
	person.x=point.x
	person.y=point.y
	app.session._send_snapshot(1)

func open_travel(app)->void:
	app._travel_menu()
	for i in range(5):await process_frame
	app._layout_preview()
	await process_frame

func run()->void:
	var path:=OS.get_environment("TEMP").path_join("mine-interaction-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	var app=preload("res://main.tscn").instantiate()
	app.village_art_preview=true
	root.add_child(app)
	app.set_process(false)
	app.session.set_physics_process(false)
	var status:int=app.session.host(0,"島民",path)
	expect(status==OK,"Actual isolated local host starts")
	if status!=OK:
		quit(1)
		return
	var fixture_resident: Dictionary=app.session.world.state.players[app.session.profile.token]
	# This local fixture isolates mountain interaction after a known route.
	fixture_resident.travel_book.visited.jinguashi=true
	for extent in [Vector2i(1024,640),Vector2i(1280,800),Vector2i(1920,1080)]:
		root.size=extent
		app.session.world.state.picnic=false
		place(app,Vector2(46.5,30.5))
		await open_travel(app)
		var mine:Button=app.modal.find_child("SelectRoute_jinguashi",true,false)
		expect(unavailable(app.modal.find_child("TravelDepart",true,false)),"Mine route locked before picnic "+str(extent))
		app.session.world.state.picnic=true
		app.session.world.state.board=true
		place(app,Vector2(39.5,33.5))
		await open_travel(app)
		mine=app.modal.find_child("SelectRoute_jinguashi",true,false)
		expect(unavailable(app.modal.find_child("TravelDepart",true,false)),"Mine route cannot teleport from far away "+str(extent))
		place(app,Vector2(46.5,30.5))
		await open_travel(app)
		mine=app.modal.find_child("SelectRoute_jinguashi",true,false)
		expect(visible(mine) and not mine.disabled and root.get_visible_rect().encloses(app.modal.get_global_rect()),"Mine route usable and fits "+str(extent))
		if not is_instance_valid(mine):break
		mine.pressed.emit()
		var outbound: Button=app.modal.find_child("TravelDepart",true,false)
		expect(visible(outbound) and not outbound.disabled,"Selected mine route has enabled confirmation")
		outbound.pressed.emit()
		expect(app.session.snapshot.region_id=="jinguashi","Travel button executes real route")
		place(app,Vector2(27.5,20.5))
		app._close_modal()
		var token:String=app.session.profile.token
		var bag:Dictionary=app.session.world.state.players[token].inventory
		bag.reinforced_pick=1
		app.session.world.state.jinguashi.ready.clear()
		var before:int=bag.get("copper_ore",0)
		app.session._send_snapshot(1)
		expect(app.view.interaction_focus()=="mine:28,20","Mine node is the E interaction target")
		app._interact()
		expect(int(bag.get("copper_ore",0))==before+World.JINGUASHI.YIELD,"E interaction commits ore via actual Session")
		place(app,Vector2(12.5,20.5))
		await open_travel(app)
		var home:Button=app.modal.find_child("SelectRoute_home",true,false)
		expect(visible(home) and not home.disabled,"Home route can be selected")
		if not is_instance_valid(home):break
		home.pressed.emit()
		var depart:Button=app.modal.find_child("TravelDepart",true,false)
		expect(visible(depart) and not depart.disabled and root.get_visible_rect().encloses(app.modal.get_global_rect()),"Return route visible and usable "+str(extent))
		depart.pressed.emit()
		expect(app.session.snapshot.region_id=="home","Return button executes real route")
	app._close_modal()
	expect(app.session.shutdown(),"Save and shut down isolated local host")
	await create_timer(0.25).timeout
	app.queue_free()
	await process_frame
	await process_frame
	for suffix in ["",".bak",".writer-lock"]:DirAccess.remove_absolute(path+suffix)
	print("JINGUASHI_INTERACTION_TEST checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
