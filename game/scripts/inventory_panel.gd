extends PanelContainer

signal close_requested
signal rice_ball_requested
signal rope_requested

const World = preload("res://scripts/world.gd")
const ItemArt = preload("res://scripts/inventory_item_art.gd")
const Slot = preload("res://scripts/item_slot.gd")
const PixelTheme = preload("res://scripts/inventory_pixel_theme.gd")
const LifeTheme = preload("res://scripts/life_ui_theme.gd")
const Flower = preload("res://scripts/flower_nursery.gd")
const Souvenir = preload("res://scripts/souvenir_exchange.gd")
## Tianwei items the stall and shipping bin never buy (contract data_values.not_sellable).
const NOT_SELLABLE := ["bluebell_seed", "orange_blossom_seed", "chime_herb_seed", "blue_dye", "sugar", "crystal_sand", "glass"]
const CATEGORIES := ["全部", "素材", "種子", "收成", "其他"]
const MATERIALS := ["rope","cotton_cloth","wool_cloth","wood", "stone", "fiber", "copper_ore", "copper_joint", "plank", "resin", "charcoal", "flour", "clay","tea_jar", "tea_returned_jar", "tea_worn_jar", "tea_spent_jar", "blue_dye", "sugar", "crystal_sand", "glass", "ochre_earth", "vein_quartz", "warm_stone"]

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
var eat_rice_ball:Button
var craft_rope:Button
var mine_energy:=100
var in_mine:=false
var notice: Label
var binding_name:Callable

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
	scroller.follow_focus = true
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
	for id in World.NAMES:
		var slot := Slot.new()
		slot.configure(id, ItemArt.icon(id), 0, World.NAMES[id])
		slot.item_selected.connect(select_item)
		slot.focus_entered.connect(select_item.bind(id))
		grid.add_child(slot)
		slots[id] = slot
	content.add_child(make_details())
	notice = make_label("", 15)
	notice.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	notice.hide()
	body.add_child(notice)
	var hint := make_label("點選查看 · 方向鍵選物品 · %s / Esc 返回"%key("inventory","Tab"), 15)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(hint)
	refresh(snapshot, own_id)
	select_category(0)
	slots[selected_id].call_deferred("grab_focus")

func layout_for(viewport_size: Vector2) -> void:
	var extent := Vector2(minf(900, viewport_size.x - 32), minf(560, viewport_size.y - 32))
	grid.columns = 6 if extent.x >= 884 else 5
	size = extent
	position = ((viewport_size - size) / 2).floor()
	link_focus()

func show_notice(message: String, success: bool) -> void:
	notice.text = message
	notice.add_theme_color_override("font_color", Color("34543d") if success else Color("874834"))
	notice.visible = not message.is_empty()

func refresh(snapshot: Dictionary, own_id: String) -> void:
	var person: Dictionary = snapshot.get("players", {}).get(own_id, {})
	inventory = person.get("inventory", {})
	mine_energy=int(person.get("mine_energy",100))
	in_mine=str(snapshot.get("region_id","")) in World.MINES.IDS
	balance.text = "鈴幣 %d" % int(person.get("coins", 0))
	for id in slots:
		slots[id].set_count(int(inventory.get(id, 0)))
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
	detail_icon = icon_rect(null, 96)
	detail_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	details.add_child(detail_icon)
	detail_name = make_label("", 23)
	details.add_child(detail_name)
	detail_category = make_label("", 15)
	details.add_child(detail_category)
	detail_count = make_label("", 19)
	details.add_child(detail_count)
	details.add_child(HSeparator.new())
	detail_use = make_label("", 16)
	detail_use.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_use.custom_minimum_size.x = 200
	details.add_child(detail_use)
	detail_value = make_label("", 16)
	details.add_child(detail_value)
	eat_rice_ball=Button.new()
	eat_rice_ball.name="EatRiceBall"
	eat_rice_ball.hide()
	eat_rice_ball.pressed.connect(func():rice_ball_requested.emit())
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
	eat_rice_ball.visible=id=="star_rice_ball" and in_mine
	eat_rice_ball.disabled=mine_energy>=100 or int(inventory.get(id,0))<1
	eat_rice_ball.text="體力已滿" if mine_energy>=100 else "吃一份 · 恢復 %d 體力"%mini(World.RICE_BALL_ENERGY,100-mine_energy)
	craft_rope.visible=id=="fiber"
	craft_rope.disabled=int(inventory.get("fiber",0))<World.ROPE_FIBER_COST

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
	if World.CROPS.has(id) or World.FISH.has(id) or id in ["egg","tea_leaf","tea_light","tea_deep"]:
		return 3
	return 4

func key(action:String,fallback:String) -> String:
	return String(binding_name.call(action)) if binding_name.is_valid() else fallback

static func use_for(id: String, key_name:Callable=Callable()) -> String:
	var shortcuts:Dictionary={"build_menu":"B","interact":"E","till_area":"U","seeds":"C","seed_area":"I","harvest_area":"O"}
	if key_name.is_valid():
		for action in shortcuts:
			shortcuts[action]=key_name.call(action)
	match id:
		"star_rice_ball":return "在合作礦場食用，最多恢復 %d 點體力。"%World.RICE_BALL_ENERGY
		"strawberry_toast":return "可送給居民，小栗特別喜歡。"
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
		"rope": return "以五份纖維手作編成。"
		"reinforced_pick": return "隨身攜帶後，可用十字鎬採集東北採石點旁的銅礦脈。"
		"copper_ore": return "在工作臺加工成銅接頭。銅礦脈位於採石點旁，需攜帶強化石鎬。"
		"copper_joint": return "用來組裝灑水器、種子機和溫室玻璃棚等設備。"
		"sprinkler_kit": return "按 %s 選小型灑水器，在空地放置。靠近按 %s 補水；每 8 秒檢查自己的四鄰格作物。" % [shortcuts["build_menu"],shortcuts["interact"]]
		"plank": return "在鋸木台加工木材取得，用於部分設備配方。"
		"resin": return "採集自種植的樹木，用於部分設備配方。"
		"charcoal": return "以炭窯加工取得。"
		"ochre_earth": return "第 6、7 層的紅褐色黏土，可當玻璃爐的耐火泥。"
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
		"flour": return "在麵粉磨坊用小麥磨成。和南瓜、雞蛋一起在小石灶烤成南瓜派；不是料理，攤位不收購。"
		"pumpkin_pie": return "在小石灶用南瓜、麵粉和雞蛋各 1 份烤成，一次 4 份，可在小栗的攤位出售。"
		"forester_kit": return "按 %s 選擇林務工作站。放置後靠近按 %s 加入木炭與樹苗。" % [shortcuts["build_menu"],shortcuts["interact"]]
		"conveyor_kit": return "按 %s 放置輸送帶。靠近按 %s 設定流向與要輸送的物品。" % [shortcuts["build_menu"],shortcuts["interact"]]
		"tiller": return "按 %s 拿起耕田機，一次最多開 9 格。會跳過占用格，成功才消耗 1 木炭。" % [shortcuts["till_area"]]
		"seeder": return "按 %s 選種子、%s 拿起播種機。只播種自己的空農田，每格用 1 顆種子，成功才消耗 1 木炭。" % [shortcuts["seeds"],shortcuts["seed_area"]]
		"harvester": return "按 %s 拿起收割機。最多收割九格有權採收的成熟作物，成功才消耗 1 木炭。" % [shortcuts["harvest_area"]]
		"sapling": return "在空地種植，三分鐘長成。"
		"feed": return "靠近糯米雞，從照料面板餵食。"
		"soup", "bread": return "可交給渡口野餐，也可以在小栗的攤位出售。"
		"bluebell": return "田尾育苗床種出的鈴蘭藍花。%d 朵可在染色桌製成藍色染料 %d 份；在留種台 1 朵換 1 包種子。" % [int(Flower.DYE.ingredients.bluebell), int(Flower.DYE.yield)]
		"orange_blossom": return "田尾育苗床種出的蜜橙花。可交付花圃訂單、捐給公共花園，或在留種台換 1 包種子。"
		"chime_herb": return "田尾育苗床種出的風鈴香草。花園餅乾的香料，也可交付訂單、捐給公共花園或留種。"
		"bluebell_seed", "orange_blossom_seed", "chime_herb_seed":
			var kind: String = id.trim_suffix("_seed")
			return "在田尾育苗床或自家農田播種並澆水。目前全年可種，澆水後約 %d 秒成熟。不能出售。" % int(Flower.CROPS[kind].time)
		"blue_dye": return "可在田尾染色桌染工作服，或捐給公共花園。不能出售。"
		"sugar": return "田尾花卉市集少量供應，每人每個遊戲日最多 %d 份。花園餅乾的材料。不能出售。" % Flower.SUGAR_DAILY
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
	if World.FISH.has(id):
		return "出售價　%d 鈴幣" % World.FISH[id].price
	if World.OTHER_SALES.has(id):
		return "出售價　%d 鈴幣" % World.OTHER_SALES[id]
	return "攤位未收購"
