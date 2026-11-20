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
func control(id:String)->Control:
	return app.modal.find_child(id,true,false) as Control if is_instance_valid(app.modal) else null
func press(id:String)->void:
	var button:=control(id) as Button
	expect(button!=null and not button.disabled and button.is_visible_in_tree(),"Button available: "+id)
	if button!=null and not button.disabled and button.is_visible_in_tree():
		if button.toggle_mode:button.button_pressed=not button.button_pressed
		button.pressed.emit()
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

func check_controller_entry(extent:Vector2i)->void:
	root.size=extent
	app._close_modal()
	app.controller_navigation=true
	app.sound.preferred_text_scale=3
	app._apply_font_scale_tree()
	app.set_meta("workshop_guide_topic",Layouts.STARTER_IRRIGATION)
	await settle()
	if app.WanganUI.card_open(app):
		await pad(JOY_BUTTON_B)
	await pad(JOY_BUTTON_B)
	for index in 3:await pad(JOY_BUTTON_DPAD_DOWN)
	await pad(JOY_BUTTON_DPAD_RIGHT)
	var help:=control("PauseHelp")
	expect(help!=null and root.gui_get_focus_owner()==help,"Controller reaches pocket guide from pause at %s"%extent)
	await pad(JOY_BUTTON_A)
	for index in 6:await pad(JOY_BUTTON_DPAD_DOWN)
	var diagrams:=control("HelpWorkshopGuide")
	expect(diagrams!=null and root.gui_get_focus_owner()==diagrams,"Controller reaches the workshop illustrations from the guide")
	await pad(JOY_BUTTON_A)
	if not is_instance_valid(app.modal) or control("WorkshopNext")==null:
		expect(false,"Controller enters the workshop illustration")
		return
	var scroll:=control("ModalScroll") as ScrollContainer
	expect(app.modal_feedback.text.contains("手把 B"),"Workshop shows the controller back shortcut")
	for step in 3:
		var next:=control("WorkshopNext") as Button
		expect(root.gui_get_focus_owner()==next,"Next retains focus at step %d"%(step+1))
		expect(scroll.get_global_rect().grow(1).encloses(next.get_global_rect()),"Next is fully visible at %s"%extent)
		await pad(JOY_BUTTON_A)
	var previous:=control("WorkshopPrev") as Button
	expect((control("WorkshopStep_3") as Button).button_pressed,"Controller advances to the final illustration")
	expect(root.gui_get_focus_owner()==previous,"Focus moves to Previous at the final illustration")
	await shot("%d_controller_large_text"%extent.x)
	await pad(JOY_BUTTON_A)
	expect((control("WorkshopStep_2") as Button).button_pressed,"Controller goes back an illustration")
	await check_controller_recipe(extent)
	await pad(JOY_BUTTON_B)
	expect(app.modal==null and root.gui_get_focus_owner()==null,"Controller closes the workshop guide and releases focus")

func check_controller_recipe(extent:Vector2i)->void:
	for key in [JOY_BUTTON_DPAD_DOWN,JOY_BUTTON_DPAD_DOWN,JOY_BUTTON_DPAD_LEFT]:
		await pad(key)
	expect(root.gui_get_focus_owner()==control("WorkshopDetailsToggle"),"Controller reaches notes at %s"%extent)
	await pad(JOY_BUTTON_A)
	expect(control("WorkshopDetails").is_visible_in_tree(),"Controller opens the materials and notes")
	await pad(JOY_BUTTON_DPAD_DOWN)
	await pad(JOY_BUTTON_DPAD_LEFT)
	var pipe:=control("WorkshopPiece_water_pipe") as Button
	expect(root.gui_get_focus_owner()==pipe,"Controller reaches the pipe material")
	await pad(JOY_BUTTON_A)
	expect(pipe.button_pressed,"Controller selects the pipe material")
	await pad(JOY_BUTTON_DPAD_UP)
	expect(root.gui_get_focus_owner()==control("WorkshopBuild"),"Controller reaches the selected material recipe")
	await pad(JOY_BUTTON_A)
	var title:=control("BuildTitle") as Label
	var diagram:=control("BuildWorkshopGuide") as Button
	if title==null or diagram==null:
		expect(false,"Controller opens the build recipe")
		return
	expect(title.text==World.BUILD.water_pipe.name,"Builder opens the selected pipe recipe")
	expect(root.gui_get_focus_owner()==diagram and diagram.text=="回圖解","Recipe gives immediate controller focus to the labelled return")
	await shot("%d_controller_recipe"%extent.x)
	await pad(JOY_BUTTON_A)
	if control("WorkshopDetails")==null:
		expect(false,"Controller returns from the build recipe")
		return
	expect(root.gui_get_focus_owner()==control("WorkshopDetailsToggle") and control("WorkshopDetails").is_visible_in_tree(),"Returning restores the notes and their controller focus")
	expect((control("WorkshopPiece_water_pipe") as Button).button_pressed,"Returning preserves the selected pipe")
	await shot("%d_controller_materials"%extent.x)
	await pad(JOY_BUTTON_A)
	expect((control("WorkshopStep_2") as Button).button_pressed,"Closing notes returns to the same irrigation step")

func shot(name:String)->void:
	if DisplayServer.get_name()=="headless" or directory.is_empty():return
	await RenderingServer.frame_post_draw
	expect(root.get_texture().get_image().save_png(directory.path_join(name+".png"))==OK,"Capture "+name)
func proof()->void:
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--qa-proof-save="):continue
		var loaded:=World.new()
		expect(loaded.load_world(arg.trim_prefix("--qa-proof-save=")),"Load real earned fuel-loop evidence")
		var stations:Array=loaded.state.objects.keys().filter(func(key):return loaded.state.objects[key].type=="forester")
		if stations.size()!=1:
			expect(false,"Earned layout has exactly one forestry station")
			return
		var origin:=World.cell(stations[0])-Vector2i(2,2)
		for piece:Dictionary in Layouts.lesson(2).design.pieces:
			var cell:=origin+Vector2i(piece.x,piece.y)
			var obj:Dictionary=loaded.state.objects.get(World.key(cell),{})
			expect(obj.get("type","")==piece.kind,"Guide piece matches earned actual layout: "+World.key(cell))
			if piece.kind=="conveyor":expect(int(obj.get("dir",-1))==piece.settings.dir and obj.get("filter","")==piece.settings.filter,"Guide belt directions/filters match actual earned loop")
func preview_of()->Node:return app.modal.find_child("WorkshopPreview",true,false)
## Opens a lesson with a chosen motion mode ("on", "off" or "auto").
func open_with(topic:int,mode:String)->void:
	app.set_meta("workshop_guide_motion",mode)
	app._workshop_guide(topic)
	await settle()
func check_guide_copy(topic:int)->void:
	var guide:Array=Layouts.lesson(topic).guide
	expect(guide.size()==4,"Four action stages for topic %d"%topic)
	var pieces:Array=Layouts.lesson(topic).design.pieces
	for data:Dictionary in guide:
		var lines:Array=data.lines
		expect(lines.size()>=1 and lines.size()<=2,"At most two focused lines per stage")
		expect(not str(data.heading).is_empty() and str(data.heading).length()<=14,"One short action heading")
		expect(int(data.placed)>=1 and int(data.placed)<=pieces.size() and int(data.from)<=int(data.placed),"Stage placement counts stay inside the real layout")
		var copy:=str(data.heading)+"".join(PackedStringArray(lines.map(func(line):return str(line))))
		expect(not copy.contains("；") and not copy.contains(";"),"Stage copy has no semicolons")
		for entry:Dictionary in data.flows:
			var route:Array=entry.path
			expect(route.size()>=2,"Flow has a direction")
func run()->void:
	create_timer(90.0).timeout.connect(func():
		if not complete:push_error("Guide test watchdog");quit(1))
	var expected:=[{"pump_kit":1,"pipe_kit":1,"tank_kit":1,"sprinkler_kit":1},{"forester_kit":1,"conveyor_kit":1,"sawmill_kit":1},{"forester_kit":1,"conveyor_kit":8,"kiln_kit":1,"sawmill_kit":1,"wood":20},{"tank_kit":1,"pipe_kit":2,"sprinkler_kit":1},{"wood":66,"fiber":24}]
	for index in Layouts.TITLES.size():
		var lesson:=Layouts.lesson(index)
		expect(Design.validate(lesson.design,World.BUILD,World.NAMES).ok,"Guide uses valid existing blueprint schema")
		expect(Layouts.cost(index)==expected[index],"Actual canonical build costs for topic %d"%index)
		for marker:Dictionary in lesson.markers:
			expect(not lesson.design.pieces.any(func(piece):return int(piece.x)==int(marker.x) and int(piece.y)==int(marker.y)),"Reserved planting marker is not occupied by a machine")
		check_guide_copy(index)
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
	if "--controller-route" in OS.get_cmdline_user_args():
		for extent in [Vector2i(1024,640),Vector2i(1280,800),Vector2i(1920,1080)]:
			await check_controller_entry(extent)
		await finish()
		return
	var world_before:Dictionary=app.session.world.state.duplicate(true)
	var counter:int=app.session.counter
	var connections:int=app.session.changed.get_connections().size()
	# The static layout checks below are the same with or without a display.
	app.set_meta("workshop_guide_motion","off")
	for extent in [Vector2i(1024,640),Vector2i(1280,800)]:
		root.size=extent
		for topic in Layouts.TITLES.size():
			app._workshop_guide(topic)
			await settle()
			expect(app.session.changed.get_connections().size()==connections+1,"Exactly one live guide listener after replacing panels")
			var scroll:=control("ModalScroll") as ScrollContainer
			expect(Rect2(Vector2.ZERO,Vector2(root.size)).encloses(app.modal.get_global_rect()),"Guide fits viewport")
			var guide:Array=Layouts.lesson(topic).guide
			var preview:Object=preview_of()
			expect(preview!=null,"Preview exists for topic %d"%topic)
			expect(control("WorkshopStepHeading").text==str(guide[0].heading) and (control("WorkshopProgress") as Label).text=="第 1／4 步","Default entrance shows the first action immediately")
			expect(not control("WorkshopDetails").visible,"Notes and costs stay behind optional details")
			for step in 4:
				press("WorkshopStep_%d"%step)
				await settle()
				var data:Dictionary=guide[step]
				var lines:Array=data.lines
				var text:=control("WorkshopStepText") as Label
				expect(control("WorkshopStepHeading").text==str(data.heading),"Stage shows its action heading")
				expect(text.text=="\n".join(PackedStringArray(lines.map(func(line):return str(line)))),"Stage shows its focused lines")
				expect((control("WorkshopStep_%d"%step) as Button).button_pressed,"Selector marks stage %d"%step)
				expect((control("WorkshopPrev") as Button).disabled==(step==0) and (control("WorkshopNext") as Button).disabled==(step==3),"Prev and next limits at stage %d"%step)
				var report:Dictionary=preview.state_report()
				expect(int(report.total)==int(data.placed) and int(report.visible)<=int(report.total),"Preview matches the stage placement")
				if topic==Layouts.FIRST_HOUSE:
					expect(int(report.marks)==(4 if step==2 else 0),"House previews automatic roofing when the door is placed")
					expect(control("WorkshopHouseCheck").visible==(step==3),"Structure check is available in the furnishing step")
				for id in ["WorkshopDiagram","WorkshopBuild","WorkshopBack","WorkshopStepText","WorkshopStepHeading","WorkshopPrev","WorkshopNext","WorkshopDetailsToggle","WorkshopReplay"]:
					expect(scroll.get_global_rect().encloses(control(id).get_global_rect()),"Guide control visible without scrolling: "+id)
			# Previous and next walk one action at a time.
			press("WorkshopStep_0")
			press("WorkshopNext")
			press("WorkshopNext")
			expect((control("WorkshopStep_2") as Button).button_pressed,"Next advances one stage at a time")
			press("WorkshopPrev")
			expect((control("WorkshopStep_1") as Button).button_pressed and control("WorkshopStepHeading").text==str(guide[1].heading),"Previous goes back one stage")
			# Details hold the real notes, startup items and live materials.
			press("WorkshopDetailsToggle")
			await settle()
			expect(control("WorkshopDetails").visible and control("WorkshopNote").text==str(Layouts.lesson(topic).note),"Details reveal the real notes")
			var startup:=control("WorkshopStartup") as Label
			if topic==Layouts.FIRST_HOUSE:expect(startup==null,"House has no machine startup items")
			else:expect(startup!=null and startup.text.begins_with("另備起動用料："),"Details list startup items")
			expect(not control("WorkshopDiagram").is_visible_in_tree() and scroll.get_global_rect().encloses(control("WorkshopMaterials").get_global_rect()),"Materials are immediately visible on the details page")
			for item in Layouts.cost(topic):
				var label:=control("WorkshopCost_"+str(item)) as Label
				expect(label.get_line_count()==1,"Material number remains on one line")
			press("WorkshopDetailsToggle")
			await settle()
			expect(not control("WorkshopDetails").visible,"Details collapse again")
			# Headless uses the readable static equivalent.
			var still:Dictionary=preview.state_report()
			expect(not bool(still.animated) and int(still.visible)==int(still.total),"Headless guide shows the static final placement")
			expect((control("WorkshopReplay") as Button).disabled,"Replay is unavailable when motion is off")
			press("WorkshopStep_0")
			await settle()
			await shot("%d_lesson_%d"%[extent.x,topic])
			press("WorkshopStep_3")
			await settle()
			await shot("%d_lesson_%d_last"%[extent.x,topic])
			press("WorkshopStep_0")
			await settle()
			# The ordinary builder remains the only construction path.
			var kind:String=["water_pump","forester","conveyor","water_tank","floor"][topic]
			press("WorkshopDetailsToggle")
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
				var kit_only:Dictionary=current.duplicate(true)
				kit_only.players[app.session.own_id].inventory={"sprinkler_kit":1}
				app.session.snapshot=kit_only
				app.life_panels.build_menu(app,"sprinkler")
				await settle()
				var description:String=control("BuildDescription").text
				expect(description.contains("每天澆一次") and description.contains("牆與關閉的門"),"The builder shows daily watering and barriers when the player has only the workbench kit")
				app.session.snapshot=current
	# Recipe link follows the stage focus.
	await open_with(0,"off")
	press("WorkshopStep_1")
	expect(control("WorkshopBuild").text.contains(World.BUILD["water_pipe"].name),"Recipe link names the device in focus")
	# Forced motion: sequential placement, replay and read-only layout.
	var saved_reduced:bool=bool(app.sound.reduced_motion)
	app.sound.reduced_motion=false
	for extent in [Vector2i(1024,640),Vector2i(1280,800)]:
		root.size=extent
		await open_with(2,"on")
		var moving:Object=preview_of()
		var real:Dictionary=Layouts.lesson(2).design
		expect(bool(moving.state_report().animated) and not (control("WorkshopReplay") as Button).disabled,"Motion plays when allowed")
		press("WorkshopStep_0")
		moving.seek(0.0)
		expect(int(moving.state_report().visible)==1,"Placement starts with the first device")
		moving.seek(2.3)
		expect(int(moving.state_report().visible)==4,"Devices appear one after another until all are placed")
		press("WorkshopStep_2")
		moving.seek(1.0)
		expect(int(moving.state_report().total)==11 and int(moving.state_report().flows)==1,"Fuel stage animates only the charcoal path")
		await settle()
		await shot("%d_motion_fuel_loop"%extent.x)
		moving.seek(7.0)
		press("WorkshopReplay")
		expect(is_zero_approx(float(moving.state_report().time)),"Replay restarts the demonstration")
		expect(moving.source==real,"Preview never edits the real lesson layout")
		await open_with(0,"on")
		press("WorkshopStep_3")
		await settle()
		preview_of().seek(1.2)
		await shot("%d_motion_wet_field"%extent.x)
		await open_with(Layouts.FIRST_HOUSE,"on")
		press("WorkshopStep_1")
		var house_preview:Object=preview_of()
		house_preview.seek(0.0)
		expect(int(house_preview.state_report().visible)==5,"The house animation starts with four floors and the first wall")
		house_preview.seek(3.0)
		expect(int(house_preview.state_report().visible)==15,"The ring is shown before the door step")
		press("WorkshopStep_2")
		await settle()
		house_preview.seek(0.9)
		expect(int(house_preview.state_report().marks)==4,"The door step shows all four roof tiles")
		await shot("%d_motion_house_roof"%extent.x)
	# Reduced motion wins over any request for motion.
	app.sound.reduced_motion=true
	await open_with(1,"on")
	var calm:Object=preview_of()
	var calm_report:Dictionary=calm.state_report()
	expect(not bool(calm_report.animated) and int(calm_report.visible)==int(calm_report.total),"Reduced motion shows the finished static state")
	expect((control("WorkshopReplay") as Button).disabled,"Replay stays off under reduced motion")
	press("WorkshopStep_2")
	expect(int(calm.state_report().flows)==1 and not bool(calm.state_report().animated),"Static equivalent still carries the flow direction")
	app.sound.reduced_motion=saved_reduced
	app.set_meta("workshop_guide_motion","auto")
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
	control("GuideCard5").grab_focus()
	await pad(JOY_BUTTON_DPAD_DOWN)
	expect(root.gui_get_focus_owner()==control("HelpWorkshopGuide"),"Controller reaches workshop diagrams from the last pocket guide card")
	await pad(JOY_BUTTON_DPAD_DOWN)
	expect(root.gui_get_focus_owner()==control("GuideCard6"),"Controller can continue down to the first workshop card")
	await pad(JOY_BUTTON_DPAD_UP)
	expect(root.gui_get_focus_owner()==control("HelpWorkshopGuide"),"Controller can return upward to workshop diagrams")
	await pad(JOY_BUTTON_A)
	await settle()
	expect(app.modal.get_meta("life_modal_layout","")=="workshop_guide","Existing pocket guide opens workshop examples")
	press("WorkshopBack")
	await settle()
	expect(app.modal.has_meta("pocket_guide"),"Back returns to existing pocket guide")
	app.life_panels.build_menu(app,"wall")
	await settle()
	var whole:=control("BuildOccupyTile") as CheckButton
	expect(whole!=null and whole.is_visible_in_tree() and not whole.button_pressed,
		"Wall recipes opened outside the lesson still default to the grid edge")
	if whole!=null:
		whole.button_pressed=true
		expect(control("BuildDescription").text.contains("以整格施工"),"Switching the method updates the construction hint")
	app._close_modal()
	await settle()
	expect(app.session.counter==counter and app.session.world.state==world_before,"Reading/navigating never sends game actions or alters world data")
	await finish()

func finish()->void:
	app.session.shutdown()
	app.queue_free()
	await process_frame
	for suffix in ["",".bak",".tmp",".writer-lock"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	complete=true
	print("WORKSHOP_GUIDE checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
