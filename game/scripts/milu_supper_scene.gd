extends Control
## N02-4 米露的晚餐 — a four-seat supper table in a warm room. 米露 sets her bowl down first, then
## quiet steam and a soft highlight drift over the table. One-off, 2.5 s, no text.
##
## Seats (left to right): guest A, 米露, the main farmer, guest B. Each chosen guest (aru, xiaoli,
## lingpopo; unknown / duplicate IDs ignored, at most two fit) takes a guest seat in order; a seat
## nobody takes stays visibly spare: empty chair, bare table, no bowl.
##
## Usage:  var scene:=preload("res://scripts/milu_supper_scene.gd").new()
##         scene.dish="corn_chowder"          # item ID; "" or an ID with no icon falls back to "soup"
##         scene.guests=["aru","xiaoli"]      # Array[String], optional
##         scene.reduced_motion=true          # optional
##         (all three set BEFORE add_child)   parent.add_child(scene)
##         scene.replay(); scene.is_finished()
## Canvas is 440x176 (a 220x88 pixel grid drawn at 2x, nearest, integer-scaled further when resized).
## Art is the game's own PNGs: character atlas, wood table, chair, public mural, lamp niche, item
## icons. Reduced motion draws the settled pose in the first frame and never enables _process. When
## the animation ends _process is switched off and the settled pose stays as a static draw.

signal finished

const SpriteArt=preload("res://scripts/character_sprite_art.gd")
const ItemArt=preload("res://scripts/inventory_item_art.gd")
const TABLE_ART:Texture2D=preload("res://assets/ui-life/rounded-wood-table-wide.png")
const CHAIR_ART:Texture2D=preload("res://assets/ui-life/low-back-wood-chair.png")
const MURAL_ART:Texture2D=preload("res://assets/ui-inventory/public-mural.png")
const LAMP_ART:Texture2D=preload("res://assets/ui-life/warm-lamp-niche.png")

const GUEST_IDS:=["aru","xiaoli","lingpopo"]
const DEFAULT_DISH:="soup"
const LINGPOPO_TINT:=Color(0.86,0.82,0.92)   # same tint character_sprite_art uses for her

const GRID:=Vector2(220,88)
const SEAT_X:=[38.0,86.0,134.0,182.0]
const MILU_SEAT:=1
const FARMER_SEAT:=2
const GUEST_SEATS:=[0,3]
const FOOT_Y:=58.0
const TABLE_LEFT:=14.0
const TABLE_WIDTH:=192.0
const BOWL_SIZE:=Vector2(20,20)
const VASE_ID:="table_vase_herb"

# Timeline (seconds)
const TOTAL:=2.5
const HOLD:=0.15          # bowl still in her hands
const LAND:=0.8           # bowl touches the table
const SETTLE:=0.3         # two small bounces
const SHINE_START:=1.1    # steam + highlight begin
const SHINE_LEN:=0.6      # one highlight pulse per bowl
const SHINE_STAGGER:=0.25 # per seat away from Milu
const LIFT:=12.0
const BOUNCE:=[-2.0,0.0,-1.0,0.0]

const WALL:=Color("e0c496")
const WALL_SEAM:=Color("d0b080")
const WALL_LIGHT:=Color("ecd3a6")
const WAINSCOT:=Color("8c5c31")
const WAINSCOT_LIGHT:=Color("b98650")
const RAIL:=Color("5d3b20")
const FLOOR_BASE:=Color("a9743f")
const FLOOR_LIGHT:=Color("b98650")
const FLOOR_SEAM:=Color("6f4725")
const FLOOR_DARK:=Color("8c5c31")
const SHADOW:=Color(0.25,0.14,0.07,0.45)
const MAT:=Color("f0e2c0")
const MAT_EDGE:=Color("c9a56a")
const STEAM:=Color("fff2d4")
const GLOW:=Color(1.0,0.78,0.38,0.34)
const LAMPLIGHT:=Color(1.0,0.85,0.5,0.06)
const VIGNETTE:=Color(0.18,0.09,0.04,0.09)

var dish:String=""
var guests:Array[String]=[]
var reduced_motion:bool=false

var _elapsed:float=0.0
var _done:bool=false
var _dish_id:String=DEFAULT_DISH
var _layout:Array[String]=["","milu","farmer",""]
var _sprites:=SpriteArt.new()
var _sprites_ready:bool=false

func _init() -> void:
	custom_minimum_size=Vector2(440,176)
	size=custom_minimum_size
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	clip_contents=true

func _ready() -> void:
	_rebuild()
	_sprites_ready=_sprites.setup()
	_elapsed=TOTAL if reduced_motion else 0.0
	_done=reduced_motion
	set_process(not _done)
	queue_redraw()

## Plays the movement again (ignored with reduced motion, which stays on the settled pose).
func replay() -> void:
	if reduced_motion:
		return
	_rebuild()
	_elapsed=0.0
	_done=false
	set_process(true)
	queue_redraw()

func is_finished() -> bool:
	return _done

func _process(delta:float) -> void:
	_elapsed=minf(_elapsed+delta,TOTAL)
	if _elapsed>=TOTAL:
		_done=true
		set_process(false)
		queue_redraw()
		finished.emit()
		return
	queue_redraw()

## Resolves the dish and who sits where from the public inputs.
func _rebuild() -> void:
	_dish_id=dish if dish!="" and ItemArt.icon(dish)!=null else DEFAULT_DISH
	var seats:Array[String]=["","milu","farmer",""]
	var taken:Array[String]=[]
	for guest in guests:
		if taken.size()>=GUEST_SEATS.size():
			break
		if guest in GUEST_IDS and not guest in taken:
			seats[GUEST_SEATS[taken.size()]]=guest
			taken.append(guest)
	_layout=seats

# --- drawing ----------------------------------------------------------------------------------

func _draw() -> void:
	var scale_i:int=maxi(1,int(floorf(minf(size.x/GRID.x,size.y/GRID.y))))
	var margin:Vector2=((size-GRID*float(scale_i))*0.5).floor()
	draw_set_transform(margin,0.0,Vector2(scale_i,scale_i))
	_draw_room()
	for seat in 4:
		_draw_chair(seat)
	if _sprites_ready:
		for seat in 4:
			if _layout[seat]!="":
				_draw_person(seat)
	_draw_table()
	for seat in 4:
		_draw_place(seat)
	_draw_vase()
	for seat in 4:
		if _layout[seat]!="":
			_draw_bowl(seat)
	_draw_vignette()
	draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE)

func _draw_room() -> void:
	# Plastered wall with faint vertical seams, wooden wainscot, plank floor.
	draw_rect(Rect2(0,0,GRID.x,42),WALL)
	for x in range(0,int(GRID.x),22):
		draw_rect(Rect2(x,0,1,42),WALL_SEAM)
		draw_rect(Rect2(x+1,0,1,42),WALL_LIGHT)
	draw_rect(Rect2(0,40,GRID.x,2),RAIL)
	draw_rect(Rect2(0,42,GRID.x,10),WAINSCOT)
	draw_rect(Rect2(0,42,GRID.x,1),WAINSCOT_LIGHT)
	for x in range(0,int(GRID.x),11):
		draw_rect(Rect2(x,44,1,8),FLOOR_DARK)
	draw_rect(Rect2(0,52,GRID.x,2),RAIL)
	draw_rect(Rect2(0,54,GRID.x,GRID.y-54),FLOOR_BASE)
	var width:int=int(GRID.x)
	for row in 5:
		var y:int=54+row*8
		draw_rect(Rect2(0,y,GRID.x,1),FLOOR_LIGHT)
		draw_rect(Rect2(0,y+7,GRID.x,1),FLOOR_SEAM)
		var end_x:int=(row*37+23)%width
		draw_rect(Rect2(end_x,y+1,1,6),FLOOR_SEAM)
		draw_rect(Rect2((end_x*3+11)%width,y+3,5,1),FLOOR_DARK)
	# Public mural centred on the wall; a warm lamp niche at each end.
	var mural_size:Vector2=MURAL_ART.get_size()
	draw_texture(MURAL_ART,Vector2(floorf(GRID.x*0.5-mural_size.x*0.5),4))
	var lamp_size:Vector2=LAMP_ART.get_size()
	var left_lamp:=Vector2(2,2)
	var right_lamp:=Vector2(GRID.x-2.0-lamp_size.x,2)
	for lamp in [left_lamp,right_lamp]:
		_draw_lamplight(lamp+Vector2(lamp_size.x*0.5,lamp_size.y*0.45))
		draw_texture(LAMP_ART,lamp)
	# Soft contact shadow of the table on the floor.
	draw_rect(Rect2(TABLE_LEFT+4,FOOT_Y+12,TABLE_WIDTH-8,6),SHADOW)

func _draw_lamplight(center:Vector2) -> void:
	for radius in [22,15,9]:
		for dy in range(-radius,radius+1):
			var half:int=int(sqrt(float(radius*radius-dy*dy)))
			draw_rect(Rect2(center.x-half,center.y+dy,half*2,1),LAMPLIGHT)

func _draw_vignette() -> void:
	for layer in 3:
		var t:int=(layer+1)*2
		draw_rect(Rect2(0,0,GRID.x,t),VIGNETTE)
		draw_rect(Rect2(0,GRID.y-t,GRID.x,t),VIGNETTE)
		draw_rect(Rect2(0,0,t,GRID.y),VIGNETTE)
		draw_rect(Rect2(GRID.x-t,0,t,GRID.y),VIGNETTE)

func _draw_chair(seat:int) -> void:
	var chair_size:Vector2=CHAIR_ART.get_size()
	var cx:float=SEAT_X[seat]
	draw_texture(CHAIR_ART,Vector2(floorf(cx-chair_size.x*0.5),FOOT_Y+8.0-chair_size.y))

func _draw_person(seat:int) -> void:
	var id:String=_layout[seat]
	var foot:=Vector2(SEAT_X[seat],FOOT_Y)
	var nod:float=_milu_nod() if id=="milu" else _guest_nod(seat)
	match id:
		"milu":_sprites.draw_seated(self,foot,false,"milu",Vector2i.DOWN,nod)
		"farmer":_sprites.draw_seated(self,foot,false,"",Vector2i.DOWN,nod)
		"lingpopo":_draw_tinted_seated(foot,"lingpopo",LINGPOPO_TINT,nod)
		_:_sprites.draw_seated(self,foot,false,id,Vector2i.DOWN,nod)

## Same cut as CharacterSpriteArt.draw_seated, with a tint (she shares Milu's atlas cell).
func _draw_tinted_seated(foot:Vector2,style:String,tint:Color,nod:float) -> void:
	if _sprites.atlas==null:
		return
	var top:=foot.round()-Vector2(24,39)
	var source:=Vector2(SpriteArt.frame_selection(style,Vector2i.DOWN,0.0,false,false)*SpriteArt.FRAME_SIZE)
	draw_texture_rect_region(_sprites.atlas,Rect2(top+Vector2(0,nod),Vector2(48,35.0-nod)),Rect2(source.x,source.y,48,35),tint)
	draw_texture_rect_region(_sprites.atlas,Rect2(top+Vector2(0,34),Vector2(48,9)),Rect2(source.x,source.y+38,48,9),tint)

## The long table is the game's wide table with its middle strip repeated, so legs and rounded
## ends stay pixel-exact.
func _draw_table() -> void:
	var tex:Vector2=TABLE_ART.get_size()
	var cap:float=floorf(tex.x*0.25)
	var mid_w:float=floorf(tex.x*0.25)
	var mid_x:float=floorf((tex.x-mid_w)*0.5)
	var y:float=FOOT_Y-14.0
	var right_start:float=TABLE_LEFT+TABLE_WIDTH-cap
	var x:float=TABLE_LEFT+cap
	while x<right_start:
		var w:float=minf(mid_w,right_start-x)
		draw_texture_rect_region(TABLE_ART,Rect2(x,y,w,tex.y),Rect2(mid_x,0,w,tex.y))
		x+=mid_w
	draw_texture_rect_region(TABLE_ART,Rect2(TABLE_LEFT,y,cap,tex.y),Rect2(0,0,cap,tex.y))
	draw_texture_rect_region(TABLE_ART,Rect2(right_start,y,cap,tex.y),Rect2(tex.x-cap,0,cap,tex.y))

## A cloth placemat at every seat. Under a bowl it is a setting; bare, it marks a spare seat.
func _draw_place(seat:int) -> void:
	var left:float=floorf(SEAT_X[seat])-12.0
	var top:float=FOOT_Y+1.0
	draw_rect(Rect2(left,top,24,7),MAT_EDGE)
	draw_rect(Rect2(left+1,top+1,22,5),MAT)
	if _layout[seat]=="":
		draw_rect(Rect2(left+5,top+2,14,1),Color(MAT_EDGE.r,MAT_EDGE.g,MAT_EDGE.b,0.55))
		draw_rect(Rect2(left+5,top+4,14,1),Color(MAT_EDGE.r,MAT_EDGE.g,MAT_EDGE.b,0.55))

func _draw_vase() -> void:
	var icon:Texture2D=ItemArt.icon(VASE_ID)
	if icon==null:
		return
	var at:=Vector2(floorf((SEAT_X[MILU_SEAT]+SEAT_X[FARMER_SEAT])*0.5-BOWL_SIZE.x*0.5),FOOT_Y-20.0)
	draw_rect(Rect2(at+Vector2(3,BOWL_SIZE.y-2),Vector2(BOWL_SIZE.x-6,2)),SHADOW)
	draw_texture_rect(icon,Rect2(at,BOWL_SIZE),false)

# --- timeline ---------------------------------------------------------------------------------

func _smooth(t:float) -> float:
	return t*t*(3.0-2.0*t)

## Milu's head dips as she leans to put the bowl down, then comes back up.
func _milu_nod() -> float:
	return roundf(2.0*sin(PI*clampf(_elapsed/(LAND+0.3),0.0,1.0)))

## Everyone else lowers their eyes a pixel once, a beat after the bowl is down.
func _guest_nod(seat:int) -> float:
	var u:float=(_elapsed-SHINE_START-0.1-_delay(seat)*0.5)/0.7
	return 1.0 if u>0.15 and u<0.85 else 0.0

func _delay(seat:int) -> float:
	return float(absi(seat-MILU_SEAT))*SHINE_STAGGER

## Vertical offset of Milu's bowl: held up, lowered, two small bounces.
func _milu_bowl_offset() -> float:
	if _elapsed<HOLD:
		return -LIFT
	if _elapsed<LAND:
		return -LIFT*(1.0-_smooth((_elapsed-HOLD)/(LAND-HOLD)))
	if _elapsed<LAND+SETTLE:
		var s:float=clampf((_elapsed-LAND)/SETTLE,0.0,0.999)
		return BOUNCE[int(s*BOUNCE.size())]
	return 0.0

## 0..1..0 pulse per bowl; Milu's bowl keeps a faint residual glow.
func _glow(seat:int) -> float:
	var u:float=clampf((_elapsed-SHINE_START-_delay(seat))/SHINE_LEN,0.0,1.0)
	var pulse:float=sin(PI*u)
	var resid:float=0.3*_smooth(u) if seat==MILU_SEAT else 0.0
	return clampf(pulse*0.7+resid,0.0,1.0)

# --- bowls ------------------------------------------------------------------------------------

func _draw_bowl(seat:int) -> void:
	var rest:=Vector2(floorf(SEAT_X[seat]-BOWL_SIZE.x*0.5),FOOT_Y-18.0)
	var pos:=rest
	if seat==MILU_SEAT:
		pos.y+=_milu_bowl_offset()
	var lift:float=maxf(0.0,rest.y-pos.y)
	if lift<=4.0:
		draw_rect(Rect2(rest+Vector2(2,BOWL_SIZE.y-1),Vector2(BOWL_SIZE.x-4,2)),SHADOW)
	var glow:float=_glow(seat)
	if glow>0.01 and lift<=0.0:
		var tint:Color=GLOW
		tint.a*=glow
		draw_rect(Rect2(rest+Vector2(-4,BOWL_SIZE.y-6),Vector2(BOWL_SIZE.x+8,7)),tint)
		draw_rect(Rect2(rest+Vector2(-2,BOWL_SIZE.y-8),Vector2(BOWL_SIZE.x+4,3)),tint)
	var icon:Texture2D=ItemArt.icon(_dish_id)
	if icon!=null:
		draw_texture_rect(icon,Rect2(pos.floor(),BOWL_SIZE),false)
	_draw_steam(seat,rest+Vector2(floorf(BOWL_SIZE.x*0.5)-3.0,1.0))

## Pixel puffs that rise, drift and fade. The settled pose is the same function at the last
## timestamp, so the animation ends on exactly the frame that stays on screen.
func _draw_steam(seat:int,base:Vector2) -> void:
	var age:float=_elapsed-SHINE_START-_delay(seat)*0.5
	if age<=0.0:
		return
	var fade_in:float=clampf(age/0.5,0.0,1.0)
	for index in 3:
		var phase:float=fposmod(age*0.9+float(index)/3.0,1.0)
		var rise:float=floorf(phase*8.0)
		var drift:float=roundf(sin(phase*TAU+float(index)*2.0))
		var point:Vector2=base+Vector2(float(index*2)+drift,-1.0-rise)
		var tint:Color=STEAM
		tint.a=0.45*(1.0-phase)*fade_in
		draw_rect(Rect2(point,Vector2(2,1)),tint)
		draw_rect(Rect2(point+Vector2(1,-1),Vector2(1,1)),tint)
