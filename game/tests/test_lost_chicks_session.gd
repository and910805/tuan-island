extends SceneTree
## P05 Lost Chicks two/three-client acceptance over a real dedicated host and real
## loopback WebSocket clients (isolated MultiplayerAPIs), same harness as
## res://tests/test_cooking_relay_session.gd.
##
## Fixture (disclosed): the saved room has picnic=true, a controlled start clock
## and two islanders standing on the sign. Walking is done by moving the islander
## record in the HOST world (fixture teleport, never normal play); lures, returns,
## follow-bucket release and scoring then happen through the automatic world step in
## real time. Every game action goes through client Session.perform over the network
## with a 0.10 s pause before it (session rate limit).
## Expiry is crossed by jumping the host clock past the reported remaining time.
## ASSUMPTIONS (World.LOST_CHICKS is not read from source): a round that is opened
## by "start" at the sign makes the starter a participant, every other online
## player must "join:<round>" (the test joins only when not already joined), the
## chick list order is stable within a round, and a round ends in "results" when
## the last chick is home. NOT covered: exact notice wording, crash durability.
const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const LC=World.LOST_CHICKS
const ACTION:="lost_chicks"
const PUBLIC_KEY:="lost_chicks"
const ROOM:="lost-chicks-test"
const ALPHA:="lost-chicks-alpha"
const BETA:="lost-chicks-beta"
const GAMMA:="lost-chicks-gamma"
const START_TIME:=3000.0
var sessions:Array[Session]=[]
var notices:Dictionary={}
var path:="user://lost-chicks-%d.json"%OS.get_process_id()
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
	print("LOST_CHICKS_SESSION checks=%d exit=%d"%[checks,code])
	quit(code)

# ------------------------------------------------------------------ fixture --

func seeded_world() -> bool:
	var world:=World.new()
	world.save_path=path
	world.state.picnic=true
	world.state.time=START_TIME
	for token in [ALPHA,BETA]:
		world.add_player(token,"Herder")
		put_record(world,token,LC.SIGN)
	return world.save()

func put_record(world:World,token:String,cell:Vector2i) -> void:
	world.state.players[token].x=cell.x+0.5
	world.state.players[token].y=cell.y+0.5

## Fixture teleport on the host, then wait until the client's own snapshot agrees.
func place(session:Session,token:String,cell:Vector2i) -> bool:
	put_record(host.world,token,cell)
	return await wait_for(func():
		var p:Dictionary=session.snapshot.get("players",{}).get(session.own_id,{})
		return absf(float(p.get("x",-99.0))-(cell.x+0.5))<0.05 and absf(float(p.get("y",-99.0))-(cell.y+0.5))<0.05)

func start_room() -> bool:
	var listener:=TCPServer.new()
	if listener.listen(0,"127.0.0.1")!=OK:return false
	port=listener.get_local_port()
	listener.stop()
	host=make_session("Host%d"%sessions.size(),"lost-chicks-host")
	return host.host(port,"Host",path,ROOM,"127.0.0.1",true,"websocket")==OK

func connect_client(branch_name:String,token:String) -> Session:
	var session:=make_session(branch_name,token)
	if session.join("ws://127.0.0.1:%d"%port,port,branch_name,ROOM)!=OK:return null
	await wait_for(func():return not session.own_id.is_empty() and not own(session).is_empty())
	return session

# ------------------------------------------------------------------ helpers --

func pub(session:Session) -> Dictionary:
	var value=session.snapshot.get(PUBLIC_KEY,{})
	return value if value is Dictionary else {}

func own(session:Session) -> Dictionary:
	var value=session.snapshot.get(LC.VIEW_KEY,{})
	return value if value is Dictionary else {}

func me(session:Session) -> Dictionary:
	return session.snapshot.get("players",{}).get(session.own_id,{})

func bag(session:Session) -> Dictionary:
	var inventory=me(session).get("inventory",{})
	return inventory if inventory is Dictionary else {}

func phase(session:Session) -> String:
	return str(pub(session).get("phase","idle"))

func round_of(session:Session) -> int:
	return int(pub(session).get("round",-1))

func chicks(session:Session) -> Array:
	var value=pub(session).get("chicks",[])
	return value if value is Array else []

func status_of(session:Session,index:int) -> String:
	var list:=chicks(session)
	if index<0 or index>=list.size() or not (list[index] is Dictionary):return ""
	return str(list[index].get("status",""))

func count(session:Session,status:String) -> int:
	var n:=0
	for chick in chicks(session):
		if chick is Dictionary and str(chick.get("status",""))==status:n+=1
	return n

func cell_of(session:Session,index:int) -> Vector2i:
	var chick:Dictionary=chicks(session)[index]
	return Vector2i(floori(float(chick.get("x",0.0))),floori(float(chick.get("y",0.0))))

func first_lost(session:Session) -> int:
	for i in chicks(session).size():
		if status_of(session,i)=="lost":return i
	return -1

func action(session:Session,cell:Vector2i,extra:String) -> bool:
	await create_timer(0.10).timeout
	var seen:int=notices[session].size()
	session.perform(ACTION,cell,extra)
	if not await wait_for(func():return notices[session].size()>seen):return false
	return notices[session].back().ok

func in_sync(a:Session,b:Session) -> bool:
	return JSON.stringify(pub(a),"",true)==JSON.stringify(pub(b),"",true)

func in_area(cell:Vector2i) -> bool:
	return LC.AREA.has_point(cell)

## Walk one person to a lost chick, wait for the automatic lure, walk to the pen
## and wait for the automatic return. Returns the chick index or -1.
func herd(session:Session,token:String,index:int) -> int:
	if not await place(session,token,cell_of(session,index)):return -1
	if not await wait_for(func():return status_of(session,index)=="follow"):return -1
	if not await place(session,token,LC.PEN):return -1
	if not await wait_for(func():return status_of(session,index)=="home"):return -1
	return index

func economy(session:Session) -> String:
	return JSON.stringify([bag(session),me(session).get("coins",null)],"",true)

func farms() -> String:
	var out:={}
	for key in ["crops","objects"]:
		if host.world.state.has(key):out[key]=host.world.state[key]
	return JSON.stringify(out,"",true)

# ----------------------------------------------------------------- scenario --

func run() -> void:
	if not check(seeded_world(),"Save a picnic room with two islanders on the sign"):return
	if not check(start_room(),"Start a dedicated WebSocket room"):return
	alpha=await connect_client("Alpha",ALPHA)
	beta=await connect_client("Beta",BETA)
	if not check(alpha!=null and beta!=null and not own(alpha).is_empty() and not own(beta).is_empty(),"Both clients entered and received their private view"):return

	# Declarations.
	if not check(LC.VIEW_KEY=="own_lost_chicks" and LC.SIGN==Vector2i(49,40) and LC.PEN==Vector2i(51,40) and LC.AREA==Rect2i(47,37,10,9),"Sign, pen, area and view key are declared"):return
	if not check(LC.SOLO_SPOTS==[Vector2i(49,42),Vector2i(52,42)],"Two solo spots are declared"):return
	if not check(LC.CREW_SPOTS.size()==6,"Six crew spots are declared"):return
	for cell in LC.SOLO_SPOTS+LC.CREW_SPOTS:
		if not check(in_area(cell),"Spot %s lies in the area"%str(cell)):return

	# Economy and farm baseline.
	var base_a:=economy(alpha)
	var base_b:=economy(beta)
	var base_farms:=farms()

	# Idle view.
	if not check(phase(alpha)=="idle" and own(alpha).get("unlocked")==true and own(alpha).has("joined"),"Fresh room is idle, unlocked and has a joined flag"):return
	if not check(chicks(alpha).is_empty() or count(alpha,"home")==chicks(alpha).size(),"No chick is lost while idle"):return

	# Start refusals, then a crew round (two active home players).
	if not check(not await action(alpha,LC.PEN,"start"),"Starting away from the sign is refused"):return
	if not check(not await action(alpha,LC.SIGN,"join:1"),"Joining while idle is refused"):return
	if not check(await action(alpha,LC.SIGN,"start"),"Alpha starts a round at the sign"):return
	if not check(await wait_for(func():return phase(alpha)=="run" and phase(beta)=="run"),"Both clients see the running round"):return
	var round_id:=round_of(beta)
	var running:=pub(beta)
	if not check(round_id>=1 and str(running.get("mode",""))=="crew" and own(alpha).get("joined")==true,"Two active players make a crew round that alpha has joined"):return
	if not check(chicks(beta).size()==LC.CREW_SPOTS.size() and int(running.get("total",-1))==6 and int(running.get("score",-1))==0 and int(running.get("returned",-1))==0,"Crew round: six lost chicks, score 0, none returned"):return
	if not check(count(beta,"lost")==6 and float(running.get("remaining",-1))>0.0,"All chicks start lost with time remaining"):return
	for i in 6:
		if not check(cell_of(beta,i)==LC.CREW_SPOTS[i],"Chick %d starts inside the area"%i):return
	if not check(in_sync(alpha,beta),"Both clients agree on the public view"):return

	# Stale / invalid commands.
	if not check(not await action(alpha,LC.SIGN,"join:%d"%round_id),"Joining twice is refused"):return
	if not check(not await action(alpha,LC.SIGN,"leave:%d"%(round_id+7)),"A stale leave is refused"):return
	if not check(not await action(beta,LC.SIGN,"join:%d"%(round_id+7)),"A stale join is refused"):return
	if not check(not await action(beta,LC.PEN,"join:%d"%round_id) ,"Join away from the sign is refused"):return
	if not check(not await action(alpha,LC.SIGN,"start"),"Starting during a running round is refused"):return
	if not check(await wait_for(func():return own(beta).get("joined")==true) or await action(beta,LC.SIGN,"join:%d"%round_id),"Beta takes part in the round"):return
	if not check(await wait_for(func():return own(beta).get("joined")==true),"Beta's private view shows joined"):return

	# Lure: two people, one chick follows each, click not required.
	var spot_a:int=0
	var spot_b:int=2
	if not check(await place(alpha,ALPHA,LC.CREW_SPOTS[spot_a]) and await place(beta,BETA,LC.CREW_SPOTS[spot_b]),"Alpha and beta walk to two different chicks"):return
	if not check(await wait_for(func():return status_of(alpha,spot_a)=="follow" and status_of(alpha,spot_b)=="follow"),"Approaching lures each chick automatically"):return
	if not check(count(alpha,"follow")==2 and count(alpha,"lost")==4,"Exactly one chick follows per person"):return
	# Walking close to another free chick must not give alpha a second one.
	if not check(await place(alpha,ALPHA,LC.CREW_SPOTS[1]),"Alpha walks next to a third chick"):return
	await create_timer(1.5).timeout
	if not check(count(alpha,"follow")==2 and count(alpha,"home")==0,"A person already leading a chick lures no second one"):return

	# Return to the pen: shared score.
	if not check(await place(alpha,ALPHA,LC.PEN),"Alpha walks to the pen"):return
	if not check(await wait_for(func():return count(alpha,"home")==1 and int(pub(beta).get("score",0))==2 and int(pub(beta).get("returned",0))==1),"One chick returns and both clients see 2 shared points"):return
	if not check(count(beta,"follow")==1 and int(pub(alpha).get("remaining",-1))>=0,"Beta's chick keeps following"):return
	if not check(await place(beta,BETA,LC.PEN),"Beta walks to the pen"):return
	if not check(await wait_for(func():return int(pub(alpha).get("score",0))==4 and int(pub(alpha).get("returned",0))==2 and count(alpha,"home")==2 and in_sync(alpha,beta)),"Second chick returns: shared score 4, both clients in sync"):return

	# Late joiner: connects mid-round, joins, leads a chick, then disconnects.
	gamma=await connect_client("Gamma",GAMMA)
	if not check(gamma!=null,"Late joiner connects"):return
	if not check(await place(gamma,GAMMA,LC.SIGN),"Late joiner stands on the sign"):return
	if not check(own(gamma).get("joined")!=true,"Late joiner is not joined before asking"):return
	if not check(not await action(gamma,LC.SIGN,"join:%d"%(round_id+7)) and own(gamma).get("joined")!=true,"Late join with a stale round is refused"):return
	if not check(await action(gamma,LC.SIGN,"join:%d"%round_id) and await wait_for(func():return own(gamma).get("joined")==true),"Late join into the running round is accepted"):return
	if not check(chicks(gamma).size()==6 and int(pub(gamma).get("score",-1))==4,"Late joiner sees the shared score and chicks"):return
	var lost:int=first_lost(gamma)
	if not check(lost>=0,"A lost chick remains for the late joiner"):return
	if not check(await place(gamma,GAMMA,cell_of(gamma,lost)) and await wait_for(func():return status_of(alpha,lost)=="follow"),"Late joiner lures a chick"):return
	var followed:=lost
	gamma.shutdown()
	if not check(await wait_for(func():return status_of(alpha,followed)=="lost" and count(alpha,"follow")==0,10.0),"Disconnect releases the followed chick back to lost"):return
	if not check(int(pub(alpha).get("score",-1))==4 and phase(alpha)=="run","Disconnect gives no points and the round keeps running"):return

	# Remaining players finish the round.
	var turn:=0
	while count(alpha,"home")<chicks(alpha).size() and turn<8:
		var idx:=first_lost(alpha)
		if not check(idx>=0,"A lost chick is left to herd"):return
		var who_session:=alpha if turn%2==0 else beta
		var who_token:=ALPHA if turn%2==0 else BETA
		if not check(await herd(who_session,who_token,idx)==idx,"Chick %d is lured and returned"%idx):return
		turn+=1
	if not check(await wait_for(func():return phase(alpha)=="results" and phase(beta)=="results" and in_sync(alpha,beta)),"Both clients reach results"):return
	var done:=pub(alpha)
	if not check(int(done.get("score",-1))==12 and int(done.get("returned",-1))==6 and count(alpha,"home")==6,"All six chicks home: 12 points, six returned"):return
	if not check(not await action(alpha,LC.SIGN,"join:%d"%round_id) and not await action(beta,LC.SIGN,"leave:%d"%round_id),"Stale join and leave after results are rejected"):return

	# Second round: leave releases, expiry sends the rest home without points.
	if not check(await place(alpha,ALPHA,LC.SIGN) and await place(beta,BETA,LC.SIGN),"Both walk back to the sign"):return
	if not check(await action(alpha,LC.SIGN,"start") and await wait_for(func():return phase(alpha)=="run" and round_of(alpha)>round_id),"Alpha starts a second round"):return
	var second:=round_of(alpha)
	if not check(await wait_for(func():return count(alpha,"lost")==chicks(alpha).size() and chicks(alpha).size()>0 and int(pub(alpha).get("score",-1))==0),"Second round is fresh: all lost, score 0"):return
	if not check(not await action(beta,LC.SIGN,"join:%d"%round_id),"A previous round id cannot be joined"):return
	if not check(await wait_for(func():return own(beta).get("joined")==true) or await action(beta,LC.SIGN,"join:%d"%second),"Beta takes part in round two"):return
	if not check(await wait_for(func():return own(beta).get("joined")==true),"Beta shows joined in round two"):return
	if not check(await herd(alpha,ALPHA,0)==0 and await wait_for(func():return int(pub(beta).get("score",0))==2),"Alpha returns one chick for 2 points"):return
	if not check(await place(beta,BETA,cell_of(beta,1)) and await wait_for(func():return status_of(beta,1)=="follow"),"Beta lures a chick"):return
	if not check(await place(beta,BETA,LC.SIGN) and await action(beta,LC.PEN,"leave:%d"%second),"Beta can leave away from the sign"):return
	if not check(await wait_for(func():return own(beta).get("joined")==false and status_of(alpha,1)=="lost"),"Leaving releases beta's chick"):return
	if not check(not await action(beta,LC.SIGN,"leave:%d"%second),"Leaving twice is refused"):return
	if not check(await place(alpha,ALPHA,cell_of(alpha,2)) and await wait_for(func():return status_of(alpha,2)=="follow"),"Alpha leads one more chick"):return
	if not check(host.world.save(),"Persist the staged round"):return
	var resumed:=World.new()
	if not check(resumed.load_world(path),"Read the live round from disk as a fresh server"):return
	var recovered:=LC.public_view(resumed.state)
	if not check(recovered.phase=="run" and int(recovered.score)==2 and int(recovered.returned)==1,"Restart preserves the active round and confirmed score"):return
	if not check(recovered.chicks[2].status=="lost" and not LC.view(resumed.state,ALPHA).joined,"No borrowed bucket or follower stays attached after a restart"):return
	var left:=float(pub(alpha).get("remaining",-1))
	if not check(left>0.0,"The clock is still running (%.1f)"%left):return
	host.world.state.time=float(host.world.state.time)+left+5.0
	if not check(await wait_for(func():return phase(alpha)=="results" and phase(beta)=="results"),"Clock jump past the deadline ends the round"):return
	if not check(count(alpha,"home")==chicks(alpha).size() and int(pub(alpha).get("score",-1))==2,"Expiry sends every chick home with no extra points"):return
	if not check(not await action(alpha,LC.SIGN,"leave:%d"%second) and not await action(beta,LC.SIGN,"join:%d"%second),"Stale join and leave after expiry are rejected"):return
	await create_timer(1.5).timeout
	if not check(int(pub(alpha).get("score",-1))==2 and phase(alpha)=="results","Score stays 2 after waiting more real time"):return

	# Ordinary economy and farms are untouched; views are private.
	if not check(await wait_for(func():return economy(alpha)==base_a and economy(beta)==base_b),"Bags and coins are exactly as before the activity"):return
	if not check(farms()==base_farms,"Ordinary farm state is unchanged"):return
	for client in [alpha,beta]:
		var dump:=JSON.stringify(client.snapshot)
		for id in client.snapshot.get("players",{}):
			var person=client.snapshot.players[id]
			if not check(not (person is Dictionary and (person.has(LC.VIEW_KEY) or person.has(PUBLIC_KEY))),"Other players carry no lost-chick view"):return
		if not check(dump.count("\"%s\""%LC.VIEW_KEY)==1,"Snapshot has exactly one private view"):return
		for token in [ALPHA,BETA,GAMMA]:
			if not check(not dump.contains(token),"Snapshot never contains a private token"):return
	finish(0)
