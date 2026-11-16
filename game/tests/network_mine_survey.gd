extends SceneTree

const Session=preload("res://scripts/session.gd")
const World=preload("res://scripts/world.gd")
const ROOM:="mine-survey-test"
const TOKEN_PREFIX:="mine-survey-net-"
var session:Session
var receipts:Array[Dictionary]=[]

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	var args:=OS.get_cmdline_user_args()
	if args[0]=="seed":
		var world:=World.new()
		world.save_path=args[1]
		world.state.mine_depths.unlocked=5
		world.state.mine_depths.pumped=24
		for role:String in ["alpha","beta"]:
			var token:=TOKEN_PREFIX+role
			world.add_player(token,role)
			var player:Dictionary=world.state.players[token]
			player.region="mine_1"
			player.x=16.5
			player.y=12.5
		world.state.mine_survey.players[TOKEN_PREFIX+"alpha"]={"seen":{"2":true,"3":true,"4":true,"5":true},"claimed":false}
		quit(0 if world.save() else 1)
		return
	var island:=Node.new()
	island.name="Island"
	root.add_child(island)
	session=Session.new()
	island.add_child(session)
	var role:=args[2]
	var alpha:=role=="alpha"
	session.profile.token=TOKEN_PREFIX+role
	if session.join("127.0.0.1",int(args[1]),role,ROOM)!=OK:
		finish(false,"join start")
		return
	if not await until(func():return not session.own_id.is_empty(),5):
		finish(false,"join snapshot")
		return
	session.notice.connect(func(message:String,ok:bool):receipts.append({"message":message,"ok":ok}))
	if args[0]=="start":
		if not await until(func():return session.snapshot.players.size()==2,5):
			finish(false,"both clients present")
			return
		var expected:Dictionary={"2":true,"3":true,"4":true,"5":true} if alpha else {}
		if record()!= {"seen":expected,"claimed":false}:
			finish(false,"initial progress privacy")
			return
		if not alpha and not await action("survey_observe",World.MINE_SURVEY.POINTS[1],"alpha",false):
			finish(false,"foreign observation identity rejected")
			return
		if not await action("survey_observe",World.MINE_SURVEY.POINTS[1],"",true):
			finish(false,"observe receipt")
			return
		expected["1"]=true
		if not await until(func():return record()=={"seen":expected,"claimed":false},3):
			finish(false,"personal observation snapshot")
			return
		if not await walk_to(Vector2(12.5,20.5)) or not await action("mine_travel",World.MINES.UP,"jinguashi",true):
			finish(false,"walk to ascent and exit")
			return
		if not await until(func():return session.snapshot.get("region_id")=="jinguashi",3):
			finish(false,"exit snapshot")
			return
		var table:Vector2i=World.BOBO_WORKSHOP.sites(session.snapshot).table
		if not await walk_to(Vector2(table)+Vector2(1.5,0.5)):
			finish(false,"walk to workshop")
			return
		if not alpha and not await action("survey_claim",table,"alpha",false):
			finish(false,"foreign claim identity rejected")
			return
		if not await action("survey_claim",table,"",alpha):
			finish(false,"only complete player may claim")
			return
	var final_seen:Dictionary={"1":true,"2":true,"3":true,"4":true,"5":true} if alpha else {"1":true}
	if not await until(func():return record()=={"seen":final_seen,"claimed":alpha} and int(person().inventory.get("gold_sample",0))==int(alpha),3):
		finish(false,"final progress and inventory")
		return
	if args[0]=="reconnect":
		var table:Vector2i=World.BOBO_WORKSHOP.sites(session.snapshot).table
		if not await action("survey_claim",table,"",false):
			finish(false,"duplicate or incomplete claim rejected after restart")
			return
	finish(true,"%s %s"%[args[0],role])

func record() -> Dictionary:
	return session.snapshot.get("mine_survey",{}).get("own_record",{})

func person() -> Dictionary:
	return session.snapshot.players[session.own_id]

func until(predicate:Callable,seconds:float) -> bool:
	var deadline:=Time.get_ticks_msec()+int(seconds*1000)
	while Time.get_ticks_msec()<deadline:
		if predicate.call():return true
		await create_timer(0.05).timeout
	return false

func action(id:String,cell:Vector2i,extra:String,expected:bool) -> bool:
	receipts.clear()
	session.perform(id,cell,extra)
	return await until(func():return not receipts.is_empty(),3) and receipts[0].ok==expected

func walk_to(goal:Vector2) -> bool:
	var deadline:=Time.get_ticks_msec()+6000
	while Time.get_ticks_msec()<deadline:
		var current:=Vector2(person().x,person().y)
		var difference:=goal-current
		if difference.length()<0.45:
			session.input_direction(Vector2.ZERO)
			return true
		session.input_direction(difference.normalized())
		await create_timer(0.05).timeout
	session.input_direction(Vector2.ZERO)
	return false

func finish(ok:bool,step:String) -> void:
	if ok:print("MINE_SURVEY_ENET_PASS ",step)
	else:push_error("MINE_SURVEY_ENET_FAIL "+step)
	session.shutdown()
	quit(0 if ok else 1)
