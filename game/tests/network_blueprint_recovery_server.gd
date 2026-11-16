extends SceneTree
## Fault-injection fixture SERVER for work/house-rooms/network_blueprint_recovery.py.
##
## Hosts the real Session + World (same node path as main.gd: /root/Island/Session)
## through a Session SUBCLASS that injects exactly one fault:
##
##   INJECTED LOST REPLY. The FIRST successful blueprint apply that freshly
##   commits (no receipt existed for that nonce before the request) runs the
##   unmodified Session._handle_blueprint_apply -> World.apply_blueprint (pieces,
##   auto roofs, inventory, receipt, save) and the unmodified snapshot broadcast.
##   Only the final Session._reply_blueprint_result call to the requesting peer
##   is suppressed, AFTER this script has proven the commit both in memory
##   (World.blueprint_receipt) and on disk (save file receipt). A marker JSON is
##   written to <handoff>/fault-marker.json, then the reply is dropped. No result
##   is ever fabricated; every other reply (including later receipt replays) is
##   delivered unchanged. The injection never re-arms.
##
## Stops normally (Session.shutdown(): final World.save, peer close) when the
## runner creates <handoff>/stop-server; exits 0 only in that case.
##
## Args (after `--`): <save> <port> <room_key> <websocket|enet> <handoff_dir> <max_seconds>

const MARKER_NAME:="fault-marker.json"
const STOP_NAME:="stop-server"

class FaultSession extends "res://scripts/session.gd":
	var fault_marker_path:=""
	var fault_fired:=false
	var fault_skipped:=""
	var apply_requests:={}
	var _candidate_peer:=0
	var _candidate_nonce:=""

	func _handle_blueprint_apply(id:int,nonce:String,design_json:String,origin:Vector2i,turns:Variant,expected_hash:String,region:String,epoch:int) -> void:
		var key:=nonce.left(64)
		apply_requests[key]=int(apply_requests.get(key,0))+1
		_candidate_peer=0
		_candidate_nonce=""
		if not fault_fired and world!=null and peers.has(id) and world.blueprint_receipt(peers[id],nonce).is_empty():
			_candidate_peer=id
			_candidate_nonce=nonce
		super._handle_blueprint_apply(id,nonce,design_json,origin,turns,expected_hash,region,epoch)
		_candidate_peer=0
		_candidate_nonce=""

	func _reply_blueprint_result(id:int,nonce:String,result:Dictionary) -> void:
		if not fault_fired and id!=0 and id==_candidate_peer and nonce==_candidate_nonce and result.get("ok")==true:
			var proof:=_commit_proof(id,nonce,result)
			if proof.get("ok")==true:
				fault_fired=true
				var marker:Dictionary=proof.marker
				if not _write_marker(marker):
					# Without a marker the runner cannot observe the fault; deliver normally.
					fault_fired=false
					fault_skipped="marker write failed"
					print("BPR_FAULT_SKIPPED marker write failed; reply delivered unchanged")
				else:
					print("BPR_FAULT injected_lost_reply nonce=%s hash=%s pieces=%d (World committed + saved; snapshots sent; reply suppressed)"%[
						nonce.left(8),str(result.get("hash","")).left(12),int(result.get("pieces",-1))])
					return
			else:
				fault_skipped=str(proof.get("reason",""))
				print("BPR_FAULT_SKIPPED %s; reply delivered unchanged"%fault_skipped)
		super._reply_blueprint_result(id,nonce,result)

	## Proves the authoritative commit before the reply is dropped.
	func _commit_proof(id:int,nonce:String,result:Dictionary) -> Dictionary:
		if world==null or not peers.has(id):return {"ok":false,"reason":"no world/peer"}
		var token:String=peers[id]
		var memory:Dictionary=world.blueprint_receipt(token,nonce)
		if memory.get("ok")!=true or str(memory.get("hash",""))!=str(result.get("hash","-")):
			return {"ok":false,"reason":"no in-memory receipt"}
		var disk=JSON.parse_string(FileAccess.get_file_as_string(str(world.save_path)))
		if not disk is Dictionary:return {"ok":false,"reason":"save file unreadable"}
		var person=disk.get("players",{}).get(token)
		var stored=person.get("receipts",{}).get(World.BLUEPRINT_RECEIPT+nonce) if person is Dictionary else null
		if not stored is Dictionary or stored.get("ok")!=true or str(stored.get("hash",""))!=str(result.get("hash","-")):
			return {"ok":false,"reason":"no receipt in the save file"}
		return {"ok":true,"marker":{
			"injection":"lost_blueprint_apply_reply",
			"boundary":"Session._reply_blueprint_result suppressed after World.apply_blueprint returned ok (state + save committed) and after the snapshot broadcast",
			"nonce":nonce,"hash":str(result.get("hash","")),"pieces":int(result.get("pieces",-1)),"cost":result.get("cost",{}),
			"actor":token.sha256_text().left(16),"world_committed":true,"disk_receipt":true,
			"disk_version":int(disk.get("version",-1)),"apply_requests_for_nonce":int(apply_requests.get(nonce.left(64),0)),
			"unix":Time.get_unix_time_from_system()}}

	func _write_marker(marker:Dictionary) -> bool:
		var temp:=fault_marker_path+".tmp"
		var file:=FileAccess.open(temp,FileAccess.WRITE)
		if file==null:return false
		file.store_string(JSON.stringify(marker))
		file.flush()
		var err:=file.get_error()
		file.close()
		return err==OK and DirAccess.rename_absolute(temp,fault_marker_path)==OK

var session:FaultSession

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=6 or not args[3] in ["websocket","enet"]:
		push_error("BPR_SERVER_FAIL usage: <save> <port> <room_key> <websocket|enet> <handoff_dir> <max_seconds>")
		quit(2)
		return
	var handoff:String=args[4]
	var island:=Node2D.new()
	island.name="Island"
	root.add_child(island)
	session=FaultSession.new()
	island.add_child(session)
	session.fault_marker_path=handoff.path_join(MARKER_NAME)
	var base:Script=load("res://scripts/session.gd")
	var mine:Script=session.get_script()
	if base.has_method("get_rpc_config"):
		var a=base.get_rpc_config()
		var b=mine.get_rpc_config()
		print("BPR_SERVER_INFO rpc_config base=%d subclass=%d equal=%s (client registration proves inherited RPCs work)"%[
			(a as Dictionary).size() if a is Dictionary else -1,(b as Dictionary).size() if b is Dictionary else -1,str(a==b)])
	var err:=session.host(int(args[1]),"",args[0],args[2],"127.0.0.1",true,args[3])
	if err!=OK:
		push_error("BPR_SERVER_FAIL host error %d"%err)
		quit(1)
		return
	print("BPR_SERVER_INFO fault armed: drop the first fresh successful blueprint apply reply")
	var stop_path:=handoff.path_join(STOP_NAME)
	var deadline:=Time.get_ticks_msec()+int(float(args[5])*1000.0)
	while not FileAccess.file_exists(stop_path) and Time.get_ticks_msec()<deadline:
		await create_timer(0.1).timeout
	var by_runner:=FileAccess.file_exists(stop_path)
	print("BPR_SERVER_STATE fault_fired=%s skipped=%s apply_requests=%s"%[str(session.fault_fired),
		JSON.stringify(session.fault_skipped),JSON.stringify(_short(session.apply_requests))])
	var saved:=session.shutdown()
	print("BPR_SERVER_STOPPED by=%s saved=%s"%["runner" if by_runner else "watchdog",str(saved)])
	for _frame in 8:await process_frame
	quit(0 if saved and by_runner else (2 if not saved else 3))

static func _short(counts:Dictionary) -> Dictionary:
	var out:={}
	for nonce in counts:out[str(nonce).left(8)]=counts[nonce]
	return out
