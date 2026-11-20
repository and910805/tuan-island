extends Control
## 米露忘記吃飯 — a single short vignette: a bowl of soup slides across the wooden table,
## settles with two small bounces, steam rises, and 米露 (seated, head a little low) relaxes.
##
## Usage:  var scene:=preload("res://scripts/milu_first_soup_scene.gd").new()
##         scene.reduced_motion=true   # optional, set BEFORE add_child
##         parent.add_child(scene)
## Canvas is 320x112 (a 160x56 pixel grid drawn at 2x, nearest). Integer-scales further if the
## control is resized; the 1x/2x display is up to the host (texture_filter is forced nearest).
## No text. Reduced motion draws the final pose in the first frame and never enables _process.
## After the animation ends _process is switched off and the final pose is a static draw.

signal finished

const SpriteArt=preload("res://scripts/character_sprite_art.gd")
const ItemArt=preload("res://scripts/inventory_item_art.gd")
const TABLE_ART:Texture2D=preload("res://assets/ui-life/rounded-wood-table-wide.png")

const GRID:=Vector2(160,56)
const SLIDE:=0.9      # bowl crosses the table
const SETTLE:=0.4     # two small bounces
const RELAX:=0.7      # Milu lifts her head after the bowl is down
const TOTAL:=SLIDE+SETTLE+RELAX
const SLUMP:=3        # head offset (px) while she is still lost in thought

const WOOD_BASE:=Color("a9743f")
const WOOD_LIGHT:=Color("b98650")
const WOOD_DARK:=Color("8c5c31")
const WOOD_SEAM:=Color("6f4725")
const WOOD_TOP:=Color("5d3b20")
const SHADOW:=Color(0.25,0.14,0.07,0.45)
const STEAM:=Color("fff2d4")
const BOUNCE:=[-2.0,0.0,-1.0,0.0]

var reduced_motion:bool=false

var _elapsed:=0.0
var _done:=false
var _sprites:=SpriteArt.new()
var _sprites_ready:=false

func _init() -> void:
	custom_minimum_size=Vector2(320,112)
	size=custom_minimum_size
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	clip_contents=true

func _ready() -> void:
	_sprites_ready=_sprites.setup()
	_elapsed=TOTAL if reduced_motion else 0.0
	_done=reduced_motion
	set_process(not _done)
	queue_redraw()

## Plays the movement again (ignored with reduced motion, which stays on the final pose).
func replay() -> void:
	if reduced_motion:
		return
	_elapsed=0.0
	_done=false
	set_process(true)
	queue_redraw()

func _process(delta:float) -> void:
	_elapsed=minf(_elapsed+delta,TOTAL)
	if _elapsed>=TOTAL:
		_done=true
		set_process(false)
		finished.emit()
	queue_redraw()

func _draw() -> void:
	var scale_i:=maxi(1,int(floorf(minf(size.x/GRID.x,size.y/GRID.y))))
	var margin:=((size-GRID*float(scale_i))*0.5).floor()
	draw_set_transform(margin,0.0,Vector2(scale_i,scale_i))
	_draw_backdrop()
	var table_size:=Vector2(64,28)
	var table_at:=Vector2(50,28)
	# Milu first, so the table covers her lap.
	if _sprites_ready:
		_sprites.draw_seated(self,Vector2(73,42),false,"milu",Vector2i.DOWN,float(_slump()))
	draw_texture_rect(TABLE_ART,Rect2(table_at,table_size),false)
	_draw_bowl(table_at,table_size)
	draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE)

# --- timeline -------------------------------------------------------------------------------

func _slump() -> int:
	var t:=clampf((_elapsed-SLIDE-SETTLE*0.5)/(RELAX+SETTLE*0.5),0.0,1.0)
	return int(roundf(float(SLUMP)*(1.0-t*t*(3.0-2.0*t))))

func _draw_backdrop() -> void:
	draw_rect(Rect2(Vector2.ZERO,GRID),WOOD_BASE)
	for row in 7:
		var y:=row*8
		draw_rect(Rect2(0,y,GRID.x,1),WOOD_LIGHT)
		draw_rect(Rect2(0,y+7,GRID.x,1),WOOD_SEAM)
		# Staggered plank ends and a couple of grain ticks.
		var width:=int(GRID.x)
		var end_x:=(row*37+23)%width
		draw_rect(Rect2(end_x,y+1,1,6),WOOD_SEAM)
		draw_rect(Rect2((end_x*3+11)%width,y+3,5,1),WOOD_DARK)
		draw_rect(Rect2((end_x*5+60)%width,y+5,3,1),WOOD_DARK)
	draw_rect(Rect2(0,0,GRID.x,2),WOOD_TOP)

func _bowl_rest(table_at:Vector2,table_size:Vector2,bowl_size:Vector2) -> Vector2:
	# Bowl base sits on the near half of the tabletop, centred on the table.
	return Vector2(floorf(table_at.x+table_size.x*0.7-bowl_size.x*0.5),table_at.y+12.0-bowl_size.y)

func _draw_bowl(table_at:Vector2,table_size:Vector2) -> void:
	var icon:=ItemArt.icon("soup")
	if icon==null:
		return
	var bowl_size:=Vector2(20,20)
	var rest:=_bowl_rest(table_at,table_size,bowl_size)
	var pos:=rest
	var landed:=_elapsed>=SLIDE
	if not landed:
		var t:=clampf(_elapsed/SLIDE,0.0,1.0)
		var ease_out:=1.0-pow(1.0-t,2.0)
		pos.x+=floorf(62.0*(1.0-ease_out))
		pos.y-=floorf(10.0*(1.0-ease_out)+4.0*sin(t*PI))
	else:
		var s:=clampf((_elapsed-SLIDE)/SETTLE,0.0,0.999)
		pos.y+=float(BOUNCE[int(s*BOUNCE.size())])
	pos=pos.floor()
	# Contact shadow on the tabletop (hidden while the bowl is still high in the air).
	var lift:=maxf(0.0,rest.y-pos.y)
	if lift<=4.0:
		draw_rect(Rect2(rest+Vector2(2,bowl_size.y-1),Vector2(bowl_size.x-4,2)),SHADOW)
	draw_texture_rect(icon,Rect2(pos,bowl_size),false)
	if landed:
		_draw_steam(pos+Vector2(floorf(bowl_size.x*0.5)-3.0,1.0))

## Same wisp technique as CommunityArt: pixel puffs that rise, drift and fade. Only animated
## while the vignette is still playing; the settled pose keeps one faint still wisp.
func _draw_steam(base:Vector2) -> void:
	if reduced_motion or _done:
		var still:=STEAM
		still.a=0.4
		draw_rect(Rect2(base+Vector2(2,-3),Vector2(2,2)),still)
		draw_rect(Rect2(base+Vector2(3,-5),Vector2(1,1)),still)
		return
	var age:=_elapsed-SLIDE
	for index in 3:
		var phase:=fposmod(age*0.9+float(index)/3.0,1.0)
		var rise:=floorf(phase*8.0)
		var drift:=roundf(sin(phase*TAU+float(index)*2.0))
		var point:=base+Vector2(float(index*2)+drift,-1.0-rise)
		var tint:=STEAM
		tint.a=0.45*(1.0-phase)
		draw_rect(Rect2(point,Vector2(2,1)),tint)
		draw_rect(Rect2(point+Vector2(1,-1),Vector2(1,1)),tint)
