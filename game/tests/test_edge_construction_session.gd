extends "res://tests/network_egg_basket.gd"
## Two independent clients observe authoritative wall actions in a local WebSocket room.
const SITE:=Vector2i(38,38)
const EDGE:="38,38,N"

func finish(code:int)->void:
	for index in range(sessions.size()-1,-1,-1):
		if not sessions[index].shutting_down:sessions[index].shutdown()
	for suffix in ["",".bak",".tmp",".writer-lock"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("EDGE_CONSTRUCTION_SESSION checks=%d failures=%d exit=%d"%[checks,int(code!=0),code])
	quit(code)

func run()->void:
	path=OS.get_environment("TEMP").path_join("edge-network-%s.json"%Crypto.new().generate_random_bytes(10).hex_encode())
	var fixture:=World.new()
	fixture.save_path=path
	for token in [GROWER,FRIEND]:
		fixture.add_player(token,"建屋島民",Vector2(SITE)+Vector2(0.5,0.5))
		fixture.state.players[token].inventory.merge({"wood":20,"fiber":10,"glass":2},true)
	for y in range(SITE.y-1,SITE.y+2):
		for x in range(SITE.x-1,SITE.x+2):
			fixture.state.removed[World.key(Vector2i(x,y))]=true
	if not check(fixture.save(),"Save empty isolated construction world"):return
	var listener:=TCPServer.new()
	if not check(listener.listen(0,"127.0.0.1")==OK,"Allocate loopback"):return
	var port:=listener.get_local_port()
	listener.stop()
	var host:=make_session("EdgeHost","edge-host")
	if not check(host.host(port,"施工測試",path,ROOM,"127.0.0.1",true,"websocket")==OK,"Dedicated WebSocket host"):return
	var one:=make_session("EdgeOne",GROWER)
	var two:=make_session("EdgeTwo",FRIEND)
	var addr:="ws://127.0.0.1:%d"%port
	if not check(one.join(addr,port,"木匠",ROOM)==OK and two.join(addr,port,"鄰居",ROOM)==OK,"Both clients request admission"):return
	if not check(await wait_for(func():return not one.own_id.is_empty() and not two.own_id.is_empty()),"Both clients entered"):return
	if not check(await action(one,"build_edge",SITE,"edge_door|0"),"The first client builds a door"):return
	if not check(await wait_for(func():return one.snapshot.edges.has(EDGE) and two.snapshot.edges.has(EDGE)),"Both see the same closed door"):return
	if not check(not one.snapshot.edges[EDGE].open and two.snapshot.edges[EDGE].owner==one.own_id,"Snapshot contains the public owner and closed state"):return
	if not check(await action(two,"toggle_edge",SITE,"0"),"The neighbor can open it"):return
	if not check(await wait_for(func():return one.snapshot.edges.get(EDGE,{}).get("open",false) and two.snapshot.edges.get(EDGE,{}).get("open",false)),"Both clients see the door open"):return
	if not check(not await action(two,"remove_edge",SITE,"0"),"The neighbor cannot dismantle another player's door"):return
	var loaded:=World.new()
	if not check(loaded.load_world(path) and loaded.state.edges.get(EDGE,{}).get("open",false),"Door and state survive loading the host's actual save"):return
	if not check(await action(one,"remove_edge",SITE,"0"),"Owner removes door"):return
	if not check(await wait_for(func():return not one.snapshot.edges.has(EDGE) and not two.snapshot.edges.has(EDGE)),"Removal synchronizes to both clients"):return
	if not await verify_edge_blueprint_rpc(one,two):return
	finish(0)

func verify_edge_blueprint_rpc(one:Session,two:Session) -> bool:
	var quote_events:Array[Dictionary]=[]
	var apply_events:Array[Dictionary]=[]
	one.blueprint_quoted.connect(func(_id:int,value:Dictionary):quote_events.append(value))
	one.blueprint_applied.connect(func(_nonce:String,value:Dictionary):apply_events.append(value))
	var design:={"version":2,"name":"連線木窗","width":1,"height":1,"pieces":[
		{"kind":"edge_window","x":0,"y":0,"settings":{"side":0}}]}
	# A clockwise turn converts N to E, where neither resident stands.
	one.quote_blueprint(design,SITE,1)
	if not check(await wait_for(func():return not quote_events.is_empty()),"Version 2 plan receives a real remote quote"):return false
	var quoted:Dictionary=quote_events.back()
	if not check(quoted.ok and quoted.cost=={"glass":1,"wood":4},"Remote quote charges exact new window cost"):return false
	one.submit_blueprint("5463750914f34824a259a97063257999",design,SITE,1,quoted.hash)
	if not check(await wait_for(func():return not apply_events.is_empty()),"Version 2 plan receives a remote apply response"):return false
	if not check(apply_events.back().ok,"Remote apply accepts the version 2 payload"):return false
	var edge_key:=World.EDGE_GRID.key(SITE,1)
	return check(await wait_for(func():return two.snapshot.edges.get(edge_key,{}).get("type")=="edge_window"),"The other client receives the correctly rotated edge")
