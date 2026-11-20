extends Control

const HARBOR=preload("res://assets/ui-life/wangan-arrival-harbor.png")
const BOAT=preload("res://assets/transit/achao-voyage.png")
const PEOPLE=preload("res://assets/life-art/characters.png")
const ART_SIZE:=Vector2(236,42)
const ARRIVAL_SECONDS:=2.4
var motion:=true
var elapsed:=0.0

func _ready()->void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	custom_minimum_size.y=ART_SIZE.y
	elapsed=0.0 if motion else ARRIVAL_SECONDS
	set_process(motion)

func _process(delta:float)->void:
	elapsed=minf(elapsed+delta,ARRIVAL_SECONDS)
	queue_redraw()
	if elapsed>=ARRIVAL_SECONDS:set_process(false)

func _draw()->void:
	if size.y<=0:return
	var scale_factor:=maxf(1.0,floorf(minf(size.x/ART_SIZE.x,size.y/ART_SIZE.y)))
	var art_offset:=((size-ART_SIZE*scale_factor)*0.5).round()
	draw_set_transform(art_offset,0,Vector2.ONE*scale_factor)
	draw_texture(HARBOR,Vector2.ZERO)
	var transit:=smoothstep(0.0,1.55,elapsed)
	var stepping:=smoothstep(1.55,ARRIVAL_SECONDS,elapsed)
	var bob:=sin(elapsed*7.0)*(1.0-transit) if motion else 0.0
	var vessel:=Vector2(lerpf(37.0,129.0,transit),26.0+bob).round()
	if transit<0.99:
		for wake in range(3):
			var at:=vessel+Vector2(-16.0-5.0*wake,5.0+2.0*wake)
			draw_line(at,at+Vector2(10.0,0.0),Color(0.82,0.93,0.85,0.52*(1.0-transit)),1.0)
	draw_texture_rect_region(BOAT,Rect2(vessel+Vector2(-19,-14),Vector2(38,36)),Rect2(0,0,48,48))
	if transit>=0.99:
		draw_rect(Rect2(Vector2(131,28),Vector2(18,5)),Color("654a34"))
		draw_line(Vector2(132,29),Vector2(148,29),Color("d7af78"))
		draw_line(Vector2(134,31),Vector2(148,31),Color("a57749"))
	var foot:=vessel+Vector2(1,4)
	if stepping>0.0:foot=Vector2(lerpf(130.0,190.0,stepping),lerpf(30.0,28.0,stepping))
	var walking:=stepping>0.0 and stepping<1.0
	var frame:=1+(floori(elapsed*15.0)%2) if walking else 0
	var direction:=2 if walking else 0
	draw_texture_rect_region(PEOPLE,Rect2(foot.round()-Vector2(11,20),Vector2(22,22)),Rect2(frame*48,direction*48,48,48))
