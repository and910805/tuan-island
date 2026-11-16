extends Control
const World=preload("res://scripts/world.gd")
const Shell=preload("res://scripts/life_ui_shell.gd")
const Items=preload("res://scripts/inventory_item_art.gd")
const TransitArt=preload("res://scripts/transit_art.gd")
const Opening=preload("res://scripts/wangan_opening.gd")
const SCALE:=7.0
const RETURN_SIGN_LEVEL:=3

static func return_sign(region:String,points:int) -> Dictionary:
	if region==World.REGIONS.HOME or region not in World.REGIONS.ALL or World.exploration_level(points)<RETURN_SIGN_LEVEL:return {}
	if region in World.MINES.IDS:
		return {"cell":World.MINES.UP,"hint":"返家路標 · 先走上階，離開礦場後再轉乘回渡口。"}
	var cell:=World.REGIONS.exit_cell(region)
	if region=="toucheng":cell=World.TRANSIT.POINTS.toucheng.street.cell
	if region=="ruifang":cell=World.TRANSIT.POINTS.ruifang.rail.cell
	if region=="jiufen":cell=World.TRANSIT.POINTS.jiufen.bus.cell
	return {"cell":cell,"hint":"返家路標 · 前往標記處，開啟旅圖並選擇風鈴渡口。"}

## 野餐前家園地圖的來信標記（格座標，已含 0.5 置中）與說明。第一株作物引導進行中且
## 田仍可用時（WanganOpening.marker_shown），標記指向「小栗留的田」的中心，而不是小栗本人。
static func letter_target(s:Dictionary,owner:String) -> Dictionary:
	var step:Dictionary=World.CHAPTER_ONE.next_step(s)
	var at:=Vector2(step.cell)+Vector2(0.5,0.5)
	var text:="來信標記："+str(step.action)
	var plot_marked:=false
	if step.id=="ship":
		var shipping:Vector2i=World.SHIPPING.cell_for(s)
		if shipping!=World.SHIPPING.NO_CELL:at=Vector2(shipping)+Vector2(0.5,0.5)
	elif step.id=="grow" and Opening.marker_shown(s,owner):
		var plot:=Opening.plot_rect()
		at=Vector2(plot.position)+Vector2(plot.size)*0.5
		text+=" · "+Opening.PLOT_TAG
		plot_marked=true
	return {"at":at,"text":text,"plot":plot_marked}

func draw_return_sign(origin:Vector2,at:Vector2,hint:String) -> void:
	draw_texture_rect(Shell.icon("home"),Rect2(at+Vector2(-11,-34),Vector2(22,22)),false)
	draw_string(font,origin+Vector2(12,67),hint,HORIZONTAL_ALIGNMENT_LEFT,530,14,Color("244847"))
var data:Dictionary={}
var own_id:=""
var font:FontVariation
func _ready() -> void:
	custom_minimum_size=Vector2(560,420)
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	font=preload("res://scripts/island_type.gd").regular()
func update_world(snapshot:Dictionary,id:String) -> void:
	data=snapshot
	own_id=id
	queue_redraw()
func _draw() -> void:
	if data.is_empty() or font==null:return
	var region:=str(data.get("region_id","home"))
	var local_world:=World.new()
	local_world.state=data
	local_world._region=region
	var viewer:Dictionary=data.players.get(own_id,{})
	var show_resources:=World.gathering_level(viewer)>=World.RESOURCE_MAP_LEVEL
	var origin:=Vector2((size.x-560)/2,0)
	if region.begins_with("mine_"):
		draw_mine_map(origin,region)
		return
	if TransitArt.NAMES.has(region):
		draw_transit_map(origin,region)
		return
	draw_rect(Rect2(origin,Vector2(560,420)),Color("92c6be"))
	for y in range(World.SIZE.y):
		for x in range(World.SIZE.x):
			var p:=Vector2i(x,y)
			var k:=World.key(p)
			var at:=origin+Vector2(p)*SCALE
			if local_world.water(p):continue
			var tint:=Color("b8a596") if region=="jinguashi" else Color("bad298")
			if data.crops.has(k):tint=Color("9e7b55")
			elif data.ground.has(k):tint=Color("d5b27e")
			draw_rect(Rect2(at,Vector2.ONE*SCALE),tint)
			if data.objects.has(k) or data.get("roofs",{}).has(k):
				draw_rect(Rect2(at+Vector2.ONE,Vector2(5,5)),Color("a76e58"))
				continue
			var resource:=local_world.resource(p)
			if show_resources and not local_world.protected(p):
				match resource:
					"tree": draw_rect(Rect2(at+Vector2.ONE,Vector2(5,5)),Color("287043"))
					"rock": draw_rect(Rect2(at+Vector2.ONE,Vector2(5,5)),Color("53687e"))
					"grass": draw_rect(Rect2(at+Vector2(2,2),Vector2(3,3)),Color("b18639"))
			elif resource in ["tree","sapling"]:
				draw_rect(Rect2(at+Vector2(2,2),Vector2(3,3)),Color("6e9a61"))
			elif resource=="rock":
				draw_rect(Rect2(at+Vector2(2,2),Vector2(3,3)),Color("8e9a8a"))
	var sign_info:=return_sign(region,int(viewer.get("exploration_points",0)))
	if not sign_info.is_empty():
		draw_return_sign(origin,origin+(Vector2(sign_info.cell)+Vector2(0.5,0.5))*SCALE,sign_info.hint)
	# Landmarks are separate from player markers so nobody's location is hidden.
	if region=="home":
		mark(origin+Vector2(40.5,29.5)*SCALE,Color("e0b558"),false)
		draw_string(font,origin+Vector2(36,27)*SCALE,"渡口／種子攤",HORIZONTAL_ALIGNMENT_LEFT,-1,15,Color("35533f"))
		mark(origin+Vector2(45.5,34.5)*SCALE,Color("fff3d0"),false)
		mark(origin+Vector2(54.5,25.5)*SCALE,Color("8b9386"),false)
		draw_string(font,origin+Vector2(49,22)*SCALE,"採石／運入礦料",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("35533f"))
		draw_string(font,origin+Vector2(58,30)*SCALE,"河灣橋",HORIZONTAL_ALIGNMENT_LEFT,-1,15,Color("35533f"))
		if not data.board:draw_string(font,origin+Vector2(58,33)*SCALE,"待修復",HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("617964"))
	var fishing_sites:Dictionary={World.SALT_PAN.REGION:World.SALT_PAN.FISHING_SPOTS,World.REGIONS.Springs.REGION:World.REGIONS.Springs.POOLS,World.REGIONS.Bamboo.REGION:World.REGIONS.Bamboo.POOLS,World.REGIONS.StarGarden.REGION:World.REGIONS.StarGarden.POOLS}
	if fishing_sites.has(region):
		var spots:Dictionary=fishing_sites[region]
		for spot in spots.values():
			var at:=origin+Vector2(spot.water.get_center())*SCALE+Vector2.ONE*SCALE*0.5
			mark(at,Color("426f78"),false)
			draw_texture_rect(Items.icon(spot.fish),Rect2(at+Vector2(10,-12),Vector2(24,24)),false)
			draw_string(font,at+Vector2(36,5),spot.label,HORIZONTAL_ALIGNMENT_LEFT,125,15,Color("244847"))
	for id in data.players:
		var person:Dictionary=data.players[id]
		var at:=origin+Vector2(person.x,person.y)*SCALE
		mark(at,Color("c96755") if id==own_id else Color("537ea4"),true)
		if id==own_id and region not in World.REGIONS.ANGLING_RESERVES:
			draw_string(font,at+Vector2(9,17),"你在這裡",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("8a463e"))
	if region=="home" and not data.get("picnic",false):
		var letter:=letter_target(data,own_id)
		var point:=origin+Vector2(letter.at)*SCALE
		# 田正好在「渡口／種子攤」字樣上方，信件圖示再往上提一點，避免壓到字。
		draw_texture_rect(Shell.icon("letter"),Rect2(point-Vector2(12,38 if letter.plot else 30),Vector2(24,24)),false)
		draw_string(font,origin+Vector2(12,26),str(letter.text),HORIZONTAL_ALIGNMENT_LEFT,530,15,Color("35533f"))
		draw_string(font,origin+Vector2(12,47),"澎湖・望安 · 風鈴渡口（本地地圖）",HORIZONTAL_ALIGNMENT_LEFT,530,13,Color("35533f"))
	elif region.begins_with("mine_"):
		var depth:=int(region.trim_prefix("mine_"))
		draw_string(font,origin+Vector2(12,26),"金瓜石合作礦場・地下第 %d 層"%depth,HORIZONTAL_ALIGNMENT_LEFT,530,15,Color("35533f"))
		var stations:Dictionary={World.MINES.UP:"上階",World.MINES.REST:"休息",World.MINES.SERVICE:"礦務站"}
		if depth<World.MINES.MAX_DEPTH:stations[World.MINES.DOWN]="下階"
		if depth>World.MINES.SHALLOW_DEPTH:stations[World.MINES.LIFT]="升降台"
		for cell in stations:
			var at:=origin+(Vector2(cell)+Vector2(0.5,0.5))*SCALE
			mark(at,Color("e0b558"),false)
			draw_string(font,at+Vector2(-10,-10),stations[cell],HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("35533f"))
		for site in World.MINES.NODES:
			var at:=origin+(Vector2(site)+Vector2(0.5,0.5))*SCALE
			draw_texture_rect(Shell.icon("pick"),Rect2(at-Vector2(9,9),Vector2(18,18)),false)
	else:
		var exit:=Vector2(World.REGIONS.exit_cell(region))+Vector2(0.5,0.5)
		var point:=origin+exit*SCALE
		draw_texture_rect(Shell.icon("map"),Rect2(point-Vector2(12,30),Vector2(24,24)),false)
		var gate:=World.TRANSIT.point_at(region,Vector2i(exit))
		var caption:String=World.TRANSIT.points(region)[gate].label if not gate.is_empty() else "回風鈴渡口"
		draw_string(font,point+Vector2(12,4),caption,HORIZONTAL_ALIGNMENT_LEFT,-1,15,Color("35533f"))
		draw_string(font,origin+Vector2(12,26),"走到路口，按互動鍵開啟旅圖",HORIZONTAL_ALIGNMENT_LEFT,530,15,Color("35533f"))
		var area_title:String={"home":"澎湖・望安・風鈴渡口","lanyang":"宜蘭・蘭陽試作田／水圳與木橋","jinguashi":"新北・金瓜石／第一層淺礦場","beimen":"臺南・北門鹽田／東岸釣點","jiaoxi":"宜蘭・礁溪暖泉高地"}.get(region,"")
		draw_string(font,origin+Vector2(12,47),area_title,HORIZONTAL_ALIGNMENT_LEFT,530,13,Color("35533f"))
	if region=="jinguashi":
		for site in World.JINGUASHI.NODES:
			var at:=origin+(Vector2(site)+Vector2(0.5,0.5))*SCALE
			draw_texture_rect(Shell.icon("pick"),Rect2(at-Vector2(9,9),Vector2(18,18)),false)
	if region=="lanyang":
		var water_at:=origin+Vector2(33.5,26.5)*SCALE
		draw_texture_rect(Items.icon("loach"),Rect2(water_at-Vector2(12,12),Vector2(24,24)),false)
		draw_string(font,water_at+Vector2(15,5),"水圳釣點",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("244847"))
		var task:Dictionary=World.LANYANG_LIFE.next_step(data)
		for blockage in World.LANYANG_LIFE.BLOCKAGES:
			if data.get("lanyang_life",{}).get("cleared",{}).has(World.key(blockage)):continue
			var at:=origin+(Vector2(blockage)+Vector2(0.5,0.5))*SCALE
			draw_texture_rect(Shell.icon("seed"),Rect2(at-Vector2(10,10),Vector2(20,20)),false)
		var service:=origin+(Vector2(World.LANYANG_LIFE.SERVICE)+Vector2(0.5,0.5))*SCALE
		if data.get("lanyang_life",{}).get("repaired",false):
			var seen:Array=data.get("history_memory",{}).get("own_memory",{}).get("seen",[])
			for site in World.HISTORY_MEMORY.OBSERVATIONS:
				if World.key(site) not in seen:
					var at:=origin+(Vector2(site)+Vector2(0.5,0.5))*SCALE
					draw_texture_rect(Shell.icon("journal"),Rect2(at-Vector2(10,10),Vector2(20,20)),false)
		mark(service,Color("e0b558"),false)
		draw_string(font,service+Vector2(12,16),"星禾・育苗",HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("35533f"))
		draw_string(font,origin+Vector2(12,378),str(task.get("action","沿水圳找星禾")),HORIZONTAL_ALIGNMENT_LEFT,530,14,Color("35533f"))
	var minute:=fposmod(float(data.get("time",0.0)),World.WEATHER.DAY_SECONDS)
	var clue:=World.Collections.fishing_forecast(region,viewer,minute)
	if clue.is_empty():clue=World.Collections.water_clues(region,viewer)
	if not clue.is_empty():
		draw_string(font,origin+Vector2(12,355),clue,HORIZONTAL_ALIGNMENT_LEFT,530,14,Color("244847"))
	if show_resources:
		draw_string(font,origin+Vector2(12,334),"採集標記 · 深綠 林木　藍灰 石材　金棕 纖維",HORIZONTAL_ALIGNMENT_LEFT,530,14,Color("244847"))
	draw_string(font,origin+Vector2(12,400),"紅點是你 · 藍點是朋友 · 棕色是農田與建物",HORIZONTAL_ALIGNMENT_LEFT,530,14,Color("35533f"))
func draw_transit_map(origin:Vector2,region:String)->void:
	var plaza:Rect2i=World.TRANSIT.PLAZA
	var scale_value:=15.0
	var base:=origin+Vector2(47,76)-Vector2(plaza.position)*scale_value
	draw_rect(Rect2(origin,Vector2(560,420)),Color("a5beb6"))
	draw_rect(Rect2(base+Vector2(plaza.position)*scale_value,Vector2(plaza.size)*scale_value),Color("dfc9a0"))
	for footprint:Rect2i in World.TRANSIT.BUILDINGS[region]:
		draw_rect(Rect2(base+Vector2(footprint.position)*scale_value,Vector2(footprint.size)*scale_value),Color("997960"))
	if World.TRANSIT.VEHICLES.has(region):
		var footprint:Rect2i=World.TRANSIT.VEHICLES[region]
		draw_rect(Rect2(base+Vector2(footprint.position)*scale_value,Vector2(footprint.size)*scale_value),Color("64867b"))
	draw_string(font,origin+Vector2(18,29),TransitArt.NAMES[region],HORIZONTAL_ALIGNMENT_LEFT,-1,19,Color("314e40"))
	for gate in World.TRANSIT.points(region):
		var point:Dictionary=World.TRANSIT.points(region)[gate]
		var at:=base+(Vector2(point.cell)+Vector2(0.5,0.5))*scale_value
		# 回渡口的「交通船・轉乘」沒有船隻圖，用中性的站房圖示，不畫成公車。
		var kind:String={"火車":"train","公車":"bus","接駁":"bus"}.get(point.mode,"station")
		var sprite:=TransitArt.icon(kind)
		if sprite:draw_texture_rect(sprite,Rect2(at-Vector2(20,36),Vector2(40,30)),false)
		mark(at,Color("f9de88"),false)
		draw_string(font,at+Vector2(-37,21),point.label,HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("314e40"))
	for id in data.players:
		var person:Dictionary=data.players[id]
		mark(base+Vector2(person.x,person.y)*scale_value,Color("c96755") if id==own_id else Color("537ea4"),true)
	var sign_info:=return_sign(region,int(data.players.get(own_id,{}).get("exploration_points",0)))
	if not sign_info.is_empty():
		draw_return_sign(origin,base+(Vector2(sign_info.cell)+Vector2(0.5,0.5))*scale_value,sign_info.hint)
	draw_string(font,origin+Vector2(18,381),"依站牌轉乘 · 棕色建物 · 綠色停靠區",HORIZONTAL_ALIGNMENT_LEFT,-1,15,Color("314e40"))
	draw_string(font,origin+Vector2(18,403),"紅點是你 · 藍點是朋友",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("314e40"))

func mark(at:Vector2,color:Color,person:bool) -> void:
	if person:
		draw_circle(at,5,Color("fff7e4"))
		draw_circle(at,3,color)
	else:
		draw_rect(Rect2(at-Vector2(5,5),Vector2(10,10)),Color("fff7e4"))
		draw_rect(Rect2(at-Vector2(3,3),Vector2(6,6)),color)

func mine_map_point(origin:Vector2,cell:Vector2) -> Vector2:
	return origin+Vector2(63,86)+(cell-Vector2(9,16))*14.0

func draw_mine_map(origin:Vector2,region:String) -> void:
	var depth:=int(region.trim_prefix("mine_"))
	draw_rect(Rect2(origin,Vector2(560,420)),Color("e8d9b5"))
	draw_string(font,origin+Vector2(24,32),"金瓜石合作礦場・地下第 %d 層礦道圖"%depth,HORIZONTAL_ALIGNMENT_LEFT,510,19,Color("4b4539"))
	draw_string(font,origin+Vector2(24,56),"往左回上一層，往右到礦務站整備。",HORIZONTAL_ALIGNMENT_LEFT,510,14,Color("635944"))
	draw_rect(Rect2(origin+Vector2(55,78),Vector2(450,198)),Color("494548"))
	for y in range(16,29):
		for x in range(9,40):
			var cell:=Vector2i(x,y)
			var at:=mine_map_point(origin,Vector2(cell))
			var tint:=Color("b5a18a")
			if depth==3 and World.MINES.POOL.has_point(cell):tint=Color("588e9a")
			draw_rect(Rect2(at,Vector2(14,14)),tint)
			if data.get("objects",{}).has(World.key(cell)):draw_rect(Rect2(at+Vector2(4,4),Vector2(6,6)),Color("75543e"))
	for node in World.MINES.NODES:
		var at:=mine_map_point(origin,Vector2(node)+Vector2(0.5,0.5))
		draw_texture_rect(Shell.icon("pick"),Rect2(at-Vector2(10,10),Vector2(20,20)),false)
	var stations:=[World.MINES.UP,World.MINES.REST,World.MINES.SERVICE]
	var labels:=["返回山城" if depth==1 else "回到第 %d 層"%(depth-1),"休息補水","礦務工程"]
	if depth<World.MINES.MAX_DEPTH:
		stations.append(World.MINES.DOWN)
		labels.append("前往第 %d 層"%(depth+1))
	if depth>World.MINES.SHALLOW_DEPTH:
		stations.append(World.MINES.LIFT)
		labels.append("升降台回山城")
	for index in range(stations.size()):
		var at:=mine_map_point(origin,Vector2(stations[index])+Vector2(0.5,0.5))
		draw_circle(at,10,Color("614c37"))
		draw_string(font,at+Vector2(-4,5),str(index+1),HORIZONTAL_ALIGNMENT_LEFT,20,14,Color("fff0cb"))
		var legend:=origin+Vector2(35+(index%2)*270,305+(index/2)*30)
		draw_string(font,legend,"%d  %s"%[index+1,labels[index]],HORIZONTAL_ALIGNMENT_LEFT,240,15,Color("4b4539"))
	for id in data.players:
		var person:Dictionary=data.players[id]
		mark(mine_map_point(origin,Vector2(person.x,person.y)),Color("c96755") if id==own_id else Color("537ea4"),true)
	var sign_info:=return_sign(region,int(data.players.get(own_id,{}).get("exploration_points",0)))
	if not sign_info.is_empty():
		draw_return_sign(origin,mine_map_point(origin,Vector2(sign_info.cell)+Vector2(0.5,0.5)),sign_info.hint)
	draw_string(font,origin+Vector2(24,383),"紅點是你 · 藍點是朋友 · 鎬頭是礦料點",HORIZONTAL_ALIGNMENT_LEFT,510,14,Color("635944"))
