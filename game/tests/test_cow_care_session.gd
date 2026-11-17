extends "res://tests/network_egg_basket.gd"
const Care=World.COW_CARE
const Follow=preload("res://scripts/cow_follow_view.gd")
const SITE:=Vector2i(48,35)
func finish(code:int)->void:
	for index in range(sessions.size()-1,-1,-1):
		if not sessions[index].shutting_down:sessions[index].shutdown()
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("COW_CARE_SESSION checks=%d exit=%d"%[checks,code])
	quit(code)
func run()->void:
	path=OS.get_environment("TEMP").path_join("cow-care-network-%s.json"%Crypto.new().generate_random_bytes(10).hex_encode())
	var fixture:=World.new()
	fixture.save_path=path
	fixture.state.picnic=true
	for token in [GROWER,FRIEND]:
		fixture.add_player(token,"照料者")
		fixture.state.players[token].x=48.5
		fixture.state.players[token].y=37.5
	if not check(fixture.save(),"Save isolated care fixture"):return
	var listener:=TCPServer.new()
	if not check(listener.listen(0,"127.0.0.1")==OK,"Allocate loopback port"):return
	var port:=listener.get_local_port()
	listener.stop()
	var host:=make_session("CowHost","cow-host")
	if not check(host.host(port,"牧場",path,ROOM,"127.0.0.1",true,"websocket")==OK,"Start real dedicated WS room"):return
	var grower:=make_session("CowOne",GROWER)
	var friend:=make_session("CowTwo",FRIEND)
	var address:="ws://127.0.0.1:%d"%port
	if not check(grower.join(address,port,"照料者",ROOM)==OK and friend.join(address,port,"照料者",ROOM)==OK,"Join two independent APIs"):return
	if not check(await wait_for(func():return not grower.own_id.is_empty() and not friend.own_id.is_empty()),"Both clients entered"):return
	var view_one:=Follow.new()
	var view_two:=Follow.new()
	view_one.observe(grower.snapshot)
	view_two.observe(friend.snapshot)
	grower.perform("livestock_pet",SITE,"cow")
	friend.perform("livestock_pet",SITE,"cow")
	if not check(await wait_for(func():return not notices[grower].is_empty() and not notices[friend].is_empty()),"Both simultaneous requests finish"):return
	if not check(int(notices[grower].back().ok)+int(notices[friend].back().ok)==1 and host.world.state.livestock.cow.bond==1,"Only one shared care wins"):return
	var actor:=Care.active_actor(host.world.state,host.world.active_tokens)
	if not check(await wait_for(func():return Care.active_actor(grower.snapshot)==actor.sha256_text().left(16) and Care.active_actor(friend.snapshot)==actor.sha256_text().left(16)),"Both clients get same hashed care actor"):return
	for client in [grower,friend]:
		var wire:=JSON.stringify(client.snapshot)
		if not check(not wire.contains(GROWER) and not wire.contains(FRIEND),"Raw profiles absent from wire snapshot"):return
	view_one.observe(grower.snapshot)
	view_two.observe(friend.snapshot)
	for frame in 10:
		view_one.advance(0.1)
		view_two.advance(0.1)
	if not check(view_one.position==view_two.position and view_one.position.distance_to(Follow.HOME)>0.5,"Both clients display same slow approach"):return
	var stable:=view_one.position
	view_one.observe(grower.snapshot)
	if not check(view_one.position==stable,"Repeated snapshot keeps travel progress"):return
	var winner=grower if actor==GROWER else friend
	var loser=friend if actor==GROWER else grower
	if not check(not await action(loser,"livestock_pet",SITE,"cow"),"Losing client cannot bypass shared cooldown"):return
	winner.shutdown()
	if not check(await wait_for(func():return host.peers.size()==1 and not host.world.state.livestock.cow.has(Care.FIELD)),"Disconnect clears shared actor"):return
	if not check(await wait_for(func():return Care.active_actor(loser.snapshot).is_empty()),"Remaining observer sees return state"):return
	var returned:=make_session("CowReturned",actor)
	if not check(returned.join(address,port,"照料者",ROOM)==OK and await wait_for(func():return not returned.own_id.is_empty()),"Original profile reconnects"):return
	if not check(int(returned.snapshot.livestock.cow.bond)==1 and Care.active_actor(returned.snapshot).is_empty(),"Reconnect preserves bond without old follow"):return
	if not check(not await action(returned,"livestock_pet",SITE,"cow"),"Reconnect cannot reset pet cooldown"):return
	var saved:=World.new()
	if not check(saved.load_world(path) and int(saved.state.livestock.cow.bond)==1 and Care.active_actor(saved.state).is_empty(),"Persisted care reloads safely"):return
	finish(0)
