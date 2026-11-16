@static_unload
extends RefCounted
## 第 40 章「金瓜石回訪」的程式繪製 32px 圖（沒有新美術檔，全部靜態，任何動態模式都不動）：
##
##  * 礦燈 mine_lantern（家園擺放的紀念物，32×32，腳落在格子下緣）：
##    鐵絲提把（半圓弧）＋小提環、黃銅燈帽與煙囪、深鐵色護籠（三根直條、一道橫箍）罩著
##    暖黃色玻璃與白亮燈芯、黃銅底座；左下角放兩小塊帶金點的礦石，右下一小截木楔。
##    與既有的紙燈籠柱（T 字木柱吊琥珀色圓紙燈籠、紅流蘇）、家具「燈」、分水木牌（檜木牌、
##    藍色水路）都不同：沒有木柱、沒有紙面、沒有藍色（test_jinguashi_revisit_scene 以像素比對）。
##    world_view.object_sprite 畫（預覽美術與一般繪製都畫），家園工坊縮圖走同一條路徑。
##  * 背包圖示 mine_lantern_kit 與記憶展卡片圖示＝同一張礦燈圖。
##  * mini(img,cx,bottom)：記憶展展台第二座石座上的 11×11 小礦燈（同樣的配色）。
const SHADOW:=Color(0.18,0.13,0.08,0.3)
const IRON:=Color("2f2a26")
const IRON_MID:=Color("4a433c")
const IRON_LIGHT:=Color("6e655a")
const BRASS:=Color("a9792f")
const BRASS_LIGHT:=Color("e0b04f")
const BRASS_DARK:=Color("6e4b1c")
const GLASS:=Color("f2c14e")
const GLASS_WARM:=Color("e89a32")
const FLAME:=Color("fff4c2")
const GLOW:=Color(1.0,0.86,0.42,0.35)
const ROCK:=Color("7d776b")
const ROCK_LIGHT:=Color("a8a294")
const ROCK_DARK:=Color("514c43")
const GOLD:=Color("f0c84a")
const WEDGE:=Color("8a6a3e")
const WEDGE_DARK:=Color("5a3d24")
static var cache:Dictionary={}

static func _r(img:Image,x:int,y:int,w:int,h:int,c:Color) -> void:
	var box:=Rect2i(x,y,w,h).intersection(Rect2i(0,0,img.get_width(),img.get_height()))
	if box.size.x>0 and box.size.y>0:img.fill_rect(box,c)

static func _px(img:Image,x:int,y:int,c:Color) -> void:
	if x>=0 and y>=0 and x<img.get_width() and y<img.get_height():img.set_pixel(x,y,c)

static func _blank() -> Image:
	var img:=Image.create_empty(32,32,false,Image.FORMAT_RGBA8)
	img.fill(Color(0,0,0,0))
	return img

## 32×32 mine lantern (world sprite, inventory icon and exhibit card icon).
static func lantern_texture() -> Texture2D:
	if cache.has("lantern"):return cache["lantern"]
	var img:=_blank()
	_lantern(img)
	cache["lantern"]=ImageTexture.create_from_image(img)
	return cache["lantern"]

static func _lantern(img:Image) -> void:
	_r(img,5,29,23,2,SHADOW)
	# Soft warm glow either side of the glass (static).
	_r(img,9,14,1,10,GLOW);_r(img,22,14,1,10,GLOW)
	_r(img,10,12,12,1,GLOW)
	# Wire bail: a half circle over the cap with a small ring on top.
	for p:Vector2i in [Vector2i(10,9),Vector2i(10,8),Vector2i(10,7),Vector2i(11,6),Vector2i(11,5),Vector2i(12,4),Vector2i(13,3),
			Vector2i(14,3),Vector2i(15,2),Vector2i(16,2),Vector2i(17,3),Vector2i(18,3),Vector2i(19,4),Vector2i(20,5),Vector2i(20,6),
			Vector2i(21,7),Vector2i(21,8),Vector2i(21,9)]:
		_px(img,p.x,p.y,IRON_MID)
	_px(img,15,0,IRON);_px(img,16,0,IRON);_px(img,14,1,IRON);_px(img,17,1,IRON)
	# Brass chimney and cap (a stepped dome).
	_r(img,14,6,4,3,BRASS_DARK);_r(img,14,6,1,3,BRASS)
	_r(img,12,9,8,1,BRASS);_r(img,11,10,10,1,BRASS);_r(img,10,11,12,1,BRASS_DARK)
	_r(img,13,9,3,1,BRASS_LIGHT);_r(img,12,10,3,1,BRASS_LIGHT)
	for x in [11,15,19]:_px(img,x,8,IRON)  # vent holes
	# Glass chamber with the flame.
	_r(img,10,12,12,13,IRON)
	_r(img,11,13,10,11,GLASS)
	_r(img,11,20,10,4,GLASS_WARM)
	_r(img,15,15,2,6,FLAME);_px(img,15,14,FLAME);_px(img,16,21,Color("f6d77a"))
	_r(img,12,14,1,5,Color("fff8dc"))  # glass sheen
	# Iron guard: three bars and one hoop.
	for x in [13,18]:_r(img,x,13,1,11,IRON)
	_r(img,11,18,10,1,IRON_MID)
	_r(img,10,12,12,1,IRON_LIGHT)
	# Brass foot with a dark rim.
	_r(img,9,24,14,1,BRASS_DARK)
	_r(img,9,25,14,3,BRASS)
	_r(img,9,25,14,1,BRASS_LIGHT)
	_r(img,8,28,16,1,IRON)
	_px(img,9,25,BRASS_DARK);_px(img,22,25,BRASS_DARK)
	# Two small ore lumps with gold flecks (left) and a little wooden wedge (right).
	_r(img,2,25,5,4,ROCK_DARK);_r(img,3,25,4,3,ROCK);_r(img,3,25,3,1,ROCK_LIGHT)
	_px(img,4,26,GOLD);_px(img,6,27,GOLD)
	_r(img,5,27,3,2,ROCK_DARK);_r(img,5,27,2,1,ROCK);_px(img,6,28,GOLD)
	_r(img,25,26,5,3,WEDGE_DARK);_r(img,25,26,4,2,WEDGE);_r(img,25,26,4,1,Color("b08a55"))

static func draw_lantern(canvas:CanvasItem,at:Vector2,tint:=Color.WHITE) -> void:
	canvas.draw_texture(lantern_texture(),at,tint)

## 11×11 miniature on an exhibit pedestal, centred on cx, standing on y=bottom.
static func mini(img:Image,cx:int,bottom:int) -> void:
	var top:=bottom-10
	for p:Vector2i in [Vector2i(-2,1),Vector2i(-1,0),Vector2i(0,0),Vector2i(1,0),Vector2i(2,1)]:_px(img,cx+p.x,top+p.y,IRON_MID)
	_r(img,cx-1,top+2,3,1,BRASS_LIGHT)
	_r(img,cx-3,top+3,7,1,BRASS)
	_r(img,cx-3,top+4,7,5,IRON)
	_r(img,cx-2,top+4,5,4,GLASS)
	_r(img,cx-2,top+7,5,1,GLASS_WARM)
	_r(img,cx,top+5,1,2,FLAME)
	_r(img,cx-3,top+8,7,1,BRASS)
	_r(img,cx-4,top+9,9,1,BRASS_DARK)
	_r(img,cx-3,top+10,7,1,IRON)

static func has_item(id:String) -> bool:
	return id=="mine_lantern_kit"

static func icon(id:String) -> Texture2D:
	return lantern_texture() if has_item(id) else null
