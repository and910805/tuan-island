extends SceneTree

const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const Frame=World.BARK_FRAME
const KIND:=World.WALL_FIXTURES.BARK_FRAME
const SITE:=Vector2i(42,35)
const SIGN_SITE:=Vector2i(43,35)
const BOARD_SITE:=Vector2i(40,35)
const SIGN_TEXT:=["木工的小屋","請進來坐坐。","歡迎帶朋友一起來。"]
const PASSWORD:="bark-frame-test"
var session:Session
var role:String
var checks:=0
var failures:=0
var replies:Array[bool]=[]

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

func token(who:String)->String:
	return "bark-frame-network-"+who

func actor(who:String)->Dictionary:
	return session.snapshot.get("players",{}).get(Session._public_actor(token(who)),{})

func object()->Dictionary:
	return session.snapshot.get("objects",{}).get(World.key(SITE),{})

func photo()->String:
	var fixture:=Image.create_empty(48,30,false,Image.FORMAT_RGB8)
	fixture.fill(Color("6ea26b"))
	fixture.fill_rect(Rect2i(10,10,20,11),Color("d6886e"))
	return Frame.from_image(fixture)

func send(value:String,success:bool,action:=Frame.ACTION,tile:=SITE)->bool:
	var reply:=replies.size()
	session.perform(action,tile,value)
	if not await wait_for(func():return replies.size()>reply,"Action receives a reply"):return false
	return expect(replies[reply]==success,"Reply enforces expected access")

func sign_visible()->bool:
	var plaque:Dictionary=session.snapshot.get("objects",{}).get(World.key(SIGN_SITE),{})
	return plaque.get("welcome")==SIGN_TEXT and plaque.get("author")=="畫框主人"

func tool_board_visible()->bool:
	var board:Dictionary=session.snapshot.get("objects",{}).get(World.key(BOARD_SITE),{})
	return board.get(World.WALL_FIXTURES.TOOL_BOARD_FIELD)==["axe","fish"]

func serve(port:int)->void:
	var path:="user://bark-frame-network-%d.json"%OS.get_process_id()
	if not expect(session.host(port,"畫框多人驗收",path,PASSWORD,"127.0.0.1",true,"websocket")==OK,"Dedicated WebSocket server starts"):return
	var world:World=session.world
	world.add_player(token("owner"),"畫框主人",Vector2(42.5,36.1))
	world.add_player(token("guest"),"來訪居民",Vector2(43.5,36.1))
	var builder:Dictionary=world.state.players[token("owner")]
	builder.inventory.merge({"wood":60,"resin":2,"copper_ingot":2},true)
	world.state.removed[World.key(SITE)]=true
	world.state.removed[World.key(SITE+Vector2i.UP)]=true
	expect(world.act(token("owner"),"support","build",SITE+Vector2i.UP,"wall").ok,"Real wall construction")
	expect(not world.act(token("owner"),"frame-locked","build",SITE,KIND).ok,"Frame construction is refused before the owner finishes Diandian 2")
	# FIXTURE: the owner's own finished Diandian 2 (frame construction requirement); the guest has none.
	builder.bonds={"diandian":{"points":10,"talk_day":-1,"gift_day":-1}}
	builder.bond_goals={"diandian":{"1":"","2":"knees"}}
	expect(world.act(token("owner"),"frame","build",SITE,KIND).ok,"Real supported frame construction")
	world.state.removed[World.key(SIGN_SITE)]=true
	world.state.removed[World.key(SIGN_SITE+Vector2i.UP)]=true
	expect(world.act(token("owner"),"sign-support","build",SIGN_SITE+Vector2i.UP,"wall").ok,"The sign has a separate supporting wall")
	expect(world.act(token("owner"),"sign","build",SIGN_SITE,World.WALL_FIXTURES.HOME_SIGN).ok,"Real supported sign construction")
	builder.x=40.5
	for tile:Vector2i in [BOARD_SITE,BOARD_SITE+Vector2i.RIGHT]:
		world.state.removed[World.key(tile)]=true
		world.state.removed[World.key(tile+Vector2i.UP)]=true
		var placed:=world.act(token("owner"),"rack-wall-%d"%tile.x,"build",tile+Vector2i.UP,"wall")
		expect(placed.ok,"Supporting wall %s: %s"%[str(tile),placed.message])
	expect(world.act(token("owner"),"rack","build",BOARD_SITE,World.WALL_FIXTURES.TOOL_BOARD).ok,"Both halves of the tool board are placed")
	builder.x=42.5
	if await wait_for(func():return session.peers.size()==2,"Both clients connect",15):
		await wait_for(func():return session.peers.is_empty(),"Both clients complete",30)
	expect(not world.state.objects[World.key(SITE)].has(Frame.FIELD),"Confirmed clear leaves the authoritative frame empty")
	expect(session.shutdown(),"Server saves cleanly")
	for suffix in ["",".bak",".writer-lock"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)

func exercise(port:int)->void:
	session.profile.token=token(role)
	session.notice.connect(func(_message:String,success:bool):replies.append(success))
	if not expect(session.join("ws://127.0.0.1:%d"%port,port,role,PASSWORD)==OK,"WebSocket client connects"):return
	if not await wait_for(func():return object().get("type")==KIND and not actor("guest").is_empty(),"Visible frame and other actor"):return
	var expected:=photo()
	if role=="owner":
		if not await send("0:axe",true,World.WALL_FIXTURES.TOOL_BOARD_WRITE,BOARD_SITE):return
		if not await send("1:fish",true,World.WALL_FIXTURES.TOOL_BOARD_WRITE,BOARD_SITE+Vector2i.RIGHT):return
		if not await wait_for(tool_board_visible,"Owner receives both display choices"):return
		if not await send(JSON.stringify(SIGN_TEXT),true,World.WELCOME_SIGN.WRITE,SIGN_SITE):return
		if not await wait_for(sign_visible,"Owner receives the name and author after writing"):return
		if not await send(expected,true):return
		if not await wait_for(func():return object().get(Frame.FIELD)==expected,"Round trip preserves every pixel"):return
		if not await wait_for(func():return float(actor("guest").get("y",0))>36.4,"Visitor checked that the display is read-only"):return
		if not await send("",true):return
		await wait_for(func():return not object().has(Frame.FIELD) and actor("guest").is_empty(),"Owner sees clear and guest completion")
	else:
		if not await wait_for(func():return object().get(Frame.FIELD)==expected,"Guest receives the same mounted image"):return
		if not await wait_for(tool_board_visible,"Guest receives the same two tool silhouettes"):return
		if not await send("0:water",false,World.WALL_FIXTURES.TOOL_BOARD_WRITE,BOARD_SITE+Vector2i.RIGHT):return
		expect(tool_board_visible(),"Rejected visitor edit leaves both tools intact")
		if not await wait_for(sign_visible,"Guest receives the nameplate author and text"):return
		if not await send(JSON.stringify(["想換名字","",""]),false,World.WELCOME_SIGN.WRITE,SIGN_SITE):return
		expect(sign_visible(),"Rejected edit leaves the nameplate intact")
		if not await send("",false):return
		expect(object().get(Frame.FIELD)==expected,"Rejected request does not alter the display")
		session.input_direction(Vector2.DOWN)
		if not await wait_for(func():return float(actor("guest").get("y",0))>36.4,"Confirms denied edit before the owner clears"):return
		session.input_direction(Vector2.ZERO)
		await wait_for(func():return not object().has(Frame.FIELD),"Owner clearing artwork is synchronized")

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
	print("BARK_FRAME_NETWORK role=%s checks=%d failures=%d"%[role,checks,failures])
	quit(int(failures>0))
