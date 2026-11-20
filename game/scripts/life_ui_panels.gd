extends RefCounted

const World = preload("res://scripts/world.gd")
const Village = preload("res://scripts/village.gd")
const Crops = preload("res://scripts/crop_sprite_art.gd")
const LifeTheme = preload("res://scripts/life_ui_theme.gd")
const MATERIALS := ["wood", "stone", "fiber", "copper_ore", "copper_joint", "plank", "resin", "charcoal", "flour", "ochre_earth", "vein_quartz", "warm_stone"]
const BUILD_MATERIALS := ["supply_box_kit", "wood", "stone", "fiber", "sprinkler_kit", "pipe_kit", "tank_kit", "pump_kit", "sawmill_kit", "kiln_kit", "forester_kit", "conveyor_kit", "waterworks_kit", "mine_drill_kit", "mill_kit", "diversion_gate_kit", "water_tower_kit"]
const BUILD_NOTES := {
	"expedition_tent":"走訪 14 個地區後解鎖的紀念家具。訪客可查看搭建者的探險紀念。",
	"supply_box":"只有本人可以存取。清空後拆除，即可把補給箱帶走。",
	"author_sign":"供訪客查看建造者的署名。",
	"author_shelf":"展示工匠製作的樣品，靠近可讀取署名。",
	"fish_display":"靠近按互動鍵查看漁獲圖鑑與全島首位釣獲者。",
	"master_flower_bed":"農耕十級的紀念花圃，可以擺在田邊或庭院。",
	"large_sprinkler":"每天可澆灌自己種植的周圍二十四格。可手動補水或接水管，不穿牆。",
	"medium_sprinkler":"澆灌自己種植的周圍八格。可手動補水，或接水管從儲水桶供水。",
	"greenhouse_rack":"星禾送的雙層花架，可以擺在家裡或農田旁。",
	"greenhouse_roof":"蓋在自己的農田上，讓作物跨季生長。玻璃隔雨；仍需澆水。",
	"mine_drill":"放在合作礦場指定工作面旁，機頭自動對準礦脈。以木炭驅動，可接燃料與礦料輸送帶；每人最多兩台。",
	"waterworks":"接自己的水管與儲水桶，以銅礦、木材和水自動製作銅接頭；可接兩條進料帶與一條出料帶。",
	"conveyor":"靠近後互動 設定方向與物品。停用並清空後才能更改設定。",
	"forester":"靠近後互動 供應木炭與樹苗。工作站依序照顧上下左右各兩格的四個地塊。",
	"sprinkler":"照顧四鄰格。E 手動補水、啟用；接水管可由自己的水桶補水。",
	"water_pipe":"四方向連接自己的泵、桶、管和灑水器；可步行穿過。",
	"diversion_gate":"接在自己的水管中間，可步行穿過。E 切換全開、餘水或關閉，決定閘門另一側的灑水器先補、後補或不補。",
	"water_tower":"接在自己的水管上，替閘門後面的田區蓄水。儲水桶有剩水時自動補進水塔；關閉或餘水的分流閘另一側，由水塔繼續供水。",
	"water_share_plaque":"蘭陽回訪的紀念木牌，不擋路。訪客靠近按 E 可看來源；拆除會收回背包。",
	"mine_lantern":"金瓜石回訪的紀念礦燈，只是裝飾、不會照明，不擋路。訪客靠近按 E 可看來源；拆除會收回背包。",
	"tea_ware":"貓空與鶯歌回訪的紀念茶陶組，茶壺和茶杯擺在木托盤上，只是裝飾，不擋路；收回背包後也能借給渡口共餐桌泡茶。訪客按 E 可看來源。",
	"salt_basket":"臺南北門回訪的紀念鹽籃，竹編小籃裡堆著一把海鹽，只是裝飾，不擋路。訪客靠近按 E 可看來源；拆除會收回背包。",
	"water_tank":"可儲存 48 份水。E 補水；接管後補給自己的灑水器。",
	"water_pump":"放在河水兩格內的陸地。E 啟用；需接通自己的儲水桶。",
	"sawmill":"E 加工木材成木板。完成後領取；取消退回原料。",
	"charcoal_kiln":"E 將木材燒成木炭。加工中不可搬動或拆除。",
	"loom":"占地 2×2。靠近按 E，用棉球花或羊毛織布。",
	"animal_collector":"放在圈舍裡可綁定整圈，放在動物四格內可綁定單隻。裝上一個收集籃，最多自動收取六份產物。",
	"assembly_table":"占地 2×1。可把材料裝成灑水器組件，帶到選好的地點放置。",
	"dye_table":"占地 2×1，能從花材提染，也能替附近的床、桌、椅和沙發換色。",
	"clay_kiln":"占地 2×2。用鶯歌陶土和木炭燒製花盆、紅磚和屋瓦。",
	World.TERRACOTTA_ROOF.KIND:"每格用一片陶窯燒的紅陶屋瓦，鋪在自己的地板上；也能直接改鋪草編屋頂，原本的材料會退還。",
	"jam_pot":"靠近按 E，用 3 份草莓和 1 份糖熬製果醬。",
	"small_smelter":"占用 2×2 格。用銅礦、鐵礦與木炭熔煉，可排入 10 筆加工。",
	"glass_furnace":"靠近按 E，把晶砂燒成玻璃，或把脈石英熔碎成晶砂。",
	"seed_maker":"把指定作物的整株收成與一份木炭加工成種子。田尾花材請到花園留種台。",
	"mill":"公共廚房開張後解鎖。E 把小麥磨成麵粉，可排程或自動加工；輸送帶可送入小麥、帶出麵粉。"
}
const FOUNDATIONS := ["floor", "stone_floor", "path", "spring_pebble_path", "wall", "door", "window", "roof", World.TERRACOTTA_ROOF.KIND, "greenhouse_roof", World.GREENHOUSE_GLASS.XINGHE_ROOF]
const FURNITURE := ["bed", World.INDUSTRY.CEDAR_BED, World.INDUSTRY.BRAIDED_RUG, World.INDUSTRY.HOLLOW_BED, World.INDUSTRY.MUSHROOM_TABLE, World.INDUSTRY.BAMBOO_TEA_TABLE, World.INDUSTRY.PAPER_TEA_LAMP, World.INDUSTRY.MUSHROOM_STOOL, World.INDUSTRY.INDIGO_CUSHION, World.INDUSTRY.LEAF_MAT, World.INDUSTRY.SPORE_LAMP, World.INDUSTRY.ACORN_CABINET, World.INDUSTRY.HEDGEHOG_BASKET, World.WALL_FIXTURES.BARK_FRAME, World.WALL_FIXTURES.HOME_SIGN, World.WALL_FIXTURES.TOOL_BOARD, World.INDUSTRY.FOREST_ARCH, World.INDUSTRY.LEAF_DESK, World.INDUSTRY.MUSHROOM_POST, World.INDUSTRY.QUIET_BIRDHOUSE, "inn_quilt_bed", "inn_stone_footbath", "lamp", World.STAR_GARDEN_LAMP, World.RESIDENT_GOALS.GARDEN_CHAIR, "table", World.INDUSTRY.ROUNDED_TABLE, World.INDUSTRY.GRID_BOOKCASE, "chair", "long_bench", "master_bench", "spring_stone_bench", World.RESIDENT_GOALS.COTTON_SOFA, World.RESIDENT_GOALS.BAMBOO_BENCH, "sofa", "planter", "guest_wardrobe", "inn_lattice_wardrobe", World.RESIDENT_GOALS.COAST_WARDROBE, World.RESIDENT_GOALS.FOREST_WARDROBE, "inn_fabric_screen", "basic_tea_set", "festival_memorial_bell", "ceramic_eave_chime", "shell_chime", "acorn_ornament", "warm_lamp_niche", World.WALL_FIXTURES.LIFEBUOY, World.WALL_FIXTURES.BAMBOO_CURTAIN, World.WALL_FIXTURES.WATER_LISTENING_CHIME, "wood_mailbox", "sketch_easel", "rope_rack", World.POSTCARDS.RACK, World.OAR_SIGN.KIND, "towel_rack", "inn_welcome_sign", "inn_tea_table", "inn_luggage_rack", "flower_pot", "greenhouse_rack", "garden_basin", "crop_observation_desk", World.INDUSTRY.SEED_CABINET, World.INDUSTRY.AQUARIUM, World.INDUSTRY.COAST_FISH_COUNTER, World.INDUSTRY.TEA_DISPLAY_CABINET, World.INDUSTRY.TEA_SNACK_SHELF, World.INDUSTRY.IMPERFECT_TEA_PAVILION, World.INDUSTRY.COAST_AWNING, World.INDUSTRY.COAST_REGISTER, World.INDUSTRY.COAST_CART, World.INDUSTRY.BEACH_CHAIR, World.INDUSTRY.RIVERSIDE_SCREEN, World.INDUSTRY.BAMBOO_LOUNGER, World.INDUSTRY.SHELL_TABLE, World.INDUSTRY.GLASS_FLOWER_TABLE, World.INDUSTRY.VINE_ARCH, World.INDUSTRY.POT_RACK, World.ROOF_FIXTURES.HANGING_POT, World.NURSERY_BOX.KIND, "master_flower_bed", "fish_display", "author_sign", "author_shelf", "expedition_tent", "sign", "ore_display"]
const ItemArt = preload("res://scripts/inventory_item_art.gd")
const PixelTheme = preload("res://scripts/inventory_pixel_theme.gd")
const BuildThumbnail = preload("res://scripts/pixel_build_thumbnail.gd")
const HouseUI = preload("res://scripts/house_ui.gd")
const BuildFolio = preload("res://scripts/build_folio.gd")
const CookingQueueUI = preload("res://scripts/cooking_queue_ui.gd")
const ChestHistoryUI = preload("res://scripts/chest_history_ui.gd")
const STALL := Vector2i(43, 29)
const Flower = preload("res://scripts/flower_nursery.gd")
const FlowerArt = preload("res://scripts/flower_art.gd")

var modal: Control
var updates: Array[Callable] = []

func refresh(app) -> void:
	if not is_instance_valid(modal) or app.modal != modal:
		updates.clear()
		modal = null
		return
	var person: Dictionary = app.session.snapshot.get("players", {}).get(app.session.own_id, {})
	for update in updates:
		update.call(person)

func begin(app, title: String) -> VBoxContainer:
	updates.clear()
	var content: VBoxContainer = app._open_modal(title)
	modal = app.modal
	return content

func balance(app, parent: Control, portrait: String = "") -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	if not portrait.is_empty():
		add_icon(row, LifeTheme.icon(portrait))
	var amount: Label = app.label("", 20)
	row.add_child(amount)
	updates.append(func(person): amount.text = "鈴幣  %d" % int(person.get("coins", 0)))
	return row

func tabs(app, parent: VBoxContainer, names: Array) -> Array[GridContainer]:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	parent.add_child(bar)
	var group := ButtonGroup.new()
	var pages: Array[GridContainer] = []
	for index in range(names.size()):
		var page := grid(parent)
		page.visible = index == 0
		pages.append(page)
	for index in range(names.size()):
		var tab: Button = app.button(names[index], func():
			for page_index in range(pages.size()):
				pages[page_index].visible = page_index == index
		)
		tab.toggle_mode = true
		tab.button_group = group
		tab.button_pressed = index == 0
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.add_child(tab)
	return pages

func grid(parent: Control) -> GridContainer:
	var result := GridContainer.new()
	result.columns = 2
	result.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result.add_theme_constant_override("h_separation", 10)
	result.add_theme_constant_override("v_separation", 8)
	parent.add_child(result)
	return result

func card(app, parent: GridContainer, title: String, crop_id: String = "", stage: int = 3) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", LifeTheme.surface(Color("fff8e8"), Color("dac5a0"), 10, 6))
	parent.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	var index := Crops.ROWS.find(crop_id)
	var garden_row:=Crops.KITCHEN_GARDEN_ROWS.find(crop_id)
	var regional_row:=Crops.REGIONAL_ROWS.find(crop_id)
	var harvest_row:=Crops.HARVEST_ROWS.find(crop_id)
	if crop_id=="pumpkin":
		add_icon(row,preload("res://scripts/bakery_art.gd").growth_texture(stage))
	elif FlowerArt.has_crop(crop_id):
		add_icon(row, FlowerArt.crop_texture(crop_id, stage))
	elif garden_row>=0:
		add_icon(row,LifeTheme.atlas_region(Crops.KITCHEN_GARDEN_PATH,Rect2(stage*32,garden_row*32,32,32)))
	elif regional_row>=0:
		add_icon(row,LifeTheme.atlas_region(Crops.REGIONAL_PATH,Rect2(stage*32,regional_row*32,32,32)))
	elif harvest_row>=0:
		add_icon(row,LifeTheme.atlas_region(Crops.HARVEST_PATH,Rect2(stage*32,harvest_row*32,32,32)))
	elif index >= 0:
		add_icon(row, LifeTheme.atlas_region(Crops.ATLAS_PATH, Rect2(stage * 32, index * 32, 32, 32)))
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(details)
	details.add_child(app.label(title, 18))
	return details

func add_icon(parent: Control, texture: Texture2D) -> void:
	if texture == null:
		return
	var icon := TextureRect.new()
	icon.texture = texture
	icon.custom_minimum_size = Vector2(44, 44)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	parent.add_child(icon)

func inventory(app) -> void:
	var content := begin(app, "隨身背包")
	balance(app, content)
	var pages := tabs(app, content, ["全部", "素材", "種子", "收成", "其他"])
	for id in World.NAMES:
		var category := 4
		if id in MATERIALS:
			category = 1
		elif id.ends_with("_seed") or id == "sapling":
			category = 2
		elif World.CROPS.has(id) or World.FISH.has(id) or id == "egg":
			category = 3
		for page in [pages[0], pages[category]]:
			var details := card(app, page, World.NAMES[id], id.trim_suffix("_seed"), 0 if category == 2 else 3)
			var count: Label = app.label("", 15)
			details.add_child(count)
			updates.append(func(person): count.text = "持有  %d" % person.get("inventory", {}).get(id, 0))
	refresh(app)

func shop(app) -> void:
	var sign:Dictionary=app.session.snapshot.get("own_xiaoli_shop",{})
	var title:="小栗的渡口小店" if app.session.snapshot.get("picnic",false) else "小栗的種子攤"
	var content:=begin(app,str(sign.get("name",title)))
	balance(app, content, "xiaoli")
	var counter := HFlowContainer.new()
	counter.name = "ShopCounter"
	counter.add_theme_constant_override("h_separation", 8)
	counter.add_theme_constant_override("v_separation", 6)
	content.add_child(counter)
	if Village.NPCS.has("xiaoli"):
		var chat: Button = app.button("和小栗聊聊", func(): app._resident_menu("xiaoli"))
		chat.name = "XiaoliShopChat"
		counter.add_child(chat)
	if app.session.snapshot.has("own_shop_history"):
		var notebook:Button=app.button("翻開交易簿",trade_book.bind(app))
		notebook.name="ShopTradeBook"
		counter.add_child(notebook)
	var catalog := catalog_shell(app, content, ["買種子與材料", "出售"], ["radish_seed", "coins"])
	app.modal.set_meta("shop_catalog", true)
	var products := [[World.FLOUR_ITEM, World.SUGAR_ITEM] + World.CROPS.keys() + ["sapling"], World.CROPS.keys() + World.FISH.keys() + World.OTHER_SALES.keys()]
	var inventory:Dictionary=app.session.snapshot.get("players",{}).get(app.session.own_id,{}).get("inventory",{})
	for id:String in inventory:
		if int(inventory[id])>0 and World.CROP_CATALOG.quality_item(id):products[1].append(id)
	var offer: Button = app.button("", func():
		var buying: bool = catalog.page == 0
		app.session.perform("buy" if buying else "sell", STALL, catalog.selected)
	)
	offer.name = "StallOffer"
	catalog.details.add_child(offer)
	# Flower seeds stay visible but locked until the player's own chapter-3 record is complete.
	var lock_note: Label = app.label(Flower.HOME_SEED_MESSAGE, 14)
	lock_note.name = "StallLockReason"
	lock_note.add_theme_color_override("font_color", Color("9c4b32"))
	lock_note.hide()
	catalog.details.add_child(lock_note)
	for page in range(products.size()):
		for id in products[page]:
			var item: String = id + "_seed" if page == 0 and id != "sapling" and id != World.FLOUR_ITEM and id != World.SUGAR_ITEM else id
			var entry := add_entry(app, catalog, page, id, World.NAMES[item], item_icon(item))
			entry.name = ("StallBuy_" if page == 0 else "StallSell_") + id
	updates.append(func(person):
		var locked_flowers := stall_flowers_locked(app.session.snapshot)
		for id in Flower.FLOWERS:
			var entry: Button = catalog.entries[0].get(id)
			if entry == null:continue
			entry.modulate = Color(1, 1, 1, 0.55) if locked_flowers else Color.WHITE
			entry.tooltip_text = Flower.HOME_SEED_MESSAGE if locked_flowers else World.NAMES[id + "_seed"]
	)
	updates.append(func(person):
		var id: String = catalog.selected
		var buying: bool = catalog.page == 0
		var is_flour: bool = buying and id == World.FLOUR_ITEM
		var is_sugar: bool = buying and id == World.SUGAR_ITEM
		var item: String = id + "_seed" if buying and id != "sapling" and not is_flour and not is_sugar else id
		var locked: bool = buying and id in Flower.FLOWERS and stall_flowers_locked(app.session.snapshot)
		lock_note.visible = locked
		offer.visible = not locked
		var flour_left: int = World.flour_left(person, float(app.session.snapshot.get("time", 0.0)))
		var sugar_left: int = World.sugar_left(person, float(app.session.snapshot.get("time", 0.0)))
		var price: int = World.FLOUR_PRICE if is_flour else World.SUGAR_PRICE if is_sugar else 20 if id == "sapling" else World.CROPS[id].seed_price if buying else shop_sale_price(id)
		var held: int = person.get("inventory", {}).get(item, 0)
		catalog.title.text = World.NAMES[item]
		catalog.icon.texture = item_icon(item)
		catalog.description.text = "持有 %d · 單價 %d 鈴幣" % [held, price]
		if locked:
			catalog.description.text = "持有 %d · 尚未進貨" % held
		if is_flour:
			catalog.description.text += "\n今日還有 %d / %d 份。換日補貨。" % [flour_left, World.FLOUR_DAILY]
			offer.tooltip_text = "磨坊啟用前，可用一份麵粉在公共廚房灶台烤一個麵包。"
		elif is_sugar:
			catalog.description.text += "\n今日還有 %d / %d 份。換日補貨。不能出售。" % [sugar_left, World.SUGAR_DAILY]
			offer.tooltip_text = "冬季甜菜開放前的少量供應：暖薑茶、草莓果醬、花園餅乾要用糖；之後可自己熬製甜菜糖。"
		else:
			offer.tooltip_text = ""
		if buying and not is_flour and not is_sugar and id != "sapling":
			catalog.description.text += "\n"+crop_season_hint(id)
		if not buying:
			var snapshot:Dictionary=app.session.snapshot
			if not snapshot.get("chapter_one",{}).get("shipped",false):
				catalog.description.text += "\n第一章出貨請用渡口出貨箱。"
			if id in ["radish","wheat"] and not snapshot.get("picnic",false):
				catalog.description.text += "\n這裡會出售全部。野餐需留蘿蔔和小麥各兩份。"
		offer.disabled = int(person.get("coins", 0)) < price or (is_flour and flour_left <= 0) or (is_sugar and sugar_left <= 0) if buying else held == 0
		offer.text = ("今日售完" if (is_flour and flour_left <= 0) or (is_sugar and sugar_left <= 0) else "鈴幣不足" if offer.disabled else "買 1 份 · %d 鈴幣" % price) if buying else "出售全部 %d 件 · 共 %d 鈴幣" % [held, held * price]
	)
	select_entry(app, catalog, 0, "radish")

func trade_book(app,history:bool=false,back:Callable=Callable()) -> void:
	var snapshot:Dictionary=app.session.snapshot
	if not snapshot.has("own_shop_history"):return
	var body:=begin(app,"小栗的交易簿")
	app.modal.set_meta("shop_catalog",true)
	var nav:=HBoxContainer.new()
	body.add_child(nav)
	var prices:Button=app.button("作物價目",trade_book.bind(app,false,back))
	var recent:Button=app.button("我的交易",trade_book.bind(app,true,back))
	prices.name="ShopTradePrices"
	recent.name="ShopTradeHistory"
	prices.disabled=not history
	recent.disabled=history
	nav.add_child(prices)
	nav.add_child(recent)
	nav.add_child(app.button("回到關係事件" if back.is_valid() else "回到種子攤",back if back.is_valid() else app._shop))
	var scroll:=ScrollContainer.new()
	scroll.name="ShopTradeRows"
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y=280
	body.add_child(scroll)
	var page:=VBoxContainer.new()
	page.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	scroll.add_child(page)
	if history:
		var rows:Array=snapshot.own_shop_history
		var first:Dictionary=snapshot.get("own_first_shop_trade",{})
		var keepsake:=PanelContainer.new()
		keepsake.name="ShopTradePinned"
		keepsake.add_theme_stylebox_override("panel",PixelTheme.paper_style())
		page.add_child(keepsake)
		var remembered:=VBoxContainer.new()
		remembered.add_theme_constant_override("separation",8)
		keepsake.add_child(remembered)
		remembered.add_child(app.label("小栗幫你留的第一筆買賣",19))
		if first.has("sale"):trade_receipt(app,remembered,first.sale,"首次賣作物")
		if first.has("seed"):trade_receipt(app,remembered,first.seed,"接著買的當季種子")
		if not first.has_all(["sale","seed"]):
			var missing:="當時的兩筆交易" if first.is_empty() else ("當時買的種子" if first.has("sale") else "當時賣的作物")
			var notice:Label=app.label("這個舊存檔沒有標記%s。"%missing,14)
			notice.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
			remembered.add_child(notice)
		page.add_child(app.label("近期交易 · 最多 10 筆",16))
		if rows.is_empty():page.add_child(app.label("近期沒有可顯示的種子攤或出貨箱交易。",15))
		for entry:Dictionary in rows:
			trade_receipt(app,page,entry)
			page.add_child(HSeparator.new())
		return
	page.add_child(app.label("每份單價（鈴幣）",16))
	for id:String in World.CROPS:
		var crop:Dictionary=World.CROPS[id]
		var row:=HBoxContainer.new()
		page.add_child(row)
		add_icon(row,item_icon(id))
		var name_label:Label=app.label(crop.name,16)
		name_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		var seed_price:="尚未進貨" if id in Flower.FLOWERS and stall_flowers_locked(snapshot) else "%d"%crop.seed_price
		var price:Label=app.label("種子 %s　｜　收成售價 %d"%[seed_price,shop_sale_price(id)],15)
		price.size_flags_horizontal=Control.SIZE_SHRINK_END
		price.autowrap_mode=TextServer.AUTOWRAP_OFF
		row.add_child(price)

func trade_receipt(app,parent:VBoxContainer,entry:Dictionary,heading:String="") -> void:
	var description:=PackedStringArray()
	for item:String in entry.items:
		description.append("%s ×%d"%[World.NAMES.get(item,item),abs(int(entry.items[item]))])
	var caption:=str({"buy":"購入","sell":"攤位售出","ship":"出貨"}.get(entry.action,""))
	if not heading.is_empty():caption=heading+" · "+caption
	var row:=HBoxContainer.new()
	row.add_theme_constant_override("separation",8)
	parent.add_child(row)
	add_icon(row,item_icon(str(entry.items.keys()[0])) if not entry.items.is_empty() else item_icon("coins"))
	var receipt:Label=app.label("第 %d 日 · %s\n%s"%[int(World.WEATHER.day_index(entry.time))+1,caption,"、".join(description)],15)
	receipt.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	receipt.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	row.add_child(receipt)
	var coins:Label=app.label("%+d 鈴幣"%entry.coins,17)
	coins.add_theme_color_override("font_color",Color("48694a") if int(entry.coins)>=0 else Color("925230"))
	coins.size_flags_horizontal=Control.SIZE_SHRINK_END
	coins.autowrap_mode=TextServer.AUTOWRAP_OFF
	coins.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	row.add_child(coins)

## Own chapter-3 record from the per-recipient snapshot (session own_view).
static func crop_season_hint(id: String) -> String:
	if id=="mist_tea":return "霧竹溪谷茶圃全年可栽培，採收後原株可再生。"
	if id=="rice":return "夏秋生長 · 宜蘭水圳東西兩岸的水田。"
	if id=="star_mushroom":return "金瓜石第五層・洞內菌床，全年可栽培。"
	var seasons: Array = World.CROP_SEASONS.get(id, [])
	var names := PackedStringArray()
	for season in seasons:
		names.append(World.WEATHER.SEASON_LABELS[season])
	var hint := "家園生長季節 · "+("四季" if names.is_empty() else "、".join(names))
	if id in Flower.FLOWERS:
		hint += "\n田尾育苗床全年可生長。"
	return hint

static func stall_flowers_locked(snapshot: Dictionary) -> bool:
	var record = snapshot.get("flower_nursery", {}).get("own", {}).get("own_record", {})
	return not (record is Dictionary and record.get("complete", false) == true)

## Flower IDs use the dedicated flower atlas; a missing texture stays null (name only).
static func item_icon(id: String) -> Texture2D:
	if FlowerArt.has_item(id):return FlowerArt.item_texture(id)
	return ItemArt.icon(id)

static func shop_sale_price(id: String) -> int:
	if World.CROP_CATALOG.quality_item(id):return World.CROP_CATALOG.quality_price(id)
	if World.CROPS.has(id):return World.CROPS[id].price
	if World.FISH.has(id):return World.FISH[id].price
	return World.OTHER_SALES[id]

func build_menu(app, preferred_piece:String="", guide:Dictionary={}) -> void:
	# Dedicated builder folio (BuildFolio / BuildShelf / BuildRecipe / BuildPlace);
	# the shared catalog_shell below stays as-is for shop, seeds, cooking and chests.
	var catalog: Dictionary = BuildFolio.open(self, app, {"notes": BUILD_NOTES,
		"foundations": FOUNDATIONS, "furniture": FURNITURE, "materials": BUILD_MATERIALS,
		"guide":guide,"guide_piece":preferred_piece})
	var selected_piece: String = preferred_piece if not preferred_piece.is_empty() else app.arg_value("capture-build", "")
	if World.BUILD.has(selected_piece):
		for page in range(1, catalog.pages.size()):
			if catalog.entries[page].has(selected_piece):
				select_entry(app, catalog, page, selected_piece)
				reveal_initial_build_slot(catalog, page, selected_piece)
				break

func reveal_initial_build_slot(catalog:Dictionary,page:int,id:String) -> void:
	var scroll:ScrollContainer=catalog.build_scroll
	# The initially shown shelf is fitted and reflowed after the modal opens.
	var tree:=scroll.get_tree()
	await tree.process_frame
	await tree.process_frame
	if not is_instance_valid(scroll) or not scroll.is_inside_tree() or catalog.page!=page or catalog.selected!=id:return
	var entry:Control=catalog.entries[page][id]
	scroll.ensure_control_visible(entry)

func catalog_shell(app, parent: VBoxContainer, labels: Array, tab_icons: Array = []) -> Dictionary:
	app.modal.set_meta("catalog", true)
	app.modal.theme = PixelTheme.make(app.modal.theme if app.modal.theme else app.theme())
	app.modal.add_theme_stylebox_override("panel", PixelTheme.frame_style())
	app.modal.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var shell := parent.get_parent().get_parent()
	if parent.get_parent() is ScrollContainer and shell is VBoxContainer:
		for child in shell.get_children():
			if child is Label:
				child.autowrap_mode = TextServer.AUTOWRAP_OFF
			elif child is HBoxContainer:
				for heading in child.get_children():
					if heading is Label:
						heading.autowrap_mode = TextServer.AUTOWRAP_OFF
	app._layout_preview.call_deferred()
	var bar := HBoxContainer.new()
	parent.add_child(bar)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	parent.add_child(body)
	var tray := PanelContainer.new()
	tray.add_theme_stylebox_override("panel", PixelTheme.paper_style())
	tray.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(tray)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 330
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	tray.add_child(scroll)
	var stack := VBoxContainer.new()
	stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(stack)
	var details_paper := PanelContainer.new()
	details_paper.add_theme_stylebox_override("panel", PixelTheme.paper_style())
	details_paper.custom_minimum_size.x = 240
	body.add_child(details_paper)
	var details := VBoxContainer.new()
	details.add_theme_constant_override("separation", 8)
	details_paper.add_child(details)
	var icon := item_picture(null, 96)
	details.add_child(icon)
	var title: Label = app.label("", 21)
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	details.add_child(title)
	var description: Label = app.label("", 15)
	description.custom_minimum_size.x = 210
	details.add_child(description)
	var catalog := {"pages": [], "buttons": [], "entries": [], "selected": "", "page": 0,
		"details": details, "icon": icon, "title": title, "description": description, "bar":bar,"body":body}
	var colors := [Color("edce8d"), Color("b6c39a"), Color("dcae92"), Color("a4bdc2")]
	var outer := parent.get_parent() as ScrollContainer
	if outer != null:
		var fit := func():
			if not is_instance_valid(scroll):return
			var reserve := float(bar.size.y) + 28.0
			for child in parent.get_children():
				if child != bar and child != body and child is Control and child.visible:
					# A just-shown child may not be sorted yet; trust its minimum then.
					reserve += maxf(child.size.y, child.get_combined_minimum_size().y) + parent.get_theme_constant("separation")
			var available := maxf(232.0, outer.size.y - reserve)
			if absf(scroll.custom_minimum_size.y - available) > 1.0:
				scroll.custom_minimum_size.y = available
		outer.resized.connect(fit)
		fit.call_deferred()
		catalog["fit"] = fit
	for index in labels.size():
		var page := grid(stack)
		page.columns = 4
		page.visible = index == 0
		catalog.pages.append(page)
		catalog.entries.append({})
		var tab: Button = app.button(labels[index], func():
			var options: Dictionary = catalog.entries[index]
			var id: String = catalog.selected if options.has(catalog.selected) else options.keys()[0]
			select_entry(app, catalog, index, id)
			scroll.set_deferred("scroll_vertical", 0)
		)
		tab.toggle_mode = true
		if index < tab_icons.size():
			tab.icon = ItemArt.icon(tab_icons[index])
			tab.add_theme_constant_override("icon_max_width", 24)
		tab.self_modulate = colors[index]
		bar.add_child(tab)
		catalog.buttons.append(tab)
	return catalog

func select_entry(app, catalog: Dictionary, page: int, id: String) -> void:
	catalog.page = page
	catalog.selected = id
	# Shared catalogs keep light-on-green selected captions; the build folio
	# passes its own (its selected slot is a light badge).
	var lit: Color = catalog.get("caption_selected", Color("fff3cf"))
	var dim: Color = catalog.get("caption_normal", Color("3d422d"))
	for index in catalog.pages.size():
		catalog.pages[index].visible = index == page
		catalog.buttons[index].set_pressed_no_signal(index == page)
		for item in catalog.entries[index]:
			var entry: Button = catalog.entries[index][item]
			entry.set_pressed_no_signal(item == id)
			var caption: Label = entry.get_child(0)
			caption.add_theme_color_override("font_color", lit if item == id else dim)
	refresh(app)
	if catalog.has("reveal_slot"):
		catalog.reveal_slot.call_deferred(catalog.entries[page][id])
	elif catalog.has("build_scroll"):
		catalog.build_scroll.call_deferred("ensure_control_visible",catalog.entries[page][id])

func add_entry(app, catalog: Dictionary, page: int, id: String, title: String, texture: Texture2D = null) -> Button:
	var entry := Button.new()
	entry.theme_type_variation = &"ItemSlot"
	entry.custom_minimum_size = Vector2(104, 112)
	entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	entry.toggle_mode = true
	entry.tooltip_text = title
	entry.pressed.connect(func(): select_entry(app, catalog, page, id))
	catalog.pages[page].add_child(entry)
	catalog.entries[page][id] = entry
	var caption := Label.new()
	caption.text = title
	caption.add_theme_font_size_override("font_size", 15)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	entry.add_child(caption)
	caption.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	caption.offset_top = -31
	if texture != null:
		var picture := item_picture(texture, 64)
		entry.add_child(picture)
		picture.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		picture.offset_left = -32
		picture.offset_top = 8
	return entry

func item_picture(texture: Texture2D, pixels: int) -> TextureRect:
	var result := TextureRect.new()
	result.texture = texture
	result.custom_minimum_size = Vector2(pixels, pixels)
	result.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	result.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	result.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result

func build_picture(parent: Control, kind: String, zoom: int) -> Control:
	var frame := Control.new()
	frame.custom_minimum_size = Vector2(32, 48) * zoom
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(frame)
	var picture := BuildThumbnail.new()
	picture.kind = kind
	picture.scale = Vector2.ONE * zoom
	frame.add_child(picture)
	return frame

func seed_menu(app) -> void:
	var seed_action:="seed_area" if app.selected=="seed_area" else "seed"
	var content := begin(app, "選擇種子")
	var catalog := catalog_shell(app, content, ["種子與樹苗"])
	app.modal.set_meta("shop_catalog", true)
	for kind in World.CROPS.keys() + ["sapling"]:
		var id: String = kind if kind == "sapling" else kind + "_seed"
		add_entry(app, catalog, 0, kind, World.NAMES[id], item_icon(id))
	var choose: Button = app.button("選擇種子", func():
		if catalog.selected == "sapling":
			app._select_tool("plant_tree")
		else:
			app.crop = catalog.selected
			app._select_tool(seed_action)
		app._close_modal()
	)
	choose.name="SeedConfirm"
	catalog.details.add_child(choose)
	updates.append(func(person):
		var tree: bool = catalog.selected == "sapling"
		var id: String = "sapling" if tree else catalog.selected + "_seed"
		var held: int = person.get("inventory", {}).get(id, 0)
		var timing := "種在空地，三分鐘長成，不需澆水。" if tree else "先鋤地、播種與澆水，約 %d 秒成熟。" % World.CROPS[catalog.selected].time
		if not tree:
			timing += "\n"+crop_season_hint(catalog.selected)
		catalog.title.text = World.NAMES[id]
		catalog.icon.texture = item_icon(id)
		catalog.description.text = "持有 %d\n%s" % [held, timing]
		choose.text = "選擇樹苗  %s"%app.binding_label("plant_tree") if tree else "選擇種子"
	)
	var tutorial:=World.CHAPTER_ONE.first_crop_step(app.session.snapshot,app.session.own_id)
	var initial:String=tutorial.get("seed",app.crop) if tutorial.get("id")=="sow" else app.crop
	select_entry(app, catalog, 0, initial)

func cook(app, cell: Vector2i) -> void:
	# The queue workbench owns its own refresh (main._state_changed), so drop
	# any closures from the previous life panel before handing over.
	updates.clear()
	modal = null
	CookingQueueUI.open(app, cell)

func acorn_cabinet(app, cell:Vector2i) -> void:
	var key:=World.key(cell)
	var content:=begin(app,"橡果收納櫃")
	app.modal.set_meta("life_modal_layout","acorn_cabinet")
	app.modal.theme=PixelTheme.make(app.modal.theme if app.modal.theme else app.theme())
	app.modal.add_theme_stylebox_override("panel",PixelTheme.frame_style())
	app._layout_preview.call_deferred()
	var summary:Label=app.label("",16)
	summary.name="CabinetSummary"
	content.add_child(summary)
	var body:=HBoxContainer.new()
	body.add_theme_constant_override("separation",12)
	content.add_child(body)
	var slot_grid:=grid(body)
	slot_grid.name="CabinetSlots"
	slot_grid.columns=4
	slot_grid.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	slot_grid.add_theme_constant_override("h_separation",4)
	slot_grid.add_theme_constant_override("v_separation",4)
	var state:={"item":"","carried":[]}
	var slots:Array[Button]=[]
	var slot_script=preload("res://scripts/item_slot.gd")
	for index in World.INDUSTRY.CABINET_SLOTS:
		var slot:Button=slot_script.new()
		slot.name="CabinetSlot%d"%index
		slot.item_selected.connect(func(item:String):
			state.item=item
			refresh(app))
		slot_grid.add_child(slot)
		slots.append(slot)
	var panel:=PanelContainer.new()
	panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel",PixelTheme.paper_style())
	body.add_child(panel)
	var details:=VBoxContainer.new()
	details.add_theme_constant_override("separation",8)
	panel.add_child(details)
	details.add_child(app.label("從背包選物品",15))
	var choose:=OptionButton.new()
	choose.name="CabinetInventory"
	choose.fit_to_longest_item=false
	choose.item_selected.connect(func(index:int):
		state.item=str(choose.get_item_metadata(index)) if index>0 else ""
		refresh(app))
	details.add_child(choose)
	details.add_child(HSeparator.new())
	var title:Label=app.label("選擇要存取的物品",18)
	title.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	details.add_child(title)
	var counts:Label=app.label("",15)
	details.add_child(counts)
	var amount:=LineEdit.new()
	amount.name="CabinetAmount"
	amount.text="1"
	amount.placeholder_text="件數"
	amount.max_length=10
	amount.text_changed.connect(func(_text:String):refresh(app))
	amount.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var quantity_row:=HBoxContainer.new()
	quantity_row.add_theme_constant_override("separation",8)
	details.add_child(quantity_row)
	quantity_row.add_child(app.label("件數",15))
	quantity_row.add_child(amount)
	var controls:=HBoxContainer.new()
	details.add_child(controls)
	var deposit:Button=app.button("存入",func():
		app.session.perform("deposit_exact",cell,"%s:%d"%[state.item,World.chest_exact_quantity(amount.text)]))
	deposit.name="CabinetDeposit"
	deposit.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	controls.add_child(deposit)
	var withdraw:Button=app.button("取出",func():
		app.session.perform("withdraw_exact",cell,"%s:%d"%[state.item,World.chest_exact_quantity(amount.text)]))
	withdraw.name="CabinetWithdraw"
	withdraw.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	controls.add_child(withdraw)
	var policy:Label=app.label("",15)
	policy.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	details.add_child(policy)
	var access:Button=app.button("",func():
		var box:Dictionary=app.session.snapshot.get("objects",{}).get(key,{})
		app.session.perform(World.INDUSTRY.CABINET_ACCESS,cell,"owner" if box.get("cabinet_shared",false) else "island"))
	access.name="CabinetAccess"
	details.add_child(access)
	updates.append(func(person:Dictionary):
		var box:Dictionary=app.session.snapshot.get("objects",{}).get(key,{})
		var exists:bool=box.get("type")==World.INDUSTRY.ACORN_CABINET
		var locked:bool=not exists or box.get("locked",false)
		var shared:bool=box.get("cabinet_shared",false)
		var stored:Dictionary={} if locked else box.get("items",{})
		var held:Dictionary=person.get("inventory",{})
		var stocked:Array=stored.keys()
		stocked.sort()
		summary.text="已用 %d / %d 格"%[stocked.size(),World.INDUSTRY.CABINET_SLOTS] if not locked else ("私人收納 · 僅櫃主可查看" if exists else "收納櫃已搬離")
		for index in slots.size():
			var slot=slots[index]
			var id:String=stocked[index] if index<stocked.size() else ""
			var count:=int(stored.get(id,0))
			if slot.item_id!=id or slot.count!=count or slot.quantity.visible!=(not id.is_empty()):
				slot.configure(id,item_icon(id) if not id.is_empty() else null,count,World.NAMES.get(id,""))
				slot.quantity.visible=not id.is_empty()
			slot.disabled=id.is_empty()
			slot.set_selected(not id.is_empty() and id==state.item)
		var carried:Array=[]
		if not locked:
			for id:String in held:
				if int(held[id])>0 and World.NAMES.has(id):carried.append(id)
			carried.sort()
		if state.carried!=carried or choose.item_count==0:
			state.carried=carried
			choose.clear()
			choose.add_item("選擇物品" if not carried.is_empty() else "無可存入物品")
			for id:String in carried:
				choose.add_item(World.NAMES[id])
				choose.set_item_metadata(choose.item_count-1,id)
		choose.select(carried.find(state.item)+1)
		choose.disabled=locked or carried.is_empty()
		var selected:String="" if locked else state.item
		var quantity:=World.chest_exact_quantity(amount.text)
		var on_hand:=int(held.get(selected,0))
		var inside:=int(stored.get(selected,0))
		var full:bool=stocked.size()>=World.INDUSTRY.CABINET_SLOTS and inside==0
		title.text=World.NAMES.get(selected,"選擇要存取的物品")
		counts.text="背包 %d · 櫃內 %d"%[on_hand,inside] if not selected.is_empty() else ""
		amount.editable=not locked and not selected.is_empty()
		deposit.disabled=locked or quantity==0 or quantity>on_hand or full
		deposit.tooltip_text="櫃內 16 格已滿。先取完一格，或加入既有物品。" if full else ""
		withdraw.disabled=locked or quantity==0 or quantity>inside
		access.visible=exists and box.get("owner")==app.session.own_id
		access.text="設為私人" if shared else "開放同島共用"
		policy.text="同島玩家可存取櫃內物品。" if shared else "只有櫃主可以存取。"
	)
	refresh(app)

## T11 茶屋點心架: two labelled tiers. Each row shows the real stored food (icon, name, count);
## every button only sends a request, the server decides. Keyboard: Tab/arrows, Enter/Space, E or Esc closes.
func tea_snack_shelf(app, cell:Vector2i) -> void:
	var key:String=World.key(cell)
	var content:VBoxContainer=begin(app,"茶屋點心架")
	app.modal.set_meta("life_modal_layout","tea_snack_shelf")
	app.modal.theme=PixelTheme.make(app.modal.theme if app.modal.theme else app.theme())
	app.modal.add_theme_stylebox_override("panel",PixelTheme.frame_style())
	app._layout_preview.call_deferred()
	var summary:Label=app.label("",16)
	summary.name="SnackSummary"
	content.add_child(summary)
	var tier_row:=HBoxContainer.new()
	tier_row.add_theme_constant_override("separation",12)
	content.add_child(tier_row)
	var picker:=OptionButton.new()
	picker.name="SnackInventory"
	var amount:=LineEdit.new()
	amount.name="SnackAmount"
	var state:Dictionary={"item":"","carried":[],"sig":""}
	var tiers:Array[Dictionary]=[]
	var tier_count:int=World.INDUSTRY.SNACK_TIER_NAMES.size()
	for tier in tier_count:
		var panel:=PanelContainer.new()
		panel.name="SnackTier%d"%tier
		panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		panel.add_theme_stylebox_override("panel",PixelTheme.paper_style())
		tier_row.add_child(panel)
		var column:=VBoxContainer.new()
		column.add_theme_constant_override("separation",6)
		panel.add_child(column)
		var heading:Label=app.label(str(World.INDUSTRY.SNACK_TIER_NAMES[tier]),18)
		heading.name="SnackTierTitle%d"%tier
		column.add_child(heading)
		var rows:Array[Dictionary]=[]
		for slot in World.INDUSTRY.SNACK_TIER_KINDS:
			var line:=HBoxContainer.new()
			line.name="SnackRow_%d_%d"%[tier,slot]
			line.add_theme_constant_override("separation",6)
			column.add_child(line)
			var icon:=TextureRect.new()
			icon.name="SnackIcon_%d_%d"%[tier,slot]
			icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
			icon.custom_minimum_size=Vector2(28,28)
			line.add_child(icon)
			var title:Label=app.label("",15)
			title.name="SnackName_%d_%d"%[tier,slot]
			title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			title.autowrap_mode=TextServer.AUTOWRAP_OFF
			line.add_child(title)
			var count:Label=app.label("",15)
			count.name="SnackCount_%d_%d"%[tier,slot]
			line.add_child(count)
			var take_one:Button=app.button("取 1",func():_snack_take(app,cell,key,tier,slot,false))
			take_one.name="SnackTake_%d_%d"%[tier,slot]
			take_one.focus_mode=Control.FOCUS_ALL
			line.add_child(take_one)
			var take_all:Button=app.button("全取",func():_snack_take(app,cell,key,tier,slot,true))
			take_all.name="SnackTakeAll_%d_%d"%[tier,slot]
			take_all.focus_mode=Control.FOCUS_ALL
			line.add_child(take_all)
			rows.append({"line":line,"icon":icon,"title":title,"count":count,"one":take_one,"all":take_all})
		var empty:Label=app.label("尚未放點心",15)
		empty.name="SnackEmpty%d"%tier
		column.add_child(empty)
		var spacer:=Control.new()
		spacer.size_flags_vertical=Control.SIZE_EXPAND_FILL
		column.add_child(spacer)
		var put:Button=app.button("存入"+str(World.INDUSTRY.SNACK_TIER_NAMES[tier]),func():
			app.session.perform(World.INDUSTRY.SNACK_PUT,cell,"%d:%s:%d"%[tier,str(state.item),World.chest_exact_quantity(amount.text)]))
		put.name="SnackDeposit%d"%tier
		put.focus_mode=Control.FOCUS_ALL
		column.add_child(put)
		tiers.append({"rows":rows,"empty":empty,"put":put})
	var controls:=PanelContainer.new()
	controls.add_theme_stylebox_override("panel",PixelTheme.paper_style())
	content.add_child(controls)
	var details:=VBoxContainer.new()
	details.add_theme_constant_override("separation",8)
	controls.add_child(details)
	var quantity_row:=HBoxContainer.new()
	quantity_row.add_theme_constant_override("separation",8)
	details.add_child(quantity_row)
	picker.fit_to_longest_item=false
	picker.focus_mode=Control.FOCUS_ALL
	picker.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	picker.item_selected.connect(func(index:int):
		state.item=str(picker.get_item_metadata(index)) if index>0 else ""
		refresh(app))
	quantity_row.add_child(picker)
	var quantity_label:Label=app.label("件數",15)
	quantity_label.size_flags_horizontal=Control.SIZE_SHRINK_END
	quantity_label.autowrap_mode=TextServer.AUTOWRAP_OFF
	quantity_row.add_child(quantity_label)
	amount.text="1"
	amount.placeholder_text="件數"
	amount.max_length=3
	amount.custom_minimum_size.x=64
	amount.expand_to_text_length=false
	amount.text_changed.connect(func(_text:String):refresh(app))
	quantity_row.add_child(amount)
	var access_row:=HBoxContainer.new()
	access_row.add_theme_constant_override("separation",8)
	details.add_child(access_row)
	var policy:Label=app.label("",15)
	policy.name="SnackPolicy"
	policy.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	policy.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	access_row.add_child(policy)
	var access:Button=app.button("",func():
		var box:Dictionary=app.session.snapshot.get("objects",{}).get(key,{})
		app.session.perform(World.INDUSTRY.CABINET_ACCESS,cell,"owner" if box.get("cabinet_shared",false) else "island"))
	access.name="SnackAccess"
	access.focus_mode=Control.FOCUS_ALL
	access_row.add_child(access)
	updates.append(func(person:Dictionary):
		var box:Dictionary=app.session.snapshot.get("objects",{}).get(key,{})
		var exists:bool=box.get("type")==World.INDUSTRY.TEA_SNACK_SHELF
		var locked:bool=not exists or box.get("locked",false)
		var shared:bool=box.get("cabinet_shared",false)
		var held:Dictionary=person.get("inventory",{})
		var foods:Array=[]
		if not locked:
			for id:String in held:
				if int(held[id])>0 and World.NAMES.has(id) and World.INDUSTRY.snack_food(id,World.RECIPES):foods.append(id)
			foods.sort()
		var signature:PackedStringArray=[]
		for id:String in foods:signature.append("%s:%d"%[id,int(held[id])])
		if str(state.sig)!="|".join(signature) or picker.item_count==0:
			state.sig="|".join(signature)
			state.carried=foods
			picker.clear()
			picker.add_item("選擇點心" if not foods.is_empty() else "背包裡沒有可存的料理")
			for id:String in foods:
				picker.add_item("%s ×%d"%[World.NAMES[id],int(held[id])])
				picker.set_item_metadata(picker.item_count-1,id)
		var carried_now:Array=state.carried
		var selected:String="" if locked else str(state.item)
		if not carried_now.has(selected):selected=""
		state.item=selected
		picker.select(carried_now.find(selected)+1)
		picker.disabled=locked or foods.is_empty()
		var quantity:int=World.chest_exact_quantity(amount.text)
		var on_hand:int=int(held.get(selected,0))
		amount.editable=not locked and not selected.is_empty()
		var totals:PackedStringArray=[]
		for tier in tier_count:
			var items:Dictionary={} if locked else World.INDUSTRY.snack_tier(box,tier)
			var ids:Array[String]=World.INDUSTRY.snack_ids(items)
			totals.append("%s %d 份"%[World.INDUSTRY.SNACK_TIER_NAMES[tier],World.INDUSTRY.snack_tier_total(items)])
			var entry:Dictionary=tiers[tier]
			var rows:Array=entry.rows
			for slot in rows.size():
				var row:Dictionary=rows[slot]
				var id:String=ids[slot] if slot<ids.size() else ""
				var line:Control=row.line
				line.visible=not id.is_empty()
				if id.is_empty():continue
				var icon:TextureRect=row.icon
				var title:Label=row.title
				var count:Label=row.count
				icon.texture=item_icon(id)
				title.text=str(World.NAMES.get(id,id))
				count.text="×%d"%int(items[id])
			var empty:Label=entry.empty
			empty.visible=ids.is_empty()
			empty.text="尚未放點心" if exists and not locked else ("這座點心架目前只有主人能存取" if exists else "點心架已搬離")
			var stored:int=int(items.get(selected,0))
			var kinds_full:bool=ids.size()>=World.INDUSTRY.SNACK_TIER_KINDS and stored==0
			var put:Button=entry.put
			put.disabled=locked or selected.is_empty() or quantity==0 or quantity>on_hand or kinds_full or stored+quantity>World.INDUSTRY.SNACK_TIER_LIMIT
			put.tooltip_text="這一層已放滿 %d 種點心。"%World.INDUSTRY.SNACK_TIER_KINDS if kinds_full and not selected.is_empty() else ""
		summary.text="　".join(totals) if not locked else ("私人點心架 · 僅主人可存取" if exists else "點心架已搬離")
		access.visible=exists and box.get("owner")==app.session.own_id
		access.text="設為私人" if shared else "開放同島共用"
		policy.text="同島玩家可存取點心架。" if shared else "只有主人可以存取。"
	)
	refresh(app)
	picker.grab_focus.call_deferred()

func _snack_take(app, cell:Vector2i, key:String, tier:int, slot:int, everything:bool) -> void:
	var box:Dictionary=app.session.snapshot.get("objects",{}).get(key,{})
	var items:Dictionary=World.INDUSTRY.snack_tier(box,tier)
	var ids:Array[String]=World.INDUSTRY.snack_ids(items)
	if slot>=ids.size():return
	var take:int=int(items[ids[slot]]) if everything else 1
	app.session.perform(World.INDUSTRY.SNACK_TAKE,cell,"%d:%s:%d"%[tier,ids[slot],take])

func chest_history(app, cell: Vector2i) -> void:
	var content := begin(app, "木箱操作紀錄")
	var view := ChestHistoryUI.build(app, func(): app._chest(cell))
	content.add_child(view.root)
	view.back.grab_focus()
	var key_text := World.key(cell)
	var session = app.session
	var region: String = session.snapshot.get("region_id", "home")
	var allowed := func() -> bool:
		if session.snapshot.get("region_id", "home") != region:
			return false
		var box: Dictionary = session.snapshot.get("objects", {}).get(key_text, {})
		return World.BOX_CAPACITY.applies(box.get("type", "")) and (not box.get("locked", false) or box.get("guest_withdraw", false))
	var action := World.SAVE_SCHEMA.CHEST_HISTORY.READ_ACTION
	var sequence: int = session.counter + 1
	var reply := func(number: int, kind: String, result: Dictionary) -> void:
		if number != sequence or kind != action or not allowed.call():
			return
		ChestHistoryUI.refresh(view, result.get("rows", []), "" if result.ok else str(result.message))
	session.action_completed.connect(reply)
	view.root.tree_exiting.connect(func():
		if is_instance_valid(session) and session.action_completed.is_connected(reply):
			session.action_completed.disconnect(reply)
	)
	updates.append(func(_person):
		if not allowed.call() and view.status.text != ChestHistoryUI.MESSAGES[ChestHistoryUI.DENIED]:
			ChestHistoryUI.refresh(view, [], ChestHistoryUI.DENIED)
	)
	if allowed.call():
		session.perform(action, cell)
	else:
		ChestHistoryUI.refresh(view, [], ChestHistoryUI.DENIED)

func chest(app, cell: Vector2i) -> void:
	var key: String = World.key(cell)
	var initial: Dictionary = app.session.snapshot.get("objects", {}).get(key, {})
	var private_box: bool = initial.get("type") in World.PRIVATE_BOXES
	var wooden: bool = World.BOX_CAPACITY.applies(initial.get("type", ""))
	var content := begin(app, ("私人木箱" if wooden else "私人箱") if private_box else "共用木箱")
	var chest_modal:Control=app.modal
	var catalog := catalog_shell(app, content, ["箱內物品"])
	var floor_notice:Label=app.label(World.PLOT_PERMISSIONS.MSG_SHARED_CHEST_FLOOR,18)
	floor_notice.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	floor_notice.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	floor_notice.custom_minimum_size.y=64
	content.add_child(floor_notice)
	floor_notice.hide()
	catalog.icon.custom_minimum_size=Vector2(72,72)
	catalog.details.add_theme_constant_override("separation",6)
	var stored_items: Dictionary = initial.get("items", {})
	var inventory: Dictionary = app.session.snapshot.get("players", {}).get(app.session.own_id, {}).get("inventory", {})
	var stocked: Array[String] = []
	var carried: Array[String] = []
	var empty: Array[String] = []
	for id: String in World.NAMES:
		if int(stored_items.get(id, 0)) > 0:
			stocked.append(id)
		elif int(inventory.get(id, 0)) > 0:
			carried.append(id)
		else:
			empty.append(id)
	var ordered_items := stocked + carried + empty
	for id: String in ordered_items:
		add_entry(app, catalog, 0, id, World.NAMES[id], item_icon(id))
	# T014: one row per direction, [1] [半數] [全部]. Same height as the former two
	# stacked buttons. The server recomputes the amount from its own counts; the
	# tooltips only preview it from the latest snapshot.
	var moves := {}
	for direction in ["deposit", "withdraw"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		catalog.details.add_child(row)
		var caption: Label = app.label("存入" if direction == "deposit" else "取出", 15)
		caption.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		caption.autowrap_mode = TextServer.AUTOWRAP_OFF
		row.add_child(caption)
		for step in [["", "1", "1"], ["_half", "Half", "半數"], ["_all", "All", "全部"]]:
			var action: String = direction + str(step[0])
			var move: Button = app.button(str(step[2]), func():
				app.session.perform(action, cell, catalog.selected)
				app._close_modal()
			)
			move.name = "Chest" + direction.capitalize() + str(step[1])
			move.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			move.focus_mode = Control.FOCUS_ALL
			row.add_child(move)
			moves[action] = move
	moves.deposit.tooltip_text = "存入 1 件"
	moves.withdraw.tooltip_text = "取出 1 件"
	var exact_controls := VBoxContainer.new()
	catalog.details.add_child(exact_controls)
	var exact_row := HBoxContainer.new()
	exact_row.add_theme_constant_override("separation", 4)
	var amount_input := LineEdit.new()
	amount_input.name = "ChestExactAmount"
	amount_input.placeholder_text = "件數"
	amount_input.tooltip_text = "輸入正整數，再選存入或取出。"
	amount_input.max_length = 32
	amount_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	exact_row.add_child(amount_input)
	var exact_toggle: Button = app.button("指定件數", func():
		exact_row.show()
		amount_input.grab_focus()
	)
	exact_toggle.name = "ChestExactToggle"
	exact_toggle.focus_mode = Control.FOCUS_ALL
	exact_controls.add_child(exact_toggle)
	exact_controls.add_child(exact_row)
	var exact_buttons := {}
	for action: String in World.CHEST_EXACT_MOVES:
		var storing := action == "deposit_exact"
		var move: Button = app.button("存入" if storing else "取出", func():
			var amount := World.chest_exact_quantity(amount_input.text)
			if amount > 0 and app.session.perform(action, cell, "%s:%d" % [catalog.selected, amount]) > 0:
				app._close_modal()
		)
		move.name = "ChestDepositExact" if storing else "ChestWithdrawExact"
		move.focus_mode = Control.FOCUS_ALL
		exact_buttons[action] = move
		exact_row.add_child(move)
	var cancel: Button = app.button("×", func():
		exact_row.hide()
		exact_toggle.grab_focus()
	)
	cancel.tooltip_text = "收合指定件數"
	cancel.focus_mode = Control.FOCUS_ALL
	exact_row.add_child(cancel)
	exact_row.visibility_changed.connect(func(): exact_toggle.visible = not exact_row.visible)
	exact_row.hide()
	amount_input.text_changed.connect(func(_text: String): refresh(app))
	var last_item := [""]
	# C06/C07: "已用 N / 16 格" for chest/private_chest (never for supply_box). Only
	# someone who may see the contents gets numbers; a deposit-only guest gets the
	# server's refusal text instead, so the box is not peeked at.
	var capacity: Label = app.label("", 15)
	capacity.name = "ChestCapacity"
	capacity.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	capacity.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	capacity.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	capacity.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	catalog.bar.add_child(capacity)
	var history_button: Button = app.button("操作紀錄", chest_history.bind(app, cell))
	history_button.name = "ChestOpenHistory"
	catalog.bar.add_child(history_button)
	if initial.get("type")=="private_chest" and not initial.get("locked",false):
		catalog.details.add_child(app._chest_deposit_toggle(cell,initial))
		catalog.details.add_child(app._chest_withdraw_picker(cell))
	updates.append(func(person):
		var id: String = catalog.selected
		var box: Dictionary = app.session.snapshot.get("objects", {}).get(key, {})
		var stored: int = int(box.get("items", {}).get(id, 0))
		var held: int = int(person.get("inventory", {}).get(id, 0))
		var exists:bool=box.get("type") in ["chest","private_chest","supply_box"]
		var locked:bool=box.get("locked",false)
		var locked_shared:bool=box.get("type")=="chest" and locked
		catalog.bar.visible=not locked_shared
		catalog.body.visible=not locked_shared
		if floor_notice.visible!=locked_shared:
			floor_notice.visible=locked_shared
			chest_modal.set_meta("life_modal_layout","locked_shared_chest" if locked_shared else "")
			app._layout_preview.call_deferred()
		var shared_floor_restricted:bool=box.get("type")=="chest" and app.session.snapshot.get("ground",{}).get(key,{}).get("placement_access")=="owner"
		var guest_deposit:bool=box.get("type")=="private_chest" and box.get("guest_deposit",false)
		var guest_withdraw:bool=box.get("type")=="private_chest" and box.get("guest_withdraw",false)
		catalog.title.text = World.NAMES[id]
		catalog.icon.texture = item_icon(id)
		if locked and not guest_withdraw:
			catalog.description.text="背包 %d\n訪客可存入，內容由箱主查看。" % held if guest_deposit else "只有箱主可以存取。"
		else:
			var rule:="島民可共同存取"
			if locked:rule="你可存入與取出" if guest_deposit else "你可取出箱內物品"
			elif shared_floor_restricted:rule="地板主人與箱主可存取"
			elif private_box:
				var deposit_label:="同島可存入" if guest_deposit else "僅箱主可存入"
				var withdraw_label:="指定島民可取出" if not str(box.get("withdraw_guest","")).is_empty() else "僅箱主可取出"
				rule=deposit_label+" · "+withdraw_label
			catalog.description.text="背包 %d · 箱內 %d\n%s" % [held,stored,rule]
		var sized:bool=exists and World.BOX_CAPACITY.applies(box.get("type",""))
		var can_view:bool=not locked or guest_withdraw
		history_button.visible = sized and can_view and app.session.snapshot.get("chest_history", false)
		var box_items:Dictionary=box.get("items",{}) if can_view else {}
		var cap:Dictionary=World.BOX_CAPACITY.summary(box_items)
		capacity.visible=sized and can_view
		if capacity.visible:
			capacity.text=World.BOX_CAPACITY.usage_text(cap)
			capacity.tooltip_text=World.BOX_CAPACITY.FULL_MESSAGE if cap.full else ""
		var slot_full:bool=sized and can_view and cap.full and stored==0
		for action: String in moves:
			var storing := action.begins_with("deposit")
			var have: int = held if storing else stored
			var move: Button = moves[action]
			move.disabled=have<=0 or not exists or (locked and not (guest_deposit if storing else guest_withdraw)) or (storing and slot_full)
			var amount := World.chest_move_amount(action, have)
			if action.ends_with("_half"):
				move.tooltip_text = ("存入半數 %d 件" if storing else "取出半數 %d 件") % amount
			elif action.ends_with("_all"):
				move.tooltip_text = ("全部存入 %d 件" if storing else "全部取出 %d 件") % amount
			elif storing:
				move.tooltip_text = "存入 1 件"
			if storing and slot_full:move.tooltip_text = World.BOX_CAPACITY.FULL_MESSAGE
		if id != last_item[0]:
			last_item[0] = id
			amount_input.clear()
		var exact_supported: bool = app.session.snapshot.get("chest_exact_transfer", false)
		exact_controls.visible = exact_supported
		exact_toggle.disabled = moves.deposit.disabled and moves.withdraw.disabled
		if not exact_supported or exact_toggle.disabled:
			exact_row.hide()
		var requested := World.chest_exact_quantity(amount_input.text)
		exact_buttons.deposit_exact.disabled = moves.deposit.disabled or requested == 0 or requested > held
		exact_buttons.withdraw_exact.disabled = moves.withdraw.disabled or requested == 0 or requested > stored
	)
	select_entry(app, catalog, 0, ordered_items[0])
