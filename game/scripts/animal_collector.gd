extends RefCounted

const Industry=preload("res://scripts/industry.gd")
const Livestock=preload("res://scripts/livestock.gd")
const CAPACITY:=6
const REACH:=4
const CHICKEN:="chicken"
const CHICKEN_CELL:=Vector2i(45,34)
const ACTIONS:=["collector_bind","collector_collect","collector_unbind"]
const SPECIES:=["chicken","cow","sheep","duck"]

static func name_for(id:String) -> String:
	if id==CHICKEN:return "糯米雞"
	return Livestock.ANIMALS[id].name

static func item_for(id:String) -> String:
	if id==CHICKEN:return "egg"
	return Livestock.ANIMALS[id].item

static func in_range(tile:Vector2i,id:String) -> bool:
	if id not in SPECIES:return false
	var origin:Vector2i=CHICKEN_CELL if id==CHICKEN else Livestock.ANIMALS[id].cell
	return absi(tile.x-origin.x)+absi(tile.y-origin.y)<=REACH

static func bound_elsewhere(objects:Dictionary,id:String,own_tile:String) -> bool:
	for key:String in objects:
		if key==own_tile:continue
		var obj:Dictionary=objects[key]
		if obj.get("type")==Industry.ANIMAL_COLLECTOR and obj.get("collector_animal")==id:return true
	return false

static func act(world,token:String,tile:Vector2i,action:String,extra:String) -> Dictionary:
	var key:String=world.key(tile)
	var obj:Dictionary=world.state.objects.get(key,{})
	if obj.get("type")!=Industry.ANIMAL_COLLECTOR or obj.get("owner")!=token:
		return world.fail("只能操作自己的動物自動收集器。")
	var inventory:Dictionary=world.state.players[token].inventory
	var animal:String=obj.get("collector_animal","")
	var stored:=int(obj.get("collector_count",0))
	if action=="collector_bind":
		if not in_range(tile,extra):return world.fail("請把收集器放在對應動物四格內。")
		if animal==extra:return world.fail("已經綁定這隻動物。")
		if bound_elsewhere(world.state.objects,extra,key):return world.fail("這隻動物已綁定另一台收集器。")
		if stored>0:return world.fail("先領完籃內產物，再更換動物。")
		if animal.is_empty():
			if int(inventory.get("egg_basket",0))<1:return world.fail("先在工作台製作一個收集籃。")
			world.give(inventory,"egg_basket",-1)
		obj.collector_animal=extra
		obj.collector_count=0
		return world.ok("已綁定"+name_for(extra)+"的收集籃。")
	if animal.is_empty() or not extra.is_empty():return world.fail("這台收集器尚未綁定收集籃。")
	if action=="collector_unbind":
		if stored>0:return world.fail("請先取出籃內產物。")
		if int(inventory.get("egg_basket",0))>=1000000000:return world.fail("背包中的物品已達上限。")
		obj.erase("collector_animal")
		obj.erase("collector_count")
		obj.erase("collector_count_quality")
		world.give(inventory,"egg_basket",1)
		return world.ok("已取回收集籃。")
	var item:=item_for(animal)
	var before_quality:=int(obj.get("collector_count_quality",0))
	var amount:=Livestock.transfer_products(obj,"collector_count",inventory,item,CAPACITY)
	if amount<=0:return world.fail("籃內沒有可領的產物，或背包已滿。")
	var quality:=before_quality-int(obj.get("collector_count_quality",0))
	var detail:="（含優良 %d 份）"%quality if quality>0 else ""
	return world.ok("取出%s ×%d%s。"%[world.NAMES[item],amount,detail])

## Drain only products which the ordinary animal timers have made ready.
## Legacy station baskets/chests get a chance to collect anything left over.
static func step(world) -> Array[String]:
	var changed:Array[String]=[]
	var now:=float(world.state.time)
	for key:String in world.state.objects:
		var obj:Dictionary=world.state.objects[key]
		if obj.get("type")!=Industry.ANIMAL_COLLECTOR or not obj.has("collector_animal"):continue
		var room:=CAPACITY-int(obj.collector_count)
		if room<=0:continue
		var species:String=obj.collector_animal
		var moved:=0
		if species==CHICKEN:
			moved=Livestock.store_chicken_cycle(world.state.animal,obj,"collector_count",CAPACITY,now)
		else:
			var animal:Dictionary=world.state.livestock.get(species,{})
			moved=Livestock.transfer_to_collector(animal,obj,"collector_count",room)
			if moved>0:
				Livestock.resume_production(animal,species,now)
		if moved>0:
			changed.append(key)
	return changed
