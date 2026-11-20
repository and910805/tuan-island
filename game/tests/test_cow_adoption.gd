extends SceneTree
## D07: actual World.act coverage for the 奶糖牛 adoption flow — a new save must adopt
## (shared, durable, paid once), while a legacy save that already holds a cow record keeps
## every milk, bond, collector and pen without being asked to adopt or pay.
const World=preload("res://scripts/world.gd")
const L=preload("res://scripts/livestock.gd")
const Schema=preload("res://scripts/save_schema.gd")
const SITE:=Vector2i(48,35)
const SHEEP:=Vector2i(50,35)
const A:="cow-adopt-a"
const B:="cow-adopt-b"
const LOCKED:="完成渡口野餐後，可照料牧場家畜。"
var checks:=0
var failures:=0
var serial:=0
var cleanup:Array[String]=[]

func expect(ok:bool,label:String)->void:
	checks+=1
	if not ok:
		failures+=1
		push_error(label)

func valid(data:Dictionary)->bool:
	return Schema.validate(JSON.parse_string(JSON.stringify(data)),World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME)

func temp_path(tag:String)->String:
	var file:=OS.get_environment("TEMP").path_join("cow-adoption-%s-%s.json"%[tag,Crypto.new().generate_random_bytes(8).hex_encode()])
	cleanup.append(file)
	return file

func act(w:World,token:String,action:String,cell:Vector2i,extra:String="cow")->Dictionary:
	serial+=1
	return w.act(token,"adopt-%d"%serial,action,cell,extra)

## Refused with the exact message, and nothing (coins, bag, records) changed.
func refused(w:World,token:String,action:String,cell:Vector2i,message:String,label:String)->void:
	var before:=w.state.duplicate(true)
	var result:=act(w,token,action,cell)
	expect(not result.ok and str(result.message)==message and w.state==before,"%s (got '%s')"%[label,str(result.message)])

func make_world(tag:String)->World:
	var w:=World.new()
	w.save_path=temp_path(tag)
	for token in [A,B]:
		w.add_player(token,"牧場")
		w.state.players[token].x=48.5
		w.state.players[token].y=37.5
	return w

func _initialize()->void:
	test_new_save()
	test_legacy_saves()
	for file in cleanup:
		for suffix in ["",".bak",".tmp"]:
			if FileAccess.file_exists(file+suffix):DirAccess.remove_absolute(file+suffix)
	print("COW_ADOPTION_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0 or checks==0))

func test_new_save()->void:
	var w:=make_world("new")
	var fee:int=L.ADOPTION_COST.cow
	expect(fee<=int(w.state.players[A].coins),"The fee is affordable from the starting coins")
	expect(not w.state.livestock.has("cow"),"A new world has no cow record yet")
	refused(w,A,"livestock_adopt",SITE,LOCKED,"The picnic gate still applies to adoption")
	w.state.picnic=true
	refused(w,A,"livestock_adopt",SITE+Vector2i.RIGHT,LOCKED,"Adoption must happen at the feed station")
	w.state.players[A].inventory.feed=2
	for action in ["livestock_pet","livestock_feed","livestock_collect","livestock_empty","livestock_brush"]:
		refused(w,A,action,SITE,L.NOT_ADOPTED_MESSAGE,"An unadopted cow refuses "+action)
	# Other livestock are unaffected by the cow gate.
	w.state.players[A].x=SHEEP.x+0.5
	w.state.players[A].y=SHEEP.y+1.5
	expect(act(w,A,"livestock_feed",SHEEP,"sheep").ok and w.state.livestock.has("sheep"),"The sheep needs no adoption")
	w.state.players[A].x=48.5
	w.state.players[A].y=37.5
	# Coins belong to the player; only a funded visitor can adopt.
	w.state.players[A].coins=fee-1
	refused(w,A,"livestock_adopt",SITE,"領養奶糖牛需要 %d 鈴幣。"%fee,"An underfunded player cannot adopt")
	var bag_b:Dictionary=w.state.players[B].inventory.duplicate(true)
	var adopted:=act(w,B,"livestock_adopt",SITE)
	expect(adopted.ok and int(w.state.players[B].coins)==120-fee and int(w.state.players[A].coins)==fee-1,"Only the adopter pays")
	expect(w.state.players[B].inventory==bag_b,"Adoption takes no materials")
	expect(w.state.livestock.cow==L.fresh() and valid(w.state.duplicate(true)),"Adoption writes one fresh, schema-valid shared record")
	# Co-op: the other player sees an adopted cow and is never charged again.
	refused(w,A,"livestock_adopt",SITE,"奶糖牛已經是島上的一員了。","The shared cow cannot be adopted twice")
	refused(w,B,"livestock_adopt",SITE,"奶糖牛已經是島上的一員了。","The adopter is not charged twice")
	expect(act(w,A,"livestock_feed",SITE).ok and int(w.state.players[A].inventory.feed)==0,"A friend feeds the adopted cow with their own feed")
	expect(act(w,B,"livestock_pet",SITE).ok and int(w.state.livestock.cow.bond)==1,"The adopter can pet the shared cow")
	expect(w.step(L.DAY,true) and int(w.state.livestock.cow.ready)==1,"The adopted cow produces milk normally")
	expect(act(w,B,"livestock_collect",SITE).ok and int(w.state.players[B].inventory.milk)==1,"Milk is only obtained after adoption")
	# Durable: reload keeps the adoption, so no second fee after a restart.
	expect(w.save() and w.load_world(w.save_path) and w.state.livestock.has("cow"),"Adoption survives save and reload")
	refused(w,A,"livestock_adopt",SITE,"奶糖牛已經是島上的一員了。","Reload does not reopen adoption")
	expect(int(w.state.livestock.cow.bond)==1 and int(w.state.players[B].inventory.milk)==1,"Reload keeps the bond and the milk already collected")

func test_legacy_saves()->void:
	var w:=make_world("legacy")
	w.state.picnic=true
	var day:=L.DAY
	w.state.time=day*3
	var cow:={"feed":2,"ready":3,"next":day*3+100.0,"bond":6,"last_pet":0.0,"bonus_progress":2,"collector":4,"managed_pen":true}
	w.state.livestock.cow=cow.duplicate(true)
	var chest_site:=L.collector_cell("cow")
	expect(w.save() and w.load_world(w.save_path),"A legacy world with a raised cow loads")
	for field in cow:
		var kept:bool
		if cow[field] is bool:kept=w.state.livestock.cow[field]==cow[field]
		else:kept=float(w.state.livestock.cow[field])==float(cow[field])
		expect(kept,"Legacy cow keeps "+field)
	var coins:int=w.state.players[A].coins
	refused(w,A,"livestock_adopt",SITE,"奶糖牛已經是島上的一員了。","A raised cow is already adopted")
	expect(int(w.state.players[A].coins)==coins,"A legacy keeper is never charged")
	expect(act(w,A,"livestock_collect",SITE).ok and int(w.state.players[A].inventory.milk)==1 and int(w.state.livestock.cow.ready)==2,"Legacy ready milk can still be collected")
	# Emptying hands over the four stored milk, then the equipment refills from the two still waiting.
	expect(act(w,A,"livestock_empty",SITE).ok and int(w.state.players[A].inventory.milk)==5 and int(w.state.livestock.cow.collector)==2 and int(w.state.livestock.cow.ready)==0,"A legacy collector still empties and refills without loss")
	w.state.players[A].inventory.feed=1
	expect(act(w,A,"livestock_feed",SITE).ok and int(w.state.livestock.cow.feed)==3,"Legacy cow still takes feed")
	expect(act(w,B,"livestock_pet",SITE).ok and int(w.state.livestock.cow.bond)==7,"Legacy bond keeps growing from the old value")
	expect(valid(w.state.duplicate(true)),"The legacy cow record still validates unchanged")
	# A legacy world that only holds an auto-collecting chest keeps draining the pen.
	var chest_world:=make_world("legacy-chest")
	chest_world.state.picnic=true
	chest_world.state.livestock.cow={"feed":0,"ready":2,"next":-1.0}
	chest_world.state.objects[World.key(chest_site)]={"type":"chest","owner":A,"items":{}}
	expect(not L.collect_into_chests(chest_world).is_empty() and int(chest_world.state.objects[World.key(chest_site)].items.milk)==2 and int(chest_world.state.livestock.cow.ready)==0,
		"A legacy auto collector chest still receives ready milk")
	# An empty legacy record (cow fed once, nothing since) also counts as adopted.
	var quiet:=make_world("legacy-empty")
	quiet.state.picnic=true
	quiet.state.livestock.cow=L.fresh()
	refused(quiet,A,"livestock_adopt",SITE,"奶糖牛已經是島上的一員了。","Any existing cow record is treated as adopted")
