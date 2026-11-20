extends RefCounted
## 打瞌睡石像 (B4 north cave) drawing helpers: the statue and its three windbell stands.
##
## Static, stateless apart from a texture cache. Every draw_* call must run inside the
## canvas item's _draw. `foot` is the pixel where the sprite foot point (16,38) lands;
## with world_view's `at=screen(Vector2(cell))` that is `at+Vector2(16,30)`, the same
## 32x40 footprint MineArt.draw_prop uses (8px above the tile, bottom flush).
##
## Textures are loaded dynamically (no preload) so a missing or not-yet-imported atlas
## never breaks the script: each draw falls back to code-drawn geometry instead.
## Bell identity is never colour-only: every bell also carries its ●/▲/■ shape, drawn as
## geometry (not font glyphs), and a lit bell gets a ring plus an enlarged shape above it.

const Guardian=preload("res://scripts/sleepy_stone_guardian.gd")
const BELL_ATLAS_PATH:="res://assets/mine/sleepy-stone-bells.png"
const BELL_ATLAS_SIZE:=Vector2i(96,40)
const GUARDIAN_ATLAS_SIZE:=Vector2i(64,80)
const INK:=Color("2b2028")
const GLOW:=Color("fff4d2")
const STONE:=Color("8c8a90")
const STONE_LIGHT:=Color("a9a7ab")
const STONE_DARK:=Color("5f5c66")
const COPPER:=Color("b9774a")
const AMBER:=Color("f0b352")
const SHADOW:=Color(0,0,0,0.28)
## Lit marker: enlarged shape floating above the stand, and the ring around the stand.
const MARKER_OFFSET:=Vector2(0,-47)
const MARKER_RADIUS:=6.0
const RING_OFFSET:=Vector2(0,-19)
const RING_RADIUS:=16.0
## Small always-on shape chip beside the stand base, clear of the atlas art.
const BADGE_OFFSET:=Vector2(11,-5)
const BADGE_RADIUS:=3.0

## Test seam: when true both texture getters return null, forcing the code-drawn path.
static var force_fallback:=false
static var _cache:Dictionary={}

static func reset_cache() -> void:
	_cache.clear()

static func bell_rect(index:int) -> Rect2i:
	return Rect2i(index*Guardian.FRAME_SIZE.x,0,Guardian.FRAME_SIZE.x,Guardian.FRAME_SIZE.y)

static func guardian_texture() -> Texture2D:
	if force_fallback:return null
	return _texture(Guardian.ATLAS_PATH,GUARDIAN_ATLAS_SIZE)

static func bell_texture() -> Texture2D:
	if force_fallback:return null
	return _texture(BELL_ATLAS_PATH,BELL_ATLAS_SIZE)

## Cached lookup; a failed load is cached too so a missing file costs one attempt, not one per frame.
static func _texture(path:String,expected:Vector2i) -> Texture2D:
	if _cache.has(path):return _cache[path]
	var texture:=load_sized(path,expected)
	_cache[path]=texture
	return texture

## Uncached: imported resource first, then the raw PNG on disk (dev, not yet imported).
## Returns null when unavailable or not exactly `expected` pixels.
static func load_sized(path:String,expected:Vector2i) -> Texture2D:
	var texture:Texture2D=null
	if ResourceLoader.exists(path):
		texture=load(path) as Texture2D
	if texture==null:
		var file:=ProjectSettings.globalize_path(path)
		if file!="" and FileAccess.file_exists(file):
			var image:=Image.load_from_file(file)
			if image!=null and not image.is_empty():texture=ImageTexture.create_from_image(image)
	if texture==null or Vector2i(texture.get_width(),texture.get_height())!=expected:return null
	return texture

## Screen rect of the 32x40 sprite for a foot position (statue or unlit bell).
static func sprite_rect(foot:Vector2) -> Rect2:
	return Rect2(foot.round()-Vector2(Guardian.FOOT),Vector2(Guardian.FRAME_SIZE))

## Everything draw_bell may touch, including the lit ring and marker: use as a label obstacle.
static func bell_bounds(foot:Vector2,lit:bool=false) -> Rect2:
	var o:=foot.round()
	if not lit:return Rect2(o+Vector2(-16,-38),Vector2(32,40))
	return Rect2(o+Vector2(-20,-59),Vector2(40,61))

static func draw_guardian(canvas:CanvasItem,foot:Vector2,frame:int,elapsed:float=0.0,reduced_motion:bool=false) -> void:
	var o:=foot.round()
	var index:=clampi(frame,0,3)
	var texture:=guardian_texture()
	if texture!=null:
		canvas.draw_texture_rect_region(texture,Rect2(o-Vector2(Guardian.FOOT),Vector2(Guardian.FRAME_SIZE)),Rect2(Guardian.frame_rect(index)))
	else:
		_guardian_fallback(canvas,o,index)
	if index<=1:_sleep_marks(canvas,o,elapsed,reduced_motion)

static func draw_bell(canvas:CanvasItem,foot:Vector2,bell:int,lit:bool=false,elapsed:float=0.0,reduced_motion:bool=false) -> void:
	if bell<0 or bell>=Guardian.BELLS.size():return
	var o:=foot.round()
	var moving:=lit and not reduced_motion
	var beat:=sin(elapsed*7.0) if moving else 0.0
	if lit:
		var radius:=RING_RADIUS+roundf(beat)
		canvas.draw_arc(o+RING_OFFSET,radius,0.0,TAU,24,INK,4.0)
		canvas.draw_arc(o+RING_OFFSET,radius,0.0,TAU,24,GLOW,2.0)
	var sway:=Vector2(roundf(beat),0)
	var texture:=bell_texture()
	if texture!=null:
		canvas.draw_texture_rect_region(texture,Rect2(o+sway-Vector2(Guardian.FOOT),Vector2(Guardian.FRAME_SIZE)),Rect2(bell_rect(bell)))
		draw_shape(canvas,o+BADGE_OFFSET,bell,BADGE_RADIUS)
	else:
		_bell_fallback(canvas,o,bell,lit,sway)
	if lit:
		draw_shape(canvas,o+MARKER_OFFSET+Vector2(0,-roundf(absf(beat)*2.0)),bell,MARKER_RADIUS,true)

## Geometric ●/▲/■ chip in the bell colour with a dark outline. `radius` is the half extent
## of the fill; the outline adds 1.5px (and a 2px pale rim when lit, so total radius+3.5).
static func draw_shape(canvas:CanvasItem,center:Vector2,bell:int,radius:float,lit:bool=false) -> void:
	if bell<0 or bell>=Guardian.COLORS.size():return
	var c:=center.round()
	var fill:Color=Guardian.COLORS[bell]
	if lit:
		_shape(canvas,c,bell,radius,3.5,GLOW)
		fill=fill.lightened(0.3)
	_shape(canvas,c,bell,radius,1.5,INK)
	_shape(canvas,c,bell,radius,0.0,fill)
	if lit:_shape(canvas,c,bell,radius*0.3,0.0,GLOW)

static func _shape(canvas:CanvasItem,c:Vector2,bell:int,radius:float,grow:float,color:Color) -> void:
	match bell:
		0:canvas.draw_circle(c,radius+grow,color)
		1:
			# Upward triangle; `grow` offsets every edge outward by the same distance.
			var inner:=radius*0.6+grow
			var mid:=c.y+radius*0.3
			var half:=inner*1.732
			canvas.draw_colored_polygon(PackedVector2Array([Vector2(c.x,mid-inner*2.0),Vector2(c.x+half,mid+inner),Vector2(c.x-half,mid+inner)]),color)
		_:
			var side:=radius*0.85+grow
			canvas.draw_rect(Rect2(c-Vector2(side,side),Vector2(side,side)*2.0),color)

## Small drifting "z" marks so sleep reads without relying on the eye pixels alone.
static func _sleep_marks(canvas:CanvasItem,o:Vector2,elapsed:float,reduced_motion:bool) -> void:
	var drift:=0.0 if reduced_motion else fposmod(elapsed*0.5,1.0)
	var rise:=roundf(drift*4.0)
	var tint:=Color(GLOW,0.9 if reduced_motion else 0.9*(1.0-drift*0.6))
	_zed(canvas,o+Vector2(9,-36-rise),3,tint)
	_zed(canvas,o+Vector2(13,-42-rise),2,tint)

static func _zed(canvas:CanvasItem,at:Vector2,size:int,tint:Color) -> void:
	canvas.draw_rect(Rect2(at,Vector2(size+1,1)),tint)
	for step in range(1,size):
		canvas.draw_rect(Rect2(at+Vector2(size-step,step),Vector2(1,1)),tint)
	canvas.draw_rect(Rect2(at+Vector2(0,size),Vector2(size+1,1)),tint)

static func _guardian_fallback(canvas:CanvasItem,o:Vector2,frame:int) -> void:
	canvas.draw_rect(Rect2(o+Vector2(-13,-2),Vector2(26,3)),SHADOW)
	# Seated body with folded paws.
	canvas.draw_rect(Rect2(o+Vector2(-12,-20),Vector2(24,20)),INK)
	canvas.draw_rect(Rect2(o+Vector2(-11,-19),Vector2(22,18)),STONE)
	canvas.draw_rect(Rect2(o+Vector2(-11,-5),Vector2(22,4)),STONE_DARK)
	canvas.draw_rect(Rect2(o+Vector2(-8,-9),Vector2(6,5)),STONE_LIGHT)
	canvas.draw_rect(Rect2(o+Vector2(2,-9),Vector2(6,5)),STONE_LIGHT)
	# Ears and head.
	canvas.draw_rect(Rect2(o+Vector2(-10,-38),Vector2(5,5)),INK)
	canvas.draw_rect(Rect2(o+Vector2(5,-38),Vector2(5,5)),INK)
	canvas.draw_rect(Rect2(o+Vector2(-9,-37),Vector2(3,4)),STONE)
	canvas.draw_rect(Rect2(o+Vector2(6,-37),Vector2(3,4)),STONE)
	canvas.draw_rect(Rect2(o+Vector2(-10,-35),Vector2(20,17)),INK)
	canvas.draw_rect(Rect2(o+Vector2(-9,-34),Vector2(18,15)),STONE_LIGHT)
	for x in [-7,3]:
		if frame<=1:
			# Closed eyes; frame 1 is the slow blink, one pixel lower.
			canvas.draw_rect(Rect2(o+Vector2(x,-27+frame),Vector2(4,1)),INK)
		elif frame==2:
			canvas.draw_rect(Rect2(o+Vector2(x,-28),Vector2(4,2)),INK)
			canvas.draw_rect(Rect2(o+Vector2(x+1,-27),Vector2(2,1)),AMBER)
		else:
			canvas.draw_rect(Rect2(o+Vector2(x,-30),Vector2(4,4)),INK)
			canvas.draw_rect(Rect2(o+Vector2(x+1,-29),Vector2(2,2)),AMBER)
	if frame>=3:
		canvas.draw_rect(Rect2(o+Vector2(-3,-23),Vector2(6,1)),INK)
		canvas.draw_rect(Rect2(o+Vector2(-4,-24),Vector2(1,1)),INK)
		canvas.draw_rect(Rect2(o+Vector2(3,-24),Vector2(1,1)),INK)
	else:
		canvas.draw_rect(Rect2(o+Vector2(-1,-23),Vector2(2,1)),INK)

static func _bell_fallback(canvas:CanvasItem,o:Vector2,bell:int,lit:bool,sway:Vector2) -> void:
	canvas.draw_rect(Rect2(o+Vector2(-9,-2),Vector2(18,3)),SHADOW)
	# Basalt base, copper post and hook arm.
	canvas.draw_rect(Rect2(o+Vector2(-9,-6),Vector2(14,6)),INK)
	canvas.draw_rect(Rect2(o+Vector2(-8,-5),Vector2(12,4)),STONE_DARK)
	canvas.draw_rect(Rect2(o+Vector2(-8,-5),Vector2(12,1)),STONE)
	canvas.draw_rect(Rect2(o+Vector2(-7,-36),Vector2(4,31)),INK)
	canvas.draw_rect(Rect2(o+Vector2(-6,-35),Vector2(2,30)),COPPER)
	canvas.draw_rect(Rect2(o+Vector2(-7,-36),Vector2(14,4)),INK)
	canvas.draw_rect(Rect2(o+Vector2(-6,-35),Vector2(12,2)),COPPER)
	canvas.draw_rect(Rect2(o+Vector2(4,-32),Vector2(1,6)),INK)
	# The bell itself is the shape, so it reads in greyscale.
	draw_shape(canvas,o+Vector2(4.5,-19)+sway,bell,6.0,lit)
