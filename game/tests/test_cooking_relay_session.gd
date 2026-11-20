extends SceneTree
## P03 Cooking Relay two-client acceptance over a real dedicated host and real
## loopback WebSocket clients (isolated MultiplayerAPIs), built on the same
## harness as res://tests/network_egg_basket.gd.
##
## Fixture (disclosed): the saved room has picnic=true, a controlled start clock
## and two islanders standing on the sign. Stations are reached by moving the
## islander record in the HOST world (fixture teleport, never normal play);
## every game action itself goes through client Session.perform over the network.
## The timeout is crossed by jumping the host clock forward 241 s.
## NOT covered: exact notice wording, the 8-player cap, crash durability.
const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const CR=World.COOKING_RELAY
const ACTION:="cooking_relay"
const PUBLIC_KEY:="cooking_relay"
const ROOM:="cooking-relay-test"
const ALPHA:="cooking-relay-alpha"
const BETA:="cooking-relay-beta"
const GAMMA:="cooking-relay-gamma"
const START_TIME:=3000.0
const JUMP:=241.0
var sessions:Array[Session]=[]
var notices:Dictionary={}
var path:="user://cooking-relay-%d.json"%OS.get_process_id()
var checks:=0
var host:Session
var alpha:Session
var beta:Session
var gamma:Session
var port:=0

func _initialize() -> void:
	run.call_deferred()

func make_session(branch_name:String,token:String) -> Session:
	var branch:=Node.new()
	branch.name=branch_name
	root.add_child(branch)
	set_multiplayer(MultiplayerAPI.create_default_interface(),branch.get_path())
	var session:=Session.new()
	branch.add_child(session)
	session.profile={"token":token}
	sessions.append(session)
	notices[session]=[]
	session.notice.connect(func(message:String,ok:bool):notices[session].append({"message":message,"ok":ok}))
	return session

func wait_for(predicate:Callable,seconds:float=10.0) -> bool:
	var deadline:=Time.get_ticks_msec()+int(seconds*1000)
	while not predicate.call() and Time.get_ticks_msec()<deadline:
		await process_frame
	return predicate.call()

func check(condition:bool,message:String) -> bool:
	checks+=1
	if condition:return true
	push_error(message)
	finish(1)
	return false

func finish(code:int) -> void:
	Engine.time_scale=1.0
	for i in range(sessions.size()-1,-1,-1):
		if not sessions[i].shutting_down:sessions[i].shutdown()
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("COOKING_RELAY_SESSION checks=%d exit=%d"%[checks,code])
	quit(code)

# ------------------------------------------------------------------ fixture --

func seeded_world() -> bool:
	var world:=World.new()
	world.save_path=path
	world.state.picnic=true
	world.state.time=START_TIME
	for token in [ALPHA,BETA]:
		world.add_player(token,"Cook")
		put_record(world,token,CR.SIGN)
	return world.save()

func put_record(world:World,token:String,cell:Vector2i) -> void:
	world.state.players[token].x=cell.x+0.5
	world.state.players[token].y=cell.y+0.5

## Fixture teleport on the host, then wait until the client's own snapshot agrees.
func place(session:Session,token:String,cell:Vector2i) -> bool:
	put_record(host.world,token,cell)
	return await wait_for(func():
		var me:Dictionary=session.snapshot.get("players",{}).get(session.own_id,{})
		return absf(float(me.get("x",-99.0))-(cell.x+0.5))<0.05 and absf(float(me.get("y",-99.0))-(cell.y+0.5))<0.05)

func start_room() -> bool:
	var listener:=TCPServer.new()
	if listener.listen(0,"127.0.0.1")!=OK:return false
	port=listener.get_local_port()
	listener.stop()
	host=make_session("Host%d"%sessions.size(),"cooking-relay-host")
	return host.host(port,"Host",path,ROOM,"127.0.0.1",true,"websocket")==OK

func connect_client(branch_name:String,token:String) -> Session:
	var session:=make_session(branch_name,token)
	if session.join("ws://127.0.0.1:%d"%port,port,branch_name,ROOM)!=OK:return null
	await wait_for(func():return not session.own_id.is_empty() and not own(session).is_empty())
	return session

func stop_room(clients:Array) -> void:
	for client in clients:
		if client!=null and not client.shutting_down:client.shutdown()
	await process_frame
	host.shutdown()
	await process_frame

# ------------------------------------------------------------------ helpers --

func pub(session:Session) -> Dictionary:
	var value=session.snapshot.get(PUBLIC_KEY,{})
	return value if value is Dictionary else {}

func own(session:Session) -> Dictionary:
	var value=session.snapshot.get(CR.VIEW_KEY,{})
	return value if value is Dictionary else {}

func tray(session:Session) -> Array:
	var value=pub(session).get("tray",[])
	var out:Array=[]
	for item in value:out.append(str(item))
	return out

func me(session:Session) -> Dictionary:
	return session.snapshot.get("players",{}).get(session.own_id,{})

func bag(session:Session) -> Dictionary:
	var inventory=me(session).get("inventory",{})
	return inventory if inventory is Dictionary else {}

func action(session:Session,cell:Vector2i,extra:String) -> bool:
	await create_timer(0.10).timeout
	var seen:int=notices[session].size()
	session.perform(ACTION,cell,extra)
	if not await wait_for(func():return notices[session].size()>seen):return false
	return notices[session].back().ok

func in_sync(a:Session,b:Session) -> bool:
	return JSON.stringify(pub(a),"",true)==JSON.stringify(pub(b),"",true)

func round_of(session:Session) -> int:
	return int(pub(session).get("round",-1))

func wrong_item(items:Array) -> String:
	for id in CR.RECIPES:
		for item in CR.RECIPES[id].items:
			if not items.has(item):return str(item)
	return "not_an_ingredient"

# ----------------------------------------------------------------- scenario --

func run() -> void:
	if not check(seeded_world(),"Save a picnic room with two cooks on the sign"):return
	if not check(start_room(),"Start a dedicated WebSocket room"):return
	alpha=await connect_client("Alpha",ALPHA)
	beta=await connect_client("Beta",BETA)
	if not check(alpha!=null and beta!=null and not own(alpha).is_empty() and not own(beta).is_empty(),"Both clients entered and received their private view"):return
	var stations:Dictionary=CR.STATIONS
	if not check(CR.SIGN==Vector2i(40,33) and stations.has("prep") and stations.has("assembly") and stations.has("serve"),"Sign and prep/assembly/serve stations are declared"):return
	for name in ["prep","assembly","serve"]:
		if not check(stations[name] is Vector2i,"Station %s is a Vector2i"%name):return
	if not check(CR.VIEW_KEY=="own_cooking_relay" and not CR.RECIPES.is_empty(),"View key and recipe table are declared"):return
	for id in CR.RECIPES:
		if not check(CR.RECIPES[id].has("title") and CR.RECIPES[id].has("items") and not CR.RECIPES[id].items.is_empty(),"Recipe %s has a title and items"%id):return

	# Economy baseline (bags and purses of both cooks).
	var base_bag_a:=bag(alpha).duplicate(true)
	var base_bag_b:=bag(beta).duplicate(true)
	var base_coins_a:=int(me(alpha).get("coins",-1))
	var base_coins_b:=int(me(beta).get("coins",-1))

	# Idle view.
	var idle:=pub(alpha)
	if not check(str(idle.get("phase","idle"))=="idle" and own(alpha).get("unlocked")==true and own(alpha).get("can_start")==true,"Fresh room is idle, unlocked and startable"):return
	for key in ["unlocked","joined","practice","crew","can_start"]:
		if not check(own(alpha).has(key),"Private view carries %s"%key):return

	# Lobby: crew, minimum two, stale/foreign refusals.
	if not check(not await action(alpha,CR.STATIONS.prep,"crew"),"Crew can only be opened at the sign"):return
	if not check(await action(alpha,CR.SIGN,"crew"),"Alpha opens a crew lobby"):return
	if not check(await wait_for(func():return str(pub(beta).get("phase",""))=="lobby" and str(pub(beta).get("mode",""))=="crew"),"Beta sees the crew lobby"):return
	var round_id:=round_of(beta)
	if not check(round_id>=1 and own(alpha).get("joined")==true,"Opening the lobby makes alpha part of round %d"%round_id):return
	if not check(not await action(alpha,CR.SIGN,"begin:%d"%round_id),"Beginning with a single cook is refused (minimum two)"):return
	if not check(not await action(beta,CR.SIGN,"join:%d"%(round_id+7)),"A stale round join is refused"):return
	if not check(not await action(beta,CR.STATIONS.prep,"join:%d"%round_id),"Joining away from the sign is refused"):return
	if not check(await action(beta,CR.SIGN,"join:%d"%round_id),"Beta joins the lobby"):return
	if not check(not await action(beta,CR.SIGN,"join:%d"%round_id),"Joining twice is refused"):return
	if not check(not await action(alpha,CR.SIGN,"begin:%d"%(round_id+7)),"A stale begin is refused"):return
	if not check(await wait_for(func():return own(beta).get("joined")==true and own(alpha).get("can_begin")==true),"Both cooks are online and the crew is ready"):return
	if not check(await action(alpha,CR.SIGN,"begin:%d"%round_id),"Two cooks begin the round"):return
	if not check(await wait_for(func():return str(pub(alpha).get("phase",""))=="run" and str(pub(beta).get("phase",""))=="run"),"Both clients see the running round"):return
	var running:=pub(beta)
	var dish:=str(running.get("dish",""))
	if not check(CR.RECIPES.has(dish) and str(running.get("mode",""))=="crew" and own(alpha).get("crew")==false,"A running crew has a known dish and no unearned keepsake"):return
	var remaining:=float(running.get("remaining",-1))
	if not check(remaining>200.0 and remaining<=240.0,"About 240 seconds remain (%.1f)"%remaining):return
	if not check(running.has("guests") and tray(beta).is_empty() and running.get("plated")==false and int(running.get("score",-1))==0 and int(running.get("plates",-1))==0,"Fresh run: empty tray, nothing plated, score 0"):return
	var items:Array=CR.RECIPES[dish].items

	# A late joiner is rejected while the round is running.
	gamma=await connect_client("Gamma",GAMMA)
	if not check(gamma!=null,"Late joiner connects"):return
	if not check(await place(gamma,GAMMA,CR.SIGN),"Late joiner stands on the sign"):return
	if not check(not await action(gamma,CR.SIGN,"join:%d"%round_id) and own(gamma).get("joined")!=true,"Late join into a running round is rejected"):return

	# Station refusals, wrong prep and undo.
	if not check(not await action(alpha,CR.SIGN,"prep:%d:%s"%[round_id,items[0]]),"The sign cannot be used as the prep station"):return
	if not check(await place(alpha,ALPHA,stations.prep) and await place(beta,BETA,stations.prep),"Both cooks walk to prep"):return
	if not check(not await action(alpha,stations.prep,"prep:%d:%s"%[round_id+7,items[0]]),"Prep with a stale round id is refused"):return
	var bad:=wrong_item(items)
	var bad_ok:=await action(beta,stations.prep,"prep:%d:%s"%[round_id,bad])
	if not check(tray(alpha)==(([bad] as Array) if bad_ok else ([] as Array)),"A wrong ingredient only reaches the tray when accepted"):return
	if not check(await place(beta,BETA,stations.assembly),"Beta moves to assembly"):return
	if not check(not await action(beta,stations.assembly,"undo:%d"%(round_id+7)),"Undo with a stale round id is refused"):return
	if bad_ok:
		if not check(not await action(beta,stations.assembly,"plate:%d"%round_id),"A wrong tray cannot be plated"):return
		if not check(await action(beta,stations.assembly,"undo:%d"%round_id) and await wait_for(func():return tray(alpha).is_empty()),"Undo removes the wrong ingredient"):return
	if not check(not await action(beta,stations.assembly,"undo:%d"%round_id),"Undo on an empty tray is refused"):return
	if not check(await place(alpha,ALPHA,stations.prep),"Alpha at prep"):return
	for item in items:
		if not check(await action(alpha,stations.prep,"prep:%d:%s"%[round_id,item]),"Alpha preps %s"%item):return
	if not check(await wait_for(func():return tray(beta)==items and in_sync(alpha,beta)),"Both clients see the complete tray %s"%str(items)):return
	if not check(await action(beta,stations.assembly,"undo:%d"%round_id) and await wait_for(func():return tray(alpha).is_empty()),"Undo returns both ingredients"):return
	if not check(not await action(beta,stations.assembly,"plate:%d"%round_id),"An incomplete tray cannot be plated"):return
	for item:String in items:
		if not check(await action(alpha,stations.prep,"prep:%d:%s"%[round_id,item]),"Alpha re-preps "+item):return
	if not check(not await action(alpha,stations.prep,"plate:%d"%round_id),"Plating away from assembly is refused"):return
	if not check(not await action(beta,stations.assembly,"serve:%d"%round_id),"Serving before plating is refused"):return
	if not check(await action(beta,stations.assembly,"plate:%d"%round_id) and await wait_for(func():return pub(alpha).get("plated")==true),"Beta plates the complete meal"):return
	if not check(not await action(beta,stations.assembly,"serve:%d"%round_id),"Serving from assembly is refused"):return
	if not check(await place(alpha,ALPHA,stations.serve),"Alpha at the serving station"):return
	if not check(not await action(alpha,stations.serve,"serve:%d"%(round_id+7)),"Serving with a stale round id is refused"):return
	if not check(await action(alpha,stations.serve,"serve:%d"%round_id),"Alpha serves the meal"):return
	if not check(await wait_for(func():return int(pub(beta).get("score",0))==3 and int(pub(beta).get("plates",0))==1 and in_sync(alpha,beta)),"Both clients agree: one plate, +3 score"):return
	if not check(pub(beta).get("plated")==false and tray(beta).is_empty() and CR.RECIPES.has(str(pub(beta).get("dish",""))),"Serving clears the tray and sets the next dish"):return

	# Work stays staged across a restart.
	var next_items:Array=CR.RECIPES[str(pub(beta).get("dish"))].items
	if not check(await place(alpha,ALPHA,stations.prep) and await action(alpha,stations.prep,"prep:%d:%s"%[round_id,next_items[0]]),"Stage one ingredient for the next dish"):return
	if not check(await wait_for(func():return tray(beta).size()==1),"Staged tray reaches beta"):return
	var staged:=pub(beta).duplicate(true)
	await stop_room([alpha,beta,gamma])
	if not check(start_room(),"Restart the room from its save"):return
	alpha=await connect_client("AlphaAgain",ALPHA)
	beta=await connect_client("BetaAgain",BETA)
	if not check(alpha!=null and beta!=null and await wait_for(func():return str(pub(beta).get("phase",""))=="run"),"Both cooks return to the running round"):return
	var restored:=pub(beta)
	if not check(round_of(beta)==round_id and str(restored.get("dish"))==str(staged.dish) and tray(beta)==tray(alpha) and tray(beta).size()==1 and tray(beta)[0]==str(next_items[0]),"Dish and staged tray survive the restart"):return
	if not check(int(restored.get("score",-1))==3 and int(restored.get("plates",-1))==1 and str(restored.get("mode",""))=="crew","Score, plates and crew mode survive the restart"):return
	if not check(float(restored.get("remaining",-1))>0.0 and float(restored.get("remaining",-1))<=240.0,"The clock still has time after restart"):return
	if not check(own(alpha).get("joined")==true and own(beta).get("joined")==true,"Both cooks are still on the crew"):return

	# Timeout: jump the host clock 241 seconds.
	host.world.state.time=float(host.world.state.time)+JUMP
	if not check(await wait_for(func():return str(pub(alpha).get("phase",""))=="results" and str(pub(beta).get("phase",""))=="results"),"Clock jump of 241 s ends the round in results"):return
	if not check(int(pub(beta).get("score",-1))==3 and int(pub(beta).get("plates",-1))==1,"Results keep the score and plates"):return
	if not check(await wait_for(func():return own(alpha).get("crew")==true and own(beta).get("crew")==true),"Both cooks who worked earn the crew keepsake"):return
	if not check(not await action(alpha,stations.prep,"prep:%d:%s"%[round_id,next_items[0]]),"No prepping after the timeout"):return
	if not check(not await action(beta,CR.SIGN,"join:%d"%round_id) and not await action(alpha,CR.SIGN,"begin:%d"%round_id),"Stale join and begin after results are rejected"):return

	# Practice is a straight run for one cook.
	if not check(await place(alpha,ALPHA,CR.SIGN) and await action(alpha,CR.SIGN,"practice"),"Alpha starts a practice run"):return
	if not check(await wait_for(func():return str(pub(alpha).get("phase",""))=="run" and str(pub(alpha).get("mode",""))=="practice" and own(alpha).get("practice")==false),"Practice starts directly without pre-awarding a keepsake"):return
	if not check(round_of(alpha)>round_id and tray(alpha).is_empty() and int(pub(alpha).get("score",-1))==0,"Practice is a new round with a clean tray and score"):return
	var practice_items:Array=CR.RECIPES[str(pub(alpha).get("dish"))].items
	if not check(await place(alpha,ALPHA,stations.prep) and await action(alpha,stations.prep,"prep:%d:%s"%[round_of(alpha),practice_items[0]]),"Practice prep works"):return
	if not check(not await action(beta,CR.SIGN,"join:%d"%round_id),"Joining a previous round id is rejected"):return

	# No normal economy effects and private records only.
	for pair in [[alpha,base_bag_a,base_coins_a],[beta,base_bag_b,base_coins_b]]:
		var client:Session=pair[0]
		if not check(await wait_for(func():return JSON.stringify(bag(client),"",true)==JSON.stringify(pair[1],"",true) and int(me(client).get("coins",-2))==int(pair[2])),"Bags and coins are exactly as before the activity"):return
	for token in [ALPHA,BETA]:
		var record:Dictionary=host.world.state.players[token]
		if not check(not record.has(PUBLIC_KEY) or record.get(PUBLIC_KEY) is Dictionary,"Host record for %s is a plain dictionary when present"%token):return
	for client in [alpha,beta]:
		var dump:=JSON.stringify(client.snapshot)
		var clean:=true
		for id in client.snapshot.get("players",{}):
			var person=client.snapshot.players[id]
			if person is Dictionary and (person.has(CR.VIEW_KEY) or person.has(PUBLIC_KEY)):clean=false
		if not check(clean and dump.count("\"%s\""%CR.VIEW_KEY)==1,"Snapshot has exactly one private view and none on other players"):return
		for token in [ALPHA,BETA,GAMMA]:
			if not check(not dump.contains(token),"Snapshot never contains a private token"):return
	finish(0)
