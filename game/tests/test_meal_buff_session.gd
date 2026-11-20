extends "res://tests/network_egg_basket.gd"
## D03: the meal-buff slot and the stamina carry are private. A dedicated host and two isolated
## WebSocket clients: the owner sees its own effect, a visitor's view of the owner omits both fields,
## and the visitor's own slot is independent.

func finish(code:int) -> void:
	for i in range(sessions.size()-1,-1,-1):
		if not sessions[i].shutting_down:sessions[i].shutdown()
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("MEAL_BUFF_SESSION_TESTS checks=%d failures=%d"%[checks,code])
	quit(code)

func run() -> void:
	path="user://meal-buff-session-%d.json"%OS.get_process_id()
	var world:=World.new()
	world.save_path=path
	for token in [GROWER,FRIEND]:
		world.add_player(token,"Diner")
	var mine:Dictionary=world.state.players[GROWER]
	world.state.time=100.0
	mine[World.MEAL_BUFF.FIELD]={"id":"salad","until":400.0}
	mine[World.MEAL_BUFF.FRAC_FIELD]=10
	mine.mine_energy=91
	if not check(world.save(),"Save a room with one active salad effect"):return
	var listener:=TCPServer.new()
	if not check(listener.listen(0,"127.0.0.1")==OK,"Allocate a loopback port"):return
	var port:=listener.get_local_port()
	listener.stop()
	var address:="ws://127.0.0.1:%d"%port
	var host:=make_session("Host","meal-network-host")
	if not check(host.host(port,"Host",path,ROOM,"127.0.0.1",true,"websocket")==OK,"Start a dedicated room"):return
	var owner:=make_session("Owner",GROWER)
	var visitor:=make_session("Visitor",FRIEND)
	if not check(owner.join(address,port,"Owner",ROOM)==OK and visitor.join(address,port,"Visitor",ROOM)==OK,"Connect two clients"):return
	if not check(await wait_for(func():return not owner.own_id.is_empty() and visitor.snapshot.get("players",{}).has(owner.own_id)),"Both islanders appear together"):return
	var id:=owner.own_id
	if not check(await wait_for(func():return owner.snapshot.get("players",{}).get(id,{}).has(World.MEAL_BUFF.FIELD)),"The owner sees its own effect"):return
	var own:Dictionary=owner.snapshot.players[id]
	if not check(own[World.MEAL_BUFF.FIELD].get("id")=="salad" and int(own[World.MEAL_BUFF.FRAC_FIELD])==10,"The owner's view carries the effect and the carry"):return
	var seen:Dictionary=visitor.snapshot.players[id]
	if not check(not seen.has(World.MEAL_BUFF.FIELD) and not seen.has(World.MEAL_BUFF.FRAC_FIELD),"A visitor's view of the owner omits the effect and the carry"):return
	if not check(not visitor.snapshot.players[visitor.own_id].has(World.MEAL_BUFF.FIELD),"The visitor's own slot is independent and empty"):return
	visitor.shutdown()
	owner.shutdown()
	host.shutdown()
	finish(0)
