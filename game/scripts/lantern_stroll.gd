extends RefCounted
## P07: 個人蓋章、共享祝福。借來的燈籠只存在於當前活動；裝飾票獨立記帳。
const KEY:="lantern_stroll"
const ACTION:=KEY
const VIEW_KEY:="own_lantern_stroll"
const SIGN:=Vector2i(47,37)
const SITES:={
	"grove":{"cell":Vector2i(37,36),"name":"花樹小徑"},
	"meadow":{"cell":Vector2i(46,39),"name":"南邊草坡"},
	"river":{"cell":Vector2i(52,36),"name":"河畔步道"}
}
const ORDER:=["grove","meadow","river"]
const WISHES:={
	"safe":"願大家平安回家。",
	"friends":"願我們常在島上相聚。",
	"growth":"願每一粒種子安心長大。"
}
const PRIZE:="lantern_post_kit"
const DURATION:=300.0
const LIMIT:=1000000000
const REACH:=3.2
const MAX_ONLINE:=8
const MAX_RECORDS:=128
const ROUTE_BOUNDS:=Rect2i(32,28,23,17)

static func near(player:Dictionary,cell:Vector2i) -> bool:
	return Vector2(float(player.x),float(player.y)).distance_to(Vector2(cell)+Vector2(0.5,0.5))<=REACH

static func count_joined(record:Dictionary) -> int:
	var count:=0
	for member:Dictionary in record.get("members",{}).values():
		if member.joined:count+=1
	return count

static func purse(player:Dictionary) -> Dictionary:
	return player.get(KEY,{"earned":0,"spent":0,"last":0})

static func public_view(state:Dictionary) -> Dictionary:
	var tour:Dictionary=state.get(KEY,{})
	var phase:String=tour.get("phase","idle")
	var remaining:=clampi(ceili(float(tour.get("start",0.0))+DURATION-float(state.time)),0,int(DURATION)) if phase=="run" else 0
	return {"phase":phase,"round":int(tour.get("round",0)),"remaining":remaining,
		"blessings":tour.get("blessings",{}).duplicate(),"count":count_joined(tour),
		"route":tour.get("route",[]).duplicate()}

static func wearing(state:Dictionary,token:String) -> bool:
	var tour:Dictionary=state.get(KEY,{})
	return tour.get("phase","idle")=="run" and tour.get("members",{}).get(token,{}).get("joined",false)

static func view(state:Dictionary,token:String) -> Dictionary:
	var player:Dictionary=state.players.get(token,{})
	var credits:=purse(player)
	var tour:Dictionary=state.get(KEY,{})
	var member:Dictionary=tour.get("members",{}).get(token,{})
	var joined:=wearing(state,token)
	return {"joined":joined,"stamps":member.get("stamps",{}).duplicate(),
		"companion":joined and member.get("companion",false),
		"tickets":int(credits.earned)-int(credits.spent),"earned":int(credits.earned)}

static func _number(value:Variant,min_value:float,max_value:float,whole:=true) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value)>=min_value and float(value)<=max_value and (not whole or floorf(float(value))==float(value))

static func _marks(value:Variant) -> bool:
	if not value is Dictionary:return false
	for site in value:
		if not SITES.has(site) or not WISHES.has(value[site]):return false
	return true

static func _valid_route(route:Variant) -> bool:
	if not route is Array or route.size()<4 or route.size()>ROUTE_BOUNDS.get_area()*ORDER.size():return false
	var previous:=SIGN
	var next_stop:=0
	for i in route.size():
		var raw:Variant=route[i]
		if not raw is String or raw.length()>5:return false
		var parts:PackedStringArray=raw.split(",")
		if parts.size()!=2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():return false
		var cell:=Vector2i(int(parts[0]),int(parts[1]))
		if raw!="%d,%d"%[cell.x,cell.y] or not ROUTE_BOUNDS.has_point(cell):return false
		if i==0 and cell!=SIGN:return false
		if i>0 and absi(previous.x-cell.x)+absi(previous.y-cell.y)!=1:return false
		if next_stop<ORDER.size() and cell==SITES[ORDER[next_stop]].cell:next_stop+=1
		previous=cell
	return next_stop==ORDER.size() and previous==SITES[ORDER.back()].cell

static func valid(state:Dictionary) -> bool:
	var players:Dictionary=state.get("players",{})
	var raw:Variant=state.get(KEY,{})
	if not raw is Dictionary:return false
	var rid:=0
	if state.has(KEY):
		if state.get("picnic")!=true or raw.size()!=6 or not _valid_route(raw.get("route")):return false
		if raw.get("phase") not in ["run","results"] or not _number(raw.get("round"),1,LIMIT):return false
		if not _number(raw.get("start"),0,float(state.time),false) or not _marks(raw.get("blessings")):return false
		if raw.phase=="results" and float(state.time)<float(raw.start)+DURATION:return false
		if not raw.get("members") is Dictionary or raw.members.is_empty() or raw.members.size()>MAX_RECORDS:return false
		rid=int(raw.round)
		for token in raw.members:
			var member:Variant=raw.members[token]
			if not players.has(token) or not member is Dictionary or member.size()!=3:return false
			if not member.get("joined") is bool or not member.get("companion") is bool or not _marks(member.get("stamps")):return false
			if member.joined and raw.phase!="run":return false
		if count_joined(raw)>MAX_ONLINE:return false
	for token in players:
		var player:Dictionary=players[token]
		var full:bool=raw.get("members",{}).get(token,{}).get("stamps",{}).size()==ORDER.size()
		if not player.has(KEY):
			if full:return false
			continue
		var credit:Variant=player[KEY]
		if not credit is Dictionary or credit.size()!=3 or not _number(credit.get("last"),1,rid):return false
		if not _number(credit.get("earned"),1,float(credit.last)) or not _number(credit.get("spent"),0,float(credit.earned)):return false
		if (int(credit.last)==rid)!=full:return false
	return true

static func _ok(message:String) -> Dictionary:
	return {"ok":true,"message":message}

static func _fail(message:String) -> Dictionary:
	return {"ok":false,"message":message}

static func _new_member() -> Dictionary:
	return {"joined":true,"companion":false,"stamps":{}}

static func walk_site(cell:Vector2i) -> bool:
	if cell==SIGN:return true
	for site:Dictionary in SITES.values():
		if cell==site.cell:return true
	return false

static func apply(state:Dictionary,token:String,cell:Vector2i,extra:String,home:bool,connected:Dictionary,route_check:Callable) -> Dictionary:
	if not state.get("picnic",false):return _fail("渡口野餐後開放燈籠散步。")
	var player:Dictionary=state.players.get(token,{})
	if player.is_empty():return _fail("請先加入小島。")
	var args:=extra.split(":")
	var verb:=args[0]
	if verb!="leave" and (not home or not connected.has(token)):return _fail("請回風鈴渡口參加燈籠散步。")
	var tour:Dictionary=state.get(KEY,{})
	if extra=="redeem":
		if cell!=SIGN or not near(player,SIGN):return _fail("請到散步告示牌兌換裝飾。")
		var credits:=purse(player)
		if int(credits.earned)<=int(credits.spent):return _fail("集滿三個印章可拿到一張票。")
		if int(player.inventory.get(PRIZE,0))>=LIMIT:return _fail("背包的紙燈籠柱已達上限。")
		credits.spent=int(credits.spent)+1
		player.inventory[PRIZE]=int(player.inventory.get(PRIZE,0))+1
		return _ok("用一張裝飾票換到紙燈籠柱。")
	if extra=="start":
		if cell!=SIGN or not near(player,SIGN):return _fail("請到散步告示牌開始。")
		if tour.get("phase")=="run":return _fail("本輪正在散步，可以直接加入。")
		var next:=int(tour.get("round",0))+1
		if next>LIMIT:return _fail("散步輪次已達上限。")
		var route:Array=route_check.call(token,cell)
		if route.is_empty():return _fail("有景點的路被擋住了，請先留出通路。")
		state[KEY]={"round":next,"phase":"run","start":float(state.time),"blessings":{},"members":{token:_new_member()},"route":route}
		return _ok("燈籠借給你了。慢慢走訪三處景點吧。")
	if args.size()<2 or args[1]!=str(int(tour.get("round",0))) or tour.get("phase")!="run":
		return _fail("這一輪已更新，請重開路線卡。")
	if float(state.time)>=float(tour.start)+DURATION:return _fail("本輪散步已結束。")
	var roster:Dictionary=tour.members
	var member:Dictionary=roster.get(token,{})
	if verb=="join" and args.size()==2:
		if not walk_site(cell) or not near(player,cell):return _fail("請走到散步告示牌或景點再加入。")
		if member.get("joined",false):return _fail("你已經在這一輪散步了。")
		if count_joined(tour)>=MAX_ONLINE or (member.is_empty() and roster.size()>=MAX_RECORDS):return _fail("這一輪已滿。")
		if member.is_empty():roster[token]=_new_member()
		else:member.joined=true
		return _ok("借到了燈籠，之前的印章還在。")
	if not member.get("joined",false):return _fail("請先加入散步。")
	if verb=="leave" and args.size()==2:
		member.joined=false
		return _ok("已歸還燈籠。本輪印章會留著。")
	if verb=="companion" and args.size()==2:
		if count_joined(tour)!=1:return _fail("獨自散步時可以邀阿燈同行。")
		member.companion=not member.companion
		return _ok("阿燈提著燈籠加入散步。" if member.companion else "阿燈揮揮手，讓你繼續散步。")
	if verb!="stamp" or args.size()!=4 or not SITES.has(args[2]) or not WISHES.has(args[3]):
		return _fail("請選一則景點祝福。")
	var site:String=args[2]
	var wish:String=args[3]
	if cell!=SITES[site].cell or not near(player,cell):return _fail("靠近景點後再寫下祝福。")
	if member.stamps.has(site):return _fail("你已蓋過這一站的印章。")
	member.stamps[site]=wish
	tour.blessings[site]=wish
	if member.stamps.size()==ORDER.size():
		var credits:=purse(player)
		credits.earned=int(credits.earned)+1
		credits.last=int(tour.round)
		player[KEY]=credits
		return _ok("叮——三枚印章集齊，獲得一張裝飾票！")
	return _ok("叮——留下祝福，蓋上一枚印章。")

static func return_lantern(state:Dictionary,token:String) -> void:
	var member:Dictionary=state.get(KEY,{}).get("members",{}).get(token,{})
	if not member.is_empty():member.joined=false

static func step(state:Dictionary,connected:Dictionary) -> bool:
	var tour:Dictionary=state.get(KEY,{})
	if tour.get("phase")!="run":return false
	var ended:=float(state.time)>=float(tour.start)+DURATION
	if ended:tour.phase="results"
	var changed:=ended
	for token:String in tour.members:
		if tour.members[token].joined and (ended or not connected.has(token) or state.players[token].get("region","home")!="home"):
			tour.members[token].joined=false
			changed=true
	return changed
