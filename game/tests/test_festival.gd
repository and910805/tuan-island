extends SceneTree
const World=preload("res://scripts/world.gd")
const Festival=preload("res://scripts/festival.gd")
const Schema=preload("res://scripts/save_schema.gd")
var w
var checks:=0
var failures:=0
var seq:=0
func expect(value:bool,message:String) -> void:
	checks+=1
	if not value:failures+=1;push_error("FAIL "+message)
func act(who:String,action:String,p:Vector2i,extra:String="") -> Dictionary:
	seq+=1
	return w.act(who,"festival-%d"%seq,action,p,extra)
func near(who:String,cell:Vector2i) -> void:
	w.state.players[who].x=cell.x+0.5;w.state.players[who].y=cell.y+0.5
func collect(who:String) -> Dictionary:
	var p:=Festival.target(w.state.festival)
	near(who,p)
	return act(who,"festival_collect",p,Festival.ticket(w.state.festival))
func valid(s:Dictionary) -> bool:return Schema.validate(s,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)
func _initialize() -> void:
	w=World.new();w.add_player("alice","米");w.add_player("bob","豆")
	var board:=Vector2i(40,29)
	near("alice",board)
	expect(not act("alice","festival_start",board,"0").ok,"picnic required")
	w.state.picnic=true;w.state.board=true
	expect(act("alice","festival_start",board,"0").ok,"first cooperative round starts")
	expect(not act("alice","festival_start",board,"0").ok,"another click cannot reset progress")
	for cell in Festival.STOPS:expect(w.protected(cell) and not w.blocked(cell),"bell uses clear protected public tile")
	var point:=Festival.target(w.state.festival)
	var ticket:=Festival.ticket(w.state.festival)
	near("alice",Vector2i(39,33))
	expect(not act("alice","festival_collect",point,ticket).ok,"collection cannot happen remotely")
	expect(collect("alice").ok,"first player collects first bell")
	near("bob",point)
	expect(not act("bob","festival_collect",point,ticket).ok,"two players cannot claim the same bell")
	expect(w.state.festival.collected==1,"contested pickup advances only once")
	var path:="user://festival-test-%d.json"%Time.get_ticks_usec()
	w.save_path=path;expect(w.save(),"active party saves")
	var loaded=World.new();expect(loaded.load_world(path),"active party resumes after restart")
	w=loaded;w.add_player("alice","米");w.add_player("bob","豆")
	expect(w.state.festival.collected==1,"restart retains shared progress")
	for i in range(1,11):expect(collect("alice" if i%2==0 else "bob").ok,"relay advances with alternating contributors")
	var before:Dictionary=w.state.duplicate(true)
	w.save_path="user://missing-festival-save-folder/world.json"
	expect(not collect("bob").ok,"failed disk write rejects final pickup")
	expect(w.state.festival.collected==11 and w.state.festival.active,"failed finish retains active party")
	expect(w.state.players.alice.coins==before.players.alice.coins and w.state.players.bob.coins==before.players.bob.coins,"failed finish pays nobody")
	w.save_path=path
	w.active_tokens.erase("alice")
	w.step(60,true)
	expect(collect("bob").ok,"last bell completes even when a participant went offline")
	expect(not w.state.festival.active and w.state.festival.collected==12,"finish state persisted")
	expect(w.state.players.alice.coins==152 and w.state.players.bob.coins==152,"both contributors paid exactly once including offline player")
	expect(not act("bob","festival_collect",Festival.STOPS[0],"1:11").ok,"finished party cannot pay again")
	near("bob",board)
	expect(not act("bob","festival_start",board,"1").ok,"repeat round cooldown enforced")
	w.step(301,false)
	expect(not act("bob","festival_start",board,"1").ok,"empty world pauses cooldown")
	w.step(301,true)
	expect(not act("bob","festival_start",board,"0").ok,"stale start cannot launch a later round")
	expect(act("bob","festival_start",board,"1").ok,"next round starts after active world cooldown")
	expect(w.state.festival.collected==0 and w.state.festival.contributors.is_empty(),"new round resets contribution count")
	expect(w.state.festival.best==60.0,"personal best survives next round")
	expect(valid(w.state.duplicate(true)),"valid party passes nested save validation")
	var bad:Dictionary=w.state.duplicate(true);bad.festival.collected=5
	expect(not valid(bad),"mismatched contribution sum rejected")
	bad=w.state.duplicate(true);bad.festival.contributors={"unknown":1};bad.festival.collected=1
	expect(not valid(bad),"unknown participant rejected")
	bad=w.state.duplicate(true);bad.erase("festival")
	expect(valid(bad) and bad.festival.round==0,"older world migrates to empty party without losing data")
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("FESTIVAL_TESTS checks=%d failures=%d"%[checks,failures])
	quit(0 if failures==0 else 1)
