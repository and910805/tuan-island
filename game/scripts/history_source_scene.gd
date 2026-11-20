extends Control
## Canal illustration with a soft reveal and a small reflected highlight.
## Purely decorative: owns no gameplay state and draws only inside its own rect.

const ART_PATH:="res://assets/ui-life/lanyang-memory-canal.png"
const REVEAL_SECONDS:=1.1

var motion:=true
var elapsed:=0.0
var art:Texture2D

func _ready()->void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	clip_contents=true
	# Loaded at runtime so the scene still opens if the image is not imported yet.
	if ResourceLoader.exists(ART_PATH):art=load(ART_PATH) as Texture2D
	custom_minimum_size=Vector2(480,200)
	size_flags_horizontal=Control.SIZE_SHRINK_CENTER
	replay()

func replay()->void:
	elapsed=0.0 if motion else REVEAL_SECONDS
	set_process(motion)
	queue_redraw()

func _process(delta:float)->void:
	var frame:=floori(elapsed*15.0)
	elapsed+=delta
	if floori(elapsed*15.0)!=frame:queue_redraw()

func _image_rect()->Rect2:
	if art==null:return Rect2(Vector2.ZERO,size)
	var factor:=minf(size.x/art.get_width(),size.y/art.get_height())
	if factor>=1.0:factor=floorf(factor)
	var drawn:=Vector2(art.get_size())*factor
	return Rect2(((size-drawn)*0.5).round(),drawn)

func _draw()->void:
	var rect:=_image_rect()
	if art==null:
		draw_rect(rect,Color("b9d3c4"))
		draw_string(ThemeDB.fallback_font,rect.position+Vector2(12,28),"運河插圖載入中",HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color("315840"))
		return
	draw_texture_rect(art,rect,false)
	var reveal:=clampf(elapsed/REVEAL_SECONDS,0.0,1.0)
	if reveal<1.0:
		# Soft reveal: a paper-coloured veil fades out inside the image.
		draw_rect(rect,Color(0.95,0.91,0.8,0.85*(1.0-smoothstep(0.0,1.0,reveal))))
	elif motion:
		# Follow three channels of reflected light over the painted foreground stream.
		for index in range(3):
			var t:=fposmod((elapsed-REVEAL_SECONDS)*0.48+index*0.33,1.0)
			var water:=Vector2(0.51+index*0.072+t*0.055,0.72+index*0.030+t*0.12)
			var at:=(rect.position+rect.size*water).round()
			draw_rect(Rect2(at,Vector2(6+index*2,2)),Color(0.89,1.0,0.94,sin(t*PI)*0.67))
