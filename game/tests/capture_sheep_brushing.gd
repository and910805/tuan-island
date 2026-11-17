extends SceneTree
const World=preload("res://scripts/world.gd")
const Almanac=preload("res://scripts/life_ui_almanac.gd")
const Art=preload("res://scripts/livestock_scene_art.gd")
var app
var checks:=0
var failures:=0
var directory:=""
func _initialize()->void:run.call_deferred()
func expect(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;push_error(label)
func shot(name:String)->void:
	app.view.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	expect(root.get_texture().get_image().save_png(directory.path_join(name+".png"))==OK,"Capture "+name)
func run()->void:
	app=preload("res://main.tscn").instantiate()
	app.village_art_preview=true
	root.add_child(app)
	root.size=Vector2i(1024,640)
	var extent:String=app.arg_value("qa-size","1024x640")
	root.size=Vector2i(int(extent.get_slice("x",0)),int(extent.get_slice("x",1)))
	directory=app.arg_value("qa-dir","")
	assert(not directory.is_empty())
	DirAccess.make_dir_recursive_absolute(directory)
	app.session.profile.token="sheep-brush-qa"
	expect(app.session.host(0,"羊毛梳理",directory.path_join("world.json"))==OK,"Host isolated native world")
	await create_timer(0.25).timeout
	app.session.set_physics_process(false)
	app.set_process(false)
	var world=app.session.world
	var token:String=app.session.peers[1]
	# Fixture: picnic gate and a real nearby standing position, not production.
	world.state.picnic=true
	world.state.players[token].x=49.5
	world.state.players[token].y=36.5
	app.session._send_snapshot(1)
	await process_frame
	preload("res://scripts/wangan_opening_ui.gd").dismiss(app)
	app.view.set_process(false)
	app.view.reduced_motion=app.arg_value("qa-reduced","")=="true"
	app.view.photograph_mode=app.arg_value("qa-photo","")=="true"
	Almanac.livestock_menu(app,"sheep")
	app._layout_preview()
	app._process(0.0)
	await create_timer(0.15).timeout
	var brush:=app.modal.find_child("SheepBrush",true,false) as Button
	expect(brush!=null and not brush.disabled and brush.icon!=null,"Actual sheep card has available brush and formal PNG")
	var text_width:float=brush.get_theme_font("font").get_string_size(brush.text,HORIZONTAL_ALIGNMENT_LEFT,-1,brush.get_theme_font_size("font_size")).x
	expect(brush.size.x>=text_width+48,"Brush button leaves room for its PNG beside text")
	var scroll:=app.modal.find_child("ModalScroll",true,false) as ScrollContainer
	for id in ["SheepBrush","LivestockFeed","LivestockCollect"]:
		expect(scroll.get_global_rect().encloses(app.modal.find_child(id,true,false).get_global_rect()),"Care action visible without scrolling: "+id)
	await shot("sheep_card")
	var before:Dictionary=world.state.players[token].inventory.duplicate(true)
	brush.pressed.emit()
	app.session._send_snapshot(1)
	await process_frame
	app.toast.hide()
	app.view.hide_interaction_prompt=true
	expect(int(world.state.livestock.sheep.bond)==1 and world.state.livestock.sheep.last_care=="brush","UI action actually brushes the sheep")
	expect(app.modal==null and app.view.livestock_pet_feedback.has("sheep"),"Confirmed fresh event closes menu and starts feedback")
	var stamp:float=app.view.livestock_pet_feedback.get("sheep",-100)
	var camera:Vector2=app.view.camera
	var state:Dictionary=world.state.duplicate(true)
	for index in 20:
		app.view.elapsed=stamp+float(index)*0.06
		await shot("brush_%02d"%index)
	expect(world.state==state and world.state.players[token].inventory==before,"Visual frames never alter animal production or inventory")
	expect(camera==app.view.camera,"Grooming never moves the map")
	app.session._send_snapshot(1)
	expect(app.view.livestock_pet_feedback.sheep==stamp,"Repeated snapshot does not restart brushing")
	app.view.elapsed=stamp+Art.PET_SECONDS+0.1
	await shot("finished")
	# Reconnect/initial data with a recent care timestamp must not replay the event.
	app.view.data={}
	app.view.update_snapshot(app.session.snapshot.duplicate(true),app.session.own_id)
	expect(app.view.livestock_pet_feedback.is_empty(),"Initial/recentered snapshot does not replay old grooming")
	Almanac.livestock_menu(app,"sheep")
	var cooling:=app.modal.find_child("SheepBrush",true,false) as Button
	expect(cooling.disabled,"UI shares the actual pet cooldown after brushing")
	app._close_modal()
	app.session.shutdown()
	print("SHEEP_BRUSH_NATIVE checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
