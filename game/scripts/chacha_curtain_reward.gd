extends RefCounted
## Tea pudding recipe and curtain diagram from Chacha's second relationship event.

const World=preload("res://scripts/world.gd")
const Pixel=preload("res://scripts/inventory_pixel_theme.gd")
const Shell=preload("res://scripts/life_ui_shell.gd")
const Items=preload("res://scripts/inventory_item_art.gd")
const BLIND=preload("res://assets/ui-life/bamboo-curtain.png")
const DISH:="tea_pudding"
const CURTAIN:="bamboo_curtain"

static func available(snapshot:Dictionary) -> bool:
	var goals:Variant=snapshot.get("resident_goals")
	if not goals is Dictionary:return false
	var chacha:Variant=goals.get("chacha")
	if not chacha is Dictionary:return false
	var event:Variant=chacha.get("2",chacha.get(2))
	return event is Dictionary and event.get("state")=="done"

static func open(app,back:Callable) -> void:
	var snapshot:Dictionary=app.session.snapshot
	if not available(snapshot):return
	var body:VBoxContainer=app._open_modal("漏下來的一束光")
	app.modal.name="ChachaCurtainReward"
	app.modal.theme=Pixel.make(app.hud.theme)
	app.modal.add_theme_stylebox_override("panel",Pixel.frame_style())
	app.modal.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	app.modal.set_meta("life_modal_layout","keepsake_paper")
	body.add_theme_constant_override("separation",8)

	var person:Dictionary=snapshot.get("players",{}).get(app.session.own_id,{})
	var inventory:Dictionary=person.get("inventory",{})

	var page:=HBoxContainer.new()
	page.add_theme_constant_override("separation",10)
	body.add_child(page)

	# Section 1: D11 茶香布丁 on the 公共廚房灶台 table.
	var stove:String=World.INDUSTRY.KITCHEN_STOVE
	var recipe:Dictionary=World.stove_recipes(stove).get(DISH,{})
	var pudding:=section(page,"ChachaCurtainPudding")
	var head:=HBoxContainer.new()
	head.add_theme_constant_override("separation",8)
	pudding.add_child(head)
	head.add_child(Shell.picture(Items.icon(DISH),32))
	line(app,head,World.NAMES[DISH],17)
	var ingredients:Dictionary=recipe.get("ingredients",{})
	for item:String in ingredients:
		pudding.add_child(part_row(app,"ChachaCurtainPuddingPart_"+item,item,int(ingredients[item]),inventory))
	var timing:=line(app,pudding,"遊戲內 %d 秒 · 一次 %d 份"%[int(recipe.time),int(recipe.yield)],15)
	timing.name="ChachaCurtainPuddingTime"
	var how:=line(app,pudding,"到公共廚房的灶台排入料理，煮好後回來領取。",14)
	how.name="ChachaCurtainPuddingHow"
	how.add_theme_color_override("font_color",Color("5a6042"))

	# Section 2: T04 半透竹簾 guide (an ordinary buildable, shown as the learned diagram).
	var cost:Dictionary=World.BUILD.get(CURTAIN,{})
	var guide:=section(page,"ChachaCurtainGuide")
	var title:=HBoxContainer.new()
	title.add_theme_constant_override("separation",8)
	guide.add_child(title)
	title.add_child(Shell.picture(BLIND,32))
	line(app,title,str(cost.name)+"圖樣",17)
	for item:String in cost:
		if item=="name":continue
		guide.add_child(part_row(app,"ChachaCurtainGuidePart_"+item,item,int(cost[item]),inventory))
	var need:=line(app,guide,"掛在自家木窗南面。先拆竹簾，才能拆窗。",14)
	need.name="ChachaCurtainGuideNeed"
	need.add_theme_color_override("font_color",Color("5a6042"))

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
	var preview:Button=app.button("預覽竹簾",func():app.life_panels.build_menu(app,CURTAIN))
	preview.name="ChachaCurtainBuiltPreview"
	actions.add_child(preview)
	var close:Button=app.button("返回關係事件",back)
	close.name="ChachaCurtainRewardBack"
	actions.add_child(close)
	close.grab_focus.call_deferred()
	app._layout_preview.call_deferred()

static func section(page:Container,node_name:String) -> VBoxContainer:
	var panel:=PanelContainer.new()
	panel.name=node_name
	panel.add_theme_stylebox_override("panel",Pixel.paper_style())
	panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio=1.0
	page.add_child(panel)
	var box:=VBoxContainer.new()
	box.add_theme_constant_override("separation",4)
	panel.add_child(box)
	return box

static func part_row(app,node_name:String,item:String,need:int,inventory:Dictionary) -> HBoxContainer:
	var row:=HBoxContainer.new()
	row.name=node_name
	row.add_theme_constant_override("separation",8)
	row.add_child(Shell.picture(Items.icon(item),24))
	line(app,row,"%s ×%d"%[World.NAMES.get(item,item),need],16)
	var held:=int(inventory.get(item,0))
	var count:=line(app,row,"背包 %d"%held,14)
	count.add_theme_color_override("font_color",Color("37573e") if held>=need else Color("8a3d2e"))
	return row

static func line(app,parent:Container,copy:String,extent:int) -> Label:
	var label:Label=app.label(copy,extent)
	label.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	if parent is VBoxContainer:
		label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	return label
