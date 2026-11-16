extends RefCounted

const MAOKONG:="maokong"
const YINGGE:="yingge"
const TEA_NPC:=Vector2i(20,20)
const TEA_NODES:=[Vector2i(25,23),Vector2i(27,23),Vector2i(29,23)]
const ROASTER:=Vector2i(23,20)
const PACKER:=Vector2i(26,20)
const POTTER:=Vector2i(20,20)
const CLAY:=Vector2i(23,23)
const KILN:=Vector2i(23,20)
const RECEIVER:=Vector2i(43,29)
const ROAST_SECONDS:={"light":8.0,"deep":12.0}
const SHIPPING_SECONDS:=20.0
const RETURN_SECONDS:=20.0
const COOLDOWN:=10.0
const KILN_SECONDS:=10.0
const POT_SECONDS:=60.0
const POT_CLAY:=4
const LIMIT:=1000000000
const JAR_USES:={"tea_jar":3,"tea_returned_jar":2,"tea_worn_jar":1,"tea_spent_jar":0}
const RETURN_ITEM:={"tea_worn_jar":"tea_spent_jar","tea_returned_jar":"tea_worn_jar","tea_jar":"tea_returned_jar"}
const FRESH:={"intro":false,"potter":false,"roast":{},"kiln":{},"packed":{},"outbound":{},"empties":0,"empty_items":{},"returning":{},"reused":false,"reuse_count":0,"auto":false,"harvest_ready":{},"clay_ready":0.0,"trials":{"jar":false,"fiber":false},"tea_discussed":false,"potter_story":false,"comparison_complete":false}
const SITES:={
	"tea_intro":["home",RECEIVER],"tea_potter":[YINGGE,POTTER],
	"tea_clay":[YINGGE,CLAY],"tea_fire":[YINGGE,KILN],"tea_fire_take":[YINGGE,KILN],"tea_repair":[YINGGE,KILN],"tea_fire_pot":[YINGGE,KILN],
	"tea_discuss":[MAOKONG,TEA_NPC],"tea_potter_story":[YINGGE,POTTER],
	"tea_pick":[MAOKONG,TEA_NODES],"tea_roast":[MAOKONG,ROASTER],
	"tea_take":[MAOKONG,ROASTER],"tea_pack":[MAOKONG,PACKER],
	"tea_ship":[MAOKONG,PACKER],"tea_sell":["home",RECEIVER],
	"tea_return":["home",RECEIVER],"tea_reclaim":[MAOKONG,PACKER],
	"tea_auto":["home",RECEIVER],
}
const OPTIONS:={"tea_roast":["light","deep"],"tea_pack":["jar","fiber","light:jar","deep:jar","light:fiber","deep:fiber"],"tea_auto":["on","off"]}

static func fresh() -> Dictionary:
	return {"players":{}}

static func own_record(state:Dictionary,actor:String) -> Dictionary:
	return state.tea_ceramics.players.get(actor,FRESH).duplicate(true)

static func valid(state:Dictionary) -> bool:
	var data=state.get("tea_ceramics")
	if not data is Dictionary or data.size()!=1 or not data.get("players") is Dictionary:return false
	var now:=float(state.time)
	for actor in data.players:
		var record=data.players[actor]
		if not state.players.has(actor) or not record is Dictionary or record.size()!=FRESH.size():return false
		for field in FRESH:
			if not record.has(field):return false
		for field in ["intro","potter","reused","auto","tea_discussed","potter_story","comparison_complete"]:
			if not record[field] is bool:return false
		if not record.intro or (record.auto and not record.reused):return false
		if not whole(record.empties,0) or not whole(record.reuse_count,0):return false
		if int(record.reuse_count)>0 and not record.reused:return false
		if not buckets_valid(record.empty_items,record.empties):return false
		if not record.trials is Dictionary or record.trials.size()!=2 or not record.trials.get("jar") is bool or not record.trials.get("fiber") is bool:return false
		if record.comparison_complete and not (record.tea_discussed and comparison_ready(record)):return false
		if not time_valid(record.clay_ready,now,COOLDOWN):return false
		if not record.harvest_ready is Dictionary:return false
		for key in record.harvest_ready:
			if key not in ["0","1","2"] or not time_valid(record.harvest_ready[key],now,COOLDOWN):return false
		if not timed_job_valid(record.roast,now,"roast") or not timed_job_valid(record.kiln,now,"kiln") or not timed_job_valid(record.returning,now,"return"):return false
		if not shipment_valid(record.packed,now,false) or not shipment_valid(record.outbound,now,true):return false
		if not record.potter and (not record.kiln.is_empty() or float(record.clay_ready)>0):return false
	return true

static func timed_job_valid(job:Variant,now:float,kind:String) -> bool:
	if not job is Dictionary:return false
	if job.is_empty():return true
	match kind:
		"roast":
			var style=job.get("style")
			return job.size()==2 and style in ROAST_SECONDS and time_valid(job.get("ready"),now,ROAST_SECONDS[style])
		"kiln":
			if job.get("kind")=="flower_pot":return job.size()==2 and time_valid(job.get("ready"),now,POT_SECONDS)
			return job.size()==2 and job.get("repair") is bool and time_valid(job.get("ready"),now,KILN_SECONDS)
		"return":return job.size()==3 and whole(job.get("count"),1) and buckets_valid(job.get("items"),job.count) and time_valid(job.get("ready"),now,RETURN_SECONDS)
	return false

static func shipment_valid(job:Variant,now:float,shipped:bool) -> bool:
	if not job is Dictionary:return false
	if job.is_empty():return true
	if job.size()!=(5 if shipped else 4) or job.get("style") not in ROAST_SECONDS or job.get("wrap") not in ["jar","fiber"]:return false
	if not job.get("reused_jar") is bool or not job.get("return_item") is String:return false
	if job.wrap=="fiber":
		if job.reused_jar or job.return_item!="":return false
	elif job.return_item not in RETURN_ITEM.values() or job.reused_jar!=(job.return_item!="tea_returned_jar"):return false
	return not shipped or time_valid(job.get("ready"),now,SHIPPING_SECONDS)

static func buckets_valid(items:Variant,total:int) -> bool:
	if not items is Dictionary:return false
	var count:=0
	for item in items:
		if item not in RETURN_ITEM.values() or not whole(items[item],1):return false
		count+=int(items[item])
	return count==total

static func migrate_15(state:Dictionary) -> bool:
	var data=state.get("tea_ceramics")
	if not data is Dictionary or data.size()!=1 or not data.get("players") is Dictionary:return false
	for record in data.players.values():
		if not record is Dictionary or record.size()!=FRESH.size()-5 or not whole(record.get("empties"),0):return false
		for field in ["kiln","packed","outbound","returning"]:
			if not record.get(field) is Dictionary:return false
		if not record.kiln.is_empty() and record.kiln.size()!=1:return false
		if not record.returning.is_empty() and (record.returning.size()!=2 or not whole(record.returning.get("count"),1)):return false
		for field in ["packed","outbound"]:
			var job:Dictionary=record[field]
			if not job.is_empty() and (job.size()!=(3 if field=="packed" else 4) or not job.get("reused_jar") is bool or job.get("wrap") not in ["jar","fiber"]):return false
		for field in ["empty_items","trials","tea_discussed","potter_story","comparison_complete"]:
			if record.has(field):return false
			record[field]=FRESH.duplicate(true)[field]
		if record.empties>0:record.empty_items={"tea_returned_jar":record.empties}
		if not record.returning.is_empty():record.returning.items={"tea_returned_jar":record.returning.count}
		if not record.kiln.is_empty():record.kiln.repair=false
		for field in ["packed","outbound"]:
			var job:Dictionary=record[field]
			if not job.is_empty():
				job.return_item="" if job.wrap=="fiber" else ("tea_worn_jar" if job.reused_jar else "tea_returned_jar")
	return true

static func time_valid(value:Variant,now:float,window:float) -> bool:
	return (value is int or value is float) and is_finite(value) and value>=0 and value<=now+window

static func whole(value:Variant,minimum:int) -> bool:
	return (value is int or value is float) and is_finite(value) and value>=minimum and value<=LIMIT and floorf(value)==value

static func apply(state:Dictionary,actor:String,action:String,region:String,p:Vector2i,extra:String) -> Dictionary:
	var site:Array=SITES[action]
	if region!=site[0] or (p not in TEA_NODES if action=="tea_pick" else p!=site[1]):
		return fail("請到對應的茶陶工坊或渡口工作點。")
	if extra not in OPTIONS.get(action,[""]):return fail("請重新選擇茶陶作業。")
	var record:=own_record(state,actor)
	if action!="tea_intro" and not record.intro:return fail("先到渡口小栗身旁讀工坊介紹信。")
	var player:Dictionary=state.players[actor]
	var now:=float(state.time)
	var result:=perform(record,player,action,p,extra,now)
	if result.ok:state.tea_ceramics.players[actor]=record
	return result

static func perform(record:Dictionary,player:Dictionary,action:String,p:Vector2i,extra:String,now:float) -> Dictionary:
	var inventory:Dictionary=player.inventory
	match action:
		"tea_intro":
			if record.intro:return fail("介紹信已讀過，可從手帳重看。")
			record.intro=true
			return ok("小栗請你到鶯歌合作陶坊借罐，再到貓空合作茶園試做一批。")
		"tea_potter":
			if record.potter:return fail("試作陶土已領過，可到供土處交換。")
			if not grant(inventory,"clay",2):return fail("陶土已達背包上限。")
			record.potter=true
			return ok("陶師給了兩份試作陶土。")
		"tea_potter_story":
			if not record.potter:return fail("先向陶師領取試作黏土。")
			if record.potter_story:return fail("這段陶師便箋已記下。")
			record.potter_story=true
			return ok("陶師：罐口磨了，就用一點黏土修補。修好的罐，還能再陪你走幾趟。")
		"tea_discuss":
			if comparison_ready(record) and not record.comparison_complete:
				record.tea_discussed=true
				record.comparison_complete=true
				return ok("茶茶記下合作成果：纖維包裝方便，陶罐則可回收再用。")
			if record.tea_discussed:return fail("完成兩種包裝的交貨並領回空罐，再來和茶茶比較。")
			record.tea_discussed=true
			return ok("茶茶：各寄一批陶罐茶和纖維茶，再領回空罐，我們一起比較。")
		"tea_clay":
			if not record.potter:return fail("先和陶師談談。")
			if now<float(record.clay_ready):return fail("供土處正在補貨。")
			if int(inventory.get("stone",0))<2:return fail("需要兩份石材交換一份陶土。")
			if not grant(inventory,"clay",1):return fail("陶土已達背包上限。")
			inventory.stone-=2
			record.clay_ready=now+COOLDOWN
			return ok("換到一份陶土。")
		"tea_fire":
			if not record.kiln.is_empty():return fail("先取出窯裡的成品。")
			if not record.potter or int(inventory.get("clay",0))<2:return fail("先找陶師，再備妥兩份陶土。")
			inventory.clay-=2
			record.kiln={"ready":now+KILN_SECONDS,"repair":false}
			return ok("陶罐已入窯。")
		"tea_repair":
			if not record.kiln.is_empty():return fail("先取出窯裡的成品。")
			if not record.potter or int(inventory.get("clay",0))<1 or int(inventory.get("tea_spent_jar",0))<1:return fail("修補需要一只待修陶罐與一份陶土。")
			inventory.clay-=1
			inventory.tea_spent_jar-=1
			record.kiln={"ready":now+KILN_SECONDS,"repair":true}
			return ok("待修陶罐已入窯。")
		"tea_fire_pot":
			if not record.kiln.is_empty():return fail("請先取出窯裡的成品。")
			if not record.potter or int(inventory.get("clay",0))<POT_CLAY:return fail("先找陶師，再準備 %d 份陶土。"%POT_CLAY)
			inventory.clay-=POT_CLAY
			record.kiln={"ready":now+POT_SECONDS,"kind":"flower_pot"}
			return ok("花盆已入窯，約 %d 秒後可取出。"%POT_SECONDS)
		"tea_fire_take":
			if record.kiln.get("kind")=="flower_pot":
				if not due(record.kiln,now):return fail("花盆還在燒製。")
				if not grant(inventory,"flower_pot",1):return fail("花盆已達背包上限。")
				record.kiln={}
				return ok("製成一只陶花盆。")
			if not due(record.kiln,now):return fail("窯裡沒有可領的陶罐。")
			if not grant(inventory,"tea_jar",1):return fail("陶罐已達背包上限。")
			var repaired:bool=record.kiln.repair
			record.kiln={}
			return ok("陶罐已修好，可再用三次。" if repaired else "製成一只可回收陶罐。")
		"tea_pick":
			var key:=str(TEA_NODES.find(p))
			if now<float(record.harvest_ready.get(key,0.0)):return fail("這叢茶還在長新葉。")
			if not grant(inventory,"tea_leaf",2):return fail("茶葉已達背包上限。")
			record.harvest_ready[key]=now+COOLDOWN
			return ok("採得兩份茶葉。")
		"tea_roast":
			if not record.roast.is_empty():return fail("先取出烘焙台上的茶。")
			if int(inventory.get("tea_leaf",0))<2:return fail("需要兩份茶葉。")
			inventory.tea_leaf-=2
			record.roast={"style":extra,"ready":now+ROAST_SECONDS[extra]}
			return ok("已開始烘焙這批茶。")
		"tea_take":
			if not due(record.roast,now):return fail("烘焙台還沒有可領的茶。")
			if not grant(inventory,"tea_"+record.roast.style,1):return fail("烘焙茶已達背包上限。")
			record.roast={}
			return ok("已取出烘焙茶。")
		"tea_pack":return pack(record,inventory,extra)
		"tea_ship":
			if record.packed.is_empty() or not record.outbound.is_empty():return fail("需要一批已包裝的茶，且上一批須先結清。")
			record.outbound=record.packed
			record.outbound.ready=now+SHIPPING_SECONDS
			record.packed={}
			return ok("茶貨已發往渡口。")
		"tea_sell":return sell(record,player,now)
		"tea_return":
			if not dispatch_return(record,now):return fail("目前沒有可發回的空罐，或上一批仍待取回。")
			return ok("空罐已發回貓空。")
		"tea_reclaim":
			if not due(record.returning,now):return fail("目前沒有已抵達的空罐。")
			var items:Dictionary=record.returning.items
			for item:String in items:
				if int(inventory.get(item,0))>LIMIT-int(items[item]):return fail("陶罐已達背包上限，整批空罐仍在取件處。")
			for item:String in items:grant(inventory,item,items[item])
			record.returning={}
			record.reused=true
			return ok("已取回空罐；待修陶罐需帶到鶯歌製罐窯修補。" if int(items.get("tea_spent_jar",0))>0 else "已取回空罐，可以再裝下一批茶。")
		"tea_auto":
			if not record.reused:return fail("先完成一次空罐回程並在貓空領回。")
			record.auto=extra=="on"
			if record.auto:dispatch_return(record,now)
			return ok("已%s空罐定期返程。"%("啟用" if record.auto else "停用"))
	return fail("無法執行茶陶作業。")

static func pack(record:Dictionary,inventory:Dictionary,extra:String) -> Dictionary:
	if not record.packed.is_empty():return fail("先寄出已包裝的茶。")
	var choices:=extra.split(":")
	var wrapping:=choices[-1]
	var style:="deep" if int(inventory.get("tea_deep",0))>0 else "light"
	if choices.size()==2:style=choices[0]
	var tea:="tea_"+style
	var material:="tea_jar" if wrapping=="jar" else "fiber"
	if wrapping=="jar":
		for candidate:String in RETURN_ITEM:
			if int(inventory.get(candidate,0))>0:
				material=candidate
				break
	if int(inventory.get(tea,0))<1 or int(inventory.get(material,0))<1:return fail("需要一份烘焙茶與對應包材。")
	inventory[tea]-=1
	inventory[material]-=1
	record.packed={"style":style,"wrap":wrapping,"reused_jar":wrapping=="jar" and material!="tea_jar","return_item":RETURN_ITEM.get(material,"")}
	return ok("已裝好這批茶。")

static func sell(record:Dictionary,player:Dictionary,now:float) -> Dictionary:
	if not due(record.outbound,now):return fail("目前沒有抵達渡口的茶貨。")
	var price:=price_for(record.outbound.style,record.outbound.wrap)
	var jar:bool=record.outbound.wrap=="jar"
	if int(player.coins)>LIMIT-price or (jar and int(record.empties)>=LIMIT) or (record.outbound.reused_jar and int(record.reuse_count)>=LIMIT):return fail("已達收款或空罐上限，茶貨仍可結清。")
	player.coins+=price
	if jar:
		record.empties+=1
		var item:String=record.outbound.return_item
		record.empty_items[item]=int(record.empty_items.get(item,0))+1
	record.trials[record.outbound.wrap]=true
	if record.outbound.reused_jar:record.reuse_count+=1
	record.outbound={}
	if record.auto:dispatch_return(record,now)
	return ok("小栗已收貨，鈴幣 +%d。"%price)

static func price_for(style:String,wrapping:String) -> int:
	return (44 if style=="deep" else 36)+(12 if wrapping=="jar" else 0)

static func dispatch_return(record:Dictionary,now:float) -> bool:
	if int(record.empties)<=0 or not record.returning.is_empty():return false
	record.returning={"count":record.empties,"ready":now+RETURN_SECONDS,"items":record.empty_items}
	record.empties=0
	record.empty_items={}
	return true

static func comparison_ready(record:Dictionary) -> bool:
	return record.trials.jar and record.trials.fiber and record.reused

static func step(state:Dictionary) -> bool:
	var changed:=false
	for record:Dictionary in state.tea_ceramics.players.values():
		if record.auto and dispatch_return(record,float(state.time)):changed=true
	return changed

static func due(job:Dictionary,now:float) -> bool:
	return not job.is_empty() and now>=float(job.ready)

static func grant(inventory:Dictionary,item:String,quantity:int) -> bool:
	var held:=int(inventory.get(item,0))
	if held>LIMIT-quantity:return false
	inventory[item]=held+quantity
	return true

static func ok(message:String) -> Dictionary:
	return {"ok":true,"message":message}

static func fail(message:String) -> Dictionary:
	return {"ok":false,"message":message}
