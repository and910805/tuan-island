extends RefCounted
## 米露〈忘記吃飯的人〉(T066 N02-1) 的「第一碗湯」說明頁：熱蘿蔔湯配方與廚房介紹。
## Gate: the own snapshot's resident_goals.milu stage 1 state is "open" or "done" (string or int stage key). No saved
## key of its own, so every old save that already reached or finished the event can open it. Nothing here changes the
## recipe, cost, economy, reward or the task gate; every number is read from World (RECIPES.soup, BUILD.stove,
## PUBLIC_KITCHEN, the stove table) and the player's own backpack.
## Page: the real recipe strip (radish -> stove -> soup, with backpack counts), a 小石灶 card and a 公共廚房 card that
## state the real stage of the shared kitchen, and only truthful links: use a stove within reach, otherwise the
## ordinary build folio entry of 小石灶, the map or the shared-kitchen page. Nothing teleports.

const World=preload("res://scripts/world.gd")
const Pixel=preload("res://scripts/inventory_pixel_theme.gd")
const Shell=preload("res://scripts/life_ui_shell.gd")
const Items=preload("res://scripts/inventory_item_art.gd")
const KitchenUI=preload("res://scripts/public_kitchen_ui.gd")
const SoupScene=preload("res://scripts/milu_first_soup_scene.gd")
const INK:=Color("4a3524")
const MUTED:=Color("6b5436")
const GOOD:=Color("37573e")
const SHORT:=Color("8a3d2e")
const PAPER:=Color("ead9b0")
const WOOD:=Color("8a6a43")
const REACH:=3.2
const RESIDENT:="milu"
const DISH:="soup"
const STOVE:="stove"

static func event_state(snapshot:Dictionary) -> String:
	var goals:Variant=snapshot.get("resident_goals")
	if not goals is Dictionary:return ""
	var milu:Variant=goals.get(RESIDENT)
	if not milu is Dictionary:return ""
	var event:Variant=milu.get("1",milu.get(1))
	return str(event.get("state","")) if event is Dictionary else ""

static func available(snapshot:Dictionary) -> bool:
	return event_state(snapshot) in ["open","done"]

## Pure helper (no UI): the stove the player can cook at right now, {} when none.
## {"cell":Vector2i anchor,"kind":String,"public":bool}. Own stoves and the opened public stove only; same region
## and the same 3.2-cell reach as the stove interaction itself.
static func usable_stove(snapshot:Dictionary,own_id:String) -> Dictionary:
	if str(snapshot.get("region_id","home"))!=World.REGIONS.HOME:return {}
	var person:Variant=snapshot.get("players",{}).get(own_id,{})
	if not person is Dictionary or person.is_empty():return {}
	var at:=Vector2(float(person.get("x",0.0)),float(person.get("y",0.0)))
	var objects:Variant=snapshot.get("objects",{})
	if not objects is Dictionary:return {}
	var public_cell:=Vector2i(-1,-1)
	if World.PUBLIC_KITCHEN.stage(snapshot)=="open":
		public_cell=World.PUBLIC_KITCHEN.parse_cell(str(snapshot.get("public_kitchen",{}).get("stove","")))
	var best:={}
	var best_distance:=INF
	for key:Variant in objects:
		var obj:Variant=objects[key]
		if not obj is Dictionary:continue
		var kind:=str(obj.get("type",""))
		if not World.INDUSTRY.is_stove(kind) or World.INDUSTRY.is_stove_extension(obj):continue
		var cell:Vector2i=World.PUBLIC_KITCHEN.parse_cell(str(key))
		if cell==World.PUBLIC_KITCHEN.NO_CELL:continue
		var public:bool=cell==public_cell
		if not public and str(obj.get("owner",""))!=own_id:continue
		var cells:Array[Vector2i]=[cell]
		if kind==World.INDUSTRY.KITCHEN_STOVE:cells=World.KITCHEN_STOVE.cells_at(cell)
		for part in cells:
			var distance:=at.distance_to(Vector2(part)+Vector2(0.5,0.5))
			if distance<=REACH and distance<best_distance:
				best_distance=distance
				best={"cell":cell,"kind":kind,"public":public}
	return best

## Whether the player owns any stove object at all (near or not).
static func owns_stove(snapshot:Dictionary,own_id:String) -> bool:
	var objects:Variant=snapshot.get("objects",{})
	if not objects is Dictionary:return false
	for key:Variant in objects:
		var obj:Variant=objects[key]
		if obj is Dictionary and World.INDUSTRY.is_stove(str(obj.get("type",""))) \
				and not World.INDUSTRY.is_stove_extension(obj) and str(obj.get("owner",""))==own_id:
			return true
	return false

static func seconds_text(seconds:float) -> String:
	return "%d 秒" % int(roundf(seconds))

## The real shared-kitchen state in one sentence.
static func kitchen_state_text(snapshot:Dictionary) -> String:
	var stage:String=World.PUBLIC_KITCHEN.stage(snapshot)
	match stage:
		"open":return "已經開張：渡口的公共石灶任何人都能用。"
		"collect":
			var meals:Variant=snapshot.get("public_kitchen",{}).get("meals",{})
			var parts:PackedStringArray=[]
			for item:String in World.PUBLIC_KITCHEN.MEALS:
				var have:=int(meals.get(item,0)) if meals is Dictionary else 0
				parts.append("%s %d／%d"%[World.PUBLIC_KITCHEN.NAMES[item],have,int(World.PUBLIC_KITCHEN.REQUIREMENTS[item])])
			return "已登記灶與長椅，備料中：%s。"%"、".join(parts)
		"register":return "可以登記了：到共用餐桌，選一座自己的小石灶和兩張長椅捐出。"
		"locked":return "還沒開放：渡口野餐辦過、共用餐桌放好之後，才能登記。"
	return "公共廚房的資料暫時讀不出來，這次先不顯示進度。"

static func open(app,back:Callable,back_label:="返回關係事件") -> void:
	var snapshot:Dictionary=app.session.snapshot
	if not available(snapshot):return
	var body:VBoxContainer=app._open_modal("米露的第一碗湯")
	app.modal.name="MiluFirstSoup"
	app.modal.theme=Pixel.make(app.hud.theme)
	app.modal.add_theme_stylebox_override("panel",Pixel.frame_style())
	app.modal.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	app.modal.set_meta("life_modal_layout","milu_first_soup")
	body.add_theme_constant_override("separation",8)
	var scroll:=body.get_parent() as ScrollContainer
	if scroll!=null:
		var shell:=scroll.get_parent() as VBoxContainer
		shell.add_theme_constant_override("separation",6)
	var own_id:String=str(app.session.own_id)
	var person:Dictionary=snapshot.get("players",{}).get(own_id,{})
	var inventory:Dictionary=person.get("inventory",{})
	var recipe:Dictionary=World.RECIPES[DISH]
	var need_soup:int=int(World.RESIDENT_GOALS.goal(RESIDENT,1).get("items",{}).get(DISH,1))

	var scene_row:=HBoxContainer.new()
	scene_row.add_theme_constant_override("separation",14)
	body.add_child(scene_row)
	var scene:=SoupScene.new()
	scene.name="MiluFirstSoupArt"
	scene.reduced_motion=app.sound.reduced_motion
	scene.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	scene_row.add_child(scene)
	var story:=VBoxContainer.new()
	story.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	story.alignment=BoxContainer.ALIGNMENT_CENTER
	scene_row.add_child(story)
	var completed:=event_state(snapshot)=="done"
	if completed:
		var dialogue:Array=World.RESIDENT_GOALS.goal(RESIDENT,1).quote
		line(app,story,"米露",15).add_theme_color_override("font_color",GOOD)
		for quote:String in dialogue:
			line(app,story,"「%s」"%quote,15).add_theme_color_override("font_color",INK)
	else:
		line(app,story,"忘記吃飯的人",18).add_theme_color_override("font_color",GOOD)
		var head:=line(app,story,"熱蘿蔔湯只要兩顆蘿蔔。下鍋、等一下、回來領，就能端一碗給米露。",16)
		head.add_theme_color_override("font_color",MUTED)

	body.add_child(recipe_strip(app,recipe,inventory,need_soup,completed))

	var interact:String=app.binding_label("interact")
	var instructions:="想再煮一鍋，在灶邊按 %s 下鍋，煮好再回來領。"%interact if completed else "灶邊按 %s 下鍋，湯好了再回來領。帶 %d 碗去找米露。"%[interact,need_soup]
	var steps:=line(app,body,instructions,15)
	steps.name="MiluFirstSoupSteps"
	steps.add_theme_color_override("font_color",INK)

	var usable:=usable_stove(snapshot,own_id)
	var cards:=HBoxContainer.new()
	cards.name="MiluFirstSoupKitchens"
	cards.add_theme_constant_override("separation",10)
	body.add_child(cards)
	var focus:=own_stove_card(app,cards,snapshot,own_id,inventory,usable)
	var shared_focus:=shared_kitchen_card(app,cards,snapshot,usable)
	if focus==null:focus=shared_focus

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
	if completed and not scene.reduced_motion:
		var replay:Button=app.button("重播片段",scene.replay)
		replay.name="MiluFirstSoupReplay"
		actions.add_child(replay)
	var close:Button=app.button(back_label,back)
	close.name="MiluFirstSoupBack"
	actions.add_child(close)
	(focus if focus!=null else close).grab_focus.call_deferred()
	app._layout_preview.call_deferred()

## radish x2 -> stove (time) -> soup x2, each with its backpack count.
static func recipe_strip(app,recipe:Dictionary,inventory:Dictionary,need_soup:int,completed:bool) -> Control:
	var panel:=PanelContainer.new()
	panel.name="MiluFirstSoupRecipe"
	panel.add_theme_stylebox_override("panel",paper_box(WOOD))
	var row:=HBoxContainer.new()
	row.add_theme_constant_override("separation",10)
	row.alignment=BoxContainer.ALIGNMENT_CENTER
	panel.add_child(row)
	var ingredients:Dictionary=recipe.ingredients
	for item:String in ingredients:
		var need:=int(ingredients[item])
		var held:=int(inventory.get(item,0))
		var column:=item_column(app,Items.icon(item),"%s ×%d"%[World.NAMES.get(item,item),need],"背包 %d／%d"%[held,need],held>=need)
		column.name="MiluFirstSoupIngredient_"+item
		row.add_child(column)
	row.add_child(arrow(app))
	var stove:=item_column(app,KitchenUI.stove_icon(),"小石灶","約 %s"%seconds_text(float(recipe.time)),true)
	stove.name="MiluFirstSoupTime"
	row.add_child(stove)
	row.add_child(arrow(app))
	var held_soup:=int(inventory.get(DISH,0))
	var count:="背包 %d 碗"%held_soup if completed else "背包 %d · 要交 %d"%[held_soup,need_soup]
	var result:=item_column(app,Items.icon(DISH),"%s ×%d"%[str(recipe.name),int(recipe.yield)],count,completed or held_soup>=need_soup)
	result.name="MiluFirstSoupYield"
	# The finished bowl gets one short puff of steam (still when reduced motion is on).
	var bowl:=result.get_child(0)
	var steam:=SteamBowl.new()
	steam.name="MiluFirstSoupSteam"
	steam.texture=Items.icon(DISH)
	steam.reduced_motion=app.sound.reduced_motion
	steam.custom_minimum_size=Vector2(48,48)
	steam.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
	result.remove_child(bowl)
	bowl.queue_free()
	result.add_child(steam)
	result.move_child(steam,0)
	row.add_child(result)
	return panel

static func item_column(app,texture:Texture2D,title:String,count:String,enough:bool) -> VBoxContainer:
	var column:=VBoxContainer.new()
	column.add_theme_constant_override("separation",2)
	column.custom_minimum_size.x=146
	column.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
	var picture:=Shell.picture(texture,48)
	picture.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
	column.add_child(picture)
	var name_label:=line(app,column,title,16)
	name_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_color_override("font_color",INK)
	var count_label:=line(app,column,count,14)
	count_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	count_label.add_theme_color_override("font_color",GOOD if enough else SHORT)
	return column

static func arrow(app) -> Label:
	var mark:Label=app.label("→",24)
	mark.add_theme_color_override("font_color",WOOD)
	mark.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	return mark

## Left card: the player's own 小石灶. Returns the button to focus.
static func own_stove_card(app,cards:Container,snapshot:Dictionary,own_id:String,inventory:Dictionary,usable:Dictionary) -> Button:
	var card:=kitchen_card(cards,"MiluFirstSoupOwnStove",WOOD)
	line(app,card,"自己的小石灶",18).add_theme_color_override("font_color",INK)
	var note:=line(app,card,"在家園放一座灶，就能開始煮湯。",14)
	note.add_theme_color_override("font_color",MUTED)
	var cost:=World.BUILD[STOVE]
	var costs:=HBoxContainer.new()
	costs.add_theme_constant_override("separation",10)
	card.add_child(costs)
	for item:String in cost:
		if item=="name":continue
		var need:=int(cost[item])
		var held:=int(inventory.get(item,0))
		var pair:=HBoxContainer.new()
		pair.add_theme_constant_override("separation",4)
		costs.add_child(pair)
		pair.add_child(Shell.picture(Items.icon(item),20))
		var count:=line(app,pair,"%s %d／%d"%[World.NAMES.get(item,item),held,need],14)
		count.autowrap_mode=TextServer.AUTOWRAP_OFF
		count.add_theme_color_override("font_color",GOOD if held>=need else SHORT)
	var button:Button
	if not usable.is_empty() and not bool(usable.public):
		var kind:String=str(usable.kind)
		var title:="廚房灶台" if kind==World.INDUSTRY.KITCHEN_STOVE else "小石灶"
		button=app.button("使用身旁的%s"%title,app._cook_menu.bind(usable.cell))
		button.name="MiluFirstSoupUseStove"
		var table:Dictionary=World.stove_recipes(kind)
		if table.has(DISH) and kind==World.INDUSTRY.KITCHEN_STOVE:
			var seconds:=float(table[DISH].time)
			if not is_equal_approx(seconds,float(World.RECIPES[DISH].time)):
				line(app,card,"這座灶煮湯約 %s。"%seconds_text(seconds),14).add_theme_color_override("font_color",MUTED)
	else:
		if str(snapshot.get("region_id","home"))!=World.REGIONS.HOME:
			line(app,card,"回到家園後，就能查看自己的灶。",14).add_theme_color_override("font_color",MUTED)
		elif owns_stove(snapshot,own_id):
			line(app,card,"走到自己的灶旁，按 %s 就能煮。"%app.binding_label("interact"),14).add_theme_color_override("font_color",GOOD)
		else:
			line(app,card,"建造前，先備好上面的材料。",14).add_theme_color_override("font_color",MUTED)
		button=app.button("查看小石灶建造圖樣",func():app.life_panels.build_menu(app,STOVE))
		button.name="MiluFirstSoupBuildStove"
		button.icon=KitchenUI.stove_icon()
		button.expand_icon=true
		button.add_theme_constant_override("icon_max_width",24)
	button.size_flags_vertical=Control.SIZE_SHRINK_END
	card.add_child(button)
	return button

## Right card: the 公共廚房 with its real stage. Returns the button to focus.
static func shared_kitchen_card(app,cards:Container,snapshot:Dictionary,usable:Dictionary) -> Button:
	var card:=kitchen_card(cards,"MiluFirstSoupSharedKitchen",GOOD)
	line(app,card,"公共廚房",18).add_theme_color_override("font_color",INK)
	var note:=line(app,card,"開張後，大家都能在渡口共用石灶。",14)
	note.add_theme_color_override("font_color",MUTED)
	var stage:String=World.PUBLIC_KITCHEN.stage(snapshot)
	var state:=line(app,card,kitchen_state_text(snapshot),14)
	state.name="MiluFirstSoupKitchenState"
	state.add_theme_color_override("font_color",GOOD if stage=="open" else INK)
	var button:Button
	if stage=="open":
		var at_home:bool=str(snapshot.get("region_id","home"))==World.REGIONS.HOME
		if not usable.is_empty() and bool(usable.public):
			button=app.button("使用公共石灶",app._cook_menu.bind(usable.cell))
			button.name="MiluFirstSoupPublicStove"
		elif at_home:
			button=app.button("在地圖找公共廚房",app._map_menu)
			button.name="MiluFirstSoupKitchenMap"
		else:
			line(app,card,"回到風鈴渡口後，可從周邊地圖找到公共廚房。",14).add_theme_color_override("font_color",MUTED)
	if button==null:
		button=app.button("查看公共廚房",func():KitchenUI.open(app))
		button.name="MiluFirstSoupKitchenPage"
		button.icon=KitchenUI.stove_icon()
		button.expand_icon=true
		button.add_theme_constant_override("icon_max_width",24)
	else:
		var more:Button=app.button("查看公共廚房",func():KitchenUI.open(app))
		more.name="MiluFirstSoupKitchenPage"
		more.size_flags_vertical=Control.SIZE_SHRINK_END
		card.add_child(more)
	button.size_flags_vertical=Control.SIZE_SHRINK_END
	card.add_child(button)
	return button

static func kitchen_card(parent:Container,node_name:String,edge:Color) -> VBoxContainer:
	var panel:=PanelContainer.new()
	panel.name=node_name
	panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	panel.size_flags_stretch_ratio=1.0
	panel.add_theme_stylebox_override("panel",paper_box(edge))
	parent.add_child(panel)
	var column:=VBoxContainer.new()
	column.add_theme_constant_override("separation",5)
	panel.add_child(column)
	return column

static func paper_box(edge:Color) -> StyleBoxFlat:
	var box:=StyleBoxFlat.new()
	box.bg_color=PAPER
	box.border_color=edge
	box.set_border_width_all(2)
	box.border_width_bottom=4
	box.set_corner_radius_all(2)
	box.set_content_margin_all(8)
	return box

static func line(app,parent:Container,copy:String,extent:int) -> Label:
	var label:Label=app.label(copy,extent)
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	parent.add_child(label)
	return label

## The existing soup icon with one short puff of steam (about 1.6 s on open). Reduced motion: no steam at all.
class SteamBowl extends Control:
	const SECONDS:=1.6
	const PUFF:=Color(1.0,0.96,0.85,0.8)
	var texture:Texture2D
	var reduced_motion:=false
	var elapsed:=0.0

	func _ready() -> void:
		mouse_filter=Control.MOUSE_FILTER_IGNORE
		texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
		set_process(not reduced_motion)

	func _process(delta:float) -> void:
		elapsed+=delta
		if elapsed>=SECONDS:
			set_process(false)
		queue_redraw()

	func _draw() -> void:
		var extent:=minf(size.x,size.y)
		var origin:=Vector2((size.x-extent)*0.5,(size.y-extent)*0.5)
		if texture!=null:
			draw_texture_rect(texture,Rect2(origin+Vector2(0,extent*0.12),Vector2(extent,extent)*0.88),false)
		if reduced_motion or elapsed>=SECONDS:return
		for index in 3:
			var phase:=fposmod(elapsed*0.9+float(index)*0.3,1.0)
			var x:=origin.x+extent*(0.3+0.2*float(index))+roundf(sin((elapsed+float(index))*4.0)*1.5)
			var y:=origin.y+extent*0.2-roundf(phase*extent*0.22)
			var fade:=clampf((SECONDS-elapsed)/0.4,0.0,1.0)
			draw_rect(Rect2(Vector2(roundf(x),roundf(y)),Vector2(2,4)),Color(PUFF.r,PUFF.g,PUFF.b,PUFF.a*(1.0-phase)*fade))
