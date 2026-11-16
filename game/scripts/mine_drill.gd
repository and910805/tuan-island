extends RefCounted

const Mines=preload("res://scripts/mine_depths.gd")
const COST := {"plank":16,"copper_joint":12,"stone":20,"resin":6}
const LIMIT := 2
const FUEL_CAP := 16
const OUTPUT_CAP := 32
const DURATION := 20.0
const NODE := Mines.NODES[2]
const NODE_KEY := "%d,%d"%[NODE.x,NODE.y]
const DIRECTIONS := [Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT]
const ACTIONS := ["mine_drill_feed","mine_drill_unload_fuel","mine_drill_collect","mine_drill_toggle"]
const OUTPUTS := [
	{"item":"stone","quantity":2},
	{"item":"copper_ore","quantity":3},
	{"item":"stone","quantity":2},
	{"item":"copper_ore","quantity":4},
	{"item":"gold_ore","quantity":1},
]

## Drills stay on the original shallow works (B1–B5); T067 deep floors are manual.
const REGIONS := ["mine_1","mine_2","mine_3","mine_4","mine_5"]

static func output(region:String)->Dictionary:
	var index:=REGIONS.find(region)
	return OUTPUTS[index] if index>=0 else {}

static func placement(cell:Vector2i)->int:
	return DIRECTIONS.find(NODE-cell)

static func fresh(dir:int)->Dictionary:
	return {"enabled":false,"fuel":0,"dir":dir,"items":{}}

static func can_move(device:Dictionary)->bool:
	return not device.enabled and not device.has("job") and device.fuel==0 and device.items.is_empty()

static func reserved(objects:Dictionary)->bool:
	for direction in DIRECTIONS:
		var tile:Vector2i=NODE-direction
		var device:Dictionary=objects.get("%d,%d"%[tile.x,tile.y],{})
		if device.get("type")=="mine_drill" and device.has("job"):return true
	return false

static func status(device:Dictionary,region:String,now:float,cooldown:float=0.0)->Dictionary:
	var id:="ready"
	var message:="準備開始"
	var remaining:=0.0
	var product:=output(region)
	if device.has("job"):
		id="working"
		message="採掘中"
		remaining=maxf(0.0,float(device.job.ready)-now)
	elif not device.enabled:
		id="stopped"
		message="已停用"
	elif int(device.fuel)==0:
		id="no_fuel"
		message="等候木炭"
	elif not product.is_empty() and int(device.items.get(product.item,0))+int(product.quantity)>OUTPUT_CAP:
		id="output_full"
		message="產出槽空間不足"
	elif cooldown>now:
		id="cooldown"
		message="等候礦點恢復"
		remaining=cooldown-now
	return {"id":id,"text":message,"remaining":remaining}

static func tick(objects:Dictionary,progress:Dictionary,region:String,now:float)->bool:
	var product:=output(region)
	if product.is_empty():return false
	var ready:Dictionary=progress.ready.get(region,{})
	for device in objects.values():
		if device.type!="mine_drill":continue
		if device.has("job"):
			if float(device.job.ready)>now:return false
			device.items[product.item]=int(device.items.get(product.item,0))+int(product.quantity)
			device.erase("job")
			ready[NODE_KEY]=now+Mines.COOLDOWN
			progress.ready[region]=ready
			return true
		if status(device,region,now,float(ready.get(NODE_KEY,0))).id!="ready":return false
		device.fuel-=1
		device.job={"owner":device.owner,"ready":now+DURATION}
		return true
	return false

static func operate(device:Dictionary,inventory:Dictionary,action:String,extra:String)->Dictionary:
	if action!="mine_drill_feed" and not extra.is_empty():return result(false,"操作參數無效。")
	match action:
		"mine_drill_feed":
			if extra not in ["1","5"]:return result(false,"只能選擇加入 1 或 5 木炭。")
			var amount:=mini(int(extra),mini(FUEL_CAP-int(device.fuel),int(inventory.get("charcoal",0))))
			if amount<=0:return result(false,"背包沒有木炭，或燃料槽已滿。")
			device.fuel+=amount
			inventory.charcoal-=amount
			return result(true,"已補入 %d 木炭。"%amount)
		"mine_drill_unload_fuel","mine_drill_collect":
			var fuel:=action=="mine_drill_unload_fuel"
			var source:Dictionary={"charcoal":device.fuel} if fuel else device.items
			if source.values().all(func(amount):return amount==0):return result(false,"目前沒有可取出的物品。")
			for item in source:
				if int(inventory.get(item,0))+int(source[item])>1000000000:return result(false,"背包物品已達上限。")
			for item in source:inventory[item]=int(inventory.get(item,0))+int(source[item])
			if fuel:device.fuel=0
			else:device.items.clear()
			return result(true,"已取回物品。")
		"mine_drill_toggle":
			device.enabled=not device.enabled
			return result(true,"採掘機已啟用。" if device.enabled else "已停用新批次，正在採掘的批次仍會完成。")
	return result(false,"找不到這項操作。")

static func result(ok:bool,message:String)->Dictionary:
	return {"ok":ok,"message":message}
