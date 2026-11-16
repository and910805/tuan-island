extends RefCounted

const ICONS=preload("res://assets/ui-life/icons.png")
const FISH_ATLAS=preload("res://assets/ui-inventory/items.png")
const Items=preload("res://scripts/inventory_item_art.gd")
const Feedback=preload("res://scripts/fishing_feedback.gd")
const Tracking=preload("res://scripts/fishing_tracking.gd")
const Pixel=preload("res://scripts/inventory_pixel_theme.gd")
const ROD:=Rect2(64,32,25,32)
const FLOAT:=Rect2(89,44,6,11)
const BELL:=Rect2(96,64,32,32)
const TROPHY:=Rect2(64,96,32,32)
const LINE_COLOR:=Color("eee3c2")
static var ready_tag:StyleBoxTexture

static func draw_tracking(canvas:CanvasItem,at:Vector2,cast:Dictionary,now:float)->void:
	if ready_tag==null:ready_tag=Pixel.texture_style("paper",3,4)
	var origin:=at.round()+Vector2(-51,17)
	var track:=Rect2(origin+Vector2(6,6),Vector2(90,13))
	canvas.draw_style_box(ready_tag,Rect2(origin,Vector2(102,29)))
	canvas.draw_rect(track,Color("384739"))
	var lower:=maxf(0.0,float(cast.band)-Tracking.HALF_WIDTH)
	var upper:=minf(1.0,float(cast.band)+Tracking.HALF_WIDTH)
	canvas.draw_rect(Rect2(track.position+Vector2(roundf(lower*90),0),Vector2(roundf((upper-lower)*90),13)),Color("a4b983"))
	var marker:=track.position+Vector2(roundf(Tracking.shadow(float(cast.ready),now)*90),6)
	canvas.draw_texture_rect_region(FISH_ATLAS,Rect2(marker-Vector2(9,9),Vector2(18,18)),Rect2(96,32,32,32))
	var progress:=Tracking.progress(cast,now)/Tracking.DURATION
	canvas.draw_rect(Rect2(origin+Vector2(6,22),Vector2(90,3)),Color("967657"))
	canvas.draw_rect(Rect2(origin+Vector2(6,22),Vector2(roundf(90*progress),3)),Color("42654d"))

static func draw_ready_label(canvas:CanvasItem,at:Vector2,font:Font)->void:
	if ready_tag==null:ready_tag=Pixel.texture_style("paper",3,4)
	var center:=at.round()+Vector2(0,16)
	canvas.draw_style_box(ready_tag,Rect2(center-Vector2(20,0),Vector2(40,23)))
	canvas.draw_string(font,center+Vector2(-14,16),"收竿",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("3d422d"))

static func draw(canvas:CanvasItem,foot:Vector2,target:Vector2,state:Dictionary,reduced_motion:bool,elapsed:float)->void:
	var phase:String=state.phase
	var age:float=state.age
	if phase=="cancel":return
	var side:=1.0 if target.x>=foot.x else -1.0
	var hand:=(foot+Vector2(side*9,-15)).round()
	if phase=="catch":
		var species:String=state.get("fish","")
		var at:=(foot+Vector2(side*25,-36-(0 if reduced_motion else minf(age*26.0,22.0)))).round()
		var badge:=Rect2(at-Vector2(16,16),Vector2(32,32))
		var icon:=Items.icon(species)
		if icon:
			canvas.draw_texture_rect(icon,badge,false)
		else:
			canvas.draw_texture_rect_region(ICONS,badge,TROPHY)
		return
	var reach:=0.0
	if not reduced_motion and phase=="cast":
		reach=roundf(5.0*sin(PI*clampf(age/Feedback.CAST_DURATION,0.0,1.0)))
	hand.x+=side*reach
	var rod_at:=hand-Vector2(7 if side>0 else 18,27)
	canvas.draw_texture_rect_region(ICONS,Rect2(rod_at,Vector2(side*ROD.size.x,ROD.size.y)),ROD)
	var tip:=hand+Vector2(side*16,-25)
	var bite:=phase=="ready"
	var float_at:=target.round()
	var airborne:=phase=="cast" and not reduced_motion
	if airborne:
		var t:=clampf(age/Feedback.CAST_DURATION,0.0,1.0)
		float_at=(tip.lerp(target,t)+Vector2(0,-sin(t*PI)*27.0)).round()
	elif not reduced_motion:
		float_at.y+=roundf(sin(elapsed*(10.0 if bite else 3.5))*(2.0 if bite else 1.0))
	if not airborne:draw_ripple(canvas,target.round(),elapsed,bite,reduced_motion)
	var bend:=((tip+float_at)*0.5+Vector2(0,6 if not airborne else -5)).round()
	canvas.draw_polyline(PackedVector2Array([tip,bend,float_at]),LINE_COLOR,1.0)
	canvas.draw_texture_rect_region(ICONS,Rect2(float_at-Vector2(3,7),FLOAT.size),FLOAT)
	if bite:
		var marker_y:=0.0 if reduced_motion else roundf(2.0*sin(elapsed*8.0))
		canvas.draw_texture_rect_region(ICONS,Rect2(float_at+Vector2(8,-38+marker_y),Vector2(32,32)),BELL)

static func draw_ripple(canvas:CanvasItem,at:Vector2,elapsed:float,bite:bool,reduced_motion:bool)->void:
	var progress:=0.38 if reduced_motion else fposmod(elapsed*(1.65 if bite else 0.82),1.0)
	var width:=roundf(6.0+progress*7.0)
	var height:=roundf(width*0.4)
	var tint:=Color("c9eee7") if bite else Color("8ed4cb")
	tint.a=0.85-progress*0.50
	canvas.draw_polyline(PackedVector2Array([
		at+Vector2(-width,0),at+Vector2(-width+3,height),at+Vector2(width-3,height),at+Vector2(width,0),
	]),tint,1.0)
	canvas.draw_polyline(PackedVector2Array([
		at+Vector2(-width,-2),at+Vector2(-width+3,-height-2),at+Vector2(width-3,-height-2),at+Vector2(width,-2),
	]),tint,1.0)
