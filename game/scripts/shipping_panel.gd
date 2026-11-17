extends PanelContainer

signal close_requested
signal shipment_requested(payload: String)

const World = preload("res://scripts/world.gd")
const Shipping = preload("res://scripts/shipping.gd")
const ItemArt = preload("res://scripts/inventory_item_art.gd")
const Slot = preload("res://scripts/item_slot.gd")
const LifeTheme = preload("res://scripts/life_ui_theme.gd")
const PixelTheme = preload("res://scripts/inventory_pixel_theme.gd")
const FurnitureArt = preload("res://scripts/furniture_sprite_art.gd")
const CATEGORIES := ["全部", "田園", "漁獲", "採集", "料理"]

var inventory: Dictionary = {}
var prices: Dictionary = {}
var cart: Dictionary = {}
var slots: Dictionary = {}
var selected_id := ""
var category := 0
var reviewing := false
var pending := false
var pending_sequence := -1
var balance: Label
var grid: GridContainer
var scroller: ScrollContainer
var tabs: Array[Button] = []
var detail_icon: TextureRect
var detail_name: Label
var detail_price: Label
var quantity: Label
var minus: Button
var plus: Button
var all_button: Button
var clear_button: Button
var receipt: VBoxContainer
var receipt_scroll: ScrollContainer
var total_label: Label
var confirm_button: Button
var notice: Label
var empty_label: Label
var coins := 0
var ready_to_ship := true

func text_label(value: String, font_size: int = 17) -> Label:
	var result := Label.new()
	result.text = value
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", LifeTheme.INK)
	return result

func icon(texture: Texture2D, extent: int) -> TextureRect:
	var result := TextureRect.new()
	result.texture = texture
	result.custom_minimum_size = Vector2(extent, extent)
	result.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	result.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	result.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return result

func button(value: String, callback: Callable) -> Button:
	var result := Button.new()
	result.text = value
	result.custom_minimum_size = Vector2(44, 44)
	result.pressed.connect(callback)
	return result

func setup(snapshot: Dictionary, own_id: String, base_theme: Theme) -> void:
	theme = LifeTheme.apply(base_theme)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_theme_stylebox_override("panel", LifeTheme.panel_style())
	prices = Shipping.prices(World.CROPS, World.FISH, World.OTHER_SALES,true)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	add_child(body)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 10)
	body.add_child(header)
	var crate := AtlasTexture.new()
	crate.atlas = load(FurnitureArt.PATH)
	crate.region = Rect2(0, 0, 32, 48)
	header.add_child(icon(crate, 48))
	var title := text_label("渡口出貨箱", 26)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	header.add_child(icon(ItemArt.icon("coins"), 32))
	balance = text_label("", 18)
	header.add_child(balance)
	header.add_child(button("返回 Esc", func(): close_requested.emit()))
	var subtitle := text_label("把今天的收穫，換成明天的種子。", 16)
	body.add_child(subtitle)
	var content := HBoxContainer.new()
	content.add_theme_constant_override("separation", 16)
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(content)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 10)
	content.add_child(left)
	var tab_bar := HBoxContainer.new()
	tab_bar.add_theme_constant_override("separation", 4)
	left.add_child(tab_bar)
	for index in CATEGORIES.size():
		var tab := button(CATEGORIES[index], select_category.bind(index))
		tab.icon = ItemArt.icon(["backpack", "radish", "carp", "wood", "soup"][index])
		tab.expand_icon = true
		tab.add_theme_constant_override("icon_max_width", 24)
		tab.toggle_mode = true
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.add_theme_font_size_override("font_size", 16)
		tabs.append(tab)
		tab_bar.add_child(tab)
	var tray := PanelContainer.new()
	tray.add_theme_stylebox_override("panel", LifeTheme.toolbar_style())
	tray.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(tray)
	scroller = ScrollContainer.new()
	scroller.follow_focus = true
	scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroller.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tray.add_child(scroller)
	grid = GridContainer.new()
	grid.columns = 5
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	scroller.add_child(grid)
	for id in prices:
		var slot := Slot.new()
		slot.configure(id, ItemArt.icon(id), 0, World.NAMES.get(id, id))
		slot.item_selected.connect(select_item)
		slot.focus_entered.connect(select_item.bind(id))
		grid.add_child(slot)
		slots[id] = slot
	empty_label = text_label("這一類還沒有可出貨的物品。", 17)
	left.add_child(empty_label)
	var selection := PanelContainer.new()
	selection.add_theme_stylebox_override("panel", LifeTheme.badge_style())
	left.add_child(selection)
	var selection_body := VBoxContainer.new()
	selection_body.add_theme_constant_override("separation", 8)
	selection.add_child(selection_body)
	var selected := HBoxContainer.new()
	selected.add_theme_constant_override("separation", 10)
	selection_body.add_child(selected)
	detail_icon = icon(null, 64)
	selected.add_child(detail_icon)
	var description := VBoxContainer.new()
	description.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selected.add_child(description)
	detail_name = text_label("選一份收穫", 21)
	detail_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description.add_child(detail_name)
	detail_price = text_label("", 16)
	description.add_child(detail_price)
	var amount_row := HBoxContainer.new()
	amount_row.add_theme_constant_override("separation", 8)
	selection_body.add_child(amount_row)
	minus = button("−", change_amount.bind(-1))
	minus.tooltip_text = "從出貨籃取回一份"
	amount_row.add_child(minus)
	quantity = text_label("出貨 0", 18)
	quantity.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	quantity.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	amount_row.add_child(quantity)
	plus = button("＋", change_amount.bind(1))
	plus.tooltip_text = "放一份到出貨籃"
	amount_row.add_child(plus)
	all_button = button("全放入", select_all)
	amount_row.add_child(all_button)
	var paper := PanelContainer.new()
	paper.custom_minimum_size.x = 340
	paper.add_theme_stylebox_override("panel", PixelTheme.paper_style())
	content.add_child(paper)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 10)
	paper.add_child(right)
	var receipt_heading := HBoxContainer.new()
	right.add_child(receipt_heading)
	var receipt_title := text_label("這一籃的收穫", 22)
	receipt_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	receipt_heading.add_child(receipt_title)
	clear_button = button("清空", clear_cart)
	receipt_heading.add_child(clear_button)
	receipt_scroll = ScrollContainer.new()
	receipt_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	receipt_scroll.follow_focus = true
	receipt_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(receipt_scroll)
	receipt = VBoxContainer.new()
	receipt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	receipt.add_theme_constant_override("separation", 6)
	receipt_scroll.add_child(receipt)
	right.add_child(HSeparator.new())
	var total_row := HBoxContainer.new()
	right.add_child(total_row)
	total_row.add_child(icon(ItemArt.icon("coins"), 32))
	total_label = text_label("預計收入  0", 22)
	total_row.add_child(total_label)
	right.add_child(text_label("收入放進你的錢包 · 確認後即出售", 14))
	confirm_button = button("核對出貨", confirm)
	confirm_button.custom_minimum_size.y = 48
	right.add_child(confirm_button)
	notice = text_label("挑選物品後按 ＋ 放入出貨籃。手把 X 可前往數量操作。", 15)
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice.custom_minimum_size.y = 40
	body.add_child(notice)
	refresh(snapshot, own_id)
	select_category(0)
	update_cart()
	var first:Control=slots.get(selected_id,tabs[0])
	first.grab_focus.call_deferred()

func _input(event:InputEvent) -> void:
	if not is_visible_in_tree() or not event is InputEventJoypadButton or not event.pressed or event.button_index!=JOY_BUTTON_X:return
	if selected_id.is_empty() or get_viewport().gui_get_focus_owner()!=slots.get(selected_id):return
	var action:=plus if not plus.disabled else minus
	if action.disabled:return
	action.grab_focus()
	get_viewport().set_input_as_handled()

func _unhandled_input(event:InputEvent) -> void:
	if not is_visible_in_tree() or not event.is_action_pressed("ui_cancel"):return
	var focused:=get_viewport().gui_get_focus_owner()
	if is_instance_valid(focused) and is_ancestor_of(focused):
		get_viewport().set_input_as_handled()
		close_requested.emit()

func layout_for(viewport_size: Vector2) -> void:
	size = Vector2(minf(960, viewport_size.x - 32), minf(500, viewport_size.y - 32))
	position = ((viewport_size - size) / 2).floor()
	var columns:=5 if size.x>=940 else 4
	if grid.columns!=columns:
		grid.columns=columns
		link_stock_focus()

func link_stock_focus() -> void:
	var entries:Array[Control]=[]
	for slot:Control in grid.get_children():
		if slot.visible:entries.append(slot)
	for index in entries.size():
		var slot:=entries[index]
		var above:Control=entries[index-grid.columns] if index>=grid.columns else tabs[category]
		var below:Control=entries[index+grid.columns] if index+grid.columns<entries.size() else plus
		slot.focus_neighbor_top=slot.get_path_to(above)
		slot.focus_neighbor_bottom=slot.get_path_to(below)
	plus.focus_neighbor_bottom=plus.get_path_to(confirm_button)
	plus.focus_neighbor_left=plus.get_path_to(minus)
	minus.focus_neighbor_right=minus.get_path_to(plus)
	minus.focus_neighbor_bottom=minus.get_path_to(confirm_button)
	plus.focus_neighbor_right=plus.get_path_to(all_button)
	all_button.focus_neighbor_left=all_button.get_path_to(plus)
	all_button.focus_neighbor_bottom=all_button.get_path_to(confirm_button)
	confirm_button.focus_neighbor_right=confirm_button.get_path_to(clear_button)
	clear_button.focus_neighbor_bottom=clear_button.get_path_to(confirm_button)
	clear_button.focus_neighbor_left=clear_button.get_path_to(confirm_button)
	confirm_button.focus_neighbor_top=confirm_button.get_path_to(plus)

static func category_for(id: String) -> int:
	if World.CROPS.has(World.CROP_CATALOG.base_kind(id)): return 1
	if World.FISH.has(id): return 2
	if Shipping.MATERIAL_PRICES.has(id): return 3
	return 4

func refresh(snapshot: Dictionary, own_id: String) -> void:
	var person: Dictionary = snapshot.get("players", {}).get(own_id, {})
	var next_inventory: Dictionary = person.get("inventory", {})
	var changed := inventory != next_inventory
	inventory = next_inventory.duplicate()
	coins = int(person.get("coins", 0))
	balance.text = str(coins)
	ready_to_ship = Shipping.cell_for(snapshot) != Shipping.NO_CELL
	if changed:
		for id in slots: slots[id].set_count(int(inventory.get(id, 0)))
		select_category(category)
	if not cart.is_empty() and not current_quote().ok:
		reviewing = false
		show_notice("背包數量或錢包已變更，請調整出貨籃後重新核對。", false)
	update_selection()
	update_confirm()

func select_category(index: int) -> void:
	category = clampi(index, 0, CATEGORIES.size() - 1)
	for i in tabs.size(): tabs[i].set_pressed_no_signal(i == category)
	var visible_ids: Array[String] = []
	for id in slots:
		var visible_item: bool = (category == 0 or category_for(id) == category) and (int(inventory.get(id, 0)) > 0 or cart.has(id))
		slots[id].visible = visible_item
		if visible_item: visible_ids.append(id)
	empty_label.visible = visible_ids.is_empty()
	if selected_id not in visible_ids: selected_id = visible_ids[0] if not visible_ids.is_empty() else ""
	select_item(selected_id)
	link_stock_focus()

func select_item(id: String) -> void:
	if not id.is_empty() and (not slots.has(id) or not slots[id].visible): return
	selected_id = id
	for item in slots: slots[item].set_selected(item == id)
	update_selection()
	var selected:Control=slots.get(selected_id,tabs[category])
	tabs[category].focus_neighbor_bottom=tabs[category].get_path_to(selected)
	plus.focus_neighbor_top=plus.get_path_to(selected)

func update_selection() -> void:
	var held := int(inventory.get(selected_id, 0))
	var amount := int(cart.get(selected_id, 0))
	detail_icon.texture = ItemArt.icon(selected_id) if not selected_id.is_empty() else null
	detail_name.text = World.NAMES.get(selected_id, "選一份收穫")
	detail_price.text = "持有 %d · 每份 %d 鈴幣" % [held, prices.get(selected_id, 0)] if not selected_id.is_empty() else "收成、漁獲、素材與料理都可以帶來。"
	quantity.text = "出貨 %d" % amount
	minus.disabled = pending or amount <= 0
	plus.disabled = pending or selected_id.is_empty() or amount >= mini(held, Shipping.MAX_QUANTITY)
	all_button.disabled = pending or selected_id.is_empty() or held <= 0 or amount == mini(held, Shipping.MAX_QUANTITY)
	clear_button.disabled = pending or cart.is_empty()

func change_amount(delta: int) -> void:
	if pending or selected_id.is_empty(): return
	set_amount(selected_id, int(cart.get(selected_id, 0)) + delta)

func select_all() -> void:
	if pending or selected_id.is_empty(): return
	set_amount(selected_id, int(inventory.get(selected_id, 0)))

func set_amount(id: String, amount: int) -> void:
	if pending or not prices.has(id): return
	var bounded := clampi(amount, 0, mini(int(inventory.get(id, 0)), Shipping.MAX_QUANTITY))
	if bounded > 0 and not cart.has(id) and cart.size() >= Shipping.MAX_LINES:
		show_notice("每籃最多 %d 種物品，先出這一籃吧。" % Shipping.MAX_LINES, false)
		return
	if bounded == 0: cart.erase(id)
	else: cart[id] = bounded
	reviewing = false
	show_notice("右側列出這一籃的數量與收入，核對後再確認出貨。", true)
	update_cart()

func clear_cart() -> void:
	if pending: return
	cart.clear()
	reviewing = false
	show_notice("已清空出貨籃，背包裡的物品沒有改變。", true)
	update_cart()

func lines() -> Array:
	var result := []
	for id in cart: result.append([id, cart[id]])
	return result

func current_quote() -> Dictionary:
	var result := Shipping.quote(lines(), inventory, prices)
	if result.ok and coins > Shipping.MAX_COINS - result.total:
		return {"ok": false, "message": "鈴幣錢包已達上限。"}
	return result

func update_cart() -> void:
	for child in receipt.get_children():
		receipt.remove_child(child)
		child.queue_free()
	if cart.is_empty():
		var empty := text_label("籃子還空著。\n\n先留好下一輪種植與建造\n需要的材料，再把多的放進來。", 17)
		receipt.add_child(empty)
	for id in cart:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		receipt.add_child(row)
		row.add_child(icon(ItemArt.icon(id), 32))
		var details := VBoxContainer.new()
		details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(details)
		var item := text_label(World.NAMES[id], 16)
		item.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		details.add_child(item)
		var subtotal := HBoxContainer.new()
		details.add_child(subtotal)
		var count := text_label("×%d" % cart[id], 14)
		count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		subtotal.add_child(count)
		subtotal.add_child(text_label(str(int(prices[id]) * int(cart[id])), 16))
	update_selection()
	update_confirm()

func update_confirm() -> void:
	var quote := current_quote()
	var sum := 0
	for id in cart: sum += int(prices[id]) * int(cart[id])
	total_label.text = "預計收入  %d" % sum
	confirm_button.disabled = pending or not ready_to_ship or not quote.ok
	confirm_button.text = "正在保存這一籃…" if pending else ("確認出貨 · %d 鈴幣" % sum if reviewing else "核對出貨")
	if not ready_to_ship: show_notice("出貨箱的位置暫時被占用，請返回島上查看。", false)

func confirm() -> void:
	if pending or not ready_to_ship: return
	var quote := current_quote()
	if not quote.ok:
		show_notice(quote.message, false)
		return
	if not reviewing:
		reviewing = true
		show_notice("請核對右側全部明細。再次按確認會立即出售；返回或清空都不扣物品。", true)
		update_confirm()
		return
	pending = true
	show_notice("正在送出並保存。送出後關閉視窗不會取消這次出貨。", true)
	update_selection()
	update_confirm()
	shipment_requested.emit(JSON.stringify([lines(), quote.total]))

func complete(result: Dictionary) -> void:
	var focused:=get_viewport().gui_get_focus_owner()
	var move_focus:=focused==confirm_button or focused==null
	pending = false
	reviewing = false
	if result.get("ok", false): cart.clear()
	update_cart()
	select_category(category)
	if move_focus and confirm_button.disabled:
		var next:Control=slots.get(selected_id,tabs[category])
		next.grab_focus()
	show_notice(str(result.get("message", "出貨未完成，請重新核對。")), result.get("ok", false))

func show_notice(message: String, success: bool) -> void:
	notice.text = message
	notice.add_theme_color_override("font_color", Color("34543d") if success else Color("874834"))
