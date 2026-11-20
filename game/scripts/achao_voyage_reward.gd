extends RefCounted
## 阿潮〈航海手記〉（N05-3）完成後的獎勵頁：海鮮燉飯兩份真實食譜＋木色／藍白船身對照。
## 純閱讀。換船身的免費開關只在渡口碼頭面板；這裡只在根節點給了 dock 回呼時才顯示按鈕。

const World=preload("res://scripts/world.gd")
const Goals=preload("res://scripts/resident_goals.gd")
const Pixel=preload("res://scripts/inventory_pixel_theme.gd")
const Shell=preload("res://scripts/life_ui_shell.gd")
const Items=preload("res://scripts/inventory_item_art.gd")
const Art=preload("res://scripts/achao_voyage_reward_art.gd")
const DISH:="seafood_rice"

static func available(snapshot:Dictionary) -> bool:
	var goals:Variant=snapshot.get("resident_goals")
	if not goals is Dictionary:return false
	var achao:Variant=goals.get("achao")
	if not achao is Dictionary:return false
	var event:Variant=achao.get("3",achao.get(3))
	return event is Dictionary and event.get("state")=="done"

static func open(app,back:Callable,dock:Callable,back_text:String="返回關係事件") -> void:
	var snapshot:Dictionary=app.session.snapshot
	if not available(snapshot):return
	var body:VBoxContainer=app._open_modal("阿潮的航海手記")
	app.modal.name="AchaoVoyageReward"
	app.modal.theme=Pixel.make(app.hud.theme)
	app.modal.add_theme_stylebox_override("panel",Pixel.frame_style())
	app.modal.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	app.modal.set_meta("life_modal_layout","achao_voyage_reward")
	body.add_theme_constant_override("separation",6)

	var person:Dictionary=snapshot.get("players",{}).get(app.session.own_id,{})
	var inventory:Dictionary=person.get("inventory",{})
	var blue:bool=person.get(Goals.VOYAGE_PAINT,false)==true

	var head:=HBoxContainer.new()
	head.add_theme_constant_override("separation",8)
	body.add_child(head)
	head.add_child(Shell.picture(Items.icon(DISH),40))
	line(app,head,"海鮮燉飯",18)

	var page:=HBoxContainer.new()
	page.add_theme_constant_override("separation",8)
	body.add_child(page)
	var stove:Dictionary=World.stove_recipes("stove").get(DISH,{})
	var kitchen:Dictionary=World.stove_recipes(World.INDUSTRY.KITCHEN_STOVE).get(DISH,{})
	recipe_card(app,page,"AchaoVoyageRewardStove","小石灶",stove,inventory)
	recipe_card(app,page,"AchaoVoyageRewardKitchen",str(World.BUILD.get(World.INDUSTRY.KITCHEN_STOVE,{}).get("name","公共廚房灶台")),kitchen,inventory)

	var art:Control=Art.make(blue,app.sound.reduced_motion)
	art.name="AchaoVoyageRewardArt"
	body.add_child(art)

	var note:=line(app,body,"目前使用%s。可在渡口碼頭免費切換。"%("藍白船身" if blue else "原木船身"),14)
	note.name="AchaoVoyageRewardNote"
	note.add_theme_color_override("font_color",Color("5a6042"))

	# 固定頁尾：放在捲動區之外，與回饋文字同列。
	var actions:=HBoxContainer.new()
	actions.name="AchaoVoyageRewardFooter"
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
	if dock.is_valid():
		var swap:Button=app.button("到碼頭換船身",dock)
		swap.name="AchaoVoyageRewardDock"
		actions.add_child(swap)
	var close:Button=app.button(back_text,back)
	close.name="AchaoVoyageRewardBack"
	actions.add_child(close)
	close.grab_focus.call_deferred()
	app._layout_preview.call_deferred()

static func recipe_card(app,page:Container,node_name:String,station:String,recipe:Dictionary,inventory:Dictionary) -> void:
	var box:=section(page,node_name)
	line(app,box,station,16)
	if recipe.is_empty():
		line(app,box,"這個灶台目前沒有這道食譜。",14)
		return
	var ingredients:Dictionary=recipe.get("ingredients",{})
	for item:String in ingredients:
		box.add_child(part_row(app,node_name+"Part_"+item,item,int(ingredients[item]),inventory))
	var timing:=line(app,box,"遊戲內 %d 秒 · 一次 %d 份"%[int(recipe.get("time",0)),int(recipe.get("yield",0))],14)
	timing.name=node_name+"Time"

static func section(page:Container,node_name:String) -> VBoxContainer:
	var panel:=PanelContainer.new()
	panel.name=node_name
	panel.add_theme_stylebox_override("panel",Pixel.paper_style())
	panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	page.add_child(panel)
	var box:=VBoxContainer.new()
	box.add_theme_constant_override("separation",3)
	panel.add_child(box)
	return box

static func part_row(app,node_name:String,item:String,need:int,inventory:Dictionary) -> HBoxContainer:
	var row:=HBoxContainer.new()
	row.name=node_name
	row.add_theme_constant_override("separation",6)
	row.add_child(Shell.picture(Items.icon(item),22))
	line(app,row,"%s ×%d"%[World.NAMES.get(item,item),need],15)
	var held:=int(inventory.get(item,0))
	var count:=line(app,row,"背包 %d"%held,13)
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
