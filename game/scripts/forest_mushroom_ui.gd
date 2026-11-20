extends RefCounted
## C12 D05「林間的濕氣」：阿榆好感頁上的專屬頁面（圖片＋下一步行動）。
##
## 只讀 snapshot.own_forest_mushroom（伺服器算好的本人摘要）；所有按鈕只送出行動，
## 位置、樹、材料與階段都由 World 重新判定。不放進每日生活訂單（公告板訂單位）。

const World=preload("res://scripts/world.gd")
const Commission=preload("res://scripts/forest_mushroom_commission.gd")
const Art=preload("res://scripts/life_ui_theme.gd")
const ItemArt=preload("res://scripts/inventory_item_art.gd")
const PixelTheme=preload("res://scripts/inventory_pixel_theme.gd")

static func line(app,parent:Container,value:String,font_size:int) -> Label:
	var label:Label=app.label(value,font_size)
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	return label

static func icon(parent:Container,texture:Texture2D,pixels:int) -> void:
	var rect:=TextureRect.new()
	rect.texture=texture
	rect.custom_minimum_size=Vector2(pixels,pixels)
	rect.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	parent.add_child(rect)

static func open(app,back:Callable=Callable()) -> void:
	var snapshot:Dictionary=app.session.snapshot
	var info:Dictionary=snapshot.get("own_forest_mushroom",{})
	var body:VBoxContainer=app._open_modal(Commission.TITLE)
	app.modal.set_meta("life_modal_layout","community_board")
	app.modal.set_meta("forest_mushroom_stage",int(info.get("stage",0)))
	var header:=HBoxContainer.new()
	header.add_theme_constant_override("separation",12)
	body.add_child(header)
	icon(header,Art.icon("aru"),72)
	var heading:=VBoxContainer.new()
	heading.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	line(app,heading,"阿榆・森林菇湯",22)
	line(app,heading,"又暗又穩的濕氣，菇才肯長。",15)
	icon(header,ItemArt.icon(Commission.DISH),64)
	var stage:=int(info.get("stage",0))
	var progress:=PanelContainer.new()
	progress.add_theme_stylebox_override("panel",PixelTheme.paper_style())
	body.add_child(progress)
	var rows:=VBoxContainer.new()
	rows.add_theme_constant_override("separation",8)
	progress.add_child(rows)
	var steps:=["向阿榆接下委託","到外圈樹林察看濕氣","帶星夜菇與風鈴香草回渡口"]
	for index in steps.size():
		var mark:="✓ " if stage>index else ("→ " if stage==index and stage<Commission.STAGE_DONE else "· ")
		line(app,rows,mark+str(steps[index]),16)
	line(app,rows,str(info.get("text","")),15)
	line(app,rows,"報酬：%d 鈴幣，並解鎖在公共廚房灶台煮森林菇湯。"%Commission.REWARD_COINS,14)
	line(app,rows,Commission.FICTION_NOTE,13)
	var player:Dictionary=snapshot.get("players",{}).get(app.session.own_id,{})
	var aru_cell:Vector2i=World.bond_place(snapshot,Commission.RESIDENT)[1]
	match str(info.get("next","")):
		Commission.ACCEPT:
			var accept:Button=app.button("向阿榆接下委託",func():
				app.session.perform(Commission.ACTION,aru_cell,Commission.ACCEPT);app._close_modal())
			accept.name="ForestMushroomAccept"
			body.add_child(accept)
		Commission.SURVEY:
			var tree:=World.forest_mushroom_tree(snapshot,Vector2(float(player.get("x",0.0)),float(player.get("y",0.0))))
			var survey:Button=app.button("察看這棵樹下的濕氣" if tree.x>=0 else "先走到外圈樹林的樹旁",func():
				app.session.perform(Commission.ACTION,tree,Commission.SURVEY);app._close_modal())
			survey.name="ForestMushroomSurvey"
			survey.disabled=tree.x<0
			body.add_child(survey)
		Commission.DELIVER:
			var deliver:Button=app.button("把菇和香草交給阿榆",func():
				app.session.perform(Commission.ACTION,aru_cell,Commission.DELIVER);app._close_modal())
			deliver.name="ForestMushroomDeliver"
			deliver.disabled=not (info.get("missing",{}) as Dictionary).is_empty()
			body.add_child(deliver)
	if back.is_valid():body.add_child(app.button("返回",back))
