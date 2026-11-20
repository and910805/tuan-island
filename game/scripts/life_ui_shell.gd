extends RefCounted

const Art=preload("res://scripts/life_ui_theme.gd")
const Items=preload("res://scripts/inventory_item_art.gd")
const World=preload("res://scripts/world.gd")
const WeatherArt=preload("res://scripts/weather_art.gd")
const Forecast=preload("res://scripts/weather_forecast.gd")
const FORECAST_TIP_WIDTH:=360
const SHORTCUT_WIDTH:=58
const SHORTCUT_COMPACT_WIDTH:=44
## Keyboard path to the read-only forecast: Godot's existing ui_focus_prev
## (Shift+Tab). Plain Tab stays the (rebindable) inventory key.
const FORECAST_HOVER_HINT:="鍵盤：Shift+Tab 開關這張預報"
const FORECAST_TIP_HINT:="Shift+Tab／Esc 收起"
const MINE_NOTE_ART:=preload("res://assets/ui-life/mine-notebook-32.png")
const MINE_ENERGY_WARNING:=25
const FOREST_TOOLS:={"axe":preload("res://assets/ui-life/forest-axe.png"),"pick":preload("res://assets/ui-life/forest-pick.png")}
const TOOL_IDS=["hoe","seed","water","harvest","axe","pick","build","remove"]
const TOOL_NAMES=["鋤頭","播種","澆水","採收","斧頭","十字鎬","建造","拆除"]
const ICON_IDS=["hoe","water","harvest","axe","pick","build","remove","fish","map","journal","weather","calendar","settings","bell","letter","home","sign","trophy","blueprint","chest"]

static func icon(id:String) -> Texture2D:
	if id=="seed":return Items.icon("radish_seed")
	if id in ["backpack","coins"]:return Items.icon(id)
	var index:=ICON_IDS.find(id)
	if index<0:return Items.icon(id)
	if not ResourceLoader.exists("res://assets/ui-life/icons.png"):return Items.icon("sapling")
	var result:=AtlasTexture.new()
	result.atlas=load("res://assets/ui-life/icons.png")
	result.region=Rect2((index%5)*32,(index/5)*32,32,32)
	result.filter_clip=true
	return result

static func picture(texture:Texture2D,extent:int=48) -> TextureRect:
	var result:=TextureRect.new()
	result.texture=texture
	result.custom_minimum_size=Vector2(extent,extent)
	result.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	result.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	result.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	result.mouse_filter=Control.MOUSE_FILTER_IGNORE
	return result

static func icon_button(app,id:String,title:String,key:String,callback:Callable,extent:int=72) -> Button:
	var result:=Button.new()
	result.custom_minimum_size=Vector2(extent,extent)
	result.tooltip_text=title+("  ["+key+"]" if not key.is_empty() else "")
	result.theme_type_variation="ItemSlot"
	result.pressed.connect(callback)
	var pixels:=64 if extent>=72 else 32
	var inset:=float(extent-pixels)/2
	var art:=picture(icon(id),pixels)
	art.name="ToolArt"
	art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	art.offset_left=inset;art.offset_right=-inset;art.offset_top=inset;art.offset_bottom=-inset
	result.add_child(art)
	if not key.is_empty():
		var badge:=Label.new()
		badge.name="KeyBadge"
		badge.text=key
		badge.position=Vector2(4,3)
		badge.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		badge.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
		badge.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
		badge.add_theme_font_size_override("font_size",13)
		badge.add_theme_color_override("font_color",Color("fff4dc"))
		badge.add_theme_stylebox_override("normal",Art.surface(Color("3e4436"),Color("8f7d55"),4.0,0.0))
		badge.mouse_filter=Control.MOUSE_FILTER_IGNORE
		result.add_child(badge)
		badge.minimum_size_changed.connect(func():fit_key_badge(badge,result.custom_minimum_size.x-8),CONNECT_DEFERRED)
		fit_key_badge(badge,extent-8)
	result.mouse_entered.connect(func():
		if app.sound and not app.sound.reduced_motion:
			var tween:=result.create_tween()
			tween.tween_property(art,"modulate",Color(1.12,1.12,1.05),0.12)
	)
	result.mouse_exited.connect(func():art.modulate=Color.WHITE)
	return result

static func fit_key_badge(badge:Label,available:float)->void:
	if not is_instance_valid(badge) or not badge.is_inside_tree():return
	var font:=badge.get_theme_font("font")
	var font_size:=badge.get_theme_font_size("font_size")
	var width:=font.get_string_size(badge.text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x
	badge.size=Vector2(clampf(ceilf(width)+10.0,20.0,available),ceilf(font.get_height(font_size))+2.0)

static func shortcut_button(app,id:String,title:String,action:String,callback:Callable)->Button:
	var shortcut:=bound_button(app,id,title,action,callback,SHORTCUT_WIDTH) if action!="ui_cancel" else icon_button(app,id,title,"Esc",callback,SHORTCUT_WIDTH)
	shortcut.custom_minimum_size.y=82
	var art:=shortcut.get_node("ToolArt") as TextureRect
	art.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	art.position=Vector2(13,27)
	art.size=Vector2(32,32)
	var caption:=Label.new()
	caption.name="ShortcutTitle"
	caption.text=title
	caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	caption.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size",16)
	caption.add_theme_color_override("font_color",Color("303e2e"))
	caption.mouse_filter=Control.MOUSE_FILTER_IGNORE
	shortcut.add_child(caption)
	caption.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	caption.offset_bottom=-2
	var key:=shortcut.get_node("KeyBadge") as Label
	var fit_caption:=func():
		if not is_instance_valid(caption) or not is_instance_valid(shortcut):return
		var height:=maxf(22.0,caption.get_combined_minimum_size().y)
		var key_height:=key.get_theme_font("font").get_height(key.get_theme_font_size("font_size"))
		art.position.y=maxf(27.0,ceilf(key_height)+8.0)
		caption.offset_top=-height-2.0
		shortcut.custom_minimum_size.y=art.position.y+35.0+height
		app._layout_preview.call_deferred()
	caption.minimum_size_changed.connect(fit_caption,CONNECT_DEFERRED)
	key.minimum_size_changed.connect(fit_caption,CONNECT_DEFERRED)
	fit_caption.call()
	return shortcut

static func text(app,value:String,size:int=16) -> Label:
	var result:Label=app.label(value,size)
	result.autowrap_mode=TextServer.AUTOWRAP_OFF
	return result

static func make_hud(app) -> void:
	var location:=VBoxContainer.new()
	location.name="LocationBadge"
	location.position=Vector2(22,18)
	location.size=Vector2(230,60)
	location.mouse_filter=Control.MOUSE_FILTER_IGNORE
	app.hud.add_child(location)
	location.minimum_size_changed.connect(app._layout_preview.call_deferred)
	var title:=text(app,"風鈴渡口",24)
	title.name="RegionTitle"
	title.add_theme_color_override("font_color",Color("fff4d6"))
	title.add_theme_color_override("font_outline_color",Color("3c4c36"))
	title.add_theme_constant_override("outline_size",6)
	location.add_child(title)
	var subtitle:=text(app,"慢慢來，島上的日子還很長",15)
	app.region_subtitle=subtitle
	subtitle.add_theme_color_override("font_color",Color("fff4d6"))
	subtitle.add_theme_color_override("font_outline_color",Color("3c4c36"))
	subtitle.add_theme_constant_override("outline_size",4)
	location.add_child(subtitle)
	var tracker:=PanelContainer.new()
	tracker.name="QuestNote"
	tracker.position=Vector2(20,92)
	tracker.custom_minimum_size=Vector2(226,0)
	tracker.size=Vector2(226,0)
	tracker.add_theme_stylebox_override("panel",Art.badge_style())
	app.hud.add_child(tracker)
	app.preview_tracker=tracker
	# 礦區專用：礦務隨身記預設收成一枚小圖示，點一下才在圖示下方展開同一張追蹤卡。
	var mine_icon:=icon_button(app,"letter","礦務隨身記",
		"",func():toggle_mine_note(app),48)
	mine_icon.name="MineNoteIcon"
	mine_icon.tooltip_text="礦務隨身記（點一下展開或收起）"
	(mine_icon.get_node("ToolArt") as TextureRect).texture=MINE_NOTE_ART
	mine_icon.focus_mode=Control.FOCUS_NONE # 不吃空白／Enter，也不與任何快捷鍵搶焦點
	mine_icon.position=tracker.position
	mine_icon.size=Vector2(48,48)
	var stamina:=Label.new()
	stamina.name="LowMineEnergy"
	stamina.position=Vector2(23,22)
	stamina.size=Vector2(23,23)
	stamina.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	stamina.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	stamina.add_theme_font_size_override("font_size",13)
	stamina.add_theme_color_override("font_color",Color("fff1cf"))
	stamina.add_theme_stylebox_override("normal",Art.surface(Color("713525"),Color("e2a663"),1.0,0.0))
	stamina.mouse_filter=Control.MOUSE_FILTER_IGNORE
	stamina.hide()
	mine_icon.add_child(stamina)
	mine_icon.hide()
	app.hud.add_child(mine_icon)
	app.preview_controls.append(mine_icon)
	var note:=VBoxContainer.new()
	tracker.add_child(note)
	var heading:=HBoxContainer.new()
	note.add_child(heading)
	heading.add_child(picture(icon("letter"),24))
	var toggle:Button=app.button("渡口的一封信  ▼",func():
		app.objective.visible=not app.objective.visible
		if bool(tracker.get_meta("tea_compact",false)):compact_tracker(app,true)
		tracker.size.y=0
	)
	toggle.name="TrackerHeading"
	toggle.flat=true
	toggle.custom_minimum_size.y=28
	toggle.add_theme_font_size_override("font_size",15)
	heading.add_child(toggle)
	app.objective=app.label("",15)
	app.objective.custom_minimum_size.x=202
	note.add_child(app.objective)
	var open:Button=app.button("看看下一步  →",func():
		var onboarding=preload("res://scripts/wangan_opening_ui.gd")
		if app._in_cart_gallery():app._party_cart_menu()
		elif app._beach_shovel_active():app._beach_treasure_menu()
		elif app._lost_chicks_active():app._lost_chicks_menu()
		elif app._stroll_tracking():app._stroll_menu()
		elif app._cooking_relay_active():app._cooking_relay_menu()
		elif not onboarding.personal_step(app).is_empty():onboarding.show_personal_help(app)
		elif app._harvest_tracking():app._harvest_menu() # T071 豐收接力（已加入進行中的一輪）
		elif app._fishmeet_tracking():app._fishmeet_menu() # T071 河岸釣魚會（已加入進行中的一輪）
		elif app._showcase_tracking():app._showcase_menu() # T071 家園布置題（已加入進行中的一輪）
		elif str(app.session.snapshot.get("region_id","home"))=="home" and app.session.snapshot.get("festival",{}).get("active",false):app._festival_menu()
		elif str(app.session.snapshot.get("region_id","home"))=="tianwei":app._journal()
		elif preload("res://scripts/salt_revisit_ui.gd").tracking(app.session.snapshot,str(app.session.own_id)):preload("res://scripts/salt_revisit_ui.gd").open(app) # 第 40 章：追蹤卡正在追鹽籃批次
		elif str(app.session.snapshot.get("region_id","home"))=="beimen":app._journal()
		elif str(app._home_memory_hint().get("kind",""))=="exhibit":preload("res://scripts/memory_exhibit_ui.gd").open(app) # 第 40 章：追蹤卡正在提示未看的展品
		elif preload("res://scripts/tea_revisit_ui.gd").tracking(app.session.snapshot,str(app.session.own_id)):preload("res://scripts/tea_revisit_ui.gd").open(app) # 第 40 章：追蹤卡正在追茶罐大單
		elif app._tea_guidance_active():app._tea_next_step()
		elif str(app.session.snapshot.get("region_id","home")).begins_with("mine_"):app._map_menu()
		elif str(app.session.snapshot.get("region_id","home"))=="lanyang":app._gardener_menu()
		elif preload("res://scripts/jinguashi_revisit_ui.gd").tracking(app.session.snapshot):preload("res://scripts/jinguashi_revisit_ui.gd").open(app) # 第 40 章：追蹤卡正在追礦料調度
		elif str(app.session.snapshot.get("region_id","home"))=="jinguashi":app._journal("bobo")
		elif preload("res://scripts/transit_art.gd").NAMES.has(str(app.session.snapshot.get("region_id",""))):app._travel_menu()
		elif World.CHAPTER_ONE.phase(app.session.snapshot)=="complete":app._travel_menu()
		else:app._chapter_menu()
	)
	open.name="TrackerNext"
	open.custom_minimum_size.y=26
	open.add_theme_font_size_override("font_size",15)
	open.flat=true
	note.add_child(open)
	# T071 豐收接力：手上有模型蔬菜時才顯示（harvest_relay_ui.refresh_hud 控制）。
	var relay_pass:Button=app.button("傳給身旁的夥伴  →",app._harvest_pass)
	relay_pass.name="TrackerHarvestPass"
	relay_pass.custom_minimum_size.y=26
	relay_pass.add_theme_font_size_override("font_size",15)
	relay_pass.flat=true
	relay_pass.hide()
	note.add_child(relay_pass)
	var top:=HBoxContainer.new()
	app.preview_top=top
	app.hud.add_child(top)
	top.minimum_size_changed.connect(app._layout_preview.call_deferred)
	var calendar:=PanelContainer.new()
	calendar.name="WeatherBadge"
	calendar.custom_minimum_size=Vector2(222,0)
	calendar.add_theme_stylebox_override("panel",Art.badge_style())
	# Read-only forecast: native tooltip on hover; keyboard/click focus shows the
	# same text in a non-blocking tip. Focus never consumes movement keys
	# (movement is polled) and no session action is ever sent.
	calendar.mouse_filter=Control.MOUSE_FILTER_PASS
	calendar.focus_mode=Control.FOCUS_ALL
	top.add_child(calendar)
	# Arrow / Tab GUI navigation never wanders from the badge onto toolbar buttons.
	for side in [SIDE_LEFT,SIDE_TOP,SIDE_RIGHT,SIDE_BOTTOM]:calendar.set_focus_neighbor(side,NodePath("."))
	calendar.focus_next=NodePath(".")
	calendar.focus_previous=NodePath(".")
	var day:=VBoxContainer.new()
	calendar.add_child(day)
	calendar.minimum_size_changed.connect(func():app._layout_preview.call_deferred())
	var sky:=HBoxContainer.new()
	sky.add_theme_constant_override("separation",10)
	day.add_child(sky)
	# Neutral calendar until the first refresh resolves the real weather; the sun icon is only used when sunny.
	var weather_icon:=picture(icon("calendar"),32)
	weather_icon.name="WeatherIcon"
	weather_icon.set_meta("weather_icon_id","calendar")
	sky.add_child(weather_icon)
	app.status_label=text(app,"",17)
	sky.add_child(app.status_label)
	var wallet:=HBoxContainer.new()
	wallet.alignment=BoxContainer.ALIGNMENT_END
	# Compact tomorrow line shares the existing coin row so the badge keeps its height.
	var tomorrow:=text(app,"",15)
	tomorrow.name="WeatherTomorrow"
	tomorrow.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	tomorrow.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	tomorrow.mouse_filter=Control.MOUSE_FILTER_IGNORE
	wallet.add_child(tomorrow)
	wallet.add_child(picture(icon("coins"),24))
	app.coin_label=text(app,"",18)
	wallet.add_child(app.coin_label)
	day.add_child(wallet)
	var tip:=PanelContainer.new()
	tip.name="WeatherForecastTip"
	tip.add_theme_stylebox_override("panel",Art.badge_style())
	tip.mouse_filter=Control.MOUSE_FILTER_IGNORE
	tip.custom_minimum_size=Vector2(FORECAST_TIP_WIDTH,0)
	tip.hide()
	app.hud.add_child(tip)
	var tip_text:Label=app.label("",13)
	tip_text.name="WeatherForecastTipText"
	tip_text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	tip_text.custom_minimum_size.x=FORECAST_TIP_WIDTH-24
	tip_text.mouse_filter=Control.MOUSE_FILTER_IGNORE
	tip.add_child(tip_text)
	calendar.focus_entered.connect(func():sync_forecast_tip(app))
	calendar.focus_exited.connect(func():sync_forecast_tip(app))
	var toolbar:=PanelContainer.new()
	app.preview_toolbar=toolbar
	toolbar.add_theme_stylebox_override("panel",Art.toolbar_style())
	app.hud.add_child(toolbar)
	var row:=HBoxContainer.new()
	row.add_theme_constant_override("separation",4)
	toolbar.add_child(row)
	for i in TOOL_IDS.size():
		var action:String=TOOL_IDS[i]
		var tool:=bound_button(app,action,TOOL_NAMES[i],action,func():app._select_tool(action))
		tool.toggle_mode=true
		row.add_child(tool)
		app.tool_buttons.append(tool)
	var rod:=bound_button(app,"fish","釣竿","fish",func():app._select_tool("fish"))
	rod.toggle_mode=true
	rod.name="FishingSlot"
	row.add_child(rod)
	var tiller:=bound_button(app,"tiller","手推耕田機","till_area",func():app._select_tool("till_area"))
	tiller.toggle_mode=true
	tiller.name="TillerSlot"
	tiller.hide()
	row.add_child(tiller)
	var seeder:=bound_button(app,"seeder","手推播種機","seed_area",func():app._select_tool("seed_area"))
	seeder.toggle_mode=true
	seeder.name="SeederSlot"
	seeder.hide()
	row.add_child(seeder)
	var harvester:=bound_button(app,"harvester","手推收割機","harvest_area",func():app._select_tool("harvest_area"))
	harvester.toggle_mode=true
	harvester.name="HarvesterSlot"
	harvester.hide()
	row.add_child(harvester)
	# 第一株作物指引：只在指引期間顯示的「所有工具」切換鈕（只存在於這個用戶端）。
	var all_tools:Button=app.button("所有\n工具",func():toggle_all_tools(app))
	all_tools.name="AllToolsToggle"
	all_tools.custom_minimum_size=Vector2(76,72)
	all_tools.add_theme_font_size_override("font_size",15)
	all_tools.tooltip_text="展開或收合完整工具列"
	all_tools.hide()
	row.add_child(all_tools)
	app.selected_label=app.label("",15)
	app.selected_label.name="ToolHint"
	app.selected_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	app.selected_label.add_theme_color_override("font_color",Color("fff7e5"))
	app.selected_label.add_theme_color_override("font_outline_color",Color("36432c"))
	app.selected_label.add_theme_constant_override("outline_size",5)
	app.selected_label.mouse_filter=Control.MOUSE_FILTER_IGNORE
	app.hud.add_child(app.selected_label)
	var shortcuts:=HBoxContainer.new()
	shortcuts.name="LifeShortcuts"
	shortcuts.add_theme_constant_override("separation",6)
	app.hud.add_child(shortcuts)
	shortcuts.minimum_size_changed.connect(app._layout_preview.call_deferred)
	shortcuts.add_child(shortcut_button(app,"backpack","背包","inventory",app._inventory))
	shortcuts.add_child(shortcut_button(app,"journal","手帳","journal",app._journal))
	shortcuts.add_child(shortcut_button(app,"settings","選單","ui_cancel",app._pause_menu))
	app.preview_controls.append_array([tracker,top,toolbar,shortcuts])

static func bound_button(app,id:String,title:String,action:String,callback:Callable,extent:int=72) -> Button:
	var key:String=app.binding_label(action)
	var result:=icon_button(app,id,title,"—" if key=="未設定" else key,callback,extent)
	result.set_meta("binding_action",action)
	result.set_meta("binding_title",title)
	result.tooltip_text="%s [%s]"%[title,key]
	return result

static func refresh_binding_hints(app) -> void:
	for node in app.hud.find_children("*","Button",true,false):
		if not node.has_meta("binding_action"):continue
		var key:String=app.binding_label(node.get_meta("binding_action"))
		var badge:=node.get_node_or_null("KeyBadge") as Label
		if badge:
			badge.text="—" if key=="未設定" else key
			fit_key_badge(badge,node.custom_minimum_size.x-8)
		node.tooltip_text="%s [%s]"%[node.get_meta("binding_title"),key]

## 工具列寬度＝目前可見子節點的最小寬度加間距與外框，所以任何顯示組合都會置中。
static func toolbar_width_for(toolbar:Control) -> int:
	var row:=toolbar.get_child(0) as BoxContainer
	var total:=0.0
	var count:=0
	for child in row.get_children():
		var item:=child as Control
		if item==null or not item.visible:continue
		total+=item.get_combined_minimum_size().x
		count+=1
	if count>1:total+=float(row.get_theme_constant("separation"))*float(count-1)
	return int(ceil(total+toolbar.get_theme_stylebox("panel").get_minimum_size().x))

## 第一株作物各步驟累積解鎖的工具；空陣列代表不在指引中。
static func guided_ids(step_id:String) -> Array:
	match step_id:
		"find","till":return ["hoe"]
		"buy_seed","sow":return ["hoe","seed"]
		"water","wait":return ["hoe","seed","water"]
		"harvest","ship":return ["hoe","seed","water","harvest"]
	return []

## 「所有工具」展開狀態只記在這個執行中的用戶端（掛在工具列節點上，依玩家 id 分開），不送伺服器、不存檔。
static func guided_overrides(toolbar:Control) -> Dictionary:
	if not toolbar.has_meta("guided_expanded"):toolbar.set_meta("guided_expanded",{})
	return toolbar.get_meta("guided_expanded")

static func toggle_all_tools(app) -> void:
	if not is_instance_valid(app.preview_toolbar):return
	var overrides:=guided_overrides(app.preview_toolbar)
	var key:=str(app.session.own_id)
	overrides[key]=not bool(overrides.get(key,false))
	app._refresh_hud()

## 依第一株作物步驟顯示／收起基本工具與釣竿；回傳可見組合是否改變（需要重排）。
## 目前選取的工具永遠可見；快捷鍵與手把仍直接呼叫 _select_tool，不受按鈕顯示影響。
static func guided_toolbar(app,step:Dictionary) -> bool:
	var toolbar:=app.preview_toolbar as Control
	if toolbar==null:return false
	var unlocked:Array=guided_ids(str(step.get("id","")))
	var guided:=not unlocked.is_empty()
	var expanded:bool=guided and bool(guided_overrides(toolbar).get(str(app.session.own_id),false))
	var narrowed:=guided and not expanded
	var changed:=false
	for index in mini(TOOL_IDS.size(),app.tool_buttons.size()):
		var button:Button=app.tool_buttons[index]
		var show:bool=not narrowed or TOOL_IDS[index] in unlocked or str(app.selected)==TOOL_IDS[index]
		if button.visible!=show:
			button.visible=show
			changed=true
	var rod:=toolbar.find_child("FishingSlot",true,false) as Button
	if rod:
		var show_rod:=not narrowed or str(app.selected)=="fish"
		if rod.visible!=show_rod:
			rod.visible=show_rod
			changed=true
	var toggle:=toolbar.find_child("AllToolsToggle",true,false) as Button
	if toggle:
		var label:="收合\n工具" if expanded else "所有\n工具"
		if toggle.text!=label:
			toggle.text=label
			changed=true
		if toggle.visible!=guided:
			toggle.visible=guided
			changed=true
	return changed

## Fixed public tea room only: collapse the quest note to its clickable header
## (expand it to reach the objective and the guide button) and restore the
## outdoor state on exit. Runs after every refresh, so it never fights text writes.
static func compact_tracker(app,active:bool) -> void:
	var tracker:=app.preview_tracker as Control
	if not is_instance_valid(tracker) or not is_instance_valid(app.objective):return
	sync_mine_note(app)
	var next:=tracker.find_child("TrackerNext",true,false) as Button
	var heading:=tracker.find_child("TrackerHeading",true,false) as Button
	var was:=bool(tracker.get_meta("tea_compact",false))
	if active:
		if not was:
			tracker.set_meta("tea_compact",true)
			tracker.set_meta("tea_saved_objective",app.objective.visible)
			tracker.set_meta("tea_saved_next",next.visible if next else true)
			app.objective.visible=false
		if heading:heading.text="任務與指南  "+("▼" if app.objective.visible else "▸")
		if next and next.visible!=app.objective.visible:next.visible=app.objective.visible
		tracker.custom_minimum_size.x=150
		tracker.size.x=150
		tracker.size.y=0
	elif was:
		tracker.set_meta("tea_compact",false)
		app.objective.visible=bool(tracker.get_meta("tea_saved_objective",true))
		if next:next.visible=bool(tracker.get_meta("tea_saved_next",true))
		tracker.custom_minimum_size.x=226
		tracker.size=Vector2(226,0)

static func mine_note_active(app) -> bool:
	return is_instance_valid(app.preview_tracker) and bool(app.preview_tracker.get_meta("mine_note",false))

## 礦區（mine_*）：礦務隨身記收成圖示。進礦場預設收起，玩家的展開／收起選擇
## 在各礦層與重複的 HUD 更新之間保留；離開礦區才還原成平常的追蹤卡。
static func sync_mine_note(app) -> void:
	var tracker:=app.preview_tracker as Control
	var icon:=app.hud.get_node_or_null("MineNoteIcon") as Button
	if not is_instance_valid(tracker) or icon==null or not is_instance_valid(app.objective):return
	var mine:=str(app.session.snapshot.get("region_id","home")).begins_with("mine_")
	var was:=bool(tracker.get_meta("mine_note",false))
	if mine and not was:
		tracker.set_meta("mine_note",true)
		tracker.set_meta("mine_open",false)
		tracker.set_meta("mine_saved_objective",app.objective.visible)
		app.objective.visible=true # 展開後要看得到體力、路線與勘查文字
		set_note_visible(app,tracker,false)
		set_note_visible(app,icon,true)
		app._layout_preview.call_deferred()
	elif was and not mine:
		tracker.set_meta("mine_note",false)
		tracker.remove_meta("mine_open")
		app.objective.visible=bool(tracker.get_meta("mine_saved_objective",true))
		set_note_visible(app,tracker,true)
		tracker.size.y=0
		set_note_visible(app,icon,false)
		app._layout_preview.call_deferred()
		return
	if not mine:return
	var person:Dictionary=app.session.snapshot.get("players",{}).get(app.session.own_id,{})
	var energy:=World.MEAL_BUFF.whole_points(person)
	var warning:=icon.get_node("LowMineEnergy") as Label
	warning.text=str(energy)
	warning.visible=not person.is_empty() and energy<=MINE_ENERGY_WARNING
	icon.tooltip_text="礦務隨身記 · 體力 %d／100\n%s"%[energy,"體力偏低，回休息站喝水" if warning.visible else "點一下展開或收起"]
	var open:=bool(tracker.get_meta("mine_open",false))
	set_note_visible(app,icon,true)
	var shown:bool=app.inventory_hidden_controls.has(tracker) if hud_suppressed(app) else tracker.visible
	if shown!=open:
		set_note_visible(app,tracker,open)
		tracker.size.y=0

static func hud_suppressed(app) -> bool:
	return is_instance_valid(app.modal) and not app.inventory_hidden_controls.is_empty()

## 背包等視窗開著時，main 會把可見的 HUD 暫時藏起來並記在 inventory_hidden_controls，
## 關閉時再還原。這段期間筆記只更新「關閉後要顯示什麼」：把控制項放進或移出還原清單，
## 實際保持隱藏，視窗關閉後才套用玩家的展開／收起狀態。
static func set_note_visible(app,control:Control,want:bool) -> void:
	if hud_suppressed(app):
		control.hide()
		var listed:int=app.inventory_hidden_controls.find(control)
		if want and listed<0:app.inventory_hidden_controls.append(control)
		elif not want and listed>=0:app.inventory_hidden_controls.remove_at(listed)
		return
	control.visible=want

static func toggle_mine_note(app) -> void:
	var tracker:=app.preview_tracker as Control
	if not mine_note_active(app):return
	var open:=not bool(tracker.get_meta("mine_open",false))
	tracker.set_meta("mine_open",open)
	if open:app.objective.visible=true
	sync_mine_note(app)
	tracker.size.y=0
	app._layout_preview.call_deferred()

static func layout_hud(app,bounds:Vector2) -> void:
	var location:Control=app.hud.get_node("LocationBadge")
	app.preview_tracker.position.y=maxf(92.0,location.position.y+location.get_combined_minimum_size().y+6.0)
	var mine_icon:=app.hud.get_node_or_null("MineNoteIcon") as Control
	if mine_icon and mine_note_active(app):
		mine_icon.position=Vector2(app.preview_tracker.position.x,app.preview_tracker.position.y)
		mine_icon.size=Vector2(48,48)
		app.preview_tracker.position.y+=54.0
	var toolbar_width:=toolbar_width_for(app.preview_toolbar)
	app.preview_toolbar.size=Vector2(toolbar_width,92)
	app.preview_toolbar.position=Vector2(maxf(0.0,floor((bounds.x-toolbar_width)/2)),bounds.y-106)
	var calendar:Control=app.preview_top
	calendar.size=calendar.get_combined_minimum_size().max(Vector2(222,100))
	var calendar_inset:=16.0 if bounds.x<=1024.0 else 22.0
	calendar.position=Vector2(bounds.x-calendar.size.x-calendar_inset,18.0)
	# Focus tip sits left of the calendar badge (never over toolbar/shortcuts) and is hidden unless focused.
	var tip:=app.hud.get_node_or_null("WeatherForecastTip") as Control
	if tip:
		tip.position=Vector2(maxf(8.0,calendar.position.x-8.0-FORECAST_TIP_WIDTH),18.0)
		tip.size=Vector2(FORECAST_TIP_WIDTH,0)
	app.selected_label.position=Vector2((bounds.x-740)/2,bounds.y-142)
	app.selected_label.size=Vector2(740,32)
	var shortcuts:HBoxContainer=app.hud.get_node("LifeShortcuts")
	var toolbar_right:float=app.preview_toolbar.position.x+toolbar_width
	var gaps:int=shortcuts.get_theme_constant("separation")*(shortcuts.get_child_count()-1)
	var standard_width:int=SHORTCUT_WIDTH*shortcuts.get_child_count()+gaps
	var compact:bool=bounds.x-20.0-standard_width<toolbar_right+6.0
	var button_width:=SHORTCUT_COMPACT_WIDTH if compact else SHORTCUT_WIDTH
	for shortcut:Button in shortcuts.get_children():
		if shortcut.custom_minimum_size.x==button_width:continue
		shortcut.custom_minimum_size.x=button_width
		var art:=shortcut.get_node("ToolArt") as TextureRect
		art.position.x=floorf((button_width-art.size.x)/2)
		fit_key_badge(shortcut.get_node("KeyBadge"),button_width-8)
	var shortcut_size:=shortcuts.get_combined_minimum_size()
	shortcuts.size=shortcut_size
	var right_x:=bounds.x-shortcut_size.x-(12.0 if compact else 20.0)
	shortcuts.position=Vector2(right_x,bounds.y-shortcut_size.y-16.0)
	if right_x<toolbar_right+6.0:
		shortcuts.position.y=maxf(calendar.position.y+calendar.size.y+8.0,
			app.selected_label.position.y-shortcut_size.y-8.0)

static func region_display_name(region:String) -> String:
	if region.begins_with("mine_"):return "金瓜石合作礦場・地下第 %d 層"%int(region.trim_prefix("mine_"))
	var qualified:Dictionary={"lanyang":"宜蘭・蘭陽試作田","jinguashi":"新北・金瓜石山城"}
	var stations:Dictionary=preload("res://scripts/transit_art.gd").NAMES
	return str(qualified.get(region,stations.get(region,World.REGIONS.label(region))))

static func refresh_location(app,s:Dictionary,p:Dictionary) -> void:
	var region_title:Label=app.hud.find_child("RegionTitle",true,false) as Label
	if not region_title:return
	var region:=str(s.get("region_id","home"))
	var title:=region_display_name(region)
	if region==World.WARM_SPRINGS.REGION and World.WARM_SPRINGS.in_inn(p):
		title="暖泉旅舍"
	elif region==World.REGIONS.HOME and not p.is_empty():
		var position:=Vector2(float(p.x),float(p.y))
		if World.WANGAN_COAST.star_shore(Vector2i(position.floor())):
			title="望安・星砂海岸"
		elif World.WANGAN_COAST.VISITOR_AREA.has_point(position):
			title="望安・南岸"
	region_title.text=title

static func refresh_hud(app,s:Dictionary,p:Dictionary) -> void:
	var depth_region:=str(s.get("region_id","home"))
	var station_name:String=preload("res://scripts/transit_art.gd").NAMES.get(depth_region,"")
	var tracker_heading:Button=app.hud.find_child("TrackerHeading",true,false) as Button
	var tracker_next:Button=app.hud.find_child("TrackerNext",true,false) as Button
	if tracker_heading:tracker_heading.text="礦務隨身記  ▼" if depth_region.begins_with("mine_") else "渡口的一封信  ▼"
	if tracker_next:tracker_next.text="查看出入口  →" if depth_region.begins_with("mine_") else "看看下一步  →"
	if not station_name.is_empty():
		if tracker_heading:tracker_heading.text="北部旅程  ▼"
		if tracker_next:tracker_next.text="查看轉乘  →"
	if depth_region=="jinguashi":
		if tracker_heading:tracker_heading.text="波波的礦樣桌  ▼"
		if tracker_next:tracker_next.text="翻開波波的故事  →"
	app.coin_label.text=str(p.get("coins",0))
	var minutes:=int(s.get("time",0))%1440
	var weather:Dictionary=WeatherArt.current(s)
	var weather_text:String=WeatherArt.label(weather)
	var season := World.WEATHER.season_label(float(s.get("time",0)))
	app.status_label.text="%s · 第 %d 日 · %s\n%02d:%02d  ·  %d / %d 人"%[season,1+int(s.get("time",0))/1440,weather_text,minutes/60,minutes%60,int(s.get("room_population",s.players.size())),int(s.get("room_capacity",4))]
	var weather_icon:TextureRect=app.hud.find_child("WeatherIcon",true,false) as TextureRect
	if weather_icon:
		var wanted:String=WeatherArt.icon_id(weather)
		if str(weather_icon.get_meta("weather_icon_id",""))!=wanted:
			weather_icon.texture=icon(wanted)
			weather_icon.set_meta("weather_icon_id",wanted)
	refresh_forecast(app,s)
	var step:Dictionary=World.CHAPTER_ONE.next_step(s)
	var short:Dictionary={"grow":"種下作物，收成第一批菜", "ship":"把收成放進出貨箱", "works":"修好公告板，開放生活訂單", "water":"接起水桶、管線和灑水器", "meal":"準備湯和麵包，一起開飯", "complete":"渡口開飯了 · 下一站的信"}
	app.objective.text="讓渡口重新開飯\n"+str(short[step.id])
	# 望安開場：自己的第一株作物依序 find → till → sow → water → wait → harvest → ship。
	var first_crop:Dictionary=World.CHAPTER_ONE.first_crop_step(s,app.session.own_id)
	if not first_crop.is_empty():app.objective.text=preload("res://scripts/wangan_opening_ui.gd").tracker_text(app,first_crop)
	elif step.id=="grow":app.objective.text=preload("res://scripts/wangan_opening.gd").heading(s)+"\n開田、播種、澆水，再採收"
	elif step.id=="ship":app.objective.text+="\n✓ 第一批收成準備好了"
	if depth_region=="home" and step.id=="works" and first_crop.is_empty():
		var cost:=World.CHAPTER_ONE.BOARD_COST
		app.objective.text="修好渡口公告板\n到公告板按 %s 捐材料\n木材 %d/%d · 石材 %d/%d"%[
			app.binding_label("interact"),s.donations.wood,cost.wood,s.donations.stone,cost.stone]
	if depth_region=="home" and step.id=="water" and first_crop.is_empty():
		if World.CHAPTER_ONE.needs_starter_kit(s,app.session.own_id):
			var cost:=World.CHAPTER_ONE.STARTER_COST
			app.objective.text="讓農田自己喝水\n找阿榆按 %s 換入門設備\n木材 %d · 石材 %d · 纖維 %d"%[
				app.binding_label("interact"),cost.wood,cost.stone,cost.fiber]
		else:
			app.objective.text="讓農田自己喝水\n用水管接起水桶和灑水器\n補滿水桶，再啟用灑水器"
	if step.id=="meal":
		if depth_region=="home" and first_crop.is_empty() and World.CHAPTER_ONE.can_serve_picnic(s,app.session.own_id):
			app.objective.text="帶料理去野餐\n到公告板按 %s 交料理"%app.binding_label("interact")
		elif depth_region=="home" and first_crop.is_empty():
			var cooking_hint:=picnic_cooking_hint(s,app.session.own_id)
			if not cooking_hint.is_empty():app.objective.text="準備渡口野餐\n"+cooking_hint
		app.objective.text+="\n蘿蔔湯 %d/2 · 麵包 %d/1"%[s.picnic_materials.soup,s.picnic_materials.bread]
	if s.get("festival",{}).get("active",false):app.objective.text="風鈴接力 %d / 12\n靠近金色風鈴按 %s"%[int(s.festival.collected),app.binding_label("interact")]
	if str(s.get("region_id","home"))=="lanyang":
		app.objective.text="星禾的水圳手記\n"+str(World.LANYANG_LIFE.next_step(s).get("action","找橋邊的星禾聊聊"))+"\nM 查看標記與回程"
		# 第 40 章蘭陽回訪：配水紀念牌設好之後，田區追蹤改看旱日分流（蘭陽沒有其他活動追蹤）。
		var revisit_line:String=preload("res://scripts/lanyang_revisit_ui.gd").tracker_text(s)
		if not revisit_line.is_empty():app.objective.text=revisit_line+"\n%s 查看標記與回程"%app.binding_label("map")
	if depth_region=="jinguashi":
		var stage:=clampi(int(p.get("stories",{}).get("bobo",0)),0,4)
		var sites:=World.Village.Workshop.sites(s)
		var workshop_hint:="到候車路口西側找波波。" if sites.npc.x<11 else "到候車亭東邊找波波。"
		var next:Array[String]=[workshop_hint,"帶三份含金原礦去整理。","把礦料寄回渡口。","擺好展示架，帶一份烤薯。","礦樣故事已完成，可翻閱回憶。"]
		if stage==1:
			var sorting:Dictionary=s.get("bobo_workshop",{})
			var job:Dictionary=sorting.get("own_job",{})
			if sorting.get("own_done",false):next[1]="礦樣整理好了，回波波身邊聊聊。"
			elif not job.is_empty():next[1]="回整理桌領取收藏樣本。" if int(job.get("step",0))==3 else "回整理桌繼續第 %d 份礦樣。"%(int(job.get("step",0))+1)
		elif stage==2 and s.get("mine_freight",{}).get("own_job",{}).get("status","")=="delivered":next[2]="貨物平安回家了，告訴波波吧。"
		app.objective.text=next[stage]+"\n%s 查看礦點與回程"%app.binding_label("map")
		# 第 40 章金瓜石回訪：升降台修好、自己也整理過礦樣之後，追蹤卡改看礦料調度（訂單進度）。
		var jg_line:String=preload("res://scripts/jinguashi_revisit_ui.gd").tracker_text(s)
		if not jg_line.is_empty():
			app.objective.text=jg_line+"\n%s 查看礦點與回程"%app.binding_label("map")
			if tracker_heading:tracker_heading.text="金瓜石回訪  ▼"
			if tracker_next:tracker_next.text="打開礦料調度  →"
	elif not station_name.is_empty():
		var onward:String={"toucheng":"往東北走到頭城月台。","ruifang":"穿過廣場，往東南找公車站。","jiufen":"沿石板街往東北走到接駁站。"}.get(depth_region,"")
		var resident_hint:String={"toucheng":"月台南側，找阿程聊聊。","ruifang":"廣場中間，穗禾在修長凳。","jiufen":"燈籠街旁，春姨等你歇腳。"}.get(depth_region,"")
		if depth_region=="ruifang" and s.get("station_life",{}).get("repairs",{}).get("ruifang",false):resident_hint="穗禾替大家留了候車座位。"
		app.objective.text="%s\n%s\n%s 交談／搭車 · %s 地圖"%[resident_hint,onward,app.binding_label("interact"),app.binding_label("map")]
	if depth_region.begins_with("mine_"):
		app.objective.text="礦內體力  %d\n休息站補水\n礦務站整備下層\n%s 查看路線"%[World.MEAL_BUFF.whole_points(p),app.binding_label("map")]
	elif depth_region=="home" and step.id=="complete" and not s.get("festival",{}).get("active",false):
		app.objective.text="田區的邀請\n在渡口搭交通船前往蘭陽\n%s 查看台灣旅圖"%app.binding_label("map")
		# 第 40 章：旱日分流完成、自己還沒有分流閘時，提示回工作台製作（活動追蹤之後會蓋過）。
		var gate_hint:String=preload("res://scripts/lanyang_revisit_ui.gd").home_hint(s,app.session.own_id)
		if not gate_hint.is_empty():app.objective.text=gate_hint
		else:
			# 第 40 章地方記憶展：有自己還沒看的展品時（最低優先，任何其他追蹤都會蓋過）。
			var exhibit_hint:String=preload("res://scripts/memory_exhibit_ui.gd").tracker_text(s)
			if not exhibit_hint.is_empty():app.objective.text=exhibit_hint
	if depth_region=="home" and s.get("festival",{}).get("active",false):
		if tracker_heading:tracker_heading.text="風鈴接力  ▼"
		if tracker_next:tracker_next.text="查看風鈴接力  →"
	if depth_region=="tianwei":
		var flower_step:Dictionary=preload("res://scripts/flower_nursery_ui.gd").next_step(s,app.session.own_id)
		if tracker_heading:tracker_heading.text="花圃手記  ▼"
		if tracker_next:tracker_next.text="翻開花圃手帳  →"
		app.objective.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		app.objective.text=str(flower_step.get("title","田尾合作花圃"))+"\n"+str(flower_step.get("detail","和花農聊聊，認識花圃。"))
	if depth_region=="beimen":
		# 北門鹽田：手記卡片顯示自己的下一步（只讀快照中的 salt_pan.own.guidance）。
		var salt_step:Dictionary=preload("res://scripts/salt_pan_ui.gd").next_step(s)
		var salt_titles:={"intro":"認識阿曬","gates":"修好三道閘門","first_salt":"第一次曬鹽","claim":"認領鹽田區","wheel":"裝上鹽田水車","rake":"做一座收鹽台","automate":"讓鹽自己進箱子","order":"帶鹽回渡口","report":"回報阿曬","complete":"北門這一段完成了"}
		if tracker_heading:tracker_heading.text="鹽田手記  ▼"
		if tracker_next:tracker_next.text="翻開鹽田手帳  →"
		app.objective.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		app.objective.text=str(salt_titles.get(str(salt_step.get("phase","")),"北門鹽風合作鹽田"))+"
"+str(salt_step.get("text","和阿曬聊聊，認識合作鹽田。"))
		# 第 40 章臺南北門回訪：鹽田章節完成、自己收過鹽，而且鹽籃批次有現在就能做的一步時，
		# 追蹤卡改看批次進度（章節還在進行時保留章節的下一步）。
		var basket_line:String=preload("res://scripts/salt_revisit_ui.gd").tracker_text(s,str(app.session.own_id))
		if not basket_line.is_empty():
			app.objective.text=basket_line
			if tracker_heading:tracker_heading.text="臺南北門回訪  ▼"
			if tracker_next:tracker_next.text="打開鹽籃批次  →"
	var forest_skin:bool=app.sound.forest_tools and World.gathering_level(p)==10
	var inventory:Dictionary=p.get("inventory",{})
	for action:String in ["hoe","seed","water","harvest","axe","pick"]:
		var index:=TOOL_IDS.find(action)
		if index>=app.tool_buttons.size():continue
		var button:Button=app.tool_buttons[index]
		refresh_tool_appearance(app,button,action,TOOL_NAMES[index],inventory,forest_skin and FOREST_TOOLS.has(action))
	var rod:=app.preview_toolbar.find_child("FishingSlot",true,false) as Button
	if rod:
		rod.set_pressed_no_signal(app.selected=="fish")
		refresh_tool_appearance(app,rod,"fish","釣竿",inventory,false)
	var needs_layout := guided_toolbar(app,first_crop)
	for tool in [["TillerSlot", "tiller", "till_area"], ["SeederSlot", "seeder", "seed_area"], ["HarvesterSlot", "harvester", "harvest_area"]]:
		var slot := app.preview_toolbar.find_child(tool[0],true,false) as Button
		if slot == null:continue
		var owned: bool = int(p.get("inventory",{}).get(tool[1],0)) > 0 or (tool[1]==World.PUBLIC_TILLER.ITEM and World.PUBLIC_TILLER.borrowed(p))
		needs_layout = needs_layout or slot.visible != owned
		slot.visible = owned
		slot.set_pressed_no_signal(app.selected == tool[2] and owned)
	if needs_layout:
		layout_hud(app,app.get_viewport().get_visible_rect().size)

static func refresh_tool_appearance(app,button:Button,action:String,base_name:String,inventory:Dictionary,use_forest:bool)->void:
	var upgrade:=World.gathering_tool_upgrade(action,inventory)
	var appearance:="forest" if use_forest else (upgrade if not upgrade.is_empty() else action)
	var title:String=World.NAMES[upgrade] if not upgrade.is_empty() else base_name
	if button.get_meta("tool_appearance",action)==appearance and button.get_meta("binding_title")==title:return
	var art:=button.get_node_or_null("ToolArt") as TextureRect
	if art:art.texture=FOREST_TOOLS[action] if use_forest else (Items.icon(upgrade) if not upgrade.is_empty() else icon(action))
	button.set_meta("tool_appearance",appearance)
	button.set_meta("binding_title",title)
	button.tooltip_text="%s [%s]"%[title,app.binding_label(action)]

## Read-only: updates the badge's tomorrow line, hover tooltip and focus tip
## from the snapshot clock. Never writes snapshot/session state.
static func refresh_forecast(app,s:Dictionary) -> void:
	if s.is_empty():return
	var badge:=app.hud.find_child("WeatherBadge",true,false) as Control
	var line:=app.hud.find_child("WeatherTomorrow",true,false) as Label
	var tip_text:=app.hud.find_child("WeatherForecastTipText",true,false) as Label
	var line_text:=Forecast.tomorrow_line(s)
	var details:=Forecast.tooltip(s)
	if line and line.text!=line_text:line.text=line_text
	var hover:=details+"\n\n"+FORECAST_HOVER_HINT
	var focused:=details+"\n\n"+FORECAST_TIP_HINT
	if badge and badge.tooltip_text!=hover:badge.tooltip_text=hover
	if tip_text and tip_text.text!=focused:tip_text.text=focused
	sync_forecast_tip(app)

## The focus tip is visible only while the badge itself holds keyboard focus
## and no modal is open, so it never covers modals or lingers after focus moves.
static func sync_forecast_tip(app) -> void:
	var badge:=app.hud.find_child("WeatherBadge",true,false) as Control
	var tip:=app.hud.get_node_or_null("WeatherForecastTip") as Control
	if tip==null:return
	var show:=badge!=null and badge.is_visible_in_tree() and badge.has_focus() and app.modal==null
	if tip.visible!=show:
		tip.visible=show
		if show:tip.size=Vector2(FORECAST_TIP_WIDTH,0)

## Esc / world click while the forecast badge is focused just drops focus
## (closing the tip). Returns true when it consumed the dismissal.
static func release_forecast_focus(app) -> bool:
	if not is_instance_valid(app.hud):return false
	var badge:Control=app.hud.find_child("WeatherBadge",true,false) as Control
	if badge==null or not badge.has_focus():return false
	badge.release_focus()
	sync_forecast_tip(app)
	return true

## Shift+Tab (ui_focus_prev) on the world HUD: focus the forecast badge when no
## other control holds focus, or drop it again. Returns false (event left for
## normal GUI focus navigation) when another control is focused or a modal is up.
static func toggle_forecast_focus(app) -> bool:
	if not is_instance_valid(app.hud) or app.modal!=null:return false
	var badge:Control=app.hud.find_child("WeatherBadge",true,false) as Control
	if badge==null or not badge.is_visible_in_tree():return false
	if badge.has_focus():return release_forecast_focus(app)
	if badge.get_viewport().gui_get_focus_owner()!=null:return false
	badge.grab_focus()
	sync_forecast_tip(app)
	return badge.has_focus()

const SHORTCUT_DIRECTIONS:={JOY_BUTTON_DPAD_UP:"ShortcutMap",JOY_BUTTON_DPAD_LEFT:"ShortcutTravel",
	JOY_BUTTON_DPAD_RIGHT:"ShortcutEmotes",JOY_BUTTON_DPAD_DOWN:"ShortcutSignal"}

static func shortcut_direction(app,index:int) -> bool:
	if not SHORTCUT_DIRECTIONS.has(index):return false
	var choice:=app.modal.find_child(SHORTCUT_DIRECTIONS[index],true,false) as Button
	if choice!=null:choice.grab_focus()
	return true

static func controller_shortcuts(app) -> void:
	var body:VBoxContainer=app._open_modal("島上快捷選單")
	app.modal.set_meta("life_modal_layout","controller_shortcuts")
	app.modal.set_meta("controller_shortcuts",true)
	for options:Array in [[ ["ShortcutMap","↑  周邊地圖","map",app._map_menu] ],
		[ ["ShortcutTravel","←  台灣旅圖","sign",func():app._travel_menu()], ["ShortcutEmotes","島民招呼  →","bell",app._emote_menu] ],
		[ ["ShortcutSignal","↓  地圖標記","sign",app._map_signal_menu.bind(app._controller_target())] ]]:
		var row:=HBoxContainer.new()
		row.alignment=BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation",12)
		body.add_child(row)
		for option:Array in options:
			var choice:Button=app.button(option[1],option[3])
			choice.name=option[0]
			choice.icon=icon(option[2])
			choice.add_theme_constant_override("icon_max_width",24)
			choice.custom_minimum_size=Vector2(176,44)
			row.add_child(choice)
	if is_instance_valid(app.modal_feedback):app.modal_feedback.text="十字鍵選擇 · 手把 A 開啟 · B 返回"
	app._layout_preview.call_deferred()

static func pause(app) -> void:
	var content:VBoxContainer=app._open_modal("歇一會兒")
	app.modal.set_meta("life_modal_layout","pause_drawer")
	var intro:=text(app,"今天也在島上留下了一點回憶。",15)
	content.add_child(intro)
	var grid:=GridContainer.new()
	grid.columns=3
	grid.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation",12)
	grid.add_theme_constant_override("v_separation",12)
	content.add_child(grid)
	var entries=[ ["map","島嶼地圖",app.binding_label("map"),app._map_menu], ["journal","島民手帳",app.binding_label("journal"),app._journal], ["trophy","生活收藏",app.binding_label("collection"),app._collection_menu], ["bell","風鈴接力",app.binding_label("festival"),app._festival_menu], ["seed","作物種子",app.binding_label("seeds"),app._seed_menu], ["settings","舒適設定","",app._settings_menu], ["settings","鍵盤設定","",app._bindings_menu], ["fish","拿起釣竿",app.binding_label("fish"),func():app._close_modal();app._select_tool("fish")], ["letter","共同工程","",app._board], ["letter","島民交換","",app._trade_menu], ["sign","操作指南","",app._help] ]
	if not app.island_passport.is_empty():entries.append(["letter","島嶼通行簿","",app._passport_menu])
	entries.append(["bell","島民招呼","",app._emote_menu])
	if app.session.snapshot.get("players",{}).get(app.session.own_id,{}).has(World.Rabbit.FIELD):
		entries.append(["home","棉球兔","",app._rabbit_menu])
	if app.session.snapshot.get("players",{}).get(app.session.own_id,{}).has(World.Cat.FIELD):
		entries.append(["home","圍巾貓","",app._cat_menu])
	if app.session.snapshot.get("players",{}).get(app.session.own_id,{}).has(World.Dog.FIELD):
		entries.append(["home","小柴犬","",app._dog_menu])
	if app.session.snapshot.get("players",{}).get(app.session.own_id,{}).has(World.Fox.FIELD):
		entries.append(["home","葉耳狐","",app._fox_menu])
	if app.session.solo_rest_enabled or app.session.snapshot.has("night_vote"):
		entries.append(["calendar","休息到清晨" if app.session.solo_rest_enabled else "夜間投票","",app._night_rest_menu])
	var shortcuts:Array[Button]=[]
	for entry in entries:
		var cell:=VBoxContainer.new()
		cell.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		cell.alignment=BoxContainer.ALIGNMENT_CENTER
		grid.add_child(cell)
		var b:=icon_button(app,entry[0],entry[1],"—" if entry[2]=="未設定" else entry[2],entry[3],72)
		if entry[1]=="島民交換":b.name="PauseTrade"
		if entry[1]=="舒適設定":b.name="PauseComfort"
		if entry[1]=="操作指南":b.name="PauseHelp"
		if entry[1] in ["休息到清晨","夜間投票"]:b.name="PauseNightRest"
		b.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
		cell.add_child(b)
		shortcuts.append(b)
		var caption:=text(app,entry[1],15)
		caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(caption)
	for index in shortcuts.size():
		var button:=shortcuts[index]
		if index>=grid.columns:button.focus_neighbor_top=button.get_path_to(shortcuts[index-grid.columns])
		if index+grid.columns<shortcuts.size():button.focus_neighbor_bottom=button.get_path_to(shortcuts[index+grid.columns])
		if index%grid.columns>0:button.focus_neighbor_left=button.get_path_to(shortcuts[index-1])
		if index%grid.columns<grid.columns-1 and index+1<shortcuts.size():
			button.focus_neighbor_right=button.get_path_to(shortcuts[index+1])
	var footer:=HBoxContainer.new()
	footer.add_theme_constant_override("separation",6)
	var shell:VBoxContainer=content.get_parent().get_parent()
	shell.add_child(footer)
	shell.move_child(footer,shell.get_child_count()-3)
	var rescue:Button=app.button(app._rescue_label(),func():app.session.perform("rescue",Vector2i.ZERO);app._close_modal())
	rescue.name="PauseRescue"
	rescue.flat=true
	rescue.add_theme_font_size_override("font_size",15)
	rescue.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	footer.add_child(rescue)
	var save:Button=app.button("儲存今天 · 離開小島",app._quit)
	save.add_theme_font_size_override("font_size",15)
	save.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	footer.add_child(save)
	app.modal_feedback.text="Esc／手把 B 返回 · 單機島已暫停" if app.session.local_paused else "Esc 返回 · 多人世界仍繼續運作"
	app._layout_preview()

static func reveal(app,control:Control) -> void:
	if app.sound and not app.sound.reduced_motion:
		control.modulate.a=0.0
		var tween:=control.create_tween()
		tween.tween_property(control,"modulate:a",1.0,0.16).set_trans(Tween.TRANS_SINE)

static func help_card(app,parent:Container,symbol:String,title:String,guide:String) -> PanelContainer:
	var card:=PanelContainer.new()
	card.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	card.focus_mode=Control.FOCUS_ALL
	card.set("accessibility_name",title)
	card.add_theme_stylebox_override("panel",Art.compact_style())
	card.focus_entered.connect(card.queue_redraw)
	card.focus_exited.connect(card.queue_redraw)
	card.draw.connect(func():
		if card.has_focus():card.draw_rect(Rect2(Vector2.ONE*2.0,card.size-Vector2.ONE*4.0),Color("527248"),false,3.0)
	)
	parent.add_child(card)
	var body:=VBoxContainer.new()
	card.add_child(body)
	var heading:=HBoxContainer.new()
	body.add_child(heading)
	heading.add_child(picture(icon(symbol),40))
	heading.add_child(app.label(title,18))
	var description:Label=app.label(guide,15)
	description.custom_minimum_size.x=290
	body.add_child(description)
	return card

static func help(app) -> void:
	var content:VBoxContainer=app._open_modal("第一天的口袋指南")
	app.modal.set_meta("pocket_guide",true)
	var scroll:=content.get_parent() as ScrollContainer
	app.modal_feedback.add_theme_font_size_override("font_size",15)
	app.modal_feedback.text="↑ ↓ 閱讀 · Esc／手把 B 返回"
	var grid:=GridContainer.new()
	grid.columns=2
	grid.add_theme_constant_override("h_separation",16)
	grid.add_theme_constant_override("v_separation",12)
	content.add_child(grid)
	var lessons=[
		["hoe","種下第一份收成","%s 鋤田 → %s 種子 → %s 澆水 → %s 採收。\n%s 換種子，靠近種子攤按 %s 買賣。"%[app.binding_label("hoe"),app.binding_label("seed"),app.binding_label("water"),app.binding_label("harvest"),app.binding_label("seeds"),app.binding_label("interact")]],
		["build","慢慢蓋起自己的家","%s 選家具，點附近空地放置。\n%s 搬家具，按住 %s 拖曳鋪地板、步道、屋頂。"%[app.binding_label("build_menu"),app.binding_label("move_object"),app.binding_label("area_modifier")]],
		["axe","口袋裡的島嶼材料","斧頭砍樹三下，十字鎬敲石兩下。瞄準同一格，按住滑鼠左鍵或手把 X 就能連續採集。\n{plant_tree} 種樹苗，約三分鐘長成。砍樹會取得樹苗。"],
		["letter","和島民一起生活","公告板按 %s 捐材料修橋，%s 看居民故事。\n放箱子共享材料，小石灶做料理和飼料。"%[app.binding_label("interact"),app.binding_label("journal")]],
		["fish","留一點時間給河岸","%s 選釣竿，點水面拋竿，咬鉤按 %s。\n靠近糯米雞按 %s 照料，%s 看生活收藏。"%[app.binding_label("fish"),app.binding_label("fish_catch"),app.binding_label("interact"),app.binding_label("collection")]],
		["settings","照自己的步調遊玩","上 %s、左 %s、下 %s、右 %s，操作範圍約三格。\n%s 切近遠景，Esc 開選單。\n%s 開招呼與標記。手把按下左搖桿再按下方向鍵可選標記。"%[app.binding_label("move_up"),app.binding_label("move_left"),app.binding_label("move_down"),app.binding_label("move_right"),app.binding_label("zoom"),app.binding_label("social")]]]
	var cards:Array[PanelContainer]=[]
	for lesson in lessons:cards.append(help_card(app,grid,lesson[0],lesson[1],lesson[2]))
	var workshop_heading:=HBoxContainer.new()
	content.add_child(workshop_heading)
	var workshop_title:Label=app.label("做大一點的工坊",20)
	workshop_title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	workshop_heading.add_child(workshop_title)
	var diagrams:Button=app.button("看工坊圖解",app._workshop_guide)
	diagrams.name="HelpWorkshopGuide"
	workshop_heading.add_child(diagrams)
	cards.append(help_card(app,content,"water","灌溉與水管","在工作台按 {interact} 做強化石鎬。採銅做銅接頭，就能製作灑水器套件。按 {build_menu} 選灑水器，靠近按 {interact} 補水。\n成熟樹提供樹脂，鋸木台做木板、炭窯做木炭。用工作台製作桶、泵與銅管，按 {build} 放置。將水泵放在離河水兩格內，用同一主人的管線接儲水桶，再接灑水器。銅管可走過，斷管後桶裡的水仍可用。"))
	cards.append(help_card(app,content,"hoe","手推農機","{till_area} 拿耕田機。點身邊空地，成功開田才消耗 1 份木炭。\n{seeds} 換種子，{seed_area} 拿播種機，點自己的空農田播種。\n{harvest_area} 拿收割機，點自家成熟作物。成功收割耗 1 份木炭。\n三種農機一次最多處理 9 格。"))
	cards.append(help_card(app,content,"axe","林務與輸送帶","在工作台製作林務工作站，按 {build} 放置，靠近按 {interact} 裝入木炭與樹苗再啟用。它每 12 秒巡查一格，只管理四個方向各兩格處的自種樹，成熟後採伐並補植。木材、纖維或樹脂存滿時會暫停。\n靠近輸送帶按 {interact} 選方向和物品再啟用。木材能送進鋸木台或炭窯，木炭能送進林務工作站。"))
	cards.append(help_card(app,content,"build","拆除與存檔","{remove} 拆除會退回材料，也能收回自己的樹苗或空農田。蓋屋頂前先鋪地板，進屋後屋頂會淡化。成功操作後自動保存，無人在線時作物暫停生長。"))
	for index in cards.size():
		cards[index].name="GuideCard%d"%index
	for index in cards.size():
		var card:=cards[index]
		card.focus_entered.connect(func():scroll_to_help_card.call_deferred(scroll,card))
		card.focus_neighbor_top=card.get_path_to(cards[maxi(0,index-1)])
		card.focus_neighbor_bottom=card.get_path_to(cards[mini(index+1,cards.size()-1)])
		card.focus_neighbor_left=card.get_path_to(cards[index-1]) if index<lessons.size() and index%2==1 else NodePath(".")
		card.focus_neighbor_right=card.get_path_to(cards[index+1]) if index<lessons.size() and index%2==0 else NodePath(".")
	var before_diagrams:=cards[lessons.size()-1]
	var after_diagrams:=cards[lessons.size()]
	before_diagrams.focus_neighbor_bottom=before_diagrams.get_path_to(diagrams)
	after_diagrams.focus_neighbor_top=after_diagrams.get_path_to(diagrams)
	diagrams.focus_neighbor_top=diagrams.get_path_to(before_diagrams)
	diagrams.focus_neighbor_bottom=diagrams.get_path_to(after_diagrams)
	diagrams.focus_neighbor_left=NodePath(".")
	diagrams.focus_neighbor_right=NodePath(".")
	diagrams.focus_entered.connect(func():scroll_to_help_card.call_deferred(scroll,diagrams))

static func scroll_to_help_card(scroll:ScrollContainer,card:Control) -> void:
	if not is_instance_valid(scroll) or not is_instance_valid(card) or not card.has_focus():return
	var bounds:=scroll.get_global_rect()
	var target:=card.get_global_rect()
	if target.position.y<bounds.position.y or target.end.y>bounds.end.y:
		scroll.scroll_vertical+=roundi(target.position.y-bounds.position.y)

static func audio_settings(app,parent:Container) -> Dictionary:
	var grid:=GridContainer.new()
	grid.columns=2
	grid.add_theme_constant_override("h_separation",16)
	parent.add_child(grid)
	var sliders:Dictionary={}
	for entry:Array in [["master_volume","主音量","MasterVolume"],["music_volume","背景音樂","MusicVolume"],
		["ambience_volume","環境聲","AmbienceVolume"],["volume","動作音","ActionVolume"],["interface_volume","介面提示","InterfaceVolume"]]:
		var key:String=entry[0]
		var caption:String=entry[1]
		var column:=VBoxContainer.new()
		column.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		grid.add_child(column)
		var heading:=text(app,"%s %d%%"%[caption,roundi(float(app.sound.get(key))*100.0)],16)
		column.add_child(heading)
		var slider:=HSlider.new()
		slider.name=entry[2]
		slider.set_meta("comfort_volume",true)
		slider.max_value=100
		slider.step=5
		slider.value=app.sound.get(key)*100.0
		slider.custom_minimum_size.y=28
		slider.tooltip_text=caption
		slider.value_changed.connect(func(value:float):heading.text="%s %d%%"%[caption,roundi(value)])
		column.add_child(slider)
		sliders[key]=slider
	parent.add_child(text(app,"0% 為靜音",14))
	var captions:=CheckBox.new()
	captions.name="ActivityCaptions"
	captions.text="顯示活動字幕"
	captions.button_pressed=app.sound.activity_captions
	captions.tooltip_text="在畫面上提示咬鉤、收成與附近自己的機台完工。"
	parent.add_child(captions)
	sliders.activity_captions=captions
	return sliders

static func audio_levels(sliders:Dictionary) -> Dictionary:
	return {"master_volume":sliders.master_volume.value/100.0,"ambience_volume":sliders.ambience_volume.value/100.0,
		"interface_volume":sliders.interface_volume.value/100.0,"activity_captions":sliders.activity_captions.button_pressed}

static func camera_setting(app,content:VBoxContainer) -> OptionButton:
	content.add_child(text(app,"鏡頭跟隨",16))
	var choice:=OptionButton.new()
	choice.name="CameraMode"
	choice.add_item("直接跟隨")
	choice.add_item("小範圍固定")
	choice.selected=int(app.sound.fixed_area_camera)
	choice.custom_minimum_size.y=40
	content.add_child(choice)
	content.add_child(text(app,"小範圍固定時，短距離走動不會帶動背景。",14))
	return choice

static func text_scale_setting(app,content:VBoxContainer) -> OptionButton:
	content.add_child(text(app,"介面與場景文字大小",16))
	var choice:=OptionButton.new()
	choice.name="TextScale"
	for index in 4:choice.add_item(["小","標準","大","特大"][index],index)
	choice.selected=app.sound.preferred_text_scale
	choice.custom_minimum_size.y=40
	content.add_child(choice)
	return choice

static func display_setting(app,content:VBoxContainer) -> CheckBox:
	var mode:=CheckBox.new()
	mode.name="DisplayCompatibility"
	mode.text="相容顯示模式（60 FPS）"
	mode.tooltip_text="關閉垂直同步，畫面可能出現撕裂。"
	mode.button_pressed=app.sound.display_compatibility
	mode.custom_minimum_size.y=32
	content.add_child(text(app,"相容模式會關閉垂直同步，畫面可能撕裂。",14))
	content.add_child(mode)
	return mode

static func settings(app) -> void:
	var content:VBoxContainer=app._open_modal("讓自己舒服一點")
	app.modal.set_meta("life_modal_layout","settings")
	var camera:=camera_setting(app,content)
	var audio:=audio_settings(app,content)
	content.add_child(HSeparator.new())
	var motion:=CheckBox.new()
	motion.name="ReduceDecorativeMotion"
	motion.text="減少裝飾動態"
	motion.tooltip_text="開啟後小鳥會靜靜停在屋旁，也會減少釣魚、料理和共餐的裝飾動態。"
	motion.custom_minimum_size.y=40
	motion.button_pressed=app.sound.reduced_motion
	content.add_child(motion)
	content.add_child(text(app,"固定俯視角 · 無鏡頭旋轉、震動或動態模糊",14))
	var choices:=HBoxContainer.new()
	choices.add_theme_constant_override("separation",16)
	content.add_child(choices)
	var group:=ButtonGroup.new()
	var selected_zoom:Dictionary={"value":int(app.view.zoom)}
	for value in [2,1]:
		var card:=VBoxContainer.new()
		card.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		choices.add_child(card)
		var choice:=icon_button(app,"home" if value==2 else "map","近景" if value==2 else "遠景","",func():selected_zoom.value=value,72)
		choice.toggle_mode=true
		choice.button_group=group
		choice.button_pressed=int(app.view.zoom)==value
		choice.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
		card.add_child(choice)
		var caption:=text(app,"近景 · 角色更清楚" if value==2 else "遠景 · 看更多小島",15)
		caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		card.add_child(caption)
	var text_scale:=text_scale_setting(app,content)
	var display_mode:=display_setting(app,content)
	var skin:=CheckBox.new()
	skin.text="森林工具外觀"
	skin.disabled=World.gathering_level(app.session.snapshot.get("players",{}).get(app.session.own_id,{}))<10
	skin.button_pressed=app.sound.forest_tools and not skin.disabled
	skin.tooltip_text="採集十級解鎖斧頭及十字鎬的森林配色。"
	content.add_child(skin)
	var fishing:=OptionButton.new()
	fishing.name="FishingMode"
	fishing.add_item("輕鬆釣魚 · 咬鉤後按一次")
	fishing.add_item("標準釣魚 · 對準移動的魚影")
	fishing.selected=int(app.sound.standard_fishing)
	fishing.custom_minimum_size.y=40
	content.add_child(fishing)
	var save_button:Button=app.button("保存偏好 · 試聽",func():
		if not app.sound.save_preferences(app.settings_path,audio.volume.value/100.0,motion.button_pressed,selected_zoom.value,null if skin.disabled else skin.button_pressed,fishing.selected==1,text_scale.get_selected_id(),audio.music_volume.value/100.0,audio_levels(audio),camera.selected==1,display_mode.button_pressed):
			app._notice("設定保存失敗，原本設定仍保留。",false)
			return
		app.view.reduced_motion=app.sound.reduced_motion
		app.view.zoom=float(app.sound.preferred_zoom)
		app.view.fixed_area_camera=app.sound.fixed_area_camera
		app._apply_display_preferences()
		app._apply_font_scale_tree()
		app._refresh_hud()
		app._notice("設定已儲存，下次啟動會沿用。",true)
		app.sound.play_cue("reward",true)
	)
	save_button.name="SaveComfort"
	var footer:=HBoxContainer.new()
	footer.add_theme_constant_override("separation",10)
	app.modal_feedback.get_parent().add_child(footer)
	app.modal_feedback.reparent(footer,false)
	app.modal_feedback.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	footer.add_child(save_button)
	content.add_theme_constant_override("separation",7)
	motion.custom_minimum_size.y=32
	app.modal_feedback.text="偏好保存在這台電腦 · %s 切換遠近"%app.binding_label("zoom")
	# 手把／鍵盤上下：明確串過整個捲動區（滑桿左右鍵仍調音量，近景／遠景左右鍵照舊）。
	var zoom_pair:Array=[]
	for card in choices.get_children():zoom_pair.append(card.get_child(0))
	link_vertical_focus([[camera],[audio.master_volume],[audio.music_volume],[audio.ambience_volume],
		[audio.volume],[audio.interface_volume],[audio.activity_captions],[motion],zoom_pair,
		[text_scale],[display_mode],[skin],[fishing],[save_button]])
	group.pressed.connect(func(selected:BaseButton):
		motion.focus_neighbor_bottom=motion.get_path_to(selected)
		text_scale.focus_neighbor_top=text_scale.get_path_to(selected)
	)
	# 近景／遠景這一對：左右只在兩顆之間切換（全寬的勾選框不會搶走空間式的右鄰居）。
	if zoom_pair.size()==2:
		var near:Control=zoom_pair[0]
		var far:Control=zoom_pair[1]
		near.focus_neighbor_right=near.get_path_to(far)
		far.focus_neighbor_left=far.get_path_to(near)
		near.focus_neighbor_left=NodePath(".")
		far.focus_neighbor_right=NodePath(".")
	app._layout_preview()

## 把每一組控制項依序以上下焦點相連；停用的控制項略過。同組（例如近景／遠景）共用上下鄰居，
## 組內的左右移動不受影響。只用於舒適設定，不改共用的空間式焦點。
static func link_vertical_focus(groups:Array) -> void:
	var rows:Array=[]
	for group:Array in groups:
		var usable:Array=group.filter(func(c): return c is Control and not (c is BaseButton and c.disabled))
		if not usable.is_empty():rows.append(usable)
	for index in rows.size():
		for control:Control in rows[index]:
			if index>0:control.focus_neighbor_top=control.get_path_to(focus_target(rows[index-1]))
			if index<rows.size()-1:control.focus_neighbor_bottom=control.get_path_to(focus_target(rows[index+1]))

static func focus_target(group:Array) -> Control:
	for control:Control in group:
		if control is BaseButton and control.button_pressed:return control
	return group[0]

static func picnic_cooking_hint(snapshot:Dictionary,owner:String) -> String:
	var person:Dictionary=snapshot.get("players",{}).get(owner,{})
	if person.is_empty():return ""
	var dishes:Dictionary=snapshot.get("picnic_materials",{})
	var needed:Array[String]=[]
	for item in ["soup","bread"]:
		if int(dishes.get(item,0))<(2 if item=="soup" else 1):needed.append(item)
	var now:=float(snapshot.get("time",0.0))
	var cooking:=""
	for device:Dictionary in snapshot.get("objects",{}).values():
		if not preload("res://scripts/industry.gd").is_stove(str(device.get("type",""))) or preload("res://scripts/industry.gd").is_stove_extension(device):continue
		var model:=preload("res://scripts/cooking_queue_ui.gd").model(device,now)
		for dish:Dictionary in model.ready:
			if dish.kind in needed:return "料理好了，到小石灶領取"
		var active:Dictionary=model.active
		if not active.is_empty() and active.kind in needed:
			cooking="小石灶料理中，約剩 %d 秒"%maxi(0,ceili(float(active.remaining)))
	return cooking
