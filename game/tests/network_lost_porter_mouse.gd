extends SceneTree
## Two independent player Sessions and a dedicated host over loopback WebSocket.
## The fixture opens B6. All movement and escort actions after joining use RPC.

const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const Porter=World.PORTER
const KEY:="porter-test-room"
const ALPHA:="porter-network-alpha"
const BETA:="porter-network-beta"

class Client:
	var session:Session
	var replies:Dictionary={}
	var shared_snapshots:=0
	var privacy_errors:=0

	func observe(snapshot:Dictionary,own_id:String)->void:
		var players:Dictionary=snapshot.get("players",{})
		for id in players:
			if str(id)==own_id:continue
			shared_snapshots+=1
			if players[id].has(Porter.FIELD):privacy_errors+=1
		var payload:=JSON.stringify(snapshot)
		if payload.contains(ALPHA) or payload.contains(BETA):privacy_errors+=1

	func person()->Dictionary:
		return session.snapshot.get("players",{}).get(session.own_id,{})

	func position()->Vector2:
		var player:=person()
		return Vector2(player.get("x",-100.0),player.get("y",-100.0))

	func stage()->int:
		return int(person().get(Porter.FIELD,Porter.Stage.WAITING))

	func ore()->int:
		return int(person().get("inventory",{}).get(Porter.REWARD_ITEM,0))

var save_path:="user://network-porter-%d.json"%Time.get_ticks_usec()
var serial:=0
var checks:=0
var failures:=0
var host:Session

func _initialize()->void:
	call_deferred("run")

func seed_room(adventure:bool)->bool:
	var fixture:=World.new()
	fixture.save_path=save_path
	fixture.state.picnic=true
	fixture.state.board=true
	fixture.state.mine_depths.unlocked=Porter.DEPTH
	fixture.state.mine_depths.pumped=24
	if adventure:fixture.state.world_mode="adventure"
	for token in [ALPHA,BETA]:
		fixture.add_player(token,"搬運測試")
		var player:Dictionary=fixture.state.players[token]
		player.merge({"region":Porter.REGION,"x":Porter.START.x,"y":Porter.START.y},true)
	fixture.active_tokens.clear()
	return fixture.save()

func run()->void:
	if not expect(seed_room(false),"Save a B6 room before either player begins"):
		finish()
		return
	var port:=start_host()
	if not expect(port>0,"Host listens over WebSocket"):
		finish()
		return
	var alpha:=await join(port,ALPHA,"海風")
	var beta:=await join(port,BETA,"潮聲")
	if not expect(not alpha.person().is_empty() and not beta.person().is_empty(),"Both clients enter B6"):
		finish()
		return
	expect(alpha.session.own_id!=beta.session.own_id,"Two distinct network identities")
	expect(await wait_until(func():return alpha.shared_snapshots>0 and beta.shared_snapshots>0),"Both clients see the other player")
	await act(alpha,Porter.Stage.WAITING,true)
	expect(beta.stage()==Porter.Stage.WAITING,"Alpha's greeting leaves Beta's escort untouched")
	await act(beta,Porter.Stage.WAITING,true)
	await act(alpha,Porter.Stage.TO_CRATE,false)
	expect(await walk(alpha,Porter.MIDDLE),"Alpha walks to the turn")
	await act(alpha,Porter.Stage.TO_MIDDLE,true)
	expect(beta.stage()==Porter.Stage.TO_MIDDLE,"Beta still needs to reach the turn")
	await act(alpha,Porter.Stage.TO_CRATE,false)
	expect(await walk(alpha,Vector2(24.5,26.4)) and await walk(alpha,Porter.DELIVERY),"Alpha follows the lane to the crate")
	await act(alpha,Porter.Stage.TO_CRATE,true)
	expect(alpha.ore()==0,"A delivered crate has not paid yet")
	await act(alpha,Porter.Stage.DELIVERED,true)
	await act(alpha,Porter.Stage.DELIVERED,false)
	expect(alpha.ore()==Porter.REWARD_COUNT and beta.ore()==0,"One gift goes only to Alpha")
	expect(await walk(beta,Porter.MIDDLE),"Beta walks to the turn")
	await act(beta,Porter.Stage.TO_MIDDLE,true)
	expect(alpha.privacy_errors+beta.privacy_errors==0,"Shared snapshots keep each escort stage and profile token private")
	alpha.session.shutdown()
	beta.session.shutdown()
	expect(host.shutdown(),"Host shuts down and saves after the first delivery")
	await process_frame

	port=start_host()
	if not expect(port>0,"A new host session opens the same save"):
		finish()
		return
	alpha=await join(port,ALPHA,"海風")
	beta=await join(port,BETA,"潮聲")
	if not expect(not alpha.person().is_empty() and not beta.person().is_empty(),"Both clients reconnect after host restart"):
		finish()
		return
	expect(alpha.stage()==Porter.Stage.REWARDED and alpha.ore()==Porter.REWARD_COUNT,"Alpha keeps one gift after restart")
	expect(beta.stage()==Porter.Stage.TO_CRATE and beta.ore()==0,"Beta resumes her own unfinished route")
	expect(await walk(beta,Vector2(24.5,26.4)) and await walk(beta,Porter.DELIVERY),"Beta follows the lane to the crate")
	await act(beta,Porter.Stage.TO_CRATE,true)
	await act(beta,Porter.Stage.DELIVERED,true)
	expect(beta.ore()==Porter.REWARD_COUNT and alpha.ore()==Porter.REWARD_COUNT,"Each player earns exactly one gift")
	expect(alpha.shared_snapshots>0 and beta.shared_snapshots>0 and alpha.privacy_errors+beta.privacy_errors==0,"Resumed sessions preserve privacy")
	alpha.session.shutdown()
	beta.session.shutdown()
	expect(host.shutdown(),"Save both completed escorts")
	var reloaded:=World.new()
	expect(reloaded.load_world(save_path) and not reloaded.recovered_from_backup,"Reload both claims from the primary save")
	for token in [ALPHA,BETA]:
		var player:Dictionary=reloaded.state.players.get(token,{})
		expect(player.get(Porter.FIELD)==Porter.Stage.REWARDED and player.get("inventory",{}).get(Porter.REWARD_ITEM)==Porter.REWARD_COUNT,"Primary save has one reward for "+token)
	await test_adventure()
	finish()

func test_adventure()->void:
	remove_fixture()
	save_path="user://network-porter-adventure-%d.json"%Time.get_ticks_usec()
	if not expect(seed_room(true),"Save an adventure room before either player begins"):return
	var port:=start_host()
	if not expect(port>0,"Start an adventure host"):return
	var alpha:=await join(port,ALPHA,"海風")
	expect(not alpha.session.snapshot.has("porter_watches"),"A solo adventurer can take the regular route")
	var beta:=await join(port,BETA,"潮聲")
	if not expect(not alpha.person().is_empty() and not beta.person().is_empty(),"Two adventurers enter B6"):return
	expect(await wait_until(func():return alpha.session.snapshot.get("porter_watches")==[false,false]),"The two lookout posts start unoccupied")
	await act(alpha,Porter.Stage.WAITING,true)
	expect(await walk(alpha,Porter.MIDDLE),"The lead reaches the turn")
	await act(alpha,Porter.Stage.TO_MIDDLE,false)
	expect(await walk(beta,Porter.WATCH_POINTS[0]),"The partner reaches the first lookout post")
	expect(await wait_until(func():return alpha.session.snapshot.get("porter_watches")==[true,false]),"The lead sees the turn guarded")
	await act(alpha,Porter.Stage.TO_MIDDLE,true)
	expect(await walk(alpha,Vector2(24.5,26.4)) and await walk(alpha,Porter.DELIVERY),"The lead reaches the delivery point")
	await act(alpha,Porter.Stage.TO_CRATE,false)
	expect(await walk(beta,Porter.WATCH_POINTS[1]),"The partner reaches the crateside lookout post")
	expect(await wait_until(func():return alpha.session.snapshot.get("porter_watches")==[false,true]),"The lead sees the crateside post guarded")
	await act(alpha,Porter.Stage.TO_CRATE,true)
	expect(await wait_until(func():return beta.stage()==Porter.Stage.DELIVERED),"Shared delivery creates a claim for the watcher")
	await act(alpha,Porter.Stage.DELIVERED,true)
	await act(beta,Porter.Stage.DELIVERED,true)
	await act(beta,Porter.Stage.DELIVERED,false)
	expect(alpha.ore()==Porter.REWARD_COUNT and beta.ore()==Porter.REWARD_COUNT,"An adventure team gets one gift per role")
	expect(alpha.privacy_errors+beta.privacy_errors==0,"The adventure UI reveals guards without private progress")
	alpha.session.shutdown()
	beta.session.shutdown()
	expect(host.shutdown(),"Save the adventure delivery")

func add_session()->Session:
	serial+=1
	var branch:=Node.new()
	branch.name="PorterPeer%d"%serial
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
	client.session.profile["token"]=token
	client.session.changed.connect(client.observe)
	client.session.action_completed.connect(func(sequence:int,action:String,result:Dictionary):
		client.replies[sequence]={"action":action,"ok":result.get("ok")}
	)
	if client.session.join("ws://127.0.0.1:%d"%port,port,nickname,KEY)==OK:
		await wait_until(func():return not client.person().is_empty())
	return client

func act(client:Client,stage:int,accepted:bool)->void:
	var step:=Porter.next_step(stage)
	var before:=client.stage()
	var sequence:=client.session.perform(step.action,step.cell)
	var replied:=await wait_until(func():return client.replies.has(sequence))
	expect(replied and client.replies[sequence]=={"action":step.action,"ok":accepted},"Correlated reply for "+str(step.action)+" accepted="+str(accepted))
	var target_stage:=stage+1 if accepted else before
	expect(await wait_until(func():return client.stage()==target_stage),"Own snapshot reaches stage %d"%target_stage)

func walk(client:Client,target:Vector2)->bool:
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline and client.position().distance_to(target)>0.2:
		client.session.input_direction((target-client.position()).limit_length())
		await create_timer(0.05).timeout
	client.session.input_direction(Vector2.ZERO)
	return client.position().distance_to(target)<=0.2

func wait_until(condition:Callable)->bool:
	var deadline:=Time.get_ticks_msec()+5000
	while Time.get_ticks_msec()<deadline:
		if condition.call():return true
		await process_frame
	return condition.call()

func expect(ok:bool,message:String)->bool:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)
	return ok

func remove_fixture()->void:
	for suffix in ["",".bak",".writer-lock"]:
		if FileAccess.file_exists(save_path+suffix):DirAccess.remove_absolute(save_path+suffix)

func finish()->void:
	remove_fixture()
	print("LOST_PORTER_MOUSE_NETWORK checks=%d failures=%d"%[checks,failures])
	quit(1 if failures else 0)
