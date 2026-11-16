extends SceneTree
## T093: deterministic timed catch batches via World.act and World.step.
## Start time and position are fixtures. Excludes travel, mistakes and selling time.
const World:=preload("res://scripts/world.gd")
const FISH_COUNT:=20
const TOKEN:="fishing-income"
var checks:=0
var failures:=0
var request:=0

func expect(ok:bool,message:String) -> bool:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)
	return ok

func act(world:World,action:String,cell:Vector2i,extra:String="") -> Dictionary:
	request+=1
	return world.act(TOKEN,"income-%d"%request,action,cell,extra)

func catch_one(world:World,water:Vector2i,mode:String) -> bool:
	if not expect(act(world,"fish_start",water,mode).ok,"Cast succeeds"):return false
	if not expect(world.step(3.0,true),"Advance to the bite"):return false
	for attempt in range(20):
		if not expect(act(world,"fish_catch",water).ok,"Reel or align succeeds"):return false
		if not world.state.players[TOKEN].has("fishing"):return true
		if not expect(world.step(0.8,true),"Advance the tracking band"):return false
	return expect(false,"Tracking did not finish")

func measure(label:String,region:String,water:Vector2i,bank:Vector2,minute:float,mode:String,expected:Dictionary) -> void:
	var world:=World.new()
	world.add_player(TOKEN,"釣客")
	world.state.time=minute
	var player:Dictionary=world.state.players[TOKEN]
	player.region=region
	player.x=bank.x
	player.y=bank.y
	for i in range(FISH_COUNT):
		if not catch_one(world,water,mode):return
	var elapsed:=float(world.state.time)-minute
	var items:Dictionary={}
	var lines:Array=[]
	var gross:=0
	for item:String in World.FISH:
		var count:=int(player.inventory.get(item,0))
		if count<=0:continue
		items[item]=count
		lines.append([item,count])
		gross+=count*int(World.FISH[item].price)
	expect(items==expected,"%s yields %s; got %s"%[label,str(expected),str(items)])
	expect(int(player.fish_caught)==FISH_COUNT,"Exactly one fish per completed cast")
	expect(elapsed>=60.0 and (is_equal_approx(elapsed,60.0) if mode.is_empty() else elapsed>60.0),"Measure bite and tracking time")
	player.region=World.REGIONS.HOME
	var box:=World.SHIPPING.cell_for(world.state)
	player.x=box.x+0.5
	player.y=box.y+1.5
	var before:=int(player.coins)
	var sold:=act(world,"ship",box,JSON.stringify([lines,gross]))
	expect(sold.ok and int(player.coins)-before==gross,"Actual shipment pays the measured gross")
	for item:String in items:expect(int(player.inventory.get(item,0))==0,"Shipment removes the fish counted")
	print("FISH_INCOME %s time=%.1f gross=%d coins_per_world_minute=%.1f species=%s"%[
		label,elapsed,gross,gross*60.0/elapsed,JSON.stringify(items)])

func _initialize() -> void:
	var river:=Vector2i(55,34)
	var riverbank:=Vector2(54.5,34.5)
	var river_mix:={"carp":5,"minnow":5,"redfish":5,"loach":5}
	measure("home_easy","home",river,riverbank,720.0,"",river_mix)
	measure("home_standard","home",river,riverbank,720.0,"standard",river_mix)
	var coast:=Vector2i(52,25)
	var coast_bank:=Vector2(50.5,25.5)
	measure("beimen_coast_day","beimen",coast,coast_bank,720.0,"",{"sardine":20})
	measure("beimen_coast_night","beimen",coast,coast_bank,1260.0,"",{"sardine":19,"flounder":1})
	measure("beimen_pier_night","beimen",Vector2i(52,22),Vector2(50.5,22.5),1260.0,"",{"moon_squid":20})
	measure("beimen_tidepool_day","beimen",Vector2i(52,36),Vector2(50.5,36.5),720.0,"",{"gold_shrimp":20})
	print("FISHING_INCOME_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
