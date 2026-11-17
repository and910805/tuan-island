extends SceneTree
## Session-side contract for sawmill/charcoal kiln processing queues (protocol 39).
## Real Session public_state/_send_snapshot over a real World. FIXTURES: queue
## state is produced by the real CookingQueue helper against
## SaveSchema.processing_recipes(station) and seeded directly into World state
## with raw owner tokens. One station (MIXED_SAW) is a LABELLED defensive
## fixture that SaveSchema would reject (record owners differ from the station
## owner); it only proves every nested owner is redacted no matter what.
## No networking is exercised: remote peers are only entries in `peers`, and the
## routing section calls the same local dispatch request_action delegates to.
## Run: godot --headless --path game --script res://tests/test_processing_queue_session.gd
const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const Schema=preload("res://scripts/save_schema.gd")
const Queue=preload("res://scripts/cooking_queue.gd")
const ALPHA:="raw-alpha-process-token-0001"
const BETA:="raw-beta-process-token-0002"
const GAMMA:="raw-gamma-offline-process-0003"
const HOME_SAW:="47,33"
const LEGACY_KILN:="49,33"
const EMPTY_SAW:="51,33"
const MIXED_SAW:="53,33"
const ACTIVE_KILN:="47,35"
const COOK_STOVE:="55,33"
const LANYANG_KILN:="20,20"
const CANCEL_ID:="0123456789abcdef0123456789abcdef"
const OLD_CORRELATED:=["ship","undo_build","cook","queue_cook","claim_cook","cancel_cook","cancel_queued_cook"]
const PROCESSING_ACTIONS:=["start_processing","queue_processing","claim_processing","cancel_processing","cancel_processing_job","feed_processing","unload_processing_input","toggle_auto_processing","collect_processing_output"]

## FIXTURE: inherits Session but replaces _ready so no user:// profile is read
## or written and no multiplayer signals are wired.
class FixtureSession extends "res://scripts/session.gd":
	func _ready() -> void:
		name="Session"
		session_nonce="processing-fixture-nonce"

## LABELLED STUB-WRAPPER (observer only): records what Session hands to
## World.act and the exact result, then delegates to the real World.act.
## save() is in-memory so no file is written.
class RecordingWorld extends "res://scripts/world.gd":
	var calls:Array=[]
	var results:Array=[]
	func act(token:String,request_id:String,action:String,p:Vector2i,extra:String="") -> Dictionary:
		calls.append({"token":token,"action":action,"p":p,"extra":extra})
		var result:Dictionary=super.act(token,request_id,action,p,extra)
		results.append(result.duplicate(true))
		return result
	func save() -> bool:
		return true

var checks:=0
var failures:=0
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures+=1;push_error(label)

static func pub(token:String)->String:
	return token.sha256_text().left(16)

static func hid(n:int)->String:
	return "%032x"%n

## Recursively collects any key or value containing a raw token.
func raw_hits(data:Variant,path:String="")->Array:
	var hits:=[]
	if data is Dictionary:
		for k in data:
			for token in [ALPHA,BETA,GAMMA]:
				if String(k).contains(token):hits.append(path+"/<key>")
			hits.append_array(raw_hits(data[k],path+"/"+String(k)))
	elif data is Array:
		for i in data.size():hits.append_array(raw_hits(data[i],path+"[%d]"%i))
	elif data is String or data is StringName:
		for token in [ALPHA,BETA,GAMMA]:
			if String(data).contains(token):hits.append(path)
	return hits

## Real helper queue: enqueue each [at, owner, id] in order, advancing to `at` first.
func build_queue(station:String,kind:String,jobs:Array,now:float)->Dictionary:
	var catalog:=Schema.processing_recipes(station)
	var q:Dictionary=Queue.empty_state()
	var bag:Dictionary={"wood":100}
	for job in jobs:
		var adv:=Queue.advance(q,catalog,float(job[0]))
		check(adv.ok,"fixture advance to %s"%job[0]);q=adv.state
		var r:=Queue.enqueue(q,catalog,float(job[0]),job[1],kind,job[2],bag)
		check(r.ok,"fixture enqueue %s at %s: %s"%[kind,job[0],r.get("message","")])
		if r.ok:q=r.state;bag=r.inventory
	var done:=Queue.advance(q,catalog,now)
	check(done.ok and Queue.validate(done.state,catalog,now),"fixture queue valid at %s"%now)
	return done.state

func _initialize()->void:run.call_deferred()

func run()->void:
	check(Session.PROTOCOL>=39,"Session supports the processing-queue protocol introduced in 39")
	var release:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://release.json"))
	check(Session.PROTOCOL==int(release.protocol),"Session protocol matches current release manifest")
	for action in OLD_CORRELATED+PROCESSING_ACTIONS:
		check(Session.CORRELATED_ACTIONS.has(action),"%s is on the correlated action_completed path"%action)
	await snapshot_section()
	await action_route_section()
	print("PROCESSING_QUEUE_SESSION_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func snapshot_section()->void:
	var session:=FixtureSession.new();root.add_child(session);session.set_physics_process(false)
	check(session.profile.is_empty(),"Fixture _ready loaded no user profile")
	session.world=World.new();var world:World=session.world
	for actor in [ALPHA,BETA,GAMMA]:world.add_player(actor,actor.left(10))
	world.active_tokens.erase(GAMMA)   # GAMMA: saved resident, offline, not a peer
	session.peers={1:ALPHA,2:BETA}
	world.state.time=300.0
	# Sawmill plank: 12s. Jobs at 270 finish 282/294/306; one more waits.
	var home_q:=build_queue("sawmill","plank",[[270.0,ALPHA,hid(1)],[270.0,ALPHA,hid(2)],[270.0,ALPHA,hid(3)],[300.0,ALPHA,hid(4)]],300.0)
	check(home_q.ready.size()==2 and not home_q.active.is_empty() and home_q.waiting.size()==1,"home fixture: 2 ready, active, 1 waiting")
	var active_q:=build_queue("charcoal_kiln","charcoal",[[290.0,GAMMA,hid(10)]],300.0)
	# LABELLED DEFENSIVE FIXTURE (schema-invalid owners): BETA active, GAMMA waiting/ready.
	var mixed_q:=build_queue("sawmill","plank",[[280.0,GAMMA,hid(20)],[280.0,BETA,hid(21)],[300.0,GAMMA,hid(22)]],300.0)
	var lan_q:=build_queue("charcoal_kiln","charcoal",[[200.0,GAMMA,hid(30)]],300.0)
	var cook_q:Dictionary=Queue.enqueue(Queue.empty_state(),World.RECIPES,0.0,ALPHA,"soup",hid(40),{"radish":10}).state
	cook_q=Queue.advance(cook_q,World.RECIPES,300.0).state
	world.state.objects[HOME_SAW]={"type":"sawmill","owner":ALPHA,"items":{"plank":2},"input_wood":3,"auto_enabled":false,"processing":home_q}
	world.state.objects[LEGACY_KILN]={"type":"charcoal_kiln","owner":BETA,"items":{},"input_wood":4,"auto_enabled":true,
		"job":{"kind":"charcoal","owner":BETA,"ready":310.0,"ingredients":{"wood":4},"yield":2,"auto":true}}
	world.state.objects[EMPTY_SAW]={"type":"sawmill","owner":BETA,"items":{},"input_wood":0,"auto_enabled":false,"processing":Queue.empty_state()}
	world.state.objects[MIXED_SAW]={"type":"sawmill","owner":ALPHA,"items":{},"input_wood":0,"auto_enabled":false,"processing":mixed_q}
	world.state.objects[ACTIVE_KILN]={"type":"charcoal_kiln","owner":GAMMA,"items":{},"input_wood":0,"auto_enabled":false,"processing":active_q}
	world.state.objects[COOK_STOVE]={"type":"stove","owner":ALPHA,"items":{},"cooking":cook_q}
	world.state.regions.lanyang.objects[LANYANG_KILN]={"type":"charcoal_kiln","owner":GAMMA,"items":{},"input_wood":0,"auto_enabled":false,"processing":lan_q}
	var before:=var_to_str([world.state.objects,world.state.regions.lanyang.objects])

	var first:Dictionary=session.public_state("home")
	var second:Dictionary=session.public_state("home")
	check(var_to_str(first)==var_to_str(second),"Repeated public_state is identical (no double hashing)")
	for view in [first,second]:
		var saw:Dictionary=view.objects[HOME_SAW]
		var q:Dictionary=saw.processing
		check(q.active.owner==pub(ALPHA),"Active processing owner hashed once")
		check(q.waiting.map(func(e):return e.owner)==[pub(ALPHA)],"Waiting processing owner hashed once")
		check(q.ready.map(func(e):return e.owner)==[pub(ALPHA),pub(ALPHA)],"Ready processing owners hashed once")
		check(q.ready.map(func(e):return e.id)==[hid(1),hid(2)] and q.active.id==hid(3) and q.waiting[0].id==hid(4),"Processing records and ids preserved")
		check(saw.owner==pub(ALPHA) and int(saw.input_wood)==3 and saw.items=={"plank":2} and saw.auto_enabled==false,"Station owner hashed; automatic buffer shown unchanged")
		check(saw.job=={"kind":"plank","owner":pub(ALPHA),"ready":282.0,"ingredients":{"wood":4},"yield":2},
			"Projection = oldest ready, legacy processing shape: %s"%[saw.get("job")])
		check(view.objects[ACTIVE_KILN].job=={"kind":"charcoal","owner":pub(GAMMA),"ready":306.0,"ingredients":{"wood":4},"yield":2},
			"Projection falls back to active record: %s"%[view.objects[ACTIVE_KILN].get("job")])
		for k in [HOME_SAW,ACTIVE_KILN,MIXED_SAW]:
			var job:Dictionary=view.objects[k].get("job",{})
			check(not job.has("auto") and not job.has("recipe_version") and not job.has("id"),"Projection on %s has no auto/recipe_version/id"%k)
		check(not view.objects[EMPTY_SAW].has("job"),"No projection for empty processing queue")
		var mixed:Dictionary=view.objects[MIXED_SAW].processing
		check(mixed.ready.map(func(e):return e.owner)==[pub(GAMMA)] and mixed.active.owner==pub(BETA) and mixed.waiting.map(func(e):return e.owner)==[pub(GAMMA)],
			"Defensive fixture: every nested owner hashed, offline GAMMA included")
		check(view.objects[MIXED_SAW].job.owner==pub(GAMMA) and view.objects[MIXED_SAW].owner==pub(ALPHA),"Defensive projection owner already public, station owner hashed once")
		var legacy:Dictionary=view.objects[LEGACY_KILN]
		check(legacy.job=={"kind":"charcoal","owner":pub(BETA),"ready":310.0,"ingredients":{"wood":4},"yield":2,"auto":true} and not legacy.has("processing"),
			"Legacy automatic job redacted once and otherwise unchanged")
		var cook_ready:Dictionary=cook_q.ready[0]
		check(view.objects[COOK_STOVE].job=={"kind":"soup","owner":pub(ALPHA),"ready":float(cook_ready.completed),"ingredients":cook_ready.ingredients,"yield":int(cook_ready["yield"]),"recipe_version":1},
			"Cooking projection unchanged by generalisation (keeps recipe_version)")
		check(view.objects[COOK_STOVE].cooking.ready[0].owner==pub(ALPHA),"Cooking owner still hashed once")
		check(raw_hits(view).is_empty(),"Home public view has no raw tokens: %s"%[raw_hits(view)])

	for pass_index in 2:
		var lanyang:Dictionary=session.public_state("lanyang")
		var kiln:Dictionary=lanyang.objects[LANYANG_KILN]
		check(kiln.processing.ready[0].owner==pub(GAMMA) and kiln.owner==pub(GAMMA),"Regional processing owner hashed once (pass %d)"%pass_index)
		check(kiln.job=={"kind":"charcoal","owner":pub(GAMMA),"ready":216.0,"ingredients":{"wood":4},"yield":2},"Regional projection exact: %s"%[kiln.get("job")])
		check(raw_hits(lanyang).is_empty(),"Regional view has no raw tokens")

	for pass_index in 2:
		session._send_snapshot(1)
		var snap:Dictionary=session.snapshot
		check(session.own_id==pub(ALPHA),"Own snapshot delivered to host peer")
		check(snap.objects[HOME_SAW].processing.active.owner==pub(ALPHA) and snap.objects[HOME_SAW].job.owner==pub(ALPHA),"Own snapshot hashes once (pass %d)"%pass_index)
		check(snap.objects[MIXED_SAW].processing.active.owner==pub(BETA),"Own snapshot nested owner hashed once")
		check(raw_hits(snap).is_empty(),"Own snapshot has no raw tokens: %s"%[raw_hits(snap)])

	check(var_to_str([world.state.objects,world.state.regions.lanyang.objects])==before,"World station state untouched by public_state/_send_snapshot")
	check(world.state.objects[HOME_SAW].processing.active.owner==ALPHA,"World keeps raw owner token")
	for k in [HOME_SAW,EMPTY_SAW,MIXED_SAW,ACTIVE_KILN,COOK_STOVE]:
		check(not world.state.objects[k].has("job"),"Projection never written into World state (%s)"%k)
	check(not world.state.regions.lanyang.objects[LANYANG_KILN].has("job"),"Projection never written into regional World state")
	session.world=null;session.queue_free();await process_frame

func action_route_section()->void:
	# Uses RecordingWorld (labelled observer around the real World.act). Session
	# must forward every processing operation unchanged and return World's exact
	# result with the request's own sequence; the outcome itself is World's business.
	var session:=FixtureSession.new();root.add_child(session);session.set_physics_process(false)
	var world:=RecordingWorld.new();session.world=world
	world.add_player(ALPHA,"甲");world.add_player(BETA,"乙")
	world.state.players[ALPHA].inventory.wood=40
	session.peers={1:ALPHA,2:BETA};session.sequences={1:0,2:0};session.rates={1:[],2:[]}
	var cell:=Vector2i(47,33)
	world.state.objects[World.key(cell)]={"type":"sawmill","owner":ALPHA,"items":{},"input_wood":0,"auto_enabled":false}
	var replies:Array=[]
	session.action_completed.connect(func(sequence:int,action:String,result:Dictionary):replies.append([sequence,action,result.duplicate(true)]))
	var requests:=[["start_processing","plank"],["queue_processing","plank"],["claim_processing",""],["cancel_processing",""],["cancel_processing_job",CANCEL_ID],["feed_processing",""],["unload_processing_input",""],["toggle_auto_processing",""],["collect_processing_output",""]]
	for r in requests:
		var calls_before:int=world.calls.size()
		var replies_before:int=replies.size()
		var seq:int=session.perform(r[0],cell,r[1])
		check(world.calls.size()==calls_before+1,"Host %s routed to World.act once"%r[0])
		if world.calls.size()==calls_before+1:
			var call:Dictionary=world.calls[-1]
			check(call.token==ALPHA and call.action==r[0] and call.extra==r[1] and call.p==cell,"Host %s forwarded unmodified"%r[0])
		check(replies.size()==replies_before+1,"Host %s gets exactly one action_completed"%r[0])
		if replies.size()==replies_before+1:
			check(replies[-1][0]==seq and replies[-1][1]==r[0],"Host %s reply carries its exact sequence %d"%[r[0],seq])
			check(replies[-1][2]==world.results[-1],"Host %s reply is World's exact result"%r[0])
	# Control: a non-correlated logistics action still gets no action_completed.
	var quiet:=replies.size()
	session.perform("toggle_conveyor",cell)
	check(replies.size()==quiet,"Non-correlated action is not acknowledged via action_completed")
	# Server dispatch used by request_action for a remote peer (no transport):
	# forwarded to World with the peer's token; the reply targets that peer, so
	# nothing is emitted on the host.
	var host_replies:=replies.size()
	session._action(2,1,"queue_processing",cell,"charcoal")
	session._action(2,2,"cancel_processing_job",cell,CANCEL_ID)
	check(world.calls.size()>=2 and world.calls[-2]=={"token":BETA,"action":"queue_processing","p":cell,"extra":"charcoal"}
		and world.calls[-1]=={"token":BETA,"action":"cancel_processing_job","p":cell,"extra":CANCEL_ID},"Peer dispatch forwards processing ops with 32-hex id intact")
	check(replies.size()==host_replies,"Remote peer replies are not emitted on the host")
	var calls_now:=world.calls.size()
	session._action(2,3,"cancel_processing_job",cell,CANCEL_ID+"0")
	check(world.calls.size()==calls_now,"Over-long job id dropped before World (existing extra bound)")
	# Rate-limited processing request still gets a correlated failure and never reaches World.
	var stamps:Array=[]
	for i in 12:stamps.append(Time.get_ticks_msec())
	session.rates[1]=stamps
	var limited_calls:=world.calls.size()
	var limited_seq:int=session.perform("queue_processing",cell,"plank")
	check(replies.size()==host_replies+1 and replies[-1][0]==limited_seq and replies[-1][1]=="queue_processing" and not replies[-1][2].ok,"Rate limit returns correlated failure")
	check(world.calls.size()==limited_calls,"Rate-limited request never reaches World")
	session.world=null;session.queue_free();await process_frame
