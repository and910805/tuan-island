extends SceneTree
## Party Cart (World.PARTY_CART) three-client acceptance over a real dedicated host and
## real loopback WebSocket clients (isolated MultiplayerAPIs), same harness as
## res://tests/test_lost_chicks_session.gd / test_cooking_relay_session.gd.
##
## Fixture (disclosed): the saved room has NO picnic and NO story flags; the only gate is the
## world-wide Bobo stage-2 unlock, seeded as one player's saved bond_goals (see seeded_world); a controlled start clock and three islanders standing in
## Jinguashi on the gallery entrance. Walking is done by moving the islander record in the
## HOST world (fixture teleport, never normal play). The cart itself rolls only through
## the server's real-time world step; every game action goes through client
## Session.perform over the network with a >=0.10 s pause before it (session rate limit).
## Expiry is crossed by jumping the host clock past the reported remaining time.
## ASSUMPTIONS (World.PARTY_CART is not read from source, it did not exist when this was
## written): push / switch / unload are performed with the action cell equal to the
## cell of the cart's current stop and the player standing there; clear is performed at
## the rock cell; a "start" at the sign makes the starter joined; a new round starts with
## at least one rock blocking; "players" in the public view is a count/list/dict of the
## joined online players; a round expires into "results" when the clock passes remaining.
## NOT covered: exact notice wording, the 4-player cap (only three clients), crash durability.
const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const PC=World.PARTY_CART
const ACTION:="party_cart"
const PUBLIC_KEY:="party_cart"
const VIEW_KEY:="own_party_cart"
const REGION:="cart_gallery"
const ROOM:="party-cart-test"
const ALPHA:="party-cart-alpha"
const BETA:="party-cart-beta"
const GAMMA:="party-cart-gamma"
const START_TIME:=3000.0
const SIGN:=Vector2i(13,17)
const ENTRY:=Vector2i(28,25)
const EXIT:=Vector2i(11,20)
const STOPS:Array[Vector2i]=[Vector2i(15,20),Vector2i(19,20),Vector2i(22,18),Vector2i(22,22),Vector2i(25,20),Vector2i(28,20)]
const CLEAR:Dictionary={"north":Vector2i(21,18),"south":Vector2i(21,22)}
const SEGMENT:=1.8
var sessions:Array[Session]=[]
var watchers:Array[Session]=[]
var notices:Dictionary={}
var path:="user://party-cart-%d.json"%OS.get_process_id()
var checks:=0
var host:Session
var alpha:Session
var beta:Session
var gamma:Session
var port:=0

func _initialize() -> void:
	create_timer(240.0,true,false,true).timeout.connect(func():
		push_error("watchdog fired before the scenario completed")
		finish(1))
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
	print("PARTY_CART_SESSION checks=%d exit=%d"%[checks,code])
	quit(code)

# ------------------------------------------------------------------ fixture --

func seeded_world() -> bool:
	var world:=World.new()
	world.save_path=path
	world.state.time=START_TIME
	for token in [ALPHA,BETA,GAMMA]:
		world.add_player(token,"Carter")
		world.state.players[token]["region"]="jinguashi"
		put_record(world,token,ENTRY)
	# T066 N03-2: the gallery is open to everyone once ONE player has Bobo stage 2. Only ALPHA
	# carries that (schema-valid) completion; BETA and GAMMA enter on the world-wide unlock.
	world.state.players[ALPHA]["bonds"]={"bobo":{"points":6,"talk_day":-1,"gift_day":-1}}
	world.state.players[ALPHA]["bond_goals"]={"bobo":{"2":"siding"}}
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
	host=make_session("Host%d"%sessions.size(),"party-cart-host")
	return host.host(port,"Host",path,ROOM,"127.0.0.1",true,"websocket")==OK

func connect_client(branch_name:String,token:String) -> Session:
	var session:=make_session(branch_name,token)
	if session.join("ws://127.0.0.1:%d"%port,port,branch_name,ROOM)!=OK:return null
	if not await wait_for(func():return not session.own_id.is_empty() and session.snapshot.get("players",{}).has(session.own_id)):return null
	return session

# ------------------------------------------------------------------ helpers --

func pub(session:Session) -> Dictionary:
	var value=session.snapshot.get(PUBLIC_KEY,{})
	return value if value is Dictionary else {}

func own(session:Session) -> Dictionary:
	var value=session.snapshot.get(VIEW_KEY,{})
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

func stop_of(session:Session) -> int:
	return int(pub(session).get("stop",-9))

func to_of(session:Session) -> int:
	return int(pub(session).get("to",-9))

func branch_of(session:Session) -> String:
	return str(pub(session).get("branch",""))

func rocks_of(session:Session) -> Dictionary:
	var value=pub(session).get("rocks",{})
	return value if value is Dictionary else {}

func rocked(session:Session,which:String) -> bool:
	return rocks_of(session).get(which)==true

func score_of(session:Session) -> int:
	return int(pub(session).get("score",-1))

func delivered_of(session:Session) -> int:
	return int(pub(session).get("delivered",-1))

func psize(session:Session) -> int:
	var value=pub(session).get("players",0)
	if value is Array or value is Dictionary:return value.size()
	return int(value)

func region_of(session:Session) -> String:
	return str(session.snapshot.get("region_id",""))

func action(session:Session,cell:Vector2i,extra:String) -> bool:
	await create_timer(0.10).timeout
	var seen:int=notices[session].size()
	session.perform(ACTION,cell,extra)
	if not await wait_for(func():return notices[session].size()>seen):return false
	return notices[session].back().ok

## Shared view without the continuously ticking countdown.
func shared(session:Session) -> String:
	var view:=pub(session).duplicate(true)
	view.erase("remaining")
	return JSON.stringify(view,"",true)

func all_sync() -> bool:
	for w in watchers:
		if shared(w)!=shared(watchers[0]):return false
	return true

func all_at(stop:int,to:int) -> bool:
	for w in watchers:
		if stop_of(w)!=stop or to_of(w)!=to:return false
	return true

func all_rock(which:String,value:bool) -> bool:
	for w in watchers:
		if rocked(w,which)!=value:return false
	return true

func all_branch(which:String) -> bool:
	for w in watchers:
		if branch_of(w)!=which:return false
	return true

func other(which:String) -> String:
	return "south" if which=="north" else "north"

func next_stop(from:int,which:String) -> int:
	match from:
		0:return 1
		1:return 2 if which=="north" else 3
		2,3:return 4
		4:return 5
	return -1

func economy(session:Session) -> String:
	return JSON.stringify([bag(session),me(session).get("coins",null)],"",true)

func farms() -> String:
	var out:={}
	for key in ["crops","objects","layers","chests","trees","buildings"]:
		if host.world.state.has(key):out[key]=host.world.state[key]
	return JSON.stringify(out,"",true)

func enter_gallery(session:Session) -> bool:
	if not await action(session,ENTRY,"enter"):return false
	return await wait_for(func():return region_of(session)==REGION)

## Waits for a push that was accepted to run: synchronized departure, autonomous timed
## segment, synchronized landing. Returns false after a failed check.
func observe_roll(from:int,target:int) -> bool:
	if not check(await wait_for(func():
		for w in watchers:
			if to_of(w)!=target:return false
		return true),"Every client sees the cart depart toward stop %d"%target):return false
	var departed_at:=Time.get_ticks_msec()
	if not check(all_at(from,target) or all_at(target,-1),"Rolling cart reports its old stop %d and target %d consistently"%[from,target]):return false
	if all_at(from,target):
		var span:=float(pub(watchers[0]).get("arrives",-1.0))-float(pub(watchers[0]).get("departed",-1.0))
		if not check(absf(span-SEGMENT)<0.25,"Segment lasts about %.1f s (reported %.2f)"%[SEGMENT,span]):return false
		if not check(await wait_for(func():return all_sync() or all_at(target,-1),2.0) and all_sync() or all_at(target,-1),"Departure state is identical on every client"):return false
	if not check(await wait_for(func():return all_at(target,-1),8.0),"Cart lands at stop %d on every client"%target):return false
	var elapsed:=Time.get_ticks_msec()-departed_at
	if not check(elapsed>=900 and elapsed<=7000,"Landing took genuine server time (%d ms)"%elapsed):return false
	return await wait_for(func():return all_sync(),3.0)

func clear_rock(who:Session,token:String,rid:int,which:String) -> bool:
	if not check(await place(who,token,CLEAR[which]),"Walk to the %s rock"%which):return false
	if not check(not await action(who,STOPS[1],"clear:%d:%s"%[rid,which]),"Clearing away from the rock is refused"):return false
	if not check(not await action(who,CLEAR[which],"clear:%d:%s"%[rid+7,which]),"A stale clear is refused"):return false
	if not check(not await action(who,CLEAR[which],"clear:%d:%s"%[rid,"east"]),"Clearing an unknown track is refused"):return false
	if not check(rocked(who,which),"The %s rock is still blocking before the clear"%which):return false
	if not check(await action(who,CLEAR[which],"clear:%d:%s"%[rid,which]),"Clearing the %s rock works"%which):return false
	if not check(await wait_for(func():return all_rock(which,false)),"Every client sees the %s rock gone"%which):return false
	if not check(not await action(who,CLEAR[which],"clear:%d:%s"%[rid,which]),"Clearing an already clear track is refused"):return false
	return true

## Push the stationary cart one segment, handling the branch rock on the way.
func roll(who:Session,token:String,rid:int) -> bool:
	var from:=stop_of(who)
	if not check(to_of(who)==-1 and from>=0 and from<5,"Cart is stationary at a pushable stop (stop %d)"%from):return false
	if not check(await place(who,token,STOPS[from]),"Walk to stop %d"%from):return false
	if from==1:
		var chosen:=branch_of(who)
		if rocked(who,chosen):
			if not check(not await action(who,STOPS[1],"push:%d"%rid),"Push onto the blocked %s track is refused"%chosen):return false
			await create_timer(0.3).timeout
			if not check(all_at(1,-1) and all_branch(chosen),"A refused push leaves the cart parked at 1"):return false
			if not await clear_rock(who,token,rid,chosen):return false
			if not check(await place(who,token,STOPS[1]),"Back to stop 1"):return false
	var target:=next_stop(from,branch_of(who))
	if not check(await action(who,STOPS[from],"push:%d"%rid),"Push from stop %d is accepted"%from):return false
	return await observe_roll(from,target)

## Unload at stop 5 and check score, reset and counter.
func unload(who:Session,token:String,rid:int,delivered:int) -> bool:
	if not check(await place(who,token,STOPS[5]),"Walk to the unloading stop"):return false
	var score:=score_of(who)
	if not check(not await action(who,STOPS[5],"unload:%d"%(rid+7)),"A stale unload is refused"):return false
	if not check(await action(who,STOPS[5],"unload:%d"%rid),"Unload at stop 5 is accepted"):return false
	if not check(await wait_for(func():
		for w in watchers:
			if delivered_of(w)!=delivered or score_of(w)!=score+2:return false
		return true),"Delivery %d adds exactly 2 points on every client"%delivered):return false
	if delivered<3:
		if not check(await wait_for(func():return all_at(0,-1)),"Cart resets to stop 0 between crates"):return false
		if not check(phase(who)=="run","Round keeps running between crates"):return false
	return true

# ----------------------------------------------------------------- scenario --

func run() -> void:
	create_timer(110.0).timeout.connect(func():check(false,"Network suite watchdog"))
	if not check(seeded_world(),"Save a room without story flags and three islanders at the Jinguashi entrance"):return
	if not check(start_room(),"Start a dedicated WebSocket room"):return
	alpha=await connect_client("Alpha",ALPHA)
	beta=await connect_client("Beta",BETA)
	if not check(alpha!=null and beta!=null and own(alpha).is_empty() and own(beta).is_empty(),"Clients connect to the surface without receiving private gallery state"):return
	watchers=[alpha,beta]

	# Declarations.
	if not check(PC.ACTION==ACTION and PC.REGION==REGION and PC.SIGN==SIGN,"Action, region and sign are declared"):return
	if not check(host.world.player_region(ALPHA)=="jinguashi","Fixture players start in Jinguashi without a picnic"):return

	# Economy and farm baseline.
	var base_a:=economy(alpha)
	var base_b:=economy(beta)
	var base_farms:=farms()

	# Idle view and entry/exit.
	if not check(not await action(alpha,EXIT,"exit"),"Exit is refused outside the gallery"):return
	if not check(not await action(alpha,SIGN,"enter"),"Enter is refused away from the Jinguashi entrance"):return
	if not check(region_of(alpha)!=REGION,"Refused entry leaves alpha in Jinguashi"):return
	if not check(await enter_gallery(alpha) and host.world.player_region(ALPHA)==REGION,"Alpha enters the gallery from (28,25) once Bobo stage 2 is done"):return
	if not check(await enter_gallery(beta) and not host.world.state.players[BETA].has("bond_goals"),"Beta enters on the world-wide unlock without owning the goal"):return
	if not check(phase(alpha)=="idle" and own(alpha).has("joined") and own(alpha).get("joined")!=true,"Fresh room is idle and the private view carries a joined flag"):return
	if not check(not await action(alpha,ENTRY,"enter"),"Enter is refused while already inside the gallery"):return
	if not check(not await action(alpha,SIGN,"exit"),"Exit is refused away from (11,20)"):return
	if not check(await place(alpha,ALPHA,SIGN) and await place(beta,BETA,SIGN),"Both walk to the sign"):return

	# Idle refusals, then start.
	if not check(not await action(alpha,STOPS[0],"start"),"Starting away from the sign is refused"):return
	if not check(not await action(alpha,SIGN,"join:1") and not await action(alpha,SIGN,"push:1"),"Join and push while idle are refused"):return
	if not check(await action(alpha,SIGN,"start"),"Alpha starts a round at the sign"):return
	if not check(await wait_for(func():return phase(alpha)=="run" and phase(beta)=="run"),"Both clients see the running round"):return
	var rid:=round_of(beta)
	var running:=pub(beta)
	if not check(rid>=1 and own(alpha).get("joined")==true,"Round %d is open and alpha has joined"%rid):return
	if not check(stop_of(beta)==0 and to_of(beta)==-1 and delivered_of(beta)==0 and score_of(beta)==0 and int(running.get("total",-1))==3,"Fresh run: cart at stop 0, stationary, 0 of 3 delivered, score 0"):return
	if not check(float(running.get("remaining",-1))>0.0 and (branch_of(beta)=="north" or branch_of(beta)=="south"),"Time remains and a branch is selected"):return
	if not check(rocks_of(beta).has("north") and rocks_of(beta).has("south") and (rocked(beta,"north") or rocked(beta,"south")),"Rocks are declared for both tracks and at least one blocks"):return
	if not check(all_sync(),"Both clients agree on the public view"):return

	# Stale / invalid commands.
	if not check(not await action(alpha,SIGN,"start"),"Starting during a running round is refused"):return
	if not check(not await action(alpha,SIGN,"join:%d"%rid),"Joining twice is refused"):return
	if not check(not await action(beta,SIGN,"join:%d"%(rid+7)),"A stale join is refused"):return
	if not check(not await action(alpha,SIGN,"leave:%d"%(rid+7)),"A stale leave is refused"):return
	if not check(not await action(alpha,STOPS[0],"push:%d"%(rid+7)),"A stale push is refused"):return
	if not check(not await action(alpha,STOPS[0],"unload:%d"%rid),"Unloading at stop 0 is refused"):return
	if not check(not await action(alpha,STOPS[0],"switch:%d"%rid),"Switching at stop 0 is refused"):return
	await create_timer(0.3).timeout
	if not check(all_at(0,-1) and delivered_of(alpha)==0 and score_of(alpha)==0,"Refused commands change nothing"):return
	if not check(await action(beta,SIGN,"join:%d"%rid) and await wait_for(func():return own(beta).get("joined")==true),"Beta joins the round"):return
	if not check(await wait_for(func():return psize(alpha)==2 and psize(beta)==2),"Both clients list two players"):return

	# A late arrival enters the gallery and joins at the board.
	gamma=await connect_client("Gamma",GAMMA)
	if not check(gamma!=null and region_of(gamma)!=REGION,"Late joiner connects in Jinguashi"):return
	if not check(not await action(gamma,ENTRY,"join:%d"%rid) and own(gamma).is_empty(),"A surface client cannot join without entering"):return
	if not check(await enter_gallery(gamma) and await place(gamma,GAMMA,SIGN),"Gamma enters the gallery and stands at the board"):return
	if not check(not await action(gamma,SIGN,"join:%d"%(rid+7)) and own(gamma).get("joined")!=true,"Late join with a stale round is refused"):return
	if not check(await action(gamma,SIGN,"join:%d"%rid) and await wait_for(func():return own(gamma).get("joined")==true),"Gamma joins the running round"):return
	watchers=[alpha,beta,gamma]
	if not check(await wait_for(func():return psize(alpha)==3 and all_sync()),"Three players, all clients in sync"):return

	for client in watchers:
		var wire:=JSON.stringify(client.snapshot)
		if not check(client.snapshot.has(PUBLIC_KEY) and wire.count("\"%s\""%VIEW_KEY)==1,"Gallery snapshot carries one private view"):return
		for token in [ALPHA,BETA,GAMMA]:
			if not check(not wire.contains(token),"Party roster tokens stay on the server"):return

	# ---- Crate 1: simultaneous push, switch, blocked branch, clear, unload. ------
	if not check(await place(alpha,ALPHA,STOPS[0]) and await place(beta,BETA,STOPS[0]),"Alpha and beta stand at stop 0"):return
	await create_timer(0.10).timeout
	var seen_a:int=notices[alpha].size()
	var seen_b:int=notices[beta].size()
	alpha.perform(ACTION,STOPS[0],"push:%d"%rid)
	beta.perform(ACTION,STOPS[0],"push:%d"%rid)
	if not check(await wait_for(func():return notices[alpha].size()>seen_a and notices[beta].size()>seen_b),"Both simultaneous pushes are answered"):return
	var accepted:int=int(notices[alpha].back().ok)+int(notices[beta].back().ok)
	if not check(accepted==1,"Exactly one of two simultaneous pushes is accepted (%d)"%accepted):return
	if not check(await observe_roll(0,1),"The single accepted push rolls the cart to stop 1"):return
	if not check(not await action(beta,STOPS[0],"push:%d"%rid),"The cart cannot be pushed from a stop it has left"):return
	if not check(all_at(1,-1),"Cart is parked at stop 1 after the rejected push"):return
	# Make sure no second roll is hiding behind the rejected simultaneous push.
	await create_timer(SEGMENT+0.5).timeout
	if not check(all_at(1,-1),"Rejected simultaneous push never rolls a second segment"):return

	# Switch at 1 toggles, is shared, and a stale/misplaced switch is refused.
	if not check(await place(alpha,ALPHA,STOPS[1]) and await place(beta,BETA,STOPS[1]),"Both stand at stop 1"):return
	var first:=branch_of(alpha)
	if not check(not await action(alpha,STOPS[1],"switch:%d"%(rid+7)),"A stale switch is refused"):return
	if not check(not await action(alpha,SIGN,"switch:%d"%rid),"Switching away from the junction is refused"):return
	if not check(branch_of(beta)==first,"Refused switches change nothing"):return
	if not check(await action(beta,STOPS[1],"switch:%d"%rid) and await wait_for(func():return all_branch(other(first))),"Beta's switch toggles the track on every client"):return
	if not check(await action(alpha,STOPS[1],"switch:%d"%rid) and await wait_for(func():return all_branch(first)),"Alpha's switch toggles it back"):return
	var chosen:=first if rocked(alpha,first) else other(first)
	if not check(rocked(alpha,chosen),"A blocked track exists to test"):return
	if branch_of(alpha)!=chosen:
		if not check(await action(alpha,STOPS[1],"switch:%d"%rid) and await wait_for(func():return all_branch(chosen)),"Switch to the blocked %s track"%chosen):return
	if not check(await roll(alpha,ALPHA,rid),"Blocked branch refuses, gets cleared, then the cart rolls"):return
	if not check(stop_of(beta)==next_stop(1,chosen) and branch_of(beta)==chosen,"Cart took the selected %s branch"%chosen):return
	if not check(await roll(beta,BETA,rid),"Beta pushes toward stop 4"):return
	if not check(stop_of(alpha)==4,"Cart is at stop 4"):return
	if not check(await place(alpha,ALPHA,STOPS[4]) and not await action(alpha,STOPS[4],"unload:%d"%rid),"Unloading before stop 5 is refused"):return
	if not check(await roll(alpha,ALPHA,rid),"Cart rolls to stop 5"):return
	if not check(await unload(beta,BETA,rid,1),"Crate 1 is delivered for 2 points"):return
	if not check(branch_of(alpha)==chosen and all_sync(),"The selected track holds across deliveries"):return
	if not check(not await action(beta,STOPS[5],"unload:%d"%rid),"Unloading an empty cart at stop 0 is refused"):return

	# ---- Crate 2: gamma pushes and disconnects mid-roll. -------------------------
	if not check(await place(gamma,GAMMA,STOPS[0]),"Gamma stands at stop 0"):return
	if not check(await action(gamma,STOPS[0],"push:%d"%rid),"Gamma pushes crate 2"):return
	if not check(await wait_for(func():return to_of(alpha)==1),"The roll is under way"):return
	watchers=[alpha,beta]
	gamma.shutdown()
	if not check(await wait_for(func():return all_at(1,-1),8.0),"A disconnect mid-roll still lands the cart at the next stop"):return
	if not check(phase(alpha)=="run" and phase(beta)=="run" and score_of(alpha)==2 and delivered_of(alpha)==1,"Round continues, no points for the disconnect"):return
	if not check(await wait_for(func():return psize(alpha)==2 and psize(beta)==2 and all_sync()),"Players drop to two and clients stay in sync"):return
	if not check(branch_of(alpha)==chosen,"Switch held through the second crate"):return
	for step in 3:
		if not check(await roll(alpha if step%2==0 else beta,ALPHA if step%2==0 else BETA,rid),"Remaining players push step %d of crate 2"%step):return
	if not check(stop_of(alpha)==5 and await unload(alpha,ALPHA,rid,2),"Crate 2 is delivered after the disconnect"):return
	if not check(score_of(beta)==4,"Score is 4 after two crates"):return

	# ---- Crate 3: other track, finish the round. ---------------------------------
	if not check(await place(beta,BETA,STOPS[0]) and await roll(beta,BETA,rid),"Beta pushes crate 3 to stop 1"):return
	if not check(await place(beta,BETA,STOPS[1]) and await action(beta,STOPS[1],"switch:%d"%rid) and await wait_for(func():return all_branch(other(chosen))),"Beta switches to the other track"):return
	for step in 3:
		if not check(await roll(beta,BETA,rid),"Beta pushes step %d of crate 3"%step):return
	if not check(stop_of(alpha)==5 and branch_of(alpha)==other(chosen),"Crate 3 took the other branch"):return
	if not check(await unload(alpha,ALPHA,rid,3),"Crate 3 is delivered"):return
	if not check(await wait_for(func():return phase(alpha)=="results" and phase(beta)=="results" and all_sync()),"Both clients reach results"):return
	if not check(score_of(alpha)==6 and delivered_of(alpha)==3 and score_of(beta)==6,"All three crates delivered for 6 points"):return
	if not check(not await action(alpha,STOPS[0],"push:%d"%rid) and not await action(alpha,STOPS[5],"unload:%d"%rid),"Push and unload after results are rejected"):return
	if not check(not await action(beta,SIGN,"join:%d"%rid) and not await action(beta,SIGN,"leave:%d"%rid),"Stale join and leave after results are rejected"):return
	if not check(not await action(beta,STOPS[1],"switch:%d"%rid) and not await action(beta,CLEAR.north,"clear:%d:north"%rid),"Switch and clear after results are rejected"):return
	await create_timer(0.3).timeout
	if not check(score_of(alpha)==6 and phase(alpha)=="results","Results are unchanged by the rejected actions"):return

	# ---- Round 2: expiry gives no phantom score. ---------------------------------
	if not check(await place(alpha,ALPHA,SIGN) and await place(beta,BETA,SIGN),"Both walk back to the sign"):return
	if not check(await action(alpha,SIGN,"start") and await wait_for(func():return phase(alpha)=="run" and round_of(alpha)>rid and round_of(beta)==round_of(alpha)),"Alpha starts a second round"):return
	var second:=round_of(alpha)
	if not check(not await action(beta,SIGN,"join:%d"%rid),"A previous round id cannot be joined"):return
	if not check(await action(beta,SIGN,"join:%d"%second) and await wait_for(func():return own(beta).get("joined")==true),"Beta joins round two"):return
	if not check(stop_of(alpha)==0 and to_of(alpha)==-1 and delivered_of(alpha)==0 and score_of(alpha)==0 and (rocked(alpha,"north") or rocked(alpha,"south")),"Round two is fresh: cart at 0, score 0, rocks reset"):return
	for step in 4:
		if not check(await roll(alpha if step%2==0 else beta,ALPHA if step%2==0 else BETA,second),"Round two push %d"%step):return
	if not check(stop_of(alpha)==5 and score_of(alpha)==0,"Loaded cart waits at stop 5, nothing scored yet"):return
	# Exit the gallery and clear membership automatically.
	if not check(await place(beta,BETA,EXIT) and await action(beta,EXIT,"exit") and await wait_for(func():return region_of(beta)=="jinguashi"),"Beta exits the gallery at (11,20)"):return
	watchers=[alpha]
	if not check(await wait_for(func():return own(beta).is_empty() and pub(beta).is_empty() and psize(alpha)==1),"Exiting clears beta’s membership and hides the gallery snapshot"):return
	if not check(not await action(beta,ENTRY,"leave:%d"%second),"Leaving twice is refused"):return
	if not check(await place(alpha,ALPHA,STOPS[5]),"Alpha waits at the unloading stop"):return
	var left:=float(pub(alpha).get("remaining",-1))
	if not check(left>0.0,"The clock is still running (%.1f)"%left):return
	host.world.state.time=float(host.world.state.time)+left+5.0
	if not check(await wait_for(func():return phase(alpha)=="results"),"Clock jump past the deadline ends the round"):return
	if not check(score_of(alpha)==0 and delivered_of(alpha)==0,"Expiry awards no phantom score for the loaded cart"):return
	if not check(not await action(alpha,STOPS[5],"unload:%d"%second) and not await action(alpha,STOPS[0],"push:%d"%second),"Unload and push after expiry are rejected"):return
	if not check(not await action(alpha,SIGN,"leave:%d"%second) and not await action(beta,ENTRY,"join:%d"%second),"Stale join and leave after expiry are rejected"):return
	await create_timer(1.5).timeout
	if not check(score_of(alpha)==0 and delivered_of(alpha)==0 and phase(alpha)=="results","Score stays 0 after waiting more real time"):return
	if not check(await place(alpha,ALPHA,EXIT) and await action(alpha,EXIT,"exit") and await wait_for(func():return region_of(alpha)=="jinguashi" and host.world.player_region(ALPHA)=="jinguashi"),"Alpha exits the gallery at (11,20)"):return

	# ---- Ordinary economy and farms are untouched; views are private. ------------
	if not check(await wait_for(func():return economy(alpha)==base_a and economy(beta)==base_b),"Bags and coins are exactly as before the activity"):return
	if not check(farms()==base_farms,"Ordinary farm and layer state is unchanged"):return
	for client in [alpha,beta]:
		var dump:=JSON.stringify(client.snapshot)
		for id in client.snapshot.get("players",{}):
			var person=client.snapshot.players[id]
			if not check(not (person is Dictionary and (person.has(VIEW_KEY) or person.has(PUBLIC_KEY))),"Other players carry no party-cart view"):return
		if not check(dump.count("\"%s\""%VIEW_KEY)==0,"Surface snapshot has no private gallery view"):return
		for token in [ALPHA,BETA,GAMMA]:
			if not check(not dump.contains(token),"Snapshot never contains a private token"):return
	finish(0)
