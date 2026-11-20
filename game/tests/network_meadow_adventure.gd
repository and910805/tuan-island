extends SceneTree
## Two WebSocket clients and a dedicated host in separate multiplayer branches.
## The fixture opens B15. Walking, interactions and reconnects use the normal RPCs.

const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const Meadow=World.MEADOW
const Trial=World.MEADOW_ADVENTURE
const KEY:="meadow-adventure-test"
const A:="meadow-loopback-first"
const B:="meadow-loopback-second"
const STARTS:=[Vector2(24.5,26.35),Vector2(22.5,26.35)]

class Client:
	var session:Session
	var results:Dictionary={}
	var shared_frames:=0
	var privacy_errors:=0

	func observe(snapshot:Dictionary,own_id:String)->void:
		var people:Dictionary=snapshot.get("players",{})
		for id in people:
			if str(id)==own_id:continue
			shared_frames+=1
			if people[id].has(Meadow.FIELD):privacy_errors+=1
		var payload:=JSON.stringify(snapshot)
		if payload.contains(A) or payload.contains(B):privacy_errors+=1

	func person()->Dictionary:
		return session.snapshot.get("players",{}).get(session.own_id,{})

	func at()->Vector2:
		var player:=person()
		return Vector2(player.get("x",-999.0),player.get("y",-999.0))

	func progress()->int:
		return int(person().get(Meadow.FIELD,0))

	func round_view()->Dictionary:
		return session.snapshot.get(Trial.VIEW,{})

	func phase()->int:
		return int(round_view().get("phase",-1))

var host:Session
var checks:=0
var failures:=0
var branch_count:=0
var save_path:="user://meadow-network-%d.json"%Time.get_ticks_usec()

func _initialize()->void:
	run.call_deferred()

func seed_room()->bool:
	var world:=World.new()
	world.save_path=save_path
	world.state.picnic=true
	world.state.board=true
	world.state.world_mode="adventure"
	world.state.mine_depths.unlocked=Meadow.DEPTH
	world.state.mine_depths.pumped=24
	for index in STARTS.size():
		var token:String=[A,B][index]
		var at:Vector2=STARTS[index]
		world.add_player(token,"提燈島民")
		world.state.players[token].merge({"region":Meadow.REGION,"x":at.x,"y":at.y},true)
	world.active_tokens.clear()
	return world.save()

func run()->void:
	if not expect(seed_room(),"Prepare a B15 adventure save"):
		finish()
		return
	var port:=start_host()
	if not expect(port>0,"Dedicated room accepts WebSocket"):
		finish()
		return
	var east:=await join(port,A,"阿福")
	var west:=await join(port,B,"米露")
	if not expect(not east.person().is_empty() and not west.person().is_empty(),"Both players reach the same room"):
		finish()
		return
	await act(east,Trial.ACTION,Meadow.CENTER,Trial.WAKE)
	expect(await wait_until(func():return east.phase()==Trial.Phase.WARNING and west.phase()==Trial.Phase.WARNING),"Warning reaches both clients")
	expect(east.round_view().get("pulse_at")==west.round_view().get("pulse_at") and east.round_view().get("required")==2,"Both clients get the same countdown and two roles")
	west.session.shutdown()
	expect(await wait_until(func():return east.round_view().is_empty() and host.peers.size()==1),"A disconnected partner cancels the round for the remaining player")
	west=await join(port,B,"米露")
	expect(not west.person().is_empty(),"The partner can return after the canceled round")
	await act(east,Trial.ACTION,Meadow.CENTER,Trial.WAKE)
	expect(await walk([east,west],[Vector2(26.35,26.35),Vector2(20.65,26.35)]),"Both players run outside the warning circle")
	expect(await wait_until(func():return east.phase()==Trial.Phase.LANTERNS and west.phase()==Trial.Phase.LANTERNS),"Host opens the lantern phase for both")

	expect(await walk([east,west],[Vector2(27.6,26.35),Vector2(19.4,26.35)]),"Walk around the outer tables")
	expect(await walk([east,west],[Vector2(27.6,28.55),Vector2(19.4,28.55)]),"Walk around the collision to the front")
	expect(await walk([east,west],[Vector2(26.5,28.55),Vector2(20.5,28.55)]),"Reach two separate lanterns")
	await act(east,Trial.ACTION,Meadow.TABLES[2],Trial.LIGHT)
	expect(await wait_until(func():return west.round_view().get("lamps")==[false,false,true]),"The partner sees the same lit lantern")
	await act(west,Trial.ACTION,Meadow.TABLES[0],Trial.LIGHT)
	expect(await walk([east],[Vector2(23.5,28.55)]),"East reaches the center lantern")
	await act(east,Trial.ACTION,Meadow.TABLES[1],Trial.LIGHT)
	expect(await wait_until(func():return east.phase()==Trial.Phase.CALMING and west.phase()==Trial.Phase.CALMING),"Three shared lanterns open the finale")
	expect(await walk([east,west],[Vector2(24.5,28.55),Vector2(21.5,28.55)]),"Move into the open lanes beside the central table")
	expect(await walk([east,west],[Vector2(24.5,26.45),Vector2(21.5,26.45)]),"Approach the guardian from the front")
	expect(await walk([west],[Vector2(22.5,26.45)]),"West reaches the guardian")
	await act(east,Trial.ACTION,Meadow.CENTER,Trial.CALM)
	expect(await wait_until(func():return west.round_view().get("calmed")==1),"Partner sees one completed calming action")
	expect(east.progress()==0 and west.progress()==0,"The first calm does not earn either claim yet")
	await act(east,Trial.ACTION,Meadow.CENTER,Trial.CALM,false)
	await act(west,Trial.ACTION,Meadow.CENTER,Trial.CALM)
	expect(await wait_until(func():return east.progress()==Meadow.ALL_TABLES and west.progress()==Meadow.ALL_TABLES),"Both helpers earn a claim at the same time")
	expect(east.shared_frames>0 and west.shared_frames>0 and east.privacy_errors+west.privacy_errors==0,"Shared snapshots hide personal data during the whole encounter")
	east.session.shutdown()
	west.session.shutdown()
	expect(host.shutdown(),"Save the shared victory before the rewards are claimed")
	await process_frame

	port=start_host()
	if not expect(port>0,"Reopen the same room"):
		finish()
		return
	east=await join(port,A,"阿福")
	west=await join(port,B,"米露")
	expect(east.progress()==Meadow.ALL_TABLES and west.progress()==Meadow.ALL_TABLES,"Both claims survive reconnecting to a new host session")
	for client:Client in [east,west]:
		await act(client,Meadow.CLAIM,Meadow.CENTER,"")
		expect(await wait_until(func():return client.progress()==Meadow.CLAIMED),"Claim reflected in the player's inventory snapshot")
		await act(client,Meadow.CLAIM,Meadow.CENTER,"",false)
		for item:String in Meadow.REWARD:
			expect(client.person().get("inventory",{}).get(item)==Meadow.REWARD[item],"Player receives the exact reward: "+item)
		client.session.shutdown()
	expect(host.shutdown(),"Save both claimed rewards")
	var reloaded:=World.new()
	expect(reloaded.load_world(save_path) and not reloaded.recovered_from_backup,"Final primary save opens")
	for token:String in [A,B]:
		var player:Dictionary=reloaded.state.players.get(token,{})
		expect(player.get(Meadow.FIELD)==Meadow.CLAIMED,"Each player's claim is durable")
		for item:String in Meadow.REWARD:
			expect(player.get("inventory",{}).get(item)==Meadow.REWARD[item],"Primary save keeps exactly one reward: "+item)
	finish()

func add_session()->Session:
	branch_count+=1
	var branch:=Node.new()
	branch.name="MeadowPeer%d"%branch_count
	root.add_child(branch)
	set_multiplayer(SceneMultiplayer.new(),branch.get_path())
	var session:=Session.new()
	branch.add_child(session)
	return session

func start_host()->int:
	host=add_session()
	for attempt in 8:
		var port:=randi_range(58101,59990)
		if host.host(port,"",save_path,KEY,"127.0.0.1",true,"websocket")==OK:return port
	return 0

func join(port:int,token:String,nickname:String)->Client:
	var client:=Client.new()
	client.session=add_session()
	client.session.profile.token=token
	client.session.changed.connect(client.observe)
	client.session.action_completed.connect(func(sequence:int,_action:String,result:Dictionary):
		client.results[sequence]=result.get("ok")
	)
	if client.session.join("ws://127.0.0.1:%d"%port,port,nickname,KEY)==OK:
		await wait_until(func():return not client.person().is_empty())
	return client

func act(client:Client,action:String,cell:Vector2i,extra:String,expected:=true)->void:
	var sequence:=client.session.perform(action,cell,extra)
	var replied:=await wait_until(func():return client.results.has(sequence))
	expect(replied and client.results[sequence]==expected,"%s/%s @ %s expected %s"%[action,extra,client.at(),expected])

func walk(clients:Array,targets:Array)->bool:
	var deadline:=Time.get_ticks_msec()+4500
	var arrived:=false
	while Time.get_ticks_msec()<deadline:
		arrived=true
		for index in clients.size():
			var offset:Vector2=targets[index]-clients[index].at()
			if offset.length()>0.20:arrived=false
			clients[index].session.input_direction(offset.limit_length() if offset.length()>0.20 else Vector2.ZERO)
		if arrived:break
		await create_timer(0.045).timeout
	for client:Client in clients:client.session.input_direction(Vector2.ZERO)
	return arrived

func wait_until(condition:Callable)->bool:
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		if condition.call():return true
		await process_frame
	return condition.call()

func expect(accepted:bool,message:String)->bool:
	checks+=1
	if not accepted:
		failures+=1
		push_error(message)
	return accepted

func finish()->void:
	for suffix:String in ["",".bak",".writer-lock"]:
		if FileAccess.file_exists(save_path+suffix):DirAccess.remove_absolute(save_path+suffix)
	print("MEADOW_ADVENTURE_NETWORK checks=%d failures=%d"%[checks,failures])
	quit(1 if failures else 0)
