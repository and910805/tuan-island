extends SceneTree

const World=preload("res://scripts/world.gd")
const Feedback=preload("res://scripts/fishing_feedback.gd")
const WATER:=Vector2i(55,34)
const TARGET:=Vector2(55.5,34.5)
var world:=World.new()
var feedback:=Feedback.new()
var checks:=0
var failures:=0

func expect(condition:bool,detail:String) -> void:
	checks+=1
	if not condition:
		failures+=1
		push_error(detail)

func snapshot(elapsed:float,region:String="home") -> void:
	var data:=world.region_snapshot(region)
	for actor_id in data.players:
		if actor_id!="alice":data.players[actor_id].erase("inventory")
	feedback.update(data,"alice",elapsed)

func state_for(actor:String,elapsed:float) -> Dictionary:
	return feedback.state_for(actor,float(world.state.time),elapsed)

func phase(actor:String,elapsed:float) -> String:
	return state_for(actor,elapsed).get("phase","")

func _initialize() -> void:
	for actor in ["alice","bob"]:
		world.add_player(actor,actor)
		world.state.players[actor].x=54.5
		world.state.players[actor].y=34.5
	snapshot(0.0)
	expect(phase("alice",0.0)=="","No event at first idle snapshot")
	expect(world.act("alice","cast","fish_start",WATER).ok,"Local cast succeeds")
	snapshot(0.1)
	expect(phase("alice",0.1)=="cast" and state_for("alice",0.1).target==TARGET,"Cast targets the water cell center")
	expect(not world.act("alice","early","fish_catch",WATER).ok,"Early reel fails")
	snapshot(0.2)
	expect(phase("alice",0.7)=="wait","Duplicate state does not restart cast animation")
	expect(is_equal_approx(state_for("alice",0.7).get("landing_age",-1.0),0.18),"Splash starts when cast reaches water")
	expect(not state_for("alice",0.9).has("landing_age"),"Splash expires while the float is still waiting")
	expect(world.act("bob","remote-cast","fish_start",WATER).ok,"Remote cast succeeds")
	snapshot(0.8)
	expect(phase("bob",0.8)=="cast" and phase("alice",0.8)=="wait","Remote cast is independent")
	expect(world.step(3.1,true),"Advance gameplay to bite threshold")
	snapshot(3.9)
	expect(phase("alice",3.9)=="ready" and phase("bob",3.9)=="ready","Ready phase follows world time")
	expect(state_for("alice",3.9).age==0.0,"The bite starts when first observed")
	snapshot(3.95)
	expect(is_equal_approx(state_for("alice",3.95).age,0.05),"A repeated ready snapshot preserves the bite animation time")
	expect(world.act("alice","catch","fish_catch",WATER).ok and world.act("bob","remote-catch","fish_catch",WATER).ok,"Both catches succeed")
	snapshot(4.0)
	expect(phase("alice",4.0)=="catch" and state_for("alice",4.0).fish=="carp","Local catch resolves authoritative inventory delta")
	expect(phase("bob",4.0)=="catch" and state_for("bob",4.0).fish=="","Remote catch does not infer hidden inventory")
	snapshot(4.3)
	expect(phase("alice",4.9)=="catch" and phase("alice",5.01)=="" and phase("bob",5.01)=="","Catch lasts through its animation, then expires despite repeated snapshots")
	var path:=OS.get_environment("TEMP").path_join("fishing-feedback-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	world.save_path=path
	expect(world.save(),"Persist gameplay after both catches")
	var reopened:=World.new()
	if reopened.load_world(path):
		world=reopened
	else:
		expect(false,"Reload saved gameplay")
	if FileAccess.file_exists(path):DirAccess.remove_absolute(path)
	world.save_path=""
	feedback.reset()
	snapshot(5.0)
	expect(phase("alice",5.0)=="" and phase("bob",5.0)=="","Initial reconnect with prior catches does not replay")
	expect(world.act("alice","next-cast","fish_start",WATER).ok,"Second local cast succeeds")
	snapshot(5.1)
	world.move_player("alice",Vector2.LEFT,0.1)
	snapshot(5.2)
	expect(phase("alice",5.2)=="cancel" and state_for("alice",5.2).target==TARGET,"Movement is cancellation at the former target")
	expect(phase("alice",5.7)=="" and int(world.state.players.alice.fish_caught)==1,"Cancel expires and adds no catch")
	expect(world.act("alice","region-cast","fish_start",WATER).ok,"Cast before region change")
	snapshot(5.8)
	snapshot(5.9,"jinguashi")
	expect(phase("alice",5.9)=="","Region change clears active events")
	snapshot(6.0)
	expect(phase("alice",6.0)=="wait" and not state_for("alice",6.0).has("landing_age"),"Returning view uses ongoing cast without replay")
	expect(world.step(3.1,true) and world.act("alice","second-catch","fish_catch",WATER).ok,"Second real catch succeeds")
	world.state.players.alice.travel_epoch+=1
	snapshot(9.1)
	expect(phase("alice",9.1)=="","Actor travel epoch invalidates old cast")
	expect(world.act("bob","peer-cast","fish_start",WATER).ok,"Remote casts again")
	snapshot(9.2)
	expect(world.step(3.1,true) and world.act("bob","peer-catch","fish_catch",WATER).ok,"Remote catches again")
	var data:=world.region_snapshot("home")
	data.players.bob.peer=99
	feedback.update(data,"alice",12.3)
	expect(phase("bob",12.3)=="","A new remote peer does not replay a catch from the old connection")
	print("FISHING_FEEDBACK_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
