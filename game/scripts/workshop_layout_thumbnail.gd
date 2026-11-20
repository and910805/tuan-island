extends "res://scripts/blueprint_thumbnail.gd"
## Same real sprites/whole-pixel fitting as the blueprint book, plus guide marks
## and a preview-only lesson overlay (placement reveal, stage marks, item flow).
## Nothing here touches the world: it only redraws a copy of the lesson layout.
const GuideItems=preload("res://scripts/inventory_item_art.gd")
const GUIDE_SCALES:=[4.0,3.0,2.0,1.5,1.0]
const REVEAL_STEP:=0.7
const REVEAL_HOLD:=1.6
const FLOW_SPEED:=0.45
const CREAM:=Color(1.0,0.96,0.83,0.92)
const TEAL:=Color("4f8a78")
const GOLD:=Color("d9ab57")
const FLOW_COLORS:={"water":Color("5aaee8"),"wood":Color("c99a58"),"plank":Color("e3c27c"),"charcoal":Color("8b8f96")}

var markers:Array=[]
var selected_kind:=""
## False means the readable static equivalent: final placement, chevron paths.
var animated:=false
var source:Dictionary={}
var step:Dictionary={}
var _shown:=-1

func _ready()->void:
	super._ready()
	crop_art=CropSprites.new()
	if not crop_art.setup():crop_art=null

func fit_scale(content:Vector2)->float:
	for candidate:float in GUIDE_SCALES:
		if content.x*candidate<=box_size.x and content.y*candidate<=box_size.y:return candidate
	return super.fit_scale(content)

## Shows one lesson stage. `layout` is the real lesson design and is never edited.
func show_step(layout:Dictionary,data:Dictionary,motion:bool)->void:
	source=layout
	step=data
	animated=motion
	elapsed=0.0
	_shown=-1
	set_process(animated and is_inside_tree())
	_sync()
	queue_redraw()

func replay()->void:
	if not animated:return
	seek(0.0)
	set_process(true)

## Freezes the animation at a moment. Used by captures and tests.
func seek(time:float)->void:
	elapsed=maxf(time,0.0)
	_sync()
	queue_redraw()

func total_pieces()->int:
	var pieces:Array=source.get("pieces",[])
	return clampi(int(step.get("placed",pieces.size())),1,maxi(pieces.size(),1))

func start_pieces()->int:
	return clampi(int(step.get("from",total_pieces())),0,total_pieces())

func reveal_count()->int:
	var total:=total_pieces()
	var first:=start_pieces()
	if not animated or first>=total:return total
	var interval:=float(step.get("reveal_interval",REVEAL_STEP))
	var cycle:=interval*float(total-first)+REVEAL_HOLD
	return clampi(first+1+int(fmod(elapsed,cycle)/interval),first+1,total)

## Read-only view of what the preview is showing, for tests and captures.
func state_report()->Dictionary:
	var flows:Array=step.get("flows",[])
	var marks:Array=step.get("marks",[])
	return {"animated":animated,"visible":reveal_count(),"total":total_pieces(),"flows":flows.size(),"marks":marks.size(),"time":elapsed}

func _process(delta:float)->void:
	if not is_visible_in_tree():return
	elapsed+=delta
	_sync()
	queue_redraw()

func _sync()->void:
	if source.is_empty() or not (source.get("pieces") is Array):return
	var count:=reveal_count()
	if count==_shown:return
	_shown=count
	var result:=source.duplicate(true)
	var pieces:Array=result.pieces
	result.pieces=pieces.slice(0,count)
	design=result

func _at(cell:Vector2)->Vector2:
	return MARGIN_TOP_LEFT+cell*float(TILE)

func _draw()->void:
	super._draw()
	if _cells==Vector2i.ZERO:return
	var content:=Vector2(_cells)*TILE+MARGIN_TOP_LEFT+MARGIN_BOTTOM_RIGHT
	var factor:=fit_scale(content)
	if factor<=0.0:return
	var offset:=((box_size-content*factor)*0.5).floor()
	draw_set_transform(offset,0,Vector2.ONE*factor)
	for marker:Dictionary in markers:
		var texture:=GuideItems.icon(str(marker.icon))
		if texture:draw_texture_rect(texture,Rect2(_at(Vector2(marker.x,marker.y)),Vector2(32,32)),false,Color(1,1,1,0.7))
	var focus:Array=step.get("focus",[])
	var pulse:float=0.65+0.35*sin(elapsed*5.0) if animated else 1.0
	for entry:Dictionary in _pieces:
		var at:=_at(Vector2(entry.x,entry.y))
		if str(entry.kind)==selected_kind:draw_rect(Rect2(at+Vector2(1,1),Vector2(30,30)),GOLD,false,1.0)
		if focus.has(str(entry.kind)):draw_rect(Rect2(at,Vector2(32,32)),Color(GOLD.r,GOLD.g,GOLD.b,pulse),false,2.0)
		if entry.kind=="conveyor":
			var arrow:String=["↑","→","↓","←"][int(entry.settings.dir)]
			var point:=at+Vector2(9,23)
			draw_string_outline(ThemeDB.fallback_font,point,arrow,HORIZONTAL_ALIGNMENT_LEFT,-1,20,2,Color("557a5e"))
			draw_string(ThemeDB.fallback_font,point,arrow,HORIZONTAL_ALIGNMENT_LEFT,-1,20,Color("fff5d5"))
	var marks:Array=step.get("marks",[])
	for mark:Dictionary in marks:_draw_mark(mark)
	var flows:Array=step.get("flows",[])
	for entry:Dictionary in flows:_draw_flow(entry)

func _draw_mark(mark:Dictionary)->void:
	var at:=_at(Vector2(mark.x,mark.y))
	var kind:=str(mark.kind)
	var cycle:=REVEAL_HOLD+2.0
	var phase:float=fmod(elapsed,cycle)/cycle if animated else 1.0
	if kind=="auto_roof":
		var alpha:=0.48*clampf((phase-0.10)*5.0,0.0,1.0)
		if alpha>0.0:roof_sprite(at,alpha,"roof")
		return
	var seed_icon:=GuideItems.icon("radish_seed")
	if kind in ["seed","planted","wet"]:
		var watered:=kind=="wet" and phase>0.45
		village_art.draw_tile(self,at,7 if watered else 15)
		var planting:=kind=="seed" and phase<0.48
		if planting and seed_icon:
			var drop:=lerpf(-12.0,7.0,clampf(phase/0.32,0.0,1.0))
			draw_texture_rect(seed_icon,Rect2(at+Vector2(6,drop).round(),Vector2(20,20)),false)
		elif crop_art:
			crop_art.draw_crop(self,at,{"kind":"radish","growth":0.0,"wet":watered},false,0)
	if kind=="wet":
		if phase>0.45:
			for drop in 3:draw_circle(at+Vector2(8+drop*8,12+(drop%2)*9),1.5,Color(0.72,0.9,1.0,0.9))
	if kind=="grow":
		var sapling:=GuideItems.icon("sapling")
		var wood:=GuideItems.icon("wood")
		if sapling:draw_texture_rect(sapling,Rect2(at+Vector2(4,4),Vector2(24,24)),false)
		if wood:
			var grown:float=1.0 if not animated else clampf((phase-0.4)*4.0,0.0,1.0)
			if grown>0.0:
				draw_circle(at+Vector2(24,24),9.0,Color(CREAM.r,CREAM.g,CREAM.b,0.9*grown))
				draw_texture_rect(wood,Rect2(at+Vector2(16,16),Vector2(16,16)),false,Color(1,1,1,grown))

func _draw_flow(entry:Dictionary)->void:
	var path:Array=entry.get("path",[])
	if path.size()<2:return
	var item:=str(entry.get("item",""))
	var points:=PackedVector2Array()
	for cell:Vector2 in path:points.append(_at(cell))
	var tint:Color=FLOW_COLORS.get(item,GOLD)
	draw_polyline(points,Color(CREAM.r,CREAM.g,CREAM.b,0.5),5.0,true)
	draw_polyline(points,Color(tint.r,tint.g,tint.b,0.85),2.0,true)
	if animated:
		var total:=_length(points)
		var count:=clampi(int(total/52.0),1,4)
		var base:=fmod(elapsed*FLOW_SPEED,1.0)
		for index in count:
			_badge(_along(points,fmod(base+float(index)/float(count),1.0),total),item,tint)
		return
	for index in points.size()-1:
		var start:=points[index]
		var finish:=points[index+1]
		var heading:=(finish-start).normalized()
		var side:=Vector2(-heading.y,heading.x)
		var middle:=(start+finish)*0.5
		var arrow:=PackedVector2Array([middle+heading*6.0,middle-heading*4.0+side*5.0,middle-heading*4.0-side*5.0])
		draw_colored_polygon(arrow,CREAM)
		draw_polyline(PackedVector2Array([arrow[0],arrow[1],arrow[2],arrow[0]]),TEAL,1.0)
	if item!="water":_badge(points[0]+Vector2(0,-11),item,tint)

func _badge(at:Vector2,item:String,tint:Color)->void:
	draw_circle(at,10.0,CREAM)
	draw_arc(at,10.0,0.0,TAU,20,TEAL,1.0)
	if item=="water":
		draw_circle(at+Vector2(0,2),5.0,tint)
		draw_colored_polygon(PackedVector2Array([at+Vector2(0,-6),at+Vector2(-4.5,0),at+Vector2(4.5,0)]),tint)
		draw_circle(at+Vector2(-1.5,1),1.2,Color(1,1,1,0.85))
		return
	var texture:=GuideItems.icon(item)
	if texture:draw_texture_rect(texture,Rect2(at-Vector2(8,8),Vector2(16,16)),false)

func _length(points:PackedVector2Array)->float:
	var total:=0.0
	for index in points.size()-1:total+=points[index].distance_to(points[index+1])
	return total

func _along(points:PackedVector2Array,fraction:float,total:float)->Vector2:
	var left:=fraction*total
	for index in points.size()-1:
		var length:=points[index].distance_to(points[index+1])
		if left<=length and length>0.0:return points[index].lerp(points[index+1],left/length)
		left-=length
	return points[points.size()-1]
