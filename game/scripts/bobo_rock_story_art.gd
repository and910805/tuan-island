extends Control

# N03-1 vignette: Bobo's sample table. Eight rocks settle one by one into a tiny
# island; the last silhouette resembles a dozing chicken. No text is drawn.

const BoboArt=preload("res://scripts/bobo_art.gd")

const VIEW:=Vector2(580,190)
const UNIT:=3.0
const STONE_COUNT:=8
const START_DELAY:=0.25
const STONE_GAP:=0.36
const DROP_TIME:=0.3
const TOTAL_TIME:=START_DELAY+STONE_GAP*(STONE_COUNT-1)+DROP_TIME

const WALL:=Color("26402f")
const WALL_FAR:=Color("1f3527")
const WALL_NEAR:=Color("34553a")
const TABLE:=Color("7a5233")
const TABLE_LIGHT:=Color("93673f")
const TABLE_DARK:=Color("573823")
const TRAY_WOOD:=Color("4a3220")
const TRAY_RIM:=Color("6b4a2f")
const SAND:=Color("c9ad7a")
const SAND_DARK:=Color("a98d5d")
const SHADOW:=Color(0.12,0.08,0.05,0.45)

# cx, cy, width units, height units, tone index. Index 7 is the chicken silhouette.
const STONES:=[
	[310,157,9,5,0],[338,161,8,5,1],[366,163,9,5,2],[396,161,8,5,0],
	[424,156,9,5,1],[352,147,8,5,2],[392,147,8,5,1],[372,137,16,8,3]
]
const STONE_TONES:=[
	[Color("a89b88"),Color("c4b8a3"),Color("7c705f")],
	[Color("958a78"),Color("b0a590"),Color("6c6252")],
	[Color("8a8272"),Color("a8a08c"),Color("625b4c")],
	[Color("b3a690"),Color("d1c5ac"),Color("85796a")]
]
const CHICKEN:=[
	"............oo..",
	"...o.......ohko.",
	"..oo...ooooooohb",
	".ooooooohhooooo.",
	"oooooooooooooooo",
	".sooooooooooooso",
	"..sssooooooosss.",
	"....ssssssss...."
]

var reduced:=true
var elapsed:=0.0
var drawn:=0

static func make(reduced_motion:bool) -> Control:
	var art:=new()
	art.reduced=reduced_motion
	art.custom_minimum_size=VIEW
	art.size=VIEW
	art.clip_contents=true
	art.mouse_filter=Control.MOUSE_FILTER_IGNORE
	art.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	if reduced_motion:
		art.elapsed=TOTAL_TIME
		art.drawn=STONE_COUNT
		art.set_process(false)
	else:
		art.elapsed=0.0
		art.drawn=0
	return art

func _ready() -> void:
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	set_process(not reduced and drawn<STONE_COUNT)

func drawn_count() -> int:
	return drawn

func is_complete() -> bool:
	return drawn>=STONE_COUNT and elapsed>=TOTAL_TIME

# Deterministic stepping for automation; _process uses the same path.
func advance(seconds:float) -> void:
	if reduced:return
	elapsed=minf(TOTAL_TIME,elapsed+maxf(0.0,seconds))
	drawn=0
	for index in range(STONE_COUNT):
		if elapsed>=_start_of(index):drawn+=1
	if is_complete():set_process(false)
	queue_redraw()

func _process(delta:float) -> void:
	advance(delta)

func _start_of(index:int) -> float:
	return START_DELAY+STONE_GAP*index

func _draw() -> void:
	var scale_x:=size.x/VIEW.x if size.x>0 else 1.0
	var scale_y:=size.y/VIEW.y if size.y>0 else 1.0
	draw_set_transform(Vector2.ZERO,0.0,Vector2(scale_x,scale_y))
	_draw_backdrop()
	_draw_bobo()
	_draw_table()
	_draw_tray()
	for index in range(drawn):
		_draw_stone(index)
	draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE)

func _px(x:float,y:float,w:float,h:float,color:Color) -> void:
	draw_rect(Rect2(x,y,w,h),color)

func _draw_backdrop() -> void:
	_px(0,0,VIEW.x,114,WALL)
	# distant forest ridge, then nearer stepped pines
	for column in range(0,int(VIEW.x),12):
		var h:=18+int(absf(sin(column*0.05))*22.0)
		_px(column,114-h-30,12,h,WALL_FAR)
	for column in range(6,int(VIEW.x),30):
		var tall:=24+((column*7)%5)*5
		for step in range(4):
			var half:=3+step*3
			_px(column-half,114-tall+step*(tall/4),half*2+3,tall/4+1,WALL_NEAR)
		_px(column,114-6,3,6,TABLE_DARK)

func _draw_bobo() -> void:
	var tex:=BoboArt.texture()
	if tex!=null:
		draw_texture_rect_region(tex,Rect2(34,22,96,96),BoboArt.region("portrait"))
		draw_texture_rect_region(tex,Rect2(468,24,96,96),BoboArt.region("lantern"))
	else:
		# plain fallback silhouette if the atlas is unavailable
		_px(62,40,36,36,Color("d9b48c"))
		_px(56,34,48,12,TABLE_DARK)
		_px(48,78,64,36,Color("3f6b4a"))

func _draw_table() -> void:
	_px(0,112,VIEW.x,78,TABLE)
	_px(0,112,VIEW.x,6,TABLE_LIGHT)
	_px(0,118,VIEW.x,3,TABLE_DARK)
	for plank in range(1,4):
		_px(0,118+plank*18,VIEW.x,2,TABLE_DARK)
	for knot in range(5):
		var x:=40+knot*131
		_px(x,134+(knot%2)*18,9,3,TABLE_LIGHT)

func _draw_tray() -> void:
	_ellipse(372,166,128,24,TRAY_WOOD)
	_ellipse(372,163,122,21,TRAY_RIM)
	_ellipse(372,162,112,18,SAND_DARK)
	_ellipse(372,160,108,16,SAND)
	# raked sand ripples
	for row in range(3):
		var y:=152+row*6
		_px(286+row*6,y,24,2,SAND_DARK)
		_px(436-row*4,y+1,24,2,SAND_DARK)

func _ellipse(cx:float,cy:float,rx:float,ry:float,color:Color) -> void:
	var rows:=int(ry*2/UNIT)
	for j in range(rows):
		var dy:=(j+0.5)/rows*2.0-1.0
		var half:=sqrt(maxf(0.0,1.0-dy*dy))*rx
		half=roundf(half/UNIT)*UNIT
		_px(cx-half,cy-ry+j*UNIT,half*2,UNIT,color)

func _draw_stone(index:int) -> void:
	var data:Array=STONES[index]
	var t:=clampf((elapsed-_start_of(index))/DROP_TIME,0.0,1.0)
	var lift:=snappedf(-(1.0-t*t)*36.0,UNIT)
	var cx:float=data[0]
	var cy:float=data[1]+lift
	var w:int=data[2]
	var h:int=data[3]
	var tones:Array=STONE_TONES[data[4]]
	# soft ground shadow stays on the tray while the stone falls
	_ellipse(float(data[0])+3,float(data[1])+h*UNIT*0.5,w*UNIT*0.5,UNIT*1.5,SHADOW)
	if index==7:
		_draw_chicken(Vector2(cx-w*UNIT*0.5,cy-h*UNIT*0.5),tones)
		return
	for j in range(h):
		var dy:=(j+0.5)/h*2.0-1.0
		var half_units:=roundf(sqrt(maxf(0.0,1.0-dy*dy))*w*0.5)
		var color:Color=tones[0]
		if j==0:color=tones[1]
		elif j>=h-1:color=tones[2]
		_px(cx-half_units*UNIT,cy-h*UNIT*0.5+j*UNIT,half_units*2*UNIT,UNIT,color)
		if j==1 and half_units>2:
			_px(cx-half_units*UNIT+UNIT,cy-h*UNIT*0.5+j*UNIT,UNIT*2,UNIT,tones[1])

func _draw_chicken(origin:Vector2,tones:Array) -> void:
	var palette:={
		"o":tones[0],"h":tones[1],"s":tones[2],
		"k":Color("3b3328"),"b":Color("c9904a")
	}
	for row in range(CHICKEN.size()):
		var line:String=CHICKEN[row]
		for col in range(line.length()):
			var key:=line[col]
			if key==".":continue
			_px(origin.x+col*UNIT,origin.y+row*UNIT,UNIT,UNIT,palette[key])
