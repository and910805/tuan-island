@static_unload
extends RefCounted
## 第 40 章「水塔」water_tower 的程式繪製圖（沒有新美術檔，同 lanyang_revisit_art.gd 的做法）。
##
##  * 世界圖 32×48（和儲水桶一樣從格子往上多畫 16px，at+(0,-16)）：底下先畫銅水管
##    （IndustryArt.pipe_texture，依鄰格連接；家園工坊縮圖為左右相連），上面是：
##      兩根灰色石柱＋木 X 撐、木平台、檜木桶身（兩道銅箍）、赤陶色尖頂與頂上小旗，
##      桶身正面一扇「水位窗」：空＝深色玻璃；1～3 格＝下方藍水；滿＝整窗藍水；
##      中間一根銅水管從桶底沿著兩柱之間落地，管上一個法蘭接頭和一個閥門。
##    出水／只蓄水一眼可分：
##      出水   ＝頂上綠色三角旗、閥門綠色且把手順著水管（直立＝開）；
##      只蓄水 ＝頂上紅色方牌、閥門紅色且把手橫擋水管（＝關），閥門下方一道紅色封條。
##    和儲水桶（地面上的木桶、看得到水面）、分流閘（雙木柱＋閘板）、河水泵（手壓泵）、
##    灑水器（地面小噴頭）都不同：只有水塔高高架在石柱上、有尖頂。
##    全部靜態（不看時間），任何動態模式都一樣。
##  * 背包圖示 water_tower_kit（32×32）：縮小的水塔（半滿、出水）＋右下一段銅管接頭。
const IndustryArt=preload("res://scripts/industry_art.gd")
const CAPACITY:=96
const SHADOW:=Color(0.18,0.13,0.08,0.32)
const STONE:=Color("8c8c84")
const STONE_LIGHT:=Color("b8b7ac")
const STONE_DARK:=Color("5f605a")
const WOOD:=Color("6b4a2f")
const WOOD_LIGHT:=Color("8a6a3e")
const DECK:=Color("a77a4a")
const DECK_LIGHT:=Color("d1a66c")
const STAVE:=Color("c79a5e")
const STAVE_LIGHT:=Color("e2bd82")
const STAVE_DARK:=Color("8d6440")
const ROOF:=Color("b0583a")
const ROOF_LIGHT:=Color("d77b52")
const ROOF_DARK:=Color("6e3122")
const COPPER:=Color("c7834a")
const COPPER_LIGHT:=Color("f0b77a")
const COPPER_DARK:=Color("7a4a26")
const GLASS:=Color("2c3a40")
const GLASS_GLINT:=Color("6f8a92")
const WATER:=Color("3f8fcf")
const WATER_LIGHT:=Color("bfe8f5")
const ON:=Color("5fae4a")
const ON_LIGHT:=Color("a6dc86")
const OFF:=Color("c8483c")
const OFF_LIGHT:=Color("f2b0a6")
const LEVELS:=4
static var cache:Dictionary={}

## 0 = empty, LEVELS = full, 1..LEVELS-1 = partly full (rounded up so any water shows).
static func level_of(water:int) -> int:
	if water<=0:return 0
	if water>=CAPACITY:return LEVELS
	return clampi(ceili(float(water)*LEVELS/CAPACITY),1,LEVELS-1)

static func enabled_of(obj:Dictionary) -> bool:
	return obj.is_empty() or obj.get("enabled",true)==true

# ----------------------------------------------------------------- helpers --

static func _r(img:Image,x:int,y:int,w:int,h:int,c:Color) -> void:
	var box:=Rect2i(x,y,w,h).intersection(Rect2i(0,0,img.get_width(),img.get_height()))
	if box.size.x>0 and box.size.y>0:img.fill_rect(box,c)

static func _px(img:Image,x:int,y:int,c:Color) -> void:
	if x>=0 and y>=0 and x<img.get_width() and y<img.get_height():img.set_pixel(x,y,c)

# ------------------------------------------------------------------- tower --

## 32×48 tower for a water `level` (0..LEVELS) and the 出水 (`enabled`) flag.
static func tower_texture(level:int,enabled:bool) -> Texture2D:
	level=clampi(level,0,LEVELS)
	var key:="tower:%d:%s"%[level,str(enabled)]
	if cache.has(key):return cache[key]
	var img:=Image.create_empty(32,48,false,Image.FORMAT_RGBA8)
	img.fill(Color(0,0,0,0))
	_tower(img,level,enabled)
	cache[key]=ImageTexture.create_from_image(img)
	return cache[key]

static func texture_for(obj:Dictionary) -> Texture2D:
	return tower_texture(level_of(int(obj.get("water",0))),enabled_of(obj))

static func _tower(img:Image,level:int,enabled:bool) -> void:
	_r(img,3,46,26,2,SHADOW)
	# Stone legs on stone feet, a timber X brace between them.
	for x in [4,24]:
		_r(img,x-1,43,6,3,STONE_DARK)
		_r(img,x-1,43,6,1,STONE)
		_r(img,x,26,4,17,STONE)
		_r(img,x,26,1,17,STONE_LIGHT)
		_r(img,x+3,26,1,17,STONE_DARK)
		for y in [30,35,40]:_r(img,x,y,4,1,STONE_DARK)
	for i in 14:
		for d in 2:
			_px(img,8+i+d,27+i,WOOD)
			_px(img,23-i-d,27+i,WOOD)
	_r(img,8,33,16,1,WOOD_LIGHT)
	# Copper down pipe from the barrel to the ground, with a flange joint.
	_r(img,14,23,4,23,COPPER_DARK)
	_r(img,15,23,2,23,COPPER)
	_r(img,15,23,1,23,COPPER_LIGHT)
	_r(img,12,29,8,3,COPPER_DARK)
	_r(img,12,29,8,1,COPPER_LIGHT)
	_px(img,13,30,COPPER);_px(img,18,30,COPPER)
	# Hand wheel on the pipe: green (出水) or red (只蓄水); 只蓄水 also hangs a red
	# "no outflow" plate with a white bar on the pipe below the wheel.
	var wheel:=ON if enabled else OFF
	var wheel_dark:=wheel.darkened(0.4)
	for p:Vector2i in [Vector2i(14,32),Vector2i(15,32),Vector2i(16,32),Vector2i(17,32),Vector2i(13,33),Vector2i(18,33),
			Vector2i(12,34),Vector2i(19,34),Vector2i(12,35),Vector2i(19,35),Vector2i(12,36),Vector2i(19,36),
			Vector2i(13,37),Vector2i(18,37),Vector2i(14,38),Vector2i(15,38),Vector2i(16,38),Vector2i(17,38)]:
		_px(img,p.x,p.y,wheel)
	_r(img,13,35,6,1,wheel_dark)
	_r(img,15,33,2,5,wheel_dark)
	_r(img,15,34,2,2,COPPER_LIGHT)
	_px(img,14,32,(ON_LIGHT if enabled else OFF_LIGHT))
	if not enabled:
		_r(img,11,40,10,6,Color("5a1f1a"))
		_r(img,12,41,8,4,OFF)
		_r(img,13,42,6,2,Color("f6efe6"))
		_px(img,12,41,OFF_LIGHT)
	# Timber deck.
	_r(img,2,23,28,3,DECK)
	_r(img,2,23,28,1,DECK_LIGHT)
	_r(img,2,25,28,1,WOOD)
	for x in [8,16,24]:_px(img,x,24,WOOD)
	# Barrel: staves and two copper hoops.
	_r(img,6,9,20,14,STAVE)
	for x in range(6,26,4):_r(img,x,9,1,14,STAVE_DARK)
	_r(img,7,9,1,14,STAVE_LIGHT)
	_r(img,24,9,2,14,STAVE_DARK)
	_r(img,5,10,22,2,COPPER_DARK)
	_r(img,5,10,22,1,COPPER)
	_r(img,5,20,22,2,COPPER_DARK)
	_r(img,5,20,22,1,COPPER)
	# Water-level window: dark glass, filled from the bottom.
	_r(img,10,12,12,9,WOOD)
	_r(img,11,13,10,7,GLASS)
	var rows:int=[0,2,4,6,7][level]
	if rows>0:
		_r(img,11,20-rows,10,rows,WATER)
		_r(img,11,20-rows,10,1,WATER_LIGHT)
	if level<LEVELS:_r(img,12,14,1,2,GLASS_GLINT)
	for y in [14,16,18]:_px(img,21,y,COPPER_LIGHT)
	# Conical roof, finial and the mode marker.
	for row in 7:
		var half:=2+row*2
		_r(img,16-half,2+row,half*2,1,ROOF if row<6 else ROOF_DARK)
		_px(img,16-half,2+row,ROOF_LIGHT)
	_r(img,15,0,2,3,WOOD)
	if enabled:
		_r(img,17,0,5,2,ON)
		_r(img,17,2,3,1,ON)
		_px(img,17,0,ON_LIGHT)
	else:
		_r(img,17,0,6,5,Color("5a1f1a"))
		_r(img,18,1,4,3,OFF)
		_px(img,18,1,OFF_LIGHT);_px(img,21,3,OFF_LIGHT)

## World / thumbnail: copper pipe joined like a water pipe on the ground tile (mask bits
## up/right/down/left), then the tower above it. Static in every motion mode.
static func draw_tower(canvas:CanvasItem,at:Vector2,obj:Dictionary,mask:int=10,tint:=Color.WHITE) -> void:
	if mask!=0:
		var pipe:=IndustryArt.pipe_texture(mask&15)
		if pipe!=null:canvas.draw_texture(pipe,at,tint)
	canvas.draw_texture(texture_for(obj),at+Vector2(0,-16),tint)

# -------------------------------------------------------------------- icon --

static func has_item(id:String) -> bool:
	return id=="water_tower_kit"

static func icon(id:String) -> Texture2D:
	if id!="water_tower_kit":return null
	if cache.has("icon"):return cache["icon"]
	var img:=Image.create_empty(32,32,false,Image.FORMAT_RGBA8)
	img.fill(Color(0,0,0,0))
	_r(img,4,30,22,2,SHADOW)
	# Legs, brace and feet.
	for x in [6,20]:
		_r(img,x,19,3,11,STONE)
		_r(img,x,19,1,11,STONE_LIGHT)
		_r(img,x-1,28,5,2,STONE_DARK)
	for i in 9:
		_px(img,9+i,20+i,WOOD)
		_px(img,19-i,20+i,WOOD)
	# Down pipe turning right into a copper joint stub (the kit joins a pipe line).
	_r(img,13,18,3,9,COPPER_DARK)
	_r(img,14,18,1,9,COPPER)
	_r(img,13,24,19,4,COPPER_DARK)
	_r(img,13,25,19,2,COPPER)
	_r(img,13,25,19,1,COPPER_LIGHT)
	_r(img,26,23,3,6,COPPER_DARK)
	_r(img,26,23,3,1,COPPER_LIGHT)
	# Deck.
	_r(img,3,17,22,2,DECK)
	_r(img,3,17,22,1,DECK_LIGHT)
	# Barrel with hoops and a half-full level window.
	_r(img,6,7,16,10,STAVE)
	for x in range(6,22,4):_r(img,x,7,1,10,STAVE_DARK)
	_r(img,20,7,2,10,STAVE_DARK)
	_r(img,5,8,18,1,COPPER)
	_r(img,5,15,18,1,COPPER)
	_r(img,10,9,8,6,WOOD)
	_r(img,11,10,6,4,GLASS)
	_r(img,11,12,6,2,WATER)
	_r(img,11,12,6,1,WATER_LIGHT)
	# Roof and green pennant.
	for row in 5:
		var half:=2+row*2
		_r(img,14-half,2+row,half*2,1,ROOF if row<4 else ROOF_DARK)
		_px(img,14-half,2+row,ROOF_LIGHT)
	_r(img,13,0,2,2,WOOD)
	_r(img,15,0,4,2,ON)
	cache["icon"]=ImageTexture.create_from_image(img)
	return cache["icon"]
