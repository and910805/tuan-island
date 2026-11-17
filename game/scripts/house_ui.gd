extends RefCounted
## 小屋結構檢查: a read-only view of HouseRooms.inspect for the current region.
## It never builds, deducts or saves; part buttons only preselect a build recipe
## through the same app.building / _select_tool("build") / _close_modal flow as
## the build catalog.
##
## Layout: a short status header, five compact horizontal pixel item cards
## (floor / wall / door / bed / roof), one concise next-step section and an
## always-visible footer (HouseRecheck / HouseBack). Sized to fit the 640x560
## house_check modal at 1024x640 and 1280x800 without vertical scrolling.
## Roofs are placed automatically when a floor ring is closed with a door; the roof
## card only offers the manual recipe for a closed room that is still roofless.

const HouseRooms = preload("res://scripts/house_rooms.gd")
const World = preload("res://scripts/world.gd")
const PixelTheme = preload("res://scripts/inventory_pixel_theme.gd")
const LifeTheme = preload("res://scripts/life_ui_theme.gd")
const BuildThumbnail = preload("res://scripts/pixel_build_thumbnail.gd")

const TITLE := "小屋結構檢查"
const LAYOUT := "house_check"
## Requested modal size for Root's main.gd layout hook (clamped to bounds - 48).
const SIZE := Vector2(640, 560)
const PARTS := ["floor", "wall", "door", "bed", "roof"]
const PART_NAMES := {"floor": "地板", "wall": "外牆", "door": "門口", "bed": "床鋪", "roof": "屋頂"}
## Native BuildThumbnail footprint (one 32px tile wide, tall enough for objects); shown at 1x.
const THUMB_SIZE := Vector2(32, 48)
## %d placeholders are the roof recipe's wood and fiber per tile (see note()).
const NOTE := "室內至少 2×2 格地板，外圈用牆、窗或門圍好；圍好時自動蓋屋頂（每格木材 %d、纖維 %d，施工者出資）。舊房間或門廊可手動蓋；屋外到門口的路請自己留好。"
const STEPS := {
	"floor": "鋪木地板，圍出至少 2×2 的室內。",
	"wall": "用牆、窗或門補上外圈缺口。",
	"door": "在外圈放一扇門。",
	"bed": "在室內放一張小床。",
	"roof": "這間還缺屋頂，可選草編屋頂逐格手動補上。",
}
const OK_COLOR := Color("4e7058")
const NEED_COLOR := Color("a4512f")
const TEXT_COLOR := Color("3d422d")
const NOTE_COLOR := Color("5d634a")

static func blank() -> Dictionary:
	return {"found": false, "cells": [], "area": 0, "door_count": 0, "roof_missing": 0, "gap_count": 0,
		"bed_count": 0, "reachable_bed": false, "complete": false, "contributors": [], "missing": [],
		"located": false, "at": Vector2i.ZERO}

static func local_cell(snapshot: Dictionary, own_id: String) -> Dictionary:
	var players = snapshot.get("players", {})
	if typeof(players) != TYPE_DICTIONARY or own_id.is_empty():
		return {"ok": false, "cell": Vector2i.ZERO}
	var person = players.get(own_id, {})
	if typeof(person) != TYPE_DICTIONARY:
		return {"ok": false, "cell": Vector2i.ZERO}
	var x = person.get("x", null)
	var y = person.get("y", null)
	if not (typeof(x) in [TYPE_INT, TYPE_FLOAT] and typeof(y) in [TYPE_INT, TYPE_FLOAT]):
		return {"ok": false, "cell": Vector2i.ZERO}
	if is_nan(float(x)) or is_nan(float(y)) or is_inf(float(x)) or is_inf(float(y)):
		return {"ok": false, "cell": Vector2i.ZERO}
	return {"ok": true, "cell": Vector2i(floori(float(x)), floori(float(y)))}

## Pure: reads the snapshot, returns a normalized copy of the helper result.
static func evaluate(snapshot, own_id: String) -> Dictionary:
	var result := blank()
	if typeof(snapshot) != TYPE_DICTIONARY or snapshot.is_empty():
		result.missing = ["目前沒有地區資料，回到島上後再檢查。"]
		return result
	var located := local_cell(snapshot, own_id)
	if not located.ok:
		result.missing = ["找不到你在這個地區的位置。"]
		return result
	result.located = true
	result.at = located.cell
	var raw = HouseRooms.inspect(snapshot, located.cell)
	if typeof(raw) != TYPE_DICTIONARY:
		result.missing = ["暫時無法檢查這裡的結構。"]
		return result
	for field in ["found", "reachable_bed", "complete"]:
		result[field] = bool(raw.get(field, false))
	for field in ["area", "door_count", "roof_missing", "gap_count", "bed_count"]:
		var value = raw.get(field, 0)
		result[field] = maxi(0, int(value)) if typeof(value) in [TYPE_INT, TYPE_FLOAT] else 0
	for field in ["cells", "contributors", "missing"]:
		var value = raw.get(field, [])
		result[field] = value.duplicate() if typeof(value) == TYPE_ARRAY else []
	return result

static func note() -> String:
	var recipe: Dictionary = World.BUILD.roof
	return NOTE % [int(recipe.get("wood", 0)), int(recipe.get("fiber", 0))]

## Floor ring closed with a door: the state in which automatic roofs are placed.
static func sealed(result: Dictionary) -> bool:
	return result.get("found", false) and int(result.get("area", 0)) >= 4 \
		and int(result.get("gap_count", 0)) == 0 and int(result.get("door_count", 0)) >= 1

## Roofs still to come automatically when the room is closed (nothing to build yet).
static func roof_automatic(result: Dictionary) -> bool:
	return not result.get("complete", false) and not sealed(result)

## Which build parts still help; reachability alone is not fixed by building.
## Roofs only need a manual build once the room is closed yet still roofless
## (e.g. a room finished before automatic roofs); before that they come with closure.
static func needs(result: Dictionary) -> Dictionary:
	var found: bool = result.get("found", false)
	return {
		"floor": not found or int(result.get("area", 0)) < 4,
		"wall": not found or int(result.get("gap_count", 0)) > 0,
		"door": int(result.get("door_count", 0)) < 1,
		"bed": int(result.get("bed_count", 0)) < 1,
		"roof": sealed(result) and int(result.get("roof_missing", 0)) > 0,
	}

static func next_part(result: Dictionary) -> String:
	if result.get("complete", false):
		return ""
	var need := needs(result)
	for kind in PARTS:
		if need[kind]:
			return kind
	return ""

static func row_ok(result: Dictionary, kind: String) -> bool:
	if kind == "door":
		return int(result.get("door_count", 0)) >= 1 and (result.get("reachable_bed", false) or int(result.get("bed_count", 0)) < 1)
	if kind == "bed":
		return int(result.get("bed_count", 0)) >= 1 and result.get("reachable_bed", false)
	if kind == "roof":
		return sealed(result) and int(result.get("roof_missing", 0)) == 0
	return not needs(result)[kind]

## Short card status (fits two lines of a ~110px card).
static func detail(result: Dictionary, kind: String) -> String:
	var found: bool = result.get("found", false)
	var beds := int(result.get("bed_count", 0))
	match kind:
		"floor":
			return "%d 格／需 4 格" % int(result.get("area", 0)) if found else "還沒圍出室內"
		"wall":
			if not found:
				return "圍住地板外圈"
			var gaps := int(result.get("gap_count", 0))
			return "外圈已圍好" if gaps == 0 else "缺口 %d 處" % gaps
		"door":
			var doors := int(result.get("door_count", 0))
			if doors < 1:
				return "需要 1 扇門"
			if beds > 0 and not result.get("reachable_bed", false):
				return "門內走不到床"
			return "門 %d 扇" % doors
		"bed":
			if beds < 1:
				return "需要 1 張床"
			return "床 %d 張" % beds if result.get("reachable_bed", false) else "床邊被擋住"
		"roof":
			if roof_automatic(result):
				return "圍好後自動蓋"
			var roofless := int(result.get("roof_missing", 0))
			return "每格都有屋頂" if roofless == 0 else "缺 %d 格屋頂" % roofless
	return ""

static func headline(result: Dictionary) -> String:
	if result.get("complete", false):
		return "結構條件都已符合"
	if not result.get("found", false):
		return "附近沒有找到小屋室內"
	return "小屋結構尚未完成"

## One concise next-step sentence; no duplicate checklist.
static func next_step(result: Dictionary) -> String:
	if result.get("complete", false):
		return "地板、牆、門、床與屋頂都符合結構條件。"
	if not result.get("located", false):
		var missing: Array = result.get("missing", [])
		return str(missing[0]) if not missing.is_empty() else "回到島上後再檢查。"
	var kind := next_part(result)
	if kind.is_empty():
		return "下一步：挪開擋路的家具，讓門內走得到床邊。"
	return "下一步：" + STEPS[kind]

static func choose_part(app, kind: String) -> void:
	if not World.BUILD.has(kind):
		return
	app.building = kind
	app.building_style = ""
	app._select_tool("build")
	app._close_modal()

static func _card_style(highlight: bool) -> StyleBoxTexture:
	var style := PixelTheme.texture_style("selected" if highlight else "normal", 3, 6)
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style

static func _part_card(app, result: Dictionary, kind: String, next: String) -> Dictionary:
	var ok := row_ok(result, kind)
	var needed: bool = needs(result)[kind] and not result.complete
	var card := PanelContainer.new()
	card.name = "HouseCard_" + kind
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size.x = 96
	card.add_theme_stylebox_override("panel", _card_style(kind == next))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 3)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(column)

	var holder := CenterContainer.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(holder)
	var frame := Control.new()
	frame.name = "Thumb"
	frame.custom_minimum_size = THUMB_SIZE
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	holder.add_child(frame)
	var picture := BuildThumbnail.new()
	picture.name = "Picture"
	picture.kind = kind
	frame.add_child(picture)

	var name_label: Label = app.label(PART_NAMES[kind], 16)
	name_label.name = "Name"
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_color_override("font_color", Color("fff1cc") if kind == next else TEXT_COLOR)
	column.add_child(name_label)

	var info: Label = app.label(detail(result, kind), 13)
	info.name = "Detail"
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	info.custom_minimum_size.y = 36
	var automatic := kind == "roof" and roof_automatic(result)
	info.add_theme_color_override("font_color", Color("ffe0a0") if kind == next else (NOTE_COLOR if automatic else (OK_COLOR if ok else NEED_COLOR)))
	column.add_child(info)

	var recipe_name: String = World.BUILD[kind].name
	var choose: Button = app.button("", func(): choose_part(app, kind))
	choose.name = "HousePart_" + kind
	choose.set_meta("house_part", kind)
	choose.custom_minimum_size = Vector2(0, 34)
	choose.add_theme_font_size_override("font_size", 14)
	choose.disabled = not needed
	if needed:
		choose.text = "下一步" if kind == next else "選擇"
		choose.tooltip_text = "選擇「%s」配方，再自己放到地上" % recipe_name
	elif automatic:
		choose.text = "自動"
		choose.tooltip_text = "牆與門圍好時自動蓋上，由完成圍合的人出資"
	else:
		choose.text = "已符合" if ok else "挪家具"
	column.add_child(choose)
	return {"card": card, "button": choose}

static func open(app) -> void:
	var result := evaluate(app.session.snapshot, str(app.session.own_id))
	var content: VBoxContainer = app._open_modal(TITLE)
	var modal: Control = app.modal
	modal.set_meta("life_modal_layout", LAYOUT)
	modal.set_meta("house_check", true)
	modal.set_meta("house_check_size", SIZE)
	modal.set_meta("house_check_result", result)
	modal.theme = PixelTheme.make(modal.theme if modal.theme else app.theme())
	modal.add_theme_stylebox_override("panel", PixelTheme.frame_style())
	modal.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	content.add_theme_constant_override("separation", 8)

	var summary := HBoxContainer.new()
	summary.name = "HouseSummary"
	summary.add_theme_constant_override("separation", 10)
	content.add_child(summary)
	var portrait := TextureRect.new()
	portrait.texture = LifeTheme.icon("aru")
	portrait.custom_minimum_size = Vector2(40, 40)
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	summary.add_child(portrait)
	var heading := VBoxContainer.new()
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_theme_constant_override("separation", 0)
	summary.add_child(heading)
	var status: Label = app.label(headline(result), 20)
	status.name = "HouseStatus"
	status.autowrap_mode = TextServer.AUTOWRAP_OFF
	status.add_theme_color_override("font_color", OK_COLOR if result.complete else NEED_COLOR)
	heading.add_child(status)
	var facts: Label = app.label("", 14)
	facts.name = "HouseFacts"
	facts.autowrap_mode = TextServer.AUTOWRAP_OFF
	facts.text = "室內 %d 格 · 參與島民 %d 位" % [int(result.area), result.contributors.size()] if result.found else "站到小屋裡或旁邊 8 格內再檢查"
	heading.add_child(facts)

	var cards := HBoxContainer.new()
	cards.name = "HouseCards"
	cards.add_theme_constant_override("separation", 8)
	content.add_child(cards)
	var next := next_part(result)
	var first: Button = null
	for kind in PARTS:
		var made := _part_card(app, result, kind, next)
		cards.add_child(made.card)
		if kind == next:
			first = made.button

	var guide := PanelContainer.new()
	guide.name = "HouseNext"
	guide.add_theme_stylebox_override("panel", PixelTheme.paper_style())
	content.add_child(guide)
	var guide_column := VBoxContainer.new()
	guide_column.add_theme_constant_override("separation", 4)
	guide.add_child(guide_column)
	var missing: Label = app.label(next_step(result), 15)
	missing.name = "HouseMissing"
	missing.add_theme_color_override("font_color", OK_COLOR if result.complete else NEED_COLOR)
	guide_column.add_child(missing)
	var note_label: Label = app.label(note(), 13)
	note_label.name = "HouseNote"
	note_label.add_theme_color_override("font_color", NOTE_COLOR)
	guide_column.add_child(note_label)

	var snapshot:Dictionary=app.session.snapshot
	var bond:Dictionary=snapshot.get("resident_bonds",{}).get("nuannuan",{})
	if snapshot.get("region_id","home")=="home" and int(bond.get("stage",0))>=3:
		var guest:=HouseRooms.guest_room(snapshot,result,result.at,app.session.own_id)
		var guest_row:=HBoxContainer.new()
		guest_row.add_theme_constant_override("separation",8)
		content.add_child(guest_row)
		var task:Label=app.label("暖暖的客房 · 床 %s　燈 %s　椅 %s"%[
			"✓" if guest.furnished.bed else "○","✓" if guest.furnished.lamp else "○","✓" if guest.furnished.chair else "○"],15)
		task.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		task.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
		guest_row.add_child(task)
		if snapshot.get("own_guest_room",false):
			guest_row.add_child(app.label("已登記 · 回礁溪找暖暖",14))
		else:
			var register_room:Button=app.button("登記這間客房",func():
				app.session.perform(World.RESIDENT_GOALS.GUEST_ROOM_ACTION,result.at)
				app._close_modal())
			register_room.name="GuestRoomRegister"
			register_room.disabled=not guest.ready
			register_room.tooltip_text="站在完整的小屋內，至少親手放一件客房家具。"
			guest_row.add_child(register_room)

	var actions := HBoxContainer.new()
	actions.name = "HouseFooter"
	actions.add_theme_constant_override("separation", 8)
	content.add_child(actions)
	var again: Button = app.button("重新檢查", func(): open(app))
	again.name = "HouseRecheck"
	again.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(again)
	var back: Button = app.button("返回家園工坊", func(): app._build_menu())
	back.name = "HouseBack"
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(back)
	(first if first != null else again).call_deferred("grab_focus")
	if app.has_method("_layout_preview"):
		app._layout_preview.call_deferred()
