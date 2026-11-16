extends SceneTree

const World = preload("res://scripts/world.gd")
const Panels = preload("res://scripts/life_ui_panels.gd")
const BuildFolio = preload("res://scripts/build_folio.gd")

var main
var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL " + message)

func press(key: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = true
	main._unhandled_input(event)

func find_label(node: Node, text: String, exact: bool = false, visible_only: bool = false) -> Label:
	if node is Label and (node.text == text if exact else node.text.contains(text)) and (not visible_only or node.is_visible_in_tree()):
		return node
	for child in node.get_children():
		var match_label := find_label(child, text, exact, visible_only)
		if match_label != null:
			return match_label
	return null

func find_button(node: Node, text: String) -> Button:
	if node is Button and node.text == text:
		return node
	for child in node.get_children():
		var result := find_button(child, text)
		if result != null:
			return result
	return null

func card_button(node: Node, item: String, visible_only: bool = false) -> Button:
	if node is Button and node.tooltip_text == item and (not visible_only or node.is_visible_in_tree()):
		return node
	if node is Label and node.text == item and (not visible_only or node.is_visible_in_tree()):
		for sibling in node.get_parent().get_children():
			if sibling is Button:
				return sibling
	for child in node.get_children():
		var entry := card_button(child, item, visible_only)
		if entry != null:return entry
	return null

func button_with_prefix(node: Node, prefix: String) -> Button:
	if node is Button and node.text.begins_with(prefix) and node.is_visible_in_tree():
		return node
	for child in node.get_children():
		var button := button_with_prefix(child, prefix)
		if button != null:
			return button
	return null

func check_catalogs(world: World) -> void:
	var person: Dictionary = world.state.players[main.session.profile.token]
	person.x = 43.5
	person.y = 30.5
	person.coins = 0
	main.session._send_snapshot(1)
	main._shop()
	await process_frame
	var shop: Control = main.modal
	var buy_tab := find_button(shop, "買種子")
	buy_tab.pressed.emit()
	var product := card_button(shop, World.NAMES.radish_seed, true)
	expect(product != null, "radish seed can be picked from the buy grid")
	if product == null:return
	product.pressed.emit()
	var purchase := find_button(shop, "鈴幣不足")
	expect(product.button_pressed and purchase != null and purchase.disabled, "selected purchase is disabled without coins")
	var price: int = World.CROPS.radish.seed_price
	person.coins = price
	main.session._send_snapshot(1)
	main._refresh_hud()
	expect(not purchase.disabled and purchase.text.contains(str(price)), "purchase enables at the exact price")
	var seeds: int = person.inventory.radish_seed
	purchase.pressed.emit()
	expect(person.inventory.radish_seed == seeds + 1 and person.coins == 0, "purchase buys one pack and charges exactly its price")
	var sell := find_button(shop, "出售")
	sell.pressed.emit()
	sell.grab_focus()
	await process_frame
	var harvest := card_button(shop, World.NAMES.radish, true)
	expect(harvest != null, "radish can be picked from the sale grid")
	if harvest == null:return
	harvest.pressed.emit()
	var offer := button_with_prefix(shop, "出售全部")
	expect(harvest.button_pressed and offer.disabled, "selling is disabled when no harvest is held")
	person.inventory.radish = 3
	main.session._send_snapshot(1)
	main._refresh_hud()
	expect(main.modal == shop and sell.button_pressed and root.gui_get_focus_owner() == sell,
		"shop snapshot refresh preserves its modal, sell tab, and keyboard focus")
	var payout: int = 3 * World.CROPS.radish.price
	expect(harvest.is_visible_in_tree() and harvest.button_pressed and not offer.disabled and offer.text.contains(str(payout)), "selected sale updates count and payout in place")
	offer.pressed.emit()
	expect(int(person.inventory.get("radish", 0)) == 0 and person.coins == payout, "sale removes the full stack and credits its exact payout")
	person.x = World.SPAWN.x
	person.y = World.SPAWN.y
	main.session._send_snapshot(1)
	press(KEY_ESCAPE)
	await process_frame
	press(KEY_C)
	for crop in World.CROPS:
		expect(card_button(main.modal, World.NAMES[crop + "_seed"]) != null, "seed picker offers " + crop)
	press(KEY_ESCAPE)
	await process_frame
	person.inventory.wood = 0
	main.session._send_snapshot(1)
	press(KEY_B)
	for kind in World.BUILD:
		var category := "基礎" if kind in Panels.FOUNDATIONS else "家具" if kind in Panels.FURNITURE else "生活"
		find_button(main.modal, category).pressed.emit()
		var item := card_button(main.modal, World.BUILD[kind].name, true)
		expect(item != null, "build category %s offers %s" % [category, kind])
		if item == null:continue
		item.pressed.emit()
		var current_person:Dictionary=main.session.snapshot.get("players",{}).get(main.session.own_id,{})
		var unlocked:bool=BuildFolio.unlocked(main,current_person,kind)
		var place:=main.modal.find_child("BuildPlace",true,false) as Button
		var status:=main.modal.find_child("BuildStatus",true,false) as Label
		expect(item.button_pressed and place!=null and status!=null and place.disabled==not unlocked and
			(status.text=="圖樣未解鎖" if not unlocked else status.text.begins_with("材料齊全") or status.text.begins_with("缺少材料")),
			"selected %s shows the matching lock state" % kind)
	find_button(main.modal, "基礎").pressed.emit()
	card_button(main.modal, World.BUILD.floor.name, true).pressed.emit()
	var floor_button := button_with_prefix(main.modal, "材料不足")
	expect(floor_button != null and not floor_button.disabled,
		"unaffordable unlocked recipe remains selectable and shows missing materials")
	var inventory_before: Dictionary = person.inventory.duplicate(true)
	if floor_button != null and not floor_button.disabled:
		floor_button.pressed.emit()
	expect(main.modal == null and main.building == "floor" and main.selected == "build",
		"selecting the unaffordable recipe equips the build tool")
	expect(person.inventory == inventory_before, "selecting a recipe does not spend materials")
	var target := Vector2i(39, 34)
	var result := world.act(main.session.profile.token, "phase3-unaffordable-floor", "build", target, "floor")
	expect(not result.ok and result.get("message", result.get("msg", "")).contains("材料"),
		"the authoritative world rejects a build with missing materials")
	expect(person.inventory == inventory_before and not world.state.ground.has(World.key(target)),
		"rejected placement consumes no materials and leaves the tile unchanged")
	await process_frame

func check_inventory(size: Vector2i) -> void:
	root.content_scale_size = size
	root.size = size
	await process_frame
	press(KEY_TAB)
	await process_frame
	await process_frame
	var viewport := root.get_visible_rect()
	expect(Vector2i(viewport.size) == size, "effective viewport size is %s" % size)
	var backpack: PanelContainer = main.modal
	expect(is_instance_valid(backpack), "Tab opens backpack at %s" % size)
	if not is_instance_valid(backpack):
		return
	expect(viewport.encloses(backpack.get_global_rect()), "backpack fits %s" % size)
	var item := find_label(backpack, "木材")
	expect(item != null, "backpack lists carried wood")
	if item != null:
		var font := item.get_theme_font("font")
		var font_size := item.get_theme_font_size("font_size")
		var text_width := font.get_string_size("木材", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		expect(item.size.x >= text_width + 1.0, "wood label fits its name horizontally at %s: %.1f px" % [size, item.size.x])
		var line_count := item.get_line_count()
		var explicit_lines := item.text.count("\n") + 1
		expect(line_count <= explicit_lines, "backpack does not wrap item names at %s: %d lines for %d rows" % [size, line_count, explicit_lines])
	var point := Vector2(640, 395)
	expect(not main._world_pointer_allowed(point), "open modal blocks world targeting")
	press(KEY_B)
	expect(main.modal == backpack, "build shortcut cannot replace an open backpack")
	var previous_tool: String = main.selected
	press(KEY_F)
	expect(main.selected == previous_tool, "world tool shortcuts are suspended in a modal")
	var click := InputEventMouseButton.new()
	click.pressed = true
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = point
	main.action_clock = 0.0
	main._unhandled_input(click)
	expect(main.action_clock == 0.0, "mouse click cannot dispatch a world action during a modal")
	press(KEY_ESCAPE)
	await process_frame
	expect(main.modal == null and not is_instance_valid(backpack), "Esc closes and releases the backpack")
	expect(main._world_pointer_allowed(point), "closing the modal restores world targeting")
	for shortcut in [[KEY_1, "hoe"], [KEY_3, "water"], [KEY_F, "fish"], [KEY_T, "plant_tree"], [KEY_R, "move_object"]]:
		press(shortcut[0])
		expect(main.selected == shortcut[1], "tool shortcut restores %s" % shortcut[1])
	for entry in [["_build_menu", []], ["_seed_menu", []], ["_shop", []],
			["_board", []], ["_resident_menu", ["aru"]], ["_journal", []], ["_collection_menu", []]]:
		main.callv(entry[0], entry[1])
		await process_frame
		await process_frame
		var panel: Control = main.modal
		expect(is_instance_valid(panel) and viewport.encloses(panel.get_global_rect()),
			"%s modal fits %s: %s" % [entry[0], size, panel.get_global_rect() if is_instance_valid(panel) else "missing"])
		if is_instance_valid(panel):
			for scroll in panel.find_children("*", "ScrollContainer", true, false):
				expect(panel.get_global_rect().encloses(scroll.get_global_rect()),
					"%s scroll viewport fits its modal at %s" % [entry[0], size])
		press(KEY_ESCAPE)
		await process_frame

func run() -> void:
	create_timer(8.0).timeout.connect(func(): quit(1))
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	main.set_process(false)
	main.sound.volume = 0.0
	var save_path := "user://ui-phase3-%s.json" % Time.get_ticks_usec()
	var err: int = main.session.host(28693, "島民", save_path)
	expect(err == OK, "isolated local session opens")
	if err != OK:
		quit(1)
		return
	var world: World = main.session.world
	main._refresh_hud()
	expect(main.village_art_preview, "preview flag is enabled")
	await check_inventory(Vector2i(1280, 800))
	await check_inventory(Vector2i(1280, 720))
	await check_catalogs(world)
	main.playing = false
	main.session.shutdown()
	for suffix in ["", ".bak"]:
		if FileAccess.file_exists(save_path + suffix):DirAccess.remove_absolute(save_path + suffix)
	main.queue_free()
	await process_frame
	print("UI_PHASE3_TESTS checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)

