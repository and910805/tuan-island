extends SceneTree
## T019 世界時間與無人暫停 — acceptance「離線一小時不偷跑成熟」, Session level.
##
## LEVEL: one machine, ONE Godot process, no client. A dedicated server Session hosts an
## isolated temporary save over the real WebSocket transport (127.0.0.1, random port) with an
## EMPTY peer population. The Session's real physics entry point `_physics_process` is called
## once with a simulated 3600-second frame (the production path: world.step(dt, peers.size()>0)
## followed by the periodic save branch). The complete World state must stay byte-for-byte
## identical, the periodic save must write exactly that unchanged state, and after a normal
## shutdown the save must reload (plain World and a restarted Session) with the same state.
##
## POSITIVE CONTROL: the same save stepped for 3600 s with active=true in a separate in-memory
## World (save_path cleared, never written) advances time, crop growth, tree growth, the
## processing queue and `committed`, so the fixture really carries time-driven state.
##
## SEEDED FIXTURE (disclosed): built offline in a World before the server starts.
##   PRESET : sawmill written into the object layer in the shape `build` produces (same as
##            test_processing_queue_world.gd place()); player teleports before each action.
##   EARNED : hoe + sow + water one plot; plant one sapling; queue three plank jobs (starter
##            wood); one World.step(5 s, active=true) so time, growth, an active processing
##            job and `committed` are all non-zero.
## TEST-ONLY SESSION SUBCLASS (disclosed): PauseSession replaces only `_ready` so that
## user://profile.json is never read or written; it wires the same multiplayer signals as
## production. host / _physics_process / shutdown are the unmodified production methods.
## All files live in one random folder under the OS TEMP directory and are deleted at the end
## (world.json, .bak, .tmp, writer-lock sidecars). User saves are never opened.
## OPTIONAL WALL-CLOCK SOAK (`-- --wallclock-seconds=N`, integer 1..7200): the same isolated
## WebSocket world with zero peers, but the Session's physics processing is LEFT ENABLED and the
## test simply waits N real seconds (engine-driven frames, periodic saves every 10 s); it never
## calls `_physics_process` itself. A heartbeat line is printed once per real minute. Afterwards
## the full World state, time-driven fixture fields, `committed` and the persisted save must be
## unchanged; shutdown / reload / restart / cleanup run as in the default mode (the restart phase
## also uses a short real wait instead of a simulated frame). Watchdog: N + 600 s.
## NOT covered: client reconnect, identity/membership worlds. Real waiting only in soak mode.
## Run: godot --headless --path game --script res://tests/test_offline_pause.gd
## Soak: godot --headless --path game --script res://tests/test_offline_pause.gd -- --wallclock-seconds=3600
const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const WriteGuard=preload("res://scripts/world_write_guard.gd")
const REGIONS=preload("res://scripts/regions.gd")
const TAG:="OFFLINE_PAUSE"
const KEY:="offline-pause-room"
const A:="offline-pause-alpha-token"
const OFFLINE_DT:=3600.0
const FIXTURE_DT:=5.0
const PORT_ATTEMPTS:=12
const WALLCLOCK_ARG:="--wallclock-seconds"
const WALLCLOCK_MAX:=7200
const DEFAULT_WATCHDOG:=60.0
const SOAK_CLEANUP_MARGIN:=600.0 # soak watchdog = N + this (covers fixture, shutdown, restart wait, cleanup)
const HEARTBEAT_SECONDS:=60
const SOAK_SAVE_PROOF_MIN:=15 # periodic save (every 10 s) is certain to have rewritten the file
const RESTART_SOAK_WAIT:=11.0 # > one periodic save interval on the restarted Session

class PauseSession extends "res://scripts/session.gd":
	func _ready() -> void:
		name="Session"
		session_nonce=Crypto.new().generate_random_bytes(16).hex_encode()
		tool_action_epoch=Crypto.new().generate_random_bytes(6).hex_encode()
		multiplayer.peer_connected.connect(_peer_connected)
		multiplayer.peer_disconnected.connect(_peer_left)
		multiplayer.connected_to_server.connect(_connected)
		multiplayer.connection_failed.connect(_failed)
		multiplayer.server_disconnected.connect(_lost)
		profile={"token":"offline-pause-unused-profile-token"}

var checks:=0
var failures:=0
var serial:=0
var presets:=0
var finished:=false
var folder:=""
var save_path:=""
var server=null
var server_branch:Node=null
var plot_key:=""
var tree_key:=""
var site_key:=""
var wallclock_seconds:=0 # 0 = default fast mode
var arg_error:=""
var physics_frames:=0

func expect(ok:bool,label:String)->bool:
	checks+=1
	if not ok:
		failures+=1
		push_error("FAIL "+label)
	return ok

func _initialize()->void:
	wallclock_seconds=parse_wallclock()
	if wallclock_seconds<0:
		# Rejected before any fixture, folder, lock or server exists: nothing to clean up.
		finished=true
		print("%s invalid %s argument: %s (expected %s=N with integer N in 1..%d)"%[TAG,WALLCLOCK_ARG,arg_error,WALLCLOCK_ARG,WALLCLOCK_MAX])
		print("%s_TESTS checks=%d failures=%d"%[TAG,0,1])
		quit(1)
		return
	var limit:=DEFAULT_WATCHDOG if wallclock_seconds==0 else float(wallclock_seconds)+SOAK_CLEANUP_MARGIN
	create_timer(limit,true,false,true).timeout.connect(_watchdog)
	if wallclock_seconds>0:physics_frame.connect(_count_physics_frame)
	run.call_deferred()

func _count_physics_frame()->void:
	physics_frames+=1

## 0 when absent; the bounded duration when valid; -1 (with arg_error) when malformed.
## Accepts the flag before or after `--`; strictly digits, no sign/space/decimal, 1..7200.
func parse_wallclock()->int:
	var found:=[]
	for a in Array(OS.get_cmdline_args())+Array(OS.get_cmdline_user_args()):
		var s:=String(a)
		if s==WALLCLOCK_ARG or s.begins_with(WALLCLOCK_ARG+"="):found.append(s)
	if found.is_empty():return 0
	if found.size()>1:
		arg_error="given %d times"%found.size()
		return -1
	var flag:String=found[0]
	if not flag.begins_with(WALLCLOCK_ARG+"="):
		arg_error="missing =N"
		return -1
	var v:=flag.substr(WALLCLOCK_ARG.length()+1)
	if v.is_empty() or v.length()>4:
		arg_error="'%s' is empty or too long"%v
		return -1
	for ch in v:
		if not "0123456789".contains(ch):
			arg_error="'%s' is not a plain positive integer"%v
			return -1
	var n:=int(v)
	if n<1 or n>WALLCLOCK_MAX:
		arg_error="%d is outside 1..%d"%[n,WALLCLOCK_MAX]
		return -1
	return n

func _watchdog()->void:
	if finished:return
	finished=true
	print("%s watchdog fired before completion"%TAG)
	release_server()
	remove_folder()
	print("%s_TESTS checks=%d failures=%d"%[TAG,checks,failures+1])
	quit(1)

func run()->void:
	var started:=Time.get_ticks_msec()
	var completed:=await scenario()
	expect(completed,"scenario ran to completion")
	await teardown()
	expect(remove_folder(),"temporary folder and every file in it (save, backup, locks) removed")
	if finished:return
	finished=true
	if wallclock_seconds>0:print("%s_MODE wallclock_soak requested_s=%d"%[TAG,wallclock_seconds])
	print("%s duration_ms=%d presets=%d"%[TAG,Time.get_ticks_msec()-started,presets])
	print("%s_TESTS checks=%d failures=%d"%[TAG,checks,failures])
	quit(int(failures>0 or checks==0))

# ---------------------------------------------------------------- helpers --

## Key-sorted, String-keyed deep copy: JSON reload sorts keys and turns StringName keys into
## String, so cross-reload comparisons use var_to_bytes(canon(x)).
static func canon(v:Variant)->Variant:
	if v is Dictionary:
		var pairs:Array=[]
		for k in v:pairs.append([str(k),k])
		pairs.sort_custom(func(a,b):return a[0]<b[0])
		var out:={}
		for p in pairs:out[p[0]]=canon(v[p[1]])
		return out
	if v is Array:
		var arr:=[]
		for x in v:arr.append(canon(x))
		return arr
	return v

static func canon_bytes(v:Variant)->PackedByteArray:
	return var_to_bytes(canon(v))

## Top-level keys whose canonical content differs (diagnostics only).
static func differing_keys(a:Dictionary,b:Dictionary)->Array:
	var keys:={}
	for k in a:keys[str(k)]=true
	for k in b:keys[str(k)]=true
	var out:=[]
	for k in keys:
		if canon_bytes(a.get(k))!=canon_bytes(b.get(k)):out.append(k)
	out.sort()
	return out

func pause(seconds:float)->void:
	await create_timer(seconds,true,false,true).timeout

static func processing_of(state:Dictionary,k:String)->Dictionary:
	var obj=state.get("objects",{}).get(k,{})
	var q=obj.get("processing") if obj is Dictionary else null
	return q if q is Dictionary else {}

static func entry(state:Dictionary,layer:String,k:String)->Dictionary:
	var d=state.get(layer,{})
	var e=d.get(k,{}) if d is Dictionary else {}
	return e if e is Dictionary else {}

# ---------------------------------------------------------------- fixture --

func teleport(w,p:Vector2i)->void:
	var person:Dictionary=w.state.players[A]
	person.x=float(p.x)+0.5 # PRESET teleport
	person.y=float(p.y)+1.6 # PRESET teleport
	presets+=1

func act(w,action:String,p:Vector2i,extra:String="")->Dictionary:
	teleport(w,p)
	serial+=1
	return w.act(A,"offline-pause-fixture-%d"%serial,action,p,extra)

func site_clear(w,a:Vector2i,size:Vector2i)->bool:
	for y in range(a.y,a.y+size.y):
		for x in range(a.x,a.x+size.x):
			var c:=Vector2i(x,y)
			var k:=World.key(c)
			if not w.is_land(c) or w.water(c) or w.protected(c):return false
			for field in ["objects","ground","roofs","crops","forest"]:
				if w.state[field].has(k):return false
			var had:bool=w.state.removed.has(k)
			w.state.removed[k]=true
			var b:bool=w.blocked(c)
			if not had:w.state.removed.erase(k)
			if b:return false
	return true

## Legal empty 3x1 row with a two-cell margin away from the spawn (copied from
## test_processing_queue_world.gd find_site); margin resources are marked removed.
func find_site(w)->Vector2i:
	var size:=Vector2i(3,1)
	for oy in range(3,57):
		for ox in range(3,76):
			if Vector2(ox,oy).distance_to(Vector2(World.SPAWN))<7.0:continue
			if site_clear(w,Vector2i(ox-2,oy-2),size+Vector2i(4,4)):
				for y in range(oy-2,oy+size.y+2):
					for x in range(ox-2,ox+size.x+2):
						var c:=Vector2i(x,y)
						if w.resource(c)!="":w.state.removed[World.key(c)]=true
				return Vector2i(ox,oy)
	return Vector2i(-1,-1)

func candidates(avoid:Vector2i)->Array:
	var out:=[]
	for y in range(18,44):
		for x in range(22,58):
			var c:=Vector2i(x,y)
			if Vector2(c).distance_to(Vector2(avoid))<6.0:continue
			out.append(c)
	out.sort_custom(func(a:Vector2i,b:Vector2i)->bool:return (Vector2(a)+Vector2(0.5,0.5)).distance_squared_to(World.SPAWN)<(Vector2(b)+Vector2(0.5,0.5)).distance_squared_to(World.SPAWN))
	return out

func seed_world(path:String)->bool:
	var w:=World.new()
	w.add_player(A,"alpha")
	var site:=find_site(w)
	if not expect(site.x>=0,"fixture: legal sawmill site found"):return false
	site_key=World.key(site)
	w.state.objects[site_key]={"type":"sawmill","owner":A,"items":{},"input_wood":0,"auto_enabled":false} # PRESET station
	presets+=1
	var cells:=candidates(site)
	var plot:=Vector2i(-1,-1)
	for c:Vector2i in cells:
		if bool(act(w,"hoe",c).get("ok",false)):
			plot=c
			break
	if not expect(plot.x>=0,"fixture: a plot was tilled through World.act"):return false
	plot_key=World.key(plot)
	var kind:=""
	for k in ["wheat","radish","lettuce"]:
		if World.crop_grows_in_season(k,REGIONS.HOME,plot,0.0):
			kind=k
			break
	if not expect(not kind.is_empty(),"fixture: a starter crop is in season at time 0"):return false
	var sown:=act(w,"seed",plot,kind)
	if not expect(bool(sown.get("ok",false)),"fixture: sow %s (%s)"%[kind,str(sown.get("message",""))]):return false
	var watered:=act(w,"water",plot)
	if not expect(bool(watered.get("ok",false)),"fixture: water the plot (%s)"%str(watered.get("message",""))):return false
	var tree:=Vector2i(-1,-1)
	for c:Vector2i in cells:
		if c==plot or Vector2(c).distance_to(Vector2(plot))<2.0:continue
		if bool(act(w,"plant_tree",c).get("ok",false)):
			tree=c
			break
	if not expect(tree.x>=0,"fixture: a sapling was planted through World.act"):return false
	tree_key=World.key(tree)
	for i in 3:
		var queued:=act(w,"queue_processing",site,"plank")
		if not expect(bool(queued.get("ok",false)),"fixture: queue plank job %d (%s)"%[i,str(queued.get("message",""))]):return false
	w.save_path=""
	if not expect(w.step(FIXTURE_DT,true),"fixture: World.step(%.0f s, active) succeeded"%FIXTURE_DT):return false
	var crop:=entry(w.state,"crops",plot_key)
	var sapling:=entry(w.state,"forest",tree_key)
	var q:=processing_of(w.state,site_key)
	expect(float(w.state.time)==FIXTURE_DT,"fixture: world time is %.1f"%FIXTURE_DT)
	expect(int(w.state.committed)>=1,"fixture: committed counter is non-zero (%s)"%str(w.state.committed))
	expect(float(crop.get("growth",0.0))>0.0 and crop.get("wet")==true,"fixture: plot is wet and growing (%s)"%str(crop))
	expect(float(sapling.get("growth",0.0))>0.0 and sapling.get("mature")==false,"fixture: sapling growing, not mature (%s)"%str(sapling))
	expect(q.get("active") is Dictionary and not (q.get("active") as Dictionary).is_empty() and q.get("waiting") is Array and (q.get("waiting") as Array).size()>=1,"fixture: sawmill has an active job and a waiting job")
	w.active_tokens.clear()
	w.save_path=path
	if not expect(w.save(),"fixture: saved to the temporary path"):return false
	var probe:=World.new()
	return expect(probe.load_world(path) and not probe.recovered_from_backup,"fixture: save reloads through load_world (SaveSchema) from the primary file")

## The same save stepped while somebody is present must change: proves the fixture is live.
func positive_control()->void:
	var ctrl:=World.new()
	if not expect(ctrl.load_world(save_path),"control: fixture loads into a separate World"):return
	ctrl.save_path="" # in-memory only; the fixture file is never written by the control
	var before:Dictionary=ctrl.state.duplicate(true)
	expect(ctrl.step(OFFLINE_DT,true),"control: World.step(%.0f s, active=true) succeeds"%OFFLINE_DT)
	expect(is_equal_approx(float(ctrl.state.time),float(before.time)+OFFLINE_DT),"control: time advances by %.0f s (%s -> %s)"%[OFFLINE_DT,str(before.time),str(ctrl.state.time)])
	expect(int(ctrl.state.committed)>int(before.committed),"control: committed increases (%s -> %s)"%[str(before.committed),str(ctrl.state.committed)])
	expect(float(entry(ctrl.state,"crops",plot_key).get("growth",0.0))>float(entry(before,"crops",plot_key).get("growth",0.0)),"control: crop growth increases")
	expect(float(entry(ctrl.state,"forest",tree_key).get("growth",0.0))>float(entry(before,"forest",tree_key).get("growth",0.0)),"control: tree growth increases")
	expect(canon_bytes(processing_of(ctrl.state,site_key))!=canon_bytes(processing_of(before,site_key)),"control: processing queue advances")
	expect(FileAccess.get_file_as_string(save_path)==fixture_text,"control: fixture file untouched by the control World")

# ------------------------------------------------------------- transport --

func host_on(port:int)->Error:
	server_branch=Node.new()
	serial+=1
	server_branch.name="OfflinePauseServer%d"%serial
	root.add_child(server_branch)
	set_multiplayer(SceneMultiplayer.new(),server_branch.get_path())
	server=PauseSession.new()
	server_branch.add_child(server)
	var err:Error=server.host(port,"",save_path,KEY,"127.0.0.1",true,"websocket")
	if err==OK and wallclock_seconds==0:
		# Only the explicit simulated frame drives this server; idle engine frames do not.
		# (Soak mode leaves production physics processing enabled: real frames drive it.)
		server.set_physics_process(false)
	return err

func start_server()->int:
	for attempt in 8:
		var port:=randi_range(31000,58000)
		if host_on(port)==OK:return port
		await drop_branch()
	return 0

func drop_branch()->void:
	if is_instance_valid(server_branch):server_branch.queue_free()
	server_branch=null
	server=null
	await process_frame

func stop_server()->bool:
	var ok:bool=server.shutdown()
	expect(server.world==null and server.shutting_down,"shutdown: Session released its World")
	await pause(0.2)
	await drop_branch()
	return ok

func release_server()->void:
	if server!=null and is_instance_valid(server) and server.world!=null:
		if not server.shutdown():
			# Error path only (final save failed): still close the port and drop the writer
			# lock so the temporary folder can be deleted.
			if server.multiplayer.multiplayer_peer!=null:server.multiplayer.multiplayer_peer.close()
			server.write_guard.release()

## Server invariants for an empty world at rest.
func assert_empty(label:String)->void:
	expect(server.multiplayer.is_server() and server.multiplayer.multiplayer_peer is WebSocketMultiplayerPeer,"%s: real WebSocket server peer"%label)
	expect(server.headless and server.membership==null,"%s: dedicated server, no identity membership"%label)
	expect(server.peers.is_empty() and server.pending.is_empty() and server.directions.is_empty(),"%s: no peers, no pending connections"%label)
	expect(server.world.active_tokens.is_empty(),"%s: no active player tokens in World"%label)
	expect(server.accepting and not server.admission_recovery_required,"%s: Session accepting, no recovery freeze"%label)

# --------------------------------------------------------------- scenario --

var fixture_text:=""

func scenario()->bool:
	var base:=OS.get_environment("TEMP")
	if base.is_empty():base=OS.get_environment("TMPDIR")
	if not expect(not base.is_empty(),"OS temporary directory available"):return false
	folder=base.path_join("offline-pause-%s"%Crypto.new().generate_random_bytes(8).hex_encode())
	if not expect(not DirAccess.dir_exists_absolute(folder) and DirAccess.make_dir_recursive_absolute(folder)==OK,"fresh temporary folder created"):return false
	save_path=folder.path_join("world.json")
	expect(not save_path.begins_with("user://") and not save_path.begins_with("res://"),"save path is outside user:// and res:// (%s)"%save_path)
	if not seed_world(save_path):return false
	fixture_text=FileAccess.get_file_as_string(save_path)
	positive_control()

	# 1. Dedicated isolated WebSocket world, nobody connected.
	var port:=await start_server()
	if not expect(port>0,"dedicated Session hosts the temporary save over websocket on 127.0.0.1"):return false
	if wallclock_seconds>0:
		print("%s_LABEL machine=single process=single transport=websocket loopback=127.0.0.1:%d peers=0 mode=WALLCLOCK_SOAK real_wait=%ds physics=engine-driven(production _physics_process enabled, never called by the test) fixture=SEEDED(sawmill placed; plot/sapling/queue earned via World.act; one 5 s active step)"%[TAG,port,wallclock_seconds])
	else:
		print("%s_LABEL machine=single process=single transport=websocket loopback=127.0.0.1:%d peers=0 frame=%.0fs fixture=SEEDED(sawmill placed; plot/sapling/queue earned via World.act; one 5 s active step)"%[TAG,port,OFFLINE_DT])
	assert_empty("before frame")
	expect(server.world.save_path==save_path,"server World uses the temporary save path")
	var fixture_world:=World.new()
	fixture_world.load_world(save_path)
	fixture_world.save_path=""
	expect(canon_bytes(server.world.state)==canon_bytes(fixture_world.state),"server loaded exactly the fixture state")
	expect(server.save_clock==0.0 and server.broadcast_clock==0.0,"periodic clocks start at zero")

	# 2. Default: one simulated 3600-second physics frame through the real Session entry point.
	#    Soak: N real seconds of engine-driven production physics frames (no manual call).
	var world_ref=server.world
	var live_before:PackedByteArray=var_to_bytes(server.world.state)
	var canon_before:=canon_bytes(server.world.state)
	var state_before:Dictionary=server.world.state.duplicate(true)
	var json_before:=JSON.stringify(server.world.state)
	if wallclock_seconds>0:
		if not await soak(world_ref,live_before,canon_before,state_before,json_before):return false
	else:
		frame_checks(world_ref,live_before,canon_before,state_before,json_before)
	return await shutdown_and_restart(port,state_before,canon_before,json_before)

## Default mode step 2: one simulated 3600-second physics frame (unchanged 74-check path).
func frame_checks(world_ref,live_before:PackedByteArray,canon_before:PackedByteArray,state_before:Dictionary,json_before:String)->void:
	server._physics_process(OFFLINE_DT)
	expect(server.world==world_ref,"frame: same World instance")
	expect(server.world.step_error=="","frame: World.step reported no error")
	var live_after:PackedByteArray=var_to_bytes(server.world.state)
	expect(live_after==live_before,"frame: complete World state byte-for-byte unchanged (differing keys %s)"%str(differing_keys(state_before,server.world.state)))
	expect(canon_bytes(server.world.state)==canon_before,"frame: canonical World state unchanged")
	var after:Dictionary=server.world.state
	expect(float(after.time)==float(state_before.time),"frame: world time unchanged (%s)"%str(after.time))
	expect(int(after.committed)==int(state_before.committed),"frame: committed counter unchanged (%s)"%str(after.committed))
	expect(canon_bytes(entry(after,"crops",plot_key))==canon_bytes(entry(state_before,"crops",plot_key)),"frame: crop growth/wetness unchanged %s"%str(entry(after,"crops",plot_key)))
	expect(canon_bytes(entry(after,"forest",tree_key))==canon_bytes(entry(state_before,"forest",tree_key)),"frame: tree growth unchanged %s"%str(entry(after,"forest",tree_key)))
	expect(canon_bytes(processing_of(after,site_key))==canon_bytes(processing_of(state_before,site_key)),"frame: processing queue unchanged")
	assert_empty("after frame")
	expect(server.save_clock==0.0,"frame: periodic save reset its clock after a %.0f s frame"%OFFLINE_DT)
	expect(server.broadcast_clock>=0.0 and server.broadcast_clock<0.1,"frame: broadcast retains at most the fractional remainder of one interval")
	expect(FileAccess.get_file_as_string(save_path)==json_before,"frame: periodic save wrote exactly the unchanged state, byte for byte")
	expect(FileAccess.file_exists(save_path+".bak"),"frame: periodic save rotated the previous file to .bak")

## Soak mode step 2: wait N real seconds while engine physics frames drive the production
## Session (world.step(dt, false) + periodic saves). The test never calls _physics_process.
func soak(world_ref,live_before:PackedByteArray,canon_before:PackedByteArray,state_before:Dictionary,json_before:String)->bool:
	expect(server.is_physics_processing(),"soak: production Session physics processing is enabled")
	var mtime_before:=FileAccess.get_modified_time(save_path)
	var frames_before:=physics_frames
	var started:=Time.get_ticks_msec()
	var limit_ms:=wallclock_seconds*1000
	var next_beat:=HEARTBEAT_SECONDS
	var max_population:=0
	var first_drift_s:=-1
	while true:
		var elapsed_ms:=Time.get_ticks_msec()-started
		if elapsed_ms>=limit_ms:break
		await pause(clampf(float(limit_ms-elapsed_ms)/1000.0,0.01,1.0))
		if finished:return false # watchdog already cleaned up
		if server==null or not is_instance_valid(server) or server.world!=world_ref:
			return expect(false,"soak: Session and its World survived the real wait")
		max_population=maxi(max_population,server.peers.size()+server.pending.size())
		var elapsed_s:=int(float(Time.get_ticks_msec()-started)/1000.0)
		if elapsed_s>=next_beat:
			var same:=var_to_bytes(server.world.state)==live_before
			if not same and first_drift_s<0:first_drift_s=elapsed_s
			print("%s_HEARTBEAT elapsed_s=%d of=%d peers=%d pending=%d physics_frames=%d state_unchanged=%s"%[TAG,elapsed_s,wallclock_seconds,server.peers.size(),server.pending.size(),physics_frames-frames_before,str(same)])
			next_beat+=HEARTBEAT_SECONDS
	var waited_ms:=Time.get_ticks_msec()-started
	var frames:=physics_frames-frames_before
	print("%s_SOAK requested_s=%d waited_ms=%d physics_frames=%d max_peers_or_pending=%d"%[TAG,wallclock_seconds,waited_ms,frames,max_population])
	expect(waited_ms>=limit_ms,"soak: waited at least %d s of real wall-clock time (%d ms)"%[wallclock_seconds,waited_ms])
	expect(frames>=wallclock_seconds,"soak: engine ran real physics frames throughout (%d frames in %d s)"%[frames,wallclock_seconds])
	expect(server.is_physics_processing(),"soak: Session physics processing still enabled at the end")
	expect(max_population==0,"soak: no peer or pending connection at any 1 s sample")
	expect(first_drift_s<0,"soak: World state unchanged at every heartbeat (first drift at %d s)"%first_drift_s)
	expect(server.world==world_ref,"soak: same World instance")
	expect(server.world.step_error=="","soak: World.step reported no error")
	expect(var_to_bytes(server.world.state)==live_before,"soak: complete World state byte-for-byte unchanged (differing keys %s)"%str(differing_keys(state_before,server.world.state)))
	expect(canon_bytes(server.world.state)==canon_before,"soak: canonical World state unchanged")
	var after:Dictionary=server.world.state
	expect(float(after.time)==float(state_before.time),"soak: world time unchanged (%s)"%str(after.time))
	expect(int(after.committed)==int(state_before.committed),"soak: committed counter unchanged (%s)"%str(after.committed))
	expect(canon_bytes(entry(after,"crops",plot_key))==canon_bytes(entry(state_before,"crops",plot_key)),"soak: crop growth/wetness unchanged %s"%str(entry(after,"crops",plot_key)))
	expect(canon_bytes(entry(after,"forest",tree_key))==canon_bytes(entry(state_before,"forest",tree_key)),"soak: tree growth unchanged %s"%str(entry(after,"forest",tree_key)))
	expect(canon_bytes(processing_of(after,site_key))==canon_bytes(processing_of(state_before,site_key)),"soak: processing queue unchanged")
	assert_empty("after soak")
	expect(server.save_clock>=0.0 and server.save_clock<10.0,"soak: periodic save clock within its production cycle (%.3f)"%server.save_clock)
	if wallclock_seconds>=SOAK_SAVE_PROOF_MIN:
		expect(FileAccess.get_modified_time(save_path)>mtime_before,"soak: real periodic saves rewrote the save during the wait")
		expect(FileAccess.get_file_as_string(save_path)==json_before,"soak: periodic saves wrote exactly the unchanged state, byte for byte")
		expect(FileAccess.file_exists(save_path+".bak"),"soak: periodic save rotated the previous file to .bak")
	else:
		print("%s_SOAK periodic-save byte proof skipped: %d s < %d s"%[TAG,wallclock_seconds,SOAK_SAVE_PROOF_MIN])
	var persisted:=World.new()
	expect(persisted.load_world(save_path) and not persisted.recovered_from_backup,"soak: persisted save loads from the primary file while the server runs")
	persisted.save_path=""
	expect(canon_bytes(persisted.state)==canon_before,"soak: persisted save equals the pre-soak state (differing keys %s)"%str(differing_keys(state_before,persisted.state)))
	return true

func shutdown_and_restart(port:int,state_before:Dictionary,canon_before:PackedByteArray,json_before:String)->bool:
	# 3. Normal shutdown releases the server, the save lock and the port.
	if not expect(await stop_server(),"shutdown: final save succeeded"):return false
	expect(FileAccess.get_file_as_string(save_path)==json_before,"shutdown: final save byte-identical to the pre-frame state")
	var guard:=WriteGuard.new()
	expect(guard.acquire([save_path])==OK,"shutdown: writer lock released (a fresh guard can acquire it)")
	guard.release()

	# 4. Reload: plain World, then a restarted Session on the same port.
	var reloaded:=World.new()
	expect(reloaded.load_world(save_path) and not reloaded.recovered_from_backup,"reload: save loads from the primary file through SaveSchema")
	reloaded.save_path=""
	expect(canon_bytes(reloaded.state)==canon_before,"reload: complete state equals the pre-frame state (differing keys %s)"%str(differing_keys(state_before,reloaded.state)))
	var rehosted:=false
	for attempt in PORT_ATTEMPTS:
		if host_on(port)==OK:
			rehosted=true
			break
		await drop_branch()
		await pause(0.2)
	if not expect(rehosted,"restart: a new Session hosts the same save on the released port %d"%port):return false
	assert_empty("restart")
	expect(canon_bytes(server.world.state)==canon_before,"restart: Session loaded the unchanged state")
	if wallclock_seconds>0:
		await pause(RESTART_SOAK_WAIT)
		if finished:return false
		expect(server.is_physics_processing() and server.world!=null and server.peers.is_empty() and canon_bytes(server.world.state)==canon_before and server.world.step_error=="","restart: %.0f s of real engine physics frames on the empty restarted Session change nothing"%RESTART_SOAK_WAIT)
	else:
		server._physics_process(OFFLINE_DT)
		expect(canon_bytes(server.world.state)==canon_before and server.world.step_error=="","restart: a second empty %.0f s frame also changes nothing"%OFFLINE_DT)
	if not expect(await stop_server(),"restart: shutdown final save succeeded"):return false
	var final_world:=World.new()
	expect(final_world.load_world(save_path) and canon_bytes(final_world.state)==canon_before,"restart: final save still equals the pre-frame state")
	var guard2:=WriteGuard.new()
	expect(guard2.acquire([save_path])==OK,"restart: writer lock released after the second shutdown")
	guard2.release()
	return true

func teardown()->void:
	release_server()
	await drop_branch()

func remove_folder()->bool:
	if folder.is_empty() or not DirAccess.dir_exists_absolute(folder):return false
	if not folder.get_file().begins_with("offline-pause-"):return false
	for file in DirAccess.get_files_at(folder):
		if DirAccess.remove_absolute(folder.path_join(file))!=OK:
			print("%s could not remove %s"%[TAG,folder.path_join(file)])
			return false
	return DirAccess.remove_absolute(folder)==OK and not DirAccess.dir_exists_absolute(folder)
