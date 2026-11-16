extends RefCounted

const Freight=preload("res://scripts/mine_freight.gd")
const REGIONS := ["mine_4","mine_5"]
const ACTIONS := ["mine_auto_config","mine_auto_toggle","mine_auto_clear"]
const MAX_BYTES := 256

static func fresh()->Dictionary:
	return {"routes":{}}

static func cell_valid(cell:Variant)->bool:
	if not cell is String:return false
	var parts:PackedStringArray=cell.split(",")
	if parts.size()!=2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():return false
	var x:=int(parts[0])
	var y:=int(parts[1])
	return x>=0 and x<80 and y>=0 and y<60 and cell=="%d,%d"%[x,y]

static func reference_valid(reference:Variant)->bool:
	return reference is Dictionary and reference.size()==2 and cell_valid(reference.get("cell")) and Freight.valid_id(reference.get("id"))

static func valid(state:Dictionary)->bool:
	var data:Variant=state.get("mine_auto_freight")
	if not data is Dictionary or data.size()!=1 or not data.get("routes") is Dictionary:return false
	for actor in data.routes:
		var route:Variant=data.routes[actor]
		if not state.players.has(actor) or int(state.mine_depths.unlocked)<5:return false
		if not route is Dictionary or route.size()!=7 or route.get("region") not in REGIONS:return false
		if not reference_valid(route.get("source")) or not reference_valid(route.get("target")):return false
		if route.get("item") not in Freight.ITEMS or not route.get("enabled") is bool:return false
		if not Freight.whole(route.get("reserve"),Freight.LIMIT) or not Freight.whole(route.get("batch"),Freight.CAPACITY) or route.batch<1:return false
		if route.reserve+route.batch>Freight.LIMIT:return false
	return true

static func matching(objects:Dictionary,reference:Dictionary,actor:String)->Dictionary:
	var chest:Dictionary=objects.get(reference.cell,{})
	if chest.get("type")!="private_chest" or chest.get("owner")!=actor or chest.get("freight_id")!=reference.id:return {}
	return chest

static func status(state:Dictionary,actor:String)->Dictionary:
	var route:Dictionary=state.mine_auto_freight.routes.get(actor,{})
	if route.is_empty():return hint("unconfigured","尚未設定裝運路線。")
	if not route.enabled:return hint("off","自動裝運已停用。")
	var job:Dictionary=state.mine_freight.jobs.get(actor,{})
	match job.get("status"):
		"transit":return hint("transit","上一批貨物仍在途中。")
		"draft":return hint("manual_draft","請先完成手動貨單。")
		"held":return hint("held","請先到渡口公告板領回貨物。")
	var source:=matching(state.regions[route.region].objects,route.source,actor)
	if source.is_empty():return hint("missing_source","來源箱不在原位或已更換；放回原箱或重新設定。")
	var target:=matching(state.objects,route.target,actor)
	var available:=maxi(0,int(source.items.get(route.item,0))-int(route.reserve))
	if target.is_empty():return hint("missing_target","目的箱不在原位或已更換；放回原箱或重新設定。",available)
	if not Freight.can_fit(target.items,{route.item:int(route.batch)}):return hint("target_full","目的箱空間不足，貨物留在來源箱。",available)
	if available<int(route.batch):return hint("waiting","等來源箱存足下一批。",available)
	return hint("ready","已備齊下一批貨物。",available)

static func hint(id:String,message:String,available:int=0)->Dictionary:
	return {"id":id,"text":message,"available":available}

static func step(state:Dictionary)->bool:
	var changed:=false
	for actor in state.mine_auto_freight.routes:
		if status(state,actor).id!="ready":continue
		var route:Dictionary=state.mine_auto_freight.routes[actor]
		var source:=matching(state.regions[route.region].objects,route.source,actor)
		var quantity:=int(route.batch)
		var item:String=route.item
		source.items[item]-=quantity
		if source.items[item]==0:source.items.erase(item)
		state.mine_freight.jobs[actor]={"status":"transit","items":{item:quantity},"target":route.target.duplicate(true),"ready":float(state.time)+Freight.TRANSIT}
		changed=true
	return changed

static func apply(state:Dictionary,actor:String,action:String,extra:String,region:String,local_objects:Dictionary,home_objects:Dictionary)->Dictionary:
	var routes:Dictionary=state.mine_auto_freight.routes
	var route:Dictionary=routes.get(actor,{})
	if action!="mine_auto_config":
		if not extra.is_empty() or route.get("region")!=region:return Freight.result(false,"請回到設定路線的礦務站。")
		if action=="mine_auto_toggle":
			route.enabled=not route.enabled
			return Freight.result(true,"已啟用自動裝運。" if route.enabled else "已停用新批次，已發車的貨物仍會送達。")
		if route.enabled:return Freight.result(false,"請先停用自動裝運。")
		routes.erase(actor)
		return Freight.result(true,"已清除裝運設定。")
	if route.get("enabled",false):return Freight.result(false,"請先停用原有裝運路線。")
	if extra.length()>MAX_BYTES or extra.to_utf8_buffer().size()>MAX_BYTES:return Freight.result(false,"裝運設定過長。")
	var config:Variant=JSON.parse_string(extra)
	if not config is Dictionary or config.size()!=5:return Freight.result(false,"無效的裝運設定。")
	if not cell_valid(config.get("source")) or not cell_valid(config.get("target")) or config.get("item") not in Freight.ITEMS:return Freight.result(false,"請選擇私人箱與礦料。")
	if not Freight.whole(config.get("reserve"),Freight.LIMIT) or not Freight.whole(config.get("batch"),Freight.CAPACITY) or config.batch<1 or config.reserve+config.batch>Freight.LIMIT:return Freight.result(false,"保留量或每批件數超出範圍。")
	var source:Dictionary=local_objects.get(config.source,{})
	var target:Dictionary=home_objects.get(config.target,{})
	for chest in [source,target]:
		if chest.get("type")!="private_chest" or chest.get("owner")!=actor:return Freight.result(false,"兩端都須使用自己的私人箱。")
	var source_id:String=source.get("freight_id",Crypto.new().generate_random_bytes(16).hex_encode())
	var target_id:String=target.get("freight_id",Crypto.new().generate_random_bytes(16).hex_encode())
	if not Freight.valid_id(source_id) or not Freight.valid_id(target_id):return Freight.result(false,"無法登記私人箱。")
	source.freight_id=source_id
	target.freight_id=target_id
	routes[actor]={"region":region,"source":{"cell":config.source,"id":source_id},"target":{"cell":config.target,"id":target_id},"item":config.item,"reserve":int(config.reserve),"batch":int(config.batch),"enabled":false}
	return Freight.result(true,"已設定裝運路線，啟用後開始等待貨物。")
