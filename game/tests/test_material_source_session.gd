extends SceneTree
## Session-side contract for explicit chest + backpack material sourcing
## (protocol 40, docs/material-source-contract.json "wire"/"session").
## Covers: protocol/correlated constants against the contract file, the
## transport extra bound (sourced <=96 ASCII bytes only for the five source
## actions, old bounds everywhere else), exact-sequence routing to World.act and
## per-recipient stripping of other players' private-chest box_id.
## FIXTURES / STUBS (labelled):
## - FixtureSession: inherits Session, replaces _ready so no user:// profile is
##   read/written and no multiplayer signals are wired.
## - RecordingWorld: LABELLED STUB-WRAPPER (observer only) around the real
##   World.act; save() is in-memory. World's own sourcing semantics are NOT
##   tested here (World may well reject these requests); only that Session
##   forwards them byte-exact and correlates World's exact result.
## - NO NETWORK: remote peers are only entries in `peers`; the "peer" paths call
##   the same local _action dispatch request_action delegates to. Snapshots for
##   a recipient are observed by making that recipient the host peer (id 1).
## Run: godot --headless --path game --script res://tests/test_material_source_session.gd
const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const CONTRACT_PATH:="res://docs/material-source-contract.json"
const ALPHA:="raw-alpha-source-token-0001"
const BETA:="raw-beta-source-token-0002"
const GAMMA:="raw-gamma-offline-source-0003"
const STATION:=Vector2i(47,33)
const BOX_CELL:="48,33"
const SHARED_ID:="11111111111111111111111111111111"
const ALPHA_PRIVATE_ID:="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
const BETA_PRIVATE_ID:="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
const GAMMA_PRIVATE_ID:="cccccccccccccccccccccccccccccccc"
const GAMMA_REGION_ID:="dddddddddddddddddddddddddddddddd"
const DIGEST:="0123456789abcdef"
const OLD_CORRELATED:=["ship","undo_build","cook","queue_cook","claim_cook","cancel_cook","cancel_queued_cook",
	"start_processing","queue_processing","claim_processing","cancel_processing","cancel_processing_job",
	"feed_processing","unload_processing_input","toggle_auto_processing","collect_processing_output"]
const SOURCE_ACTIONS:=["craft","cook","queue_cook","start_processing","queue_processing"]

class FixtureSession extends "res://scripts/session.gd":
	func _ready() -> void:
		name="Session"
		session_nonce="material-source-fixture-nonce"

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

static func sourced(recipe:String,cell:String,id:String,digest:String)->String:
	return "%s|%s|%s|%s"%[recipe,cell,id,digest]

func longest()->String:
	return sourced("r".repeat(32),"-12345,-12345",ALPHA_PRIVATE_ID,DIGEST)

func bad_sourced()->Dictionary:
	return {
		"97_bytes":sourced("r".repeat(32),"-123456,-12345",ALPHA_PRIVATE_ID,DIGEST),
		"97_bytes_padding":sourced("plank",BOX_CELL,SHARED_ID,DIGEST)+"x".repeat(97-sourced("plank",BOX_CELL,SHARED_ID,DIGEST).length()),
		"non_ascii_recipe":sourced("湯品",BOX_CELL,SHARED_ID,DIGEST),
		"non_ascii_digest":sourced("soup",BOX_CELL,SHARED_ID,"0123456789abcdeｆ"),
		"three_parts":"soup|%s|%s"%[BOX_CELL,DIGEST],
		"five_parts":sourced("soup",BOX_CELL,SHARED_ID,DIGEST)+"|x",
		"empty_recipe":sourced("",BOX_CELL,SHARED_ID,DIGEST),
		"recipe_space":sourced("so up",BOX_CELL,SHARED_ID,DIGEST),
		"recipe_33":sourced("r".repeat(33),BOX_CELL,SHARED_ID,DIGEST),
		"id_upper":sourced("soup",BOX_CELL,SHARED_ID.replace("1","A"),DIGEST),
		"id_31":sourced("soup",BOX_CELL,SHARED_ID.left(31),DIGEST),
		"id_33":sourced("soup",BOX_CELL,SHARED_ID+"1",DIGEST),
		"id_nonhex":sourced("soup",BOX_CELL,"g"+SHARED_ID.left(31),DIGEST),
		"digest_15":sourced("soup",BOX_CELL,SHARED_ID,DIGEST.left(15)),
		"digest_17":sourced("soup",BOX_CELL,SHARED_ID,DIGEST+"0"),
		"digest_upper":sourced("soup",BOX_CELL,SHARED_ID,DIGEST.to_upper()),
		"digest_empty":sourced("soup",BOX_CELL,SHARED_ID,""),
		"cell_space":sourced("soup","48, 33",SHARED_ID,DIGEST),
		"cell_leading_zero":sourced("soup","048,33",SHARED_ID,DIGEST),
		"cell_plus":sourced("soup","+48,33",SHARED_ID,DIGEST),
		"cell_semicolon":sourced("soup","48;33",SHARED_ID,DIGEST),
		"cell_three":sourced("soup","48,33,1",SHARED_ID,DIGEST),
		"cell_empty":sourced("soup","",SHARED_ID,DIGEST),
	}

func _initialize()->void:run.call_deferred()

func run()->void:
	constants_section()
	bounds_section()
	await routing_section()
	await privacy_section()
	print("MATERIAL_SOURCE_SESSION_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func constants_section()->void:
	check(Session.PROTOCOL==45,"Session.PROTOCOL is 40 for material sourcing")
	var contract=JSON.parse_string(FileAccess.get_file_as_string(CONTRACT_PATH))
	check(contract is Dictionary,"contract file parses")
	if contract is Dictionary:
		check(int(contract.get("protocol",0))==Session.PROTOCOL,"protocol matches contract")
		check(contract.get("source_actions")==Session.SOURCE_ACTIONS,"Session.SOURCE_ACTIONS equals contract source_actions")
	check(Session.SOURCE_ACTIONS==SOURCE_ACTIONS,"source actions are exactly the five contract actions")
	for action in OLD_CORRELATED:check(Session.CORRELATED_ACTIONS.has(action),"%s stays correlated"%action)
	for action in ["craft","prepare_material_box"]:check(Session.CORRELATED_ACTIONS.has(action),"%s added to correlated actions"%action)
	for action in SOURCE_ACTIONS:check(Session.CORRELATED_ACTIONS.has(action),"sourced %s is correlated"%action)
	for action in ["kitchen_register","kitchen_contribute"]:check(Session.CORRELATED_ACTIONS.has(action),"public kitchen followup is correlated: "+action)
	var expected_correlated:Array=OLD_CORRELATED+["craft","prepare_material_box","kitchen_register","kitchen_contribute","flower_ship","flower_give","salt_gate_give","salt_rake","salt_install","salt_uninstall","salt_auto_cfg","salt_order","salt_box_take"]
	check(Session.CORRELATED_ACTIONS.size()==expected_correlated.size() and expected_correlated.all(func(action):return Session.CORRELATED_ACTIONS.has(action)),"exact correlated set preserves older actions and adds both flower actions")
	check(Session.PLAIN_EXTRA_MAX==32 and Session.SOURCED_EXTRA_MAX==96,"plain 32 / sourced 96 bounds")

func bounds_section()->void:
	var top:=longest()
	check(top.length()==96 and top.to_utf8_buffer().size()==96,"fixture: longest grammatical sourced extra is exactly 96 bytes")
	var bads:=bad_sourced()
	check(bads["97_bytes"].length()==97 and bads["97_bytes_padding"].length()==97,"fixture: 97-byte cases are 97 long")
	for action in SOURCE_ACTIONS:
		check(Session.extra_allowed(action,"plank"),"%s plain recipe allowed"%action)
		check(Session.extra_allowed(action,"x".repeat(32)),"%s plain 32 allowed"%action)
		check(not Session.extra_allowed(action,"x".repeat(33)),"%s plain 33 still rejected"%action)
		check(Session.extra_allowed(action,sourced("soup",BOX_CELL,SHARED_ID,DIGEST)),"%s sourced extra allowed"%action)
		check(Session.extra_allowed(action,top),"%s 96-byte sourced extra allowed"%action)
		check(not Session.extra_allowed(action,sourced("soup",BOX_CELL,"",DIGEST)),"%s sourced request requires an explicitly prepared box id"%action)
		check(Session.extra_allowed(action,sourced("soup","-1,0",SHARED_ID,DIGEST)),"%s sourced negative canonical cell allowed"%action)
		for name in bads:check(not Session.extra_allowed(action,bads[name]),"%s %s rejected"%[action,name])
	var normal:=sourced("soup",BOX_CELL,SHARED_ID,DIGEST)
	for action in ["claim_cook","cancel_cook","cancel_queued_cook","claim_processing","cancel_processing_job","feed_processing","build","move","undo_build","toggle_conveyor","collect_processing_output"]:
		check(not Session.extra_allowed(action,normal),"%s (not a source action) keeps the 32 bound for sourced payload"%action)
		check(Session.extra_allowed(action,"x".repeat(32)) and not Session.extra_allowed(action,"x".repeat(33)),"%s plain 32/33 bound unchanged"%action)
	for ok_cell in [BOX_CELL,"-1,0","0,0","123456,-123456"]:
		check(Session.extra_allowed("prepare_material_box",ok_cell),"prepare_material_box cell %s allowed"%ok_cell)
	for bad_cell in ["",BOX_CELL+"|"+SHARED_ID,"48, 33","048,33","+48,33","48","a,b","1234567,1","1".repeat(33),normal]:
		check(not Session.extra_allowed("prepare_material_box",bad_cell),"prepare_material_box extra %s rejected"%bad_cell.left(20))
	var ship_max:int=World.SHIPPING.MAX_BYTES
	check(Session.extra_allowed("ship","a".repeat(ship_max)) and not Session.extra_allowed("ship","a".repeat(ship_max+1)),"ship byte bound unchanged")
	var freight_max:int=World.MINE_AUTO_FREIGHT.MAX_BYTES
	check(Session.extra_allowed("mine_auto_config","a".repeat(freight_max)) and not Session.extra_allowed("mine_auto_config","a".repeat(freight_max+1)),"mine_auto_config byte bound unchanged")

func routing_section()->void:
	var session:=FixtureSession.new();root.add_child(session);session.set_physics_process(false)
	var world:=RecordingWorld.new();session.world=world
	world.add_player(ALPHA,"甲");world.add_player(BETA,"乙")
	session.peers={1:ALPHA,2:BETA};session.sequences={1:0,2:0};session.rates={1:[],2:[]}
	world.state.objects[World.key(STATION)]={"type":"sawmill","owner":ALPHA,"items":{},"input_wood":0,"auto_enabled":false}
	world.state.objects[BOX_CELL]={"type":"chest","owner":ALPHA,"items":{"wood":5}}
	var replies:Array=[]
	session.action_completed.connect(func(sequence:int,action:String,result:Dictionary):replies.append([sequence,action,result.duplicate(true)]))
	var requests:=[["prepare_material_box",BOX_CELL],["craft","plank"],["craft",sourced("plank",BOX_CELL,SHARED_ID,DIGEST)],
		["cook",sourced("soup",BOX_CELL,SHARED_ID,DIGEST)],["queue_cook",sourced("soup",BOX_CELL,SHARED_ID,DIGEST)],
		["start_processing",sourced("plank",BOX_CELL,SHARED_ID,DIGEST)],["queue_processing",longest()]]
	for r in requests:
		session.rates[1]=[]   # isolate from the unrelated 12/s limiter
		var calls_before:int=world.calls.size()
		var replies_before:int=replies.size()
		var seq:int=session.perform(r[0],STATION,r[1])
		check(world.calls.size()==calls_before+1,"Host %s routed to World.act once"%r[0])
		if world.calls.size()==calls_before+1:
			var call:Dictionary=world.calls[-1]
			check(call.token==ALPHA and call.action==r[0] and call.extra==r[1] and call.p==STATION,"Host %s forwarded byte-exact (%d bytes)"%[r[0],String(r[1]).length()])
		check(int(session.sequences[1])==seq,"Host %s consumed exactly its sequence %d"%[r[0],seq])
		check(replies.size()==replies_before+1,"Host %s gets exactly one action_completed"%r[0])
		if replies.size()==replies_before+1:
			check(replies[-1][0]==seq and replies[-1][1]==r[0],"Host %s reply carries its exact sequence %d"%[r[0],seq])
			check(replies[-1][2]==world.results[-1],"Host %s reply is World's exact result"%r[0])
	# Invalid length / grammar: dropped before World, no reply, sequence not consumed.
	var bads:=bad_sourced()
	for action in SOURCE_ACTIONS:
		for extra in [bads["97_bytes"],bads["non_ascii_recipe"],bads["id_upper"],"x".repeat(33)]:
			session.rates[1]=[]
			var calls_before:int=world.calls.size()
			var replies_before:int=replies.size()
			var seq_before:int=int(session.sequences[1])
			session.perform(action,STATION,extra)
			check(world.calls.size()==calls_before,"Host %s invalid extra (%d chars) never reaches World"%[action,extra.length()])
			check(replies.size()==replies_before,"Host %s invalid extra gets no action_completed"%action)
			check(int(session.sequences[1])==seq_before,"Host %s invalid extra does not consume a sequence"%action)
	session.rates[1]=[]
	var calls_now:int=world.calls.size()
	session.perform("claim_cook",STATION,sourced("soup",BOX_CELL,SHARED_ID,DIGEST))
	check(world.calls.size()==calls_now,"Non-source action with sourced payload dropped by old 32 bound")
	session.perform("prepare_material_box",STATION,BOX_CELL+"|"+SHARED_ID)
	check(world.calls.size()==calls_now,"prepare_material_box with non-cell extra dropped")
	session.rates[1]=[]
	var after_drop:int=session.perform("queue_cook",STATION,sourced("soup",BOX_CELL,SHARED_ID,DIGEST))
	check(world.calls.size()==calls_now+1 and replies[-1][0]==after_drop and replies[-1][1]=="queue_cook","Valid request after drops is routed and correlated with its own sequence")
	# Non-correlated control.
	session.rates[1]=[]
	var quiet:=replies.size()
	session.perform("toggle_conveyor",STATION)
	check(replies.size()==quiet,"Non-correlated action is not acknowledged via action_completed")
	# Remote peer dispatch (no transport): forwarded with the peer's token, reply
	# targets that peer so nothing is emitted on the host.
	var host_replies:=replies.size()
	var wire:=sourced("charcoal",BOX_CELL,BETA_PRIVATE_ID,DIGEST)
	session._action(2,1,"queue_processing",STATION,wire)
	session._action(2,2,"prepare_material_box",STATION,BOX_CELL)
	check(world.calls.size()>=2 and world.calls[-2]=={"token":BETA,"action":"queue_processing","p":STATION,"extra":wire}
		and world.calls[-1]=={"token":BETA,"action":"prepare_material_box","p":STATION,"extra":BOX_CELL},"Peer dispatch forwards sourced wire and prepare cell intact")
	check(int(session.sequences[2])==2,"Peer sequences consumed in order")
	var peer_calls:=world.calls.size()
	session._action(2,3,"queue_cook",STATION,bads["97_bytes"])
	check(world.calls.size()==peer_calls and int(session.sequences[2])==2,"Peer 97-byte sourced extra dropped without consuming sequence 3")
	session._action(2,3,"queue_cook",STATION,sourced("soup",BOX_CELL,SHARED_ID,DIGEST))
	check(world.calls.size()==peer_calls+1 and int(session.sequences[2])==3,"Peer sequence 3 still usable after the refused request")
	check(replies.size()==host_replies,"Remote peer replies are not emitted on the host")
	session.world=null;session.queue_free();await process_frame

func privacy_section()->void:
	var session:=FixtureSession.new();root.add_child(session);session.set_physics_process(false)
	session.world=World.new();var world:World=session.world
	for actor in [ALPHA,BETA,GAMMA]:world.add_player(actor,actor.left(10))
	world.active_tokens.erase(GAMMA)   # GAMMA: saved resident, offline, not a peer
	# LABELLED FIXTURE: box_ids written directly into World state.
	world.state.objects["40,30"]={"type":"chest","owner":ALPHA,"items":{"wood":3},"box_id":SHARED_ID}
	world.state.objects["41,30"]={"type":"private_chest","owner":ALPHA,"items":{"stone":2},"box_id":ALPHA_PRIVATE_ID}
	world.state.objects["42,30"]={"type":"private_chest","owner":BETA,"items":{"fiber":1},"box_id":BETA_PRIVATE_ID}
	world.state.objects["43,30"]={"type":"private_chest","owner":GAMMA,"items":{"wood":9},"box_id":GAMMA_PRIVATE_ID}
	world.state.objects["44,30"]={"type":"private_chest","owner":BETA,"items":{}}
	world.state.regions.lanyang.objects["20,20"]={"type":"private_chest","owner":GAMMA,"items":{},"box_id":GAMMA_REGION_ID}
	var before:=var_to_str([world.state.objects,world.state.regions.lanyang.objects])
	var views:={}
	for viewer in [ALPHA,BETA]:
		session.peers={1:viewer,2:BETA if viewer==ALPHA else ALPHA}
		for pass_index in 2:
			session._send_snapshot(1)
			var snap:Dictionary=session.snapshot
			var text:=var_to_str(snap)
			check(session.own_id==pub(viewer),"Snapshot delivered to %s as host peer"%viewer.left(9))
			check(snap.objects["40,30"].get("box_id")==SHARED_ID,"Shared chest id visible to %s (pass %d)"%[viewer.left(9),pass_index])
			var own_cell:="41,30" if viewer==ALPHA else "42,30"
			var other_cell:="42,30" if viewer==ALPHA else "41,30"
			var own_id:=ALPHA_PRIVATE_ID if viewer==ALPHA else BETA_PRIVATE_ID
			var other_id:=BETA_PRIVATE_ID if viewer==ALPHA else ALPHA_PRIVATE_ID
			check(snap.objects[own_cell].get("box_id")==own_id and not snap.objects[own_cell].get("locked",false),"Own private chest keeps its box_id for %s"%viewer.left(9))
			check(not snap.objects[other_cell].has("box_id") and snap.objects[other_cell].locked==true and snap.objects[other_cell].items.is_empty(),"Other online player's private box_id/items stripped for %s"%viewer.left(9))
			check(not snap.objects["43,30"].has("box_id") and snap.objects["43,30"].items.is_empty(),"Offline non-peer owner's private box_id stripped for %s"%viewer.left(9))
			check(not text.contains(other_id) and not text.contains(GAMMA_PRIVATE_ID),"No other owner's private id anywhere in %s's snapshot"%viewer.left(9))
			for token in [ALPHA,BETA,GAMMA]:check(not text.contains(token),"No raw token in %s's snapshot"%viewer.left(9))
			views[viewer]=snap
	check(not views[BETA].objects["44,30"].has("box_id") and not views[ALPHA].objects["44,30"].has("box_id"),"Chest without id stays without id (nothing invented)")
	# Regional recipient: a non-owner in lanyang never sees GAMMA's regional id.
	world.state.players[BETA].region="lanyang"
	session.peers={1:BETA}
	session._send_snapshot(1)
	check(session.snapshot.objects.has("20,20"),"Regional snapshot built for lanyang recipient")
	check(not session.snapshot.objects.get("20,20",{}).has("box_id"),"Regional non-owner private box_id stripped")
	check(not var_to_str(session.snapshot).contains(GAMMA_REGION_ID),"Regional private id never leaks")
	world.state.players[BETA].region="home"
	check(var_to_str([world.state.objects,world.state.regions.lanyang.objects])==before,"World state untouched by _send_snapshot (ids kept server-side)")
	check(world.state.objects["42,30"].box_id==BETA_PRIVATE_ID,"World keeps the private box_id")
	session.world=null;session.queue_free();await process_frame
