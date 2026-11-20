extends RefCounted

const Industry=preload("res://scripts/industry.gd")
const Items=preload("res://scripts/item_catalog.gd")
const Edges=preload("res://scripts/edge_grid.gd")
const FIELD:="mill_restoration"
const JOB:="public_mill_job"
const ACTION:="restore_mill"
const SERVICE:="mill_service"
const BOARD:=Vector2i(40,29)
const SITE:=Rect2i(47,23,3,3)
const DOOR:=Vector2i(48,25)
const APPROACH:=Vector2i(48,26)
const POINT:="public_mill"
const SITE_VISIBLE:="public_mill_visible"
const BUSY:="public_mill_busy"
const COST:={"plank":12,"stone":12,"woodwork_parts":2}
const RECIPES:=["flour","feed"]

static func reserved(cell:Vector2i)->bool:
	return SITE.has_point(cell) or cell==APPROACH

## The village building is used only when the parcel was left empty in older saves.
static func site_clear(state:Dictionary)->bool:
	for y in range(SITE.position.y,APPROACH.y+1):
		for x in range(SITE.position.x,SITE.end.x):
			var tile:=Vector2i(x,y)
			if not reserved(tile):continue
			var key:="%d,%d"%[x,y]
			for layer in ["objects","ground","roofs","crops","forest"]:
				if state[layer].has(key):return false
			for side in range(4):
				if state.edges.has(Edges.key(tile,side)):return false
	return true

static func available(state:Dictionary)->bool:
	return state.get("picnic",false)==true and state.get("public_kitchen",{}).get("opened",false)==true

static func repaired(state:Dictionary)->bool:
	var materials:Dictionary=state.get(FIELD,{})
	for item:String in COST:
		if int(materials.get(item,0))!=COST[item]:return false
	return true

static func busy(state:Dictionary)->bool:
	var now:=float(state.time)
	for person:Dictionary in state.players.values():
		if float(person.get(JOB,{}).get("ready",0))>now:return true
	return false

static func contribution(state:Dictionary,inventory:Dictionary)->Dictionary:
	var collected:Dictionary=state.get(FIELD,{})
	var amounts:={}
	for item:String in COST:
		var amount:=mini(int(inventory.get(item,0)),COST[item]-int(collected.get(item,0)))
		if amount>0:amounts[item]=amount
	return amounts

static func repair(state:Dictionary,inventory:Dictionary)->Dictionary:
	if not available(state):return failure("公共廚房開張後，才能修復渡口舊磨坊。")
	if repaired(state):return failure("渡口舊磨坊已經修好了。")
	var amounts:=contribution(state,inventory)
	if amounts.is_empty():return failure("背包裡沒有工程還缺的材料。")
	var collected:Dictionary=state.get(FIELD,{})
	for item:String in amounts:
		inventory[item]-=int(amounts[item])
		collected[item]=int(collected.get(item,0))+int(amounts[item])
	state[FIELD]=collected
	return {"ok":true,"message":"渡口舊磨坊重新轉起來了！現在可以磨麵粉、做飼料。" if repaired(state) else "材料已登記，大家可以接著補齊。"}

static func service(state:Dictionary,player:Dictionary,recipe:String)->Dictionary:
	if not repaired(state):return failure("先修好渡口舊磨坊。")
	var job:Dictionary=player.get(JOB,{})
	var inventory:Dictionary=player.inventory
	if recipe=="claim":
		if job.is_empty() or float(state.time)<float(job.ready):return failure("現在沒有可領的磨坊成品。")
		var count:=int(Industry.PROCESS[job.kind].yield)
		if int(inventory.get(job.kind,0))>Items.saved_count_limit(job.kind)-count:return failure("背包放不下這批成品。")
		inventory[job.kind]=int(inventory.get(job.kind,0))+count
		player.erase(JOB)
		return {"ok":true,"message":"已領取磨坊成品。","mill_claimed":true}
	if recipe not in RECIPES:return failure("請選擇要加工的原料。")
	if not job.is_empty():return failure("先等自己的上一批完成並領取。")
	var process:Dictionary=Industry.PROCESS[recipe]
	for item:String in process.ingredients:
		if int(inventory.get(item,0))<int(process.ingredients[item]):return failure("背包裡的加工材料不足。")
	for item:String in process.ingredients:
		inventory[item]-=int(process.ingredients[item])
	player[JOB]={"kind":recipe,"ready":float(state.time)+float(process.time)}
	return {"ok":true,"message":"原料已送進磨坊，約 %d 秒後可領取。"%int(process.time)}

static func valid(state:Dictionary)->bool:
	if state.has(FIELD):
		if not state[FIELD] is Dictionary or state[FIELD].is_empty() or not available(state):return false
		for item in state[FIELD]:
			if not COST.has(item):return false
			var amount:Variant=state[FIELD][item]
			if not (amount is int or amount is float) or not is_finite(amount) or amount!=floorf(amount) or amount<1 or amount>COST[item]:return false
	for player:Dictionary in state.players.values():
		if not player.has(JOB):continue
		var job:Variant=player[JOB]
		if not repaired(state) or not job is Dictionary or job.size()!=2 or job.get("kind") not in RECIPES:return false
		var ready:Variant=job.get("ready")
		if not (ready is int or ready is float) or not is_finite(ready) or ready<0 or ready>float(state.time)+float(Industry.PROCESS[job.kind].time):return false
	return true

static func failure(message:String)->Dictionary:
	return {"ok":false,"message":message}
