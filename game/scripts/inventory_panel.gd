extends PanelContainer

signal close_requested
signal rice_ball_requested
signal ginger_tea_requested
signal ginger_tea_replace_requested
## C12 D01-D16 dishes other than the two above: one serving of dish `id` (World action eat_meal).
signal meal_requested(id:String)
signal rope_requested

const World = preload("res://scripts/world.gd")
const ItemArt = preload("res://scripts/inventory_item_art.gd")
const Slot = preload("res://scripts/item_slot.gd")
const PixelTheme = preload("res://scripts/inventory_pixel_theme.gd")
const LifeTheme = preload("res://scripts/life_ui_theme.gd")
const ControllerScroll = preload("res://scripts/controller_scroll_container.gd")
const Flower = preload("res://scripts/flower_nursery.gd")
const Souvenir = preload("res://scripts/souvenir_exchange.gd")
## Tianwei items the stall and shipping bin never buy (contract data_values.not_sellable).
const NOT_SELLABLE := ["orange_dye","bluebell_seed", "orange_blossom_seed", "chime_herb_seed", "blue_dye", "sugar", "crystal_sand", "glass"]
const CATEGORIES := ["全部", "素材", "種子", "收成", "其他"]
const MATERIALS := ["bamboo","orange_dye","fired_brick","roof_tile","woodwork_parts","rope","cotton_cloth","wool_cloth","wood", "stone", "fiber", "copper_ore", "copper_ingot", "iron_ore", "iron_ingot", "copper_joint", "plank", "hardwood", "resin", "charcoal", "flour", "clay","tea_jar", "tea_returned_jar", "tea_worn_jar", "tea_spent_jar", "blue_dye", "sugar", "crystal_sand", "glass", "ochre_earth", "vein_quartz", "warm_stone"]

var selected_id := "wood"
var category := 0
var slots: Dictionary = {}
var tabs: Array[Button] = []
var inventory: Dictionary = {}
var balance: Label
var grid: GridContainer
var scroller: ScrollContainer
var empty_state: Label
var detail_icon: TextureRect
var detail_name: Label
var detail_category: Label
var detail_count: Label
var detail_use: Label
var detail_value: Label
var detail_scroll: ScrollContainer
var meal_hint: Label
var eat_rice_ball:Button
var craft_rope:Button
var mine_energy:=100
var in_mine:=false
var in_warm_springs:=false
var warmth_left:=0.0
## One-slot meal buff read from the authoritative snapshot ({} none, else id/until/left) and the
## item whose replacement the player has been asked to confirm (second press sends it).
var meal_effect:Dictionary={}
var replace_armed:=""
var notice: Label
var binding_name:Callable
var layout_bounds:=Vector2.ZERO
var tray_overhead:=0.0

func setup(snapshot: Dictionary, own_id: String, base_theme: Theme, key_name:Callable=Callable()) -> void:
	binding_name=key_name
	theme = PixelTheme.make(base_theme)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_theme_stylebox_override("panel", LifeTheme.panel_style())
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	add_child(body)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	body.add_child(header)
	header.add_child(icon_rect(ItemArt.icon("backpack"), 32))
	var heading := make_label("隨身背包", 26)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	header.add_child(icon_rect(ItemArt.icon("coins"), 32))
	balance = make_label("", 20)
	header.add_child(balance)
	var close := Button.new()
	close.text = "關閉"
	close.custom_minimum_size = Vector2(72, 34)
	close.pressed.connect(func(): close_requested.emit())
	header.add_child(close)
	var tab_bar := HBoxContainer.new()
	tab_bar.add_theme_constant_override("separation", 8)
	body.add_child(tab_bar)
	for index in CATEGORIES.size():
		var tab := Button.new()
		tab.text = CATEGORIES[index]
		tab.icon = ItemArt.icon(["backpack","wood","radish_seed","radish","egg"][index])
		tab.expand_icon = true
		tab.add_theme_constant_override("icon_max_width",24)
		tab.toggle_mode = true
		tab.custom_minimum_size.y = 34
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.pressed.connect(select_category.bind(index))
		tab_bar.add_child(tab)
		tabs.append(tab)
	var content := HBoxContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 14)
	body.add_child(content)
	var tray := PanelContainer.new()
	tray.add_theme_stylebox_override("panel", PixelTheme.paper_style())
	tray.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(tray)
	var tray_content := VBoxContainer.new()
	tray.add_child(tray_content)
	scroller = ScrollContainer.new()
	scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroller.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tray_content.add_child(scroller)
	grid = GridContainer.new()
	grid.columns = 6
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	scroller.add_child(grid)
	empty_state = make_label("這個分類目前沒有物品。", 17)
	tray_content.add_child(empty_state)
	var player:Dictionary=snapshot.get("players",{}).get(own_id,{})
	var bag:Dictionary=player.get("inventory",{})
	var held_ids:Array[String]=[]
	var unheld_ids:Array[String]=[]
	for id:String in World.NAMES:
		if id=="wood":continue
		if int(bag.get(id,0))>0:held_ids.append(id)
		else:unheld_ids.append(id)
	# Set the order once when opening, so live counts never move focused slots.
	for id in ["wood"]+held_ids+unheld_ids:
		var slot := Slot.new()
		slot.configure(id, ItemArt.icon(id), 0, World.NAMES[id])
		slot.item_selected.connect(select_item)
		slot.focus_entered.connect(select_item.bind(id))
		grid.add_child(slot)
		slots[id] = slot
	var details_panel:=make_details()
	content.add_child(details_panel)
	tray_overhead=details_panel.custom_minimum_size.x+content.get_theme_constant("separation")
	tray_overhead+=get_theme_stylebox("panel").get_minimum_size().x+tray.get_theme_stylebox("panel").get_minimum_size().x
	tray_overhead+=scroller.get_v_scroll_bar().get_combined_minimum_size().x
	notice = make_label("", 15)
	notice.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	notice.hide()
	body.add_child(notice)
	var hint := make_label("方向鍵選物品 · X 前往物品操作 · 右搖桿閱讀詳情 · %s / Esc 返回"%key("inventory","Tab"), 15)
	hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(hint)
	refresh(snapshot, own_id)
	select_category(0)
	minimum_size_changed.connect(_fit_panel)
	_focus_initial_item.call_deferred(selected_id)

func _focus_initial_item(item:String) -> void:
	if not item.is_empty() and slots[item].is_visible_in_tree():slots[item].grab_focus()
	scroller.follow_focus=true

func _input(event:InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventJoypadButton or not event.pressed or event.button_index!=JOY_BUTTON_X:return
	if selected_id.is_empty() or get_viewport().gui_get_focus_owner()!=slots.get(selected_id):return
	for action in [eat_rice_ball,craft_rope]:
		if action.visible and not action.disabled:
			action.grab_focus()
			get_viewport().set_input_as_handled()
			return

func _unhandled_input(event:InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel") or not is_visible_in_tree():return
	var focused:=get_viewport().gui_get_focus_owner()
	if focused!=null and is_ancestor_of(focused):
		get_viewport().set_input_as_handled()
		close_requested.emit()

func layout_for(viewport_size: Vector2) -> void:
	layout_bounds=viewport_size
	var extent:=_panel_extent()
	var gap:=grid.get_theme_constant("h_separation")
	var slot_width:=float(slots["wood"].custom_minimum_size.x)
	grid.columns=clampi(floori((extent.x-tray_overhead+gap)/(slot_width+gap)),1,6)
	_fit_panel()
	link_focus()

func _panel_extent() -> Vector2:
	return Vector2(minf(900,layout_bounds.x-32),minf(560,layout_bounds.y-32))

func _fit_panel() -> void:
	if layout_bounds==Vector2.ZERO:return
	# A previously selected item may temporarily report a larger minimum
	# until Godot settles the containers. Refit when that minimum changes.
	size=_panel_extent()
	position=((layout_bounds-size)/2).floor()

func show_notice(message: String, success: bool) -> void:
	notice.text = message
	notice.add_theme_color_override("font_color", Color("34543d") if success else Color("874834"))
	notice.visible = not message.is_empty()

func refresh(snapshot: Dictionary, own_id: String) -> void:
	var person: Dictionary = snapshot.get("players", {}).get(own_id, {})
	inventory = person.get("inventory", {})
	mine_energy=World.MEAL_BUFF.whole_points(person)
	in_mine=str(snapshot.get("region_id","")) in World.MINES.IDS
	in_warm_springs=snapshot.get("region_id","")==World.WARM_SPRINGS.REGION
	warmth_left=World.WARM_SPRINGS.warmth_left(person,float(snapshot.get("time",0.0)))
	meal_effect=World.MEAL_BUFF.read(person,float(snapshot.get("time",0.0)))
	balance.text = "鈴幣 %d" % int(person.get("coins", 0))
	var quality_visibility_changed:=false
	for id in slots:
		var count:=int(inventory.get(id,0))
		if id.begins_with("quality_") and (count>0)!=(slots[id].count>0):quality_visibility_changed=true
		slots[id].set_count(count)
	if quality_visibility_changed:
		select_category(category)
		return
	update_details()

func select_category(index: int) -> void:
	category = index
	# Category filtering changes the grid height; discard the old scroll offset.
	# Otherwise switching from a long catalogue to a small crop list can show blank paper.
	scroller.scroll_vertical=0
	for i in tabs.size():
		tabs[i].set_pressed_no_signal(i == index)
	var ids: Array[String] = []
	for id in slots:
		var visible_item := index == 0 or category_for(id) == index
		if id.begins_with("quality_") and int(inventory.get(id,0))==0:visible_item=false
		slots[id].visible = visible_item
		if visible_item:
			ids.append(id)
	empty_state.visible = ids.is_empty()
	scroller.visible = not ids.is_empty()
	if selected_id not in ids:
		selected_id = ids[0] if not ids.is_empty() else ""
	select_item(selected_id)
	link_focus()

func select_item(id: String) -> void:
	if not id.is_empty() and (not slots.has(id) or not slots[id].visible):
		return
	if id!=selected_id:
		replace_armed=""
		detail_scroll.scroll_vertical=0
	selected_id = id
	for item in slots:
		slots[item].set_selected(item == id)
	if not id.is_empty():
		tabs[category].focus_neighbor_bottom = tabs[category].get_path_to(slots[id])
	update_details()

func link_focus() -> void:
	var visible_slots: Array[Control] = []
	for slot in slots.values():
		if slot.visible:
			visible_slots.append(slot)
	for i in visible_slots.size():
		var slot := visible_slots[i]
		var column := i % grid.columns
		slot.focus_neighbor_left = slot.get_path_to(visible_slots[i - 1] if column > 0 else slot)
		slot.focus_neighbor_right = slot.get_path_to(visible_slots[i + 1] if column < grid.columns - 1 and i + 1 < visible_slots.size() else slot)
		slot.focus_neighbor_top = slot.get_path_to(visible_slots[i - grid.columns] if i >= grid.columns else tabs[category])
		slot.focus_neighbor_bottom = slot.get_path_to(visible_slots[i + grid.columns] if i + grid.columns < visible_slots.size() else slot)

func make_details() -> PanelContainer:
	var paper := PanelContainer.new()
	paper.custom_minimum_size.x = 250
	paper.add_theme_stylebox_override("panel", PixelTheme.paper_style())
	var details := VBoxContainer.new()
	details.add_theme_constant_override("separation", 8)
	paper.add_child(details)
	detail_scroll=ControllerScroll.new()
	detail_scroll.name="ItemDetailsScroll"
	detail_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	detail_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	details.add_child(detail_scroll)
	var readable:=VBoxContainer.new()
	readable.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	readable.add_theme_constant_override("separation", 6)
	detail_scroll.add_child(readable)
	var item_header:=HBoxContainer.new()
	item_header.add_theme_constant_override("separation",8)
	readable.add_child(item_header)
	detail_icon = icon_rect(null, 64)
	detail_icon.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	item_header.add_child(detail_icon)
	var identity:=VBoxContainer.new()
	identity.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	identity.add_theme_constant_override("separation",0)
	item_header.add_child(identity)
	detail_name = make_label("", 23)
	detail_name.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	identity.add_child(detail_name)
	detail_category = make_label("", 15)
	identity.add_child(detail_category)
	detail_count = make_label("", 19)
	identity.add_child(detail_count)
	readable.add_child(HSeparator.new())
	detail_use = make_label("", 16)
	detail_use.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	readable.add_child(detail_use)
	detail_value = make_label("", 16)
	detail_value.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	readable.add_child(detail_value)
	meal_hint=make_label("",15)
	meal_hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	meal_hint.hide()
	details.add_child(meal_hint)
	eat_rice_ball=Button.new()
	eat_rice_ball.name="EatRiceBall"
	eat_rice_ball.hide()
	eat_rice_ball.pressed.connect(func():
		var conflict:=meal_conflict(selected_id)
		if conflict and replace_armed!=selected_id:
			# Replacing a different active meal effect needs a second, explicit press.
			replace_armed=selected_id
			update_details()
			return
		replace_armed=""
		if selected_id==World.GINGER_TEA:
			if conflict:ginger_tea_replace_requested.emit()
			else:ginger_tea_requested.emit()
		elif World.KITCHEN_STOVE.is_dish(selected_id) and selected_id not in World.KITCHEN_STOVE.LEGACY_EAT:
			meal_requested.emit(selected_id+":"+World.MEAL_BUFF.CONFIRM if conflict else selected_id)
		else:rice_ball_requested.emit())
	details.add_child(eat_rice_ball)
	craft_rope=Button.new()
	craft_rope.name="CraftRope"
	craft_rope.text="手作繩索 · 纖維 %d"%World.ROPE_FIBER_COST
	craft_rope.hide()
	craft_rope.pressed.connect(func():rope_requested.emit())
	details.add_child(craft_rope)
	return paper

func update_details() -> void:
	var id := selected_id
	detail_icon.texture = slots[id].artwork.texture if not id.is_empty() else null
	detail_name.text = World.NAMES.get(id, "未選擇物品")
	detail_category.text = CATEGORIES[category_for(id)] if not id.is_empty() else ""
	detail_count.text = "持有 %d" % int(inventory.get(id, 0)) if not id.is_empty() else ""
	detail_use.text = use_for(id,binding_name)
	detail_value.text = value_for(id)
	var plain_dish:bool=World.KITCHEN_STOVE.is_dish(id) and id not in World.KITCHEN_STOVE.LEGACY_EAT
	eat_rice_ball.visible=(id in ["star_rice_ball",World.GINGER_TEA] or plain_dish) and in_mine
	eat_rice_ball.disabled=mine_energy>=100 or int(inventory.get(id,0))<1
	var verb:="喝一杯" if id==World.GINGER_TEA else "吃一份"
	var restore:int=World.KITCHEN_STOVE.restore_for(id)
	var effect_hint:=""
	eat_rice_ball.text="體力已滿" if mine_energy>=100 else "%s · 恢復 %d 體力"%[verb,mini(restore,100-mine_energy)]
	if id==World.MEAL_BUFF.SALAD and in_mine:
		# D03: eating at a full bar is allowed so the effect can start; refused only when it is
		# already running and the bar is full (nothing to gain).
		var running:bool=meal_effect.get("id","")==World.MEAL_BUFF.SALAD
		eat_rice_ball.disabled=int(inventory.get(id,0))<1 or (mine_energy>=100 and running)
		eat_rice_ball.text="吃一份 · 恢復 %d 體力"%mini(restore,100-mine_energy) if mine_energy<100 else "吃一份"
		effect_hint="採礦耗體 −5%（6 分鐘）"
		if running:
			if mine_energy>=100:
				eat_rice_ball.text="沙拉效果還在"
				effect_hint="剩 %s"%World.MEAL_BUFF.clock_text(ceili(float(meal_effect.left)))
			else:effect_hint="採礦耗體 −5%，重新計時 6 分鐘"
	if id==World.GINGER_TEA and in_warm_springs:
		eat_rice_ball.show()
		var warm_running:=warmth_left>0.0
		eat_rice_ball.disabled=int(inventory.get(id,0))<1 or (mine_energy>=100 and warm_running)
		eat_rice_ball.text="暖意還在" if warm_running and mine_energy>=100 else "喝一杯 · 保暖 8 分鐘"
	if meal_conflict(id) and not eat_rice_ball.disabled:
		var other:=World.MEAL_BUFF.label_for(str(meal_effect.id))
		if not effect_hint.is_empty():effect_hint+="\n"
		effect_hint+="取代「%s」 · %s"%[other,World.MEAL_BUFF.clock_text(ceili(float(meal_effect.left)))]
		if replace_armed==id:eat_rice_ball.text="確認取代"
	elif replace_armed==id:
		replace_armed=""
	meal_hint.text=effect_hint
	meal_hint.visible=eat_rice_ball.visible and not effect_hint.is_empty()
	craft_rope.visible=id=="fiber"
	craft_rope.disabled=int(inventory.get("fiber",0))<World.ROPE_FIBER_COST
	for action in [eat_rice_ball,craft_rope]:
		if action.visible and not id.is_empty():action.focus_neighbor_left=action.get_path_to(slots[id])

## True when eating `id` here would replace a different active meal effect (needs confirmation).
func meal_conflict(id:String) -> bool:
	if meal_effect.is_empty() or id not in [World.MEAL_BUFF.SALAD,World.GINGER_TEA]:return false
	if id==World.GINGER_TEA and not in_warm_springs:return false
	if id==World.MEAL_BUFF.SALAD and not in_mine:return false
	return meal_effect.id!=id

static func make_label(value: String, font_size: int) -> Label:
	var result := Label.new()
	result.text = value
	result.add_theme_font_size_override("font_size", font_size)
	return result

static func icon_rect(texture: Texture2D, pixels: int) -> TextureRect:
	var result := TextureRect.new()
	result.texture = texture
	result.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	result.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	result.custom_minimum_size = Vector2(pixels, pixels)
	result.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result

static func category_for(id: String) -> int:
	if id in MATERIALS:
		return 1
	if id.ends_with("_seed") or id == "sapling":
		return 2
	if World.CROPS.has(World.CROP_CATALOG.base_kind(id)) or World.LIVESTOCK.quality_item(id) or World.FISH.has(id) or id in ["egg","tea_leaf","tea_light","tea_deep"]:
		return 3
	return 4

func key(action:String,fallback:String) -> String:
	return String(binding_name.call(action)) if binding_name.is_valid() else fallback

static func use_for(id: String, key_name:Callable=Callable()) -> String:
	if World.CROP_CATALOG.quality_item(id):return "照料或輪作可取得，能放進出貨箱、賣給種子攤或在市集上架。"
	if World.LIVESTOCK.quality_item(id):return "親密度達標後，畜牧定期多產出的一份優良品。可出貨或在市集上架。"
	var shortcuts:Dictionary={"build_menu":"B","interact":"E","till_area":"U","seeds":"C","seed_area":"I","harvest_area":"O"}
	if key_name.is_valid():
		for action in shortcuts:
			shortcuts[action]=key_name.call(action)
	if id in World.INDUSTRY.SHELL_BOTTLES:
		return "靠近自己的木桌或貝殼圓桌，按 %s 將這款貝殼瓶擺上桌。"%shortcuts.interact
	if id==World.INDUSTRY.TEA_SET:
		return "擺在自己的木桌、圓角木桌或低腳竹茶桌上；走近桌子就能選斟茶或奉茶表情。只是裝飾，不會產出茶飲或鈴幣。"
	if id in World.INDUSTRY.TABLE_VASE_BLOOMS:
		return "靠近自己的木桌或貝殼圓桌，按 %s 擺上花瓶或更換瓶裡的花。"%shortcuts.interact
	match id:
		"star_rice_ball":return "在合作礦場食用，最多恢復 %d 點體力。"%World.KITCHEN_STOVE.restore_for(id)
		"ginger_tea":return "最多恢復 %d 點探索體力。在暖泉高地喝一杯可保暖 8 分鐘。"%World.KITCHEN_STOVE.restore_for(id)
		"salad":return "公共廚房灶台的料理。在合作礦場食用，恢復 %d 點探索體力，並在 6 分鐘內讓採礦耗體減少 5%%。同一時間只有一種料理效果；再吃只會重新計時，不會疊加。"%World.KITCHEN_STOVE.restore_for(id)
		"strawberry_toast":return "可送給居民，小栗特別喜歡。"
		World.XIAOLI_SHOP.SCALE_ITEM:return "替渡口小店掛上招牌後，小栗送你的紀念秤。以前攤車上的每筆生意，都從這裡開始。"
		"forest_mushroom_soup","rainbow_skewer":return "公共廚房灶台的料理。在合作礦場食用，每份恢復 %d 點探索體力。"%World.KITCHEN_STOVE.restore_for(id)
		"tea_leaf":return "在貓空合作茶園採得，兩份可在烘焙台製成一批茶。"
		"clay":return "由鶯歌合作陶坊供應；兩份可在工坊窯內燒製一只陶罐。"
		"tea_jar":return "新罐可配送 3 次。小栗收貨後留下空罐，寄回即可再用；用完可修補。"
		"tea_returned_jar":return "回收罐剩 2 次配送。包裝時優先使用舊罐，磨損罐會比此罐更先使用。"
		"tea_worn_jar":return "剩 1 次配送。最後一趟仍會完整送達茶貨，寄回後成為待修陶罐，可帶去修補。"
		"tea_spent_jar":return "暫時不能裝茶。帶這只罐與陶土 1 份到鶯歌製罐窯修補，再領取可用 3 次的新罐。"
		"tea_light","tea_deep":return "到貓空寄運桌選包材、寄往渡口；到小栗身旁結清茶貨。"
		"": return ""
		"wood", "stone": return "可用於建造，也能捐給渡口的共同工程。"
		"fiber": return "可用於手作繩索、家具、屋頂和混合飼料。"
		"rope": return "以五份纖維手作編成。可用來建造航海繩掛架。"
		"reinforced_pick": return "隨身攜帶後，可用十字鎬採集東北採石點旁的銅礦脈。"
		"copper_pick": return "帶在身上即可用十字鎬操作。地表岩石一下敲開，礦道同一礦點的等待時間從 12 秒降到 9 秒。"
		"iron_pick", "precision_pick":
			var effect:Dictionary=World.MINING_PICK_EFFECTS[id]
			return "帶在身上即可使用。地表岩石一擊敲開，礦道同一礦點等 %d 秒，每鎬約省 %d%% 體力。"%[int(effect.cooldown), roundi(100.0*(1.0-float(effect.energy)))]
		"copper_axe": return "放進背包即可使用，兩下砍倒樹木。"
		"iron_axe": return "放進背包即可使用，一擊砍倒樹木。"
		"precision_axe": return "一擊砍倒樹木。砍島民種下的成熟樹木時，多掉一塊硬木。"
		"copper_hoe", "iron_hoe", "precision_hoe":
			return "放進背包後，在家園可使用範圍整地，最多 %d 格，操作方式顯示在快捷列上方。"%World.TILLER.HAND_PATTERNS[id].size()
		"copper_can", "iron_can", "precision_can":
			return "放進背包後，在家園可一次澆最多 %d 格作物。會略過已澆過和沒有權限的田格。"%World.TILLER.HAND_PATTERNS[id].size()
		"copper_rod", "iron_rod", "precision_rod":
			return "帶在背包時，平常等 %.1f 秒咬鉤，標準釣法的亮帶更寬。河岸釣魚會沿用活動規則。"%World.FishingTracking.bite_wait(id)
		"copper_seed_pouch", "iron_seed_pouch", "precision_seed_pouch":
			return "在家園可播最多 %d 格自己的空田，每格用一粒種子。種子不夠時先播中央附近。"%World.TILLER.HAND_PATTERNS[id].size()
		"copper_sickle", "iron_sickle", "precision_sickle":
			return "在家園可採收最多 %d 格成熟作物。範圍採收只收自己的田或明確授權的田。"%World.TILLER.HAND_PATTERNS[id].size()
		"copper_ore": return "渡口運入的練習礦料或金瓜石礦點可取得，需強化石鎬或公用鎬資格。可在工作台加工成銅接頭。"
		"copper_joint": return "用來組裝灑水器、種子機和溫室玻璃棚等設備。"
		"sprinkler_kit": return "按 %s 選小型灑水器，在空地放置。靠近按 %s 補水。每天澆一次上下左右的自家作物，牆與關閉的門會擋水。" % [shortcuts["build_menu"],shortcuts["interact"]]
		"iron_ore": return "金瓜石礦道 B4 和 B6 的伴生礦，可與木炭熔成鐵錠。"
		"fired_brick": return "用鶯歌陶土燒成的紅磚，可以從出貨箱出售。"
		"roof_tile": return "陶窯燒成的紅陶屋瓦。每片可在自己的地板上鋪一格紅陶瓦屋頂，拆下會退回。"
		"woodwork_parts": return "在木工台用木板和硬木製作。可組裝農機，也能交給波波修礦車。"
		"iron_ingot": return "用鐵礦與木炭熔出的金屬錠，可以從出貨箱出售。"
		"copper_ingot": return "在小熔爐或玻璃爐用銅礦和木炭熔煉。波波修礦車與鈴婆婆做紀念鐘時會用到。"
		"hardwood": return "砍伐島民種下的成熟樹木可取得 2 塊硬木，精製斧可取得 3 塊。可用於阿榆的長椅修繕。"
		"plank": return "在鋸木台加工木材取得，用於部分設備配方。"
		"resin": return "採集自種植的樹木，用於部分設備配方。"
		"charcoal": return "以炭窯加工取得。"
		"crystal_sand": return "來自望安星砂海岸或金瓜石礦道。用 2 份晶砂和 1 份木炭在工作台製成溫室玻璃。"
		"ochre_earth": return "金瓜石第 6、7 層的紅褐色黏土，可交給出貨箱出售。"
		"vein_quartz": return "第 9、10 層晶洞的石英塊，玻璃爐可以把它熔碎成晶砂。"
		"warm_stone": return "第 12、13 層微溫的岩片，可鋪成共餐桌的保溫底座。"
		"waterworks_kit": return "按 %s 放置水力加工台。接上自己的水管與儲水桶，以銅礦和木材自動製作銅接頭，可用輸送帶進出料。" % [shortcuts["build_menu"]]
		"mine_drill_kit": return "在合作礦場指定工作面旁架設，機頭會自動對準。每批消耗 1 木炭，依當層礦脈產出礦料，可接輸送帶；每人最多兩台。"
		"pipe_kit", "tank_kit", "pump_kit", "sawmill_kit", "kiln_kit":
			return "按 %s 開啟建造目錄，選擇對應設備後放置。" % [shortcuts["build_menu"]]
		"diversion_gate_kit": return "按 %s 在「生活」頁選分流閘，接在自己的水管中間。靠近按 %s 切換全開、餘水或關閉，決定哪一段灑水器先拿到桶水。" % [shortcuts["build_menu"],shortcuts["interact"]]
		"water_tower_kit": return "按 %s 在「生活」頁選水塔，接在自己的水管上，可存 96 份水。靠近按 %s 切換出水或只蓄水；關閉或餘水的分流閘另一側由水塔繼續供水。" % [shortcuts["build_menu"],shortcuts["interact"]]
		"water_share_plaque_kit": return "紀念物・蘭陽回訪時星禾送的分水木牌。按 %s 打開家園工坊，在「生活」頁選它擺到家園；不擋路，拆除會收回背包。" % [shortcuts["build_menu"]]
		"mine_lantern_kit": return "紀念物・金瓜石回訪時波波送的礦燈（裝飾，不會照明）。按 %s 打開家園工坊，在「生活」頁選它擺到家園；不擋路，拆除會收回背包。" % [shortcuts["build_menu"]]
		"tea_ware_kit": return "紀念物・貓空與鶯歌回訪時陶師送的茶陶組（茶壺、茶杯與木托盤）。按 %s 打開家園工坊，在「生活」頁選它擺到家園，只是裝飾；也能借給渡口共餐桌泡茶。拆除會收回背包。" % [shortcuts["build_menu"]]
		"salt_basket_kit": return "紀念物・臺南北門回訪時阿曬送的鹽籃（竹編小籃裝著一把海鹽，只是裝飾）。按 %s 打開家園工坊，在「生活」頁選它擺到家園；不擋路，拆除會收回背包。" % [shortcuts["build_menu"]]
		"mill_kit": return "公共廚房開張後解鎖。按 %s 放置麵粉磨坊，靠近按 %s 把小麥 2 磨成麵粉 1，也可用輸送帶自動送料。" % [shortcuts["build_menu"],shortcuts["interact"]]
		"flour": return "來源：麵粉磨坊把小麥 2 磨成 1；磨坊前可到小栗的攤位買，每人每天最多 %d 份、每份 %d 鈴幣。公共廚房灶台 1 份烤成 1 個麵包，也用來做南瓜派；不是料理，攤位不收購。" % [preload("res://scripts/save_schema.gd").FLOUR_STALL_DAILY,preload("res://scripts/save_schema.gd").FLOUR_STALL_PRICE]
		"pumpkin_pie": return "在小石灶用南瓜、麵粉和雞蛋各 1 份烤成，一次 4 份，可在小栗的攤位出售。"
		"forester_kit": return "按 %s 選擇林務工作站。放置後靠近按 %s 加入木炭與樹苗。" % [shortcuts["build_menu"],shortcuts["interact"]]
		"conveyor_kit": return "按 %s 放置輸送帶。靠近按 %s 設定流向與要輸送的物品。" % [shortcuts["build_menu"],shortcuts["interact"]]
		"tiller": return "按 %s 拿起耕田機，一次最多開 9 格。會跳過占用格，成功才消耗 1 木炭。" % [shortcuts["till_area"]]
		"seeder": return "按 %s 選種子、%s 拿起播種機。只播種自己的空農田，每格用 1 顆種子，成功才消耗 1 木炭。" % [shortcuts["seeds"],shortcuts["seed_area"]]
		"harvester": return "按 %s 拿起收割機。最多收割九格有權採收的成熟作物，成功才消耗 1 木炭。" % [shortcuts["harvest_area"]]
		"sapling": return "在空地種植，三分鐘長成。"
		"egg_basket": return "到渡口找糯米雞，從照料面板裝設收集籃。"
		"feed": return "靠近糯米雞，從照料面板餵食。"
		"soup", "bread": return "可交給渡口野餐，也可以在小栗的攤位出售。"
		"bluebell": return "田尾育苗床種出的鈴蘭藍花。%d 朵可在染色桌製成藍色染料 %d 份；在留種台 1 朵換 1 包種子。" % [int(Flower.DYE.ingredients.bluebell), int(Flower.DYE.yield)]
		"orange_blossom": return "田尾育苗床種出的蜜橙花。可交付花圃訂單、捐給公共花園，或在留種台換 1 包種子。"
		"chime_herb": return "田尾育苗床種出的風鈴香草。花園餅乾的香料，也可交付訂單、捐給公共花園或留種。"
		"bluebell_seed", "orange_blossom_seed", "chime_herb_seed":
			var kind: String = id.trim_suffix("_seed")
			return "在田尾育苗床或自家農田播種並澆水。目前全年可種，澆水後約 %d 秒成熟。不能出售。" % int(Flower.CROPS[kind].time)
		"animal_collector_kit": return "在家園工坊放置。裝上收集籃後，可綁定一隻動物或整座圍好的圈舍。"
		"field_sprinkler_kit","medium_sprinkler_kit","large_sprinkler_kit": return "到家園工坊的生活分類，選擇對應的灑水器就能放置。拆除時會收回組件。"
		"orange_dye": return "用蜜橙花做成，可替家園家具染成暖橙色。"
		"blue_dye": return "可替家園家具染色，也能染工作服或捐給田尾公共花園。"
		"sugar": return "來源：熬製甜菜糖；冬季前可到小栗的攤位買（每人每天最多 %d 份、每份 %d 鈴幣），田尾花卉市集也少量供應（每天最多 %d 份）。暖薑茶、草莓果醬、花園餅乾的材料。不能出售。" % [World.SUGAR_DAILY, World.SUGAR_PRICE, Flower.SUGAR_DAILY]
		"garden_cookie":
			var cookie: Dictionary = Flower.COOKIE.garden_cookie
			return "麵粉、糖、風鈴香草各 1 份在小石灶烤成 %d 份，可在小栗的攤位出售。" % int(cookie.yield)
	if Souvenir.is_item(id):
		return "紀念裝飾・按 %s 打開家園工坊，在「生活」分頁選它擺到家園。不擋路，拆除會收回背包。" % [shortcuts["build_menu"]]
	if World.RESIDENT_GOALS.is_keepsake_item(id):
		var keepsake: Dictionary = World.RESIDENT_GOALS.KEEPSAKES[id.trim_suffix(World.RESIDENT_GOALS.KIT_SUFFIX)]
		return "%s按 %s 打開家園工坊，在「生活」分頁選它擺到家園。不擋路，拆除會收回背包。" % [str(keepsake.blurb), shortcuts["build_menu"]]
	if id.ends_with("_seed"):
		var crop: Dictionary = World.CROPS[id.trim_suffix("_seed")]
		return "在農田播種並澆水，約 %d 秒成熟。" % crop.time
	if World.CROPS.has(id) or id == "carp":
		return "可當作料理材料，也可以在小栗的攤位出售。"
	if World.FISH.has(id) or World.OTHER_SALES.has(id):
		return "可在小栗的攤位出售。"
	return ""

static func value_for(id: String) -> String:
	if id.is_empty():
		return ""
	if id == "sapling":
		return "購入價　20 鈴幣"
	if Souvenir.is_item(id):
		return "紀念票兌換的紀念品 · 不能出售或交易"
	if id in ["water_share_plaque_kit", "mine_lantern_kit", "tea_ware_kit", "salt_basket_kit"]:
		return "紀念物・不能出售或交易"
	if World.RESIDENT_GOALS.is_keepsake_item(id):
		return "和%s一起做的事的紀念小物 · 不能出售或交易" % World.RESIDENT_BOND.name_of(str(World.RESIDENT_GOALS.KEEPSAKES[id.trim_suffix(World.RESIDENT_GOALS.KIT_SUFFIX)].resident))
	if id in NOT_SELLABLE:
		if Flower.MARKET_PRICES.has(id):
			return "田尾市集購入價　%d 鈴幣 · 不能出售" % int(Flower.MARKET_PRICES[id])
		return "不能出售"
	if id.ends_with("_seed"):
		return "購入價　%d 鈴幣" % World.CROPS[id.trim_suffix("_seed")].seed_price
	if World.CROPS.has(id):
		return "出售價　%d 鈴幣" % World.CROPS[id].price
	if World.CROP_CATALOG.quality_item(id):
		return "優良出售價　%d 鈴幣" % World.CROP_CATALOG.quality_price(id)
	if World.FISH.has(id):
		return "出售價　%d 鈴幣" % World.FISH[id].price
	if World.OTHER_SALES.has(id):
		return "出售價　%d 鈴幣" % World.OTHER_SALES[id]
	return "攤位未收購"
