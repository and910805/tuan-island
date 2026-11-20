extends SceneTree
## R24 packaged Linux server acceptance: real WebSocket clients (this development Godot's own
## Session, one isolated MultiplayerAPI per client) against an ALREADY RUNNING packaged r24 server.
## This script starts no server, edits no save and never calls into the remote World; every step is
## a normal Session call (perform / input_direction). Players move only by input_direction at the
## server's own walking pace (3.6 cells/s), so no teleport, clock jump or state edit is used.
##
## Environment (read once):
##   R24_PORT  (required) TCP port of the packaged server's WebSocket listener.
##   R24_PASS  (required) room password / key passed to Session.join as key_value.
##   R24_HOST  (optional) "127.0.0.1" (default), "localhost" or "::1". Anything else is refused:
##             this test never talks to a non-loopback host.
##   R24_VERIFY_RESTART=1 (or the user arg --verify-restart) runs ONLY the post-restart read-back.
##
## Run (development Godot, project in game/):
##   godot --headless --path game --script res://tests/test_r24_party_remote.gd
##   ... restart the packaged server on the same world save (graceful stop so it saves) ...
##   R24_VERIFY_RESTART=1 godot --headless --path game --script res://tests/test_r24_party_remote.gd
##
## FIXTURE REQUIREMENTS (seeded in the world save the packaged server loads, FRESH: no lantern_stroll
## round, no party_cart record, so the first "start" of each is round 1):
##   * state.picnic=true (Lantern Stroll gate).
##   * Players "r24-party-owner" and "r24-party-friend": region "home", standing on a free cell at
##     World.LANTERN_STROLL.SIGN (center x+0.5,y+0.5), empty lantern_stroll purse, empty bag.
##   * Player "r24-party-carter": region "jinguashi", standing within 3.2 cells of
##     World.PARTY_CART.SURFACE_PORTAL (28,25). No picnic or story flag is needed for the cart.
##   * T066 N03-2 host external fixture: the cart portal opens world-wide once ANY saved player has
##     Bobo stage 2. Seed "r24-party-owner" (NOT the carter, to prove the world-wide unlock) with
##     bonds.bobo={"points":6,"talk_day":-1,"gift_day":-1} and bond_goals={"bobo":{"2":"siding"}}
##     in the world save the packaged server loads (alternatively a legacy cart round already exists).
##     The Jinguashi snapshot must then publish party_cart_unlocked=true.
##   * The server accepts the three tokens as returning players (no admission gate for them).
## NOT covered: exact notice wording, the 8/4 player caps, crash (non graceful) durability.

const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const Stroll=World.LANTERN_STROLL
const PC=World.PARTY_CART
const OWNER_TOKEN:="r24-party-owner"
const FRIEND_TOKEN:="r24-party-friend"
const CARTER_TOKEN:="r24-party-carter"
const WISHES:={"grove":"safe","meadow":"friends","river":"growth"}
const FRIEND_WISH:="growth"
const SPEED:=3.6

var sessions:Array[Session]=[]
var notices:Dictionary={}
var checks:=0
var host_name:="127.0.0.1"
var port:=0
var room_pass:=""
var walked_cells:=0.0
var walked_ms:=0

func _initialize() -> void:
	create_timer(240.0,true,false,true).timeout.connect(func():
		push_error("R24 watchdog fired before the scenario completed")
		finish(1))
	run.call_deferred()

# ---------------------------------------------------------------- plumbing --

func check(condition:bool,message:String) -> bool:
	checks+=1
	if condition:return true
	push_error("R24_PARTY_REMOTE check %d failed: %s"%[checks,message])
	finish(1)
	return false

func finish(code:int) -> void:
	for i in range(sessions.size()-1,-1,-1):
		if not sessions[i].shutting_down:sessions[i].shutdown()
	if code==0:print("R24_PARTY_REMOTE ok checks=%d"%checks)
	else:print("R24_PARTY_REMOTE FAIL checks=%d"%checks)
	quit(code)

func wait_for(predicate:Callable,seconds:float=10.0) -> bool:
	var deadline:=Time.get_ticks_msec()+int(seconds*1000)
	while not predicate.call() and Time.get_ticks_msec()<deadline:
		await process_frame
	return predicate.call()

func make_session(branch_name:String,token:String) -> Session:
	var branch:=Node.new()
	branch.name=branch_name
	root.add_child(branch)
	set_multiplayer(MultiplayerAPI.create_default_interface(),branch.get_path())
	var island:=Node2D.new()
	island.name="Island"
	branch.add_child(island)
	var session:=Session.new()
	island.add_child(session)
	session.profile={"token":token}
	sessions.append(session)
	notices[session]=[]
	session.notice.connect(func(message:String,ok:bool):notices[session].append({"message":message,"ok":ok}))
	return session

func connect_client(branch_name:String,token:String) -> Session:
	var session:=make_session("%s%d"%[branch_name,sessions.size()],token)
	var address:="ws://%s:%d"%["[::1]" if host_name=="::1" else host_name,port]
	if session.join(address,port,branch_name,room_pass)!=OK:return null
	if not await wait_for(func():return not session.own_id.is_empty() and session.snapshot.get("players",{}).has(session.own_id),15.0):return null
	return session

func release(session:Session) -> void:
	session.shutdown()
	sessions.erase(session)

# ----------------------------------------------------------------- helpers --

func me(s:Session) -> Dictionary:
	return s.snapshot.get("players",{}).get(s.own_id,{})

func pos_of(s:Session) -> Vector2:
	var p:Dictionary=me(s)
	return Vector2(float(p.get("x",-99.0)),float(p.get("y",-99.0)))

func region_of(s:Session) -> String:
	return str(s.snapshot.get("region_id",""))

func bag(s:Session) -> Dictionary:
	var inventory:Variant=me(s).get("inventory",{})
	return inventory if inventory is Dictionary else {}

func shared(s:Session) -> Dictionary:
	var value:Variant=s.snapshot.get(Stroll.KEY,{})
	return value if value is Dictionary else {}

func mine(s:Session) -> Dictionary:
	var value:Variant=s.snapshot.get(Stroll.VIEW_KEY,{})
	return value if value is Dictionary else {}

func cart(s:Session) -> Dictionary:
	var value:Variant=s.snapshot.get(PC.KEY,{})
	return value if value is Dictionary else {}

func cart_mine(s:Session) -> Dictionary:
	var value:Variant=s.snapshot.get(PC.VIEW_KEY,{})
	return value if value is Dictionary else {}

func center(cell:Vector2i) -> Vector2:
	return Vector2(cell)+Vector2(0.5,0.5)

## One normal action; true only when the server answered with ok=true.
func act(s:Session,action:String,cell:Vector2i,extra:String) -> bool:
	await create_timer(0.12).timeout # stays under the session rate limit
	var seen:int=notices[s].size()
	s.perform(action,cell,extra)
	if not await wait_for(func():return notices[s].size()>seen):return false
	return notices[s].back().ok

func stroll(s:Session,cell:Vector2i,extra:String) -> bool:
	return await act(s,Stroll.ACTION,cell,extra)

func route_cells(route:Array) -> Array[Vector2i]:
	var out:Array[Vector2i]=[]
	for raw in route:
		var parts:PackedStringArray=str(raw).split(",")
		out.append(Vector2i(int(parts[0]),int(parts[1])))
	return out

## Walk with input_direction only (axis-aligned steps toward a cell center). Pace is measured from
## the server snapshot positions while the input is held.
func walk_to(s:Session,target:Vector2,tolerance:float=0.3,limit:float=10.0) -> bool:
	var start:=Time.get_ticks_msec()
	var last_pos:=pos_of(s)
	var last_progress:=start
	while Time.get_ticks_msec()-start<int(limit*1000):
		var pos:=pos_of(s)
		var d:=target-pos
		if d.length()<=tolerance:
			s.input_direction(Vector2.ZERO)
			return true
		var moved:=pos.distance_to(last_pos)
		if moved>0.02:
			last_progress=Time.get_ticks_msec()
			if moved<2.0:walked_cells+=moved
		elif Time.get_ticks_msec()-last_progress>2500:
			break
		last_pos=pos
		var dir:=Vector2.ZERO
		if absf(d.x)>=absf(d.y):dir.x=signf(d.x)
		else:dir.y=signf(d.y)
		s.input_direction(dir)
		await process_frame
	s.input_direction(Vector2.ZERO)
	return false

func walk_path(s:Session,cells:Array[Vector2i],from:int,to:int) -> bool:
	var step:=1 if to>=from else -1
	var i:=from+step
	while from!=to and (i-to)*step<=0:
		var final:=i==to
		var t0:=Time.get_ticks_msec()
		var ok:bool=await walk_to(s,center(cells[i]),0.3 if final else 0.5)
		walked_ms+=Time.get_ticks_msec()-t0
		if not ok:return false
		i+=step
	await create_timer(0.3).timeout # let the stop reach the server before acting
	return true

func pace() -> float:
	return walked_cells/maxf(0.001,walked_ms/1000.0)

# ----------------------------------------------------------------- scenario --

func read_env() -> bool:
	host_name=OS.get_environment("R24_HOST") if not OS.get_environment("R24_HOST").is_empty() else "127.0.0.1"
	if host_name not in ["127.0.0.1","localhost","::1"]:
		push_error("R24_HOST must be loopback (127.0.0.1, localhost or ::1)")
		return false
	var raw:=OS.get_environment("R24_PORT")
	if not raw.is_valid_int() or int(raw)<1 or int(raw)>65535:
		push_error("R24_PORT must be a TCP port")
		return false
	port=int(raw)
	room_pass=OS.get_environment("R24_PASS")
	if room_pass.is_empty():
		push_error("R24_PASS (room password) is required")
		return false
	return true

func run() -> void:
	if not read_env():
		finish(2)
		return
	var restart:=OS.get_environment("R24_VERIFY_RESTART")=="1" or "--verify-restart" in OS.get_cmdline_user_args()
	if restart:await verify_restart()
	else:await party()

## Second invocation: persisted data only, no new actions.
func verify_restart() -> void:
	var owner:=await connect_client("R24Owner",OWNER_TOKEN)
	var friend:=await connect_client("R24Friend",FRIEND_TOKEN)
	if not check(owner!=null and friend!=null,"Reconnect owner and friend to the restarted server"):return
	if not check(await wait_for(func():return not mine(owner).is_empty() and not mine(friend).is_empty()),"Private walk views arrive"):return
	var view:Dictionary=mine(owner)
	if not check(view.stamps.size()==Stroll.ORDER.size() and int(view.earned)==1 and int(view.tickets)==0,"Owner keeps 3 stamps, 1 earned credit, 0 tickets after restart"):return
	if not check(int(bag(owner).get(Stroll.PRIZE,0))==1,"Owner's redeemed %s survived the restart"%Stroll.PRIZE):return
	if not check(mine(friend).stamps.size()==1 and mine(friend).stamps.get("grove")==FRIEND_WISH and int(mine(friend).tickets)==0,"Friend keeps exactly its own one stamp"):return
	if not check(int(bag(friend).get(Stroll.PRIZE,0))==0,"Friend never received a lantern kit"):return
	var carter:=await connect_client("R24Carter",CARTER_TOKEN)
	if not check(carter!=null and region_of(carter)==PC.SURFACE,"Carter returns on the Jinguashi surface after restart"):return
	for client:Session in [owner,friend,carter]:
		var dump:=JSON.stringify(client.snapshot)
		for token:String in [OWNER_TOKEN,FRIEND_TOKEN,CARTER_TOKEN]:
			if not check(not dump.contains(token),"Snapshot hides raw token"):return
	finish(0)

func party() -> void:
	var owner:=await connect_client("R24Owner",OWNER_TOKEN)
	var friend:=await connect_client("R24Friend",FRIEND_TOKEN)
	if not check(owner!=null and friend!=null,"Owner and friend connect to the packaged server over loopback WebSocket"):return
	if not check(await wait_for(func():return not mine(owner).is_empty() and not mine(friend).is_empty()),"Both receive a private walk summary in home"):return
	if not check(region_of(owner)=="home" and region_of(friend)=="home","Both start in home"):return
	if not check(shared(owner).get("phase")!="run" and not mine(owner).joined and mine(owner).stamps.is_empty() and mine(friend).stamps.is_empty(),"Fresh fixture: no round running, no stamps"):return
	if not check(pos_of(owner).distance_to(center(Stroll.SIGN))<=1.0 and pos_of(friend).distance_to(center(Stroll.SIGN))<=1.0,"Fixture players stand at the walk sign"):return
	var prior_bag:=JSON.stringify(bag(owner),"",true)

	# Real party: owner starts, friend joins.
	if not check(await stroll(owner,Stroll.SIGN,"start"),"Owner starts the stroll at the sign"):return
	if not check(await wait_for(func():return shared(friend).get("phase")=="run" and mine(owner).joined),"Round runs and is visible to the friend"):return
	var rid:int=int(shared(friend).round)
	var route:Array=shared(friend).route
	if not check(Stroll._valid_route(route) and JSON.stringify(route)==JSON.stringify(shared(owner).route),"Both clients see the same server-validated connected route"):return
	if not check(await stroll(friend,Stroll.SIGN,"join:%d"%rid) and await wait_for(func():return mine(friend).joined and int(shared(owner).count)==2),"Friend joins the party (2 lanterns)"):return
	var cells:=route_cells(route)

	# Owner walks the route and stamps every site; the friend waits at the sign.
	print("R24 Connected two clients; walking the signed route")
	var stops:Dictionary={}
	var at:=0
	for site:String in Stroll.ORDER:
		var found:=cells.find(Stroll.SITES[site].cell,at)
		if not check(found>=at,"Route contains %s after the previous stop"%site):return
		if not check(await walk_path(owner,cells,at,found),"Owner walks to %s with input_direction"%site):return
		at=found
		stops[site]=found
		if not check(await stroll(owner,Stroll.SITES[site].cell,"stamp:%d:%s:%s"%[rid,site,WISHES[site]]),"Owner stamps %s"%site):return
		if not check(await wait_for(func():return mine(owner).stamps.get(site)==WISHES[site]),"Owner's own view shows the %s stamp"%site):return
		if site==Stroll.ORDER[0]:
			if not check(await wait_for(func():return shared(friend).get("blessings",{}).get(site)==WISHES[site]),"Friend sees the shared blessing"):return
			if not check(mine(friend).stamps.is_empty() and int(mine(friend).tickets)==0,"Friend gets no stamp for the owner's visit"):return
	var rate:=pace()
	if not check(rate>=1.0 and rate<=SPEED+0.6,"Observed walking pace %.2f cells/s is a genuine walk (max %.1f)"%[rate,SPEED]):return
	if not check(mine(owner).stamps.size()==3 and int(mine(owner).tickets)==1 and int(mine(owner).earned)==1,"Three stamps earn exactly one private ticket"):return
	if not check(mine(friend).stamps.is_empty() and int(mine(friend).tickets)==0,"Friend still has no stamps and no ticket"):return

	# Friend stamps the first stop personally, with a different wish.
	var first:String=Stroll.ORDER[0]
	if not check(await walk_path(friend,cells,0,stops[first]),"Friend walks to %s"%first):return
	if not check(await stroll(friend,Stroll.SITES[first].cell,"stamp:%d:%s:%s"%[rid,first,FRIEND_WISH]) and await wait_for(func():return mine(friend).stamps.get(first)==FRIEND_WISH),"Friend stamps %s personally"%first):return
	if not check(mine(owner).stamps.get(first)==WISHES[first] and mine(friend).stamps.size()==1 and int(mine(friend).tickets)==0,"Personal stamps stay isolated per player"):return
	if not check(not await stroll(friend,Stroll.SITES[first].cell,"stamp:%d:%s:%s"%[rid,first,"safe"]),"A player cannot stamp the same stop twice"):return

	# Owner walks back and redeems the ticket.
	if not check(await walk_path(owner,cells,at,0),"Owner walks back to the sign"):return
	if not check(await stroll(owner,Stroll.SIGN,"redeem"),"Owner redeems the ticket at the sign"):return
	if not check(await wait_for(func():return int(bag(owner).get(Stroll.PRIZE,0))==1 and int(mine(owner).tickets)==0),"Redemption grants exactly one %s"%Stroll.PRIZE):return
	if not check(not await stroll(owner,Stroll.SIGN,"redeem") and int(bag(owner).get(Stroll.PRIZE,0))==1,"Replayed redemption is refused"):return
	if not check(prior_bag!=JSON.stringify(bag(owner),"",true),"Bag changed only by the redemption"):return
	if not check(int(bag(friend).get(Stroll.PRIZE,0))==0,"Friend's bag has no kit"):return

	# Disconnect and reconnect: personal progress persists, the lantern was returned.
	release(owner)
	if not check(await wait_for(func():return int(shared(friend).get("count",9))==1),"Disconnect returns the owner's lantern"):return
	var again:=await connect_client("R24Owner",OWNER_TOKEN)
	if not check(again!=null and await wait_for(func():return not mine(again).is_empty()),"Owner reconnects"):return
	if not check(mine(again).stamps.size()==3 and int(mine(again).earned)==1 and int(mine(again).tickets)==0 and not mine(again).joined,"Reconnected owner keeps 3 stamps and the spent ticket, lantern returned"):return
	if not check(int(bag(again).get(Stroll.PRIZE,0))==1,"Reconnected owner still holds the kit"):return
	if not check(await stroll(again,Stroll.SIGN,"join:%d"%rid) and await wait_for(func():return mine(again).joined and mine(again).stamps.size()==3),"Explicit rejoin restores the lantern, stamps intact"):return
	for client:Session in [again,friend]:
		var dump:=JSON.stringify(client.snapshot)
		for token:String in [OWNER_TOKEN,FRIEND_TOKEN,CARTER_TOKEN]:
			if not check(not dump.contains(token),"Snapshot hides raw tokens"):return
		for visible:Dictionary in client.snapshot.players.values():
			if not check(not visible.has(Stroll.KEY) and not visible.has(Stroll.VIEW_KEY),"No player record exposes walk credits"):return

	# Third player: Jinguashi portal -> cart gallery, early cart play on the same server.
	var carter:=await connect_client("R24Carter",CARTER_TOKEN)
	if not check(carter!=null and region_of(carter)==PC.SURFACE,"Carter connects in Jinguashi"):return
	if not check(cart_mine(carter).is_empty() and mine(carter).is_empty(),"No walk or cart private view on the surface"):return
	if not check(await wait_for(func():return carter.snapshot.get("party_cart_unlocked",false)==true),"Seeded host fixture: Jinguashi snapshot publishes party_cart_unlocked=true (Bobo stage 2 seeded on the owner, not the carter)"):return
	if not check(not me(carter).has("bond_goals"),"Carter holds no Bobo goal of their own"):return
	if not check(await act(carter,PC.ACTION,PC.SURFACE_PORTAL,"enter") and await wait_for(func():return region_of(carter)==PC.REGION),"Carter enters the cart gallery at (28,25)"):return
	if not check(await wait_for(func():return carter.snapshot.has(PC.KEY) and cart_mine(carter).has("joined")),"Gallery views arrive"):return
	if not check(await walk_to(carter,center(PC.SIGN),0.4),"Carter walks to the cart sign"):return
	if not check(await act(carter,PC.ACTION,PC.SIGN,"start") and await wait_for(func():return cart(carter).get("phase")=="run" and cart_mine(carter).joined),"Carter starts a cart round"):return
	var cart_round:int=int(cart(carter).round)
	if not check(int(cart(carter).stop)==0 and int(cart(carter).to)==-1 and int(cart(carter).delivered)==0,"Cart waits at its start"):return
	if not check(await walk_to(carter,center(PC.STOPS[0]),0.4),"Carter walks to the cart"):return
	print("R24 Entered the mine gallery; testing rail travel")
	var pushed:=Time.get_ticks_msec()
	if not check(await act(carter,PC.ACTION,PC.STOPS[0],"push:%d"%cart_round),"Carter pushes the cart"):return
	if not check(await wait_for(func():return int(cart(carter).to)==1 or int(cart(carter).stop)==1),"Cart leaves the start"):return
	if not check(await wait_for(func():return int(cart(carter).stop)==1 and int(cart(carter).to)==-1,8.0),"Cart lands at the junction"):return
	if not check(Time.get_ticks_msec()-pushed>=900,"Cart travel used genuine server time"):return
	if not check(await act(carter,PC.ACTION,PC.SIGN,"leave:%d"%cart_round) and await wait_for(func():return not cart_mine(carter).joined),"Carter leaves the round"):return
	if not check(await walk_to(carter,center(PC.EXIT),0.4),"Carter walks to the exit"):return
	if not check(await act(carter,PC.ACTION,PC.EXIT,"exit") and await wait_for(func():return region_of(carter)==PC.SURFACE),"Carter exits back to Jinguashi"):return
	if not check(await wait_for(func():return mine(again).stamps.size()==3 and mine(friend).stamps.size()==1),"Walk progress is unaffected by cart play"):return
	finish(0)
