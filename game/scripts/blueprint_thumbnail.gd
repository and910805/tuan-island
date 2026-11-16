extends "res://scripts/world_view.gd"
## Small blueprint picture for the folio (docs/blueprint-client-contract.md).
##
## A Node2D placed inside a Control; the UI sets `design` (a blueprint, or a
## library entry {id, design}) and `box_size`. Both setters redraw. Only the
## design is drawn — with the real world sprites, ground → objects → roofs in
## canonical y/x order — plus faint footprint grid lines for context.
##
## Fit: whole-number scale (≤4), then reciprocal powers of two down to 1/32
## for tiny badges; nearest filtering, keeping the
## 8px side / 16px top / 8px bottom overhang that 48px machine sprites
## (waterworks, mine_drill, ore_display) and tall furniture use.
##
## Art: shares PixelBuildThumbnail's root-metadata VillagePreview (no static
## Texture cache of its own, never clears the shared cache; Main removes it).
## Empty or malformed designs simply draw nothing.

const Design=preload("res://scripts/blueprint_design.gd")
const PixelBuildThumbnail=preload("res://scripts/pixel_build_thumbnail.gd")
## Inside VillagePreview.REGION even for a 16x16 design, so ground uses its tiles.
const ANCHOR:=Vector2i(40,30)
const MARGIN_TOP_LEFT:=Vector2(8,16)
const MARGIN_BOTTOM_RIGHT:=Vector2(8,8)
const SCALES:=[4.0,3.0,2.0,1.0,0.5,0.25,0.125,0.0625,0.03125]
const GRID:=Color(0.42,0.36,0.26,0.32)
const ROOF_ALPHA:=0.5

var design:Dictionary={}:
	set(value):
		design=value
		_rebuild()
		queue_redraw()
var box_size:=Vector2(200,160):
	set(value):
		box_size=Vector2(maxf(value.x,0.0),maxf(value.y,0.0))
		queue_redraw()

var _pieces:Array=[]
var _cells:=Vector2i.ZERO
var _objects:Dictionary={}

func _ready() -> void:
	set_process(false)
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	var cache_owner:=get_tree().root
	var shared:Variant=cache_owner.get_meta(PixelBuildThumbnail.CACHE_KEY) if cache_owner.has_meta(PixelBuildThumbnail.CACHE_KEY) else null
	if shared is RefCounted:
		village_art=shared
	else:
		var art:=VillagePreview.new()
		art.setup()
		cache_owner.set_meta(PixelBuildThumbnail.CACHE_KEY,art)
		village_art=art
	data={"objects":_objects}
	queue_redraw()

## Normalises the design once per assignment; failures leave nothing to draw.
func _rebuild() -> void:
	_pieces=[]
	_cells=Vector2i.ZERO
	_objects={}
	var result:Dictionary=Design.validate(design,World.BUILD,World.NAMES)
	if result.get("ok")!=true and design.get("design") is Dictionary:
		result=Design.validate(design.design,World.BUILD,World.NAMES)
	if result.get("ok")!=true or not (result.get("blueprint") is Dictionary):
		data={"objects":_objects}
		return
	var bp:Dictionary=result.blueprint
	_pieces=bp.pieces
	_cells=Vector2i(int(bp.width),int(bp.height))
	for item in _pieces:
		var piece:Dictionary=item
		var kind:=str(piece.kind)
		if kind in Design.GROUND_KINDS or kind in Design.ROOF_KINDS:continue
		var obj:={"type":kind,"owner":"blueprint_thumbnail"}
		if piece.has("style"):obj.style=piece.style
		if piece.has("settings"):
			var settings:Dictionary=piece.settings
			obj["dir"]=int(settings.get("dir",1))
			obj["filter"]=str(settings.get("filter",""))
			obj["enabled"]=false
		_objects[World.key(ANCHOR+Vector2i(int(piece.x),int(piece.y)))]=obj
	data={"objects":_objects}

func fit_scale(content:Vector2) -> float:
	for candidate:float in SCALES:
		if content.x*candidate<=box_size.x and content.y*candidate<=box_size.y:return candidate
	# Tiny header badges must not overflow into neighboring labels. The large
	# folio preview remains the place to inspect individual sprite pixels.
	return 0.0

func _draw() -> void:
	if _pieces.is_empty() or _cells.x<=0 or _cells.y<=0:return
	var footprint:=Vector2(_cells)*TILE
	var content:=footprint+MARGIN_TOP_LEFT+MARGIN_BOTTOM_RIGHT
	var factor:=fit_scale(content)
	if factor<=0.0:return
	var offset:=((box_size-content*factor)*0.5).floor()
	camera=Vector2(ANCHOR)*TILE-MARGIN_TOP_LEFT
	draw_set_transform(offset,0,Vector2.ONE*factor)
	# Footprint grid: outlines only, as context for empty cells.
	var top_left:=MARGIN_TOP_LEFT
	for x in range(_cells.x+1):
		draw_line(top_left+Vector2(x*TILE,0),top_left+Vector2(x*TILE,footprint.y),GRID,-1.0)
	for y in range(_cells.y+1):
		draw_line(top_left+Vector2(0,y*TILE),top_left+Vector2(footprint.x,y*TILE),GRID,-1.0)
	# Pieces are already canonical: ground → objects → roofs, then y, then x.
	for item in _pieces:
		var piece:Dictionary=item
		var kind:=str(piece.kind)
		var cell:=ANCHOR+Vector2i(int(piece.x),int(piece.y))
		var at:=screen(Vector2(cell))
		var style := str(piece.get("style",""))
		if kind in Design.GROUND_KINDS:ground_tile(at,kind,style)
		elif kind in Design.ROOF_KINDS:roof_sprite(at,ROOF_ALPHA,kind,style)
		else:object_sprite(at,kind,_objects.get(World.key(cell),{}))
