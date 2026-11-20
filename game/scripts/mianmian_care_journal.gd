extends RefCounted
## T066 N06-4 reward: 棉棉的照料手札 and the 羊毛帽. Read-only apart from the hat toggle
## (an existing-style personal flag). Gated on the viewer's own mianmian stage 4 being done.
## The page also gathers the earlier pages (聞聞筆記, 布玩具) so the four events read as one.

const World=preload("res://scripts/world.gd")
const Pixel=preload("res://scripts/inventory_pixel_theme.gd")
const Hat=preload("res://scripts/mianmian_wool_hat_art.gd")
const Toy=preload("res://scripts/mianmian_toy_art.gd")
const Notes=preload("res://scripts/mianmian_animal_notes.gd")
const ToyPage=preload("res://scripts/mianmian_toy_page.gd")
const SCALE:=4

static func available(snapshot:Dictionary) -> bool:
	var goals:Variant=snapshot.get("resident_goals")
	if not goals is Dictionary:return false
	var mianmian:Variant=goals.get("mianmian")
	if not mianmian is Dictionary:return false
	var event:Variant=mianmian.get("4",mianmian.get(4))
	return event is Dictionary and event.get("state")=="done"

static func wearing(snapshot:Dictionary,own_id:String) -> bool:
	var players:Variant=snapshot.get("players")
	var person:Variant=players.get(own_id) if players is Dictionary else null
	return person is Dictionary and person.get(World.RESIDENT_GOALS.WOOL_HAT_KEY,false)==true

class HatFrame extends Control:
	func _init() -> void:
		name="MianmianHatArt"
		mouse_filter=Control.MOUSE_FILTER_IGNORE
		texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
		custom_minimum_size=Vector2(Hat.WIDTH*SCALE+20,Hat.HEIGHT*SCALE+20)
		size_flags_vertical=Control.SIZE_SHRINK_CENTER
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO,size),Color("f3e6c4"))
		draw_rect(Rect2(Vector2.ZERO,size),Color("5b4630"),false,2.0)
		draw_texture_rect(Hat.texture(),Rect2(Vector2(10,10),Vector2(Hat.WIDTH*SCALE,Hat.HEIGHT*SCALE)),false)

static func open(app,back:Callable,back_label:String="返回") -> void:
	var snapshot:Dictionary=app.session.snapshot
	if not available(snapshot):return
	var body:VBoxContainer=app._open_modal("棉棉的照料手札")
	app.modal.name="MianmianJournal"
	app.modal.theme=Pixel.make(app.hud.theme)
	app.modal.add_theme_stylebox_override("panel",Pixel.frame_style())
	app.modal.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	app.modal.set_meta("life_modal_layout","mianmian_journal")
	body.add_theme_constant_override("separation",8)
	var pad:=MarginContainer.new()
	pad.name="MianmianJournalTips"
	pad.add_theme_constant_override("margin_left",18)
	pad.add_theme_constant_override("margin_right",18)
	body.add_child(pad)
	var column:=VBoxContainer.new()
	column.add_theme_constant_override("separation",10)
	pad.add_child(column)
	var header:=HBoxContainer.new()
	header.add_theme_constant_override("separation",14)
	column.add_child(header)
	header.add_child(HatFrame.new())
	var speech:=VBoxContainer.new()
	speech.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	speech.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	speech.add_theme_constant_override("separation",2)
	header.add_child(speech)
	Notes.tone(Notes.line(app,speech,"「我們沒有把牠拉出來。所以這一步，完完整整是牠自己的。」",16),Notes.QUOTE_INK)
	var who:=Notes.line(app,speech,"—— 棉棉",14)
	Notes.tone(who,Notes.TITLE_INK)
	who.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	var worn:=wearing(snapshot,app.session.own_id)
	var hat:Button=app.button("脫下羊毛帽" if worn else "戴上羊毛帽",func():
		var me:Dictionary=app.session.snapshot.get("players",{}).get(app.session.own_id,{})
		# The server wants the request anchored at the player's own cell.
		app.session.perform(World.RESIDENT_GOALS.WOOL_HAT_ACTION,Vector2i(floori(float(me.get("x",0.0))),floori(float(me.get("y",0.0)))))
		app._close_modal())
	hat.name="MianmianHatToggle"
	var toy_kind:=Toy.choice(snapshot)
	var copy:=[
		["先讓牠聞聞","餵一份飼料，退後等牠走近。"],
		["遮雨角落","棚和纖維墊讓小羊躲雨。"],
		["不完美的玩具","你縫的%s，夥伴抱得很緊。"%(Toy.label(toy_kind) if not toy_kind.is_empty() else "玩具")],
		["自己走出屋簷","晴天安靜等，小羊自己跨出一步。"]]
	for index in copy.size():
		var line:=VBoxContainer.new()
		line.name="MianmianJournalLine_%d"%index
		line.add_theme_constant_override("separation",1)
		column.add_child(line)
		Notes.tone(Notes.line(app,line,"%d　%s"%[index+1,copy[index][0]],17),Notes.TITLE_INK)
		var text:=Notes.line(app,line,str(copy[index][1]),15)
		Notes.tone(text,Notes.BODY_INK)
		text.add_theme_constant_override("line_spacing",3)
	var footer_actions:=HBoxContainer.new()
	footer_actions.alignment=BoxContainer.ALIGNMENT_END
	if is_instance_valid(app.modal_feedback) and app.modal.is_ancestor_of(app.modal_feedback):
		var footer:Label=app.modal_feedback
		footer.get_parent().add_child(footer_actions)
		footer.reparent(footer_actions,false)
		footer.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		footer.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	else:
		body.add_child(footer_actions)
	footer_actions.add_child(hat)
	var close:Button=app.button(back_label,back)
	close.name="MianmianJournalBack"
	footer_actions.add_child(close)
	close.grab_focus.call_deferred()
	app._layout_preview.call_deferred()
