extends RefCounted

const Tea=preload("res://scripts/tea_ceramics.gd")
const PLACES:={"home":"風鈴渡口","maokong":"貓空合作茶園","yingge":"鶯歌合作陶坊"}
const SITE_FOR:={"tea_intro":"home","tea_sell":"home","tea_return":"home","tea_potter":"potter","tea_clay":"clay","tea_fire":"kiln","tea_fire_take":"kiln","tea_repair":"kiln","tea_pick":"pick","tea_roast":"roast","tea_take":"roast","tea_pack":"pack","tea_ship":"pack","tea_reclaim":"pack","tea_discuss":"host","tea_potter_story":"potter"}

static func next_step(snapshot:Dictionary,own_id:String) -> Dictionary:
	var actor:Dictionary=snapshot.get("players",{}).get(own_id,{})
	if actor.is_empty():return {}
	var record:Dictionary=snapshot.get("tea_ceramics",{}).get("own_record",Tea.FRESH)
	var bag:Dictionary=actor.get("inventory",{})
	var now:=float(snapshot.get("time",0))
	var step:=choose(record,bag,now)
	var current:=str(snapshot.get("region_id","home"))
	if step.region!=current:
		step.text="前往%s。%s"%[PLACES[step.region],step.text]
	return step

static func choose(record:Dictionary,bag:Dictionary,now:float) -> Dictionary:
	if not record.get("intro",false):
		return hint("tea_intro","收下小栗的介紹信","第一章完成後，到小栗的茶單收下介紹信。")
	var outbound:Dictionary=record.get("outbound",{})
	var returning:Dictionary=record.get("returning",{})
	var roast:Dictionary=record.get("roast",{})
	var kiln:Dictionary=record.get("kiln",{})
	var packed:Dictionary=record.get("packed",{})
	if Tea.due(outbound,now):
		return hint("tea_sell","向小栗收款","茶貨已到。這批可收 %d 鈴幣。"%Tea.price_for(outbound.style,outbound.wrap))
	if Tea.due(returning,now):
		return hint("tea_reclaim","領回空陶罐","到寄運台查看罐況，待修罐可帶到陶坊。")
	if int(record.get("empties",0))>0 and returning.is_empty():
		return hint("tea_return","寄回空陶罐","請小栗寄回空罐。首趟領回後可開啟自動回程。")
	if Tea.due(roast,now):
		var style:="淺焙" if roast.style=="light" else "深焙"
		return hint("tea_take","取出%s茶"%style,"茶已烘好，到烘焙台取出。")
	if Tea.due(kiln,now):
		return hint("tea_fire_take","取出陶罐","陶罐已修補，可再用三次。" if kiln.get("repair",false) else "陶罐已燒好，到製罐窯取出。")
	if not packed.is_empty() and outbound.is_empty():
		return hint("tea_ship","把茶寄給小栗","這批茶已包好，可從寄運台發往渡口。")

	var has_tea:=int(bag.get("tea_light",0))+int(bag.get("tea_deep",0))>0
	var trials:Dictionary=record.get("trials",{})
	if trials.get("jar",false) and trials.get("fiber",false) and record.get("reused",false) and not record.get("comparison_complete",false):
		return hint("tea_discuss","和茶茶比較兩種包裝","兩種茶貨都送到了，把配送和空罐回程的經驗告訴茶茶。")
	var jar_count:=int(bag.get("tea_jar",0))+int(bag.get("tea_returned_jar",0))+int(bag.get("tea_worn_jar",0))
	if jar_count==0 and int(bag.get("tea_spent_jar",0))>0 and kiln.is_empty() and returning.is_empty():
		if int(bag.get("clay",0))>=1:return hint("tea_repair","修補待修罐","到窯邊用一份黏土修補，出窯後可再用三次。")
		if not record.get("potter_story",false):return hint("tea_potter_story","向陶師請教修補","帶待修罐去陶坊，向陶師請教修補。")
		if int(bag.get("stone",0))>=2 and now>=float(record.get("clay_ready",0)):
			return hint("tea_clay","換土修補陶罐","到備土台用兩份石材換一份黏土，修補只需一份。")
	var has_fiber:=int(bag.get("fiber",0))>0
	if has_tea and packed.is_empty() and (jar_count>0 or has_fiber):
		if int(bag.get("tea_worn_jar",0))>0:
			return hint("tea_pack","用磨損罐裝茶","這只罐還能安全配送一次，回程後可以修補。")
		if int(bag.get("tea_returned_jar",0))>0:
			return hint("tea_pack","用回收罐裝茶","用領回的空罐裝下一批茶。也可選纖維包裝。")
		if jar_count>0:
			return hint("tea_pack","包裝烘焙茶","陶罐可寄回重用。也可用纖維包裝先寄一批。")
		return hint("tea_pack","用纖維包裝","用一份纖維包茶。想試空罐回程，可到陶坊製罐。")
	var preparing:=packed.is_empty() and not has_tea
	if preparing and roast.is_empty() and int(bag.get("tea_leaf",0))>=2:
		return hint("tea_roast","開始烘焙","到烘焙台選淺焙或深焙，兩種都用兩份茶葉。")
	var first_jar:bool=not record.get("reused",false) and preparing
	var needs_jar:=jar_count==0 and (not has_fiber or first_jar)
	if needs_jar and returning.is_empty() and kiln.is_empty():
		if not record.get("potter",false):
			return hint("tea_potter","向陶師領試作黏土","首訪可以向陶師領兩份黏土，用來燒第一只罐。")
		if int(bag.get("clay",0))>=2:
			return hint("tea_fire","燒製陶罐","到製罐窯用兩份黏土燒一只陶罐。")
		if int(bag.get("stone",0))>=2 and now>=float(record.get("clay_ready",0)):
			return hint("tea_clay","到備土台交換黏土","兩份石材可以換一份黏土，攢足兩份再燒罐。")
	if preparing and roast.is_empty():
		var plant:=available_plant(record.get("harvest_ready",{}),now)
		if plant>=0:
			var title:="採茶，開始下一批" if record.get("reused",false) else "採兩份茶葉"
			return hint("tea_pick",title,"到可採的茶叢採葉，再帶回烘焙台。",Tea.TEA_NODES[plant])

	if not outbound.is_empty():
		return waiting("tea_sell","茶貨送往渡口",outbound,now,"到貨後向小栗收款。")
	if not returning.is_empty():
		return waiting("tea_reclaim","空罐正在回程",returning,now,"送達後可在寄運台領取。")
	if not roast.is_empty():
		return waiting("tea_take","茶葉烘焙中",roast,now,"烘好後到烘焙台取茶。")
	if not kiln.is_empty():
		return waiting("tea_fire_take","陶罐燒製中",kiln,now,"燒好後到製罐窯取罐。")
	if has_tea and jar_count==0 and not has_fiber:
		if int(bag.get("stone",0))<2:
			return hint("tea_pack","準備包材","備一份纖維，或帶石材到陶坊換土製罐。")
		return waiting("tea_clay","備土台補貨中",{"ready":record.get("clay_ready",now)},now,"也可用纖維包裝這批茶。")
	return hint("tea_pick","等茶叢長出新葉","目前茶叢都在生長，稍後可以再來採葉。",Tea.TEA_NODES[0])

static func available_plant(cooldowns:Dictionary,now:float) -> int:
	for index in range(Tea.TEA_NODES.size()):
		if float(cooldowns.get(str(index),0))<=now:return index
	return -1

static func waiting(action:String,title:String,job:Dictionary,now:float,detail:String) -> Dictionary:
	return hint(action,title,"約剩 %d 秒。%s"%[maxi(0,ceili(float(job.ready)-now)),detail])

static func hint(action:String,title:String,detail:String,cell:=Vector2i.ZERO) -> Dictionary:
	var location:Array=Tea.SITES[action]
	var target:Vector2i=cell if action=="tea_pick" else location[1]
	return {"title":title,"text":detail,"region":location[0],"cell":target,"site":SITE_FOR[action]}
