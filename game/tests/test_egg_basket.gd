extends SceneTree

const World=preload("res://scripts/world.gd")
const HEN:=World.CHICKEN_CELL
const BENCH:=HEN+Vector2i.LEFT
var failures:=0
var checks:=0

func expect(condition:bool,message:String) -> void:
	checks+=1
	if not condition:
		failures+=1
		push_error(message)

func _initialize() -> void:
	var path:="user://egg-basket-%d-%d.json"%[OS.get_process_id(),Time.get_ticks_usec()]
	var world:=World.new()
	world.save_path=path
	for token in ["grower","friend"]:
		world.add_player(token,token)
		var player:Dictionary=world.state.players[token]
		player.x=HEN.x+0.5
		player.y=HEN.y+0.5
	var bag:Dictionary=world.state.players.grower.inventory
	bag.wood=8
	bag.fiber=6
	bag.feed=World.EGG_BASKET_CAPACITY+2
	world.state.objects[World.key(BENCH)]={"type":"bench","owner":"grower","items":{}}
	expect(world.act("grower","first-feed","feed",HEN).ok,"Legacy hen accepts feed without a basket")
	expect(world.step(60.0,true) and not world.state.animal.has("basket_eggs"),"Legacy pending egg remains collectable")
	expect(world.act("grower","make-basket","craft",BENCH,"egg_basket").ok,"Craft a basket at the bench")
	expect(int(bag.wood)==0 and int(bag.fiber)==0 and int(bag.egg_basket)==1,"Craft charges exactly eight wood and six fiber")
	expect(world.act("grower","install","install_egg_basket",HEN).ok,"Install the basket at the chicken")
	expect(int(world.state.animal.basket_eggs)==1 and float(world.state.animal.egg_ready)==-1.0,"Existing mature egg is transferred once")
	expect(not world.act("grower","already-installed","install_egg_basket",HEN).ok,"The shared pen only accepts one basket")
	for i in range(1,World.EGG_BASKET_CAPACITY):
		expect(world.act("grower","feed-%d"%i,"feed",HEN).ok,"Feed with room in the basket")
		expect(world.step(59.0,true) and int(world.state.animal.basket_eggs)==i,"No egg arrives early")
		expect(world.step(1.0,true) and int(world.state.animal.basket_eggs)==i+1,"One egg reaches the basket at the deadline")
	var feed_before:=int(world.state.players.grower.inventory.feed)
	expect(not world.act("grower","full-feed","feed",HEN).ok,"Full basket blocks feeding")
	expect(int(world.state.players.grower.inventory.feed)==feed_before,"Full basket preserves feed")
	expect(world.load_world(path),"Load saved full basket")
	expect(world.step(120.0,true) and int(world.state.animal.basket_eggs)==World.EGG_BASKET_CAPACITY,"Restart and elapsed time cannot duplicate eggs")
	var claim:=world.act("friend","claim","egg",HEN)
	expect(claim.ok,"A second player can collect the shared eggs")
	expect(int(world.state.players.friend.inventory.egg)==World.EGG_BASKET_CAPACITY,"Collector receives the entire basket")
	expect(world.load_world(path),"Reload after collection")
	expect(not world.act("friend","claim-again","egg",HEN).ok,"Collecting again after reload cannot award the same eggs")
	expect(int(world.state.players.friend.inventory.egg)==World.EGG_BASKET_CAPACITY,"Friend inventory survives reload")
	expect(world.act("grower","resume-feed","feed",HEN).ok,"Feeding resumes when the basket is empty")
	var due:=float(world.state.animal.egg_ready)
	world.save_path=path+"/missing"
	expect(not world.step(60.0,true),"A failed save rejects the production tick")
	expect(int(world.state.animal.basket_eggs)==0 and float(world.state.animal.egg_ready)==due,"Failed save restores both basket count and production timer")
	world.save_path=path
	expect(world.step(60.0,true) and int(world.state.animal.basket_eggs)==1,"Retry produces exactly one egg")
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	for mode in ["hand","basket","machine"]:verify_quality(mode)
	var hen:Dictionary={"egg_ready":1.0,"bond":5,"bonus_progress":3,"basket_eggs":3}
	expect(World.LIVESTOCK.store_chicken_cycle(hen,hen,"basket_eggs",4,1.0)==1 and int(hen.bonus_progress)==4,
		"A one-slot basket stores the ordinary egg and saves the owed quality reward")
	hen.basket_eggs=0
	hen.egg_ready=2.0
	expect(World.LIVESTOCK.store_chicken_cycle(hen,hen,"basket_eggs",4,2.0)==2
		and int(hen.basket_eggs_quality)==1 and int(hen.bonus_progress)==0,"The next cycle pays the deferred bonus only once")
	print("EGG_BASKET_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func verify_quality(mode:String)->void:
	var world:=World.new()
	var token:="grower"
	world.add_player(token,"牧場")
	var player:Dictionary=world.state.players[token]
	player.x=HEN.x+0.5
	player.y=HEN.y+0.5
	player.inventory.feed=World.LIVESTOCK.BONUS_INTERVAL
	for i in World.LIVESTOCK.BONUS_BOND:
		expect(world.act(token,"pet-%d"%i,"pet",HEN).ok,"Pet the hen through the normal action")
		world.step(World.LIVESTOCK.PET_INTERVAL,true)
	var site:=HEN+Vector2i.DOWN
	if mode=="basket":
		player.inventory.egg_basket=1
		expect(world.act(token,"install","install_egg_basket",HEN).ok,"Install the legacy basket")
	if mode=="machine":
		world.state.objects[World.key(site)]={"type":"animal_collector","owner":token,"items":{}}
		player.inventory.egg_basket=1
		expect(world.act(token,"bind","collector_bind",site,"chicken").ok,"Bind the equipment to the hen")
	for i in World.LIVESTOCK.BONUS_INTERVAL:
		expect(world.act(token,"feed-%d"%i,"feed",HEN).ok,"Feed through the usual action")
		world.step(World.CHICKEN_EGG_SECONDS,true)
		if mode=="hand":expect(world.act(token,"collect-%d"%i,"egg",HEN).ok,"Collect the egg by hand")
	var path:="user://quality-egg-%s-%d.json"%[mode,Time.get_ticks_usec()]
	world.save_path=path
	expect(world.save() and world.load_world(path),"Save and reload "+mode)
	if mode=="basket":expect(world.act(token,"collect","egg",HEN).ok,"Empty the legacy basket")
	if mode=="machine":expect(world.act(token,"collect","collector_collect",site).ok,"Empty the equipment")
	var bag:Dictionary=world.state.players[token].inventory
	expect(int(bag.get("egg",0))==4 and int(bag.get("quality_egg",0))==1,"Exactly four normal eggs and one quality egg through "+mode)
	expect(int(world.state.animal.bonus_progress)==0,"Granting a quality egg resets the streak")
	var stall:=Vector2i(43,29)
	player=world.state.players[token]
	player.x=stall.x+0.5
	player.y=stall.y+0.5
	var coins:=int(player.coins)
	expect(world.act(token,"sell","sell",stall,"quality_egg").ok and int(player.coins)==coins+37
		and int(bag.egg)==4,"Selling a quality egg pays 37 and keeps ordinary eggs")
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
