extends Control
## N02-3 不是同一道湯 — 米露 tastes one of two bowls on the wooden table and answers quietly.
##   "soup"        : plain soup. A regular sip, then two small, easy nods.
##   "carrot_soup" : carrot soup. A sip, a held pause, then a slow warm response
##                   (head lifts, the bowl glows, a few warm sparks drift up).
##   "forest_mushroom_soup": a longer sip and one slow nod.
## Both bowls contain the selected dish. The left bowl is tasted for radish,
## the right bowl for carrot, so the two memories also have distinct motion.
##
## Usage:  var scene:=preload("res://scripts/milu_tasting_scene.gd").new()
##         scene.dish="carrot_soup"      # "soup" (default) or "carrot_soup"; set BEFORE add_child
##         scene.reduced_motion=true     # optional, set BEFORE add_child
##         parent.add_child(scene)
##         scene.replay(); scene.is_finished()
## Canvas is 320x144 minimum (a 160x72 pixel grid drawn at 2x, nearest, integer-scaled further
## when resized). No text; the host owns all UI. Reduced motion draws the final pose in the first
## frame and never enables _process. When the animation ends _process is switched off.

signal finished

const SpriteArt=preload("res://scripts/character_sprite_art.gd")
const ItemArt=preload("res://scripts/inventory_item_art.gd")
const TABLE_ART:Texture2D=preload("res://assets/ui-life/rounded-wood-table-wide.png")

const DISH_SOUP:="soup"
const DISH_CARROT:="carrot_soup"
const DISH_FOREST:="forest_mushroom_soup"

const GRID:=Vector2(160,72)
const TOTAL:=2.8
const LIFT_START:=0.4   # spoon leaves the bowl
const LIFT_END:=1.1     # spoon reaches Milu's mouth
const SIP_END:=1.35     # sip finished
const PAUSE_END:=2.0    # carrot soup holds still until here, then answers
const LOWER_END:=2.5    # spoon is back in the bowl

const TABLE_AT:=Vector2(36,42)
const TABLE_SIZE:=Vector2(88,28)
const BOWL_SIZE:=Vector2(20,20)
const BOWL_Y:=38.0
const LEFT_BOWL_X:=62.0
const RIGHT_BOWL_X:=98.0
const MILU_FOOT:=Vector2(80,56)
const MOUTH:=Vector2(80,39)

const WOOD_BASE:=Color("a9743f")
const WOOD_LIGHT:=Color("b98650")
const WOOD_DARK:=Color("8c5c31")
const WOOD_SEAM:=Color("6f4725")
const WOOD_TOP:=Color("5d3b20")
const SHADOW:=Color(0.25,0.14,0.07,0.45)
const STEAM:=Color("fff2d4")
const SPOON:=Color("e3dccb")
const SPOON_SHADE:=Color("8d8573")
const BROTH_SOUP:=Color("e8c36a")
const BROTH_CARROT:=Color("e8873a")
const BROTH_FOREST:=Color("bd915d")
const GLOW_SOUP:=Color(1.0,0.95,0.78,0.22)
const GLOW_CARROT:=Color(1.0,0.62,0.25,0.34)
const SPARK:=Color("ffd08a")

var dish:String=DISH_SOUP
var reduced_motion:bool=false

var _elapsed:float=0.0
var _done:bool=false
var _dish_id:String=DISH_SOUP
var _sprites:=SpriteArt.new()
var _sprites_ready:bool=false

func _init() -> void:
	custom_minimum_size=Vector2(320,144)
	size=custom_minimum_size
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	clip_contents=true

func _ready() -> void:
	_dish_id=_normalized_dish()
	_sprites_ready=_sprites.setup()
	_elapsed=TOTAL if reduced_motion else 0.0
	_done=reduced_motion
	set_process(not _done)
	queue_redraw()

## Plays the movement again (ignored with reduced motion, which stays on the final pose).
func replay() -> void:
	if reduced_motion:
		return
	_dish_id=_normalized_dish()
	_elapsed=0.0
	_done=false
	set_process(true)
	queue_redraw()

func is_finished() -> bool:
	return _done

func _normalized_dish() -> String:
	return dish if dish in [DISH_CARROT,DISH_FOREST] else DISH_SOUP

func _process(delta:float) -> void:
	_elapsed=minf(_elapsed+delta,TOTAL)
	if _elapsed>=TOTAL:
		_done=true
		set_process(false)
		queue_redraw()
		finished.emit()
		return
	queue_redraw()

# --- drawing ----------------------------------------------------------------------------------

func _draw() -> void:
	var scale_i:int=maxi(1,int(floorf(minf(size.x/GRID.x,size.y/GRID.y))))
	var margin:Vector2=((size-GRID*float(scale_i))*0.5).floor()
	draw_set_transform(margin,0.0,Vector2(scale_i,scale_i))
	_draw_backdrop()
	if _sprites_ready:
		_sprites.draw_seated(self,MILU_FOOT,false,"milu",Vector2i.DOWN,_nod())
	draw_texture_rect(TABLE_ART,Rect2(TABLE_AT,TABLE_SIZE),false)
	var carrot:bool=_dish_id==DISH_CARROT
	_draw_bowl(_dish_id,LEFT_BOWL_X,not carrot)
	_draw_bowl(_dish_id,RIGHT_BOWL_X,carrot)
	_draw_spoon()
	if carrot:
		_draw_sparks()
	draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE)

func _draw_backdrop() -> void:
	draw_rect(Rect2(Vector2.ZERO,GRID),WOOD_BASE)
	var width:int=int(GRID.x)
	for row in 9:
		var y:int=row*8
		draw_rect(Rect2(0,y,GRID.x,1),WOOD_LIGHT)
		draw_rect(Rect2(0,y+7,GRID.x,1),WOOD_SEAM)
		var end_x:int=(row*37+23)%width
		draw_rect(Rect2(end_x,y+1,1,6),WOOD_SEAM)
		draw_rect(Rect2((end_x*3+11)%width,y+3,5,1),WOOD_DARK)
		draw_rect(Rect2((end_x*5+60)%width,y+5,3,1),WOOD_DARK)
	draw_rect(Rect2(0,0,GRID.x,2),WOOD_TOP)

# --- timeline ---------------------------------------------------------------------------------

## Head offset in px (positive = lower). Soup: two small nods. Carrot: still, then a slow lift.
func _nod() -> float:
	if _dish_id==DISH_FOREST:
		var late:=clampf((_elapsed-1.7)/0.9,0.0,1.0)
		return roundf(3.0*sin(late*PI))
	if _dish_id==DISH_CARROT:
		if _elapsed<SIP_END:
			return 0.0
		if _elapsed<PAUSE_END:
			return 1.0   # held, a hair low: she is thinking about it
		var t:float=_smooth(clampf((_elapsed-PAUSE_END)/(TOTAL-PAUSE_END),0.0,1.0))
		return roundf(1.0-2.0*t)   # ends a pixel above neutral, content
	var span:float=TOTAL-SIP_END
	var t2:float=clampf((_elapsed-SIP_END)/span,0.0,1.0)
	if t2>=0.85:
		return 0.0
	return roundf(2.0*absf(sin(t2/0.85*TAU)))

func _smooth(t:float) -> float:
	return t*t*(3.0-2.0*t)

## 0 = spoon in the bowl, 1 = at the mouth.
func _spoon_progress() -> float:
	if _elapsed<LIFT_START:
		return 0.0
	if _elapsed<LIFT_END:
		return _smooth((_elapsed-LIFT_START)/(LIFT_END-LIFT_START))
	var release:float=PAUSE_END if _dish_id==DISH_CARROT else SIP_END
	if _dish_id==DISH_FOREST:release=1.7
	if _elapsed<release:
		return 1.0
	if _elapsed<LOWER_END:
		return 1.0-_smooth((_elapsed-release)/(LOWER_END-release))
	return 0.0

## 0..1 warmth of the carrot response (glow, sparks). Zero for plain soup.
func _warmth() -> float:
	if _dish_id!=DISH_CARROT:
		return 0.0
	return _smooth(clampf((_elapsed-PAUSE_END)/(TOTAL-PAUSE_END),0.0,1.0))

# --- props ------------------------------------------------------------------------------------

func _bowl_pos(center_x:float) -> Vector2:
	return Vector2(floorf(center_x-BOWL_SIZE.x*0.5),BOWL_Y)

func _draw_bowl(id:String,center_x:float,tasted:bool) -> void:
	var pos:Vector2=_bowl_pos(center_x)
	draw_rect(Rect2(pos+Vector2(2,BOWL_SIZE.y-1),Vector2(BOWL_SIZE.x-4,2)),SHADOW)
	if tasted:
		var glow:Color=GLOW_CARROT if id==DISH_CARROT else GLOW_SOUP
		var warm:float=_warmth()
		if id==DISH_CARROT:
			glow.a*=warm
		if glow.a>0.01:
			draw_rect(Rect2(pos+Vector2(-3,BOWL_SIZE.y-6),Vector2(BOWL_SIZE.x+6,7)),glow)
			draw_rect(Rect2(pos+Vector2(-1,BOWL_SIZE.y-8),Vector2(BOWL_SIZE.x+2,3)),glow)
	var icon:Texture2D=ItemArt.icon(id)
	if icon!=null:
		draw_texture_rect(icon,Rect2(pos,BOWL_SIZE),false)
	_draw_steam(pos+Vector2(floorf(BOWL_SIZE.x*0.5)-3.0,1.0),tasted)

## Pixel puffs that rise and fade; the settled pose keeps one faint still wisp.
func _draw_steam(base:Vector2,tasted:bool) -> void:
	var tint:Color=STEAM
	if reduced_motion or _done:
		tint.a=0.4 if tasted else 0.28
		draw_rect(Rect2(base+Vector2(2,-3),Vector2(2,2)),tint)
		draw_rect(Rect2(base+Vector2(3,-5),Vector2(1,1)),tint)
		return
	for index in 3:
		var phase:float=fposmod(_elapsed*0.9+float(index)/3.0,1.0)
		var rise:float=floorf(phase*8.0)
		var drift:float=roundf(sin(phase*TAU+float(index)*2.0))
		var point:Vector2=base+Vector2(float(index*2)+drift,-1.0-rise)
		tint.a=(0.45 if tasted else 0.3)*(1.0-phase)
		draw_rect(Rect2(point,Vector2(2,1)),tint)
		draw_rect(Rect2(point+Vector2(1,-1),Vector2(1,1)),tint)

func _draw_spoon() -> void:
	var carrot:bool=_dish_id==DISH_CARROT
	var center_x:float=RIGHT_BOWL_X if carrot else LEFT_BOWL_X
	var start:Vector2=Vector2(center_x+1.0,BOWL_Y+2.0)
	var p:float=_spoon_progress()
	var at:Vector2=start.lerp(MOUTH,p)
	at.y-=4.0*sin(p*PI)
	# A small dip while she picks it up.
	if _elapsed<LIFT_START and not reduced_motion:
		at.y+=roundf(sin(_elapsed/LIFT_START*PI))
	at=at.floor()
	var outward:float=signf(center_x-MOUTH.x)
	# Handle trails back toward its own bowl, then the bowl of the spoon on top.
	for k in range(1,7):
		var hp:Vector2=at+Vector2(outward*float(k),floorf(float(k)*0.7)+1.0)
		draw_rect(Rect2(hp,Vector2(1,1)),SPOON_SHADE if k%2==0 else SPOON)
	draw_rect(Rect2(at+Vector2(-1,0),Vector2(4,3)),SPOON_SHADE)
	draw_rect(Rect2(at+Vector2(0,0),Vector2(2,2)),SPOON)
	# Broth stays on the spoon until the sip is over.
	var sipped:bool=_elapsed>=LIFT_END+(SIP_END-LIFT_END)*0.5
	if not sipped:
		var broth:=BROTH_CARROT if carrot else (BROTH_FOREST if _dish_id==DISH_FOREST else BROTH_SOUP)
		draw_rect(Rect2(at+Vector2(0,-1),Vector2(3,1)),broth)

func _draw_sparks() -> void:
	var warm:float=_warmth()
	if warm<=0.0:
		return
	var base:Vector2=Vector2(RIGHT_BOWL_X-1.0,BOWL_Y-6.0)
	if reduced_motion or _done:
		var still:Color=SPARK
		still.a=0.8
		draw_rect(Rect2(base+Vector2(-6,-4),Vector2(1,1)),still)
		draw_rect(Rect2(base+Vector2(6,-8),Vector2(1,1)),still)
		draw_rect(Rect2(base+Vector2(1,-12),Vector2(1,1)),still)
		return
	for index in 4:
		var phase:float=fposmod((_elapsed-PAUSE_END)*0.8+float(index)/4.0,1.0)
		var point:Vector2=base+Vector2(float(index*4-6)+roundf(sin(phase*TAU+float(index))),-floorf(phase*14.0))
		var tint:Color=SPARK
		tint.a=warm*(1.0-phase)*0.9
		draw_rect(Rect2(point.floor(),Vector2(1,1)),tint)
		if index%2==0:
			draw_rect(Rect2(point.floor()+Vector2(-1,0),Vector2(3,1)),Color(tint.r,tint.g,tint.b,tint.a*0.5))
