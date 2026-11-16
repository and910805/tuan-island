extends SceneTree
## Runs a dedicated host and isolated client MultiplayerAPIs over real loopback WS.
const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const HEN:=World.CHICKEN_CELL
const BENCH:=HEN+Vector2i.LEFT
const ROOM:="basket-test"
const GROWER:="egg-network-grower"
const FRIEND:="egg-network-friend"
var sessions:Array[Session]=[]
var notices:Dictionary={}
var path:="user://egg-network-%d.json"%OS.get_process_id()
var checks:=0

func _initialize() -> void:
	run.call_deferred()

func make_session(branch_name:String,token:String) -> Session:
	var branch:=Node.new()
	branch.name=branch_name
	root.add_child(branch)
	set_multiplayer(MultiplayerAPI.create_default_interface(),branch.get_path())
	var session:=Session.new()
	branch.add_child(session)
	session.profile={"token":token}
	sessions.append(session)
	notices[session]=[]
	session.notice.connect(func(message:String,ok:bool):notices[session].append({"message":message,"ok":ok}))
	return session

func wait_for(predicate:Callable,seconds:float=10.0) -> bool:
	var deadline:=Time.get_ticks_msec()+int(seconds*1000)
	while not predicate.call() and Time.get_ticks_msec()<deadline:
		await process_frame
	return predicate.call()

func check(condition:bool,message:String) -> bool:
	checks+=1
	if condition:return true
	push_error(message)
	finish(1)
	return false

func finish(code:int) -> void:
	Engine.time_scale=1.0
	for i in range(sessions.size()-1,-1,-1):
		if not sessions[i].shutting_down:sessions[i].shutdown()
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("EGG_BASKET_NETWORK checks=%d exit=%d"%[checks,code])
	quit(code)

func seeded_world() -> bool:
	var world:=World.new()
	world.save_path=path
	for token in [GROWER,FRIEND]:
		world.add_player(token,"Farmer")
		world.state.players[token].x=HEN.x+0.5
		world.state.players[token].y=HEN.y+0.5
	var bag:Dictionary=world.state.players[GROWER].inventory
	bag.wood=8
	bag.fiber=6
	bag.feed=1
	world.state.objects[World.key(BENCH)]={"type":"bench","owner":GROWER,"items":{}}
	return world.save()

func eggs(session:Session) -> int:
	return int(session.snapshot.get("players",{}).get(session.own_id,{}).get("inventory",{}).get("egg",0))

func stored(session:Session) -> int:
	return int(session.snapshot.get("animal",{}).get("basket_eggs",-1))

func action(session:Session,name:String,cell:Vector2i,extra:String="") -> bool:
	var seen:int=notices[session].size()
	session.perform(name,cell,extra)
	if not await wait_for(func():return notices[session].size()>seen):return false
	return notices[session].back().ok

func run() -> void:
	if not check(seeded_world(),"Save a room with a bench and supplies"):return
	var listener:=TCPServer.new()
	if not check(listener.listen(0,"127.0.0.1")==OK,"Allocate a loopback port"):return
	var port:=listener.get_local_port()
	listener.stop()
	var address:="ws://127.0.0.1:%d"%port
	var host:=make_session("Host","egg-network-host")
	if not check(host.host(port,"Host",path,ROOM,"127.0.0.1",true,"websocket")==OK,"Start a dedicated WebSocket room"):return
	var grower:=make_session("Grower",GROWER)
	var friend:=make_session("Friend",FRIEND)
	if not check(grower.join(address,port,"Grower",ROOM)==OK and friend.join(address,port,"Friend",ROOM)==OK,"Connect two WebSocket clients"):return
	if not check(await wait_for(func():return not grower.own_id.is_empty() and not friend.own_id.is_empty()),"Both clients entered the island"):return
	if not check(await action(grower,"craft",BENCH,"egg_basket"),"Craft through the remote workbench"):return
	if not check(await action(grower,"install_egg_basket",HEN),"Install through the remote chicken panel action"):return
	if not check(await action(grower,"feed",HEN),"Feed the chicken once"):return
	if not check(stored(friend)==0 and float(host.world.state.animal.egg_ready)>float(host.world.state.time),"Disconnect before the egg is due"):return
	grower.shutdown()
	if not check(await wait_for(func():return host.peers.size()==1),"Host saw the original grower disconnect"):return
	Engine.time_scale=10.0
	if not check(await wait_for(func():return stored(friend)==1,15.0),"Remaining player sees exactly one egg reach the basket"):return
	Engine.time_scale=1.0
	var returned:=make_session("Returned",GROWER)
	if not check(returned.join(address,port,"Grower",ROOM)==OK,"Reconnect the original profile"):return
	if not check(await wait_for(func():return stored(returned)==1),"Reconnected client sees the one pending egg"):return
	var returned_notices:int=notices[returned].size()
	var friend_notices:int=notices[friend].size()
	returned.perform("egg",HEN)
	friend.perform("egg",HEN)
	if not check(await wait_for(func():return notices[returned].size()>returned_notices and notices[friend].size()>friend_notices),"Both remote claims were answered"):return
	if not check(await wait_for(func():return stored(returned)==0 and stored(friend)==0 and eggs(returned)+eggs(friend)==1),"Both clients agree that only one egg was collected"):return
	if not check(notices[returned].back().ok!=notices[friend].back().ok,"Exactly one player won the claim"):return
	var saved:=World.new()
	if not check(saved.load_world(path) and int(saved.state.animal.basket_eggs)==0 and int(saved.state.players[GROWER].inventory.get("egg",0))+int(saved.state.players[FRIEND].inventory.get("egg",0))==1,"The room save contains precisely one awarded egg"):return
	finish(0)
