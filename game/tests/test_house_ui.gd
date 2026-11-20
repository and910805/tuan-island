extends SceneTree
## Native UI test for 小屋結構檢查 (house_ui.gd) reached through the real build catalog.
## FIXTURE, not human play: the house is written straight into a local World and
## pushed to the app as a snapshot; the app is then entered through its real
## _entered() / _state_changed() / _refresh_hud() path so HUD and world view
## reflect that snapshot. Optional: --qa-preview [--qa-output=DIR] saves
## empty/incomplete/complete fixture PNGs.

const World = preload("res://scripts/world.gd")
const HouseUI = preload("res://scripts/house_ui.gd")
const BuildThumbnail = preload("res://scripts/pixel_build_thumbnail.gd")
const EXTENTS := [Vector2i(1024, 640), Vector2i(1280, 800)]
const FORBIDDEN := ["第一個家", "首個家", "第一間", "章節完成", "已獲得", "領取獎勵", "獎勵", "居住安全"]

var checks := 0
var failures := 0
var app
var world
var entered := false

func _initialize() -> void:
	call_deferred("run")

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error("FAIL " + message)

func find_all(node: Node, type_name: String) -> Array[Control]:
	var matches: Array[Control] = []
	if node is Control and node.is_visible_in_tree() and node.is_class(type_name):
		matches.append(node)
	for child in node.get_children():
		matches.append_array(find_all(child, type_name))
	return matches

func modal_text() -> String:
	var parts := PackedStringArray()
	for control in find_all(app.modal, "Label") + find_all(app.modal, "Button"):
		parts.append(control.text)
	return "\n".join(parts)

func clear_spot(origin: Vector2i) -> bool:
	for y in range(origin.y - 1, origin.y + 5):
		for x in range(origin.x - 1, origin.x + 5):
			var cell := Vector2i(x, y)
			var tile: String = World.key(cell)
			if world.resource(cell) != "" or world.blocked(cell) or world.protected(cell):
				return false
			for layer in ["objects", "ground", "roofs", "crops", "forest"]:
				if world.state[layer].has(tile):
					return false
	return true

func find_spot() -> Vector2i:
	for y in range(18, 52):
		for x in range(14, 66):
			if clear_spot(Vector2i(x, y)):
				return Vector2i(x, y)
	return Vector2i(-1, -1)

func piece(kind: String) -> Dictionary:
	var result := {"type": kind, "owner": "tester", "items": {}}
	if kind == "door":
		result.open = false
	return result

## 4x4 outline with a 2x2 interior; the door is on the top edge.
func place_house(origin: Vector2i, roofed: bool, bed: bool) -> void:
	for y in 4:
		for x in 4:
			var cell := origin + Vector2i(x, y)
			var tile: String = World.key(cell)
			if x in [1, 2] and y in [1, 2]:
				world.state.ground[tile] = piece("floor")
				if roofed:
					world.state.roofs[tile] = piece("roof")
			else:
				world.state.objects[tile] = piece("door" if cell == origin + Vector2i(1, 0) else "wall")
	if bed:
		world.state.objects[World.key(origin + Vector2i(2, 2))] = piece("bed")

## Fixture step: move the tester, publish the snapshot and refresh HUD/view from it.
func stand(cell: Vector2i) -> void:
	world.state.players.tester.x = cell.x + 0.5
	world.state.players.tester.y = cell.y + 0.5
	app.session.snapshot = world.region_snapshot("home")
	if not entered:
		app._entered()
		entered = true
	app._state_changed(app.session.snapshot, app.session.own_id)
	app._refresh_hud()

func open_from_catalog(case_name: String) -> void:
	app._build_menu()
	await process_frame
	var entry: Button = app.modal.find_child("HouseCheck", true, false)
	expect(entry != null and app.modal.get_meta("catalog", false), "%s: HouseCheck lives in the real build catalog" % case_name)
	if entry == null:
		return
	expect(entry.text == HouseUI.TITLE and not entry.disabled, "%s: entry is labelled and enabled" % case_name)
	entry.pressed.emit()
	for frame in 4:
		await process_frame

func part(kind: String) -> Button:
	return app.modal.find_child("HousePart_" + kind, true, false) if is_instance_valid(app.modal) else null

func visible_in(control: Control, area: Rect2) -> bool:
	return control != null and control.is_visible_in_tree() and area.encloses(control.get_global_rect())

func verify_layout(case_name: String) -> void:
	for extent in EXTENTS:
		root.size = extent
		for frame in 4:
			await process_frame
		var bounds := root.get_visible_rect()
		expect(bounds.encloses(app.modal.get_global_rect()), "%s: modal fits %s" % [case_name, extent])
		var scroll: ScrollContainer = app.modal.find_child("ModalScroll", true, false)
		expect(scroll != null, "%s: modal scroll present at %s" % [case_name, extent])
		if scroll == null:
			continue
		var area := scroll.get_global_rect()
		var body: Control = scroll.get_child(0) if scroll.get_child_count() > 0 else null
		expect(not scroll.get_v_scroll_bar().visible, "%s: no vertical scrollbar at %s" % [case_name, extent])
		expect(scroll.scroll_vertical == 0 and body != null and body.get_combined_minimum_size().y <= area.size.y + 0.5,
			"%s: content fits without vertical scrolling at %s" % [case_name, extent])
		for kind in HouseUI.PARTS:
			expect(visible_in(part(kind), area) and bounds.encloses(part(kind).get_global_rect()),
				"%s: %s part button visible without scrolling at %s" % [case_name, kind, extent])
		var footer: Control = app.modal.find_child("HouseFooter", true, false)
		expect(visible_in(footer, bounds) and not scroll.is_ancestor_of(footer), "%s: footer stays visible outside the scroll at %s" % [case_name, extent])
		for node_name in ["HouseRecheck", "HouseBack"]:
			var control: Control = app.modal.find_child(node_name, true, false)
			expect(visible_in(control, bounds) and footer.get_global_rect().encloses(control.get_global_rect()) and control.size.y >= 32,
				"%s: %s fully visible without scrolling at %s" % [case_name, node_name, extent])
		var guide: Control = app.modal.find_child("HouseNext", true, false)
		expect(visible_in(guide, area), "%s: next-step section visible at %s" % [case_name, extent])
		# Cards sit on one horizontal row, each with its 1x pixel thumbnail.
		var previous := -INF
		var row_y := NAN
		for kind in HouseUI.PARTS:
			var card: Control = app.modal.find_child("HouseCard_" + kind, true, false)
			if not visible_in(card, area):
				expect(false, "%s: %s card visible at %s" % [case_name, kind, extent])
				continue
			var rect := card.get_global_rect()
			if is_nan(row_y):
				row_y = rect.position.y
			expect(absf(rect.position.y - row_y) < 1.0 and rect.position.x > previous and rect.size.x <= 140,
				"%s: %s card is a compact horizontal card at %s" % [case_name, kind, extent])
			previous = rect.end.x - 1.0
			var thumb: Control = card.find_child("Thumb", true, false)
			expect(thumb != null and thumb.size == HouseUI.THUMB_SIZE and thumb.get_global_transform().get_scale() == Vector2.ONE
				and rect.encloses(thumb.get_global_rect()), "%s: %s thumbnail at integer 1x scale at %s" % [case_name, kind, extent])
		if guide != null and not is_nan(row_y):
			var cards_box: Control = app.modal.find_child("HouseCards", true, false)
			expect(cards_box != null and guide.get_global_rect().position.y >= cards_box.get_global_rect().end.y,
				"%s: next-step section sits beneath the cards at %s" % [case_name, extent])

func verify_common(case_name: String) -> void:
	expect(is_instance_valid(app.modal) and app.modal.get_meta("life_modal_layout", "") == HouseUI.LAYOUT, "%s: dedicated house_check layout hook" % case_name)
	if not is_instance_valid(app.modal):
		return
	expect(app.modal.get_meta("house_check_size", Vector2.ZERO) == HouseUI.SIZE, "%s: requested size metadata" % case_name)
	var text := modal_text()
	expect(text.contains(HouseUI.TITLE), "%s: title shown" % case_name)
	expect(text.contains("2×2") and text.contains("自動蓋屋頂") and text.contains("手動") and text.contains("屋外"),
		"%s: 2x2 / automatic roof on closure / manual roof for old rooms / exterior route note shown" % case_name)
	var roof_recipe: Dictionary = World.BUILD.roof
	expect(text.contains("木材 %d、纖維 %d" % [int(roof_recipe.wood), int(roof_recipe.fiber)]), "%s: note states the per-tile automatic roof cost" % case_name)
	for word in FORBIDDEN:
		expect(not text.contains(word), "%s: no reward/chapter/safety wording '%s'" % [case_name, word])
	var missing: Label = app.modal.find_child("HouseMissing", true, false)
	var note: Label = app.modal.find_child("HouseNote", true, false)
	expect(note != null and missing != null, "%s: reasons and note present" % case_name)
	if missing != null:
		expect(not missing.text.is_empty() and not missing.text.contains("\n") and missing.find_parent("HouseNext") != null,
			"%s: single concise next-step line in the next-step section" % case_name)
	if note != null:
		expect(note.get_line_count() <= 3, "%s: note stays short" % case_name)
	# Compact cards replace the old desktop checklist rows.
	expect(app.modal.find_child("HouseChecks", true, false) == null and app.modal.find_child("HouseRow_*", true, false) == null,
		"%s: no long checklist rows" % case_name)
	expect(not text.contains("· 牆") and text.count("\n· ") == 0, "%s: no duplicate bullet list" % case_name)
	var cards: Control = app.modal.find_child("HouseCards", true, false)
	expect(cards is HBoxContainer and cards.get_child_count() == HouseUI.PARTS.size(), "%s: five horizontal part cards" % case_name)
	for kind in HouseUI.PARTS:
		var card: Control = app.modal.find_child("HouseCard_" + kind, true, false)
		var button := part(kind)
		var picture: Node = card.find_child("Picture", true, false) if card != null else null
		var title: Label = card.find_child("Name", true, false) if card != null else null
		var status: Label = card.find_child("Detail", true, false) if card != null else null
		expect(card != null and button != null and card.is_ancestor_of(button), "%s: %s card holds HousePart_%s" % [case_name, kind, kind])
		expect(picture != null and picture.get_script() == BuildThumbnail and str(picture.get("kind")) == kind, "%s: %s card uses the real build thumbnail" % [case_name, kind])
		expect(title != null and title.text == HouseUI.PART_NAMES[kind], "%s: %s card named" % [case_name, kind])
		expect(status != null and not status.text.is_empty() and status.text.length() <= 10, "%s: %s card has a short status" % [case_name, kind])
		expect(button != null and button.text.length() <= 4, "%s: %s card button is compact" % [case_name, kind])

func capture(case_name: String) -> void:
	if not "--qa-preview" in OS.get_cmdline_user_args():
		return
	var directory: String = app.arg_value("qa-output", "user://house-ui-qa")
	DirAccess.make_dir_recursive_absolute(directory)
	for extent in EXTENTS:
		root.size = extent
		for frame in 3:
			await process_frame
		# Fixture capture: in-game state (menu gone, HUD up), no transient toast over the panel.
		app.toast_time = 0.0
		app.toast.hide()
		for frame in 30:
			if app.modal.modulate.a >= 1.0:
				break
			await process_frame
		await RenderingServer.frame_post_draw
		expect(app.playing and not app.menu.visible and app.hud.visible, "%s: capture shows the entered island, not the login menu at %s" % [case_name, extent])
		expect(not app.toast.visible and app.modal.is_visible_in_tree() and app.modal.modulate.a >= 1.0, "%s: capture shows the panel without a toast at %s" % [case_name, extent])
		var image := root.get_texture().get_image()
		var path := directory.path_join("house-%s-%dx%d.png" % [case_name, extent.x, extent.y])
		expect(image != null and image.save_png(path) == OK, "qa capture saved " + path)

func press_escape() -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.physical_keycode = KEY_ESCAPE
	event.pressed = true
	expect(app.playing, "Esc is delivered to an entered (playing) app")
	app._input(event)

func run() -> void:
	app = load("res://main.tscn").instantiate()
	app.village_art_preview = true
	root.add_child(app)
	app.set_process(false)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	world = World.new()
	world.add_player("tester", "島民")
	app.session.set_physics_process(false)
	app.session.own_id = "tester"
	app.session.world = world
	app.session.peers[1] = "tester"

	# Invalid inputs stay safe and never claim a house.
	for bad in [null, {}, {"players": {}}, {"players": {"tester": {"x": "a", "y": 1}}}]:
		var safe := HouseUI.evaluate(bad, "tester")
		expect(not safe.found and not safe.complete and not safe.missing.is_empty(), "invalid snapshot is safe: %s" % [bad])

	var origin := find_spot()
	expect(origin.x >= 0, "found clear home-region ground for the fixture")
	if origin.x < 0:
		finish()
		return

	# Existing catalog behaviour is preserved: four tabs and the original place flow.
	# First valid snapshot: stand() enters the app through its real _entered().
	stand(origin + Vector2i(1, -2))
	expect(app.playing and not app.menu.visible and app.hud.visible, "fixture entered the island through _entered(); login menu hidden")
	expect(app.view != null and not app.view.data.is_empty(), "world view refreshed from the fixture snapshot")
	for extent in EXTENTS:
		root.size = extent
		app._build_menu()
		for frame in 3:
			await process_frame
		var tabs := find_all(app.modal, "Button").filter(func(b): return b.text in ["全部", "基礎", "家具", "生活"])
		expect(tabs.size() == 4, "catalog keeps its four tabs at %s" % extent)
		var entry: Button = app.modal.find_child("HouseCheck", true, false)
		expect(entry != null and root.get_visible_rect().encloses(entry.get_global_rect()), "HouseCheck visible at %s" % extent)
		expect(root.get_visible_rect().encloses(app.modal.get_global_rect()), "build catalog fits %s" % extent)
	var place: Array = find_all(app.modal, "Button").filter(func(b): return b.text in ["選擇配方", "材料不足，仍可選擇"])
	expect(place.size() == 1, "original place button still present")
	if place.size() == 1:
		place[0].pressed.emit()
		expect(app.building == "floor" and app.selected == "build" and app.modal == null, "original place button selects floor recipe and closes")

	# Empty: nothing built near the player.
	var empty_before: Dictionary = app.session.snapshot.duplicate(true)
	await open_from_catalog("empty")
	verify_common("empty")
	var result: Dictionary = app.modal.get_meta("house_check_result", {})
	expect(not result.get("found", true) and not result.get("complete", true), "empty: no interior found")
	expect(part("floor") != null and not part("floor").disabled and part("floor").text.begins_with("下一步"), "empty: floor is the next part")
	expect(part("roof") != null and part("roof").disabled and part("roof").text == "自動", "empty: roof comes automatically with closure, no manual pick yet")
	await verify_layout("empty")
	await capture("empty")
	expect(app.session.snapshot == empty_before, "empty: opening never mutates the snapshot")
	press_escape()
	expect(app.modal == null, "empty: Esc closes the house check")

	# Incomplete: floor, walls and door; no roof, no bed.
	place_house(origin, false, false)
	stand(origin + Vector2i(1, 1))
	var state_before: Dictionary = world.state.duplicate(true)
	var snapshot_before: Dictionary = app.session.snapshot.duplicate(true)
	await open_from_catalog("incomplete")
	verify_common("incomplete")
	result = app.modal.get_meta("house_check_result", {})
	expect(result.get("found", false) and int(result.get("area", 0)) == 4 and int(result.get("door_count", 0)) == 1, "incomplete: 2x2 interior with one door")
	expect(int(result.get("roof_missing", 0)) == 4 and int(result.get("bed_count", -1)) == 0 and not result.get("complete", true), "incomplete: roof and bed missing")
	expect(not result.get("missing", []).is_empty(), "incomplete: Chinese reasons provided")
	for kind in ["floor", "wall", "door"]:
		expect(part(kind) != null and part(kind).disabled and part(kind).text == "已符合", "incomplete: %s satisfied and disabled" % kind)
	expect(part("bed") != null and not part("bed").disabled and part("bed").text.begins_with("下一步"), "incomplete: bed is the next part")
	# Legacy closed-but-roofless room (fixture written without auto roofs): manual roofing stays available.
	expect(part("roof") != null and not part("roof").disabled and part("roof").text == "選擇", "incomplete: legacy roofless room can still be roofed manually")
	expect(not modal_text().contains("每格都有屋頂") and not modal_text().contains("結構條件都已符合"), "incomplete: never claims the roof or room is done")
	await verify_layout("incomplete")
	await capture("incomplete")
	var inventory_before: Dictionary = world.state.players.tester.inventory.duplicate(true)
	if part("bed") != null:
		part("bed").pressed.emit()
	expect(app.building == "bed" and app.selected == "build" and app.modal == null, "incomplete: part button preselects bed via build tool and closes")
	expect(world.state == state_before and app.session.snapshot == snapshot_before, "incomplete: no auto-build, deduction or state change")
	expect(world.state.players.tester.inventory == inventory_before, "incomplete: inventory untouched")

	# Recheck and back buttons keep the original flows.
	await open_from_catalog("recheck")
	var back: Button = app.modal.find_child("HouseBack", true, false)
	if back != null:
		back.pressed.emit()
		await process_frame
	expect(is_instance_valid(app.modal) and app.modal.get_meta("catalog", false) and app.modal.find_child("HouseCheck", true, false) != null, "back returns to build catalog")
	app._close_modal()

	# Unsealed (door replaced by wall): roofs wait for closure; no manual roof offered.
	world.state.objects[World.key(origin + Vector2i(1, 0))] = piece("wall")
	stand(origin + Vector2i(1, 1))
	await open_from_catalog("unsealed")
	verify_common("unsealed")
	expect(part("door") != null and not part("door").disabled and part("door").text.begins_with("下一步"), "unsealed: door is the next part")
	expect(part("roof") != null and part("roof").disabled and part("roof").text == "自動", "unsealed: roof marked automatic, not a manual pick")
	var roof_card: Control = app.modal.find_child("HouseCard_roof", true, false)
	var roof_detail: Label = roof_card.find_child("Detail", true, false) if roof_card != null else null
	expect(roof_detail != null and roof_detail.text.contains("自動") and not roof_detail.text.contains("缺"), "unsealed: roof card explains automatic roofing instead of a shortfall")
	await verify_layout("unsealed")
	app._close_modal()

	# Complete: roofs and a reachable bed.
	place_house(origin, true, true)
	stand(origin + Vector2i(1, 1))
	await open_from_catalog("complete")
	verify_common("complete")
	result = app.modal.get_meta("house_check_result", {})
	expect(result.get("complete", false) and result.get("reachable_bed", false), "complete: structure passes")
	var contributors: Array = result.get("contributors", [])
	expect(contributors.size() == 1 and str(contributors[0]) == "tester", "complete: single contributor")
	for kind in HouseUI.PARTS:
		expect(part(kind) != null and part(kind).disabled, "complete: %s button disabled" % kind)
	var status: Label = app.modal.find_child("HouseStatus", true, false)
	var facts: Label = app.modal.find_child("HouseFacts", true, false)
	expect(status != null and status.text == "結構條件都已符合", "complete: structural headline")
	expect(facts != null and facts.text.contains("參與島民 1 位") and facts.text.contains("室內 4 格"), "complete: area and contributor count")
	await verify_layout("complete")
	await capture("complete")
	press_escape()
	expect(app.modal == null, "complete: Esc closes the house check")
	await roof_quote_flow(origin)
	finish()

## Stand-in for res://scripts/auto_roof_preview.gd so the client confirmation flow is
## tested independently of the server commit (Root tests the real quote separately).
class RoofQuoteStub:
	extends RefCounted
	var reply: Dictionary = {}
	var calls: Array = []
	func quote(snapshot, actor, action, at, extra = ""):
		calls.append({"actor": actor, "action": action, "at": at, "extra": extra, "snapshot": typeof(snapshot) == TYPE_DICTIONARY})
		return reply.duplicate(true)

func roof_reply(add: int, remove: int, wood: int, fiber: int, own_back: int, other_back: int) -> Dictionary:
	var added := {}
	for i in add:
		added["%d,0" % i] = {"type": "roof", "owner": "tester", "items": {}, "auto": true}
	var removed: Array[String] = []
	for i in remove:
		removed.append("%d,9" % i)
	var refunds := {}
	if own_back > 0:
		refunds["tester"] = {"wood": own_back}
	if other_back > 0:
		refunds["7f3a0c9be21d44aa"] = {"wood": other_back, "fiber": other_back * 3}
	return {"ok": true, "message": "", "plan": {"add": added, "remove": removed, "cost": {}, "refunds": {}},
		"base_cost": {"wood": 1}, "total_cost": {"wood": wood, "fiber": fiber}, "base_refund": {}, "refunds": refunds, "affected": add + remove > 0}

func roof_button(node_name: String) -> Button:
	return app.modal.find_child(node_name, true, false) if is_instance_valid(app.modal) else null

func verify_roof_layout(case_name: String) -> void:
	for extent in EXTENTS:
		root.size = extent
		for frame in 4:
			await process_frame
		var bounds := root.get_visible_rect()
		expect(is_instance_valid(app.modal) and bounds.encloses(app.modal.get_global_rect()), "%s: roof modal fits %s" % [case_name, extent])
		var scroll: ScrollContainer = app.modal.find_child("ModalScroll", true, false)
		if scroll == null:
			expect(false, "%s: roof modal scroll present at %s" % [case_name, extent])
			continue
		var area := scroll.get_global_rect()
		var body: Control = scroll.get_child(0) if scroll.get_child_count() > 0 else null
		expect(not scroll.get_v_scroll_bar().visible and body != null and body.get_combined_minimum_size().y <= area.size.y + 0.5,
			"%s: roof modal has no vertical scrolling at %s" % [case_name, extent])
		for node_name in ["AutoRoofQuote", "RoofConfirm", "RoofCancel"]:
			var control: Control = app.modal.find_child(node_name, true, false)
			expect(visible_in(control, area) and bounds.encloses(control.get_global_rect()), "%s: %s fully visible at %s" % [case_name, node_name, extent])
		var thumb: Control = app.modal.find_child("RoofThumb", true, false)
		expect(thumb != null and thumb.get_global_transform().get_scale() == Vector2.ONE, "%s: roof thumbnail at 1x at %s" % [case_name, extent])

func roof_quote_flow(origin: Vector2i) -> void:
	var stub := RoofQuoteStub.new()
	app.auto_roof_preview = stub
	# Fixture: keep perform() local-only; session.counter counts each original perform call.
	app.session.accepting = false
	app._close_modal()
	app.building = "wall"
	app._select_tool("build")
	var at := origin + Vector2i(6, 0)

	# Unaffected: original single-click perform, no modal.
	stub.reply = roof_reply(0, 0, 1, 0, 0, 0)
	var sent: int = app.session.counter
	app._perform_build_action("build", at, "wall")
	expect(app.session.counter == sent + 1 and app.modal == null, "roof quote: unaffected build forwards once without a modal")
	expect(stub.calls.size() == 1 and stub.calls[0].actor == str(app.session.own_id) and stub.calls[0].action == "build" and stub.calls[0].at == at and stub.calls[0].extra == "wall",
		"roof quote: quoted with the original action/at/extra for the local player")

	# Non-build tools are never quoted.
	sent = app.session.counter
	app._perform_build_action("hoe", at, "")
	expect(app.session.counter == sent + 1 and stub.calls.size() == 1 and app.modal == null, "roof quote: farming actions bypass the quote")

	# Affected: modal shows counts and totals; nothing sent yet.
	stub.reply = roof_reply(4, 1, 5, 12, 1, 1)
	sent = app.session.counter
	app._perform_build_action("build", at, "wall")
	expect(app.session.counter == sent and is_instance_valid(app.modal) and app.modal.get_meta("life_modal_layout", "") == "roof_confirm",
		"roof quote: affected build opens confirmation without performing")
	expect(app.modal.get_meta("roof_request", {}) == {"action": "build", "at": at, "extra": "wall"}, "roof quote: pending request keeps original args")
	var text := modal_text()
	expect(text.contains("新增 4 格") and text.contains("拆除 1 格") and text.contains("×5") and text.contains("×12"), "roof quote: roof counts and total cost shown")
	expect(app.modal.find_child("AutoRoofMine", true, false) != null and text.contains("其他 1 位"), "roof quote: own refund and aggregate others shown")
	expect(not text.contains("7f3a0c9be21d44aa") and not text.contains("tester"), "roof quote: no raw owner IDs shown")
	expect(text.contains("由你出資") and text.contains("退回當初出資"), "roof quote: actor pays, refunds go to original payers")
	expect(not app.preview_toolbar.is_visible_in_tree(), "roof quote: world HUD hidden behind the modal")
	await verify_roof_layout("roof quote")

	# Cancel: nothing sent, HUD restored.
	roof_button("RoofCancel").pressed.emit()
	await process_frame
	expect(app.modal == null and app.session.counter == sent, "roof quote: cancel sends nothing")
	expect(app.preview_toolbar.is_visible_in_tree(), "roof quote: HUD restored after cancel")

	# Esc: nothing sent.
	app._perform_build_action("build", at, "wall")
	press_escape()
	await process_frame
	expect(app.modal == null and app.session.counter == sent, "roof quote: Esc sends nothing")

	# Quote changes while open: redraw and require a second click.
	app._perform_build_action("build_area", at, "floor|%d|%d" % [at.x + 2, at.y + 2])
	stub.reply = roof_reply(4, 1, 6, 12, 1, 1)
	roof_button("RoofConfirm").pressed.emit()
	await process_frame
	expect(app.session.counter == sent and is_instance_valid(app.modal) and app.modal.find_child("AutoRoofChanged", true, false) != null,
		"roof quote: changed cost is shown again instead of being charged")
	expect(modal_text().contains("×6"), "roof quote: updated total shown")
	var confirm := roof_button("RoofConfirm")
	confirm.pressed.emit()
	confirm.pressed.emit()
	await process_frame
	expect(app.session.counter == sent + 1 and app.modal == null, "roof quote: confirm performs exactly once")
	expect(app.selected == "build" and not app.area_drag, "roof quote: build tool kept, no drag left running")

	app.auto_roof_preview = null
	app.session.accepting = true

func finish() -> void:
	if is_instance_valid(app):
		app._close_modal()
		app.queue_free()
	await process_frame
	print("HOUSE_UI_TESTS checks=%d failures=%d" % [checks, failures])
	quit(int(failures > 0))
