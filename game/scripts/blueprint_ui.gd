extends RefCounted
## 藍圖冊 (blueprint folio modal) and 施工側欄 (non-modal placement strip).
## docs/blueprint-client-contract.md「藍圖冊與施工資訊」.
##
## UI only. Every value shown is read from the BlueprintController passed in;
## this module never keeps a second copy of the library, the draft or the
## quote. Buttons call the controller's public methods. controller.changed
## (and Session.changed for held counts) update the existing controls in place,
## so moving the mouse never rebuilds the strip or steals focus.
##
## Art: PixelTheme / LifeTheme styleboxes, LifeShell UI icons, InventoryItemArt
## material icons and BlueprintThumbnail (Node2D design/box_size) previews.
## No static Texture cache is created here.

const World := preload("res://scripts/world.gd")
const Design := preload("res://scripts/blueprint_design.gd")
const LifeTheme := preload("res://scripts/life_ui_theme.gd")
const PixelTheme := preload("res://scripts/inventory_pixel_theme.gd")
const ItemArt := preload("res://scripts/inventory_item_art.gd")
const LifeShell := preload("res://scripts/life_ui_shell.gd")

## Loaded lazily: the thumbnail is provided by the art worker.
const THUMB_PATH := "res://scripts/blueprint_thumbnail.gd"
const LAYOUT := "blueprint_folio"
const CAPTURED := "__captured__"
const MAX_ENTRIES := 12
const NAME_MAX := 32

const INK := Color("354334")
const INK_SOFT := Color("5d634a")
const CREAM := Color("f4e6bf")
const CREAM_SOFT := Color("dccfa6")
const SHORT := Color("a4452c")
const READY := Color("3f6a3a")
const WAIT := Color("8a6326")

const POCKET_THUMB := Vector2(128, 80)
const POCKET_MIN := Vector2(140, 122)
const POCKET_CAPTION_H := 22.0
const STAGE_BOX := Vector2(304, 120)
const DETAIL_W := 352.0
const GRID_GAP := 8
const BODY_GAP := 14
const FOLIO_GAP := 10
const SCROLLBAR_RESERVE := 14.0
const STRIP_THUMB := Vector2(56, 44)
const STRIP_TOP := 188.0
const STRIP_BOTTOM_RESERVE := 150.0
const STRIP_MARGIN := 16.0

# =============================================================== folio (modal)

static func open(app, controller) -> void:
	if app == null or not is_instance_valid(controller):return
	var content: VBoxContainer = app._open_modal("藍圖冊")
	var modal: Control = app.modal
	if content == null or modal == null:return
	modal.set_meta("life_modal_layout", LAYOUT)
	modal.theme = PixelTheme.make(modal.theme if modal.theme else app.theme())
	_pocket_theme(modal.theme)
	modal.add_theme_stylebox_override("panel", PixelTheme.frame_style())
	modal.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var outer := content.get_parent() as ScrollContainer

	var ui := {"app": app, "controller": controller, "selected": "", "renaming": false,
		"armed": "", "captured_key": 0, "cost_key": -1, "panel": "", "message": "", "message_ok": true}

	var folio := VBoxContainer.new()
	folio.name = "BlueprintFolio"
	folio.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	folio.add_theme_constant_override("separation", FOLIO_GAP)
	content.add_child(folio)
	ui.folio = folio

	# --- bar: capture entry + page count ---------------------------------------
	var bar := HBoxContainer.new()
	bar.name = "BlueprintFolioBar"
	bar.add_theme_constant_override("separation", 10)
	folio.add_child(bar)
	var capture: Button = app.button("框選新藍圖", func(): _start_capture(ui))
	capture.name = "BlueprintCapture"
	capture.icon = LifeShell.icon("blueprint")
	capture.add_theme_constant_override("icon_max_width", 24)
	bar.add_child(capture)
	ui.capture = capture
	var hint: Label = app.label("", 14)
	hint.name = "BlueprintFolioHint"
	hint.autowrap_mode = TextServer.AUTOWRAP_OFF
	hint.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hint.clip_text = true
	hint.add_theme_color_override("font_color", INK_SOFT)
	hint.text = "框住自己蓋的建物收成一頁，之後可旋轉、整組放到別處。"
	bar.add_child(hint)
	var count_badge := PanelContainer.new()
	count_badge.name = "BlueprintCountBadge"
	count_badge.add_theme_stylebox_override("panel", LifeTheme.badge_style())
	bar.add_child(count_badge)
	var count_row := HBoxContainer.new()
	count_row.add_theme_constant_override("separation", 4)
	count_badge.add_child(count_row)
	count_row.add_child(LifeShell.picture(LifeShell.icon("blueprint"), 24))
	var count: Label = app.label("", 15)
	count.name = "BlueprintCount"
	count.autowrap_mode = TextServer.AUTOWRAP_OFF
	count.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	count_row.add_child(count)
	ui.count = count

	# --- banners: library error / pending construction ---------------------------
	var error_box := _banner(app, "BlueprintLibraryError", SHORT)
	folio.add_child(error_box)
	ui.error_box = error_box
	var pending_box := _banner(app, "BlueprintPendingNote", WAIT)
	folio.add_child(pending_box)
	ui.pending_box = pending_box

	# --- body: gallery (left) + detail card (right) --------------------------------
	var body := HBoxContainer.new()
	body.name = "BlueprintFolioBody"
	body.add_theme_constant_override("separation", BODY_GAP)
	folio.add_child(body)

	var gallery := PanelContainer.new()
	gallery.name = "BlueprintGallery"
	gallery.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	gallery.add_theme_stylebox_override("panel", LifeTheme.toolbar_style())
	body.add_child(gallery)
	var linen := PanelContainer.new()
	linen.name = "BlueprintGalleryLinen"
	var linen_style := PixelTheme.texture_style("button_pressed", 3, 8)
	linen_style.modulate_color = Color(0.88, 0.92, 0.86)
	linen.add_theme_stylebox_override("panel", linen_style)
	gallery.add_child(linen)
	var scroll := ScrollContainer.new()
	scroll.name = "BlueprintGalleryScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	linen.add_child(scroll)
	var grid := GridContainer.new()
	grid.name = "BlueprintGrid"
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", GRID_GAP)
	grid.add_theme_constant_override("v_separation", GRID_GAP)
	scroll.add_child(grid)
	var pockets: Array = []
	for index in MAX_ENTRIES:
		var pocket := _pocket(index)
		grid.add_child(pocket)
		pocket.pressed.connect(func(): _select(ui, str(pocket.get_meta("key", ""))))
		pockets.append(pocket)
	ui.pockets = pockets

	var detail := PanelContainer.new()
	detail.name = "BlueprintDetail"
	detail.custom_minimum_size.x = DETAIL_W
	detail.add_theme_stylebox_override("panel", LifeTheme.panel_style())
	body.add_child(detail)
	var dbox := VBoxContainer.new()
	dbox.add_theme_constant_override("separation", 8)
	detail.add_child(dbox)
	var dscroll := ScrollContainer.new()
	dscroll.name = "BlueprintDetailScroll"
	dscroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	dscroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dbox.add_child(dscroll)
	var dinner := VBoxContainer.new()
	dinner.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dinner.add_theme_constant_override("separation", 8)
	dscroll.add_child(dinner)

	var stage := PanelContainer.new()
	stage.name = "BlueprintStage"
	stage.clip_contents = true
	stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_theme_stylebox_override("panel", linen_style)
	dinner.add_child(stage)
	ui.stage = stage
	var stage_center := CenterContainer.new()
	stage_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage_center.custom_minimum_size.y = STAGE_BOX.y
	stage.add_child(stage_center)
	var stage_art := _thumb(STAGE_BOX)
	stage_art.name = "BlueprintStageArt"
	stage_center.add_child(stage_art)
	ui.stage_art = stage_art
	var empty_art := VBoxContainer.new()
	empty_art.name = "BlueprintEmptyArt"
	empty_art.alignment = BoxContainer.ALIGNMENT_CENTER
	empty_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage_center.add_child(empty_art)
	var empty_icon := LifeShell.picture(LifeShell.icon("blueprint"), 64)
	empty_icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	empty_icon.modulate = Color(1, 1, 1, 0.75)
	empty_art.add_child(empty_icon)
	var empty_caption := Label.new()
	empty_caption.text = "空白的藍圖冊"
	empty_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty_caption.add_theme_font_size_override("font_size", 14)
	empty_caption.add_theme_color_override("font_color", INK_SOFT)
	empty_art.add_child(empty_caption)
	ui.empty_art = empty_art

	var title_row := HBoxContainer.new()
	title_row.name = "BlueprintTitleRow"
	title_row.add_theme_constant_override("separation", 6)
	dinner.add_child(title_row)
	var title: Label = app.label("", 21)
	title.name = "BlueprintName"
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.clip_text = true
	title_row.add_child(title)
	ui.title = title
	var rename_toggle: Button = _small(app, "改名", func(): _begin_rename(ui))
	rename_toggle.name = "BlueprintRenameToggle"
	rename_toggle.tooltip_text = "重新命名這份藍圖（1–32 字）"
	title_row.add_child(rename_toggle)
	ui.rename_toggle = rename_toggle

	var rename_row := HBoxContainer.new()
	rename_row.name = "BlueprintRenameRow"
	rename_row.add_theme_constant_override("separation", 6)
	dinner.add_child(rename_row)
	var name_edit := LineEdit.new()
	name_edit.name = "BlueprintNameEdit"
	name_edit.max_length = NAME_MAX
	name_edit.placeholder_text = "新的名稱"
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_edit.text_submitted.connect(func(_text: String): _rename(ui))
	rename_row.add_child(name_edit)
	ui.name_edit = name_edit
	var rename_save: Button = _small(app, "儲存", func(): _rename(ui))
	rename_save.name = "BlueprintRenameSave"
	rename_row.add_child(rename_save)
	var rename_cancel: Button = _small(app, "取消", func():
		ui.renaming = false
		_refresh_folio(ui)
	)
	rename_cancel.name = "BlueprintRenameCancel"
	rename_row.add_child(rename_cancel)
	ui.rename_row = rename_row

	var capture_row := VBoxContainer.new()
	capture_row.name = "BlueprintCaptureRow"
	capture_row.add_theme_constant_override("separation", 4)
	dinner.add_child(capture_row)
	var capture_caption: Label = app.label("", 14)
	capture_caption.text = "替新藍圖取個名字（1–32 字）"
	capture_caption.add_theme_color_override("font_color", INK_SOFT)
	capture_row.add_child(capture_caption)
	var capture_edit := LineEdit.new()
	capture_edit.name = "BlueprintCaptureName"
	capture_edit.max_length = NAME_MAX
	capture_edit.placeholder_text = "例如：河邊的小木屋"
	capture_edit.text_submitted.connect(func(_text: String): _save_capture(ui))
	capture_row.add_child(capture_edit)
	ui.capture_edit = capture_edit
	var roof_note: Label = app.label("", 13)
	roof_note.name = "BlueprintRoofNote"
	roof_note.add_theme_color_override("font_color", INK_SOFT)
	capture_row.add_child(roof_note)
	ui.roof_note = roof_note
	ui.capture_row = capture_row

	var stats: Label = app.label("", 14)
	stats.name = "BlueprintStats"
	stats.add_theme_color_override("font_color", INK_SOFT)
	dinner.add_child(stats)
	ui.stats = stats
	var cost_title: Label = app.label("", 13)
	cost_title.name = "BlueprintBaseCostTitle"
	cost_title.text = "基本材料 · 持有／所需（實際以放置估價為準）"
	cost_title.add_theme_color_override("font_color", INK_SOFT)
	dbox.add_child(cost_title)
	ui.cost_title = cost_title
	var cost := HFlowContainer.new()
	cost.name = "BlueprintBaseCost"
	cost.add_theme_constant_override("h_separation", 10)
	cost.add_theme_constant_override("v_separation", 4)
	dbox.add_child(cost)
	ui.cost = cost

	var note: Label = app.label("", 14)
	note.name = "BlueprintNote"
	dinner.add_child(note)
	ui.note = note

	var delete_row := HBoxContainer.new()
	delete_row.name = "BlueprintDeleteRow"
	title_row.add_child(delete_row)
	var delete_spacer := Control.new()
	delete_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	delete_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	delete_row.add_child(delete_spacer)
	var delete: Button = _small(app, "刪除", func():
		ui.armed = ui.selected
		ui.renaming = false
		_refresh_folio(ui)
	)
	delete.name = "BlueprintDelete"
	delete.icon = LifeShell.icon("remove")
	delete.add_theme_constant_override("icon_max_width", 20)
	delete_row.add_child(delete)
	ui.delete_row = delete_row
	ui.delete = delete

	var confirm_box := PanelContainer.new()
	confirm_box.name = "BlueprintDeleteConfirm"
	confirm_box.add_theme_stylebox_override("panel", LifeTheme.badge_style())
	dbox.add_child(confirm_box)
	var confirm_col := VBoxContainer.new()
	confirm_col.add_theme_constant_override("separation", 6)
	confirm_box.add_child(confirm_col)
	var confirm_text: Label = app.label("", 14)
	confirm_text.name = "BlueprintDeleteQuestion"
	confirm_text.add_theme_color_override("font_color", SHORT)
	confirm_col.add_child(confirm_text)
	ui.confirm_text = confirm_text
	var confirm_buttons := HBoxContainer.new()
	confirm_buttons.add_theme_constant_override("separation", 6)
	confirm_col.add_child(confirm_buttons)
	var delete_yes: Button = _small(app, "確定刪除", func(): _delete(ui))
	delete_yes.name = "BlueprintDeleteYes"
	delete_yes.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm_buttons.add_child(delete_yes)
	var delete_no: Button = _small(app, "保留", func():
		ui.armed = ""
		_refresh_folio(ui)
	)
	delete_no.name = "BlueprintDeleteNo"
	delete_no.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	confirm_buttons.add_child(delete_no)
	ui.confirm_box = confirm_box

	var feedback: Label = app.label("", 13)
	feedback.name = "BlueprintFeedback"
	dbox.add_child(feedback)
	ui.feedback = feedback
	var primary: Button = app.button("", func(): _primary(ui))
	primary.name = "BlueprintPrimary"
	primary.custom_minimum_size.y = 46
	primary.add_theme_constant_override("icon_max_width", 28)
	dbox.add_child(primary)
	ui.primary = primary

	# --- fit: body fills the modal scroll; gallery columns follow its width -----
	var fit := func():
		if not is_instance_valid(body):return
		if not is_instance_valid(outer):
			body.custom_minimum_size.y = 430
			return
		var gap := float(folio.get_theme_constant("separation"))
		var reserve := 0.0
		for child in folio.get_children():
			if child != body and child is Control and child.visible:
				reserve += maxf(child.size.y, child.get_combined_minimum_size().y) + gap
		var available := maxf(300.0, floorf(outer.size.y - reserve - 2.0))
		if absf(body.custom_minimum_size.y - available) > 1.0:
			body.custom_minimum_size.y = available
	ui.fit = fit
	if outer != null:
		outer.resized.connect(fit)
	var columns := func():
		if not is_instance_valid(scroll):return
		var width := scroll.size.x - SCROLLBAR_RESERVE
		var wanted := clampi(int(floorf((width + GRID_GAP) / (POCKET_MIN.x + GRID_GAP))), 2, 4)
		if grid.columns != wanted:grid.columns = wanted
	scroll.resized.connect(columns)

	# --- live data -------------------------------------------------------------
	var refresh := func():_refresh_folio(ui)
	# Session ticks only move held counts; leave pockets/designs untouched.
	var held_refresh := func(_snapshot, _own_id):
		if is_instance_valid(folio) and (ui.cost as Control).visible:
			_fill_chips(ui.cost, ui.get("base_cost", {}), _held(app), true)
	var on_feedback := func(message: String, ok: bool):
		ui.message = message
		ui.message_ok = ok
		_refresh_folio(ui)
	_bind(folio, controller, "changed", refresh)
	_bind(folio, controller, "feedback", on_feedback)
	var session = app.get("session")
	if session is Object and session.has_signal("changed"):
		_bind(folio, session, "changed", held_refresh)

	_refresh_folio(ui)
	fit.call_deferred()
	columns.call_deferred()
	if app.has_method("_layout_preview"):app._layout_preview.call_deferred()

static func _refresh_folio(ui: Dictionary) -> void:
	var folio: Control = ui.folio
	var c = ui.controller
	if not is_instance_valid(folio) or not is_instance_valid(c):return
	var entries := _entries(c)
	var captured_raw := _dict(c.get("captured"))
	var captured := _design_of(captured_raw)
	var error := str(c.get("library_error")) if c.get("library_error") != null else ""
	var busy := _busy(c)
	var full := entries.size() >= MAX_ENTRIES

	# Selection: a freshly captured layout always comes forward once.
	var ids: Array = []
	for entry in entries:ids.append(str(entry.get("id", "")))
	var captured_key: int = captured.hash() if not captured.is_empty() else 0
	if captured_key != int(ui.captured_key):
		ui.captured_key = captured_key
		if captured_key != 0:
			ui.selected = CAPTURED
			ui.renaming = false
			ui.armed = ""
			(ui.capture_edit as LineEdit).text = str(captured.get("name", ""))
	if ui.selected == CAPTURED and captured.is_empty():ui.selected = ""
	if ui.selected != CAPTURED and not ui.selected in ids:
		ui.selected = ids[0] if not ids.is_empty() else (CAPTURED if not captured.is_empty() else "")
		ui.renaming = false
		ui.armed = ""

	# Gallery pockets (always 12: filled pages, the unsaved capture, blank pages).
	var capture_slot := entries.size() if not captured.is_empty() and not full else -1
	var pockets: Array = ui.pockets
	for index in pockets.size():
		var pocket: Button = pockets[index]
		var key := ""
		var pocket_design := {}
		var caption_text := "第 %02d 頁" % (index + 1)
		if index < entries.size():
			key = ids[index]
			pocket_design = _design_of(entries[index])
			caption_text = str(pocket_design.get("name", ""))
		elif index == capture_slot:
			key = CAPTURED
			pocket_design = captured
			caption_text = "新藍圖・未儲存"
		pocket.set_meta("key", key)
		if pocket.disabled != (key == ""):pocket.disabled = key == ""
		pocket.set_pressed_no_signal(key != "" and key == ui.selected)
		pocket.focus_mode = Control.FOCUS_NONE if key == "" else Control.FOCUS_ALL
		_set_design(pocket.get_node("Art"), pocket_design)
		var caption: Label = pocket.get_node("Caption")
		_set_text(caption, caption_text)
		caption.add_theme_color_override("font_color", INK if key != "" else Color(INK_SOFT, 0.55))
		(pocket.get_node("Ribbon") as Control).visible = key == CAPTURED
		var tip := "第 %d 頁 · 空白" % (index + 1)
		if key != "":
			tip = "%s\n%s" % [caption_text, _size_text(pocket_design)]
		pocket.tooltip_text = tip
		pocket.set("accessibility_name", caption_text)

	_set_text(ui.count, "%d／%d 頁" % [entries.size(), MAX_ENTRIES])
	var capture: Button = ui.capture
	capture.disabled = busy or full or not error.is_empty()
	capture.tooltip_text = ("有施工待確認，完成後才能框選" if busy else
		("藍圖冊已滿 %d 頁，請先刪除一頁" % MAX_ENTRIES if full else
		("藍圖冊目前無法寫入" if not error.is_empty() else "回到地面拖曳框住自己蓋的建物（手作三級解鎖 16×16 格）")))

	var error_box: Control = ui.error_box
	error_box.visible = not error.is_empty()
	_set_text(error_box.get_node("Text"), "藍圖冊讀取失敗，已暫停寫入並保留原檔：%s" % error)
	var pending_box: Control = ui.pending_box
	pending_box.visible = busy
	_set_text(pending_box.get_node("Text"), "有一筆藍圖施工待確認，請到地圖右側的施工欄查看；完成前不能放置或框選新藍圖。")
	if not str(c.get("pending_error")).is_empty():
		_set_text(pending_box.get_node("Text"),str(c.get("pending_error")))

	# Detail card.
	var panel := "empty"
	if ui.selected == CAPTURED:panel = "captured"
	elif ui.selected != "":panel = "entry"
	ui.panel = panel
	var design := {}
	if panel == "captured":design = captured
	elif panel == "entry":design = _design_of(entries[ids.find(ui.selected)])
	(ui.stage_art as Control).visible = panel != "empty"
	(ui.stage as Control).visible = panel != "captured"
	(ui.empty_art as Control).visible = panel == "empty"
	_set_design(ui.stage_art, design)
	var title_text := "還沒有藍圖"
	if panel == "captured":title_text = "新藍圖"
	elif panel == "entry":title_text = str(design.get("name", ""))
	_set_text(ui.title, title_text)
	(ui.title as Label).tooltip_text = title_text
	var rename_toggle: Button = ui.rename_toggle
	rename_toggle.visible = panel == "entry" and not ui.renaming
	rename_toggle.disabled = not error.is_empty()
	(ui.rename_row as Control).visible = panel == "entry" and ui.renaming
	(ui.capture_row as Control).visible = panel == "captured"
	var omitted := int(c.get("auto_roofs_omitted")) if c.get("auto_roofs_omitted") != null else 0
	_set_text(ui.roof_note, ("已略過 %d 格自動屋頂；放置時會依圍好的房間重新加蓋。" % omitted) if omitted > 0 else "範圍內沒有自動屋頂需要略過。")
	(ui.stats as Control).visible = panel != "empty"
	_set_text(ui.stats, _stats_text(design))
	(ui.cost_title as Control).visible = panel != "empty"
	(ui.cost as Control).visible = panel != "empty"
	var cost_key: int = design.hash() if not design.is_empty() else -1
	if cost_key != int(ui.cost_key):
		ui.cost_key = cost_key
		var base := Design.base_cost(design, World.BUILD, World.NAMES) if not design.is_empty() else {}
		ui.base_cost = _dict(base.get("cost")) if bool(base.get("ok", false)) else {}
	_fill_chips(ui.cost, ui.get("base_cost", {}), _held(ui.app), true)

	var note_text := ""
	var note_color := INK
	if panel == "empty":
		note_text = "按「框選新藍圖」，回到地面拖曳框住自己蓋的小屋、步道或擺設（手作三級解鎖 16×16 格），放開後就能命名收進這本冊子。最多 %d 頁。" % MAX_ENTRIES
	elif panel == "captured" and full:
		note_text = "藍圖冊已滿 %d 頁，先刪除一頁才能存入這份新藍圖。" % MAX_ENTRIES
		note_color = SHORT
	elif panel == "captured":
		note_text = "還沒存檔：按「存入藍圖冊」後才會留在冊子裡。"
		note_color = INK_SOFT
	var note: Label = ui.note
	note.visible = not note_text.is_empty()
	_set_text(note, note_text)
	note.add_theme_color_override("font_color", note_color)

	var armed: bool = panel == "entry" and ui.armed == ui.selected
	(ui.delete_row as Control).visible = panel == "entry" and not armed and not ui.renaming
	(ui.delete as Button).disabled = not error.is_empty()
	(ui.confirm_box as Control).visible = armed
	_set_text(ui.confirm_text, "要把「%s」從藍圖冊移除嗎？這一頁刪除後無法找回。" % title_text)

	var feedback: Label = ui.feedback
	var message := str(ui.message)
	feedback.visible = not message.is_empty()
	_set_text(feedback, message)
	feedback.add_theme_color_override("font_color", READY if ui.message_ok else SHORT)

	var primary: Button = ui.primary
	match panel:
		"entry":
			_set_text(primary, "放到地圖上")
			primary.icon = _icon_once(primary, "build")
			primary.disabled = busy
			primary.tooltip_text = "有施工待確認，完成後才能放置" if busy else "回到地面選位置，R 旋轉、點地面估價"
		"captured":
			_set_text(primary, "存入藍圖冊")
			primary.icon = _icon_once(primary, "blueprint")
			primary.disabled = full or not error.is_empty()
			primary.tooltip_text = ""
		_:
			_set_text(primary, "框選新藍圖")
			primary.icon = _icon_once(primary, "blueprint")
			primary.disabled = capture.disabled
			primary.tooltip_text = capture.tooltip_text
	if ui.has("fit"):(ui.fit as Callable).call_deferred()

static func _select(ui: Dictionary, key: String) -> void:
	if key.is_empty():return
	if key != ui.selected:
		ui.renaming = false
		ui.armed = ""
		ui.message = ""
	ui.selected = key
	_refresh_folio(ui)

static func _primary(ui: Dictionary) -> void:
	match str(ui.panel):
		"entry":_choose(ui)
		"captured":_save_capture(ui)
		_:_start_capture(ui)

static func _start_capture(ui: Dictionary) -> void:
	var c = ui.controller
	if not is_instance_valid(c):return
	if _truthy(_call(c, "begin_capture", [])):
		ui.app._close_modal()
		return
	_report(ui, _status(c, "現在不能開始框選。"), false)

static func _choose(ui: Dictionary) -> void:
	var c = ui.controller
	if not is_instance_valid(c) or str(ui.selected).is_empty() or ui.selected == CAPTURED:return
	if _truthy(_call(c, "choose", [str(ui.selected)])):
		ui.app._close_modal()
		return
	_report(ui, _status(c, "現在不能放置這份藍圖。"), false)

static func _save_capture(ui: Dictionary) -> void:
	var c = ui.controller
	if not is_instance_valid(c):return
	var before: Array = []
	for entry in _entries(c):before.append(str(entry.get("id", "")))
	var result := _result(_call(c, "save_capture", [(ui.capture_edit as LineEdit).text]))
	if not bool(result.get("ok", false)):
		# Typed name and the captured layout stay as they were.
		_report(ui, str(result.get("reason", "")) if str(result.get("reason", "")) != "" else "藍圖沒有儲存。", false)
		return
	for entry in _entries(c):
		var id := str(entry.get("id", ""))
		if not id in before:
			ui.selected = id
			break
	ui.armed = ""
	ui.renaming = false
	_report(ui, "已收進藍圖冊。選好後按「放到地圖上」。", true)

static func _begin_rename(ui: Dictionary) -> void:
	ui.renaming = true
	ui.armed = ""
	var edit: LineEdit = ui.name_edit
	edit.text = (ui.title as Label).text
	_refresh_folio(ui)
	if edit.is_inside_tree():
		edit.grab_focus()
		edit.select_all()

static func _rename(ui: Dictionary) -> void:
	var c = ui.controller
	if not is_instance_valid(c) or ui.panel != "entry":return
	var result := _result(_call(c, "rename_entry", [str(ui.selected), (ui.name_edit as LineEdit).text]))
	if bool(result.get("ok", false)):
		ui.renaming = false
		_report(ui, "已改名。", true)
	else:
		_report(ui, str(result.get("reason", "")) if str(result.get("reason", "")) != "" else "名稱沒有變更。", false)

static func _delete(ui: Dictionary) -> void:
	var c = ui.controller
	if not is_instance_valid(c) or ui.panel != "entry" or ui.armed != ui.selected:return
	var result := _result(_call(c, "delete_entry", [str(ui.selected)]))
	if bool(result.get("ok", false)):
		ui.armed = ""
		ui.selected = ""
		_report(ui, "已刪除這一頁。", true)
	else:
		_report(ui, str(result.get("reason", "")) if str(result.get("reason", "")) != "" else "這一頁沒有刪除。", false)

static func _report(ui: Dictionary, message: String, ok: bool) -> void:
	ui.message = message
	ui.message_ok = ok
	_refresh_folio(ui)

static func _pocket_theme(theme: Theme) -> void:
	theme.set_type_variation("BlueprintPocket", "Button")
	var filled := PixelTheme.texture_style("paper", 3, 0)
	var blank := PixelTheme.texture_style("normal", 3, 0)
	blank.modulate_color = Color(1, 1, 1, 0.38)
	var chosen := LifeTheme.badge_style()
	theme.set_stylebox("normal", "BlueprintPocket", filled)
	theme.set_stylebox("disabled", "BlueprintPocket", blank)
	theme.set_stylebox("hover", "BlueprintPocket", PixelTheme.texture_style("hover", 3, 0))
	theme.set_stylebox("pressed", "BlueprintPocket", chosen)
	theme.set_stylebox("hover_pressed", "BlueprintPocket", chosen)
	theme.set_stylebox("focus", "BlueprintPocket", PixelTheme.texture_style("focus", 3, 0))

static func _pocket(index: int) -> Button:
	var pocket := Button.new()
	pocket.name = "BlueprintPocket%d" % index
	pocket.theme_type_variation = &"BlueprintPocket"
	pocket.toggle_mode = true
	pocket.custom_minimum_size = POCKET_MIN
	pocket.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pocket.clip_contents = true
	pocket.set_meta("key", "")
	var art := _thumb(POCKET_THUMB)
	art.name = "Art"
	pocket.add_child(art)
	art.set_anchors_preset(Control.PRESET_CENTER_TOP)
	art.offset_left = -POCKET_THUMB.x / 2
	art.offset_right = POCKET_THUMB.x / 2
	art.offset_top = 8
	art.offset_bottom = 8 + POCKET_THUMB.y
	var caption := Label.new()
	caption.name = "Caption"
	caption.add_theme_font_size_override("font_size", 14)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	caption.clip_text = true
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pocket.add_child(caption)
	caption.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	caption.offset_left = 6
	caption.offset_right = -6
	caption.offset_top = -(POCKET_CAPTION_H + 6)
	caption.offset_bottom = -6
	# Small "new" ribbon on the unsaved capture's pocket.
	var ribbon := PanelContainer.new()
	ribbon.name = "Ribbon"
	ribbon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ribbon.add_theme_stylebox_override("panel", LifeTheme.toolbar_style())
	ribbon.visible = false
	pocket.add_child(ribbon)
	ribbon.position = Vector2(6, 6)
	var ribbon_text := Label.new()
	ribbon_text.text = "新"
	ribbon_text.add_theme_font_size_override("font_size", 12)
	ribbon_text.add_theme_color_override("font_color", CREAM)
	ribbon.add_child(ribbon_text)
	return pocket

static func _banner(app, node_name: String, color: Color) -> PanelContainer:
	var box := PanelContainer.new()
	box.name = node_name
	box.add_theme_stylebox_override("panel", LifeTheme.badge_style())
	box.visible = false
	var text: Label = app.label("", 14)
	text.name = "Text"
	text.add_theme_color_override("font_color", color)
	box.add_child(text)
	return box

static func _stats_text(design: Dictionary) -> String:
	if design.is_empty():return ""
	var kinds := {}
	for piece in design.get("pieces", []):
		if piece is Dictionary:
			var kind := str(piece.get("kind", ""))
			kinds[kind] = int(kinds.get(kind, 0)) + 1
	var order := kinds.keys()
	order.sort_custom(func(a, b): return int(kinds[a]) > int(kinds[b]) or (int(kinds[a]) == int(kinds[b]) and str(a) < str(b)))
	var parts := PackedStringArray()
	for index in mini(order.size(), 4):
		var kind: String = order[index]
		var recipe = World.BUILD.get(kind, {})
		parts.append("%s×%d" % [str(recipe.get("name", kind)) if recipe is Dictionary else kind, int(kinds[kind])])
	if order.size() > 4:parts.append("等 %d 種" % order.size())
	return "%s\n%s" % [_size_text(design), "  ".join(parts)]

static func _size_text(design: Dictionary) -> String:
	if design.is_empty():return ""
	var pieces = design.get("pieces", [])
	return "%d×%d 格 · %d 件" % [int(design.get("width", 0)), int(design.get("height", 0)), pieces.size() if pieces is Array else 0]

# ============================================================ strip (non-modal)

static func make_strip(app, controller) -> Control:
	var strip := PanelContainer.new()
	strip.name = "BlueprintStrip"
	strip.theme = PixelTheme.make(app.theme())
	strip.add_theme_stylebox_override("panel", PixelTheme.frame_style())
	strip.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	strip.mouse_filter = Control.MOUSE_FILTER_STOP
	strip.custom_minimum_size.x = 300
	strip.visible = false
	var ui := {"app": app, "controller": controller, "strip": strip, "message": "", "message_ok": true,
		"last_mode": "", "rot_key": [], "rotated": {}, "sig": "", "layout_queued": false}
	strip.set_meta("blueprint_ui", ui)

	var box := VBoxContainer.new()
	box.name = "BlueprintStripBox"
	box.add_theme_constant_override("separation", 6)
	strip.add_child(box)

	var header := PanelContainer.new()
	header.name = "BlueprintStripHeader"
	header.add_theme_stylebox_override("panel", LifeTheme.toolbar_style())
	box.add_child(header)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	header.add_child(head)
	var thumb := _thumb(STRIP_THUMB)
	thumb.name = "BlueprintStripThumb"
	head.add_child(thumb)
	ui.thumb = thumb
	var words := VBoxContainer.new()
	words.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	words.add_theme_constant_override("separation", 0)
	head.add_child(words)
	var title := Label.new()
	title.name = "BlueprintStripTitle"
	title.add_theme_font_size_override("font_size", 17)
	title.add_theme_color_override("font_color", CREAM)
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.clip_text = true
	words.add_child(title)
	ui.title = title
	var info := Label.new()
	info.name = "BlueprintStripInfo"
	info.add_theme_font_size_override("font_size", 13)
	info.add_theme_color_override("font_color", CREAM_SOFT)
	info.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	info.clip_text = true
	words.add_child(info)
	ui.info = info

	var scroll := ScrollContainer.new()
	scroll.name = "BlueprintStripScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	ui.scroll = scroll
	var body := VBoxContainer.new()
	body.name = "BlueprintStripBody"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 5)
	scroll.add_child(body)
	ui.body = body

	ui.state = _strip_label(app, body, "BlueprintStripState", 16, READY)
	ui.hint = _strip_label(app, body, "BlueprintStripHint", 13, INK_SOFT)
	ui.cost_title = _strip_label(app, body, "BlueprintStripCostTitle", 13, INK_SOFT)
	ui.cost = _strip_flow(body, "BlueprintStripCost")
	ui.refund_title = _strip_label(app, body, "BlueprintStripRefundTitle", 13, INK_SOFT)
	ui.refund = _strip_flow(body, "BlueprintStripRefund")
	ui.others_title = _strip_label(app, body, "BlueprintStripOthersTitle", 13, INK_SOFT)
	ui.others = _strip_flow(body, "BlueprintStripOthers")
	ui.roofs = _strip_label(app, body, "BlueprintStripRoofs", 13, INK)
	ui.problems = _strip_label(app, body, "BlueprintStripProblems", 13, SHORT)
	var warning_box := PanelContainer.new()
	warning_box.name = "BlueprintStripWarningBox"
	warning_box.add_theme_stylebox_override("panel", LifeTheme.badge_style())
	body.add_child(warning_box)
	ui.warning_box = warning_box
	ui.warning = _strip_label(app, warning_box, "BlueprintStripWarning", 13, SHORT)
	ui.message_label = _strip_label(app, body, "BlueprintStripMessage", 13, INK_SOFT)

	var tools := HBoxContainer.new()
	tools.name = "BlueprintStripTools"
	tools.add_theme_constant_override("separation", 6)
	box.add_child(tools)
	ui.tools = tools
	var rotate: Button = _small(app, "旋轉  R", func(): _call(ui.controller, "rotate", []))
	rotate.name = "BlueprintRotate"
	rotate.tooltip_text = "順時針轉 90°（會清除舊估價，需重新估價）"
	rotate.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tools.add_child(rotate)
	ui.rotate = rotate
	var reposition: Button = _small(app, "換位置", func(): _call(ui.controller, "reposition", []))
	reposition.name = "BlueprintReposition"
	reposition.tooltip_text = "解除鎖定，重新點地面選擇落點"
	reposition.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tools.add_child(reposition)
	ui.reposition = reposition
	var quote: Button = _small(app, "重新估價", func(): _call(ui.controller, "request_quote", []))
	quote.name = "BlueprintQuote"
	quote.tooltip_text = "向島上重新確認材料與空間"
	quote.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tools.add_child(quote)
	ui.quote = quote

	var actions := HBoxContainer.new()
	actions.name = "BlueprintStripActions"
	actions.add_theme_constant_override("separation", 6)
	box.add_child(actions)
	ui.actions = actions
	var confirm: Button = app.button("確認施工", func(): _call(ui.controller, "confirm", []))
	confirm.name = "BlueprintConfirm"
	confirm.icon = LifeShell.icon("build")
	confirm.add_theme_constant_override("icon_max_width", 24)
	confirm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(confirm)
	ui.confirm = confirm
	var retry: Button = app.button("重新查詢結果", func(): _call(ui.controller, "retry_pending", []))
	retry.name = "BlueprintRetry"
	retry.tooltip_text = "用同一筆施工記錄向島上確認，不會重複扣料"
	retry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(retry)
	ui.retry = retry
	var cancel: Button = app.button("取消", func(): _call(ui.controller, "cancel", []))
	cancel.name = "BlueprintCancel"
	cancel.tooltip_text = "結束藍圖模式（Esc）"
	actions.add_child(cancel)
	ui.cancel = cancel

	# --- live data + pointer gate -------------------------------------------------
	var refresh := func():_refresh_strip(ui)
	var held_refresh := func(_snapshot, _own_id):
		if is_instance_valid(strip) and strip.visible:_refresh_strip(ui)
	var on_feedback := func(message: String, ok: bool):
		ui.message = message
		ui.message_ok = ok
		_refresh_strip(ui)
	_bind(strip, controller, "changed", refresh)
	_bind(strip, controller, "feedback", on_feedback)
	var session = app.get("session")
	if session is Object and session.has_signal("changed"):
		_bind(strip, session, "changed", held_refresh)
	strip.tree_entered.connect(func():
		var gate = app.get("preview_controls")
		if gate is Array and not strip in gate:gate.append(strip)
		_refresh_strip(ui)
		_queue_layout(ui)
	)
	strip.tree_exiting.connect(func():
		var gate = app.get("preview_controls")
		if gate is Array:gate.erase(strip)
	)
	body.minimum_size_changed.connect(func(): _queue_layout(ui))
	strip.visibility_changed.connect(func(): _queue_layout(ui))
	_refresh_strip(ui)
	return strip

static func layout_strip(strip: Control, bounds: Vector2) -> void:
	if not is_instance_valid(strip):return
	strip.set_meta("bounds", bounds)
	var width := minf(300.0 if bounds.x < 1180.0 else 320.0, maxf(220.0, bounds.x - 2 * STRIP_MARGIN))
	var top := STRIP_TOP
	var available := maxf(160.0, bounds.y - STRIP_BOTTOM_RESERVE - top)
	if absf(strip.custom_minimum_size.x - width) > 0.5:strip.custom_minimum_size.x = width
	var ui = strip.get_meta("blueprint_ui", null)
	if ui is Dictionary and is_instance_valid(ui.get("scroll")) and is_instance_valid(ui.get("body")):
		var scroll: ScrollContainer = ui.scroll
		var body: Control = ui.body
		var fixed := strip.get_combined_minimum_size().y - scroll.custom_minimum_size.y
		var wanted := clampf(body.get_combined_minimum_size().y, 0.0, maxf(48.0, available - fixed))
		if absf(scroll.custom_minimum_size.y - wanted) > 0.5:scroll.custom_minimum_size.y = wanted
	strip.size = Vector2(width, minf(available, strip.get_combined_minimum_size().y))
	strip.position = Vector2(floorf(bounds.x - width - STRIP_MARGIN), floorf(top))

static func _refresh_strip(ui: Dictionary) -> void:
	var strip: Control = ui.strip
	var c = ui.controller
	if not is_instance_valid(strip):return
	if not is_instance_valid(c):
		strip.visible = false
		return
	var mode := str(c.get("mode"))
	var pending := _dict(c.get("pending"))
	var unknown: bool = mode == "unknown" or (mode != "submitting" and (not pending.is_empty() or not str(c.get("pending_error")).is_empty()))
	var shown: bool = mode in ["capture", "placing", "submitting"] or unknown
	var display: bool = shown and ui.app.get("modal")==null and bool(ui.app.get("playing"))
	if strip.visible != display:strip.visible = display
	if not shown:
		ui.last_mode = mode
		ui.message = ""
		return
	var phase := "unknown" if unknown else mode
	if phase != ui.last_mode:
		ui.last_mode = phase
		ui.message = ""

	var design := {}
	var turns := 0
	if phase == "placing":
		design = _dict(c.get("draft"))
		turns = int(c.get("turns")) if c.get("turns") != null else 0
	elif not pending.is_empty():
		design = _dict(pending.get("design"))
		turns = int(pending.get("turns", 0))
	else:
		design = _dict(c.get("draft"))
		turns = int(c.get("turns")) if c.get("turns") != null else 0
	var rotated := _rotated(ui, design, turns)
	_set_design(ui.thumb, rotated)

	var q := _dict(c.get("quote"))
	var locked := bool(c.get("locked"))
	var waiting := bool(c.get("quote_waiting"))
	var status := str(c.get("status")) if c.get("status") != null else ""
	var state_text := ""
	var state_color := READY
	var hint_text := ""
	var show_quote := false
	var show_tools := false
	var show_confirm := false
	var show_retry := false
	var show_cancel := false
	var warning_text := ""

	if phase == "capture":
		_set_text(ui.title, "框選新藍圖")
		_set_text(ui.info, "基本 8×8 格 · 手作三級 16×16 格")
		state_text = "拖曳框選範圍"
		hint_text = "在地面按住滑鼠拖曳，框住自己蓋的建物；放開後替它命名收進藍圖冊。Esc 或「取消」結束框選。"
		show_cancel = true
	else:
		var name_text := str(design.get("name", "藍圖"))
		_set_text(ui.title, name_text)
		(ui.title as Label).tooltip_text = name_text
		var info_text := _size_text(rotated)
		if not info_text.is_empty():info_text += " · 旋轉 %d°" % (turns * 90)
		_set_text(ui.info, info_text)
		match phase:
			"placing":
				show_tools = true
				show_confirm = true
				show_cancel = true
				if not locked:
					state_text = "選擇落點"
					hint_text = "移動滑鼠預覽位置，點地面鎖定並向島上估價。R 旋轉。"
				elif waiting:
					state_text = "估價中…"
					state_color = WAIT
					hint_text = "正在確認材料、空間與屋頂，請稍候。"
				elif q.is_empty():
					state_text = "還沒有估價"
					state_color = SHORT
					hint_text = "目前沒有可用報價，按「估價」確認這個落點與方向。"
				elif not bool(q.get("ok", false)):
					state_text = "這裡不能施工"
					state_color = SHORT
					hint_text = str(q.get("message", ""))
					show_quote = true
				else:
					state_text = "可以施工"
					hint_text = "價格已更新，請重新檢查材料後再確認。" if bool(q.get("requote", false)) else str(q.get("message", ""))
					if bool(q.get("requote", false)):state_color = WAIT
					show_quote = true
					warning_text = "確認後會立即施工並扣除材料，不能用「復原」撤回。"
			"submitting":
				state_text = "施工已送出，等待島上回覆"
				state_color = WAIT
				hint_text = "記錄已先保存。等待時可以關閉介面或打開選單，但不能開始另一筆施工。"
				show_quote = not q.is_empty()
			_:
				state_text = "施工結果待確認"
				state_color = SHORT
				hint_text = "連線中斷或等待逾時，目前無法確定這筆施工是否已完成。按「重新查詢結果」會用同一筆記錄向島上確認，不會重複扣料。"
				var pending_error := str(c.get("pending_error")) if c.get("pending_error") != null else ""
				if not pending_error.is_empty():hint_text += "\n" + pending_error
				show_retry = true
				show_quote = not q.is_empty()

	_set_text(ui.state, state_text)
	(ui.state as Label).add_theme_color_override("font_color", state_color)
	_set_text(ui.hint, hint_text)
	(ui.hint as Control).visible = not hint_text.is_empty()

	# Quote: every material, refunds (mine / other original owners), roofs, problems.
	var cost := _dict(q.get("cost")) if show_quote else {}
	var mine := _dict(q.get("mine_refund")) if show_quote else {}
	var others := _dict(q.get("others_refund")) if show_quote else {}
	var held := _held(ui.app)
	(ui.cost_title as Control).visible = show_quote
	_set_text(ui.cost_title, ("施工材料 · 持有／所需" if not cost.is_empty() else "施工材料 · 不需額外材料") if phase == "placing" else "送出的材料")
	(ui.cost as Control).visible = show_quote and not cost.is_empty()
	_fill_chips(ui.cost, cost, held, phase == "placing")
	(ui.refund_title as Control).visible = not mine.is_empty()
	_set_text(ui.refund_title, "拆換後退回給你")
	(ui.refund as Control).visible = not mine.is_empty()
	_fill_chips(ui.refund, mine, {}, false)
	var other_people := int(q.get("other_people", 0)) if show_quote else 0
	(ui.others_title as Control).visible = not others.is_empty() or other_people > 0
	_set_text(ui.others_title, "退回其他 %d 位原主" % other_people if other_people > 0 else "退回其他原主")
	(ui.others as Control).visible = not others.is_empty()
	_fill_chips(ui.others, others, {}, false)
	var roof_add := int(q.get("roof_add", 0)) if show_quote else 0
	var roof_remove := int(q.get("roof_remove", 0)) if show_quote else 0
	var roof_parts := PackedStringArray()
	if roof_add > 0:roof_parts.append("自動加蓋 %d 格" % roof_add)
	if roof_remove > 0:roof_parts.append("拆除 %d 格" % roof_remove)
	(ui.roofs as Control).visible = not roof_parts.is_empty()
	_set_text(ui.roofs, "屋頂：" + "、".join(roof_parts))
	var problem_text := _problem_text(q.get("problems", []) if show_quote else [])
	(ui.problems as Control).visible = not problem_text.is_empty()
	_set_text(ui.problems, problem_text)
	(ui.warning_box as Control).visible = not warning_text.is_empty()
	_set_text(ui.warning, warning_text)
	var message := str(ui.message)
	var message_color := READY if ui.message_ok else SHORT
	if message.is_empty() and not status.is_empty() and status != hint_text:
		message = status
		message_color = INK_SOFT
	var message_label: Label = ui.message_label
	message_label.visible = not message.is_empty()
	_set_text(message_label, message)
	message_label.add_theme_color_override("font_color", message_color)

	# Buttons are reused; only visibility, labels and enabled state change.
	(ui.tools as Control).visible = show_tools
	(ui.rotate as Button).disabled = not show_tools
	(ui.reposition as Button).disabled = not (show_tools and locked)
	(ui.quote as Button).disabled = not (show_tools and locked and not waiting)
	_set_text(ui.quote, "重新估價" if not q.is_empty() else "估價")
	var confirm: Button = ui.confirm
	confirm.visible = show_confirm
	confirm.disabled = not (show_confirm and locked and not waiting and bool(q.get("ok", false)))
	_set_text(confirm, "確認新價格" if bool(q.get("requote", false)) else "確認施工")
	confirm.tooltip_text = "先點地面鎖定落點並取得有效估價" if confirm.disabled else "按下後立即施工，無法復原"
	(ui.retry as Button).visible = show_retry
	(ui.retry as Button).disabled = pending.is_empty()
	(ui.cancel as Button).visible = show_cancel

	var sig := "%s|%s|%s|%s|%s" % [phase, show_tools, show_confirm, show_retry, show_cancel]
	if sig != ui.sig:
		ui.sig = sig
		_queue_layout(ui)

static func _problem_text(problems) -> String:
	if not problems is Array or problems.is_empty():return ""
	var counts := {}
	var order: Array = []
	for entry in problems:
		if not entry is Dictionary:continue
		var reason := str(entry.get("reason", ""))
		if reason.is_empty():reason = "這格不能施工"
		if not counts.has(reason):order.append(reason)
		counts[reason] = int(counts.get(reason, 0)) + 1
	var lines := PackedStringArray(["有 %d 格需要處理（地面紅框）：" % problems.size()])
	for index in mini(order.size(), 3):
		var reason: String = order[index]
		lines.append("· %s%s" % [reason, (" ×%d" % counts[reason]) if int(counts[reason]) > 1 else ""])
	if order.size() > 3:lines.append("· 還有 %d 種問題" % (order.size() - 3))
	return "\n".join(lines)

static func _rotated(ui: Dictionary, design: Dictionary, turns: int) -> Dictionary:
	if design.is_empty():return {}
	var key := [design.hash(), turns]
	if ui.rot_key == key:return ui.rotated
	var result := Design.rotate(design, clampi(turns, 0, 3), World.BUILD, World.NAMES)
	ui.rot_key = key
	ui.rotated = _dict(result.get("blueprint")) if bool(result.get("ok", false)) else design
	return ui.rotated

static func _queue_layout(ui: Dictionary) -> void:
	if bool(ui.get("layout_queued", false)):return
	ui.layout_queued = true
	var run := func():
		ui.layout_queued = false
		var strip: Control = ui.strip
		if not is_instance_valid(strip):return
		var bounds: Vector2 = strip.get_meta("bounds", Vector2(1280, 800))
		if strip.is_inside_tree():bounds = strip.get_viewport().get_visible_rect().size
		layout_strip(strip, bounds)
	run.call_deferred()

static func _strip_label(app, parent: Control, node_name: String, font_size: int, color: Color) -> Label:
	var label: Label = app.label("", font_size)
	label.name = node_name
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

static func _strip_flow(parent: Control, node_name: String) -> HFlowContainer:
	var flow := HFlowContainer.new()
	flow.name = node_name
	flow.add_theme_constant_override("h_separation", 8)
	flow.add_theme_constant_override("v_separation", 2)
	parent.add_child(flow)
	return flow

# ===================================================================== shared

## Holder Control with a BlueprintThumbnail child named "Art" (when the art
## script exists) and a faint blueprint-icon placeholder for empty designs.
static func _thumb(box: Vector2) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = box
	holder.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	holder.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	holder.clip_contents = true
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var placeholder := LifeShell.picture(LifeShell.icon("blueprint"), int(minf(48.0, minf(box.x, box.y))))
	placeholder.name = "Placeholder"
	placeholder.modulate = Color(1, 1, 1, 0.4)
	holder.add_child(placeholder)
	placeholder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if ResourceLoader.exists(THUMB_PATH):
		var script := load(THUMB_PATH) as Script
		if script != null and script.can_instantiate():
			var art = script.new()
			if art is Node2D:
				art.name = "Art"
				art.set("box_size", box)
				art.visible = false
				holder.add_child(art)
			elif art is Node:
				art.free()
	return holder

static func _set_design(holder: Control, design: Dictionary) -> void:
	if not is_instance_valid(holder):return
	var key: int = design.hash() if not design.is_empty() else 0
	if int(holder.get_meta("design_key", -1)) == key:return
	holder.set_meta("design_key", key)
	var art := holder.get_node_or_null("Art") as Node2D
	if art != null:
		art.set("design", design.duplicate(true))
		art.visible = not design.is_empty()
		art.queue_redraw()
	(holder.get_node("Placeholder") as Control).visible = art == null and not design.is_empty()

static func _chip() -> HBoxContainer:
	var chip := HBoxContainer.new()
	chip.mouse_filter = Control.MOUSE_FILTER_PASS
	chip.add_theme_constant_override("separation", 2)
	var picture := LifeShell.picture(null, 24)
	picture.name = "Icon"
	chip.add_child(picture)
	var count := Label.new()
	count.name = "Count"
	count.add_theme_font_size_override("font_size", 14)
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(count)
	return chip

## Reuses chip controls; only icon/text/colour of changed chips are touched.
static func _fill_chips(flow: Container, items: Dictionary, held: Dictionary, show_held: bool) -> void:
	if not is_instance_valid(flow):return
	var keys := items.keys()
	keys.sort()
	while flow.get_child_count() < keys.size():flow.add_child(_chip())
	for index in flow.get_child_count():
		var chip: Control = flow.get_child(index)
		var used := index < keys.size()
		if chip.visible != used:chip.visible = used
		if not used:continue
		var item := str(keys[index])
		var need := int(items[item])
		var name_text := str(World.NAMES.get(item, item))
		var picture: TextureRect = chip.get_node("Icon")
		if str(chip.get_meta("item", "")) != item:
			chip.set_meta("item", item)
			picture.texture = ItemArt.icon(item)
		picture.visible = picture.texture != null
		var count: Label = chip.get_node("Count")
		var prefix := "" if picture.texture != null else name_text + " "
		var have := int(held.get(item, 0))
		if show_held:
			_set_text(count, "%s%d／%d" % [prefix, have, need])
			count.add_theme_color_override("font_color", READY if have >= need else SHORT)
			chip.tooltip_text = "%s  持有 %d／所需 %d%s" % [name_text, have, need, "" if have >= need else "（缺 %d）" % (need - have)]
		else:
			_set_text(count, "%s×%d" % [prefix, need])
			count.add_theme_color_override("font_color", INK)
			chip.tooltip_text = "%s ×%d" % [name_text, need]

static func _small(app, text: String, callback: Callable) -> Button:
	var button: Button = app.button(text, callback)
	button.custom_minimum_size.y = 34
	button.add_theme_font_size_override("font_size", 14)
	return button

static func _icon_once(button: Button, id: String) -> Texture2D:
	if str(button.get_meta("icon_id", "")) == id and button.icon != null:return button.icon
	button.set_meta("icon_id", id)
	return LifeShell.icon(id)

## Connects while `owner` is in the tree; disconnects on tree exit so freed
## UI never receives controller/session signals.
static func _bind(owner: Node, source: Object, signal_name: String, callable: Callable) -> void:
	if not is_instance_valid(source) or not source.has_signal(signal_name):return
	var attach := func():
		if is_instance_valid(source) and not source.is_connected(signal_name, callable):
			source.connect(signal_name, callable)
	var detach := func():
		if is_instance_valid(source) and source.is_connected(signal_name, callable):
			source.disconnect(signal_name, callable)
	owner.tree_entered.connect(attach)
	owner.tree_exiting.connect(detach)
	if owner.is_inside_tree():attach.call()

static func _set_text(control: Control, text: String) -> void:
	if control == null:return
	if control.get("text") != text:control.set("text", text)

static func _entries(c) -> Array:
	var raw = c.get("entries")
	var out: Array = []
	if raw is Array:
		for entry in raw:
			if entry is Dictionary:out.append(entry)
	return out

static func _design_of(value: Dictionary) -> Dictionary:
	for key in ["design", "blueprint"]:
		if value.get(key) is Dictionary:return value[key]
	return value if value.has("pieces") else {}

static func _dict(value) -> Dictionary:
	return value if value is Dictionary else {}

static func _held(app) -> Dictionary:
	var session = app.get("session") if app != null else null
	if not session is Object:return {}
	var snapshot = session.get("snapshot")
	if not snapshot is Dictionary:return {}
	var person = snapshot.get("players", {}).get(str(session.get("own_id")), {})
	return _dict(person.get("inventory")) if person is Dictionary else {}

static func _busy(c) -> bool:
	return str(c.get("mode")) in ["submitting", "unknown"] or not _dict(c.get("pending")).is_empty() or not str(c.get("pending_error")).is_empty()

static func _call(target, method: String, args: Array):
	if not is_instance_valid(target) or not target.has_method(method):return null
	return target.callv(method, args)

static func _truthy(value) -> bool:
	if value is Dictionary:return bool(value.get("ok", false))
	return value is bool and value

static func _result(value) -> Dictionary:
	if value is Dictionary:return value
	return {"ok": value is bool and value, "reason": ""}

static func _status(c, fallback: String) -> String:
	var status = c.get("status")
	return str(status) if status is String and not str(status).is_empty() else fallback
