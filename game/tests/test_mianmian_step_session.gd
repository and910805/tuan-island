extends "res://tests/network_egg_basket.gd"
## T066 N06-4 over real loopback WebSocket: the quiet sheep watch, readiness and reward per player.
const Goals=World.RESIDENT_GOALS
const Weather=preload("res://scripts/weather.gd")
const Step=preload("res://scripts/mianmian_sheep_step.gd")
func finish(code:int)->void:
	for index in range(sessions.size()-1,-1,-1):
		if not sessions[index].shutting_down:sessions[index].shutdown()
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("MIANMIAN_STEP_SESSION checks=%d exit=%d"%[checks,code])
	quit(code)
func send_all(host)->void:
	for peer in host.peers:host._send_snapshot(peer)
func dry_time()->float:
	for day in range(1,60):
		if not Weather.rains(float(day),"home"):return float(day)*Weather.DAY_SECONDS+30.0
	return 30.0
func run()->void:
	path=OS.get_environment("TEMP").path_join("mianmian-step-network-%s.json"%Crypto.new().generate_random_bytes(10).hex_encode())
	var sheep:Vector2i=World.LIVESTOCK.ANIMALS.sheep.cell
	var fixture:=World.new()
	fixture.save_path=path
	fixture.state.picnic=true
	fixture.state.time=dry_time()
	for token in [GROWER,FRIEND]:
		fixture.add_player(token,"看羊的人")
		fixture.state.players[token].x=sheep.x+0.5
		fixture.state.players[token].y=sheep.y+0.5
		fixture.state.players[token].bonds={"mianmian":{"points":24,"talk_day":-1,"gift_day":-1}}
	fixture.state.players[GROWER][Goals.SHEEP_SHELTER_KEY]=Goals.SHEEP_COMFORT_MASK
	if not check(fixture.save(),"Save normal stock, friendship and standing fixture"):return
	var listener:=TCPServer.new()
	if not check(listener.listen(0,"127.0.0.1")==OK,"Allocate loopback port"):return
	var port:=listener.get_local_port()
	listener.stop()
	var host:=make_session("StepHost","step-host")
	if not check(host.host(port,"屋簷",path,ROOM,"127.0.0.1",true,"websocket")==OK,"Start real WS dedicated host"):return
	host.set_physics_process(false)
	var owner:=make_session("StepOne",GROWER)
	var friend:=make_session("StepTwo",FRIEND)
	var address:="ws://127.0.0.1:%d"%port
	if not check(owner.join(address,port,"看羊的人",ROOM)==OK and friend.join(address,port,"旁觀者",ROOM)==OK,"Join two independent clients"):return
	if not check(await wait_for(func():return not owner.own_id.is_empty() and not friend.own_id.is_empty()),"Both enter"):return
	var state:Dictionary=host.world.state
	var start:float=float(state.time)
	if not check(not owner.snapshot.has("own_mianmian_step_time"),"No watch time before watching"):return
	if not check(await action(owner,Goals.SHEEP_STEP_ACTION,sheep),"Owner watches the sheep over WS"):return
	if not check(await wait_for(func():return owner.snapshot.has("own_mianmian_step_time")),"Owner receives the private watch time"):return
	if not check(Step.active(owner.snapshot,start+1.0),"Owner's helper starts the local walk"):return
	send_all(host)
	await process_frame
	await process_frame
	if not check(not friend.snapshot.has("own_mianmian_step_time") and not friend.snapshot.players.get(owner.own_id,{}).has(Goals.SHEEP_STEP_KEY) and not Step.active(friend.snapshot,start+1.0),"Guest receives no watch time and sees no walk"):return
	if not check(not state.players[FRIEND].has(Goals.SHEEP_STEP_KEY),"Guest has no record"):return
	var cell:Vector2i=World.bond_place(owner.snapshot,"mianmian")[1]
	state.players[GROWER].x=cell.x+0.5
	state.players[GROWER].y=cell.y+0.5
	if not check(not await action(owner,Goals.ACTION,cell,"mianmian:4::"),"Report refused before six seconds"):return
	if not check(host.world.step(Goals.SHEEP_STEP_SECONDS+0.1,true),"Advance authoritative time"):return
	send_all(host)
	if not check(await wait_for(func():return float(owner.snapshot.get("time",0))>=start+Goals.SHEEP_STEP_SECONDS),"Owner receives later time"):return
	if not check(await action(owner,Goals.ACTION,cell,"mianmian:4::"),"Owner reports after six seconds"):return
	if not check(not await action(owner,Goals.ACTION,cell,"mianmian:4::"),"Second report refused"):return
	state.players[GROWER].x=cell.x+0.5
	if not check(await action(owner,Goals.WOOL_HAT_ACTION,cell) and state.players[GROWER].get(Goals.WOOL_HAT_KEY)==true,"Owner wears the hat over WS"):return
	send_all(host)
	await process_frame
	await process_frame
	if not check(friend.snapshot.players.get(owner.own_id,{}).get(Goals.WOOL_HAT_KEY,false)==true,"Guest sees the owner wearing the cosmetic hat"):return
	if not check(friend.snapshot.resident_goals.mianmian["4"].state!="done" and not Goals.done(state.players[FRIEND],"mianmian").has(4),"Guest sees no completion"):return
	if not check(not await action(friend,Goals.WOOL_HAT_ACTION,World.bond_place(friend.snapshot,"mianmian")[1]),"Guest cannot wear a hat they have not earned"):return
	# The guest then does their own watch independently.
	state.players[FRIEND].x=sheep.x+0.5
	state.players[FRIEND].y=sheep.y+0.5
	if not check(await action(friend,Goals.SHEEP_STEP_ACTION,sheep) and not is_equal_approx(float(state.players[FRIEND][Goals.SHEEP_STEP_KEY]),start),"Guest's watch starts at their own time"):return
	if not check(is_equal_approx(float(state.players[GROWER][Goals.SHEEP_STEP_KEY]),start),"Owner's recorded time is unchanged"):return
	owner.shutdown()
	if not check(await wait_for(func():return host.peers.size()==1),"Host sees owner leave"):return
	var returned:=make_session("StepReturned",GROWER)
	if not check(returned.join(address,port,"回來的看羊人",ROOM)==OK,"Reconnect owner"):return
	if not check(await wait_for(func():return not returned.own_id.is_empty() and returned.snapshot.resident_goals.mianmian["4"].state=="done"),"Reconnect keeps the completion"):return
	var loaded:=World.new()
	if not check(host.world.save() and loaded.load_world(path) and Goals.done(loaded.state.players[GROWER],"mianmian").has(4) and loaded.state.players[GROWER].get(Goals.WOOL_HAT_KEY)==true,"Completion and hat persist in the save"):return
	finish(0)
