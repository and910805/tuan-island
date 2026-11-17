extends RefCounted

const View=preload("res://scripts/world_view.gd")
const World=preload("res://scripts/world.gd")
const PixelTheme=preload("res://scripts/inventory_pixel_theme.gd")
const Shell=preload("res://scripts/life_ui_shell.gd")
const ThemeArt=preload("res://scripts/life_ui_theme.gd")

static func make_menu(app) -> void:
	app.menu=Control.new()
	app.menu.theme=app.theme()
	app.menu.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	app.ui.add_child(app.menu)
	app.menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var view:=View.new()
	view.village_art_preview=true
	app.menu.add_child(view)
	view.set_process(false)
	view.camera=Vector2(830,778)
	var island:=World.new()
	island.state.board=true
	view.update_snapshot(island.state,"")

	var scroll:=ScrollContainer.new()
	app.menu.add_child(scroll)
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus=true
	var margin:=MarginContainer.new()
	margin.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left",56)
	margin.add_theme_constant_override("margin_top",54)
	margin.add_theme_constant_override("margin_bottom",78)
	scroll.add_child(margin)
	var shell:=PanelContainer.new()
	shell.custom_minimum_size.x=370
	shell.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	shell.size_flags_vertical=Control.SIZE_SHRINK_BEGIN
	shell.add_theme_stylebox_override("panel",ThemeArt.panel_style())
	margin.add_child(shell)
	var content:=VBoxContainer.new()
	content.add_theme_constant_override("separation",12)
	shell.add_child(content)
	var masthead:=HBoxContainer.new()
	masthead.add_theme_constant_override("separation",10)
	content.add_child(masthead)
	masthead.add_child(Shell.picture(Shell.icon("home"),48))
	masthead.add_child(app.label("糰糰島",48))
	content.add_child(app.label("一起種一片田，慢慢蓋一個家。",18))
	content.add_child(app.label("島民名字",16))
	app.name_input=field("小糰","島民名字")
	app.name_input.max_length=12
	content.add_child(app.name_input)
	var enter:Button=app.button("住進自己的小島",func():app._host(false))
	enter.name="TitleSolo"
	enter.custom_minimum_size.y=52
	enter.add_theme_stylebox_override("normal",PixelTheme.texture_style("button_pressed",3,8))
	enter.add_theme_stylebox_override("hover",PixelTheme.texture_style("button_pressed",3,8))
	for color in ["font_color","font_hover_color","font_focus_color"]:
		enter.add_theme_color_override(color,Color("fff3cf"))
	content.add_child(enter)
	var adventure:Button=app.button("開啟冒險小島",func():app._host(false,"adventure"))
	adventure.name="TitleAdventure"
	content.add_child(adventure)
	var identity:Button=app.button("封測島嶼",app._open_identity)
	identity.icon=Shell.icon("letter")
	content.add_child(identity)

	var invitation:=PanelContainer.new()
	invitation.add_theme_stylebox_override("panel",ThemeArt.badge_style())
	content.add_child(invitation)
	var mail:=VBoxContainer.new()
	mail.add_theme_constant_override("separation",8)
	invitation.add_child(mail)
	var room:=VBoxContainer.new()
	room.add_theme_constant_override("separation",7)
	room.hide()
	var toggle:Button=app.button("朋友房間  ▸",func():room.visible=not room.visible)
	toggle.name="TitleFriends"
	toggle.icon=Shell.icon("letter")
	toggle.toggle_mode=true
	toggle.custom_minimum_size.y=44
	mail.add_child(toggle)
	enter.focus_neighbor_bottom=enter.get_path_to(adventure)
	adventure.focus_neighbor_top=adventure.get_path_to(enter)
	adventure.focus_neighbor_bottom=adventure.get_path_to(identity)
	identity.focus_neighbor_top=identity.get_path_to(adventure)
	identity.focus_neighbor_bottom=identity.get_path_to(toggle)
	toggle.focus_neighbor_top=toggle.get_path_to(identity)
	mail.add_child(room)
	room.add_child(app.label("房間密碼",15))
	app.key_input=field("","至少四個字")
	app.key_input.secret=true
	room.add_child(app.key_input)
	room.add_child(app.label("連接埠",15))
	app.port_input=field("28417","連接埠")
	room.add_child(app.port_input)
	room.add_child(app.button("開啟區域網路房間",func():app._host(true)))
	room.add_child(app.button("開啟冒險房間",func():app._host(true,"adventure")))
	room.add_child(app.label("朋友的伺服器位址",15))
	app.address_input=field("127.0.0.1","IP 或完整 wss:// 網址")
	room.add_child(app.address_input)
	room.add_child(app.button("加入朋友的小島",app._join))
	room.visibility_changed.connect(func():toggle.text="朋友房間  ▾" if room.visible else "朋友房間  ▸")
	content.add_child(app.title_build_label())

	app.toast=app.label("歡迎來到糰糰島。",16)
	app.ui.add_child(app.toast)
	style_menu_notice(app)
	app.menu.visibility_changed.connect(func():
		if app.menu.visible:style_menu_notice.call_deferred(app)
		else:app.toast.set_anchors_preset(Control.PRESET_TOP_LEFT)
	)

static func style_menu_notice(app) -> void:
	if not app.menu.visible:return
	var toast:Label=app.toast
	toast.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	toast.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	toast.add_theme_color_override("font_color",ThemeArt.INK)
	toast.add_theme_stylebox_override("normal",ThemeArt.badge_style())
	toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	toast.offset_left=-310
	toast.offset_right=310
	toast.offset_top=-56
	toast.offset_bottom=-14

static func field(initial:String,hint:String) -> LineEdit:
	var control:=LineEdit.new()
	control.text=initial
	control.placeholder_text=hint
	control.custom_minimum_size.y=44
	return control
