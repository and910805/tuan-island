extends "res://tests/network_egg_basket.gd"
## T066 N06-3 over real loopback WebSocket: the sewn toy's shape and completion stay private.
const Goals=World.RESIDENT_GOALS
const Art=preload("res://scripts/mianmian_toy_art.gd")
func finish(code:int)->void:
	for index in range(sessions.size()-1,-1,-1):
		if not sessions[index].shutting_down:sessions[index].shutdown()
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("MIANMIAN_TOY_SESSION checks=%d exit=%d"%[checks,code])
	quit(code)
func send_all(host)->void:
	for peer in host.peers:host._send_snapshot(peer)
func run()->void:
	path=OS.get_environment("TEMP").path_join("mianmian-toy-network-%s.json"%Crypto.new().generate_random_bytes(10).hex_encode())
	var fixture:=World.new()
	fixture.save_path=path
	fixture.state.picnic=true
	for token in [GROWER,FRIEND]:
		fixture.add_player(token,"縫玩具的人")
		fixture.state.players[token].x=HEN.x+2.5
		fixture.state.players[token].y=HEN.y+0.5
		fixture.state.players[token].bonds={"mianmian":{"points":14,"talk_day":-1,"gift_day":-1}}
		fixture.state.players[token].inventory.cotton_cloth=3
		fixture.state.players[token].inventory.fiber=4
	fixture.state.players[GROWER].companion_dog={"following":true,"bond":0,"last_pet":-30.0}
	if not check(fixture.save(),"Save normal stock, friendship and standing fixture"):return
	var listener:=TCPServer.new()
	if not check(listener.listen(0,"127.0.0.1")==OK,"Allocate loopback port"):return
	var port:=listener.get_local_port()
	listener.stop()
	var host:=make_session("ToyHost","toy-host")
	if not check(host.host(port,"玩具",path,ROOM,"127.0.0.1",true,"websocket")==OK,"Start real WS dedicated host"):return
	host.set_physics_process(false)
	var owner:=make_session("ToyOne",GROWER)
	var friend:=make_session("ToyTwo",FRIEND)
	var address:="ws://127.0.0.1:%d"%port
	if not check(owner.join(address,port,"縫的人",ROOM)==OK and friend.join(address,port,"旁觀者",ROOM)==OK,"Join two independent clients"):return
	if not check(await wait_for(func():return not owner.own_id.is_empty() and not friend.own_id.is_empty()),"Both enter"):return
	var state:Dictionary=host.world.state
	var cell:Vector2i=World.bond_place(owner.snapshot,"mianmian")[1]
	state.players[GROWER].x=cell.x+0.5
	state.players[GROWER].y=cell.y+0.5
	if not check(not await action(owner,Goals.ACTION,cell,"mianmian:3::"),"A shape must be chosen"):return
	if not check(await action(owner,Goals.ACTION,cell,"mianmian:3:doll:"),"Owner sews the doll over WS"):return
	var bag:Dictionary=state.players[GROWER].inventory
	if not check(int(bag.get("cotton_cloth",0))==0 and int(bag.get("fiber",0))==0,"Exactly 3 cloth and 4 fiber are spent"):return
	if not check(await wait_for(func():return Art.choice(owner.snapshot)=="doll"),"Owner receives the chosen shape"):return
	if not check(not await action(owner,Goals.ACTION,cell,"mianmian:3:ball:"),"Second report is refused"):return
	send_all(host)
	await process_frame
	await process_frame
	if not check(Art.choice(friend.snapshot).is_empty() and friend.snapshot.resident_goals.mianmian["3"].state!="done","Observer sees neither shape nor completion"):return
	if not check(int(state.players[FRIEND].inventory.cotton_cloth)==3,"Observer inventory untouched"):return
	state.players[GROWER].x=World.Dog.SITE.x+0.5
	state.players[GROWER].y=World.Dog.SITE.y+0.5
	if not check(await action(owner,"dog_toy",World.Dog.SITE) and int(state.players[GROWER].companion_dog.bond)==1,"Existing dog toy action plays once"):return
	if not check(not await action(owner,"dog_toy",World.Dog.SITE),"Existing cooldown still applies"):return
	owner.shutdown()
	if not check(await wait_for(func():return host.peers.size()==1),"Host sees owner leave"):return
	var returned:=make_session("ToyReturned",GROWER)
	if not check(returned.join(address,port,"回來的人",ROOM)==OK,"Reconnect owner"):return
	if not check(await wait_for(func():return not returned.own_id.is_empty() and Art.choice(returned.snapshot)=="doll"),"Reconnect keeps the shape"):return
	var loaded:=World.new()
	if not check(host.world.save() and loaded.load_world(path) and Goals.done(loaded.state.players[GROWER],"mianmian").has(3),"Completion persists in the existing save format"):return
	finish(0)
