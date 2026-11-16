extends RefCounted

const INK:=Color("514c42")
const SKIN:=Color("f4caa0")
const SHADE:=Color("cf956f")
const CREAM:=Color("fff0cc")

static func pixel(canvas:CanvasItem,at:Vector2,x:int,y:int,w:int,h:int,color:Color) -> void:
	canvas.draw_rect(Rect2(at+Vector2(x,y),Vector2(w,h)),color)

static func person(canvas:CanvasItem,at:Vector2,shirt:Color,style:String,facing:Vector2i,phase:float,walking:bool,reduced_motion:bool) -> void:
	var foot:=at.round()
	var side:=facing.x
	var back:=facing==Vector2i.UP
	var stride:=roundi(sin(phase)*(1.0 if reduced_motion else 2.0)) if walking else 0
	var lift:=1 if walking and not reduced_motion and absi(stride)>0 else 0
	var body:=foot-Vector2(0,lift)
	var hair:=Color("57493e")
	if style=="aru":hair=Color("76513d")
	if style=="milu":hair=Color("7c5145")
	var hat:=Color("e2b36e") if style=="farmer" else shirt
	pixel(canvas,foot,-10,1,20,4,Color(0.20,0.27,0.20,0.22))
	pixel(canvas,foot,-7+side*stride,-4+stride,6,6,INK)
	pixel(canvas,foot,1-side*stride,-4-stride,6,6,INK)
	pixel(canvas,foot,-7+side*stride,-4+stride,5,3,Color("8b674e"))
	pixel(canvas,foot,1-side*stride,-4-stride,5,3,Color("8b674e"))
	pixel(canvas,body,-8,-16,16,13,INK)
	pixel(canvas,body,-7,-15,14,11,shirt)
	pixel(canvas,body,-10,-13-stride,4,6,shirt.darkened(0.18))
	pixel(canvas,body,6,-13+stride,4,6,shirt.darkened(0.18))
	pixel(canvas,body,-10,-8-stride,3,3,SKIN)
	pixel(canvas,body,7,-8+stride,3,3,SKIN)
	if back:
		pixel(canvas,body,-5,-15,10,10,INK)
		pixel(canvas,body,-4,-14,8,8,Color("ac7854"))
		pixel(canvas,body,-3,-13,6,2,Color("dab080"))
		pixel(canvas,body,-1,-11,2,3,CREAM)
	elif style=="milu" or style=="aru":
		pixel(canvas,body,-4+side*2,-14,8,9,CREAM)
		pixel(canvas,body,-2+side*2,-9,4,2,shirt)
	else:
		pixel(canvas,body,-6,-9,12,5,Color("5f7481"))
		pixel(canvas,body,-5,-13,2,5,Color("5f7481"))
		pixel(canvas,body,3,-13,2,5,Color("5f7481"))
		pixel(canvas,body,-2,-8,4,2,CREAM)
	var head:=body+Vector2(side*2,0)
	pixel(canvas,head,-8,-33,16,22,INK)
	pixel(canvas,head,-11,-29,22,14,INK)
	pixel(canvas,head,-9,-30,18,17,hair)
	pixel(canvas,head,-7,-32,14,5,hair.lightened(0.16))
	if back:
		pixel(canvas,head,-8,-29,16,13,hair)
		pixel(canvas,head,-5,-18,10,4,hair.lightened(0.12))
	else:
		var face_half_width:=8-absi(side)
		var face_left:=side*3-face_half_width
		pixel(canvas,head,face_left,-24,face_half_width*2,10,SHADE)
		pixel(canvas,head,face_left+1,-25,face_half_width*2-2,10,SKIN)
		if side==0:
			pixel(canvas,head,-5,-23,2,4,INK)
			pixel(canvas,head,3,-23,2,4,INK)
			pixel(canvas,head,-7,-19,3,2,Color("e89987"))
			pixel(canvas,head,4,-19,3,2,Color("e89987"))
			pixel(canvas,head,-1,-18,2,1,SHADE)
		else:
			pixel(canvas,head,side*4-1,-23,2,4,INK)
			pixel(canvas,head,side*6-1,-19,3,2,Color("e89987"))
			pixel(canvas,head,side*8-1,-21,3,3,SKIN)
	match style:
		"farmer":
			pixel(canvas,head,-8,-37,16,8,INK)
			pixel(canvas,head,-7,-36,14,6,hat)
			pixel(canvas,head,-5,-36,10,2,hat.lightened(0.27))
			pixel(canvas,head,-7,-32,14,2,Color("a76d4c"))
			pixel(canvas,head,-12,-30,24,3,INK)
			pixel(canvas,head,-11,-30,22,2,hat.lightened(0.20))
		"aru":
			pixel(canvas,head,-10,-32,20,6,hair)
			pixel(canvas,head,-7,-35,13,4,hair.lightened(0.22))
			pixel(canvas,head,-9,-30,6,6,hair)
			pixel(canvas,head,-10,-31,4,2,CREAM)
		"milu":
			pixel(canvas,head,-5,-38,10,6,INK)
			pixel(canvas,head,-4,-37,8,4,hair.lightened(0.22))
			pixel(canvas,head,-10,-33,20,5,CREAM)
			pixel(canvas,head,-8,-29,16,2,Color("b56e64"))
		_:
			pixel(canvas,head,-8,-35,16,7,INK)
			pixel(canvas,head,-7,-34,14,5,hat)
			pixel(canvas,head,-11+side*2,-30,21,3,hat.lightened(0.25))
