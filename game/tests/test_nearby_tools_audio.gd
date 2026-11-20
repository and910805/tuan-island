extends SceneTree

# Native test of the real SoftAudio node (res://scripts/soft_audio.gd) for the
# "nearby tools" voice and for outdoor-vs-indoor ambience.
#
# Contract under test:
#   * play_nearby_tools(actors,records,own_id,listener)->bool keeps its signature.
#   * One voice: the strongest source = nearest valid source, gain bounded by
#     NEARBY_MAX_GAIN / NEARBY_RADIUS; own actions are never replayed locally;
#     while the voice is busy a second call does not overlap or restart it.
#   * The nearby player covers axe/pick/harvest plus hoe/seed/water, build/remove,
#     plant_tree and move_object, each mapped to a local cue that exists.
#   * Muting through refresh_gains() stops an in-flight nearby voice;
#     a region change or entering/leaving a room clears it;
#     stop_cues() resets it.
#   * Outdoors plays "wind"; roofed house, greenhouse, public tea house, pottery
#     workshop and warm-springs inn have no outdoor ambience; stepping back
#     outside resumes wind.
#   * AudioEffectCapture on Master measures audibility and clipping.
#
# Run (windowed, real driver, needed for the ambience and capture parts):
#   godot --path game --script res://tests/test_nearby_tools_audio.gd
# Headless runs the contract parts only; set_world() deliberately returns before
# ambience in headless, so the ambience parts are reported as skipped.

const Audio=preload("res://scripts/soft_audio.gd")
const Music=preload("res://scripts/scene_music.gd")
const TeaInterior=preload("res://scripts/tea_house_interior.gd")
const PotteryInterior=preload("res://scripts/pottery_workshop_interior.gd")
const Springs=preload("res://scripts/warm_springs.gd")
const LISTENER:=Vector2(20.5,20.5)
const ORIGIN:=Vector2i(20,20)
const REQUIRED_CUES:={"axe":"wood_hit","pick":"stone_hit","harvest":"crop_pick","hoe":"hoe_soil","seed":"seed_drop","water":"water_pour","build":"build_set","remove":"build_lift","plant_tree":"seed_drop","move_object":"build_lift"}
const EPS:=0.01
const AUDIBLE_PEAK:=0.002
const SILENT_PEAK:=0.0005
const CLIP_LIMIT:=0.98
var checks:=0
var failures:=0
var skipped:=0

func _initialize()->void:
	run.call_deferred()

func expect(ok:bool,message:String)->void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)
		print("FAIL: ",message)

func skip(message:String)->void:
	skipped+=1
	print("SKIPPED: ",message)

func record(tool:String,cell:Vector2i)->Dictionary:
	return {"tool":tool,"cell":cell}

func person(x:float,y:float)->Dictionary:
	return {"x":x,"y":y,"travel_epoch":0,"peer":1}

func snap(region:String,x:float,y:float,roofs:Dictionary={})->Dictionary:
	return {"region_id":region,"time":720.0,"roofs":roofs,"players":{"own":person(x,y)}}

func make_sound()->Audio:
	var sound:=Audio.new()
	root.add_child(sound)
	sound.volume=1.0
	sound.master_volume=1.0
	return sound

func fire(sound:Audio,actors:Array,records:Dictionary,listener:Vector2=LISTENER)->bool:
	return sound.play_nearby_tools(actors,records,"own",listener)

func expected_gain(distance:float)->float:
	return Audio.NEARBY_MAX_GAIN*pow(1.0-distance/Audio.NEARBY_RADIUS,2.0)

func run()->void:
	var headless:=DisplayServer.get_name()=="headless"
	print("NEARBY_TOOLS_AUDIO display=%s audio_driver=%s"%[DisplayServer.get_name(),AudioServer.call("get_driver_name") if AudioServer.has_method("get_driver_name") else "unknown"])
	check_source_selection()
	check_busy_and_gain()
	check_burst()
	check_mute_and_reset()
	check_room_clearing()
	if headless:skip("ambience wind/indoor parts: set_world() returns before ambience when DisplayServer is headless; rerun windowed")
	else:await check_ambience()
	await check_capture(headless)
	await create_timer(0.2).timeout
	print("NEARBY_TOOLS_AUDIO skipped=%d"%skipped)
	print("NEARBY_TOOLS_AUDIO_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

# ------------------------------------------------------- source selection

func check_source_selection()->void:
	var sound:=make_sound()
	# Every supported tool is audible from another actor and picks its own cue.
	for tool:String in REQUIRED_CUES:
		sound.nearby.stop()
		var played:=fire(sound,["a"],{"a":record(tool,ORIGIN+Vector2i(2,0))})
		expect(played and sound.nearby.playing,"Another actor's "+tool+" is heard")
		expect(sound.nearby.stream==sound.sounds[REQUIRED_CUES[tool]],tool+" plays its mapped cue")
		expect(not sound.player.playing,tool+" does not take the shared interface voice")
	# Nearest valid source wins, regardless of order and of louder-looking far records.
	sound.nearby.stop()
	var records:={
		"far":record("pick",ORIGIN+Vector2i(7,0)),
		"near":record("axe",ORIGIN+Vector2i(1,0)),
		"mid":record("harvest",ORIGIN+Vector2i(3,3)),
	}
	expect(fire(sound,["far","mid","near"],records),"Several sources give one sound")
	expect(sound.nearby.stream==sound.sounds.wood_hit,"Nearest source (axe) is the one heard")
	expect(absf(sound.nearby_gain-expected_gain(1.0))<0.0005,"Gain follows the nearest source distance, got %f"%sound.nearby_gain)
	sound.nearby.stop()
	expect(fire(sound,["near","mid","far"],records) and sound.nearby.stream==sound.sounds.wood_hit,"Actor order does not change the winner")
	# No local replay: own actions and stale records are ignored.
	sound.nearby.stop()
	expect(not fire(sound,["own"],{"own":record("axe",ORIGIN)}),"Own action is never replayed locally")
	expect(not sound.nearby.playing,"Own action leaves the voice idle")
	expect(not fire(sound,[],{"a":record("axe",ORIGIN+Vector2i(1,0))}),"Records for actors that were not fresh are not replayed")
	var own_and_other:=fire(sound,["own","a"],{"own":record("axe",ORIGIN),"a":record("pick",ORIGIN+Vector2i(4,0))})
	expect(own_and_other and sound.nearby.stream==sound.sounds.stone_hit,"Own action does not mask or beat another actor")
	expect(absf(sound.nearby_gain-expected_gain(4.0))<0.0005,"Own distance (0) is not used for gain")
	# Invalid sources never play and never raise the gain.
	sound.nearby.stop()
	sound.nearby_gain=0.0
	expect(not fire(sound,["a"],{"a":record("fish",ORIGIN)}),"Unsupported tool is silent")
	expect(not fire(sound,["a"],{}),"Actor without a record is silent")
	expect(not fire(sound,["a"],{"a":{"tool":"axe"}}),"Record without a cell is silent")
	expect(not fire(sound,["a"],{"a":{"tool":"axe","cell":"20,20"}}),"Record with a non-cell value is silent")
	expect(not fire(sound,["a"],{"a":record("axe",ORIGIN+Vector2i(9,0))}),"Exactly at the radius is silent")
	expect(not fire(sound,["a"],{"a":record("axe",ORIGIN+Vector2i(30,30))}),"Far away is silent")
	expect(not fire(sound,["a"],{"a":record("axe",ORIGIN)},Vector2(NAN,NAN)),"Non-finite listener is silent")
	expect(not fire(sound,["a"],{"a":record("axe",ORIGIN)},Vector2(INF,0.0)),"Infinite listener is silent")
	expect(not sound.nearby.playing and sound.nearby_gain==0.0,"Invalid sources leave voice idle and gain at zero")
	expect(fire(sound,["a"],{"a":record("axe",ORIGIN+Vector2i(8,0))}),"Just inside the radius is heard")
	expect(absf(sound.nearby_gain-expected_gain(8.0))<0.0005 and sound.nearby_gain>0.0,"Edge gain is small but non-zero")
	finish(sound)

# ------------------------------------------------------- busy and gain bounds

func check_busy_and_gain()->void:
	var sound:=make_sound()
	var previous:=-1.0
	for distance in [8,6,4,2,1,0]:
		sound.nearby.stop()
		fire(sound,["a"],{"a":record("axe",ORIGIN+Vector2i(distance,0))})
		var step_gain:float=sound.nearby_gain
		expect(is_finite(step_gain) and step_gain>=0.0 and step_gain<=Audio.NEARBY_MAX_GAIN+0.0001,"Gain %f within [0,NEARBY_MAX_GAIN] at distance %d"%[step_gain,distance])
		expect(step_gain>previous,"Gain rises as the source gets closer (distance %d)"%distance)
		previous=step_gain
		var ceiling:=Music.to_db(Audio.NEARBY_MAX_GAIN*sound.master_volume*sound.volume)
		expect(sound.nearby.volume_db<=ceiling+EPS,"Voice level %f dB never exceeds %f dB"%[sound.nearby.volume_db,ceiling])
		expect(absf(sound.nearby.volume_db-Music.to_db(step_gain*sound.master_volume*sound.volume))<EPS,"Voice level matches gain, volume and master")
	expect(absf(previous-Audio.NEARBY_MAX_GAIN)<0.0005,"Standing on the source gives exactly NEARBY_MAX_GAIN")
	# The master and effects sliders scale the voice down, never up.
	sound.master_volume=0.5
	sound.volume=0.5
	sound.nearby.stop()
	fire(sound,["a"],{"a":record("axe",ORIGIN)})
	expect(sound.nearby.volume_db<=Music.to_db(Audio.NEARBY_MAX_GAIN)-6.0+EPS,"Half master and half effects scale the voice down")
	# Busy: a second call neither overlaps nor restarts nor changes the voice.
	sound.master_volume=1.0
	sound.volume=1.0
	sound.nearby.stop()
	expect(fire(sound,["a"],{"a":record("pick",ORIGIN+Vector2i(3,0))}),"First tool sound starts")
	var stream:AudioStream=sound.nearby.stream
	var level:float=sound.nearby.volume_db
	var gain:float=sound.nearby_gain
	expect(not fire(sound,["b"],{"b":record("axe",ORIGIN)}),"Busy voice rejects a second (louder, nearer) source")
	expect(sound.nearby.stream==stream and is_equal_approx(sound.nearby.volume_db,level) and sound.nearby_gain==gain,"Busy voice keeps stream, level and gain")
	expect(sound.nearby.playing,"Busy voice keeps playing")
	finish(sound)

# ------------------------------------------------------- burst of other actors

func burst_records()->Dictionary:
	# Seven other actors at different distances using different tools.
	return {
		"p1":record("axe",ORIGIN+Vector2i(5,2)),
		"p2":record("pick",ORIGIN+Vector2i(-4,3)),
		"p3":record("harvest",ORIGIN+Vector2i(2,-2)),
		"p4":record("hoe",ORIGIN+Vector2i(1,1)),
		"p5":record("water",ORIGIN+Vector2i(0,6)),
		"p6":record("build",ORIGIN+Vector2i(-7,0)),
		"p7":record("seed",ORIGIN+Vector2i(4,0)),
		"own":record("axe",ORIGIN),
	}

func check_burst()->void:
	var sound:=make_sound()
	var records:=burst_records()
	var actors:Array=["p1","p2","p3","p4","own","p5","p6","p7"]
	var wins:=0
	for pass_index in range(3):
		sound.nearby.stop()
		var played:=fire(sound,actors,records)
		wins+=int(played)
		expect(played,"Burst of other actors is heard (pass %d)"%pass_index)
		# p4 is the closest valid source. The local action does not compete.
		expect(sound.nearby.stream==sound.sounds.hoe_soil,"Burst plays only the nearest valid source (hoe_soil)")
		expect(absf(sound.nearby_gain-expected_gain(Vector2(1.0,1.0).length()))<0.0005,"Burst gain is that of the nearest source only")
		expect(sound.nearby_gain<=Audio.NEARBY_MAX_GAIN,"Seven actors are not louder than one")
	expect(wins==3,"Every burst produced a sound")
	# The same burst arriving while busy is dropped, not queued or stacked.
	var queued:=0
	for index in range(7):queued+=int(fire(sound,actors,records))
	expect(queued==0,"Burst while busy gives zero extra starts, got %d"%queued)
	# Once the voice ends, it can be heard again (no stuck busy flag).
	sound.nearby.stop()
	expect(fire(sound,["p6"],{"p6":records.p6}) and sound.nearby.stream==sound.sounds.build_set,"Voice is reusable after the previous sound ended")
	finish(sound)

# ------------------------------------------------------- mute and reset

func check_mute_and_reset()->void:
	var sound:=make_sound()
	var near:={"a":record("axe",ORIGIN+Vector2i(1,0))}
	# Master mute stops an in-flight nearby voice via refresh_gains().
	expect(fire(sound,["a"],near) and sound.nearby.playing,"Voice in flight before master mute")
	sound.master_volume=0.0
	sound.refresh_gains()
	expect(not sound.nearby.playing,"Master mute stops the in-flight nearby voice")
	expect(not fire(sound,["a"],near) and not sound.nearby.playing,"Nothing starts while master is muted")
	sound.master_volume=1.0
	sound.refresh_gains()
	# Effects volume to zero does the same.
	expect(fire(sound,["a"],near) and sound.nearby.playing,"Voice in flight before effects mute")
	sound.volume=0.0
	sound.refresh_gains()
	expect(not sound.nearby.playing,"Effects volume zero stops the in-flight nearby voice")
	expect(not fire(sound,["a"],near),"Nothing starts while effects are muted")
	# Unmuting restores audibility and a sane level.
	sound.volume=1.0
	sound.refresh_gains()
	expect(fire(sound,["a"],near) and sound.nearby.playing,"Unmuting lets the voice be heard again")
	# Lowering (not muting) does not cut the sound and keeps it bounded.
	sound.master_volume=0.4
	sound.refresh_gains()
	expect(sound.nearby.playing and sound.nearby.volume_db<=Music.to_db(Audio.NEARBY_MAX_GAIN*0.4)+EPS,"Lowering master keeps the voice but quieter")
	sound.master_volume=1.0
	sound.refresh_gains()
	# stop_cues() resets the voice and its region memory.
	sound.set_world(snap("home",LISTENER.x,LISTENER.y),"own")
	sound.nearby.stop()
	fire(sound,["a"],near)
	sound.stop_cues()
	expect(not sound.nearby.playing,"stop_cues stops the nearby voice")
	expect(sound.nearby_region=="","stop_cues resets the remembered region")
	expect(not sound.player.playing and not sound.footstep_voice.playing,"stop_cues leaves no other voice")
	expect(fire(sound,["a"],near) and sound.nearby.playing,"Nearby voice works after stop_cues")
	sound.close()
	expect(not sound.nearby.playing,"close() also silences the nearby voice")
	finish(sound)

# ------------------------------------------------------- room transitions

func check_room_clearing()->void:
	var sound:=make_sound()
	var near:={"a":record("axe",ORIGIN+Vector2i(1,0))}
	sound.set_world(snap("home",LISTENER.x,LISTENER.y),"own")
	expect(fire(sound,["a"],near) and sound.nearby.playing,"Voice in flight in the home region")
	sound.set_world(snap("home",LISTENER.x+1.0,LISTENER.y),"own")
	expect(sound.nearby.playing,"Walking inside the same open area does not cut the voice")
	sound.set_world(snap("maokong",30.5,30.5),"own")
	expect(not sound.nearby.playing,"A region change clears the nearby voice")
	expect(sound.nearby_region=="maokong","Region change is remembered")
	# Entering a room inside the same region id also clears it.
	var rooms:=[
		{"name":"tea house","region":TeaInterior.REGION,"inside":Vector2(TeaInterior.ROOM.position)+Vector2(5.5,4.5),"outside":Vector2(30.5,30.5)},
		{"name":"pottery workshop","region":PotteryInterior.REGION,"inside":Vector2(PotteryInterior.ROOM.position)+Vector2(5.5,4.5),"outside":Vector2(30.5,30.5)},
		{"name":"warm springs inn","region":Springs.REGION,"inside":Vector2(Springs.INN_ROOM.position)+Vector2(5.5,4.5),"outside":Vector2(30.5,30.5)},
	]
	for room:Dictionary in rooms:
		var region:String=room.region
		sound.set_world(snap(region,room.outside.x,room.outside.y),"own")
		sound.nearby.stop()
		expect(fire(sound,["a"],near) and sound.nearby.playing,"Voice in flight outside the "+str(room.name))
		sound.set_world(snap(region,room.inside.x,room.inside.y),"own")
		expect(not sound.nearby.playing,"Entering the %s clears the nearby voice"%room.name)
		sound.nearby.stop()
		expect(fire(sound,["a"],near) and sound.nearby.playing,"Voice in flight inside the "+str(room.name))
		sound.set_world(snap(region,room.outside.x,room.outside.y),"own")
		expect(not sound.nearby.playing,"Leaving the %s clears the nearby voice"%room.name)
	# Roofed house and greenhouse are rooms too.
	for roof in ["roof","greenhouse_roof"]:
		var roofs:={"40,34":{"type":roof}}
		sound.set_world(snap("home",40.5,34.5),"own")
		sound.nearby.stop()
		fire(sound,["a"],near)
		sound.set_world(snap("home",40.5,34.5,roofs),"own")
		expect(not sound.nearby.playing,"Walking under a %s clears the nearby voice"%roof)
	finish(sound)

# ------------------------------------------------------- ambience

func ambience_silent(sound:Audio)->bool:
	return sound.ambience_kind.is_empty() and not sound.ambience.playing

func ambience_wind(sound:Audio)->bool:
	return sound.ambience_kind=="wind" and sound.ambience.playing and sound.ambience.stream!=null

func check_ambience()->void:
	var sound:=make_sound()
	sound.ambience_volume=0.25
	var outdoors:=snap("home",40.5,34.5)
	sound.set_world(outdoors,"own")
	expect(Music.local_track(outdoors,"home",outdoors.players.own)=="","Test spot in the open is outside any room/zone (it would otherwise be water)")
	expect(ambience_wind(sound),"Outdoors plays wind, got kind '%s'"%sound.ambience_kind)
	expect(sound.ambience.volume_db<=Music.to_db(sound.master_volume*sound.ambience_volume)+EPS,"Wind stays at the ambience level")
	var cases:=[
		{"name":"roofed house","region":"home","roofs":{"40,34":{"type":"roof"}},"inside":Vector2(40.5,34.5),"track":"house_interior"},
		{"name":"greenhouse","region":"home","roofs":{"40,34":{"type":"greenhouse_roof"}},"inside":Vector2(40.5,34.5),"track":"greenhouse_interior"},
		{"name":"public tea house","region":TeaInterior.REGION,"roofs":{},"inside":Vector2(TeaInterior.ROOM.position)+Vector2(5.5,4.5),"track":Music.TEA_HOUSE_TRACK},
		{"name":"pottery workshop","region":PotteryInterior.REGION,"roofs":{},"inside":Vector2(PotteryInterior.ROOM.position)+Vector2(5.5,4.5),"track":Music.POTTERY_WORKSHOP_TRACK},
		{"name":"warm springs inn","region":Springs.REGION,"roofs":{},"inside":Vector2(Springs.INN_ROOM.position)+Vector2(5.5,4.5),"track":Music.INN_TRACK},
	]
	for entry:Dictionary in cases:
		var region:String=entry.region
		var outside:=snap(region,30.5,30.5) if region!="home" else snap("home",40.5,34.5)
		var inside:=snap(region,entry.inside.x,entry.inside.y,entry.roofs)
		expect(Music.local_track(inside,region,inside.players.own)==entry.track,"%s is a room by Music.local_track (%s)"%[entry.name,entry.track])
		# Start outdoors in this region so wind is the baseline, then step in.
		sound.set_world(outside,"own")
		expect(ambience_wind(sound),"Wind outdoors before the "+str(entry.name))
		sound.set_world(inside,"own")
		expect(ambience_silent(sound),"No outdoor ambience inside the %s (kind '%s', playing %s)"%[entry.name,sound.ambience_kind,str(sound.ambience.playing)])
		sound.set_world(inside,"own")
		expect(ambience_silent(sound),"Repeated snapshots inside the %s stay silent"%entry.name)
		sound.set_world(outside,"own")
		expect(ambience_wind(sound),"Back outside the %s resumes wind"%entry.name)
	# A room entered straight from loading (no earlier wind) is silent as well.
	for entry:Dictionary in cases:
		sound.stop_ambience()
		sound.set_world(snap(entry.region,entry.inside.x,entry.inside.y,entry.roofs),"own")
		expect(ambience_silent(sound),"Loading directly into the %s stays silent"%entry.name)
	finish(sound)

# ------------------------------------------------------- real mix capture

func collect(capture:AudioEffectCapture,seconds:float)->Dictionary:
	var peak:=0.0
	var frames:=0
	var clipped:=0
	var left:=seconds
	while left>0.0:
		await create_timer(0.03).timeout
		left-=0.03
		var available:=capture.get_frames_available()
		if available<=0:continue
		var buffer:PackedVector2Array=capture.get_buffer(available)
		frames+=buffer.size()
		for frame in buffer:
			var value:=maxf(absf(frame.x),absf(frame.y))
			peak=maxf(peak,value)
			if value>=1.0 or not is_finite(value):clipped+=1
	return {"frames":frames,"peak":peak,"clipped":clipped}

func check_capture(headless:bool)->void:
	var bus:=AudioServer.get_bus_index("Master")
	var capture:=AudioEffectCapture.new()
	capture.buffer_length=1.2
	AudioServer.add_bus_effect(bus,capture)
	var slot:=AudioServer.get_bus_effect_count(bus)-1
	var sound:=make_sound()
	sound.master_volume=1.0
	sound.volume=1.0
	# Earlier checks stop voices in one frame. Clear their buffered mix before measuring silence.
	await create_timer(0.15).timeout
	capture.clear_buffer()
	var quiet:=await collect(capture,0.18)
	if quiet.frames<256:
		expect(false,"AudioEffectCapture got %d frames, so audibility and clipping were not measured"%quiet.frames)
		AudioServer.remove_bus_effect(bus,slot)
		finish(sound)
		return
	if headless:print("NOTE capture ran on the headless dummy driver; it mixes in software, so levels are valid but the OS device was not exercised.")
	expect(quiet.peak<SILENT_PEAK,"Idle SoftAudio is silent in the mix, peak %f"%quiet.peak)
	# Single nearest source, standing on it: audible, bounded by NEARBY_MAX_GAIN, no clipping.
	capture.clear_buffer()
	expect(fire(sound,["a"],{"a":record("axe",ORIGIN)}),"Capture: nearby axe starts")
	var near:=await collect(capture,0.35)
	expect(near.peak>AUDIBLE_PEAK*5.0,"Nearby axe is audible in the mix, peak %f"%near.peak)
	expect(near.peak<=Audio.NEARBY_MAX_GAIN*0.5,"Nearby axe stays soft in the mix, peak %f"%near.peak)
	expect(near.clipped==0 and near.peak<CLIP_LIMIT,"Nearby axe does not clip")
	# A distant source is still audible but clearly quieter.
	sound.nearby.stop()
	capture.clear_buffer()
	expect(fire(sound,["a"],{"a":record("axe",ORIGIN+Vector2i(6,0))}),"Capture: distant axe starts")
	var far:=await collect(capture,0.35)
	expect(far.peak>AUDIBLE_PEAK,"Distant axe (6 tiles) is still audible, peak %f"%far.peak)
	expect(far.peak<near.peak*0.5,"Distant axe is quieter than the one at your feet (%f vs %f)"%[far.peak,near.peak])
	# Busy repeats do not stack: sustained bursts cannot exceed one voice's level.
	sound.nearby.stop()
	capture.clear_buffer()
	var records:=burst_records()
	var actors:Array=["p1","p2","p3","p4","own","p5","p6","p7"]
	var starts:=0
	var elapsed:=0.0
	while elapsed<0.6:
		starts+=int(fire(sound,actors,records))
		await create_timer(0.03).timeout
		elapsed+=0.03
	var burst:=await collect(capture,0.1)
	expect(starts>=1 and starts<=int(ceil(0.6/0.22))+1,"Burst starts at most one sound per voice cycle, got %d"%starts)
	expect(burst.clipped==0 and burst.peak<CLIP_LIMIT,"Burst of seven actors does not clip, peak %f"%burst.peak)
	# Music, wind, an active machine, the local cue, a footstep and a remote burst.
	capture.clear_buffer()
	sound.music_volume=1.0
	sound.ambience_volume=1.0
	sound.interface_volume=1.0
	sound.refresh_gains()
	if not headless:
		var active:=snap("home",ORIGIN.x+0.5,ORIGIN.y+0.5)
		active.objects={"20,21":{"type":"sawmill","processing":{"active":{"finish":800.0}}}}
		sound.set_world(active,"own")
		expect(sound.machine.playing and sound.music.current.playing and sound.ambience.playing,"Machine, music and ambience join the recorded mix")
		await create_timer(Music.FADE_SECONDS+0.1).timeout
		capture.clear_buffer()
	sound.play_cue("coins_collect",true)
	sound.footstep_voice.stream=sound.sounds.step_wood
	sound.footstep_voice.play()
	sound.nearby.stop()
	fire(sound,actors,records)
	var mixed:=await collect(capture,0.4)
	expect(mixed.peak>AUDIBLE_PEAK*5.0,"Combined mix is audible, peak %f"%mixed.peak)
	expect(mixed.clipped==0 and mixed.peak<CLIP_LIMIT,"Combined mix does not clip, peak %f (limit %f)"%[mixed.peak,CLIP_LIMIT])
	# Muting silences the mix again (nothing left running in the nearby voice).
	sound.nearby.stop()
	fire(sound,["a"],{"a":record("axe",ORIGIN)})
	sound.master_volume=0.0
	sound.refresh_gains()
	await create_timer(0.1).timeout
	capture.clear_buffer()
	var muted:=await collect(capture,0.15)
	expect(muted.peak<SILENT_PEAK*4.0,"Muted playback falls below the noise limit, peak %f"%muted.peak)
	expect(not sound.nearby.playing,"Muted nearby voice is stopped")
	print("NEARBY_TOOLS_AUDIO_MIX %s"%JSON.stringify({"near":near,"far":far,"burst":burst,"mixed":mixed,"muted":muted}))
	AudioServer.remove_bus_effect(bus,slot)
	finish(sound)

func finish(sound:Audio)->void:
	if not is_instance_valid(sound):return
	sound.close()
	sound.get_parent().remove_child(sound)
	sound.free()
