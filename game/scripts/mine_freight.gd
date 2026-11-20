extends RefCounted
const Mines=preload("res://scripts/mine_depths.gd")
const BoxCapacity=preload("res://scripts/box_capacity.gd")
const ChestHistory=preload("res://scripts/chest_history.gd")
## Actor label written to wooden chest history for freight deliveries and auto-freight pickups.
const HISTORY_LABEL:="礦務貨運"
const LOAD_CELL := Mines.SERVICE
const CLAIM_CELL := Vector2i(40,29)
const CAPACITY := 32
const TRANSIT := 60.0
const ITEMS := ["stone","copper_ore","gold_ore"]
const ACTIONS := ["freight_load","freight_unload","freight_target","freight_dispatch","freight_claim","freight_cancel"]
const LIMIT := 1000000000

static func fresh() -> Dictionary:
	return {"jobs":{}}

static func draft() -> Dictionary:
	return {"status":"draft","items":{},"target":{},"ready":0.0}

static func total(items: Dictionary) -> int:
	var sum := 0
	for amount in items.values():sum+=int(amount)
	return sum

static func valid_id(value: Variant) -> bool:
	return value is String and value.length()==32 and value.is_valid_hex_number(false)

static func whole(value: Variant, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(value) and value>=0 and value<=maximum and floor(value)==value

static func valid(state: Dictionary) -> bool:
	var freight = state.get("mine_freight")
	if not freight is Dictionary or freight.size()!=1 or not freight.get("jobs") is Dictionary:return false
	if not freight.jobs.is_empty() and int(state.mine_depths.unlocked)<5:return false
	for actor in freight.jobs:
		var job = freight.jobs[actor]
		if not state.players.has(actor) or not job is Dictionary or job.size()!=4:return false
		if job.get("status") not in ["draft","transit","held","delivered"] or not job.get("items") is Dictionary or not job.get("target") is Dictionary:return false
		for item in job.items:
			if item not in ITEMS or not whole(job.items[item],CAPACITY) or job.items[item]==0:return false
		if total(job.items)>CAPACITY:return false
		var ready = job.get("ready")
		if (not ready is int and not ready is float) or not is_finite(ready) or ready<0 or ready>float(state.time)+TRANSIT:return false
		if (job.status=="draft") != (ready==0):return false
		if job.status in ["held","delivered"] and ready>float(state.time):return false
		if job.status!="draft" and (job.items.is_empty() or job.target.is_empty()):return false
		if not job.target.is_empty():
			if job.target.size()!=2 or not job.target.get("cell") is String or not valid_id(job.target.get("id")):return false
			var coords: PackedStringArray = job.target.cell.split(",")
			if coords.size()!=2 or not coords[0].is_valid_int() or not coords[1].is_valid_int():return false
			if int(coords[0]) not in range(80) or int(coords[1]) not in range(60) or job.target.cell!="%d,%d"%[int(coords[0]),int(coords[1])]:return false
	return true

static func own_chests(home: Dictionary, actor: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for cell in home:
		var box: Dictionary = home[cell]
		if box.type=="private_chest" and box.owner==actor:result.append({"cell":cell,"id":box.get("freight_id","")})
	return result

static func can_fit(destination: Dictionary, items: Dictionary) -> bool:
	for item in items:
		if int(destination.get(item,0)) > LIMIT-int(items[item]):return false
	return true

## Same as can_fit for a private chest destination: also honours the 16-slot rule
## (a job may carry several ore kinds, each new kind needs a free slot).
static func can_fit_chest(destination: Dictionary, items: Dictionary) -> bool:
	return can_fit(destination, items) and BoxCapacity.slot_ok(destination, items)

static func transfer(destination: Dictionary, items: Dictionary) -> void:
	for item in items:destination[item]=int(destination.get(item,0))+int(items[item])

## One history row per item of a committed chest transfer (sorted item order).
static func record_history(chest: Dictionary, items: Dictionary, depositing: bool, now: float) -> void:
	var names: Array = items.keys()
	names.sort()
	for item in names:
		if int(items[item])>0:ChestHistory.record(chest,HISTORY_LABEL,str(item),int(items[item]),depositing,now)

static func step(state: Dictionary) -> bool:
	var changed := false
	for actor in state.mine_freight.jobs:
		var job: Dictionary = state.mine_freight.jobs[actor]
		if job.status!="transit" or float(job.ready)>float(state.time):continue
		var chest: Dictionary = state.objects.get(job.target.cell,{})
		if chest.get("type")=="private_chest" and chest.get("owner")==actor and chest.get("freight_id")==job.target.id and can_fit_chest(chest.items,job.items):
			transfer(chest.items,job.items)
			record_history(chest,job.items,true,float(state.time))
			job.status="delivered"
		else:job.status="held"
		changed=true
	return changed

static func apply(state: Dictionary, actor: String, action: String, cell: Vector2i, extra: String, region: String, home_objects: Dictionary) -> Dictionary:
	var jobs: Dictionary=state.mine_freight.jobs
	var job: Dictionary=jobs.get(actor,{})
	var inv: Dictionary=state.players[actor].inventory
	if action=="freight_claim":
		if region!="home" or cell!=CLAIM_CELL or not extra.is_empty() or job.get("status")!="held":return result(false,"目前沒有可在渡口公告板領回的貨物。")
		if not can_fit(inv,job.items):return result(false,"背包空間不足，貨物仍留在公告板。")
		transfer(inv,job.items)
		job.status="delivered"
		return result(true,"已領回全部運礦貨物。")
	if region not in ["mine_4","mine_5"] or cell!=LOAD_CELL or int(state.mine_depths.unlocked)<5:return result(false,"請先修好第四層軌道，再到第四或第五層裝貨。")
	if action=="freight_load" and (job.is_empty() or job.status=="delivered"):job=draft()
	if job.is_empty() or job.status!="draft":return result(false,"目前沒有可修改的裝貨單。")
	if action=="freight_cancel":
		if not extra.is_empty() or not job.items.is_empty():return result(false,"請先卸回貨物，才能取消空貨單。")
		jobs.erase(actor)
		return result(true,"已取消空貨單。")
	if action=="freight_target":
		var chest: Dictionary=home_objects.get(extra,{})
		if chest.get("type")!="private_chest" or chest.get("owner")!=actor:return result(false,"請選擇自己在渡口的私人箱。")
		if not chest.has("freight_id"):
			var generated := Crypto.new().generate_random_bytes(16).hex_encode()
			if not valid_id(generated):return result(false,"無法登記私人箱。")
			chest.freight_id=generated
		job.target={"cell":extra,"id":chest.freight_id}
		return result(true,"已選定送達的私人箱。")
	if action=="freight_dispatch":
		if not extra.is_empty() or job.target.is_empty() or job.items.is_empty():return result(false,"請先裝貨並選擇目的箱。")
		job.status="transit"
		job.ready=float(state.time)+TRANSIT
		return result(true,"已發車，約 60 遊戲秒送達渡口。")
	var parts:=extra.split(":")
	if parts.size()!=2 or parts[0] not in ITEMS or not parts[1].is_valid_int():return result(false,"無效的貨物或數量。")
	var item:String=parts[0]
	var amount:=int(parts[1])
	if amount<1 or amount>CAPACITY or parts[1]!=str(amount):return result(false,"無效的貨物數量。")
	if action=="freight_load":
		if int(inv.get(item,0))<amount or total(job.items)+amount>CAPACITY:return result(false,"貨箱空間或持有量不足。")
		inv[item]-=amount
		job.items[item]=int(job.items.get(item,0))+amount
		jobs[actor]=job
		return result(true,"已裝入運礦貨箱。")
	if int(job.items.get(item,0))<amount or int(inv.get(item,0))>LIMIT-amount:return result(false,"貨箱數量或背包空間不足。")
	inv[item]=int(inv.get(item,0))+amount
	job.items[item]-=amount
	if job.items[item]==0:job.items.erase(item)
	return result(true,"已卸回背包。")

static func result(ok: bool, message: String) -> Dictionary:
	return {"ok":ok,"message":message}
