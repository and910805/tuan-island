extends SceneTree

const Audio=preload("res://scripts/soft_audio.gd")
var checks:=0
var failures:=0

func _initialize()->void:
	run.call_deferred()

func expect(ok:bool,message:String)->void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)

func run()->void:
	var app=preload("res://main.tscn").instantiate()
	root.add_child(app)
	app.set_process(false)
	app.playing=true
	var sound:Node=app.sound
	var hashes:Dictionary={}
	for cue:String in Audio.FISHING_CUES:
		var stream:AudioStreamWAV=sound.sounds[cue]
		var pcm:=stream.data
		var peak:=0
		for offset in range(0,pcm.size(),2):
			peak=maxi(peak,absi(pcm.decode_s16(offset)))
		expect(stream.mix_rate==Audio.RATE and not stream.stereo and peak>1000 and peak<8000,"Audible headroom for "+cue)
		expect(pcm.decode_s16(0)==0 and absi(pcm.decode_s16(pcm.size()-2))<=2,"Attack and release taper "+cue)
		hashes[pcm.hex_encode().sha256_text()]=true
	var cast_pcm:PackedByteArray=sound.sounds.fish_cast.data
	var water_peak:=0
	for index in range(roundi(Audio.FishingFeedback.CAST_DURATION*Audio.RATE),cast_pcm.size() >> 1):
		water_peak=maxi(water_peak,absi(cast_pcm.decode_s16(index*2)))
	expect(water_peak>1000 and cast_pcm.decode_s16(roundi(0.32*Audio.RATE)*2)==0,"Rod swish gives way to a splash at the animated landing")
	var reel:PackedByteArray=sound.sounds.fish_catch.data
	expect(reel.size()/2.0/Audio.RATE>0.80,"Reel includes water, tension and the catch chime")
	var cue_voices:=sound.get_children().filter(func(child:Node):return child is AudioStreamPlayer and child not in [sound.ambience,sound.nearby,sound.machine,sound.cart_roll,sound.footstep_voice,sound.meadow_warning])
	expect(hashes.size()==Audio.FISHING_CUES.size() and cue_voices==[sound.player],"Distinct fishing cues share one SFX voice")
	var snapshot:Dictionary={"region_id":"home","time":10.0,"players":{"local":{"fish_caught":0},"other":{"fish_caught":0}}}
	var local:Dictionary=snapshot.players.local
	app.fishing_audio.update(snapshot,"local")
	snapshot.players.other.fishing={"x":54,"y":34,"ready":13.0}
	expect(app.fishing_audio.update(snapshot,"local").is_empty(),"Remote cast is silent")
	app._notice("任務成功",true)
	local.fishing={"x":55,"y":34,"ready":13.0}
	for cue:String in app.fishing_audio.update(snapshot,"local"):sound.play_cue(cue)
	await create_timer(0.14).timeout
	expect(sound.player.stream==sound.sounds.fish_cast,"Notice first cannot replace cast")
	snapshot.time=13.0
	for cue:String in app.fishing_audio.update(snapshot,"local"):sound.play_cue(cue)
	expect(sound.player.stream==sound.sounds.fish_bite,"Bite bypasses generic debounce")
	local.erase("fishing")
	local.fish_caught=1
	for cue:String in app.fishing_audio.update(snapshot,"local"):sound.play_cue(cue)
	app._notice("操作成功",true)
	await create_timer(0.14).timeout
	expect(sound.player.stream==sound.sounds.fish_catch,"Snapshot first suppresses a late generic success")
	expect(not sound.play_cue("notice"),"Generic failure sound cannot interrupt a fishing cue")
	var path:=OS.get_environment("TEMP").path_join("fishing-sound-%s.cfg"%Crypto.new().generate_random_bytes(8).hex_encode())
	expect(sound.save_preferences(path,0.0,true,2),"Can mute")
	sound.defer_action("action")
	local.fishing={"x":55,"y":34,"ready":16.0}
	for cue:String in app.fishing_audio.update(snapshot,"local"):sound.play_cue(cue)
	expect(sound.save_preferences(path,0.35,false,1),"Can unmute")
	var loaded:=Audio.new()
	expect(loaded.load_preferences(path) and is_equal_approx(loaded.volume,0.35) and not loaded.reduced_motion and loaded.preferred_zoom==1,"Audio respects saved comfort preferences")
	loaded.free()
	await create_timer(0.14).timeout
	expect(not sound.player.playing and app.fishing_audio.update(snapshot,"local").is_empty(),"Muted cue and action never replay after unmute")
	await create_timer(0.11).timeout
	sound.defer_action("reward")
	app._disconnected()
	await create_timer(0.14).timeout
	expect(sound.player.stream==null and app.fishing_audio.context.is_empty(),"Disconnect clears voice, pending success and fishing baseline")
	var transient:=Audio.new()
	root.add_child(transient)
	transient.defer_action("reward")
	expect(transient.is_processing(),"Success cue is scheduled on the audio node")
	var reference:WeakRef=weakref(transient)
	transient.queue_free()
	await process_frame
	await process_frame
	expect(reference.get_ref()==null,"Node is released before its pending success cue is due")
	sound.close()
	await create_timer(0.15).timeout
	app.queue_free()
	await process_frame
	DirAccess.remove_absolute(path)
	print("FISHING_SOUND_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
