extends SceneTree
## Standalone test for the shy mushroom cues. Preloads only the pure Shy module and the audio
## script (no World/Session/SoftAudio); `main` and `sound` are tiny stand-ins.
## This checks the sample data and the player plumbing. It cannot judge how the cues sound.

const Shy=preload("res://scripts/shy_mushroom.gd")
const ShyAudio=preload("res://scripts/shy_mushroom_audio.gd")
const CUES:=["shy_rustle","shy_peek","shy_splash","shy_open"]
var checks:=0
var failures:=0

func expect(ok:bool,message:String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)

func _initialize() -> void:
	check_ids()
	check_streams()
	check_determinism()
	# The root window only enters the tree once the main loop is running.
	await process_frame
	check_gain_and_play()
	await check_play_all()
	print("SHY_MUSHROOM_AUDIO_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func make_node(source:String) -> Node:
	var script:=GDScript.new()
	script.source_code=source
	script.reload()
	var node:=Node.new()
	node.set_script(script)
	return node

func make_main(level:float) -> Node:
	var main:=make_node("extends Node\nvar sound:Node\n")
	var sound:=make_node("extends Node\nvar level:=0.0\nvar asked:=\"\"\nvar player=null\nvar cue_kind:=\"\"\nfunc cue_gain(kind:String) -> float:\n\tasked=kind\n\treturn level\n")
	sound.set("level",level)
	main.add_child(sound)
	main.set("sound",sound)
	return main

func voice_of(main:Node) -> AudioStreamPlayer:
	return main.get("sound").get_node_or_null(ShyAudio.PLAYER_NAME) as AudioStreamPlayer

func check_ids() -> void:
	expect(ShyAudio.PLAYER_NAME=="ShyMushroomCue","Player node name")
	expect(CUES==[Shy.CUE_RUSTLE,Shy.CUE_PEEK,Shy.CUE_SPLASH,Shy.CUE_OPEN],"Cue ids match the rules module")
	for cue in CUES:
		expect(ShyAudio.valid_cue(cue),"%s is valid"%cue)
	for cue in ["","action","shy","shy_rustle ","SHY_PEEK","water_pour"]:
		expect(not ShyAudio.valid_cue(cue),"'%s' is not valid"%cue)
		expect(ShyAudio.make_stream(cue)==null,"'%s' has no stream"%cue)

func peak_of(data:PackedByteArray) -> float:
	var peak:=0
	for i in range(0,data.size(),2):
		peak=maxi(peak,absi(data.decode_s16(i)))
	return peak/32767.0

## Largest sample-to-sample step: a click shows up as a jump far above the cue's own slope.
func jump_of(data:PackedByteArray) -> float:
	var jump:=0
	var last:=0
	for i in range(0,data.size(),2):
		var value:=data.decode_s16(i)
		jump=maxi(jump,absi(value-last))
		last=value
	return jump/32767.0

func zero_crossings(data:PackedByteArray) -> int:
	var count:=0
	var last:=0
	for i in range(0,data.size(),2):
		var value:=data.decode_s16(i)
		if value!=0:
			if last!=0 and (value>0)!=(last>0):count+=1
			last=value
	return count

func check_streams() -> void:
	ShyAudio.reset_cache()
	var seen:Array[PackedByteArray]=[]
	for cue in CUES:
		var stream:=ShyAudio.make_stream(cue) as AudioStreamWAV
		expect(stream!=null,"%s builds a WAV stream"%cue)
		if stream==null:continue
		expect(stream.format==AudioStreamWAV.FORMAT_16_BITS and stream.mix_rate==22050 and not stream.stereo,"%s is 22050 Hz 16-bit mono"%cue)
		expect(stream.loop_mode==AudioStreamWAV.LOOP_DISABLED,"%s does not loop"%cue)
		var data:=stream.data
		var seconds:=data.size()/2.0/22050.0
		expect(data.size()%2==0 and seconds>=0.15 and seconds<=0.7,"%s lasts %.2fs (0.15..0.7)"%[cue,seconds])
		expect(is_equal_approx(stream.get_length(),seconds),"%s reports its length"%cue)
		var peak:=peak_of(data)
		expect(peak>=0.05 and peak<=0.35,"%s peak %.3f is audible but modest"%[cue,peak])
		expect(absf(peak-float(ShyAudio.PEAKS[cue]))<0.002,"%s is normalized to its target peak"%cue)
		expect(absi(data.decode_s16(0))<=64 and absi(data.decode_s16(data.size()-2))<=64,"%s starts and ends at silence"%cue)
		# Tones move smoothly; the rustle is noise, so only its faded edges can be checked.
		if cue!=Shy.CUE_RUSTLE:expect(jump_of(data)<peak*0.6,"%s has no click-sized jumps"%cue)
		var edge:=int(22050*0.002)*2
		expect(peak_of(data.slice(0,edge))<peak*0.5 and peak_of(data.slice(data.size()-edge))<peak*0.2,"%s fades in and out"%cue)
		expect(ShyAudio.make_stream(cue)==stream,"%s is cached"%cue)
		for other in seen:
			expect(other!=data,"%s differs from the earlier cues"%cue)
		seen.append(data)
	# The cues differ in character, not just bytes: noise vs tones, and their lengths.
	var rustle:=(ShyAudio.make_stream(Shy.CUE_RUSTLE) as AudioStreamWAV).data
	var peek:=(ShyAudio.make_stream(Shy.CUE_PEEK) as AudioStreamWAV).data
	var splash:=(ShyAudio.make_stream(Shy.CUE_SPLASH) as AudioStreamWAV).data
	var open:=(ShyAudio.make_stream(Shy.CUE_OPEN) as AudioStreamWAV).data
	var rustle_rate:=zero_crossings(rustle)/(rustle.size()/2.0)
	var peek_rate:=zero_crossings(peek)/(peek.size()/2.0)
	expect(rustle_rate>peek_rate*2.0,"Rustle is noisy, peek is tonal")
	expect(open.size()>peek.size() and peek.size()>splash.size(),"Open is the longest cue, splash the shortest")
	expect(splash.size()/2.0/22050.0<=ShyAudio.STAGGER,"Splash finishes before the staggered open cue starts")
	# Splash falls in pitch: more zero crossings in its first 40 ms than in the next 40 ms.
	var window:=int(22050*0.04)*2
	expect(zero_crossings(splash.slice(0,window))>zero_crossings(splash.slice(window,window*2)),"Splash droplet descends")
	# Peek rises: its second note crosses zero more often than its first.
	var first:=zero_crossings(peek.slice(int(22050*0.02)*2,int(22050*0.10)*2))
	var second:=zero_crossings(peek.slice(int(22050*0.18)*2,int(22050*0.26)*2))
	expect(second>first,"Peek rises from its first note to its second")

func check_determinism() -> void:
	var before:Dictionary={}
	for cue in CUES:
		before[cue]=(ShyAudio.make_stream(cue) as AudioStreamWAV).data.duplicate()
	ShyAudio.reset_cache()
	expect(ShyAudio._streams.is_empty(),"reset_cache forgets the streams")
	for cue in CUES:
		var rebuilt:=ShyAudio.make_stream(cue) as AudioStreamWAV
		expect(rebuilt.data==before[cue],"%s rebuilds byte-identical"%cue)

func check_gain_and_play() -> void:
	# Nothing to play on: all quiet no-ops.
	expect(ShyAudio.gain(null)==0.0,"Null main has no gain")
	ShyAudio.play(null,Shy.CUE_PEEK)
	ShyAudio.play_all(null,[Shy.CUE_SPLASH,Shy.CUE_OPEN])
	var bare:=Node.new()
	expect(ShyAudio.gain(bare)==0.0,"A main without a sound node has no gain")
	ShyAudio.play(bare,Shy.CUE_PEEK)
	ShyAudio.play_all(bare,[Shy.CUE_SPLASH,Shy.CUE_OPEN])
	bare.free()
	expect(ShyAudio.gain(bare)==0.0,"A freed main has no gain")
	ShyAudio.play(bare,Shy.CUE_PEEK)
	ShyAudio.play_all(bare,[Shy.CUE_PEEK])
	expect(true,"play and play_all survive null, bare and freed mains")
	# Muted: no player is created.
	var muted:=make_main(0.0)
	root.add_child(muted)
	expect(ShyAudio.gain(muted)==0.0,"Zero volume gives zero gain")
	ShyAudio.play(muted,Shy.CUE_PEEK)
	expect(voice_of(muted)==null,"Muted play creates no player")
	muted.get("sound").set("level",NAN)
	expect(ShyAudio.gain(muted)==0.0,"A non-finite volume is treated as off")
	muted.free()
	# Audible.
	var main:=make_main(0.25)
	root.add_child(main)
	expect(is_equal_approx(ShyAudio.gain(main),0.25),"Gain follows the sound node")
	expect(main.get("sound").get("asked")==ShyAudio.GAIN_KIND,"Gain asks for the chime family")
	ShyAudio.play(main,"not_a_cue")
	expect(voice_of(main)==null,"An invalid cue creates no player")
	ShyAudio.play(main,Shy.CUE_PEEK)
	var voice:=voice_of(main)
	expect(voice!=null and voice.stream==ShyAudio.make_stream(Shy.CUE_PEEK),"Play creates the named player with the cue stream")
	expect(voice!=null and is_equal_approx(voice.volume_db,linear_to_db(0.25)),"Player volume follows the gain")
	ShyAudio.play(main,Shy.CUE_RUSTLE)
	expect(voice_of(main)==voice and voice.stream==ShyAudio.make_stream(Shy.CUE_RUSTLE),"The same player is reused for the next cue")
	expect(main.get("sound").get_child_count()==1,"Only one player is ever added")
	ShyAudio.play(main,"not_a_cue")
	expect(voice.stream==ShyAudio.make_stream(Shy.CUE_RUSTLE),"An invalid cue leaves the player alone")
	main.get("sound").set("level",0.0)
	ShyAudio.play(main,Shy.CUE_OPEN)
	expect(not voice.playing and voice.stream==ShyAudio.make_stream(Shy.CUE_RUSTLE),"Muting stops the player instead of starting a cue")
	main.free()

func check_play_all() -> void:
	var main:=make_main(0.25)
	root.add_child(main)
	ShyAudio.play_all(main,[])
	ShyAudio.play_all(main,["nope",7,null])
	expect(voice_of(main)==null,"play_all with nothing valid plays nothing")
	ShyAudio.play_all(main,["nope",Shy.CUE_SPLASH,Shy.CUE_OPEN])
	var voice:=voice_of(main)
	expect(voice!=null and voice.stream==ShyAudio.make_stream(Shy.CUE_SPLASH),"The first valid cue plays at once")
	await create_timer(ShyAudio.STAGGER*0.5).timeout
	expect(voice.stream==ShyAudio.make_stream(Shy.CUE_SPLASH),"The second cue waits for its stagger")
	await create_timer(ShyAudio.STAGGER).timeout
	expect(voice.stream==ShyAudio.make_stream(Shy.CUE_OPEN),"The second cue plays after the stagger")
	# Three in a row, each one stagger later than the last.
	ShyAudio.play_all(main,[Shy.CUE_RUSTLE,Shy.CUE_PEEK,Shy.CUE_OPEN])
	expect(voice.stream==ShyAudio.make_stream(Shy.CUE_RUSTLE),"A new sequence starts at once")
	await create_timer(ShyAudio.STAGGER*1.5).timeout
	expect(voice.stream==ShyAudio.make_stream(Shy.CUE_PEEK),"Second of three")
	await create_timer(ShyAudio.STAGGER).timeout
	expect(voice.stream==ShyAudio.make_stream(Shy.CUE_OPEN),"Third of three")
	# Main freed while a staggered cue is still pending.
	ShyAudio.play_all(main,[Shy.CUE_SPLASH,Shy.CUE_OPEN])
	main.free()
	await create_timer(ShyAudio.STAGGER*1.5).timeout
	expect(not is_instance_valid(main),"A pending cue is dropped quietly when main is freed")
	# Outside the tree only the first cue plays and no timer is needed.
	var loose:=make_main(0.25)
	ShyAudio.play(loose,Shy.CUE_PEEK)
	ShyAudio.play_all(loose,[Shy.CUE_PEEK,Shy.CUE_OPEN])
	expect(voice_of(loose)==null,"Outside the scene tree nothing is created or played")
	loose.free()
