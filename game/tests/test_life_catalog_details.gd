extends SceneTree

const World = preload("res://scripts/world.gd")
const CELL := Vector2i(38, 33)

var failures := 0
var checks := 0
var app

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func button_named(title: String, node: Node) -> Button:
	if node is Button and (node.text == title or node.tooltip_text == title):
		return node
	for child in node.get_children():
		var match_button := button_named(title, child)
		if match_button != null:
			return match_button
	return null

const SHIP_HINT := "第一章出貨請用渡口出貨箱。"
const PICNIC_HINT := "這裡會出售全部。野餐需留蘿蔔和小麥各兩份。"

func shop_description(node: Node) -> Label:
	if node is Label and node.text.begins_with("持有 ") and node.text.contains("單價"):
		return node
	for child in node.get_children():
		var found := shop_description(child)
		if found != null:
			return found
	return null

func shop_text() -> String:
	var label: Label = shop_description(app.modal) if app.modal != null else null
	return label.text if label != null else ""

func check_shop_guidance(world, person: Dictionary) -> void:
	world.state.chapter_one.shipped = false
	world.state.picnic = false
	person.inventory.radish = 3
	app.life_panels.shop(app)
	var description := shop_text()
	expect(description.begins_with("持有 5 · 單價 12 鈴幣"), "shop opens on the buying tab with seed details")
	expect(not description.contains(SHIP_HINT) and not description.contains(PICNIC_HINT), "buying tab is not labelled with selling guidance")
	expect(button_named("買 1 份 · 12 鈴幣", app.modal) != null, "buying tab offers a single seed purchase")
	button_named("出售", app.modal).pressed.emit()
	description = shop_text()
	expect(description.begins_with("持有 3 · 單價 24 鈴幣"), "selling tab shows held radishes and sale price")
	expect(description.contains(SHIP_HINT), "selling before the chapter shipment points to the shipping box")
	expect(description.contains(PICNIC_HINT), "selling radishes before the picnic warns to reserve two")
	expect(button_named("出售全部 3 件 · 共 72 鈴幣", app.modal) != null, "radish offer sells the whole stack")
	button_named(World.NAMES.wheat, app.modal).pressed.emit()
	description = shop_text()
	expect(description.contains(SHIP_HINT) and description.contains(PICNIC_HINT), "selling wheat before the picnic warns to reserve two")
	button_named(World.NAMES.lettuce, app.modal).pressed.emit()
	description = shop_text()
	expect(description.contains(SHIP_HINT) and not description.contains(PICNIC_HINT), "non-picnic crops omit the reserve warning")
	button_named(World.NAMES.radish, app.modal).pressed.emit()
	world.state.chapter_one.shipped = true
	app.life_panels.refresh(app)
	description = shop_text()
	expect(not description.contains(SHIP_HINT) and description.contains(PICNIC_HINT), "shipping box hint disappears after the chapter shipment")
	world.state.picnic = true
	app.life_panels.refresh(app)
	description = shop_text()
	expect(not description.contains(SHIP_HINT) and not description.contains(PICNIC_HINT), "reserve warning disappears after the picnic")
	expect(description.begins_with("持有 3 · 單價 24 鈴幣"), "plain sale details remain after guidance clears")
	world.state.chapter_one.shipped = false
	world.state.picnic = false
	button_named("買種子", app.modal).pressed.emit()
	description = shop_text()
	expect(description.begins_with("持有 5 · 單價 12 鈴幣"), "returning to buying shows radish seed details")
	expect(not description.contains(SHIP_HINT) and not description.contains(PICNIC_HINT), "buying tab stays free of selling guidance even before shipment and picnic")

func run() -> void:
	app = load("res://main.tscn").instantiate()
	root.add_child(app)
	app.set_process(false)
	var world = World.new()
	world.add_player("tester", "島民")
	var person: Dictionary = world.state.players.tester
	app.session.snapshot = world.state
	app.session.own_id = "tester"
	var key: String = World.key(CELL)
	app.life_panels.seed_menu(app)
	button_named(World.NAMES.sapling, app.modal).pressed.emit()
	button_named("選擇樹苗  T", app.modal).pressed.emit()
	expect(app.selected == "plant_tree" and app.modal == null, "tree selection selects the planting tool")
	world.state.objects[key] = {"type": "stove"}
	app.life_panels.cook(app, CELL)
	var enqueue:=app.modal.find_child("CookingEnqueue",true,false) as Button
	expect(enqueue!=null and enqueue.disabled, "soup requires radishes")
	person.inventory.radish = 2
	app.CookingQueueUI.refresh(app)
	expect(enqueue!=null and not enqueue.disabled, "live inventory unlocks the recipe")
	world.state.objects[key].job = {"kind": "soup", "ready": 10.0, "owner": "other"}
	app.CookingQueueUI.refresh(app)
	var claim:=app.modal.find_child("CookingClaim",true,false) as Button
	expect(claim!=null and claim.disabled, "unfinished cooking cannot be claimed")
	var cancel:=app.modal.find_child("CookingCancel_legacy",true,false) as Button
	expect(cancel==null or cancel.disabled, "another owner's cooking cannot be cancelled")
	world.state.time = 10.0
	app.CookingQueueUI.refresh(app)
	expect(claim!=null and not claim.disabled, "ready shared dish is claimable")
	world.state.objects[key] = {"type": "chest", "items": {"radish": 1}}
	app.life_panels.chest(app, CELL)
	button_named(World.NAMES.radish, app.modal).pressed.emit()
	expect(not button_named("存入 1 件", app.modal).disabled and not button_named("取出 1 件", app.modal).disabled, "held and stored item supports both actions")
	world.state.objects[key].items.radish = 0
	app.life_panels.refresh(app)
	expect(button_named("取出 1 件", app.modal).disabled, "empty chest amount disables withdrawal in place")
	check_shop_guidance(world, person)
	app.life_panels.updates.clear()
	app.queue_free()
	await process_frame
	print("LIFE_CATALOG_DETAILS_TESTS checks=%d failures=%d" % [checks, failures])
	quit(0 if failures == 0 else 1)
