extends Control
const World=preload("res://scripts/world.gd")
const Shell=preload("res://scripts/life_ui_shell.gd")
const Items=preload("res://scripts/inventory_item_art.gd")
const TransitArt=preload("res://scripts/transit_art.gd")
const Opening=preload("res://scripts/wangan_opening.gd")
const CanalArt=preload("res://scripts/lanyang_life_art.gd")
const Revisit=World.LANYANG_REVISIT
const OreRoute=World.ORE_ROUTE
const BoboCart=World.BOBO_EMPTY_CART
const CartArt=preload("res://scripts/ore_route_art.gd")
const PanArt=preload("res://scripts/gold_panning_art.gd")
const Salt=World.SALT_PAN
const SaltRevisitUI=preload("res://scripts/salt_revisit_ui.gd")
const Tea=World.TEA_CERAMICS
const TeaGuide=preload("res://scripts/tea_guidance.gd")
const TeaArt=preload("res://scripts/tea_ceramics_art.gd")
const TeaRevisitUI=preload("res://scripts/tea_revisit_ui.gd")
const FlowerGuide=preload("res://scripts/flower_nursery_ui.gd")
const Flower=World.FLOWER_NURSERY
const Springs=World.WARM_SPRINGS
const Bamboo=World.REGIONS.Bamboo
const StarGarden=World.REGIONS.StarGarden
const Memory=World.WANGAN_MEMORY
const Coast=World.WANGAN_COAST
const MineLayout := preload("res://scripts/mine_layout.gd")
const SCALE:=7.0
const TRANSIT_WALKWAY_COLOR:=Color("ead29a")
const RETURN_SIGN_LEVEL:=3
const WANGAN_STOPS:=[
	[Vector2i(Coast.FERRY_LANDING),"靠岸碼頭"],
	[Memory.SITE,"花宅觀察牌"],
	[Memory.WEIR_SITE,"石滬觀察牌"],
	[Memory.WEIR_LOOKOUT,"南岸觀潮・海釣"],
	[Coast.SHELL_CELL,"退潮撿貝殼"],
	[World.SEAWEED_CELL,"採集海苔"],
]

static func return_sign(region:String,points:int) -> Dictionary:
	if region==World.REGIONS.HOME or region not in World.REGIONS.ALL or World.exploration_level(points)<RETURN_SIGN_LEVEL:return {}
	if region in World.MINES.IDS:
		return {"cell":World.MINES.UP,"hint":"返家路標 · 先走上階，離開礦場後再轉乘回渡口。"}
	var cell:=World.REGIONS.exit_cell(region)
	if region=="toucheng":cell=World.TRANSIT.POINTS.toucheng.street.cell
	if region=="ruifang":cell=World.TRANSIT.POINTS.ruifang.rail.cell
	if region=="jiufen":cell=World.TRANSIT.POINTS.jiufen.bus.cell
	return {"cell":cell,"hint":"返家路標 · 前往標記處，開啟旅圖並選擇風鈴渡口。"}

static func public_kitchen_marker(snapshot:Dictionary)->Vector2i:
	var kitchen:=World.PUBLIC_KITCHEN
	if kitchen.stage(snapshot)!="open":return kitchen.NO_CELL
	return kitchen.parse_cell(str(snapshot.get("public_kitchen",{}).get("stove","")))

## 家園來信優先指出目前玩家的第一株作物步驟。
static func letter_target(s:Dictionary,owner:String) -> Dictionary:
	var personal:=World.CHAPTER_ONE.first_crop_step(s,owner)
	var cell:Vector2i=personal.get("cell",World.CHAPTER_ONE.NO_PLOT_CELL)
	if cell!=World.CHAPTER_ONE.NO_PLOT_CELL:
		var in_plot:=Opening.plot_rect().has_point(cell)
		var hint:=str(personal.text)
		if in_plot and not hint.contains(Opening.PLOT_TAG):hint+=" · "+Opening.PLOT_TAG
		return {"at":Vector2(cell)+Vector2(0.5,0.5),"text":"第一件事："+hint,"plot":in_plot,"personal":true}
	var step:Dictionary=World.CHAPTER_ONE.next_step(s)
	var at:=Vector2(step.cell)+Vector2(0.5,0.5)
	if step.id=="ship":
		var shipping:Vector2i=World.SHIPPING.cell_for(s)
		if shipping!=World.SHIPPING.NO_CELL:at=Vector2(shipping)+Vector2(0.5,0.5)
	return {"at":at,"text":"來信標記："+str(step.action),"plot":false,"personal":false}

static func flower_landmarks(snapshot:Dictionary,owner:String) -> Array[Dictionary]:
	var next:=FlowerGuide.next_step(snapshot,owner)
	var destination:String=next.get("site","") if next.get("region","")==Flower.REGION else ""
	var markers:Array[Dictionary]=[]
	for entry in [["travel","接駁站",Flower.TRANSFER],["farmer","花農阿蕾",Flower.FARMER],
		["beds","育苗床",Flower.NURSERY_BEDS.get_center()],["seed","留種台",Flower.SEED_TABLE],
		["dye","染色桌",Flower.DYE_TABLE],["market","合作市集",Flower.MARKET],
		["garden","公共花園",Flower.GARDEN_CELL],["xinghe","花架旁的星禾",Flower.XINGHE]]:
		markers.append({"site":entry[0],"label":entry[1],"cell":entry[2],"active":entry[0]==destination})
	return markers

func draw_flower_landmarks(origin:Vector2) -> void:
	var markers:=flower_landmarks(data,own_id)
	for index in markers.size():
		var marker:Dictionary=markers[index]
		var at:=origin+(Vector2(marker.cell)+Vector2(0.5,0.5))*SCALE
		var number:=str(index+1)
		var tint:=Color("ac522f") if marker.active else Color("375846")
		draw_circle(at,7.0,tint)
		draw_string(font,at+Vector2(-4,4),number,HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("fff4d7"))
		var row:=origin+Vector2(318,90+index*26)
		draw_string(font,row,"%s  %s%s"%[number,marker.label," · 下一步" if marker.active else ""],
			HORIZONTAL_ALIGNMENT_LEFT,232,15,tint)

static func reserve_landmark(region:String)->Dictionary:
	if region==Bamboo.REGION:
		return {"cell":Bamboo.TEA_BEDS.get_center(),"label":"霧竹茶苗床","item":"mist_tea"}
	if region==StarGarden.REGION:
		return {"cell":World.RESIDENT_BOND.GARDEN_CELL,"label":"點點","item":""}
	return {}

static func canal_revisit(snapshot:Dictionary) -> Dictionary:
	if not Revisit.unlocked(snapshot) or not Revisit.player_ready(snapshot):return {}
	var done:=Revisit.completed(snapshot)
	var revisit_gate:=not Revisit.gates_today(snapshot) or Revisit.shares(snapshot)!=Revisit.demand(snapshot)
	var note:="沿水圳巡看三塊田"
	var active:="gate" if revisit_gate else "fields"
	if done:
		active="" if Revisit.claimed_own(snapshot) else "claim"
		note="分流完成・已領取分水木牌" if active.is_empty() else "分流完成・到木橋找星禾領取分水木牌"
	elif Revisit.waiting_for_return(snapshot):
		active=""
		note="第一次練習已完成・明天起找個沒下雨的日子再來"
	elif Revisit.raining(snapshot):
		active=""
		note="今天有雨・等水圳附近放晴再來"
	elif revisit_gate:
		var demand:=Revisit.demand(snapshot)
		note="到岔口配水・上游 %d／中段 %d／田尾 %d 份"%[demand[0],demand[1],demand[2]]
	else:
		note+="・%d／3"%Revisit.checked_today(snapshot).size()
	var markers:=[{"cell":Revisit.GATE_CELL,"label":"岔口分流閘","state":"next" if active=="gate" else "idle"}]
	for row:Dictionary in Revisit.fields(snapshot):
		var state:="checked" if row.checked else ("next" if active=="fields" else "idle")
		var title:=str(row.name)+("・已巡" if row.checked else "")
		if row.id=="middle" and active=="claim":
			state="next"
			title="木橋・領木牌"
		markers.append({"cell":row.cell,"label":title,"state":state})
	return {"markers":markers,"note":note}

static func mine_route(snapshot:Dictionary) -> Dictionary:
	var stage:=OreRoute.stage(snapshot)
	var delivered:=OreRoute.count_today(snapshot)
	# T066 波波的「最後一趟空車」：只有本人正在推的時候，地圖上的台車才換成劇情空車（不是礦料、不計工資）。
	var story:int=BoboCart.stage(snapshot)
	if BoboCart.active(snapshot):
		return {"cell":BoboCart.cart_cell(snapshot),"loaded":false,"delivered":delivered,"story":true,
			"note":"波波的空車・已推 %d／%d 段"%[story-1,OreRoute.PUSHES],"arrived":false}
	var arrived:=story==OreRoute.LAST
	var note:="先到坑口裝礦"
	if stage==OreRoute.LAST:note="台車已到站，請卸礦"
	elif stage>0:note="沿軌道推車・%d／%d 段"%[stage-1,OreRoute.PUSHES]
	elif delivered>=OreRoute.DAILY:note="今天已送完，明天再來"
	return {"cell":OreRoute.cart_cell(stage),"loaded":stage>0,"delivered":delivered,"note":note,"story":false,"arrived":arrived}

static func salt_landmarks(snapshot:Dictionary,owner:String="") -> Dictionary:
	var own:Dictionary=snapshot.get("salt_pan",{}).get("own",{})
	var guide:Dictionary=own.get("guidance",{})
	var hand_pan:=Salt.pan_rect(Salt.PUBLIC_LOT*2)
	var names:={
		Salt.PUBLIC_SIGN:"保留手作池",
		Salt.HERITAGE_SIGN:"瓦盤鹽田觀景區",
		Salt.SALT_WORKER:"阿曬・合作社",
		Salt.TRANSFER:"海邊公車站"
	}
	if World.SALT_BRINE.unlocked(snapshot):
		names[Salt.BRINE_TANK]="儲滷槽"
		names[Salt.APPRENTICE_CHEST]="合作社收鹽箱"
	var lot:=int(own.get("lot",-1))
	var plot:=Rect2i()
	if lot>=0 and lot<Salt.LOT_COUNT:
		plot=Salt.pan_rect(lot*2).merge(Salt.pan_rect(lot*2+1))
	var target:Vector2i=guide.get("cell",Vector2i(-1,-1)) if guide.get("region")==Salt.REGION else Vector2i(-1,-1)
	var note:=str(guide.get("text",""))
	var order:=SaltRevisitUI.navigation(snapshot,owner)
	if not order.is_empty():
		target=order.cell
		note="鹽籃批次・"+str(order.action)
	return {"names":names,"target":target,"manual":hand_pan.merge(Salt.pan_rect(Salt.PUBLIC_LOT*2+1)),"plot":plot,"note":note}

static func tea_map_guide(snapshot:Dictionary,owner:String) -> Dictionary:
	var region:=str(snapshot.get("region_id",""))
	if region not in World.TRANSIT.TEA_STOPS:return {}
	var order:=TeaRevisitUI.navigation(snapshot,owner)
	if not order.is_empty():
		var destination:String=order.region
		return {"target":order.cell if destination==region else World.TRANSIT.STATIONS[region].cell,
			"title":order.action,"destination":str(TeaGuide.PLACES[destination]),"travelling":destination!=region}
	var step:=TeaGuide.next_step(snapshot,owner)
	if step.is_empty():return {}
	var destination:String=step.region
	return {"target":step.cell if destination==region else World.TRANSIT.STATIONS[region].cell,
		"title":step.title,"destination":str(TeaGuide.PLACES[destination]),"travelling":destination!=region}

func draw_return_sign(origin:Vector2,at:Vector2,hint:String,hint_y:=67.0) -> void:
	draw_texture_rect(Shell.icon("home"),Rect2(at+Vector2(-11,-34),Vector2(22,22)),false)
	draw_string(font,origin+Vector2(12,hint_y),hint,HORIZONTAL_ALIGNMENT_LEFT,530,14,Color("244847"))
var data:Dictionary={}
const SignalLabels=preload("res://scripts/session.gd").MAP_SIGNALS
const SIGNAL_COLORS:={"wood":Color("895633"),"meet":Color("3d6778"),"build":Color("735078")}
var own_id:=""
var font:FontVariation
signal oar_target_selected(cell:Vector2i)
var oar_focus:=World.OAR_SIGN.NO_CELL
var oar_candidate:=World.OAR_SIGN.NO_CELL
var oar_world:World
var oar_base:=Vector2.ZERO
var oar_scale:=0.0
var oar_cells:=Rect2i()
var reduced_motion:=false
var oar_pin_tween:Tween
var oar_pin_pulse:=0.0
var home_route:=""
var home_route_cells:Array[Vector2i]=[]
var home_route_stamp:Array=[]
signal home_route_hint(message:String)
func _ready() -> void:
	custom_minimum_size=Vector2(560,420)
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	font=preload("res://scripts/island_type.gd").regular()
func update_world(snapshot:Dictionary,id:String) -> void:
	data=snapshot
	own_id=id
	if oar_world!=null:
		oar_world.state=snapshot
		oar_world._region=str(snapshot.get("region_id","home"))
	refresh_home_route()
	queue_redraw()

func select_home_route(destination:String)->void:
	home_route="" if home_route==destination else destination
	home_route_stamp.clear()
	refresh_home_route()
	queue_redraw()

func refresh_home_route()->void:
	if home_route.is_empty() or data.get("region_id","home")!="home":
		home_route_cells.clear()
		home_route_hint.emit("選一個地點，看看可以怎麼走。")
		return
	var viewer:Dictionary=data.get("players",{}).get(own_id,{})
	if viewer.is_empty():return
	var start:=Vector2i(Vector2(viewer.x,viewer.y).floor())
	var bridge:=World.STONE_WORKSHOP.bridge_open(data)
	var mill_visible:bool=data.get(World.MILL_RESTORATION.SITE_VISIBLE,false)
	var loan_cell:=World.PUBLIC_TILLER.loan_cell(data) if home_route=="tiller" else World.PUBLIC_TILLER.NO_SITE
	var signature:=[start,own_id,bridge,mill_visible,loan_cell,hash(data.get("objects",{})),hash(data.get("edges",{})),
		hash(data.get("ground",{})),hash(data.get("forest",{})),hash(data.get("removed",{}))]
	if signature==home_route_stamp:return
	home_route_stamp=signature
	var goals:Array[Vector2i]=[]
	var summary:="西北資源林"
	if home_route=="forest":
		var area:=World.WOODLAND.GROVE
		for y in range(area.position.y,area.end.y):goals.append(Vector2i(area.end.x-1,y))
		if area.has_point(start):goals.append(start)
	elif home_route=="mill":
		summary="渡口磨坊" if mill_visible else "公告板・磨坊代辦"
		goals.append(World.MILL_RESTORATION.APPROACH if mill_visible else World.MILL_RESTORATION.BOARD+Vector2i.DOWN)
	elif home_route=="tiller":
		summary="公告板借用處" if loan_cell==World.PUBLIC_TILLER.DESK else "渡口農機架"
		if loan_cell!=World.PUBLIC_TILLER.NO_SITE:
			for offset:Vector2i in [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]:goals.append(loan_cell+offset)
	else:
		summary="河灣橋・東岸" if bridge else "河灣橋・西岸"
		for y in range(29,32):goals.append(Vector2i(57 if bridge else 54,y))
	var local:=World.new()
	local.state=data
	home_route_cells=local.walk_route(own_id,start,goals,Rect2i(Vector2i.ZERO,World.SIZE))
	if not home_route_cells.is_empty():home_route_cells.push_front(start)
	var guidance:="已到%s"%summary if start in goals else ("%s · 步行 %d 格"%[summary,home_route_cells.size()-1] if not home_route_cells.is_empty() else "目前沒有通往%s的路。"%summary)
	if home_route=="river" and not bridge:guidance+=" · 修好橋後可往東岸"
	home_route_hint.emit(guidance)

func draw_home_route(origin:Vector2)->void:
	if home_route_cells.size()<2:return
	var points:=PackedVector2Array()
	for cell:Vector2i in home_route_cells:points.append(origin+(Vector2(cell)+Vector2(0.5,0.5))*SCALE)
	draw_polyline(points,Color("365352"),5.0)
	draw_polyline(points,Color("edc85f"),2.0)
	draw_circle(points[-1],5.0,Color("365352"))
	draw_circle(points[-1],3.0,Color("ffe6a2"))

func configure_oar(site:Vector2i,editable:bool)->void:
	oar_focus=site
	if editable:
		oar_world=World.new()
		update_world(data,own_id)
		mouse_filter=Control.MOUSE_FILTER_STOP
		focus_mode=Control.FOCUS_ALL
	queue_redraw()

func _gui_input(event:InputEvent)->void:
	if oar_world==null or oar_scale<=0.0:return
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed:
		var cell:=Vector2i(((event.position-oar_base)/oar_scale).floor())
		if try_oar_cell(cell):grab_focus()
		accept_event()
		return
	if not event.is_pressed():return
	var step:=Vector2i.ZERO
	if event.is_action_pressed("ui_left"):step=Vector2i.LEFT
	elif event.is_action_pressed("ui_right"):step=Vector2i.RIGHT
	elif event.is_action_pressed("ui_up"):step=Vector2i.UP
	elif event.is_action_pressed("ui_down"):step=Vector2i.DOWN
	if step==Vector2i.ZERO:return
	var saved:Dictionary=data.get("objects",{}).get(World.key(oar_focus),{})
	var cell:=oar_candidate if oar_candidate!=World.OAR_SIGN.NO_CELL else World.OAR_SIGN.cell(saved.get(World.OAR_SIGN.FIELD))
	if not oar_cells.has_point(cell):cell=oar_focus
	while true:
		cell+=step
		if not oar_cells.has_point(cell) or try_oar_cell(cell):break
	accept_event()

func try_oar_cell(cell:Vector2i)->bool:
	if oar_world==null or not oar_cells.has_point(cell) or not oar_world.is_land(cell) or oar_world.water(cell):return false
	if cell!=oar_candidate and reduced_motion:
		if oar_pin_tween:oar_pin_tween.kill()
		set_oar_pin_pulse(0.0)
	elif cell!=oar_candidate:
		if oar_pin_tween:oar_pin_tween.kill()
		set_oar_pin_pulse(1.0)
		oar_pin_tween=create_tween()
		oar_pin_tween.tween_method(set_oar_pin_pulse,1.0,0.0,0.32)
	oar_candidate=cell
	oar_target_selected.emit(cell)
	queue_redraw()
	return true

func set_oar_pin_pulse(value:float)->void:
	oar_pin_pulse=value
	queue_redraw()

func _draw() -> void:
	if data.is_empty() or font==null:return
	var region:=str(data.get("region_id","home"))
	var local_world:=World.new()
	local_world.state=data
	local_world._region=region
	var viewer:Dictionary=data.players.get(own_id,{})
	var show_resources:=World.gathering_level(viewer)>=World.RESOURCE_MAP_LEVEL
	var has_walkway:=World.REGIONS.TRANSIT_WALKWAYS.has(region)
	var origin:=Vector2((size.x-560)/2,0)
	if region.begins_with("mine_"):
		draw_mine_map(origin,region)
		return
	if TransitArt.NAMES.has(region):
		draw_transit_map(origin,region)
		return
	if region in World.TRANSIT.TEA_STOPS:
		draw_tea_map(origin,region)
		return
	if region==Springs.REGION:
		draw_springs_map(origin,viewer)
		return
	draw_rect(Rect2(origin,Vector2(560,420)),Color("92c6be"))
	for y in range(World.SIZE.y):
		for x in range(World.SIZE.x):
			var p:=Vector2i(x,y)
			var k:=World.key(p)
			var at:=origin+Vector2(p)*SCALE
			var water:=not Flower.land(p) if region==Flower.REGION else local_world.water(p)
			if water:
				if (region==Bamboo.REGION and Bamboo.water(p)) or (region==StarGarden.REGION and StarGarden.POOL.has_point(p)):
					draw_rect(Rect2(at,Vector2.ONE*SCALE),Color("619d9f") if region==Bamboo.REGION else Color("7d88ad"))
				if region=="home" and Coast.FISHING_WATER.has_point(p):
					draw_rect(Rect2(at,Vector2.ONE*SCALE),Color("619d9f"))
				if region=="home" and Coast.STAR_POOL.has_point(p):
					draw_rect(Rect2(at,Vector2.ONE*SCALE),Color("487e81"))
				continue
			var tint:=Color("b8a596") if region=="jinguashi" else Color("bad298")
			if data.crops.has(k):tint=Color("9e7b55")
			elif data.ground.has(k):tint=Color("d5b27e")
			elif has_walkway and World.REGIONS.transit_walkway(p,region):tint=TRANSIT_WALKWAY_COLOR
			elif region==Flower.REGION:
				if Flower.NURSERY_BEDS.has_point(p):tint=Color("d6ac7b")
				elif Flower.SHED.has_point(p):tint=Color("a48468")
				elif Flower.GARDEN.has_point(p):tint=Color("8eb277")
			elif region==Bamboo.REGION:
				if Bamboo.TEA_BEDS.has_point(p):tint=Color("af8c62")
				elif y in [25,26] and x<23:tint=Color("ded2a2")
			elif region==StarGarden.REGION:
				tint=Color("ded2ba") if y in [25,26] else Color("b9b0c8")
			elif region=="home":
				if Coast.boardwalk(p) or Coast.ferry_walk(p) or (data.get("wangan_star_walk",false) and Coast.star_boardwalk(p)):tint=Color("bc8d60")
				elif Coast.shore_cell(p) or Coast.star_shore(p):tint=Color("e3ca96")
				elif World.VILLAGE_LAYOUT.path_at(Vector2(p)+Vector2(0.5,0.5)):tint=Color("ded2a2")
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
		if region==Salt.REGION:
			draw_string(font,origin+Vector2(12,67),sign_info.hint,HORIZONTAL_ALIGNMENT_LEFT,530,14,Color("244847"))
		else:
			draw_return_sign(origin,origin+(Vector2(sign_info.cell)+Vector2(0.5,0.5))*SCALE,sign_info.hint)
	# Landmarks are separate from player markers so nobody's location is hidden.
	if region=="home":
		draw_home_route(origin)
		if home_route=="tiller":
			var loan_cell:=World.PUBLIC_TILLER.loan_cell(data)
			if loan_cell!=World.PUBLIC_TILLER.NO_SITE:
				var loan_pin:=origin+(Vector2(loan_cell)+Vector2(0.5,0.5))*SCALE
				draw_circle(loan_pin,6,Color("34554d"))
				draw_circle(loan_pin,4,Color("e9bf60"))
				draw_texture_rect(Items.icon(World.PUBLIC_TILLER.ITEM),Rect2(loan_pin+Vector2(8,0),Vector2(22,22)),false)
		var grove:=World.WOODLAND.GROVE
		var grove_mark:=origin+Vector2(grove.end.x-0.5,grove.get_center().y+0.5)*SCALE
		mark(grove_mark,Color("527e4f"),false)
		draw_string(font,grove_mark+Vector2(9,4),"西北資源林",HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("35533f"))
		if data.has("can_build_public_plot"):
			var plot:=World.PUBLIC_BUILD_PLOT
			var bounds:=Rect2(origin+Vector2(plot.position)*SCALE,Vector2(plot.size)*SCALE)
			var outline:=Color("35533f") if data.can_build_public_plot else Color("9b5440")
			draw_rect(bounds.grow(1.0),Color("fff3d0"),false,3.0)
			draw_rect(bounds,outline,false,1.5)
			draw_string(font,bounds.position+Vector2(-46,-5),"公共施工地",HORIZONTAL_ALIGNMENT_LEFT,-1,13,outline)
		mark(origin+Vector2(40.5,29.5)*SCALE,Color("e0b558"),false)
		draw_string(font,origin+Vector2(36,27)*SCALE,"聚落／種子攤",HORIZONTAL_ALIGNMENT_LEFT,-1,15,Color("35533f"))
		mark(origin+Vector2(45.5,34.5)*SCALE,Color("fff3d0"),false)
		mark(origin+Vector2(54.5,25.5)*SCALE,Color("8b9386"),false)
		draw_string(font,origin+Vector2(49,22)*SCALE,"採石／運入礦料",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("35533f"))
		draw_string(font,origin+Vector2(58,30)*SCALE,"河灣橋",HORIZONTAL_ALIGNMENT_LEFT,-1,15,Color("35533f"))
		if not World.STONE_WORKSHOP.bridge_open(data):draw_string(font,origin+Vector2(58,33)*SCALE,"待修復",HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("617964"))
		draw_wangan_stops(origin)
		draw_fox_finds(origin,viewer)
		if data.get(World.MILL_RESTORATION.SITE_VISIBLE,false):
			var mill_at:=origin+(Vector2(World.MILL_RESTORATION.DOOR)+Vector2(0.5,0.5))*SCALE
			mark(mill_at,Color("9f664b"),false)
			draw_string(font,mill_at+Vector2(7,-10),"渡口磨坊",HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("35533f"))
		var kitchen_tile:=public_kitchen_marker(data)
		if kitchen_tile!=World.PUBLIC_KITCHEN.NO_CELL:
			var kitchen_at:=origin+(Vector2(kitchen_tile)+Vector2(0.5,0.5))*SCALE
			mark(kitchen_at,Color("9f664b"),false)
			draw_texture_rect(Items.icon("soup"),Rect2(kitchen_at+Vector2(7,-10),Vector2(20,20)),false)
			draw_string(font,kitchen_at+Vector2(12,22),"公共廚房",HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("35533f"))
		var star_open:bool=data.get("wangan_star_walk",false)
		var star_cell:=Coast.STAR_SAND if star_open else Coast.STAR_REPAIR
		var star_point:=origin+(Vector2(star_cell)+Vector2(0.5,0.5))*SCALE
		mark(star_point,Color("567c70"),false)
		draw_string(font,star_point+Vector2(-126,-9),"星砂潮池・晶砂" if star_open else "星砂步道待修",HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("244847"))
		if star_open:
			var parcel_point:=origin+(Vector2(Coast.SALT_PARCEL)+Vector2(0.5,0.5))*SCALE
			mark(parcel_point,Color("8f8a6c"),false)
			draw_string(font,parcel_point+Vector2(-126,-9),"北門海鹽包",HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("244847"))
	var fishing_sites:Dictionary={World.SALT_PAN.REGION:World.SALT_PAN.FISHING_SPOTS,World.REGIONS.Springs.REGION:World.REGIONS.Springs.POOLS,World.REGIONS.Bamboo.REGION:World.REGIONS.Bamboo.POOLS,World.REGIONS.StarGarden.REGION:World.REGIONS.StarGarden.POOLS}
	if fishing_sites.has(region):
		var spots:Dictionary=fishing_sites[region]
		for spot in spots.values():
			var at:=origin+Vector2(spot.water.get_center())*SCALE+Vector2.ONE*SCALE*0.5
			mark(at,Color("426f78"),false)
			draw_texture_rect(Items.icon(spot.fish),Rect2(at+Vector2(10,-12),Vector2(24,24)),false)
			draw_string(font,at+Vector2(36,5),spot.label,HORIZONTAL_ALIGNMENT_LEFT,125,15,Color("244847"))
	if region=="jinguashi":draw_jinguashi_route(origin)
	if region==Salt.REGION:draw_salt_landmarks(origin)
	if region==Flower.REGION:draw_flower_landmarks(origin)
	var landmark:=reserve_landmark(region)
	if not landmark.is_empty():
		var at:=origin+(Vector2(landmark.cell)+Vector2(0.5,0.5))*SCALE
		mark(at,Color("806049"),false)
		var texture:Texture2D=Items.icon(landmark.item) if not str(landmark.item).is_empty() else Shell.icon("journal")
		draw_texture_rect(texture,Rect2(at-Vector2(10,24),Vector2(20,20)),false)
		draw_string(font,at+Vector2(-18,-29),landmark.label,HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("35533f"))
	if region==Bamboo.REGION:
		var bamboo_at:=origin+(Vector2(Bamboo.CLUMPS[1])+Vector2(0.5,0.5))*SCALE
		mark(bamboo_at,Color("4f704d"),false)
		draw_texture_rect(Items.icon(Bamboo.ITEM),Rect2(bamboo_at+Vector2(-25,-44),Vector2(22,22)),false)
		draw_string(font,bamboo_at+Vector2(-2,-28),"竹材採集區",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("35533f"))
	for id in data.players:
		var person:Dictionary=data.players[id]
		var at:=origin+Vector2(person.x,person.y)*SCALE
		mark(at,Color("c96755") if id==own_id else Color("537ea4"),true)
		if id==own_id and region not in ["home","lanyang",Salt.REGION] and region not in World.REGIONS.ANGLING_RESERVES:
			draw_string(font,at+Vector2(9,17),"你在這裡",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("8a463e"))
	if region=="home":
		var letter:=letter_target(data,own_id)
		if letter.personal or not data.get("picnic",false):
			var point:=origin+Vector2(letter.at)*SCALE
			if letter.personal:
				draw_circle(point,7.0,Color("986742"),false,2.0)
				draw_circle(point,5.0,Color("fff0ad"),false,2.0)
			draw_texture_rect(Shell.icon("letter"),Rect2(point-Vector2(12,38 if letter.plot else 30),Vector2(24,24)),false)
			draw_string(font,origin+Vector2(12,26),str(letter.text),HORIZONTAL_ALIGNMENT_LEFT,530,15,Color("35533f"))
		draw_string(font,origin+Vector2(12,47),"澎湖・望安 · 風鈴渡口",HORIZONTAL_ALIGNMENT_LEFT,270,15,Color("35533f"))
		draw_string(font,origin+Vector2(285,47),"潭門港與網垵口地景縮編",HORIZONTAL_ALIGNMENT_RIGHT,255,14,Color("5d543b"))
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
		if region not in [Salt.REGION,Flower.REGION]:
			draw_texture_rect(Shell.icon("map"),Rect2(point-Vector2(12,30),Vector2(24,24)),false)
		var gate:=World.TRANSIT.point_at(region,Vector2i(exit))
		var caption:String=World.TRANSIT.points(region)[gate].label if not gate.is_empty() else "回風鈴渡口"
		if region==Bamboo.REGION:caption="往貓空"
		if region==StarGarden.REGION:caption="往田尾"
		var caption_offset:=Vector2(12,-13) if region=="jinguashi" else Vector2(12,4)
		if region not in [Salt.REGION,Flower.REGION]:
			draw_string(font,point+caption_offset,caption,HORIZONTAL_ALIGNMENT_LEFT,-1,15,Color("35533f"))
		draw_string(font,origin+Vector2(12,26),"走到路口，按互動鍵開啟旅圖",HORIZONTAL_ALIGNMENT_LEFT,530,15,Color("35533f"))
		var area_title:String={"home":"澎湖・望安・風鈴渡口","lanyang":"宜蘭・蘭陽試作田／水圳與木橋","jinguashi":"新北・金瓜石山城／坑口與運礦軌道","beimen":"臺南・北門鹽田／東岸釣點","tianwei":"彰化・田尾合作花圃","bamboo_grove":"臺北・貓空霧竹溪谷","star_garden":"彰化・星芽庭園"}.get(region,"")
		draw_string(font,origin+Vector2(12,47),area_title,HORIZONTAL_ALIGNMENT_LEFT,530,13,Color("35533f"))
	if region=="lanyang":
		var water_at:=origin+Vector2(33.5,26.5)*SCALE
		draw_texture_rect(Items.icon("loach"),Rect2(water_at-Vector2(12,12),Vector2(24,24)),false)
		draw_string(font,water_at+Vector2(15,5),"水圳釣點",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("244847"))
		var task:Dictionary=World.LANYANG_LIFE.next_step(data)
		var cleared:Dictionary=data.get("lanyang_life",{}).get("cleared",{})
		for index in World.LANYANG_LIFE.BLOCKAGES.size():
			var blockage:Vector2i=World.LANYANG_LIFE.BLOCKAGES[index]
			if cleared.has(World.key(blockage)):continue
			var at:=origin+(Vector2(blockage)+Vector2(0.5,0.5))*SCALE
			draw_texture_rect_region(CanalArt.SOURCE,Rect2(at-Vector2(9,9),Vector2(18,18)),CanalArt.BLOCKAGE)
			draw_circle(at+Vector2(-12,0),7,Color("eedcb4"))
			draw_string(font,at+Vector2(-15,4),str(index+1),HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("35533f"))
		var service:=origin+(Vector2(World.LANYANG_LIFE.SERVICE)+Vector2(0.5,0.5))*SCALE
		if data.get("lanyang_life",{}).get("repaired",false):
			var seen:Array=data.get("history_memory",{}).get("own_memory",{}).get("seen",[])
			for site in World.HISTORY_MEMORY.OBSERVATIONS:
				if World.key(site) not in seen:
					var at:=origin+(Vector2(site)+Vector2(0.5,0.5))*SCALE
					draw_texture_rect(Shell.icon("journal"),Rect2(at-Vector2(10,10),Vector2(20,20)),false)
		mark(service,Color("e0b558"),false)
		draw_string(font,service+Vector2(12,16),"星禾・育苗",HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("35533f"))
		var progress_text:="水口 %d／3 · ① 北段　② 中段　③ 南段"%cleared.size() if task.id=="clear" else str(task.action)
		var revisit:=canal_revisit(data)
		if not revisit.is_empty():
			draw_canal_revisit(origin,revisit.markers)
			progress_text=revisit.note
		draw_string(font,origin+Vector2(12,378),progress_text,HORIZONTAL_ALIGNMENT_LEFT,530,14,Color("35533f"))
	var minute:=fposmod(float(data.get("time",0.0)),World.WEATHER.DAY_SECONDS)
	var clue:=World.Collections.fishing_forecast(region,viewer,minute)
	if clue.is_empty():clue=World.Collections.water_clues(region,viewer)
	if not clue.is_empty():
		draw_string(font,origin+Vector2(12,355),clue,HORIZONTAL_ALIGNMENT_LEFT,530,14,Color("244847"))
	if show_resources:
		draw_string(font,origin+Vector2(12,334),"採集標記 · 深綠 林木　藍灰 石材　金棕 纖維",HORIZONTAL_ALIGNMENT_LEFT,530,14,Color("244847"))
	draw_string(font,origin+Vector2(12,415),"紅點是你 · 藍點是朋友 · 棕色是農田與建物",HORIZONTAL_ALIGNMENT_LEFT,530,14,Color("35533f"))
	if has_walkway:
		draw_rect(Rect2(origin+Vector2(433,405),Vector2(10,10)),TRANSIT_WALKWAY_COLOR)
		draw_string(font,origin+Vector2(449,415),"公共步道",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("35533f"))
	draw_map_signals(origin,origin,SCALE)

func draw_jinguashi_route(origin:Vector2) -> void:
	const INK:=Color("3d443a")
	const RAIL:=Color("704d33")
	var center:=origin+Vector2.ONE*SCALE*0.5
	var route:=mine_route(data)
	var rail:=PackedVector2Array()
	for cell:Vector2i in OreRoute.TRACK:rail.append(center+Vector2(cell)*SCALE)
	draw_polyline(rail,Color("f0d4a4"),5.0)
	draw_polyline(rail,RAIL,2.0)
	for stop:Vector2i in OreRoute.STOPS:
		draw_circle(center+Vector2(stop)*SCALE,2.5,RAIL)
	var load_site:=center+Vector2(OreRoute.STOPS[0])*SCALE
	var unload_site:=center+Vector2(OreRoute.STOPS[-1])*SCALE
	draw_string(font,load_site+Vector2(9,-5),"坑口裝礦台",HORIZONTAL_ALIGNMENT_LEFT,-1,13,INK)
	draw_string(font,unload_site+Vector2(-19,36),"卸礦台",HORIZONTAL_ALIGNMENT_LEFT,-1,13,INK)
	draw_line(unload_site,unload_site+Vector2(0,22),RAIL)
	var cart_at:=center+Vector2(route.cell)*SCALE
	var cart_icon:=CartArt.cart_texture(route.loaded)
	draw_circle(cart_at,6.5,Color("ffe9ad"))
	draw_circle(cart_at,4.5,Color("92512b"),false,2.0)
	draw_texture_rect(cart_icon,Rect2(cart_at+Vector2(-12,-28),Vector2(24,24)),false)
	if route.arrived:
		# 抵達後短暫標在展覽位置，用不同的點和文字，不當成運礦台車。
		var exhibit_at:=center+Vector2(OreRoute.STOPS[-1])*SCALE
		draw_circle(exhibit_at+Vector2(0,10),4.5,Color("c9dfd0"))
		draw_circle(exhibit_at+Vector2(0,10),3.0,Color("55785c"))
		draw_string(font,exhibit_at+Vector2(-40,25),"波波的空車",HORIZONTAL_ALIGNMENT_LEFT,-1,12,INK)
	var pan_at:=center+Vector2(World.GOLD_PANNING.SITE)*SCALE
	draw_texture_rect(PanArt.pan_texture(5),Rect2(pan_at+Vector2(-10,0),Vector2(20,20)),false)
	draw_string(font,pan_at+Vector2(14,14),"淘砂處",HORIZONTAL_ALIGNMENT_LEFT,-1,13,INK)
	var gallery_at:=center+Vector2(World.PARTY_CART.SURFACE_PORTAL)*SCALE
	var gallery_open:bool=data.get("party_cart_unlocked",false)
	mark(gallery_at,Color("55785c") if gallery_open else Color("9a6646"),false)
	draw_string(font,gallery_at+Vector2(11,-4),"礦車搬運活動" if gallery_open else "礦車維修中",
		HORIZONTAL_ALIGNMENT_LEFT,-1,13,INK)
	for site in World.JINGUASHI.NODES:
		var at:=center+Vector2(site)*SCALE
		draw_circle(at,2.5,Color("556c74"))
	var sidebar:=origin+Vector2(399,86)
	draw_style_box(preload("res://scripts/inventory_pixel_theme.gd").paper_style(),Rect2(sidebar,Vector2(151,112)))
	draw_string(font,sidebar+Vector2(10,25),"運礦路線",HORIZONTAL_ALIGNMENT_LEFT,-1,16,INK)
	draw_string(font,sidebar+Vector2(10,52),route.note,HORIZONTAL_ALIGNMENT_LEFT,-1,13,INK)
	draw_string(font,sidebar+Vector2(10,76),"紀念空車・不計運礦工資" if route.story else "今日交運 %d／%d 車"%[route.delivered,OreRoute.DAILY],HORIZONTAL_ALIGNMENT_LEFT,-1,13,INK)
	draw_string(font,sidebar+Vector2(10,99),"金環 空車・藍灰 礦點" if route.story else "金環 台車・藍灰 礦點",HORIZONTAL_ALIGNMENT_LEFT,-1,12,INK)

func draw_canal_revisit(origin:Vector2,markers:Array) -> void:
	for point:Dictionary in markers:
		var at:=origin+(Vector2(point.cell)+Vector2(0.5,0.5))*SCALE
		var pin:=at-Vector2(14,0)
		var color:Color={"next":Color("985529"),"checked":Color("4e7138")}.get(point.state,Color("315851"))
		draw_line(at,pin,color,1.0)
		draw_circle(pin,5.0,Color("fff0cc"))
		draw_circle(pin,3.5,color)
		var width:=ceilf(font.get_string_size(point.label,HORIZONTAL_ALIGNMENT_LEFT,-1,12).x)
		var text_at:=pin-Vector2(width+9,0)
		draw_rect(Rect2(text_at-Vector2(4,8),Vector2(width+8,16)),Color("f3e8c4"))
		draw_string(font,text_at+Vector2(0,4),point.label,HORIZONTAL_ALIGNMENT_LEFT,-1,12,color)

func draw_salt_landmarks(origin:Vector2) -> void:
	var landmarks:=salt_landmarks(data,own_id)
	var ink:=Color("315652")
	var warm:=Color("f4e6bc")
	var personal:=Color("8d5335")
	var manual:Rect2i=landmarks.manual
	draw_rect(Rect2(origin+Vector2(manual.position)*SCALE,Vector2(manual.size)*SCALE),Color("578883"),false,2.0)
	var scenic:=Salt.HERITAGE_VIEW
	draw_rect(Rect2(origin+Vector2(scenic.position)*SCALE,Vector2(scenic.size)*SCALE),Color("b9a080"),false,2.0)
	var plot:Rect2i=landmarks.plot
	if plot.has_area():
		var corner:=origin+Vector2(plot.position)*SCALE
		draw_rect(Rect2(corner,Vector2(plot.size)*SCALE),personal,false,2.0)
		draw_string(font,corner+Vector2(0,-4),"你的鹽田",HORIZONTAL_ALIGNMENT_LEFT,-1,12,personal)
	for cell:Vector2i in landmarks.names:
		var at:=origin+(Vector2(cell)+Vector2(0.5,0.5))*SCALE
		var title:String=landmarks.names[cell]
		var width:=ceilf(font.get_string_size(title,HORIZONTAL_ALIGNMENT_LEFT,-1,12).x)
		var caption_at:=at+Vector2(7,0)
		if cell==Salt.BRINE_TANK or cell==Salt.APPRENTICE_CHEST:caption_at.x=at.x-width-7
		if cell==Salt.TRANSFER:caption_at.y+=14
		draw_circle(at,4.0,warm)
		draw_circle(at,2.5,ink)
		draw_rect(Rect2(caption_at-Vector2(3,8),Vector2(width+6,16)),warm)
		draw_string(font,caption_at+Vector2(0,4),title,HORIZONTAL_ALIGNMENT_LEFT,-1,12,ink)
	var target:Vector2i=landmarks.target
	if target.x>=0:
		var at:=origin+(Vector2(target)+Vector2(0.5,0.5))*SCALE
		draw_circle(at,7.0,warm,false,3.0)
		draw_circle(at,7.0,personal,false,1.0)
	if not landmarks.note.is_empty():
		draw_string(font,origin+Vector2(12,381),landmarks.note,HORIZONTAL_ALIGNMENT_LEFT,530,14,ink)

func draw_fox_finds(origin:Vector2,viewer:Dictionary)->void:
	var clues:=World.Fox.visible_clues(World,data,viewer)
	for cell:Vector2i in clues:
		var point:=origin+(Vector2(cell)+Vector2(0.5,0.5))*SCALE
		var item:="seaweed" if cell==World.SEAWEED_CELL else World.WANGAN_COAST.SHELL_ITEM
		var offset:=Vector2(16,-11) if item=="seaweed" else Vector2(-120,-10)
		draw_circle(point,10.0,Color("fff3bc"),false,2.0)
		draw_texture_rect(Items.icon(item),Rect2(point+offset,Vector2(19,19)),false)
		draw_string(font,point+offset+Vector2(22,14),clues[cell],HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("244847"))

func draw_wangan_stops(origin:Vector2)->void:
	var panel:=Rect2(origin+Vector2(10,55),Vector2(147,213))
	draw_style_box(preload("res://scripts/inventory_pixel_theme.gd").paper_style(),panel)
	for index in WANGAN_STOPS.size():
		var stop:Array=WANGAN_STOPS[index]
		var at:=origin+(Vector2(stop[0])+Vector2(0.5,0.5))*SCALE
		var row:=panel.position+Vector2(15,17+index*22)
		draw_wangan_number(at,index+1)
		draw_wangan_number(row,index+1)
		draw_string(font,row+Vector2(14,5),stop[1],HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("35533f"))
	draw_string(font,panel.position+Vector2(12,154),"沿淺色小徑下南岸",HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("5d543b"))
	draw_line(panel.position+Vector2(12,165),panel.position+Vector2(135,165),Color("bcac87"))
	var time:=float(data.get("time",0.0))
	var tide_text:="現在・漲潮" if Coast.high_tide(time) else "現在・退潮"
	draw_string(font,panel.position+Vector2(12,184),tide_text,HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("355b56"))
	draw_string(font,panel.position+Vector2(12,201),Coast.next_tide_text(time),HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("5d543b"))
	if data.get("wangan_star_walk",false):
		var dock:=origin+(Vector2(Coast.DOCK_ORDERS)+Vector2(0.5,0.5))*SCALE
		draw_texture_rect(Shell.icon("letter"),Rect2(dock-Vector2(9,9),Vector2(18,18)),false)
		draw_string(font,dock+Vector2(11,27),"碼頭訂單",HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("244847"))

func draw_wangan_number(at:Vector2,index:int)->void:
	draw_circle(at,8,Color("eedcb4"))
	draw_circle(at,6.5,Color("3b6359"))
	draw_string(font,at+Vector2(-3.5,4),str(index),HORIZONTAL_ALIGNMENT_LEFT,-1,11,Color("fff4d7"))

func draw_tea_map(origin:Vector2,region:String) -> void:
	var growing:=region==Tea.MAOKONG
	var ink:=Color("355342")
	var paper:=Color("f4e5c4")
	var scale_value:=13.0
	var base:=origin+Vector2(76,78)-Vector2(8,12)*scale_value
	var center:=base+Vector2.ONE*scale_value*0.5
	draw_rect(Rect2(origin,Vector2(560,420)),Color("94ada0") if growing else Color("a7a59a"))
	for y in range(12,31):
		for x in range(8,38):
			var cell:=Vector2i(x,y)
			if not World.land(cell,region):continue
			var lane:=y in [19,20,21] or (x in [22,23,24] and y in range(21,27))
			var tint:=Color("c2cca2") if growing else Color("c6b09c")
			if lane:tint=Color("dfc9a3")
			elif growing and y in [23,25,27,29] and x in range(24,34):tint=Color("73935c")
			if y==17 and World.REGIONS.tea_blocked(cell,region):
				tint=Color("8d745b")
			draw_rect(Rect2(base+Vector2(cell)*scale_value,Vector2.ONE*scale_value),tint)
	draw_string(font,origin+Vector2(18,34),"臺北・貓空合作茶園" if growing else "新北・鶯歌合作陶坊",HORIZONTAL_ALIGNMENT_LEFT,-1,19,ink)
	var gates:Dictionary=World.TRANSIT.points(region)
	var stop:Dictionary=gates.transfer
	var sites:Array=[
		[stop.cell,stop.label,TransitArt.icon("station"),Vector2(-22,25)],
		[Tea.TEA_NPC,"茶茶",Shell.icon("journal"),Vector2(-18,-27)],
		[Tea.ROASTER,"烘焙台",TeaArt.icon("tea_light"),Vector2(-19,-27)],
		[Tea.PACKER,"包裝寄運",TeaArt.icon("wrapped_jar"),Vector2(19,-5)]
	] if growing else [
		[stop.cell,stop.label,TransitArt.icon("station"),Vector2(-22,25)],
		[Tea.POTTER,"陶師",Shell.icon("journal"),Vector2(-18,-27)],
		[Tea.KILN,"製罐窯",TeaArt.icon("tea_jar"),Vector2(19,-7)],
		[Tea.CLAY,"備土台",TeaArt.icon("clay"),Vector2(19,6)]
	]
	if growing and World.TEA_REVISIT.house_open(data):
		sites.append([World.TEA_REVISIT.HOUSE_SITE,"茶屋展示桌",Items.icon(World.TEA_REVISIT.TEAWARE_ITEM),Vector2(-76,10)])
	for site:Array in sites:
		var at:=center+Vector2(site[0])*scale_value
		mark(at,Color("806049"),false)
		draw_texture_rect(site[2],Rect2(at-Vector2(9,18),Vector2(18,18)),false)
		draw_string(font,at+site[3],site[1],HORIZONTAL_ALIGNMENT_LEFT,-1,13,ink)
	if growing:
		for cell:Vector2i in Tea.TEA_NODES:
			var at:=center+Vector2(cell)*scale_value
			draw_texture_rect(TeaArt.icon("tea_bush"),Rect2(at-Vector2(9,11),Vector2(18,18)),false)
		draw_string(font,center+Vector2(Tea.TEA_NODES[0])*scale_value+Vector2(-11,28),"採茶區",HORIZONTAL_ALIGNMENT_LEFT,-1,13,ink)
	var guide:=tea_map_guide(data,own_id)
	if not guide.is_empty():
		var at:=center+Vector2(guide.target)*scale_value
		draw_circle(at,9.0,paper,false,4.0)
		draw_circle(at,9.0,Color("9c5936"),false,1.5)
		var note:="下一步・"+str(guide.title)
		if guide.travelling:note="從轉乘站前往%s・%s"%[guide.destination,guide.title]
		draw_string(font,origin+Vector2(18,373),note,HORIZONTAL_ALIGNMENT_LEFT,524,15,ink)
	for id in data.players:
		var person:Dictionary=data.players[id]
		mark(base+Vector2(person.x,person.y)*scale_value,Color("c96755") if id==own_id else Color("537ea4"),true)
	draw_string(font,origin+Vector2(18,403),"紅點是你 · 藍點是朋友 · 褐色環標出下一站",HORIZONTAL_ALIGNMENT_LEFT,524,14,ink)
	draw_map_signals(origin,base,scale_value,Rect2i(8,12,30,19))

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
	draw_map_signals(origin,base,scale_value,plaza)

static func springs_sites(indoor:bool,bath_ready:bool) -> Array:
	if indoor:
		return [[Springs.INN_EXIT,"旅舍出口"],[Vector2i(61,22),"暖被床"],[Vector2i(66,24),"暖茶桌"],[Vector2i(69,22),"更衣櫃"]]
	return [
		[World.REGIONS.exit_cell(Springs.REGION),"回程站牌"],
		[World.RESIDENT_BOND.SPRING_CELL,"暖暖"],
		[Springs.INN_DOOR,"暖泉旅舍入口"],
		[Springs.BATH_ENTRANCE,"公共泡腳池" if bath_ready else "公共泡腳池・待修"],
		[Springs.POOLS.spring.water.get_center(),Springs.POOLS.spring.label],
		[Springs.POOLS.upland.water.get_center(),Springs.POOLS.upland.label],
	]

func draw_springs_map(origin:Vector2,viewer:Dictionary) -> void:
	var indoor:=Springs.in_inn(viewer)
	var area:Rect2i=Springs.INN_ROOM if indoor else Springs.LAND
	var scale_value:=24.0 if indoor else 9.0
	var base:=origin+Vector2(24,82)-Vector2(area.position)*scale_value
	draw_rect(Rect2(origin,Vector2(560,420)),Color("eee1c3") if indoor else Color("9ab9ac"))
	for y in range(area.position.y,area.end.y):
		for x in range(area.position.x,area.end.x):
			var cell:=Vector2i(x,y)
			var tint:=Color("c7d1a7")
			if indoor:
				tint=Color("8a6a55") if Springs.room_blocked(cell) else Color("d6b380")
				if cell==Springs.INN_EXIT:tint=Color("ece0bb")
			elif not Springs.spot(cell).is_empty():tint=Color("619b9f")
			elif Springs.INN_FOOTPRINT.has_point(cell) or Springs.BATH_FOOTPRINT.has_point(cell):tint=Color("ab856a")
			draw_rect(Rect2(base+Vector2(cell)*scale_value,Vector2.ONE*scale_value),tint)
	var sites:=springs_sites(indoor,bool(data.get(Springs.BATH_KEY,false)))
	for index in sites.size():
		var site:Array=sites[index]
		var at:=base+(Vector2(site[0])+Vector2(0.5,0.5))*scale_value
		draw_circle(at,7.0,Color("43604c"))
		draw_string(font,at+Vector2(-4,4),str(index+1),HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("fff4d7"))
		var row:=origin+Vector2(326,104+index*28)
		draw_string(font,row,"%d  %s"%[index+1,site[1]],
			HORIZONTAL_ALIGNMENT_LEFT,214,15,Color("324b3e"))
		if not indoor and index>=4:
			var fish:String=Springs.POOLS.spring.fish if index==4 else Springs.POOLS.upland.fish
			draw_texture_rect(Items.icon(fish),Rect2(row+Vector2(172,-18),Vector2(22,22)),false)
	for id in data.players:
		var person:Dictionary=data.players[id]
		if Springs.in_inn(person)!=indoor:continue
		mark(base+Vector2(person.x,person.y)*scale_value,Color("c96755") if id==own_id else Color("537ea4"),true)
	draw_string(font,origin+Vector2(18,35),"暖泉旅舍・室內" if indoor else "宜蘭・礁溪暖泉高地",HORIZONTAL_ALIGNMENT_LEFT,524,19,Color("324b3e"))
	if not indoor:
		var minute:=fposmod(float(data.get("time",0.0)),World.WEATHER.DAY_SECONDS)
		var clue:=World.Collections.fishing_forecast(Springs.REGION,viewer,minute)
		if clue.is_empty():clue=World.Collections.water_clues(Springs.REGION,viewer)
		draw_string(font,origin+Vector2(18,357),clue,HORIZONTAL_ALIGNMENT_LEFT,524,14,Color("324b3e"))
	draw_string(font,origin+Vector2(18,400),"紅點是你 · 藍點是同一區域的朋友",HORIZONTAL_ALIGNMENT_LEFT,524,14,Color("324b3e"))
	draw_map_signals(origin,base,scale_value,area)

func draw_map_signals(origin:Vector2,base:Vector2,cell_scale:float,cells:=Rect2i(Vector2i.ZERO,World.SIZE)) -> void:
	var slots:Dictionary={}
	for entry:Dictionary in data.get("map_signals",[]):
		var kind:String=entry.kind
		if not SignalLabels.has(kind):continue
		var at:=(base+(Vector2(entry.cell)+Vector2(0.5,0.5))*cell_scale).round()
		if not Rect2(origin,Vector2(560,420)).has_point(at):continue
		var index:int=slots.get(entry.cell,0)
		slots[entry.cell]=index+1
		var caption:String=SignalLabels[kind]
		var width:=ceilf(font.get_string_size(caption,HORIZONTAL_ALIGNMENT_LEFT,-1,14).x)+12.0
		var left:=clampf(at.x-width*0.5,origin.x,origin.x+560-width)
		var above:=clampf(at.y-25-index*22,origin.y,origin.y+398)
		var tint:Color=SIGNAL_COLORS[kind]
		var ink:=Color("fff3d1")
		tint.a=clampf(float(entry.remaining)/3000.0,0.0,1.0)
		ink.a=tint.a
		draw_line(at,Vector2(clampf(at.x,left,left+width),above+19),ink,2.0)
		draw_circle(at,3.0,ink)
		draw_rect(Rect2(left,above,width,20),tint)
		draw_rect(Rect2(left,above,width,20),ink,false,1.0)
		draw_string(font,Vector2(left+6,above+15),caption,HORIZONTAL_ALIGNMENT_LEFT,-1,14,ink)
	oar_base=base
	oar_scale=cell_scale
	oar_cells=cells
	if oar_focus!=World.OAR_SIGN.NO_CELL:
		var sign:Dictionary=data.get("objects",{}).get(World.key(oar_focus),{})
		var target:=oar_candidate if oar_candidate!=World.OAR_SIGN.NO_CELL else World.OAR_SIGN.cell(sign.get(World.OAR_SIGN.FIELD))
		var source:=oar_point(oar_focus)
		var source_visible:=cells.has_point(oar_focus)
		if cells.has_point(target):
			var pin:=oar_point(target)
			if source_visible and source!=pin:draw_dashed_line(source,pin,Color("254a49"),2.0,5.0)
			if not reduced_motion and oar_pin_pulse>0.0:
				draw_arc(pin,9.0+roundf(8.0*(1.0-oar_pin_pulse)),0.0,TAU,12,Color(1.0,0.95,0.8,oar_pin_pulse),2.0)
			draw_oar_pin(pin)
		if source_visible:draw_texture_rect(Shell.icon("sign"),Rect2(source-Vector2(8,17),Vector2(16,16)),false)
	else:
		var shown:={}
		for obj:Dictionary in data.get("objects",{}).values():
			if obj.get("type")!=World.OAR_SIGN.KIND or obj.get("owner")!=own_id:continue
			var target:=World.OAR_SIGN.cell(obj.get(World.OAR_SIGN.FIELD))
			if cells.has_point(target) and not shown.has(target):
				shown[target]=true
				draw_oar_pin(oar_point(target))

func oar_point(cell:Vector2i)->Vector2:
	return (oar_base+(Vector2(cell)+Vector2(0.5,0.5))*oar_scale).round()

func draw_oar_pin(at:Vector2)->void:
	draw_circle(at,8.0,Color("fff1cd"))
	draw_circle(at,5.5,Color("235b62"))
	draw_circle(at,2.0,Color("fff1cd"))

func mark(at:Vector2,color:Color,person:bool) -> void:
	if person:
		draw_circle(at,5,Color("fff7e4"))
		draw_circle(at,3,color)
	else:
		draw_rect(Rect2(at-Vector2(5,5),Vector2(10,10)),Color("fff7e4"))
		draw_rect(Rect2(at-Vector2(3,3),Vector2(6,6)),color)

func draw_mine_map(origin:Vector2,region:String) -> void:
	var depth:=int(region.trim_prefix("mine_"))
	draw_rect(Rect2(origin,Vector2(560,420)),Color("e8d9b5"))
	draw_string(font,origin+Vector2(24,32),"金瓜石合作礦場・地下第 %d 層礦道圖"%depth,HORIZONTAL_ALIGNMENT_LEFT,510,19,Color("4b4539"))
	draw_string(font,origin+Vector2(24,56),"往左回上一層，往右到礦務站整備。",HORIZONTAL_ALIGNMENT_LEFT,510,14,Color("635944"))
	var cells := MineLayout.bounds(depth)
	var diagram := Rect2(origin+Vector2(45,78),Vector2(470,208))
	var map_scale := minf(14.0, minf(diagram.size.x/cells.size.x, diagram.size.y/cells.size.y))
	var first := (diagram.get_center()-Vector2(cells.size)*map_scale*0.5).round()
	var base := first-Vector2(cells.position)*map_scale
	var project := func(cell: Vector2) -> Vector2:
		return (base+cell*map_scale).round()
	var terrain := Rect2(first, (Vector2(cells.size)*map_scale).round())
	draw_rect(terrain.grow(5.0),Color("494548"))
	for y in range(cells.position.y,cells.end.y):
		for x in range(cells.position.x,cells.end.x):
			var cell := Vector2i(x,y)
			if not MineLayout.land(cell,depth):
				continue
			var at: Vector2 = project.call(Vector2(cell))
			var corner: Vector2 = project.call(Vector2(cell+Vector2i.ONE))
			var tint := Color("b5a18a") if MineLayout.BASE_RECT.has_point(cell) else Color("baa081")
			if depth==3 and World.MINES.POOL.has_point(cell):
				tint=Color("588e9a")
			draw_rect(Rect2(at,corner-at),tint)
			if data.get("objects",{}).has(World.key(cell)):
				draw_rect(Rect2((at+corner)*0.5-Vector2(3,3),Vector2(6,6)),Color("75543e"))
	for node in World.MINES.NODES:
		var at: Vector2 = project.call(Vector2(node)+Vector2(0.5,0.5))
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
		var at: Vector2 = project.call(Vector2(stations[index])+Vector2(0.5,0.5))
		draw_circle(at,10,Color("614c37"))
		draw_string(font,at+Vector2(-4,5),str(index+1),HORIZONTAL_ALIGNMENT_LEFT,20,14,Color("fff0cb"))
		var legend:=origin+Vector2(35+(index%2)*270,305+(index/2)*30)
		draw_string(font,legend,"%d  %s"%[index+1,labels[index]],HORIZONTAL_ALIGNMENT_LEFT,240,15,Color("4b4539"))
	for id in data.players:
		var person:Dictionary=data.players[id]
		mark(project.call(Vector2(person.x,person.y)),Color("c96755") if id==own_id else Color("537ea4"),true)
	var sign_info:=return_sign(region,int(data.players.get(own_id,{}).get("exploration_points",0)))
	if not sign_info.is_empty():
		draw_return_sign(origin,project.call(Vector2(sign_info.cell)+Vector2(0.5,0.5)),sign_info.hint,405.0)
	draw_string(font,origin+Vector2(24,383),"紅點是你 · 藍點是朋友 · 鎬頭是礦料點",HORIZONTAL_ALIGNMENT_LEFT,510,14,Color("635944"))
	draw_map_signals(origin,base,map_scale,cells)
