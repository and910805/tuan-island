extends SceneTree
const Layouts=preload("res://scripts/workshop_layouts.gd")
const World=preload("res://scripts/world.gd")
const Design=preload("res://scripts/blueprint_design.gd")
var app
var checks:=0
var failures:=0
var complete:=false
var path:=""
var directory:=""
func _initialize()->void:run.call_deferred()
func expect(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func control(id:String)->Control:return app.modal.find_child(id,true,false) as Control
func press(id:String)->void:
	var button:=control(id) as Button
	expect(button!=null and not button.disabled,"Button available: "+id)
	if button!=null and not button.disabled:button.pressed.emit()
func settle()->void:
	for frame in 5:await process_frame
	app._layout_preview()
	await process_frame
func pad(key:JoyButton)->void:
	for down in [true,false]:
		var event:=InputEventJoypadButton.new()
		event.button_index=key
		event.pressed=down
		root.push_input(event)
	await settle()
func shot(name:String)->void:
	if DisplayServer.get_name()=="headless" or directory.is_empty():return
	await RenderingServer.frame_post_draw
	expect(root.get_texture().get_image().save_png(directory.path_join(name+".png"))==OK,"Capture "+name)
func proof()->void:
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--qa-proof-save="):continue
		var loaded:=World.new()
		expect(loaded.load_world(arg.trim_prefix("--qa-proof-save=")),"Load real earned fuel-loop evidence")
		for piece:Dictionary in Layouts.lesson(2).design.pieces:
			var cell:=Vector2i(33+int(piece.x),32+int(piece.y))
			var obj:Dictionary=loaded.state.objects.get(World.key(cell),{})
			expect(obj.get("type","")==piece.kind,"Guide piece matches earned actual layout: "+World.key(cell))
			if piece.kind=="conveyor":expect(int(obj.get("dir",-1))==piece.settings.dir and obj.get("filter","")==piece.settings.filter,"Guide belt directions/filters match actual earned loop")
func run()->void:
	create_timer(90.0).timeout.connect(func():
		if not complete:push_error("Guide test watchdog");quit(1))
	var expected:=[{"pump_kit":1,"pipe_kit":1,"tank_kit":1,"sprinkler_kit":1},{"forester_kit":1,"conveyor_kit":1,"sawmill_kit":1},{"forester_kit":1,"conveyor_kit":8,"kiln_kit":1,"sawmill_kit":1,"wood":20}]
	for index in 3:
		var lesson:=Layouts.lesson(index)
		expect(Design.validate(lesson.design,World.BUILD,World.NAMES).ok,"Guide uses valid existing blueprint schema")
		expect(Layouts.cost(index)==expected[index],"Actual canonical build costs for topic %d"%index)
		for marker:Dictionary in lesson.markers:
			expect(not lesson.design.pieces.any(func(piece):return int(piece.x)==int(marker.x) and int(piece.y)==int(marker.y)),"Reserved planting marker is not occupied by a machine")
	expect(Layouts.lesson(-1).is_empty() and Layouts.cost(9).is_empty(),"Unknown lesson is not a valid construction plan")
	proof()
	app=preload("res://main.tscn").instantiate()
	app.village_art_preview=true
	root.add_child(app)
	app.set_process(false)
	app.session.set_physics_process(false)
	root.content_scale_mode=Window.CONTENT_SCALE_MODE_DISABLED
	path=OS.get_environment("TEMP").path_join("workshop-guide-%s.json"%Crypto.new().generate_random_bytes(10).hex_encode())
	expect(app.session.host(0,"圖解試讀",path)==OK,"Open isolated normal new player")
	await settle()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-dir="):directory=arg.trim_prefix("--qa-dir=");DirAccess.make_dir_recursive_absolute(directory)
	var world_before:Dictionary=app.session.world.state.duplicate(true)
	var counter:int=app.session.counter
	var connections:int=app.session.changed.get_connections().size()
	for extent in [Vector2i(1024,640),Vector2i(1280,800)]:
		root.size=extent
		for topic in 3:
			app._workshop_guide(topic)
			await settle()
			expect(app.session.changed.get_connections().size()==connections+1,"Exactly one live guide listener after replacing panels")
			var scroll:=control("ModalScroll") as ScrollContainer
			expect(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(app.modal.get_global_rect()),"Guide fits viewport")
			for step in 5:
				press("WorkshopStep_%d"%step)
				await settle()
				var text:=control("WorkshopStepText") as Label
				expect(text.text==(Layouts.lesson(topic).steps[step] if step<4 else Layouts.lesson(topic).note),"Step/notes page shows complete actual instruction")
				for id in ["WorkshopDiagram","WorkshopMaterials","WorkshopStartup","WorkshopBuild","WorkshopBack","WorkshopStepText"]:
					expect(scroll.get_global_rect().encloses(control(id).get_global_rect()),"Guide control visible without scrolling: "+id)
			for item in Layouts.cost(topic):
				var label:=control("WorkshopCost_"+str(item)) as Label
				expect(label.get_line_count()==1,"Material number remains on one line")
			press("WorkshopStep_0")
			await settle()
			await shot("%d_lesson_%d"%[extent.x,topic])
			# The ordinary builder remains the only construction path.
			var kind:String=["water_pump","forester","conveyor"][topic]
			press("WorkshopPiece_"+kind)
			press("WorkshopBuild")
			await settle()
			expect(control("BuildTitle").text==World.BUILD[kind].name,"Guide opens original builder with selected item")
			press("BuildWorkshopGuide")
			await settle()
			expect(int(app.get_meta("workshop_guide_topic",-1))==topic,"Builder returns to matching guide topic")
			if topic==0:
				# UI-only fixture for the existing alternative recipe. No world writes.
				var current:Dictionary=app.session.snapshot
				var legacy:Dictionary=current.duplicate(true)
				legacy.players[app.session.own_id].inventory={"sprinkler_kit":1}
				app.session.snapshot=legacy
				app.life_panels.build_menu(app,"sprinkler")
				await settle()
				expect(control("BuildDescription").text.contains("每 %d 秒"%World.SPRINKLER_INTERVAL) and not control("BuildDescription").text.contains("每天"),"Builder describes actual legacy-kit cadence consistently with guide")
				app.session.snapshot=current
	app._workshop_guide(2)
	await settle()
	# Model a new incoming snapshot while open; this changes no server inventory.
	var incoming:Dictionary=app.session.snapshot.duplicate(true)
	incoming.players[app.session.own_id].inventory.wood=99
	app.session.changed.emit(incoming,app.session.own_id)
	expect(control("WorkshopCost_wood").text=="99／20","Open guide refreshes when a new inventory snapshot arrives")
	app.session.changed.emit(app.session.snapshot,app.session.own_id)
	control("WorkshopStep_0").grab_focus()
	await pad(JOY_BUTTON_DPAD_RIGHT)
	await pad(JOY_BUTTON_A)
	expect((control("WorkshopStep_1") as Button).button_pressed,"Controller selects and reads next step")
	await pad(JOY_BUTTON_B)
	expect(app.modal==null,"Controller B returns to world")
	await settle()
	expect(app.session.changed.get_connections().size()==connections,"Closing guide disconnects the live listener")
	app._help()
	await settle()
	press("HelpWorkshopGuide")
	await settle()
	expect(app.modal.get_meta("life_modal_layout","")=="workshop_guide","Existing pocket guide opens workshop examples")
	press("WorkshopBack")
	await settle()
	expect(app.modal.has_meta("pocket_guide"),"Back returns to existing pocket guide")
	app._close_modal()
	await settle()
	expect(app.session.counter==counter and app.session.world.state==world_before,"Reading/navigating never sends game actions or alters world data")
	app.session.shutdown()
	app.queue_free()
	await process_frame
	for suffix in ["",".bak",".tmp",".writer-lock"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	complete=true
	print("WORKSHOP_GUIDE checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
