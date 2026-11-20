extends "res://tests/network_egg_basket.gd"

const Goals=World.RESIDENT_GOALS
const OWNER:="aru-rest-owner"
const GUEST:="aru-rest-guest"
const ARRIVAL:="aru-rest-arrival"

func finish(code:int) -> void:
	for index in range(sessions.size()-1,-1,-1):
		if not sessions[index].shutting_down:sessions[index].shutdown()
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("ARU_REST_SESSION_TESTS checks=%d failures=%d"%[checks,int(code!=0)])
	quit(code)

func seed_island() -> bool:
	var world:=World.new()
	world.save_path=path
	var site:Vector2i=World.bond_place(world.state,"aru")[1]
	for token in [OWNER,GUEST,ARRIVAL]:
		world.add_player(token,token)
		var person:Dictionary=world.state.players[token]
		person.x=site.x+0.5
		person.y=site.y+1.5
	world.state.players[OWNER].bonds={"aru":{"points":14,"talk_day":-1,"gift_day":-1}}
	return world.save()

func sitters(client:Session) -> Dictionary:
	return client.snapshot.get("aru_bench_scene",{}).get("sitters",{})

func position(host:Session,token:String) -> Vector2:
	var person:Dictionary=host.world.state.players[token]
	return Vector2(person.x,person.y)

func run() -> void:
	path="user://aru-rest-loopback-%d.json"%OS.get_process_id()
	if not check(seed_island(),"Save an island with a trusted host and two visitors"):return
	var listener:=TCPServer.new()
	if not check(listener.listen(0,"127.0.0.1")==OK,"Allocate a loopback port"):return
	var port:=listener.get_local_port()
	listener.stop()
	var host:=make_session("AruServer","aru-rest-network-host")
	if not check(host.host(port,"渡口",path,ROOM,"127.0.0.1",true,"websocket")==OK,"Start the WebSocket host"):return
	var owner:=make_session("AruOwner",OWNER)
	var guest:=make_session("AruGuest",GUEST)
	var arrival:=make_session("AruArrival",ARRIVAL)
	var address:="ws://127.0.0.1:%d"%port
	if not check(owner.join(address,port,"約阿榆",ROOM)==OK and guest.join(address,port,"訪客",ROOM)==OK and arrival.join(address,port,"島民",ROOM)==OK,"Join with three clients"):return
	if not check(await wait_for(func():return not owner.own_id.is_empty() and not guest.own_id.is_empty() and not arrival.own_id.is_empty()),"All islanders receive their own snapshots"):return
	var site:Vector2i=World.bond_place(host.world.state,"aru")[1]
	var guest_before:=position(host,GUEST)
	if not check(not await action(guest,Goals.ARU_REST_ACTION,site),"A visitor cannot join before a trusted islander starts"):return
	if not check(await action(owner,Goals.ARU_REST_ACTION,site),"The trusted islander takes a physical seat"):return
	if not check(await wait_for(func():return sitters(guest).get(owner.own_id,-1)==0),"A nearby visitor sees the host's seat"):return
	if not check(position(host,GUEST)==guest_before and not sitters(guest).has(guest.own_id),"Receiving the invitation leaves the visitor standing"):return
	if not check(await action(guest,Goals.ARU_REST_ACTION,site),"The visitor opts in"):return
	if not check(await wait_for(func():return sitters(owner).get(guest.own_id,-1)==1 and sitters(arrival).size()==2),"Other clients agree that the guest took the second seat"):return
	if not check(position(host,OWNER).distance_to(position(host,GUEST))>=0.45,"The people occupy different places in the scene"):return
	if not check(not sitters(arrival).has(OWNER) and not sitters(arrival).has(GUEST),"The snapshot only carries the public player IDs"):return
	if not check(not host.world.state.players[GUEST].has(Goals.ARU_REST_KEY),"A visiting guest does not complete the main story"):return
	if not check(not await action(arrival,Goals.ARU_REST_ACTION,site) and sitters(arrival).size()==2,"A full bench keeps both existing seats"):return

	var guest_id:=guest.own_id
	guest.shutdown()
	if not check(await wait_for(func():return not sitters(owner).has(guest_id)),"Disconnect frees the visitor's seat"):return
	if not check(await action(arrival,Goals.ARU_REST_ACTION,site),"A nearby islander can take the freed seat"):return
	if not check(await wait_for(func():return sitters(owner).get(arrival.own_id,-1)==1),"The replacement is visible to the primary sitter"):return
	owner.input_direction(Vector2.DOWN)
	var stood:=await wait_for(func():return not sitters(owner).has(owner.own_id),3.0)
	owner.input_direction(Vector2.ZERO)
	if not check(stood,"Walking puts the primary islander back on their feet"):return
	if not check(host.world.state.players[OWNER].has(Goals.ARU_REST_KEY),"Standing keeps the private story prerequisite"):return
	if not check(await action(owner,Goals.ACTION,site,"aru:3::"),"Report the completed rest over WebSocket"):return
	if not check(World.Village.unlocked(host.world.state.players[OWNER],"sign") and not World.Village.unlocked(host.world.state.players[ARRIVAL],"sign"),"Only the islander who reported gets engraving progress"):return
	if not check(not await action(owner,Goals.ACTION,site,"aru:3::"),"The reward cannot be collected twice"):return
	var before_attempt:=position(host,OWNER)
	host.world.save_path=path.path_join("unwritable.json")
	var failed:Dictionary=host.world.act(OWNER,"force-save-failure",Goals.ARU_REST_ACTION,site)
	host.world.save_path=path
	if not check(not failed.ok and position(host,OWNER)==before_attempt and host.world.aru_bench_scene().is_empty(),"A failed save rolls back both the seat and the moved position"):return
	var saved:=World.new()
	if not check(host.world.save() and saved.load_world(path) and Goals.done(saved.state.players[OWNER],"aru").has(3),"The finished story reloads"):return
	finish(0)
