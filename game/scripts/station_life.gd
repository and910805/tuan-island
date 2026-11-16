extends RefCounted

const RESIDENTS := {
	"toucheng":{"name":"阿程","role":"站務員","cell":Vector2i(21,21),"hello":"上車前看一眼月台牌，才知道下一站往哪走。"},
	"ruifang":{"name":"穗禾","role":"公車調度員","cell":Vector2i(24,25),"hello":"火車門在西邊，等公車要過廣場。"},
	"jiufen":{"name":"春姨","role":"山城住戶","cell":Vector2i(23,20),"hello":"走累了就在這裡坐坐，接駁站還在前頭。"},
}
const REPAIR_COST := {"plank":2,"stone":2}
const STAGES := [
	{"region":"toucheng","title":"阿程的路線便箋","line":"替我把沿途的停靠點走一遍吧。第一站，去瑞芳找穗禾。","intro":"阿榆說你熟悉渡口。替我看看沿線的停靠點，先到瑞芳找穗禾。","goal":"收下路線便箋","action":"收下便箋"},
	{"region":"ruifang","title":"等車的長凳","line":"有了能坐的地方，轉車的人就可以安心等下一班。","intro":"長凳一腳鬆了。帶兩塊木板和兩份石材，來幫我修好它。","goal":"修好瑞芳候車長凳","action":"告訴穗禾長凳修好了"},
	{"region":"jiufen","title":"老街分一塊麵包","line":"在山城走累了，就分一塊麵包休息，再搭車去金瓜石。","intro":"米露說你會烤麵包。要不要在老街休息一下，分我一塊？","goal":"分享 1 份麵包","action":"分享麵包"},
	{"region":"toucheng","title":"走完一趟的便箋","line":"你走到金瓜石了。這株苗帶回渡口種吧，下次我們再沿線走一趟。","intro":"到金瓜石看看波波的山城，再回來跟我說說路上看見什麼。","goal":"親自抵達金瓜石後回到頭城","action":"交回旅遊便箋"},
]

static func fresh()->Dictionary:
	return {"repairs":{"toucheng":false,"ruifang":false,"jiufen":false},"players":{}}

static func fresh_record()->Dictionary:
	return {"stage":0}

static func story(state:Dictionary,token:String)->Dictionary:
	var data:Dictionary=state.get("station_life",{})
	return data.get("players",{}).get(token,data.get("own_story",fresh_record()))

static func chapter_complete(state:Dictionary)->bool:
	return state.get("picnic",false)

static func valid(state:Dictionary)->bool:
	var data:Variant=state.get("station_life")
	if not data is Dictionary or data.size()!=2 or not data.get("players") is Dictionary or not data.get("repairs") is Dictionary:return false
	if data.repairs.size()!=RESIDENTS.size():return false
	for region in RESIDENTS:
		if not data.repairs.get(region) is bool or (data.repairs[region] and not state.picnic):return false
	for token in data.players:
		var person:Variant=state.players.get(token)
		var record:Variant=data.players[token]
		if not person is Dictionary or not record is Dictionary or record.size()!=1:return false
		var stage:Variant=record.get("stage")
		if not (stage is int or stage is float) or not is_finite(float(stage)) or stage<0 or stage>4 or float(stage)!=floorf(float(stage)):return false
		if stage>0 and (not chapter_complete(state) or not person.travel_book.visited.has("toucheng")):return false
		if stage>=2 and (not data.repairs.ruifang or not person.travel_book.visited.has("ruifang")):return false
		if stage>=3 and not person.travel_book.visited.has("jiufen"):return false
		if stage==4 and not person.travel_book.visited.has("jinguashi"):return false
		record.stage=int(stage)
	return true

static func offer(state:Dictionary,token:String,region:String)->Dictionary:
	var stage:=int(story(state,token).stage)
	var person:Dictionary=state.get("players",{}).get(token,{})
	var reason:=""
	if stage==4:
		return {"title":"三站便箋","line":"下次轉車也來坐坐。","goal":"已完成沿線拜訪","action":"","extra":"4","ready":false,"reason":"已領取謝禮。"}
	var entry:Dictionary=STAGES[stage].duplicate()
	entry.line=entry.intro
	if stage==1 and state.station_life.repairs.ruifang:entry.line="長凳穩了！替我告訴九份的春姨，下回轉車有地方坐了。"
	if stage==3 and person.get("travel_book",{}).get("visited",{}).has("jinguashi"):entry.line="你把金瓜石的見聞帶回來了。便箋補齊，帶一株樹苗回渡口吧。"
	if not chapter_complete(state):
		reason="請先完成渡口野餐。"
	elif region!=entry.region:
		reason="到%s繼續拜訪。" % RESIDENTS[entry.region].name
	elif stage==1 and not state.station_life.repairs.ruifang:
		reason="先修好瑞芳候車長凳。"
	elif stage==2 and int(person.get("inventory",{}).get("bread",0))<1:
		reason="帶 1 份麵包再來。"
	elif stage==3 and not person.get("travel_book",{}).get("visited",{}).has("jinguashi"):
		reason="先親自到過金瓜石。"
	elif stage==3 and (int(person.get("coins",0))>999999920 or int(person.get("inventory",{}).get("sapling",0))>=1000000000):
		reason="鈴幣或樹苗達上限，請留出空間。"
	entry.merge({"extra":str(stage),"ready":reason.is_empty(),"reason":reason})
	return entry

static func apply(state:Dictionary,token:String,action:String,region:String,extra:String)->Dictionary:
	var person:Dictionary=state.players[token]
	var inventory:Dictionary=person.inventory
	if action=="station_repair":
		if extra!=region or not state.picnic:return result(false,"請到要修繕的站區。")
		if state.station_life.repairs[region]:return result(false,"這個站區已修好。")
		for item in REPAIR_COST:
			if int(inventory.get(item,0))<REPAIR_COST[item]:return result(false,"修繕需要木板 2、石材 2。")
		for item in REPAIR_COST:inventory[item]-=REPAIR_COST[item]
		state.station_life.repairs[region]=true
		return result(true,"公共候車處修好了。")
	var entry:=offer(state,token,region)
	if extra!=entry.extra:return result(false,"這張便箋的進度已更新。")
	if not entry.ready:return result(false,entry.reason)
	var stage:=int(extra)
	if stage==2:inventory.bread-=1
	if stage==3:
		person.coins+=80
		inventory.sapling=int(inventory.get("sapling",0))+1
	state.station_life.players[token]={"stage":stage+1}
	return result(true,"收到謝禮：80 鈴幣和 1 株樹苗。" if stage==3 else "沿線便箋已更新。")

static func result(ok:bool,message:String)->Dictionary:
	return {"ok":ok,"message":message}
