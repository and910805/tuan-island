extends SceneTree

const World=preload("res://scripts/world.gd")
const Audio=preload("res://scripts/fishing_audio.gd")
const WATER:=Vector2i(55,34)
var world:=World.new()
var tracker:=Audio.new()
var checks:=0
var failures:=0

func expect(condition:bool,detail:String) -> void:
	checks+=1
	if not condition:
		failures+=1
		push_error(detail)

func update(own_id:String="alice",region:String="home") -> Array[String]:
	return tracker.update(world.region_snapshot(region),own_id)

func _initialize() -> void:
	for actor in ["alice","bob"]:
		world.add_player(actor,actor)
		world.state.players[actor].x=54.5
		world.state.players[actor].y=34.5
	expect(update().is_empty(),"First snapshot is quiet")
	expect(world.act("bob","cast","fish_start",WATER).ok and update().is_empty(),"Remote cast is quiet")
	expect(world.act("alice","cast","fish_start",WATER).ok and update()==["fish_cast"],"Local cast plays once")
	expect(update().is_empty(),"Repeated cast snapshot is quiet")
	expect(world.step(2.9,true) and update().is_empty(),"Waiting before readiness is quiet")
	expect(world.step(0.2,true) and update()==["fish_bite"],"Crossing the world readiness threshold plays one local bite")
	expect(update().is_empty(),"Repeated ready snapshot is quiet")
	expect(world.act("bob","catch","fish_catch",WATER).ok and update().is_empty(),"Remote catch is quiet")
	expect(world.act("alice","catch","fish_catch",WATER).ok and update()==["fish_catch"],"Local catch plays once")
	expect(update().is_empty(),"Repeated catch snapshot is quiet")
	expect(world.act("alice","mute-cast","fish_start",WATER).ok,"Cast while muted")
	update()
	expect(update().is_empty(),"Discarding the cue while muted consumes it")
	world.move_player("alice",Vector2.LEFT,0.1)
	expect(update()==["fish_cancel"] and update().is_empty(),"Moving away plays one empty-line retract cue")

	expect(world.act("alice","baseline-cast","fish_start",WATER).ok,"Cast before reconnect")
	tracker.reset()
	expect(update().is_empty(),"An already active cast is a quiet baseline")
	expect(world.step(3.1,true) and update().is_empty(),"Baseline cast does not produce a historical bite")
	expect(world.act("alice","baseline-catch","fish_catch",WATER).ok and update()==["fish_catch"],"A newly completed catch after baseline still plays")
	expect(world.act("alice","region-cast","fish_start",WATER).ok and update()==["fish_cast"],"Start before a region change")
	expect(update("alice","jinguashi").is_empty() and update().is_empty(),"Leaving and returning to region are quiet")
	expect(world.step(3.1,true) and update().is_empty(),"Region re-entry suppresses the old bite")
	expect(world.act("alice","region-catch","fish_catch",WATER).ok and update("bob").is_empty() and update().is_empty(),"Switching local identity is quiet")

	expect(world.act("alice","rollback-cast","fish_start",WATER).ok and update()==["fish_cast"],"Start before world rollback")
	var rolled_back:=world.region_snapshot("home")
	rolled_back.time-=0.1
	rolled_back.players.alice.erase("fishing")
	rolled_back.players.alice.fish_caught+=1
	expect(tracker.update(rolled_back,"alice").is_empty(),"A time rollback never replays an apparent catch")
	var peer_changed:=world.region_snapshot("home")
	peer_changed.players.alice.peer=42
	expect(tracker.update(peer_changed,"alice").is_empty(),"Peer replacement establishes a quiet baseline")
	expect(update("").is_empty() and update().is_empty(),"Missing own identity clears pending cues")
	print("FISHING_AUDIO_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
