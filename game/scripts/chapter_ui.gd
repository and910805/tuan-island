extends RefCounted

const World=preload("res://scripts/world.gd")
const Village=preload("res://scripts/village.gd")
const Art=preload("res://scripts/life_ui_theme.gd")
const Pixel=preload("res://scripts/inventory_pixel_theme.gd")
const Shell=preload("res://scripts/life_ui_shell.gd")
const Tasks=preload("res://scripts/life_ui_tasks.gd")
const Items=preload("res://scripts/inventory_item_art.gd")
const STEPS:=["grow","ship","works","water","meal"]
const ICONS:=["radish","wood","stone","sprinkler_kit","soup"]

static func open(app) -> void:
	var content:VBoxContainer=app._open_modal("讓渡口重新開飯")
	app.modal.set_meta("life_modal_layout","chapter_letter")
	app.modal.set_meta("chapter_content",content)
	refresh(app)

static func refresh(app) -> void:
	if not is_instance_valid(app.modal):return
	Tasks.refresh_chapter_starter(app)
	if not app.modal.has_meta("chapter_content"):return
	var step:Dictionary=World.CHAPTER_ONE.next_step(app.session.snapshot)
	if step.id=="meal":
		var person:Dictionary=app.session.snapshot.get("players",{}).get(app.session.own_id,{})
		var inventory:Dictionary=person.get("inventory",{})
		step.meal_counts={}
		for item in ["radish","wheat","soup","bread"]:
			step.meal_counts[item]=int(inventory.get(item,0))
		step.meal_delivered=app.session.snapshot.get("picnic_materials",{}).duplicate(true)
	if app.modal.get_meta("chapter_step",{})==step:return
	app.modal.set_meta("chapter_step",step)
	var content:VBoxContainer=app.modal.get_meta("chapter_content")
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	var letter:=PanelContainer.new()
	letter.add_theme_stylebox_override("panel",Pixel.paper_style())
	content.add_child(letter)
	var body:=VBoxContainer.new()
	body.add_theme_constant_override("separation",8)
	letter.add_child(body)
	var progress:=HBoxContainer.new()
	progress.add_theme_constant_override("separation",8)
	body.add_child(progress)
	var phase:=str(step.get("id","grow"))
	var index:=STEPS.find(phase)
	var done:=STEPS.size() if phase=="complete" else maxi(index,0)
	for slot in STEPS.size():
		var icon:=Shell.picture(Items.icon(ICONS[slot]),24)
		icon.modulate=Color.WHITE if slot<=done else Color(1,1,1,0.4)
		progress.add_child(icon)
	progress.add_child(app.label("%d／%d 步完成"%[done,STEPS.size()],15))
	var npc:=str(step.get("npc",""))
	var portrait:=HBoxContainer.new()
	portrait.add_theme_constant_override("separation",12)
	body.add_child(portrait)
	if Village.NPCS.has(npc):portrait.add_child(Shell.picture(Art.icon(npc),48))
	var text:=VBoxContainer.new()
	text.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	portrait.add_child(text)
	if Village.NPCS.has(npc):text.add_child(app.label(Village.NPCS[npc].name,17))
	var dialogue:Label=app.label("「"+str(step.get("line",""))+"」",16)
	dialogue.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	text.add_child(dialogue)
	var action:Label=app.label(str(step.get("action","")),18)
	action.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	body.add_child(action)
	var locations:={"grow":"小栗種子攤東北邊的田","ship":"渡口出貨箱","works":"渡口公告板","water":"阿榆的工坊旁","meal":"渡口公告板","complete":"小栗的種子攤"}
	body.add_child(app.label(str(locations.get(phase,"渡口")),14))
	if phase=="water":
		var flow:=HBoxContainer.new()
		flow.name="ChapterWaterFlow"
		body.add_child(flow)
		for item in ["tank_kit","pipe_kit","sprinkler_kit","radish"]:
			if flow.get_child_count()>0:
				var arrow:Label=app.label("→",16)
				arrow.autowrap_mode=TextServer.AUTOWRAP_OFF
				arrow.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
				flow.add_child(arrow)
			var icon:=Shell.picture(Items.icon(item),28)
			icon.tooltip_text=World.NAMES[item]
			flow.add_child(icon)
	if phase=="grow":
		add_first_crop(app,body)
	elif step.get("detail")!=step.get("action"):
		var details:Label=app.label(str(step.get("detail","")),15)
		details.name="ChapterDetails"
		details.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		body.add_child(details)
	if phase=="meal":add_picnic_recipes(app,body,step.meal_counts,step.meal_delivered)
	var footer:=HBoxContainer.new()
	var shell:Node=content.get_parent().get_parent()
	for child in shell.get_children():
		if child.has_meta("chapter_routes"):
			shell.remove_child(child)
			child.queue_free()
	shell.add_child(footer)
	shell.move_child(footer,shell.get_child_count()-3)
	footer.set_meta("chapter_routes",true)
	var map_button:Button=app.button("查看小島地圖",app._map_menu)
	map_button.icon=Shell.icon("map")
	footer.add_child(map_button)
	var book_button:Button=app.button("島民手冊",func():app._journal())
	book_button.icon=Shell.icon("journal")
	footer.add_child(book_button)

static func add_picnic_recipes(app,body:VBoxContainer,held:Dictionary,delivered:Dictionary) -> void:
	var recipes:=VBoxContainer.new()
	recipes.name="ChapterPicnicRecipes"
	recipes.add_theme_constant_override("separation",8)
	body.add_child(recipes)
	if app.village_art_preview:
		var stove:Button=app.button("查看小石灶配方",func():app.life_panels.build_menu(app,"stove"))
		stove.name="ChapterBuildStove"
		stove.icon=Items.icon("soup")
		recipes.add_child(stove)
	for item in ["soup","bread"]:
		var recipe:Dictionary=World.RECIPES[item]
		var row:=HBoxContainer.new()
		row.add_theme_constant_override("separation",10)
		recipes.add_child(row)
		row.add_child(Shell.picture(Items.icon(item),32))
		var lines:=VBoxContainer.new()
		lines.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		row.add_child(lines)
		var title:Label=app.label("%s · 已交 %d／%d"%[recipe.name,int(delivered.get(item,0)),2 if item=="soup" else 1],16)
		title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		lines.add_child(title)
		var materials:PackedStringArray=[]
		for ingredient in recipe.ingredients:
			materials.append("%s %d／%d"%[World.NAMES[ingredient],int(held.get(ingredient,0)),int(recipe.ingredients[ingredient])])
		var detail:Label=app.label("、".join(materials)+" → 一次做出 %d 份 · 背包已有 %d 份"%[
			int(recipe.yield),int(held.get(item,0))],14)
		detail.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		lines.add_child(detail)
	var hint:Label=app.label("在小石灶選料理，完成後記得領取。帶回公告板按 %s 交野餐材料。"%app.binding_label("interact"),15)
	hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	recipes.add_child(hint)

static func add_first_crop(app,body:VBoxContainer) -> void:
	var heading:Label=app.label("第一件事・種一株蘿蔔",18)
	heading.name="FirstCropHeading"
	body.add_child(heading)
	var move:Label=app.label("用 %s 走到小栗種子攤東北邊，木樁圍起的那塊田是她留給你的。背包已經有蘿蔔種子。"%app.movement_hint(),15)
	move.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	body.add_child(move)
	var instructions:=VBoxContainer.new()
	instructions.name="FirstCropInstructions"
	body.add_child(instructions)
	for entry in [
		["hoe","鋤頭","用滑鼠左鍵點田裡的草地，翻出一格土。田被占用時，附近任一塊空草地都可以。"],
		["seed","播種","點翻好的土。若選到其他種子，按 %s 換回蘿蔔。"%app.binding_label("seeds")],
		["water","澆水","點種好的那一格。"],
		["harvest","採收","等蘿蔔長熟，再點同一格。"],
	]:
		var instruction:Label=app.label("%s  %s · %s"%[app.binding_label(entry[0]),entry[1],entry[2]],15)
		instruction.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		instructions.add_child(instruction)
	var next:Label=app.label("採收後，左上角會指引你到出貨箱。之後留兩份蘿蔔、兩份小麥做野餐，也留一包種子測試灑水器。",15)
	next.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	body.add_child(next)
