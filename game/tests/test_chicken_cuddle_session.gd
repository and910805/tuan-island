extends "res://tests/network_egg_basket.gd"
const Care=World.CHICKEN_CUDDLE
func finish(code:int)->void:
	for index in range(sessions.size()-1,-1,-1):
		if not sessions[index].shutting_down:sessions[index].shutdown()
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("CHICKEN_CUDDLE_SESSION checks=%d exit=%d"%[checks,code])
	quit(code)
func broadcast(host)->void:
	for peer in host.peers:host._send_snapshot(peer)
func run()->void:
	path=OS.get_environment("TEMP").path_join("chicken-cuddle-network-%s.json"%Crypto.new().generate_random_bytes(10).hex_encode())
	var fixture:=World.new()
	fixture.save_path=path
	for token in [GROWER,FRIEND]:
		fixture.add_player(token,"抱抱者")
		fixture.state.players[token].x=45.5
		fixture.state.players[token].y=35.5
	if not check(fixture.save(),"Normal inventory and valid standing fixture saved"):return
	var listener:=TCPServer.new()
	if not check(listener.listen(0,"127.0.0.1")==OK,"Allocate loopback port"):return
	var port:=listener.get_local_port()
	listener.stop()
	var host:=make_session("CuddleHost","cuddle-host")
	if not check(host.host(port,"抱抱",path,ROOM,"127.0.0.1",true,"websocket")==OK,"Start dedicated WebSocket host"):return
	host.set_physics_process(false)
	var first:=make_session("CuddleOne",GROWER)
	var second:=make_session("CuddleTwo",FRIEND)
	var address:="ws://127.0.0.1:%d"%port
	if not check(first.join(address,port,"第一位",ROOM)==OK and second.join(address,port,"第二位",ROOM)==OK,"Join two isolated client APIs"):return
	if not check(await wait_for(func():return not first.own_id.is_empty() and not second.own_id.is_empty()),"Both clients enter"):return
	first.perform(Care.ACTION,HEN)
	second.perform(Care.ACTION,HEN)
	if not check(await wait_for(func():return notices[first].size()>0 and notices[second].size()>0),"Simultaneous requests both receive acknowledgements"):return
	if not check(int(notices[first].back().ok)+int(notices[second].back().ok)==1 and host.world.state.animal.bond==1,"Only one shared chicken and one bond"):return
	if not check(await wait_for(func():return not Care.holder(first.snapshot).is_empty() and Care.holder(first.snapshot)==Care.holder(second.snapshot)),"Both snapshots agree on exactly one holder"):return
	var held_id:=Care.holder(first.snapshot)
	if not check(held_id.length()==16 and first.snapshot.players.has(held_id),"Holder is an existing public actor id"):return
	if not check(not JSON.stringify(first.snapshot).contains(GROWER) and not JSON.stringify(first.snapshot).contains(FRIEND),"Private profile tokens never cross snapshot wire"):return
	var winner=first if held_id==first.own_id else second
	var loser=second if winner==first else first
	if not check(not await action(loser,Care.RELEASE,HEN),"Observer cannot release another player's hen"):return
	if not check(not await action(winner,"hoe",Vector2i(44,35)),"Server rejects hand tool while held"):return
	if not check(await action(winner,Care.RELEASE,HEN),"Owner can release through actual RPC"):return
	if not check(await wait_for(func():return Care.holder(loser.snapshot).is_empty()),"Observer sees release"):return
	if not check(not await action(winner,Care.ACTION,HEN),"Release cannot bypass cooldown"):return
	if not check(host.world.step(30.1,true),"Advance actual care cooldown"):return
	broadcast(host)
	if not check(await action(first,Care.ACTION,HEN),"First client claims after cooldown"):return
	first.shutdown()
	if not check(await wait_for(func():return host.peers.size()==1),"Host sees holding client disconnect"):return
	broadcast(host)
	if not check(await wait_for(func():return Care.holder(second.snapshot).is_empty()) and not host.world.state.animal.has(Care.FIELD),"Disconnect returns hen for remaining client"):return
	var returned:=make_session("CuddleReturned",GROWER)
	if not check(returned.join(address,port,"回來的照料者",ROOM)==OK,"Reconnect original profile"):return
	if not check(await wait_for(func():return not returned.own_id.is_empty()),"Reconnect enters"):return
	if not check(Care.holder(returned.snapshot).is_empty() and not await action(returned,Care.ACTION,HEN),"Reconnect retains cooldown without old held pose"):return
	if not check(host.world.step(30.1,true),"Advance to expiry scenario"):return
	broadcast(host)
	if not check(await action(second,Care.ACTION,HEN),"Second client can care next"):return
	if not check(host.world.step(Care.SECONDS+0.1,true),"Actual server tick expires hug"):return
	broadcast(host)
	if not check(await wait_for(func():return Care.holder(returned.snapshot).is_empty() and Care.holder(second.snapshot).is_empty()),"Both observe timeout return"):return
	finish(0)
