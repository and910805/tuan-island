extends RefCounted
## A personal journal page unlocked when the B1 rest-station work is reported to Bobo.

const World=preload("res://scripts/world.gd")
const Pixel=preload("res://scripts/inventory_pixel_theme.gd")
const Shell=preload("res://scripts/life_ui_shell.gd")
const Items=preload("res://scripts/inventory_item_art.gd")
const Art=preload("res://scripts/bobo_rest_box_art.gd")
const RECIPE:="supply_box_kit"

static func available(snapshot:Dictionary) -> bool:
	var goals:Variant=snapshot.get("resident_goals")
	if not goals is Dictionary:return false
	var bobo:Variant=goals.get("bobo")
	if not bobo is Dictionary:return false
	var event:Variant=bobo.get("3",bobo.get(3))
	return event is Dictionary and event.get("state")=="done"

static func open(app,back:Callable) -> void:
	var snapshot:Dictionary=app.session.snapshot
	if not available(snapshot):return
	var body:VBoxContainer=app._open_modal("休息站便攜箱圖樣")
	app.modal.name="BoboRestPattern"
	app.modal.theme=Pixel.make(app.hud.theme)
	app.modal.add_theme_stylebox_override("panel",Pixel.frame_style())
	app.modal.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	app.modal.set_meta("life_modal_layout","bobo_rest_pattern")
	body.add_theme_constant_override("separation",9)

	var art:Control=Art.make()
	art.name="BoboRestPatternArt"
	art.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
	art.custom_minimum_size.x=500
	body.add_child(art)

	var details:=HBoxContainer.new()
	details.add_theme_constant_override("separation",20)
	body.add_child(details)
	var materials:=VBoxContainer.new()
	materials.custom_minimum_size.x=208
	materials.add_theme_constant_override("separation",4)
	details.add_child(materials)
	line(app,materials,"工作台配方",18)
	var person:Dictionary=snapshot.get("players",{}).get(app.session.own_id,{})
	var inventory:Dictionary=person.get("inventory",{})
	var ingredients:Dictionary=World.CRAFT[RECIPE].ingredients
	for item:String in ingredients:
		var row:=HBoxContainer.new()
		row.name="BoboRestPatternPart_"+item
		row.add_theme_constant_override("separation",8)
		materials.add_child(row)
		row.add_child(Shell.picture(Items.icon(item),24))
		var need:=int(ingredients[item])
		var held:=int(inventory.get(item,0))
		line(app,row,"%s ×%d"%[World.NAMES[item],need],16)
		var count:=line(app,row,"背包 %d"%held,14)
		count.add_theme_color_override("font_color",Color("37573e") if held>=need else Color("8a3d2e"))

	var guidance:=VBoxContainer.new()
	guidance.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	guidance.add_theme_constant_override("separation",4)
	details.add_child(guidance)
	line(app,guidance,"放置與收回",18)
	line(app,guidance,"在建造目錄的「生活」放置。箱子只供本人存取，清空後可拆回背包。",16)
	var note:=line(app,guidance,"波波以第一層休息站的箱子為原型。",14)
	note.add_theme_color_override("font_color",Color("5a6042"))

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
	var close:Button=app.button("返回關係事件",back)
	close.name="BoboRestPatternBack"
	actions.add_child(close)
	close.grab_focus.call_deferred()
	app._layout_preview.call_deferred()

static func line(app,parent:Container,copy:String,extent:int) -> Label:
	var label:Label=app.label(copy,extent)
	if parent is VBoxContainer:label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	parent.add_child(label)
	return label
