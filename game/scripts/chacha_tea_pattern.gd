extends RefCounted
## A personal journal page unlocked when 茶茶's 〈杯子要排成一線〉 (stage 1) is reported.
## Gate: the own snapshot's resident_goals.chacha stage 1 state is "done" (string or int stage key).
## Illustration: the saved own table orientation (snapshot.own_chacha_tea_setup) through
## tea_arrangement_preview.gd; a legacy save without an orientation shows the plain furniture sprite.

const World=preload("res://scripts/world.gd")
const Pixel=preload("res://scripts/inventory_pixel_theme.gd")
const Shell=preload("res://scripts/life_ui_shell.gd")
const Items=preload("res://scripts/inventory_item_art.gd")
const Preview=preload("res://scripts/tea_arrangement_preview.gd")
const SET_SPRITE:=preload("res://assets/ui-inventory/basic-tea-set.png")
const RECIPE:="basic_tea_set"
const AXES:={"horizontal":"橫放","vertical":"直放"}
const QUOTE:="杯口朝外，客人就不會碰到壺嘴。"

static func available(snapshot:Dictionary) -> bool:
	var goals:Variant=snapshot.get("resident_goals")
	if not goals is Dictionary:return false
	var chacha:Variant=goals.get("chacha")
	if not chacha is Dictionary:return false
	var event:Variant=chacha.get("1",chacha.get(1))
	return event is Dictionary and event.get("state")=="done"

static func open(app,back:Callable) -> void:
	var snapshot:Dictionary=app.session.snapshot
	if not available(snapshot):return
	var body:VBoxContainer=app._open_modal("基本茶具圖樣")
	app.modal.name="ChachaTeaPattern"
	app.modal.theme=Pixel.make(app.hud.theme)
	app.modal.add_theme_stylebox_override("panel",Pixel.frame_style())
	app.modal.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	app.modal.set_meta("life_modal_layout","keepsake_paper")
	body.add_theme_constant_override("separation",8)

	var saved:String=str(snapshot.get("own_chacha_tea_setup",""))
	var known:=AXES.has(saved)

	var top:=HBoxContainer.new()
	top.add_theme_constant_override("separation",14)
	body.add_child(top)

	var art:=PanelContainer.new()
	art.name="ChachaTeaPatternArt"
	art.add_theme_stylebox_override("panel",Pixel.paper_style())
	art.size_flags_vertical=Control.SIZE_SHRINK_BEGIN
	top.add_child(art)
	if known:
		var preview:=Preview.new()
		preview.axis=saved
		preview.cups=2
		preview.custom_minimum_size=Vector2(168,170)
		art.add_child(preview)
	else:
		var sprite:=TextureRect.new()
		sprite.texture=SET_SPRITE
		sprite.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		sprite.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		sprite.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.custom_minimum_size=Vector2(168,170)
		art.add_child(sprite)

	var info:=VBoxContainer.new()
	info.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	info.custom_minimum_size.x=330
	info.add_theme_constant_override("separation",4)
	top.add_child(info)
	var design:=HBoxContainer.new()
	design.add_theme_constant_override("separation",8)
	info.add_child(design)
	design.add_child(Shell.picture(SET_SPRITE,32))
	line(app,design,"基本茶具 · 木托盤與兩只茶杯",17)
	var orientation:=line(app,info,("你在貓空把茶桌%s，擺上兩只杯子。"%AXES[saved]) if known else "茶具成品圖。",15)
	orientation.name="ChachaTeaPatternOrientation"
	orientation.add_theme_color_override("font_color",Color("5a6042"))

	line(app,info,"建造材料",17)
	var person:Dictionary=snapshot.get("players",{}).get(app.session.own_id,{})
	var inventory:Dictionary=person.get("inventory",{})
	var recipe:Dictionary=World.BUILD[RECIPE]
	for item:String in recipe:
		if item=="name":continue
		var row:=HBoxContainer.new()
		row.name="ChachaTeaPatternPart_"+item
		row.add_theme_constant_override("separation",8)
		info.add_child(row)
		row.add_child(Shell.picture(Items.icon(item),24))
		var need:=int(recipe[item])
		var held:=int(inventory.get(item,0))
		line(app,row,"%s ×%d"%[World.NAMES.get(item,item),need],16)
		var count:=line(app,row,"背包 %d"%held,14)
		count.add_theme_color_override("font_color",Color("37573e") if held>=need else Color("8a3d2e"))

	var story:=line(app,body,"「%s」——茶茶"%QUOTE,15)
	story.name="ChachaTeaPatternQuote"
	story.add_theme_color_override("font_color",Color("5a6042"))

	var actions:=HBoxContainer.new()
	actions.alignment=BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation",8)
	if is_instance_valid(app.modal_feedback) and app.modal.is_ancestor_of(app.modal_feedback):
		var footer:Label=app.modal_feedback
		footer.get_parent().add_child(actions)
		footer.reparent(actions,false)
		footer.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		footer.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	else:
		body.add_child(actions)
	var build:Button=app.button("在工坊預覽",func():app.life_panels.build_menu(app,RECIPE))
	build.name="ChachaTeaPatternBuild"
	actions.add_child(build)
	var close:Button=app.button("返回關係事件",back)
	close.name="ChachaTeaPatternBack"
	actions.add_child(close)
	close.grab_focus.call_deferred()
	app._layout_preview.call_deferred()

static func line(app,parent:Container,copy:String,extent:int) -> Label:
	var label:Label=app.label(copy,extent)
	if parent is VBoxContainer:label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	parent.add_child(label)
	return label
