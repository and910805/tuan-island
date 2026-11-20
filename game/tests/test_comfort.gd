extends SceneTree
const Audio=preload("res://scripts/soft_audio.gd")
const World=preload("res://scripts/world.gd")
const View=preload("res://scripts/world_view.gd")
var checks:=0
var failures:=0
func expect(value:bool,message:String) -> void:
	checks+=1
	if not value:failures+=1;push_error("FAIL "+message)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var sound=Audio.new();root.add_child(sound)
	var path:="user://comfort-test-%d.cfg"%Time.get_ticks_usec()
	expect(sound.save_preferences(path,0.0,true,1),"mute and far view save")
	expect(not sound.play_cue("reward",true),"muted player refuses audio")
	var loaded=Audio.new();root.add_child(loaded)
	expect(loaded.load_preferences(path),"preferences reload")
	expect(loaded.volume==0.0 and loaded.reduced_motion and loaded.preferred_zoom==1,"all comfort choices survive restart")
	expect(not loaded.save_preferences("user://missing-comfort-test/settings.cfg",0.8,false,2),"write failure reported")
	expect(loaded.volume==0.0 and loaded.preferred_zoom==1,"failed save does not apply unsaved preferences")
	expect(not loaded.save_preferences(path,NAN,true,2),"invalid volume rejected")
	expect(not loaded.save_preferences(path,0.5,true,3),"unsupported zoom rejected")
	expect(loaded.save_preferences(path,0.4,false,2),"valid settings can change")
	expect(not loaded.fixed_area_camera,"A pre-existing preference keeps direct following")
	expect(loaded.save_preferences(path,0.4,false,2,null,null,null,null,{},true),"Fixed-area choice saves")
	expect(sound.load_preferences(path) and sound.fixed_area_camera,"Fixed-area choice survives reload")
	expect(not loaded.save_preferences(path,0.4,false,2,null,null,null,null,{},"fixed") and loaded.fixed_area_camera,"Invalid camera values leave the setting intact")
	expect(not loaded.display_compatibility,"Older preferences use standard display mode")
	expect(loaded.save_preferences(path,0.4,false,2,null,null,null,null,{},null,true),"Display compatibility saves")
	expect(sound.load_preferences(path) and sound.display_compatibility,"Display compatibility survives a reload")
	expect(not loaded.save_preferences(path,0.4,false,2,null,null,null,null,{},null,"yes") and loaded.display_compatibility,"Invalid display setting does not apply")
	expect(not loaded.save_preferences("user://missing-comfort-test/settings.cfg",0.4,false,2,null,null,null,null,{},null,false) and loaded.display_compatibility,"Display mode changes only after successful save")
	verify_camera()
	expect(loaded.play_cue("reward",true),"preview plays a generated cue")
	expect(not loaded.play_cue("action"),"rapid actions do not stack sound")
	for kind in ["action","reward","notice"]:
		var stream:AudioStreamWAV=Audio.make_cue(kind)
		expect(stream.mix_rate==22050 and stream.format==AudioStreamWAV.FORMAT_16_BITS and not stream.stereo,"cue is valid mono PCM")
		var data:=stream.data
		var peak:=0
		for offset in range(0,data.size(),2):peak=maxi(peak,absi(data.decode_s16(offset)))
		expect(peak>100 and peak<5000,"cue is audible data with conservative peak headroom")
		expect(data.decode_s16(0)==0 and absi(data.decode_s16(data.size()-2))<=1,"cue has soft silent endpoints")
	var bad:=ConfigFile.new()
	bad.set_value("comfort","volume","loud")
	bad.set_value("comfort","reduced_motion",99)
	bad.set_value("comfort","zoom",-5)
	bad.set_value("comfort","display_compatibility","yes")
	bad.save(path)
	var safe=Audio.new();root.add_child(safe);safe.load_preferences(path)
	expect(safe.volume==0.45 and safe.reduced_motion and safe.preferred_zoom==2,"malformed preference values preserve safe defaults")
	expect(not safe.display_compatibility,"malformed display preference retains standard mode")
	DirAccess.remove_absolute(path)
	sound.close();loaded.close();safe.close()
	await create_timer(0.15).timeout
	sound.queue_free();loaded.queue_free();safe.queue_free()
	await process_frame
	print("COMFORT_TESTS checks=%d failures=%d"%[checks,failures])
	quit(0 if failures==0 else 1)

func verify_camera() -> void:
	var world:=World.new()
	world.add_player("camera-test","島民")
	var actor:Dictionary=world.state.players["camera-test"]
	var view:=View.new()
	root.add_child(view)
	view.set_process(false)
	view.village_art_preview=true
	view.fixed_area_camera=true
	var position:=Vector2(39.5,33.5)
	actor.x=position.x
	actor.y=position.y
	view.update_snapshot(world.state.duplicate(true),"camera-test")
	var original:=view.camera
	actor.x+=1.0
	view.update_snapshot(world.state.duplicate(true),"camera-test")
	advance_camera(view)
	expect(view.camera==original,"A one-tile walk leaves the background stationary")
	actor.x+=2.0
	view.update_snapshot(world.state.duplicate(true),"camera-test")
	advance_camera(view)
	expect(view.camera.x>original.x and view.camera.y==original.y,"Crossing the edge follows only along the moving axis")
	expect(view.camera==view.camera.round(),"Fixed-area offsets land on whole pixels")
	var chosen:=Vector2(44.5,35.5)
	expect(view.to_cell(view.screen(chosen)*view.view_zoom())==Vector2i(44,35),"Screen picking stays attached to the same world cell")
	actor.x+=0.25
	view.update_snapshot(world.state.duplicate(true),"camera-test")
	advance_camera(view)
	var moved:=Vector2(actor.x,actor.y)
	var anchor:=view.get_viewport_rect().size*0.5+Vector2(0,40)
	view.zoom=1.0
	view._process(0.1)
	expect((view.screen(moved)*view.view_zoom()).distance_to(anchor)<=1.0,"Changing zoom recenters without a stale edge offset")
	actor.y+=8.0
	view.update_snapshot(world.state.duplicate(true),"camera-test")
	expect((view.screen(Vector2(actor.x,actor.y))*view.view_zoom()).distance_to(anchor)<=1.0,"A long jump immediately centers the area on arrival")
	var mine_snapshot:=world.state.duplicate(true)
	mine_snapshot.region_id="mine_1"
	view.zoom=2.0
	view.update_snapshot(mine_snapshot,"camera-test")
	expect(view.view_zoom()==1.0 and (view.screen(Vector2(actor.x,actor.y))*view.view_zoom()).distance_to(anchor)<=1.0,"Changing region resets the camera with the mine's own zoom")
	view.fixed_area_camera=false
	view._process(0.1)
	actor.x+=1.0
	mine_snapshot.players["camera-test"]=actor.duplicate()
	view.update_snapshot(mine_snapshot,"camera-test")
	view._process(1.0/60.0)
	expect((view.screen(view.display_positions["camera-test"])*view.view_zoom()).distance_to(anchor)<=1.0,"Direct mode follows the drawn player on the first movement frame")
	advance_camera(view)
	expect((view.screen(Vector2(actor.x,actor.y))*view.view_zoom()).distance_to(anchor)<=1.0,"Direct mode stays centered after the motion settles")
	view.queue_free()

func advance_camera(view:View) -> void:
	# A server snapshot can arrive ahead of the drawn actor. Let up to one
	# simulated second of normal rendering elapse before checking settled offsets.
	for frame in 60:view._process(1.0/60.0)
