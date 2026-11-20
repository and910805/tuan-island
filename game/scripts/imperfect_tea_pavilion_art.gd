extends RefCounted
## T12 不完美的茶亭 art. Two standalone 96×96 layers share ONE origin (the north-west corner of the
## 3×3 footprint):
##   imperfect-tea-pavilion-base.png  ground, shadow and the lower four posts only.
##   imperfect-tea-pavilion.png       upper canopy and roof supports.
## The base is drawn in the ground pass (under every walker); the canopy is drawn after the walkers
## and fades while the local avatar is under it or its body would be hidden behind it. Textures are
## loaded lazily and null-safe so a missing import never takes the whole world view down; the view
## itself already draws with nearest filtering.
const Industry=preload("res://scripts/industry.gd")
const MAIN_PATH:="res://assets/ui-life/imperfect-tea-pavilion.png"
const BASE_PATH:="res://assets/ui-life/imperfect-tea-pavilion-base.png"
const SIZE:=Vector2(96,96)
## Same quiet opacity as the coast awning so a hidden avatar always reads.
const FADED:=0.37
## Avatar body in tile units relative to its feet: half-width and height above the feet.
const BODY_HALF_WIDTH:=0.45
const BODY_HEIGHT:=1.5
const FADE_REACH:=0.3
const FADE_DEPTH:=0.45

static var _cache:Dictionary={}

static func load_texture(path:String) -> Texture2D:
	if not _cache.has(path):
		_cache[path]=load(path) if ResourceLoader.exists(path) else null
	return _cache[path] as Texture2D

static func main_texture() -> Texture2D:
	return load_texture(MAIN_PATH)

static func base_texture() -> Texture2D:
	return load_texture(BASE_PATH)

## Opacity of the canopy for the local avatar. `player` is the drawn foot position in tiles.
## Quiet (photograph or reduced motion) is a flat step; otherwise a short smooth ramp.
static func opacity(anchor:Vector2i,player:Vector2,quiet:bool) -> float:
	if not player.is_finite():return 1.0
	var area:=Rect2(Vector2(anchor),Vector2(Industry.PAVILION_SIZE,Industry.PAVILION_SIZE))
	var body:=Rect2(player.x-BODY_HALF_WIDTH,player.y-BODY_HEIGHT,BODY_HALF_WIDTH*2.0,BODY_HEIGHT).grow(FADE_REACH)
	if not area.intersects(body):return 1.0
	if quiet:
		return FADED if area.intersects(body.grow(-FADE_REACH)) else 1.0
	var overlap:=area.intersection(body)
	var depth:float=minf(overlap.size.x,overlap.size.y)
	return lerpf(1.0,FADED,smoothstep(0.0,FADE_DEPTH,depth))

static func draw_base(canvas:CanvasItem,at:Vector2,tint:=Color.WHITE) -> void:
	var texture:=base_texture()
	if texture!=null:canvas.draw_texture(texture,at.round(),tint)

static func draw_canopy(canvas:CanvasItem,at:Vector2,tint:=Color.WHITE,alpha:=1.0) -> void:
	var texture:=main_texture()
	if texture!=null:canvas.draw_texture(texture,at.round(),Color(tint,tint.a*alpha))

## Builder thumbnail: both layers scaled to a 32×32 cell (3:1, nearest).
static func draw_thumbnail(canvas:CanvasItem,at:Vector2) -> void:
	for texture:Texture2D in [base_texture(),main_texture()]:
		if texture!=null:canvas.draw_texture_rect(texture,Rect2(at,Vector2(32,32)),false)
