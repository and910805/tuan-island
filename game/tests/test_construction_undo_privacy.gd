extends SceneTree
const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const ALPHA:="private-alpha-construct-token"
const BETA:="private-beta-construct-token"
const OFFLINE:="private-offline-construct-token"
const RAW_IDS:=["raw-history-entry-alpha-0001","raw-history-entry-beta-0002","raw-history-entry-offline-0003","raw-unknown-nested-id-0004"]
const SUMMARY_KEYS:=["available","id","label","reason","region","seconds_left"]
var checks:=0
var failures:=0
func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;push_error(message)
func leaks(data:Variant,secrets:Array)->Array:
	var text:=JSON.stringify(data)
	var found:=[]
	for secret in secrets:
		if text.contains(String(secret)):found.append(secret)
	return found
func _initialize()->void:run.call_deferred()
func run()->void:
	check(Session.PROTOCOL>=39,"protocol supports construction undo summaries and blueprint RPC")
	var session:=Session.new();root.add_child(session);session.set_physics_process(false)
	session.world=World.new();var world:World=session.world
	check(int(world.state.version)==preload("res://scripts/save_schema.gd").VERSION,"New world modelled through core at version 20")
	check(world.state.has("construction"),"Core world carries construction history state")
	for actor in [ALPHA,BETA,OFFLINE]:world.add_player(actor,actor.left(12))
	# OFFLINE has saved state and history but no live peer.
	world.active_tokens.erase(OFFLINE)
	session.peers={1:ALPHA,2:BETA}
	# Unknown fields with nested raw tokens/IDs: public_state must drop the whole
	# construction subtree, not filter known keys.
	var fixture:={"unknown_privacy_fixture":{"by_actor":{ALPHA:{"id":RAW_IDS[0]},BETA:{"id":RAW_IDS[1]},OFFLINE:{"id":RAW_IDS[2]}},
		"deep":[{"owner":OFFLINE,"nested":{"token":BETA,"entry":RAW_IDS[3]}}]},
		"unknown_flat_token":OFFLINE}
	if world.state.construction is Dictionary:world.state.construction.merge(fixture,true)
	else:world.state.construction=fixture
	var all_secrets:Array=[ALPHA,BETA,OFFLINE]+RAW_IDS
	for region in World.REGIONS.ALL:
		var public:Dictionary=session.public_state(region)
		if public.is_empty():continue
		check(not public.has("construction"),"public_state(%s) erases whole construction"%region)
		check(not public.has("own_construction_undo"),"public_state(%s) carries no per-recipient summary"%region)
		var leaked:=leaks(public,all_secrets)
		check(leaked.is_empty(),"public_state(%s) leaks raw tokens/history ids: %s"%[region,leaked])
	# Offline players are not peers, but their history must still be absent.
	var home_public:Dictionary=session.public_state("home")
	check(leaks(home_public,[OFFLINE,RAW_IDS[2]]).is_empty(),"Offline player's raw history hidden")
	session._send_snapshot(1)
	var snap:Dictionary=session.snapshot
	check(not snap.is_empty(),"Local recipient snapshot delivered")
	check(not snap.has("construction"),"Recipient snapshot has no raw construction history")
	check(snap.has("own_construction_undo") and snap.own_construction_undo is Dictionary,"Recipient snapshot contains own undo summary")
	var own:Dictionary=snap.get("own_construction_undo",{})
	var keys:Array=own.keys();keys.sort()
	check(keys==SUMMARY_KEYS,"Own summary exposes only safe fields: %s"%[keys])
	check(own==world.undo_summary(ALPHA),"Own summary matches core summary for recipient token")
	var other_keys:=[]
	check(snap.get("edge_construction") is bool,"Edge construction capability is only a Boolean")
	for field in snap.keys():
		if String(field).contains("construction") and field not in ["own_construction_undo","edge_construction"]:other_keys.append(field)
	check(other_keys.is_empty(),"No other construction summaries in snapshot: %s"%[other_keys])
	var snap_leaks:=leaks(snap,all_secrets)
	check(snap_leaks.is_empty(),"Recipient snapshot leaks raw tokens/history ids: %s"%[snap_leaks])
	check(leaks(own,all_secrets).is_empty(),"Own summary contains no raw tokens or raw history ids")
	# Peer 2 cannot be sent to without a transport; verify its public view and the
	# summary core would hand it are both free of raw identifiers.
	var beta_public:Dictionary=session.public_state(world.player_region(BETA))
	check(not beta_public.has("construction") and leaks(beta_public,all_secrets).is_empty(),"Peer public snapshot exposes no raw history")
	var beta_summary:Dictionary=world.undo_summary(BETA)
	check(leaks(beta_summary,all_secrets).is_empty(),"Peer's own summary exposes no raw ids")
	session.world=null;session.queue_free();await process_frame
	print("CONSTRUCTION_UNDO_PRIVACY_TESTS checks=%d failures=%d"%[checks,failures]);quit(int(failures>0))
