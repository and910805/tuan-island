extends RefCounted

const Art=preload("res://scripts/life_ui_theme.gd")
const Items=preload("res://scripts/inventory_item_art.gd")
const World=preload("res://scripts/world.gd")
const WeatherArt=preload("res://scripts/weather_art.gd")
const Forecast=preload("res://scripts/weather_forecast.gd")
const FORECAST_TIP_WIDTH:=360
## Keyboard path to the read-only forecast: Godot's existing ui_focus_prev
## (Shift+Tab). Plain Tab stays the (rebindable) inventory key.
const FORECAST_HOVER_HINT:="鍵盤：Shift+Tab 開關這張預報"
const FORECAST_TIP_HINT:="Shift+Tab／Esc 收起"
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
		badge.position=Vector2(5,1)
		badge.size.x=extent-10
		badge.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
		badge.add_theme_font_size_override("font_size",12)
		badge.add_theme_color_override("font_color",Color("fff5df"))
		badge.add_theme_color_override("font_outline_color",Color("583c32"))
		badge.add_theme_constant_override("outline_size",4)
		badge.mouse_filter=Control.MOUSE_FILTER_IGNORE
		result.add_child(badge)
	result.mouse_entered.connect(func():
		if app.sound and not app.sound.reduced_motion:
			var tween:=result.create_tween()
			tween.tween_property(art,"modulate",Color(1.12,1.12,1.05),0.12)
	)
	result.mouse_exited.connect(func():art.modulate=Color.WHITE)
	return result

static func text(app,value:String,size:int=16) -> Label:
	var result:Label=app.label(value,size)
	result.autowrap_mode=TextServer.AUTOWRAP_OFF
	return result

static func make_hud(app) -> void:
	var location:=VBoxContainer.new()
	location.position=Vector2(22,18)
	location.size=Vector2(230,60)
	location.mouse_filter=Control.MOUSE_FILTER_IGNORE
	app.hud.add_child(location)
	var title:=text(app,"風鈴渡口",24)
	title.name="RegionTitle"
	title.add_theme_color_override("font_color",Color("fff4d6"))
	title.add_theme_color_override("font_outline_color",Color("3c4c36"))
	title.add_theme_constant_override("outline_size",6)
	location.add_child(title)
	var subtitle:=text(app,"慢慢來，島上的日子還很長",13)
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
	var note:=VBoxContainer.new()
	tracker.add_child(note)
	var heading:=HBoxContainer.new()
	note.add_child(heading)
	heading.add_child(picture(icon("letter"),24))
	var toggle:Button=app.button("渡口的一封信  ▾",func():
		app.objective.visible=not app.objective.visible
		tracker.size.y=0
	)
	toggle.name="TrackerHeading"
	toggle.flat=true
	toggle.custom_minimum_size.y=28
	toggle.add_theme_font_size_override("font_size",14)
	heading.add_child(toggle)
	app.objective=app.label("",14)
	app.objective.custom_minimum_size.x=202
	note.add_child(app.objective)
	var open:Button=app.button("看看下一步  →",func():
		if app._harvest_tracking():app._harvest_menu() # T071 豐收接力（已加入進行中的一輪）
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
	open.add_theme_font_size_override("font_size",12)
	open.flat=true
	note.add_child(open)
	# T071 豐收接力：手上有模型蔬菜時才顯示（harvest_relay_ui.refresh_hud 控制）。
	var relay_pass:Button=app.button("傳給身旁的夥伴  →",app._harvest_pass)
	relay_pass.name="TrackerHarvestPass"
	relay_pass.custom_minimum_size.y=26
	relay_pass.add_theme_font_size_override("font_size",12)
	relay_pass.flat=true
	relay_pass.hide()
	note.add_child(relay_pass)
	var top:=HBoxContainer.new()
	app.preview_top=top
	app.hud.add_child(top)
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
	var tomorrow:=text(app,"",13)
	tomorrow.name="WeatherTomorrow"
	tomorrow.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	tomorrow.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
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
	app.selected_label=app.label("",14)
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
	shortcuts.add_child(bound_button(app,"backpack","背包","inventory",app._inventory,48))
	shortcuts.add_child(bound_button(app,"journal","島民手帳","journal",app._journal,48))
	shortcuts.add_child(icon_button(app,"settings","生活選單","Esc",app._pause_menu,48))
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
		if badge:badge.text="—" if key=="未設定" else key
		node.tooltip_text="%s [%s]"%[node.get_meta("binding_title"),key]

static func layout_hud(app,bounds:Vector2) -> void:
	var tiller:=app.preview_toolbar.find_child("TillerSlot",true,false) as Button
	var seeder:=app.preview_toolbar.find_child("SeederSlot",true,false) as Button
	var harvester:=app.preview_toolbar.find_child("HarvesterSlot",true,false) as Button
	var toolbar_width:=700 + 76 * (int(tiller != null and tiller.visible) + int(seeder != null and seeder.visible) + int(harvester != null and harvester.visible))
	app.preview_toolbar.size=Vector2(toolbar_width,92)
	app.preview_toolbar.position=Vector2(floor((bounds.x-toolbar_width)/2),bounds.y-106)
	app.preview_top.position=Vector2(bounds.x-244,18)
	app.preview_top.size=Vector2(222,100)
	# Focus tip sits left of the calendar badge (never over toolbar/shortcuts) and is hidden unless focused.
	var tip:=app.hud.get_node_or_null("WeatherForecastTip") as Control
	if tip:
		tip.position=Vector2(maxf(8.0,bounds.x-244-8-FORECAST_TIP_WIDTH),18)
		tip.size=Vector2(FORECAST_TIP_WIDTH,0)
	app.selected_label.position=Vector2((bounds.x-740)/2,bounds.y-142)
	app.selected_label.size=Vector2(740,32)
	var shortcuts:Control=app.hud.get_node("LifeShortcuts")
	shortcuts.position=Vector2(bounds.x-180,bounds.y-66)
	shortcuts.size=Vector2(156,48)
	if bounds.x<toolbar_width+368:
		shortcuts.position=Vector2(bounds.x-180,132)

static func refresh_hud(app,s:Dictionary,p:Dictionary) -> void:
	var region_title:Label=app.hud.find_child("RegionTitle",true,false) as Label
	if region_title:region_title.text={"home":"風鈴渡口","lanyang":"宜蘭・蘭陽試作田","jinguashi":"新北・金瓜石山城"}.get(s.get("region_id","home"),World.REGIONS.label(str(s.get("region_id","home"))))
	var depth_region:=str(s.get("region_id","home"))
	var station_name:String=preload("res://scripts/transit_art.gd").NAMES.get(depth_region,"")
	if region_title and not station_name.is_empty():region_title.text=station_name
	var tracker_heading:Button=app.hud.find_child("TrackerHeading",true,false) as Button
	var tracker_next:Button=app.hud.find_child("TrackerNext",true,false) as Button
	if tracker_heading:tracker_heading.text="礦務隨身記  ▾" if depth_region.begins_with("mine_") else "渡口的一封信  ▾"
	if tracker_next:tracker_next.text="查看出入口  →" if depth_region.begins_with("mine_") else "看看下一步  →"
	if not station_name.is_empty():
		if tracker_heading:tracker_heading.text="北部旅程  ▾"
		if tracker_next:tracker_next.text="查看轉乘  →"
	if depth_region=="jinguashi":
		if tracker_heading:tracker_heading.text="波波的礦樣桌  ▾"
		if tracker_next:tracker_next.text="翻開波波的故事  →"
	if region_title and depth_region.begins_with("mine_"):
		region_title.text="金瓜石合作礦場・地下第 %d 層"%int(depth_region.trim_prefix("mine_"))
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
	var short:Dictionary={"grow":"種下作物，收成第一批菜", "ship":"把收成放進出貨箱", "works":"修橋，讓配送重新出發", "water":"接起水桶、管線和灑水器", "meal":"準備湯和麵包，一起開飯", "complete":"渡口開飯了 · 下一站的信"}
	app.objective.text="讓渡口重新開飯\n"+str(short[step.id])
	# 望安開場：自己的第一株作物依序 find → till → sow → water → wait → harvest → ship。
	var first_crop:Dictionary=World.CHAPTER_ONE.first_crop_step(s,app.session.own_id)
	if not first_crop.is_empty():app.objective.text=preload("res://scripts/wangan_opening_ui.gd").tracker_text(app,first_crop)
	elif step.id=="grow":app.objective.text="第一件事・種一株蘿蔔\n開田、播種、澆水，再採收"
	elif step.id=="ship":app.objective.text+="\n✓ 第一批收成準備好了"
	if step.id=="works":app.objective.text+="\n木 %d/30 · 石 %d/10"%[s.donations.wood,s.donations.stone]
	if step.id=="meal":app.objective.text+="\n蘿蔔湯 %d/2 · 麵包 %d/1"%[s.picnic_materials.soup,s.picnic_materials.bread]
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
			if tracker_heading:tracker_heading.text="金瓜石回訪  ▾"
			if tracker_next:tracker_next.text="打開礦料調度  →"
	elif not station_name.is_empty():
		var onward:String={"toucheng":"往東北走到頭城月台。","ruifang":"穿過廣場，往東南找公車站。","jiufen":"沿石板街往東北走到接駁站。"}.get(depth_region,"")
		var resident_hint:String={"toucheng":"月台南側，找阿程聊聊。","ruifang":"廣場中間，穗禾在修長凳。","jiufen":"燈籠街旁，春姨等你歇腳。"}.get(depth_region,"")
		if depth_region=="ruifang" and s.get("station_life",{}).get("repairs",{}).get("ruifang",false):resident_hint="穗禾替大家留了候車座位。"
		app.objective.text="%s\n%s\n%s 交談／搭車 · %s 地圖"%[resident_hint,onward,app.binding_label("interact"),app.binding_label("map")]
	if depth_region.begins_with("mine_"):
		app.objective.text="礦內體力  %d\n在休息站補水，礦務站可整備下層。\n%s 查看路線"%[int(p.get("mine_energy",0)),app.binding_label("map")]
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
		if tracker_heading:tracker_heading.text="風鈴接力  ▾"
		if tracker_next:tracker_next.text="查看風鈴接力  →"
	if depth_region=="tianwei":
		var flower_step:Dictionary=preload("res://scripts/flower_nursery_ui.gd").next_step(s,app.session.own_id)
		if tracker_heading:tracker_heading.text="花圃手記  ▾"
		if tracker_next:tracker_next.text="翻開花圃手帳  →"
		app.objective.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		app.objective.text=str(flower_step.get("title","田尾合作花圃"))+"\n"+str(flower_step.get("detail","和花農聊聊，認識花圃。"))
	if depth_region=="beimen":
		# 北門鹽田：手記卡片顯示自己的下一步（只讀快照中的 salt_pan.own.guidance）。
		var salt_step:Dictionary=preload("res://scripts/salt_pan_ui.gd").next_step(s)
		var salt_titles:={"intro":"認識阿曬","gates":"修好三道閘門","first_salt":"第一次曬鹽","claim":"認領鹽田區","wheel":"裝上鹽田水車","rake":"做一座收鹽台","automate":"讓鹽自己進箱子","order":"帶鹽回渡口","report":"回報阿曬","complete":"北門這一段完成了"}
		if tracker_heading:tracker_heading.text="鹽田手記  ▾"
		if tracker_next:tracker_next.text="翻開鹽田手帳  →"
		app.objective.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		app.objective.text=str(salt_titles.get(str(salt_step.get("phase","")),"北門鹽風合作鹽田"))+"
"+str(salt_step.get("text","和阿曬聊聊，認識合作鹽田。"))
		# 第 40 章臺南北門回訪：鹽田章節完成、自己收過鹽，而且鹽籃批次有現在就能做的一步時，
		# 追蹤卡改看批次進度（章節還在進行時保留章節的下一步）。
		var basket_line:String=preload("res://scripts/salt_revisit_ui.gd").tracker_text(s,str(app.session.own_id))
		if not basket_line.is_empty():
			app.objective.text=basket_line
			if tracker_heading:tracker_heading.text="臺南北門回訪  ▾"
			if tracker_next:tracker_next.text="打開鹽籃批次  →"
	var forest_skin:bool=app.sound.forest_tools and World.gathering_level(p)==10
	for action in FOREST_TOOLS:
		var index:=TOOL_IDS.find(action)
		if index>=app.tool_buttons.size():continue
		var button:Button=app.tool_buttons[index]
		if button.get_meta("forest_skin",false)==forest_skin:continue
		var art:=button.get_node_or_null("ToolArt") as TextureRect
		if art:art.texture=FOREST_TOOLS[action] if forest_skin else icon(action)
		button.set_meta("forest_skin",forest_skin)
	var rod:=app.preview_toolbar.find_child("FishingSlot",true,false) as Button
	if rod:rod.set_pressed_no_signal(app.selected=="fish")
	var needs_layout := false
	for tool in [["TillerSlot", "tiller", "till_area"], ["SeederSlot", "seeder", "seed_area"], ["HarvesterSlot", "harvester", "harvest_area"]]:
		var slot := app.preview_toolbar.find_child(tool[0],true,false) as Button
		if slot == null:continue
		var owned := int(p.get("inventory",{}).get(tool[1],0)) > 0
		needs_layout = needs_layout or slot.visible != owned
		slot.visible = owned
		slot.set_pressed_no_signal(app.selected == tool[2] and owned)
	if needs_layout:
		layout_hud(app,app.get_viewport().get_visible_rect().size)

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

static func pause(app) -> void:
	var content:VBoxContainer=app._open_modal("歇一會兒")
	app.modal.set_meta("life_modal_layout","pause_drawer")
	var intro:=text(app,"今天也在島上留下了一點回憶。",14)
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
	for entry in entries:
		var cell:=VBoxContainer.new()
		cell.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		cell.alignment=BoxContainer.ALIGNMENT_CENTER
		grid.add_child(cell)
		var b:=icon_button(app,entry[0],entry[1],"—" if entry[2]=="未設定" else entry[2],entry[3],72)
		if entry[1]=="島民交換":b.name="PauseTrade"
		if entry[1]=="舒適設定":b.name="PauseComfort"
		b.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
		cell.add_child(b)
		var caption:=text(app,entry[1],14)
		caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		cell.add_child(caption)
	var footer:=HBoxContainer.new()
	footer.add_theme_constant_override("separation",6)
	var shell:VBoxContainer=content.get_parent().get_parent()
	shell.add_child(footer)
	shell.move_child(footer,shell.get_child_count()-3)
	var rescue:Button=app.button("迷路了？回到渡口",func():app.session.perform("rescue",Vector2i.ZERO);app._close_modal())
	rescue.flat=true
	rescue.add_theme_font_size_override("font_size",13)
	rescue.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	footer.add_child(rescue)
	var save:Button=app.button("儲存今天 · 離開小島",app._quit)
	save.add_theme_font_size_override("font_size",13)
	save.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	footer.add_child(save)
	app.modal_feedback.text="Esc 返回 · 多人世界仍繼續運作"
	app._layout_preview()

static func reveal(app,control:Control) -> void:
	if app.sound and not app.sound.reduced_motion:
		control.modulate.a=0.0
		var tween:=control.create_tween()
		tween.tween_property(control,"modulate:a",1.0,0.16).set_trans(Tween.TRANS_SINE)

static func help(app) -> void:
	var content:VBoxContainer=app._open_modal("第一天的口袋指南")
	var grid:=GridContainer.new()
	grid.columns=2
	grid.add_theme_constant_override("h_separation",16)
	grid.add_theme_constant_override("v_separation",12)
	content.add_child(grid)
	var lessons=[
		["hoe","種下第一份收成","%s 鋤田 → %s 種子 → %s 澆水 → %s 採收。\n%s 換種子，靠近種子攤按 %s 買賣。"%[app.binding_label("hoe"),app.binding_label("seed"),app.binding_label("water"),app.binding_label("harvest"),app.binding_label("seeds"),app.binding_label("interact")]],
		["build","慢慢蓋起自己的家","%s 選家具，點附近空地放置。\n%s 搬家具，按住 %s 拖曳鋪地板、步道、屋頂。"%[app.binding_label("build_menu"),app.binding_label("move_object"),app.binding_label("area_modifier")]],
		["axe","口袋裡的島嶼材料","斧頭砍樹三下，十字鎬敲石兩下。\nT 種樹苗約三分鐘長成；砍樹會取得樹苗。"],
		["letter","和島民一起生活","公告板按 %s 捐材料修橋，%s 看居民故事。\n放箱子共享材料，小石灶做料理和飼料。"%[app.binding_label("interact"),app.binding_label("journal")]],
		["fish","留一點時間給河岸","%s 選釣竿，點水面拋竿，咬鉤按 %s。\n靠近糯米雞按 %s 照料，%s 看生活收藏。"%[app.binding_label("fish"),app.binding_label("fish_catch"),app.binding_label("interact"),app.binding_label("collection")]],
		["settings","照自己的步調遊玩","上 %s、左 %s、下 %s、右 %s，操作範圍約三格。\n%s 切近遠景，Esc 開選單。"%[app.binding_label("move_up"),app.binding_label("move_left"),app.binding_label("move_down"),app.binding_label("move_right"),app.binding_label("zoom")]]]
	for lesson in lessons:
		var card:=PanelContainer.new()
		card.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		card.add_theme_stylebox_override("panel",Art.compact_style())
		grid.add_child(card)
		var body:=VBoxContainer.new()
		card.add_child(body)
		var heading:=HBoxContainer.new()
		body.add_child(heading)
		heading.add_child(picture(icon(lesson[0]),40))
		heading.add_child(text(app,lesson[1],18))
		var description:Label=app.label(lesson[2],14)
		description.custom_minimum_size.x=290
		body.add_child(description)
	content.add_child(app.label("菜園小幫手：蓋工作台，靠近按 %s 做強化石鎬 → 採銅 → 銅接頭 → 灑水器套件。%s 放置，靠近按 %s 補水。"%[app.binding_label("interact"),app.binding_label("build_menu"),app.binding_label("interact")],14))
	content.add_child(app.label(app.binding_text("林間水工坊：成熟樹提供樹脂；鋸木台做木板、炭窯做木炭。工作台再做桶、泵和銅管，{build} 放置。河水泵在河水兩格內啟用，以同主人的四向管線接桶、再接灑水器。管線占一格，可走過；斷管後既有儲水仍可用。"),14))
	content.add_child(app.label("輸送帶：按 %s 選方向和物品，再啟用。木材可送入鋸木台或炭窯，木炭可送入林務工作站。"%[app.binding_label("interact")],14))
	content.add_child(app.label("手推耕田機：持有時按 %s，點身邊空地一次最多開 9 格。成功才消耗 1 木炭。"%[app.binding_label("till_area")],14))
	content.add_child(app.label("手推播種機：按 %s 換種子，按 %s 拿起。點自己的空農田，最多播 9 格。"%[app.binding_label("seeds"),app.binding_label("seed_area")],14))
	content.add_child(app.label("手推收割機：按 %s 拿起，點自家成熟作物，最多收 9 格，整次成功耗 1 木炭。"%[app.binding_label("harvest_area")],14))
	content.add_child(app.label(app.binding_text("小小林務所：工作台製作林務工作站，{build} 放置，{interact} 裝入木炭與樹苗再啟用。管理上下左右各兩格的四塊人工林；每 12 秒巡一格，成熟後採伐並補植。只處理自己的人工樹，不動原生林。木材、纖維、樹脂存滿會停止，領取後可帶去鋸木台與炭窯。"),14))
	content.add_child(app.label(app.binding_text("{remove} 拆除會退回材料，也能收回自己的樹苗或空農田。屋頂先鋪地板，進屋後會淡化。成功操作後自動保存；無人在線時生長暫停。"),14))

static func settings(app) -> void:
	var content:VBoxContainer=app._open_modal("讓自己舒服一點")
	app.modal.set_meta("life_modal_layout","settings")
	var audio:=HBoxContainer.new()
	audio.add_theme_constant_override("separation",16)
	content.add_child(audio)
	audio.add_child(picture(icon("bell"),48))
	var volume:=VBoxContainer.new()
	volume.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	audio.add_child(volume)
	var amount:=text(app,"提示音 %d%%"%roundi(app.sound.volume*100),20)
	volume.add_child(amount)
	var slider:=HSlider.new()
	slider.min_value=0;slider.max_value=100;slider.step=5;slider.value=app.sound.volume*100
	slider.custom_minimum_size.y=32
	volume.add_child(slider)
	slider.value_changed.connect(func(value):amount.text="提示音 %d%%"%int(value))
	content.add_child(text(app,"靜音也能靠文字提示完成所有操作。",14))
	content.add_child(HSeparator.new())
	var motion:=CheckBox.new()
	motion.text="減少裝飾動態"
	motion.tooltip_text="開啟：保留靜態提示，減少釣魚、料理與共餐裝飾動態。關閉：顯示拋竿、浮標、熱湯蒸氣與共餐慶祝。兩種模式皆無鏡頭震動。"
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
	content.add_child(text(app,"介面文字大小",16))
	var text_scale:=OptionButton.new()
	text_scale.name="TextScale"
	for index in 4:text_scale.add_item(["小","標準","大","特大"][index],index)
	text_scale.selected=app.sound.preferred_text_scale
	text_scale.custom_minimum_size.y=40
	content.add_child(text_scale)
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
		if not app.sound.save_preferences(app.arg_value("settings","user://settings.cfg"),slider.value/100.0,motion.button_pressed,selected_zoom.value,null if skin.disabled else skin.button_pressed,fishing.selected==1,text_scale.get_selected_id()):
			app._notice("設定保存失敗，原本設定仍保留。",false)
			return
		app.view.reduced_motion=app.sound.reduced_motion
		app.view.zoom=float(app.sound.preferred_zoom)
		app._apply_font_scale_tree()
		app._refresh_hud()
		app._notice("設定已儲存，下次啟動會沿用。",true)
		app.sound.play_cue("reward",true)
	)
	save_button.name="SaveComfort"
	content.add_child(save_button)
	content.add_theme_constant_override("separation",7)
	motion.custom_minimum_size.y=32
	app.modal_feedback.text="偏好保存在這台電腦 · %s 切換遠近"%app.binding_label("zoom")
	app._layout_preview()
