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

static func open(app,station_id:String="")->void:
	var s:Dictionary=app.session.snapshot
	var person:Dictionary=s.get("players",{}).get(app.session.own_id,{})
	if person.is_empty():return
	var region:=str(s.get("region_id","home"))
	if station_id.is_empty():station_id=nearest(region,Vector2(person.x,person.y))
	var content:VBoxContainer=app._open_modal("旅途車票 · 選一站出發")
	app.modal.set_meta("life_modal_layout","travel_map")
	app.modal.set_meta("travel_body",content)
	app.modal.set_meta("travel_station",station_id)
	app.modal.theme=Pixel.make(app.hud.theme)
	refresh(app)

static func words(app,parent:Node,text:String,size:int=15)->Label:
	var label:Label=app.label(text,size)
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label

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
	var fingerprint:=JSON.stringify([region,station_id,selected,near,unlocked,flowers,salts,stars,dock_stage,book,p.inventory.get("reinforced_pick",0),commissions,World.JINGUASHI_REVISIT.unlocked(s) if region=="jinguashi" else false,World.SALT_REVISIT.unlocked(s) if region==SaltPan.REGION else false])
	if app.modal.get_meta("travel_fingerprint","")==fingerprint:return
	app.modal.set_meta("travel_fingerprint",fingerprint)
	var content:VBoxContainer=app.modal.get_meta("travel_body")
	var focused:=content.get_viewport().gui_get_focus_owner()
	var focus_name:String=focused.name if is_instance_valid(focused) and content.is_ancestor_of(focused) else ""
	for child in content.get_children():content.remove_child(child);child.queue_free()
	var row:=HBoxContainer.new();row.add_theme_constant_override("separation",20);content.add_child(row)
	var map:=Map.new();map.set_meta("current_region",region);map.set_meta("travel_book",book);map.set_meta("flower_open",flowers);map.set_meta("salt_open",salts);row.add_child(map)
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
		title.add_child(Shell.picture(artwork,72))
		var heading:=VBoxContainer.new();heading.size_flags_horizontal=Control.SIZE_EXPAND_FILL;title.add_child(heading)
		words(app,heading,str(chosen.label),21)
		var known:bool=book.get("visited",{}).has(selected)
		words(app,heading,mode+" · "+("已走訪" if known else ("保留原通行" if mode=="既有通行" else "這一站的新風景")),14)
		var itinerary:=PackedStringArray([World.REGIONS.label(region)])
		for via in chosen.get("via",[]):itinerary.append(World.REGIONS.label(via))
		itinerary.append(str(chosen.label))
		words(app,ticket," → ".join(itinerary),14)
		words(app,ticket,note(region,selected,mode),15)
		if selected=="jinguashi" and int(p.inventory.get("reinforced_pick",0))==0:words(app,ticket,"背包還沒有強化石鎬；可以先去拜訪，在西側水邊淘砂金、到坑口幫忙推一車礦料，再回家準備。",13)
	else:words(app,ticket,"請到車站或接駁站查看下一段旅程。",16)
	var depart:Button=app.button("搭乘出發  →" if not chosen.is_empty() and chosen.get("mode","")!="步行" else "沿路出發  →",func():
		if chosen.is_empty():return
		app.set_meta("travel_mode",str(chosen.mode))
		app.session.perform(str(chosen.get("action","transit")),cell,selected)
	)
	depart.name="TravelDepart";depart.disabled=not (near and unlocked and not chosen.is_empty());right.add_child(depart)
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
	var local_map:Button=app.button("攤開地方路線圖",app._map_menu);local_map.name="TravelLocalMap";local_map.flat=true;local_map.add_theme_font_size_override("font_size",14);right.add_child(local_map)
	if is_instance_valid(app.modal_feedback):
		app.modal_feedback.text="先完成渡口共餐，居民就會介紹這條路。" if not unlocked else ("已到乘車點；背包隨行，旅行不會跳過其他島民的時間。" if near else "請走到「%s」再出發；可先查看地方路線圖。"%str(point.get("label","田區路口")))
	if not focus_name.is_empty():
		var next=content.find_child(focus_name,true,false)
		if next is BaseButton and not next.disabled:next.grab_focus.call_deferred()
	app._layout_preview.call_deferred()

# 抵達緞帶的插圖：交通船與合作小船沒有船隻圖，改用旅圖圖示，避免讓渡海旅程顯示成公車或火車。
static func arrival_art(mode:String)->Texture2D:
	if mode.contains("船"):return Shell.icon("map")
	return Art.icon("train" if mode=="火車" else "bus")

static func arrived(app,origin:String,destination:String)->void:
	if origin not in Transit.ROUTE or destination not in Transit.ROUTE:return
	var previous=app.hud.get_node_or_null("TravelArrival")
	if previous:app.hud.remove_child(previous);previous.queue_free()
	var ribbon:=PanelContainer.new();ribbon.name="TravelArrival";ribbon.add_theme_stylebox_override("panel",Pixel.paper_style())
	ribbon.mouse_filter=Control.MOUSE_FILTER_PASS;ribbon.z_index=8
	var row:=HBoxContainer.new();row.add_theme_constant_override("separation",10);ribbon.add_child(row)
	var art_space:=Control.new();art_space.custom_minimum_size=Vector2(112,64);row.add_child(art_space)
	var mode:=str(app.get_meta("travel_mode","接駁"))
	var sprite:=Shell.picture(arrival_art(mode),80);sprite.custom_minimum_size=Vector2.ZERO;sprite.size=Vector2(80,60);sprite.position=Vector2(16,0);art_space.add_child(sprite)
	var title:Label=app.label("%s → %s"%[World.REGIONS.label(origin),World.REGIONS.label(destination)],16);title.custom_minimum_size.x=300;title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;title.size_flags_vertical=Control.SIZE_SHRINK_CENTER;row.add_child(title)
	var skip:Button=app.button("略過",func():ribbon.queue_free());skip.custom_minimum_size=Vector2(48,32);skip.size_flags_vertical=Control.SIZE_SHRINK_CENTER;skip.add_theme_font_size_override("font_size",13);row.add_child(skip)
	app.hud.add_child(ribbon)
	var bounds:Vector2=app.get_viewport().get_visible_rect().size
	ribbon.size=Vector2(minf(560,bounds.x-48),80);ribbon.position=Vector2((bounds.x-ribbon.size.x)/2,140)
	if app.sound and not app.sound.reduced_motion:
		sprite.position.x=-8
		var movement:=sprite.create_tween();movement.tween_property(sprite,"position:x",24.0,0.65).set_trans(Tween.TRANS_SINE)
	var lifetime:=ribbon.create_tween();lifetime.tween_interval(1.8);lifetime.tween_callback(ribbon.queue_free)
