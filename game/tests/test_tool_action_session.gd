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
const Audio=preload("res://scripts/soft_audio.gd")
const CropSprites=preload("res://scripts/crop_sprite_art.gd")
const Regions=preload("res://scripts/regions.gd")
const ViewProjection=preload("res://scripts/view_projection.gd")
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
	var audio:Audio
	var heard:Array[AudioStream]=[]
	## view_full of every marked (T046 opted-in) snapshot, and how many carried a rectangle
	var view_modes:Array=[]
	var view_epochs:Array=[]
	var view_levels:Array=[]
	var view_rects:=0
	func on_notice(message:String,success:bool)->void:
		notices.append([message,success])
	func on_changed(data:Dictionary,id:String)->void:
		changes+=1
		if data.has(ViewProjection.FULL):
			view_modes.append(data[ViewProjection.FULL])
			view_levels.append(ViewProjection.packet_level(data))
			view_epochs.append(int(data.get("players",{}).get(id,{}).get("travel_epoch",0)))
			if ViewProjection.packet_rect(data).has_area():view_rects+=1
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
		if audio:
			var listener:Dictionary=data.get("players",{}).get(id,{})
			if not listener.is_empty() and audio.play_nearby_tools(fresh,feedback.actions,id,Vector2(listener.x,listener.y)):
				heard.append(audio.nearby.stream)
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

func join(label:String,token:String,port:int,with_audio:=false)->Client:
	var c:=Client.new()
	c.label=label
	c.token=token
	c.secrets=[ALPHA,BETA,GAMMA]
	c.branch=new_branch("Client_%s_"%label)
	if with_audio:
		c.audio=Audio.new()
		c.branch.add_child(c.audio)
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
	expect(Session.PROTOCOL>=48,"tool events preserve the cow-care protocol feature")
	expect(seed_fixture(),"SEEDED FIXTURE written to TEMP and accepted by SaveSchema.validate")
	if save_path.is_empty() or not FileAccess.file_exists(save_path):return false
	var port:=start_server()
	expect(port>0,"server Session hosts on 127.0.0.1 with the websocket transport")
	if port==0:return false
	alpha=await join("alpha",ALPHA,port,true)
	beta=await join("beta",BETA,port,true)
	gamma=await join("gamma",GAMMA,port,true)
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
	expect(beta.heard==[beta.audio.sounds.hoe_soil] and alpha.heard.is_empty() and gamma.heard.is_empty(),"Exactly the nearby peer plays the remote hoe sound")

	# 2. Rejection (plot already tilled): no event, no animation anywhere.
	var counts:=[alpha.received.size(),beta.received.size()]
	var event_counter_before_reject:int=server.tool_action_counter
	var again:=await act(alpha,"hoe",PLOT)
	expect(again.replied and not again.ok,"repeated hoe is rejected by the server")
	await pause(0.3)
	expect(server.tool_action_counter==event_counter_before_reject,"rejected hoe adds no server event (independent of TTL pruning)")
	expect(alpha.received.size()==counts[0] and beta.received.size()==counts[1],"rejected hoe sends no event to anyone")
	expect(beta.heard.size()==1,"Repeated snapshots and rejected actions do not replay the hoe")

	# 3. beta's confirmed water: alpha sees beta's animation once; gamma still nothing.
	var water:=await act(beta,"water",PLOT)
	expect(water.ok,"beta water confirmed")
	var water_n:=newest_n()
	await pause(0.3)
	await settle(live())
	expect(water_n>hoe_n and int(alpha.started.get(water_n,0))==1 and int(beta.started.get(water_n,0))==1,"beta's water animates once on both home clients")
	expect(not alpha.received.has(water_n) or alpha.received[water_n].actor==b_id,"water event is attributed to beta's public id")
	expect(gamma.received.is_empty(),"other region still received nothing")
	expect(alpha.heard==[alpha.audio.sounds.water_pour] and beta.heard.size()==1 and gamma.heard.is_empty(),"Water plays only on the nearby peer; the actor does not get a duplicate")

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
	alpha=await join("alpha2",ALPHA,port,true)
	expect(joined(alpha),"alpha rejoined")
	expect(bool(alpha.session.snapshot.island_news.returning) and int(alpha.session.snapshot.island_news.notes_unread)==1,"Reconnect projects the unread offline note for the returning resident")
	var acknowledged:=await act(alpha,"news_notes_read",Vector2i.ZERO,str(alpha.session.snapshot.island_news.note_revision))
	expect(acknowledged.ok and int(alpha.session.snapshot.island_news.notes_unread)==0 and int(beta.session.snapshot.island_news.notes_unread)==1,"Acknowledging the note updates only the reader")
	await pause(0.3)
	await settle(live())
	expect(alpha.first_events.has(away_n),"rejoined alpha's first snapshot still lists the earlier event (window kept open)")
	expect(not alpha.started.has(away_n),"rejoined alpha does not replay the earlier event")
	expect(alpha.heard.is_empty(),"Rejoining does not replay the earlier action sound")
	frozen_ms=-1

	# 5. A fresh action after the rejoin plays normally.
	var axe_setup:=await act(alpha,"water",PLOT)
	expect(axe_setup.ok,"alpha acts after rejoining")
	var fresh_n:=newest_n()
	await pause(0.3)
	await settle(live())
	expect(int(alpha.started.get(fresh_n,0))==1 and int(beta.started.get(fresh_n,0))==1,"post-rejoin action animates once for both")
	expect(not beta.heard.is_empty() and beta.heard.back()==beta.audio.sounds.water_pour and alpha.heard.is_empty(),"New remote sounds still play after rejoin")

	await verify_view_interest()
	verify_projection_cache()
	await verify_view_projection()
	verify_structure_cache()
	await verify_structure_projection()
	verify_early_projection_parity()

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

func verify_view_interest()->void:
	var player:Dictionary=server.world.state.players[BETA]
	var original:=Vector2(player.x,player.y)
	player.x=21.5
	player.y=19.5
	beta.session.update_view_interest(Vector2i(8,8))
	await settle(live())
	var remote_damage:=World.key(PLOT)
	server.world.state.damage[remote_damage]=1
	var crop:Dictionary=server.world.state.crops[remote_damage]
	crop.kind="radish"
	crop.growth=27.0
	frozen_ms=Time.get_ticks_msec()
	var distant:=await act(alpha,"water",PLOT)
	var distant_n:=newest_n()
	expect(distant.ok and alpha.received.has(distant_n) and not beta.received.has(distant_n),"Only the subscribed near view receives the tool effect across the same island")
	expect(alpha.session.snapshot.damage.has(remote_damage) and not beta.session.snapshot.damage.has(remote_damage),"A far view omits harvest damage while an unsubscribed peer retains the layer")
	expect(beta.session.snapshot.crops.get(remote_damage,{}).get("wet",false) and int(beta.session.snapshot.tool_actions.get("cursor",0))>=distant_n,"The whole-island plot and event watermark still arrive")
	var far_crop:Dictionary=beta.session.snapshot.crops[remote_damage]
	var full_crop:Dictionary=alpha.session.snapshot.crops[remote_damage]
	expect(far_crop.growth!=full_crop.growth and CropSprites.stage_for(far_crop)==CropSprites.stage_for(full_crop),"Distant crop sends a stable matching art stage in place of each growth tick")
	expect(far_crop.owner==full_crop.owner and crop.growth<35.0,"Crop ownership stays visible and projection never mutates authoritative growth")
	var farmer:Dictionary=server.world.state.players[ALPHA]
	var farm_position:=Vector2(farmer.x,farmer.y)
	farmer.x=21.5
	farmer.y=19.5
	alpha.session.update_view_interest(Vector2i(8,8))
	await settle(live())
	expect(float(alpha.session.snapshot.crops[remote_damage].growth)<35.0,"A subscribed owner still receives exact progress while away from their farm")
	farmer.x=farm_position.x
	farmer.y=farm_position.y
	player.x=original.x
	player.y=original.y
	await settle(live())
	expect(beta.session.snapshot.damage.has(remote_damage) and not beta.started.has(distant_n),"Re-entering the area restores damage without replaying a missed animation")
	expect(float(beta.session.snapshot.crops[remote_damage].growth)<35.0,"A near view receives exact crop growth again")
	server.world.state.damage.erase(remote_damage)
	frozen_ms=-1
	var near:=await act(alpha,"water",PLOT)
	var near_n:=newest_n()
	expect(near.ok and int(beta.started.get(near_n,0))==1,"The next nearby tool animation still plays once")

# T046 phase 1 -------------------------------------------------------------

func projected_packet(full:bool,rect:Array,crops:Dictionary,epoch:=1,region:="home")->Dictionary:
	return {"region_id":region,"players":{"me":{"travel_epoch":epoch}},"crops":crops,"forest":{},"removed":{},
		ViewProjection.RECT:rect,ViewProjection.FULL:full}

## The client cache alone, with hand-built packets.
func verify_projection_cache()->void:
	var island:=[0,0,World.SIZE.x,World.SIZE.y]
	var near:=[0,0,5,5]
	var cache:=ViewProjection.new()
	var seed_packet:=projected_packet(true,island,{"1,1":{"growth":1.0,"owner":"x"},"30,30":{"growth":1.0,"owner":"x"},"31,30":{"growth":1.0,"owner":"me"}})
	expect(is_same(cache.compose(seed_packet,"me"),seed_packet),"A complete packet is shown as sent")
	var part:=projected_packet(false,near,{"1,1":{"growth":2.0,"owner":"x"}})
	var shown:Dictionary=cache.compose(part,"me")
	expect(shown.crops.size()==2 and shown.crops["1,1"].growth==2.0 and shown.crops["30,30"].growth==1.0,"A projection keeps the last known far cell and takes near cells from the packet")
	expect(not shown.crops.has("31,30"),"An own crop missing from a projection is gone, wherever it stood")
	expect(part.crops.size()==1 and not is_same(shown,part),"Composition never changes the packet kept as a delta base")
	shown=cache.compose(projected_packet(false,near,{}),"me")
	expect(shown.crops.size()==1 and shown.crops.has("30,30"),"A near cell missing from the next projection of the same window is removed")
	shown=cache.compose(projected_packet(false,[28,28,5,5],{"1,1":{"growth":9.0,"owner":"me"}}),"me")
	expect(shown.crops.size()==1 and shown.crops["1,1"].growth==9.0,"A moved window drops what it now covers and accepts an own crop outside it")
	# A projection whose rectangle spans the island is still a projection.
	cache.compose(seed_packet,"me")
	shown=cache.compose(projected_packet(false,island,{}),"me")
	expect(shown.crops.is_empty() and shown[ViewProjection.FULL]==false,"Full and projected packets differ by their flag even when the rectangle spans the island")
	# Region, stay and legacy packets never inherit a cache.
	cache.compose(seed_packet,"me")
	shown=cache.compose(projected_packet(false,near,{},2),"me")
	expect(shown.crops.is_empty(),"A new travel epoch starts from an empty cache")
	cache.compose(seed_packet,"me")
	shown=cache.compose(projected_packet(false,near,{},1,"lanyang"),"me")
	expect(shown.crops.is_empty(),"Another region starts from an empty cache")
	cache.compose(seed_packet,"me")
	var legacy:={"region_id":"home","players":{"me":{"travel_epoch":1}},"crops":{},"forest":{},"removed":{}}
	expect(is_same(cache.compose(legacy,"me"),legacy) and cache.compose(projected_packet(false,near,{}),"me").crops.is_empty(),"An unmarked packet passes through and clears the cache")
	cache.compose(seed_packet,"me")
	var broken:=projected_packet(false,[0,0,5],{})
	expect(is_same(cache.compose(broken,"me"),broken) and cache.compose(projected_packet(false,near,{}),"me").crops.is_empty(),"A packet without a usable rectangle is never composed")

func beta_marked(full:bool)->bool:
	return beta.session.snapshot.get(ViewProjection.FULL)==full

## Real WebSocket opt-in: beta negotiates the projection, alpha stays legacy.
func verify_view_projection()->void:
	var state:Dictionary=server.world.state
	var person:Dictionary=state.players[BETA]
	var home:=Vector2(person.x,person.y)
	var theirs:=World.key(PLOT+Vector2i(3,0))
	var mine:=World.key(PLOT+Vector2i(4,0))
	var doomed:=World.key(PLOT+Vector2i(5,0))
	var mine_doomed:=World.key(PLOT+Vector2i(6,0))
	var sapling:=World.key(PLOT+Vector2i(3,2))
	var stump:=World.key(PLOT+Vector2i(4,2))
	var template:Dictionary=state.crops[World.key(PLOT)].duplicate(true)
	template.kind="radish"
	template.growth=2.0
	template.wet=false
	for entry in [[theirs,ALPHA],[mine,BETA],[doomed,ALPHA],[mine_doomed,BETA]]:
		var crop:Dictionary=template.duplicate(true)
		crop.owner=entry[1]
		state.crops[entry[0]]=crop
	state.forest[sapling]={"growth":1.0,"mature":false,"owner":ALPHA}
	var marked_before:=beta.view_modes.size()
	expect(marked_before==0 and bool(beta.session.snapshot.get(ViewProjection.ADVERT,false)),"Before opting in a client sees only the capability flag")
	beta.session.update_view_interest(Vector2i(8,8),true)
	var negotiated:bool=await wait_until(func():return beta_marked(false),5.0)
	expect(negotiated and beta.view_modes[0]==true and beta.view_modes.back()==false,"Opting in is answered by one complete seed and then projections")
	if not negotiated:return
	expect(beta.session._received_snapshot_frame>0,"The projection travels through the WebSocket keyframe and delta path")
	var near_crops:Dictionary=beta.session.snapshot.crops
	expect(near_crops.has(theirs) and near_crops.has(mine) and beta.session.snapshot.forest.has(sapling),"Cells inside the window arrive in a projection")
	# Walk away, then change the far cells behind beta's back.
	person.x=21.5
	person.y=19.5
	var away:bool=await wait_until(func():
		var base:Dictionary=beta.session._received_snapshot_base
		return base.get(ViewProjection.FULL)==false and not ViewProjection.packet_rect(base).has_point(PLOT),5.0)
	expect(away,"A keyframe for the far window arrives")
	state.crops[theirs].growth=12.0
	state.crops[mine].growth=12.0
	state.crops.erase(doomed)
	state.crops.erase(mine_doomed)
	state.forest[sapling].growth=150.0
	state.removed[stump]=true
	await settle(live())
	await settle(live())
	var wire:Dictionary=beta.session._received_snapshot_base
	var shown:Dictionary=beta.session.snapshot
	expect(not wire.crops.has(theirs) and not wire.forest.has(sapling) and wire.crops.has(mine),"The far packet carries the recipient's own crop and no other far cell")
	expect(beta_marked(false) and float(shown.crops.get(theirs,{}).get("growth",0.0))<8.0 and shown.crops.has(doomed)
		and float(shown.forest.get(sapling,{}).get("growth",0.0))<60.0 and not shown.removed.has(stump),"Far cells stay at their last known value instead of vanishing")
	expect(float(shown.crops.get(mine,{}).get("growth",0.0))>=12.0 and not shown.crops.has(mine_doomed),"Own crops stay exact across the island, removal included")
	var legacy:Dictionary=alpha.session.snapshot
	expect(not legacy.has(ViewProjection.FULL) and not legacy.has(ViewProjection.RECT) and alpha.view_modes.is_empty()
		and float(legacy.crops[theirs].growth)>=12.0 and not legacy.crops.has(doomed) and legacy.removed.has(stump),"A client that never opted in keeps receiving every layer unmarked")
	# Bounded refresh: a due seed replaces the stale cells, then projections resume.
	server.view_refresh_ms=1
	var refreshed:bool=await wait_until(func():return beta_marked(true),5.0)
	server.view_refresh_ms=ViewProjection.REFRESH_MS
	shown=beta.session.snapshot
	expect(refreshed and ViewProjection.packet_rect(shown)==Rect2i(Vector2i.ZERO,World.SIZE) and float(shown.crops[theirs].growth)>=12.0
		and not shown.crops.has(doomed) and float(shown.forest[sapling].growth)>=150.0 and shown.removed.has(stump),"A due refresh sends complete layers marked full with the island rectangle")
	var resumed:bool=await wait_until(func():return beta_marked(false),5.0)
	shown=beta.session.snapshot
	expect(resumed and float(shown.crops[theirs].growth)>=12.0 and not shown.crops.has(doomed) and shown.removed.has(stump),"Projections after the refresh build on the refreshed cells")
	# Stale again, then walk back: the window itself brings the fresh cell.
	state.crops[theirs].growth=22.0
	await settle(live())
	expect(float(beta.session.snapshot.crops[theirs].growth)<18.0,"A later far change is again withheld")
	person.x=home.x
	person.y=home.y
	var back:bool=await wait_until(func():return beta_marked(false) and float(beta.session.snapshot.crops[theirs].growth)>=22.0,5.0)
	expect(back and ViewProjection.packet_rect(beta.session.snapshot).has_point(PLOT),"Walking back replaces the stale cell from a projection whose rectangle now covers it")
	# Whole-island request, then release.
	beta.session.hold_full_view("map")
	beta.session.update_view_interest(Vector2i(8,8),true)
	var held:bool=await wait_until(func():return beta_marked(true),5.0)
	var held_from:=beta.view_modes.size()
	await settle(live())
	expect(held and beta.view_modes.size()>held_from and not beta.view_modes.slice(held_from).has(false),"Every packet is complete while the whole island is requested")
	beta.session.release_full_view("map")
	beta.session.update_view_interest(Vector2i(8,8),true)
	expect(await wait_until(func():return beta_marked(false),5.0),"Releasing the request returns to projections")
	# A new stay (travel epoch) is seeded before any projection.
	var next_epoch:=int(person.travel_epoch)+1
	person.travel_epoch=next_epoch
	var reseeded:bool=await wait_until(func():return beta.view_epochs.has(next_epoch) and beta_marked(false),5.0)
	expect(reseeded and beta.view_modes[beta.view_epochs.find(next_epoch)]==true,"A new travel epoch gets a complete seed first")
	expect(beta.view_rects==beta.view_modes.size(),"Every marked packet carried its rectangle")
	# Opting out restores the unmarked legacy stream for the rest of the scenario.
	beta.session.update_view_interest(Vector2i(8,8))
	var opted_out:bool=await wait_until(func():return not beta.session.snapshot.has(ViewProjection.FULL),5.0)
	expect(opted_out and beta.session.snapshot.crops.has(theirs),"Opting out returns to unmarked complete layers")
	for key in [theirs,mine]:state.crops.erase(key)
	state.forest.erase(sapling)
	state.removed.erase(stump)
	await settle(live())

# T046 phase 2 -------------------------------------------------------------

func structure_packet(full:bool,rect:Array,ground:Dictionary,roofs:Dictionary,edges:Dictionary,level:=2)->Dictionary:
	var packet:=projected_packet(full,rect,{})
	packet.merge({"ground":ground,"roofs":roofs,"edges":edges})
	if level!=1:packet[ViewProjection.LEVEL]=level
	return packet

## Edge eligibility, server trimming and the client cache for ground, roofs and edges.
func verify_structure_cache()->void:
	var window:=Rect2i(10,10,5,5)
	var accepted:=["10,10,N","12,10,N","10,15,N","10,12,W","15,12,W","14,14,W"]
	var refused:=["10,16,N","12,9,N","16,12,W","9,12,W","15,15,N","15,15,W"]
	expect(accepted.all(func(id):return ViewProjection.inside("edges",id,window)) and not refused.any(func(id):return ViewProjection.inside("edges",id,window)),
		"A canonical edge is eligible exactly when one of the two cells it separates lies in the window")
	var corner:=Rect2i(75,55,5,5)
	expect(ViewProjection.inside("edges","80,57,W",corner) and ViewProjection.inside("edges","77,60,N",corner) and not ViewProjection.inside("edges","80,54,W",corner),
		"Rim edges whose owner cell is off the map follow their one island cell")
	expect(ViewProjection.inside("edges","bad",window) and ViewProjection.inside("edges","1,1,S",window)
		and ViewProjection.inside("ground","10,10",window) and not ViewProjection.inside("ground","15,10",window) and not ViewProjection.inside("roofs","9,14",window),
		"A non-canonical edge key is never withheld, and cell layers use the plain rectangle")
	expect(ViewProjection.level_of(ViewProjection.opt_in(2))==2 and ViewProjection.level_of(ViewProjection.opt_in(1))==1 and ViewProjection.level_of("")==0 and ViewProjection.opt_in(0)==""
		and ViewProjection.offered_level(true)==1 and ViewProjection.offered_level(2)==2 and ViewProjection.offered_level(9)==ViewProjection.MAX_LEVEL and ViewProjection.offered_level(null)==0,
		"Levels map to their opt-in words, and a phase 1 server's flag reads as level 1")
	# Server trimming.
	var floor_x:={"type":"floor","owner":"x","items":{}}
	var floor_me:={"type":"floor","owner":"me","items":{}}
	var wall_x:={"type":"edge_wall","owner":"x"}
	var wall_me:={"type":"edge_wall","owner":"me"}
	var source:={"ground":{"11,11":floor_x,"30,30":floor_x,"31,30":floor_me},"roofs":{"11,11":floor_x,"30,30":floor_x,"31,30":floor_me},
		"edges":{"10,15,N":wall_x,"10,16,N":wall_x,"15,12,W":wall_x,"16,12,W":wall_x,"40,40,W":wall_me},"crops":{},"forest":{},"removed":{},"objects":{"30,30":{"type":"chest"}}}
	var first:=source.duplicate(true)
	ViewProjection.project(first,window,"me",1)
	expect(first.ground==source.ground and first.roofs==source.roofs and first.edges==source.edges and not first.has(ViewProjection.LEVEL) and first[ViewProjection.FULL]==false,
		"A phase 1 projection leaves ground, roofs and edges complete and carries no level")
	var second:=source.duplicate(true)
	ViewProjection.project(second,window,"me",2)
	expect(second.ground.keys()==["11,11","31,30"] and second.roofs.keys()==["11,11","31,30"] and second.edges.keys()==["10,15,N","15,12,W","40,40,W"]
		and second[ViewProjection.LEVEL]==2 and second.objects==source.objects,
		"A phase 2 projection keeps window cells, both-side boundary edges and the recipient's own rows, and never trims objects")
	var whole:=source.duplicate(true)
	ViewProjection.mark_full(whole,Rect2i(Vector2i.ZERO,World.SIZE),2)
	expect(whole.ground==source.ground and whole.edges==source.edges and whole[ViewProjection.LEVEL]==2 and ViewProjection.complete(whole) and not ViewProjection.complete(second) and ViewProjection.complete(source),
		"Full and legacy packets read as complete, a projection does not")
	expect(not ViewProjection.complete(first) and ViewProjection.structure_complete(first) and not ViewProjection.structure_complete(second) and ViewProjection.structure_complete(whole) and ViewProjection.structure_complete(source),
		"Structure layers count as complete in every packet except a phase 2 projection")
	# Client cache.
	var island:=[0,0,World.SIZE.x,World.SIZE.y]
	var near:=[10,10,5,5]
	var cache:=ViewProjection.new()
	var seed_packet:=structure_packet(true,island,source.ground,source.roofs,source.edges)
	expect(is_same(cache.compose(seed_packet,"me"),seed_packet),"A complete phase 2 packet is shown as sent")
	var part:=structure_packet(false,near,{"11,11":floor_x,"31,30":floor_me},{"31,30":floor_me},{"10,15,N":wall_x,"40,40,W":wall_me})
	var shown:Dictionary=cache.compose(part,"me")
	expect(shown.ground.size()==3 and shown.ground.has("30,30") and shown.roofs.size()==2 and not shown.roofs.has("11,11") and shown.roofs.has("30,30"),
		"Far ground and roofs stay at their last known value while a near roof missing from the window is removed")
	expect(shown.edges.size()==4 and shown.edges.has("10,16,N") and shown.edges.has("16,12,W") and not shown.edges.has("15,12,W"),
		"A boundary edge missing from the window is removed; edges beyond it are kept")
	expect(part.edges.size()==2 and part.ground.size()==2,"Composition leaves the phase 2 packet untouched as a delta base")
	var again:Dictionary=cache.compose(part.duplicate(true),"me")
	expect(is_same(again.ground,shown.ground) and is_same(again.edges,shown.edges) and again.edges==shown.edges,"An unchanged window reuses the composed layers")
	shown=cache.compose(structure_packet(false,near,{"11,11":floor_x},{},{"10,15,N":wall_x}),"me")
	expect(not shown.ground.has("31,30") and not shown.roofs.has("31,30") and not shown.edges.has("40,40,W") and shown.ground.has("30,30"),
		"The recipient's own far floor, roof and wall disappear as soon as a projection omits them")
	shown=cache.compose(structure_packet(false,[28,28,5,5],{},{},{"10,15,N":wall_me}),"me")
	expect(not shown.ground.has("30,30") and not shown.roofs.has("30,30") and shown.ground.has("11,11") and shown.edges.get("10,15,N",{}).get("owner")=="me" and shown.edges.has("10,16,N"),
		"A moved window drops what it now covers, keeps the cells it left and accepts an own wall outside it")
	# Levels never share a cache, and an unknown level is never composed.
	cache.compose(seed_packet,"me")
	var crops_only:=projected_packet(false,near,{})
	crops_only.merge({"ground":source.ground,"roofs":source.roofs,"edges":source.edges})
	shown=cache.compose(crops_only,"me")
	expect(is_same(shown.ground,source.ground) and is_same(shown.edges,source.edges),"A phase 1 packet's structure layers pass through as sent")
	shown=cache.compose(structure_packet(false,near,{},{},{}),"me")
	expect(shown.ground.is_empty() and shown.edges.is_empty(),"A change of level starts from an empty cache")
	cache.compose(seed_packet,"me")
	var future:=structure_packet(false,near,{},{},{},3)
	expect(is_same(cache.compose(future,"me"),future) and cache.compose(structure_packet(false,near,{},{},{}),"me").ground.is_empty(),"A packet of an unknown level is never composed and clears the cache")
	var hollow:=structure_packet(false,near,{},{},{})
	hollow.erase("edges")
	expect(is_same(cache.compose(hollow,"me"),hollow),"A phase 2 packet missing a structure layer is never composed")

func beta_level(full:bool,level:int)->bool:
	var data:Dictionary=beta.session.snapshot
	return data.get(ViewProjection.FULL)==full and ViewProjection.packet_level(data)==level and data.has(ViewProjection.LEVEL)==(level>=2)

## Real WebSocket: beta negotiates ground, roofs and edges; alpha stays legacy.
func verify_structure_projection()->void:
	var state:Dictionary=server.world.state
	var person:Dictionary=state.players[BETA]
	var home:=Vector2(person.x,person.y)
	# Far window after the walk: centre (21,19), half 8 -> x 13..29, y 11..27.
	var their_floor:=World.key(PLOT+Vector2i(3,3))
	var my_floor:=World.key(PLOT+Vector2i(4,3))
	var my_doomed_floor:=World.key(PLOT+Vector2i(5,3))
	var their_wall:="%d,%d,N"%[PLOT.x+3,PLOT.y+3]
	var my_wall:="%d,%d,N"%[PLOT.x+4,PLOT.y+3]
	var late_wall:="%d,%d,W"%[PLOT.x+3,PLOT.y+3]
	var rim_wall:="30,20,W"
	var beyond_wall:="31,20,W"
	for entry in [[their_floor,ALPHA],[my_floor,BETA],[my_doomed_floor,BETA]]:
		state.ground[entry[0]]={"type":"floor","owner":entry[1],"items":{}}
	state.roofs[their_floor]={"type":"roof","owner":ALPHA,"items":{}}
	state.roofs[my_floor]={"type":"roof","owner":BETA,"items":{}}
	state.edges[their_wall]={"type":"edge_wall","owner":ALPHA}
	state.edges[my_wall]={"type":"edge_wall","owner":BETA}
	state.edges[rim_wall]={"type":"edge_wall","owner":ALPHA}
	state.edges[beyond_wall]={"type":"edge_wall","owner":ALPHA}
	await settle(live())
	expect(int(beta.session.snapshot.get(ViewProjection.ADVERT,0))==ViewProjection.MAX_LEVEL and not beta.session.snapshot.has(ViewProjection.FULL),"The server advertises the phase 2 level to a client that has not opted in")
	# A phase 1 client keeps complete structure layers.
	beta.session.view_layers_level=1
	beta.session.update_view_interest(Vector2i(8,8),true)
	var first:bool=await wait_until(func():return beta_level(false,1),5.0)
	person.x=21.5
	person.y=19.5
	var first_away:bool=await wait_until(func():
		var base:Dictionary=beta.session._received_snapshot_base
		return base.get(ViewProjection.FULL)==false and not ViewProjection.packet_rect(base).has_point(PLOT),5.0)
	var wire:Dictionary=beta.session._received_snapshot_base
	expect(first and first_away and beta.session.structure_view_complete() and not beta.session.view_complete() and not wire.has(ViewProjection.LEVEL) and wire.ground.has(their_floor) and wire.roofs.has(their_floor) and wire.edges.has(their_wall) and wire.edges.has(beyond_wall),
		"A phase 1 opt-in still receives every ground, roof and edge cell")
	# Raising the level is answered by a complete seed before any phase 2 projection.
	var before:=beta.view_modes.size()
	beta.session.view_layers_level=2
	beta.session.update_view_interest(Vector2i(8,8),true)
	var second:bool=await wait_until(func():return beta_level(false,2),5.0)
	var first_two:=beta.view_levels.find(2,before)
	expect(second and first_two>=0 and beta.view_modes[first_two]==true and not beta.view_levels.slice(first_two).has(1),"Raising the level gets a complete phase 2 seed first, then phase 2 projections")
	if not second:return
	await settle(live())
	wire=beta.session._received_snapshot_base
	var shown:Dictionary=beta.session.snapshot
	expect(wire.get(ViewProjection.FULL)==false and not wire.ground.has(their_floor) and not wire.roofs.has(their_floor) and not wire.edges.has(their_wall),"A far phase 2 packet omits other players' ground, roofs and edges")
	expect(wire.ground.has(my_floor) and wire.roofs.has(my_floor) and wire.edges.has(my_wall),"The recipient's own floor, roof and wall travel in every packet")
	expect(wire.edges.has(rim_wall) and not wire.edges.has(beyond_wall),"An edge on the window boundary is sent because its inner cell is in view; the next one out is not")
	expect(shown.ground.has(their_floor) and shown.roofs.has(their_floor) and shown.edges.has(their_wall) and shown.edges.has(beyond_wall)
		and shown.objects.size()==alpha.session.snapshot.objects.size() and shown.objects.has_all(alpha.session.snapshot.objects.keys()),"The composed view keeps the far structure, and objects are still complete")
	# Change the far structure behind beta's back.
	state.roofs.erase(their_floor)
	state.edges.erase(their_wall)
	state.edges[late_wall]={"type":"edge_door","owner":ALPHA,"open":true}
	state.ground[their_floor].type="stone_floor"
	state.ground.erase(my_doomed_floor)
	state.roofs.erase(my_floor)
	state.edges[my_wall]={"type":"edge_door","owner":BETA,"open":false}
	state.edges.erase(rim_wall)
	await settle(live())
	await settle(live())
	shown=beta.session.snapshot
	expect(beta_level(false,2) and shown.roofs.has(their_floor) and shown.edges.has(their_wall) and not shown.edges.has(late_wall) and shown.ground[their_floor].type=="floor",
		"Another player's far structure stays at its last known state while projected")
	expect(not shown.ground.has(my_doomed_floor) and not shown.roofs.has(my_floor) and shown.edges[my_wall].type=="edge_door" and shown.ground.has(my_floor),
		"The recipient's own far structure is exact: removals and changes arrive at once")
	expect(not shown.edges.has(rim_wall) and shown.edges.has(beyond_wall),"A boundary wall removed on the server disappears from the composed view")
	expect(not beta.session.view_complete() and not beta.session.structure_view_complete() and alpha.session.view_complete() and alpha.session.structure_view_complete(),"The session reports whether the shown layers are complete")
	var legacy:Dictionary=alpha.session.snapshot
	expect(not legacy.has(ViewProjection.FULL) and not legacy.roofs.has(their_floor) and not legacy.edges.has(their_wall) and legacy.edges.has(late_wall)
		and legacy.ground[their_floor].type=="stone_floor","The legacy client keeps receiving the true structure layers")
	# Opening construction holds the whole view: the far structure becomes current.
	beta.session.set_full_view("build",true)
	beta.session.update_view_interest(Vector2i(8,8),true)
	var held:bool=await wait_until(func():return beta_level(true,2),5.0)
	shown=beta.session.snapshot
	expect(held and beta.session.view_complete() and beta.session.structure_view_complete() and shown.roofs==legacy.roofs and shown.edges==legacy.edges and shown.ground==legacy.ground,
		"Holding the whole view makes every ground, roof and edge cell current")
	beta.session.set_full_view("build",false)
	beta.session.update_view_interest(Vector2i(8,8),true)
	var released:bool=await wait_until(func():return beta_level(false,2),5.0)
	shown=beta.session.snapshot
	expect(released and not shown.roofs.has(their_floor) and shown.edges.has(late_wall) and shown.ground[their_floor].type=="stone_floor","Projections after the hold build on the refreshed structure")
	# Walking back brings the window's own cells.
	state.edges.erase(late_wall)
	await settle(live())
	expect(beta.session.snapshot.edges.has(late_wall),"A later far change is again withheld")
	person.x=home.x
	person.y=home.y
	var back:bool=await wait_until(func():return beta_level(false,2) and not beta.session.snapshot.edges.has(late_wall),5.0)
	expect(back,"Walking back replaces the stale edge from a projection whose window covers it")
	# Restore the fixture and the unmarked stream.
	beta.session.update_view_interest(Vector2i(8,8))
	var opted_out:bool=await wait_until(func():return not beta.session.snapshot.has(ViewProjection.FULL),5.0)
	expect(opted_out and not beta.session.snapshot.has(ViewProjection.LEVEL),"Opting out of phase 2 returns to unmarked complete layers")
	for cell_key in [their_floor,my_floor,my_doomed_floor]:
		state.ground.erase(cell_key)
		state.roofs.erase(cell_key)
	for edge_key in [their_wall,my_wall,late_wall,rim_wall,beyond_wall]:state.edges.erase(edge_key)
	await settle(live())

## T061: a projection's rows are chosen before the per-recipient copy and redaction.
## Runs synchronously on the live server Session (no frame passes, nothing is sent):
## the production snapshot builder with the early choice must give the packet the
## earlier trim-after-redaction order gives for the same world and the same plan.
func verify_early_projection_parity()->void:
	var state:Dictionary=server.world.state
	var id:int=server.peers.find_key(BETA)
	var person:Dictionary=state.players[BETA]
	var me:=BETA.sha256_text().left(16)
	var window:=Rect2i(Vector2i(floori(person.x),floori(person.y))-Vector2i(8,8),Vector2i(17,17))
	var kept_interest:Variant=server._view_interests.get(id)
	var kept_level:Variant=server._view_layers.get(id)
	var kept_seed:Variant=server._view_seeds.get(id)
	var kept_layers:Dictionary={}
	for layer:String in ViewProjection.LAYERS+ViewProjection.STRUCTURE_LAYERS:kept_layers[layer]=state[layer].duplicate(true)
	# Dense far farm: 320 rows outside the window, every 40th the recipient's own.
	var far_theirs:=""
	var far_mine:=""
	var index:=0
	for x in range(2,22):
		for y in range(2,18):
			var mine:bool=index%40==0
			var owner:String=BETA if mine else ALPHA
			var crop:Dictionary={"kind":"radish","growth":2.0+index*0.01,"wet":index%2==0,"owner":owner}
			if index%7==0:crop["harvest_friend"]=GAMMA
			state.crops[World.key(Vector2i(x,y))]=crop
			if mine and far_mine.is_empty():far_mine=World.key(Vector2i(x,y))
			if not mine and far_theirs.is_empty():far_theirs=World.key(Vector2i(x,y))
			if index%4==0:state.ground[World.key(Vector2i(x,y+20))]={"type":"floor","owner":owner,"items":{}}
			if index%8==0:state.roofs[World.key(Vector2i(x,y+20))]={"type":"roof","owner":owner,"items":{}}
			if index%8==0:state.edges["%d,%d,N"%[x,y+20]]={"type":"edge_wall","owner":owner}
			if index%16==0:state.forest[World.key(Vector2i(x+30,y))]={"growth":1.0,"mature":false,"owner":ALPHA}
			if index%16==0:state.removed[World.key(Vector2i(x+30,y+1))]=true
			index+=1
	var near_theirs:=World.key(window.position+Vector2i(1,1))
	var near_mine:=World.key(window.position+Vector2i(2,1))
	state.crops[near_theirs]={"kind":"radish","growth":3.0,"wet":true,"owner":ALPHA}
	state.crops[near_mine]={"kind":"radish","growth":4.0,"wet":true,"owner":BETA}
	# Guest fields are redacted per row; the far rows differ only in who owns them.
	var far_guest_floor:="3,50"
	var far_host_floor:="4,50"
	var near_floor:=World.key(window.position+Vector2i(1,3))
	state.ground[far_guest_floor]={"type":"floor","owner":ALPHA,"items":{},"visit_guest":BETA}
	state.ground[far_host_floor]={"type":"floor","owner":BETA,"items":{},"visit_guest":ALPHA}
	state.ground[near_floor]={"type":"floor","owner":ALPHA,"items":{},"visit_guest":GAMMA}
	state.roofs[near_floor]={"type":"roof","owner":ALPHA,"items":{}}
	var rim_wall:="%d,%d,W"%[window.end.x,window.position.y+2]
	var beyond_wall:="%d,%d,W"%[window.end.x+1,window.position.y+2]
	var odd_wall:="not-a-canonical-edge"
	for edge_key:String in [rim_wall,beyond_wall,odd_wall]:state.edges[edge_key]={"type":"edge_wall","owner":ALPHA}
	server._view_interests[id]=Vector2i(8,8)
	var world_before:=var_to_bytes(state)
	var dense_plan:Dictionary={}
	for level:int in [1,2]:
		server._view_layers[id]=level
		server._view_seeds[id]={"epoch":int(person.get("travel_epoch",0)),"at":Time.get_ticks_msec(),"level":level}
		var plan:Dictionary=server._view_plan(id)
		expect(plan.home and plan.tracked and plan.level==level and not plan.full and plan.interest==window,"A seeded level %d peer is planned a projection of its window"%level)
		server.view_early_projection=true
		var early:Dictionary=server._snapshot_data(id,plan)
		server.view_early_projection=false
		var late:Dictionary=server._snapshot_data(id,plan)
		server.view_early_projection=true
		var same:bool=var_to_bytes(early)==var_to_bytes(late)
		expect(same,"Level %d: choosing rows before the copy gives the byte-identical packet of trimming after redaction"%level)
		if not same:
			for field:Variant in late:
				if not early.has(field) or var_to_bytes(early[field])!=var_to_bytes(late[field]):print("TOOL_ACTION_SESSION early projection differs in %s"%str(field))
		expect(early.get(ViewProjection.FULL)==false and ViewProjection.packet_rect(early)==window and ViewProjection.packet_level(early)==level,"Level %d: the early packet is marked as a projection of the window"%level)
		expect(not early.crops.has(far_theirs) and early.crops.has(near_theirs) and early.crops.has(near_mine)
			and early.crops.get(far_mine,{}).get("owner")==me and early.crops.get(far_mine,{}).get("harvest_friend")==GAMMA.sha256_text().left(16),"Level %d: far crops of others are left out, own far crops stay with public ids"%level)
		var text:=var_to_str(early)
		expect(not text.contains(ALPHA) and not text.contains(BETA) and not text.contains(GAMMA),"Level %d: no raw owner or guest token reaches the early packet"%level)
		if level==1:
			expect(early.ground.has(far_guest_floor) and early.edges.has(beyond_wall) and early.roofs.size()==state.roofs.size()
				and early.ground.size()==state.ground.size() and early.edges.size()==state.edges.size(),"Level 1 keeps complete structure layers")
		else:
			expect(not early.ground.has(far_guest_floor) and early.ground.get(far_host_floor,{}).get("visit_guest")==ALPHA.sha256_text().left(16)
				and early.ground.get(far_host_floor,{}).get("owner")==me and early.ground.has(near_floor) and not early.ground[near_floor].has("visit_guest")
				and early.roofs.has(near_floor),"Level 2: structure rows keep their per-recipient guest redaction")
			expect(early.edges.has(rim_wall) and not early.edges.has(beyond_wall) and early.edges.has(odd_wall),"Level 2: rim and non-canonical edges are sent, edges past the rim are not")
			dense_plan=plan
		expect(early.objects.size()==state.objects.size() and early.has("own_crop_summary") and early.has("room_population") and early.has("tool_actions"),"Level %d: objects and the whole-view summaries are unaffected"%level)
		# Complete packets never take the early path.
		var full_plan:Dictionary=plan.duplicate()
		full_plan.full=true
		var full_early:Dictionary=server._snapshot_data(id,full_plan)
		server.view_early_projection=false
		var full_late:Dictionary=server._snapshot_data(id,full_plan)
		server.view_early_projection=true
		expect(var_to_bytes(full_early)==var_to_bytes(full_late) and full_early.get(ViewProjection.FULL)==true and full_early.crops.size()==state.crops.size()
			and full_early.ground.size()==state.ground.size() and full_early.edges.size()==state.edges.size(),"Level %d: a seed or refresh still carries every row"%level)
	server._view_layers[id]=0
	var legacy_plan:Dictionary=server._view_plan(id)
	var legacy:Dictionary=server._snapshot_data(id,legacy_plan)
	expect(legacy_plan.tracked and legacy_plan.level==0 and not server._view_seeds.has(id) and not legacy.has(ViewProjection.FULL)
		and legacy.crops.size()==state.crops.size() and legacy.ground.size()==state.ground.size(),"A window without layers keeps every row, unmarked, and drops the seed")
	expect(var_to_bytes(state)==world_before,"Building early and reference snapshots leaves the world state untouched")
	# Focused timing on the same input, alternating so drift affects both equally.
	if not dense_plan.is_empty():
		var shifted:=dense_plan.duplicate()
		shifted.interest=dense_plan.interest.grow(3)
		var original:Dictionary=server._snapshot_data(id,dense_plan)
		var shifted_original:Dictionary=server._snapshot_data(id,shifted)
		server._begin_broadcast_share()
		var shared:Dictionary=server._snapshot_data(id,dense_plan)
		var cached_count:int=server._bcast_cell_positions.size()
		var shared_shifted:Dictionary=server._snapshot_data(id,shifted)
		expect(cached_count>=state.crops.size() and server._bcast_cell_positions.size()==cached_count,
			"A broadcast decodes each tile position once across different interest windows")
		expect(var_to_bytes(shared)==var_to_bytes(original) and var_to_bytes(shared_shifted)==var_to_bytes(shifted_original),
			"Reusing positions preserves wire payloads for both window sizes")
		server._end_broadcast_share()
		expect(server._bcast_cell_positions.is_empty(),"Position cache is scoped to a single broadcast")
		const ROUNDS:=40
		var spent:Dictionary={true:0,false:0}
		for turn in ROUNDS:
			for mode:bool in [turn%2==0,turn%2!=0]:
				server.view_early_projection=mode
				var started:=Time.get_ticks_usec()
				server._snapshot_data(id,dense_plan)
				spent[mode]+=Time.get_ticks_usec()-started
		server.view_early_projection=true
		print("VIEW_EARLY_PROJECTION_TIMING level=2 crops=%d ground=%d edges=%d builds=%d reference_ms=%.2f early_ms=%.2f"%[state.crops.size(),state.ground.size(),state.edges.size(),ROUNDS,spent[false]*0.001,spent[true]*0.001])
	for layer:String in kept_layers:
		state[layer].clear()
		state[layer].merge(kept_layers[layer])
	for entry:Array in [[server._view_interests,kept_interest],[server._view_layers,kept_level],[server._view_seeds,kept_seed]]:
		if entry[1]==null:entry[0].erase(id)
		else:entry[0][id]=entry[1]

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
