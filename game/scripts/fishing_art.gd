extends RefCounted

const ICONS=preload("res://assets/ui-life/icons.png")
const FISH_ATLAS=preload("res://assets/ui-inventory/items.png")
const Items=preload("res://scripts/inventory_item_art.gd")
const Feedback=preload("res://scripts/fishing_feedback.gd")
const Tracking=preload("res://scripts/fishing_tracking.gd")
const Pixel=preload("res://scripts/inventory_pixel_theme.gd")
const SPLASH_ATLAS=preload("res://assets/fishing/fishing-splash.png")
const ROD:=Rect2(64,32,25,32)
const ROD_TINTS:={"copper_rod":Color("ffd1ba"),"iron_rod":Color("b3edff"),"precision_rod":Color("8efee7")}
const FLOAT:=Rect2(89,44,6,11)
const BELL:=Rect2(96,64,32,32)
const TROPHY:=Rect2(64,96,32,32)
const LINE_COLOR:=Color("eee3c2")
const REEL_DURATION:=Feedback.REEL_DURATION
const SURFACE_PULL:=0.13
static var ready_tag:StyleBoxTexture

static func angler_lean(state:Dictionary,elapsed:float,reduced_motion:bool)->float:
	if reduced_motion:return 0.0
	match state.get("phase",""):
		"wait":
			return 1.2*sin(elapsed*1.8)
		"cast":
			return 5.0*sin(PI*clampf(float(state.age)/Feedback.CAST_DURATION,0.0,1.0))
		"ready":
			return 1.0+3.0*bite_pull(float(state.age))
		"catch":
			var brace:=clampf(float(state.age)/REEL_DURATION,0.0,1.0)
			return -7.0*sin(PI*brace)
	return 0.0

static func bite_pull(age:float)->float:
	# A sharp first tug, then smaller tugs while the fish stays on the line.
	var cycle:=fposmod(age,0.9)
	if cycle>=0.34:return 0.0
	return sin(PI*cycle/0.34)*(1.0 if age<0.9 else 0.58)

static func draw_tracking(canvas:CanvasItem,at:Vector2,cast:Dictionary,now:float)->void:
	if ready_tag==null:ready_tag=Pixel.texture_style("paper",3,4)
	var origin:=at.round()+Vector2(-51,17)
	var track:=Rect2(origin+Vector2(6,6),Vector2(90,13))
	canvas.draw_style_box(ready_tag,Rect2(origin,Vector2(102,29)))
	canvas.draw_rect(track,Color("384739"))
	var half_width:=Tracking.band_half_width(cast)
	var lower:=maxf(0.0,float(cast.band)-half_width)
	var upper:=minf(1.0,float(cast.band)+half_width)
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

static func draw(canvas:CanvasItem,foot:Vector2,target:Vector2,state:Dictionary,reduced_motion:bool,elapsed:float,zoom:float=1.0)->void:
	var phase:String=state.phase
	var age:float=state.age
	var side:=1.0 if target.x>=foot.x else -1.0
	var hand:=(foot+Vector2(side*9,-15)).round()
	var rod_tint:Color=ROD_TINTS.get(state.get("rod",""),Color.WHITE)
	if phase=="cancel":
		if reduced_motion:return
		var progress:=clampf(age/Feedback.CANCEL_DURATION,0.0,1.0)
		var ink:=Color(1.0,1.0,1.0,1.0-smoothstep(0.65,1.0,progress))
		var tip:=draw_rod(canvas,hand,side,-side*0.45*sin(PI*progress),zoom,rod_tint*ink)
		var pull:=1.0-pow(1.0-progress,2.0)
		var float_at:=(target.lerp(tip,pull)+Vector2(0,-sin(PI*progress)*13.0)).round()
		canvas.draw_line(tip,float_at,LINE_COLOR*ink)
		canvas.draw_texture_rect_region(ICONS,Rect2(float_at-Vector2(3,7),FLOAT.size),FLOAT,ink)
		if progress<0.75:draw_landing(canvas,target.round(),progress/0.75)
		return
	if phase=="catch":
		var species:String=state.get("fish","")
		if state.get("released",false):
			draw_release(canvas,hand,side,target,species,age,reduced_motion,zoom,rod_tint)
			return
		var at:=foot+Vector2(side*25,-36)
		var size:=32.0
		if not reduced_motion:
			var lift:=clampf((age-SURFACE_PULL)/(REEL_DURATION-SURFACE_PULL),0.0,1.0)
			var pull:=clampf(age/SURFACE_PULL,0.0,1.0)
			var surface:=target.lerp(foot,0.17*pull).round()
			var reel:=smoothstep(0.0,1.0,lift)
			at=surface.lerp(at,reel)+Vector2(0,-sin(PI*lift)*34.0-minf(age*18.0,12.0)*reel)
			# A short settling flutter, using the actual catch PNG without scaling its pixels.
			if age>REEL_DURATION:
				var settle:=clampf((age-REEL_DURATION)/(Feedback.CATCH_DURATION-REEL_DURATION),0.0,1.0)
				at+=Vector2(roundf(sin(settle*TAU*2.0)*3.0*(1.0-settle)), -roundf(absf(sin(settle*TAU*2.0))*3.0*(1.0-settle)))
			size=roundf(lerpf(18.0,32.0,reel))
			if reel<1.0:
				var sweep:=clampf(age/REEL_DURATION,0.0,1.0)
				hand.x-=side*roundf(sin(sweep*PI)*4.0)
				var reel_tip:=draw_rod(canvas,hand,side,-side*0.78*sin(sweep*PI*0.8),zoom,rod_tint)
				canvas.draw_line(reel_tip,at.round(),LINE_COLOR)
			if age<0.24:
				draw_hook_splash(canvas,surface,age/0.24)
			if age>=REEL_DURATION:draw_catch_glint(canvas,at.round(),(age-REEL_DURATION)/(Feedback.CATCH_DURATION-REEL_DURATION))
		var badge:=Rect2((at-Vector2.ONE*size*0.5).round(),Vector2.ONE*size)
		var icon:=Items.icon(species)
		if icon:
			canvas.draw_texture_rect(icon,badge,false)
		else:
			canvas.draw_texture_rect_region(ICONS,badge,TROPHY)
		return
	var reach:=0.0
	if not reduced_motion and phase=="wait":
		hand.y+=roundf(sin(elapsed*1.8))
	if not reduced_motion and phase=="cast":
		reach=roundf(5.0*sin(PI*clampf(age/Feedback.CAST_DURATION,0.0,1.0)))
	hand.x+=side*reach
	var bite:=phase=="ready"
	var angle:=0.0
	if not reduced_motion:
		if phase=="cast":
			var swing:=clampf(age/Feedback.CAST_DURATION,0.0,1.0)
			angle=side*sin(swing*TAU)*lerpf(-0.78,-0.36,swing)
		elif bite:
			angle=side*0.44*bite_pull(age)
		elif phase=="wait":
			angle=side*0.035*sin(elapsed*1.8)
	var tip:=draw_rod(canvas,hand,side,angle,zoom,rod_tint)
	var float_at:=target.round()
	var airborne:=phase=="cast" and not reduced_motion
	if airborne:
		var t:=clampf(age/Feedback.CAST_DURATION,0.0,1.0)
		float_at=(tip.lerp(target,t)+Vector2(0,-sin(t*PI)*27.0)).round()
	elif not reduced_motion:
		float_at.y+=roundf(10.0*bite_pull(age) if bite else sin(elapsed*3.5))
	if not airborne:
		var water_at:=target.round()
		if not reduced_motion and not state.has("landing_age"):
			draw_fish_shadow(canvas,water_at,elapsed,bite)
		draw_ripple(canvas,water_at,elapsed,bite,reduced_motion)
		if not reduced_motion and state.has("landing_age"):
			draw_landing(canvas,water_at,float(state.landing_age)/Feedback.LANDING_DURATION)
	var slack:=6.0 if not airborne else -5.0
	if bite and not reduced_motion:slack*=1.0-bite_pull(age)
	var bend:=((tip+float_at)*0.5+Vector2(0,slack)).round()
	canvas.draw_polyline(PackedVector2Array([tip,bend,float_at]),LINE_COLOR,1.0)
	# Keep the float at the surface and crop its submerged portion.
	var visible_height:=FLOAT.size.y
	if bite and not reduced_motion:
		visible_height=clampf(target.round().y+4.0-(float_at.y-7.0),0.0,FLOAT.size.y)
	if visible_height>0.0:
		var visible_size:=Vector2(FLOAT.size.x,visible_height)
		canvas.draw_texture_rect_region(ICONS,Rect2(float_at-Vector2(3,7),visible_size),Rect2(FLOAT.position,visible_size))
	if bite:
		if not reduced_motion:draw_bite_splash(canvas,target.round(),age)
		var marker_y:=0.0 if reduced_motion else -roundf(4.0*bite_pull(age))
		canvas.draw_texture_rect_region(ICONS,Rect2(target.round()+Vector2(8,-38+marker_y),Vector2(32,32)),BELL)

static func draw_release(canvas:CanvasItem,hand:Vector2,side:float,target:Vector2,species:String,age:float,reduced_motion:bool,zoom:float,tint:Color) -> void:
	var icon:=Items.icon(species)
	if not icon:return
	if reduced_motion:
		canvas.draw_texture_rect(icon,Rect2(target.round()-Vector2(12,32),Vector2(24,24)),false)
		return
	var leap:=Feedback.RELEASE_LEAP
	var surface:=(target+Vector2(side*9,0)).round()
	if age<leap:
		var progress:=age/leap
		var arc:=(target.lerp(surface,progress)+Vector2(0,-30.0*sin(progress*PI))).round()
		var wrist:=draw_rod(canvas,hand,side,-side*0.52*sin(progress*PI),zoom,tint)
		if progress<0.43:canvas.draw_line(wrist,arc,LINE_COLOR)
		canvas.draw_texture_rect(icon,Rect2(arc-Vector2(12,12),Vector2(24,24)),false)
		if age<0.20:draw_hook_splash(canvas,target,age/0.20)
	else:
		draw_landing(canvas,surface,(age-leap)/(Feedback.CATCH_DURATION-leap))

static func draw_rod(canvas:CanvasItem,hand:Vector2,side:float,angle:float,zoom:float,tint:=Color.WHITE)->Vector2:
	var scale_value:=Vector2.ONE*zoom
	canvas.draw_set_transform(hand*zoom,angle,scale_value)
	canvas.draw_texture_rect_region(ICONS,Rect2(Vector2(-7 if side>0 else -18,-27),Vector2(side*ROD.size.x,ROD.size.y)),ROD,tint)
	canvas.draw_set_transform(Vector2.ZERO,0.0,scale_value)
	return (hand+Vector2(side*16,-25).rotated(angle)).round()

static func draw_landing(canvas:CanvasItem,at:Vector2,progress:float)->void:
	# Top row of the splash sheet: the bobber landing in water.
	draw_splash_frame(canvas,at,progress,0)

static func draw_hook_splash(canvas:CanvasItem,at:Vector2,progress:float)->void:
	# Bottom row of the splash sheet: the fish being pulled up.
	draw_splash_frame(canvas,at,progress,1)

static func draw_splash_frame(canvas:CanvasItem,at:Vector2,progress:float,row:int)->void:
	# Three 32px frames per row; cell point (16,28) sits on the water contact point.
	var step:=mini(2,int(clampf(progress,0.0,1.0)*3))
	var source:=Rect2(Vector2(step,row)*32.0,Vector2(32,32))
	var dest:=Rect2(at.round()-Vector2(16,28),Vector2(32,32))
	var tint:=Color(1.0,1.0,1.0,1.0-smoothstep(0.68,1.0,progress))
	canvas.draw_texture_rect_region(SPLASH_ATLAS,dest,source,tint)

static func draw_fish_shadow(canvas:CanvasItem,at:Vector2,elapsed:float,bite:bool)->void:
	# Stay within the selected water tile even when fishing beside the bank.
	var phase:=elapsed*(3.8 if bite else 1.9)
	var heading:=signf(cos(phase))
	var center:=at+Vector2(roundf(sin(phase)*(4.0 if bite else 8.0)),10-roundf(2.0*cos(phase)))
	var tail:=roundf(sin(phase*2.0))
	var ink:=Color(0.08,0.28,0.32,0.56 if bite else 0.44)
	canvas.draw_rect(Rect2(center-Vector2(3,2),Vector2(7,4)),ink)
	canvas.draw_rect(Rect2(center+Vector2(heading*4,-1),Vector2(1,2)),ink)
	canvas.draw_rect(Rect2(center+Vector2(-heading*4,-1),Vector2(1,2)),ink)
	canvas.draw_rect(Rect2(center+Vector2(-heading*5,tail-1),Vector2(1,3)),ink)

static func draw_catch_glint(canvas:CanvasItem,at:Vector2,progress:float)->void:
	var tint:=Color("ffe6a2")
	tint.a=sin(progress*PI)
	var spread:=roundf(progress*6.0)
	var left:=at+Vector2(-15.0-spread,-9.0-spread)
	var right:=at+Vector2(15.0+spread,6.0-spread)
	canvas.draw_rect(Rect2(left-Vector2(1,3),Vector2(2,6)),tint)
	canvas.draw_rect(Rect2(left-Vector2(3,1),Vector2(6,2)),tint)
	canvas.draw_rect(Rect2(right,Vector2(2,2)),tint)

static func draw_bite_splash(canvas:CanvasItem,at:Vector2,elapsed:float)->void:
	var cycle:=fposmod(elapsed,0.9)
	if cycle>=0.34:return
	var progress:=cycle/0.34
	var lift:=roundf(sin(progress*PI)*10.0)
	var spread:=roundf(4.0+8.0*progress)
	var tint:=Color("d9fff3")
	tint.a=1.0-progress*0.75
	canvas.draw_rect(Rect2(at+Vector2(-spread,-lift),Vector2(2,3)),tint)
	canvas.draw_rect(Rect2(at+Vector2(spread,-lift-2),Vector2(2,3)),tint)
	canvas.draw_rect(Rect2(at+Vector2(2,-lift*0.6),Vector2(2,2)),tint)

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
