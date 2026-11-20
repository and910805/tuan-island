extends "res://tests/network_egg_basket.gd"
## D07 multiplayer: two real clients race to adopt the shared 奶糖牛 over a dedicated WS room.
const L=preload("res://scripts/livestock.gd")
const SITE:=Vector2i(48,35)

func finish(code:int)->void:
	for index in range(sessions.size()-1,-1,-1):
		if not sessions[index].shutting_down:sessions[index].shutdown()
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("COW_ADOPTION_SESSION checks=%d exit=%d"%[checks,code])
	quit(code)

func coins(session:Session)->int:
	return int(session.snapshot.get("players",{}).get(session.own_id,{}).get("coins",-1))

func run()->void:
	path=OS.get_environment("TEMP").path_join("cow-adoption-network-%s.json"%Crypto.new().generate_random_bytes(10).hex_encode())
	var fee:int=L.ADOPTION_COST.cow
	var fixture:=World.new()
	fixture.save_path=path
	fixture.state.picnic=true
	for token in [GROWER,FRIEND]:
		fixture.add_player(token,"領養者")
		fixture.state.players[token].x=48.5
		fixture.state.players[token].y=37.5
		fixture.state.players[token].inventory.feed=1
	if not check(not fixture.state.livestock.has("cow") and fixture.save(),"Save a new world with no cow record"):return
	var listener:=TCPServer.new()
	if not check(listener.listen(0,"127.0.0.1")==OK,"Allocate loopback port"):return
	var port:=listener.get_local_port()
	listener.stop()
	var host:=make_session("AdoptHost","adopt-host")
	if not check(host.host(port,"牧場",path,ROOM,"127.0.0.1",true,"websocket")==OK,"Start real dedicated WS room"):return
	var one:=make_session("AdoptOne",GROWER)
	var two:=make_session("AdoptTwo",FRIEND)
	var address:="ws://127.0.0.1:%d"%port
	if not check(one.join(address,port,"領養者",ROOM)==OK and two.join(address,port,"領養者",ROOM)==OK,"Join two independent clients"):return
	if not check(await wait_for(func():return not one.own_id.is_empty() and not two.own_id.is_empty()),"Both clients entered"):return
	var start_one:=coins(one)
	var start_two:=coins(two)
	if not check(start_one>=fee and start_two>=fee,"Both clients can afford the early fee"):return
	if not check(not await action(one,"livestock_feed",SITE,"cow"),"A client cannot feed an unadopted cow"):return
	if not check(not host.world.state.livestock.has("cow"),"The refused feed created no record"):return
	one.perform("livestock_adopt",SITE,"cow")
	two.perform("livestock_adopt",SITE,"cow")
	if not check(await wait_for(func():return notices[one].size()>=2 and notices[two].size()>=1),"Both simultaneous adoptions answer"):return
	if not check(int(notices[one].back().ok)+int(notices[two].back().ok)==1,"Exactly one racing client adopts"):return
	if not check(await wait_for(func():return one.snapshot.livestock.has("cow") and two.snapshot.livestock.has("cow")),"Both clients see the one shared cow"):return
	if not check(await wait_for(func():return coins(one)+coins(two)==start_one+start_two-fee),"The fee is charged exactly once across both clients"):return
	var loser=two if coins(one)<start_one else one
	if not check(await action(loser,"livestock_feed",SITE,"cow"),"The client who did not pay can feed the shared cow"):return
	if not check(not await action(loser,"livestock_adopt",SITE,"cow"),"A late adopter is refused as already adopted"):return
	if not check(coins(one)+coins(two)==start_one+start_two-fee,"Refusals charge no coins"):return
	if not check(int(host.world.state.livestock.cow.feed)==1,"The shared cow keeps the friend's feed"):return
	var saved:=World.new()
	if not check(saved.load_world(path) and saved.state.livestock.has("cow") and int(saved.state.livestock.cow.feed)==1,"The adoption is persisted by the dedicated room"):return
	finish(0)
