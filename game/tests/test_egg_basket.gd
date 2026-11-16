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
	print("EGG_BASKET_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
