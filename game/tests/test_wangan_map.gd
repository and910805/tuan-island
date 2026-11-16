extends SceneTree
## 旅圖把出生島標成「澎湖・望安」（headless）。
##
## PRESET / FIXTURE（不是玩家實際遊玩）：
##  * 隔離的 host 存檔（%TEMP%，結束時刪除）；app.village_art_preview=true；
##  * state.picnic / state.board 直接寫 true（旅行解鎖前提）；state.dock_stage 直接寫 0/1/2；
##  * 玩家 region / x / y 直接寫入（站到渡口轉乘點或蘭陽出口旁），travel_book 重設為 Transit.fresh()；
##  * 四種花圃／鹽田狀態是直接改地圖控制項的 meta（flower_open / salt_open），不是寄信。
## REALLY EXERCISED：app._travel_menu()（M 鍵 / 旅圖選單同一路徑）開出旅圖；
##  SelectRoute_* 與 TravelDepart 以 pressed 觸發，經 session.perform 交給 World 處理 travel；
##  地圖控制項是旅圖裡實際建立的 taiwan_map.gd 實例，標籤外框取自它的 layout_rects()。
const World=preload("res://scripts/world.gd")
const Transit=preload("res://scripts/transit.gd")
const TravelUI=preload("res://scripts/travel_ui.gd")
const Map=preload("res://scripts/taiwan_map.gd")
const Outline=preload("res://scripts/taiwan_outline.gd")
const Shell=preload("res://scripts/life_ui_shell.gd")
const Art=preload("res://scripts/transit_art.gd")
const IslandMap=preload("res://scripts/island_map.gd")
const Opening=preload("res://scripts/wangan_opening.gd")
const Chapter=preload("res://scripts/chapter_one.gd")
const BANNED:=["班次","時刻","票價","航班","分鐘","小時","業者","直達"]
var app
var w
var id:=""
var checks:=0
var failures:=0
var finished:=false

func _initialize()->void:run.call_deferred()

func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;push_error(message)

func finish()->void:
	if finished:return
	finished=true
	print("WANGAN_MAP_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 or checks==0 else 0)

func frames()->void:
	for i in range(5):await process_frame
	app._layout_preview();await process_frame

func person()->Dictionary:
	return w.state.players[id]

func place(region:String,at:Vector2)->void:
	var p:=person()
	p.region=region;p.x=at.x;p.y=at.y
	app.session._send_snapshot(1)
	app.view.update_snapshot(app.session.snapshot,app.session.own_id)
	await frames()

func control(name:String)->Control:
	if not is_instance_valid(app.modal):return null
	return app.modal.find_child(name,true,false) as Control

func labels_text()->Array:
	var out:=[]
	if not is_instance_valid(app.modal):return out
	for node in app.modal.find_children("*","Label",true,false):
		if (node as Label).is_visible_in_tree():out.append((node as Label).text)
	return out

func map_control()->Control:
	if not is_instance_valid(app.modal):return null
	for node in app.modal.find_children("*","Control",true,false):
		if node.get_script()==Map:return node
	return null

func press(name:String)->void:
	var b:=control(name) as BaseButton
	check(b!=null and not b.disabled,"Button %s enabled"%name)
	if b==null or b.disabled:return
	app.session.rates[1].clear()
	await create_timer(0.12).timeout
	b.pressed.emit()
	await frames()

func fits(tag:String)->void:
	check(is_instance_valid(app.modal) and str(app.modal.get_meta("life_modal_layout",""))=="travel_map","Travel modal open (%s)"%tag)
	if not is_instance_valid(app.modal):return
	var modal:Control=app.modal
	check(root.get_visible_rect().encloses(modal.get_global_rect()),"Travel modal fits viewport (%s) %s"%[tag,str(modal.get_global_rect())])
	for node in modal.find_children("*","Label",true,false):
		var l:=node as Label
		if not l.is_visible_in_tree():continue
		check(modal.get_global_rect().grow(0.5).encloses(l.get_global_rect()) and l.get_visible_line_count()>=l.get_line_count(),"Label whole inside modal 「%s」 (%s)"%[l.text,tag])
	for node in modal.find_children("*","Button",true,false):
		var b:=node as Button
		if not b.is_visible_in_tree():continue
		check(modal.get_global_rect().grow(0.5).encloses(b.get_global_rect()),"Button whole inside modal 「%s」 (%s)"%[b.text,tag])
	var map:=map_control()
	check(map!=null,"Taiwan map present (%s)"%tag)
	if map!=null:check(modal.get_global_rect().grow(0.5).encloses(map.get_global_rect()) and map.size.x>=279.0 and map.size.y>=379.0,"Map whole inside modal at full size (%s) %s"%[tag,str(map.size)])

func west_edge(y:float)->float:
	var band:=[]
	for point in Outline.POINTS:
		var q:Vector2=point+Map.OFFSET
		if absf(q.y-y)<=10.0:band.append(q.x)
	return band.min() if not band.is_empty() else -INF

## 出生島標記：在主島西側、控制項內；標籤與示意框不壓到其他標籤、面板與引線（四種花圃／鹽田狀態）。
func map_layout(map:Control,tag:String,current:bool)->void:
	var home:Dictionary=map.home_marker()
	var at:Vector2=home.position
	var edge:=west_edge(at.y)
	check(edge>-INF and at.x<edge-8.0,"Home marker west of the island's western edge (%s) x=%.1f edge=%.1f"%[tag,at.x,edge])
	var box:=Rect2(Vector2.ZERO,map.size)
	check(box.has_point(at) and box.encloses(home.inset),"Home marker and inset inside the map control (%s)"%tag)
	var truth:Vector2=home.true_position
	check(not box.has_point(truth) or Map.NORTH_PANEL.has_point(truth),"Projected Wang'an really is off-map or under the route panel, so an inset is needed (%s) %s"%[tag,str(truth)])
	check(str(home.label)==("澎湖・望安・目前" if current else "澎湖・望安"),"Home label (%s): %s"%[tag,home.label])
	check(str(home.caption).contains("位置示意"),"Inset caption says 位置示意 (%s)"%tag)
	for flowers in [false,true]:
		for salt in [false,true]:
			map.set_meta("flower_open",flowers);map.set_meta("salt_open",salt);map.queue_redraw()
			var state:="%s flowers=%s salt=%s"%[tag,flowers,salt]
			var rects:Dictionary=map.layout_rects()
			check(rects.has("home") and rects.has("home_caption") and rects.has("home_inset") and rects.has("lanyang"),"Layout has home and Lanyang rects (%s)"%state)
			check(rects.has("tianwei")==flowers or str(map.get_meta("current_region",""))=="tianwei","Tianwei label follows flower flag (%s)"%state)
			check(rects.has("beimen"),"Beimen label present (%s)"%state)
			var labels:Array=map.labels()
			var texts:=labels.map(func(l):return str(l.text))
			check(not texts.any(func(t):return t.contains("渡口")),"No map label calls a Yilan spot 渡口 (%s): %s"%[state,str(texts)])
			check(texts.has("宜蘭・蘭陽") or texts.has("宜蘭・蘭陽・目前"),"Yilan end reads 宜蘭・蘭陽 (%s)"%state)
			for own in ["home","home_caption","home_inset","lanyang"]:
				var r:Rect2=rects.get(own,Rect2())
				check(box.encloses(r),"%s inside the map (%s) %s"%[own,state,str(r)])
				for other in rects:
					if other==own:continue
					if own.begins_with("home") and str(other).begins_with("home"):continue
					check(not r.intersects(rects[other]),"%s does not overlap %s (%s) %s vs %s"%[own,other,state,str(r),str(rects[other])])
			check(Map.HOME_INSET.encloses(rects.home) and Map.HOME_INSET.encloses(rects.home_caption),"Home label and caption inside the inset (%s)"%state)
	map.set_meta("flower_open",false);map.set_meta("salt_open",false);map.queue_redraw()

func no_yilan_home()->void:
	check(not str(TravelUI.NOTES.home).contains("宜蘭") and str(TravelUI.NOTES.home).contains("澎湖・望安"),"NOTES.home places home in 澎湖・望安: "+TravelUI.NOTES.home)
	for key in TravelUI.ROUTE_NOTES:
		var text:=str(TravelUI.ROUTE_NOTES[key])
		if str(key).ends_with(">home"):check(not text.contains("宜蘭") and text.contains("澎湖・望安"),"ROUTE_NOTES %s places home in 澎湖・望安: %s"%[key,text])
	for table in [TravelUI.NOTES,TravelUI.ROUTE_NOTES]:
		for key in table:
			var text:=str(table[key])
			check(not text.contains("宜蘭熟悉的渡口") and not text.contains("宜蘭渡口") and not text.contains("步行"),"No Yilan ferry village or walking in %s"%key)
			if text.contains("交通船"):check(text.contains("合併") and text.contains("縮短"),"Boat note says merged and shortened: %s"%key)
			for word in BANNED:check(not text.contains(word),"No timetable/operator wording 「%s」 in %s"%[word,key])
	check(TravelUI.HOME_LANYANG_MODE=="交通船","Home<->Lanyang mode constant is 交通船")
	check(Transit.HOME_FERRY_MODE=="交通船・轉乘" and Transit.POINTS.home.ferry.mode==Transit.HOME_FERRY_MODE and Transit.POINTS.toucheng.street.mode==Transit.HOME_FERRY_MODE,"Home<->Toucheng ferry links use the boat transfer mode")
	check(Transit.POINTS.home.ferry.cell==Vector2i(47,30) and Transit.POINTS.home.ferry.links==["toucheng"] and Transit.POINTS.toucheng.street.cell==Vector2i(12,25) and Transit.POINTS.toucheng.street.links==["home"],"Ferry and street cells/links unchanged")
	var map_icon:=Shell.icon("map") as AtlasTexture
	for mode in ["交通船","交通船・轉乘","合作小船"]:
		var art:=TravelUI.arrival_art(mode) as AtlasTexture
		check(art!=null and map_icon!=null and art.atlas==map_icon.atlas and art.region==map_icon.region,"Boat trip %s shows the map icon, not a bus"%mode)
	check(TravelUI.arrival_art("火車")==Art.icon("train") and TravelUI.arrival_art("公車")==Art.icon("bus") and TravelUI.arrival_art("接駁")==Art.icon("bus"),"Land trips keep train/bus art")

## 合作小船的車票說明依交通方式改寫：讀起來是渡海，不是「從頭城搭車」。
func boat_notes()->void:
	check(TravelUI.BOAT_MODE=="合作小船","Boat mode constant matches Transit options")
	check(TravelUI.BOAT_NOTES.keys().size()==4,"Four boat notes (home<->jiaoxi/bamboo_grove)")
	for key in TravelUI.BOAT_NOTES:
		var text:=str(TravelUI.BOAT_NOTES[key])
		check(text.contains("合作小船") and text.contains("渡海") and text.contains("合併") and text.contains("縮短"),"Boat note %s reads as a merged, shortened boat crossing: %s"%[key,text])
		check(not text.contains("搭車") and not text.contains("步行") and not text.contains("宜蘭渡口") and not text.contains("宜蘭熟悉"),"Boat note %s has no bus/walking/Yilan-home wording"%key)
		for word in BANNED:check(not text.contains(word),"No timetable/operator wording 「%s」 in boat note %s"%[word,key])
		if str(key).ends_with(">home"):check(text.contains("澎湖・望安") and not text.contains("宜蘭") and text.contains("免費"),"Boat note %s returns to 澎湖・望安 for free"%key)
	for pair in [["home","jiaoxi"],["home","bamboo_grove"],["jiaoxi","home"],["bamboo_grove","home"]]:
		var key:="%s>%s"%pair
		check(TravelUI.note(pair[0],pair[1],"合作小船")==TravelUI.BOAT_NOTES[key],"note(%s, 合作小船) uses the boat note"%key)
	check(TravelUI.note("home","jiaoxi","合併轉乘")==TravelUI.NOTES.jiaoxi and TravelUI.note("toucheng","jiaoxi","火車")==TravelUI.NOTES.jiaoxi and TravelUI.note("toucheng","jiaoxi")==TravelUI.NOTES.jiaoxi,"Overland Jiaoxi notes unchanged")
	check(TravelUI.note("maokong","bamboo_grove","茶園步道")==TravelUI.NOTES.bamboo_grove and TravelUI.note("jiaoxi","home","地方接駁")==TravelUI.NOTES.home,"Non-boat modes keep the old notes")
	check(TravelUI.note("home","lanyang",TravelUI.HOME_LANYANG_MODE)==TravelUI.NOTES.lanyang and TravelUI.note("lanyang","home",TravelUI.HOME_LANYANG_MODE)==TravelUI.ROUTE_NOTES["lanyang>home"],"Home<->Lanyang notes unchanged")
	# 用實際的 Transit.options 確認哪些方向是合作小船，說明就跟著改寫。
	for origin in ["home","jiaoxi","bamboo_grove"]:
		for station in Transit.points(origin):
			for option in Transit.options(origin,Transit.fresh(),true,station,true,false,false,false,true):
				if str(option.mode)!="合作小船":continue
				var text:=TravelUI.note(origin,str(option.region),str(option.mode))
				check(text.contains("合作小船") and not text.contains("搭車"),"Boat option %s->%s gets a boat ticket note: %s"%[origin,option.region,text])

## 周邊地圖的來信標記：第一株作物引導進行中時指向「小栗留的田」的中心，而不是小栗本人。
func letter_marker()->void:
	var center:=Vector2(46.5,27.0)
	var own:Dictionary=IslandMap.letter_target(app.session.snapshot,str(app.session.own_id))
	check(Vector2(own.at)==center and str(own.text).contains(Opening.PLOT_TAG) and own.plot==true,"Snapshot letter marker points at the starter plot: %s"%str(own))
	var server:Dictionary=IslandMap.letter_target(w.state,id)
	check(server==own,"Server state and snapshot agree on the letter marker")
	var taken:Dictionary=w.state.duplicate(true)
	for cell in Chapter.STARTER_PLOT:taken.ground["%d,%d"%[cell.x,cell.y]]={"owner":"someone_else"}
	var full:Dictionary=IslandMap.letter_target(taken,id)
	check(Vector2(full.at)==Vector2(Chapter.STEPS.grow.cell)+Vector2(0.5,0.5) and not str(full.text).contains(Opening.PLOT_TAG) and full.plot==false,"Fully occupied plot: marker falls back to 小栗: %s"%str(full))
	var shipped:Dictionary=w.state.duplicate(true)
	shipped.chapter_one.shipped=true;shipped.board=false
	var works:Dictionary=IslandMap.letter_target(shipped,id)
	check(Vector2(works.at)==Vector2(Chapter.STEPS.works.cell)+Vector2(0.5,0.5) and str(works.text)=="來信標記："+str(Chapter.STEPS.works.action),"After shipping the marker follows the chapter step: %s"%str(works))
	check(w.state.chapter_one.shipped==false and not w.state.ground.has("45,26"),"letter_target does not change the world")

func ticket(tag:String,target:String,mode:String,note:String,label:String)->void:
	var button:=control("SelectRoute_"+target) as Button
	check(button!=null and button.button_pressed,"%s route offered and selected (%s)"%[target,tag])
	if button!=null:check(button.text==label,"%s button label (%s): %s"%[target,tag,button.text])
	var texts:=labels_text()
	check(texts.has(mode+" · 已走訪") or texts.has(mode+" · 這一站的新風景"),"Ticket shows mode %s (%s): %s"%[mode,tag,str(texts)])
	check(texts.has(note),"Ticket shows the note (%s): %s"%[tag,note])
	check(not texts.any(func(t):return t.contains("步行") or t.contains("宜蘭渡口") or t.contains("宜蘭熟悉")),"No walking or Yilan ferry wording on the ticket (%s)"%tag)
	var depart:=control("TravelDepart") as Button
	check(depart!=null and depart.text=="搭乘出發  →" and not depart.disabled,"Depart says 搭乘出發 and is enabled (%s): %s"%[tag,depart.text if depart else "none"])

func size_flow(size:Vector2i)->void:
	root.size=size
	var tag:="%dx%d"%[size.x,size.y]
	var p:=person()
	p.travel_book=Transit.fresh()
	w.state.dock_stage=0  # PRESET
	await place("home",Vector2(47.5,31.5))
	app._travel_menu();await frames()
	fits("home "+tag)
	check(str(app.modal.get_meta("travel_station",""))=="ferry","Nearest gate is the ferry (%s)"%tag)
	ticket("home "+tag,"lanyang","交通船",TravelUI.NOTES.lanyang,"蘭陽試作田")
	var map:=map_control()
	if map!=null:
		check(str(map.get_meta("current_region",""))=="home","Map knows we are home (%s)"%tag)
		map_layout(map,"home "+tag,true)
	var inventory:Dictionary=p.inventory.duplicate(true)
	var coins:=int(p.coins)
	var epoch:=int(p.travel_epoch)
	var time:=float(w.state.time)
	var book:Dictionary=p.travel_book.duplicate(true)
	await press("TravelDepart")
	check(p.region=="lanyang","Boat trip reaches Lanyang (%s)"%tag)
	check(str(app.get_meta("travel_mode",""))=="交通船","Departure records travel_mode 交通船 (%s)"%tag)
	check(p.inventory==inventory and int(p.coins)==coins and int(p.travel_epoch)==epoch+1 and float(w.state.time)==time and p.travel_book==book,"Travel keeps inventory/coins/time/book and bumps epoch (%s)"%tag)
	if is_instance_valid(app.modal):app._close_modal()
	await place("lanyang",Vector2(12.5,20.5))
	app._travel_menu();await frames()
	fits("lanyang "+tag)
	ticket("lanyang "+tag,"home","交通船",TravelUI.ROUTE_NOTES["lanyang>home"],"風鈴渡口")
	map=map_control()
	if map!=null:
		map_layout(map,"lanyang "+tag,false)
		var lanyang_texts:=(map.labels() as Array).filter(func(l):return str(l.id)=="lanyang").map(func(l):return str(l.text))
		check(lanyang_texts==["宜蘭・蘭陽・目前"],"Lanyang marker marked current (%s): %s"%[tag,str(lanyang_texts)])
	await press("TravelDepart")
	check(p.region=="home" and p.inventory==inventory and int(p.coins)==coins and int(p.travel_epoch)==epoch+2,"Boat trip back reaches home with the same pack (%s)"%tag)
	if is_instance_valid(app.modal):app._close_modal()

## 碼頭 0–2：選項與狀態列和改動前一致（蘭陽在最前，其餘全來自 Transit.options）。
func dock_flow()->void:
	root.size=Vector2i(1024,640)
	var copy:=["碼頭待修 · 到公告板查看工程","碼頭已修好 · 等待小船完工","小船已就緒 · 可航往霧竹與暖泉"]
	for stage in range(3):
		w.state.dock_stage=stage  # PRESET
		person().travel_book=Transit.fresh()
		await place("home",Vector2(47.5,31.5))
		app._travel_menu();await frames()
		var status:=control("DockTravelStatus") as Label
		check(status!=null and status.text==copy[stage],"Dock status stage %d: %s"%[stage,status.text if status else "none"])
		var shown:=[]
		var row:=control("TravelDestinations")
		if row!=null:
			for child in row.get_children():shown.append(str(child.name).trim_prefix("SelectRoute_"))
		var expected:=["lanyang","toucheng"]+(["jiaoxi"] if stage>=2 else [])
		check(shown==expected,"Ferry destinations at dock stage %d: %s"%[stage,str(shown)])
		var options:=Transit.options("home",Transit.fresh(),true,"ferry",false,false,false,false,stage>=2)
		check(options.map(func(o):return o.region)==expected.slice(1),"Transit options unchanged at stage %d"%stage)
		for option in options:
			if option.region=="jiaoxi":check(option.mode=="合作小船" and option.direct and option.via==[],"Co-op boat to Jiaoxi unchanged")
			if option.region=="toucheng":check(option.mode=="交通船・轉乘" and option.direct,"Ferry to Toucheng is the boat transfer")
		fits("dock %d"%stage)
		if stage>=2:
			await press("SelectRoute_jiaoxi")
			var texts:=labels_text()
			check(texts.has(TravelUI.BOAT_NOTES["home>jiaoxi"]),"Boat ticket to Jiaoxi shows the boat note: %s"%str(texts))
			check(texts.has("合作小船 · 已走訪") or texts.has("合作小船 · 這一站的新風景"),"Boat ticket shows mode 合作小船")
			check(not texts.any(func(t):return str(t).contains("搭車") or str(t).contains("步行")),"Boat ticket has no bus/walking wording")
			var depart:=control("TravelDepart") as Button
			check(depart!=null and depart.text=="搭乘出發  →","Boat ticket depart says 搭乘出發")
			fits("dock boat ticket")
		app._close_modal()
	w.state.dock_stage=0

func run()->void:
	create_timer(110.0).timeout.connect(func():
		check(false,"Watchdog: suite exceeded 110 s")
		finish())
	var path:=OS.get_environment("TEMP").path_join("wangan-map-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	app=preload("res://main.tscn").instantiate();app.village_art_preview=true;root.add_child(app)
	app.set_process(false);app.session.set_physics_process(false)
	app.menu.hide();app.hud.show()
	if app.session.host(0,"望安旅人",path)!=OK:check(false,"Host starts");finish();return
	w=app.session.world;id=app.session.profile.token
	w.state.picnic=true  # PRESET
	w.state.board=true  # PRESET
	no_yilan_home()
	boat_notes()
	await place("home",Vector2(39.5,33.5))
	letter_marker()
	for size in [Vector2i(1024,640),Vector2i(1280,800)]:await size_flow(size)
	await dock_flow()
	app.session.shutdown();await create_timer(0.3).timeout
	app.queue_free();await process_frame;await process_frame
	for suffix in ["",".bak",".writer-lock"]:DirAccess.remove_absolute(path+suffix)
	finish()
