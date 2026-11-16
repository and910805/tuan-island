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
	"loom":"靠近按 E，用棉球花或羊毛織布。",
	"jam_pot":"靠近按 E，用 3 份草莓和 1 份糖熬製果醬。",
	"glass_furnace":"靠近按 E，把晶砂燒成玻璃，或把脈石英熔碎成晶砂。",
	"seed_maker":"靠近按 E，把成熟作物和木炭加工成種子。成品可領回背包。",
	"mill":"公共廚房開張後解鎖。E 把小麥磨成麵粉，可排程或自動加工；輸送帶可送入小麥、帶出麵粉。"
}
const FOUNDATIONS := ["floor", "path", "wall", "door", "window", "roof", "greenhouse_roof"]
const FURNITURE := ["bed", "lamp", "table", "chair", "long_bench", "sofa", "planter", "sketch_easel", "rope_rack", "flower_pot", "greenhouse_rack", "master_flower_bed", "fish_display", "author_sign", "author_shelf", "expedition_tent", "sign", "ore_display"]
const ItemArt = preload("res://scripts/inventory_item_art.gd")
const PixelTheme = preload("res://scripts/inventory_pixel_theme.gd")
const BuildThumbnail = preload("res://scripts/pixel_build_thumbnail.gd")
const HouseUI = preload("res://scripts/house_ui.gd")
const BuildFolio = preload("res://scripts/build_folio.gd")
const CookingQueueUI = preload("res://scripts/cooking_queue_ui.gd")
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
	var index := Crops.ROWS.find(Crops.PREVIEW_ROWS.get(crop_id,crop_id))
	if crop_id in ["pumpkin","watermelon"]:
		add_icon(row,preload("res://scripts/bakery_art.gd").growth_texture(stage))
	elif FlowerArt.has_crop(crop_id) or crop_id=="cotton":
		add_icon(row, FlowerArt.crop_texture("bluebell" if crop_id=="cotton" else crop_id, stage))
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
	var content := begin(app, "小栗的渡口小店" if app.session.snapshot.get("picnic",false) else "小栗的種子攤")
	balance(app, content, "xiaoli")
	var counter := HFlowContainer.new()
	counter.name = "ShopCounter"
	counter.add_theme_constant_override("h_separation", 8)
	counter.add_theme_constant_override("v_separation", 6)
	content.add_child(counter)
	if Village.NPCS.has("xiaoli"):
		counter.add_child(app.button("和小栗聊聊", func(): app._resident_menu("xiaoli")))
	if app.session.snapshot.has("own_shop_history"):
		var notebook:Button=app.button("翻開交易簿",trade_book.bind(app))
		notebook.name="ShopTradeBook"
		counter.add_child(notebook)
	var catalog := catalog_shell(app, content, ["買種子", "出售"], ["radish_seed", "coins"])
	app.modal.set_meta("shop_catalog", true)
	var products := [World.CROPS.keys() + ["sapling"], World.CROPS.keys() + World.FISH.keys() + World.OTHER_SALES.keys()]
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
			var item: String = id + "_seed" if page == 0 and id != "sapling" else id
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
		var item: String = id + "_seed" if buying and id != "sapling" else id
		var locked: bool = buying and id in Flower.FLOWERS and stall_flowers_locked(app.session.snapshot)
		lock_note.visible = locked
		offer.visible = not locked
		var price: int = 20 if id == "sapling" else World.CROPS[id].seed_price if buying else shop_sale_price(id)
		var held: int = person.get("inventory", {}).get(item, 0)
		catalog.title.text = World.NAMES[item]
		catalog.icon.texture = item_icon(item)
		catalog.description.text = "持有 %d · 單價 %d 鈴幣" % [held, price]
		if locked:
			catalog.description.text = "持有 %d · 尚未進貨" % held
		if buying and id != "sapling":
			catalog.description.text += "\n"+crop_season_hint(id)
		if not buying:
			var snapshot:Dictionary=app.session.snapshot
			if not snapshot.get("chapter_one",{}).get("shipped",false):
				catalog.description.text += "\n第一章出貨請用渡口出貨箱。"
			if id in ["radish","wheat"] and not snapshot.get("picnic",false):
				catalog.description.text += "\n這裡會出售全部。野餐需留蘿蔔和小麥各兩份。"
		offer.disabled = int(person.get("coins", 0)) < price if buying else held == 0
		offer.text = ("鈴幣不足" if offer.disabled else "買 1 份 · %d 鈴幣" % price) if buying else "出售全部 %d 件 · 共 %d 鈴幣" % [held, held * price]
	)
	select_entry(app, catalog, 0, "radish")

func trade_book(app,history:bool=false) -> void:
	var snapshot:Dictionary=app.session.snapshot
	if not snapshot.has("own_shop_history"):return
	var body:=begin(app,"小栗的交易簿")
	app.modal.set_meta("shop_catalog",true)
	var nav:=HBoxContainer.new()
	body.add_child(nav)
	var prices:Button=app.button("作物價目",trade_book.bind(app,false))
	var recent:Button=app.button("我的交易",trade_book.bind(app,true))
	prices.name="ShopTradePrices"
	recent.name="ShopTradeHistory"
	prices.disabled=not history
	recent.disabled=history
	nav.add_child(prices)
	nav.add_child(recent)
	nav.add_child(app.button("回到種子攤",app._shop))
	var scroll:=ScrollContainer.new()
	scroll.name="ShopTradeRows"
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y=270
	body.add_child(scroll)
	var page:=VBoxContainer.new()
	page.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	scroll.add_child(page)
	if history:
		var rows:Array=snapshot.own_shop_history
		var heading:Label=app.label("最近 10 筆種子攤與出貨箱交易",16)
		page.add_child(heading)
		if rows.is_empty():page.add_child(app.label("交易簿目前沒有可顯示的紀錄。",15))
		for entry:Dictionary in rows:
			var description:=PackedStringArray()
			for item:String in entry.items:
				description.append("%s ×%d"%[World.NAMES.get(item,item),abs(int(entry.items[item]))])
			var caption:=str({"buy":"購入","sell":"攤位售出","ship":"出貨"}.get(entry.action,""))
			var row:=HBoxContainer.new()
			page.add_child(row)
			add_icon(row,item_icon(str(entry.items.keys()[0])) if not entry.items.is_empty() else item_icon("coins"))
			var receipt:Label=app.label("第 %d 日 · %s\n%s"%[
				int(World.WEATHER.day_index(entry.time))+1,caption,"、".join(description)],15)
			receipt.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
			receipt.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			row.add_child(receipt)
			var coins:Label=app.label("%+d 鈴幣"%entry.coins,17)
			coins.add_theme_color_override("font_color",Color("48694a") if int(entry.coins)>=0 else Color("925230"))
			row.add_child(coins)
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
		row.add_child(app.label("種子 %s　｜　收成售價 %d"%[seed_price,crop.price],15))

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
	if World.CROPS.has(id):return World.CROPS[id].price
	if World.FISH.has(id):return World.FISH[id].price
	return World.OTHER_SALES[id]

func build_menu(app) -> void:
	# Dedicated builder folio (BuildFolio / BuildShelf / BuildRecipe / BuildPlace);
	# the shared catalog_shell below stays as-is for shop, seeds, cooking and chests.
	var catalog: Dictionary = BuildFolio.open(self, app, {"notes": BUILD_NOTES,
		"foundations": FOUNDATIONS, "furniture": FURNITURE, "materials": BUILD_MATERIALS})
	var capture_build: String = app.arg_value("capture-build", "")
	if World.BUILD.has(capture_build):
		for page in range(1, catalog.pages.size()):
			if catalog.entries[page].has(capture_build):
				select_entry(app, catalog, page, capture_build)
				var scroll: ScrollContainer = catalog.pages[page].get_parent().get_parent()
				scroll.call_deferred("ensure_control_visible", catalog.entries[page][capture_build])
				break

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
		"details": details, "icon": icon, "title": title, "description": description}
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
	if catalog.has("build_scroll"):
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
	caption.add_theme_font_size_override("font_size", 14)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	entry.add_child(caption)
	caption.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	caption.offset_top = -27
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
	select_entry(app, catalog, 0, app.crop)

func cook(app, cell: Vector2i) -> void:
	# The queue workbench owns its own refresh (main._state_changed), so drop
	# any closures from the previous life panel before handing over.
	updates.clear()
	modal = null
	CookingQueueUI.open(app, cell)

func chest(app, cell: Vector2i) -> void:
	var key: String = World.key(cell)
	var initial: Dictionary = app.session.snapshot.get("objects", {}).get(key, {})
	var private_box: bool = initial.get("type") in World.PRIVATE_BOXES
	var content := begin(app, "私人箱" if private_box else "共用箱")
	var catalog := catalog_shell(app, content, ["箱內物品"])
	for id in World.NAMES:
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
	updates.append(func(person):
		var id: String = catalog.selected
		var box: Dictionary = app.session.snapshot.get("objects", {}).get(key, {})
		var stored: int = int(box.get("items", {}).get(id, 0))
		var held: int = int(person.get("inventory", {}).get(id, 0))
		var accessible: bool = box.get("type") in ["chest", "private_chest", "supply_box"] and not box.get("locked", false)
		catalog.title.text = World.NAMES[id]
		catalog.icon.texture = item_icon(id)
		catalog.description.text = "背包 %d · 箱內 %d\n%s" % [held, stored, "僅主人可存取" if private_box else "島民可共同存取"]
		for action: String in moves:
			var storing := action.begins_with("deposit")
			var have: int = held if storing else stored
			var move: Button = moves[action]
			move.disabled = have <= 0 or not accessible
			var amount := World.chest_move_amount(action, have)
			if action.ends_with("_half"):
				move.tooltip_text = ("存入半數 %d 件" if storing else "取出半數 %d 件") % amount
			elif action.ends_with("_all"):
				move.tooltip_text = ("全部存入 %d 件" if storing else "全部取出 %d 件") % amount
	)
	select_entry(app, catalog, 0, World.NAMES.keys()[0])
