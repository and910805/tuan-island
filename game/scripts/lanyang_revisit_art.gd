@static_unload
extends RefCounted
## 第 40 章「蘭陽回訪」的像素圖：
##
##  * 分流閘 diversion_gate（家園水網的一格）：先畫底下的銅水管（IndustryArt.pipe_texture，
##    與一般水管同樣依鄰格連接），再疊上木造閘框。三種設定一眼可分：
##      open   全開：閘板拉到頂，閘框中間整片藍色水流與白色波紋，右上綠色小旗；
##      low    餘水：閘板放到一半，只剩下方一道淺藍細水，右上琥珀色半圓牌；
##      closed 關閉：深色閘板放到底（X 形撐木），沒有水，閘板中間一條紅色封條，右上紅色小牌。
##    world_view.object_sprite 畫（預覽美術與一般繪製都畫），家園工坊縮圖用同一條路徑
##    （object_data 為空 → 左右相連、全開）。全部靜態，任何動態模式都不動。
##  * 分水木牌 water_share_plaque：淺色檜木圓角牌立在兩根短木樁上，牌面刻一道藍色水路
##    在中間分成三道水口（像「山」字倒過來），下緣三個深藍水口；左下一小撮秧苗。
##    與既有告示牌（橋邊配水紀念牌也用告示牌圖）、木板圖示、三活動紀念牌都不同。
##  * 背包圖示：diversion_gate_kit＝餘水模式閘框＋兩端銅管接頭；water_share_plaque_kit＝木牌圖。
const IndustryArt=preload("res://scripts/industry_art.gd")
const MODES:=["open","low","closed"]
const SHADOW:=Color(0.18,0.13,0.08,0.3)
const POST:=Color("5a3d24")
const POST_LIGHT:=Color("8a6a3e")
const BEAM:=Color("6b4a2f")
const BOARD:=Color("c79a5e")
const BOARD_LIGHT:=Color("e2bd82")
const BOARD_DARK:=Color("8d6440")
const BOARD_CLOSED:=Color("9a6e40")
const STONE:=Color("8f8f86")
const STONE_LIGHT:=Color("b9b8ad")
const WATER:=Color("3f8fcf")
const WATER_LIGHT:=Color("bfe8f5")
const WATER_SOFT:=Color("79b9dc")
const WET:=Color("2f4f5f")
const FLAG_OPEN:=Color("5fae4a")
const FLAG_LOW:=Color("e0a33a")
const FLAG_CLOSED:=Color("c8483c")
const CEDAR:=Color("e6c891")
const CEDAR_LIGHT:=Color("f6e2b6")
const CEDAR_RIM:=Color("7a5530")
const CARVE:=Color("2f6fae")
const CARVE_DARK:=Color("1f4a7a")
const SPROUT:=Color("6fae4a")
static var cache:Dictionary={}

static func mode_of(obj:Dictionary) -> String:
	var mode:=str(obj.get("mode","open"))
	return mode if mode in MODES else "open"

# ----------------------------------------------------------------- helpers --

static func _r(img:Image,x:int,y:int,w:int,h:int,c:Color) -> void:
	var box:=Rect2i(x,y,w,h).intersection(Rect2i(0,0,img.get_width(),img.get_height()))
	if box.size.x>0 and box.size.y>0:img.fill_rect(box,c)

static func _px(img:Image,x:int,y:int,c:Color) -> void:
	if x>=0 and y>=0 and x<img.get_width() and y<img.get_height():img.set_pixel(x,y,c)

static func _blank() -> Image:
	var img:=Image.create_empty(32,32,false,Image.FORMAT_RGBA8)
	img.fill(Color(0,0,0,0))
	return img

# -------------------------------------------------------------------- gate --

## 32×32 gate frame for `mode` (transparent around it; the pipe is drawn underneath).
static func gate_texture(mode:String) -> Texture2D:
	if not mode in MODES:mode="open"
	var key:="gate:"+mode
	if cache.has(key):return cache[key]
	var img:=_blank()
	_gate(img,mode)
	cache[key]=ImageTexture.create_from_image(img)
	return cache[key]

static func _gate(img:Image,mode:String) -> void:
	# Stone footing and channel bed.
	_r(img,3,26,26,4,STONE)
	_r(img,3,26,26,1,STONE_LIGHT)
	_r(img,9,8,14,19,WET)
	# Water in the channel.
	if mode=="open":
		_r(img,9,9,14,18,WATER)
		for row:Array in [[10,11],[13,16],[11,20],[15,23]]:_r(img,int(row[0]),int(row[1]),5,1,WATER_LIGHT)
		_r(img,18,14,3,1,WATER_LIGHT)
	elif mode=="low":
		_r(img,9,17,14,10,WATER_SOFT)
		_r(img,10,19,5,1,WATER_LIGHT)
		_r(img,15,22,5,1,WATER_LIGHT)
		_r(img,11,25,4,1,WATER_LIGHT)
	# Gate board (sliding between the posts); the closed board is a darker, braced one.
	var board_bottom:int=int({"open":9,"low":16,"closed":26}[mode])
	var face:=BOARD if mode!="closed" else BOARD_CLOSED
	_r(img,9,5,14,board_bottom-4,face)
	_r(img,9,5,14,1,BOARD_LIGHT if mode!="closed" else face.lightened(0.2))
	for y in range(9,board_bottom,4):_r(img,9,y,14,1,BOARD_DARK)
	_r(img,9,board_bottom,14,1,BOARD_DARK)
	if mode=="closed":
		# X brace and a red seal strip across the closed board.
		for i in 14:
			for d in 2:
				_px(img,9+i,6+i+d,POST)
				_px(img,22-i,6+i+d,POST)
		_r(img,9,15,14,3,FLAG_CLOSED)
		_r(img,9,15,14,1,Color("e7867a"))
	# Two posts and the crossbeam with a hand wheel.
	for x in [5,23]:
		_r(img,x,3,4,25,POST)
		_r(img,x+1,3,1,25,POST_LIGHT)
	_r(img,4,2,24,4,BEAM)
	_r(img,4,2,24,1,POST_LIGHT)
	_r(img,14,0,4,2,POST)
	_r(img,15,0,2,1,POST_LIGHT)
	# Mode marker on the top-right post: green pennant / amber half disc / red square.
	match mode:
		"open":
			_r(img,27,0,1,6,POST)
			_r(img,28,0,4,3,FLAG_OPEN)
			_r(img,28,3,2,1,FLAG_OPEN)
		"low":
			_r(img,27,0,5,5,Color("6e4f24"))
			_r(img,28,1,3,3,FLAG_LOW)
			_r(img,28,3,3,1,Color("f6d48a"))
		"closed":
			_r(img,27,0,5,5,Color("5a1f1a"))
			_r(img,28,1,3,3,FLAG_CLOSED)
			_px(img,28,1,Color("f2b0a6"));_px(img,30,3,Color("f2b0a6"))
	_r(img,4,30,24,2,SHADOW)

## World / thumbnail: copper pipe joined like a water pipe (mask bits up/right/down/left),
## then the gate frame of `mode`. Static in every motion mode.
static func draw_gate(canvas:CanvasItem,at:Vector2,mode:String,mask:int=10) -> void:
	var pipe:=IndustryArt.pipe_texture(mask&15)
	if pipe!=null:canvas.draw_texture(pipe,at)
	canvas.draw_texture(gate_texture(mode),at)

# Public canal gate. Each leaf occupies a canal tile and has four heights.
static func fork_texture(upstream:int,middle:int) -> Texture2D:
	upstream=clampi(upstream,0,3)
	middle=clampi(middle,0,3)
	var key:="fork:%d:%d"%[upstream,middle]
	if cache.has(key):return cache[key]
	var img:=Image.create_empty(64,32,false,Image.FORMAT_RGBA8)
	_fork_leaf(img,0,upstream)
	_fork_leaf(img,32,middle)
	cache[key]=ImageTexture.create_from_image(img)
	return cache[key]

static func _fork_leaf(img:Image,x:int,level:int) -> void:
	var sill:=Color("4c5c4e")
	var stone:=Color("7e8871")
	var bevel:=Color("a9ad8d")
	var iron:=Color("433a2f")
	var moss:=Color("687c43")
	# River stones anchor the timber and split the current at the sill.
	for offset:int in [1,26]:
		_r(img,x+offset,19,5,12,SHADOW)
		_r(img,x+offset,17,5,12,sill)
		_r(img,x+offset+1,17,3,10,stone)
		_r(img,x+offset+1,17,3,1,bevel)
		_px(img,x+offset+1,23,moss)
	_r(img,x+5,24,22,3,sill)
	_r(img,x+5,24,22,1,bevel)
	var bottom:=23-level*4
	_r(img,x+5,7,22,bottom-6,POST)
	for y in range(8,bottom,4):
		_r(img,x+6,y,20,3,BOARD_DARK)
		_r(img,x+7,y,18,1,BOARD)
		_r(img,x+8+(y%3),y+1,5,1,BOARD_CLOSED)
	_r(img,x+7,8,2,bottom-7,BEAM)
	_r(img,x+23,8,2,bottom-7,BEAM)
	# Short runs of foam show the water emerging beneath the raised boards.
	if level>0:
		_r(img,x+11,bottom+1,6,1,WATER_LIGHT)
		_r(img,x+17,22,6,1,WATER_SOFT)
		_r(img,x+9,27,7,1,WATER_LIGHT)
		_r(img,x+18,29,4,1,WATER_SOFT)
	for offset:int in [4,25]:
		_r(img,x+offset,4,3,20,POST)
		_r(img,x+offset,5,1,17,POST_LIGHT)
	_r(img,x+3,4,26,4,POST)
	_r(img,x+4,4,24,1,BOARD)
	_r(img,x+12,2,8,3,iron)
	_r(img,x+14,1,4,2,bevel)
	_r(img,x+15,7,2,bottom-7,iron)
	_px(img,x+16,3,BOARD_LIGHT)

# ------------------------------------------------------------------ plaque --

static func plaque_texture() -> Texture2D:
	if cache.has("plaque"):return cache["plaque"]
	var img:=_blank()
	_plaque(img)
	cache["plaque"]=ImageTexture.create_from_image(img)
	return cache["plaque"]

static func _plaque(img:Image) -> void:
	_r(img,5,29,22,2,SHADOW)
	# Two short stakes.
	for x in [9,21]:
		_r(img,x,21,2,9,POST)
		_r(img,x,21,1,9,POST_LIGHT)
	# Rounded cedar board with a dark rim.
	_r(img,4,5,24,18,CEDAR_RIM)
	_r(img,3,6,26,16,CEDAR_RIM)
	_r(img,5,6,22,16,CEDAR)
	_r(img,4,7,24,14,CEDAR)
	_r(img,5,6,22,1,CEDAR_LIGHT)
	_r(img,4,7,1,13,CEDAR_LIGHT)
	_px(img,4,5,Color(0,0,0,0));_px(img,27,5,Color(0,0,0,0))
	_px(img,3,6,Color(0,0,0,0));_px(img,28,6,Color(0,0,0,0))
	_px(img,3,21,Color(0,0,0,0));_px(img,28,21,Color(0,0,0,0))
	# Carved water channel: one stream from the top splitting into three mouths.
	_r(img,15,8,2,5,CARVE)
	_r(img,8,12,16,2,CARVE)
	for x in [8,15,22]:_r(img,x,14,2,4,CARVE)
	for x in [7,14,21]:
		_r(img,x,18,4,2,CARVE_DARK)
	_px(img,16,9,Color("8cc4ec"));_px(img,9,15,Color("8cc4ec"));_px(img,23,15,Color("8cc4ec"))
	# Two nail heads and a rice sprout tuft at the foot.
	_px(img,6,8,BOARD_DARK);_px(img,25,8,BOARD_DARK)
	for p:Vector2i in [Vector2i(4,27),Vector2i(5,25),Vector2i(5,26),Vector2i(6,24),Vector2i(6,27),Vector2i(7,26),Vector2i(7,25),Vector2i(3,26)]:
		_px(img,p.x,p.y,SPROUT)
	_r(img,4,28,4,1,Color("4a7a30"))

static func draw_plaque(canvas:CanvasItem,at:Vector2) -> void:
	canvas.draw_texture(plaque_texture(),at)

# -------------------------------------------------------------------- icons --

static func has_item(id:String) -> bool:
	return id in ["diversion_gate_kit","water_share_plaque_kit"]

static func icon(id:String) -> Texture2D:
	if id=="water_share_plaque_kit":return plaque_texture()
	if id!="diversion_gate_kit":return null
	if cache.has("gate_icon"):return cache["gate_icon"]
	var img:=_blank()
	# Copper pipe stubs either side of the frame (the kit joins a pipe line).
	for x in [0,27]:
		_r(img,x,12,5,7,Color("7a4a26"))
		_r(img,x,13,5,5,Color("c7834a"))
		_r(img,x,13,5,1,Color("f0b77a"))
	_gate(img,"low")
	cache["gate_icon"]=ImageTexture.create_from_image(img)
	return cache["gate_icon"]
