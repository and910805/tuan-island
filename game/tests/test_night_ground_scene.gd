extends SceneTree

const World=preload("res://scripts/world.gd")
const View=preload("res://scripts/world_view.gd")
const PLAYER:="night-preview-player"
const FOOT:=Vector2(43.5,33.5)
const LAMP:=Vector2i(47,34)
const GRASS:=Vector2(48.3,33.5)
const ROAD:=Vector2(41.0,31.0)
var app
var world:World
var checks:=0
var failures:=0

func _initialize() -> void:
	run.call_deferred()

func expect(condition:bool,message:String) -> void:
	checks+=1
	if not condition:
		failures+=1
		push_error(message)

func frame(time:float) -> Image:
	world.state.time=time
	app.session.receive_state(world.state.duplicate(true),PLAYER)
	app.view.update_camera(FOOT,true)
	app._refresh_hud()
	app._update_world_label_obstacles()
	app.view.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func point(cell:Vector2) -> Vector2i:
	return Vector2i((app.view.screen(cell)*app.view.view_zoom()).round())

func brightness(color:Color) -> float:
	return color.r*0.2126+color.g*0.7152+color.b*0.0722

func run() -> void:
	var full:=View.night_darkness(0.0)
	expect(full==1.0 and View.night_darkness(1439.0)==full,"Midnight has no lighting jump")
	expect(View.night_darkness(360.0)==0.0 and View.night_darkness(720.0)==0.0,"Daylight has no terrain wash")
	expect(is_equal_approx(View.night_darkness(330.0),0.5) and is_equal_approx(View.night_darkness(1140.0),0.5),"Dawn and dusk blend smoothly")
	if DisplayServer.get_name()=="headless":
		print("NIGHT_GROUND_SCENE_TESTS checks=%d failures=%d"%[checks,failures])
		quit(int(failures>0))
		return
	app=preload("res://main.tscn").instantiate()
	app.village_art_preview=true
	root.add_child(app)
	root.size=Vector2i(1280,800)
	await process_frame
	app.set_process(false)
	app.view.set_process(false)
	app.view.reduced_motion=true
	app.view.zoom=2.0
	app.playing=true
	app.menu.hide()
	app.hud.show()
	world=World.new()
	world.add_player(PLAYER,"望安旅人")
	world.state.players[PLAYER].x=FOOT.x
	world.state.players[PLAYER].y=FOOT.y
	var day:=await frame(720.0)
	var dark:=await frame(0.0)
	var grass:=point(GRASS)
	var road:=point(ROAD)
	expect(brightness(dark.get_pixelv(grass)) < brightness(day.get_pixelv(grass))*0.84,"Midnight grass is noticeably dimmer in the game image")
	var night_road:=dark.get_pixelv(road)
	var night_grass:=dark.get_pixelv(grass)
	var color_gap:=Vector3(night_road.r-night_grass.r,night_road.g-night_grass.g,night_road.b-night_grass.b).length()
	expect(color_gap>0.10,"The road remains distinct from grass in the rendered night")
	var actor_at:=point(FOOT)+Vector2i(-8,-37)
	var body:=Rect2i(actor_at,Vector2i(16,14))
	expect(day.get_region(body).get_data()==dark.get_region(body).get_data(),"Night terrain leaves character pixels unchanged")
	var lamp_key:=World.key(LAMP)
	world.state.objects[lamp_key]={"type":"lamp","owner":PLAYER,"items":{}}
	world.state.objects[World.key(Vector2i(43,31))]={"type":"lantern_post","owner":PLAYER,"items":{}}
	var lit:=await frame(0.0)
	var light_spot:=point(Vector2(LAMP)+Vector2(0.85,0.88))
	var light_color:=lit.get_pixelv(light_spot)
	var unlit_color:=dark.get_pixelv(light_spot)
	expect(light_color.r>unlit_color.r and brightness(light_color)>brightness(unlit_color),"A placed lamp warms and brightens nearby ground")
	var still:=await frame(0.0)
	expect(lit.get_region(Rect2i(light_spot-Vector2i(6,6),Vector2i(12,12))).get_data()==still.get_region(Rect2i(light_spot-Vector2i(6,6),Vector2i(12,12))).get_data(),"Reduced-motion lighting is steady")
	var destination:String=app.arg_value("night-ground-preview","")
	if not destination.is_empty():
		var lit_day:=await frame(720.0)
		expect(DirAccess.make_dir_recursive_absolute(destination)==OK,"Capture directory is available")
		expect(lit_day.save_png(destination.path_join("day.png"))==OK and lit.save_png(destination.path_join("night.png"))==OK,"Day and night screenshots saved")
	app.queue_free()
	await process_frame
	print("NIGHT_GROUND_SCENE_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
