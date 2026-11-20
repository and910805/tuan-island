extends RefCounted
## 害羞菇 (B2 east cave) drawing helpers: the mushroom sprite and its quiet-wait ring.
##
## Static, stateless apart from a texture cache. Every draw* call must run inside the canvas
## item's _draw. `foot` is the pixel where the sprite foot point (16,38) lands; with
## world_view's `at=screen(Vector2(cell))` that is `at+Vector2(16,30)`, the same 32x40
## footprint the sleepy stone guardian uses (8px above the tile, bottom flush).
##
## The atlas is loaded dynamically (no preload) so a missing or not-yet-imported file never
## breaks the script: draw() falls back to code-drawn geometry instead.
## The wait ring never relies on colour alone: progress is the arc length plus four pips that
## grow when filled, and the ready state adds a thicker closed ring and a sparkle marker.

const Shy=preload("res://scripts/shy_mushroom.gd")
const INK:=Color("2b2028")
const GLOW:=Color("fff4d2")
const TRACK:=Color("6b5a58")
const CAP:=Color("d9737a")
const CAP_DARK:=Color("a94f5e")
const STEM:=Color("f1e3c6")
const STEM_DARK:=Color("cdb894")
const WATER:=Color("7fc8e8")
const SHADOW:=Color(0,0,0,0.28)
## Ring centre is the sprite centre (the sprite spans foot.y-38 .. foot.y+2).
const RING_OFFSET:=Vector2(0,-18)
const RING_RADIUS:=16.0
const PIPS:=4
## Ready marker: a four-point sparkle floating just above the ring.
const MARKER_OFFSET:=Vector2(0,-46)
const MARKER_RADIUS:=5.0

## Test seam: when true texture() returns null, forcing the code-drawn path.
static var force_fallback:=false
static var _cache:Dictionary={}

static func reset_cache() -> void:
	_cache.clear()

## Cached; a miss is cached too so a missing file costs one attempt, not one per frame.
static func texture() -> Texture2D:
	if force_fallback:return null
	if _cache.has(Shy.ATLAS_PATH):return _cache[Shy.ATLAS_PATH]
	var loaded:Texture2D=null
	if ResourceLoader.exists(Shy.ATLAS_PATH):
		loaded=load(Shy.ATLAS_PATH) as Texture2D
	if loaded!=null and Vector2i(loaded.get_width(),loaded.get_height())!=Shy.ATLAS_SIZE:loaded=null
	_cache[Shy.ATLAS_PATH]=loaded
	return loaded

## Screen rect of the 32x40 sprite for a foot position.
static func sprite_rect(foot:Vector2) -> Rect2:
	return Rect2(foot.round()-Vector2(Shy.FOOT),Vector2(Shy.FRAME_SIZE))

## Everything draw_ring may touch (ring, pips, ready marker and its 1px bob): label obstacle.
static func ring_rect(foot:Vector2) -> Rect2:
	return Rect2(foot.round()+Vector2(-21,-55),Vector2(42,58))

## How many of the four pips are filled: one per quarter of the wait (one world-second each).
static func pip_count(progress:float) -> int:
	if not is_finite(progress):return 0
	return clampi(int(floor(progress*PIPS+0.0001)),0,PIPS)

static func draw(canvas:CanvasItem,foot:Vector2,frame:int,elapsed:float=0.0,reduced_motion:bool=false) -> void:
	var o:=foot.round()
	var index:=clampi(frame,0,3)
	# Idle breath: the whole sprite lifts 1px for part of a slow cycle. Never when reduced.
	if not reduced_motion and sin(elapsed*1.8)>0.55:o+=Vector2(0,-1)
	var atlas:=texture()
	if atlas!=null:
		canvas.draw_texture_rect_region(atlas,Rect2(o-Vector2(Shy.FOOT),Vector2(Shy.FRAME_SIZE)),Rect2(Shy.frame_rect(index)))
	else:
		_fallback(canvas,o,index)

static func draw_spore_path(canvas:CanvasItem,from:Vector2,to:Vector2,radius:float)->void:
	var top:=to.round()
	var bottom:=from.round()
	var tint:=Color("#f2b18c")
	canvas.draw_rect(Rect2(top-Vector2(radius,0),Vector2(radius*2.0,bottom.y-top.y)),Color(tint,0.22))
	var y:=bottom.y-13.0
	while y>top.y:
		var center:=Vector2(top.x,y)
		canvas.draw_polyline(PackedVector2Array([center+Vector2(-6,3),center+Vector2(0,-2),center+Vector2(6,3)]),tint,2.0)
		y-=22.0

static func draw_spore(canvas:CanvasItem,center:Vector2,radius:float,wiggle:float)->void:
	center=center.round()
	canvas.draw_circle(center,radius,Color("#e9aa8d",0.28))
	canvas.draw_arc(center,radius,0.0,TAU,18,Color("#f6c6a5"),1.0)
	var origin:=center+Vector2(roundf(wiggle),-7)
	canvas.draw_rect(Rect2(origin-Vector2(7,4),Vector2(14,8)),INK)
	canvas.draw_rect(Rect2(origin-Vector2(5,6),Vector2(10,12)),INK)
	canvas.draw_rect(Rect2(origin-Vector2(4,5),Vector2(8,10)),Color("#eaaf83"))
	canvas.draw_rect(Rect2(origin-Vector2(6,3),Vector2(12,6)),Color("#eaaf83"))
	canvas.draw_rect(Rect2(origin-Vector2(3,4),Vector2(5,3)),GLOW)
	canvas.draw_rect(Rect2(origin+Vector2(9,-3),Vector2(2,2)),GLOW)
	canvas.draw_rect(Rect2(origin+Vector2(-10,3),Vector2(2,2)),CAP)

## Quiet-wait cue. `progress` 0..1 fills an arc clockwise from the top and the four pips;
## `ready` (wait complete, press interact again) closes and thickens the ring and adds a
## sparkle above it. `elapsed` only drives the ready pulse; when omitted the engine clock is
## used. With reduced_motion everything is static and fully visible.
static func draw_ring(canvas:CanvasItem,foot:Vector2,progress:float,ready:bool,reduced_motion:bool,elapsed:float=-1.0) -> void:
	var amount:=clampf(progress,0.0,1.0) if is_finite(progress) else 0.0
	if ready:amount=1.0
	if amount<=0.0:return
	var o:=foot.round()
	var centre:=o+RING_OFFSET
	var start:=-PI*0.5
	if amount<1.0:
		canvas.draw_arc(centre,RING_RADIUS,0.0,TAU,32,Color(INK,0.55),2.0)
	var points:=maxi(4,int(ceil(32.0*amount))+1)
	canvas.draw_arc(centre,RING_RADIUS,start,start+TAU*amount,points,INK,6.0 if ready else 4.0)
	canvas.draw_arc(centre,RING_RADIUS,start,start+TAU*amount,points,GLOW,4.0 if ready else 2.0)
	var filled:=pip_count(amount)
	for pip in PIPS:
		var angle:=start+TAU*float(pip+1)/PIPS
		var at:=(centre+Vector2(cos(angle),sin(angle))*RING_RADIUS).round()
		if pip<filled:
			canvas.draw_rect(Rect2(at-Vector2(4,4),Vector2(8,8)),INK)
			canvas.draw_rect(Rect2(at-Vector2(3,3),Vector2(6,6)),GLOW)
		else:
			canvas.draw_rect(Rect2(at-Vector2(3,3),Vector2(6,6)),INK)
			canvas.draw_rect(Rect2(at-Vector2(2,2),Vector2(4,4)),TRACK)
	if not ready:return
	var beat:=0.0
	if not reduced_motion:
		var clock:=elapsed if elapsed>=0.0 else Time.get_ticks_msec()/1000.0
		beat=absf(sin(clock*6.0))
	var marker:=o+MARKER_OFFSET+Vector2(0,-roundf(beat))
	_spark(canvas,marker,MARKER_RADIUS+2.0,3.5,INK)
	_spark(canvas,marker,MARKER_RADIUS,1.5,GLOW)

## Four-point sparkle: two thin diamonds crossed (both convex, so no triangulation surprises).
static func _spark(canvas:CanvasItem,c:Vector2,reach:float,waist:float,color:Color) -> void:
	canvas.draw_colored_polygon(PackedVector2Array([c+Vector2(0,-reach),c+Vector2(waist,0),c+Vector2(0,reach),c+Vector2(-waist,0)]),color)
	canvas.draw_colored_polygon(PackedVector2Array([c+Vector2(-reach,0),c+Vector2(0,-waist),c+Vector2(reach,0),c+Vector2(0,waist)]),color)

## Rounded cap whose top edge sits at o.y+top; `half` is the half width, `height` the body.
static func _cap(canvas:CanvasItem,o:Vector2,top:float,half:float,height:float) -> void:
	canvas.draw_rect(Rect2(o+Vector2(-half+3,top),Vector2(half*2-6,4)),INK)
	canvas.draw_rect(Rect2(o+Vector2(-half,top+3),Vector2(half*2,height-3)),INK)
	canvas.draw_rect(Rect2(o+Vector2(-half+4,top+1),Vector2(half*2-8,3)),CAP)
	canvas.draw_rect(Rect2(o+Vector2(-half+1,top+4),Vector2(half*2-2,height-5)),CAP)
	canvas.draw_rect(Rect2(o+Vector2(-half+1,top+height-4),Vector2(half*2-2,3)),CAP_DARK)
	# Pale spots.
	canvas.draw_rect(Rect2(o+Vector2(-half+4,top+5),Vector2(4,3)),GLOW)
	canvas.draw_rect(Rect2(o+Vector2(half-8,top+4),Vector2(3,3)),GLOW)
	canvas.draw_rect(Rect2(o+Vector2(-1,top+2),Vector2(3,2)),GLOW)

static func _stem(canvas:CanvasItem,o:Vector2,top:float) -> void:
	canvas.draw_rect(Rect2(o+Vector2(-7,top),Vector2(14,-top)),INK)
	canvas.draw_rect(Rect2(o+Vector2(-6,top+1),Vector2(12,-top-2)),STEM)
	canvas.draw_rect(Rect2(o+Vector2(-6,-4),Vector2(12,2)),STEM_DARK)

static func _fallback(canvas:CanvasItem,o:Vector2,frame:int) -> void:
	canvas.draw_rect(Rect2(o+Vector2(-11,-2),Vector2(22,3)),SHADOW)
	match frame:
		Shy.FRAME_HIDDEN:
			# Cap pulled right down: only a sliver of stem shows.
			_stem(canvas,o,-6)
			_cap(canvas,o,-25,12,21)
		Shy.FRAME_PEEK:
			# Cap lifted a crack: a dark slit with two eye dots.
			_stem(canvas,o,-10)
			_cap(canvas,o,-30,12,18)
			canvas.draw_rect(Rect2(o+Vector2(-8,-12),Vector2(16,4)),INK)
			canvas.draw_rect(Rect2(o+Vector2(-5,-11),Vector2(2,2)),GLOW)
			canvas.draw_rect(Rect2(o+Vector2(3,-11),Vector2(2,2)),GLOW)
		Shy.FRAME_WATER:
			# Little hands up, eyes showing, a water drop above the cap.
			_stem(canvas,o,-14)
			_cap(canvas,o,-31,12,16)
			canvas.draw_rect(Rect2(o+Vector2(-11,-13),Vector2(4,3)),INK)
			canvas.draw_rect(Rect2(o+Vector2(7,-13),Vector2(4,3)),INK)
			canvas.draw_rect(Rect2(o+Vector2(-10,-12),Vector2(3,1)),STEM)
			canvas.draw_rect(Rect2(o+Vector2(7,-12),Vector2(3,1)),STEM)
			canvas.draw_rect(Rect2(o+Vector2(-4,-11),Vector2(2,2)),INK)
			canvas.draw_rect(Rect2(o+Vector2(2,-11),Vector2(2,2)),INK)
			var drop:=o+Vector2(0,-34)
			canvas.draw_colored_polygon(PackedVector2Array([drop+Vector2(0,-5),drop+Vector2(4,1),drop+Vector2(0,4),drop+Vector2(-4,1)]),INK)
			canvas.draw_colored_polygon(PackedVector2Array([drop+Vector2(0,-3),drop+Vector2(2.5,1),drop+Vector2(0,3),drop+Vector2(-2.5,1)]),WATER)
			canvas.draw_rect(Rect2(drop+Vector2(-1,0),Vector2(1,1)),GLOW)
		_:
			# Fully open: tall stem with a face under a wide, raised cap.
			_stem(canvas,o,-20)
			_cap(canvas,o,-36,15,13)
			canvas.draw_rect(Rect2(o+Vector2(-4,-16),Vector2(2,3)),INK)
			canvas.draw_rect(Rect2(o+Vector2(2,-16),Vector2(2,3)),INK)
			canvas.draw_rect(Rect2(o+Vector2(-3,-10),Vector2(6,1)),INK)
			canvas.draw_rect(Rect2(o+Vector2(-4,-11),Vector2(1,1)),INK)
			canvas.draw_rect(Rect2(o+Vector2(3,-11),Vector2(1,1)),INK)
