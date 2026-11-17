@static_unload
extends RefCounted
## 第 40 章北門合作鹽田「儲滷槽」的程式繪製圖。
##
## 一格（SaltBrine.TANK＝(48,14)，合作社工寮東側）上的 32×48 圖，腳落在格子下緣（ANCHOR），
## 往上高出格子 RISE＝16 px 以內（實際槽口最高點約高出 12 px）。左右都不超出這一格：
## 工寮圖（192×128）的右緣剛好在 x＝48 格的左邊界，兩張圖不互相遮。
##
## 外觀（斜俯視的低矮橢圓槽）：
##  * 一圈厚實的深褐木槽口（上緣較亮），槽身上半是直立木板、下半是灰白石砌（灰泥縫交錯），
##    中間一道銅箍；
##  * 槽身左前方一截向南（往學徒區鹽田）伸出的銅管，接管處有法蘭、旁邊一個紅色小閥輪；
##  * 槽身右前方一根白色水位尺（三道刻度），裡面的藍綠色水柱跟著水位升高；
##  * 槽口裡：槽壁（深褐內壁）＋看得到的槽底或滷水面。
## 與工寮（大屋頂）、合作社收鹽箱（方木箱）、鹽田（平的方格）、閘門、水車、收鹽台都不同：
## 辨識點是「橢圓槽口＋石砌槽身＋銅管＋水位尺＋藍綠滷水」（test_salt_brine_scene 以像素比對）。
##
## 水位（SaltBrine.level，0..30 桶）分五種畫法，一眼看得出來：
##   empty（0）     ：看得到乾的槽底（淺土黃、白色鹽殼斑點），上方一圈乾掉的白色鹽線；水位尺空的。
##   low（1–10）    ：槽底一小彎淺藍綠滷水，上方白色鹽線；水位尺 1／4。
##   mid（11–20）   ：滷水蓋住大半個槽口，較深的藍綠；水位尺一半多。
##   high（21–29）  ：滷水幾乎滿到槽口，只剩一圈窄窄的內壁；最深的藍綠；水位尺 3／4 多。
##   full（30）     ：滷水齊平槽口，槽口內緣一圈白色鹽沫（滿槽的亮邊）；水位尺全滿。
## 每種基礎水位快取成貼圖，收存或放滷時另繪短暫的水面與管口回饋。

const SaltBrine=preload("res://scripts/salt_brine.gd")
const TRANSFER_SECONDS:=0.76

const SIZE:=Vector2i(32,48)
## Bottom-centre feet of the canvas (on the tank cell's lower edge).
const ANCHOR:=Vector2i(16,48)
## Canvas pixels above the tank cell's top edge.
const RISE:=16
const STATES:=["empty","low","mid","high","full"]
## Depth (px) of the visible floor / brine surface below the rim opening, per state.
const SURFACE_SHIFT:={"empty":6.0,"low":5.0,"mid":3.0,"high":1.5,"full":0.0}
## Gauge column fill height (px of 13), per state.
const GAUGE_FILL:={"empty":0,"low":3,"mid":7,"high":10,"full":13}
## Label anchor relative to the tank cell's top-left (label bottom sits on the rim top).
const LABEL_OFFSET:=Vector2(16,3)

const SHADOW:=Color(0.18,0.13,0.08,0.3)
const OUTLINE:=Color("2e2418")
const RIM:=Color("7d5530")
const RIM_LIGHT:=Color("b88a52")
const PLANK:=Color("a3743f")
const PLANK_LIGHT:=Color("c4955a")
const PLANK_DARK:=Color("6e4a26")
const PLANK_SHADE:=Color("85592f")
const STONE:=Color("c2b9a6")
const STONE_LIGHT:=Color("d9d1bf")
const STONE_DARK:=Color("948b7a")
const MORTAR:=Color("6f675a")
const COPPER:=Color("b8693a")
const COPPER_LIGHT:=Color("e39a63")
const COPPER_DARK:=Color("7a3f1f")
const VALVE:=Color("b03a2e")
const INNER_WALL:=Color("4f3721")
const INNER_WALL_LIGHT:=Color("6a4a2c")
const FLOOR:=Color("c8b894")
const FLOOR_DARK:=Color("a59472")
const CRUST:=Color("f1ece0")
const TIDE:=Color("e9e4d6")
const BRINE:={"low":Color("5aa3a6"),"mid":Color("3b8792"),"high":Color("2b6f80"),"full":Color("2b6f80")}
const BRINE_LIGHT:=Color("a6dcd8")
const FOAM:=Color("f6f3ea")
const GAUGE_FACE:=Color("ebe3cf")
const GAUGE_MARK:=Color("6e4a26")
const GAUGE_WATER:=Color("2f7f8e")

static var cache:Dictionary={}

# ------------------------------------------------------------------ public --

## Visual state for a tank level (clamped to 0..SaltBrine.CAP).
static func state_of(level:int) -> String:
	var n:=clampi(level,0,SaltBrine.CAP)
	if n<=0:return "empty"
	if n<=10:return "low"
	if n<=20:return "mid"
	if n<SaltBrine.CAP:return "high"
	return "full"

## World label of the focused tank:「儲滷槽・n／30 桶」.
static func label(level:int) -> String:
	return "%s・%d／%d 桶"%[SaltBrine.NAME,clampi(level,0,SaltBrine.CAP),SaltBrine.CAP]

## Canvas top-left (world px, before camera) of the tank drawn on `cell`.
static func top_left(cell:Vector2i) -> Vector2:
	return Vector2(cell)*32+Vector2(0,-RISE)

## Whole canvas rect (world px) — every pixel the tank draw can touch.
static func canvas_rect(cell:Vector2i=SaltBrine.TANK) -> Rect2:
	return Rect2(top_left(cell),Vector2(SIZE))

## Painted part of the tank (rim top to the pipe end), world px.
static func art_rect(cell:Vector2i=SaltBrine.TANK) -> Rect2:
	return Rect2(top_left(cell)+Vector2(1,19),Vector2(30,29))

static func texture_for_state(state:String) -> Texture2D:
	var key:=state if state in STATES else "empty"
	if cache.has(key):return cache[key]
	var img:=Image.create_empty(SIZE.x,SIZE.y,false,Image.FORMAT_RGBA8)
	img.fill(Color(0,0,0,0))
	_paint(img,key)
	cache[key]=ImageTexture.create_from_image(img)
	return cache[key]

static func texture_for(level:int) -> Texture2D:
	return texture_for_state(state_of(level))

## Draws the tank at `at` = the tank cell's top-left on the canvas (already
## camera-shifted). Static: no elapsed / reduced-motion input on purpose.
static func draw_tank(canvas:CanvasItem,at:Vector2,level:int) -> void:
	canvas.draw_texture(texture_for(level),(at+Vector2(0,-RISE)).round())

static func draw_transfer(canvas:CanvasItem,at:Vector2,level:int,delta:int,age:float) -> void:
	if age<0.0 or age>=TRANSFER_SECONDS:return
	var top:=(at+Vector2(0,-RISE)).round()
	var progress:=age/TRANSFER_SECONDS
	var tint:=BRINE_LIGHT
	tint.a=(1.0-progress)*0.94
	if level>0:
		var surface_y:=roundf(26.0+float(SURFACE_SHIFT[state_of(level)])*0.48)
		var spread:=roundf(2.0+7.0*(progress if delta>0 else 1.0-progress))
		var center:=top+Vector2(16,surface_y)
		canvas.draw_line(center-Vector2(spread,0),center+Vector2(spread,0),tint,1.0)
		canvas.draw_line(center+Vector2(-spread+2,2),center+Vector2(spread-2,2),tint,1.0)
	for trail in range(2):
		var step:=fposmod(progress*2.8+trail*0.5,1.0)
		if delta>0:step=1.0-step
		canvas.draw_rect(Rect2(top+Vector2(7,42+roundf(step*8.0)),Vector2(2,2)),tint)

# ------------------------------------------------------------------ painting --

static func _in(x:int,y:int,cx:float,cy:float,rx:float,ry:float) -> bool:
	var dx:=(float(x)+0.5-cx)/rx
	var dy:=(float(y)+0.5-cy)/ry
	return dx*dx+dy*dy<=1.0

static func _body_in(x:int,y:int) -> bool:
	return (y>=27 and y<41 and x>=2 and x<30) or _in(x,y,16.0,41.0,14.0,5.0)

static func _body_out(x:int,y:int) -> bool:
	return (y>=26 and y<41 and x>=1 and x<31) or _in(x,y,16.0,41.0,15.0,6.0)

static func _wall(x:int,y:int) -> Color:
	if y<=36:
		if x%4==1:return PLANK_DARK
		if x<=5:return PLANK_LIGHT
		if x>=26:return PLANK_SHADE
		return PLANK
	if y==37:
		if x==6 or x==16 or x==26:return COPPER_DARK
		return COPPER_LIGHT if x<12 else COPPER
	if y==38:return COPPER_DARK
	var band:=0 if y<=42 else 1
	if y==42 or (x+band*4)%8==3:return MORTAR
	if x<=6:return STONE_LIGHT
	if x>=25:return STONE_DARK
	return STONE

static func _paint(img:Image,state:String) -> void:
	var w:=SIZE.x
	var h:=SIZE.y
	var shift:float=SURFACE_SHIFT[state]
	for y in h:
		for x in w:
			var c:=Color(0,0,0,0)
			if _in(x,y,16.0,46.0,15.5,2.0):c=SHADOW
			if _body_out(x,y):c=OUTLINE
			if _body_in(x,y):c=_wall(x,y)
			# Rim ring (outline, wood, lighter top arc).
			if _in(x,y,16.0,27.0,15.0,7.5):c=OUTLINE
			if _in(x,y,16.0,27.0,14.0,6.5):c=RIM_LIGHT if y<=23 else RIM
			# Opening: inner wall, then floor / brine surface.
			if _in(x,y,16.0,26.5,11.0,4.5):
				c=INNER_WALL_LIGHT if x<=9 else INNER_WALL
				var surface:=_in(x,y,16.0,26.5+shift,11.0,4.5)
				if surface:
					if state=="empty":
						c=FLOOR
						if (x*7+y*13)%9==0:c=CRUST
						elif (x+y*3)%11==0:c=FLOOR_DARK
					else:
						c=BRINE[state]
				elif state!="full" and _in(x,y,16.0,25.5+shift,11.0,4.5):
					c=TIDE
			img.set_pixel(x,y,c)
	if state=="full":
		# Brim: a white salt-foam ring right at the rim's inner edge.
		for y in h:
			for x in w:
				if _in(x,y,16.0,26.5,11.0,4.5) and not _in(x,y,16.0,26.5,9.6,3.4):img.set_pixel(x,y,FOAM)
	if state!="empty":
		# Glints on the brine surface (static).
		var top:=int(ceilf(22.0+shift))
		var water:Color=BRINE[state]
		for glint:Vector2i in [Vector2i(9,top+1),Vector2i(10,top+1),Vector2i(11,top+1),Vector2i(12,top+1),Vector2i(17,top+3),Vector2i(18,top+3)]:
			if img.get_pixel(glint.x,glint.y)==water:img.set_pixel(glint.x,glint.y,BRINE_LIGHT)
	_gauge(img,state)
	_pipe(img)

static func _px(img:Image,x:int,y:int,c:Color) -> void:
	if x>=0 and y>=0 and x<img.get_width() and y<img.get_height():img.set_pixel(x,y,c)

static func _rect(img:Image,x:int,y:int,w:int,h:int,c:Color) -> void:
	var box:=Rect2i(x,y,w,h).intersection(Rect2i(0,0,img.get_width(),img.get_height()))
	if box.size.x>0 and box.size.y>0:img.fill_rect(box,c)

## Level gauge on the front-right of the wall: white face, three notches, water column.
static func _gauge(img:Image,state:String) -> void:
	_rect(img,22,32,6,15,OUTLINE)
	_rect(img,23,33,4,13,GAUGE_FACE)
	for y in [36,39,42]:_px(img,23,y,GAUGE_MARK)
	var fill:int=GAUGE_FILL[state]
	if fill>0:
		_rect(img,24,46-fill,2,fill,GAUGE_WATER)
		_rect(img,24,46-fill,2,1,BRINE_LIGHT)

## Copper outlet toward the pans (south): flange on the wall, spout down to the ground, red valve.
static func _pipe(img:Image) -> void:
	_rect(img,4,39,7,3,OUTLINE)
	_rect(img,5,40,5,1,COPPER)
	_rect(img,5,40,1,1,COPPER_LIGHT)
	_rect(img,5,42,5,6,OUTLINE)
	for y in range(42,47):
		_px(img,6,y,COPPER_LIGHT)
		_px(img,7,y,COPPER)
		_px(img,8,y,COPPER_DARK)
	_rect(img,6,47,3,1,OUTLINE)
	_rect(img,10,43,3,3,VALVE)
	_px(img,11,44,OUTLINE)
