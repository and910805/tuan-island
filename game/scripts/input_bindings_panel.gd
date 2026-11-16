extends VBoxContainer

const Bindings=preload("res://scripts/input_bindings.gd")
var app
var capturing:=""
var pending_key:=0
var notice:Label
var confirm_row:HBoxContainer
var values:Dictionary={}
var category_pages:Dictionary={}
var category_buttons:Dictionary={}
var transfer_button:Button

func setup(owner) -> void:
	app=owner
	var parent:VBoxContainer=app._open_modal("鍵盤設定")
	parent.add_child(self)
	add_theme_constant_override("separation",9)
	# Bindings follow the key label of the active keyboard layout (Bindings.event_key), not physical positions.
	var intro:Label=app.label("依目前鍵盤配置上的鍵名綁定。Esc 取消改鍵或返回，方向鍵仍操作介面。",15)
	add_child(intro)
	notice=app.label("",16)
	notice.custom_minimum_size.y=28
	add_child(notice)
	confirm_row=HBoxContainer.new()
	add_child(confirm_row)
	transfer_button=app.button("轉移這個鍵",confirm_transfer)
	confirm_row.add_child(transfer_button)
	confirm_row.add_child(app.button("取消",func():cancel_capture()))
	confirm_row.hide()
	add_child(app.button("恢復預設",func():finish(app.bindings.restore_defaults())))
	var category_tabs:=HBoxContainer.new()
	add_child(category_tabs)
	var group:=ButtonGroup.new()
	for title in Bindings.GROUPS:
		var button:Button=app.button(title,func():select_category(title))
		button.toggle_mode=true
		button.button_group=group
		button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		category_tabs.add_child(button)
		category_buttons[title]=button
	for title in Bindings.GROUPS:
		var rows:=VBoxContainer.new()
		add_child(rows)
		category_pages[title]=rows
		for action in Bindings.GROUPS[title]:
			add_action(rows,action)
	select_category(Bindings.GROUPS.keys()[0])
	refresh()

func select_category(title:String) -> void:
	if not capturing.is_empty():cancel_capture()
	for category in category_pages:
		category_pages[category].visible=category==title
		category_buttons[category].set_pressed_no_signal(category==title)

func add_action(parent:VBoxContainer,action:String) -> void:
	var row:=HBoxContainer.new()
	parent.add_child(row)
	var name_label:Label=app.label(Bindings.LABELS[action],16)
	name_label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	var value:Label=app.label("",16)
	value.custom_minimum_size.x=110
	row.add_child(value)
	values[action]=value
	row.add_child(app.button("改鍵",func():begin_capture(action)))
	row.add_child(app.button("清除",func():finish(app.bindings.clear(action))))

func refresh() -> void:
	for action in values:
		values[action].text=app.binding_label(action)

func begin_capture(action:String) -> void:
	capturing=action
	pending_key=0
	confirm_row.hide()
	notice.text="請按新的按鍵 · %s · Esc 取消"%Bindings.LABELS[action]
	app.get_viewport().gui_release_focus()
	reveal_notice()

func reveal_notice() -> void:
	var node:=get_parent()
	while node and not node is ScrollContainer:node=node.get_parent()
	if node:node.ensure_control_visible.call_deferred(notice)

func capture_event(event:InputEvent) -> bool:
	if capturing.is_empty() or not is_visible_in_tree() or not event is InputEventKey:return false
	# One identity for Escape, modifiers, storage and display: Bindings.event_key
	# (logical key of the active layout; physical only when no logical code exists).
	var key:int=Bindings.event_key(event as InputEventKey)
	if event.pressed and not event.echo and key==KEY_ESCAPE:
		cancel_capture()
		return true
	if pending_key!=0:return false
	if not event.pressed or event.echo:return true
	if key==KEY_NONE or key==KEY_UNKNOWN:
		notice.text="無法辨識這個鍵，請換一個。Esc 取消。"
		return true
	var has_extra_modifier: bool = event.meta_pressed or (event.ctrl_pressed and key != KEY_CTRL) or (
		event.alt_pressed and key != KEY_ALT) or (event.shift_pressed and key != KEY_SHIFT)
	if has_extra_modifier:
		notice.text="請只按一個鍵。Esc 取消。"
		return true
	var result:Dictionary=app.bindings.rebind(capturing,key)
	if result.has("conflict"):
		pending_key=key
		confirm_row.show()
		notice.text="把 %s 轉移給「%s」？原本「%s」將未設定。"%[OS.get_keycode_string(pending_key),Bindings.LABELS[capturing],Bindings.LABELS[result.conflict]]
		transfer_button.grab_focus()
		reveal_notice()
	elif result.ok:
		finish(result)
	else:
		notice.text=result.message+" Esc 取消。"
	return true

func cancel_capture() -> bool:
	if capturing.is_empty():return false
	capturing=""
	pending_key=0
	confirm_row.hide()
	notice.text="已取消改鍵。"
	return true

func confirm_transfer() -> void:
	if pending_key!=0 and not capturing.is_empty():finish(app.bindings.rebind(capturing,pending_key,true))

func finish(result:Dictionary) -> void:
	var action:=capturing
	capturing=""
	pending_key=0
	confirm_row.hide()
	notice.text=result.message
	if result.ok:
		if not action.is_empty():notice.text="已儲存「%s」的新按鍵 %s。"%[Bindings.LABELS[action],app.binding_label(action)]
		refresh()
		app._bindings_changed()
	reveal_notice()
