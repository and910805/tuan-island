extends SceneTree
const World=preload("res://scripts/world.gd")
const Transit=preload("res://scripts/transit.gd")
const Regions=preload("res://scripts/regions.gd")
const TravelUI=preload("res://scripts/travel_ui.gd")
const FlowerNursery=preload("res://scripts/flower_nursery.gd")
const FORBIDDEN:=["田尾站","田尾火車站","直達"]
const SOUTH:="經縱貫線鐵路南下・轉地方接駁（合併轉乘）"
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

func give_letter(w:World,token:String)->void:
	var nursery:Dictionary=w.state.get("flower_nursery",FlowerNursery.fresh())
	if not nursery.has("players"):nursery.players={}
	var record:Dictionary=FlowerNursery.own_record(w.state,token)
	record.letter=true
	nursery.players[token]=record
	w.state.flower_nursery=nursery

func _initialize()->void:
	# 圖與常數：只能附加在尾端，舊順序不變。
	check(Transit.ROUTE==["home","toucheng","ruifang","jiufen","jinguashi","maokong","yingge","tianwei","beimen","jiaoxi","bamboo_grove","star_garden"],"ROUTE appends tianwei (then chapter-4 beimen) before the fishing branches")
	var original_regions:=["home","lanyang","jinguashi","toucheng","ruifang","jiufen","mine_1","mine_2","mine_3","mine_4","mine_5","maokong","yingge","tianwei","beimen","jiaoxi","bamboo_grove","star_garden"]+Regions.DEEP_MINES
	check(Regions.ALL.slice(0,original_regions.size())==original_regions,"Tianwei, other stops and mine floors retain their original order")
	check(Transit.CONNECTIONS.yingge==["maokong","tianwei"] and Transit.CONNECTIONS.tianwei==["yingge","beimen","star_garden"],"yingge<->tianwei connection (tianwei also links chapter-4 beimen)")
	check(Transit.STATIONS.tianwei=={"name":"田尾合作花圃","cell":Vector2i(12,25),"arrival":Vector2(13.5,25.5),"size":Vector2i(80,60)},"Tianwei station exact")
	check(Transit.POINTS.yingge.transfer.links==["maokong","tianwei"],"Yingge transfer links tianwei")
	check(Transit.POINTS.tianwei=={"transfer":{"cell":Vector2i(12,25),"label":"花圃接駁點","mode":"地方接駁","links":["yingge","beimen","star_garden"]}},"Tianwei shuttle point exact (links chapter-4 beimen)")
	check("tianwei" not in Transit.TEA_STOPS and "tianwei" not in Transit.LOCAL,"Tianwei is neither tea stop nor local plaza")
	check(Transit.point_at("tianwei",Vector2i(12,25))=="transfer","Shuttle point found by cell")
	check(Transit.arrival("yingge","tianwei")==Vector2(13.5,25.5) and Transit.arrival("tianwei","yingge")==Vector2(13.5,25.5),"Arrival uses station arrival")

	# 閘門：未讀信看不到田尾；讀信後在鶯歌直連。
	var tea_book:={"visited":{"home":true,"ruifang":true,"maokong":true,"yingge":true},"legacy_pass":false}
	check(find(Transit.options("yingge",tea_book,true,"transfer",true),"tianwei").is_empty(),"Default flower_open=false hides tianwei")
	check(find(Transit.options("yingge",tea_book,true,"transfer",true,false),"tianwei").is_empty(),"Tianwei hidden without letter")
	var seen_book:Dictionary=tea_book.duplicate(true);seen_book.visited.tianwei=true
	check(find(Transit.options("home",seen_book,true,"ferry",true,false),"tianwei").is_empty(),"Visited tianwei still hidden while flower route closed")
	var south:=find(Transit.options("yingge",tea_book,true,"transfer",true,true),"tianwei")
	check(not south.is_empty() and south.direct and south.mode==SOUTH and south.label=="田尾合作花圃" and south.via==[],"Yingge offers direct southbound combined transfer to Tianwei")
	check(not str(south.get("mode","")).contains("經臺北"),"Southbound mode never says via Taipei")
	var maokong:=find(Transit.options("yingge",tea_book,true,"transfer",true,true),"maokong")
	check(maokong.mode=="經臺北・鐵路與市區轉乘","Yingge->Maokong keeps Taipei override")
	var north_options:=Transit.options("tianwei",seen_book,true,"transfer",true,true)
	var north:=find(north_options,"yingge")
	check(not north.is_empty() and north.direct and north.mode==SOUTH and not str(north.mode).contains("經臺北"),"Tianwei->Yingge uses the same corridor wording, not via Taipei")
	for option in north_options:
		if option.region!="yingge":check(not option.direct and option.mode=="合併轉乘","Other stations from Tianwei are combined transfer "+str(option.region))
	check(find(north_options,"home").mode=="合併轉乘","Home reachable from Tianwei")
	check(regions_of(north_options)==["home","ruifang","maokong","yingge"],"Tianwei offers only known stations and home")
	var fresh_book:=Transit.fresh()
	check(find(Transit.options("tianwei",fresh_book,true,"transfer",true,true),"home").region=="home","Home always selectable even with fresh book")
	check(find(Transit.options("tianwei",fresh_book,true,"transfer",false,true),"home").region=="home","Home selectable even if tea flag missing")
	var from_home:=find(Transit.options("home",seen_book,true,"ferry",true,true),"tianwei")
	check(not from_home.direct and from_home.mode=="合併轉乘","Home->Tianwei is combined transfer")
	check(from_home.via==["toucheng","ruifang","maokong","yingge"] and Transit.intermediate("home","tianwei")==["toucheng","ruifang","maokong","yingge"],"Home->Tianwei goes via Yingge")
	var from_maokong:=find(Transit.options("maokong",seen_book,true,"transfer",true,true),"tianwei")
	check(not from_maokong.direct and from_maokong.mode=="合併轉乘" and from_maokong.via==["yingge"],"Maokong->Tianwei is combined via Yingge")
	check(find(Transit.options("home",tea_book,true,"ferry",true,true),"tianwei").is_empty(),"Unvisited tianwei not offered from home shortcut")

	# route_options：茶陶章完成但沒有信 → 看不到；有信 → 看得到。
	var w:=World.new()
	w.add_player("alpha","旅行者")
	w.add_player("beta","同行者")
	w.state.picnic=true
	w.state.chapter_one.shipped=true
	w.state.chapter_one.watered=true
	w.state.board=true
	check(Transit.tea_unlocked(w.state),"Fixture has tea branch unlocked")
	for token in ["alpha","beta"]:
		w.state.players[token].region="yingge"
		w.state.players[token].travel_book.visited.maokong=true
		w.state.players[token].travel_book.visited.yingge=true
	check(not FlowerNursery.route_open(w.state,"alpha"),"No letter in fresh state")
	var before:=Transit.route_options(w.state,"alpha","transfer")
	check(find(before,"tianwei").is_empty() and not find(before,"maokong").is_empty(),"Tea-unlocked player without letter cannot see Tianwei")
	give_letter(w,"alpha")
	check(FlowerNursery.route_open(w.state,"alpha"),"Letter fixture opens route")
	var after:=find(Transit.route_options(w.state,"alpha","transfer"),"tianwei")
	check(not after.is_empty() and after.direct and after.mode==SOUTH,"After letter Tianwei visible from Yingge")
	check(find(Transit.route_options(w.state,"beta","transfer"),"tianwei").is_empty(),"Another player's letter does not open the route")
	check(TravelUI.flower_open(w.state,"alpha") and not TravelUI.flower_open(w.state,"beta"),"Travel UI uses server state when no own view")
	check(TravelUI.flower_open({"flower_nursery":{"own":{"own_record":{"letter":true},"own_given":0}}},"x"),"Travel UI reads client own_record letter")
	check(not TravelUI.flower_open({"flower_nursery":{"own":{"own_record":{"letter":false},"own_given":0}}},"x"),"Client own_record without letter stays closed")
	check(not TravelUI.flower_open({},"x"),"Missing nursery data is closed")

	# Transit.valid
	check(Transit.valid(seen_book),"visited with tianwei is valid")
	check(Transit.valid(tea_book) and Transit.valid(Transit.fresh()) and Transit.valid({"visited":{"home":true,"jinguashi":true},"legacy_pass":true}),"Old visited books stay valid")
	check(not Transit.valid({"visited":{"home":true,"tianwei":false},"legacy_pass":false}),"Non-true tianwei entry rejected")
	check(not Transit.valid({"visited":{"home":true,"taichung":true},"legacy_pass":false}),"Unknown station still rejected")

	# Regions 對 tianwei。
	check(Regions.label("tianwei")=="田尾合作花圃","Region label from STATIONS")
	check(Regions.exit_cell("tianwei")==Vector2i(12,25) and Regions.spawn("tianwei")==Vector2(13.5,25.5),"Exit cell and spawn from STATIONS")
	var beds:Rect2i=FlowerNursery.NURSERY_BEDS
	var land_rect:Rect2i=FlowerNursery.LAND
	var bed_cells:=0
	var outside_protected:=true
	var land_matches:=true
	for x in range(0,80):
		for y in range(0,60):
			var p:=Vector2i(x,y)
			if Regions.land(p,"tianwei")!=FlowerNursery.land(p):land_matches=false
			if Regions.water(p,"tianwei"):check(false,"Tianwei has no water "+str(p))
			if Regions.resource(p,"tianwei")!="":check(false,"Tianwei spawns no random resource "+str(p))
			if beds.has_point(p):
				bed_cells+=1
				check(Regions.land(p,"tianwei") and not Regions.protected(p,"tianwei"),"Nursery bed is open land "+str(p))
			elif not Regions.protected(p,"tianwei"):outside_protected=false
	check(land_matches,"Regions.land delegates to FlowerNursery.land")
	check(bed_cells==24 and outside_protected,"Only the 24 nursery bed cells are unprotected")
	check(Regions.land(Vector2i(13,25),"tianwei") and not Regions.flower_blocked(Vector2i(13,25),"tianwei"),"Arrival cell is walkable land")
	check(not Regions.land(Vector2i(land_rect.position.x-1,land_rect.position.y),"tianwei") and Regions.flower_blocked(Vector2i(land_rect.position.x-1,land_rect.position.y),"tianwei"),"Outside nursery land blocks walking")
	check(Regions.flower_blocked(FlowerNursery.SHED.position,"tianwei"),"Shed blocks walking")
	check(not Regions.flower_blocked(Vector2i(0,0),"home") and not Regions.flower_blocked(FlowerNursery.SHED.position,"yingge"),"Flower collision only applies in tianwei")

	# 舊站點結果不變（與加入田尾前的行為逐項比對）。
	var old_book:={"visited":{"home":true,"ruifang":true},"legacy_pass":false}
	for flowers in [false,true]:
		var ruifang:=Transit.options("ruifang",old_book,true,"rail",true,flowers)
		check(regions_of(ruifang)==["home","toucheng","maokong"],"Ruifang rail options unchanged")
		check(find(ruifang,"home").mode=="合併轉乘" and find(ruifang,"home").via==["toucheng"],"Ruifang->home unchanged")
		check(find(ruifang,"toucheng").mode=="火車" and find(ruifang,"maokong").mode=="經臺北・鐵路與市區轉乘","Ruifang rail modes unchanged")
		var yingge:=Transit.options("yingge",tea_book,true,"transfer",true,flowers)
		check(regions_of(yingge)==(["home","ruifang","maokong","tianwei"] if flowers else ["home","ruifang","maokong"]),"Yingge order unchanged apart from appended tianwei")
		check(find(yingge,"home").via==["maokong","ruifang","toucheng"] and find(yingge,"ruifang").mode=="合併轉乘","Yingge->home/ruifang unchanged")
		var ferry:=Transit.options("home",Transit.fresh(),true,"ferry",true,flowers)
		check(ferry.size()==1 and ferry[0].region=="toucheng" and ferry[0].mode==Transit.HOME_FERRY_MODE,"Home ferry unchanged (boat transfer from 澎湖・望安)")
		var legacy:=Transit.options("jiufen",{"visited":{"home":true},"legacy_pass":true},true,"bus",false,flowers)
		check(regions_of(legacy)==["home","ruifang","jinguashi"] and find(legacy,"jinguashi").mode=="既有通行" and find(legacy,"ruifang").mode=="公車","Legacy pass unchanged")
	check(Transit.options("yingge",tea_book,false,"transfer",true,true).is_empty(),"Locked travel still offers nothing")
	check(Transit.intermediate("jinguashi","yingge")==["jiufen","ruifang","maokong"] and Transit.intermediate("yingge","toucheng")==["maokong","ruifang"],"Old intermediates unchanged")
	check(Transit.arrival("maokong","ruifang")==Vector2(15.5,19.5) and Transit.arrival("jiufen","ruifang")==Vector2(30.5,25.5),"Old arrival overrides stay beside (not on) the Ruifang stop signs")
	check(Regions.label("yingge")=="鶯歌合作陶坊" and Regions.protected(Vector2i(23,20),"yingge") and not Regions.water(Vector2i(13,25),"maokong"),"Tea stop region helpers unchanged")

	# 禁用字掃描。
	for station in Transit.STATIONS:clean(str(Transit.STATIONS[station].name),"STATIONS."+station)
	for region in Transit.POINTS:
		for id in Transit.POINTS[region]:
			clean(str(Transit.POINTS[region][id].label),"POINTS label "+region)
			clean(str(Transit.POINTS[region][id].mode),"POINTS mode "+region)
	for region in Transit.ROUTE:
		for id in Transit.points(region):
			for option in Transit.options(region,seen_book,true,id,true,true):
				clean(str(option.mode),"options mode %s->%s"%[region,option.region])
				clean(str(option.label),"options label")
	for key in TravelUI.NOTES:clean(str(TravelUI.NOTES[key]),"travel NOTES."+key)
	for key in TravelUI.ROUTE_NOTES:clean(str(TravelUI.ROUTE_NOTES[key]),"travel ROUTE_NOTES."+key)
	check(TravelUI.NOTES.tianwei=="經縱貫線鐵路南下彰化，再轉地方接駁到虛構的田尾合作花圃。田尾以花卉苗木聞名；這裡的花農與花圃都是原創，交通以遊戲合併轉乘呈現。","Tianwei travel note matches contract")
	check(not TravelUI.note("tianwei","yingge").contains("經臺北") and TravelUI.note("toucheng","yingge")==TravelUI.NOTES.yingge,"Northbound note from Tianwei does not claim via Taipei; other origins unchanged")
	var map_source:=FileAccess.get_file_as_string("res://scripts/taiwan_map.gd")
	check(map_source.contains("座標待查核") and map_source.contains("120.52") and map_source.contains("23.89"),"Map Tianwei point flagged as pending verification")
	clean(map_source,"taiwan_map.gd")
	print("TIANWEI_TRANSIT_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
