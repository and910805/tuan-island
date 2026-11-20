extends RefCounted
## T066 N04-4: a cozy pixel vignette of the guest chair set beside the table, with the food or
## drink a guest is offered resting on it.
##
##   var view:=ChachaHandwrittenMenuArt.make(chair,reduced_motion)   # Control, 320x140 logical
##   view.show_item("tea_light"|"tea_deep"|"tea_pudding")
##
## chair is a TEA_CHAIRS key ("wood" / "coast"). Anything else (legacy / unknown / empty) draws the
## neutral view: table and offering only, no personal chair. Wood and coast keep distinct palettes.
## Motion is brief only: one steam puff (drinks) or one sunlight sweep (pudding) per show_item call,
## a stepped Tween (no _process, no timers, no input). reduced_motion draws the same scene static.

const Goals=preload("res://scripts/resident_goals.gd")
const TeaCeramicsArt=preload("res://scripts/tea_ceramics_art.gd")
const FURNITURE:Texture2D=preload("res://assets/ui-life/furniture.png")
const TEA_SET:Texture2D=preload("res://assets/ui-inventory/basic-tea-set.png")
const PUDDING:Texture2D=preload("res://assets/ui-inventory/tea-pudding.png")
const CHAIR_REGION:=Rect2(96,48,32,48)
const SIZE:=Vector2(320,140)
const STEPS:=10.0
const ITEMS:=["tea_light","tea_deep","tea_pudding"]
const PALETTES:={
	"wood":{"wall":"e8cfa4","wall2":"d9bb8a","floor":"a8794a","floor2":"94673c","sky":"f6e3b0","trim":"7a5232","table":"b98a58","table2":"8f6339","sun":"fff0b0"},
	"coast":{"wall":"cfe3df","wall2":"b4d1ce","floor":"b49a78","floor2":"9f8666","sky":"a9d6e8","trim":"5d7f86","table":"c2a67e","table2":"967c58","sun":"e8fbff"},
	"":{"wall":"e6d8bd","wall2":"d3c2a2","floor":"a98a62","floor2":"957852","sky":"f0e2bc","trim":"7a6247","table":"b99a6c","table2":"8f7549","sun":"fff2c0"},
}

static func make(chair:String="",reduced_motion:bool=false)->Control:
	var view:=Vignette.new()
	view.chair=chair if Goals.TEA_CHAIRS.has(chair) else ""
	view.reduced=reduced_motion
	view.custom_minimum_size=SIZE
	view.size=SIZE
	return view

class Vignette extends Control:
	var chair:=""
	var reduced:=false
	var item:="tea_light"
	var _t:=1.0
	var _animating:=false
	var _tween:Tween

	func _ready()->void:
		texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
		mouse_filter=Control.MOUSE_FILTER_IGNORE
		clip_contents=true
		custom_minimum_size=SIZE

	## Select the offering; plays one short steam/sunlight accent unless reduced motion.
	func show_item(next:String)->void:
		item=next if next in ITEMS else "tea_light"
		if reduced:
			_t=1.0
			_animating=false
			queue_redraw()
			return
		_play(1.0)

	func is_animating()->bool:
		return _animating

	func _play(seconds:float)->void:
		if _tween:_tween.kill()
		if not is_inside_tree():
			_finish()
			return
		_animating=true
		_t=0.0
		queue_redraw()
		_tween=create_tween()
		_tween.tween_method(_step,0.0,1.0,seconds)
		_tween.tween_callback(_finish)

	func _step(value:float)->void:
		var stepped:=floorf(value*STEPS)/STEPS
		if is_equal_approx(stepped,_t):return
		_t=stepped
		queue_redraw()

	func _finish()->void:
		_animating=false
		_t=1.0
		queue_redraw()

	func _r(x:float,y:float,w:float,h:float,color:Variant,alpha:float=1.0)->void:
		var c:=Color(color)
		c.a*=alpha
		draw_rect(Rect2(x,y,w,h),c)

	func _draw()->void:
		var p:Dictionary=PALETTES[chair]
		var chair_left:=chair!="coast"
		_room(p,chair_left)
		_sun(p,chair_left)
		if chair!="":_chair(chair_left)
		else:_neutral_spot(p)
		_table(p)
		_offering()
		_steam()

	func _room(p:Dictionary,chair_left:bool)->void:
		_r(0,0,320,100,p.wall)
		for x in range(0,320,16):_r(x,0,8,100,p.wall2,0.35)
		_r(0,92,320,8,p.trim)
		_r(0,100,320,40,p.floor)
		for y in [108,118,128]:_r(0,y,320,1,p.floor2)
		for x in range(8,320,40):_r(x,100,1,40,p.floor2,0.6)
		# window on the side opposite the chair
		var wx:=236.0 if chair_left else 40.0
		_r(wx-3,11,62,50,p.trim)
		_r(wx,14,56,44,p.sky)
		if chair=="coast":
			_r(wx,40,56,18,"6fb4cc")
			_r(wx,38,56,2,"ffffff",0.6)
			_r(wx+30,22,3,2,"ffffff")
			_r(wx+36,21,6,2,"ffffff")
		else:
			_r(wx,42,56,16,"8fae6a")
			_r(wx+10,36,18,6,"7a9a58")
		_r(wx+26,14,4,44,p.trim)
		_r(wx,34,56,3,p.trim)

	func _sun(p:Dictionary,chair_left:bool)->void:
		var wx:=236.0 if chair_left else 40.0
		var strength:=0.16
		if item=="tea_pudding" and not reduced:
			# one soft sweep: brightens then settles
			strength=0.12+0.2*sin(clampf(_t,0.0,1.0)*PI)
		elif item!="tea_pudding":
			strength=0.1
		var dx:=-70.0 if chair_left else 70.0
		var top:=PackedVector2Array([Vector2(wx+4,58),Vector2(wx+52,58),Vector2(wx+52+dx,128),Vector2(wx+4+dx,128)])
		var c:=Color(p.sun)
		c.a=strength
		draw_colored_polygon(top,c)

	func _neutral_spot(p:Dictionary)->void:
		# no personal chair: just a bare patch of floor where one could be set
		_r(58,126,44,3,p.floor2,0.55)

	func _chair(chair_left:bool)->void:
		var tint:Color=Goals.TEA_CHAIRS[chair].tint
		var x:=36.0 if chair_left else 220.0
		_r(x+6,128,52,5,"000000",0.18)
		if chair_left:
			draw_texture_rect_region(FURNITURE,Rect2(x,40,64,96),CHAIR_REGION,tint)
		else:
			draw_set_transform(Vector2(x+64,0),0.0,Vector2(-1,1))
			draw_texture_rect_region(FURNITURE,Rect2(0,40,64,96),CHAIR_REGION,tint)
			draw_set_transform(Vector2.ZERO,0.0,Vector2.ONE)

	func _table(p:Dictionary)->void:
		_r(112,134,96,3,"000000",0.15)
		_r(116,104,6,30,p.table2)
		_r(198,104,6,30,p.table2)
		_r(112,100,96,5,p.table2)
		_r(108,94,104,7,p.table)
		_r(108,94,104,1,"ffffff",0.25)
		# small linen runner
		_r(128,95,64,3,"f4ead6" if chair!="coast" else "e2f1ef")

	func _offering()->void:
		if item=="tea_pudding":
			draw_texture_rect(PUDDING,Rect2(124,30,64,64),false)
		else:
			var icon:Texture2D=TeaCeramicsArt.icon(item)
			if icon:draw_texture_rect(icon,Rect2(124,30,64,64),false)
		# the basic tea set beside the offering, scaled to fit a small box
		var s:=TEA_SET.get_size()
		if s.x>0.0 and s.y>0.0:
			var k:=minf(1.0,minf(22.0/s.x,26.0/s.y))
			var w:=roundf(s.x*k)
			var h:=roundf(s.y*k)
			draw_texture_rect(TEA_SET,Rect2(190,94-h,w,h),false)

	func _steam()->void:
		if item=="tea_pudding":return
		var drinks:=item=="tea_deep"
		var base:=Color(1,1,1)
		if reduced:
			# static faint wisps, no motion
			for i in 3:_r(148+i*6,24-(i%2)*3,2,6,base,0.35)
			return
		if not _animating:return
		var rise:=_t*18.0
		var fade:=1.0-_t
		for i in 3:
			var x:=142.0+i*10.0+(2.0 if int(_t*STEPS+i)%2==0 else -2.0)
			var y:=36.0-rise-i*4.0
			_r(x,y,3,5,base,0.55*fade)
			_r(x+(1 if drinks else -1),y-6,2,4,base,0.35*fade)
