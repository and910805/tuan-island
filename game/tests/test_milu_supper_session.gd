extends SceneTree
## N02-4 Milu supper invitations (World.MILU_SUPPER.ACTION) over a real loopback WebSocket server
## and two real client Sessions (alice, bob). Compact; conventions from test_bobo_cart_unlock_session.gd.
##
## LEVEL: one machine, ONE Godot process, 127.0.0.1 only, fresh TEMP save, no production data touched.
## SEEDED FIXTURE (disclosed, SaveSchema-validated): picnic=true, daytime; alice and bob each have Milu bond
## 24 points (stage 4) and stand near the common table (cell/stands from a probe World that went through
## save -> load like the server); alice holds 4 corn_chowder, bob holds none; no bond_goals, no milu_supper.
## PLAYED over the network: serve_chowder, claim_chowder, milu_supper_invite toggles, resident_goal "milu:4::",
## client disconnect + rejoin.
## Fixture relocations (server world writes): alice stands by Milu for the hand-in, then returns to the table.
## NOT covered: multiple processes, TLS, latency/loss, UI.
const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const Schema=preload("res://scripts/save_schema.gd")
const Goals=preload("res://scripts/resident_goals.gd")
const Supper=preload("res://scripts/milu_supper.gd")
const COMMUNITY=preload("res://scripts/community.gd")
const KEY:="milu-supper-session"
const ALICE:="milu-supper-alice-token"
const BOB:="milu-supper-bob-token"
const DISH:="corn_chowder"
const START_TIME:=2.0*1440.0+300.0
const HALF:=Vector2(0.5,0.5)

class Client:
	var label:=""
	var branch:Node
	var session
	var notices:Array=[]
	func on_notice(message:String,success:bool)->void:
		notices.append([message,success])
	func me()->Dictionary:
		var people=session.snapshot.get("players",{})
		if not people is Dictionary or session.own_id.is_empty():return {}
		return people.get(session.own_id,{})
	func bag()->Dictionary:
		var inv=me().get("inventory",{})
		return inv if inv is Dictionary else {}
	func own_supper()->Dictionary:
		var v=session.snapshot.get(Supper.VIEW_KEY,null)
		return v if v is Dictionary else {}
	func portions()->int:
		return int(session.snapshot.get("community",{}).get("chowder",{}).get("portions",-1))

var checks:=0
var failures:=0
var serial:=0
var folder:=""
var save_path:=""
var server
var server_branch:Node
var finished:=false
var table:=Vector2i.ZERO
var milu_cell:=Vector2i.ZERO
var alice_stand:=Vector2.ZERO
var bob_stand:=Vector2.ZERO
var milu_stand:=Vector2.ZERO
var alice:Client
var bob:Client

func expect(ok:bool,label:String)->bool:
	checks+=1
	if not ok:
		failures+=1
		push_error("FAIL "+label)
	return ok

func _initialize()->void:
	create_timer(100.0,true,false,true).timeout.connect(_watchdog)
	run.call_deferred()

func _watchdog()->void:
	if finished:return
	finished=true
	print("MILU_SUPPER_SESSION watchdog fired before completion")
	print("MILU_SUPPER_SESSION_TESTS checks=%d failures=%d"%[checks,failures+1])
	quit(1)

func run()->void:
	var completed:=await scenario()
	expect(completed,"scenario ran to completion")
	await teardown()
	if failures==0 and completed:expect(remove_folder(),"temp fixture folder removed")
	else:print("MILU_SUPPER_SESSION kept temp folder: %s"%folder)
	if finished:return
	finished=true
	print("MILU_SUPPER_SESSION_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0 or checks==0))

# ---------------------------------------------------------------- fixture --

static func stand_near(w,cell:Vector2i,skip:Vector2=Vector2.INF)->Vector2:
	for off:Vector2 in [Vector2(0.5,1.5),Vector2(1.5,1.5),Vector2(-0.5,1.5),Vector2(1.5,0.5),Vector2(-0.5,0.5),Vector2(0.5,-0.5)]:
		var at:Vector2=Vector2(cell)+off
		if at!=skip and w.can_stand(at):return at
	return Vector2.ZERO

func seed_world(path:String,with_people:bool)->bool:
	var w:=World.new()
	w.save_path=path
	w.state["picnic"]=true
	w.state["time"]=START_TIME
	if with_people:
		for spec:Array in [[ALICE,"alice",alice_stand,4],[BOB,"bob",bob_stand,0]]:
			w.add_player(spec[0],spec[1])
			var p:Dictionary=w.state.players[spec[0]]
			p["x"]=(spec[2] as Vector2).x
			p["y"]=(spec[2] as Vector2).y
			p["bonds"]={"milu":{"points":24,"talk_day":-1,"gift_day":-1}}
			p["inventory"][DISH]=int(spec[3])
			p.erase("bond_goals")
	w.active_tokens.clear()
	if not w.save():return false
	var parsed=JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed is Dictionary and Schema.validate(parsed,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)

func plan()->bool:
	var probe:=folder.path_join("probe.json")
	if not expect(seed_world(probe,false),"probe fixture saved"):return false
	var w:=World.new()
	if not expect(w.load_world(probe),"probe fixture loads like the server's save"):return false
	table=COMMUNITY.table_cell(w.state)
	var place:Array=World.bond_place(w.state,"milu")
	milu_cell=place[1]
	if not expect(table!=COMMUNITY.NO_CELL and str(place[0])=="home","common table placed and Milu lives in home"):return false
	alice_stand=stand_near(w,table)
	bob_stand=stand_near(w,table,alice_stand)
	milu_stand=stand_near(w,milu_cell)
	return expect(alice_stand!=Vector2.ZERO and bob_stand!=Vector2.ZERO and milu_stand!=Vector2.ZERO,"standable cells near table and Milu")

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
	for attempt in 8:
		var port:=randi_range(31000,58000)
		if server.host(port,"",save_path,KEY,"127.0.0.1",true,"websocket")==OK:return port
	return 0

func join(label:String,token:String,port:int)->Client:
	var c:=Client.new()
	c.label=label
	c.branch=new_branch("Client_%s_"%label)
	c.session=Session.new()
	c.branch.add_child(c.session)
	c.session.profile["token"]=token
	c.session.notice.connect(c.on_notice)
	if c.session.join("ws://127.0.0.1:%d"%port,port,label,KEY)!=OK:return c
	await wait_until(func():return joined(c),8.0)
	return c

func joined(c:Client)->bool:
	return c!=null and not c.session.own_id.is_empty() and not c.me().is_empty() and c.session.snapshot.has(Supper.VIEW_KEY)

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
	await create_timer(seconds,true,false,true).timeout

func act(c:Client,action:String,p:Vector2i,extra:String="")->Dictionary:
	await pause(0.15) # session rate limit
	var before:=c.notices.size()
	c.session.perform(action,p,extra)
	if not await wait_until(func():return c.notices.size()>before,4.0):return {"replied":false,"ok":false,"message":""}
	var reply:Array=c.notices[before]
	return {"replied":true,"ok":bool(reply[1]),"message":str(reply[0])}

func invite(c:Client,id:String)->Dictionary:
	return await act(c,Supper.ACTION,table,id)

func guests_are(c:Client,want:Array)->bool:
	return c.own_supper().get("guests",null)==want

## Wait for the invite to show up in the owner's private view (snapshot follows the reply).
func settle(c:Client,want:Array)->bool:
	return await wait_until(func():return guests_are(c,want),3.0)

func no_leak(c:Client,label:String)->void:
	var people=c.session.snapshot.get("players",{})
	var leaked:=false
	for id in people:
		if people[id] is Dictionary and people[id].has(Supper.KEY):leaked=true
	expect(not leaked,"%s: no player carries a '%s' field in %s's snapshot"%[label,Supper.KEY,c.label])
	var dump:=JSON.stringify(c.session.snapshot)
	expect(not dump.contains(ALICE) and not dump.contains(BOB),"%s: %s's snapshot has no raw token"%[label,c.label])

# --------------------------------------------------------------- scenario --

func scenario()->bool:
	folder=OS.get_environment("TEMP").path_join("milu-supper-session-%s"%Crypto.new().generate_random_bytes(8).hex_encode())
	if not expect(DirAccess.make_dir_recursive_absolute(folder)==OK,"temp folder created"):return false
	save_path=folder.path_join("world.json")
	if not plan():return false
	if not expect(seed_world(save_path,true),"SEEDED FIXTURE (picnic, milu bond 24 for both, alice 4 corn_chowder) accepted by SaveSchema"):return false
	var port:=start_server()
	if not expect(port>0,"server Session hosts on 127.0.0.1 (websocket)"):return false
	alice=await join("alice",ALICE,port)
	bob=await join("bob",BOB,port)
	if not expect(joined(alice) and joined(bob),"alice and bob joined over loopback"):return false
	expect(server.multiplayer.multiplayer_peer is WebSocketMultiplayerPeer and alice.session.world==null,"websocket transport, client holds no World")
	print("MILU_SUPPER_SESSION_LABEL fixture=SEEDED-LOCAL process=single transport=websocket loopback=127.0.0.1:%d public-service=none teleport=alice-milu-and-table"%port)

	# 1. Before serving: nobody can invite; nothing is stored.
	var early:=await invite(alice,"aru")
	expect(early.replied and not early.ok and early.message==Supper.NOT_SERVED,"1 alice cannot invite before she serves ('%s')"%early.message)
	expect(alice.own_supper()=={"dish":"","guests":[]} and bob.own_supper()=={"dish":"","guests":[]},"1 both private views start empty")

	# 2. Alice serves 4 via the actual request; Bob only sees portions.
	var served:=await act(alice,"serve_chowder",table)
	expect(served.replied and served.ok,"2 alice's serve_chowder succeeds ('%s')"%served.message)
	await wait_until(func():return alice.own_supper().get("dish","")==DISH and bob.portions()==4,4.0)
	expect(int(alice.bag().get(DISH,0))==0 and alice.portions()==4,"2 alice's 4 bowls left her bag for 4 table portions (bag %s, portions %d)"%[str(alice.bag().get(DISH,0)),alice.portions()])
	expect(alice.own_supper()=={"dish":DISH,"guests":[]},"2 alice's own_milu_supper remembers the actual dish (%s)"%str(alice.own_supper()))
	expect(bob.portions()==4,"2 bob sees only the public portions (%d)"%bob.portions())
	expect(bob.own_supper()=={"dish":"","guests":[]},"2 bob's own_milu_supper does not carry alice's dish (%s)"%str(bob.own_supper()))
	no_leak(alice,"2")
	no_leak(bob,"2")

	# 3. Bob claims his single portion but cannot invite until he serves.
	var claim:=await act(bob,"claim_chowder",table)
	expect(claim.replied and claim.ok,"3 bob's claim_chowder succeeds ('%s')"%claim.message)
	await wait_until(func():return int(bob.bag().get(DISH,0))==1,3.0)
	expect(int(bob.bag().get(DISH,0))==1 and bob.portions()==3,"3 bob holds exactly one portion; 3 left on the table")
	var bob_invite:=await invite(bob,"aru")
	expect(bob_invite.replied and not bob_invite.ok and bob_invite.message==Supper.NOT_SERVED,"3 bob cannot invite until he serves ('%s')"%bob_invite.message)
	expect(bob.own_supper()=={"dish":"","guests":[]},"3 bob's private list stays empty")
	await pause(0.3)
	expect(guests_are(alice,[]),"3 alice's list is untouched by bob")

	# 4. Alice personally invites two; overcapacity and bad ids refused; toggling works.
	var bad:=await invite(alice,"milu")
	expect(bad.replied and not bad.ok and bad.message==Supper.BAD_GUEST,"4 a non-invitee id is refused ('%s')"%bad.message)
	var first:=await invite(alice,"aru")
	expect(first.replied and first.ok and await settle(alice,["aru"]),"4 alice invites aru ('%s')"%first.message)
	var second:=await invite(alice,"xiaoli")
	expect(second.replied and second.ok and await settle(alice,["aru","xiaoli"]),"4 alice invites xiaoli ('%s')"%second.message)
	var over:=await invite(alice,"lingpopo")
	expect(over.replied and not over.ok and over.message==Supper.FULL,"4 a third guest is refused as over capacity ('%s')"%over.message)
	await pause(0.3)
	expect(guests_are(alice,["aru","xiaoli"]),"4 list still [aru, xiaoli] after the refusal")
	var off:=await invite(alice,"xiaoli")
	expect(off.replied and off.ok and await settle(alice,["aru"]),"4 inviting xiaoli again toggles her off ('%s')"%off.message)
	var swap:=await invite(alice,"lingpopo")
	expect(swap.replied and swap.ok and await settle(alice,["aru","lingpopo"]),"4 lingpopo takes the freed seat ('%s')"%swap.message)
	expect(bob.own_supper()=={"dish":"","guests":[]},"4 bob never sees alice's guests")
	no_leak(bob,"4")

	# 5. Hand-in near Milu with the actual request (disclosed fixture teleport for alice).
	var far:=await act(alice,Goals.ACTION,milu_cell,"milu:4::")
	expect(far.replied and not far.ok,"5 hand-in from the table is refused while out of reach of Milu ('%s')"%far.message)
	server.world.state.players[ALICE].x=milu_stand.x # FIXTURE TELEPORT (disclosed)
	server.world.state.players[ALICE].y=milu_stand.y
	await wait_until(func():return Vector2(float(alice.me().get("x",-99.0)),float(alice.me().get("y",-99.0))).distance_to(milu_stand)<0.1,3.0)
	var done:=await act(alice,Goals.ACTION,milu_cell,"milu:4::")
	expect(done.replied and done.ok,"5 alice's actual milu:4:: hand-in succeeds ('%s')"%done.message)
	await pause(0.3)

	# 6. Edits are frozen afterwards; the record is intact.
	server.world.state.players[ALICE].x=alice_stand.x
	server.world.state.players[ALICE].y=alice_stand.y
	expect(await wait_until(func():return Vector2(float(alice.me().get("x",-99.0)),float(alice.me().get("y",-99.0))).distance_to(alice_stand)<0.1,3.0),"6 alice is back at the table")
	var frozen:=await invite(alice,"xiaoli")
	expect(frozen.replied and not frozen.ok and frozen.message==Supper.NOT_OPEN,"6 alice cannot edit after completion ('%s')"%frozen.message)
	var frozen_off:=await invite(alice,"aru")
	expect(frozen_off.replied and not frozen_off.ok,"6 alice cannot remove a guest after completion ('%s')"%frozen_off.message)
	expect(alice.own_supper()=={"dish":DISH,"guests":["aru","lingpopo"]},"6 alice's view is unchanged (%s)"%str(alice.own_supper()))

	# 7. Reconnect: private dish and guest list come back for alice only.
	await leave(alice)
	alice=await join("alice",ALICE,port)
	if not expect(joined(alice),"7 alice rejoins"):return false
	expect(alice.own_supper()=={"dish":DISH,"guests":["aru","lingpopo"]},"7 reconnected alice retrieves her dish and guests (%s)"%str(alice.own_supper()))
	expect(bob.own_supper()=={"dish":"","guests":[]},"7 bob still sees an empty private view")
	no_leak(alice,"7")
	no_leak(bob,"7")
	return true

func teardown()->void:
	for c in [alice,bob]:
		if c!=null and is_instance_valid(c.session) and not c.session.shutting_down:c.session.shutdown()
	await pause(0.2)
	if server!=null and is_instance_valid(server) and server.world!=null:
		expect(server.shutdown(),"final server shutdown saves cleanly")
	await pause(0.2)
	for c in [alice,bob]:
		if c!=null and is_instance_valid(c.branch):c.branch.queue_free()
	if is_instance_valid(server_branch):server_branch.queue_free()
	await process_frame

func remove_folder()->bool:
	if folder.is_empty() or not DirAccess.dir_exists_absolute(folder):return false
	var dir:=DirAccess.open(folder)
	if dir==null:return false
	for file in dir.get_files():
		if DirAccess.remove_absolute(folder.path_join(file))!=OK:return false
	return DirAccess.remove_absolute(folder)==OK and not DirAccess.dir_exists_absolute(folder)
