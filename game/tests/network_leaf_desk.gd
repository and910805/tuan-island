extends SceneTree

const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const Industry=World.INDUSTRY
const SITE:=Vector2i(40,35)
const PASSWORD:="leaf-desk-test"
const GUEST_DRAFT:="別忘了帶相機。"
var session:Session
var role:String
var checks:=0
var failures:=0

func _initialize()->void:
	run.call_deferred()

func expect(success:bool,label:String)->bool:
	checks+=1
	if not success:
		failures+=1
		push_error(role+": "+label)
	return success

func wait_for(condition:Callable,label:String,seconds:=8.0)->bool:
	var deadline:=Time.get_ticks_msec()+int(seconds*1000)
	while not condition.call() and Time.get_ticks_msec()<deadline:
		await create_timer(0.03).timeout
	return expect(bool(condition.call()),label)

func draft_for(who:String)->String:
	return "渡口的草稿".repeat(24) if who=="owner" else GUEST_DRAFT

func token(who:String)->String:
	return "leaf-desk-network-"+who

func actor(who:String)->Dictionary:
	return session.snapshot.get("players",{}).get(Session._public_actor(token(who)),{})

func serve(port:int)->void:
	var path:="user://leaf-desk-net-%d.json"%OS.get_process_id()
	if not expect(session.host(port,"書桌多人驗收",path,PASSWORD,"127.0.0.1",true,"websocket")==OK,"Dedicated room starts"):return
	var world:World=session.world
	world.add_player(token("owner"),"桌主",Vector2(40.5,36.35))
	world.add_player(token("guest"),"朋友",Vector2(41.5,36.35))
	world.state.players[token("owner")].inventory.merge({"wood":14,"hardwood":4},true)
	for offset:Vector2i in [Vector2i.ZERO,Vector2i.RIGHT]:
		world.state.removed[World.key(SITE+offset)]=true
	expect(world.act(token("owner"),"fixture","build",SITE,Industry.LEAF_DESK).ok,"Server builds a genuine desk")
	if await wait_for(func():return session.peers.size()==2,"Both clients connect",15):
		await wait_for(func():return session.peers.is_empty(),"Both clients finish",24)
	expect(world.state.players[token("owner")].get(Industry.DESK_DRAFT_FIELD)==draft_for("owner") and world.state.players[token("guest")].get(Industry.DESK_DRAFT_FIELD)==GUEST_DRAFT,"Shared furniture stores two independent personal drafts")
	expect(world.state.get("island_notes",[]).is_empty(),"No public message was posted")
	expect(session.shutdown(),"The server saves cleanly")
	for suffix in ["",".bak",".writer-lock"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)

func exercise(port:int)->void:
	session.profile.token=token(role)
	if not expect(session.join("ws://127.0.0.1:%d"%port,port,role,PASSWORD)==OK,"Client connects"):return
	if not await wait_for(func():return not actor("owner").is_empty() and not actor("guest").is_empty(),"Both profiles are present"):return
	# Both clients stay connected until their own saved draft is visible. Every
	# emitted snapshot is checked, including those following the other save.
	var observed_other:=[false]
	var other:="guest" if role=="owner" else "owner"
	session.changed.connect(func(_snapshot:Dictionary,_own:String):
		if actor(other).has(Industry.DESK_DRAFT_FIELD):observed_other[0]=true)
	var expected:String=draft_for(role)
	session.perform(Industry.DESK_DRAFT_ACTION,SITE if role=="owner" else SITE+Vector2i.RIGHT,expected)
	if not await wait_for(func():return actor(role).get(Industry.DESK_DRAFT_FIELD)==expected,"Only the player snapshot acknowledges the stored text"):return
	await create_timer(0.85).timeout
	expect(not observed_other[0] and not actor(other).has(Industry.DESK_DRAFT_FIELD),"No snapshot exposes the other player's draft")
	expect(session.snapshot.get("island_notes",[]).is_empty(),"The public board remains empty")

func run()->void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=2 or args[0] not in ["owner","guest","server"]:
		quit(1)
		return
	role=args[0]
	var island:=Node2D.new()
	island.name="Island"
	root.add_child(island)
	session=Session.new()
	island.add_child(session)
	if role=="server":await serve(int(args[1]))
	else:
		await exercise(int(args[1]))
		session.shutdown()
	print("LEAF_DESK_NETWORK role=%s checks=%d failures=%d"%[role,checks,failures])
	quit(int(failures>0))
