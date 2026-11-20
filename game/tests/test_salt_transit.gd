extends SceneTree
const World=preload("res://scripts/world.gd")
const Transit=preload("res://scripts/transit.gd")
const Regions=preload("res://scripts/regions.gd")
const TravelUI=preload("res://scripts/travel_ui.gd")
const Map=preload("res://scripts/taiwan_map.gd")
const Outline=preload("res://scripts/taiwan_outline.gd")
const FlowerNursery=preload("res://scripts/flower_nursery.gd")
const SaltPan=preload("res://scripts/salt_pan.gd")
const FORBIDDEN:=["北門站","北門火車站","田尾站","田尾火車站","直達","班次","票價","時刻表","切片","debug"]
const SALT:="花圃接駁・縱貫線鐵路南下・轉沿海公車（合併轉乘）"
const OLD_ROUTE:=["home","toucheng","ruifang","jiufen","jinguashi","maokong","yingge","tianwei"]
const OLD_ALL:=["home","lanyang","jinguashi","toucheng","ruifang","jiufen","mine_1","mine_2","mine_3","mine_4","mine_5","maokong","yingge","tianwei"]
var checks:=0
var failures:=0
func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;push_error(message)

func find(options:Array,region:String)->Dictionary:
	for option in options:
		if option.region==region:return option
	return {}

func regions_of(options:Array)->Array:
	return options.map(func(option):return option.region)

func clean(text:String,where:String)->void:
	for word in FORBIDDEN:check(not text.contains(word),"Forbidden wording「%s」in %s: %s"%[word,where,text])

func completed_flower_fixture(w:World,token:String)->void:
	var tea:Dictionary=World.TEA_CERAMICS.FRESH.duplicate(true)
	tea.merge({"intro":true,"potter":true,"reused":true,"reuse_count":1,
		"trials":{"jar":true,"fiber":true},"tea_discussed":true,"comparison_complete":true},true)
	w.state.tea_ceramics.players[token]=tea
	var flowers:Dictionary=FlowerNursery.FRESH.duplicate(true)
	flowers.merge({"letter":true,"intro":true,"shipped":true,"complete":true},true)
	for kind in FlowerNursery.FLOWERS:
		flowers.planted[kind]=true
		flowers.harvested[kind]=2
		flowers.saved[kind]=true
	w.state.flower_nursery.players[token]=flowers

func give_salt_letter(w:World,token:String)->void:
	var salt:Dictionary=w.state.get("salt_pan",{})
	if not salt.has("players"):
		var root=SaltPan.fresh()
		if root is Dictionary and root.has("players"):salt=root
		else:salt.players={}
	var record:Dictionary=SaltPan.own_record(w.state,token)
	record.letter=true
	salt.players[token]=record
	w.state.salt_pan=salt

func _initialize()->void:
	# 圖與常數：beimen 只附加在尾端，舊順序完全保留。
	check(Transit.ROUTE==OLD_ROUTE+["beimen","jiaoxi","bamboo_grove","star_garden"],"Existing route order is preserved before the Jiaoxi branch")
	var original_regions:=OLD_ALL+["beimen","jiaoxi","bamboo_grove","star_garden"]+Regions.DEEP_MINES
	check(Regions.ALL.slice(0,original_regions.size())==original_regions,"The original region and mine order survives later activity areas")
	check(Regions.BEIMEN=="beimen" and Transit.SALT_STOP=="beimen" and SaltPan.REGION=="beimen","Region id agrees with SaltPan.REGION")
	check(Transit.CONNECTIONS.tianwei==["yingge","beimen","star_garden"] and Transit.CONNECTIONS.beimen==["tianwei"] and Transit.CONNECTIONS.yingge==["maokong","tianwei"],"tianwei<->beimen connection, yingge unchanged")
	check(Transit.STATIONS.beimen=={"name":"北門・鹽風合作鹽田","cell":Vector2i(48,25),"arrival":Vector2(47.5,25.5),"size":Vector2i(80,60)},"Beimen station exact")
	check(Transit.STATIONS.beimen.cell==SaltPan.TRANSFER and Transit.STATIONS.beimen.arrival==SaltPan.ARRIVAL,"Station agrees with SaltPan transfer/arrival")
	check(Transit.POINTS.tianwei.transfer.links==["yingge","beimen","star_garden"] and Transit.POINTS.tianwei.transfer.cell==Vector2i(12,25) and Transit.POINTS.tianwei.transfer.mode=="地方接駁","Tianwei shuttle links beimen, and the garden branch")
	check(Transit.POINTS.beimen=={"bus":{"cell":Vector2i(48,25),"label":"鹽田站牌","mode":"沿海公車","links":["tianwei"]}},"Beimen bus point exact")
	check("beimen" not in Transit.TEA_STOPS and "beimen" not in Transit.LOCAL,"Beimen is neither tea stop nor local plaza")
	check(Transit.point_at("beimen",Vector2i(48,25))=="bus" and Transit.point_at("beimen",Vector2i(12,25))=="","Bus point found by cell only")
	check(Transit.arrival("tianwei","beimen")==Vector2(47.5,25.5) and Transit.arrival("beimen","tianwei")==Vector2(13.5,25.5),"Arrival uses station arrival both ways")
	check(Transit.SALT_MODE==SALT and Transit.FLOWER_MODE=="經縱貫線鐵路南下・轉地方接駁（合併轉乘）","Salt mode exact; flower mode unchanged")

	# 閘門：沒有鹽田來信看不到北門；有信後在田尾直連，一路南下不經臺北。
	var flower_book:={"visited":{"home":true,"ruifang":true,"maokong":true,"yingge":true,"tianwei":true},"legacy_pass":false}
	var salt_book:Dictionary=flower_book.duplicate(true);salt_book.visited.beimen=true
	check(find(Transit.options("tianwei",flower_book,true,"transfer",true,true),"beimen").is_empty(),"Default salt_open=false hides beimen")
	check(find(Transit.options("tianwei",flower_book,true,"transfer",true,true,false),"beimen").is_empty(),"Beimen hidden before the letter")
	check(find(Transit.options("home",salt_book,true,"ferry",true,true,false),"beimen").is_empty(),"Visited beimen still hidden while salt route closed")
	for region in Transit.ROUTE:
		for id in Transit.points(region):
			if region!="beimen":check(find(Transit.options(region,salt_book,true,id,true,true,false),"beimen").is_empty(),"Closed salt route hides beimen from %s/%s"%[region,id])
	var south:=find(Transit.options("tianwei",flower_book,true,"transfer",true,true,true),"beimen")
	check(not south.is_empty() and south.direct and south.mode==SALT and south.label=="北門・鹽風合作鹽田" and south.via==[] and south.arrival==Vector2(47.5,25.5),"After letter Tianwei offers direct southbound merged trip to Beimen")
	check(not str(south.get("mode","")).contains("經臺北"),"Southbound to Beimen never says via Taipei")
	var tianwei_after:=Transit.options("tianwei",flower_book,true,"transfer",true,true,true)
	check(find(tianwei_after,"yingge").mode==Transit.FLOWER_MODE,"Tianwei->Yingge keeps flower corridor wording")
	check(regions_of(tianwei_after)==["home","ruifang","maokong","yingge","beimen"],"Tianwei order unchanged apart from appended beimen")
	var from_beimen:=Transit.options("beimen",salt_book,true,"bus",true,true,true)
	var north:=find(from_beimen,"tianwei")
	check(not north.is_empty() and north.direct and north.mode==SALT and north.via==[],"Beimen->Tianwei uses the merged corridor wording")
	for option in from_beimen:
		check(not str(option.mode).contains("經臺北") or not option.direct,"No direct option from Beimen claims via Taipei "+str(option.region))
		if option.region!="tianwei":check(not option.direct and option.mode=="合併轉乘","Other stations from Beimen are merged transfers "+str(option.region))
	check(regions_of(from_beimen)==["home","ruifang","maokong","yingge","tianwei"],"Beimen offers only known stations and home")
	var maokong_to_beimen:=find(Transit.options("maokong",salt_book,true,"transfer",true,true,true),"beimen")
	check(not maokong_to_beimen.direct and maokong_to_beimen.mode=="合併轉乘" and maokong_to_beimen.via==["yingge","tianwei"],"Maokong->Beimen merged via Yingge and Tianwei")
	check(find(Transit.options("yingge",flower_book,true,"transfer",true,true,true),"beimen").is_empty(),"Unvisited beimen not offered as a shortcut from Yingge")

	# 回家：北門永遠可選風鈴渡口，免費、合併轉乘、列出途經站。
	var home_via:=["tianwei","yingge","maokong","ruifang","toucheng"]
	check(Transit.intermediate("beimen","home")==home_via and Transit.intermediate("home","beimen")==["toucheng","ruifang","maokong","yingge","tianwei"],"Beimen<->home intermediates run through the real corridor")
	for flags in [[false,false,false],[true,true,true],[false,true,false],[true,false,true]]:
		var home:=find(Transit.options("beimen",Transit.fresh(),true,"bus",flags[0],flags[1],flags[2]),"home")
		check(not home.is_empty() and not home.direct and home.mode=="合併轉乘" and home.via==home_via and home.label=="風鈴渡口","Home always listed from Beimen as merged trip "+str(flags))
		check(not home.has("cost") and not home.has("fare") and not home.has("price"),"Return trip carries no cost "+str(flags))
	check(Transit.options("beimen",salt_book,false,"bus",true,true,true).is_empty(),"Locked travel still offers nothing")
	check(TravelUI.NOTES.home.contains("免費"),"Home note says the return is free")

	# 走訪紀錄：options 不寫 visited；World 只在抵達時寫入。
	var before_bytes:=var_to_bytes(flower_book)
	for region in Transit.ROUTE:
		for id in Transit.points(region):Transit.options(region,flower_book,true,id,true,true,true)
	check(var_to_bytes(flower_book)==before_bytes,"Listing routes never writes visited")

	# Transit.valid：舊簿相容，含 beimen 的簿也有效。
	check(Transit.valid(salt_book),"Book with visited.beimen is valid")
	check(Transit.valid(flower_book) and Transit.valid(Transit.fresh()) and Transit.valid({"visited":{"home":true,"jinguashi":true},"legacy_pass":true}),"Old books without beimen stay valid")
	check(not Transit.valid({"visited":{"home":true,"beimen":false},"legacy_pass":false}),"Non-true beimen entry rejected")
	check(not Transit.valid({"visited":{"home":true,"tainan":true},"legacy_pass":false}),"Unknown station still rejected")

	# Regions 對 beimen 一律交給 SaltPan。
	check(Regions.label("beimen")=="北門・鹽風合作鹽田","Region label from STATIONS")
	check(Regions.exit_cell("beimen")==Vector2i(48,25) and Regions.spawn("beimen")==Vector2(47.5,25.5),"Exit cell and spawn from STATIONS")
	var matches:=true
	var resources:=0
	var buildable:=0
	for x in range(0,80):
		for y in range(0,60):
			var p:=Vector2i(x,y)
			if Regions.land(p,"beimen")!=SaltPan.land(p) or Regions.water(p,"beimen")!=SaltPan.water(p) or Regions.protected(p,"beimen")!=SaltPan.protected(p):matches=false
			if Regions.salt_blocked(p,"beimen")!=(not SaltPan.land(p) or SaltPan.blocked(p)):matches=false
			if Regions.resource(p,"beimen")!="":resources+=1
			if Regions.land(p,"beimen") and not Regions.protected(p,"beimen"):buildable+=1
	check(matches,"land/water/protected/blocked delegate to SaltPan")
	check(resources==0,"Beimen spawns no random resources")
	check(buildable==16,"Only the 16 private chest-socket cells are buildable (got %d)"%buildable)
	var arrive:=Vector2i(Transit.STATIONS.beimen.arrival.floor())
	check(Regions.land(arrive,"beimen") and not Regions.water(arrive,"beimen") and not SaltPan.blocked(arrive) and not Regions.salt_blocked(arrive,"beimen"),"Arrival cell is standable land")
	for id in Transit.POINTS.beimen:
		var cell:Vector2i=Transit.POINTS.beimen[id].cell
		check(Regions.land(cell,"beimen") and Regions.protected(cell,"beimen") and not Regions.water(cell,"beimen"),"Beimen travel point is protected land like other stations")
		check(Transit.STATIONS.beimen.arrival.distance_to(Vector2(cell)+Vector2(0.5,0.5))<=3.2,"Arrival is within reach of the bus point")
	check(not Regions.salt_blocked(Vector2i(47,25),"tianwei") and not Regions.salt_blocked(Vector2i(0,0),"home"),"Salt collision only applies in beimen")
	check(Regions.land(Vector2i(13,25),"tianwei") and not Regions.water(Vector2i(13,25),"maokong") and Regions.protected(Vector2i(23,20),"yingge"),"Other region helpers unchanged")

	# 舊站點結果不變（salt_open 開關都一樣）。
	var old_book:={"visited":{"home":true,"ruifang":true},"legacy_pass":false}
	var tea_book:={"visited":{"home":true,"ruifang":true,"maokong":true,"yingge":true},"legacy_pass":false}
	for salt in [false,true]:
		var ruifang:=Transit.options("ruifang",old_book,true,"rail",true,true,salt)
		check(regions_of(ruifang)==["home","toucheng","maokong"] and find(ruifang,"home").via==["toucheng"],"Ruifang rail options unchanged")
		check(find(ruifang,"toucheng").mode=="火車" and find(ruifang,"maokong").mode=="經臺北・鐵路與市區轉乘","Ruifang modes unchanged")
		var yingge:=Transit.options("yingge",tea_book,true,"transfer",true,true,salt)
		check(regions_of(yingge)==["home","ruifang","maokong","tianwei"] and find(yingge,"tianwei").mode==Transit.FLOWER_MODE and find(yingge,"maokong").mode=="經臺北・鐵路與市區轉乘","Yingge options unchanged")
		var ferry:=Transit.options("home",Transit.fresh(),true,"ferry",true,true,salt)
		check(ferry.size()==1 and ferry[0].region=="toucheng" and ferry[0].mode==Transit.HOME_FERRY_MODE,"Home ferry unchanged (boat transfer from 澎湖・望安)")
		var legacy:=Transit.options("jiufen",{"visited":{"home":true},"legacy_pass":true},true,"bus",false,false,salt)
		check(regions_of(legacy)==["home","ruifang","jinguashi"] and find(legacy,"jinguashi").mode=="既有通行","Legacy pass unchanged")
		var tianwei:=Transit.options("tianwei",tea_book,true,"transfer",true,true,salt)
		check(regions_of(tianwei)==(["home","ruifang","maokong","yingge","beimen"] if salt else ["home","ruifang","maokong","yingge"]),"Tianwei lists beimen only as its open direct neighbour")
	check(Transit.intermediate("home","tianwei")==["toucheng","ruifang","maokong","yingge"] and Transit.intermediate("jinguashi","yingge")==["jiufen","ruifang","maokong"],"Old intermediates unchanged")

	# route_options：要自己的鹽田來信才看得到北門。
	var w:=World.new()
	w.add_player("alpha","旅行者")
	w.add_player("beta","同行者")
	w.state.picnic=true
	w.state.chapter_one.shipped=true
	w.state.chapter_one.watered=true
	w.state.board=true
	for token in ["alpha","beta"]:
		w.state.players[token].region="tianwei"
		for station in ["maokong","yingge","tianwei"]:w.state.players[token].travel_book.visited[station]=true
		completed_flower_fixture(w,token)
	w.state.flower_nursery.garden={"given":{"blue_dye":4,"orange_blossom":4,"chime_herb":2},
		"contributors":{"alpha":10},"complete":true,"completed_at":0.0}
	check(not SaltPan.route_open(w.state,"alpha"),"No salt letter in fresh state")
	check(find(Transit.route_options(w.state,"alpha","transfer"),"beimen").is_empty() and not find(Transit.route_options(w.state,"alpha","transfer"),"yingge").is_empty(),"Without letter Beimen is hidden")
	give_salt_letter(w,"alpha")
	check(SaltPan.route_open(w.state,"alpha"),"Letter fixture opens the salt route")
	var opened:=find(Transit.route_options(w.state,"alpha","transfer"),"beimen")
	check(not opened.is_empty() and opened.direct and opened.mode==SALT,"After letter Beimen is listed from Tianwei")
	check(find(Transit.route_options(w.state,"beta","transfer"),"beimen").is_empty(),"Another player's letter does not open the route")
	check(TravelUI.salt_open(w.state,"alpha") and not TravelUI.salt_open(w.state,"beta"),"Travel UI uses server state when no own view")
	check(TravelUI.salt_open({"salt_pan":{"own":{"record":{"letter":true}}}},"x") and not TravelUI.salt_open({"salt_pan":{"own":{"record":{"letter":false}}}},"x"),"Travel UI reads client own record letter")
	check(not TravelUI.salt_open({"players":{}},"x"),"Missing salt data is closed")
	check_visit_record(w)

	# 文字：模式與說明標明合併、縮短，不出現站名、班次、票價。
	for station in Transit.STATIONS:clean(str(Transit.STATIONS[station].name),"STATIONS."+station)
	for region in Transit.POINTS:
		for id in Transit.POINTS[region]:
			clean(str(Transit.POINTS[region][id].label),"POINTS label "+region)
			clean(str(Transit.POINTS[region][id].mode),"POINTS mode "+region)
	for region in Transit.ROUTE:
		for id in Transit.points(region):
			for option in Transit.options(region,salt_book,true,id,true,true,true):
				clean(str(option.mode),"options mode %s->%s"%[region,option.region])
				clean(str(option.label),"options label")
	for key in TravelUI.NOTES:clean(str(TravelUI.NOTES[key]),"travel NOTES."+key)
	for key in TravelUI.ROUTE_NOTES:clean(str(TravelUI.ROUTE_NOTES[key]),"travel ROUTE_NOTES."+key)
	check(TravelUI.note("tianwei","beimen").contains("縱貫線鐵路南下") and TravelUI.note("tianwei","beimen").contains("沿海公車") and TravelUI.note("tianwei","beimen").contains("縮短") and TravelUI.note("tianwei","beimen").contains("原創"),"Beimen note: merged, shortened, original cooperative")
	check(not TravelUI.note("tianwei","beimen").contains("經臺北"),"Beimen note never says via Taipei")
	check(TravelUI.note("beimen","tianwei").contains("北上") and not TravelUI.note("beimen","tianwei").contains("南下"),"Northbound note from Beimen says north")
	check(TravelUI.note("beimen","home").contains("免費") and TravelUI.note("toucheng","home")==TravelUI.NOTES.home and TravelUI.note("tianwei","yingge")==TravelUI.ROUTE_NOTES["tianwei>yingge"],"Home notes: Beimen free return, others unchanged")
	var ui_source:=FileAccess.get_file_as_string("res://scripts/travel_ui.gd")
	check(ui_source.contains("Transit.options(region,book,true,station_id,Transit.tea_unlocked(s),flowers,salts,stars,boat)") and ui_source.contains("map.set_meta(\"salt_open\",salts)"),"Travel UI passes salt route flag to options and map")

	# 地圖：北門在田尾的南方、西海岸；未開放只畫輪廓，地圖本身不接收點擊。
	var map:=Map.new()
	map.set_meta("current_region","tianwei")
	map.set_meta("travel_book",flower_book)
	map.set_meta("salt_open",false)
	var closed:=map.salt_marker()
	check(not closed.open and str(closed.label)=="臺南北門・未開放","Closed marker shows outline label 未開放")
	var tianwei_at:=Map.project(Map.TIANWEI_LONLAT)
	var at:Vector2=closed.position
	check(at.y>tianwei_at.y+30 and at.x<tianwei_at.x,"Beimen marker is south-west of Tianwei")
	var band:=[]
	for point in Outline.POINTS:
		var q:Vector2=point+Map.OFFSET
		if absf(q.y-at.y)<=8.0:band.append(q.x)
	check(not band.is_empty(),"Outline has points near Beimen latitude")
	if not band.is_empty():
		var west:float=band.min()
		var east:float=band.max()
		check(absf(at.x-west)<=8.0 and at.x<(west+east)/2.0,"Beimen marker sits on the west coast (x=%.1f west=%.1f east=%.1f)"%[at.x,west,east])
	map.set_meta("salt_open",true)
	check(map.salt_marker().open and str(map.salt_marker().label)=="臺南北門","Letter opens the marker")
	map.set_meta("salt_open",false);map.set_meta("travel_book",salt_book)
	check(map.salt_marker().open,"Visited Beimen stays shown")
	map.set_meta("travel_book",flower_book);map.set_meta("current_region","beimen")
	check(map.salt_marker().open and str(map.salt_marker().label).ends_with("目前"),"Current region marks Beimen")
	var map_source:=FileAccess.get_file_as_string("res://scripts/taiwan_map.gd")
	check(map_source.contains("mouse_filter=Control.MOUSE_FILTER_IGNORE"),"Map never takes clicks")
	check(map_source.contains("座標待查核") and map_source.contains("120.52"),"Tianwei map point unchanged")
	clean(map_source,"taiwan_map.gd")
	map.free()
	print("SALT_TRANSIT_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func check_visit_record(world:World)->void:
	var departure:Vector2i=Transit.POINTS.tianwei.transfer.cell
	for person:Dictionary in world.state.players.values():
		person.x=departure.x+0.5
		person.y=departure.y+0.5
	var path:="user://salt-transit-%d-%d.json"%[OS.get_process_id(),Time.get_ticks_usec()]
	world.save_path=path
	var other_book:Dictionary=world.state.players.beta.travel_book.duplicate(true)
	var refused:=world.act("beta","refuse-salt", "transit",departure,"beimen")
	check(not refused.ok and world.player_region("beta")=="tianwei","A player without the letter remains in Tianwei")
	check(world.state.players.beta.travel_book==other_book,"A refused transfer leaves the visit record unchanged")
	var arrived:=world.act("alpha","visit-salt","transit",departure,"beimen")
	check(arrived.ok and world.player_region("alpha")=="beimen","The unlocked ticket arrives in Beimen")
	check(world.state.players.alpha.travel_book.visited.get("beimen",false) and world.state.players.beta.travel_book==other_book,"Only the traveler records a successful visit")
	var reloaded:=World.new()
	check(reloaded.load_world(path) and reloaded.player_region("alpha")=="beimen" and reloaded.state.players.alpha.travel_book.visited.get("beimen",false),"The new visit survives reloading the world")
	for suffix in ["",".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
