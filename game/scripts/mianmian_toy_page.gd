extends RefCounted
## T066 N06-3 reward page: the toy sewn with Mianmian and how it is used with companions.
## Read-only; gated on the viewer's own mianmian stage 3 being done. No new state.

const Pixel=preload("res://scripts/inventory_pixel_theme.gd")
const Art=preload("res://scripts/mianmian_toy_art.gd")
const Notes=preload("res://scripts/mianmian_animal_notes.gd")
const SCALE:=6

static func available(snapshot:Dictionary) -> bool:
	return not Art.choice(snapshot).is_empty()

class ToyFrame extends Control:
	var kind:=""
	func _init(toy:String) -> void:
		kind=toy
		name="MianmianToyArt"
		mouse_filter=Control.MOUSE_FILTER_IGNORE
		texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
		custom_minimum_size=Vector2(Art.SIZE*SCALE+16,Art.SIZE*SCALE+16)
		size_flags_vertical=Control.SIZE_SHRINK_CENTER
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO,size),Color("f3e6c4"))
		draw_rect(Rect2(Vector2.ZERO,size),Color("5b4630"),false,2.0)
		draw_texture_rect(Art.texture(kind),Rect2(Vector2(8,8),Vector2(Art.SIZE*SCALE,Art.SIZE*SCALE)),false)

static func open(app,back:Callable,back_label:String="返回") -> void:
	var snapshot:Dictionary=app.session.snapshot
	var kind:=Art.choice(snapshot)
	if kind.is_empty():return
	var body:VBoxContainer=app._open_modal("棉棉縫的%s"%Art.label(kind))
	app.modal.name="MianmianToy"
	app.modal.theme=Pixel.make(app.hud.theme)
	app.modal.add_theme_stylebox_override("panel",Pixel.frame_style())
	app.modal.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	app.modal.set_meta("life_modal_layout","mianmian_notes")
	body.add_theme_constant_override("separation",8)
	var pad:=MarginContainer.new()
	pad.name="MianmianToyTips"
	pad.add_theme_constant_override("margin_left",18)
	pad.add_theme_constant_override("margin_right",18)
	body.add_child(pad)
	var column:=VBoxContainer.new()
	column.add_theme_constant_override("separation",10)
	pad.add_child(column)
	var header:=HBoxContainer.new()
	header.add_theme_constant_override("separation",14)
	column.add_child(header)
	header.add_child(ToyFrame.new(kind))
	var speech:=VBoxContainer.new()
	speech.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	speech.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	speech.add_theme_constant_override("separation",2)
	header.add_child(speech)
	Notes.tone(Notes.line(app,speech,"「縫線有一點歪，可是牠抱得很緊。」",16),Notes.QUOTE_INK)
	var who:=Notes.line(app,speech,"—— 棉棉",14)
	Notes.tone(who,Notes.TITLE_INK)
	who.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	var copy:=[["找個夥伴","叫小柴犬或圍巾貓同行，到小窩選「%s」陪牠玩。"%Art.label(kind)],["玩一次就好","每次親密度加一，之後要歇 30 秒再玩。"],["只在你的畫面","別人看不到牠抱著你縫的玩具。"]]
	for index in copy.size():
		var tip:=VBoxContainer.new()
		tip.name="MianmianToyTip_%d"%index
		tip.add_theme_constant_override("separation",1)
		column.add_child(tip)
		Notes.tone(Notes.line(app,tip,"%d　%s"%[index+1,copy[index][0]],17),Notes.TITLE_INK)
		var text:=Notes.line(app,tip,str(copy[index][1]),15)
		Notes.tone(text,Notes.BODY_INK)
		text.add_theme_constant_override("line_spacing",4)
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
	close.name="MianmianToyBack"
	actions.add_child(close)
	close.grab_focus.call_deferred()
	app._layout_preview.call_deferred()
