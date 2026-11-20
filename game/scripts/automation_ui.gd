extends RefCounted

const World = preload("res://scripts/world.gd")
const Tasks = preload("res://scripts/life_ui_tasks.gd")
const ItemArt = preload("res://scripts/inventory_item_art.gd")
const PixelTheme = preload("res://scripts/inventory_pixel_theme.gd")
const SourcePicker = preload("res://scripts/material_source_ui.gd")
const ProcessingUI=preload("res://scripts/processing_queue_ui.gd")
## Player-facing "what is this for" guidance for every World.CRAFT recipe.
## kind: place (standard 1:1 kit), alternate_place (fallback kit), collection (consumed by
## World.BUILD[build] as decoration), part (ingredient of other CRAFT recipes),
## key_tool (enables or upgrades a world action), tool (portable equipment, see PORTABLE_TOOLS).
## tab is the BuildFolio tab that lists `build`. Tool text takes binding labels for
## `keys` so rebinding stays accurate. test_workbench_guidance.gd checks every
## field against the real recipe, build and device data.
const SHELL_BOTTLE_USE:="在工作台挑選排列。做好後，走近自己的木桌或貝殼圓桌互動，就能把成品擺上桌。"
const GUIDE := {
	World.INDUSTRY.TABLE_VASE:{"kind":"table_display","text":"做好後擺在自己的木桌或貝殼圓桌上。換一枝新花，原來的花會放回背包。"},
	World.INDUSTRY.TEA_SET:{"kind":"table_display","text":"擺上木桌、圓角木桌或低腳竹茶桌。靠近茶具即可選擇斟茶或奉茶表情。"},
	"shell_bottle_scallop":{"kind":"table_display","text":SHELL_BOTTLE_USE},
	"shell_bottle_conch":{"kind":"table_display","text":SHELL_BOTTLE_USE},
	"shell_bottle_tide":{"kind":"table_display","text":SHELL_BOTTLE_USE},
	"woodwork_parts":{"kind":"part","used_in_build":["loom","assembly_table","seed_maker","large_sprinkler","mill"],"feeds":[],"text":"用木板與硬木組裝的接榫，可組裝織布機、裝配桌、種子機、大型灑水器及麵粉磨坊。"},
	"egg_basket":{"kind":"animal_facility","text":"帶著收集籃到渡口找糯米雞，在照料面板裝設。籃子可放六顆雞蛋，裝滿後先領取再餵食。"},
	"supply_box_kit":{"kind":"place","build":"supply_box","tab":"生活","text":"探索六級或完成波波的休息站事件解鎖。到建造目錄「生活」放置，清空後可拆回背包。"},
	"glass":{"kind":"collection","build":"greenhouse_roof","tab":"基礎",
		"text":"晶砂在望安星砂海岸或金瓜石第五層。建造目錄「基礎」用玻璃 2、銅接頭 1 搭溫室玻璃棚。"},
	"salt_wheel_kit": {"kind": "salt_facility",
		"text": "在北門親手收過一次鹽後可製作。到自己照顧的鹽田操作水車座，裝上水車後會自動引入海水。"},
	"salt_rake_kit": {"kind": "salt_facility",
		"text": "收過水車引水的鹽後可製作。到自己照顧的鹽田操作收鹽台座，裝上後可設定收鹽箱與存量上限。"},
	"gold_sample": {"kind": "collection", "build": "ore_display", "tab": "家具",
		"text": "完成波波三段故事後，到建造目錄「家具」用木材 4＋樣本 1 放礦樣展示架。"},
	"reinforced_pick": {"kind": "key_tool", "action": "mine_copper",
		"text": "放在背包即可。到渡口運入礦料點互動採銅礦，每次 2 個；每人只能製作一把。"},
	"copper_pick": {"kind": "key_tool", "action": "mine_copper",
		"text": "用原本的強化石鎬升級。放進背包即可使用，一下敲開地表岩石，礦道同一礦點提前 3 秒可再採。"},
	"iron_pick": {"kind": "key_tool", "action": "mine_copper",
		"text": "用銅鎬升級。帶在身上即可使用。地表岩石一擊敲開，礦道等 8 秒，每鎬約省兩成體力。"},
	"precision_pick": {"kind": "key_tool", "action": "mine_copper",
		"text": "用鐵鎬和脈石英升級。帶在身上即可使用。地表岩石一擊敲開，礦道等 7 秒，每鎬約省三成半體力。"},
	"copper_axe": {"kind": "key_tool", "action": "axe", "text": "放在背包就會用銅斧。一般樹木砍兩下就倒，材料掉在地上，走近便能撿取。"},
	"iron_axe": {"kind": "key_tool", "action": "axe", "text": "用銅斧加鐵錠、硬木升級。帶在身上即可使用，砍一下就能伐倒樹木。"},
	"precision_axe": {"kind": "key_tool", "action": "axe", "text": "一擊伐木。砍島民種下的成熟樹木時多掉一塊硬木。帶在身上即可使用。"},
	"copper_hoe": {"kind": "key_tool", "action": "hoe", "text": "放在背包即可使用。在家園可橫耕一排 3 格，直接點擊仍只耕一格。"},
	"iron_hoe": {"kind": "key_tool", "action": "hoe", "text": "用銅鋤升級。在家園可一次耕十字形 5 格，直接點擊仍只耕一格。"},
	"precision_hoe": {"kind": "key_tool", "action": "hoe", "text": "用鐵鋤與脈石英升級。在家園可耕 3×3 格，直接點擊仍只耕一格。"},
	"copper_can": {"kind": "key_tool", "action": "water", "text": "放在背包即可使用。在家園可一次澆一排 3 格作物，直接點擊維持單格。"},
	"iron_can": {"kind": "key_tool", "action": "water", "text": "用銅澆水壺升級。在家園可一次澆十字形 5 格作物，直接點擊維持單格。"},
	"precision_can": {"kind": "key_tool", "action": "water", "text": "用鐵澆水壺與脈石英升級。在家園可一次澆 3×3 格作物，直接點擊維持單格。"},
	"copper_rod": {"kind": "key_tool", "action": "fish_start", "text": "帶在身上即可使用。平常等 2.6 秒咬鉤，標準釣法的亮帶也變寬。"},
	"iron_rod": {"kind": "key_tool", "action": "fish_start", "text": "由銅釣竿升級。平常等 2.2 秒咬鉤，標準釣法的亮帶再加寬。"},
	"precision_rod": {"kind": "key_tool", "action": "fish_start", "text": "以鐵釣竿與脈石英升級。平常等 1.8 秒咬鉤，標準釣法的亮帶最寬。"},
	"copper_seed_pouch": {"kind": "key_tool", "action": "seed", "text": "帶著就能在家園播橫排 3 格自己的空田。每格一粒種子，普通點擊只播單格。"},
	"iron_seed_pouch": {"kind": "key_tool", "action": "seed", "text": "用銅扣撒種袋升級。在家園可播十字形 5 格，每格一粒種子。"},
	"precision_seed_pouch": {"kind": "key_tool", "action": "seed", "text": "用鐵扣撒種袋與脈石英升級。在家園可播 3×3 格，種子不足時先播中央附近。"},
	"copper_sickle": {"kind": "key_tool", "action": "harvest", "text": "帶在身上即可使用。在家園可一次採收橫排 3 格，普通點擊只收一格。"},
	"iron_sickle": {"kind": "key_tool", "action": "harvest", "text": "由銅採收鐮升級。在家園可收十字形 5 格，跳過未成熟或無權採收的田。"},
	"precision_sickle": {"kind": "key_tool", "action": "harvest", "text": "用鐵採收鐮與脈石英升級。家園可採收 3×3 格，保留作物原有再收成次數。"},
	"mine_drill_kit": {"kind": "place", "build": "mine_drill", "tab": "生活",
		"text": "開通第五層後可製作。建造目錄「生活」放在礦層指定礦點旁，裝木炭自動採礦。"},
	"waterworks_kit": {"kind": "place", "build": "waterworks", "tab": "生活",
		"text": "第三層抽水工程完成後可製作。建造目錄「生活」放置並接水管，把銅礦與木材加工成銅接頭。"},
	"copper_joint": {"kind": "part", "used_in_build": ["greenhouse_roof", "festival_memorial_bell"], "feeds": ["mine_drill_kit", "waterworks_kit", "sprinkler_kit", "pipe_kit", "pump_kit", "forester_kit", "conveyor_kit", "tiller", "seeder", "harvester", "salt_wheel_kit", "salt_rake_kit", "diversion_gate_kit", "water_tower_kit"],
		"text": "玻璃棚、灑水器與鹽田機具的零件。"},
	"sprinkler_kit": {"kind": "alternate_place", "build": "sprinkler", "tab": "生活",
		"text": "在家園工坊「生活」放置。每天澆一次上下左右的自家作物，牆與關閉的門會擋水。可手動補水或接水管。"},
	"pipe_kit": {"kind": "place", "build": "water_pipe", "tab": "生活",
		"text": "建造目錄「生活」鋪設，連接自己的河水泵、儲水桶、灑水器與水力加工台。"},
	"tank_kit": {"kind": "place", "build": "water_tank", "tab": "生活",
		"text": "建造目錄「生活」放置，可存 48 份水；接水管後供水給自己的灑水器。"},
	"pump_kit": {"kind": "place", "build": "water_pump", "tab": "生活",
		"text": "建造目錄「生活」放在河水兩格內的陸地，啟用後把河水送進接通的儲水桶。"},
	"sawmill_kit": {"kind": "place", "build": "sawmill", "tab": "生活",
		"text": "建造目錄「生活」放置，互動把木材 4 加工成木板 2，完成後領取。"},
	"kiln_kit": {"kind": "place", "build": "charcoal_kiln", "tab": "生活",
		"text": "建造目錄「生活」放置，互動把木材 4 燒成木炭 2，完成後領取。"},
	"forester_kit": {"kind": "place", "build": "forester", "tab": "生活",
		"text": "建造目錄「生活」放置，補入木炭與樹苗，照顧四周地塊並產出木材、纖維、樹脂。"},
	"conveyor_kit": {"kind": "place", "build": "conveyor", "tab": "生活",
		"text": "建造目錄「生活」鋪設，設定方向與物品，在自己的設備和私人箱之間運送。"},
	# 第 40 章：蘭陽回訪「旱日分流」完成後解鎖（INDUSTRY.GATE_LOCKED）。
	"diversion_gate_kit": {"kind": "place", "build": "diversion_gate", "tab": "生活",
		"text": "建造目錄「生活」接在自己的水管中間，靠近互動切換全開、餘水或關閉，決定哪一段灑水器先拿到桶水。"},
	# 第 40 章：和分流閘同一個解鎖（INDUSTRY.TOWER_LOCKED）。
	"water_tower_kit": {"kind": "place", "build": "water_tower", "tab": "生活",
		"text": "建造目錄「生活」接上自己的水管，存 96 份水；桶有剩水自動補入，閘門後缺水時由它供水。"},
	"tiller": {"kind": "tool", "keys": ["till_area"],
		"text": "%s 裝備 · 一次最多耕 9 格 · 每次 1 木炭"},
	"seeder": {"kind": "tool", "keys": ["seed_area", "seeds"],
		"text": "%s 裝備 · %s 換種子 · 每格 1 種子 / 每次 1 木炭"},
	"harvester": {"kind": "tool", "keys": ["harvest_area"],
		"text": "%s 裝備 · 收割自家成熟作物 · 每次 1 木炭"},
}
## Neutral fallback: true for any recipe, never promises placement or equipment.
const USE_FALLBACK := "製作後收進背包。"
const PORTABLE_TOOLS := {
	"tiller": ["till_area", "拿起耕田機"],
	"seeder": ["seed_area", "拿起播種機"],
	"harvester": ["harvest_area", "拿起收割機"],
}

var modal: Control
var update_view: Callable

func refresh(app) -> void:
	if not is_instance_valid(modal) or app.modal != modal:
		update_view = Callable()
		modal = null
		return
	if update_view.is_valid():
		var snapshot: Dictionary = app.session.snapshot
		update_view.call(snapshot, snapshot.get("players", {}).get(app.session.own_id, {}))

func open(app, title: String) -> VBoxContainer:
	var body: VBoxContainer = app._open_modal(title)
	modal = app.modal
	modal.theme = PixelTheme.make(modal.theme if modal.theme else app.theme())
	modal.add_theme_stylebox_override("panel", PixelTheme.frame_style())
	modal.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	update_view = Callable()
	return body

func workbench(app, cell: Vector2i,initial_recipe:String="",return_trail:Array[String]=[]) -> void:
	# C08: either end of a wide workbench opens the same station; every later action (craft, sourced
	# craft, workshop upgrade, ProcessingUI return) uses the anchor. Legacy 1x1 benches resolve to themselves.
	cell = World.station_anchor(app.session.snapshot.get("objects", {}), cell)
	var station:Dictionary=app.session.snapshot.get("objects",{}).get(World.key(cell),{})
	var body := open(app, World.BUILD.bench.name if World.INDUSTRY.is_wide_bench(station) else "工作台")
	modal.set_meta("life_modal_layout", "automation_workbench")
	if is_instance_valid(app.modal_feedback):
		app.modal_feedback.text="手把 X 前往製作 · B 返回"
	var layout := HBoxContainer.new()
	layout.add_theme_constant_override("separation", 12)
	body.add_child(layout)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(365, 312)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	layout.add_child(scroll)
	var choices := GridContainer.new()
	choices.columns = 3
	choices.add_theme_constant_override("h_separation", 6)
	choices.add_theme_constant_override("v_separation", 6)
	scroll.add_child(choices)
	var ids := World.CRAFT.keys()
	var selected := {"id": ids[0]}
	var source_choice:={"id":""}
	var entries: Dictionary = {}
	var recipe_history:Array[String]=return_trail.duplicate()
	var choose_recipe:=func(recipe_id:String,clear_history:bool):
		if not World.CRAFT.has(recipe_id):return
		if clear_history:recipe_history.clear()
		selected.id=recipe_id
		source_choice.id=""
		for key in entries:entries[key].set_pressed_no_signal(key==recipe_id)
		refresh(app)
		reveal_recipe(scroll,entries[recipe_id])
	for id in ids:
		var recipe_name:String=World.CRAFT[id].name
		var caption:=recipe_name.get_slice("・",1) if id in World.INDUSTRY.SHELL_BOTTLES else recipe_name
		var button: Button = app.button(caption, func():
			choose_recipe.call(id,true)
		)
		button.name="WorkbenchRecipe_"+id
		button.tooltip_text=recipe_name
		button.icon = ItemArt.icon(id)
		button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		button.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		button.custom_minimum_size = Vector2(112, 94)
		button.add_theme_constant_override("icon_max_width", 64)
		button.expand_icon = true
		button.theme_type_variation = &"ItemSlot"
		button.toggle_mode = true
		choices.add_child(button)
		entries[id] = button
	var capture_craft: String = initial_recipe if not initial_recipe.is_empty() else app.arg_value("capture-craft", "")
	if World.CRAFT.has(capture_craft):
		selected.id = capture_craft
	entries[selected.id].set_pressed_no_signal(true)
	if not capture_craft.is_empty():
		reveal_recipe(scroll, entries[selected.id])
	var details := Tasks.card(layout)
	details.add_theme_constant_override("separation", 5)
	details.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	details.add_child(header)
	var preview := TextureRect.new()
	preview.custom_minimum_size = Vector2(48, 48)
	preview.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	header.add_child(preview)
	var title: Label = app.label("", 22)
	var use: Label = app.label("", 16)
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	use.name = "RecipeUse"
	use.custom_minimum_size.x = 235
	header.add_child(title)
	details.add_child(use)
	var amounts := GridContainer.new()
	amounts.columns = 2
	amounts.add_theme_constant_override("h_separation", 8)
	details.add_child(amounts)
	var materials: Dictionary = {}
	for id in ids:
		for item in recipe_ingredients(id):
			if materials.has(item):continue
			var card := Tasks.card(amounts)
			# Compact material rows keep six-ingredient recipes and actions in view.
			var material_style := StyleBoxEmpty.new()
			material_style.content_margin_top = 2
			material_style.content_margin_bottom = 2
			card.get_parent().add_theme_stylebox_override("panel", material_style)
			var row := HBoxContainer.new()
			card.add_child(row)
			var hint:=material_hint(item)
			if hint.is_empty():Tasks.add_icon(row, ItemArt.icon(item), 32)
			else:
				var help:Button=app.button("",func():
					source_choice.id="" if source_choice.id==item else item
					refresh(app))
				help.name="MaterialHint_"+item
				help.icon=ItemArt.icon(item)
				help.expand_icon=true
				help.custom_minimum_size=Vector2(32,32)
				help.add_theme_constant_override("icon_max_width",32)
				help.theme_type_variation=&"ItemSlot"
				help.tooltip_text="查看%s來源；再點一次回到成品用途。"%World.NAMES.get(item,item)
				row.add_child(help)
			var value: Label = app.label("", 15)
			value.name = "MaterialAmount"
			value.custom_minimum_size.x = 110
			value.autowrap_mode = TextServer.AUTOWRAP_OFF
			row.add_child(value)
			materials[item] = [card.get_parent(), value]
	# Material source: defaults to backpack only on every open (see material_source_ui.gd).
	var picker = SourcePicker.create(app, cell, "bench", "craft", false)
	details.add_child(picker)
	var controller := WorkbenchController.new()
	controller.name = "WorkbenchController"
	controller.app = app
	controller.cell = cell
	controller.picker = picker
	controller.status = app.modal_feedback if is_instance_valid(app.modal_feedback) else null
	controller.on_change = func(): refresh(app)
	modal.add_child(controller)
	picker.state_changed.connect(func(): refresh(app))
	var craft: Button = app.button("製作", func(): controller.submit(selected.id))
	craft.name = "CraftRecipe"
	var actions := HBoxContainer.new()
	details.add_child(actions)
	craft.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(craft)
	var equip: Button = app.button("", func():
		app._close_modal()
		app._select_tool(PORTABLE_TOOLS[selected.id][0])
	)
	actions.add_child(equip)
	var back:Button=app.button("←",func():
		if controller.busy() or recipe_history.is_empty():return
		choose_recipe.call(recipe_history.pop_back(),false))
	back.name="RecipeBack"
	back.custom_minimum_size=Vector2(36,36)
	actions.add_child(back)
	var source_recipe:Button=app.button("↗",func():
		var target:String=source_choice.id
		if controller.busy() or not recipe_ingredients(selected.id).has(target):return
		var route:=material_route(app.session.snapshot,app.session.own_id,target)
		if route.get("action","")=="device":
			var original:String=selected.id
			var trail:Array[String]=recipe_history.duplicate()
			ProcessingUI.open(app,route.cell,func():workbench(app,cell,original,trail),str(World.CRAFT[original].name))
			return
		if not World.CRAFT.has(target):target=str(route.get("recipe",""))
		if not World.CRAFT.has(target) or target in recipe_history:return
		recipe_history.append(selected.id)
		choose_recipe.call(target,false))
	source_recipe.name="MaterialRecipe"
	source_recipe.custom_minimum_size=Vector2(36,36)
	actions.add_child(source_recipe)
	details.add_child(app.button("家園建造  %s"%app.binding_label("build_menu"), app._build_menu))
	var upgrade:Button=app.button("升級工坊",func():app.session.perform("upgrade_workshop",cell))
	upgrade.name="UpgradeWorkshop"
	details.add_child(upgrade)
	update_view = func(snapshot: Dictionary, person: Dictionary):
		var id: String = selected.id
		craft.focus_neighbor_left=craft.get_path_to(entries[id])
		var needs := recipe_ingredients(id)
		var bag: Dictionary = person.get("inventory", {})
		for item in materials:
			var required: int = needs.get(item, 0)
			var held: int = bag.get(item, 0)
			materials[item][0].visible = required > 0
			# Actual backpack count only; any box share is shown by the picker breakdown.
			materials[item][1].text = "%s %d／%d" % [World.NAMES.get(item, item), held, required]
		var bench_present: bool = snapshot.get("objects", {}).get(World.key(cell), {}).get("type") == "bench"
		picker.set_locked("" if bench_present else "工作台已移除")
		if picker.recipe_id != id:
			picker.set_recipe(id, World.CRAFT[id])
		else:
			picker.refresh()
		# The source breakdown already shows every debit when a box is selected.
		amounts.visible = not picker.uses_box()
		var enough: bool = not needs.is_empty() and picker.plan_ok()
		var already_crafted: bool = person.get("crafted_reinforced_pick", false) or owns_pick(person)
		title.text = "%s　持有 %d" % [World.CRAFT[id].name, int(bag.get(id, 0))]
		preview.texture = ItemArt.icon(id)
		var material:String=source_choice.id
		if not needs.has(material):material="";source_choice.id=""
		use.text=recipe_use(id,app) if material.is_empty() else "%s來源：%s"%[World.NAMES.get(material,material),material_hint(material)]
		var route:=material_route(snapshot,app.session.own_id,material)
		if route.get("action","")=="recipe":use.text+=" 此區尚無自己的%s，可查看設備配方。"%World.BUILD[route.station].name
		elif route.get("action","")=="far":use.text+=" 你的%s在%s約%d格，走近後互動。"%[World.BUILD[route.station].name,route.direction,ceili(float(route.distance))]
		back.visible=not recipe_history.is_empty()
		back.disabled=controller.busy()
		back.tooltip_text="返回「%s」配方"%World.CRAFT[recipe_history.back()].name if back.visible else ""
		var target_recipe:String=material if World.CRAFT.has(material) else str(route.get("recipe",""))
		source_recipe.visible=route.get("action","")=="device" or (World.CRAFT.has(target_recipe) and target_recipe!=id and target_recipe not in recipe_history)
		source_recipe.disabled=controller.busy()
		source_recipe.tooltip_text=""
		if route.get("action","")=="device":source_recipe.tooltip_text="開啟附近的%s"%World.BUILD[route.station].name
		elif source_recipe.visible:source_recipe.tooltip_text="查看「%s」配方"%World.CRAFT[target_recipe].name
		var bench: Dictionary = snapshot.get("objects", {}).get(World.key(cell), {})
		var available: bool = bench.get("type") == "bench"
		upgrade.visible=World.crafting_level(person)>=World.WORKSHOP_LEVEL and not person.get("workshop_upgraded",false)
		upgrade.disabled=not available or controller.busy()
		equip.visible = PORTABLE_TOOLS.has(id) and int(bag.get(id, 0)) > 0
		equip.text = "%s  %s" % [PORTABLE_TOOLS[id][1],app.binding_label(PORTABLE_TOOLS[id][0])] if equip.visible else ""
		var locked: bool = id == "waterworks_kit" and int(snapshot.get("mine_depths",{}).get("unlocked",1)) < 4
		locked = locked or (id == "mine_drill_kit" and int(snapshot.get("mine_depths",{}).get("unlocked",1)) < 5)
		var kitchen_locked: bool = id in World.KITCHEN_GATED and not bool(snapshot.get("public_kitchen",{}).get("opened",false))
		var supply_locked:bool=id=="supply_box_kit" and not World.supply_box_unlocked(person,snapshot.get("resident_goals",{}).get("bobo",{}).get("3",{}).get("state")=="done")
		locked = locked or kitchen_locked or supply_locked
		# 第 40 章分流閘：蘭陽回訪的旱日分流完成後才解鎖；說明列寫出原因。
		# 水塔（TOWER_KIT）用同一個解鎖，只換說明文字。
		var gate_locked: bool = id in [World.INDUSTRY.GATE_KIT, World.INDUSTRY.TOWER_KIT] and not World.LANYANG_REVISIT.tech_unlocked(snapshot)
		var lock_message: String = World.INDUSTRY.TOWER_LOCKED if id == World.INDUSTRY.TOWER_KIT else World.INDUSTRY.GATE_LOCKED
		locked = locked or gate_locked
		if gate_locked:
			use.text = lock_message
		craft.tooltip_text = lock_message if gate_locked else ""
		var busy: bool = controller.busy()
		craft.disabled = busy or not available or not picker.can_submit() or locked or (id == "reinforced_pick" and already_crafted)
		if busy:
			craft.text = "等待工作台回應……"
		elif not available:
			craft.text = "工作台已移除"
		elif kitchen_locked:
			craft.text = "公共廚房開張後解鎖"
		elif supply_locked:
			craft.text = "探索六級或完成波波事件"
		elif gate_locked:
			craft.text = "完成旱日分流後解鎖"
		elif locked:
			craft.text = "先開通第五層" if id == "mine_drill_kit" else "先完成第三層抽水工程"
		elif id == "reinforced_pick" and already_crafted:
			craft.text = "已製作過強化石鎬"
		elif not enough:
			craft.text = "材料不足"
		elif not picker.can_submit():
			craft.text = picker.block_reason()
		else:
			craft.text = "製作 %d 件%s" % [World.CRAFT[id].yield, " · 用箱子補足" if picker.uses_box() else ""]
	refresh(app)

func assembly(app,cell:Vector2i) -> void:
	var body:=open(app,"裝配桌")
	modal.set_meta("life_modal_layout","automation_device")
	Tasks.line(app,body,"裝成組件後，可在家園工坊選對應設備放置。",16)
	var layout:=GridContainer.new()
	layout.columns=2
	layout.add_theme_constant_override("h_separation",8)
	layout.add_theme_constant_override("v_separation",8)
	body.add_child(layout)
	var bindings:Dictionary={}
	for kind:String in World.INDUSTRY.assembly_items():
		var kit:String=World.INDUSTRY.assembly_items()[kind]
		var card:=Tasks.card(layout)
		(card.get_parent() as Control).size_flags_horizontal=Control.SIZE_EXPAND_FILL
		Tasks.add_icon(card,ItemArt.icon(kit),32)
		Tasks.line(app,card,World.BUILD[kind].name,18)
		var inputs:=World.assembly_recipe(kind)
		var amounts:Dictionary={}
		for item in inputs:
			var row:=HBoxContainer.new()
			card.add_child(row)
			Tasks.add_icon(row,ItemArt.icon(item),20)
			var count:Label=app.label("",14)
			row.add_child(count)
			amounts[item]=count
		var spacer:=Control.new()
		spacer.size_flags_vertical=Control.SIZE_EXPAND_FILL
		card.add_child(spacer)
		var make:Button=app.button("裝配",func():app.session.perform("assemble",cell,kind))
		make.name="Assemble_"+kind
		card.add_child(make)
		bindings[kind]={"inputs":inputs,"amounts":amounts,"make":make}
	update_view=func(snapshot:Dictionary,person:Dictionary):
		var table:Dictionary=snapshot.get("objects",{}).get(World.key(cell),{})
		var own:bool=table.get("type")==World.INDUSTRY.ASSEMBLY_TABLE and table.get("owner")==app.session.own_id
		var bag:Dictionary=person.get("inventory",{})
		for kind in bindings:
			var entry:Dictionary=bindings[kind]
			var enough:=true
			for item in entry.inputs:
				var need:=int(entry.inputs[item])
				var held:=int(bag.get(item,0))
				entry.amounts[item].text="%s %d／%d"%[World.NAMES[item],held,need]
				enough=enough and held>=need
			var level:=World.sprinkler_level(kind)
			var ready:=World.farming_level(person)>=level
			entry.make.disabled=not (own and enough and ready)
			entry.make.text="農耕 %d 級"%level if not ready else ("裝配" if enough else "材料不足")
	refresh(app)

func animal_collector(app,cell:Vector2i) -> void:
	var body:=open(app,"動物自動收集器")
	modal.set_meta("life_modal_layout","automation_device")
	var card:=Tasks.card(body)
	Tasks.add_icon(card,ItemArt.icon(World.INDUSTRY.ANIMAL_COLLECTOR_KIT),48)
	var summary:Label=app.label("",18)
	card.add_child(summary)
	var gauge:=ProgressBar.new()
	gauge.max_value=World.AnimalCollector.CAPACITY
	gauge.show_percentage=false
	gauge.custom_minimum_size.y=18
	card.add_child(gauge)
	var products:=HFlowContainer.new()
	products.add_theme_constant_override("h_separation",14)
	products.add_theme_constant_override("v_separation",6)
	card.add_child(products)
	var product_rows:Dictionary={}
	for item:String in World.AnimalCollector.PEN_ITEMS:
		var row:=HBoxContainer.new()
		row.add_theme_constant_override("separation",5)
		Tasks.add_icon(row,ItemArt.icon(item),32)
		var item_label:Label=app.label("",15)
		item_label.autowrap_mode=TextServer.AUTOWRAP_OFF
		row.add_child(item_label)
		products.add_child(row)
		product_rows[item]={"row":row,"label":item_label}
	var hint:Label=app.label("",15)
	card.add_child(hint)
	var bind_row:=HFlowContainer.new()
	bind_row.add_theme_constant_override("h_separation",8)
	bind_row.add_theme_constant_override("v_separation",8)
	card.add_child(bind_row)
	var binds:Dictionary={}
	for id:String in World.AnimalCollector.SPECIES:
		if not World.AnimalCollector.in_range(cell,id):continue
		var bind:Button=app.button(World.AnimalCollector.name_for(id),func():app.session.perform("collector_bind",cell,id))
		bind.name="CollectorBind_"+id
		bind_row.add_child(bind)
		binds[id]=bind
	# C24: whole-enclosure binding. Shown only while this cell is inside a valid pen.
	var pen_bind:Button=app.button(World.AnimalCollector.name_for(World.AnimalCollector.PEN),func():app.session.perform("collector_bind",cell,World.AnimalCollector.PEN))
	pen_bind.name="CollectorBind_pen"
	pen_bind.visible=false
	bind_row.add_child(pen_bind)
	var actions:=HBoxContainer.new()
	actions.add_theme_constant_override("separation",8)
	card.add_child(actions)
	var take:Button=app.button("領取產物",func():app.session.perform("collector_collect",cell))
	take.name="CollectorTake"
	actions.add_child(take)
	var unbind:Button=app.button("取回收集籃",func():app.session.perform("collector_unbind",cell))
	unbind.name="CollectorUnbind"
	actions.add_child(unbind)
	update_view=func(snapshot:Dictionary,person:Dictionary):
		var objects:Dictionary=snapshot.get("objects",{})
		var key:=World.key(cell)
		var obj:Dictionary=objects.get(key,{})
		var own:bool=obj.get("type")==World.INDUSTRY.ANIMAL_COLLECTOR and obj.get("owner")==app.session.own_id
		var species:String=obj.get("collector_animal","")
		var count:=int(obj.get("collector_count",0))
		var basket:=int(person.get("inventory",{}).get("egg_basket",0))
		var pen_mode:bool=species==World.AnimalCollector.PEN
		var penned:Array[String]=World.AnimalCollector.pen_species(objects,cell)
		if species.is_empty():summary.text="尚未安裝收集籃"
		elif pen_mode:summary.text="%s · %d／%d"%[World.AnimalCollector.name_for(species),count,World.AnimalCollector.CAPACITY]
		else:summary.text="%s · %s %d／%d"%[World.AnimalCollector.name_for(species),World.NAMES[World.AnimalCollector.item_for(species)],count,World.AnimalCollector.CAPACITY]
		if int(obj.get("collector_count_quality",0))>0:summary.text+=" · 其中優良 %d"%int(obj.collector_count_quality)
		gauge.value=count
		var stored:Dictionary=obj.get("collector_items",{})
		products.visible=pen_mode and not stored.is_empty()
		for item:String in product_rows:
			var amount:=int(stored.get(item,0))
			var entry:Dictionary=product_rows[item]
			entry.row.visible=amount>0
			entry.label.text="%s ×%d"%[World.NAMES[item],amount] if amount>0 else ""
		if species.is_empty():hint.text="在工作台製作收集籃，再選附近的一隻動物，或放進圍好的圈舍綁定整座圈舍。"
		elif count>=World.AnimalCollector.CAPACITY:hint.text="收集籃已滿，領取後會繼續收集。"
		elif pen_mode and penned.is_empty():hint.text="圈舍有缺口或沒有木門，補好前產物會留在動物身邊。"
		elif pen_mode:
			var served:PackedStringArray=[]
			for id:String in penned:served.append(World.AnimalCollector.name_for(id))
			hint.text="自動接取圈舍內的%s。動物仍需要餵食。"%"、".join(served)
		else:hint.text="會自動接取動物已產出的物品。動物仍需要餵食。"
		if not own:hint.text="只有收集器的擁有者可以操作。"
		elif binds.is_empty() and penned.is_empty() and not pen_mode:hint.text="請搬到對應動物四格內，或放進圍好的圈舍。"
		for id in binds:
			binds[id].disabled=not own or id==species or count>0 or (species.is_empty() and basket==0) or World.AnimalCollector.bound_elsewhere(objects,id,key) or World.AnimalCollector.pen_served(objects,id,key)
		pen_bind.visible=not penned.is_empty() or pen_mode
		var pen_taken:=false
		for id:String in penned:
			if World.AnimalCollector.bound_elsewhere(objects,id,key) or World.AnimalCollector.pen_served(objects,id,key):pen_taken=true
		pen_bind.disabled=not own or pen_mode or penned.is_empty() or count>0 or (species.is_empty() and basket==0) or pen_taken
		take.disabled=not own or count==0
		unbind.disabled=not own or species.is_empty() or count>0
	refresh(app)

func focus_sprinkler_action(app) -> bool:
	if not is_instance_valid(modal) or app.modal!=modal or not modal.has_meta("sprinkler_controls"):return false
	refresh(app)
	for id in ["SprinklerRefill","SprinklerToggle"]:
		var action:=modal.find_child(id,true,false) as Button
		if not is_instance_valid(action) or action.disabled or not action.is_visible_in_tree():continue
		action.grab_focus()
		var scroll:=modal.find_child("ModalScroll",true,false) as ScrollContainer
		if scroll!=null:scroll.ensure_control_visible(action)
		break
	return true

func sprinkler(app, cell: Vector2i) -> void:
	var device:Dictionary=app.session.snapshot.get("objects",{}).get(World.key(cell),{})
	var kind:String=device.get("type","sprinkler")
	var capacity:int=World.INDUSTRY.SPRINKLER_CAPACITIES.get(kind,World.SPRINKLER_CAPACITY)
	var coverage:String={"large_sprinkler":"周圍二十四格","medium_sprinkler":"周圍八格"}.get(kind,"上下左右相鄰格")
	var body := open(app, World.BUILD[kind].name)
	modal.set_meta("life_modal_layout", "automation_device")
	modal.set_meta("sprinkler_controls",true)
	var details := Tasks.card(body)
	Tasks.add_icon(details, ItemArt.icon("large_sprinkler" if kind=="large_sprinkler" else "sprinkler_kit"), 64)
	var water: Label = app.label("", 22)
	var state: Label = app.label("", 16)
	details.add_child(water)
	var gauge := ProgressBar.new()
	gauge.max_value = capacity
	gauge.show_percentage = false
	gauge.custom_minimum_size.y = 18
	details.add_child(gauge)
	details.add_child(state)
	var supply: Label = app.label("", 15)
	supply.name="SprinklerSupply"
	supply.custom_minimum_size.x = 280
	details.add_child(supply)
	if device.get("sprinkler_daily",false):
		Tasks.line(app, details, "每天澆一次%s內自己的作物，水不會穿過牆壁。" % coverage, 16)
	else:
		Tasks.line(app, details, "每 %d 秒檢查%s內，同一位主人種植的作物。" % [World.SPRINKLER_INTERVAL,coverage], 16)
	var actions := HBoxContainer.new()
	details.add_child(actions)
	var refill: Button = app.button("補滿水", func(): app.session.perform("refill_sprinkler", cell))
	var toggle: Button = app.button("啟用", func(): app.session.perform("toggle_sprinkler", cell))
	refill.name="SprinklerRefill"
	toggle.name="SprinklerToggle"
	refill.tooltip_text="手把 X 選取 · A 確認"
	actions.add_child(refill)
	actions.add_child(toggle)
	update_view = func(snapshot: Dictionary, _person: Dictionary):
		var obj: Dictionary = snapshot.get("objects", {}).get(World.key(cell), {})
		var amount: int = obj.get("water", 0)
		var active: bool = obj.get("enabled", false)
		var present: bool = obj.get("type") == kind
		var owner: bool = present and obj.get("owner") == app.session.own_id
		water.text = "水量 %d／%d" % [amount, capacity]
		gauge.value = amount
		state.text = ("運作中" if active else "已停止") if present else "灑水器已移除"
		if present and active and obj.get("sprinkler_daily",false) and float(obj.get("next_water",0))>float(snapshot.get("time",0)):
			state.text = "今天已澆水，明天再灑"
		if present and not owner:
			state.text += " · 由擁有者操作"
		var network: Dictionary = World.INDUSTRY.network_info(snapshot, World.key(cell))
		var tanks: int = network.get("connected_tanks", 0)
		supply.visible = present
		supply.text = "接通 %d 桶 · 管網水量 %d／%d" % [tanks, network.water, network.capacity] if tanks > 0 else "未接通儲水桶，需手動補水。"
		# 第 40 章水塔：同一條水管上有水塔時多一行座數與存水。
		var towers: int = int(network.get("towers", 0))
		if towers > 0:
			var tower_text:="水塔 %d 座 · 存水 %d／%d" % [towers, int(network.get("tower_water", 0)), int(network.get("tower_capacity", 0))]
			supply.text=tower_text if tanks==0 else supply.text+"\n"+tower_text
		var note:=World.INDUSTRY.supply_note(network)
		if not note.is_empty():supply.text+="\n"+note
		if owner and World.CHAPTER_ONE.phase(snapshot)=="water" and str(snapshot.get("region_id","home"))=="home":
			supply.text+="\n"+starter_supply_hint(obj,network)
		elif present and amount==0:
			state.text+=" · 暫無存水"
		refill.disabled = not owner or amount >= capacity
		toggle.disabled = not owner
		toggle.text = "停止" if active else "啟用"
	refresh(app)

static func starter_supply_hint(device:Dictionary,network:Dictionary)->String:
	var water:=int(device.get("water",0))
	if water>int(device.get("network_water",0)):
		return "目前有手動補的水。先用完，或拆除重放，再讓管網供水。"
	if int(network.get("connected_tanks",0))+int(network.get("towers",0))==0:
		return "第一章需要管網水。用自己的水管接上儲水桶。"
	if network.get("supply_zone","")==World.INDUSTRY.ZONE_CUT:
		return "先開啟分流閘，讓管網水到達灑水器。"
	if water==0 and int(network.get("water",0))+int(network.get("tower_water",0))==0:
		return "先給管網補水，再啟用灑水器。"
	if not device.get("enabled",false):return "水源已接通。啟用後，等它澆濕範圍內自己的乾田。"
	return "等待管網供水澆到自己的乾田。"

func copper(app) -> void:
	var body := open(app, "渡口・運入礦料")
	modal.set_meta("life_modal_layout", "automation_copper")
	var details := Tasks.card(body)
	Tasks.add_icon(details, ItemArt.icon("copper_ore"), 64)
	Tasks.line(app, details, "這批練習礦料由外地送來。用工作台製作的強化鎬整理礦料，再加工成銅接頭。", 16)
	var state: Label = app.label("", 20)
	details.add_child(state)
	var mine: Button = app.button("採掘銅礦", func(): app.session.perform("mine_copper", World.COPPER_CELL))
	details.add_child(mine)
	var borrow:Button=app.button("借用公用鎬",func():app.session.perform("borrow_mine_pick",World.COPPER_CELL))
	details.add_child(borrow)
	update_view = func(snapshot: Dictionary, person: Dictionary):
		var deposit: Dictionary = snapshot.get("copper", {})
		var remaining := maxi(0, ceili(float(deposit.get("ready", 0.0)) - float(snapshot.get("time", 0.0))))
		var owns_tool:=owns_pick(person)
		var borrowed:bool=person.get("borrowed_mine_pick",false)
		var has_pick:=owns_tool or borrowed
		borrow.visible=bool(snapshot.get("picnic",false)) and not has_pick
		state.text = "需要強化鎬" if not has_pick else ("等待補貨 · 約剩 %d 秒" % remaining if remaining > 0 else "可以整理礦料")
		if borrowed and not owns_tool:state.text+=" · 使用公用鎬"
		mine.disabled = not has_pick or remaining > 0
	refresh(app)

static func reveal_recipe(scroll: ScrollContainer, entry: Button) -> void:
	var tree := scroll.get_tree()
	await tree.process_frame
	await tree.process_frame
	if is_instance_valid(scroll) and is_instance_valid(entry) and entry.is_visible_in_tree():
		entry.grab_focus()
		scroll.ensure_control_visible(entry)

## Correlated craft submit for the bench. Pending clears only on
## Session.action_completed with the exact predicted sequence AND action "craft";
## notices, snapshots and prepare_material_box completions never release it.
## One craft at a time (no double craft), no automatic retry.
class WorkbenchController extends Node:
	const ACK_TIMEOUT_MS := 10000
	const GOOD := Color("3e664b")
	const WARN := Color("9c4b32")
	var app
	var cell := Vector2i.ZERO
	var picker
	var status: Label
	var on_change: Callable
	var pending: Dictionary = {}

	func _ready() -> void:
		app.session.action_completed.connect(_on_completed)

	func _exit_tree() -> void:
		if app and app.session and app.session.action_completed.is_connected(_on_completed):
			app.session.action_completed.disconnect(_on_completed)

	func _process(_delta: float) -> void:
		if not pending.is_empty() and not bool(pending.host) and Time.get_ticks_msec() - int(pending.at) > ACK_TIMEOUT_MS:
			pending = {}
			picker.release()
			_status("還沒收到工作台回應。請先看背包裡是否已有成品，再決定要不要重試，以免重複製作。", false)
			_changed()

	func busy() -> bool:
		return not pending.is_empty()

	func submit(recipe_id: String) -> void:
		if busy():
			_status("上一個製作還在等待回應，請稍候。", false)
			return
		if not World.CRAFT.has(recipe_id) or picker.recipe_id != recipe_id:
			return
		var session = app.session
		var hosting: bool = session.world != null
		if not hosting and not _connected():
			_status("與世界的連線已中斷，這次沒有送出。", false)
			return
		var intent: Dictionary = picker.freeze()
		if not bool(intent.get("ok", false)):
			_status(str(intent.get("reason", "目前不能製作。")), false)
			_changed()
			return
		var title := str(World.CRAFT[recipe_id].name)
		# Predict first: a host completes synchronously inside perform().
		pending = {"action": "craft", "sequence": int(session.counter) + 1, "host": hosting, "at": Time.get_ticks_msec(), "intent": title}
		_status("製作%s……等待工作台回應" % title, true)
		_changed()
		var sequence: int = session.perform("craft", cell, str(intent.extra))
		if pending.is_empty():
			return
		if sequence <= 0:
			pending = {}
			picker.release()
			_status("世界正在關閉，這次沒有送出。", false)
			_changed()
			return
		pending.sequence = sequence
		if hosting:
			pending = {}
			picker.release()
			_status("沒有收到工作台確認。請看背包數量是否已更新；沒有變化時世界可能正在保存或暫停。", false)
			_changed()

	func _connected() -> bool:
		var peer = app.session.multiplayer.multiplayer_peer
		return peer != null and peer.get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED

	func _on_completed(sequence: int, action: String, result: Dictionary) -> void:
		if pending.is_empty() or sequence != int(pending.sequence) or action != str(pending.action):
			return
		pending = {}
		var success := bool(result.get("ok", false))
		var message := str(result.get("message", "工作台已回覆。"))
		var source_note: String = picker.release(result)
		if success:
			_status(message if source_note.is_empty() else "%s · %s" % [message, source_note], true)
		else:
			_status(source_note if not source_note.is_empty() else "沒有變更：" + message, false)
		_changed()

	func _status(message: String, success: bool) -> void:
		if not is_instance_valid(status):
			return
		status.text = message
		status.add_theme_color_override("font_color", GOOD if success else WARN)

	func _changed() -> void:
		if on_change.is_valid():
			on_change.call()


static func owns_pick(person: Dictionary) -> bool:
	return not World.active_mining_pick(person.get("inventory", {})).is_empty()

## Concise use guidance for a craft recipe. `app` supplies live key labels for
## portable tools (any object with binding_label(action)); without it the key
## prefix is left out rather than guessed.
static func material_route(snapshot:Dictionary,own:String,item:String)->Dictionary:
	if item not in ["plank","charcoal"]:return {}
	var station:String=World.INDUSTRY.PROCESS[item].station
	var person:Dictionary=snapshot.get("players",{}).get(own,{})
	if person.is_empty():return {}
	var position:=Vector2(float(person.x),float(person.y))
	var nearest:=""
	var distance:=INF
	var objects:Dictionary=snapshot.get("objects",{})
	var keys:=objects.keys()
	keys.sort()
	for key in keys:
		var obj:Dictionary=objects[key]
		if obj.get("type","")!=station or obj.get("owner","")!=own:continue
		var gap:=position.distance_to(Vector2(World.cell(str(key)))+Vector2(0.5,0.5))
		if gap<distance:nearest=str(key);distance=gap
	if not nearest.is_empty():
		var cell:=World.cell(nearest)
		if distance<=3.2:return {"action":"device","station":station,"cell":cell}
		var delta:=Vector2(cell)+Vector2(0.5,0.5)-position
		var direction:="東" if delta.x>0.5 else ("西" if delta.x< -0.5 else "")
		direction+="南" if delta.y>0.5 else ("北" if delta.y< -0.5 else "")
		return {"action":"far","station":station,"cell":cell,"distance":distance,"direction":direction}
	for ingredient in World.BUILD[station]:
		if World.CRAFT.has(ingredient):return {"action":"recipe","station":station,"recipe":ingredient}
	return {}

static func material_hint(item:String)->String:
	if item in ["plank","charcoal"]:
		var recipe:Dictionary=World.INDUSTRY.PROCESS[item]
		return "%s加工木材 %d → %s %d。"%[World.BUILD[recipe.station].name,int(recipe.ingredients.wood),World.NAMES[item],int(recipe.yield)]
	var hints:={
		"wood":"用斧頭採集成熟樹木；林務工作站也會產出。",
		"stone":"用十字鎬採集島上的岩石。",
		"fiber":"清理草叢或採集樹木取得。",
		"sapling":"採集樹木取得，再種在自己的空地。",
		"resin":"採集樹木取得；林務工作站也會產出。",
		"copper_ore":"渡口運入礦料點／金瓜石；用強化石鎬或公用鎬。",
		"copper_ingot":"用小熔爐或玻璃爐熔煉兩份銅礦和一份木炭，取得兩份銅錠。",
		"iron_ingot":"在金瓜石礦道 B4 或 B6 收集鐵礦，用小熔爐或玻璃爐煉成鐵錠。",
		"vein_quartz":"在金瓜石礦道 B9 或 B10 採礦時取得。",
		"hardwood":"用斧頭採伐自種成樹取得；林務站不產硬木。"}
	if hints.has(item):return hints[item]
	if World.CRAFT.has(item):return "在工作台查看「%s」配方與解鎖條件。"%World.CRAFT[item].name
	return ""

static func recipe_use(id: String, app = null) -> String:
	var guide: Dictionary = GUIDE.get(id, {})
	var text: String = guide.get("text", USE_FALLBACK)
	var keys: Array = guide.get("keys", [])
	if keys.is_empty():
		return text
	var labels: Array = []
	for action in keys:
		labels.append(str(app.binding_label(action)) if app != null and app.has_method("binding_label") else "")
	return (text % labels).strip_edges()

static func recipe_ingredients(id: String) -> Dictionary:
	return World.CRAFT.get(id, {}).get("ingredients", {})
