extends SceneTree
## T017 hand-tool action feedback, local (no transport) level:
## 1. Session records a public event only for a fresh, World-confirmed success of
##    each hand tool; rejections, rate-limited, re-sent and receipt-replayed
##    requests, non-tool actions and farm machines add nothing. Events carry only
##    {n,actor,tool,x,y[,tx,ty]}; same-region filtering, TTL, cap, leaving player.
## 2. ToolActionFeedback plays each event once: baseline on first snapshot,
##    duplicate snapshots, region change, server epoch change, reset (reconnect),
##    absent actors, invalid events, one animation per actor, expiry.
## 3. Per-tool plans: motion + particles normally; reduced motion has a fixed
##    pose, no lunge/lift and no particles. Held icons come from existing PNG art.
## 4. WorldView draw path (real _draw frames): normal motion draws particles,
##    lunges and a moving tool; reduced motion draws the tool but no particles,
##    no lunge and a single angle.
const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const Feedback=preload("res://scripts/tool_action_feedback.gd")
const View=preload("res://scripts/world_view.gd")
const ALPHA:="tool-action-alpha-private-token"
const BETA:="tool-action-beta-private-token"
const GAMMA:="tool-action-gamma-private-token"
const EVENT_KEYS:=["actor","n","tool","x","y"]
const MOVE_KEYS:=["actor","n","tool","tx","ty","x","y"]

var checks:=0
var failures:=0
var session
var w
var seqs:={1:0,2:0,3:0}
var notices:Array=[]
var clock_ms:=500000

func expect(ok:bool,label:String)->void:
	checks+=1
	if not ok:
		failures+=1
		push_error("FAIL "+label)

func _initialize()->void:
	run.call_deferred()

func on_notice(message:String,success:bool)->void:
	notices.append([message,success])

static func public_id(token:String)->String:
	return token.sha256_text().left(16)

## Sends one request through Session._action (the same path request_action uses).
func send(id:int,action:String,p:Vector2i,extra:String="")->bool:
	seqs[id]=int(seqs[id])+1
	session.rates[id]=[]
	var before:=notices.size()
	session._action(id,int(seqs[id]),action,p,extra)
	if id!=1:return true
	return notices.size()>before and bool(notices.back()[1])

func events_for(region:String)->Array:
	return session.tool_action_view(region).events

func run()->void:
	await server_events()
	client_observer()
	interrupted_targets()
	resource_reactions()
	resource_finishes()
	watered_plant_response()
	tool_plans()
	await view_draw_path()
	print("TOOL_ACTION_FEEDBACK_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 or checks==0 else 0)

# ------------------------------------------------------------ 1. server --

func server_events()->void:
	session=Session.new()
	root.add_child(session)
	session.set_physics_process(false)
	session.notice.connect(on_notice)
	session.tool_action_clock=func():return clock_ms
	session.world=World.new()
	w=session.world
	for token in [ALPHA,BETA,GAMMA]:w.add_player(token,token.left(10))
	w.state.players[BETA].x=40.5
	w.state.players[BETA].y=35.5
	w.state.players[GAMMA].region="jinguashi"
	session.peers={1:ALPHA,2:BETA,3:GAMMA}
	session.sequences={1:0,2:0,3:0}
	session.rates={1:[],2:[],3:[]}
	expect(not session.tool_action_epoch.is_empty(),"server session has a random tool-action epoch")
	expect(Session.PROTOCOL==47,"tool events use the current chicken-care protocol")
	me().inventory.wood=100
	me().inventory.stone=50
	var plot:=Vector2i(38,34)
	var tree:=Vector2i(39,35)
	w.state.forest[World.key(tree)]={"owner":ALPHA,"mature":true,"growth":World.TREE_TIME}
	var rock:=find_rock()
	expect(rock!=Vector2i(-1,-1),"fixture: a natural rock cell exists on the home island")
	var steps:=[
		["hoe",plot,""],
		["seed",plot,"radish"],
		["water",plot,""],
		["harvest",plot,""],
		["axe",tree,""],
		["pick",rock,""],
		["build",Vector2i(38,33),"chest"],
		["move_object",Vector2i(38,33),"40,33"],
		["remove",Vector2i(40,33),""],
		["plant_tree",Vector2i(40,34),""],
	]
	var last_n:=0
	var tools_seen:Array=[]
	for step in steps:
		var alpha:Dictionary=me()
		alpha.x=World.SPAWN.x
		alpha.y=World.SPAWN.y
		if step[0]=="harvest":
			w.state.crops[World.key(plot)].growth=float(World.CROPS.radish.time)
			w.state.crops[World.key(plot)].wet=true
		elif step[0]=="pick":
			alpha.x=rock.x+0.5
			alpha.y=rock.y+1.5
		var count:=events_for("home").size()
		var inventory_before:Dictionary=alpha.inventory.duplicate(true)
		var ok:=send(1,step[0],step[1],step[2])
		expect(ok,"%s succeeds on the server"%step[0])
		var events:=events_for("home")
		expect(events.size()==count+1,"%s success adds exactly one public event"%step[0])
		if events.size()!=count+1:continue
		var event:Dictionary=events.back()
		var keys:Array=event.keys().map(func(key):return str(key))
		keys.sort()
		expect(keys==(MOVE_KEYS if step[0]=="move_object" else EVENT_KEYS),"%s event carries only %s (got %s)"%[step[0],"tool/actor/cell",keys])
		expect(event.tool==step[0] and event.actor==public_id(ALPHA) and event.x==step[1].x and event.y==step[1].y,"%s event names tool, public actor and target cell"%step[0])
		expect(int(event.n)>last_n,"%s event number increases"%step[0])
		last_n=int(event.n)
		tools_seen.append(event.tool)
		if step[0]=="move_object":expect(event.tx==40 and event.ty==33,"move_object event carries the destination cell")
		if step[0] in ["seed","plant_tree","build"]:expect(me().inventory!=inventory_before,"%s still consumed its normal cost"%step[0])
	var expected_tools:Array=Session.TOOL_ACTION_EVENTS.duplicate()
	expected_tools.sort()
	tools_seen.sort()
	expect(tools_seen==expected_tools,"every hand tool in T017 list produced its event: %s"%[tools_seen])
	me().x=World.SPAWN.x
	me().y=World.SPAWN.y

	# Rejections: notice is a failure and no event appears.
	me().inventory.sapling=0
	var rejects:=[["hoe",plot,""],["seed",Vector2i(41,34),"radish"],["water",Vector2i(41,34),""],["harvest",Vector2i(41,34),""],
		["axe",Vector2i(41,34),""],["pick",tree,""],["build",Vector2i(2,2),"wall"],["remove",Vector2i(41,34),""],
		["plant_tree",Vector2i(41,34),""],["move_object",Vector2i(41,34),"abc"]]
	for reject in rejects:
		var count:=events_for("home").size()
		var state_before:Dictionary=w.state.duplicate(true)
		expect(not send(1,reject[0],reject[1],reject[2]),"%s rejection reported as failure"%reject[0])
		expect(events_for("home").size()==count,"%s rejection adds no event"%reject[0])
		expect(w.state.players[ALPHA].inventory==state_before.players[ALPHA].inventory,"%s rejection leaves the bag unchanged"%reject[0])

	# Re-sent sequence (network retry) is dropped before World; no second event.
	var water_count:=events_for("home").size()
	expect(send(1,"water",plot),"fresh water request succeeds")
	expect(events_for("home").size()==water_count+1,"fresh water request animates once")
	session.rates[1]=[]
	session._action(1,int(seqs[1]),"water",plot,"")
	expect(events_for("home").size()==water_count+1,"re-sent sequence adds no event")

	# A stored receipt is a replay of an old answer: World says ok, nothing is animated.
	var replay_seq:=int(seqs[1])+1
	var replay_id:="%s-%d-%d"%[session.session_nonce,1,replay_seq]
	w.state.players[ALPHA].receipts[replay_id]={"ok":true,"message":"舊回覆"}
	seqs[1]=replay_seq
	session.rates[1]=[]
	var replay_count:=events_for("home").size()
	var before_notices:=notices.size()
	session._action(1,replay_seq,"water",plot,"")
	expect(notices.size()>before_notices and bool(notices.back()[1]),"receipt replay still answers ok")
	expect(events_for("home").size()==replay_count,"receipt replay adds no event")

	# Rate-limited request never reaches World and never animates.
	seqs[1]=int(seqs[1])+1
	var stamps:Array=[]
	for i in 12:stamps.append(Time.get_ticks_msec())
	session.rates[1]=stamps
	var limited_count:=events_for("home").size()
	session._action(1,int(seqs[1]),"water",plot,"")
	expect(not bool(notices.back()[1]),"rate-limited request reported as failure")
	expect(events_for("home").size()==limited_count,"rate-limited request adds no event")

	# Farm machine keeps its own feedback and is not duplicated as a hand-tool event.
	me().x=42.5
	me().y=36.5
	me().inventory.merge({"tiller":1,"charcoal":3},true)
	var machine_count:=events_for("home").size()
	expect(send(1,"till_area",Vector2i(42,36)),"till_area succeeds")
	expect(events_for("home").size()==machine_count,"farm machine success adds no hand-tool event")
	expect(not session.snapshot.get("players",{}).get(public_id(ALPHA),{}).get("last_till",{}).is_empty(),"farm machine keeps its existing last_till feedback")
	me().x=World.SPAWN.x
	me().y=World.SPAWN.y

	# Snapshot projection: own region only, minimal data, nothing private.
	expect(send(2,"water",plot),"beta request dispatched")
	var home_events:=events_for("home")
	expect(home_events.any(func(e):return e.actor==public_id(BETA) and e.tool=="water"),"beta's confirmed water is a home event")
	session._record_tool_action(GAMMA,"hoe",Vector2i(5,5),"")
	expect(not events_for("home").any(func(e):return e.actor==public_id(GAMMA)),"other-region action is not sent to home recipients")
	expect(events_for("jinguashi").size()==1 and events_for("jinguashi")[0].actor==public_id(GAMMA),"other-region recipients get only their region's event")
	session._send_snapshot(1)
	var own_snap:Dictionary=session.snapshot
	expect(own_snap.has("tool_actions") and own_snap.tool_actions.get("epoch")==session.tool_action_epoch,"own snapshot carries tool_actions with the server epoch")
	var text:=JSON.stringify(own_snap.get("tool_actions",{}))
	for secret in [ALPHA,BETA,GAMMA,session.session_nonce,"inventory","coins","message","receipts","radish"]:
		expect(not text.contains(secret),"tool_actions payload does not contain %s"%("a raw token" if secret in [ALPHA,BETA,GAMMA] else secret))
	expect(own_snap.tool_actions.events.all(func(e):return own_snap.players.has(e.actor)),"every event actor is an already-public player id")
	# Recipient copies cannot alter the server buffer.
	var original_tool:String=session.tool_actions[0].event.tool
	own_snap.tool_actions.events[0].tool="remove" if original_tool!="remove" else "hoe"
	expect(session.tool_actions[0].event.tool==original_tool,"recipient copy is detached from the server buffer")

	# TTL and cap.
	clock_ms+=Session.TOOL_ACTION_TTL_MS+1
	expect(events_for("home").is_empty() and events_for("jinguashi").is_empty(),"events expire after the TTL")
	for i in Session.TOOL_ACTION_MAX+8:session._record_tool_action(ALPHA,"water",plot,"")
	expect(session.tool_actions.size()==Session.TOOL_ACTION_MAX,"server buffer is capped")
	# Player leaves: their pending events are dropped.
	session._record_tool_action(BETA,"water",plot,"")
	session._peer_left(2)
	expect(not events_for("home").any(func(e):return e.actor==public_id(BETA)),"leaving player's events are dropped")
	# Save data is untouched: World state has no tool-action field.
	expect(not JSON.stringify(w.state).contains("tool_action"),"World/save state carries no tool-action data")
	session.world=null
	session.queue_free()
	await process_frame

## Always the live record: a rejected World.act may restore a state copy.
func me()->Dictionary:
	return w.state.players[ALPHA]

func find_rock()->Vector2i:
	for y in range(15,60):
		for x in range(20,80):
			var p:=Vector2i(x,y)
			if p==Vector2i(54,25) or p==World.COPPER_CELL:continue
			if World.base_resource(p)=="rock" and not w.water(p) and not w.protected(p) and w.is_land(p+Vector2i(0,1)):return p
	return Vector2i(-1,-1)

# ------------------------------------------------------- 2. observer --

func snap(region:String,epoch:String,events:Array,players:Array)->Dictionary:
	var people:={}
	for id in players:people[id]={"x":39.5,"y":33.5,"name":id}
	return {"region_id":region,"players":people,"crops":{"38,34":{"kind":"radish"}},"tool_actions":{"epoch":epoch,"events":events}}

func ev(n:int,actor:String,tool:String,x:int=38,y:int=34)->Dictionary:
	return {"n":n,"actor":actor,"tool":tool,"x":x,"y":y}

func client_observer()->void:
	var a:="a1b2c3d4e5f60718"
	var b:="0123456789abcdef"
	var fb:=Feedback.new()
	var first:=snap("home","E1",[ev(4,b,"hoe")],[a,b])
	expect(fb.observe({},first,a,0.0).is_empty(),"first snapshot is a baseline (event already in flight is not replayed)")
	expect(fb.active(b,0.0).is_empty(),"baseline leaves no animation")
	var second:=snap("home","E1",[ev(4,b,"hoe"),ev(5,b,"seed")],[a,b])
	expect(fb.observe(first,second,a,1.0)==[b],"a new event starts its actor's animation")
	expect(fb.active(b,1.0).get("tool")=="seed" and fb.active(b,1.0).get("item")=="radish_seed","seed animation uses the sown crop's seed icon")
	expect(fb.active(a,1.0).is_empty(),"another actor is not animated")
	expect(fb.observe(second,second.duplicate(true),a,1.1).is_empty() and fb.active(b,1.1).get("started")==1.0,"duplicate snapshot does not restart")
	expect(fb.active(b,1.0+Feedback.DURATION+0.01).is_empty(),"animation times out")
	var third:=snap("home","E1",[ev(6,a,"axe",39,35),ev(7,a,"pick",39,35)],[a,b])
	expect(fb.observe(second,third,a,2.0)==[a] and fb.active(a,2.0).tool=="pick","one animation per actor: the newest event wins")
	expect(fb.active(a,2.0).n==7,"newest event number kept")
	var harvest_prev:=snap("home","E1",[],[a,b])
	var harvest_next:=snap("home","E1",[ev(8,a,"harvest")],[a,b])
	harvest_next.crops={}
	fb.observe(harvest_prev,harvest_next,a,3.0)
	expect(fb.active(a,3.0).get("item")=="radish","harvest animation uses the crop from the previous snapshot")
	var moved:=snap("home","E1",[ev(9,a,"move_object",38,33)],[a,b])
	moved.tool_actions.events[0].merge({"tx":40,"ty":33})
	fb.observe(harvest_next,moved,a,4.0)
	expect(fb.active(a,4.0).get("to")==Vector2i(40,33),"move_object animation targets the destination")
	var junk:=snap("home","E1",[{"n":10,"actor":ALPHA,"tool":"hoe","x":1,"y":1},ev(11,a,"fish"),ev(12,a,"till_area"),{"n":"13","actor":a,"tool":"hoe","x":1,"y":1},ev(14,"ffffffffffffffff","hoe")],[a,b])
	expect(fb.observe(moved,junk,a,5.0).is_empty(),"malformed, non-hand-tool and absent-actor events are ignored")
	var b_acts:=snap("home","E1",[ev(16,b,"build",38,33)],[a,b])
	expect(fb.observe(junk,b_acts,a,6.0)==[b],"precondition: beta's build animates")
	var left:=snap("home","E1",[ev(16,b,"build",38,33)],[a])
	fb.observe(b_acts,left,a,6.1)
	expect(fb.active(b,6.1).is_empty(),"an actor who left stops animating at once")
	# Region change: baseline again (an old event in the new region is not replayed).
	fb.observe(left,snap("home","E1",[ev(20,b,"water")],[a,b]),a,7.0)
	expect(not fb.active(b,7.0).is_empty(),"precondition: home event animates")
	var other:=snap("jinguashi","E1",[ev(15,b,"pick")],[a,b])
	expect(fb.observe({},other,a,7.1).is_empty() and fb.active(b,7.1).is_empty(),"region change clears and baselines without replay")
	expect(fb.observe(other,snap("jinguashi","E1",[ev(15,b,"pick"),ev(21,b,"axe")],[a,b]),a,7.2)==[b],"new event in the new region plays")
	# Server restart (new epoch, counter restarts): baseline, no replay.
	expect(fb.observe({},snap("jinguashi","E2",[ev(1,b,"hoe")],[a,b]),a,8.0).is_empty(),"new server epoch is a baseline")
	expect(fb.observe({},snap("jinguashi","E2",[ev(1,b,"hoe"),ev(2,b,"water")],[a,b]),a,8.1)==[b],"after epoch baseline new events play")
	# Reconnect (main.gd resets the observer on disconnect): baseline, no replay.
	fb.reset()
	expect(fb.observe({},snap("jinguashi","E2",[ev(2,b,"water"),ev(3,b,"axe")],[a,b]),a,9.0).is_empty(),"after reset the first snapshot does not replay")
	# Own id change (another character in the same process): baseline.
	expect(fb.observe({},snap("jinguashi","E2",[ev(3,b,"axe"),ev(4,b,"hoe")],[a,b]),b,9.5).is_empty(),"own id change is a baseline")
	# Missing payload (older server) is harmless.
	var bare:=snap("jinguashi","E2",[],[a,b])
	bare.erase("tool_actions")
	expect(fb.observe({},bare,b,10.0).is_empty(),"snapshot without tool_actions is ignored")

# --------------------------------------------------------- 3. plans --

func interrupted_targets()->void:
	var fb:=Feedback.new()
	var actor:=public_id(ALPHA)
	var base:=snap("home","tail-epoch",[],[actor])
	fb.observe({},base,actor,0.0)
	var first:=snap("home","tail-epoch",[ev(1,actor,"hoe",38,34)],[actor])
	fb.observe(base,first,actor,1.0)
	var second:=snap("home","tail-epoch",[ev(1,actor,"hoe",38,34),ev(2,actor,"hoe",39,34)],[actor])
	fb.observe(first,second,actor,1.16)
	expect(fb.active(actor,1.28).n==2,"Rapid action immediately uses the newest held pose")
	var tails:=fb.target_tails(actor,1.28)
	expect(tails.size()==1 and tails[0].n==1 and tails[0].cell==Vector2i(38,34),"Interrupted confirmed impact retains its original tile and time")
	expect(not Feedback.plan("hoe",(1.28-float(tails[0].started))/Feedback.DURATION,false).particles.is_empty(),"First impact can appear while the second swing is winding up")
	fb.observe(second,second,actor,1.30)
	expect(fb.target_tails(actor,1.30).size()==1,"Repeated snapshots do not duplicate impact tails")
	expect(fb.target_tails(actor,1.56).is_empty() and not fb.active(actor,1.56).is_empty(),"Old target effect expires independently of the newer held pose")
	for n in range(3,45):
		fb.observe({},snap("home","tail-epoch",[ev(n,actor,"hoe")],[actor]),actor,1.16+n*0.001)
	expect(fb.tails.size()==Feedback.MAX_TAILS,"Interrupted effects have a strict memory bound")
	fb.observe({},snap("home","tail-epoch",[],[]),actor,1.3)
	expect(fb.target_tails(actor,1.3).is_empty(),"Leaving actors remove their pending target effects")
	fb.observe({},snap("home","tail-epoch",[ev(45,actor,"hoe")],[actor]),actor,2.0)
	fb.observe({},snap("home","tail-epoch",[ev(46,actor,"hoe")],[actor]),actor,2.1)
	expect(not fb.target_tails(actor,2.1).is_empty(),"Precondition: pending effect before changing regions")
	fb.observe({},snap("jinguashi","tail-epoch",[ev(46,actor,"hoe")],[actor]),actor,2.2)
	expect(fb.tails.is_empty(),"Region changes clear interrupted effects without replay")
	fb.reset()
	expect(fb.tails.is_empty(),"Disconnect reset clears interrupted effects")

func resource_reactions()->void:
	var fb:=Feedback.new()
	var actor:=public_id(ALPHA)
	var cell:=Vector2i(38,34)
	fb.observe({},snap("home","resource",[],[actor]),actor,0.0)
	fb.observe({},snap("home","resource",[ev(1,actor,"axe",38,34)],[actor]),actor,1.0)
	expect(fb.resource_pose(cell,"axe",1.1,false).angle==0.0,"Tree waits until confirmed swing contact")
	expect(absf(fb.resource_pose(cell,"axe",1.35,false).angle)>0.001,"Confirmed contact shakes the struck tree")
	expect(fb.resource_pose(cell+Vector2i.RIGHT,"axe",1.35,false).angle==0.0,"Neighbouring trees do not shake")
	expect(fb.resource_pose(cell,"axe",1.35,true).angle==0.0,"Reduced motion leaves trees still")
	fb.observe({},snap("home","resource",[ev(2,actor,"pick",39,34)],[actor]),actor,1.16)
	expect(absf(fb.resource_pose(cell,"axe",1.35,false).angle)>0.001,"Interrupted confirmed swing still reaches its original tree")
	var stone:=fb.resource_pose(cell+Vector2i.RIGHT,"pick",1.48,false)
	expect(stone.shift!=Vector2.ZERO and stone.angle==0.0,"Rock contact uses a small pixel jolt without rotation")
	expect(fb.resource_pose(cell+Vector2i.RIGHT,"pick",1.48,true).shift==Vector2.ZERO,"Reduced motion leaves rocks still")
	expect(fb.resource_pose(cell,"axe",1.56,false).angle==0.0,"Tree settles even without another snapshot")
	expect(fb.resource_pose(cell,"water",1.35,false).angle==0.0,"Non-gathering tools do not shake resources")
	fb.reset()
	expect(fb.resource_pose(cell,"axe",1.35,false).angle==0.0,"Reset cancels resource reaction")

func resource_finishes()->void:
	var fb:=Feedback.new()
	var actor:=public_id(ALPHA)
	var cell:=Vector2i(38,34)
	var key:=World.key(cell)
	var before:=snap("home","finish",[],[actor])
	before.forest={key:{"mature":true}}
	# A planted tree can stand on a formerly cleared natural-resource cell.
	before.removed={key:true}
	fb.observe({},before,actor,0.0)
	var partial:Dictionary=before.duplicate(true)
	partial.tool_actions.events=[ev(1,actor,"axe",cell.x,cell.y)]
	fb.observe(before,partial,actor,0.5)
	expect(fb.finishes.is_empty(),"Partial tree hit does not start felling")
	var after:Dictionary=partial.duplicate(true)
	after.forest={}
	after.tool_actions.events=[ev(2,actor,"axe",cell.x,cell.y)]
	fb.observe(partial,after,actor,1.0)
	var start:=fb.resource_finish(cell,1.0,false)
	expect(start.kind=="tree" and start.progress==0.0 and start.alpha==1.0,"Final planted-tree hit keeps original art until swing contact")
	expect(fb.resource_finish(cell,1.2,false).progress==0.0,"Felling waits for the tool contact")
	var middle:=fb.resource_finish(cell,1.5,false)
	expect(middle.progress>0.0 and middle.alpha<1.0 and middle.alpha>0.0,"Final-hit sprite moves and fades")
	expect(fb.resource_finish(cell,1.5,true).is_empty(),"Still mode suppresses final-hit art")
	fb.observe(after,after,actor,1.3)
	expect(float(fb.finishes[key].started)==1.0,"Repeated snapshot cannot restart felling")
	expect(fb.resource_finish(cell,1.76,false).is_empty(),"Final-hit sprite finishes without another snapshot")
	var newcomer:=Feedback.new()
	newcomer.observe({},after,actor,1.0)
	expect(newcomer.finishes.is_empty(),"Joining after removal does not replay old felling")
	fb.observe({},snap("home","restart",[],[actor]),actor,1.4)
	expect(fb.finishes.is_empty(),"Server epoch change clears final-hit art")
	var rock:=Vector2i(-1,-1)
	for y in range(20,40):
		for x in range(28,55):
			if World.base_resource(Vector2i(x,y))=="rock":rock=Vector2i(x,y);break
		if rock.x>=0:break
	expect(rock.x>=0,"Natural stone fixture exists")
	var stone_before:=snap("home","restart",[],[actor])
	var stone_after:=snap("home","restart",[ev(1,actor,"pick",rock.x,rock.y)],[actor])
	stone_after.removed={World.key(rock):true}
	fb.observe(stone_before,stone_after,actor,2.0)
	expect(fb.resource_finish(rock,2.0,false).get("kind")=="rock","Only an actual natural-rock removal starts breaking")
	fb.reset()
	expect(fb.finishes.is_empty(),"Disconnect clears final-hit art")

func watered_plant_response()->void:
	var fb:=Feedback.new()
	var actor:=public_id(ALPHA)
	var baseline:=snap("home","water-care",[],[actor])
	var watering:=snap("home","water-care",[ev(1,actor,"water")],[actor])
	fb.observe({},baseline,actor,0.0)
	fb.observe(baseline,watering,actor,1.0)
	var plot:=Vector2i(38,34)
	expect(fb.crop_press(plot,1.0,false)==0,"Plant waits until the water reaches it")
	expect(fb.crop_press(plot,1.0+Feedback.DURATION*0.6,false)==2,"Watered plant gives a two-pixel settling nod")
	expect(fb.crop_press(plot,1.0+Feedback.DURATION,false)==0,"Plant returns to its exact rest height")
	expect(fb.crop_press(plot,1.3,true)==0 and fb.crop_press(plot+Vector2i.RIGHT,1.3,false)==0,"Quiet mode and neighbouring crops stay still")
	fb.observe(watering,watering,actor,1.1)
	expect(fb.crop_press(plot,1.0+Feedback.DURATION,false)==0,"Repeated snapshot cannot restart the crop response")
	var next:=snap("home","water-care",[ev(1,actor,"water"),ev(2,actor,"seed",39,34)],[actor])
	fb.observe(watering,next,actor,1.1)
	expect(fb.crop_press(plot,1.3,false)>0,"Interrupted pour finishes its crop response")
	fb.reset()
	fb.observe({},watering,actor,2.0)
	expect(fb.crop_press(plot,2.3,false)==0,"Joining with an old watering event does not nod the plant")
	for facing in [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]:
		var pose:=Feedback.plan("water",0.4,false,facing)
		pose.facing=facing
		var foot:=Vector2(80,90)
		var shoulder:=(Vector2(facing)*float(pose.body_lean)).round()
		expect(Feedback.hand_grip(foot,pose)==(foot+pose.hand+pose.lunge).round()+Vector2(shoulder.x,absf(shoulder.y)),"Water trail follows the same hand as the PNG: "+str(facing))

func tool_plans()->void:
	var impact_colors:Dictionary={}
	for tool in ["hoe","seed","water"]:
		var first:=Feedback.soil_impact(tool,0.70,false)
		var later:=Feedback.soil_impact(tool,0.91,false)
		expect(Feedback.soil_impact(tool,0.35,false).is_empty(),"soil cue waits for contact: "+tool)
		expect(not first.is_empty() and not later.is_empty() and first.spread<later.spread and first.color.a>later.color.a,
			"soil cue travels outward and fades: "+tool)
		if not first.is_empty():impact_colors[first.color.to_html(false)]=true
		expect(Feedback.soil_impact(tool,0.75,true).is_empty() and Feedback.soil_impact(tool,1.0,false).is_empty(),
			"soil cue respects reduced motion and expires: "+tool)
	expect(impact_colors.size()==3 and Feedback.soil_impact("pick",0.75,false).is_empty(),
		"soil cues distinguish the three farm actions and leave mining alone")
	var grip:=Vector2(8,6)
	var cell:=Vector2(56,12)
	for tool in ["seed","water"]:
		var early:=Feedback.farm_trail(tool,0.06,grip,cell)
		var late:=Feedback.farm_trail(tool,0.16,grip,cell)
		expect(early.size()==1 and late.size()>1 and early[0].x<late[0].x,"%s travels from the hand toward the tile in a staggered arc"%tool)
		expect(Feedback.farm_trail(tool,0.7,grip,cell).is_empty(),"%s trail ends after arrival"%tool)
	for tool in Feedback.TOOLS:
		var particles:=0
		var motion:={}
		var lunges:=0
		var reduced_particles:=0
		var reduced_motion:={}
		var reduced_lunge:=0
		var body_poses:={}
		for facing in [Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP]:
			for step in 21:
				var t:=step/20.0
				var normal:=Feedback.plan(tool,t,false,facing)
				body_poses[normal.body_lean]=true
				particles+=normal.particles.size()
				motion["%s|%s|%s"%[snappedf(normal.angle,0.01),normal.lift,normal.lunge]]=true
				if normal.lunge!=Vector2.ZERO:lunges+=1
				var calm:=Feedback.plan(tool,t,true,facing)
				reduced_particles+=calm.particles.size()
				if calm.lunge!=Vector2.ZERO or calm.lift!=0.0 or calm.body_lean!=0.0:reduced_lunge+=1
				reduced_motion["%s|%s"%[facing,snappedf(calm.angle,0.01)]]=true
		expect(particles>0,"%s draws target particles with normal motion"%tool)
		expect(motion.size()>4,"%s pose changes over the action with normal motion"%tool)
		expect(reduced_particles==0,"%s reduced motion draws no particles"%tool)
		expect(reduced_lunge==0,"%s reduced motion has no lunge or lift"%tool)
		expect(reduced_motion.size()<=4,"%s reduced motion keeps one fixed pose per facing"%tool)
		if tool in ["hoe","axe","pick","plant_tree"]:expect(lunges>0,"%s body leans into the action with normal motion"%tool)
		expect(Feedback.held_icon(tool)!=null,"%s held icon comes from existing PNG art"%tool)
		if tool in ["hoe","axe","pick","seed","water","harvest"]:
			expect(body_poses.size()>=3,"%s has readable torso anticipation and recovery"%tool)
			expect(Feedback.plan(tool,0.0,false).body_lean==0 and Feedback.plan(tool,1.0,false).body_lean==0,"%s starts and ends at the standing pose"%tool)
	expect(Feedback.held_icon("seed","carrot_seed")!=null,"seed icon follows the sown crop")
	expect(Feedback.held_icon("fish")==null,"fishing keeps its own art (no hand-tool icon)")
	expect(Feedback.facing_toward(Vector2(39.5,33.5),Vector2i(41,33),Vector2i.DOWN)==Vector2i.RIGHT,"actor turns toward the target cell")
	expect(Feedback.facing_toward(Vector2(39.5,33.5),Vector2i(39,33),Vector2i.LEFT)==Vector2i.LEFT,"own cell keeps the previous facing")

# ------------------------------------------------------ 4. draw path --

func view_draw_path()->void:
	var host=Session.new()
	root.add_child(host)
	host.set_physics_process(false)
	host.world=World.new()
	host.world.add_player(ALPHA,"alpha")
	host.peers={1:ALPHA}
	host.sequences={1:0}
	host.rates={1:[]}
	var plot:=Vector2i(38,34)
	var seq:=0
	var original_ground:Dictionary=host.world.state.ground.duplicate(true)
	var original_position:=Vector2(host.world.state.players[ALPHA].x,host.world.state.players[ALPHA].y)
	host._send_snapshot(1)
	var view=View.new()
	root.add_child(view)
	view.update_snapshot(host.snapshot,host.own_id)
	var results:={}
	for step in [["hoe","",false],["seed","radish",false],["water","",false],["water","",true]]:
		var tool:String=step[0]
		var reduced:bool=step[2]
		view.reduced_motion=reduced
		view.tool_draw_stats={"held":0,"particles":0,"lunge":0,"angles":{}}
		host.rates[1]=[]
		seq+=1
		host._action(1,seq,tool,plot,step[1])
		view.update_snapshot(host.snapshot,host.own_id)
		var started:float=view.elapsed
		expect(view.tool_action_plan(host.own_id).get("tool")==tool,"view starts the confirmed %s action (reduced=%s)"%[tool,reduced])
		if not reduced:
			view.elapsed=started+Feedback.DURATION*0.4
			view.photograph_mode=true
			var still:Dictionary=view.tool_action_plan(host.own_id)
			expect(still.reduced and still.body_lean==0.0 and still.particles.is_empty(),"Photo mode freezes the complete farm pose: "+tool)
			view.photograph_mode=false
			view.elapsed=started
		var deadline:=Time.get_ticks_msec()+3000
		while view.elapsed-started<Feedback.DURATION+0.05 and Time.get_ticks_msec()<deadline:
			await process_frame
		if tool=="water":results[reduced]=view.tool_draw_stats.duplicate(true)
		expect(int(view.tool_draw_stats.held)>0,"view renders the confirmed "+tool)
		expect(view.tool_action_plan(host.own_id).is_empty(),"view animation ends after "+tool)
	var planted:Dictionary=host.world.state.crops.get(World.key(plot),{})
	expect(planted.get("kind")=="radish" and planted.get("wet")==true,"the same hoed tile contains a watered radish")
	var person:Dictionary=host.world.state.players[ALPHA]
	expect(Vector2(person.x,person.y)==original_position and host.world.state.ground==original_ground,
		"confirmed farm actions preserve the player and base ground coordinates")
	var normal:Dictionary=results[false]
	var calm:Dictionary=results[true]
	print("TOOL_ACTION_DRAW normal=%s reduced=%s"%[normal,calm])
	expect(int(normal.held)>0 and int(calm.held)>0,"held tool is drawn in both motion settings")
	expect(int(normal.particles)>0,"normal motion draws water particles")
	expect(int(calm.particles)==0,"reduced motion draws no particles")
	expect(normal.angles.size()>1,"normal motion swings the held tool")
	expect(calm.angles.size()==1,"reduced motion keeps the held tool still")
	expect(int(calm.lunge)==0,"reduced motion never offsets the body")
	# A rejected request must not start any animation in the view.
	host.rates[1]=[]
	seq+=1
	var events_before:int=host.tool_action_view("home").events.size()
	host._action(1,seq,"hoe",plot,"")
	view.update_snapshot(host.snapshot,host.own_id)
	expect(host.tool_action_view("home").events.size()==events_before and view.tool_action_plan(host.own_id).is_empty(),"rejected hoe does not animate in the view")
	view.queue_free()
	host.world=null
	host.queue_free()
	await process_frame
