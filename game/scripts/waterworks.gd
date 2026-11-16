extends RefCounted

const COST := {"plank":12,"copper_joint":8,"stone":16,"resin":4}
const LIMIT := 4
const CAPACITY := 12
const INPUT_CAP := 32
const OUTPUT_CAP := 32
const DURATION := 12.0
const INPUTS := {"copper_ore":2,"wood":1}
const WATER_COST := 2
const ACTIONS := ["waterworks_feed","waterworks_unload_input","waterworks_collect","waterworks_toggle","waterworks_drain"]

static func fresh()->Dictionary:
	return {"enabled":false,"water":0,"input":{"wood":0,"copper_ore":0},"items":{}}

static func can_move(device:Dictionary)->bool:
	return not device.enabled and not device.has("job") and device.water==0 and device.items.is_empty() and device.input.values().all(func(value):return value==0)

static func status(device:Dictionary,now:float)->Dictionary:
	var id:="ready"
	var message:="準備開始"
	var remaining:=0.0
	if device.has("job"):
		id="working"
		message="加工中"
		remaining=maxf(0.0,float(device.job.ready)-now)
	elif not device.enabled:
		id="stopped"
		message="已停用"
	elif int(device.items.get("copper_joint",0))>=OUTPUT_CAP:
		id="output_full"
		message="成品已滿"
	elif int(device.water)<WATER_COST:
		id="no_water"
		message="等候管網供水"
	else:
		for item in INPUTS:
			if int(device.input[item])<INPUTS[item]:
				id="no_materials"
				message="等候原料"
				break
	return {"id":id,"text":message,"remaining":remaining}

static func tick(objects:Dictionary,now:float)->bool:
	var changed:=false
	for device in objects.values():
		if device.type!="waterworks":continue
		if device.has("job"):
			if float(device.job.ready)>now:continue
			device.items.copper_joint=int(device.items.get("copper_joint",0))+1
			device.erase("job")
		elif status(device,now).id=="ready":
			for item in INPUTS:device.input[item]-=INPUTS[item]
			device.water-=WATER_COST
			device.job={"owner":device.owner,"ready":now+DURATION}
		else:
			continue
		changed=true
	return changed

static func operate(device:Dictionary,inventory:Dictionary,action:String,extra:String)->Dictionary:
	if action!="waterworks_feed" and not extra.is_empty():return result(false,"操作參數無效。")
	match action:
		"waterworks_feed":
			var args:=extra.split(":")
			if args.size()!=2 or not INPUTS.has(args[0]) or args[1] not in ["1","5"]:return result(false,"只能放入指定數量的木材或銅礦。")
			var item:=args[0]
			var amount:=mini(int(args[1]),mini(int(inventory.get(item,0)),INPUT_CAP-int(device.input[item])))
			if amount<=0:return result(false,"背包沒有原料，或進料已滿。")
			inventory[item]-=amount
			device.input[item]+=amount
			return result(true,"已放入 %d 件原料。" % amount)
		"waterworks_unload_input","waterworks_collect":
			var source:Dictionary=device.input if action=="waterworks_unload_input" else device.items
			if source.values().all(func(value):return value==0):return result(false,"目前沒有可取出的物品。")
			for item in source:
				if int(inventory.get(item,0))+int(source[item])>1000000000:return result(false,"背包物品已達上限。")
			for item in source:
				if source[item]>0:inventory[item]=int(inventory.get(item,0))+int(source[item])
			if action=="waterworks_unload_input":
				for item in INPUTS:source[item]=0
			else:
				source.clear()
			return result(true,"已取回物品。")
		"waterworks_toggle":
			device.enabled=not device.enabled
			return result(true,"水力加工台已啟用。" if device.enabled else "已停用新批次，進行中的加工會完成。")
		"waterworks_drain":
			if device.enabled or device.has("job") or device.water==0:return result(false,"請停用並等加工結束後再排水。")
			device.water=0
			return result(true,"加工台已排空。")
	return result(false,"找不到這項操作。")

static func result(ok:bool,message:String)->Dictionary:
	return {"ok":ok,"message":message}
