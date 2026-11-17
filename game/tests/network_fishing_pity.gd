extends SceneTree

const World=preload("res://scripts/world.gd")
const Session=preload("res://scripts/session.gd")
const SITES:={
	"lanyang":{"cell":Vector2i(33,26),"stand":Vector2(32.5,26.5),"season":2,"minute":480},
	"beimen":{"cell":Vector2i(52,25),"stand":Vector2(50.5,26.5),"season":0,"minute":1260},
	"jiaoxi":{"cell":Vector2i(32,25),"stand":Vector2(32.5,24.5),"season":3,"minute":720},
	"bamboo_grove":{"cell":Vector2i(23,22),"stand":Vector2(22.5,22.5),"season":0,"minute":480},
	"star_garden":{"cell":Vector2i(23,21),"stand":Vector2(22.5,21.5),"season":0,"minute":1260},
}
const TOKEN_PREFIX:="pity-fixture-"

var session:Session
var notices:Array[Dictionary]=[]
var region:String
var target:Vector2i
var rare_fish:String

func _initialize()->void:
	run.call_deferred()

func run()->void:
	var args:=OS.get_cmdline_user_args()
	var mode:=args[0]
	var port:=int(args[1])
	var path:=args[2]
	region=args[3]
	var site:Dictionary=SITES[region]
	target=site.cell
	var water:Dictionary=World.Collections.RARE_WATERS[region]
	rare_fish=water.fish
	if mode=="seed":
		var world:=World.new()
		world.save_path=path
		world.state.time=site.season*World.WEATHER.DAYS_PER_SEASON*World.WEATHER.DAY_SECONDS+site.minute
		for who in ["owner","friend"]:
			var token:String=TOKEN_PREFIX+who
			world.add_player(token,who)
			var person:Dictionary=world.state.players[token]
			person.region=region
			person.x=site.stand.x
			person.y=site.stand.y
			if region!="lanyang":person.travel_book.visited[region]=true
			person[water.counter]=18 if who=="owner" else 5
			if region=="beimen":seed_beimen_access(world,token)
		if region=="beimen":
			world.state.board=true
			world.state.picnic_materials={"soup":2,"bread":1}
			world.state.picnic=true
			world.state.chapter_one={"shipped":true,"watered":true,"harvests":{},"starter_claims":{}}
			world.state.community={"table":"39,30"}
			world.state.flower_nursery.garden={"given":World.FLOWER_NURSERY.GARDEN_NEEDS.duplicate(),"contributors":{TOKEN_PREFIX+"owner":6,TOKEN_PREFIX+"friend":4},"complete":true,"completed_at":0.0}
		world.switch_region(region)
		var accessible:=world.can_stand(site.stand) and world.water(target)
		world.switch_region("home")
		if not accessible:
			push_error("Fishing fixture is blocked in "+region)
			quit(1)
			return
		quit(0 if world.save() and World.new().load_world(path) else 1)
		return
	var island:=Node.new()
	root.add_child(island)
	session=Session.new()
	island.add_child(session)
	if mode=="server":
		var code:=session.host(port,"",path,"","127.0.0.1",true,"websocket")
		if code!=OK:
			quit(1)
			return
		print("PITY_HOST_READY")
		if not await until(func():return FileAccess.file_exists(path+".stop"),30.0):
			quit(1)
			return
		var saved:=session.shutdown()
		print("MEAL_STOP ",saved)
		quit(0 if saved else 1)
		return
	var who:="owner" if mode.begins_with("owner") else "friend"
	session.profile.token=TOKEN_PREFIX+who
	session.notice.connect(func(message:String,ok:bool):notices.append({"message":message,"ok":ok}))
	var connected:=session.join("ws://127.0.0.1:%d"%port,port,who,"")
	if connected!=OK or not await until(func():return session.snapshot.get("players",{}).has(session.own_id)):
		finish(false,mode,"could not join")
		return
	var restarted:=mode.ends_with("-after")
	var initial_catches:=1 if restarted else 0
	if not await until(func():return int(person().get("fish_caught",-1))==initial_catches):
		finish(false,mode,"player catch count did not survive reconnect")
		return
	var before:=int(person().get("inventory",{}).get(rare_fish,0))
	var cast:=await perform("fish_start")
	if not cast.get("ok",false):
		finish(false,mode,"could not cast in %s at (%s,%s): %s"%[str(session.snapshot.get("region_id")),str(person().get("x")),str(person().get("y")),str(cast.get("message","no reply"))])
		return
	var early:=await perform("fish_catch")
	if early.get("ok",true):
		finish(false,mode,"reeling early was not refused")
		return
	var due:=await until(func():
		var fishing:Dictionary=person().get("fishing",{})
		return not fishing.is_empty() and float(session.snapshot.get("time",0.0))>=float(fishing.ready))
	if not due:
		finish(false,mode,"cast never became ready")
		return
	var landed:=await perform("fish_catch")
	var caught:=await until(func():return int(person().get("fish_caught",-1))==initial_catches+1)
	var expected_rare:=1 if restarted and who=="owner" else 0
	finish(landed.get("ok",false) and caught and int(person().inventory.get(rare_fish,0))==before+expected_rare,mode,"exact catch count and rare fish award")

func person()->Dictionary:
	return session.snapshot.get("players",{}).get(session.own_id,{})

func seed_beimen_access(world:World,token:String)->void:
	var tea:Dictionary=World.TEA_CERAMICS.FRESH.duplicate(true)
	tea.merge({"intro":true,"potter":true,"reused":true,"reuse_count":1,"trials":{"jar":true,"fiber":true},"tea_discussed":true,"comparison_complete":true},true)
	world.state.tea_ceramics.players[token]=tea
	var flower:Dictionary=World.FLOWER_NURSERY.FRESH.duplicate(true)
	flower.merge({"letter":true,"intro":true,"shipped":true,"complete":true},true)
	for kind in World.FLOWER_NURSERY.FLOWERS:
		flower.planted[kind]=true
		flower.harvested[kind]=2
		flower.saved[kind]=true
	world.state.flower_nursery.players[token]=flower
	var salt:Dictionary=World.SALT_PAN.RECORD.duplicate(true)
	salt.letter=true
	world.state.salt_pan.players[token]=salt
	for stop in ["maokong","yingge","tianwei"]:
		world.state.players[token].travel_book.visited[stop]=true

func until(predicate:Callable,timeout:=9.0)->bool:
	var deadline:=Time.get_ticks_msec()+int(timeout*1000)
	while Time.get_ticks_msec()<deadline:
		if predicate.call():return true
		await create_timer(0.05).timeout
	return false

func perform(action:String)->Dictionary:
	var before:=notices.size()
	if session.perform(action,target)<=0:return {}
	if not await until(func():return notices.size()>before):return {}
	return notices[before]

func finish(ok:bool,mode:String,message:String)->void:
	print("PITY_WS ",mode," ",ok," ",message," catches=",person().get("fish_caught",-1)," ",rare_fish,"=",person().get("inventory",{}).get(rare_fish,0))
	session.shutdown()
	quit(0 if ok else 1)
