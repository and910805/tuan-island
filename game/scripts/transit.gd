extends RefCounted
const FlowerNursery=preload("res://scripts/flower_nursery.gd")
const SaltPan=preload("res://scripts/salt_pan.gd")
const Springs=preload("res://scripts/warm_springs.gd")
const Bamboo=preload("res://scripts/bamboo_grove.gd")
const StarGarden=preload("res://scripts/star_garden.gd")

const ROUTE := ["home", "toucheng", "ruifang", "jiufen", "jinguashi", "maokong", "yingge", "tianwei", "beimen", Springs.REGION,Bamboo.REGION,StarGarden.REGION]
const TEA_STOPS := ["maokong", "yingge"]
const CONNECTIONS := {
	"home":["toucheng"], "toucheng":["home","ruifang",Springs.REGION],
	Springs.REGION:["toucheng"],
	"ruifang":["toucheng","jiufen","maokong"], "jiufen":["ruifang","jinguashi"],
	"jinguashi":["jiufen"], "maokong":["ruifang","yingge",Bamboo.REGION], "yingge":["maokong","tianwei"],
	Bamboo.REGION:["maokong"],
	"tianwei":["yingge","beimen",StarGarden.REGION], "beimen":["tianwei"],
	StarGarden.REGION:["tianwei"],
}
# tianwei 不是茶陶站也不是 LOCAL 廣場；地形與碰撞由 FlowerNursery 決定。
const FLOWER_STOP := "tianwei"
# 鶯歌↔田尾是縱貫線鐵路走廊加地方接駁的合併旅程；田尾沒有火車站，也不是直達。
const FLOWER_MODE := "經縱貫線鐵路南下・轉地方接駁（合併轉乘）"
# beimen 是虛構的鹽風合作鹽田；地形與碰撞由 SaltPan 決定。
const SALT_STOP := "beimen"
# 田尾↔北門是花圃接駁、縱貫線鐵路南下、再轉沿海公車的合併旅程；不提供班次、票價或真實站名。
const SALT_MODE := "花圃接駁・縱貫線鐵路南下・轉沿海公車（合併轉乘）"
const LOCAL := ["toucheng", "ruifang", "jiufen"]
const HOME_FERRY_MODE := "交通船・轉乘"
const PLAZA := Rect2i(9,12,31,18)
const STATIONS := {
	"home":{"name":"風鈴渡口","cell":Vector2i(47,30),"arrival":Vector2(46.5,30.5),"size":Vector2i(80,60)},
	"toucheng":{"name":"頭城車站","cell":Vector2i(25,19),"arrival":Vector2(12.5,25.5),"size":Vector2i(80,60)},
	"ruifang":{"name":"瑞芳轉乘廣場","cell":Vector2i(31,25),"arrival":Vector2(14.5,19.5),"size":Vector2i(80,60)},
	"jiufen":{"name":"九份山城","cell":Vector2i(29,20),"arrival":Vector2(12.5,25.5),"size":Vector2i(80,60)},
	"jinguashi":{"name":"金瓜石山城","cell":Vector2i(11,20),"arrival":Vector2(12.5,20.5),"size":Vector2i(80,60)},
	"maokong":{"name":"貓空合作茶園","cell":Vector2i(12,25),"arrival":Vector2(13.5,25.5),"size":Vector2i(80,60)},
	"yingge":{"name":"鶯歌合作陶坊","cell":Vector2i(12,25),"arrival":Vector2(13.5,25.5),"size":Vector2i(80,60)},
	"tianwei":{"name":"田尾合作花圃","cell":Vector2i(12,25),"arrival":Vector2(13.5,25.5),"size":Vector2i(80,60)},
	"beimen":{"name":"北門・鹽風合作鹽田","cell":Vector2i(48,25),"arrival":Vector2(47.5,25.5),"size":Vector2i(80,60)},
	Springs.REGION:{"name":"礁溪・暖泉高地","cell":Vector2i(13,25),"arrival":Vector2(14.5,25.5),"size":Vector2i(80,60)},
	Bamboo.REGION:{"name":"貓空・霧竹溪谷","cell":Vector2i(13,25),"arrival":Vector2(14.5,25.5),"size":Vector2i(80,60)},
	StarGarden.REGION:{"name":"星芽庭園","cell":Vector2i(13,25),"arrival":Vector2(14.5,25.5),"size":Vector2i(80,60)},
}
const BUILDINGS := {
	"toucheng":[Rect2i(20,15,10,3)],
	"ruifang":[Rect2i(10,15,9,3),Rect2i(27,15,10,3)],
	"jiufen":[Rect2i(12,14,9,4),Rect2i(27,14,10,4)],
}

const VEHICLES := {
	"toucheng":Rect2i(15,17,4,2),
	"ruifang":Rect2i(29,22,5,2),
}

static func blocked(p:Vector2i,region:String)->bool:
	if VEHICLES.has(region) and VEHICLES[region].has_point(p):return true
	for footprint in BUILDINGS.get(region,[]):
		if footprint.has_point(p):return true
	return false

static func fresh()->Dictionary:
	return {"visited":{"home":true},"legacy_pass":false}

static func valid(book:Variant)->bool:
	if not book is Dictionary or book.size()!=2 or not book.get("legacy_pass") is bool or not book.get("visited") is Dictionary:return false
	if book.visited.get("home") != true:return false
	for station in book.visited:
		if station not in ROUTE or book.visited[station] != true:return false
	return true

const POINTS := {
	# 出生島在澎湖・望安：渡口與頭城之間是交通船加陸上轉乘的合併旅程（不提供航線、班次或業者）。
	"home":{"ferry":{"cell":Vector2i(47,30),"label":"渡口轉乘","mode":HOME_FERRY_MODE,"links":["toucheng"]}},
	"toucheng":{"street":{"cell":Vector2i(12,25),"label":"車站街口","mode":HOME_FERRY_MODE,"links":["home"]},"rail":{"cell":Vector2i(25,19),"label":"頭城月台","mode":"火車","links":["ruifang",Springs.REGION]}},
	Springs.REGION:{"rail":{"cell":Vector2i(13,25),"label":"暖泉轉乘點","mode":"地方接駁","links":["toucheng"]}},
	"ruifang":{"rail":{"cell":Vector2i(14,19),"label":"瑞芳鐵路門","mode":"火車","links":["toucheng","maokong"]},"bus":{"cell":Vector2i(31,25),"label":"瑞芳公車站","mode":"公車","links":["jiufen"]}},
	"jiufen":{"bus":{"cell":Vector2i(12,25),"label":"九份公車站","mode":"公車","links":["ruifang"]},"shuttle":{"cell":Vector2i(29,20),"label":"金瓜石接駁站","mode":"接駁","links":["jinguashi"]}},
	"jinguashi":{"shuttle":{"cell":Vector2i(11,20),"label":"山城接駁站","mode":"接駁","links":["jiufen"]}},
	"maokong":{"transfer":{"cell":Vector2i(12,25),"label":"貓空轉乘站","mode":"市區轉乘","links":["ruifang","yingge",Bamboo.REGION]}},
	Bamboo.REGION:{"trail":{"cell":Vector2i(13,25),"label":"溪谷步道口","mode":"步行","links":["maokong"]}},
	"yingge":{"transfer":{"cell":Vector2i(12,25),"label":"鶯歌工坊街口","mode":"鐵路與市區轉乘","links":["maokong","tianwei"]}},
	# 花圃接駁點屬於虛構的合作花圃，不是真實站名。
	"tianwei":{"transfer":{"cell":Vector2i(12,25),"label":"花圃接駁點","mode":"地方接駁","links":["yingge","beimen",StarGarden.REGION]}},
	StarGarden.REGION:{"trail":{"cell":Vector2i(13,25),"label":"庭園步道口","mode":"步行","links":["tianwei"]}},
	# 鹽田站牌屬於虛構的合作鹽田，不是真實公車站名或路線。
	"beimen":{"bus":{"cell":Vector2i(48,25),"label":"鹽田站牌","mode":"沿海公車","links":["tianwei"]}},
}

static func points(region:String)->Dictionary:
	return POINTS.get(region,{})

static func point_at(region:String,cell:Vector2i)->String:
	for id in points(region):
		if points(region)[id].cell==cell:return id
	return ""

static func route_options(state:Dictionary,token:String,station_id:String)->Array[Dictionary]:
	var person:Dictionary=state.get("players",{}).get(token,{})
	return options(str(person.get("region","home")),person.get("travel_book",{}),state.get("picnic",false),station_id,tea_unlocked(state),FlowerNursery.route_open(state,token),SaltPan.route_open(state,token),star_garden_open(state),boat_open(state))

static func boat_open(state:Dictionary)->bool:
	return int(state.get("dock_stage",0))>=2

static func star_garden_open(state:Dictionary)->bool:
	return state.get("flower_nursery",{}).get("garden",{}).get("complete",false)==true

static func tea_unlocked(state:Dictionary)->bool:
	return preload("res://scripts/chapter_one.gd").phase(state)=="complete"

static func options(region:String,book:Dictionary,unlocked:bool,station_id:String,tea_open:bool=false,flower_open:bool=false,salt_open:bool=false,star_open:bool=false,boat_ready:bool=false)->Array[Dictionary]:
	var result:Array[Dictionary]=[]
	if not unlocked or not points(region).has(station_id):return result
	var point:Dictionary=points(region)[station_id]
	var known:Dictionary=book.get("visited",{})
	for station in ROUTE:
		if station==region:continue
		if station==Bamboo.REGION and not tea_open:continue
		if station==StarGarden.REGION and (not star_open or not flower_open):continue
		if station in TEA_STOPS and not tea_open:continue
		if station==FLOWER_STOP and not flower_open:continue
		if station==SALT_STOP and not salt_open:continue
		var boat:bool=boat_ready and ((region=="home" and station in [Bamboo.REGION,Springs.REGION]) or (station=="home" and region in [Bamboo.REGION,Springs.REGION]))
		if boat:
			result.append({"region":station,"label":STATIONS[station].name,"direct":true,"mode":"合作小船","arrival":STATIONS[station].arrival,"via":[]})
			continue
		var direct:bool=station in point.links
		var legacy:bool=book.get("legacy_pass",false) and station=="jinguashi"
		if direct or station=="home" or known.has(station) or legacy:
			var mode:String=point.mode if direct else ("既有通行" if legacy and not known.has(station) else "合併轉乘")
			# 田尾覆寫必須排在「經臺北」之前：往南的路線不經臺北。
			# 北門覆寫排在田尾與「經臺北」之前：田尾往北門一路南下。
			if direct and [region,station].has(SALT_STOP) and [region,station].has(FLOWER_STOP):mode=SALT_MODE
			elif direct and [region,station].has(FLOWER_STOP) and [region,station].has("yingge"):mode=FLOWER_MODE
			elif direct and Bamboo.REGION in [region,station]:mode="茶園步道"
			elif direct and StarGarden.REGION in [region,station]:mode="庭園步道"
			elif direct and (station in TEA_STOPS or region in TEA_STOPS):mode="經臺北・鐵路與市區轉乘"
			result.append({"region":station,"label":STATIONS[station].name,"direct":direct,"mode":mode,"arrival":arrival(region,station),"via":intermediate(region,station)})
	return result

static func intermediate(origin:String,destination:String)->Array:
	if not CONNECTIONS.has(origin) or not CONNECTIONS.has(destination) or origin==destination:return []
	var queue:Array=[[origin]]
	var seen:Dictionary={origin:true}
	while not queue.is_empty():
		var path:Array=queue.pop_front()
		for next in CONNECTIONS[path.back()]:
			if seen.has(next):continue
			var extended:Array=path.duplicate()
			extended.append(next)
			if next==destination:return extended.slice(1,extended.size()-1)
			seen[next]=true
			queue.append(extended)
	return []

static func arrival(origin:String,destination:String)->Vector2:
	if origin in ["ruifang",Springs.REGION] and destination=="toucheng":return Vector2(24.5,19.5)
	if origin=="jiufen" and destination=="ruifang":return Vector2(30.5,25.5)
	if origin=="jinguashi" and destination=="jiufen":return Vector2(28.5,20.5)
	if origin=="maokong" and destination=="ruifang":return Vector2(14.5,19.5)
	return STATIONS[destination].arrival
