@static_unload
extends RefCounted
## T066 第三批：居民紀念小物（十二件，一位居民一件）的像素圖（程式繪製，沒有新美術檔）。
##
## 每件一張 32×32 圖（piece(kind) 快取），同一張圖用在兩個地方：
##  * 世界與建造目錄縮圖：FurnitureSpriteArt.draw_sprite / world_view 轉來 draw()，圖的
##    左上角對齊格子左上角，腳（陰影）落在格子下緣 —— 與 souvenir_art.gd 相同；
##  * 背包圖示：InventoryItemArt.icon 轉來 icon("<kind>_kit")。
## 全部靜態（任何動態模式都不動）。規則與名稱在 resident_goals.gd 的 KEEPSAKES；這裡
## 刻意不 preload 它（KINDS 寫死，測試比對 KEEPSAKE_ORDER）。
##
##   keepsake_aru       兩根短樁上釘著一塊有點歪的淺色木板（木紋、節疤、釘頭），樁腳有草
##   keepsake_milu      小木凳上疊著三只米白碗，每只碗口一圈藍線
##   keepsake_bobo      平石板上用灰、褐石頭排成的小島，最上面一顆像帽子，旁邊一撮綠草
##   keepsake_chacha    小木架下用麻繩串著四片長短不一的舊竹片（黃綠色、竹節線）
##   keepsake_achao     深色粗繫船樁（淺色磨亮的樁頭）上掛著盤好的麻色纜繩，繩尾垂到地上
##   keepsake_mianmian  小竹籃裡坐著粉色／米白的布球娃娃，額頭一道歪歪的縫線
##   keepsake_xinghe    小畫架上的畫板，釘著四格花圃圖：三格畫了粉、黃、藍小花，右下一格空白
##   keepsake_lingpopo  木製牌坊架下吊著一枚青銅小鈴，鈴身一圈青綠色帶，下垂紅流蘇
##   keepsake_xiaoli    短樁上的試寫木片：深色重描的抽象筆畫（不是可讀的字）與一顆栗色圓點
##   keepsake_luoluo    柱上的灰青綠小信箱，投信口露出米白信封一角與小紅封蠟，側邊紅色小旗
##   keepsake_diandian  摺疊 A 字畫架夾著一張速寫（鉛筆灰的一雙放鬆的手），畫架托板上一支鉛筆
##   keepsake_nuannuan  短柱上的門牌（深色木框、米白牌面），框頂右側一盞亮著的暖黃小燈與微光

const KINDS:=["keepsake_aru","keepsake_milu","keepsake_bobo","keepsake_chacha","keepsake_achao","keepsake_mianmian","keepsake_xinghe","keepsake_lingpopo","keepsake_xiaoli","keepsake_luoluo","keepsake_diandian","keepsake_nuannuan","keepsake_aru_bird","keepsake_achao_oar","keepsake_xinghe_sign","keepsake_lingpopo_memorial","keepsake_nuannuan_room"]
const KIT_SUFFIX:="_kit"
const SHADOW:=Color(0.18,0.13,0.08,0.3)
const OUTLINE:=Color("3e2a1a")
const WOOD_DARK:=Color("5a3d24")
const WOOD:=Color("8a6a3e")
const WOOD_LIGHT:=Color("c79a5e")
const WOOD_HI:=Color("e0b880")
const POLE:=Color("6b4a2f")
const POLE_LIGHT:=Color("8d6440")
const CREAM:=Color("f4ead2")
const LEAF:=Color("4f8a36")
const LEAF_LIGHT:=Color("7fbf5a")
const ROPE:=Color("d2b07a")
const ROPE_HI:=Color("ead0a0")
const ROPE_TWIST:=Color("b08a52")
const ROPE_EDGE:=Color("6e5430")
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

## Filled disc with a 1px outline and a small highlight (stones, chestnut, doll head).
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

## Short stake (4 px wide, outlined) with a lit right side and light end grain on top.
static func _stake(img:Image,x:int,y:int,h:int) -> void:
	_boxed(img,x,y,4,h,POLE,OUTLINE)
	_r(img,x+2,y+1,1,h-2,POLE_LIGHT)
	_r(img,x+1,y+1,2,1,WOOD_LIGHT)

## Straight line, `w` pixels wide on every row it crosses.
static func _line(img:Image,x0:int,y0:int,x1:int,y1:int,c:Color,w:int) -> void:
	var n:=maxi(absi(x1-x0),absi(y1-y0))
	for i in n+1:
		var t:=float(i)/float(maxi(n,1))
		_r(img,int(round(lerpf(float(x0),float(x1),t))),int(round(lerpf(float(y0),float(y1),t))),w,1,c)

## Outlined easel leg (dark 3 px line with a light 1 px core).
static func _leg(img:Image,x0:int,y0:int,x1:int,y1:int) -> void:
	_line(img,x0,y0,x1,y1,WOOD_DARK,3)
	_line(img,x0+1,y0,x1+1,y1,WOOD_LIGHT,1)

## Pixel pattern: one String per row, each character looked up in `colors` (others skipped).
static func _pattern(img:Image,x:int,y:int,rows:Array,colors:Dictionary,flip:=false) -> void:
	for j in rows.size():
		var row:String=rows[j]
		for i in row.length():
			var ch:String=row[i]
			if colors.has(ch):
				var c:Color=colors[ch]
				_px(img,x+(row.length()-1-i if flip else i),y+j,c)

## One loop of a hung rope coil (elliptical ring with edges, twist marks and a lit top).
static func _rope_ring(img:Image,cx:float,cy:float,rx:float,ry:float) -> void:
	for y in range(int(cy-ry)-1,int(cy+ry)+2):
		for x in range(int(cx-rx)-1,int(cx+rx)+2):
			var d:float=pow((float(x)-cx)/rx,2.0)+pow((float(y)-cy)/ry,2.0)
			if d>1.0 or d<0.38:continue
			var c:Color=ROPE
			if d>0.8 or d<0.48:c=ROPE_EDGE
			elif (x+2*y)%4==0:c=ROPE_TWIST
			elif float(y)<cy-ry*0.45:c=ROPE_HI
			_px(img,x,y,c)

## Tiny planned flower: plus-shaped petals, orange centre, green stem.
static func _flower(img:Image,x:int,y:int,c:Color) -> void:
	_px(img,x-1,y,c);_px(img,x+1,y,c);_px(img,x,y-1,c)
	_px(img,x,y,Color("e0913e"))
	_px(img,x,y+1,LEAF);_px(img,x,y+2,LEAF)

## One cream bowl (rows y..y+4) with a blue rim line; `open` also draws the visible inside.
static func _bowl(img:Image,cx:int,y:int,open:bool) -> void:
	var edge:=Color("7a6a50")
	if open:
		_r(img,cx-6,y-2,12,1,edge)
		_r(img,cx-7,y-1,14,1,edge)
		_r(img,cx-6,y-1,12,1,Color("e2d3ad"))
	_r(img,cx-8,y,16,1,edge);_r(img,cx-7,y,14,1,Color("4f86b8"))
	_r(img,cx-8,y+1,16,1,edge);_r(img,cx-7,y+1,14,1,CREAM)
	_r(img,cx-5,y+1,3,1,Color("fffaf0"))
	_r(img,cx-7,y+2,14,1,edge);_r(img,cx-6,y+2,12,1,CREAM)
	_r(img,cx-6,y+3,12,1,edge);_r(img,cx-5,y+3,10,1,Color("d8cba8"))
	_r(img,cx-4,y+4,8,1,edge)

# -------------------------------------------------------------------- art --

## The 32×32 picture of a keepsake (cached); null for unknown kinds.
static func piece(kind:String) -> Texture2D:
	if not kind in KINDS:return null
	if cache.has(kind):return cache[kind]
	if kind=="keepsake_lingpopo_memorial":
		cache[kind]=ImageTexture.create_from_image(preload("res://assets/ui-inventory/memorial-bell-reward.png").get_image())
		return cache[kind]
	if kind=="keepsake_xinghe_sign":
		cache[kind]=ImageTexture.create_from_image(preload("res://assets/ui-inventory/xinghe-garden-sign.png").get_image())
		return cache[kind]
	if kind=="keepsake_achao_oar":
		cache[kind]=ImageTexture.create_from_image(preload("res://assets/ui-inventory/achao-oar.png").get_image())
		return cache[kind]
	if kind=="keepsake_aru_bird":
		cache[kind]=ImageTexture.create_from_image(preload("res://assets/ui-inventory/aru-wood-bird.png").get_image())
		return cache[kind]
	var img:=Image.create_empty(32,32,false,Image.FORMAT_RGBA8)
	img.fill(Color(0,0,0,0))
	match kind:
		"keepsake_aru":_aru(img)
		"keepsake_milu":_milu(img)
		"keepsake_bobo":_bobo(img)
		"keepsake_chacha":_chacha(img)
		"keepsake_achao":_achao(img)
		"keepsake_mianmian":_mianmian(img)
		"keepsake_xinghe":_xinghe(img)
		"keepsake_lingpopo":_lingpopo(img)
		"keepsake_xiaoli":_xiaoli(img)
		"keepsake_luoluo":_luoluo(img)
		"keepsake_diandian":_diandian(img)
		"keepsake_nuannuan":_nuannuan(img)
		"keepsake_nuannuan_room":_nuannuan_room(img)
	var texture:=ImageTexture.create_from_image(img)
	cache[kind]=texture
	return texture

## Top row of the crooked plank at column x (rises 4 px from left to right).
static func _aru_top(x:int) -> int:
	return 15+int(float(x-3)*4.0/25.0)

static func _aru(img:Image) -> void:
	_r(img,3,29,26,2,SHADOW)
	_stake(img,6,12,19)
	_stake(img,21,13,18)
	for g:Array in [[4,28],[5,27],[10,28],[19,28],[25,28],[26,27]]:_px(img,g[0],g[1],LEAF);_px(img,g[0],g[1]+1,LEAF_LIGHT)
	# The plank, column by column so it sits a little crooked.
	var plank:=Color("dcbc84")
	var grain:=Color("a8834e")
	for x in range(3,29):
		var ty:=_aru_top(x)
		_r(img,x,ty,1,7,OUTLINE)
		if x==3 or x==28:continue
		_r(img,x,ty+1,1,5,plank)
		_px(img,x,ty+1,Color("f0d8a8"))
		_px(img,x,ty+5,Color("b8945c"))
		if (x>=5 and x<=11) or (x>=16 and x<=25):_px(img,x,ty+3,grain)
		elif x>=12 and x<=15:_px(img,x,ty+2,grain)
	# A knot in the grain.
	var k:=_aru_top(19)
	_px(img,19,k+3,Color("7a5530"));_px(img,18,k+3,Color("c8a068"));_px(img,20,k+3,Color("c8a068"))
	# Nail heads over each stake.
	for nx:int in [8,23]:
		var t:=_aru_top(nx)
		for ny:int in [t+2,t+4]:
			_px(img,nx,ny,Color("4a4a52"));_px(img,nx-1,ny,Color("a8a8b4"))

static func _milu(img:Image) -> void:
	_r(img,4,29,24,2,SHADOW)
	# Stool legs and stretcher, then the seat.
	for lx:int in [8,21]:
		_r(img,lx,22,3,9,WOOD_DARK)
		_r(img,lx+1,22,1,8,WOOD)
	_r(img,11,26,10,2,WOOD_DARK);_r(img,11,26,10,1,WOOD)
	_boxed(img,6,19,20,4,WOOD_LIGHT,WOOD_DARK)
	_r(img,7,20,18,1,WOOD_HI)
	# Three nested bowls: top one first so each lower rim sits in front of the one above.
	_bowl(img,17,8,true)
	_bowl(img,16,11,false)
	_bowl(img,16,14,false)

static func _bobo(img:Image) -> void:
	_r(img,2,29,28,2,SHADOW)
	# Flat slab.
	_boxed(img,3,25,26,5,Color("9a948a"),Color("4a4640"))
	_r(img,4,26,24,1,Color("bdb7aa"))
	_r(img,4,28,24,1,Color("7e786e"))
	# Bottom ring of stones.
	_disc(img,8,22,4,Color("8c8478"),Color("3e3a34"))
	_disc(img,23,22,4,Color("9a8a72"),Color("4a3e30"))
	_disc(img,15,21,5,Color("a39c8e"),Color("3e3a34"))
	# Second tier.
	_disc(img,12,16,3,Color("7e7a72"),Color("34302c"))
	_disc(img,19,16,3,Color("a08a6a"),Color("4a3a28"))
	# Hat-shaped top stone: crown and brim.
	var hat:=Color("8a7a66")
	var hat_edge:=Color("3e3428")
	_boxed(img,13,6,7,6,hat,hat_edge)
	_boxed(img,10,11,13,3,hat,hat_edge)
	_r(img,14,7,2,2,Color("b3a48c"))
	_r(img,14,10,5,1,Color("6e5e4c"))
	_r(img,11,12,3,1,Color("a8987e"))
	# Tiny green tuft growing out of the right stone.
	_r(img,26,16,1,3,LEAF)
	_px(img,25,15,LEAF_LIGHT);_px(img,27,15,LEAF_LIGHT);_px(img,27,17,LEAF)

static func _chacha(img:Image) -> void:
	_r(img,2,29,28,2,SHADOW)
	# Small wooden frame.
	_post(img,4,5,24)
	_post(img,26,5,24)
	_boxed(img,2,27,6,4,WOOD,WOOD_DARK)
	_boxed(img,24,27,6,4,WOOD,WOOD_DARK)
	_boxed(img,2,3,28,3,WOOD_LIGHT,WOOD_DARK)
	_r(img,3,4,8,1,WOOD_HI)
	# Four old bamboo slats of uneven length, each hung on a twine loop.
	var twine:=Color("c9b58a")
	var twine_dark:=Color("8a7650")
	for s:Array in [[7,9,15],[12,8,17],[17,10,14],[22,9,16]]:
		var x:int=s[0]
		var top:int=s[1]
		var h:int=s[2]
		_r(img,x+1,6,1,top-6,twine)
		_boxed(img,x,top,4,h,Color("c4be62"),Color("6f7436"))
		_r(img,x+1,top+1,1,h-2,Color("e2dc9a"))
		for n:int in [top+4,top+10]:_r(img,x+1,n,2,1,Color("8f9448"))
		_px(img,x+2,top+7,Color("a89a5a"))
	# Two twine lines strung through all four slats, knotted at each slat edge.
	for y:int in [12,20]:
		_r(img,6,y,20,1,twine)
		for x:int in [7,12,17,22]:_px(img,x,y,twine_dark);_px(img,x+3,y,twine_dark)

static func _achao(img:Image) -> void:
	_r(img,5,29,22,2,SHADOW)
	# Stout dark mooring post.
	var edge:=Color("2e2018")
	_boxed(img,11,8,10,23,Color("5a4030"),edge)
	_r(img,12,9,2,21,Color("7a5a40"))
	_r(img,18,9,2,21,Color("45301f"))
	for g:Array in [[15,12,4],[16,20,5],[14,25,3]]:_r(img,g[0],g[1],1,g[2],Color("4a3426"))
	# Wider head with a lighter, worn top.
	_boxed(img,9,4,14,5,Color("8a6a48"),edge)
	_r(img,10,5,12,2,Color("c49a68"))
	_r(img,11,5,5,1,Color("e0bc88"))
	# Rope over the post and the hung coil (three loops).
	_boxed(img,13,8,6,3,ROPE,ROPE_EDGE)
	_rope_ring(img,15.0,16.5,7.5,5.5)
	_rope_ring(img,16.0,18.0,7.5,5.5)
	_rope_ring(img,17.0,19.5,7.5,5.5)
	# Loose rope end trailing down to the ground, frayed tip.
	for i in 6:
		_r(img,21+i/2,24+i,2,1,ROPE)
		_px(img,23+i/2,24+i,ROPE_EDGE)
	_px(img,23,30,ROPE_HI);_px(img,25,30,ROPE_HI);_px(img,24,30,ROPE_TWIST)

static func _mianmian(img:Image) -> void:
	_r(img,4,29,24,2,SHADOW)
	var pink:=Color("eeaab8")
	var pink_edge:=Color("8a4a5a")
	# Cloth ears, then the round head of the ball-doll.
	_boxed(img,10,4,4,4,pink,pink_edge)
	_boxed(img,19,4,4,4,pink,pink_edge)
	_px(img,11,5,Color("f8d0d8"));_px(img,20,5,Color("f8d0d8"))
	_disc(img,16,11,6,pink,pink_edge)
	# Cream face patch, eyes, blush.
	_r(img,12,10,9,5,Color("f6ead0"))
	_px(img,14,11,Color("3c3036"));_px(img,18,11,Color("3c3036"))
	_px(img,13,13,Color("e07888"));_px(img,19,13,Color("e07888"))
	# The crooked stitch seam across the forehead.
	for p:Array in [[11,9],[12,8],[13,9],[14,8],[15,7],[16,8],[17,8],[18,7],[19,8],[20,9],[21,8]]:_px(img,p[0],p[1],Color("7a3a4a"))
	# Woven bamboo basket (2×2 checker weave) with a light rim.
	var weave_a:=Color("d9b56a")
	var weave_b:=Color("b8914a")
	var basket_edge:=Color("6e4f24")
	_r(img,5,19,22,11,basket_edge)
	for y in range(20,29):
		for x in range(6,26):
			_px(img,x,y,weave_a if ((x/2)+(y/2))%2==0 else weave_b)
	_boxed(img,4,17,24,3,Color("e8c97e"),basket_edge)
	_r(img,5,18,6,1,Color("f6e2a8"))
	# Little cloth arms resting on the rim.
	_boxed(img,7,16,5,3,pink,pink_edge)
	_boxed(img,20,16,5,3,pink,pink_edge)

static func _xinghe(img:Image) -> void:
	_r(img,4,29,24,2,SHADOW)
	# Easel: back leg, then two splayed front legs.
	_r(img,15,18,2,13,POLE)
	_leg(img,9,18,5,30)
	_leg(img,22,18,25,30)
	# Drawing board with the pinned plan.
	_boxed(img,5,3,22,18,Color("b88a54"),WOOD_DARK)
	_r(img,6,4,20,1,WOOD_HI)
	_boxed(img,7,5,18,14,Color("f6efdc"),Color("a89878"))
	var grid:=Color("8fa0b8")
	_r(img,15,6,1,12,grid)
	_r(img,8,11,16,1,grid)
	_px(img,9,5,Color("d8453a"));_px(img,22,5,Color("d8453a"))
	# Three planted cells (pink, yellow, blue); the bottom-right cell stays blank.
	for f:Array in [[10,8,"e98ca8"],[13,8,"e98ca8"],[18,8,"f2d06b"],[21,8,"f2d06b"],[10,14,"6f9fd8"],[13,14,"6f9fd8"]]:
		_flower(img,f[0],f[1],Color(f[2]))
	# Ledge.
	_boxed(img,4,20,24,3,WOOD_LIGHT,WOOD_DARK)
	_r(img,5,21,8,1,WOOD_HI)

static func _lingpopo(img:Image) -> void:
	_r(img,2,29,28,2,SHADOW)
	# Wooden arch stand: two posts on feet, a beam with upturned ends.
	_boxed(img,3,6,4,24,POLE,OUTLINE)
	_r(img,5,7,1,22,POLE_LIGHT)
	_boxed(img,25,6,4,24,POLE,OUTLINE)
	_r(img,27,7,1,22,POLE_LIGHT)
	_boxed(img,1,27,8,4,WOOD,WOOD_DARK)
	_boxed(img,23,27,8,4,WOOD,WOOD_DARK)
	_boxed(img,1,4,30,3,WOOD,WOOD_DARK)
	_r(img,2,5,28,1,WOOD_LIGHT)
	_r(img,1,3,2,1,WOOD_DARK);_r(img,29,3,2,1,WOOD_DARK)
	_r(img,15,7,2,3,Color("3a2a1e"))
	# Bronze bell.
	var edge:=Color("5a3a14")
	var bronze:=Color("b8863a")
	var rows:=[[10,4],[11,6],[12,8],[13,8],[14,8],[15,10],[16,10],[17,10],[18,10],[19,12],[20,12],[21,14]]
	_r(img,14,9,4,1,edge)
	for row:Array in rows:
		var w:int=row[1]
		_r(img,16-w/2-1,row[0],w+2,1,edge)
	for row:Array in rows:
		var y:int=row[0]
		var w:int=row[1]
		_r(img,16-w/2,y,w,1,bronze)
		_px(img,16-w/2,y,Color("e0b060"))
		_px(img,16+w/2-1,y,Color("8a5a20"))
		if w>=10:_px(img,16+w/2-2,y,Color("9a6a2a"))
	_r(img,13,12,1,3,Color("f0c878"))
	# The visitor's colour: a teal band around the bell.
	_r(img,11,15,10,2,Color("3a9a94"))
	_r(img,11,15,2,1,Color("7cc8c0"))
	_px(img,20,15,Color("24706c"));_px(img,20,16,Color("24706c"))
	_r(img,9,21,14,1,Color("8a5a20"))
	_r(img,8,22,16,1,edge)
	_r(img,15,23,2,1,Color("4a3010"))
	# Red tassel.
	_r(img,14,24,4,1,Color("c8453a"))
	_r(img,14,25,4,4,Color("d8453a"))
	_px(img,15,26,Color("9a2a24"));_px(img,15,27,Color("9a2a24"));_px(img,17,27,Color("9a2a24"));_px(img,16,28,Color("9a2a24"))

static func _xiaoli(img:Image) -> void:
	_r(img,9,29,14,2,SHADOW)
	_stake(img,14,16,15)
	# Trial signboard with trimmed corners, light top and shaded bottom edge.
	var clear:=Color(0,0,0,0)
	_boxed(img,3,5,26,13,Color("dcb47a"),WOOD_DARK)
	_px(img,3,5,clear);_px(img,28,5,clear);_px(img,3,17,clear);_px(img,28,17,clear)
	_r(img,4,6,24,1,Color("efd2a0"))
	_r(img,4,16,24,1,Color("b88c58"))
	var grain:=Color("c49a62")
	for y:int in [9,12,14]:
		_r(img,5,y,9,1,grain)
		_r(img,17,y,9,1,grain)
	# Abstract brush strokes, retraced: a faint first pass under the dark ink.
	var ghost:=Color("9c8064")
	var ink:=Color("2e2622")
	_r(img,7,10,8,1,ghost)
	_r(img,12,11,1,5,ghost)
	_line(img,17,9,21,15,ghost,1)
	_r(img,6,8,8,2,ink);_px(img,14,9,ink)
	_r(img,10,10,2,6,ink);_px(img,9,15,ink)
	_line(img,16,8,20,14,ink,2)
	_r(img,17,12,5,1,ink)
	# Chestnut-brown dot with a darker point.
	_disc(img,24,12,2,Color("8a4a24"),Color("4a2410"))
	_px(img,24,9,Color("4a2410"))

static func _luoluo(img:Image) -> void:
	_r(img,8,29,17,2,SHADOW)
	# Post and base.
	_boxed(img,14,18,5,11,POLE,OUTLINE)
	_r(img,16,19,1,9,POLE_LIGHT)
	_boxed(img,11,27,11,4,WOOD,WOOD_DARK)
	_r(img,12,28,9,1,WOOD_LIGHT)
	# Muted blue-green mailbox with a rounded top.
	var dark:=Color("2a4a44")
	var lit:=Color("86b8a8")
	var shade:=Color("4a7e72")
	_r(img,6,8,20,12,dark)
	_r(img,7,8,18,11,Color("5f9a8c"))
	_r(img,8,6,16,1,dark)
	_r(img,7,7,18,1,dark)
	_r(img,8,7,16,1,lit)
	_r(img,7,8,1,10,lit)
	_r(img,23,8,2,11,shade)
	# Envelope corner sticking out of the slot, with its flap lines and a tiny red seal.
	_boxed(img,11,9,9,4,CREAM,Color("9a8a6a"))
	var flap:=Color("c8b890")
	_px(img,12,10,flap);_px(img,13,11,flap);_px(img,17,11,flap);_px(img,18,10,flap)
	_r(img,14,10,2,2,Color("c8453a"));_px(img,14,10,Color("e87a6a"))
	_r(img,9,12,14,2,Color("1e3430"))
	# Brass latch and a little red flag on the side.
	_r(img,14,15,4,2,Color("c9a64a"));_px(img,14,15,Color("f0d27a"))
	_r(img,26,9,1,7,Color("3a2a1e"))
	_r(img,27,9,3,2,Color("d8453a"));_px(img,27,9,Color("f08070"))

static func _diandian(img:Image) -> void:
	_r(img,5,29,22,2,SHADOW)
	# Folding A-frame easel: two legs, hinge on top, brace below.
	_leg(img,13,3,6,30)
	_leg(img,18,3,25,30)
	_r(img,8,25,16,1,WOOD_DARK)
	_boxed(img,13,1,6,3,WOOD_LIGHT,WOOD_DARK)
	# Clipped sketch paper.
	_boxed(img,8,5,16,15,Color("f6efdc"),Color("8a7a60"))
	_r(img,14,4,4,2,Color("7a7a82"));_px(img,14,4,Color("c8c8d0"))
	# Pencil-grey sketch of two relaxed hands (one mirrored).
	var hand:=["..##...",".#..#..","#....#.","#.....#","#..+..#",".#.+.#.",".#...#.","..#.#..","..#.#.."]
	var colors:={"#":Color("6a6a72"),"+":Color("a8a8b0")}
	_pattern(img,9,8,hand,colors)
	_pattern(img,16,9,hand,colors,true)
	# Ledge with a pencil resting on it.
	_boxed(img,7,20,18,3,WOOD_LIGHT,WOOD_DARK)
	_r(img,10,18,9,1,Color("f6d870"))
	_r(img,10,19,9,1,Color("d8a830"))
	_r(img,9,18,1,2,Color("e98ca8"))
	_r(img,10,18,1,2,Color("a8a8b0"))
	_r(img,19,18,1,2,Color("e8c8a0"))
	_px(img,20,19,Color("3a3a3a"))

static func _nuannuan_room(img:Image) -> void:
	_r(img,4,28,24,2,SHADOW)
	_boxed(img,7,22,18,7,WOOD,OUTLINE)
	_r(img,8,27,16,1,WOOD_LIGHT)
	_boxed(img,4,9,24,15,Color("46796b"),Color("322f2c"))
	_r(img,6,10,20,1,Color("9fbc9e"))
	_boxed(img,7,12,18,9,Color("f3ddb0"),Color("325c54"))
	_r(img,9,15,4,1,Color("534536"))
	_r(img,9,17,7,1,Color("534536"))
	_r(img,17,15,4,1,Color("534536"))
	_r(img,18,17,4,1,Color("a45d42"))
	for x in [12,18]:
		_px(img,x,5,Color("fcf0d1"))
		_px(img,x+1,6,Color("fcf0d1"))
		_px(img,x,7,Color("cfddbe"))

static func _nuannuan(img:Image) -> void:
	_r(img,6,29,20,2,SHADOW)
	# Short post on a base.
	_boxed(img,10,19,5,12,POLE,OUTLINE)
	_r(img,12,20,1,10,POLE_LIGHT)
	_boxed(img,7,27,11,4,WOOD,WOOD_DARK)
	_r(img,8,28,9,1,WOOD_LIGHT)
	# Doorplate: dark frame, cream plate, abstract name marks (not readable text).
	_r(img,2,11,22,10,Color("3a2618"))
	_r(img,3,12,20,8,Color("7a5232"))
	_r(img,3,12,20,1,Color("9a7048"))
	_r(img,4,13,18,6,CREAM)
	_r(img,4,18,18,1,Color("e2d3ad"))
	var mark:=Color("6e5a44")
	_r(img,6,14,4,1,mark);_r(img,11,14,5,1,mark);_r(img,7,16,9,1,mark)
	_px(img,18,16,Color("c8453a"))
	_r(img,15,13,6,1,Color("fff8e4"))
	# Small lamp standing on the frame, lit warm yellow.
	_r(img,19,3,4,1,Color("3a2a1e"))
	_r(img,18,4,6,1,WOOD_DARK)
	_boxed(img,18,5,6,5,Color("ffd66b"),Color("6e4a1e"))
	_r(img,20,6,2,3,Color("fff6d0"))
	_r(img,18,10,6,1,WOOD_DARK)
	# Soft glow: a few lighter, half-transparent pixels around the lamp.
	var glow:=Color(1.0,0.93,0.6,0.6)
	for g:Array in [[17,6],[17,7],[16,7],[24,6],[24,7],[25,7],[20,2],[21,2]]:_px(img,g[0],g[1],glow)
