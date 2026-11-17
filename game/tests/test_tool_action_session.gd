extends SceneTree
## T017 hand-tool action feedback over a REAL local WebSocket connection.
##
## LEVEL: one machine, ONE Godot process. A dedicated server Session listens on a
## free 127.0.0.1 port with the WebSocket transport; three client Sessions join
## over loopback, each in its own branch with its own SceneMultiplayer, so
## requests, notices and snapshots travel through the real RPC + WebSocket path.
## alpha and beta stand on the home island; gamma stands on the jinguashi surface.
## Each client feeds its received snapshots to its own ToolActionFeedback (the
## observer WorldView uses) to count which animations would start.
##
## SEEDED FIXTURE (written to a fresh TEMP folder, SaveSchema-validated):
## picnic=true and mine_depths as in test_mine_deep_session so the surface is a
## valid location; alpha/beta at home near spawn, gamma on the jinguashi surface.
## Checks: confirmed actions reach the actor and the same-region peer exactly
## once; rejected actions animate nowhere; the other region receives nothing;
## events carry only public fields; a reconnecting client and a client whose
## peer left do not replay; protocol unchanged.
const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const Schema=preload("res://scripts/save_schema.gd")
const Feedback=preload("res://scripts/tool_action_feedback.gd")
const Regions=preload("res://scripts/regions.gd")
const KEY:="tool-action-session"
const ALPHA:="tool-session-alpha-token"
const BETA:="tool-session-beta-token"
const GAMMA:="tool-session-gamma-token"
const SURFACE:="jinguashi"
const SURFACE_ARRIVAL:=Vector2(27.5,19.5)
const PLOT:=Vector2i(38,34)
const EVENT_KEYS:=["actor","n","tool","x","y"]

class Client:
	var label:=""
	var token:=""
	var branch:Node
	var session
	var notices:Array=[]
	var changes:=0
	var feedback:=Feedback.new()
	var previous:Dictionary={}
	## n -> number of animations this client started for that event.
	var started:Dictionary={}
	## every event (by n) this client ever received in a snapshot
	var received:Dictionary={}
	var first_events:Array=[]
	var payload_keys_ok:=true
	var leaked:Array=[]
	var secrets:Array=[]
	func on_notice(message:String,success:bool)->void:
		notices.append([message,success])
	func on_changed(data:Dictionary,id:String)->void:
		changes+=1
		var payload=data.get("tool_actions",{})
		var events:Array=payload.get("events",[]) if payload is Dictionary else []
		if changes==1:first_events=events.map(func(e):return int(e.n))
		var text:=JSON.stringify(payload)
		for secret in secrets:
			if text.contains(secret) and not leaked.has(secret):leaked.append(secret)
		for e in events:
			var keys:Array=e.keys()
			keys.sort()
			if keys!=EVENT_KEYS:payload_keys_ok=false
			received[int(e.n)]=e
		var now:=Time.get_ticks_msec()/1000.0
		var fresh:Array=feedback.observe(previous,data,id,now)
		for actor in fresh:
			var record:Dictionary=feedback.active(actor,now)
			started[int(record.n)]=int(started.get(int(record.n),0))+1
		previous=data
	func me()->Dictionary:
		var people=session.snapshot.get("players",{})
		if not people is Dictionary or session.own_id.is_empty():return {}
		return people.get(session.own_id,{})
	func region()->String:
		return str(session.snapshot.get("region_id",""))

var checks:=0
var failures:=0
var serial:=0
var folder:=""
var save_path:=""
var server
var server_branch:Node
var finished:=false
var frozen_ms:=-1
var clients:Array=[]

func expect(ok:bool,label:String)->void:
	checks+=1
	if not ok:
		failures+=1
		push_error("FAIL "+label)

func _initialize()->void:
	create_timer(90.0).timeout.connect(_watchdog)
	run.call_deferred()

func _watchdog()->void:
	if finished:return
	finished=true
	print("TOOL_ACTION_SESSION watchdog fired before completion")
	print("TOOL_ACTION_SESSION_TESTS checks=%d failures=%d"%[checks,failures+1])
	quit(1)

func run()->void:
	var completed:=await scenario()
	expect(completed,"scenario ran to completion without an aborted wait")
	await teardown()
	if failures==0 and completed:expect(remove_folder(),"temp fixture folder removed")
	else:print("TOOL_ACTION_SESSION kept temp folder for inspection: %s"%folder)
	if finished:return
	finished=true
	print("TOOL_ACTION_SESSION_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 or checks==0 else 0)

# ---------------------------------------------------------------- fixture --

func seed_fixture()->bool:
	folder=OS.get_environment("TEMP").path_join("tool-action-session-%s"%Crypto.new().generate_random_bytes(8).hex_encode())
	if DirAccess.make_dir_recursive_absolute(folder)!=OK:return false
	save_path=folder.path_join("world.json")
	var w:=World.new()
	w.save_path=save_path
	w.state["picnic"]=true
	w.state["mine_depths"]={"unlocked":9,"ready":{},"pumped":24,"hoist":false}
	w.switch_region(SURFACE)
	var spot:=w.safe_arrival(SURFACE_ARRIVAL)
	w.switch_region(Regions.HOME)
	if spot==Vector2.ZERO:return false
	for token in [ALPHA,BETA,GAMMA]:
		w.add_player(token,{ALPHA:"alpha",BETA:"beta",GAMMA:"gamma"}[token])
	w.state.players[BETA].x=40.5
	w.state.players[BETA].y=35.5
	w.state.players[GAMMA]["region"]=SURFACE
	w.state.players[GAMMA]["x"]=spot.x
	w.state.players[GAMMA]["y"]=spot.y
	w.active_tokens.clear()
	if not w.save():return false
	var parsed=JSON.parse_string(FileAccess.get_file_as_string(save_path))
	return parsed is Dictionary and Schema.validate(parsed,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)

# ------------------------------------------------------------- transport --

func new_branch(prefix:String)->Node:
	serial+=1
	var branch:=Node.new()
	branch.name="%s%d"%[prefix,serial]
	root.add_child(branch)
	set_multiplayer(SceneMultiplayer.new(),branch.get_path())
	return branch

func start_server()->int:
	server_branch=new_branch("Server")
	server=Session.new()
	server_branch.add_child(server)
	server.tool_action_clock=func():return frozen_ms if frozen_ms>=0 else Time.get_ticks_msec()
	for attempt in 8:
		var port:=randi_range(31000,58000)
		if server.host(port,"",save_path,KEY,"127.0.0.1",true,"websocket")==OK:return port
	return 0

func join(label:String,token:String,port:int)->Client:
	var c:=Client.new()
	c.label=label
	c.token=token
	c.secrets=[ALPHA,BETA,GAMMA]
	c.branch=new_branch("Client_%s_"%label)
	c.session=Session.new()
	c.branch.add_child(c.session)
	c.session.profile["token"]=token
	c.session.notice.connect(c.on_notice)
	c.session.changed.connect(c.on_changed)
	clients.append(c)
	if c.session.join("ws://127.0.0.1:%d"%port,port,label,KEY)!=OK:return c
	await wait_until(func():return not c.session.own_id.is_empty() and not c.me().is_empty(),8.0)
	return c

func joined(c:Client)->bool:
	return c!=null and not c.session.own_id.is_empty() and not c.me().is_empty()

func leave(c:Client)->void:
	if c==null or not is_instance_valid(c.session):return
	if not c.session.shutting_down:c.session.shutdown()
	await process_frame
	c.branch.queue_free()

func wait_until(condition:Callable,seconds:float)->bool:
	var deadline:=Time.get_ticks_msec()+int(seconds*1000.0)
	while Time.get_ticks_msec()<deadline:
		if condition.call():return true
		await process_frame
	return condition.call()

func pause(seconds:float)->void:
	await create_timer(seconds).timeout

func settle(group:Array)->void:
	var marks:Array=group.map(func(c):return c.changes)
	await wait_until(func():
		for i in group.size():
			if group[i].changes<int(marks[i])+3:return false
		return true,3.0)

func act(c:Client,action:String,p:Vector2i,extra:String="")->Dictionary:
	var before:=c.notices.size()
	c.session.perform(action,p,extra)
	var replied:=await wait_until(func():return c.notices.size()>before,4.0)
	if not replied:return {"replied":false,"ok":false}
	await settle(live())
	return {"replied":true,"ok":bool(c.notices[before][1])}

func live()->Array:
	return clients.filter(func(c):return is_instance_valid(c.session) and not c.session.shutting_down)

func server_events()->Array:
	return server.tool_action_view("home").events

func newest_n()->int:
	var events:=server_events()
	return int(events.back().n) if not events.is_empty() else 0

# --------------------------------------------------------------- scenario --

var alpha:Client
var beta:Client
var gamma:Client

func scenario()->bool:
	expect(Session.PROTOCOL==48,"tool events use the current cow-care protocol")
	expect(seed_fixture(),"SEEDED FIXTURE written to TEMP and accepted by SaveSchema.validate")
	if save_path.is_empty() or not FileAccess.file_exists(save_path):return false
	var port:=start_server()
	expect(port>0,"server Session hosts on 127.0.0.1 with the websocket transport")
	if port==0:return false
	alpha=await join("alpha",ALPHA,port)
	beta=await join("beta",BETA,port)
	gamma=await join("gamma",GAMMA,port)
	expect(joined(alpha) and joined(beta) and joined(gamma),"three clients joined over loopback")
	if not (joined(alpha) and joined(beta) and joined(gamma)):return false
	var ws:bool=server.multiplayer.multiplayer_peer is WebSocketMultiplayerPeer and alpha.session.multiplayer.multiplayer_peer is WebSocketMultiplayerPeer and beta.session.multiplayer.multiplayer_peer is WebSocketMultiplayerPeer
	expect(ws,"server and clients use WebSocketMultiplayerPeer")
	expect(server.multiplayer.is_server() and not alpha.session.multiplayer.is_server() and not beta.session.multiplayer.is_server(),"one server, remote clients")
	expect(alpha.session.world==null and beta.session.world==null and gamma.session.world==null,"client Sessions hold no World (snapshots only)")
	expect(alpha.region()=="home" and beta.region()=="home" and gamma.region()==SURFACE,"alpha/beta at home, gamma on the jinguashi surface")
	var disallowed_rest:=await act(alpha,"night_rest",Vector2i.ZERO)
	expect(disallowed_rest.replied and not disallowed_rest.ok,"A remote peer cannot advance a multiplayer island unilaterally")
	print("TOOL_ACTION_SESSION_LABEL machine=single process=single transport=%s loopback=127.0.0.1:%d clients=3(alpha,beta home; gamma jinguashi)"%["websocket" if ws else "UNEXPECTED",port])
	await settle(live())
	var a_id:String=alpha.session.own_id
	var b_id:String=beta.session.own_id

	var marked:=await act(alpha,"map_signal",PLOT,"wood")
	var shared:Array=beta.session.snapshot.get("map_signals",[])
	expect(marked.ok and shared.size()==1 and shared[0].cell==PLOT and shared[0].kind=="wood","A nearby marker travels over WebSocket to another resident")
	expect(gamma.session.snapshot.get("map_signals",[]).is_empty(),"Players in a different region receive no marker")
	var far_away:=await act(alpha,"map_signal",Vector2i(60,30),"build")
	expect(not far_away.ok and beta.session.snapshot.map_signals[0].kind=="wood","A distant request cannot replace the active marker")
	var second:=await act(beta,"map_signal",PLOT,"build")
	var cancelled:=await act(alpha,"map_signal",Vector2i.ZERO,"cancel")
	var remaining:Array=beta.session.snapshot.get("map_signals",[])
	expect(second.ok and cancelled.ok and remaining.size()==1 and remaining[0].kind=="build","Cancelling one player's mark leaves the other player's mark intact")
	var marker:Dictionary=server.map_signals.values()[0]
	expect(server.map_signal_view("home",int(marker.until)-1)[0].remaining==1
		and server.map_signal_view("home",int(marker.until)).is_empty(),"The mark expires at its 30-second deadline")

	# 1. alpha's confirmed hoe animates once on alpha and on beta; gamma gets nothing.
	var hoe:=await act(alpha,"hoe",PLOT)
	expect(hoe.ok,"alpha hoe confirmed by the server")
	var hoe_n:=newest_n()
	expect(hoe_n>0 and server_events().back().tool=="hoe" and server_events().back().actor==a_id,"server recorded alpha's hoe with alpha's public id")
	await pause(0.4)
	await settle(live())
	expect(alpha.received.has(hoe_n) and beta.received.has(hoe_n),"actor and same-region peer both receive the hoe event")
	expect(int(alpha.started.get(hoe_n,0))==1,"alpha animates its own confirmed hoe exactly once (got %d)"%int(alpha.started.get(hoe_n,0)))
	expect(int(beta.started.get(hoe_n,0))==1,"beta sees alpha's hoe exactly once despite repeated snapshots (got %d)"%int(beta.started.get(hoe_n,0)))
	expect(beta.changes>=5,"several snapshots carried the event window (changes=%d)"%beta.changes)
	if beta.received.has(hoe_n):
		var e:Dictionary=beta.received[hoe_n]
		expect(e.actor==a_id and e.tool=="hoe" and e.x==PLOT.x and e.y==PLOT.y,"beta's event: public actor id, tool, target cell")
	expect(gamma.received.is_empty() and gamma.started.is_empty(),"other-region client received no tool events")

	# 2. Rejection (plot already tilled): no event, no animation anywhere.
	var counts:=[alpha.received.size(),beta.received.size()]
	var event_counter_before_reject:int=server.tool_action_counter
	var again:=await act(alpha,"hoe",PLOT)
	expect(again.replied and not again.ok,"repeated hoe is rejected by the server")
	await pause(0.3)
	expect(server.tool_action_counter==event_counter_before_reject,"rejected hoe adds no server event (independent of TTL pruning)")
	expect(alpha.received.size()==counts[0] and beta.received.size()==counts[1],"rejected hoe sends no event to anyone")

	# 3. beta's confirmed water: alpha sees beta's animation once; gamma still nothing.
	var water:=await act(beta,"water",PLOT)
	expect(water.ok,"beta water confirmed")
	var water_n:=newest_n()
	await pause(0.3)
	await settle(live())
	expect(water_n>hoe_n and int(alpha.started.get(water_n,0))==1 and int(beta.started.get(water_n,0))==1,"beta's water animates once on both home clients")
	expect(not alpha.received.has(water_n) or alpha.received[water_n].actor==b_id,"water event is attributed to beta's public id")
	expect(gamma.received.is_empty(),"other region still received nothing")

	# 4. Reconnect: an action happens while alpha is away; the rejoining client's
	# first snapshot contains it (server clock frozen so it cannot expire) but it is
	# a baseline and never replays.
	expect(beta.payload_keys_ok and beta.leaked.is_empty(),"beta only received minimal, token-free events")
	await leave(alpha)
	clients.erase(alpha)
	var alpha_gone:bool=await wait_until(func():return not server.peers.values().has(ALPHA),5.0)
	expect(alpha_gone,"server noticed alpha leaving")
	frozen_ms=Time.get_ticks_msec()
	var seed_ok:=await act(beta,"water",PLOT)
	expect(seed_ok.ok,"beta acts while alpha is offline")
	var note_sent:=await act(beta,"news_note",Vector2i.ZERO,"等你回來收成。")
	expect(note_sent.ok,"beta posts a durable note while alpha is offline")
	var away_n:=newest_n()
	alpha=await join("alpha2",ALPHA,port)
	expect(joined(alpha),"alpha rejoined")
	expect(bool(alpha.session.snapshot.island_news.returning) and int(alpha.session.snapshot.island_news.notes_unread)==1,"Reconnect projects the unread offline note for the returning resident")
	var acknowledged:=await act(alpha,"news_notes_read",Vector2i.ZERO,str(alpha.session.snapshot.island_news.note_revision))
	expect(acknowledged.ok and int(alpha.session.snapshot.island_news.notes_unread)==0 and int(beta.session.snapshot.island_news.notes_unread)==1,"Acknowledging the note updates only the reader")
	await pause(0.3)
	await settle(live())
	expect(alpha.first_events.has(away_n),"rejoined alpha's first snapshot still lists the earlier event (window kept open)")
	expect(not alpha.started.has(away_n),"rejoined alpha does not replay the earlier event")
	frozen_ms=-1

	# 5. A fresh action after the rejoin plays normally.
	var axe_setup:=await act(alpha,"water",PLOT)
	expect(axe_setup.ok,"alpha acts after rejoining")
	var fresh_n:=newest_n()
	await pause(0.3)
	await settle(live())
	expect(int(alpha.started.get(fresh_n,0))==1 and int(beta.started.get(fresh_n,0))==1,"post-rejoin action animates once for both")

	# 6. A peer leaves: its pending events are dropped and nothing animates for it.
	var b_last:=await act(beta,"water",PLOT)
	expect(b_last.ok,"beta acts just before leaving")
	await leave(beta)
	clients.erase(beta)
	var beta_gone:bool=await wait_until(func():return not server.peers.values().has(BETA),5.0)
	expect(beta_gone,"server noticed beta leaving")
	await settle(live())
	expect(not server_events().any(func(e):return e.actor==b_id),"server dropped the departed player's events")
	expect(alpha.feedback.active(b_id,Time.get_ticks_msec()/1000.0).is_empty(),"no animation remains for the departed player")

	# 7. Data minimisation over the wire.
	for c in [alpha,gamma]:
		expect(c.leaked.is_empty(),"%s never received a raw token in tool_actions: %s"%[c.label,c.leaked])
		expect(c.payload_keys_ok,"%s only received {actor,n,tool,x,y} events"%c.label)
	expect(gamma.received.is_empty() and gamma.started.is_empty(),"other-region client never received or animated a tool event")
	var tree:=PLOT+Vector2i.DOWN
	var tree_key:=World.key(tree)
	server.world.state.forest[tree_key]={"growth":World.TREE_TIME,"mature":true,"owner":ALPHA}
	var results:Dictionary={}
	alpha.session.action_completed.connect(func(sequence:int,action:String,result:Dictionary):
		if action=="axe":results[sequence]=result
	)
	for hit in 3:
		var sequence:int=alpha.session.perform("axe",tree)
		var arrived:=await wait_until(func():return results.has(sequence),4.0)
		expect(arrived and results[sequence].ok and results[sequence].get("gather_continue",false)==(hit<2),
			"The correlated WebSocket response permits the next swing only before the final hit")
	expect(not server.world.state.forest.has(tree_key),"The last hit removes the authoritative tree")
	await verify_night_vote(port)
	return true

func verify_night_vote(port:int) -> void:
	server.set_physics_process(false)
	server.world.state.time=350.0
	server.world.state.players[GAMMA].region="mine_1"
	for id in server.peers:server._send_snapshot(id)
	var unsafe:=await act(alpha,"night_vote",Vector2i.ZERO,"open")
	expect(not unsafe.ok and server.night_vote.is_empty() and server.world.state.time==350.0,"An online player in a mine prevents opening a ballot")
	server.world.state.players[GAMMA].region=SURFACE
	for id in server.peers:server._send_snapshot(id)
	await settle(live())
	var trade:=World.TRADE.open("test-open",ALPHA,GAMMA,Time.get_unix_time_from_system())
	server.world.trade_offers["test-open"]=trade.offer
	var trading:=await act(alpha,"night_vote",Vector2i.ZERO,"open")
	expect(not trading.ok and server.night_vote.is_empty(),"An active exchange blocks the ballot")
	server.world.trade_offers.clear()
	alpha.session.perform("night_vote",Vector2i.ZERO,"open")
	var visible:=await wait_until(func():return int(gamma.session.snapshot.get("night_vote",{}).get("id",0))>0,5.0)
	expect(visible and bool(alpha.session.snapshot.night_vote.mine)
		and int(gamma.session.snapshot.night_vote.yes)==1 and server.world.state.time==350.0,"The first vote stays pending and is visible across regions")
	if not visible:return
	var first_id:int=gamma.session.snapshot.night_vote.id
	var decline:=await act(gamma,"night_vote",Vector2i.ZERO,"no:%d"%first_id)
	expect(decline.replied and server.night_vote.is_empty() and server.world.state.time==350.0,"One decline closes the ballot without skipping")
	alpha.session.perform("night_vote",Vector2i.ZERO,"open")
	var reopened:=await wait_until(func():return int(gamma.session.snapshot.night_vote.id)>first_id,5.0)
	expect(reopened,"A new ballot has a fresh identifier")
	if not reopened:return
	var second_id:int=gamma.session.snapshot.night_vote.id
	var stale:=await act(gamma,"night_vote",Vector2i.ZERO,"yes:%d"%first_id)
	expect(not stale.ok and server.night_vote.yes.size()==1 and server.world.state.time==350.0,"An older vote cannot approve a new ballot")
	var new_peer:=await join("beta2",BETA,port)
	expect(joined(new_peer) and server.night_vote.is_empty(),"A new arrival cancels the ballot and requires a fresh vote")
	alpha.session.perform("night_vote",Vector2i.ZERO,"open")
	var three_online:=await wait_until(func():
		var vote:Dictionary=new_peer.session.snapshot.get("night_vote",{})
		return int(vote.get("total",0))==3 and int(vote.get("id",0))>second_id
	,5.0)
	expect(three_online,"The new ballot includes all three online players")
	await leave(new_peer)
	clients.erase(new_peer)
	await wait_until(func():return not server.peers.values().has(BETA),5.0)
	expect(server.night_vote.is_empty() and server.world.state.time==350.0,"Leaving never turns a partial vote into a unanimous one")
	alpha.session.perform("night_vote",Vector2i.ZERO,"open")
	var timed:=await wait_until(func():return int(gamma.session.snapshot.night_vote.id)>second_id,5.0)
	expect(timed,"A fresh ballot opens after the membership change")
	if not timed:return
	server.night_vote.until=Time.get_ticks_msec()-1
	server._physics_process(0.0)
	await wait_until(func():return int(gamma.session.snapshot.night_vote.id)==0,5.0)
	expect(server.night_vote.is_empty() and server.world.state.time==350.0,"An expired ballot leaves time alone")
	alpha.session.perform("night_vote",Vector2i.ZERO,"open")
	var final_open:=await wait_until(func():return int(gamma.session.snapshot.night_vote.id)>second_id,5.0)
	expect(final_open,"The last ballot opens for the remaining players")
	if not final_open:return
	var final_id:int=gamma.session.snapshot.night_vote.id
	var before:int=server.world.state.committed
	var finished:=await act(gamma,"night_vote",Vector2i.ZERO,"yes:%d"%final_id)
	expect(finished.ok and server.night_vote.is_empty() and server.world.state.time==360.0
		and float(alpha.session.snapshot.time)==360.0 and float(gamma.session.snapshot.time)==360.0,"Both regions advance together only on unanimous consent")
	var repeated:=await act(gamma,"night_vote",Vector2i.ZERO,"yes:%d"%final_id)
	expect(not repeated.ok and int(server.world.state.committed)==before+1,"A late duplicate cannot settle or save the night again")

func teardown()->void:
	for c in clients.duplicate():await leave(c)
	clients.clear()
	if server!=null and is_instance_valid(server) and not server.shutting_down:server.shutdown()
	await process_frame
	if is_instance_valid(server_branch):server_branch.queue_free()
	await process_frame

func remove_folder()->bool:
	if folder.is_empty() or not DirAccess.dir_exists_absolute(folder):return true
	for name in DirAccess.get_files_at(folder):DirAccess.remove_absolute(folder.path_join(name))
	return DirAccess.remove_absolute(folder)==OK
