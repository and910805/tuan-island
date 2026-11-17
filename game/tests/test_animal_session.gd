extends "res://tests/network_egg_basket.gd"
## Dedicated session plus two independent WebSocket clients on one machine.
## Positions and the duck's prior care/feed history are fixture data.

const DUCK=World.LIVESTOCK.Duck

func finish(code:int) -> void:
	Engine.time_scale=1.0
	for i in range(sessions.size()-1,-1,-1):
		if not sessions[i].shutting_down:sessions[i].shutdown()
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("ANIMAL_SESSION_TESTS checks=%d failures=%d"%[checks,code])
	quit(code)

func stand(world:World,token:String,tile:Vector2i) -> void:
	var player:Dictionary=world.state.players[token]
	player.x=tile.x+0.5
	player.y=tile.y+0.5

func person(client:Session,id:String) -> Dictionary:
	return client.snapshot.get("players",{}).get(id,{})

func run() -> void:
	path="user://animal-session-%d.json"%OS.get_process_id()
	var fixture:=World.new()
	fixture.save_path=path
	fixture.state.picnic=true
	fixture.state.time=540.0
	for token in [GROWER,FRIEND]:
		fixture.add_player(token,"Ranch")
		stand(fixture,token,World.LIVESTOCK.ANIMALS.sheep.cell)
	fixture.state.players[GROWER].inventory.merge({"feed":1,"egg_basket":1},true)
	fixture.state.livestock.duck={"feed":0,"ready":0,"next":-1.0,"bond":5,"last_pet":0.0,"bonus_progress":3}
	var collector:=World.LIVESTOCK.collector_cell("duck")
	var key:=World.key(collector)
	fixture.state.objects[key]={"type":"animal_collector","owner":GROWER,"items":{}}
	if not check(fixture.save(),"The dedicated test fixture is saveable"):return
	var listener:=TCPServer.new()
	if not check(listener.listen(0,"127.0.0.1")==OK,"Allocate a loopback port"):return
	var port:=listener.get_local_port()
	listener.stop()
	var address:="ws://127.0.0.1:%d"%port
	var host:=make_session("Host","animal-network-host")
	if not check(host.host(port,"Host",path,ROOM,"127.0.0.1",true,"websocket")==OK,"Start a dedicated WebSocket room"):return
	var grower:=make_session("Grower",GROWER)
	var friend:=make_session("Friend",FRIEND)
	if not check(grower.join(address,port,"Grower",ROOM)==OK and friend.join(address,port,"Friend",ROOM)==OK,"Connect both WebSocket clients"):return
	if not check(await wait_for(func():return not grower.own_id.is_empty() and not friend.own_id.is_empty()),"Both clients enter the room"):return
	var grower_id:=grower.own_id
	var home_site:Vector2i=World.LIVESTOCK.ANIMALS.sheep.cell
	if not check(await action(grower,"rabbit_adopt",home_site),"Adopt the rabbit through a client"):return
	if not check(await action(grower,"rabbit_pet",home_site),"Pet the rabbit through a client"):return
	if not check(await wait_for(func():
		return (person(grower,grower_id).get(World.Rabbit.FIELD,{}).get("bond",0)==1
			and person(friend,grower_id).get(World.Rabbit.FIELD,{})=={"following":true})),
		"The owner sees bond, while the neighbor sees only the follower"):return
	stand(host.world,GROWER,World.Dog.SITE)
	if not check(await action(grower,"dog_adopt",World.Dog.SITE),"Adopt the second companion"):return
	if not check(await action(grower,"dog_toy",World.Dog.SITE),"Give the dog its toy"):return
	if not check(await wait_for(func():
		var other:=person(friend,grower_id)
		return (other.get(World.Dog.FIELD,{})=={"following":true,"last_play":"toy"}
			and other.get(World.Rabbit.FIELD,{})=={"following":false})),
		"The neighbor sees the toy and exactly one following pet"):return
	for token in [GROWER,FRIEND]:stand(host.world,token,World.Seal.SITE)
	if not check(await action(grower,World.Seal.ACTION,World.Seal.SITE),"Observe the seal during low tide"):return
	if not check(await wait_for(func():
		return person(grower,grower_id).get("seal_seen",false) and not person(friend,grower_id).has("seal_seen")),
		"The wildlife observation is sent only to its owner"):return
	for token in [GROWER,FRIEND]:stand(host.world,token,DUCK.SITE)
	if not check(await action(grower,"collector_bind",collector,"duck"),"Bind the collector to the duck remotely"):return
	if not check(await action(grower,"livestock_feed",DUCK.SITE,"duck"),"Feed the bonded duck over the network"):return
	if not check(host.world.step(World.LIVESTOCK.DAY,true),"Advance one production day on the host"):return
	if not check(await wait_for(func():
		var machine:Dictionary=friend.snapshot.get("objects",{}).get(key,{})
		return machine.get("collector_count",0)==2 and machine.get("collector_count_quality",0)==1),
		"Another client sees one ordinary and one premium egg in the machine"):return
	if not check(not await action(friend,"collector_collect",collector),"A neighbor cannot collect from someone else's machine"):return
	grower.shutdown()
	if not check(await wait_for(func():return host.peers.size()==1),"The host notices the disconnect"):return
	var returned:=make_session("Returned",GROWER)
	if not check(returned.join(address,port,"Grower",ROOM)==OK,"Reconnect the same profile"):return
	if not check(await wait_for(func():
		var own:=person(returned,returned.own_id)
		return own.get("seal_seen",false) and own.get(World.Dog.FIELD,{}).get("bond",0)==1),
		"Reconnecting restores the wildlife observation and pet relationship"):return
	if not check(await action(returned,"collector_collect",collector),"The owner collects both grades after reconnecting"):return
	if not check(await wait_for(func():
		var bag:Dictionary=person(returned,returned.own_id).get("inventory",{})
		return bag.get(DUCK.EGG,0)==1 and bag.get(DUCK.QUALITY_EGG,0)==1),
		"The owner gets exactly one egg of each grade"):return
	if not check(not await action(returned,"collector_collect",collector),"No duplicate claim after reconnecting"):return
	var saved:=World.new()
	if not check(saved.load_world(path) and int(saved.state.players[GROWER].inventory.get(DUCK.QUALITY_EGG,0))==1
		and int(saved.state.objects[key].collector_count)==0,"The two grades are durably collected"):return
	finish(0)
