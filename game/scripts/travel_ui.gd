extends RefCounted
const World=preload("res://scripts/world.gd")
const Transit=preload("res://scripts/transit.gd")
const Map=preload("res://scripts/taiwan_map.gd")
const Art=preload("res://scripts/transit_art.gd")
const Shell=preload("res://scripts/life_ui_shell.gd")
const Pixel=preload("res://scripts/inventory_pixel_theme.gd")
const FlowerNursery=preload("res://scripts/flower_nursery.gd")
const SaltPan=preload("res://scripts/salt_pan.gd")
const NOTES:={
	"home":"搭交通船渡海，回到澎湖・望安的風鈴渡口。海上航程與陸上轉乘由遊戲合併、縮短成一段；收成與礦料都在背包裡，回程免費。",
	"lanyang":"從風鈴渡口搭交通船渡海到宜蘭，再轉往蘭陽試作田的水圳找星禾。這是遊戲合併、縮短後的航程與轉乘；田區與家裡共用背包，各區設備持續運作。",
	"toucheng":"從車站街口走到北側月台，可前往瑞芳或轉乘礁溪。",
	"jiaoxi":"從頭城搭車到礁溪，再轉地方接駁到暖泉高地。暖泉溪適合白天垂釣，高地冷泉可在冬季尋找雪點鱒魚。",
	"bamboo_grove":"從貓空合作茶園沿遊戲中的山間步道進入霧竹溪谷。竹澗晨間起微風，適合尋找竹影香魚。",
	"star_garden":"沿田尾合作花圃的步道走到映星池，入夜後可尋找星斑魚。",
	"ruifang":"出鐵路門後，穿過廣場到東南側公車站，再上山去九份。",
	"jiufen":"在公車站下車，沿石階老街前往東側的金瓜石接駁站。",
	"jinguashi":"到合作礦場拜訪波波。採礦請帶強化石鎬，大宗礦料可另外寄運。",
	"maokong":"經臺北轉乘到文山貓空。茶茶的合作茶園有採茶、烘焙與寄運工作角；交通以遊戲合併轉乘呈現。",
	"yingge":"經臺北轉乘到新北鶯歌。到合作陶坊製作能反覆回收的茶罐；陶土由工坊供應，不在街道或古蹟採挖。",
	"tianwei":"經縱貫線鐵路南下彰化，再轉地方接駁到虛構的田尾合作花圃。田尾以花卉苗木聞名；這裡的花農與花圃都是原創，交通以遊戲合併轉乘呈現。",
	"beimen":"從田尾的花圃接駁點出發，經縱貫線鐵路南下，再轉沿海公車到臺南北門的虛構鹽風合作鹽田。北門沿海以曬鹽歷史聞名；這裡的鹽田與阿曬都是原創。這是遊戲合併、縮短後的旅程，沿途轉乘不一一列出。"
}
# 依出發地改寫的說明：從田尾回鶯歌是北上，不經臺北。
const ROUTE_NOTES:={
	"bamboo_grove>maokong":"從溪谷步道口沿茶園步道走回貓空合作茶園。到貓空轉乘站可再前往鶯歌或瑞芳。",
	"star_garden>tianwei":"從庭園步道口走回田尾合作花圃。到花圃接駁點可再轉乘鶯歌或北門。",
	"jiaoxi>toucheng":"從暖泉高地的回程站牌搭地方接駁，再轉回頭城北側月台。",
	"tianwei>yingge":"從虛構的花圃接駁點轉地方接駁，再經縱貫線鐵路北上回到新北鶯歌；交通以遊戲合併轉乘呈現，不是直接相鄰。",
	"beimen>tianwei":"從鹽田站牌搭沿海公車，經縱貫線鐵路北上，再轉花圃接駁回到田尾；這是遊戲合併、縮短後的旅程，沿途轉乘不一一列出。",
	"beimen>home":"沿旅圖上的轉乘路線北上，再搭交通船渡海回到澎湖・望安的風鈴渡口。這是遊戲合併、縮短後的旅程，沿途轉乘不一一列出；回程免費，背包隨行。",
	"home>toucheng":"從風鈴渡口搭交通船渡海，再轉乘到頭城車站街口。這是遊戲合併、縮短後的航程與轉乘，沿途不一一列出。",
	"lanyang>home":"從蘭陽試作田轉乘到海邊，再搭交通船渡海回到澎湖・望安的風鈴渡口。這是遊戲合併、縮短後的航程與轉乘；回程免費，背包隨行。"
}
# 出生島（澎湖・望安）與宜蘭之間的旅程一律是交通船加陸上轉乘的合併旅程，不是步行。
const HOME_LANYANG_MODE:="交通船"
# 碼頭修好後的合作小船（Transit.options 的 mode「合作小船」）：渡海加轉乘的合併航程，不寫航線、時刻或業者。
const BOAT_MODE:="合作小船"
const BOAT_NOTES:={
	"home>jiaoxi":"從風鈴渡口搭合作小船渡海，再轉乘到礁溪・暖泉高地。這是遊戲合併、縮短後的航程與轉乘，沿途不一一列出。暖泉溪適合白天垂釣，高地冷泉可在冬季尋找雪點鱒魚。",
	"home>bamboo_grove":"從風鈴渡口搭合作小船渡海，再轉乘到貓空・霧竹溪谷。這是遊戲合併、縮短後的航程與轉乘，沿途不一一列出。竹澗晨間起微風，適合尋找竹影香魚。",
	"jiaoxi>home":"從暖泉高地轉乘到海邊，再搭合作小船渡海回到澎湖・望安的風鈴渡口。這是遊戲合併、縮短後的航程與轉乘；回程免費，背包隨行。",
	"bamboo_grove>home":"從霧竹溪谷轉乘到海邊，再搭合作小船渡海回到澎湖・望安的風鈴渡口。這是遊戲合併、縮短後的航程與轉乘；回程免費，背包隨行。"
}

## 車票說明：合作小船依航程改寫，其餘依出發地或目的地。
static func note(origin:String,destination:String,mode:String="")->String:
	if mode==BOAT_MODE and BOAT_NOTES.has(origin+">"+destination):return str(BOAT_NOTES[origin+">"+destination])
	return str(ROUTE_NOTES.get(origin+">"+destination,NOTES.get(destination,"")))

# 用戶端快照只帶自己的花圃紀錄（flower_nursery.own.own_record）；伺服器端完整狀態則交給 FlowerNursery。
static func flower_open(s:Dictionary,token:String)->bool:
	var nursery=s.get("flower_nursery",{})
	if nursery is Dictionary and nursery.get("own") is Dictionary and nursery.own.get("own_record") is Dictionary:
		return nursery.own.own_record.get("letter",false)==true
	return FlowerNursery.route_open(s,token)

# 鹽田來信：用戶端快照只帶自己的鹽田紀錄（salt_pan.own.record）；伺服器端完整狀態交給 SaltPan。
static func salt_open(s:Dictionary,token:String)->bool:
	var salt=s.get("salt_pan",{})
	if salt is Dictionary and salt.get("own") is Dictionary:
		for key in ["record","own_record"]:
			if salt.own.get(key) is Dictionary:return salt.own[key].get("letter",false)==true
	return SaltPan.route_open(s,token)


static func nearest(region:String,pos:Vector2)->String:
	var id:=""
	var distance:=INF
	for key in Transit.points(region):
		var point:Vector2=Vector2(Transit.points(region)[key].cell)+Vector2(0.5,0.5)
		if pos.distance_to(point)<distance:id=key;distance=pos.distance_to(point)
	return id

static func open(app,station_id:String="",selected:String="")->void:
	var s:Dictionary=app.session.snapshot
	var person:Dictionary=s.get("players",{}).get(app.session.own_id,{})
	if person.is_empty():return
	var region:=str(s.get("region_id","home"))
	if station_id.is_empty():station_id=nearest(region,Vector2(person.x,person.y))
	var content:VBoxContainer=app._open_modal("旅途車票 · 選一站出發")
	app.modal.set_meta("life_modal_layout","travel_map")
	app.modal.set_meta("travel_body",content)
	app.modal.set_meta("travel_station",station_id)
	app.modal.set_meta("travel_selected",selected)
	app.modal.theme=Pixel.make(app.hud.theme)
	refresh(app)

static func open_toward(app,destination:String) -> void:
	var route:=route_toward(app.session.snapshot,app.session.own_id,destination)
	app._travel_menu(str(route.get("station","")),str(route.get("selection","")))

static func route_toward(snapshot:Dictionary,owner:String,destination:String) -> Dictionary:
	var person:Dictionary=snapshot.get("players",{}).get(owner,{})
	if person.is_empty():return {}
	var region:=str(snapshot.get("region_id","home"))
	var position:=Vector2(person.x,person.y)
	var book:Dictionary=person.get("travel_book",Transit.fresh())
	var path:=Transit.intermediate(region,destination)
	var next_stop:=str(path[0]) if not path.is_empty() else destination
	var station:=""
	var selection:=""
	var distance:=INF
	# Prefer an available through ticket. Otherwise choose the next actual leg.
	for target in [destination,next_stop]:
		for id in Transit.points(region):
			var choices:=Transit.options(region,book,snapshot.get("picnic",false),id,
				Transit.tea_unlocked(snapshot),flower_open(snapshot,owner),
				salt_open(snapshot,owner),Transit.star_garden_open(snapshot),Transit.boat_open(snapshot))
			if not choices.any(func(option):return option.region==target):continue
			var stop:Vector2=Vector2(Transit.points(region)[id].cell)+Vector2(0.5,0.5)
			if position.distance_squared_to(stop)<distance:
				station=id
				selection=target
				distance=position.distance_squared_to(stop)
		if not station.is_empty():break
	return {} if station.is_empty() else {"station":station,"selection":selection}

static func words(app,parent:Node,text:String,size:int=15)->Label:
	var label:Label=app.label(text,size)
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label

static func focus_departure(app)->bool:
	if not is_instance_valid(app.modal) or not app.modal.has_meta("travel_body"):return false
	var depart:=app.modal.find_child("TravelDepart",true,false) as Button
	if is_instance_valid(depart) and depart.is_visible_in_tree() and not depart.disabled:
		depart.grab_focus()
		var scroll:=app.modal.find_child("ModalScroll",true,false) as ScrollContainer
		if scroll!=null:scroll.ensure_control_visible(depart)
	return true

static func refresh(app)->void:
	if not is_instance_valid(app.modal) or not app.modal.has_meta("travel_body"):return
	var s:Dictionary=app.session.snapshot
	var p:Dictionary=s.get("players",{}).get(app.session.own_id,{})
	if p.is_empty():return
	var region:=str(s.get("region_id","home"))
	var station_id:=str(app.modal.get_meta("travel_station",""))
	var point:Dictionary=Transit.points(region).get(station_id,{})
	var cell:Vector2i=point.get("cell",World.REGIONS.exit_cell(region))
	var near:=Vector2(p.x,p.y).distance_to(Vector2(cell)+Vector2(0.5,0.5))<=3.2
	var unlocked:bool=s.get("picnic",false)
	var book:Dictionary=p.get("travel_book",Transit.fresh())
	var flowers:=flower_open(s,str(app.session.own_id))
	var salts:=salt_open(s,str(app.session.own_id))
	var stars:=Transit.star_garden_open(s)
	var boat:=Transit.boat_open(s)
	var dock_stage:=int(s.get("dock_stage",0))
	var options:Array[Dictionary]=Transit.options(region,book,true,station_id,Transit.tea_unlocked(s),flowers,salts,stars,boat)
	if region in ["home","lanyang"]:
		options.push_front({"region":"lanyang" if region=="home" else "home","label":"蘭陽試作田" if region=="home" else "風鈴渡口","mode":HOME_LANYANG_MODE,"direct":true,"via":[],"action":"travel"})
	var selected:=str(app.modal.get_meta("travel_selected",""))
	if not options.any(func(option):return option.region==selected):
		selected=str(options[0].region) if not options.is_empty() else ""
		for option in options:
			if option.region in point.get("links",[]) and option.region!="home":selected=option.region;break
		if region=="home":selected="lanyang"
		app.modal.set_meta("travel_selected",selected)
	var commissions:Dictionary=s.get("own_outlying_commissions",{})
	var mining_pick:=World.active_mining_pick(p.inventory)
	var fingerprint:=JSON.stringify([region,station_id,selected,near,unlocked,flowers,salts,stars,Transit.tea_unlocked(s),dock_stage,book,mining_pick,commissions,World.JINGUASHI_REVISIT.unlocked(s) if region=="jinguashi" else false,World.SALT_REVISIT.unlocked(s) if region==SaltPan.REGION else false])
	if app.modal.get_meta("travel_fingerprint","")==fingerprint:return
	app.modal.set_meta("travel_fingerprint",fingerprint)
	var content:VBoxContainer=app.modal.get_meta("travel_body")
	var focused:=content.get_viewport().gui_get_focus_owner()
	var focus_name:String=focused.name if is_instance_valid(focused) and content.is_ancestor_of(focused) else ""
	for child in content.get_children():content.remove_child(child);child.queue_free()
	var row:=HBoxContainer.new();row.add_theme_constant_override("separation",20);content.add_child(row)
	var map:=Map.new();map.set_meta("current_region",region);map.set_meta("travel_book",book);map.set_meta("flower_open",flowers);map.set_meta("salt_open",salts);row.add_child(map)
	add_map_marks(map,region,selected,known_reserves(region,book,Transit.tea_unlocked(s),flowers,stars))
	var right:=VBoxContainer.new();right.size_flags_horizontal=Control.SIZE_EXPAND_FILL;right.add_theme_constant_override("separation",10);row.add_child(right)
	words(app,right,str(point.get("label","田區路口"))+" · 往返免費",20)
	if region=="home" and station_id=="ferry":
		var dock_copy:=["碼頭待修 · 到公告板查看工程","碼頭已修好 · 等待小船完工","小船已就緒 · 可航往霧竹與暖泉"]
		var status:=Label.new()
		status.name="DockTravelStatus"
		status.text=dock_copy[clampi(dock_stage,0,2)]
		status.add_theme_font_size_override("font_size",14)
		right.add_child(status)
	var destinations:=HFlowContainer.new();destinations.name="TravelDestinations";destinations.add_theme_constant_override("h_separation",8);destinations.add_theme_constant_override("v_separation",6);right.add_child(destinations)
	var chosen:Dictionary={}
	for option in options:
		var target:=str(option.region)
		if target==selected:chosen=option
		var button:Button=app.button(str(option.label),func():app.modal.set_meta("travel_selected",target);refresh(app))
		button.name="SelectRoute_"+target;button.toggle_mode=true;button.button_pressed=target==selected
		button.custom_minimum_size=Vector2(150,40);button.add_theme_font_size_override("font_size",14)
		button.icon=Art.icon("station") if target in Transit.LOCAL else Shell.icon("home" if target=="home" else ("pick" if target=="jinguashi" else "seed"))
		button.expand_icon=true;button.add_theme_constant_override("icon_max_width",28)
		destinations.add_child(button)
	var card:=PanelContainer.new();card.name="TravelTicket";card.add_theme_stylebox_override("panel",Pixel.paper_style());right.add_child(card)
	var ticket:=VBoxContainer.new();ticket.add_theme_constant_override("separation",8);card.add_child(ticket)
	if not chosen.is_empty():
		var title:=HBoxContainer.new();ticket.add_child(title)
		var mode:=str(chosen.mode)
		var artwork:Texture2D=Art.icon(selected) if selected in Transit.LOCAL else (Shell.icon("home") if selected=="home" else Shell.icon("pick" if selected=="jinguashi" else "seed"))
		if mode.contains("船") or mode=="火車" or mode.contains("公車"):
			artwork=arrival_art(mode)
		var illustration:=Shell.picture(artwork,72)
		illustration.name="TravelTicketArt"
		title.add_child(illustration)
		var heading:=VBoxContainer.new();heading.size_flags_horizontal=Control.SIZE_EXPAND_FILL;title.add_child(heading)
		words(app,heading,str(chosen.label),21)
		var known:bool=book.get("visited",{}).has(selected)
		words(app,heading,mode+" · "+("已走訪" if known else ("保留原通行" if mode=="既有通行" else "這一站的新風景")),14)
		var itinerary:=PackedStringArray([World.REGIONS.label(region)])
		for via in chosen.get("via",[]):itinerary.append(World.REGIONS.label(via))
		itinerary.append(str(chosen.label))
		words(app,ticket," → ".join(itinerary),14)
		words(app,ticket,note(region,selected,mode),15)
		if selected=="jinguashi" and mining_pick.is_empty():
			words(app,ticket,"可在下坑路牌借公用鎬採 B1–B5，也可在西側水邊淘砂金或到坑口推礦車。",13)
	else:words(app,ticket,"請到車站或接駁站查看下一段旅程。",16)
	var on_foot:bool=chosen.get("mode","") in ["步行","茶園步道","庭園步道"]
	var depart:Button=app.button("沿路出發  →" if on_foot else "搭乘出發  →",func():
		if chosen.is_empty():return
		app.set_meta("travel_mode",str(chosen.mode))
		app.session.perform(str(chosen.get("action","transit")),cell,selected)
	)
	var trip_actions:=HFlowContainer.new()
	trip_actions.add_theme_constant_override("h_separation",8)
	right.add_child(trip_actions)
	depart.name="TravelDepart"
	depart.tooltip_text="X 選取出發 · A 確認"
	depart.disabled=not (near and unlocked and not chosen.is_empty())
	trip_actions.add_child(depart)
	var local_map:Button=app.button("攤開地方路線圖",func():
		app._map_menu(app._travel_menu.bind(station_id,selected))
	)
	local_map.name="TravelLocalMap"
	local_map.flat=true
	local_map.add_theme_font_size_override("font_size",14)
	trip_actions.add_child(local_map)
	for commission_id:String in commissions:
		var commission:Dictionary=World.OUTLYING_COMMISSIONS.DEFS.get(commission_id,{})
		if commission.get("region","")!=region or cell!=Transit.STATIONS[region].cell:continue
		var record:Dictionary=commissions[commission_id]
		words(app,right,str(commission.title),17)
		words(app,right,str(record.text),14)
		if not record.get("done",false):
			var deliver:Button=app.button("交付地方委託",func():app.session.perform("outlying_deliver",cell,commission_id))
			deliver.disabled=not near or not record.get("can_complete",false)
			right.add_child(deliver)
	# 第 40 章金瓜石回訪：渡口家園工坊這一箱在山城接駁站寄運（升降台修好前按鈕寫明鎖定）。
	if region=="jinguashi" and station_id=="shuttle":right.add_child(preload("res://scripts/jinguashi_revisit_ui.gd").entry_button(app,"ferry"))
	# 第 40 章臺南北門回訪：鹽籃在海邊公車站（鹽田站牌）送出（三道閘門修好前寫明鎖定）。
	if region==SaltPan.REGION and station_id=="bus" and salts:right.add_child(preload("res://scripts/salt_revisit_ui.gd").entry_button(app,"stop"))
	if is_instance_valid(app.modal_feedback):
		app.modal_feedback.text="先完成渡口共餐，居民就會介紹這條路。" if not unlocked else ("已到乘車點；背包隨行，旅行不會跳過其他島民的時間。" if near else "請走到「%s」再出發；可先查看地方路線圖。"%str(point.get("label","田區路口")))
	if not focus_name.is_empty():
		var next=content.find_child(focus_name,true,false)
		if next is BaseButton and not next.disabled:next.grab_focus.call_deferred()
	app._layout_preview.call_deferred()

# ---- 旅圖標記層：疊在 taiwan_map.gd 上的小圖層，不接收點擊，也不改地圖本身的標籤 ----
# 兩處步道保護區都是遊戲原創，沒有實際座標：只畫成掛在既有站點（Transit.CONNECTIONS）下的示意支線，不落在臺灣輪廓上。
const RESERVES:=["bamboo_grove","star_garden"]
const RESERVE_STOP_NAMES:={"maokong":"貓空","tianwei":"田尾"}
const RESERVE_PANEL_AT:=Vector2(176,286)
const RESERVE_PANEL_WIDTH:=136.0
# 與 taiwan_map.gd draw_northern_route 的站序、站距相同（該面板的站點位置沒有對外函式）。
const NORTH_STOPS:=[["toucheng","頭城"],["ruifang","瑞芳"],["jiufen","九份"],["jinguashi","金瓜石"],["maokong","貓空"],["yingge","鶯歌"],["tianwei","田尾"]]
const MARK_CURRENT:=Color("ad644b")
const MARK_SELECTED:=Color("2e5f6b")

## 已知的保護區：正在那裡、走訪過，或車票已經能選（與 Transit.options 相同的開放條件）；其餘不畫，避免提前暴露。
static func known_reserves(region:String,book:Dictionary,tea_open:bool,flower_route:bool,star_open:bool)->Array:
	var result:=[]
	var visited:Dictionary=book.get("visited",{})
	for id:String in RESERVES:
		var open:bool=tea_open if id=="bamboo_grove" else (star_open and flower_route)
		if region==id or visited.get(id,false)==true or open:result.append(id)
	return result

## 標記資料（繪製與排版檢查共用）：anchors 是各地區的圖上錨點，labels 是本層自己畫的文字。
## 目前位置＝雙圈＋「目前」；選取的目的地＝箭頭＋「前往」，形狀與文字都不同，不只靠顏色。
static func map_marks(map:Control,region:String,selected:String,reserves:Array)->Dictionary:
	map.ensure_font()
	var font:Font=map.font
	var ends:={}
	for label:Dictionary in map.labels():
		ends[str(label.id)]=Vector2(label.at.x+font.get_string_size(str(label.text),HORIZONTAL_ALIGNMENT_LEFT,-1,int(label.size)).x+3,label.at.y)
	var anchors:={
		"home":{"at":map.home_marker().position,"dot":8.0,"from":Vector2.DOWN,"tag":ends.get("home",Vector2.ZERO)},
		"lanyang":{"at":Map.project(Map.LANYANG_LONLAT),"dot":3.5,"from":Vector2.RIGHT,"tag":ends.get("lanyang",Vector2.ZERO)},
		"jiaoxi":{"at":Map.project(Map.JIAOXI_LONLAT),"dot":4.0,"from":Vector2.RIGHT,"tag":ends.get("jiaoxi",Vector2.ZERO)},
		"beimen":{"at":map.salt_marker().position,"dot":3.5,"from":Vector2.DOWN,"tag":ends.get("beimen",Vector2.ZERO)},
	}
	var flowers:bool=map.show_flowers()
	var step:=16.0 if flowers else 18.0
	for index in NORTH_STOPS.size():
		var id:String=NORTH_STOPS[index][0]
		if id=="tianwei" and not flowers:continue
		var y:float=65.0+index*step
		var text:String=str(NORTH_STOPS[index][1])+("・目前" if id==region else "")
		anchors[id]={"at":Vector2(21,y),"dot":4.0,"from":Vector2.LEFT,"tag":Vector2(34+font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,13).x,y+4)}
	var labels:=[]
	var rows:=[]
	var panel:=Rect2()
	if not reserves.is_empty():
		var origin:=RESERVE_PANEL_AT
		panel=Rect2(origin,Vector2(RESERVE_PANEL_WIDTH,38+16*reserves.size()))
		labels.append({"id":"reserve_title","text":"步道支線","at":origin+Vector2(5,15),"size":12,"color":Color("3c573e")})
		labels.append({"id":"reserve_caption","text":"原創保護區・示意位置","at":origin+Vector2(5,30),"size":10,"color":Color("686f58")})
		for index in reserves.size():
			var id:String=reserves[index]
			var parent:String=str(Transit.CONNECTIONS[id][0])
			var y:float=origin.y+47+index*16
			var here:bool=id==region
			var title:String=str(Transit.STATIONS[id].name)
			title=title.get_slice("・",title.get_slice_count("・")-1)+("・目前" if here else "")
			var color:=MARK_CURRENT if here else Color("3c573e")
			var at:=Vector2(origin.x+45,y-4)
			labels.append({"id":id+"_stop","text":str(RESERVE_STOP_NAMES.get(parent,World.REGIONS.label(parent))),"at":Vector2(origin.x+5,y),"size":11,"color":Color("54774d")})
			labels.append({"id":id,"text":title,"at":Vector2(origin.x+55,y),"size":11,"color":color})
			rows.append({"id":id,"parent":parent,"at":at,"line":Vector2(origin.x+29,y-4),"current":here})
			anchors[id]={"at":at,"dot":4.0,"from":Vector2.LEFT,"tag":Vector2(origin.x+58+font.get_string_size(title,HORIZONTAL_ALIGNMENT_LEFT,-1,11).x,y)}
	var going:Dictionary=anchors.get(selected,{}) if selected!=region else {}
	if not going.is_empty():labels.append({"id":"selected_tag","text":"前往","at":going.tag,"size":11,"color":MARK_SELECTED})
	labels.append({"id":"key_current","text":"目前","at":Vector2(182,373),"size":11,"color":MARK_CURRENT})
	labels.append({"id":"key_selected","text":"前往","at":Vector2(224,373),"size":11,"color":MARK_SELECTED})
	return {"current_region":region,"selected_region":selected if not going.is_empty() else "","reserves":reserves.duplicate(),"current":anchors.get(region,{}),"selected":going,"panel":panel,"rows":rows,"labels":labels}

static func add_map_marks(map:Control,region:String,selected:String,reserves:Array)->Control:
	var layer:=Control.new()
	layer.name="TravelMapMarks"
	layer.mouse_filter=Control.MOUSE_FILTER_IGNORE
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	var marks:=map_marks(map,region,selected,reserves)
	layer.set_meta("travel_marks",marks)
	layer.draw.connect(func():draw_map_marks(layer,map.font,marks))
	map.add_child(layer)
	return layer

static func draw_mark_arrow(layer:Control,at:Vector2,from:Vector2,gap:float)->void:
	var tip:=at+from*gap
	var base:=tip+from*7.0
	var side:=Vector2(-from.y,from.x)*4.0
	layer.draw_colored_polygon(PackedVector2Array([tip,base+side,base-side]),MARK_SELECTED)

static func draw_map_marks(layer:Control,font:Font,marks:Dictionary)->void:
	if font==null:return
	var panel:Rect2=marks.panel
	if panel.size.y>0:layer.draw_style_box(Pixel.paper_style(),panel)
	for row:Dictionary in marks.rows:
		var at:Vector2=row.at
		var color:=MARK_CURRENT if row.current else Color("54774d")
		layer.draw_dashed_line(row.line,at-Vector2(5,0),Color("a78764"),1.0,3.0)
		var diamond:=PackedVector2Array([at+Vector2(0,-4),at+Vector2(4,0),at+Vector2(0,4),at+Vector2(-4,0)])
		if row.current:layer.draw_colored_polygon(diamond,color)
		diamond.append(diamond[0])
		layer.draw_polyline(diamond,color,1.5)
	for label:Dictionary in marks.labels:
		layer.draw_string(font,label.at,str(label.text),HORIZONTAL_ALIGNMENT_LEFT,-1,int(label.size),label.color)
	var current:Dictionary=marks.current
	if not current.is_empty():layer.draw_arc(current.at,float(current.dot)+3.0,0.0,TAU,24,MARK_CURRENT,1.5)
	var selected:Dictionary=marks.selected
	if not selected.is_empty():draw_mark_arrow(layer,selected.at,selected.from,float(selected.dot)+2.0)
	# 圖例：圈＝目前位置，箭頭＝選取的目的地。
	layer.draw_arc(Vector2(174,369),4.0,0.0,TAU,16,MARK_CURRENT,1.5)
	layer.draw_circle(Vector2(174,369),1.5,MARK_CURRENT)
	draw_mark_arrow(layer,Vector2(221,369),Vector2.LEFT,0.0)

static func arrival_art(mode:String)->Texture2D:
	if mode==BOAT_MODE:return Art.icon("cooperative_boat")
	if mode.contains("船"):return Art.icon("ferry")
	if mode.contains("步"):return Shell.icon("map")
	return Art.icon("train" if mode=="火車" else "bus")

static func dismiss_arrival(app)->bool:
	if not is_instance_valid(app.hud):return false
	var ribbon:=app.hud.get_node_or_null("TravelArrival") as Control
	if not is_instance_valid(ribbon) or not ribbon.is_visible_in_tree() or ribbon.is_queued_for_deletion():return false
	ribbon.hide()
	ribbon.queue_free()
	return true

static func covers_arrival_notice(app,message:String)->bool:
	if not app.village_art_preview or not is_instance_valid(app.hud):return false
	var ribbon:=app.hud.get_node_or_null("TravelArrival") as Control
	return is_instance_valid(ribbon) and ribbon.is_visible_in_tree() and not ribbon.is_queued_for_deletion() and ribbon.get_meta("arrival_notice","")==message

static func arrived(app,origin:String,destination:String)->void:
	if origin not in Transit.ROUTE or destination not in Transit.ROUTE:return
	var previous=app.hud.get_node_or_null("TravelArrival")
	if previous:app.hud.remove_child(previous);previous.queue_free()
	var ribbon:=PanelContainer.new();ribbon.name="TravelArrival";ribbon.add_theme_stylebox_override("panel",Pixel.paper_style())
	ribbon.set_meta("arrival_notice",World.REGIONS.arrival_notice(destination))
	ribbon.mouse_filter=Control.MOUSE_FILTER_PASS;ribbon.z_index=8
	var row:=HBoxContainer.new();row.add_theme_constant_override("separation",10);ribbon.add_child(row)
	var art_space:=Control.new();art_space.custom_minimum_size=Vector2(112,64);row.add_child(art_space)
	art_space.clip_contents=true
	var mode:=str(app.get_meta("travel_mode","接駁"))
	var sprite:=Shell.picture(arrival_art(mode),80);sprite.custom_minimum_size=Vector2.ZERO;sprite.size=Vector2(80,60);sprite.position=Vector2(16,0);art_space.add_child(sprite)
	sprite.name="ArrivalArt"
	var title:Label=app.label("%s → %s"%[Shell.region_display_name(origin),Shell.region_display_name(destination)],16);title.custom_minimum_size.x=300;title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;title.size_flags_vertical=Control.SIZE_SHRINK_CENTER;row.add_child(title)
	var skip:Button=app.button("略過",func():ribbon.queue_free());skip.custom_minimum_size=Vector2(48,32);skip.size_flags_vertical=Control.SIZE_SHRINK_CENTER;skip.add_theme_font_size_override("font_size",13);row.add_child(skip)
	skip.tooltip_text="Esc／手把 B"
	app.hud.add_child(ribbon)
	# The success notice and region snapshot can arrive in either order.
	if is_instance_valid(app.toast) and app.toast_success and covers_arrival_notice(app,app.toast.text):
		app.toast_time=0.0
		app.toast.hide()
	var bounds:Vector2=app.get_viewport().get_visible_rect().size
	ribbon.size=Vector2(minf(520,bounds.x-48),80);ribbon.position=Vector2((bounds.x-ribbon.size.x)/2,140)
	var lifetime:=ribbon.create_tween()
	if app.sound and not app.sound.reduced_motion:
		sprite.position.x=-20
		ribbon.modulate.a=0.4
		var entrance:=ribbon.create_tween().set_parallel()
		entrance.tween_property(ribbon,"modulate:a",1.0,0.18)
		entrance.tween_property(sprite,"position:x",16.0,0.52).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		lifetime.tween_interval(1.6)
		lifetime.tween_property(ribbon,"modulate:a",0.0,0.2)
	else:
		lifetime.tween_interval(1.8)
	lifetime.tween_callback(ribbon.queue_free)
