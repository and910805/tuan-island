extends RefCounted
## T066 N06-1: 糯米雞的偏好筆記, an illustrated journal page unlocked by Mianmian's first event.
##
## Read-only and personal: gated on the viewer's own resident_goals.mianmian stage 1 being done.
## The chicken is the real pixel art from res://assets/life-art/animals.png. The little scene
## plays one short walk (three steps toward a shoe) and then rests; reduced motion shows the
## finished pose straight away. No world logic, no new state.

const Pixel=preload("res://scripts/inventory_pixel_theme.gd")
const ANIMALS:=preload("res://assets/life-art/animals.png")
const PAPER:=Color("f3e6c4")
const INK:=Color("5b4630")
const WALK_SECONDS:=3.0
const LOGICAL:=Vector2i(100,44)
const TITLE_INK:=Color("7a4a22")
const BODY_INK:=Color("2f2418")
const QUOTE_INK:=Color("4a3524")

static func available(snapshot:Dictionary) -> bool:
	var goals:Variant=snapshot.get("resident_goals")
	if not goals is Dictionary:return false
	var mianmian:Variant=goals.get("mianmian")
	if not mianmian is Dictionary:return false
	var event:Variant=mianmian.get("1",mianmian.get(1))
	return event is Dictionary and event.get("state")=="done"

class NotesArt extends Control:
	var reduced:=false
	var age:=0.0
	var _scale:=1

	func _init() -> void:
		name="MianmianNotesArt"
		mouse_filter=Control.MOUSE_FILTER_IGNORE
		clip_contents=true
		texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
		custom_minimum_size=Vector2(LOGICAL*2)
		size_flags_horizontal=Control.SIZE_SHRINK_BEGIN

	func _ready() -> void:
		set_process(not reduced)

	func _process(delta:float) -> void:
		if age>=WALK_SECONDS+0.5:
			set_process(false)
			return
		age+=delta
		queue_redraw()

	func _notification(what:int) -> void:
		if what==NOTIFICATION_RESIZED:
			_scale=maxi(1,int(floor(size.x/LOGICAL.x)))
			var want:=float(LOGICAL.y*_scale)
			if not is_equal_approx(custom_minimum_size.y,want):custom_minimum_size.y=want
			queue_redraw()

	func _draw() -> void:
		var s:=_scale
		var origin:=Vector2(maxi(0,(int(size.x)-LOGICAL.x*s)/2),maxi(0,(int(size.y)-LOGICAL.y*s)/2))
		draw_rect(Rect2(origin,Vector2(LOGICAL*s)),PAPER)
		draw_rect(Rect2(origin,Vector2(LOGICAL*s)),INK,false,2.0)
		# Ground line, a feed bowl, and the shoe the chicken is getting to know.
		var floor_y:=origin.y+38.0*s
		draw_rect(Rect2(origin+Vector2(4,38)*s,Vector2(92,2)*s),Color("b8a47a"))
		var bowl:=origin+Vector2(6,30)*s
		draw_rect(Rect2(bowl,Vector2(14,8)*s),Color("9a6b3f"))
		draw_rect(Rect2(bowl+Vector2(2,-2)*s,Vector2(10,3)*s),Color("e2c066"))
		var shoe:=origin+Vector2(76,30)*s
		draw_rect(Rect2(shoe,Vector2(20,8)*s),Color("6b4f3a"))
		draw_rect(Rect2(shoe+Vector2(2,-6)*s,Vector2(10,7)*s),Color("6b4f3a"))
		draw_rect(Rect2(shoe,Vector2(20,2)*s),Color("3c2d22"))
		# Three small steps from the bowl toward the shoe, then it stays put.
		var progress:=1.0 if reduced else clampf(age/WALK_SECONDS,0.0,1.0)
		var steps:=3
		var stepped:=floorf(progress*steps)/float(steps) if progress<1.0 else 1.0
		var x:=28.0+stepped*30.0
		var hop:=0.0
		if not reduced and progress<1.0:hop=absf(sin(progress*steps*PI))*3.0
		var frame:=1 if (not reduced and progress<1.0 and int(progress*steps*2.0)%2==1) else 0
		var foot:=Vector2(origin.x+x*s,floor_y-hop*s)
		draw_texture_rect_region(ANIMALS,Rect2(foot-Vector2(16,28)*s,Vector2(32,32)*s),Rect2(frame*32,0,32,32))

static func open(app,back:Callable,back_label:String="返回") -> void:
	var snapshot:Dictionary=app.session.snapshot
	if not available(snapshot):return
	var body:VBoxContainer=app._open_modal("糯米雞的偏好筆記")
	app.modal.name="MianmianNotes"
	app.modal.theme=Pixel.make(app.hud.theme)
	app.modal.add_theme_stylebox_override("panel",Pixel.frame_style())
	app.modal.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	app.modal.set_meta("life_modal_layout","mianmian_notes")
	body.add_theme_constant_override("separation",8)

	var tips:=MarginContainer.new()
	tips.name="MianmianNotesTips"
	tips.add_theme_constant_override("margin_left",18)
	tips.add_theme_constant_override("margin_right",18)
	body.add_child(tips)
	var column:=VBoxContainer.new()
	column.add_theme_constant_override("separation",10)
	tips.add_child(column)
	# One compact header: the little scene beside 棉棉's attributed quote.
	var header:=HBoxContainer.new()
	header.add_theme_constant_override("separation",14)
	column.add_child(header)
	var art:=NotesArt.new()
	art.reduced=bool(app.sound.reduced_motion)
	art.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	header.add_child(art)
	var speech:=VBoxContainer.new()
	speech.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	speech.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	speech.add_theme_constant_override("separation",2)
	header.add_child(speech)
	tone(line(app,speech,"「牠不是不喜歡你，只是還在認識你的鞋子。」",16),QUOTE_INK)
	var who:=line(app,speech,"—— 棉棉",14)
	who.name="MianmianNotesQuoteBy"
	tone(who,TITLE_INK)
	who.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT

	var copy:=[["一份飼料就夠","小石灶用小麥和纖維做飼料，餵一份就好。約一分鐘後下蛋。"],["退後等一下","餵完不必連續餵或摸，站著等幾秒，牠會自己走近。"],["想親近再摸摸","摸一下牠會開心，之後要休息 30 秒。"]]
	for index in copy.size():
		var tip:=VBoxContainer.new()
		tip.name="MianmianNotesTip_%d"%index
		tip.add_theme_constant_override("separation",1)
		column.add_child(tip)
		tone(line(app,tip,"%d　%s"%[index+1,copy[index][0]],17),TITLE_INK)
		tone(line(app,tip,str(copy[index][1]),15),BODY_INK)
		(tip.get_child(1) as Label).add_theme_constant_override("line_spacing",4)

	var actions:=HBoxContainer.new()
	actions.alignment=BoxContainer.ALIGNMENT_END
	if is_instance_valid(app.modal_feedback) and app.modal.is_ancestor_of(app.modal_feedback):
		var footer:Label=app.modal_feedback
		footer.get_parent().add_child(actions)
		footer.reparent(actions,false)
		footer.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		footer.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	else:
		body.add_child(actions)
	var close:Button=app.button(back_label,back)
	close.name="MianmianNotesBack"
	actions.add_child(close)
	close.grab_focus.call_deferred()
	app._layout_preview.call_deferred()

static func line(app,parent:Container,copy:String,extent:int) -> Label:
	var label:Label=app.label(copy,extent)
	if parent is VBoxContainer:label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	parent.add_child(label)
	return label

static func tone(label:Label,color:Color) -> void:
	label.add_theme_color_override("font_color",color)
