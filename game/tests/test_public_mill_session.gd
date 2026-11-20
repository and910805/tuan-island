extends "res://tests/network_egg_basket.gd"
## T068 public mill (渡口舊磨坊) over real loopback WebSocket.
##
## One dedicated host Session plus two client Sessions, each on its own scene branch with its own
## MultiplayerAPI and its own profile token. Every restoration / processing / claim goes through
## Session.perform -> server RPC -> World.act. The save is an isolated user:// file deleted at the end.
##
## FIXTURE, NOT NORMAL PLAY (disclosed): the picnic, shared table and opened public kitchen are written
## into the seed (the Q05 gate is covered by test_public_kitchen_world.gd), backpacks are written directly
## and both players stand beside the bulletin board. The game clock is advanced only by an explicit
## host.world.step() call; the real-time physics drift during the test is far below the 60 s job time.

const MR:=World.MILL_RESTORATION
const PK:=World.PUBLIC_KITCHEN
const OWNER_A:="public-mill-owner-a"
const OWNER_B:="public-mill-owner-b"
const SPOT:=Vector2(40.5,30.5)
## Exact starting bags. Repair cost is plank 12, stone 12, woodwork_parts 2.
## A pays plank 8, stone 12 (3 spare), parts 1; B pays the remaining plank 4 and parts 1.
const BAG_A:={"plank":8,"stone":15,"woodwork_parts":1,"wheat":4}
const BAG_B:={"plank":6,"stone":2,"woodwork_parts":3,"sweet_corn":2,"fiber":4}
var finished:=false

func _initialize() -> void:
	create_timer(110.0,true,false,true).timeout.connect(func():
		if finished:return
		push_error("watchdog fired")
		finish(1))
	run.call_deferred()

func finish(code:int) -> void:
	if finished:return
	finished=true
	for index in range(sessions.size()-1,-1,-1):
		if not sessions[index].shutting_down:sessions[index].shutdown()
	for suffix in ["",".bak",".tmp",".bak.staged",".writer-lock"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("PUBLIC_MILL_SESSION checks=%d failures=%d"%[checks,int(code!=0)])
	quit(code)

# ----------------------------------------------------------------- views --

func me(session:Session) -> Dictionary:
	return session.snapshot.get("players",{}).get(session.own_id,{})

func bag(session:Session) -> Dictionary:
	return me(session).get("inventory",{})

func job(session:Session) -> Dictionary:
	return me(session).get(MR.JOB,{})

func progress(session:Session) -> Dictionary:
	return session.snapshot.get(MR.FIELD,{})

func busy_flag(session:Session) -> Variant:
	return session.snapshot.get(MR.BUSY)

func counts(d:Dictionary,keys:Array) -> Dictionary:
	var out:={}
	for k:String in keys:out[k]=int(d.get(k,0))
	return out

## Exact key set and whole-number values (JSON reloads turn ints into floats).
func same(d:Variant,want:Dictionary) -> bool:
	if not d is Dictionary or d.size()!=want.size():return false
	for k:String in want:
		if not d.has(k) or float(d[k])!=float(want[k]):return false
	return true

## No other player's row in this client's snapshot carries a mill job or an inventory.
func foreign_rows_private(session:Session) -> bool:
	var rows:Dictionary=session.snapshot.get("players",{})
	if rows.size()<2:return false
	for id:String in rows:
		if id==session.own_id:continue
		if rows[id].has(MR.JOB) or rows[id].has("inventory"):return false
	return true

func joined(session:Session) -> bool:
	return not session.own_id.is_empty() and not me(session).is_empty()

func saved_world() -> World:
	var w:=World.new()
	return w if w.load_world(path) else null

# --------------------------------------------------------------- fixture --

func seed_world() -> bool:
	var w:=World.new()
	w.save_path=path
	for token:String in [OWNER_A,OWNER_B]:
		w.add_player(token,"磨坊測試")
		w.state.players[token].x=SPOT.x
		w.state.players[token].y=SPOT.y
	w.state.picnic=true
	w.state.community={"table":World.COMMUNITY.choose_table(w.state)}
	var table:=World.COMMUNITY.table_cell(w.state)
	if table==World.COMMUNITY.NO_CELL:
		push_error("no community table cell")
		return false
	# A stove within 8 tiles of the table and two of the same owner's long benches within 3 of it.
	var placed:=false
	for dy in range(-4,5):
		for dx in range(-4,5):
			var stove:=table+Vector2i(dx,dy)
			var seats:Array=[stove+Vector2i(0,-1),stove+Vector2i(0,1)] if dx!=0 or absi(dy)>1 else [stove+Vector2i(-1,0),stove+Vector2i(1,0)]
			var cells:Array=[stove]+seats
			var free:=true
			for c:Vector2i in cells:
				if c==table or MR.reserved(c) or World.COMMUNITY.occupied(w.state,c):free=false
			if not free:continue
			w.state.objects[World.key(stove)]={"type":"stove","owner":OWNER_A,"items":{}}
			var keys:Array=[]
			for c:Vector2i in seats:
				w.state.objects[World.key(c)]={"type":"long_bench","owner":OWNER_A,"items":{}}
				keys.append(World.key(c))
			keys.sort()
			w.state.public_kitchen={"stove":World.key(stove),"seats":keys,"meals":PK.REQUIREMENTS.duplicate(),"opened":true}
			if validate(w.state):
				placed=true
				break
			w.state.objects.erase(World.key(stove))
			for k:String in keys:w.state.objects.erase(k)
		if placed:break
	if not placed:
		push_error("no schema-valid opened kitchen placement near table %s"%table)
		return false
	w.state.players[OWNER_A].inventory=BAG_A.duplicate()
	w.state.players[OWNER_B].inventory=BAG_B.duplicate()
	if not validate(w.state):return false
	return w.save()

func validate(state:Dictionary) -> bool:
	var parsed=JSON.parse_string(JSON.stringify(state))
	return parsed is Dictionary and bool(World.SAVE_SCHEMA.validate(parsed,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME))

func free_port() -> int:
	var listener:=TCPServer.new()
	if listener.listen(0,"127.0.0.1")!=OK:return 0
	var port:=listener.get_local_port()
	listener.stop()
	return port

func start_host(label:String,port:int) -> Session:
	var host:=make_session(label,"public-mill-host")
	if host.host(port,"渡口",path,ROOM,"127.0.0.1",true,"websocket")!=OK:return null
	return host

# ------------------------------------------------------------------ run --

func run() -> void:
	path="user://public-mill-network-%d.json"%OS.get_process_id()
	if not check(seed_world(),"Seed an isolated schema-valid save with an opened kitchen and two bags"):return
	if not check(not MR.repaired(saved_world().state) and not saved_world().state.has(MR.FIELD),"Seed starts with the mill unrepaired"):return
	var port:=free_port()
	if not check(port>0,"Reserve a loopback port"):return
	var host:=start_host("MillHost",port)
	if not check(host!=null,"Start the dedicated WebSocket host"):return
	var address:="ws://127.0.0.1:%d"%port
	var a:=make_session("MillA",OWNER_A)
	var b:=make_session("MillB",OWNER_B)
	if not check(a.multiplayer!=b.multiplayer and a.multiplayer!=host.multiplayer and b.multiplayer!=host.multiplayer,"Three distinct MultiplayerAPI branches"):return
	if not check(a.join(address,port,"甲",ROOM)==OK and b.join(address,port,"乙",ROOM)==OK,"Connect both WebSocket clients"):return
	if not check(await wait_for(func():return joined(a) and joined(b) and host.peers.size()==2),"Both clients enter the room"):return
	if not check(a.own_id!=b.own_id and not JSON.stringify(a.snapshot).contains(OWNER_B) and not JSON.stringify(b.snapshot).contains(OWNER_A),"Distinct identities and no raw profile token leaks"):return
	if not check(await wait_for(func():return a.snapshot.get(MR.SITE_VISIBLE)==true and b.snapshot.get(MR.SITE_VISIBLE)==true),"Both clients see the empty mill site"):return
	if not check(not a.snapshot.has(MR.BUSY) and progress(a).is_empty(),"No busy flag or progress before restoration"):return

	# ---- restoration: both contribute, exact balances ----
	if not check(not await action(a,MR.SERVICE,MR.BOARD,"flour"),"Mill service refused before restoration"):return
	if not check(not await action(a,MR.ACTION,MR.BOARD,"extra"),"Contribution with an extra argument is refused"):return
	if not check(await action(a,MR.ACTION,MR.BOARD),"A contributes materials"):return
	var after_a:={"plank":8,"stone":12,"woodwork_parts":1}
	if not check(await wait_for(func():return same(progress(a),after_a) and same(progress(b),after_a)),"Both clients see A's exact partial progress"):return
	if not check(await wait_for(func():return counts(bag(a),["plank","stone","woodwork_parts","wheat"])=={"plank":0,"stone":3,"woodwork_parts":0,"wheat":4}),"A keeps exactly the 3 spare stone and the wheat"):return
	if not check(not MR.repaired(host.world.state),"Host: still unrepaired after A"):return
	if not check(await action(b,MR.ACTION,MR.BOARD),"B contributes the remainder"):return
	if not check(await wait_for(func():return same(progress(a),MR.COST) and same(progress(b),MR.COST)),"Both clients see the exact full cost collected"):return
	if not check(await wait_for(func():return counts(bag(b),["plank","stone","woodwork_parts","sweet_corn","fiber"])=={"plank":2,"stone":2,"woodwork_parts":2,"sweet_corn":2,"fiber":4}),"B keeps exactly the unneeded materials"):return
	if not check(not await action(a,MR.ACTION,MR.BOARD) and not await action(b,MR.ACTION,MR.BOARD),"Further contributions refused once repaired"):return
	if not check(same(host.world.state[MR.FIELD],MR.COST) and int(host.world.state.players[OWNER_A].inventory.get("stone",0))==3 and int(host.world.state.players[OWNER_B].inventory.get("plank",0))==2,"Host state holds exactly the cost; refused retries charged nothing"):return
	if not check(await wait_for(func():return busy_flag(a)==false and busy_flag(b)==false),"Both clients see the repaired mill idle"):return

	# ---- shared busy state, private jobs ----
	if not check(not await action(a,MR.SERVICE,MR.BOARD,"plank"),"Unknown recipe refused"):return
	if not check(not await action(a,MR.SERVICE,MR.BOARD,"claim"),"Claim with no job refused"):return
	if not check(await action(a,MR.SERVICE,MR.BOARD,"flour"),"A queues flour"):return
	if not check(await wait_for(func():return busy_flag(a)==true and busy_flag(b)==true),"Both clients see the shared busy mill"):return
	if not check(await wait_for(func():return job(a).get("kind")=="flour" and int(bag(a).get("wheat",0))==2),"A sees own flour job and 2 wheat charged"):return
	if not check(job(b).is_empty() and foreign_rows_private(a) and foreign_rows_private(b),"A's job is absent from B's view and every foreign row"):return
	if not check(not await action(a,MR.SERVICE,MR.BOARD,"flour") and int(bag(a).get("wheat",0))==2,"A cannot queue a second job; nothing charged"):return
	if not check(not await action(b,MR.SERVICE,MR.BOARD,"flour") and job(b).is_empty(),"B cannot mill flour without wheat"):return
	if not check(await action(b,MR.SERVICE,MR.BOARD,"feed"),"B queues feed while the mill is busy for A"):return
	if not check(await wait_for(func():return job(b).get("kind")=="feed" and int(bag(b).get("sweet_corn",0))==1 and int(bag(b).get("fiber",0))==2),"B sees own feed job and exact corn/fiber charge"):return
	if not check(job(a).get("kind")=="flour" and foreign_rows_private(a) and foreign_rows_private(b),"Each client still sees only its own job"):return
	if not check(not await action(a,MR.SERVICE,MR.BOARD,"claim") and int(bag(a).get("flour",0))==0,"Early claim refused"):return

	# ---- disconnect and host restart ----
	b.shutdown()
	if not check(await wait_for(func():return host.peers.size()==1),"Host saw B disconnect"):return
	if not check(await wait_for(func():return busy_flag(a)==true),"Remaining client still sees the busy mill"):return
	var clock_before:=float(host.world.state.time)
	var ready_a:=float(host.world.state.players[OWNER_A][MR.JOB].ready)
	var ready_b:=float(host.world.state.players[OWNER_B][MR.JOB].ready)
	if not check(ready_a>clock_before and ready_b>clock_before,"Both jobs are still pending on the host clock"):return
	if not check(host.shutdown(),"Shut down and save the host"):return
	a.shutdown()
	var saved:=saved_world()
	if not check(saved!=null,"Reload the isolated save after shutdown"):return
	if not check(same(saved.state[MR.FIELD],MR.COST) and saved.state.players[OWNER_A][MR.JOB].kind=="flour" and saved.state.players[OWNER_B][MR.JOB].kind=="feed","Save holds the full restoration and both private jobs"):return
	if not check(MR.busy(saved.state) and validate(saved.state),"Saved world is busy and schema-valid"):return
	var port2:=free_port()
	if not check(port2>0,"Reserve a loopback port for the restarted host"):return
	var host2:=start_host("MillHost2",port2)
	if not check(host2!=null,"Restart the dedicated host on the same save"):return
	var address2:="ws://127.0.0.1:%d"%port2

	# ---- rejoin, explicit clock advance, claim once ----
	var a2:=make_session("MillA2",OWNER_A)
	var b2:=make_session("MillB2",OWNER_B)
	if not check(a2.join(address2,port2,"甲",ROOM)==OK and b2.join(address2,port2,"乙",ROOM)==OK,"Both profiles rejoin"):return
	if not check(await wait_for(func():return joined(a2) and joined(b2) and host2.peers.size()==2),"Both rejoined clients enter"):return
	if not check(await wait_for(func():return busy_flag(a2)==true and busy_flag(b2)==true),"Busy state survives the restart for both"):return
	if not check(await wait_for(func():return job(a2).get("kind")=="flour" and job(b2).get("kind")=="feed" and foreign_rows_private(a2) and foreign_rows_private(b2)),"Private jobs survive the restart, still private"):return
	if not check(same(progress(a2),MR.COST) and same(progress(b2),MR.COST),"Restoration progress survives the restart"):return
	if not check(not await action(b2,MR.SERVICE,MR.BOARD,"claim"),"Claim before the clock advance is refused"):return
	var latest:=maxf(float(host2.world.state.players[OWNER_A][MR.JOB].ready),float(host2.world.state.players[OWNER_B][MR.JOB].ready))
	var advance:=latest-float(host2.world.state.time)+1.0
	if not check(advance>0.0 and advance<=61.0,"Pending time is within one job length"):return
	if not check(host2.world.step(advance,true),"Explicitly advance the host game clock"):return
	if not check(not MR.busy(host2.world.state),"Host clock now past both jobs"):return
	if not check(await wait_for(func():return busy_flag(a2)==false and busy_flag(b2)==false),"Both clients see the mill idle again"):return
	# A double-sends a claim; exactly one may succeed.
	var seen_a:int=notices[a2].size()
	a2.perform(MR.SERVICE,MR.BOARD,"claim")
	a2.perform(MR.SERVICE,MR.BOARD,"claim")
	if not check(await wait_for(func():return notices[a2].size()>=seen_a+2),"Both of A's claims are answered"):return
	var oks:=0
	for n:Dictionary in notices[a2].slice(seen_a,seen_a+2):oks+=int(n.ok)
	if not check(oks==1,"Exactly one of A's two claims succeeds"):return
	if not check(await wait_for(func():return int(bag(a2).get("flour",0))==1 and job(a2).is_empty()),"A receives exactly 1 flour and the job clears"):return
	if not check(int(bag(b2).get("flour",0))==0 and job(b2).get("kind")=="feed","A's claim does not touch B"):return
	if not check(await action(b2,MR.SERVICE,MR.BOARD,"claim"),"B claims feed"):return
	if not check(await wait_for(func():return int(bag(b2).get("feed",0))==4 and job(b2).is_empty()),"B receives exactly 4 feed"):return
	if not check(not await action(b2,MR.SERVICE,MR.BOARD,"claim") and int(bag(b2).get("feed",0))==4,"B's second claim is refused"):return
	if not check(not await action(a2,MR.SERVICE,MR.BOARD,"claim") and int(bag(a2).get("flour",0))==1,"A's later claim is refused"):return
	if not check(int(bag(a2).get("feed",0))==0,"A never receives B's feed"):return

	# ---- final persisted balances ----
	if not check(host2.shutdown(),"Shut down and save the restarted host"):return
	a2.shutdown()
	b2.shutdown()
	var final:=saved_world()
	if not check(final!=null and validate(final.state),"Final save reloads and is schema-valid"):return
	var fa:Dictionary=final.state.players[OWNER_A]
	var fb:Dictionary=final.state.players[OWNER_B]
	if not check(same(final.state[MR.FIELD],MR.COST) and not fa.has(MR.JOB) and not fb.has(MR.JOB),"Final save: full restoration, no outstanding jobs"):return
	if not check(counts(fa.inventory,["plank","stone","woodwork_parts","wheat","flour","feed"])=={"plank":0,"stone":3,"woodwork_parts":0,"wheat":2,"flour":1,"feed":0},"Final save: A's exact balances"):return
	if not check(counts(fb.inventory,["plank","stone","woodwork_parts","sweet_corn","fiber","feed","flour"])=={"plank":2,"stone":2,"woodwork_parts":2,"sweet_corn":1,"fiber":2,"feed":4,"flour":0},"Final save: B's exact balances"):return
	finish(0)
