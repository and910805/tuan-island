extends "res://tests/test_bakery_visual.gd"
## Native isolated seeded clock/soil fixture, not an earned journey or network.
const Weather=preload("res://scripts/weather.gd")
class RainCanvas extends "res://scripts/world_view.gd":
	func _draw()->void:
		draw_rect(Rect2(0,0,256,160),Color("88a76d"))
		draw_weather(Vector2(256,160))
var weather_done:=false
func rain_pixels(view:RainCanvas,quiet:bool,t:float)->PackedByteArray:
	view.reduced_motion=quiet;view.elapsed=t;view.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	return view.get_viewport().get_texture().get_image().get_data()
func rain_render_checks()->void:
	var surface:=SubViewport.new();surface.size=Vector2i(256,160)
	surface.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(surface)
	var view:=RainCanvas.new();surface.add_child(view);view.set_process(false)
	view.data={"time":2881.0,"region_id":"home","roofs":{}}
	view.camera=Vector2.ZERO
	var state_before:=JSON.stringify(view.data)
	var moving_a:=await rain_pixels(view,false,0.1)
	var moving_b:=await rain_pixels(view,false,0.6)
	expect(moving_a!=moving_b,"actual native rain pixels move")
	var quiet_a:=await rain_pixels(view,true,0.1)
	var quiet_b:=await rain_pixels(view,true,0.6)
	expect(quiet_a==quiet_b,"actual reduced-motion rain pixels remain static")
	expect(JSON.stringify(view.data)==state_before,"native rain drawing is read-only")
	for y in range(-3,9):
		for x in range(-3,12):view.data.roofs[World.key(Vector2i(x,y))]={}
	var roof_a:=await rain_pixels(view,false,0.1)
	var roof_b:=await rain_pixels(view,false,0.6)
	expect(roof_a==roof_b,"fully roofed native view has no moving rainfall")
	view.data.region_id="mine_1";view.data.roofs={}
	var cave_a:=await rain_pixels(view,false,0.1)
	var cave_b:=await rain_pixels(view,false,0.6)
	expect(cave_a==cave_b,"native cave has no moving rainfall")
	for case in [[18.0,"home"],[48.0,"jiaoxi"]]:
		view.data.time=float(case[0])*Weather.DAY_SECONDS
		view.data.region_id=case[1]
		var drift_a:=await rain_pixels(view,false,0.2)
		var drift_b:=await rain_pixels(view,false,1.6)
		var still_a:=await rain_pixels(view,true,0.2)
		var still_b:=await rain_pixels(view,true,1.6)
		expect(drift_a!=drift_b,"native breeze/snow moves the rendered pixels for "+case[1])
		expect(still_a==still_b,"native reduced motion keeps breeze/snow static for "+case[1])
	surface.queue_free();await settle()
func weather_snapshot()->void:
	app.session._send_snapshot(1)
	app._refresh_hud()
	app.view._process(0.0)
	app.toast.hide()
	await settle()
func weather_frame(name:String,quiet:bool,t:float)->void:
	app.view.reduced_motion=quiet
	app.view.elapsed=t
	app.view._process(0.0)
	await super.shot(name)
func shot(name:String)->void:
	await super.shot(name)
	if name!="bakery-world" or weather_done:return
	weather_done=true
	await rain_render_checks()
	await weather_frame("weather-sunny",false,0.0)
	expect(app.status_label.text.contains("晴"),"native day-one HUD shows sunny weather")
	# Explicit clock and dry-soil setup; rain itself comes from World.step.
	world.state.time=2879.0
	for tile in world.state.crops:
		world.state.crops[tile].wet=false
		world.state.crops[tile].growth=0.0
	var exposed:=World.key(DEMO_CROP_START)
	var covered:=World.key(DEMO_CROP_START+Vector2i.RIGHT)
	world.state.ground[covered]={"type":"floor","owner":HOST,"items":{}}
	world.state.roofs[covered]={"type":"roof","owner":HOST,"items":{}}
	await weather_snapshot()
	expect(app.status_label.text.contains("多雲"),"native cloudy HUD matches authoritative world time")
	await weather_frame("weather-cloudy",false,0.0)
	expect(world.step(2.0,true),"cross midnight through actual World.step")
	await weather_snapshot()
	expect(Weather.at(world.state.time).raining,"world entered rainy day")
	expect(world.state.crops.get(exposed,{}).get("wet",false),"actual rain wets exposed plot")
	expect(not world.state.crops.get(covered,{}).get("wet",true),"actual roof excludes rain")
	expect(app.status_label.text.contains("小雨"),"native rain HUD matches authoritative world time")
	var before:=JSON.stringify(world.state)
	for i in 4:await weather_frame("weather-rain-%02d"%i,false,float(i)*0.25)
	await weather_frame("weather-reduced",true,0.75)
	expect(app.status_label.text.contains("小雨"),"reduced motion keeps rain text")
	expect(JSON.stringify(world.state)==before,"presentation and reduced motion cannot change crops/world")
	root.size=Vector2i(1024,640)
	await weather_snapshot()
	await weather_frame("weather-rain-1024",false,0.5)
	expect(root.get_visible_rect().encloses(app.status_label.get_global_rect()),"weather HUD fits minimum viewport")
	root.size=Vector2i(1280,800)
	app.view.reduced_motion=false
	var original_time:float=world.state.time
	var actor:Dictionary=world.state.players[HOST]
	var original_position:=Vector2(float(actor.x),float(actor.y))
	var original_region:String=actor.region
	world.state.time=18.0*Weather.DAY_SECONDS+600.0
	await weather_snapshot()
	expect(app.status_label.text.contains("微風"),"the live HUD names the breeze")
	await weather_frame("weather-breeze",false,1.6)
	world.state.time=48.0*Weather.DAY_SECONDS+600.0
	actor.region="jiaoxi"
	actor.x=28.5
	actor.y=24.5
	await weather_snapshot()
	expect(app.status_label.text.contains("細雪"),"the live HUD names fine snow in Jiaoxi")
	await create_timer(2.0).timeout
	await weather_frame("weather-snow",false,1.6)
	world.state.time=original_time
	actor.region=original_region
	actor.x=original_position.x
	actor.y=original_position.y
	await weather_snapshot()
	await settle()
