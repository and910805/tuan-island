extends SceneTree
const Session=preload("res://scripts/session.gd")
var session:Node
var done:=false
var failures:=0
var label_name:="bot"
var address:="127.0.0.1"
func _initialize() -> void:
	call_deferred("run")
func expect(value:bool,description:String) -> void:
	if not value:
		failures+=1
		push_error("FAIL "+description)
func run() -> void:
	var island:=Node2D.new()
	island.name="Island"
	root.add_child(island)
	session=Session.new()
	island.add_child(session)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--profile="):label_name=arg.trim_prefix("--profile=")
		if arg.begins_with("--address="):address=arg.trim_prefix("--address=")
	session.connected_world.connect(exercise)
	session.notice.connect(func(message:String,success:bool):print("RESPONSE ",success," ",message))
	session.join(address,28551,label_name,"integration-key")
	await create_timer(12).timeout
	if not done:push_error("NETWORK_TIMEOUT");quit(1)
func exercise() -> void:
	await create_timer(0.6).timeout
	var s:Dictionary=session.snapshot
	expect(s.players.has(session.own_id),"own player received")
	expect(s.players.size()==2,"two real clients share world")
	for id in s.players:
		expect(not s.players[id].has("receipts"),"request history is private")
		if id!=session.own_id:expect(not s.players[id].has("inventory"),"other inventory is private")
	var before:int=s.players[session.own_id].inventory.wood
	session.perform("build",Vector2i(38,34),"floor")
	await create_timer(0.4).timeout
	# Replay the same network sequence; it must not perform a second action.
	session.request_action.rpc_id(1,1,"build",Vector2i(38,35),"floor","home",0)
	session.perform("build",Vector2i(2,2),"wall")
	await create_timer(0.4).timeout
	s=session.snapshot
	expect(s.ground.has("38,34"),"both clients observe the winning placement")
	expect(not s.ground.has("38,35"),"replayed network sequence rejected")
	var after:int=s.players[session.own_id].inventory.wood
	expect(after==before or after==before-2,"only winning builder pays")
	var x_before:float=s.players[session.own_id].x
	session.input_direction(Vector2.RIGHT)
	await create_timer(1.8).timeout
	var x_after:float=session.snapshot.players[session.own_id].x
	expect(x_after-x_before<1.8,"stale movement stops without key-up packet")
	expect(x_after>x_before,"real network input moved player")
	print("NETWORK_TEST ",label_name," failures=",failures," wood=",after," delta=",x_after-x_before)
	done=true
	session.shutdown()
	quit(0 if failures==0 else 1)
