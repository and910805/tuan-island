extends RefCounted

const World = preload("res://scripts/world.gd")
const Tasks = preload("res://scripts/life_ui_tasks.gd")
const ItemArt = preload("res://scripts/inventory_item_art.gd")
const PixelTheme = preload("res://scripts/inventory_pixel_theme.gd")
const SourcePicker = preload("res://scripts/material_source_ui.gd")
## Player-facing "what is this for" guidance for every World.CRAFT recipe.
## kind: place (kit consumed 1:1 by World.BUILD[build]), collection (consumed by
## World.BUILD[build] as decoration), part (ingredient of other CRAFT recipes),
## key_tool (enables a world action), tool (portable equipment, see PORTABLE_TOOLS).
## tab is the BuildFolio tab that lists `build`. Tool text takes binding labels for
## `keys` so rebinding stays accurate. test_workbench_guidance.gd checks every
## field against the real recipe, build and device data.
const GUIDE := {
	"supply_box_kit":{"kind":"place","build":"supply_box","tab":"生活","text":"探索六級解鎖。到建造目錄「生活」放置，清空後可拆回背包。"},
	"glass":{"kind":"collection","build":"greenhouse_roof","tab":"基礎",
		"text":"金瓜石五層採晶砂。建造目錄「基礎」用玻璃 2、銅接頭 1 在自家農田蓋溫室玻璃棚。"},
	"salt_wheel_kit": {"kind": "salt_facility",
		"text": "在北門親手收過一次鹽後可製作。到自己照顧的鹽田操作水車座，裝上水車後會自動引入海水。"},
	"salt_rake_kit": {"kind": "salt_facility",
		"text": "收過水車引水的鹽後可製作。到自己照顧的鹽田操作收鹽台座，裝上後可設定收鹽箱與存量上限。"},
	"gold_sample": {"kind": "collection", "build": "ore_display", "tab": "家具",
		"text": "完成波波三段故事後，到建造目錄「家具」用木材 4＋樣本 1 放礦樣展示架。"},
	"reinforced_pick": {"kind": "key_tool", "action": "mine_copper",
		"text": "放在背包即可。到渡口運入礦料點互動採銅礦，每次 2 個；每人只能製作一把。"},
	"mine_drill_kit": {"kind": "place", "build": "mine_drill", "tab": "生活",
		"text": "開通第五層後可製作。建造目錄「生活」放在礦層指定礦點旁，裝木炭自動採礦。"},
	"waterworks_kit": {"kind": "place", "build": "waterworks", "tab": "生活",
		"text": "第三層抽水工程完成後可製作。建造目錄「生活」放置並接水管，把銅礦與木材加工成銅接頭。"},
	"copper_joint": {"kind": "part", "used_in_build": ["loom", "glass_furnace", "seed_maker", "greenhouse_roof", "medium_sprinkler"], "feeds": ["mine_drill_kit", "waterworks_kit", "sprinkler_kit", "pipe_kit", "pump_kit", "forester_kit", "conveyor_kit", "tiller", "seeder", "harvester", "mill_kit", "salt_wheel_kit", "salt_rake_kit", "diversion_gate_kit", "water_tower_kit"],
		"text": "供織布機、玻璃爐、種子機、溫室玻璃棚、灑水器與鹽田機具使用。種子機需 2 個，玻璃棚 1 個。"},
	"sprinkler_kit": {"kind": "place", "build": "sprinkler", "tab": "生活",
		"text": "建造目錄「生活」放在田邊，替上下左右自家作物澆水；手動補水或接水管。"},
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
	"mill_kit": {"kind": "place", "build": "mill", "tab": "生活",
		"text": "公共廚房開張後製作。「生活」放置，小麥 2 磨麵粉 1，配南瓜和蛋烤派。"},
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

func workbench(app, cell: Vector2i) -> void:
	var body := open(app, "工作台")
	modal.set_meta("life_modal_layout", "automation_workbench")
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
	var entries: Dictionary = {}
	for id in ids:
		var button: Button = app.button(World.CRAFT[id].name, func():
			selected.id = id
			for key in entries:
				entries[key].set_pressed_no_signal(key == id)
			refresh(app)
			reveal_recipe(scroll, entries[id])
		)
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
	var capture_craft: String = app.arg_value("capture-craft", "")
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
			Tasks.add_icon(row, ItemArt.icon(item), 32)
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
	details.add_child(app.button("家園建造  %s"%app.binding_label("build_menu"), app._build_menu))
	update_view = func(snapshot: Dictionary, person: Dictionary):
		var id: String = selected.id
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
		use.text = recipe_use(id, app)
		var bench: Dictionary = snapshot.get("objects", {}).get(World.key(cell), {})
		var available: bool = bench.get("type") == "bench"
		equip.visible = PORTABLE_TOOLS.has(id) and int(bag.get(id, 0)) > 0
		equip.text = "%s  %s" % [PORTABLE_TOOLS[id][1],app.binding_label(PORTABLE_TOOLS[id][0])] if equip.visible else ""
		var locked: bool = id == "waterworks_kit" and int(snapshot.get("mine_depths",{}).get("unlocked",1)) < 4
		locked = locked or (id == "mine_drill_kit" and int(snapshot.get("mine_depths",{}).get("unlocked",1)) < 5)
		var kitchen_locked: bool = id in World.KITCHEN_GATED and not bool(snapshot.get("public_kitchen",{}).get("opened",false))
		locked = locked or kitchen_locked
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

func sprinkler(app, cell: Vector2i) -> void:
	var kind:String=app.session.snapshot.get("objects",{}).get(World.key(cell),{}).get("type","sprinkler")
	var capacity:int=World.INDUSTRY.SPRINKLER_CAPACITIES.get(kind,World.SPRINKLER_CAPACITY)
	var coverage:="周圍八格" if kind=="medium_sprinkler" else "上下左右相鄰格"
	var body := open(app, World.BUILD[kind].name)
	modal.set_meta("life_modal_layout", "automation_device")
	var details := Tasks.card(body)
	Tasks.add_icon(details, ItemArt.icon("sprinkler_kit"), 64)
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
	supply.custom_minimum_size.x = 280
	details.add_child(supply)
	Tasks.line(app, details, "每 %d 秒檢查%s內，同一位主人種植的作物。" % [World.SPRINKLER_INTERVAL,coverage], 16)
	var actions := HBoxContainer.new()
	details.add_child(actions)
	var refill: Button = app.button("補滿水", func(): app.session.perform("refill_sprinkler", cell))
	var toggle: Button = app.button("啟用", func(): app.session.perform("toggle_sprinkler", cell))
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
		if present and amount == 0:
			state.text += " · 無水，補水後才能灑水"
		if present and not owner:
			state.text += " · 由擁有者操作"
		var network: Dictionary = World.INDUSTRY.network_info(snapshot, World.key(cell))
		var tanks: int = network.get("connected_tanks", 0)
		supply.visible = present
		supply.text = "接通 %d 桶 · 管網水量 %d／%d" % [tanks, network.water, network.capacity] if tanks > 0 else "未接通儲水桶，需手動補水。"
		# 第 40 章水塔：同一條水管上有水塔時多一行座數與存水。
		var towers: int = int(network.get("towers", 0))
		if towers > 0:
			if tanks == 0:supply.text = "未接通儲水桶"
			supply.text += "\n水塔 %d 座 · 存水 %d／%d" % [towers, int(network.get("tower_water", 0)), int(network.get("tower_capacity", 0))]
		refill.disabled = not owner or amount >= capacity
		toggle.disabled = not owner
		toggle.text = "停止" if active else "啟用"
	refresh(app)

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
	return int(person.get("inventory", {}).get("reinforced_pick", 0)) > 0

## Concise use guidance for a craft recipe. `app` supplies live key labels for
## portable tools (any object with binding_label(action)); without it the key
## prefix is left out rather than guessed.
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
