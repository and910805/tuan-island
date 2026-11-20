extends RefCounted
## Presentation only. Existing buttons, callbacks, signatures and file picker
## are retained; less common manual methods live in an explicit disclosure.
const Pixel=preload("res://scripts/inventory_pixel_theme.gd")

static func handle_navigation(overlay:Control,event:InputEvent)->bool:
	var picker:=overlay.get_node_or_null("UpdateArchivePicker") as FileDialog
	if picker and picker.visible:return false
	var panel:=overlay.find_child("VersionUpdatePanel",true,false) as Control
	var buttons:Array[Button]=[]
	for button:Button in panel.find_children("*","Button",true,false):
		if button.is_visible_in_tree() and not button.disabled:buttons.append(button)
	if event.is_action_pressed("ui_cancel") and not event.is_echo():
		var dismiss:=find_button(panel,"稍後再說")
		if not dismiss.disabled:
			var manual:=panel.find_child("UpdateManualMethods",true,false) as Control
			if manual.visible:
				var toggle:=panel.find_child("UpdateMethodsToggle",true,false) as Button
				toggle.pressed.emit()
				toggle.grab_focus()
			else:dismiss.pressed.emit()
		return true
	var focus:=overlay.get_viewport().gui_get_focus_owner() as Button
	if event.is_action("ui_accept"):
		if event.is_action_pressed("ui_accept") and not event.is_echo() and not buttons.is_empty():
			var target:=focus if focus in buttons else buttons[0]
			target.grab_focus()
			target.pressed.emit()
		return true
	var direction:=0
	for action in ["ui_focus_next","ui_down","ui_right"]:
		if event.is_action_pressed(action,true):direction=1;break
	for action in ["ui_focus_prev","ui_up","ui_left"]:
		if event.is_action_pressed(action,true):direction=-1;break
	if event is InputEventJoypadButton and event.pressed:
		if event.button_index in [JOY_BUTTON_DPAD_DOWN,JOY_BUTTON_DPAD_RIGHT]:direction=1
		elif event.button_index in [JOY_BUTTON_DPAD_UP,JOY_BUTTON_DPAD_LEFT]:direction=-1
	if direction==0:return false
	if not buttons.is_empty():
		var index:=buttons.find(focus)
		buttons[0 if index<0 else posmod(index+direction,buttons.size())].grab_focus()
	return true

static func find_button(parent:Node,caption:String)->Button:
	for node in parent.find_children("*","Button",true,false):
		if node.text==caption:return node
	return null

static func style_primary(button:Button)->void:
	button.custom_minimum_size.y=48
	for state in ["normal","hover","pressed","hover_pressed"]:
		button.add_theme_stylebox_override(state,Pixel.texture_style("button_pressed" if state!="hover" else "selected",3,10))
	for state in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:
		button.add_theme_color_override(state,Color("fff3cf"))

static func arrange(app:Node,overlay:Control,info:Dictionary)->void:
	var panel:PanelContainer=overlay.get_node("VersionUpdatePanel")
	var content:VBoxContainer=panel.get_child(0)
	var heading:Label=content.get_child(0)
	var details:Label=content.get_child(1)
	var download:=find_button(overlay,"前往下載新版")
	var dismiss:=find_button(overlay,"稍後再說")
	var fetch:=find_button(overlay,"在遊戲內下載")
	var launch:=find_button(overlay,"啟動新版")
	var folder:=find_button(overlay,"開啟新版資料夾")
	var status:=overlay.find_child("UpdateArchiveStatus",true,false) as Label
	var validate:=find_button(overlay,"驗證下載的 ZIP")
	var actions:HBoxContainer=validate.get_parent() if validate else null
	var center:=CenterContainer.new()
	center.name="UpdateCardCenter"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter=Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)
	panel.reparent(center)
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	panel.custom_minimum_size=Vector2(580,0)
	panel.theme=Pixel.make(overlay.theme)
	panel.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	panel.add_theme_stylebox_override("panel",Pixel.frame_style())
	content.add_theme_constant_override("separation",10)
	var header:=HBoxContainer.new()
	header.add_theme_constant_override("separation",14)
	content.add_child(header)
	content.move_child(header,0)
	var icon:=TextureRect.new()
	var atlas:=AtlasTexture.new()
	atlas.atlas=preload("res://assets/ui-life/icons.png")
	atlas.region=Rect2(128,64,32,32) # Existing letter icon.
	icon.texture=atlas
	icon.custom_minimum_size=Vector2(64,64)
	icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	header.add_child(icon)
	var titles:=VBoxContainer.new()
	titles.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	header.add_child(titles)
	var eyebrow:Label=app.label("小島來信",14)
	eyebrow.add_theme_color_override("font_color",Color("64734b"))
	titles.add_child(eyebrow)
	heading.reparent(titles)
	details.custom_minimum_size.y=0
	details.text="目前 %s   →   新版 %s\n%s"%[info.get("current_version",""),info.get("latest_version",""),"請先更新，再回到小島。" if info.get("required",false) else "準備好時，再一起回到小島。"]
	var paper:=PanelContainer.new()
	paper.name="UpdateMessagePaper"
	paper.add_theme_stylebox_override("panel",Pixel.paper_style())
	content.add_child(paper)
	content.move_child(paper,1)
	details.reparent(paper)
	var manual:=VBoxContainer.new()
	manual.name="UpdateManualMethods"
	manual.add_theme_constant_override("separation",8)
	manual.hide()
	content.add_child(manual)
	var footer:=HBoxContainer.new()
	footer.name="UpdateCardFooter"
	content.add_child(footer)
	var toggle:Button=app.button("其他更新方式 ▸",func():
		manual.visible=not manual.visible
	)
	toggle.name="UpdateMethodsToggle"
	toggle.flat=true
	toggle.tooltip_text="開啟下載頁，或使用已下載的 ZIP"
	toggle.pressed.connect(func():toggle.text="其他更新方式 ▾" if manual.visible else "其他更新方式 ▸")
	footer.add_child(toggle)
	var space:=Control.new()
	space.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	footer.add_child(space)
	dismiss.reparent(footer)
	dismiss.flat=true
	if fetch:
		download.reparent(manual)
		style_primary(fetch)
		content.move_child(fetch,2)
	else:
		style_primary(download)
		content.move_child(download,2)
	if actions:actions.reparent(manual)
	if folder:folder.reparent(manual)
	if status:
		status.custom_minimum_size=Vector2(0,42)
		status.text="下載後會先核對檔案，再準備啟動。"
		status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		content.move_child(status,3)
	var progress:=ProgressBar.new()
	progress.name="UpdateDownloadProgress"
	progress.custom_minimum_size.y=12
	progress.show_percentage=false
	progress.add_theme_stylebox_override("background",Pixel.paper_style())
	progress.add_theme_stylebox_override("fill",Pixel.texture_style("button_pressed",3,0))
	content.add_child(progress)
	content.move_child(progress,4)
	progress.hide()
	for node in overlay.get_children():
		if node.has_signal("transfer_progress"):
			node.connect("transfer_progress",func(percent:int):
				progress.value=percent
				progress.show()
			)
	if launch:
		style_primary(launch)
		content.move_child(launch,2)
		launch.visibility_changed.connect(func():
			if is_instance_valid(fetch):fetch.visible=not launch.visible
			if launch.is_visible_in_tree():launch.grab_focus()
		)
	toggle.visible=fetch!=null or actions!=null or folder!=null
	content.move_child(footer,content.get_child_count()-2)
	content.move_child(manual,content.get_child_count()-1)
	if fetch:fetch.grab_focus()
	else:download.grab_focus()
	if app.sound!=null and not app.sound.reduced_motion:
		overlay.modulate.a=0.0
		overlay.create_tween().tween_property(overlay,"modulate:a",1.0,0.14).set_trans(Tween.TRANS_SINE)
