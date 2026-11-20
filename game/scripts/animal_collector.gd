extends RefCounted

const Industry=preload("res://scripts/industry.gd")
const Livestock=preload("res://scripts/livestock.gd")
const CAPACITY:=6
const REACH:=4
const CHICKEN:="chicken"
const CHICKEN_CELL:=Vector2i(45,34)
const ACTIONS:=["collector_bind","collector_collect","collector_unbind"]
const SPECIES:=["chicken","cow","sheep","duck"]
## C24 pen-bound mode: `collector_animal` holds this reserved word instead of a species and
## the basket keeps one count per item ID in `collector_items`; `collector_count` stays the
## basket total (<= CAPACITY). Single-species collectors keep their original fields.
const PEN:="pen"
const PEN_ITEMS:=["egg","quality_egg","milk","quality_milk","wool","quality_wool","duck_egg","quality_duck_egg"]
const ITEM_LIMIT:=1000000000

static func name_for(id:String) -> String:
	if id==PEN:return "整座圈舍"
	if id==CHICKEN:return "糯米雞"
	return Livestock.ANIMALS[id].name

## Product of one species; a pen-bound basket has no single product, so PEN gives "".
static func item_for(id:String) -> String:
	if id==PEN:return ""
	if id==CHICKEN:return "egg"
	return Livestock.ANIMALS[id].item

static func seed_for(id:String) -> Vector2i:
	return CHICKEN_CELL if id==CHICKEN else Livestock.ANIMALS[id].cell

static func tile_of(key:String) -> Vector2i:
	var parts:=key.split(",")
	return Vector2i(int(parts[0]),int(parts[1]))

static func in_range(tile:Vector2i,id:String) -> bool:
	if id not in SPECIES:return false
	var origin:=seed_for(id)
	return absi(tile.x-origin.x)+absi(tile.y-origin.y)<=REACH

static func bound_elsewhere(objects:Dictionary,id:String,own_tile:String) -> bool:
	for key:String in objects:
		if key==own_tile:continue
		var obj:Dictionary=objects[key]
		if obj.get("type")==Industry.ANIMAL_COLLECTOR and obj.get("collector_animal")==id:return true
	return false

## Species whose valid enclosure (Livestock.pen_cells) contains `tile`, in SPECIES order.
## An open, doorless or oversized enclosure contributes nothing.
static func pen_species(objects:Dictionary,tile:Vector2i) -> Array[String]:
	var found:Array[String]=[]
	for id:String in SPECIES:
		if Livestock.pen_cells(objects,seed_for(id)).has(tile):found.append(id)
	return found

## True when another pen-bound collector stands inside the valid enclosure of `id`.
## Topology-dependent, so it guards binding only and is never part of save validation.
static func pen_served(objects:Dictionary,id:String,own_tile:String) -> bool:
	if id not in SPECIES:return false
	var cells:Dictionary={}
	var filled:=false
	for key:String in objects:
		if key==own_tile:continue
		var obj:Dictionary=objects[key]
		if obj.get("type")!=Industry.ANIMAL_COLLECTOR or obj.get("collector_animal")!=PEN:continue
		if not filled:
			cells=Livestock.pen_cells(objects,seed_for(id))
			filled=true
		if cells.has(tile_of(key)):return true
	return false

## First stored item in the fixed PEN_ITEMS order (for the world icon); "" when empty.
static func pen_first_item(obj:Dictionary) -> String:
	var items:Dictionary=obj.get("collector_items",{})
	for item:String in PEN_ITEMS:
		if int(items.get(item,0))>0:return item
	return ""

## Save shape of a pen-bound basket: known item IDs, whole positive counts that add up to
## `collector_count` (<= CAPACITY), no single-mode quality field. Counts are normalised to
## int. Position and enclosure are deliberately not checked: walls change after binding.
static func valid_pen_basket(obj:Dictionary) -> bool:
	if obj.has("collector_count_quality") or not obj.get("collector_items") is Dictionary:return false
	var items:Dictionary=obj.collector_items
	var total:=0
	for item in items.keys():
		if not (item is String or item is StringName) or str(item) not in PEN_ITEMS:return false
		var amount=items[item]
		if not (amount is int or amount is float) or float(amount)<1.0 or float(amount)>CAPACITY or floorf(float(amount))!=float(amount):return false
		items[item]=int(amount)
		total+=int(amount)
	var count=obj.get("collector_count")
	if not (count is int or count is float) or float(count)!=float(total) or total>CAPACITY:return false
	return true

static func act(world,token:String,tile:Vector2i,action:String,extra:String) -> Dictionary:
	var key:String=world.key(tile)
	var obj:Dictionary=world.state.objects.get(key,{})
	if obj.get("type")!=Industry.ANIMAL_COLLECTOR or obj.get("owner")!=token:
		return world.fail("只能操作自己的動物自動收集器。")
	var inventory:Dictionary=world.state.players[token].inventory
	var animal:String=obj.get("collector_animal","")
	var stored:=int(obj.get("collector_count",0))
	if action=="collector_bind":
		if extra==PEN:return _bind_pen(world,obj,key,tile,inventory,animal,stored)
		if not in_range(tile,extra):return world.fail("請把收集器放在對應動物四格內。")
		if animal==extra:return world.fail("已經綁定這隻動物。")
		if bound_elsewhere(world.state.objects,extra,key):return world.fail("這隻動物已綁定另一台收集器。")
		if pen_served(world.state.objects,extra,key):return world.fail("這隻動物的圈舍已有整圈收集籃。")
		if stored>0:return world.fail("先領完籃內產物，再更換動物。")
		if animal.is_empty():
			if int(inventory.get("egg_basket",0))<1:return world.fail("先在工作台製作一個收集籃。")
			world.give(inventory,"egg_basket",-1)
		obj.collector_animal=extra
		obj.collector_count=0
		obj.erase("collector_items")
		return world.ok("已綁定"+name_for(extra)+"的收集籃。")
	if animal.is_empty() or not extra.is_empty():return world.fail("這台收集器尚未綁定收集籃。")
	if action=="collector_unbind":
		if stored>0:return world.fail("請先取出籃內產物。")
		if int(inventory.get("egg_basket",0))>=ITEM_LIMIT:return world.fail("背包中的物品已達上限。")
		obj.erase("collector_animal")
		obj.erase("collector_count")
		obj.erase("collector_count_quality")
		obj.erase("collector_items")
		world.give(inventory,"egg_basket",1)
		return world.ok("已取回收集籃。")
	if animal==PEN:return _collect_pen(world,obj,inventory)
	var item:=item_for(animal)
	var before_quality:=int(obj.get("collector_count_quality",0))
	var amount:=Livestock.transfer_products(obj,"collector_count",inventory,item,CAPACITY)
	if amount<=0:return world.fail("籃內沒有可領的產物，或背包已滿。")
	var quality:=before_quality-int(obj.get("collector_count_quality",0))
	var detail:="（含優良 %d 份）"%quality if quality>0 else ""
	return world.ok("取出%s ×%d%s。"%[world.NAMES[item],amount,detail])

## Bind the whole enclosure this collector stands in. The basket fee is the same single
## egg_basket as single mode; rebinding an already installed (empty) basket is free.
static func _bind_pen(world,obj:Dictionary,key:String,tile:Vector2i,inventory:Dictionary,animal:String,stored:int) -> Dictionary:
	var objects:Dictionary=world.state.objects
	var species:=pen_species(objects,tile)
	if species.is_empty():return world.fail("請把收集器放進圍好並留一扇木門的圈舍內。")
	if animal==PEN:return world.fail("已經綁定這座圈舍。")
	if stored>0:return world.fail("先領完籃內產物，再更換綁定。")
	var names:PackedStringArray=[]
	for id:String in species:
		if bound_elsewhere(objects,id,key) or pen_served(objects,id,key):
			return world.fail("圈舍內的%s已綁定另一台收集器。"%name_for(id))
		names.append(name_for(id))
	if animal.is_empty():
		if int(inventory.get("egg_basket",0))<1:return world.fail("先在工作台製作一個收集籃。")
		world.give(inventory,"egg_basket",-1)
	obj.collector_animal=PEN
	obj.collector_count=0
	obj.collector_items={}
	obj.erase("collector_count_quality")
	return world.ok("已綁定整座圈舍的收集籃：%s。"%"、".join(names))

## Each item ID moves only as far as the backpack's per-item limit allows; the rest stays
## in the basket for a later pickup. Nothing moved at all is a failure with no change.
static func _collect_pen(world,obj:Dictionary,inventory:Dictionary) -> Dictionary:
	var items:Dictionary=obj.get("collector_items",{})
	var parts:PackedStringArray=[]
	var total:=0
	for item:String in PEN_ITEMS:
		var held:=int(items.get(item,0))
		var amount:=mini(held,ITEM_LIMIT-int(inventory.get(item,0)))
		if amount<=0:continue
		inventory[item]=int(inventory.get(item,0))+amount
		if amount==held:items.erase(item)
		else:items[item]=held-amount
		parts.append("%s ×%d"%[world.NAMES.get(item,item),amount])
		total+=amount
	if total<=0:return world.fail("籃內沒有可領的產物，或背包已滿。")
	obj.collector_items=items
	obj.collector_count=int(obj.get("collector_count",0))-total
	return world.ok("取出%s。"%"、".join(parts))

static func _pen_order(a:String,b:String) -> bool:
	var first:=tile_of(a)
	var second:=tile_of(b)
	return first.x<second.x or (first.x==second.x and first.y<second.y)

## Move what one species has ready into a pen basket, split by item ID. Reuses the
## single-mode transfer rules through a scratch record so both modes share one source of
## truth: products leave `ready` (or end the hen's one cycle) exactly as they enter.
static func _pen_take(world,obj:Dictionary,id:String,now:float) -> int:
	var total:=int(obj.get("collector_count",0))
	var room:=CAPACITY-total
	if room<=0:return 0
	var scratch:Dictionary={"n":0}
	var moved:=0
	if id==CHICKEN:
		scratch.n=total
		moved=Livestock.store_chicken_cycle(world.state.animal,scratch,"n",CAPACITY,now)
	else:
		var animal:Dictionary=world.state.livestock.get(id,{})
		moved=Livestock.transfer_to_collector(animal,scratch,"n",room)
		if moved>0:Livestock.resume_production(animal,id,now)
	if moved<=0:return 0
	var quality:=int(scratch.get("n_quality",0))
	var item:=item_for(id)
	var items:Dictionary=obj.get("collector_items",{})
	if moved>quality:items[item]=int(items.get(item,0))+moved-quality
	if quality>0:items["quality_"+item]=int(items.get("quality_"+item,0))+quality
	obj.collector_items=items
	obj.collector_count=total+moved
	return moved

## Drain only products which the ordinary animal timers have made ready.
## Legacy station baskets/chests get a chance to collect anything left over.
##
## Order is fixed so a product has exactly one destination per tick:
## 1. single-species collectors (original behaviour; they keep sole service of their animal);
## 2. pen-bound collectors, by ascending cell (x, then y) so a JSON reload cannot reorder
##    them. For each species the first pen-bound collector standing in its valid enclosure
##    is the only one that serves it, even when that basket is full, so joining two pens
##    never splits or double-serves a species; an open enclosure serves nobody and the
##    products simply wait in `ready`.
static func step(world) -> Array[String]:
	var changed:Array[String]=[]
	var now:=float(world.state.time)
	var pens:Array[String]=[]
	var single:Dictionary={}
	for key:String in world.state.objects:
		var obj:Dictionary=world.state.objects[key]
		if obj.get("type")!=Industry.ANIMAL_COLLECTOR or not obj.has("collector_animal"):continue
		var species:String=obj.collector_animal
		if species==PEN:
			pens.append(key)
			continue
		single[species]=true
		var room:=CAPACITY-int(obj.collector_count)
		if room<=0:continue
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
	if pens.is_empty():return changed
	pens.sort_custom(func(a:String,b:String)->bool:return _pen_order(a,b))
	for id:String in SPECIES:
		if single.has(id):continue
		# Cheap readiness test first: the enclosure is only traced when something waits.
		if id==CHICKEN:
			if not Livestock.chicken_egg_due(world.state.animal,now):continue
		elif int(world.state.livestock.get(id,{}).get("ready",0))<=0:continue
		var cells:=Livestock.pen_cells(world.state.objects,seed_for(id))
		if cells.is_empty():continue
		for key:String in pens:
			if not cells.has(tile_of(key)):continue
			if _pen_take(world,world.state.objects[key],id,now)>0 and key not in changed:changed.append(key)
			break
	return changed
