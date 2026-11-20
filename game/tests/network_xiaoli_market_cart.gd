extends SceneTree

const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const Cart:=World.INDUSTRY
const SITE:=Vector2i(40,34)
const MOVED:=Vector2i(43,34)
const PASSWORD:="market-cart-test"
var session:Session
var role:String
var checks:=0
var failures:=0
var notices:Array[bool]=[]

func _initialize()->void:
	run.call_deferred()

func expect(ok:bool,message:String)->bool:
	checks+=1
	if ok:return true
	failures+=1
	push_error(role+": "+message)
	return false

func wait_for(condition:Callable,message:String,seconds:=7.0)->bool:
	var deadline:=Time.get_ticks_msec()+int(seconds*1000)
	while not condition.call() and Time.get_ticks_msec()<deadline:
		await create_timer(0.025).timeout
	return expect(bool(condition.call()),message)

func actor(which:String)->Dictionary:
	return session.snapshot.get("players",{}).get(Session._public_actor(token(which)),{})

func token(which:String)->String:
	return "market-cart-network-"+which

func request(verb:String,tile:Vector2i,extra:String,expected:bool)->bool:
	var target:=notices.size()
	session.perform(verb,tile,extra)
	if not await wait_for(func():return notices.size()>target,"Receives an action result"):return false
	return expect(notices[target]==expected,"Action result matches server rules")

func cart(at:=SITE)->Dictionary:
	return session.snapshot.get("objects",{}).get(World.key(at),{})

func serve(port:int)->void:
	var path:="user://market-cart-network-%d.json"%OS.get_process_id()
	if not expect(session.host(port,"攤車連線驗收",path,PASSWORD,"127.0.0.1",true,"websocket")==OK,"Starts a dedicated WebSocket server"):return
	var world:World=session.world
	for which:String in ["alpha","beta"]:
		world.add_player(token(which),which,Vector2(41.5,33.5 if which=="alpha" else 32.5))
	var host:Dictionary=world.state.players[token("alpha")]
	host.inventory.merge({"wood":24,"copper_ingot":4,"cotton_cloth":4,"radish":8},true)
	world.state.picnic=true
	world.state.time=720.0
	for origin:Vector2i in [SITE,MOVED]:
		for offset:Vector2i in Cart.SQUARE_CELLS:world.state.removed[World.key(origin+offset)]=true
	if not expect(world.act(token("alpha"),"setup-cart","build",SITE,Cart.COAST_CART).ok,"Builds the cart using normal construction"):return
	if await wait_for(func():return session.peers.size()==2,"Two distinct clients connect",15.0):
		var observed:=func():return bool(host.get("market",{}).get("pending",false)) and float(world.state.players[token("beta")].y)<32.25
		if await wait_for(observed,"Guest confirmed the open cart before the accelerated midnight"):
			world.state.time=World.WEATHER.DAY_SECONDS-0.05
		await wait_for(func():return session.peers.is_empty(),"Both clients finish and disconnect",15.0)
	expect(session.shutdown(),"Server closes and saves cleanly")
	for suffix:String in ["",".bak",".writer-lock"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)

func exercise(port:int)->void:
	session.profile.token=token(role)
	session.notice.connect(func(_message:String,success:bool):notices.append(success))
	if not expect(session.join("ws://127.0.0.1:%d"%port,port,role,PASSWORD)==OK,"Starts a WebSocket connection"):return
	if not await wait_for(func():return not actor("alpha").is_empty() and not actor("beta").is_empty(),"Both players are visible"):return
	if role=="alpha":
		if not await request("market_stock",SITE+Vector2i.RIGHT,"radish:5",true):return
		if not await request("market_open",SITE,"",true):return
		if not await request("move_object",SITE,World.key(MOVED),false):return
		if not await wait_for(func():return not cart().get("market_cart_open",false) and int(session.snapshot.own_market.till)>0,"Midnight closes the cart and credits sales"):return
		if not await request("move_object",SITE+Vector2i.RIGHT,World.key(MOVED),true):return
		if not await request("market_collect",MOVED+Vector2i.RIGHT,"",true):return
		await wait_for(func():return cart().is_empty() and cart(MOVED).get("type")==Cart.COAST_CART and int(session.snapshot.own_market.till)==0,"Collecting preserves the moved cart and empties the till")
	else:
		if not await wait_for(func():return cart().get("market_cart_goods",[])==["radish"],"Guest sees visual goods on the open cart"):return
		expect(cart().items.is_empty() and not actor("alpha").has("market") and session.snapshot.own_market.stock.is_empty(),"Guest sees only public goods, not the other player's stock quantities")
		if not await request("market_take",SITE+Vector2i.RIGHT,"radish:1",false):return
		session.input_direction(Vector2.UP)
		if not await wait_for(func():return float(actor("beta").get("y",0.0))<32.25,"Guest walks away after viewing the open cart"):return
		session.input_direction(Vector2.ZERO)
		await wait_for(func():return cart().is_empty() and cart(MOVED).get("type")==Cart.COAST_CART,"Guest sees the same four-tile cart at its new position")
	session.shutdown()

func run()->void:
	var args:=OS.get_cmdline_user_args()
	if args.size()!=2 or args[0] not in ["server","alpha","beta"]:
		quit(1)
		return
	role=args[0]
	var island:=Node2D.new()
	island.name="Island"
	root.add_child(island)
	session=Session.new()
	island.add_child(session)
	if role=="server":await serve(int(args[1]))
	else:await exercise(int(args[1]))
	print("MARKET_CART_NETWORK_TESTS role=%s checks=%d failures=%d"%[role,checks,failures])
	quit(int(failures>0))
