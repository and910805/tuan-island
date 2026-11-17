extends "res://tests/network_egg_basket.gd"
const Shelter=preload("res://scripts/sheep_shelter.gd")
const SITE:=Vector2i(50,35)
func finish(code:int)->void:
	for index in range(sessions.size()-1,-1,-1):
		if not sessions[index].shutting_down:sessions[index].shutdown()
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("SHEEP_SHELTER_SESSION checks=%d exit=%d"%[checks,code])
	quit(code)
func send_all(host)->void:
	for peer in host.peers:host._send_snapshot(peer)
func run()->void:
	path=OS.get_environment("TEMP").path_join("sheep-shelter-network-%s.json"%Crypto.new().generate_random_bytes(10).hex_encode())
	var fixture:=World.new()
	fixture.save_path=path
	fixture.state.picnic=true
	fixture.state.time=2870.0
	for token in [GROWER,FRIEND]:
		fixture.add_player(token,"照料者")
		fixture.state.players[token].x=50.5
		fixture.state.players[token].y=36.5
	fixture.state.players[GROWER].bonds={"mianmian":{"points":6,"talk_day":-1,"gift_day":-1}}
	if not check(fixture.save(),"Save normal stock, friendship and standing fixture"):return
	var listener:=TCPServer.new()
	if not check(listener.listen(0,"127.0.0.1")==OK,"Allocate loopback port"):return
	var port:=listener.get_local_port()
	listener.stop()
	var host:=make_session("RainHost","rain-host")
	if not check(host.host(port,"雨棚",path,ROOM,"127.0.0.1",true,"websocket")==OK,"Start real WS dedicated host"):return
	host.set_physics_process(false)
	var grower:=make_session("RainOne",GROWER)
	var friend:=make_session("RainTwo",FRIEND)
	var address:="ws://127.0.0.1:%d"%port
	if not check(grower.join(address,port,"搭棚者",ROOM)==OK and friend.join(address,port,"旁觀者",ROOM)==OK,"Join two independent clients"):return
	if not check(await wait_for(func():return not grower.own_id.is_empty() and not friend.own_id.is_empty()),"Both enter"):return
	if not check(await action(grower,World.RESIDENT_GOALS.SHEEP_SHELTER_ACTION,SITE,"shelter"),"Build actual shelter over WS"):return
	if not check(await action(grower,World.RESIDENT_GOALS.SHEEP_SHELTER_ACTION,SITE,"mat"),"Build actual mat over WS"):return
	if not check(await wait_for(func():return friend.snapshot.get("sheep_comfort_fixtures",0)==3),"Observer receives shared fixtures"):return
	var owner:Dictionary=host.world.state.players[GROWER]
	if not check(int(owner.inventory.wood)==8 and int(owner.inventory.fiber)==7,"Only original construction cost deducted"):return
	if not check(friend.snapshot.get("own_sheep_corner",0)==0,"Observer receives no personal project credit"):return
	var first:=Shelter.new()
	var second:=Shelter.new()
	first.observe(grower.snapshot,0.0)
	second.observe(friend.snapshot,0.0)
	if not check(host.world.step(11.0,true),"Advance actual authoritative weather into rain"):return
	send_all(host)
	if not check(await wait_for(func():return float(grower.snapshot.get("time",0))>=2880 and float(friend.snapshot.get("time",0))>=2880),"Both receive rainy world time"):return
	first.observe(grower.snapshot,1.0)
	second.observe(friend.snapshot,1.0)
	if not check(first.offset(2.1,false)==second.offset(2.1,false) and first.offset(2.1,false).x>0,"Both observers take the same shelter route"):return
	first.observe(grower.snapshot,1.5)
	if not check(first.offset(2.1,false)==second.offset(2.1,false),"Duplicate wire snapshot does not restart"):return
	if not check(second.offset(1.0,true)==Vector2(32,0),"Quiet client shares the same sheltered destination"):return
	friend.shutdown()
	if not check(await wait_for(func():return host.peers.size()==1),"Host notices observer leaving"):return
	var returned:=make_session("RainReturned",FRIEND)
	if not check(returned.join(address,port,"回來的旁觀者",ROOM)==OK,"Reconnect same profile"):return
	if not check(await wait_for(func():return not returned.own_id.is_empty() and returned.snapshot.get("sheep_comfort_fixtures",0)==3),"Reconnect receives fixtures and rain"):return
	var rejoined:=Shelter.new()
	rejoined.observe(returned.snapshot,4.0)
	if not check(rejoined.offset(4.0,false)==Vector2(32,0) and not rejoined.walking(4.0,false),"Reconnect starts sheltered without replay"):return
	var loaded:=World.new()
	if not check(loaded.load_world(path) and int(loaded.state.players[GROWER].get(World.RESIDENT_GOALS.SHEEP_SHELTER_KEY,0))==3,"Built fixtures persist in the existing save format"):return
	finish(0)
