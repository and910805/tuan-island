extends "res://scripts/world_view.gd"
## Blueprint ground preview (docs/blueprint-client-contract.md「素材預覽」).
##
## Main owns one instance above the world view, sets `source_view`/`controller`
## and calls queue_redraw() every frame. Nothing of the parent world drawing,
## interpolation or _process runs here: _ready/_draw are overridden and
## processing stays off.
##
## Ghost: the controller's draft is rotated with Design.rotate and drawn with
## the real world art (ground → objects → roofs, canonical y/x order) through
## this node's self_modulate, sharing source_view's camera, view_zoom and
## village_art reference. Frames, grid lines and problem cells are drawn by an
## internal child canvas at full opacity, so they stay crisp over the ghost.
##
## Border stays neutral until the controller holds the current authoritative
## quote; red cells come only from that quote's `problems`.

const Design=preload("res://scripts/blueprint_design.gd")
const GHOST:=Color(1,1,1,0.62)
const ROOF_ALPHA:=0.7
const NEUTRAL:=Color("fff4c2")
const GOOD:=Color("b3d894")
const BAD:=Color("db9980")
const PROBLEM:=Color("d0654f")
const GRID:=Color(1,0.96,0.80,0.22)
const CAPTURE_FILL:=Color(0.96,0.92,0.67,0.23)
const CAPTURE_EDGE:=Color("fff4c2")
const GHOST_MODES:=["placing","submitting"]
const MAX_PROBLEM_CELLS:=64

var source_view:Node2D
var controller:Node
var capture_rect:=Rect2i()
var capture_visible:=false

var _frame:Node2D
var _view_zoom:=2.0
var _rotated_key:Array=[]
var _rotated:Dictionary={}

func _ready() -> void:
	set_process(false)
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	self_modulate=GHOST
	data={}
	_frame=Node2D.new()
	_frame.name="BlueprintPreviewFrame"
	_frame.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	_frame.draw.connect(_draw_frame)
	add_child(_frame,false,Node.INTERNAL_MODE_BACK)

func _draw() -> void:
	if is_instance_valid(_frame):_frame.queue_redraw()
	if not _sync_view():return
	var layout:=_layout()
	if layout.is_empty():return
	var origin:Vector2i=layout.origin
	var pieces:Array=layout.pieces
	var objects:={}
	for item in pieces:
		var piece:Dictionary=item
		var kind:=str(piece.kind)
		if kind in Design.GROUND_KINDS or kind in Design.ROOF_KINDS:continue
		var cell:=origin+Vector2i(int(piece.x),int(piece.y))
		var obj:={"type":kind,"owner":"blueprint_preview"}
		if piece.has("style"):obj.style=piece.style
		if piece.has("settings"):
			var settings:Dictionary=piece.settings
			obj["dir"]=int(settings.get("dir",1))
			obj["filter"]=str(settings.get("filter",""))
			obj["enabled"]=false
		objects[World.key(cell)]=obj
	data={"region_id":_source_region(),"time":_source_time(),"objects":objects}
	draw_set_transform(Vector2.ZERO,0,Vector2.ONE*_view_zoom)
	# Pieces are already canonical: ground → objects → roofs, then y, then x.
	for item in pieces:
		var piece:Dictionary=item
		var kind:=str(piece.kind)
		var cell:=origin+Vector2i(int(piece.x),int(piece.y))
		var at:=screen(Vector2(cell))
		var style := str(piece.get("style",""))
		if kind in Design.GROUND_KINDS:ground_tile(at,kind,style)
		elif kind in Design.ROOF_KINDS:roof_sprite(at,ROOF_ALPHA,kind,style)
		else:object_sprite(at,kind,objects.get(World.key(cell),{}))

func _draw_frame() -> void:
	if not is_instance_valid(_frame) or not _sync_view():return
	_frame.draw_set_transform(Vector2.ZERO,0,Vector2.ONE*_view_zoom)
	if capture_visible:_draw_capture()
	var layout:=_layout()
	if layout.is_empty():return
	var origin:Vector2i=layout.origin
	var size:Vector2i=layout.size
	var area:=Rect2i(origin,size)
	var top_left:=screen(Vector2(origin))
	var extent:=Vector2(size)*TILE
	for x in range(1,size.x):
		_frame.draw_line(top_left+Vector2(x*TILE,0),top_left+Vector2(x*TILE,extent.y),GRID,1.0)
	for y in range(1,size.y):
		_frame.draw_line(top_left+Vector2(0,y*TILE),top_left+Vector2(extent.x,y*TILE),GRID,1.0)
	var quote:=_current_quote(origin,int(layout.turns))
	var tint:=NEUTRAL
	if not quote.is_empty():
		tint=GOOD if quote.get("ok")==true else BAD
		var raw_problems:Variant=quote.get("problems")
		if raw_problems is Array:
			var problems:Array=raw_problems
			for index in mini(problems.size(),MAX_PROBLEM_CELLS):
				var entry:Variant=problems[index]
				if not (entry is Dictionary):continue
				var cx:Variant=(entry as Dictionary).get("x")
				var cy:Variant=(entry as Dictionary).get("y")
				if not (typeof(cx) in [TYPE_INT,TYPE_FLOAT] and typeof(cy) in [TYPE_INT,TYPE_FLOAT]):continue
				var cell:=Vector2i(int(cx),int(cy))
				if not area.has_point(cell):continue
				var at:=screen(Vector2(cell))
				_frame.draw_rect(Rect2(at+Vector2(1,1),Vector2(30,30)),Color(PROBLEM,0.34))
				_frame.draw_rect(Rect2(at+Vector2(2,2),Vector2(28,28)),PROBLEM,false,2.0)
	_frame.draw_rect(Rect2(top_left,extent),Color(0.18,0.22,0.16,0.55),false,4.0)
	_frame.draw_rect(Rect2(top_left,extent),tint,false,2.0)

func _draw_capture() -> void:
	var rect:=capture_rect.abs()
	if rect.size.x<=0 or rect.size.y<=0:return
	var too_big:=rect.size.x>Design.SIZE_MAX or rect.size.y>Design.SIZE_MAX or rect.size.x*rect.size.y>Design.MAX_AREA_CELLS
	var edge:=BAD if too_big else CAPTURE_EDGE
	var at:=screen(Vector2(rect.position))
	var extent:=Vector2(rect.size)*TILE
	_frame.draw_rect(Rect2(at,extent),Color(BAD,0.2) if too_big else CAPTURE_FILL)
	_frame.draw_rect(Rect2(at,extent),edge,false,2.0)
	var label_font:Font=source_view.get("font") as Font
	if label_font==null:label_font=ThemeDB.fallback_font
	if label_font==null:return
	var text:="%d×%d 格"%[rect.size.x,rect.size.y]
	if too_big:text+=" · 最大 %d×%d"%[Design.SIZE_MAX,Design.SIZE_MAX]
	var width:=label_font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,13).x
	var anchor:=at+Vector2(minf(extent.x*0.5,width*0.5+8),-10)
	_frame.draw_style_box(label_box(),Rect2(anchor+Vector2(-width/2-6,-16),Vector2(width+12,24)))
	_frame.draw_string(label_font,anchor+Vector2(-width/2,1),text,HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("fff2ce"))

## Copies camera/zoom/art reference from the live world view. False when there
## is nothing valid to follow.
func _sync_view() -> bool:
	if not is_instance_valid(source_view):return false
	var cam:Variant=source_view.get("camera")
	if cam is Vector2:camera=cam
	var art:Variant=source_view.get("village_art")
	village_art=art if art is RefCounted else null
	var factor:=2.0
	if source_view.has_method("view_zoom"):
		var value:Variant=source_view.call("view_zoom")
		if typeof(value) in [TYPE_FLOAT,TYPE_INT]:factor=float(value)
	_view_zoom=factor if factor>0.0 else 1.0
	return true

func _source_region() -> String:
	if source_view.has_method("region_id"):return str(source_view.call("region_id"))
	return "home"

func _source_time() -> float:
	var source_data:Variant=source_view.get("data")
	if source_data is Dictionary:
		var t:Variant=(source_data as Dictionary).get("time",0.0)
		if typeof(t) in [TYPE_FLOAT,TYPE_INT]:return float(t)
	return 0.0

## {pieces, size, origin, turns} of the rotated draft, or {} when the
## controller is not placing a valid design. Rotation is cached per draft/turns.
func _layout() -> Dictionary:
	if not is_instance_valid(controller):return {}
	if str(controller.get("mode")) not in GHOST_MODES:return {}
	var draft_value:Variant=controller.get("draft")
	if not (draft_value is Dictionary):return {}
	var draft:Dictionary=draft_value
	if draft.is_empty():return {}
	var origin_value:Variant=controller.get("origin")
	if not (origin_value is Vector2i):return {}
	var turns_value:Variant=controller.get("turns")
	var turns:=int(turns_value) if typeof(turns_value)==TYPE_INT else 0
	var cache_key:Array=[draft.hash(),turns]
	if cache_key!=_rotated_key:
		_rotated_key=cache_key
		_rotated={}
		var result:Dictionary=Design.rotate(draft,turns,World.BUILD,World.NAMES)
		if result.get("ok")==true and result.get("blueprint") is Dictionary:_rotated=result.blueprint
	if _rotated.is_empty():return {}
	return {"pieces":_rotated.pieces,"size":Vector2i(int(_rotated.width),int(_rotated.height)),"origin":origin_value,"turns":turns}

## The controller's quote only while it is the authoritative answer for the
## pinned origin/rotation (controller clears quote on move/rotate/reposition).
func _current_quote(origin:Vector2i,turns:int) -> Dictionary:
	if controller.get("quote_waiting")==true or controller.get("locked")!=true:return {}
	var value:Variant=controller.get("quote")
	if not (value is Dictionary):return {}
	var quote:Dictionary=value
	if quote.is_empty() or not quote.has("ok"):return {}
	if quote.has("origin") and quote.origin is Vector2i and quote.origin!=origin:return {}
	if quote.has("turns") and typeof(quote.turns)==TYPE_INT and int(quote.turns)!=turns:return {}
	return quote
