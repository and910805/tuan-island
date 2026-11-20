extends SceneTree

const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const Mail=World.MUSHROOM_MAIL
const KIND:=World.INDUSTRY.MUSHROOM_POST
const SITE:=Vector2i(42,35)
const PASSWORD:="mushroom-mail-fixture"
var session:Session
var role:String
var checks:=0
var failures:=0
var notices:Array[bool]=[]

func _initialize()->void:
	run.call_deferred()

func expect(success:bool,label:String)->bool:
	checks+=1
	if not success:
		failures+=1
		push_error(role+": "+label)
		return false
	return true

func wait_for(condition:Callable,label:String,seconds:=8.0)->bool:
	var deadline:=Time.get_ticks_msec()+int(seconds*1000)
	while not condition.call() and Time.get_ticks_msec()<deadline:
		await create_timer(0.03).timeout
	return expect(bool(condition.call()),label)

func token(who:String)->String:
	return "mushroom-post-network-"+who

func actor(who:String)->Dictionary:
	return session.snapshot.get("players",{}).get(Session._public_actor(token(who)),{})

func serve(port:int)->void:
	var path:="user://mushroom-mail-net-%d.json"%OS.get_process_id()
	if not expect(session.host(port,"郵箱多人驗收",path,PASSWORD,"127.0.0.1",true,"websocket")==OK,"Dedicated room starts"):return
	var world:World=session.world
	var positions:=[SITE,SITE+Vector2i.RIGHT]
	var people:=["owner","guest"]
	for index in people.size():
		var who:String=people[index]
		var tile:Vector2i=positions[index]
		world.add_player(token(who),who,Vector2(tile)+Vector2(0.5,1.4))
		world.state.players[token(who)].inventory.merge({"wood":10,"copper_ingot":2,"radish_seed":0,"wheat_seed":0},true)
		world.state.removed[World.key(tile)]=true
		expect(world.act(token(who),"box","build",tile,KIND).ok,"Build real mailbox for "+who)
	if await wait_for(func():return session.peers.size()==2,"Two separate clients connect",15):
		await wait_for(func():return session.peers.is_empty(),"Both clients finish",28)
	for who:String in people:
		var player:Dictionary=world.state.players[token(who)]
		expect(player.get(Mail.RECORD,{})=={Mail.ARRIVAL:"claimed"} and player.inventory.radish_seed==3 and player.inventory.wheat_seed==2,"Server has exactly one parcel for "+who)
	expect(session.shutdown(),"Server saves cleanly")
	for suffix in ["",".bak",".writer-lock"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)

func exercise(port:int)->void:
	session.profile.token=token(role)
	session.notice.connect(func(_text:String,success:bool):notices.append(success))
	if not expect(session.join("ws://127.0.0.1:%d"%port,port,role,PASSWORD)==OK,"Client connects"):return
	if not await wait_for(func():return not actor("owner").is_empty() and not actor("guest").is_empty(),"Both players are visible"):return
	var place:=SITE if role=="owner" else SITE+Vector2i.RIGHT
	var another:=SITE+Vector2i.RIGHT if role=="owner" else SITE
	expect(session.snapshot.get("own_mushroom_mail",{}).get(Mail.ARRIVAL)=="new","Recipient starts with their own unread letter")
	session.perform(Mail.CLAIM,another,Mail.ARRIVAL)
	session.perform(Mail.CLAIM,place,Mail.ARRIVAL)
	session.perform(Mail.CLAIM,place,Mail.ARRIVAL)
	if not await wait_for(func():return notices.size()>=3,"Foreign, first claim and duplicate all receive replies"):return
	expect(notices.slice(0,3)==[false,true,false],"Server only accepts the first claim at the player's own mailbox")
	if not await wait_for(func():return session.snapshot.get("own_mushroom_mail",{}).get(Mail.ARRIVAL)=="claimed","Receipt is in the recipient's snapshot"):return
	var other:="guest" if role=="owner" else "owner"
	expect(not actor(other).has(Mail.RECORD) and not actor(role).has(Mail.RECORD),"Private storage details are not broadcast")
	var own:Dictionary=actor(role).get("inventory",{})
	expect(own.get("radish_seed")==3 and own.get("wheat_seed")==2,"Client inventory contains exactly one parcel")
	await create_timer(0.65).timeout

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
	print("MUSHROOM_MAIL_NETWORK role=%s checks=%d failures=%d"%[role,checks,failures])
	quit(int(failures>0))
