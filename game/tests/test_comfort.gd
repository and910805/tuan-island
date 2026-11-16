extends SceneTree
const Audio=preload("res://scripts/soft_audio.gd")
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
	bad.save(path)
	var safe=Audio.new();root.add_child(safe);safe.load_preferences(path)
	expect(safe.volume==0.45 and safe.reduced_motion and safe.preferred_zoom==2,"malformed preference values preserve safe defaults")
	DirAccess.remove_absolute(path)
	sound.close();loaded.close();safe.close()
	await create_timer(0.15).timeout
	sound.queue_free();loaded.queue_free();safe.queue_free()
	await process_frame
	print("COMFORT_TESTS checks=%d failures=%d"%[checks,failures])
	quit(0 if failures==0 else 1)
