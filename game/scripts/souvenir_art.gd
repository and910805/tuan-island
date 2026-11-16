@static_unload
extends RefCounted
## T071 紀念票兌換裝飾的像素圖（程式繪製，沒有新美術檔）。
##
## 七種裝飾各一張 32×32 圖（piece(kind) 快取），同一張圖用在三個地方：
##  * 世界與建造目錄縮圖：FurnitureSpriteArt.draw_sprite 轉來 draw()，圖的左上角對齊
##    格子左上角，腳（陰影）落在格子下緣 —— 與家園布置題的八種道具相同；
##  * 背包圖示：InventoryItemArt.icon 轉來 icon("<kind>_kit")；
##  * 紀念品交換攤頁面的目錄圖示（souvenir_exchange_ui.gd）。
## 全部靜態（任何動態模式都不動），因此減少動態時也不需要另外處理。
##
## 造型刻意與既有家具、家園布置題道具分開：
##   veg_basket_rack   兩層木架＋三只竹籃（紅蘿蔔、葉菜、南瓜色木塊）
##   relay_crate_stack 大小兩只疊起的木箱，側面米白接力箭頭，上箱冒出葉菜
##   carp_banner       左側旗竿＋金色頂珠，米白布旗、藍色上下邊，中間圓肚橘色鯽魚
##   float_garland     兩柱曬網架，菱形漁網上綁藍、綠、橘三顆玻璃浮球，下方再垂一顆紅球
##   lantern_post      T 字木柱，中央吊一盞琥珀色圓燈籠（橫向竹骨、紅色流蘇）
##                     —— 與布置題的紅色方燈籠（側臂吊掛）顏色、外形都不同
##   flower_arch       細竹半圓拱，纏著綠葉與粉、白、黃小花
##   trio_keepsake     深色木框牌子立在兩腳上，畫著菜籃、鯽魚、燈籠三個小圖，頂上紅色花結
## 紀念品交換攤（souvenir_exchange_ui.gd）另有 48×56 的攤位圖 booth()。

const KINDS:=["veg_basket_rack","relay_crate_stack","carp_banner","float_garland","lantern_post","flower_arch","trio_keepsake"]
const KIT_SUFFIX:="_kit"
const SHADOW:=Color(0.18,0.13,0.08,0.3)
const WOOD_DARK:=Color("5a3d24")
const WOOD:=Color("8a6a3e")
const WOOD_LIGHT:=Color("c79a5e")
const POLE:=Color("6b4a2f")
const POLE_LIGHT:=Color("8d6440")
static var cache:Dictionary={}

static func has_kind(kind:String) -> bool:
	return kind in KINDS

static func has_item(id:String) -> bool:
	return id.ends_with(KIT_SUFFIX) and id.trim_suffix(KIT_SUFFIX) in KINDS

## 世界與縮圖：32×32 圖畫在格子左上角 at（腳落在格子下緣）。
static func draw(canvas:CanvasItem,at:Vector2,kind:String,tint:=Color.WHITE) -> bool:
	var texture:=piece(kind)
	if texture==null:return false
	canvas.draw_texture(texture,at,tint)
	return true

## 背包圖示（32×32，與世界圖同一張）。
static func icon(id:String) -> Texture2D:
	if not has_item(id):return null
	return piece(id.trim_suffix(KIT_SUFFIX))

# ----------------------------------------------------------------- helpers --

static func _r(img:Image,x:int,y:int,w:int,h:int,c:Color) -> void:
	var box:=Rect2i(x,y,w,h).intersection(Rect2i(0,0,img.get_width(),img.get_height()))
	if box.size.x>0 and box.size.y>0:img.fill_rect(box,c)

static func _px(img:Image,x:int,y:int,c:Color) -> void:
	if x>=0 and y>=0 and x<img.get_width() and y<img.get_height():img.set_pixel(x,y,c)

static func _boxed(img:Image,x:int,y:int,w:int,h:int,fill:Color,edge:Color) -> void:
	_r(img,x,y,w,h,edge)
	_r(img,x+1,y+1,w-2,h-2,fill)

## Filled disc with a 1px outline and a small highlight (glass float, rosette, veg).
static func _disc(img:Image,cx:int,cy:int,radius:int,fill:Color,edge:Color,shine:=true) -> void:
	for y in range(cy-radius,cy+radius+1):
		for x in range(cx-radius,cx+radius+1):
			var d:=Vector2(x-cx,y-cy).length()
			if d<=radius+0.25:_px(img,x,y,edge)
	for y in range(cy-radius,cy+radius+1):
		for x in range(cx-radius,cx+radius+1):
			if Vector2(x-cx,y-cy).length()<=radius-0.75:_px(img,x,y,fill)
	if shine and radius>=2:
		_px(img,cx-1,cy-1,fill.lightened(0.55))
		if radius>=3:_px(img,cx-2,cy-1,fill.lightened(0.35));_px(img,cx-1,cy-2,fill.lightened(0.35))

static func _post(img:Image,x:int,y:int,h:int) -> void:
	_r(img,x,y,2,h,POLE)
	_r(img,x+1,y,1,h,POLE_LIGHT)

## Small bamboo basket (body x..x+w, y..y+h) with weave lines and a light rim.
static func _basket(img:Image,x:int,y:int,w:int,h:int) -> void:
	_boxed(img,x,y,w,h,Color("d9b56a"),Color("6e4f24"))
	for i in range(x+2,x+w-1,3):_r(img,i,y+2,1,h-3,Color("b8914a"))
	_r(img,x+1,y+1,w-2,1,Color("f0d58e"))

# -------------------------------------------------------------------- art --

## The 32×32 picture of a decoration (cached); null for unknown kinds.
static func piece(kind:String) -> Texture2D:
	if not kind in KINDS:return null
	if cache.has(kind):return cache[kind]
	var img:=Image.create_empty(32,32,false,Image.FORMAT_RGBA8)
	img.fill(Color(0,0,0,0))
	match kind:
		"veg_basket_rack":_veg_basket_rack(img)
		"relay_crate_stack":_relay_crate_stack(img)
		"carp_banner":_carp_banner(img)
		"float_garland":_float_garland(img)
		"lantern_post":_lantern_post(img)
		"flower_arch":_flower_arch(img)
		"trio_keepsake":_trio_keepsake(img)
	var texture:=ImageTexture.create_from_image(img)
	cache[kind]=texture
	return texture

static func _veg_basket_rack(img:Image) -> void:
	_r(img,3,29,27,2,SHADOW)
	_post(img,4,6,24);_post(img,26,6,24)
	_r(img,4,5,24,2,WOOD_DARK)
	# Top tier: two baskets — radishes and leafy greens.
	for leaf:Array in [[7,4],[11,4]]:_r(img,leaf[0],leaf[1],2,3,Color("5f9e3e"))
	_disc(img,8,8,2,Color("e0505a"),Color("7a2a2a"))
	_disc(img,12,8,2,Color("e0505a"),Color("7a2a2a"))
	_disc(img,20,7,3,Color("7fbf5a"),Color("3f6e2a"))
	_r(img,18,6,2,2,Color("a8d880"))
	_basket(img,6,9,9,6)
	_basket(img,17,9,9,6)
	_boxed(img,3,15,26,3,WOOD_LIGHT,WOOD_DARK)
	# Bottom tier: one wide basket of pumpkin-orange blocks.
	_disc(img,11,20,3,Color("e8923e"),Color("7a4a1a"))
	_disc(img,17,20,3,Color("f0b040"),Color("7a5a1a"))
	_disc(img,22,21,2,Color("e8923e"),Color("7a4a1a"))
	_r(img,11,16,1,2,Color("4f8a36"));_r(img,17,16,1,2,Color("4f8a36"))
	_basket(img,7,21,18,6)
	_boxed(img,3,26,26,3,WOOD_LIGHT,WOOD_DARK)

static func _relay_crate_stack(img:Image) -> void:
	_r(img,2,29,29,2,SHADOW)
	# Greens peeking out of the top crate.
	for leaf:Array in [[10,2,3,5,"6aa84a"],[14,1,3,6,"4f8a36"],[18,2,3,5,"6aa84a"],[22,3,2,4,"4f8a36"]]:
		_r(img,leaf[0],leaf[1],leaf[2],leaf[3],Color(leaf[4]))
	_disc(img,16,6,2,Color("e0505a"),Color("7a2a2a"),false)
	# Top crate (smaller, set back).
	_boxed(img,7,7,19,11,Color("c99a64"),WOOD_DARK)
	_r(img,8,12,17,1,Color("9a6a3a"))
	_r(img,8,8,17,1,Color("e0b880"))
	# Small green arrow on the top crate.
	_r(img,11,14,7,2,Color("4f8a36"))
	for i in 3:_r(img,18+i,13+i,1,4-2*i,Color("4f8a36"))
	# Bottom crate (wide).
	_boxed(img,3,17,26,13,Color("b8865a"),WOOD_DARK)
	_r(img,4,18,24,1,Color("d9b580"))
	_r(img,4,27,24,1,Color("8a5c30"))
	_r(img,5,18,2,11,Color("9a6a3a"));_r(img,25,18,2,11,Color("9a6a3a"))
	# Cream relay arrow →.
	_r(img,8,22,11,3,Color("f3e2b0"))
	for i in 4:_r(img,19+i,20+i,1,7-2*i,Color("f3e2b0"))
	_r(img,8,25,11,1,Color("8a5c30"))

static func _carp_banner(img:Image) -> void:
	_r(img,3,29,24,2,SHADOW)
	_boxed(img,2,27,9,4,Color("8a6a3e"),Color("4a3626"))
	_post(img,5,2,26)
	_disc(img,6,2,2,Color("f0c048"),Color("8a5c20"),false)
	_r(img,6,4,21,2,POLE)
	# Cloth.
	_boxed(img,9,5,17,21,Color("f4ead2"),Color("7a6a50"))
	_r(img,10,6,15,2,Color("4f86b8"))
	_r(img,10,22,15,2,Color("4f86b8"))
	for x in range(10,25,3):_px(img,x,26,Color("4f86b8"))
	# Round-bellied carp facing left.
	var body:=[[10,14,5],[11,13,7],[12,12,9],[13,12,9],[14,12,9],[15,12,9],[16,13,7],[17,14,5]]
	for row:Array in body:_r(img,row[1],row[0],row[2],1,Color("d98b45"))
	_r(img,13,15,6,2,Color("f2c48a"))
	_r(img,21,12,2,5,Color("c0703a"));_r(img,23,11,1,7,Color("c0703a"))
	_r(img,15,10,4,1,Color("c0703a"))
	_px(img,16,13,Color("c0703a"));_px(img,18,14,Color("c0703a"));_px(img,17,12,Color("c0703a"))
	_r(img,13,13,2,2,Color("3c3a36"));_px(img,13,13,Color("fff8e8"))

static func _float_garland(img:Image) -> void:
	_r(img,1,29,7,2,SHADOW);_r(img,24,29,7,2,SHADOW)
	_post(img,3,5,25);_post(img,27,5,25)
	_r(img,2,4,28,2,WOOD)
	_r(img,2,4,28,1,Color("b08a58"))
	# Diamond fishing net hanging from the bar, sagging in the middle.
	var net:=Color("cdb88c")
	for x in range(5,27):
		var bottom:=17+int(round(3.0*sin(PI*float(x-5)/21.0)))
		for y in range(6,bottom+1):
			if (x+y)%4==0 or (x-y+40)%4==0:_px(img,x,y,net)
		_px(img,x,bottom,Color("a8915e"))
	# Glass floats tied in the net.
	_disc(img,10,10,3,Color("4f9fd1"),Color("1f4f73"))
	_disc(img,21,9,3,Color("e88a3e"),Color("7a3f14"))
	_disc(img,16,15,3,Color("5fb38a"),Color("235a40"))
	# One more float hanging on a rope below the net.
	_r(img,9,18,1,4,Color("8a7650"))
	_disc(img,9,24,3,Color("d9534a"),Color("6e2420"))

static func _lantern_post(img:Image) -> void:
	_r(img,7,29,19,2,SHADOW)
	_r(img,8,28,16,2,POLE)
	_r(img,14,3,4,26,POLE)
	_r(img,15,3,1,26,POLE_LIGHT)
	_r(img,7,2,18,2,WOOD_DARK)
	_r(img,7,2,18,1,Color("8a6a3e"))
	_r(img,16,4,1,3,Color("3a2a1e"))
	# Round amber paper lantern hung in front of the post.
	var rows:=[[7,6],[8,10],[9,12],[10,14],[11,14],[12,14],[13,14],[14,14],[15,14],[16,14],[17,12],[18,10],[19,6]]
	for row:Array in rows:
		var w:int=row[1]
		_r(img,16-w/2-1,row[0],w+2,1,Color("7a4a1a"))
	for row:Array in rows:
		var w:int=row[1]
		_r(img,16-w/2,row[0],w,1,Color("f6c36b"))
	for y in [9,12,15,18]:
		var w:int=0
		for row:Array in rows:
			if int(row[0])==y:w=int(row[1])
		_r(img,16-w/2,y,w,1,Color("e09a3e"))
	_r(img,13,10,6,6,Color("ffe4a0"))
	_r(img,15,9,2,10,Color("c8453a"))
	_r(img,12,6,8,1,Color("3a2a1e"))
	_r(img,12,20,8,1,Color("3a2a1e"))
	_r(img,15,21,2,5,Color("d8453a"))
	_px(img,14,25,Color("d8453a"));_px(img,17,25,Color("d8453a"))

static func _flower_arch(img:Image) -> void:
	_r(img,2,29,9,2,SHADOW);_r(img,21,29,9,2,SHADOW)
	var bamboo:=Color("9bb66e")
	var node:=Color("6f8a48")
	# Uprights.
	for x in [5,25]:
		_r(img,x,14,2,15,bamboo)
		for y in [17,22,27]:_r(img,x,y,2,1,node)
	# Half-circle top (2px thick).
	for i in 41:
		var t:=PI*float(i)/40.0
		var x:=int(round(16.0-10.5*cos(t)))
		var y:=int(round(14.0-11.0*sin(t)))
		_r(img,x-1,y,2,2,bamboo)
	# Leaves along the arch and uprights.
	for leaf:Array in [[4,9],[7,5],[12,2],[19,2],[24,5],[27,9],[3,18],[27,20],[4,24],[26,25]]:
		_r(img,leaf[0],leaf[1],2,2,Color("4f8a36"))
		_px(img,leaf[0]+1,leaf[1],Color("7fbf5a"))
	# Flowers: pink, white, yellow.
	for bloom:Array in [[6,7,"e98ca8"],[10,3,"fff4d8"],[16,2,"f2d06b"],[22,3,"e98ca8"],[26,7,"fff4d8"],[5,13,"f2d06b"],[26,15,"e98ca8"],[5,21,"fff4d8"],[25,23,"f2d06b"]]:
		var c:=Color(bloom[2])
		_r(img,bloom[0]-1,bloom[1],3,1,c);_r(img,bloom[0],bloom[1]-1,1,3,c)
		_px(img,bloom[0],bloom[1],Color("e0913e") if c!=Color("f2d06b") else Color("c0653f"))
	_r(img,3,28,6,3,Color("7a5a3a"));_r(img,23,28,6,3,Color("7a5a3a"))

static func _trio_keepsake(img:Image) -> void:
	_r(img,4,29,25,2,SHADOW)
	_post(img,8,21,9);_post(img,22,21,9)
	_boxed(img,2,7,28,16,Color("ead4a0"),Color("4a3020"))
	_r(img,3,8,26,1,Color("c89a5a"))
	_r(img,3,21,26,1,Color("c89a5a"))
	_px(img,2,7,Color(0,0,0,0));_px(img,29,7,Color(0,0,0,0))
	# Glyph 1: basket with a radish and a leaf.
	_r(img,6,11,2,2,Color("5f9e3e"))
	_disc(img,8,13,1,Color("e0505a"),Color("a03030"),false)
	_r(img,4,14,8,5,Color("6e4f24"));_r(img,5,15,6,3,Color("d9b56a"))
	# Glyph 2: carp.
	_r(img,13,14,5,4,Color("d98b45"));_r(img,14,13,3,6,Color("d98b45"))
	_r(img,18,13,2,6,Color("c0703a"))
	_px(img,14,14,Color("3c3a36"))
	# Glyph 3: amber lantern.
	_r(img,22,12,6,1,Color("3a2a1e"));_r(img,22,19,6,1,Color("3a2a1e"))
	_r(img,22,13,6,6,Color("f6c36b"));_r(img,21,14,8,4,Color("f6c36b"))
	_r(img,24,13,2,6,Color("c8453a"))
	# Red rosette on top.
	_r(img,13,6,2,5,Color("b03a30"));_r(img,17,6,2,5,Color("b03a30"))
	_disc(img,16,4,3,Color("d8453a"),Color("7a2420"),false)
	_r(img,15,3,2,2,Color("f0c048"))

## 紀念品交換攤 (48×56): navy-and-gold striped awning (the market stall is green and
## cream, 小栗's shop red and cream) with a coloured bunting, a
## counter carrying three tiny souvenirs (amber lantern, carp flag, veg basket) and a
## big yellow ticket painted on its front. Feet on the bottom row (drawn at
## cell + (-8,-24) so it stands on its tile). Static.
static func booth() -> Texture2D:
	if cache.has("booth"):return cache["booth"]
	var img:=Image.create_empty(48,56,false,Image.FORMAT_RGBA8)
	img.fill(Color(0,0,0,0))
	_r(img,1,52,46,4,SHADOW)
	# Posts.
	_r(img,3,12,3,42,POLE);_r(img,4,12,1,42,POLE_LIGHT)
	_r(img,42,12,3,42,POLE);_r(img,43,12,1,42,POLE_LIGHT)
	# Awning: stripes, dark trim, scalloped edge.
	_r(img,0,2,48,2,Color("1f3354"))
	for i in 6:
		var c:=Color("35588f") if i%2==0 else Color("f2c94c")
		_r(img,i*8,4,8,10,c)
		_r(img,i*8+1,14,6,2,c)
		_r(img,i*8+2,16,4,1,c)
	_r(img,0,4,48,1,Color("8fb0d8"))
	for i in 6:_px(img,i*8,14,Color("1f3354"));_px(img,i*8+7,14,Color("1f3354"))
	# Bunting between the posts.
	var flags:=["d8453a","f2cf4a","4f86b8","5fb38a","d8453a","f2cf4a"]
	_r(img,6,19,36,1,Color("8a7650"))
	for i in 6:
		var x:=7+i*6
		var c:=Color(flags[i])
		_r(img,x,20,5,1,c);_r(img,x+1,21,3,1,c);_r(img,x+2,22,1,1,c)
	# Souvenirs on the counter.
	_r(img,9,24,1,2,Color("3a2a1e"))
	_r(img,7,26,5,6,Color("f6c36b"));_r(img,6,27,7,4,Color("f6c36b"))
	_r(img,7,26,5,1,Color("3a2a1e"));_r(img,7,31,5,1,Color("3a2a1e"))
	_r(img,9,27,1,4,Color("c8453a"))
	_r(img,18,22,1,10,POLE)
	_r(img,19,22,7,6,Color("f4ead2"));_r(img,19,22,7,1,Color("4f86b8"))
	_r(img,20,24,4,2,Color("d98b45"));_px(img,24,24,Color("c0703a"));_px(img,20,24,Color("3c3a36"))
	_disc(img,31,26,2,Color("e0505a"),Color("7a2a2a"),false)
	_r(img,34,24,3,3,Color("7fbf5a"))
	_r(img,29,27,10,5,Color("6e4f24"));_r(img,30,28,8,3,Color("d9b56a"))
	# Counter.
	_boxed(img,0,31,48,5,Color("d9a866"),Color("4a3020"))
	_r(img,1,32,46,1,Color("efc98f"))
	_boxed(img,2,35,44,18,Color("b07a4a"),Color("4a3020"))
	_r(img,3,41,42,1,Color("8a5c30"));_r(img,3,47,42,1,Color("8a5c30"))
	# Yellow ticket on the counter front (notched ends, perforation, red star).
	_boxed(img,13,38,22,12,Color("f2cf4a"),Color("8a6a20"))
	_r(img,13,43,2,3,Color("b07a4a"));_r(img,33,43,2,3,Color("b07a4a"))
	for y in range(40,49,2):_px(img,18,y,Color("8a6a20"))
	_r(img,24,41,3,6,Color("d8453a"));_r(img,22,43,7,2,Color("d8453a"))
	_px(img,25,40,Color("d8453a"));_px(img,25,47,Color("d8453a"))
	var texture:=ImageTexture.create_from_image(img)
	cache["booth"]=texture
	return texture
