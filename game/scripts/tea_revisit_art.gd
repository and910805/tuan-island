@static_unload
extends RefCounted
## 第 40 章「貓空與鶯歌回訪」的程式繪製 32px 圖（沒有新美術檔，全部靜態，任何動態模式都不動）：
##
##  * 茶陶組 tea_ware（家園擺放的紀念物，32×32，腳落在格子下緣）：
##    紅褐色木托盤（淺色上緣、深色前緣與兩隻小腳）上，左邊一把象牙白小茶壺（深色描邊、
##    圓壺身上一道靛藍釉帶、藍色壺蓋與壺鈕、左側把手、右側往上翹的壺嘴），右邊兩只米白小茶杯
##    （靛藍杯腰、杯口看得到琥珀色的茶）。
##    與既有的陶罐類圖（灰綠青瓷罐身、無把手壺嘴）、礦燈（黃銅燈帽、黃色玻璃）、分水木牌
##    （檜木牌、藍色水路、木樁）都不同：主色是象牙白＋靛藍＋紅褐托盤，形狀是低矮的一壺兩杯
##    （test_tea_revisit_scene 以像素比對；第一版青瓷壺太像陶罐，見 outputs/茶罐大單預覽/before/）。
##    world_view.object_sprite 畫（預覽美術與一般繪製都畫），家園工坊縮圖走同一條路徑。
##  * 背包圖示 tea_ware_kit 與記憶展卡片圖示＝同一張茶陶組圖。
##  * mini(img,cx,bottom)：記憶展展台第三座石座上的 11×11 小茶陶組（同樣的配色：托盤、茶壺、一只杯）。
const SHADOW:=Color(0.18,0.13,0.08,0.3)
const OUTLINE:=Color("33372b")
## Ivory glaze with an indigo band (the tea jars are grey-green celadon; an earlier celadon
## teapot read too close to them: outputs/茶罐大單預覽/before/).
const GLAZE:=Color("f1e7cf")
const GLAZE_LIGHT:=Color("fffaee")
const GLAZE_DARK:=Color("cdb88e")
const BLUE:=Color("35548a")
const CREAM:=Color("f5ecd4")
const CREAM_SHADE:=Color("d9cba6")
const TEA:=Color("c98a3a")
const TRAY:=Color("9a5532")
const TRAY_LIGHT:=Color("c47a4a")
const TRAY_FACE:=Color("743d22")
const TRAY_DARK:=Color("4a2615")
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

## 32×32 tea ware (world sprite, inventory icon and exhibit card icon).
static func teaware_texture() -> Texture2D:
	if cache.has("teaware"):return cache["teaware"]
	var img:=_blank()
	_teaware(img)
	cache["teaware"]=ImageTexture.create_from_image(img)
	return cache["teaware"]

static func _cup(img:Image,x:int) -> void:
	# A small cream cup, 5 px wide, standing on the tray surface (bottom row 23).
	_r(img,x,17,5,6,OUTLINE)
	_r(img,x+1,18,3,4,CREAM)
	_r(img,x+1,18,3,1,TEA)
	_r(img,x+1,20,3,1,BLUE)
	_px(img,x+3,21,CREAM_SHADE)
	_r(img,x+1,23,3,1,OUTLINE)

static func _teaware(img:Image) -> void:
	_r(img,1,29,30,2,SHADOW)
	# Wooden tray: a light top surface, a darker front edge and two little feet.
	_r(img,1,20,30,8,TRAY_DARK)
	_r(img,2,21,28,4,TRAY)
	_r(img,2,21,28,1,TRAY_LIGHT)
	_r(img,2,25,28,2,TRAY_FACE)
	for x in [8,15,22]:_r(img,x,25,1,2,TRAY_DARK)
	_r(img,3,28,3,1,TRAY_DARK);_r(img,26,28,3,1,TRAY_DARK)
	# Teapot body: a round celadon pot (rows 12..23) with a dark outline.
	var half:=[2,4,5,5,6,6,6,6,6,5,5,3]
	for i in half.size():
		var y:=12+i
		var w:int=half[i]
		_r(img,10-w,y,w*2+1,1,OUTLINE)
		if i>0 and i<half.size()-1:_r(img,11-w,y,w*2-1,1,GLAZE)
	_r(img,5,16,11,2,BLUE)  # indigo band
	for x in [7,10,13]:_px(img,x,18,BLUE)  # little drops under the band
	_r(img,5,20,11,1,GLAZE_DARK);_r(img,6,21,9,1,GLAZE_DARK)  # foot shade
	_r(img,6,14,1,2,GLAZE_LIGHT);_px(img,7,13,GLAZE_LIGHT)  # glaze sheen
	# Lid and knob.
	_r(img,7,10,7,2,OUTLINE);_r(img,8,10,5,1,BLUE)
	_r(img,9,8,3,2,OUTLINE);_px(img,10,8,BLUE)
	# Handle: a C loop on the left.
	_r(img,1,14,1,5,OUTLINE);_r(img,2,13,4,1,OUTLINE);_r(img,2,19,2,1,OUTLINE)
	_r(img,2,14,1,5,GLAZE_DARK)
	# Spout rising to the upper right.
	for p:Vector2i in [Vector2i(16,17),Vector2i(17,16),Vector2i(17,15),Vector2i(18,14),Vector2i(19,13)]:
		_px(img,p.x,p.y,OUTLINE);_px(img,p.x,p.y+1,OUTLINE)
	_r(img,16,18,1,1,GLAZE);_px(img,17,17,GLAZE);_px(img,18,15,GLAZE);_px(img,20,12,OUTLINE)
	# Two cups on the right.
	_cup(img,20)
	_cup(img,26)

static func draw_teaware(canvas:CanvasItem,at:Vector2,tint:=Color.WHITE) -> void:
	canvas.draw_texture(teaware_texture(),at,tint)

## 11×11 miniature on an exhibit pedestal, centred on cx, standing on y=bottom.
static func mini(img:Image,cx:int,bottom:int) -> void:
	var top:=bottom-10
	# Tray.
	_r(img,cx-5,bottom-2,11,3,TRAY_DARK)
	_r(img,cx-5,bottom-2,11,1,TRAY_LIGHT)
	_r(img,cx-4,bottom-1,9,1,TRAY)
	# Teapot (left) with lid, knob, handle and spout.
	_px(img,cx-2,top+1,OUTLINE)
	_r(img,cx-3,top+2,3,1,OUTLINE)
	_r(img,cx-4,top+3,5,5,OUTLINE)
	_r(img,cx-3,top+3,3,4,GLAZE)
	_r(img,cx-3,top+5,3,1,BLUE)
	_px(img,cx-3,top+3,GLAZE_LIGHT)
	_r(img,cx-5,top+4,1,2,OUTLINE)
	_px(img,cx+1,top+4,OUTLINE);_px(img,cx+2,top+3,OUTLINE)
	# One cream cup with tea (right).
	_r(img,cx+2,top+5,4,3,OUTLINE)
	_r(img,cx+3,top+5,2,2,CREAM)
	_r(img,cx+3,top+5,2,1,TEA)

static func has_item(id:String) -> bool:
	return id=="tea_ware_kit"

static func icon(id:String) -> Texture2D:
	return teaware_texture() if has_item(id) else null
