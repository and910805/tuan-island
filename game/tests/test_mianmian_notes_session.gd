extends "res://tests/network_egg_basket.gd"
## T066 N06-1 over real loopback WebSocket: one feed, five-second readiness, private cue and unlock.
const Goals=World.RESIDENT_GOALS
const Approach=preload("res://scripts/mianmian_chicken_approach.gd")
const Notes=preload("res://scripts/mianmian_animal_notes.gd")
func finish(code:int)->void:
	for index in range(sessions.size()-1,-1,-1):
		if not sessions[index].shutting_down:sessions[index].shutdown()
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("MIANMIAN_NOTES_SESSION checks=%d exit=%d"%[checks,code])
	quit(code)
func send_all(host)->void:
	for peer in host.peers:host._send_snapshot(peer)
func run()->void:
	path=OS.get_environment("TEMP").path_join("mianmian-notes-network-%s.json"%Crypto.new().generate_random_bytes(10).hex_encode())
	var fixture:=World.new()
	fixture.save_path=path
	fixture.state.picnic=true
	for token in [GROWER,FRIEND]:
		fixture.add_player(token,"照料者")
		fixture.state.players[token].x=HEN.x+2.5
		fixture.state.players[token].y=HEN.y+0.5
		fixture.state.players[token].bonds={"mianmian":{"points":6,"talk_day":-1,"gift_day":-1}}
		fixture.state.players[token].inventory.feed=1
	if not check(fixture.save(),"Save normal stock, friendship and standing fixture"):return
	var listener:=TCPServer.new()
	if not check(listener.listen(0,"127.0.0.1")==OK,"Allocate loopback port"):return
	var port:=listener.get_local_port()
	listener.stop()
	var host:=make_session("NoteHost","note-host")
	if not check(host.host(port,"筆記",path,ROOM,"127.0.0.1",true,"websocket")==OK,"Start real WS dedicated host"):return
	host.set_physics_process(false)
	var owner:=make_session("NoteOne",GROWER)
	var friend:=make_session("NoteTwo",FRIEND)
	var address:="ws://127.0.0.1:%d"%port
	if not check(owner.join(address,port,"餵雞者",ROOM)==OK and friend.join(address,port,"旁觀者",ROOM)==OK,"Join two independent clients"):return
	if not check(await wait_for(func():return not owner.own_id.is_empty() and not friend.own_id.is_empty()),"Both enter"):return
	var state:Dictionary=host.world.state
	if not check(not owner.snapshot.has("own_mianmian_feed_time") and not Notes.available(owner.snapshot),"Nothing before feeding"):return
	if not check(await action(owner,"feed",HEN),"Owner feeds once over WS"):return
	var fed_at:=float(state.players[GROWER][Goals.CHICKEN_FED_KEY])
	if not check(await wait_for(func():return owner.snapshot.has("own_mianmian_feed_time")),"Owner snapshot carries private feed time"):return
	if not check(is_equal_approx(float(owner.snapshot.own_mianmian_feed_time),fed_at) and int(state.players[GROWER].inventory.feed)==0,"Exactly one feed, time matches host"):return
	send_all(host)
	await process_frame
	await process_frame
	if not check(not friend.snapshot.has("own_mianmian_feed_time") and not friend.snapshot.players.get(owner.own_id,{}).has(Goals.CHICKEN_FED_KEY),"Observer receives no owner feed time"):return
	var rest:=Vector2(45.7,33.8)
	if not check(Approach.shift(owner.snapshot,owner.own_id,rest,false,fed_at+3.5).length()>1.0,"Owner gets the approach cue"):return
	if not check(Approach.shift(friend.snapshot,friend.own_id,rest,false,fed_at+3.5)==Vector2.ZERO,"Observer gets no cue"):return
	var cell:Vector2i=World.bond_place(owner.snapshot,"mianmian")[1]
	state.players[GROWER].x=cell.x+0.5
	state.players[GROWER].y=cell.y+0.5
	if not check(not await action(owner,Goals.ACTION,cell,"mianmian:1::"),"Report is refused before five seconds"):return
	if not check(host.world.step(5.1,true),"Advance authoritative time"):return
	send_all(host)
	if not check(await wait_for(func():return float(owner.snapshot.get("time",0))>=fed_at+5.0),"Owner receives later time"):return
	if not check(await action(owner,Goals.ACTION,cell,"mianmian:1::"),"Owner reports after five seconds"):return
	if not check(await wait_for(func():return Notes.available(owner.snapshot)),"Owner unlocks the notes"):return
	send_all(host)
	await process_frame
	await process_frame
	if not check(not Notes.available(friend.snapshot) and not Goals.done(state.players[FRIEND],"mianmian").has(1),"Observer receives no completion"):return
	# Normal shared livestock still works for both.
	state.players[GROWER].x=HEN.x+2.5
	state.players[GROWER].y=HEN.y+0.5
	if not check(host.world.step(60.0,true),"Advance to egg ready"):return
	send_all(host)
	if not check(await action(owner,"egg",HEN) and eggs(owner)==1,"Owner collects the shared egg"):return
	if not check(await action(friend,"feed",HEN),"Observer feeds the shared hen normally"):return
	if not check(is_equal_approx(float(state.players[GROWER][Goals.CHICKEN_FED_KEY]),fed_at) and state.players[FRIEND].has(Goals.CHICKEN_FED_KEY),"Each player keeps their own first-feed time"):return
	# Reconnect and persistence.
	owner.shutdown()
	if not check(await wait_for(func():return host.peers.size()==1),"Host sees owner leave"):return
	var returned:=make_session("NoteReturned",GROWER)
	if not check(returned.join(address,port,"回來的餵雞者",ROOM)==OK,"Reconnect owner"):return
	if not check(await wait_for(func():return not returned.own_id.is_empty() and Notes.available(returned.snapshot) and returned.snapshot.has("own_mianmian_feed_time")),"Reconnect reopens notes and private time"):return
	var loaded:=World.new()
	if not check(host.world.save() and loaded.load_world(path) and Goals.done(loaded.state.players[GROWER],"mianmian").has(1),"Completion persists in the existing save format"):return
	finish(0)
