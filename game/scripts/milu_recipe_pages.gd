extends RefCounted
## The portable plaza clues and the restored companion to the public dining table.

const World=preload("res://scripts/world.gd")
const Goals=World.RESIDENT_GOALS
const Pixel=preload("res://scripts/inventory_pixel_theme.gd")
const Shell=preload("res://scripts/life_ui_shell.gd")
const Items=preload("res://scripts/inventory_item_art.gd")
const Sketch=preload("res://scripts/milu_recipe_map.gd")
const MendScene=preload("res://scripts/milu_recipe_mend_scene.gd")
const SITES:=["board","shop","table"]
const DISHES:=["hotpot","watermelon","chowder"]
const INK:=Color("483020")
const GREEN:=Color("35543d")
const MUTED:=Color("6a5236")

static func completed(snapshot:Dictionary) -> bool:
	return snapshot.get("resident_goals",{}).get("milu",{}).get("2",{}).get("state")=="done"

static func open(app,back:Callable,back_label:String) -> void:
	var snapshot:Dictionary=app.session.snapshot
	var done:=completed(snapshot)
	var body:VBoxContainer=app._open_modal("米露的共餐桌手記" if done else "沾到麵粉的頁角")
	app.modal.name="MiluRecipePages"
	app.modal.set_meta("life_modal_layout","milu_recipe_book")
	app.modal.set_meta("milu_recipe_restored",done)
	app.modal.theme=Pixel.make(app.hud.theme)
	app.modal.add_theme_stylebox_override("panel",Pixel.frame_style())
	app.modal.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	body.add_theme_constant_override("separation",10)
	var actions:=HBoxContainer.new()
	actions.alignment=BoxContainer.ALIGNMENT_END
	actions.add_theme_constant_override("separation",8)
	if done:
		show_handbook(app,body,actions,snapshot)
	else:
		show_search(app,body,snapshot)
	if is_instance_valid(app.modal_feedback) and app.modal.is_ancestor_of(app.modal_feedback):
		var footer:Label=app.modal_feedback
		footer.get_parent().add_child(actions)
		footer.reparent(actions,false)
		actions.move_child(footer,0)
		footer.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		footer.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	else:
		body.add_child(actions)
	var back_button:Button=app.button(back_label,back)
	back_button.name="MiluRecipeBack"
	actions.add_child(back_button)
	app._layout_preview.call_deferred()

static func show_search(app,body:VBoxContainer,snapshot:Dictionary) -> void:
	var found:=int(snapshot.get("own_milu_recipe_pages",0))
	var cells:Dictionary={}
	var pieces:=0
	for site:String in SITES:
		cells[site]=World.milu_recipe_cell(snapshot,site)
		pieces+=int((found&int(Goals.RECIPE_PAGES[site].bit))!=0)
	var progress:=label(app,body,"已找到 %d／%d 片"%[pieces,SITES.size()],18,GREEN)
	progress.name="MiluRecipeProgress"
	var spread:=HBoxContainer.new()
	spread.add_theme_constant_override("separation",12)
	body.add_child(spread)
	var atlas:=paper(spread)
	atlas.custom_minimum_size.x=284
	label(app,atlas,"風鈴渡口",16,GREEN)
	var sketch:=Sketch.new()
	sketch.name="MiluRecipeMap"
	sketch.configure(cells,found)
	atlas.add_child(sketch)
	var list:=VBoxContainer.new()
	list.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation",7)
	spread.add_child(list)
	for index in SITES.size():
		var site:String=SITES[index]
		var detail:Dictionary=Goals.RECIPE_PAGES[site]
		var picked:bool=(found&int(detail.bit))!=0
		var entry:=paper(list)
		entry.name="MiluRecipeClue_"+site
		label(app,entry,"%d  %s"%[index+1,detail.name],17,GREEN if picked else INK)
		var hint:String=detail.hint
		if cells[site]==World.COMMUNITY.NO_CELL:
			hint="共餐桌還沒擺好。讓出廣場上的空位，桌子就會擺上。" if snapshot.get("picnic",false) else "先完成渡口野餐，等共餐桌擺好再來。"
		label(app,entry,"已收好紙角" if picked else hint,15,GREEN if picked else MUTED)
	var next:="三片都找到了。回去找米露，把紙角交給她。" if pieces==SITES.size() else "順序不限。走到標記旁按 %s 查看，就能拾起紙角。"%app.binding_label("interact")
	label(app,body,next,16,INK).name="MiluRecipeNext"

static func show_handbook(app,body:VBoxContainer,actions:HBoxContainer,snapshot:Dictionary) -> void:
	var spread:=HBoxContainer.new()
	spread.add_theme_constant_override("separation",14)
	body.add_child(spread)
	var animation:=MendScene.new()
	animation.name="MiluRecipeMend"
	animation.reduced_motion=app.sound.reduced_motion
	animation.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	spread.add_child(animation)
	var quotes:=VBoxContainer.new()
	quotes.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	quotes.alignment=BoxContainer.ALIGNMENT_CENTER
	spread.add_child(quotes)
	label(app,quotes,"米露",16,GREEN)
	for quote:String in Goals.goal("milu",2).quote:
		label(app,quotes,"「%s」"%quote,15,INK)
	var details:=paper(body)
	label(app,details,"共餐桌怎麼用",20,GREEN)
	label(app,details,"帶 %d 份同一道料理上桌。每位島民每輪可以領 1 份。"%World.COMMUNITY.HOTPOT_PORTIONS,16,INK)
	if World.TABLE_WARMER.installed(snapshot):
		label(app,details,"保溫底座也能一次端上 %d 份熱火鍋。"%World.COMMUNITY.WARM_HOTPOT_PORTIONS,14,MUTED)
	var dishes:=HBoxContainer.new()
	dishes.add_theme_constant_override("separation",8)
	details.add_child(dishes)
	var person:Dictionary=snapshot.get("players",{}).get(app.session.own_id,{})
	var bag:Dictionary=person.get("inventory",{})
	for dish:String in DISHES:
		var item:String=World.COMMUNITY.DISHES[dish]
		var column:=paper(dishes)
		column.name="MiluRecipeDish_"+dish
		var picture:=Shell.picture(Items.icon(item),42)
		picture.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
		column.add_child(picture)
		label(app,column,World.NAMES[item],16,INK).horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		label(app,column,"背包 %d 份"%int(bag.get(item,0)),14,MUTED).horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	var cell:=World.milu_recipe_cell(snapshot,"table")
	var spot:=Vector2(float(person.get("x",0)),float(person.get("y",0)))
	if snapshot.get("region_id")==World.REGIONS.HOME and cell!=World.COMMUNITY.NO_CELL and spot.distance_to(Vector2(cell)+Vector2(0.5,0.5))<=3.2:
		var enter:Button=app.button("打開共餐桌",app._community_menu)
		enter.name="MiluRecipeOpenTable"
		enter.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
		body.add_child(enter)
	else:
		label(app,body,"帶好想分享的料理，到渡口廣場的共餐桌旁就能上桌。",16,MUTED)
	if not animation.reduced_motion:
		var replay:Button=app.button("重播拼合",animation.replay)
		replay.name="MiluRecipeReplay"
		actions.add_child(replay)

static func paper(parent:Container) -> VBoxContainer:
	var panel:=PanelContainer.new()
	panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var trim:=StyleBoxFlat.new()
	trim.bg_color=Color("ead8b0")
	trim.border_color=Color("a38457")
	trim.set_border_width_all(1)
	trim.border_width_bottom=3
	trim.set_content_margin_all(9)
	panel.add_theme_stylebox_override("panel",trim)
	parent.add_child(panel)
	var paper_content:=VBoxContainer.new()
	paper_content.add_theme_constant_override("separation",4)
	panel.add_child(paper_content)
	return paper_content

static func label(app,parent:Container,copy:String,extent:int,color:Color) -> Label:
	var text:Label=app.label(copy,extent)
	text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	text.add_theme_color_override("font_color",color)
	parent.add_child(text)
	return text
