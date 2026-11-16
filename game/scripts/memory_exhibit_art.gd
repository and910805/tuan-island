@static_unload
extends RefCounted
## 第 40 章「風鈴節廣場・地方記憶展」的程式繪製像素圖（沒有新美術檔，全部靜態）。
##
##  * stand(on_display)：56×56 展台，畫在格子左上角 + STAND_OFFSET(-12,-24)，腳落在格子下緣。
##    灰藍瓦片屋頂（紅褐屋脊、兩端翹起的燕尾）、屋簷下一塊紅底金邊的小匾額、米白色展示牆、
##    四座灰石小展台（固定 EXHIBIT_ORDER 順序：分水木牌、礦燈、陶器、鹽籃）、木造底座。
##    展出中的展台擺著該展品的迷你圖（分水木牌沿用 lanyang_revisit_art 木牌的檜木色與藍色
##    三道水口）；空展台只有一圈虛線框，一眼看得出空著。
##    與紀念品交換攤（深藍金條紋遮雨棚、彩旗、櫃台黃票）、市集攤位（綠米白棚）、公告板與
##    告示牌（木板）都不同（test_memory_exhibit_scene 以像素比對）。
##  * icon(id)：頁面卡片用 32×32 圖示（分水木牌直接用 lanyang_revisit_art.plaque_texture()，
##    礦燈直接用 jinguashi_revisit_art.lantern_texture()；第二座石座的小礦燈也同配色；
##    陶器＝茶陶組，直接用 tea_revisit_art.teaware_texture()，第三座石座畫 tea_revisit_art.mini；
##    鹽籃直接用 salt_revisit_art.basket_texture()，第四座石座畫 salt_revisit_art.mini）。
##  * 未讀標記（紅色小圓點）不在圖裡，由 memory_exhibit_ui.draw_stand 另外畫。
const RevisitArt=preload("res://scripts/lanyang_revisit_art.gd")
const JgArt=preload("res://scripts/jinguashi_revisit_art.gd")
const TeaArt=preload("res://scripts/tea_revisit_art.gd")
const SaltArt=preload("res://scripts/salt_revisit_art.gd")
const ORDER:=["lanyang","jinguashi","tea_pottery","beimen"]
const SIZE:=Vector2i(56,56)
## Pedestal centres (x) inside the 56×56 stand image; objects stand on y=36.
const PEDESTALS:=[12,23,34,45]
const SHADOW:=Color(0.18,0.13,0.08,0.3)
const WOOD_DARK:=Color("4a3020")
const WOOD:=Color("8a6a3e")
const WOOD_LIGHT:=Color("c79a5e")
const POST:=Color("5a3d24")
const POST_LIGHT:=Color("8a6a3e")
const TILE:=Color("5d6b73")
const TILE_LIGHT:=Color("7d8b92")
const TILE_DARK:=Color("3f4a50")
const RIDGE:=Color("8a3b2f")
const RIDGE_LIGHT:=Color("b65a45")
const BOARD_RED:=Color("9e2f28")
const GOLD:=Color("d9a441")
const GOLD_LIGHT:=Color("f3d27a")
const WALL:=Color("efe2c2")
const WALL_EDGE:=Color("b89b6a")
const STONE:=Color("a9a395")
const STONE_TOP:=Color("d6d1c4")
const STONE_DARK:=Color("6e695e")
const GHOST:=Color("9c7f4f")
static var cache:Dictionary={}

static func _r(img:Image,x:int,y:int,w:int,h:int,c:Color) -> void:
	var box:=Rect2i(x,y,w,h).intersection(Rect2i(0,0,img.get_width(),img.get_height()))
	if box.size.x>0 and box.size.y>0:img.fill_rect(box,c)

static func _px(img:Image,x:int,y:int,c:Color) -> void:
	if x>=0 and y>=0 and x<img.get_width() and y<img.get_height():img.set_pixel(x,y,c)

static func _blank(w:int,h:int) -> Image:
	var img:=Image.create_empty(w,h,false,Image.FORMAT_RGBA8)
	img.fill(Color(0,0,0,0))
	return img

# ------------------------------------------------------------------- stand --

## The whole stand with the listed exhibits on their pedestals (cached per set).
static func stand(on_display:Array) -> Texture2D:
	var shown:=[]
	for id:String in ORDER:
		if id in on_display:shown.append(id)
	var key:="stand:"+",".join(PackedStringArray(shown))
	if cache.has(key):return cache[key]
	var img:=_blank(SIZE.x,SIZE.y)
	_stand(img)
	for i in ORDER.size():
		var id:String=ORDER[i]
		if id in shown:_object(img,id,int(PEDESTALS[i]),36)
		else:_empty(img,int(PEDESTALS[i]))
	cache[key]=ImageTexture.create_from_image(img)
	return cache[key]

static func _stand(img:Image) -> void:
	_r(img,2,53,52,3,SHADOW)
	# Back wall (cream exhibition board) with a tan frame.
	_r(img,6,11,44,27,WALL_EDGE)
	_r(img,7,12,42,25,WALL)
	_r(img,7,36,42,1,Color("ddcfa8"))
	# Posts.
	for x in [3,50]:
		_r(img,x,9,3,45,POST)
		_r(img,x+1,9,1,45,POST_LIGHT)
	# Grey-blue tiled roof: a trapezoid widening towards the eave.
	for y in range(2,10):
		var spread:=(y-2)/2
		var left:=6-spread
		var right:=50+spread
		_r(img,left,y,right-left,1,TILE_LIGHT if y%2==0 else TILE)
		for x in range(left+2,right,4):_px(img,x,y,TILE_DARK)
	# Ridge with upturned swallow-tail ends.
	_r(img,5,1,46,2,RIDGE)
	_r(img,5,1,46,1,RIDGE_LIGHT)
	_r(img,2,0,4,2,RIDGE);_px(img,2,0,RIDGE_LIGHT);_px(img,1,0,RIDGE)
	_r(img,50,0,4,2,RIDGE);_px(img,53,0,RIDGE_LIGHT);_px(img,54,0,RIDGE)
	# Eave trim.
	_r(img,1,10,54,2,WOOD_DARK)
	_r(img,1,10,54,1,Color("6b4a2f"))
	# Small red name board (匾額) with a gold rim and four gold "characters".
	_r(img,17,12,22,9,GOLD)
	_r(img,18,13,20,7,BOARD_RED)
	# Five tiny glyph shapes (one per character of 地方記憶展, not legible text).
	var glyphs:=[[[0,0,3,1],[1,0,1,4],[0,3,3,1]],[[0,0,3,1],[0,0,1,4],[2,0,1,4],[0,3,3,1]],
		[[1,0,1,4],[0,1,3,1]],[[0,0,1,4],[0,0,3,1],[2,2,1,2],[0,3,3,1]],[[0,0,3,1],[1,1,1,3],[0,3,1,1],[2,3,1,1]]]
	for i in glyphs.size():
		for part:Array in glyphs[i]:_r(img,19+i*4+int(part[0]),14+int(part[1]),int(part[2]),int(part[3]),GOLD_LIGHT)
	# Four stone pedestals.
	# Four separate stone pedestals (9 px wide, 2 px of wall between them).
	_r(img,7,37,42,10,Color("cfc09a"))
	for cx:int in PEDESTALS:
		_r(img,cx-4,37,9,11,STONE_DARK)
		_r(img,cx-3,38,7,9,STONE)
		_r(img,cx-4,37,9,2,STONE_TOP)
		_r(img,cx-3,39,1,8,Color("bdb7a9"))
		_r(img,cx-3,46,7,1,Color("8d887b"))
	# Wooden plinth.
	_r(img,2,47,52,6,WOOD_DARK)
	_r(img,3,48,50,4,WOOD)
	_r(img,3,48,50,1,WOOD_LIGHT)
	for x in range(8,52,9):_r(img,x,49,1,3,Color("6e4f2c"))

## Empty pedestal: a dashed outline where an object will stand.
static func _empty(img:Image,cx:int) -> void:
	for x in range(cx-4,cx+5):
		if (x-cx)%2==0:
			_px(img,x,27,GHOST)
			_px(img,x,36,GHOST)
	for y in range(27,37):
		if y%2==1:
			_px(img,cx-4,y,GHOST)
			_px(img,cx+4,y,GHOST)

## Miniature exhibit standing on y=bottom, centred on cx (at most 11×11).
static func _object(img:Image,id:String,cx:int,bottom:int) -> void:
	var top:=bottom-10
	match id:
		"lanyang":
			# Cedar plaque on two stakes with the carved three-mouth channel.
			_r(img,cx-3,top+7,1,4,RevisitArt.POST);_r(img,cx+3,top+7,1,4,RevisitArt.POST)
			_r(img,cx-5,top,11,8,RevisitArt.CEDAR_RIM)
			_r(img,cx-4,top+1,9,6,RevisitArt.CEDAR)
			_r(img,cx-4,top+1,9,1,RevisitArt.CEDAR_LIGHT)
			_r(img,cx,top+1,1,2,RevisitArt.CARVE)
			_r(img,cx-3,top+3,7,1,RevisitArt.CARVE)
			for x in [cx-3,cx,cx+3]:_r(img,x,top+4,1,2,RevisitArt.CARVE_DARK)
			_px(img,cx-5,top,Color(0,0,0,0));_px(img,cx+5,top,Color(0,0,0,0))
		"jinguashi":
			# 礦燈 in the jinguashi_revisit_art colours: bail, brass cap, glowing glass, brass foot.
			JgArt.mini(img,cx,bottom)
		"tea_pottery":
			# 茶陶組 in the tea_revisit_art colours: tray, celadon teapot and a cream cup.
			TeaArt.mini(img,cx,bottom)
		"beimen":
			# 鹽籃 in the salt_revisit_art colours: bamboo handle, white salt heap, woven body.
			SaltArt.mini(img,cx,bottom)

# ------------------------------------------------------------------- icons --

## 32×32 card icon of an exhibit (the plaque reuses the lanyang plaque art).
static func icon(id:String) -> Texture2D:
	if id=="lanyang":return RevisitArt.plaque_texture()
	if id=="jinguashi":return JgArt.lantern_texture()
	if id=="tea_pottery":return TeaArt.teaware_texture()
	if id=="beimen":return SaltArt.basket_texture()
	return null
