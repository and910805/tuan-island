extends "res://tests/network_egg_basket.gd"
## T065: feeding the hen starts a ten-second follow that real clients see only as a hashed public actor.
const Follow=World.CHICKEN_FEED_FOLLOW
const Care=World.CHICKEN_CUDDLE

func finish(code:int)->void:
	for index in range(sessions.size()-1,-1,-1):
		if not sessions[index].shutting_down:sessions[index].shutdown()
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("CHICKEN_FEED_FOLLOW_SESSION checks=%d exit=%d"%[checks,code])
	quit(code)

func broadcast(host:Session)->void:
	for peer in host.peers:host._send_snapshot(peer)

func advance(host:Session,seconds:float)->bool:
	if not host.world.step(seconds,true):return false
	broadcast(host)
	return true

func feed_count(session:Session)->int:
	return int(session.snapshot.get("players",{}).get(session.own_id,{}).get("inventory",{}).get("feed",0))

func followers_are(viewers:Array,expected:String)->bool:
	for viewer:Session in viewers:
		if Follow.holder(viewer.snapshot)!=expected:return false
	return true

func tokens_hidden(viewers:Array)->bool:
	for viewer:Session in viewers:
		var wire:=JSON.stringify(viewer.snapshot)
		if wire.contains(GROWER) or wire.contains(FRIEND):return false
	return true

func run()->void:
	path=OS.get_environment("TEMP").path_join("chicken-feed-follow-%s.json"%Crypto.new().generate_random_bytes(10).hex_encode())
	var fixture:=World.new()
	fixture.save_path=path
	for token in [GROWER,FRIEND]:
		fixture.add_player(token,"餵食者")
		fixture.state.players[token].x=HEN.x+0.5
		fixture.state.players[token].y=HEN.y+0.5
		fixture.state.players[token].inventory.feed=3
	if not check(fixture.save(),"Fixture with two fed-ready players saved"):return
	if not check(Follow.FIELD=="feed_follow_actor" and is_equal_approx(Follow.SECONDS,10.0),"Feed follow exposes its field and ten second window"):return
	var listener:=TCPServer.new()
	if not check(listener.listen(0,"127.0.0.1")==OK,"Allocate loopback port"):return
	var port:=listener.get_local_port()
	listener.stop()
	var address:="ws://127.0.0.1:%d"%port
	var host:=make_session("FollowHost","follow-host")
	if not check(host.host(port,"Host",path,ROOM,"127.0.0.1",true,"websocket")==OK,"Start dedicated WebSocket host"):return
	host.set_physics_process(false)
	var first:=make_session("FollowOne",GROWER)
	var second:=make_session("FollowTwo",FRIEND)
	if not check(first.join(address,port,"第一位",ROOM)==OK and second.join(address,port,"第二位",ROOM)==OK,"Join two isolated client APIs"):return
	if not check(await wait_for(func():return not first.own_id.is_empty() and not second.own_id.is_empty()),"Both clients enter"):return
	var viewers:=[first,second]
	if not check(followers_are(viewers,"") and not host.world.state.animal.has(Follow.FIELD),"Nobody is followed before feeding"):return

	if not check(await action(first,"feed",HEN),"Normal feed succeeds through the real action RPC"):return
	var feed_time:float=host.world.state.time
	if not check(host.world.state.players[GROWER].inventory.feed==2 and await wait_for(func():return feed_count(first)==2),"Feeding deducts exactly one feed"):return
	if not check(is_equal_approx(float(host.world.state.animal.egg_ready)-feed_time,World.CHICKEN_EGG_SECONDS),"Egg production keeps its existing duration"):return
	if not check(host.world.state.animal[Follow.FIELD]==GROWER,"Host keeps the raw actor privately"):return
	if not check(await wait_for(func():return followers_are(viewers,first.own_id)),"Both viewers independently see the feeder as the follow target"):return
	var public_id:=Follow.holder(second.snapshot)
	if not check(public_id.length()==16 and public_id!=GROWER and second.snapshot.players.has(public_id),"Follow target is an existing hashed public actor"):return
	if not check(second.snapshot.animal[Follow.FIELD]==public_id and tokens_hidden(viewers),"Raw actor and profile tokens never cross the snapshot wire"):return
	if not check(Follow.holder(first.snapshot)!=second.own_id,"A viewer is not mistaken for the feeder"):return

	var friend_feed:=feed_count(second)
	if not check(not await action(second,"feed",HEN) and feed_count(second)==friend_feed,"A refused feed neither costs feed nor takes the follow"):return
	broadcast(host)
	if not check(await wait_for(func():return followers_are(viewers,first.own_id)),"Refused feed leaves the original follower"):return

	if not check(advance(host,Follow.SECONDS*0.4),"Advance part-way through the follow"):return
	if not check(await wait_for(func():return followers_are(viewers,first.own_id)),"Follow remains active inside ten world seconds"):return
	if not check(advance(host,Follow.SECONDS*0.6+0.1),"Advance past the follow window"):return
	if not check(await wait_for(func():return followers_are(viewers,"")),"Both viewers see the follow expire"):return
	if not check(not host.world.state.animal.has(Follow.FIELD) and float(host.world.state.animal.egg_ready)>=0.0,"Expiry clears the actor but keeps the pending egg"):return
	if not check(not await action(second,"egg",HEN),"The egg is still not ready when the follow ends"):return

	if not check(advance(host,World.CHICKEN_EGG_SECONDS),"Advance until the egg is due"):return
	var eggs_before:=eggs(second)
	if not check(await action(second,"egg",HEN) and eggs(second)==eggs_before+1,"Existing egg collection still pays one egg"):return
	if not check(await action(second,"feed",HEN),"A later successful feed is accepted"):return
	if not check(await wait_for(func():return followers_are(viewers,second.own_id)),"Later feed starts the follow again for the other feeder"):return
	if not check(await wait_for(func():return feed_count(second)==friend_feed-1) and tokens_hidden(viewers),"Second feed also deducts one and stays hashed"):return

	if not check(await action(first,Care.ACTION,HEN),"Another player can hug the following hen"):return
	if not check(await wait_for(func():return followers_are(viewers,"") and Care.holder(second.snapshot)==first.own_id),"Hug clears the follow and replaces it with the hug"):return
	if not check(not host.world.state.animal.has(Follow.FIELD),"Hug erases the raw follower"):return
	if not check(await action(first,Care.RELEASE,HEN),"Hug can be released"):return
	if not check(await wait_for(func():return followers_are(viewers,"") and Care.holder(second.snapshot).is_empty()),"Release does not resume the follow"):return

	if not check(advance(host,World.CHICKEN_EGG_SECONDS),"Advance to the next due egg"):return
	if not check(await action(first,"egg",HEN) and await action(first,"feed",HEN),"First player collects and feeds again"):return
	if not check(await wait_for(func():return followers_are(viewers,first.own_id)),"Repeat feeding by the same player follows again"):return
	first.shutdown()
	if not check(await wait_for(func():return host.peers.size()==1),"Host sees the feeder disconnect"):return
	broadcast(host)
	if not check(await wait_for(func():return followers_are([second],"")) and not host.world.state.animal.has(Follow.FIELD),"Disconnect clears the follow for the remaining viewer"):return
	if not check(float(host.world.state.animal.egg_ready)>=0.0,"Disconnect leaves egg production running"):return

	var returned:=make_session("FollowReturned",GROWER)
	if not check(returned.join(address,port,"回來的餵食者",ROOM)==OK and await wait_for(func():return not returned.own_id.is_empty()),"Original profile reconnects"):return
	if not check(await wait_for(func():return followers_are([returned,second],"")),"Reconnect does not restore the old follow"):return

	if not check(advance(host,World.CHICKEN_EGG_SECONDS),"Advance to the last due egg"):return
	if not check(await action(returned,"egg",HEN) and await action(returned,"feed",HEN),"Reconnected player collects and feeds"):return
	if not check(await wait_for(func():return followers_are([returned,second],returned.own_id)),"Final follow is visible before restart"):return
	if not check(host.world.save(),"Save the room while the follow is active"):return
	var stored_state:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path)).animal
	if not check(stored_state.get(Follow.FIELD,"")==GROWER,"Save fixture contains an active follow to restart"):return
	var restarted:=World.new()
	if not check(restarted.load_world(path),"Restart loads the saved room"):return
	if not check(not restarted.state.animal.has(Follow.FIELD) and Follow.holder(restarted.state).is_empty() and float(restarted.state.animal.egg_ready)>=0.0,"Restart does not resume the follow but keeps egg progress"):return
	finish(0)
