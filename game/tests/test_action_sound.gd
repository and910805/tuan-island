extends SceneTree

const Audio=preload("res://scripts/soft_audio.gd")
const Step=Audio.Footsteps
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
	var sound:=Audio.new()
	root.add_child(sound)
	var cues:=Audio.HAND_CUES.duplicate()
	cues.append_array(Audio.PORTER_CUES)
	cues.append(Audio.JOURNAL_PAGE)
	for surface:String in Step.SURFACES:cues.append("step_"+surface)
	var distinct:Dictionary={}
	for cue:String in cues:
		var bytes:PackedByteArray=sound.sounds[cue].data
		var peak:=0
		for n in range(0,bytes.size(),2):peak=maxi(peak,absi(bytes.decode_s16(n)))
		expect(peak>900 and peak<11000 and bytes.decode_s16(0)==0 and absi(bytes.decode_s16(bytes.size()-2))<=2,"Clean audible waveform for "+cue)
		distinct[bytes.hex_encode().sha256_text()]=true
	expect(distinct.size()==cues.size(),"Surfaces and hand actions each have a distinct sound")
	var porter_actions:Array=Audio.World.PORTER.ACTIONS
	for index in range(porter_actions.size()):
		expect(Audio.action_cue(porter_actions[index],"")==Audio.PORTER_CUES[index],"Escort stage maps to its own sound")
	var snapshot:={"region_id":"home","players":{"own":{"travel_epoch":0,"peer":1}},
		"ground":{"40,34":{"type":"floor"},"43,34":{"type":"path"}},"crops":{"42,34":{}},
		"board":true}
	var tracker:=Step.new()
	expect(tracker.advance(snapshot,"own",Vector2(40.05,34.5),true).is_empty(),"Initial footstep baseline is quiet")
	for index in range(10):
		expect(tracker.advance(snapshot,"own",Vector2(40.05,34.5),true).is_empty(),"Holding against an obstacle does not walk")
	expect(tracker.advance(snapshot,"own",Vector2(40.55,34.5),true)=="wood","Actual distance triggers a wood step")
	expect(tracker.advance(snapshot,"own",Vector2(42.55,34.5),true).is_empty(),"Position corrections do not create a footstep")
	expect(tracker.advance(snapshot,"own",Vector2(42.77,34.5),false).is_empty(),"Stopped input is quiet")
	expect(tracker.advance(snapshot,"own",Vector2(42.1,34.5),true).is_empty() and tracker.advance(snapshot,"own",Vector2(42.6,34.5),true)=="soil","Tilled plots sound like loose soil")
	snapshot.players.own.travel_epoch=1
	expect(tracker.advance(snapshot,"own",Vector2(43.4,34.5),true).is_empty() and tracker.advance(snapshot,"own",Vector2(43.9,34.5),true)=="stone","Travel resets cadence and the paved path sounds like stone")
	expect(Step.surface(snapshot,"home",{},Vector2(55.5,30.5))=="wood","Repaired bridge is timber")
	expect(Step.surface(snapshot,"home",{},Vector2(47.5,56.5))=="sand","Beach uses the sand voice")
	expect(Step.surface(snapshot,"mine_2",{},Vector2(20.5,20.5))=="stone","The mine floor uses stone")
	expect(Step.surface(snapshot,"home",{},Vector2(42.5,48.5))=="grass","Open grassy ground uses the soft tread")
	sound.play_cue("fish_cast")
	sound.update_footsteps(snapshot,"own",Vector2(40.1,34.5),true)
	sound.update_footsteps(snapshot,"own",Vector2(40.6,34.5),true)
	expect(sound.footstep_voice.stream==sound.sounds.step_wood and sound.player.stream==sound.sounds.fish_cast,"Footsteps and fishing can play independently")
	await create_timer(0.06).timeout
	sound.master_volume=0
	sound.refresh_gains()
	expect(not sound.footstep_voice.playing and not sound.player.playing,"Master mute stops active effects")
	sound.master_volume=1.0
	var mill:=Audio.World.MILL_RESTORATION
	expect(Audio.action_cue(mill.SERVICE,"")=="machine_start" and Audio.action_cue(mill.SERVICE,"",true)=="machine_claim","Public milling uses different start and pickup sounds")
	var near:={"x":mill.APPROACH.x+0.5,"y":mill.APPROACH.y+0.5}
	var public_mill:={"region_id":"home",mill.BUSY:true,mill.SITE_VISIBLE:true,"time":10.0}
	sound.update_machine(public_mill,near)
	var porch_gain:=sound.machine_gain
	expect(sound.machine_kind=="waterwheel" and porch_gain>0.0,"A working shared mill has a waterwheel sound near the entrance")
	sound.update_machine(public_mill,{"x":near.x+3.0,"y":near.y})
	expect(sound.machine_kind=="waterwheel" and sound.machine_gain<porch_gain,"The mill sounds quieter farther from the entrance")
	sound.update_machine(public_mill,{"x":near.x+10.0,"y":near.y})
	expect(sound.machine_kind.is_empty(),"Leaving the mill area stops the sound")
	sound.update_machine(public_mill,near)
	public_mill[mill.BUSY]=false
	sound.update_machine(public_mill,near)
	expect(sound.machine_kind.is_empty(),"A finished batch does not keep the wheel sound running")
	await create_timer(0.10).timeout
	sound.close()
	expect(sound.footsteps.context.is_empty(),"Leaving the world clears the step origin")
	sound.queue_free()
	await create_timer(0.20).timeout
	print("ACTION_SOUND_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
