extends RefCounted

const World=preload("res://scripts/world.gd")
const Plate=preload("res://scripts/xinghe_growth_plate.gd")
const Pixel=preload("res://scripts/inventory_pixel_theme.gd")
const Items=preload("res://scripts/inventory_item_art.gd")
const INK:=Color("493626")
const GREEN:=Color("36543c")
const MUTED:=Color("735a40")

static func available(snapshot:Dictionary) -> bool:
	return int(snapshot.get("resident_bonds",{}).get("xinghe",{}).get("stage",0))>=1 or completed(snapshot)

static func completed(snapshot:Dictionary) -> bool:
	return snapshot.get("resident_goals",{}).get("xinghe",{}).get("1",{}).get("state")=="done"

static func open(app,back:Callable,back_label:String) -> void:
	var body:VBoxContainer=app._open_modal("星禾的作物觀察簿")
	app.modal.name="XingheGrowthNotebook"
	app.modal.set_meta("life_modal_layout","xinghe_growth_notebook")
	app.modal.theme=Pixel.make(app.hud.theme)
	app.modal.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	app.modal.add_theme_stylebox_override("panel",Pixel.frame_style())
	body.add_theme_constant_override("separation",10)
	var spread:=HBoxContainer.new()
	spread.add_theme_constant_override("separation",12)
	body.add_child(spread)
	var index:=panel(spread)
	index.custom_minimum_size.x=172
	var index_contents:=VBoxContainer.new()
	index_contents.add_theme_constant_override("separation",8)
	index.add_child(index_contents)
	label(app,index_contents,"作物索引",19,GREEN)
	var scroller:=ScrollContainer.new()
	scroller.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroller.size_flags_vertical=Control.SIZE_EXPAND_FILL
	scroller.custom_minimum_size.y=252
	index_contents.add_child(scroller)
	var buttons:=VBoxContainer.new()
	buttons.name="XingheGrowthIndex"
	buttons.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	buttons.add_theme_constant_override("separation",5)
	scroller.add_child(buttons)
	var sheet:=panel(spread)
	sheet.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var details:=VBoxContainer.new()
	details.name="XingheGrowthPage"
	details.add_theme_constant_override("separation",8)
	sheet.add_child(details)
	if back.is_valid():
		var button:Button=app.button(back_label,back)
		button.name="XingheGrowthBack"
		button.size_flags_horizontal=Control.SIZE_SHRINK_END
		if is_instance_valid(app.modal_feedback) and app.modal.is_ancestor_of(app.modal_feedback):
			var footer:=HBoxContainer.new()
			app.modal_feedback.get_parent().add_child(footer)
			app.modal_feedback.reparent(footer,false)
			app.modal_feedback.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			footer.add_child(button)
		else:body.add_child(button)
	sync(app)
	app._layout_preview.call_deferred()

static func sync(app) -> void:
	if not is_instance_valid(app.modal) or app.modal.name!="XingheGrowthNotebook":return
	var snapshot:Dictionary=app.session.snapshot
	var archive:Dictionary=snapshot.get("own_xinghe_growth_log",{})
	var tracked:Dictionary=snapshot.get("own_xinghe_growth",{})
	var kinds:=archive.keys()
	kinds.sort()
	var current:=str(tracked.get("kind",""))
	if World.CROPS.has(current) and current not in kinds:kinds.push_front(current)
	var status:=tracking_text(snapshot,tracked)
	var signature:=[kinds,current,completed(snapshot),status]
	if app.modal.get_meta("growth_signature",[])==signature:return
	app.modal.set_meta("growth_signature",signature)
	var selection:=str(app.modal.get_meta("growth_selection",""))
	if selection not in kinds:selection="" if kinds.is_empty() else str(kinds[0])
	if not app.modal.has_meta("growth_index") or app.modal.get_meta("growth_index")!=[kinds,current]:
		app.modal.set_meta("growth_index",[kinds,current])
		build_index(app,kinds,current)
	select(app,selection)

static func build_index(app,kinds:Array,current:String) -> void:
	var index:=app.modal.find_child("XingheGrowthIndex",true,false) as VBoxContainer
	clear(index)
	if kinds.is_empty():label(app,index,"尚未收錄",15,MUTED)
	var group:=ButtonGroup.new()
	for kind:String in kinds:
		var button:Button=app.button(str(World.CROPS[kind].name),select.bind(app,kind))
		button.name="XingheGrowthSpecies_"+kind
		button.toggle_mode=true
		button.button_group=group
		button.icon=Items.icon(kind)
		if kind==current:button.tooltip_text="正在觀察"
		button.add_theme_constant_override("icon_max_width",23)
		index.add_child(button)

static func select(app,kind:String) -> void:
	var snapshot:Dictionary=app.session.snapshot
	var archive:Dictionary=snapshot.get("own_xinghe_growth_log",{})
	var tracked:Dictionary=snapshot.get("own_xinghe_growth",{})
	app.modal.set_meta("growth_selection",kind)
	var index:=app.modal.find_child("XingheGrowthIndex",true,false) as VBoxContainer
	for entry:Node in index.get_children():
		var button:=entry as Button
		if button!=null:button.set_pressed_no_signal(str(button.name)=="XingheGrowthSpecies_"+kind)
	var details:=app.modal.find_child("XingheGrowthPage",true,false) as VBoxContainer
	clear(details)
	var title:=str(World.CROPS[kind].name) if World.CROPS.has(kind) else "從一株幼苗開始"
	label(app,details,title,23,GREEN).name="XingheGrowthSelected"
	var copied:=archive.has(kind)
	var specimens:=HBoxContainer.new()
	specimens.add_theme_constant_override("separation",10)
	details.add_child(specimens)
	specimen(app,specimens,kind,"early","幼苗",not kind.is_empty(),"XingheGrowthEarly")
	specimen(app,specimens,kind,"mature","成熟",copied,"XingheGrowthMature")
	if copied:
		label(app,details,"露天生長季  %s"%World.crop_season_text(kind),15,MUTED)
		var copy:="可以在渡口或蘭陽記錄另一種自己種的作物。" if completed(snapshot) else "把這頁帶到蘭陽水圳旁，和星禾聊聊。"
		label(app,details,copy,16,INK)
	elif not kind.is_empty():
		label(app,details,tracking_text(snapshot,tracked),16,INK).name="XingheGrowthTracking"
	else:
		var copy:="在渡口或蘭陽種一株作物。到田邊按互動鍵，記下幼苗。" if available(snapshot) else "先到蘭陽水圳旁認識星禾，就能開始觀察。"
		label(app,details,copy,16,INK)

static func tracking_text(snapshot:Dictionary,tracked:Dictionary) -> String:
	if tracked.is_empty():return ""
	var region:=str(tracked.get("region",""))
	var kind:=str(tracked.get("kind",""))
	var key:=str(tracked.get("tile",""))
	var spot:=World.REGIONS.label(region)
	if str(snapshot.get("region_id",""))!=region:
		return "正在觀察 %s 的幼苗。回到原本的田邊查看這一株。"%spot
	var crop:Dictionary=snapshot.get("crops",{}).get(key,{})
	if crop.get("kind")!=kind or not World.CROPS.has(kind):
		return "回到 %s 的田邊查看原本的作物。"%spot
	if World.RESIDENT_GOALS.growth_phase(crop,float(World.CROPS[kind].time))=="mature":
		return "%s 的這一株已成熟。到原本的田邊記下成熟的樣子。"%spot
	return "正在觀察 %s 的幼苗。田邊的紙標會標出這一株。"%spot

static func specimen(app,parent:Container,kind:String,phase:String,title:String,recorded:bool,identity:String) -> void:
	var column:=VBoxContainer.new()
	column.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation",4)
	parent.add_child(column)
	var art:=Plate.new()
	art.name=identity
	art.configure(kind if recorded else "",phase)
	column.add_child(art)
	var caption:=label(app,column,"%s  ·  %s"%[title,"已記錄" if recorded else "待記錄"],16,GREEN if recorded else MUTED)
	caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER

static func clear(container:Container) -> void:
	for child:Node in container.get_children():
		container.remove_child(child)
		child.queue_free()

static func panel(parent:Container) -> PanelContainer:
	var box:=PanelContainer.new()
	var trim:=StyleBoxFlat.new()
	trim.bg_color=Color("f1e2be")
	trim.border_color=Color("ad8b62")
	trim.set_border_width_all(1)
	trim.set_content_margin_all(10)
	box.add_theme_stylebox_override("panel",trim)
	parent.add_child(box)
	return box

static func label(app,parent:Container,copy:String,pixels:int,tint:Color) -> Label:
	var text:Label=app.label(copy,pixels)
	text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	text.add_theme_color_override("font_color",tint)
	parent.add_child(text)
	return text
