extends RefCounted

const DAY:=1440.0
const LIMIT:=7
const BOND_LIMIT:=10
const BONUS_BOND:=5
const BONUS_INTERVAL:=4
const PET_INTERVAL:=30.0
const COLLECTOR_COST:={"plank":6,"copper_joint":2}
const COLLECTOR_CAPACITY:=12
const PEN_RADIUS:=4
const PEN_NEIGHBORS:=[Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT]
const ANIMALS:={
	"cow":{"name":"奶糖牛","item":"milk","days":1,"cell":Vector2i(48,35)},
	"sheep":{"name":"雲朵羊","item":"wool","days":2,"cell":Vector2i(50,35)},
}

static func fresh()->Dictionary:
	return {"feed":0,"ready":0,"next":-1.0}

static func collector_cell(id:String)->Vector2i:
	return ANIMALS[id].cell+Vector2i.DOWN

static func pen_status(objects:Dictionary,id:String)->bool:
	var seed:Vector2i=ANIMALS[id].cell
	if objects.get("%d,%d"%[seed.x,seed.y],{}).get("type","") in ["wall","window","door"]:return false
	var visited:Dictionary={seed:true}
	var pending:Array[Vector2i]=[seed]
	var has_door:=false
	var area:=0
	while not pending.is_empty():
		var current:Vector2i=pending.pop_back()
		area+=1
		for offset:Vector2i in PEN_NEIGHBORS:
			var next:=current+offset
			if visited.has(next):continue
			visited[next]=true
			var kind:String=objects.get("%d,%d"%[next.x,next.y],{}).get("type","")
			if kind=="door":
				has_door=true
				continue
			if kind in ["wall","window"]:continue
			if maxi(absi(next.x-seed.x),absi(next.y-seed.y))>PEN_RADIUS:return false
			pending.append(next)
	return has_door and area>=2

static func refill_collector(animal:Dictionary,id:String,now:float)->bool:
	var moved:=mini(int(animal.ready),COLLECTOR_CAPACITY-int(animal.collector))
	if moved<=0:return false
	animal.collector=int(animal.collector)+moved
	animal.ready=int(animal.ready)-moved
	resume_production(animal,id,now)
	return true

static func collect_into_equipment(records:Dictionary,now:float)->bool:
	var changed:=false
	for id:String in records:
		var animal:Dictionary=records[id]
		if animal.has("collector") and refill_collector(animal,id,now):
			changed=true
	return changed

static func collect_into_chests(world)->Array[String]:
	var changed:Array[String]=[]
	for id:String in world.state.livestock:
		var animal:Dictionary=world.state.livestock[id]
		if animal.has("collector"):continue
		var key:String=world.key(collector_cell(id))
		var chest:Dictionary=world.state.objects.get(key,{})
		if chest.get("type","")!="chest":continue
		var item:String=ANIMALS[id].item
		var stored:=int(chest.items.get(item,0))
		var moved:=mini(int(animal.ready),1000000000-stored)
		if moved<=0:continue
		chest.items[item]=stored+moved
		animal.ready=int(animal.ready)-moved
		resume_production(animal,id,float(world.state.time))
		changed.append(key)
	return changed

static func resume_production(animal:Dictionary,id:String,now:float)->void:
	if float(animal.next)<0.0 and int(animal.feed)>0 and int(animal.ready)<LIMIT:
		animal.next=now+DAY*int(ANIMALS[id].days)

static func step(records:Dictionary,now:float,objects:Dictionary={},elapsed:float=0.0)->bool:
	var changed:=false
	for id in records:
		var animal:Dictionary=records[id]
		if animal.get("managed_pen",false) and not pen_status(objects,id):
			if float(animal.next)>=0.0 and elapsed>0.0:
				animal.next=float(animal.next)+elapsed
				changed=true
			continue
		if float(animal.next)<0.0 or now<float(animal.next):continue
		var interval:float=DAY*int(ANIMALS[id].days)
		while int(animal.feed)>0 and int(animal.ready)<LIMIT and now>=float(animal.next):
			animal.ready=int(animal.ready)+1
			animal.feed=int(animal.feed)-1
			if int(animal.get("bond",0))>=BONUS_BOND:
				var progress:=mini(BONUS_INTERVAL,int(animal.get("bonus_progress",0))+1)
				if progress==BONUS_INTERVAL and int(animal.ready)<LIMIT:
					animal.ready=int(animal.ready)+1
					progress=0
				animal.bonus_progress=progress
			animal.next=float(animal.next)+interval
			changed=true
		if int(animal.feed)==0 or int(animal.ready)==LIMIT:animal.next=-1.0
	return changed

static func perform(records:Dictionary,inventory:Dictionary,id:String,action:String,now:float)->Dictionary:
	var animal:Dictionary=records.get(id,fresh())
	var spec:Dictionary=ANIMALS[id]
	if action=="livestock_pen":
		if animal.get("managed_pen",false):return {"ok":false,"message":"這座圈舍已登記。"}
		animal.managed_pen=true
		records[id]=animal
		return {"ok":true,"message":"已登記圈舍，缺口修好後才能繼續生產。"}
	if action=="livestock_install":
		if animal.has("collector"):return {"ok":false,"message":"收集器已裝好。"}
		for item:String in COLLECTOR_COST:
			if int(inventory.get(item,0))<int(COLLECTOR_COST[item]):return {"ok":false,"message":"收集器材料不足。"}
		for item:String in COLLECTOR_COST:inventory[item]-=COLLECTOR_COST[item]
		animal.collector=0
		refill_collector(animal,id,now)
		records[id]=animal
		return {"ok":true,"message":"收集器已裝好。"}
	if action=="livestock_empty":
		var count:=mini(int(animal.get("collector",0)),1000000000-int(inventory.get(spec.item,0)))
		if count<=0:return {"ok":false,"message":"收集器沒有可取的產物，或背包已滿。"}
		inventory[spec.item]=int(inventory.get(spec.item,0))+count
		animal.collector=int(animal.collector)-count
		refill_collector(animal,id,now)
		return {"ok":true,"message":"已從收集器取出 %d 份產物。"%count}
	if action=="livestock_pet":
		if now-float(animal.get("last_pet",-PET_INTERVAL))<PET_INTERVAL:
			return {"ok":false,"message":"%s正開心地休息，稍後再來摸摸牠。"%spec.name}
		animal.bond=mini(BOND_LIMIT,int(animal.get("bond",0))+1)
		animal.last_pet=now
		records[id]=animal
		return {"ok":true,"message":"%s高興地靠了過來。"%spec.name}
	if action=="livestock_feed":
		if int(animal.feed)>=LIMIT or int(inventory.get("feed",0))<1:return {"ok":false,"message":"飼料槽已滿，或背包沒有飼料。"}
		inventory["feed"]=int(inventory.feed)-1
		animal.feed=int(animal.feed)+1
	else:
		if int(animal.ready)<1:return {"ok":false,"message":"目前沒有可領取的產物。"}
		var item:String=spec.item
		if int(inventory.get(item,0))>=1000000000:return {"ok":false,"message":"背包已達上限。"}
		inventory[item]=int(inventory.get(item,0))+1
		animal.ready=int(animal.ready)-1
	resume_production(animal,id,now)
	records[id]=animal
	return {"ok":true,"message":"已替%s補充一份飼料。" % spec.name if action=="livestock_feed" else "已領取一份產物。"}
