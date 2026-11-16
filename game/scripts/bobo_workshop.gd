extends RefCounted
const CELL:=Vector2i(23,20)
const NPC_CELL:=Vector2i(22,20)
const INPUT:=3
const OUTPUT:=1
const STEPS:=["large","medium","small"]
const ACTIONS:=["bobo_sort_start","bobo_sort_answer","bobo_sort_claim","bobo_sort_cancel"]
const LIMIT:=1000000000
const ANNEX := Rect2i(3,18,3,6)
const SITE_PAIRS := [[NPC_CELL,CELL],[Vector2i(21,19),Vector2i(22,19)],[Vector2i(23,19),Vector2i(24,19)],[Vector2i(4,20),Vector2i(5,20)]]

static func sites(state:Dictionary)->Dictionary:
	var fixed = state.get("bobo_workshop",{}).get("site",-1)
	if fixed >= 0 and fixed < SITE_PAIRS.size():return {"npc":SITE_PAIRS[int(fixed)][0],"table":SITE_PAIRS[int(fixed)][1]}
	var layer:Dictionary=state.get("regions",{}).get("jinguashi",state)
	for pair in SITE_PAIRS:
		var clear:=true
		for point:Vector2i in pair:
			var key:="%d,%d"%[point.x,point.y]
			for field in ["objects","ground","roofs","crops","forest"]:
				if layer.get(field,{}).has(key):clear=false
		if clear:return {"npc":pair[0],"table":pair[1]}
	return {"npc":SITE_PAIRS[-1][0],"table":SITE_PAIRS[-1][1]}

static func fresh()->Dictionary:
	return {"jobs":{},"done":{},"site":0}

static func valid(state:Dictionary)->bool:
	var data=state.get("bobo_workshop")
	if not data is Dictionary or data.size()!=3 or not data.get("jobs") is Dictionary or not data.get("done") is Dictionary:return false
	var site=data.get("site")
	if (not site is int and not site is float) or not is_finite(site) or floor(site)!=site or site<0 or site>=SITE_PAIRS.size():return false
	var layer:Dictionary=state.regions.jinguashi
	for point:Vector2i in SITE_PAIRS[int(site)]:
		var key:="%d,%d"%[point.x,point.y]
		for field in ["objects","ground","roofs","crops","forest"]:
			if layer[field].has(key):return false
	for actor in data.done:
		if not state.players.has(actor) or not data.done[actor] is bool or not data.done[actor]:return false
	for actor in data.jobs:
		var job=data.jobs[actor]
		if not state.players.has(actor) or not job is Dictionary or job.size()!=1:return false
		var step=job.get("step")
		if (not step is int and not step is float) or not is_finite(step) or step<0 or step>STEPS.size() or floor(step)!=step:return false
	return true

static func apply(state:Dictionary,actor:String,action:String,extra:String)->Dictionary:
	var workshop:Dictionary=state.bobo_workshop
	var inventory:Dictionary=state.players[actor].inventory
	var job:Dictionary=workshop.jobs.get(actor,{})
	if action!="bobo_sort_answer" and not extra.is_empty():return response(false,"請重新選擇整理操作。")
	if action=="bobo_sort_start":
		if not job.is_empty():return response(false,"請先處理目前的礦樣。")
		if int(inventory.get("gold_ore",0))<INPUT:return response(false,"需三份含金礦料。")
		inventory.gold_ore-=INPUT
		workshop.jobs[actor]={"step":0}
		return response(true,"請按照標籤將礦樣分格。")
	if job.is_empty():return response(false,"目前沒有整理中的礦樣。")
	var step:=int(job.step)
	if action=="bobo_sort_answer":
		if step>=STEPS.size() or extra!="%d:%s"%[step,STEPS[step]]:
			return response(false,"請依礦樣標籤選擇這一輪的格子。")
		job.step=step+1
		return response(true,"已放入對應格子。")
	if action=="bobo_sort_claim" and step!=STEPS.size():return response(false,"請完成三輪整理。")
	var output:="gold_ore" if action=="bobo_sort_cancel" else "gold_sample"
	var quantity:=INPUT if action=="bobo_sort_cancel" else OUTPUT
	if int(inventory.get(output,0))>LIMIT-quantity:return response(false,"背包已達上限，礦樣仍在工作桌。")
	inventory[output]=int(inventory.get(output,0))+quantity
	workshop.jobs.erase(actor)
	if action=="bobo_sort_claim":workshop.done[actor]=true
	return response(true,"已取回原料。" if action=="bobo_sort_cancel" else "已領取金工收藏樣本。")

static func response(ok:bool,message:String)->Dictionary:
	return {"ok":ok,"message":message}
