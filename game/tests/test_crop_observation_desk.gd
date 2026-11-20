extends SceneTree

const World=preload("res://scripts/world.gd")
const KIND:=World.INDUSTRY.OBSERVATION_DESK
const SITE:=Vector2i(38,34)
const ROTATED:=Vector2i(41,34)
var app
var directory:String
var checks:=0
var failures:=0

func _initialize()->void:
	run.call_deferred()

func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)

func back_button()->Button:
	for button:Button in app.modal.find_children("*","Button",true,false):
		if button.text=="返回觀察記錄桌":return button
	return null

func capture(image_name:String)->void:
	if directory.is_empty() or DisplayServer.get_name()=="headless":return
	await process_frame
	await RenderingServer.frame_post_draw
	check(root.get_texture().get_image().save_png(directory.path_join(image_name+".png"))==OK,"Captured "+image_name)

func run()->void:
	app=preload("res://main.tscn").instantiate()
	root.add_child(app)
	root.size=Vector2i(1280,800)
	directory=app.arg_value("desk-preview","")
	var path:="user://crop-desk-test-%d.json"%Time.get_ticks_usec()
	app.session.profile.token="crop-desk-qa"
	if app.session.host(0,"溫室家具測試",path)!=OK:
		quit(1)
		return
	app.session.set_physics_process(false)
	app.WanganUI.dismiss(app)
	var world:World=app.session.world
	var actor:String=app.session.peers[1]
	var person:Dictionary=world.state.players[actor]
	person.x=World.SPAWN.x
	person.y=World.SPAWN.y
	person.inventory.wood=24
	person.inventory.glass=4
	person.inventory.cotton_cloth=4
	person.bonds={"xinghe":{"points":24,"talk_day":0,"gift_day":0}}
	person[World.RESIDENT_GOALS.GROWTH_LOG_KEY]={"radish":true}
	var visitor:="crop-desk-visitor"
	world.add_player(visitor,"鄰居",Vector2(44.5,36.5))
	world.state.players[visitor].bonds=person.bonds.duplicate(true)
	world.state.players[visitor][World.RESIDENT_GOALS.GROWTH_LOG_KEY]={"lettuce":true}
	app.session._send_snapshot(1)
	app._build_menu()
	var style:Button
	for button:Button in app.modal.find_children("BuildTab*","Button",true,false):
		if button.text=="星砂溫室":style=button
	check(style!=null,"The greenhouse shelf is visible")
	if style!=null:
		style.pressed.emit()
		var slot:=app.modal.find_child("BuildSlot_"+KIND+"_"+str(style.name).trim_prefix("BuildTab"),true,false) as Button
		check(slot!=null and slot.is_visible_in_tree(),"The desk is selectable on the greenhouse shelf")
		if slot!=null:slot.pressed.emit()
	var place:=app.modal.find_child("BuildPlace",true,false) as Button
	check(place!=null and not place.disabled,"The workshop accepts the recipe")
	app._layout_preview()
	await capture("observation-desk-workshop")
	if place!=null:place.pressed.emit()
	check(app.selected=="build" and app.building==KIND,"The workshop selects the ordinary placement tool")
	app.session.perform("build",SITE,KIND)
	var far:=SITE+Vector2i.RIGHT
	check(world.blocked(SITE) and world.blocked(far) and World.station_anchor(world.state.objects,far)==SITE,"The solid desk spans two tiles with one anchor")
	check(person.inventory.wood==12 and person.inventory.glass==2 and person.inventory.cotton_cloth==2,"Standard placement costs the exact recipe")
	var design:=World.BLUEPRINT_DESIGN.capture(world.state,actor,Rect2i(SITE,Vector2i(2,1)),"觀察記錄桌",World.BUILD,World.NAMES)
	check(design.ok and design.get("blueprint",{}).get("pieces",[]).size()==1,"A blueprint records the desk as one piece")
	if design.ok:
		var quote:=world.quote_blueprint(actor,design.blueprint,ROTATED,1)
		check(quote.ok,"A rotated blueprint fits the plot")
		if quote.ok:
			var placed:=world.apply_blueprint(actor,"d".repeat(32),design.blueprint,ROTATED,1,quote.hash)
			check(placed.ok and World.INDUSTRY.is_vertical(world.state.objects.get(World.key(ROTATED),{})) and World.station_anchor(world.state.objects,ROTATED+Vector2i.DOWN)==ROTATED,"A rotated blueprint builds the vertical footprint")
	app.session._send_snapshot(1)
	app.view.zoom=2.0
	app.view.show_target=false
	app.view.camera=Vector2(39.5,34.5)*32-Vector2(root.size)/4.0
	app.view.queue_redraw()
	await capture("observation-desk-placed")
	var before:=world.state.duplicate(true)
	app.sound.reduced_motion=false
	app._interact()
	var notes:=app.modal.find_child("DeskNotes",true,false) as Control if app.modal!=null else null
	check(notes!=null and is_zero_approx(notes.modulate.a),"Interaction from the secondary tile opens the desk with a fade")
	var fade_deadline:=Time.get_ticks_msec()+1800
	while notes!=null and not is_equal_approx(notes.modulate.a,1.0) and Time.get_ticks_msec()<fade_deadline:
		await process_frame
	check(notes!=null and is_equal_approx(notes.modulate.a,1.0),"The short fade finishes at full opacity")
	await capture("observation-desk-open")
	if notes!=null:
		app.modal.find_child("DeskCropAlmanac",true,false).pressed.emit()
		var tab:=app.modal.find_child("CollectionTab1",true,false) as Button
		check(tab!=null and tab.button_pressed,"The desk opens the crop page directly")
		var back:=back_button()
		check(back!=null,"The crop almanac has a route back to the desk")
		if back!=null:
			app.sound.reduced_motion=true
			back.pressed.emit()
			var still:=app.modal.find_child("DeskNotes",true,false) as Control
			check(still!=null and is_equal_approx(still.modulate.a,1.0),"Reduced motion shows the content immediately")
			app.modal.find_child("DeskGrowthLog",true,false).pressed.emit()
			var own_rows:=0
			for pick:Button in app.modal.find_children("XingheGrowthSpecies_*","Button",true,false):
				own_rows+=1
				check(pick.text==World.CROPS.radish.name and pick.name=="XingheGrowthSpecies_radish","The displayed record belongs to the local player")
			var selected:=app.modal.find_child("XingheGrowthSelected",true,false) as Label
			check(own_rows==1 and selected!=null and selected.text==World.CROPS.radish.name and back_button()!=null,"The growth notebook has one personal record and a return route")
			await capture("observation-desk-growth-log")
	check(world.state==before,"Reading books does not change the world state")
	var loaded:=World.new()
	check(loaded.load_world(path) and not loaded.recovered_from_backup and loaded.state.objects.get(World.key(SITE),{}).get("type")==KIND,"The primary save reloads the desk")
	app.session.perform("remove",far)
	check(not world.state.objects.has(World.key(SITE)) and not world.state.objects.has(World.key(far)) and person.inventory.wood==12 and person.inventory.glass==2 and person.inventory.cotton_cloth==2,"Removing by the second tile restores the recipe exactly once")
	app.session.shutdown()
	for suffix:String in ["",".bak",".writer-lock"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("CROP_OBSERVATION_DESK_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
