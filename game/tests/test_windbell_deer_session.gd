extends "res://tests/network_egg_basket.gd"

const Deer=World.Deer

func finish(code:int)->void:
	for index in range(sessions.size()-1,-1,-1):
		if not sessions[index].shutting_down:sessions[index].shutdown()
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("WINDBELL_DEER_SESSION checks=%d failures=%d"%[checks,code])
	quit(code)

func player(client:Session,id:String)->Dictionary:
	return client.snapshot.get("players",{}).get(id,{})

func move_to_tree(clients:Array)->bool:
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		var arrived:=true
		for client:Session in clients:
			var x:=float(player(client,client.own_id).get("x",47.0))
			client.input_direction(Vector2.LEFT if x>45.0 else Vector2.ZERO)
			arrived=arrived and x<=45.0
		if arrived:return true
		await process_frame
	for client:Session in clients:client.input_direction(Vector2.ZERO)
	return false

func run()->void:
	path=OS.get_environment("TEMP").path_join("deer-network-%s.json"%Crypto.new().generate_random_bytes(10).hex_encode())
	var fixture:=World.new()
	fixture.save_path=path
	fixture.state.festival_story_open=true
	fixture.add_player(GROWER,"島民")
	fixture.add_player(FRIEND,"來客")
	var grower:Dictionary=fixture.state.players[GROWER]
	for index in range(4):
		var tile:Vector2i=Deer.SITES[index]
		grower.x=tile.x+0.5
		grower.y=tile.y+0.5
		if not check(fixture.act(GROWER,"field-%d"%index,"hoe",tile).ok,"Till the original deer candidates through the farming action"):return
	var site:=Deer.site(fixture.state)
	if not check(site==Deer.SITES[4],"The deer uses an unobstructed overflow site"):return
	for token in [GROWER,FRIEND]:
		fixture.state.players[token].x=46.5
		fixture.state.players[token].y=26.5
	if not check(fixture.save(),"Save the prepared festival landscape"):return
	var listener:=TCPServer.new()
	if not check(listener.listen(0,"127.0.0.1")==OK,"Allocate a loopback port"):return
	var port:=listener.get_local_port()
	listener.stop()
	var host:=make_session("DeerHost","deer-host")
	if not check(host.host(port,"風鈴渡口",path,ROOM,"127.0.0.1",true,"websocket")==OK,"Start dedicated host"):return
	var first:=make_session("DeerOne",GROWER)
	var second:=make_session("DeerTwo",FRIEND)
	var address:="ws://127.0.0.1:%d"%port
	if not check(first.join(address,port,"島民",ROOM)==OK and second.join(address,port,"來客",ROOM)==OK,"Join two clients"):return
	if not check(await wait_for(func():return not first.own_id.is_empty() and not second.own_id.is_empty()),"Both clients enter the festival"):return
	if not check(Deer.present(first.snapshot) and Deer.site(first.snapshot)==site and Deer.site(second.snapshot)==site,"Both clients see the same safe deer location"):return
	if not check(not await action(first,Deer.ACTION,site),"An out-of-range observation is refused"):return
	if not check(await move_to_tree([first,second]),"Both clients walk to the deer with normal movement input"):return
	if not check(not await action(first,Deer.ACTION,Deer.SITE),"The obsolete location does not record a sighting"):return
	var seen_first:int=notices[first].size()
	var seen_second:int=notices[second].size()
	first.perform(Deer.ACTION,site)
	second.perform(Deer.ACTION,site)
	if not check(await wait_for(func():return notices[first].size()>seen_first and notices[second].size()>seen_second),"Both simultaneous observations finish"):return
	if not check(notices[first].back().ok and notices[second].back().ok,"Both visitors can observe the same deer"):return
	for pair in [[first,second],[second,first]]:
		var own:Session=pair[0]
		var other:Session=pair[1]
		if not check(await wait_for(func():return player(own,own.own_id).get("windbell_deer_seen",false)),"The owner's observation arrives"):return
		if not check(not player(own,other.own_id).has("windbell_deer_seen"),"The neighbor's observation stays private"):return
	if not check(not await action(second,Deer.ACTION,site),"Repeat observation cannot add another entry"):return
	first.shutdown()
	if not check(await wait_for(func():return host.peers.size()==1),"Host registers the disconnect"):return
	var returned:=make_session("DeerReturn",GROWER)
	if not check(returned.join(address,port,"島民",ROOM)==OK and await wait_for(func():return player(returned,returned.own_id).get("windbell_deer_seen",false)),"Reconnecting keeps the original observation"):return
	var saved:=World.new()
	if not check(host.world.save() and saved.load_world(path) and saved.state.players[GROWER].windbell_deer_seen and saved.state.players[FRIEND].windbell_deer_seen,"Both observations persist in the saved world"):return
	finish(0)
