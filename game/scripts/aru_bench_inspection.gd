extends Control

## N01-2〈長椅少了一隻腳〉：在師父長椅的鉛筆圖樣上直接點三處接點。
##
## 圖樣用既有的 aru-bench-pattern.png（整數倍放大、最近鄰）。三顆語意 Button 就是
## 既有的 BondGoalStep_0/1/2（0 左邊的椅腳、1 椅背的橫木、2 右邊的椅腳），疊在圖上的接點圈上；
## 它們放在名為 BondGoalSteps 的容器裡，所以 focus_goal / pick_goal_step 原本的找法照樣有效。
## 這裡只讀 picks，不存檔、不改任何遊戲狀態、不計時；三處順序不拘。
## 已檢查的接點會畫上勾；減少動態時直接顯示，否則只有一圈約 0.5 秒的小波紋，播完即停。

const TEXTURE:=preload("res://assets/ui-life/aru-bench-pattern.png")

const POINTS:=3
const SCALE:=2
const HOTSPOT:=Vector2(56,48) # 每個接點至少 44 px 的觸控範圍
const RIPPLE_TIME:=0.5

const NAMES:=["左邊的椅腳","椅背的橫木","右邊的椅腳"]
const CLUES:=["左腳的接點空了，只剩一截舊榫。","橫木還牢，只是兩端的孔磨大了。","右腳也鬆了，沒有硬木撐不住。"]
# 接點圈在原圖（224×70）上的位置比例：左腳、椅背橫木、右腳
const CENTERS:=[Vector2(0.12,0.67),Vector2(0.254,0.30),Vector2(0.40,0.67)]

const HINT:=Color("b5462f")
const DONE:=Color("3e664b")
const DONE_LIGHT:=Color("e9f2d8")
const FOCUS:=Color("e0a526")

var reduced:=true
var _seen:Array[int]=[]
var _ripple:=-1
var _t:=0.0
var _marks:Control
var _layer:Control
var _buttons:Array[Button]=[]

## pick 收到接點編號（0..2）。app 只用來建立既有樣式的 Button。
static func make(app,reduced_motion:bool,pick:Callable) -> Control:
	var art:=new()
	art.reduced=reduced_motion
	art.name="AruBenchInspection"
	var image:=Vector2(TEXTURE.get_size())*SCALE
	art.custom_minimum_size=image
	art.size=image
	art.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
	art.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	art.set_process(false)
	var picture:=TextureRect.new()
	picture.name="AruBenchSketchArt"
	picture.texture=TEXTURE
	picture.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode=TextureRect.STRETCH_SCALE
	picture.mouse_filter=Control.MOUSE_FILTER_IGNORE
	picture.size=image
	art.add_child(picture)
	var reference:Label=app.label("側面參考",14)
	reference.position=Vector2(image.x*0.60,5)
	reference.size=Vector2(image.x*0.36,20)
	reference.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	reference.mouse_filter=Control.MOUSE_FILTER_IGNORE
	reference.add_theme_color_override("font_color",Color("755839"))
	art.add_child(reference)
	art._marks=Control.new()
	art._marks.name="AruBenchMarks"
	art._marks.mouse_filter=Control.MOUSE_FILTER_IGNORE
	art._marks.size=image
	art._marks.draw.connect(art._draw_marks)
	art.add_child(art._marks)
	art._layer=Control.new()
	art._layer.name="BondGoalSteps"
	art._layer.mouse_filter=Control.MOUSE_FILTER_PASS
	art._layer.size=image
	art.add_child(art._layer)
	for index in range(POINTS):
		var b:Button=app.button("",func():pick.call(index))
		b.name="BondGoalStep_%d"%index
		b.text=NAMES[index]
		b.clip_text=true
		b.flat=true
		b.focus_mode=Control.FOCUS_ALL
		b.custom_minimum_size=HOTSPOT
		b.size=HOTSPOT
		b.position=(art.center(index)-HOTSPOT*0.5).round()
		b.tooltip_text="檢查%s"%NAMES[index]
		if "accessibility_name" in b:b.set("accessibility_name","檢查%s"%NAMES[index])
		art._style(b)
		art._layer.add_child(b)
		art._buttons.append(b)
	return art

func center(index:int) -> Vector2:
	var image:=Vector2(TEXTURE.get_size())*SCALE
	return Vector2(image.x*CENTERS[index].x,image.y*CENTERS[index].y).round()

func _style(b:Button) -> void:
	var empty:=StyleBoxEmpty.new()
	var hover:=StyleBoxFlat.new()
	hover.bg_color=Color(1.0,0.95,0.7,0.28)
	hover.set_border_width_all(0)
	hover.anti_aliasing=false
	var focus:=StyleBoxFlat.new()
	focus.bg_color=Color(1.0,0.95,0.7,0.18)
	focus.border_color=FOCUS
	focus.set_border_width_all(3)
	focus.anti_aliasing=false
	b.add_theme_stylebox_override("normal",empty)
	b.add_theme_stylebox_override("disabled",empty)
	b.add_theme_stylebox_override("hover",hover)
	b.add_theme_stylebox_override("pressed",hover)
	b.add_theme_stylebox_override("hover_pressed",hover)
	b.add_theme_stylebox_override("focus",focus)
	for state in ["font_color","font_hover_color","font_pressed_color","font_hover_pressed_color","font_focus_color","font_disabled_color"]:
		b.add_theme_color_override(state,Color.TRANSPARENT)

## picks：已檢查的接點（任意順序）。同步按鈕狀態與圖上的勾；重來時整個清掉。
func sync(picks:Array) -> void:
	var now:Array[int]=[]
	for value in picks:
		var index:=int(value)
		if index>=0 and index<POINTS and not now.has(index):now.append(index)
	for index in _seen:
		if not now.has(index):
			_seen.clear()
			_ripple=-1
			_t=0.0
			set_process(false)
			break
	var fresh:Array[int]=[]
	for index in now:
		if not _seen.has(index):fresh.append(index)
	for index in fresh:_seen.append(index)
	if fresh.size()==1 and not reduced:
		_ripple=fresh[0]
		_t=0.0
		set_process(true)
	for index in range(_buttons.size()):
		var order:=now.find(index)
		var seen:=order>=0
		_buttons[index].text=("%d. "%(order+1) if seen else "")+NAMES[index]
		_buttons[index].disabled=seen
		_buttons[index].tooltip_text=("已檢查：%s"%NAMES[index]) if seen else "檢查%s"%NAMES[index]
		if "accessibility_name" in _buttons[index]:
			_buttons[index].set("accessibility_name",("已檢查，%s"%NAMES[index]) if seen else "檢查%s"%NAMES[index])
	_marks.queue_redraw()

func inspected_count() -> int:
	return _seen.size()

func set_reduced_motion(value:bool) -> void:
	reduced=value
	if reduced:
		_ripple=-1
		_t=0.0
		set_process(false)
	_marks.queue_redraw()

func is_animating() -> bool:
	return _ripple>=0

# 供自動化逐步推進；_process 走同一條路。
func advance(seconds:float) -> void:
	if _ripple<0 or reduced:return
	_t+=maxf(0.0,seconds)
	if _t>=RIPPLE_TIME:
		_ripple=-1
		_t=0.0
		set_process(false)
	_marks.queue_redraw()

func _process(delta:float) -> void:
	advance(delta)

## 進度與短線索：已看過的接點各一行，順序依檢查先後。
static func progress_text(picks:Array) -> String:
	var rows:PackedStringArray=["已檢查 %d／%d 處（順序不拘）"%[mini(picks.size(),POINTS),POINTS] if not picks.is_empty() else "點正面圖上的三處標記，順序不拘。"]
	for value in picks:
		var index:=int(value)
		if index>=0 and index<POINTS:rows.append("✓ %s：%s"%[NAMES[index],CLUES[index]])
	return "\n".join(rows)

func _draw_marks() -> void:
	for index in range(POINTS):
		var c:=center(index)
		if _seen.has(index):
			var r:=11.0
			_marks.draw_circle(c,r+2.0,Color(1,1,1,0.9))
			_marks.draw_circle(c,r,DONE)
			_marks.draw_polyline(PackedVector2Array([c+Vector2(-5,0),c+Vector2(-1,4),c+Vector2(6,-5)]),DONE_LIGHT,3.0)
		else:
			_marks.draw_circle(c,12.0,Color("f4dbaf"))
			_marks.draw_arc(c,11.0,0.0,TAU,24,HINT,2.0)
			_marks.draw_circle(c,3.0,HINT)
	if _ripple>=0:
		var p:=clampf(_t/RIPPLE_TIME,0.0,1.0)
		_marks.draw_arc(center(_ripple),12.0+p*20.0,0.0,TAU,24,Color(DONE.r,DONE.g,DONE.b,(1.0-p)*0.8),3.0)
