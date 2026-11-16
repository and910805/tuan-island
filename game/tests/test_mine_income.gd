extends SceneTree
## T093: fixed-site production cycles through gameplay actions. The mine floor,
## reinforced pick and standing spots are fixtures. Travel is excluded.
const World:=preload("res://scripts/world.gd")
const Mines:=World.MINES
const Gold:=World.GOLD_PANNING
const PLAYER:="mine-income"
var checks:=0
var failures:=0
var serial:=0

func expect(ok:bool,message:String) -> bool:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)
	return ok

func action(world:World,id:String,cell:Vector2i,extra:String="") -> Dictionary:
	serial+=1
	return world.act(PLAYER,"income-%d"%serial,id,cell,extra)

func stand(world:World,region:String,cell:Vector2i) -> void:
	var person:Dictionary=world.state.players[PLAYER]
	person.region=region
	person.x=cell.x-0.5
	person.y=cell.y+0.5

func measure_mine(depth:int,ore:String,yield_per_hit:int,gross:int) -> void:
	var world:=World.new()
	world.add_player(PLAYER,"試算礦工")
	world.state.mine_depths.unlocked=depth
	var person:Dictionary=world.state.players[PLAYER]
	person.inventory.reinforced_pick=1
	person.inventory.stone=0
	var node:Vector2i=Mines.NODES[0]
	stand(world,Mines.IDS[depth-1],node)
	for i in range(3):
		if i>0:
			expect(not action(world,"mine_extract",node).ok,"A depleted node refuses immediate extraction")
			expect(world.step(Mines.COOLDOWN,true),"Wait for the same node to recover")
		if not expect(action(world,"mine_extract",node).ok,"Mine extraction succeeds at B%d"%depth):return
	expect(int(person.inventory.get(ore,0))==3*yield_per_hit,"All three strikes yield the measured ore")
	expect(int(person.mine_energy)==100-3*Mines.energy_cost(depth),"Energy is charged for each strike")
	var before:=int(person.coins)
	var box:=World.SHIPPING.cell_for(world.state)
	stand(world,World.REGIONS.HOME,box)
	var sale:=action(world,"ship",box,JSON.stringify([[[ore,3*yield_per_hit]],gross]))
	if gross>0:expect(sale.ok and int(person.coins)-before==gross,"Sell the measured stone through the shipping box")
	else:expect(not sale.ok and int(person.coins)==before and int(person.inventory[ore])==3*yield_per_hit,"Unpriced gold ore stays in inventory")
	print("MINE_INCOME floor=B%d ore=%s amount=%d energy=%d seconds=%.0f gross=%d"%[
		depth,ore,3*yield_per_hit,100-int(person.mine_energy),world.state.time,int(person.coins)-before])

func measure_panning() -> void:
	var world:=World.new()
	world.add_player(PLAYER,"淘金旅人")
	stand(world,Gold.REGION,Gold.SITE)
	for i in range(3):
		for step:String in Gold.STEPS:
			if not expect(action(world,Gold.ACTION,Gold.SITE,step).ok,"Complete panning step "+step):return
	expect(not action(world,Gold.ACTION,Gold.SITE,"scoop").ok,"Fourth pan is blocked on the same day")
	var person:Dictionary=world.state.players[PLAYER]
	expect(int(person.inventory.get("gold_ore",0))==3,"Three pans yield three gold ore")
	var box:=World.SHIPPING.cell_for(world.state)
	stand(world,World.REGIONS.HOME,box)
	var before:=int(person.coins)
	expect(not action(world,"ship",box,JSON.stringify([[["gold_ore",3]],0])).ok,"Panned gold ore has no direct shipping price")
	expect(int(person.coins)==before and int(person.inventory.gold_ore)==3,"Refused sale keeps both coins and ore unchanged")
	print("PANNING_INCOME pans=3 actions=%d gold_ore=3 gross=0"%[3*Gold.STEPS.size()])

func _initialize() -> void:
	measure_mine(1,"stone",2,12)
	measure_mine(3,"stone",4,24)
	measure_mine(5,"gold_ore",2,0)
	measure_panning()
	print("MINE_INCOME_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
