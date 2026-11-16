extends SceneTree
## Session-side contract for stove cooking queues (protocol 38).
## Real Session + real World public_state/_send_snapshot. The queue records are
## seeded directly into World state in the backend contract shape
## cooking={active:{..},waiting:[..],ready:[..]} with raw owner tokens.
## No networking is exercised: remote peers are only entries in `peers`, and the
## action-route section calls the same local dispatch request_action delegates to.
const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const ALPHA:="raw-alpha-cook-token-0001"
const BETA:="raw-beta-cook-token-0002"
const GAMMA:="raw-gamma-offline-token-0003"
const HOME_STOVE:="47,33"
const LEGACY_STOVE:="49,33"
const EMPTY_STOVE:="51,33"
const WAITING_ONLY_STOVE:="53,33"
const ACTIVE_ONLY_STOVE:="47,35"
const LANYANG_STOVE:="20,20"
const CANCEL_ID:="0123456789abcdef0123456789abcdef"

## Fixture: inherits Session but replaces _ready so no user:// profile is read
## or written and no multiplayer signals are wired.
class FixtureSession extends "res://scripts/session.gd":
	func _ready() -> void:
		name="Session"
		session_nonce="fixture-nonce"

## Action-route observer ONLY (labelled stub-wrapper): records exactly what
## Session hands to World.act, then delegates to the real World.act.
class RecordingWorld extends "res://scripts/world.gd":
	var calls:Array=[]
	func act(token:String,request_id:String,action:String,p:Vector2i,extra:String="") -> Dictionary:
		calls.append({"token":token,"action":action,"p":p,"extra":extra})
		return super.act(token,request_id,action,p,extra)

var checks:=0
var failures:=0
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures+=1;push_error(label)

static func pub(token:String)->String:
	return token.sha256_text().left(16)

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

func record(id:String,kind:String,owner:String,times:Dictionary)->Dictionary:
	var recipe:Dictionary=World.RECIPES[kind]
	var out:={"id":id,"kind":kind,"owner":owner,"ingredients":recipe.ingredients.duplicate(true),"yield":int(recipe.yield),"recipe_version":1}
	out.merge(times)
	return out

func _initialize()->void:run.call_deferred()

func run()->void:
	check(Session.PROTOCOL==45,"Session.PROTOCOL is 39 for cooking queues")
	await snapshot_section()
	await action_route_section()
	print("COOKING_QUEUE_SESSION_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func snapshot_section()->void:
	var session:=FixtureSession.new();root.add_child(session);session.set_physics_process(false)
	check(session.profile.is_empty(),"Fixture _ready loaded no user profile")
	session.world=World.new();var world:World=session.world
	for actor in [ALPHA,BETA,GAMMA]:world.add_player(actor,actor.left(10))
	world.active_tokens.erase(GAMMA)   # GAMMA: saved resident, offline, not a peer
	session.peers={1:ALPHA,2:BETA}
	world.state.time=300.0
	var active:=record("a".repeat(32),"bread",ALPHA,{"queued":280.0,"started":290.0,"finish":305.0})
	var waiting:=[record("b".repeat(32),"soup",BETA,{"queued":292.0}),record("c".repeat(32),"bread",GAMMA,{"queued":295.0})]
	var ready_list:=[record("d".repeat(32),"soup",GAMMA,{"queued":240.0,"started":250.0,"finish":260.0,"completed":260.0}),
		record("e".repeat(32),"bread",BETA,{"queued":255.0,"started":262.0,"finish":277.0,"completed":277.0})]
	world.state.objects[HOME_STOVE]={"type":"stove","owner":ALPHA,"cooking":{"active":active,"waiting":waiting,"ready":ready_list}}
	world.state.objects[LEGACY_STOVE]={"type":"stove","owner":BETA,"job":{"kind":"soup","ready":310.0,"owner":GAMMA,"ingredients":{"radish":2},"yield":2,"recipe_version":1}}
	world.state.objects[EMPTY_STOVE]={"type":"stove","owner":BETA,"cooking":{"active":{},"waiting":[],"ready":[]}}
	world.state.objects[WAITING_ONLY_STOVE]={"type":"stove","owner":ALPHA,"cooking":{"active":{},"waiting":[record("f".repeat(32),"soup",GAMMA,{"queued":299.0})],"ready":[]}}
	world.state.objects[ACTIVE_ONLY_STOVE]={"type":"stove","owner":GAMMA,"cooking":{"active":record("1".repeat(32),"soup",BETA,{"queued":296.0,"started":296.0,"finish":306.0}),"waiting":[],"ready":[]}}
	world.state.regions.lanyang.objects[LANYANG_STOVE]={"type":"stove","owner":GAMMA,"cooking":{"active":{},"waiting":[],"ready":[record("2".repeat(32),"bread",GAMMA,{"queued":200.0,"started":201.0,"finish":216.0,"completed":216.0})]}}
	# Compare the stove layers only: _send_snapshot may lazily touch unrelated
	# per-player records, which is outside this contract.
	var before:=var_to_str([world.state.objects,world.state.regions.lanyang.objects])

	var first:Dictionary=session.public_state("home")
	var second:Dictionary=session.public_state("home")
	check(var_to_str(first)==var_to_str(second),"Repeated public_state is identical (no double hashing)")
	for view in [first,second]:
		var q:Dictionary=view.objects[HOME_STOVE].cooking
		check(q.active.owner==pub(ALPHA),"Active owner hashed to public actor id")
		check(q.waiting.map(func(e):return e.owner)==[pub(BETA),pub(GAMMA)],"Every waiting owner hashed, offline GAMMA included")
		check(q.ready.map(func(e):return e.owner)==[pub(GAMMA),pub(BETA)],"Every ready owner hashed, offline GAMMA included")
		check(q.waiting.size()==2 and q.ready.size()==2 and q.waiting[1].id=="c".repeat(32),"Queue records and ids preserved")
		check(view.objects[HOME_STOVE].job=={"kind":"soup","owner":pub(GAMMA),"ready":260.0,"ingredients":{"radish":2},"yield":2,"recipe_version":1},
			"Derived job = oldest ready record, exact fields: %s"%[view.objects[HOME_STOVE].get("job")])
		check(view.objects[ACTIVE_ONLY_STOVE].job=={"kind":"soup","owner":pub(BETA),"ready":306.0,"ingredients":{"radish":2},"yield":2,"recipe_version":1},
			"Derived job falls back to active record when nothing is ready")
		check(not view.objects[EMPTY_STOVE].has("job"),"No derived job for empty queue")
		check(not view.objects[WAITING_ONLY_STOVE].has("job"),"Waiting-only queue gets no derived job")
		check(view.objects[WAITING_ONLY_STOVE].cooking.waiting[0].owner==pub(GAMMA),"Waiting-only owner hashed")
		check(view.objects[LEGACY_STOVE].job.owner==pub(GAMMA) and not view.objects[LEGACY_STOVE].has("cooking"),"Legacy job owner still hashed once")
		check(view.objects[HOME_STOVE].owner==pub(ALPHA),"Stove owner hashed once")
		check(raw_hits(view).is_empty(),"Home public view has no raw tokens: %s"%[raw_hits(view)])

	for pass_index in 2:
		var lanyang:Dictionary=session.public_state("lanyang")
		var stove:Dictionary=lanyang.objects[LANYANG_STOVE]
		check(stove.cooking.ready[0].owner==pub(GAMMA) and stove.owner==pub(GAMMA),"Regional queue owner hashed once (pass %d)"%pass_index)
		check(stove.job=={"kind":"bread","owner":pub(GAMMA),"ready":216.0,"ingredients":{"wheat":2},"yield":1,"recipe_version":1},"Regional derived job exact")
		check(raw_hits(lanyang).is_empty(),"Regional view has no raw tokens")

	for pass_index in 2:
		session._send_snapshot(1)
		var snap:Dictionary=session.snapshot
		check(session.own_id==pub(ALPHA),"Own snapshot delivered to host peer")
		check(snap.objects[HOME_STOVE].cooking.active.owner==pub(ALPHA) and snap.objects[HOME_STOVE].job.owner==pub(GAMMA),"Own snapshot hashes once (pass %d)"%pass_index)
		check(snap.objects[LEGACY_STOVE].job.owner==pub(GAMMA),"Own snapshot legacy job redacted")
		check(raw_hits(snap).is_empty(),"Own snapshot has no raw tokens: %s"%[raw_hits(snap)])

	check(var_to_str([world.state.objects,world.state.regions.lanyang.objects])==before,"World stove state untouched by public_state/_send_snapshot")
	check(world.state.objects[HOME_STOVE].cooking.active.owner==ALPHA,"World keeps raw owner token")
	for k in [HOME_STOVE,EMPTY_STOVE,ACTIVE_ONLY_STOVE]:
		check(not world.state.objects[k].has("job"),"Derived job never written into World state (%s)"%k)
	check(not world.state.regions.lanyang.objects[LANYANG_STOVE].has("job"),"Derived job never written into regional World state")
	session.world=null;session.queue_free();await process_frame

func action_route_section()->void:
	# Uses RecordingWorld (labelled observer around the real World.act) to prove
	# Session forwards queue operations unchanged; outcome is World's business.
	var session:=FixtureSession.new();root.add_child(session);session.set_physics_process(false)
	var world:=RecordingWorld.new();session.world=world
	world.add_player(ALPHA,"甲");world.add_player(BETA,"乙")
	session.peers={1:ALPHA,2:BETA};session.sequences={1:0,2:0};session.rates={1:[],2:[]}
	var cell:=Vector2i(47,33)
	var requests:=[["queue_cook","soup"],["cancel_queued_cook",CANCEL_ID],["claim_cook",""],["cancel_cook",""]]
	for r in requests:session.perform(r[0],cell,r[1])
	check(world.calls.size()==4,"Host perform routes every queue operation to World.act: %d"%world.calls.size())
	for i in mini(world.calls.size(),requests.size()):
		var call:Dictionary=world.calls[i]
		check(call.token==ALPHA and call.action==requests[i][0] and call.extra==requests[i][1] and call.p==cell,"Host %s forwarded unmodified"%requests[i][0])
	# Server dispatch used by request_action for a remote peer (called directly; no transport).
	session._action(2,1,"queue_cook",cell,"bread")
	session._action(2,2,"cancel_queued_cook",cell,CANCEL_ID)
	check(world.calls.size()==6 and world.calls[4]=={"token":BETA,"action":"queue_cook","p":cell,"extra":"bread"}
		and world.calls[5]=={"token":BETA,"action":"cancel_queued_cook","p":cell,"extra":CANCEL_ID},"Peer dispatch forwards queue ops with 32-hex id intact")
	session.world=null;session.queue_free();await process_frame
