extends Control
const Outline=preload("res://scripts/taiwan_outline.gd")
const Shell=preload("res://scripts/life_ui_shell.gd")
const TransitArt=preload("res://scripts/transit_art.gd")
var font:SystemFont
const TIANWEI_LONLAT:=Vector2(120.52,23.89) # 座標待查核
# 臺南市北門區沿海約 120.13E, 23.27N：在田尾西南方、臺灣海峽一側；投影與其他地點相同。
const BEIMEN_LONLAT:=Vector2(120.13,23.27)
const JIAOXI_LONLAT:=Vector2(121.775,24.827)
# 澎湖・望安約 119.50E, 23.36N（座標待查核）。依本圖投影會落在控制項左緣之外、北部路線面板底下，
# 所以出生島以「位置示意」框畫在臺灣海峽一側（主島西方），不是真實比例位置。
const WANGAN_LONLAT:=Vector2(119.50,23.36) # 座標待查核
# 蘭陽試作田是宜蘭的原創地點；此點只標示宜蘭蘭陽平原一帶，座標待查核。
const LANYANG_LONLAT:=Vector2(121.78,24.62)
const OFFSET:=Vector2(30,8)
# 出生島示意框：位於北部路線面板與「中部花木」標籤下方、圖例上方。
const HOME_INSET:=Rect2(4,258,124,42)
const HOME_MARKER:=Vector2(16,270)
const HOME_LABEL_AT:=Vector2(27,275)
const HOME_CAPTION_AT:=Vector2(27,293)
const NORTH_PANEL:=Rect2(5,54,120,181)
func _ready()->void:
	custom_minimum_size=Vector2(280,380)
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	ensure_font()

func ensure_font()->void:
	if font!=null:return
	font=SystemFont.new()
	font.font_names=PackedStringArray(["Microsoft JhengHei","Noto Sans CJK TC","Arial"])

func _draw()->void:
	if font==null:return
	var offset:=OFFSET
	var outline:=PackedVector2Array()
	for point in Outline.POINTS:outline.append(point+offset)
	draw_colored_polygon(outline,Color("a8bc86"))
	draw_polyline(outline,Color("5b7858"),2.0)
	var region:=str(get_meta("current_region",""))
	# 宜蘭端：蘭陽試作田（原創）在宜蘭；房子圖示改畫在澎湖・望安。
	var lanyang:=project(LANYANG_LONLAT)
	var lanyang_color:=Color("ad644b") if region=="lanyang" else Color("3c573e")
	draw_circle(lanyang,3.5,lanyang_color)
	draw_line(lanyang,lanyang+Vector2(-6,8),lanyang_color,1)
	var springs:=project(JIAOXI_LONLAT)
	var here:=region=="jiaoxi"
	var spring_color:=Color("ad644b") if here else Color("3c573e")
	draw_circle(springs,4,spring_color)
	draw_line(springs,springs+Vector2(9,-8),spring_color)
	var mine:=project(Vector2(121.86,25.11))
	draw_texture_rect(Shell.icon("pick"),Rect2(mine-Vector2(12,12),Vector2(24,24)),false)
	for point in [["貓空",121.59,24.97],["鶯歌",121.35,24.95]]:
		var spot:=project(Vector2(float(point[1]),float(point[2])))
		draw_circle(spot,3,Color("54774d"))
		var offset_y:=18 if point[0]=="貓空" else 38
		draw_line(spot,spot+Vector2(-5,offset_y-4),Color("a78764"),1)
	draw_northern_route()
	for place in [["中部花木",120.5,24.0],["花東縱谷",121.35,23.5]]:
		draw_circle(project(Vector2(float(place[1]),float(place[2]))),3,Color("897f68"))
	if show_flowers():
		# 田尾鄉（彰化縣）約 120.52E, 23.89N，座標待查核；投影與其他地點相同。
		var tianwei:=project(TIANWEI_LONLAT)
		draw_line(tianwei,Vector2(126,tianwei.y),Color("a78764"),1)
		draw_circle(tianwei,3.5,Color("54774d"))
	draw_salt_marker()
	draw_home_inset()
	for label in labels():
		draw_string(font,label.at,str(label.text),HORIZONTAL_ALIGNMENT_LEFT,-1,int(label.size),label.color)

# 地圖上所有獨立標籤（北部路線面板內的站名另計為面板）；繪製與重疊檢查共用同一份位置。
func labels()->Array:
	var region:=str(get_meta("current_region",""))
	var result:=[]
	var lanyang:=project(LANYANG_LONLAT)
	result.append({"id":"lanyang","text":"宜蘭・蘭陽"+("・目前" if region=="lanyang" else ""),"at":Vector2(172,lanyang.y+19),"size":12,"color":Color("ad644b") if region=="lanyang" else Color("3c573e")})
	var springs:=project(JIAOXI_LONLAT)
	var here:=region=="jiaoxi"
	result.append({"id":"jiaoxi","text":"礁溪"+("・目前" if here else ""),"at":springs+Vector2(11,-7),"size":12,"color":Color("ad644b") if here else Color("3c573e")})
	var mine:=project(Vector2(121.86,25.11))
	result.append({"id":"jinguashi","text":"金瓜石・礦區","at":mine+Vector2(-98,-10),"size":14,"color":Color("5d4837")})
	for point in [["貓空",121.59,24.97],["鶯歌",121.35,24.95]]:
		var spot:=project(Vector2(float(point[1]),float(point[2])))
		var offset_y:=18 if point[0]=="貓空" else 38
		result.append({"id":str(point[0]),"text":str(point[0]),"at":spot+Vector2(-10,offset_y+8),"size":12,"color":Color("3c573e")})
	for place in [["中部花木",120.5,24.0],["花東縱谷",121.35,23.5]]:
		var at:=project(Vector2(float(place[1]),float(place[2])))
		var shift:=Vector2(-88,-4) if float(place[1])<120.8 else Vector2(8,5)
		if place[0]=="中部花木":shift=Vector2(10,250-at.y)
		result.append({"id":str(place[0]),"text":str(place[0]),"at":Vector2(maxf(6,at.x+shift.x),at.y+shift.y),"size":12,"color":Color("7d7968")})
	if show_flowers():
		var tianwei:=project(TIANWEI_LONLAT)
		result.append({"id":"tianwei","text":"田尾","at":Vector2(128,tianwei.y+4),"size":12,"color":Color("3c573e")})
	var marker:=salt_marker()
	var salt_color:=Color("54774d") if marker.open else Color("958877")
	result.append({"id":"beimen","text":str(marker.label),"at":Vector2(128,marker.position.y+4),"size":12,"color":salt_color})
	var home:=home_marker()
	result.append({"id":"home","text":str(home.label),"at":HOME_LABEL_AT,"size":12,"color":Color("ad644b") if home.current else Color("3c573e")})
	result.append({"id":"home_caption","text":str(home.caption),"at":HOME_CAPTION_AT,"size":10,"color":Color("686f58")})
	result.append({"id":"legend","text":"N ↑  灰點：後續章節","at":Vector2(8,373),"size":12,"color":Color("686f58")})
	return result

# 估計標籤外框：取字型量測與「每字一個字級寬」的較大者，寧可估大。
func label_rect(label:Dictionary)->Rect2:
	ensure_font()
	var text:=str(label.text)
	var size:=int(label.size)
	var width:=float(text.length()*size)
	if font!=null:width=maxf(width,font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x)
	var at:Vector2=label.at
	return Rect2(at.x,at.y-size,width,size*1.3)

# 供測試與排版檢查：標籤外框、北部路線面板、出生島示意框與田尾／北門引線。
func layout_rects()->Dictionary:
	var result:={}
	for label in labels():result[str(label.id)]=label_rect(label)
	result["north_panel"]=NORTH_PANEL
	result["home_inset"]=HOME_INSET
	var marker:=salt_marker()
	var beimen:Vector2=marker.position
	result["beimen_leader"]=Rect2(beimen.x,beimen.y-1,126-beimen.x,2)
	if show_flowers():
		var tianwei:=project(TIANWEI_LONLAT)
		result["tianwei_leader"]=Rect2(tianwei.x,tianwei.y-1,126-tianwei.x,2)
	return result

# 出生島：澎湖・望安（風鈴渡口與居民為遊戲原創）。
func home_marker()->Dictionary:
	var current:=str(get_meta("current_region",""))=="home"
	return {"position":HOME_MARKER,"true_position":project(WANGAN_LONLAT),"current":current,"label":"澎湖・望安"+("・目前" if current else ""),"caption":"位置示意・不依比例","inset":HOME_INSET}

func draw_home_inset()->void:
	var home:=home_marker()
	draw_style_box(preload("res://scripts/inventory_pixel_theme.gd").paper_style(),HOME_INSET)
	draw_rect(HOME_INSET.grow(-2),Color("a78764"),false,1.0)
	var color:=Color("ad644b") if home.current else Color("3c573e")
	draw_circle(HOME_MARKER,7,Color("8fb3b0"))
	draw_texture_rect(Shell.icon("home"),Rect2(HOME_MARKER-Vector2(8,8),Vector2(16,16)),false)
	if home.current:draw_arc(HOME_MARKER,9,0.0,TAU,20,color,1.5)

# 田尾只在收到花圃來信（或已走訪）後顯示，避免提前暴露後續旅程。
func show_flowers()->bool:
	var book:Dictionary=get_meta("travel_book",{})
	return bool(get_meta("flower_open",false)) or book.get("visited",{}).get("tianwei",false)==true or str(get_meta("current_region",""))=="tianwei"

func draw_northern_route()->void:
	var active:=str(get_meta("current_region",""))
	var book:Dictionary=get_meta("travel_book",{})
	var visited:Dictionary=book.get("visited",{})
	var flowers:=show_flowers()
	var step:=18.0 if flowers else 21.0
	var stop_y:=func(index:int)->float:return 89.0+index*step
	draw_style_box(preload("res://scripts/inventory_pixel_theme.gd").paper_style(),NORTH_PANEL)
	draw_string(font,Vector2(16,73),"北部路線",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("3c573e"))
	draw_line(Vector2(21,stop_y.call(0)-1),Vector2(21,stop_y.call(3)+1),Color("a78764"),2)
	var last:float=stop_y.call(6 if flowers else 5)
	draw_polyline(PackedVector2Array([Vector2(21,stop_y.call(1)),Vector2(12,stop_y.call(1)),Vector2(12,last),Vector2(21,last)]),Color("a78764"),1)
	draw_line(Vector2(12,stop_y.call(4)),Vector2(21,stop_y.call(4)),Color("a78764"),1)
	if flowers:draw_line(Vector2(12,stop_y.call(5)),Vector2(21,stop_y.call(5)),Color("a78764"),1)
	var stops:=[["toucheng","頭城"],["ruifang","瑞芳"],["jiufen","九份"],["jinguashi","金瓜石"],["maokong","貓空"],["yingge","鶯歌"]]
	if flowers:stops.append(["tianwei","田尾"])
	for index in stops.size():
		var id:String=stops[index][0]
		var here:=id==active
		var known:=bool(visited.get(id,false))
		var y:float=stop_y.call(index)
		var color:=Color("ad644b") if here else (Color("54774d") if known else Color("958877"))
		draw_circle(Vector2(21,y),4,color)
		draw_string(font,Vector2(31,y+4),stops[index][1]+("・目前" if here else ""),HORIZONTAL_ALIGNMENT_LEFT,-1,13,color)
	draw_string(font,Vector2(14,218 if flowers else 222),"茶陶線經臺北轉乘",HORIZONTAL_ALIGNMENT_LEFT,-1,10,Color("54774d"))
	if flowers:draw_string(font,Vector2(14,230),"花圃線縱貫線南下",HORIZONTAL_ALIGNMENT_LEFT,-1,10,Color("54774d"))

static func project(lonlat:Vector2)->Vector2:
	return OFFSET+Vector2((lonlat.x-119.95)*90,(25.4-lonlat.y)*99)

# 北門鹽田：收到鹽田來信（或已走訪、正在北門）前只畫輪廓與「未開放」；整張地圖不接收點擊。
func salt_marker()->Dictionary:
	var book:Dictionary=get_meta("travel_book",{})
	var open:bool=bool(get_meta("salt_open",false)) or book.get("visited",{}).get("beimen",false)==true or str(get_meta("current_region",""))=="beimen"
	var here:=str(get_meta("current_region",""))=="beimen"
	return {"position":project(BEIMEN_LONLAT),"open":open,"label":"臺南北門"+("・目前" if here else ("" if open else "・未開放"))}

func draw_salt_marker()->void:
	var marker:=salt_marker()
	var at:Vector2=marker.position
	var open:bool=marker.open
	var color:=Color("54774d") if open else Color("958877")
	draw_line(at,Vector2(126,at.y),Color("a78764") if open else Color("b9ad98"),1)
	if open:draw_circle(at,3.5,color)
	else:draw_arc(at,3.5,0.0,TAU,16,color,1.2)
