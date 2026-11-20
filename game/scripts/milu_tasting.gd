extends RefCounted
## N02-3 uses the saved soup choice. Replaying only opens the memory.

const World=preload("res://scripts/world.gd")
const Pixel=preload("res://scripts/inventory_pixel_theme.gd")
const Shell=preload("res://scripts/life_ui_shell.gd")
const Items=preload("res://scripts/inventory_item_art.gd")
const KeepsakeArt=preload("res://scripts/resident_keepsake_art.gd")
const Scene=preload("res://scripts/milu_tasting_scene.gd")
const INK:=Color("4a3224")
const GREEN:=Color("375540")
const FLAVORS:={
	"soup":"「蘿蔔煮得透透的，喝起來甜甜的。這就是我記得的味道。」",
	"forest_mushroom_soup":"「這碗有樹蔭下的香氣……星夜菇和香草煮在一起，喝完還想再添。」",
	"carrot_soup":"「咦，先是胡蘿蔔的甜味，後來才喝到濃濃的湯。我再試一口。」",
}
const RECIPE_NOTES:={
	"salt_grilled_fish":"修通河灣橋去釣溪魚，海鹽可在北門取得。",
	"corn_chowder":"夏天的甜玉米，加上奶糖牛的鮮奶。",
	"pumpkin_pie":"秋天種南瓜，備好麵粉和雞蛋。",
}

static func completed_dish(snapshot:Dictionary) -> String:
	var event:Dictionary=snapshot.get("resident_goals",{}).get("milu",{}).get("3",{})
	var dish:=str(event.get("choice",""))
	return dish if event.get("state","")=="done" and FLAVORS.has(dish) else ""

static func preparation(dish:String) -> String:
	if dish.is_empty():return "選一道湯。準備同一種兩碗，就能請米露試喝。"
	var forest:=dish==World.FOREST_MUSHROOM.DISH
	var station:Dictionary=World.BUILD[World.KITCHEN_STOVE.KIND if forest else "stove"]
	var recipe:Dictionary=World.stove_recipes(World.KITCHEN_STOVE.KIND if forest else "stove")[dish]
	var copy:="%s  ·  %s  ·  約 %d 秒，煮出 %d 碗"%[station.name,ingredient_list(recipe),int(recipe.time),int(recipe.yield)]
	return copy+"\n這份做法可從阿榆的〈林間的濕氣〉取得。" if forest else copy

static func ingredient_list(recipe:Dictionary) -> String:
	var ingredients:=PackedStringArray()
	for item:String in recipe.ingredients:
		ingredients.append("%s ×%d"%[World.NAMES[item],int(recipe.ingredients[item])])
	return "、".join(ingredients)

static func open(app,back:Callable,back_label:String) -> void:
	var snapshot:Dictionary=app.session.snapshot
	var dish:=completed_dish(snapshot)
	if dish.is_empty():return
	var body:VBoxContainer=app._open_modal("不是同一道湯")
	app.modal.name="MiluTasting"
	app.modal.set_meta("life_modal_layout","milu_tasting")
	app.modal.theme=Pixel.make(app.hud.theme)
	app.modal.add_theme_stylebox_override("panel",Pixel.frame_style())
	app.modal.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	body.add_theme_constant_override("separation",14)

	var scene_row:=HBoxContainer.new()
	scene_row.add_theme_constant_override("separation",16)
	body.add_child(scene_row)
	var scene:=Scene.new()
	scene.name="MiluTastingScene"
	scene.dish=dish
	scene.reduced_motion=app.sound.reduced_motion
	scene.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	scene_row.add_child(scene)
	var dialogue:=VBoxContainer.new()
	dialogue.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	dialogue.alignment=BoxContainer.ALIGNMENT_CENTER
	dialogue.add_theme_constant_override("separation",8)
	scene_row.add_child(dialogue)
	var dish_title:=line(app,dialogue,str(World.RECIPES[dish].name),21,GREEN)
	dish_title.name="MiluTastingDish"
	line(app,dialogue,str(FLAVORS[dish]),16,INK)

	var closing:Dictionary=World.RESIDENT_GOALS.goal("milu",3)
	line(app,body,"「%s」"%str(closing.quote[1]),17,INK)
	var keepsake:=HBoxContainer.new()
	keepsake.add_theme_constant_override("separation",12)
	body.add_child(keepsake)
	keepsake.add_child(Shell.picture(KeepsakeArt.piece("keepsake_milu"),48))
	var ribbon:=VBoxContainer.new()
	ribbon.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	ribbon.alignment=BoxContainer.ALIGNMENT_CENTER
	keepsake.add_child(ribbon)
	line(app,ribbon,str(closing.keepsake),16,GREEN)
	var reward:Dictionary=snapshot.get("resident_goals",{}).get("milu",{}).get("3",{}).get("keepsake",{})
	var claimed:=bool(reward.get("claimed",false))
	line(app,ribbon,"可當作家裡的擺設。" if claimed else "回到米露身邊，從完成頁領取空碗。",14,INK)
	var recipes:Button=app.button("翻開中階食譜組",open_notebook.bind(app,open.bind(app,back,back_label)))
	recipes.name="MiluTastingRecipes"
	recipes.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	keepsake.add_child(recipes)

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
	if not scene.reduced_motion:
		var replay:Button=app.button("重播試吃",func():
			scene.replay()
			app.sound.defer_action("meal_serve"))
		replay.name="MiluTastingReplay"
		actions.add_child(replay)
	var return_button:Button=app.button(back_label,back)
	return_button.name="MiluTastingBack"
	actions.add_child(return_button)
	return_button.grab_focus.call_deferred()
	app._layout_preview.call_deferred()

static func open_notebook(app,back:Callable) -> void:
	if completed_dish(app.session.snapshot).is_empty():return
	var body:VBoxContainer=app._open_modal("米露的中階食譜組")
	app.modal.name="MiluTastingFolio"
	app.modal.set_meta("life_modal_layout","milu_tasting_folio")
	app.modal.theme=Pixel.make(app.hud.theme)
	app.modal.add_theme_stylebox_override("panel",Pixel.frame_style())
	app.modal.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	body.add_theme_constant_override("separation",8)
	line(app,body,"到公共廚房灶台試試這三道菜。",16,GREEN)
	var recipes:Dictionary=World.stove_recipes(World.KITCHEN_STOVE.KIND)
	for item:String in RECIPE_NOTES:
		var recipe:Dictionary=recipes[item]
		var row:=HBoxContainer.new()
		row.name="MiluTastingRecipe_"+item
		row.add_theme_constant_override("separation",12)
		body.add_child(row)
		row.add_child(Shell.picture(Items.icon(item),48))
		var notes:=VBoxContainer.new()
		notes.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		row.add_child(notes)
		line(app,notes,"%s  ·  %d 份  ·  %d 秒"%[recipe.name,int(recipe.yield),int(recipe.time)],17,GREEN)
		line(app,notes,ingredient_list(recipe),15,INK)
		line(app,notes,str(RECIPE_NOTES[item]),14,INK)
	var return_button:Button=app.button("返回試吃會",back)
	return_button.name="MiluTastingFolioBack"
	return_button.size_flags_horizontal=Control.SIZE_SHRINK_END
	body.add_child(return_button)
	return_button.grab_focus.call_deferred()
	app._layout_preview.call_deferred()

static func line(app,parent:Container,copy:String,pixels:int,tint:Color) -> Label:
	var text:Label=app.label(copy,pixels)
	text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	text.add_theme_color_override("font_color",tint)
	parent.add_child(text)
	return text
