extends SceneTree
const World=preload("res://scripts/world.gd")
const Travel=preload("res://scripts/travel_ui.gd")
var checks:=0
var failures:=0
func _initialize()->void:run.call_deferred()
func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;push_error(message)
func visible(control:Control)->bool:
	var parent:=control.get_parent()
	while parent!=null:
		if parent is ScrollContainer and not parent.get_global_rect().encloses(control.get_global_rect()):return false
		parent=parent.get_parent()
	return control.is_visible_in_tree()
func run()->void:
	var app=preload("res://main.tscn").instantiate()
	app.village_art_preview=true
	root.add_child(app)
	app.set_process(false)
	app.session.set_physics_process(false)
	app.menu.hide();app.hud.show()
	var world:=World.new()
	world.add_player("tester","島民")
	app.session.own_id="tester"
	app.session.snapshot=world.region_snapshot("home")
	app._travel_menu()
	check(app.modal.find_child("TravelDepart",true,false).disabled,"Travel locked before picnic")
	world.state.picnic=true
	world.state.board=true
	app.session.snapshot=world.region_snapshot("home")
	app._travel_menu()
	check(app.modal.find_child("TravelDepart",true,false).disabled,"Remote map does not teleport")
	world.state.players.tester.x=46.5;world.state.players.tester.y=30.5
	for region in ["home","lanyang"]:
		world.state.players.tester.region=region
		world.state.players.tester.x=46.5 if region=="home" else 12.5
		world.state.players.tester.y=30.5 if region=="home" else 20.5
		app.session.snapshot=world.region_snapshot(region)
		app.view.update_snapshot(app.session.snapshot,"tester")
		for extent in [Vector2i(1024,640),Vector2i(1280,800),Vector2i(1920,1080)]:
			root.size=extent
			app._travel_menu()
			for i in range(5):await process_frame
			app._layout_preview()
			await process_frame
			var depart:Button=app.modal.find_child("TravelDepart",true,false)
			check(Rect2(Vector2.ZERO,Vector2(extent)).encloses(app.modal.get_global_rect()),"Travel fits "+str(extent))
			check(visible(depart) and not depart.disabled,"Departure visible and available "+region)
			if region=="home":
				var toucheng:=app.modal.find_child("SelectRoute_toucheng",true,false) as Button
				toucheng.pressed.emit()
			var selected:String=app.modal.get_meta("travel_selected")
			var station:String=app.modal.get_meta("travel_station")
			var local:=app.modal.find_child("TravelLocalMap",true,false) as Button
			local.pressed.emit()
			for i in range(3):await process_frame
			check(is_instance_valid(app.map_view) and app.map_view.data.region_id==region,"Local map uses current region")
			var back:=app.modal.find_child("LocalMapTravel",true,false) as Button
			check(back.text=="返回旅途車票","The local map opened from a ticket offers a return")
			back.pressed.emit()
			check(app.modal.get_meta("travel_selected")==selected and app.modal.get_meta("travel_station")==station,
				"Returning keeps the original destination and station")
	check(Travel.note("bamboo_grove","maokong").contains("茶園步道") and Travel.note("star_garden","tianwei").contains("庭園步道口"),"Return tickets describe the walking route from the actual reserve")
	check(Travel.note("jiaoxi","toucheng").contains("回程站牌"),"Warm springs return starts at the local stop")
	app._close_modal()
	app.queue_free()
	await process_frame
	print("TRAVEL_UI_TEST checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
