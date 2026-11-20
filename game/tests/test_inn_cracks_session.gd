extends "res://tests/network_egg_basket.gd"

const Springs=World.WARM_SPRINGS
const Goals=World.RESIDENT_GOALS
const RESIDENT:=World.RESIDENT_BOND.SPRING_CELL

func finish(code:int) -> void:
	for index in range(sessions.size()-1,-1,-1):
		if not sessions[index].shutting_down:sessions[index].shutdown()
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("INN_CRACK_SESSION_TESTS checks=%d failures=%d"%[checks,int(code!=0)])
	quit(code)

func place(host:Session,token:String,tile:Vector2i) -> void:
	var person:Dictionary=host.world.state.players[token]
	person.x=tile.x+0.5
	person.y=tile.y+0.5

func seed_crack_room(path_name:String) -> bool:
	var world:=World.new()
	world.save_path=path_name
	for token:String in [GROWER,FRIEND]:
		world.add_player(token,token)
		var person:Dictionary=world.state.players[token]
		person.region=Springs.REGION
		person.x=RESIDENT.x+0.5
		person.y=RESIDENT.y+0.5
		person.bonds={"nuannuan":{"points":6,"gift_day":-1,"talk_day":-1}}
		person.inventory.clay=8
		person.inventory.stone=12
	return world.save()

func mark(host:Session,client:Session,token:String,index:int) -> bool:
	var tile:Vector2i=Springs.CRACK_SITES[index]
	place(host,token,tile)
	return await action(client,Springs.CRACK_ACTION,tile)

func report(host:Session,client:Session,token:String) -> bool:
	place(host,token,RESIDENT)
	return await action(client,Goals.ACTION,RESIDENT,"nuannuan:2::")

func run() -> void:
	path="user://inn-cracks-network-%d.json"%OS.get_process_id()
	if not check(seed_crack_room(path),"Save both players at the start of the pool story"):return
	var listener:=TCPServer.new()
	if not check(listener.listen(0,"127.0.0.1")==OK,"Allocate a loopback port"):return
	var port:=listener.get_local_port()
	listener.stop()
	var host:=make_session("CrackHost","inn-cracks-host")
	if not check(host.host(port,"礁溪",path,ROOM,"127.0.0.1",true,"websocket")==OK,"Start a WebSocket host"):return
	host.set_physics_process(false)
	var owner:=make_session("CrackOwner",GROWER)
	var friend:=make_session("CrackFriend",FRIEND)
	var address:="ws://127.0.0.1:%d"%port
	if not check(owner.join(address,port,"先來的旅客",ROOM)==OK and friend.join(address,port,"後來的旅客",ROOM)==OK,"Connect both clients"):return
	if not check(await wait_for(func():return Springs.crack_survey_open(owner.snapshot) and Springs.crack_survey_open(friend.snapshot)),"Both see the open survey"):return
	if not check(not await action(owner,Springs.CRACK_ACTION,Springs.CRACK_SITES[2]),"Cannot mark a crack from the resident's spot"):return
	if not check(await mark(host,owner,GROWER,2),"Owner marks the steps first"):return
	if not check(await wait_for(func():return owner.snapshot.get("own_inn_cracks",0)==4) and friend.snapshot.get("own_inn_cracks",0)==0,"Each client sees their own marks"):return
	if not check(not await report(host,owner,GROWER),"Cannot pay to repair with only one mark"):return
	var players:Dictionary=host.world.state.players
	if not check(players[GROWER].inventory.clay==8 and players[GROWER].inventory.stone==12,"Rejected repair leaves materials in the bag"):return
	if not check(await mark(host,owner,GROWER,0) and await mark(host,owner,GROWER,1),"Owner finishes their survey"):return
	if not check(await report(host,owner,GROWER),"Owner repairs the public pool"):return
	if not check(await wait_for(func():return friend.snapshot.get(Springs.BATH_KEY,false)),"Friend sees the repaired pool in the shared world"):return
	if not check(not await report(host,friend,FRIEND),"Public repair does not finish the friend's survey"):return
	for index in [1,2,0]:
		if not check(await mark(host,friend,FRIEND,index),"Friend can still inspect joint %d in the repaired pool"%index):return
	if not check(await report(host,friend,FRIEND),"Friend completes their own story after the first public repair"):return
	for client:Session in [owner,friend]:
		for person:Dictionary in client.snapshot.get("players",{}).values():
			if not check(not person.has(Springs.CRACK_KEY),"Public player entry omits the private marks"):return
	var loaded:=World.new()
	if not check(loaded.load_world(path) and loaded.state.get(Springs.BATH_KEY,false),"Public pool state survives reloading"):return
	for token:String in [GROWER,FRIEND]:
		var saved:Dictionary=loaded.state.players[token]
		if not check(int(saved.get(Springs.CRACK_KEY,0))==Springs.CRACK_MASK and Goals.done(saved,"nuannuan").has(2),"Both marks and story survive reloading"):return
		if not check(saved.inventory.clay==0 and saved.inventory.stone==0,"Each player paid the materials exactly once"):return
	finish(0)
