extends RefCounted
## T066 N04-3: a cozy pixel vignette of a small evening conversation at the Maokong pavilion.
## Chacha (actual tea-ceramics host portrait) talks over the actual basic tea set sprite with a
## visitor seen from behind, bamboo rail in front, Taipei lights fading in the valley.
##
##   var view:=ChachaTeaGatheringArt.make(reduced_motion)   # Control, 320x160 logical
##   view.show_topic(0|1|2)                                  # 0 tea, 1 weather, 2 learning
##
## Motion is brief only: one entrance play and one short accent per show_topic call, driven by a
## stepped Tween (no _process, no timers). reduced_motion draws the same scene fully static.

const TeaResidentArt=preload("res://scripts/tea_resident_art.gd")
const TEA_SET:Texture2D=preload("res://assets/ui-inventory/basic-tea-set.png")
const SIZE:=Vector2(320,160)
const STEPS:=12.0
const SKY:=["3b2f5c","5a3f6e","8a4f73","c0635f","e08a55","f0b469"]
const TOPIC_COLORS:=["c98a5a","6a8fb5","6fa05a"]

static func make(reduced_motion:bool=false)->Control:
	var view:=Vignette.new()
	view.reduced=reduced_motion
	view.custom_minimum_size=SIZE
	view.size=SIZE
	return view

class Vignette extends Control:
	var reduced:=false
	var topic:=0
	var _t:=1.0
	var _animating:=false
	var _tween:Tween

	func _ready()->void:
		texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
		mouse_filter=Control.MOUSE_FILTER_IGNORE
		clip_contents=true
		custom_minimum_size=SIZE
		if not reduced:_play(1.4)

	## Fast visual accent: 0 tea (steam), 1 weather (wind + leaves), 2 learning (book + sprout).
	func show_topic(index:int)->void:
		topic=clampi(index,0,2)
		if reduced:
			_t=1.0
			_animating=false
			queue_redraw()
			return
		_play(0.9)

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

	func _r(x:float,y:float,w:float,h:float,color:Variant)->void:
		draw_rect(Rect2(x,y,w,h),Color(color))

	func _draw()->void:
		_sky_and_hills()
		_pavilion()
		_chacha()
		_guest()
		_rail()
		_floor_and_table()
		_steam()
		_bubble()
		_leaves()

	func _sky_and_hills()->void:
		for i in SKY.size():_r(0,i*14,320,14,SKY[i])
		for dy in range(-9,10):
			var half:=int(sqrt(maxf(0.0,81.0-dy*dy)))
			_r(180-half,68+dy,half*2,1,"ffd98a")
		for x in range(0,320,4):
			_r(x,int(60.0+8.0*sin(x*0.03)+4.0*sin(x*0.09)),4,50,"6b4a7a")
		# Tiny Taipei 101 on the far ridge, a few valley lights.
		_r(285,50,2,3,"4a3560")
		_r(284,53,4,12,"4a3560")
		_r(283,58,6,2,"4a3560")
		for x in range(0,320,4):
			var top:=int(76.0+6.0*sin(x*0.045+1.3))
			_r(x,top,4,40,"3f3a5e")
			if x%12==0:_r(x,top+6,6,2,"4c7a4a")
		for x in [150,196,214,236]:_r(x,92,1,1,"ffd98a")

	func _pavilion()->void:
		_r(0,0,320,12,"3a2418")
		_r(0,12,320,3,"5a3a22")
		for x in range(0,320,8):_r(x,4,4,1,"4d3020")
		_r(8,15,8,110,"6b4426")
		_r(8,15,2,110,"835534")
		_r(304,15,8,110,"6b4426")
		_r(304,15,2,110,"835534")
		var glow:="ffd98a" if not _animating or int(_t*6.0)%2==0 else "ffb85a"
		_r(262,15,1,8,"2a1a10")
		_r(257,22,11,2,"2a1a10")
		_r(257,24,11,12,"c8452f")
		_r(259,26,7,8,glow)
		_r(257,36,11,2,"2a1a10")
		_r(255,38,1,1,"c8452f")

	func _chacha()->void:
		var nod:=1 if _animating and int(_t*6.0)%2==1 else 0
		_r(31,25,70,70,"3a2418")
		_r(32,26,68,68,"e9d3a0")
		var portrait:=TeaResidentArt.portrait("host")
		if portrait:draw_texture_rect(portrait,Rect2(34,28+nod,64,64),false)
		if topic==2 and _animating:
			var pop:=int(_t*8.0)%2
			_r(96,22-pop,1,5,"fff0a0")
			_r(94,24-pop,5,1,"fff0a0")

	func _guest()->void:
		var lean:=-1 if _animating and int(_t*6.0)%2==1 else 0
		_r(250,78,24,18,"4d6a7a")
		_r(252,76,20,3,"5d7d8e")
		_r(257+lean,62,10,12,"2b2230")
		_r(252+lean,59,20,3,"d9b45f")
		_r(256+lean,54,12,5,"e8c874")
		_r(256+lean,58,12,1,"9a7a3a")

	func _rail()->void:
		for y in [94,106]:
			_r(16,y,288,3,"7a9a3c")
			_r(16,y,288,1,"b7d46a")
		_r(16,118,288,4,"5f7f2e")
		for x in range(18,304,20):
			_r(x,94,4,26,"7a9a3c")
			_r(x,94,1,26,"a8c85a")
			_r(x-1,101,6,2,"4f6b28")
			_r(x-1,113,6,2,"4f6b28")

	func _floor_and_table()->void:
		_r(0,136,320,24,"5c3b22")
		_r(0,148,320,1,"472c18")
		for x in range(10,320,34):_r(x,136,1,12,"472c18")
		for x in range(27,320,34):_r(x,149,1,11,"472c18")
		_r(100,128,5,16,"6b4426")
		_r(229,128,5,16,"6b4426")
		_r(92,118,150,6,"9c6a3c")
		_r(92,118,150,1,"c28f56")
		_r(96,124,142,4,"6b4426")
		var size:=TEA_SET.get_size()
		var at:=Vector2(167.0-size.x*0.5,121.0-size.y).round()
		draw_texture_rect(TEA_SET,Rect2(at,size),false)
		# Resting bamboo leaves on the table.
		_r(104,116,3,1,"6f9a3a")
		_r(105,117,2,1,"9fc25a")
		_r(214,115,3,1,"9fc25a")
		_r(215,116,3,1,"6f9a3a")

	func _steam()->void:
		var size:=TEA_SET.get_size()
		var base_y:=121.0-size.y+size.y*0.3
		var tea:=topic==0 and _animating
		var phase:=_t*(2.0 if tea else 1.0) if _animating else 0.0
		var rise:=26.0 if tea else 16.0
		var puffs:=4 if tea else 3
		for col:int in [-4,4]:
			for i in puffs:
				var ph:=fposmod(phase+float(i)/puffs+col*0.02,1.0)
				var x:=167.0+col+roundf(sin(ph*TAU+col)*2.0)
				_r(x,base_y-ph*rise,2,2,Color(1,0.96,0.9,0.8*(1.0-ph)))

	func _bubble()->void:
		var accent:String=TOPIC_COLORS[topic]
		_r(112,28,98,44,accent)
		_r(114,30,94,40,"fff4dc")
		for i in 4:_r(104+i*2,48-i,8-i*2,3+i*2,accent if i==0 else "fff4dc")
		_r(106,50,6,1,"fff4dc")
		_r(106,49,2,3,accent)
		_r(110,49,3,3,"fff4dc")
		match topic:
			0:_icon_tea()
			1:_icon_weather()
			_:_icon_learning()
		for i in 3:_r(151+i*8,76,4,4,TOPIC_COLORS[i] if i==topic else "5a4a6a")

	func _icon_tea()->void:
		var shift:=int(_t*8.0)%2 if _animating else 0
		for i in 3:
			var x:=154+i*6+(shift if i%2==0 else 1-shift)
			_r(x,40,1,3,"b9a98a")
			_r(x+1,43,1,3,"b9a98a")
		_r(150,49,20,12,"c98a5a")
		_r(150,49,20,2,"e0b080")
		_r(152,51,16,2,"5a3a22")
		_r(170,51,5,2,"c98a5a")
		_r(174,51,2,6,"c98a5a")
		_r(170,56,5,2,"c98a5a")
		_r(146,61,28,2,"8a5a38")

	func _icon_weather()->void:
		var drift:=int(roundf(sin(_t*PI)*4.0)) if _animating else 0
		var ray:=_animating and int(_t*6.0)%2==1
		_r(145,45,10,10,"ffd25a")
		_r(147,43,6,14,"ffd25a")
		_r(143,47,14,6,"ffd25a")
		if ray:
			_r(149,39,2,3,"ffd25a")
			_r(149,58,2,3,"ffd25a")
		_r(160+drift,52,24,9,"cfe0ee")
		_r(165+drift,47,11,6,"cfe0ee")
		_r(174+drift,49,7,4,"cfe0ee")
		_r(160+drift,60,24,1,"9fb8cf")
		if _animating:
			for i in 3:_r(164+i*7+drift,62+(int(_t*10.0)+i)%3*2,1,3,"6a8fb5")

	func _icon_learning()->void:
		_r(145,64,32,2,"8a4f3a")
		_r(146,48,14,16,"f7f0d8")
		_r(162,48,14,16,"f7f0d8")
		_r(160,47,2,18,"8a4f3a")
		for i in 3:
			_r(148,51+i*4,10,1,"9a8a6a")
			_r(164,51+i*4,10,1,"9a8a6a")
		var grow:=int(6.0*minf(1.0,_t*1.5)) if _animating else 6
		_r(190,58-grow,2,grow+4,"4c9a4a")
		if grow>=3:_r(186,56-grow,4,3,"6fb85a")
		if grow>=5:_r(192,54-grow,4,3,"6fb85a")

	func _leaves()->void:
		if not _animating:return
		var wind:=120.0 if topic==1 else 40.0
		for i in 4:
			var lt:=clampf(_t*1.3-i*0.12,0.0,1.0)
			if lt<=0.0 or lt>=1.0:continue
			var alpha:=1.0-smoothstep(0.7,1.0,lt)
			var x:=floorf(300.0-lt*wind-i*18.0)
			var y:=floorf(20.0+i*14.0+lt*30.0+sin(lt*9.0+i)*4.0)
			var dark:=Color("6f9a3a",alpha)
			var light:=Color("9fc25a",alpha)
			_r(x,y,3,1,dark)
			_r(x+1,y+1,2,1,light)
			_r(x+3,y,1,1,light)
