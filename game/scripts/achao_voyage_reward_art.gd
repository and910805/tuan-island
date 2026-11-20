extends Control
## 阿潮航海手記獎勵插圖：並排畫出實際的兩種船身（原木／藍白），標示目前使用中的一艘。
## 船圖直接取自 achao-voyage.png 的既有圖集格；背景是原創的暖色海港像素畫，不新增素材。

const BOATS=preload("res://assets/transit/achao-voyage.png")
const CELL:=48.0
const BOAT_SIZE:=72.0
const ART_HEIGHT:=106.0
const ART_WIDTH:=280.0
const GAP:=8.0
const RIPPLE_SECONDS:=2.4
const LABELS:=["原木船身","藍白船身"]

const INK:=Color("3d422d")
const PAPER:=Color("f3dfb4")
const PAPER_SHADE:=Color("e2c58d")
const SKY:=Color("f6d9a2")
const SUN:=Color("fff0c4")
const SEA:=Color("6aa7a6")
const SEA_DEEP:=Color("4a8590")
const FOAM:=Color("dff0e0")
const PIER:=Color("8a5a3a")
const PIER_LIGHT:=Color("d7af78")
const GOLD:=Color("e8b04a")
const BADGE_TEXT:=Color("3d2a14")

var blue_current:=false
var still:=true
var elapsed:=0.0

static func make(blue:bool,reduced_motion:bool) -> Control:
	var art:=new()
	art.blue_current=blue
	art.still=reduced_motion
	art.custom_minimum_size=Vector2(ART_WIDTH,ART_HEIGHT)
	art.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	art.mouse_filter=Control.MOUSE_FILTER_IGNORE
	art.set_process(not reduced_motion)
	return art

func _ready() -> void:
	set_process(not still)

func _process(delta:float) -> void:
	elapsed+=delta
	if elapsed>=RIPPLE_SECONDS:
		elapsed=RIPPLE_SECONDS
		set_process(false)
	queue_redraw()

func _draw() -> void:
	var total:=Vector2(maxf(size.x,ART_WIDTH),maxf(size.y,ART_HEIGHT))
	var panel_width:=floorf((total.x-GAP)*0.5)
	for index in 2:
		var panel:=Rect2(Vector2(index*(panel_width+GAP),0.0),Vector2(panel_width,total.y))
		_draw_panel(panel,index==1,(index==1)==blue_current)

func _draw_panel(panel:Rect2,blue:bool,current:bool) -> void:
	var font:=get_theme_default_font()
	# 紙底與暖色天空
	draw_rect(panel,PAPER)
	var sky:=Rect2(panel.position+Vector2(3,3),Vector2(panel.size.x-6,panel.size.y*0.52))
	draw_rect(sky,SKY)
	draw_rect(Rect2(sky.position+Vector2(0,sky.size.y-8),Vector2(sky.size.x,8)),PAPER_SHADE)
	# 像素小太陽
	var sun:=sky.position+Vector2(sky.size.x-22,10)
	draw_rect(Rect2(sun+Vector2(2,0),Vector2(8,12)),SUN)
	draw_rect(Rect2(sun+Vector2(0,2),Vector2(12,8)),SUN)
	# 海面
	var sea_top:=floorf(panel.position.y+panel.size.y*0.52)
	var sea:=Rect2(panel.position.x+3,sea_top,panel.size.x-6,panel.end.y-3-sea_top-14)
	draw_rect(sea,SEA)
	draw_rect(Rect2(sea.position+Vector2(0,sea.size.y-7),Vector2(sea.size.x,7)),SEA_DEEP)
	# 木碼頭棧板（左側）
	var pier:=Vector2(panel.position.x+3,sea_top-3)
	draw_rect(Rect2(pier,Vector2(14,5)),PIER_LIGHT)
	draw_rect(Rect2(pier+Vector2(0,5),Vector2(14,2)),PIER)
	draw_rect(Rect2(pier+Vector2(3,7),Vector2(3,12)),PIER)
	draw_rect(Rect2(pier+Vector2(10,7),Vector2(3,12)),PIER)
	# 小船：直接取用既有圖集格（原木在 0，藍白在 48）
	var boat_pos:=Vector2(floorf(panel.position.x+(panel.size.x-BOAT_SIZE)*0.5),sea_top-BOAT_SIZE+24.0)
	var progress:=elapsed/RIPPLE_SECONDS
	if not still:
		boat_pos.y+=roundf(sin(progress*TAU))
	_draw_ripples(Rect2(sea.position,Vector2(sea.size.x,sea.size.y)),boat_pos+Vector2(BOAT_SIZE*0.5,BOAT_SIZE-14.0),progress)
	draw_texture_rect_region(BOATS,Rect2(boat_pos,Vector2(BOAT_SIZE,BOAT_SIZE)),Rect2(CELL if blue else 0.0,0.0,CELL,CELL))
	# 標籤列
	var label_bar:=Rect2(panel.position.x+3,panel.end.y-17,panel.size.x-6,14)
	draw_rect(label_bar,PAPER)
	draw_rect(Rect2(label_bar.position,Vector2(label_bar.size.x,1)),PAPER_SHADE)
	draw_string(font,label_bar.position+Vector2(0,11),LABELS[1 if blue else 0],HORIZONTAL_ALIGNMENT_CENTER,label_bar.size.x,12,INK)
	# 外框：目前使用的以金色加粗
	draw_rect(panel,GOLD if current else INK,false,3.0 if current else 1.0)
	if current:
		_draw_badge(panel,font)

func _draw_ripples(water:Rect2,center:Vector2,progress:float) -> void:
	var rows:=2
	for row in rows:
		var phase:=0.0 if still else fposmod(progress+float(row)*0.5,1.0)
		var spread:=18.0+(0.0 if still else phase*10.0)+float(row)*6.0
		var y:=roundf(center.y+float(row)*4.0)
		if y<water.position.y or y>water.end.y-2.0:continue
		var alpha:=0.8 if still else 0.85*(1.0-phase)
		var color:=Color(FOAM.r,FOAM.g,FOAM.b,alpha)
		var half:=roundf(spread)
		draw_rect(Rect2(roundf(center.x-half),y,8.0,1.0),color)
		draw_rect(Rect2(roundf(center.x+half-8.0),y,8.0,1.0),color)

func _draw_badge(panel:Rect2,font:Font) -> void:
	var badge:=Rect2(panel.end.x-46,panel.position.y+5,40,16)
	draw_rect(Rect2(badge.position+Vector2(0,2),badge.size),INK)
	draw_rect(badge,GOLD)
	draw_rect(badge,INK,false,1.0)
	# 像素勾號
	var tick:=badge.position+Vector2(4,8)
	for step in 3:
		draw_rect(Rect2(tick+Vector2(step,step),Vector2(1,2)),BADGE_TEXT)
	for step in 5:
		draw_rect(Rect2(tick+Vector2(3+step,2-step),Vector2(1,2)),BADGE_TEXT)
	draw_string(font,badge.position+Vector2(14,12),"目前",HORIZONTAL_ALIGNMENT_LEFT,24,11,BADGE_TEXT)
