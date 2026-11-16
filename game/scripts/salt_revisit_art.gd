@static_unload
extends RefCounted
## 第 40 章「臺南北門回訪・鹽籃批次」的程式繪製 32px 圖（沒有新美術檔，全部靜態，任何動態模式都不動）：
##
##  * 鹽籃 salt_basket（家園擺放的紀念物，32×32，腳落在格子下緣）：
##    一只寬口、略收腳的竹編小籃（麥稈黃的斜紋編織、深褐色粗籃口與籃底），籃口上堆著一座
##    白白的海鹽（右下帶淡藍灰的陰影、幾點亮白的鹽粒），一道彎彎的竹提把從兩側籃口拱到最上方，
##    提把兩端綁著紅色小繩結。
##    與既有的圖都不同：茶陶組（象牙白茶壺＋靛藍釉帶＋紅褐木托盤，低矮一壺兩杯）、礦燈（黃銅燈帽、
##    黃色玻璃、細長直立）、分水木牌（檜木牌、藍色水路、木樁）、海鹽圖示（salt_art 的鹽袋圖）、
##    菜籃小架與接力菜箱（木架、方箱、蔬菜）——鹽籃的辨識點是「拱形提把＋白鹽堆＋斜紋竹編」
##    （test_salt_revisit_scene 以像素比對）。
##    world_view.object_sprite 畫（預覽美術與一般繪製都畫），家園工坊縮圖走同一條路徑。
##  * 背包圖示 salt_basket_kit 與記憶展卡片圖示＝同一張鹽籃圖。
##  * mini(img,cx,bottom)：記憶展展台第四座石座上的 11×11 小鹽籃（提把、鹽堆、竹編籃身）。
const SHADOW:=Color(0.18,0.13,0.08,0.3)
const OUTLINE:=Color("3b2c14")
const RIM:=Color("6b4a1e")
const RIM_LIGHT:=Color("a07a3a")
const STRAW:=Color("dcc27a")
const STRAW_LIGHT:=Color("efdc9c")
const STRAW_DARK:=Color("a98a42")
const HANDLE:=Color("b89a52")
const HANDLE_LIGHT:=Color("e3cc86")
const SALT:=Color("fbfaf4")
const SALT_SHADE:=Color("c6d2da")
const SALT_DEEP:=Color("9fb2bf")
const CORD:=Color("c0392b")
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

## 32×32 salt basket (world sprite, inventory icon and exhibit card icon).
static func basket_texture() -> Texture2D:
	if cache.has("basket"):return cache["basket"]
	var img:=_blank()
	_basket(img)
	cache["basket"]=ImageTexture.create_from_image(img)
	return cache["basket"]

static func _basket(img:Image) -> void:
	_r(img,3,29,26,2,SHADOW)
	# Bamboo hoop handle: an arch from the left rim (x 5) over the top (y 2) to the right rim (x 26).
	var arch:=[[5,15],[5,14],[5,13],[6,12],[6,11],[6,10],[7,9],[7,8],[8,7],[9,6],[10,5],[11,4],[12,4],[13,3],[14,3],[15,3],[16,3],[17,3],[18,3],[19,4],[20,4],[21,5],[22,6],[23,7],[24,8],[24,9],[25,10],[25,11],[25,12],[26,13],[26,14],[26,15]]
	for p:Array in arch:
		_r(img,int(p[0])-1,int(p[1])-1,3,3,OUTLINE)
	for p:Array in arch:
		_px(img,int(p[0]),int(p[1]),HANDLE)
	for p:Array in arch.slice(9,23):_px(img,int(p[0]),int(p[1])-0,HANDLE_LIGHT)
	# Heap of white sea salt above the rim (rows 8..16), shaded blue-grey to the lower right.
	var heap:=[[14,4],[12,8],[10,12],[8,16],[7,18],[6,20],[5,22],[4,24],[4,24]]
	for i in heap.size():
		var y:=8+i
		var x0:int=int(heap[i][0])
		var w:int=int(heap[i][1])
		_r(img,x0-1,y,w+2,1,SALT_DEEP)
		_r(img,x0,y,w,1,SALT)
		_r(img,x0+w-maxi(2,w/3),y,maxi(2,w/3),1,SALT_SHADE)
	for p:Vector2i in [Vector2i(15,9),Vector2i(11,12),Vector2i(17,11),Vector2i(9,14),Vector2i(14,13),Vector2i(20,14),Vector2i(7,15)]:_px(img,p.x,p.y,Color.WHITE)
	for p:Vector2i in [Vector2i(13,11),Vector2i(18,13),Vector2i(10,15),Vector2i(22,15)]:_px(img,p.x,p.y,SALT_SHADE)
	# Thick dark rim (rows 16..18) with a light top edge.
	_r(img,2,16,28,3,OUTLINE)
	_r(img,3,16,26,2,RIM)
	_r(img,3,16,26,1,RIM_LIGHT)
	# Woven body: tapers from 26 px under the rim to 20 px at the foot (rows 19..27).
	for i in 9:
		var y:=19+i
		var inset:=i/3
		_r(img,3+inset-1,y,26-inset*2+2,1,OUTLINE)
		for x in range(3+inset,29-inset):
			# Diagonal twill: 2×2 cells shifting one column per row pair.
			var light:=((x+(y/2))/2)%2==0
			_px(img,x,y,STRAW if light else STRAW_DARK)
		_px(img,3+inset,y,STRAW_LIGHT)
	# A horizontal binding band half way down and the dark foot.
	_r(img,4,23,24,1,RIM)
	_r(img,5,28,22,1,OUTLINE)
	_r(img,6,27,20,1,RIM)
	# Red cord knots where the handle meets the rim.
	_r(img,4,14,3,2,CORD);_px(img,4,16,CORD)
	_r(img,25,14,3,2,CORD);_px(img,27,16,CORD)

static func draw_basket(canvas:CanvasItem,at:Vector2,tint:=Color.WHITE) -> void:
	canvas.draw_texture(basket_texture(),at,tint)

## 11×11 miniature on an exhibit pedestal, centred on cx, standing on y=bottom.
static func mini(img:Image,cx:int,bottom:int) -> void:
	var top:=bottom-10
	# Rounded handle arch (an earlier square handle read as a crate: outputs/鹽籃批次預覽/before/).
	_r(img,cx-2,top,5,1,RIM)
	_px(img,cx-3,top+1,RIM);_px(img,cx+3,top+1,RIM)
	_r(img,cx-4,top+2,1,3,RIM);_r(img,cx+4,top+2,1,3,RIM)
	# Salt heap: a dome above the rim.
	_r(img,cx-1,top+2,3,1,SALT)
	_r(img,cx-2,top+3,5,1,SALT)
	_r(img,cx-3,top+4,7,1,SALT)
	_r(img,cx+1,top+3,1,1,SALT_SHADE);_r(img,cx+2,top+4,1,1,SALT_SHADE)
	# Red cord knots, rim and a woven body that narrows to the foot.
	_px(img,cx-4,top+4,CORD);_px(img,cx+4,top+4,CORD)
	_r(img,cx-5,top+5,11,1,OUTLINE)
	_r(img,cx-4,top+5,9,1,RIM_LIGHT)
	for y in range(top+6,top+10):
		var inset:=0 if y<top+8 else 1
		_px(img,cx-5+inset,y,OUTLINE);_px(img,cx+5-inset,y,OUTLINE)
		for x in range(cx-4+inset,cx+5-inset):
			_px(img,x,y,STRAW if (x+y)%2==0 else STRAW_DARK)
	_r(img,cx-3,top+10,7,1,OUTLINE)

static func has_item(id:String) -> bool:
	return id=="salt_basket_kit"

static func icon(id:String) -> Texture2D:
	return basket_texture() if has_item(id) else null
