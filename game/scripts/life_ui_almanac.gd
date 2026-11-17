extends RefCounted

const Tasks = preload("res://scripts/life_ui_tasks.gd")
const World = preload("res://scripts/world.gd")
const Collections = preload("res://scripts/collections.gd")
const Festival = preload("res://scripts/festival.gd")
const Art = preload("res://scripts/inventory_item_art.gd")
const Shell = preload("res://scripts/life_ui_shell.gd")
const LivestockArt=preload("res://scripts/livestock_scene_art.gd")
const BOARD := Vector2i(40, 29)

static func collection_menu(app,initial_tab:=0) -> void:
	var body: VBoxContainer = app._open_modal("小島生活圖鑑  %s"%app.binding_label("collection"))
	app.modal.set_meta("life_modal_layout", "collection_almanac")
	var person := Tasks.player(app)
	var collection: Dictionary = person.get("collection", {})
	var tabs := HBoxContainer.new()
	body.add_child(tabs)
	var group := ButtonGroup.new()
	var pages: Array[Control] = []
	var categories := ["里程碑", "菜園", "魚類", "料理", "海岸", "故事", "展示"]
	for index in categories.size():
		var page := VBoxContainer.new()
		page.visible = index == initial_tab
		body.add_child(page)
		pages.append(page)
		var tab: Button = app.button(categories[index], func():
			for page_index in pages.size():
				pages[page_index].visible = page_index == index
		)
		tab.name="CollectionTab%d"%index
		tab.toggle_mode = true
		tab.icon = Art.icon(["coins", "radish", "carp", "soup", World.WANGAN_COAST.SHELL_ITEM, "gold_sample", "gold_sample"][index])
		tab.expand_icon = true
		tab.add_theme_constant_override("icon_max_width", 24)
		tab.button_group = group
		tab.button_pressed = index == initial_tab
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tabs.add_child(tab)
	var stamps := GridContainer.new()
	stamps.columns = 3
	stamps.add_theme_constant_override("h_separation", 12)
	pages[0].add_child(stamps)
	add_gallery(app,pages[6])
	var stamp_index := 0
	for id in Collections.MILESTONES:
		var milestone: Dictionary = Collections.MILESTONES[id]
		var amount := Collections.progress(person, id)
		var target := int(milestone.target)
		var claimed: bool = collection.get("claimed", {}).get(id, false)
		var card := Tasks.card(stamps)
		card.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
		Tasks.add_icon(card, Art.icon(["radish", "carp", "soup"][stamp_index]), 56)
		stamp_index += 1
		Tasks.line(app, card, milestone.name, 19)
		Tasks.line(app, card, "✓ 已領取" if claimed else "%d／%d" % [amount, target], 15)
		Tasks.line(app, card, milestone.reward_text, 15)
		if not claimed and amount >= target:
			card.add_child(app.button("領取里程碑獎勵",
				func(): app.session.perform("claim_milestone", Vector2i.ZERO, id); app._close_modal()))
	if app.session.snapshot.get("resident_goals",{}).get("diandian",{}).get("1",{}).get("state")=="done":
		var sticker_card:=Tasks.card(pages[1])
		Tasks.line(app,sticker_card,"點點的菜園貼紙",18)
		var strip:=HBoxContainer.new()
		sticker_card.add_child(strip)
		for kind:String in app.session.snapshot.get("own_crop_sketches",{}):
			var sticker:=Tasks.card(strip)
			var sticker_panel:=sticker.get_parent() as Control
			sticker_panel.custom_minimum_size.x=116
			Tasks.add_icon(sticker,sketch_icon(kind),40)
			var caption:String=World.RESIDENT_GOALS.SKETCH_ANIMALS.get(kind,World.CROPS.get(kind,{}).get("name",kind))
			Tasks.line(app,sticker,caption,14)
	var keys := ["crops", "fish", "meals", "shore"]
	var catalogs := [World.CROPS, World.FISH, World.RECIPES, Collections.SHORE_FINDS]
	Tasks.line(app,pages[4],"望安南岸・已收錄 %d／%d"%[collection.get("shore",{}).size(),Collections.SHORE_FINDS.size()],16)
	var observation:=World.Collections.angling_level(person)
	Tasks.line(app,pages[2],"漁獵觀察 %d 級 · 三級解鎖水域線索，六級解鎖北門釣點預報。" % observation,15)
	Tasks.line(app,pages[2],"北門東岸釣點 · 北側碼頭水面夜釣月光小魷，南側潮池全天可釣金邊蝦。",15)
	Tasks.line(app,pages[2],"礁溪暖泉溪 · 白天可釣玻璃小蝦；冬季到高地冷泉找雪點鱒魚。",15)
	for water in Collections.RARE_WATERS.values():
		Tasks.line(app,pages[2],"%s · %s · 保底進度 %d／%d" % [World.FISH[water.fish].name,water.hint,int(person.get(water.counter,0)),Collections.RARE_FISH_LIMIT],15)
	for index in keys.size():
		var grid := GridContainer.new()
		grid.columns = 2 if keys[index]=="shore" else 3
		pages[index + 1].add_child(grid)
		for id in catalogs[index]:
			if keys[index]=="meals" and not Collections.is_meal(id):
				continue
			var cell := Tasks.card(grid)
			cell.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var found: bool = collection.get(keys[index], {}).get(id, false)
			var icon := TextureRect.new()
			icon.texture = Art.icon(id)
			icon.custom_minimum_size = Vector2(40, 40)
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			icon.modulate.a = 1.0 if found else 0.42
			cell.add_child(icon)
			Tasks.line(app, cell, ("✓ " if found else "○ ") + catalogs[index][id].name, 15)
			var location:="望安南岸" if keys[index]=="shore" else ""
			if keys[index]=="shore":Tasks.line(app,cell,catalogs[index][id].hint,14)
			var field:String=keys[index]+"_discoveries"
			var first:Dictionary=app.session.snapshot.get("island_"+field,{}).get(id,{})
			if not first.is_empty():
				Tasks.line(app,cell,"全島首位 %s・%s" % [first.name,discovery_location(first,location)],13)
			var discovery:Dictionary=person.get(field,{}).get(id,{})
			if not discovery.is_empty():
				Tasks.line(app,cell,"個人首次 "+discovery_location(discovery,location),13)
			add_collection_status(app,cell,person,id,found,not first.is_empty())
	Tasks.line(app,pages[5],"故事物件登錄後仍可保留或擺放。",15)
	var story_grid:=GridContainer.new()
	story_grid.columns=3
	pages[5].add_child(story_grid)
	var stories:=Collections.story_catalog()
	for id:String in stories:
		var story_item:=Tasks.card(story_grid)
		(story_item.get_parent() as Control).size_flags_horizontal=Control.SIZE_EXPAND_FILL
		Tasks.add_icon(story_item,Art.icon(id),48)
		Tasks.line(app,story_item,stories[id],17)
		var keepsake:Dictionary=World.RESIDENT_GOALS.KEEPSAKES.get(id.trim_suffix(World.RESIDENT_GOALS.KIT_SUFFIX),{})
		var received:bool=not keepsake.is_empty() and Tasks.goal_state(app,keepsake.resident,int(keepsake.stage)).get("keepsake",{}).get("claimed",false)
		add_collection_status(app,story_item,person,id,received,false)
	Tasks.line(app, body, "記錄親手採收、釣魚、料理和海岸採集。出售或使用後仍保留，舊背包不會自動算入。", 15)

static func add_collection_status(app,card:VBoxContainer,person:Dictionary,id:String,found:bool,seen_on_island:bool) -> void:
	var inventory:Dictionary=person.get("inventory",{})
	var donated:bool=person.get("collection_donations",{}).has(id)
	var displayed:bool=id in person.get("collection_display",[])
	var held:=int(inventory.get(id,0))
	var acquired:bool=found or donated or held>0 or person.get("collection_acquired",{}).has(id)
	var seen:=seen_on_island or acquired
	Tasks.line(app,card,"%s見過  %s取得\n%s捐贈  %s展示"%[
		"✓" if seen else "○","✓" if acquired else "○","✓" if donated else "○","✓" if displayed else "○"],13)
	var snapshot:Dictionary=app.session.snapshot
	var nearby:bool=snapshot.get("region_id","home")=="home" and Vector2(person.get("x",0),person.get("y",0)).distance_to(Vector2(BOARD)+Vector2(0.5,0.5))<=3.2
	if not nearby:return
	if not donated and (held>0 or (found and Collections.story_item(id))):
		var caption:="登錄故事物件" if Collections.story_item(id) else "捐贈 1 件"
		card.add_child(app.button(caption,func():app.session.perform("collection_donate",BOARD,id);app._close_modal()))
	elif donated:
		card.add_child(app.button("撤下展示" if displayed else "放上展示",func():
			app.session.perform("collection_unshow" if displayed else "collection_display",BOARD,id)
			app._close_modal()))

static func add_gallery(app,page:VBoxContainer) -> void:
	var card:=Tasks.card(page)
	Tasks.line(app,card,"渡口收藏展示",18)
	Tasks.line(app,card,"到公告板旁打開各分類，就能捐贈普通物品或安排展示。每位居民可展示六件。",14)
	var exhibits:Dictionary=app.session.snapshot.get("collection_exhibits",{})
	if exhibits.is_empty() and not Tasks.player(app).get("collection_display",[]).is_empty():
		var viewer:=Tasks.player(app)
		exhibits={app.session.own_id:{"name":viewer.get("name",""),"items":viewer.collection_display}}
	if exhibits.is_empty():Tasks.line(app,card,"展示架還沒有收藏。",14)
	for exhibit:Dictionary in exhibits.values():
		Tasks.line(app,card,str(exhibit.name),15)
		var items:=HFlowContainer.new()
		items.add_theme_constant_override("separation",12)
		card.add_child(items)
		for item:String in exhibit.items:
			var piece:=Tasks.card(items)
			(piece.get_parent() as Control).custom_minimum_size.x=116
			var icon:=Shell.picture(Art.icon(item),32)
			icon.tooltip_text=str(World.NAMES.get(item,item))
			piece.add_child(icon)
			Tasks.line(app,piece,icon.tooltip_text,14)

static func sketch_icon(kind:String) -> Texture2D:
	if kind=="duck":return World.LIVESTOCK.Duck.texture()
	if kind=="chicken":
		var icon:=AtlasTexture.new()
		icon.atlas=preload("res://assets/life-art/animals.png")
		icon.region=Rect2(0,0,32,32)
		return icon
	if LivestockArt.has_animal(kind):return LivestockArt.texture(kind,"idle")
	return Art.icon(kind)

static func add_animal_sketch(app,parent:Container,id:String,cell:Vector2i) -> void:
	var s:Dictionary=app.session.snapshot
	if int(s.get("resident_bonds",{}).get("diandian",{}).get("stage",0))<1:return
	var sketches:Dictionary=s.get("own_crop_sketches",{})
	if sketches.size()>=World.RESIDENT_GOALS.SKETCH_TARGET or sketches.has(id):return
	var sketch:Button=app.button("畫下%s"%World.RESIDENT_GOALS.SKETCH_ANIMALS[id],func():
		app.session.perform(World.RESIDENT_GOALS.SKETCH_ACTION,cell,id)
		app._close_modal())
	sketch.name="AnimalSketch"
	parent.add_child(sketch)

static func discovery_location(discovery:Dictionary,location:="") -> String:
	if not location.is_empty():return "%s・第 %d 日"%[location,int(discovery.day)]
	var place:String={"home":"風鈴渡口","lanyang":"宜蘭水圳","beimen":"北門海岸","jiaoxi":"礁溪・暖泉高地"}.get(discovery.region,discovery.region)
	return "%s・第 %d 日"%[place,int(discovery.day)]

static func festival_menu(app) -> void:
	var body: VBoxContainer = app._open_modal("渡口派對  ·  風鈴接力")
	app.modal.set_meta("life_modal_layout", "festival_card")
	var snapshot: Dictionary = app.session.snapshot
	var festival: Dictionary = snapshot.festival
	var card := Tasks.card(body)
	Tasks.add_icon(card, Shell.icon("bell"), 56)
	if not snapshot.picnic:
		app.modal.set_meta("life_modal_layout", "festival_locked")
		Tasks.line(app, card, "完成公告板的渡口野餐後，即可開辦派對。", 17)
		# T071 紀念品交換攤 (locked) sits beside the bell icon (the icon row is taller than
		# the button), right above the three locked activity entries: no new page height.
		var bell := card.get_child(0) as Control
		var icon_row := HBoxContainer.new()
		icon_row.name = "FestivalLockedRow"
		icon_row.add_theme_constant_override("separation", 12)
		card.add_child(icon_row)
		card.move_child(icon_row, 0)
		card.remove_child(bell)
		icon_row.add_child(bell)
		var locked := souvenir_entry(app, false)
		locked.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon_row.add_child(locked)
		harvest_entry(app, body, false)
		return
	Tasks.line(app, card, "一到四人接力收集十二枚金色風鈴。靠近按 %s，下一枚會在別處出現。"%app.binding_label("interact"), 17)
	var stamps := HBoxContainer.new()
	card.add_child(stamps)
	for index in 12:
		Tasks.line(app, stamps, "◆" if index < int(festival.collected) else "◇", 18)
	if festival.active:
		var target := Festival.target(festival)
		Tasks.line(app, card, "第 %d 場 · %d／12 · 下一枚位於 %d, %d" % [festival.round, festival.collected, target.x, target.y], 18)
	else:
		if int(festival.round) > 0:
			Tasks.line(app, card, "上一場 %d 秒 · 最快 %d 秒 · 獎勵已入帳" %
				[ceili(float(festival.finished)-float(festival.started)), ceili(float(festival.best))], 17)
		var wait := maxi(0, ceili(float(festival.ready)-float(snapshot.time)))
		var round_id := str(int(festival.round))
		var start: Button = app.button("約 %d 秒後可再玩" % wait if wait > 0 else "在公告板旁開始一場接力",
			func(): app.session.perform("festival_start", BOARD, round_id); app._close_modal())
		start.disabled = wait > 0
		card.add_child(start)
	var finished:bool=not festival.active and int(festival.collected)==Festival.GOAL
	if finished:
		add_festival_food(app,body,snapshot)
	var results:=card
	if finished and not festival.contributors.is_empty():
		results=Tasks.card(body)
		Tasks.line(app,results,"這一場的接力夥伴",17)
	for contribution in festival.contributors.values():
		var count := int(contribution.count)
		Tasks.line(app, results, "%s  ·  接住 %d 枚%s" % [contribution.name, count,
			"" if festival.active else "  ·  鈴幣 +%d" % (20 + 2 * count)], 15)
	# T071 紀念品交換攤 entry shares the row of 「給大家的風鈴節」 (no new page height),
	# right above the three activity entries.
	var links := HBoxContainer.new()
	links.name = "FestivalLinks"
	links.add_theme_constant_override("separation", 8)
	body.add_child(links)
	var story: Button = app.button("給大家的風鈴節",festival_story.bind(app))
	story.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	links.add_child(story)
	links.add_child(souvenir_entry(app, true))
	# 第 40 章地方記憶展 shares the same row (no new page height; locked caption before
	# the festival opening).
	links.add_child(preload("res://scripts/memory_exhibit_ui.gd").entry_button(app))
	harvest_entry(app, body, true)
	Tasks.line(app, body, "無失敗倒數、不耗材料，離線會保留進度。每位有收集者可得 20 鈴幣及每枚 2 鈴幣；五分鐘在線世界時間後可再玩。", 15)

## T071 豐收接力 entry: opens its panel from anywhere (start/join there explain that
## you must stand at the sign). Before the picnic the caption states the lock.
static func harvest_entry(app, body: VBoxContainer, unlocked: bool) -> void:
	var entry: Button = app.button("另一個合作活動：豐收接力（廣場西側）" if unlocked else "豐收接力・渡口野餐後開放", app._harvest_menu)
	entry.name = "HarvestRelayEntry"
	# T071 河岸釣魚會 entry shares the row so the page keeps its height (no new scrolling).
	var row := HBoxContainer.new()
	row.name = "ActivityEntries"
	row.add_theme_constant_override("separation", 8)
	body.add_child(row)
	entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(entry)
	var fishing: Button = app.button("河岸釣魚會（河灣橋南岸）" if unlocked else "河岸釣魚會・渡口野餐後開放", app._fishmeet_menu)
	fishing.name = "FishingMeetEntry"
	fishing.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(fishing)
	# T071 家園布置題 entry joins the same row (no new page height).
	var showcase: Button = app.button("家園布置題（渡口西南草地）" if unlocked else "家園布置題・渡口野餐後開放", app._showcase_menu)
	showcase.name = "ShowcaseEntry"
	showcase.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(showcase)

## T071 紀念品交換攤 entry button (opens the exchange page from anywhere; redeeming
## there still needs the booth within reach). Before the picnic the caption states the lock.
static func souvenir_entry(app, unlocked: bool) -> Button:
	var entry: Button = app.button(preload("res://scripts/souvenir_exchange_ui.gd").entry_caption(unlocked), app._souvenir_menu)
	entry.name = "SouvenirEntry"
	entry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return entry

const FESTIVAL_SCENES := [
	["aru","阿榆","你看，風鈴樹開花了。我把燈掛低一點，晚來的人也看得見路。"],
	["milu","米露","茶茶帶了茶，阿蕾帶了花。來，先坐下喝口湯，桌邊還有位置。"],
	["xiaoli","小栗","我把今晚寫進收貨簿了。這一頁只記得大家又回到渡口，下一頁就留給你們。"],
]

static func festival_story(app,from_journal:=false,scene_index:=0) -> void:
	var snapshot:Dictionary=app.session.snapshot
	var story:Dictionary=snapshot.get("festival_story",{})
	var body:VBoxContainer=app._open_modal("給大家的風鈴節",story.get("opened",false))
	app.modal.set_meta("life_modal_layout","community_board")
	var paper:=Tasks.card(body)
	if story.get("opened",false):
		if scene_index<FESTIVAL_SCENES.size():
			var scene:Array=FESTIVAL_SCENES[scene_index]
			Tasks.portrait_header(app,paper,scene[0],"",80)
			Tasks.line(app,paper,"「%s」"%scene[2],18)
		else:
			Tasks.add_icon(paper,World.Deer.texture(),80)
			Tasks.line(app,paper,"樹下的最後一位訪客",20)
			Tasks.line(app,paper,"花瓣落在風鈴鹿的背上。牠朝還亮著燈的渡口低了低頭，角間的小鈴應了一聲。",18)
		var pages:=HBoxContainer.new()
		body.add_child(pages)
		if scene_index>0:pages.add_child(app.button("上一幕",festival_story.bind(app,from_journal,scene_index-1)))
		var page:Label=app.label("%d / %d"%[scene_index+1,FESTIVAL_SCENES.size()+1],16)
		page.name="FestivalScenePage"
		page.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		page.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		pages.add_child(page)
		if scene_index<FESTIVAL_SCENES.size():pages.add_child(app.button("下一幕",festival_story.bind(app,from_journal,scene_index+1)))
	else:
		var mask:=int(story.get("projects",0))
		var boat_ready:bool=story.get("boat_ready",false)
		Tasks.line(app,paper,"第四章・碼頭與小船 · %s"%("已完成" if boat_ready else "待完成"),15)
		for index in World.ISLAND_NOTES.PROJECTS.size():
			var status:="已完成" if (mask & (1<<index))!=0 else "待完成"
			Tasks.line(app,paper,"%s · %s"%[World.ISLAND_NOTES.PROJECTS[index],status],15)
		Tasks.line(app,paper,"共餐桌上有料理 · %s"%("已備妥" if story.get("meal",false) else "待準備"),15)
		Tasks.line(app,paper,"共餐桌三格內的燈飾 · %d／2"%mini(int(story.get("lights",0)),2),15)
		var start:Button=app.button("在公告板宣布開幕",func():app.session.perform("festival_story_open",BOARD))
		var can_start:bool=snapshot.get("can_start_large_projects",true)
		app.modal.set_meta("festival_opening",[story.duplicate(true),can_start])
		app.modal.set_meta("festival_from_journal",from_journal)
		start.disabled=not can_start or not boat_ready or mask!=World.ISLAND_NOTES.project_mask() or not story.get("meal",false) or int(story.get("lights",0))<2
		if not can_start:Tasks.line(app,paper,"開幕由島主或管理員宣布，所有島民都可以參與籌備。",15)
		start.name="FestivalOpen"
		body.add_child(start)
	if from_journal:
		body.add_child(app.button("返回居民回憶",Tasks.resident_memories.bind(app)))
	else:
		body.add_child(app.button("返回風鈴接力",festival_menu.bind(app)))

static func add_festival_food(app,body:VBoxContainer,snapshot:Dictionary)->void:
	if snapshot.get("region_id","home")!="home":return
	var table:=World.COMMUNITY.table_cell(snapshot)
	if table==World.COMMUNITY.NO_CELL:return
	var person:=Tasks.player(app)
	var near:=Vector2(person.get("x",0),person.get("y",0)).distance_to(Vector2(table)+Vector2(0.5,0.5))<=3.2
	var table_menu:=Tasks.card(body)
	Tasks.line(app,table_menu,"接力留餐",17)
	add_festival_dish(app,table_menu,snapshot,person,table,near,"watermelon","FestivalWatermelon","領一片")
	add_festival_dish(app,table_menu,snapshot,person,table,near,"hotpot","FestivalHotpot","領一碗")
	add_festival_dish(app,table_menu,snapshot,person,table,near,"chowder","FestivalChowder","領一碗")

static func add_festival_dish(app,body:VBoxContainer,snapshot:Dictionary,person:Dictionary,table:Vector2i,near:bool,dish:String,node_name:String,claim_text:String)->void:
	var platter:Dictionary=snapshot.community.get(dish,{})
	var portions:=int(platter.get("portions",0))
	var item:String=World.COMMUNITY.DISHES[dish]
	var row:=HBoxContainer.new()
	body.add_child(row)
	row.add_child(Shell.picture(Art.icon(item),32))
	var status:=app.label("%s · 桌上 %d 份"%[World.NAMES[item],portions],15) as Label
	status.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	row.add_child(status)
	var claimed:=bool(platter.get("claimed_own",false))
	var serving:=portions==0
	var action:=("serve_" if serving else "claim_")+dish
	var caption:="上桌四份" if serving else ("已領取" if claimed else claim_text)
	var button:Button=app.button(caption,func():app.session.perform(action,table);app._close_modal())
	button.name=node_name
	button.disabled=not near or (int(person.get("inventory",{}).get(item,0))<World.COMMUNITY.HOTPOT_PORTIONS if serving else claimed)
	if not near:button.tooltip_text="先走到渡口共餐桌旁"
	row.add_child(button)

static func livestock_menu(app,id:String)->void:
	var spec:Dictionary=World.LIVESTOCK.ANIMALS[id]
	var snapshot:Dictionary=app.session.snapshot
	var state:Dictionary=snapshot.get("livestock",{}).get(id,World.LIVESTOCK.fresh())
	var inventory:Dictionary=Tasks.player(app).get("inventory",{})
	var body:VBoxContainer=app._open_modal(spec.name+"的飼料站")
	app.modal.set_meta("life_modal_layout","livestock_card")
	if id=="cow":app.modal.set_meta("cow_care",true)
	add_animal_sketch(app,body,id,spec.cell)
	if id=="sheep" and int(Tasks.bond_view(app,"mianmian").get("stage",0))>=2:
		var corner:Button=app.button("雲朵羊的遮雨角落",Tasks.sheep_corner.bind(app))
		corner.name="SheepCorner"
		body.add_child(corner)
	var card:=Tasks.card(body)
	var row:=HBoxContainer.new()
	row.add_theme_constant_override("separation",16)
	card.add_child(row)
	var portrait:=Shell.picture(World.LIVESTOCK.Duck.texture() if id=="duck" else LivestockArt.texture(id,LivestockArt.state_for(state)),80)
	portrait.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	row.add_child(portrait)
	var details:=VBoxContainer.new()
	details.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	row.add_child(details)
	var product:String=World.NAMES[spec.item]
	Tasks.line(app,details,"飼料 %d／%d · 待領%s %d 份"%[state.feed,World.LIVESTOCK.LIMIT,product,state.ready],18)
	var status:="補充飼料後會開始生產。"
	if int(state.ready)>=World.LIVESTOCK.LIMIT:
		status="產物槽已滿，領取後會繼續生產。"
	elif float(state.next)>=0.0:
		var remaining:=maxi(0,ceili(float(state.next)-float(snapshot.get("time",0))))
		status="下次產出約 %d 遊戲小時後。"%ceili(float(remaining)*24.0/World.LIVESTOCK.DAY)
	var enclosed:=World.LIVESTOCK.pen_status(snapshot.get("objects",{}),id)
	var managed:bool=state.get("managed_pen",false)
	if managed and not enclosed:status="圈舍有缺口，已暫停生產。修好後會繼續。"
	Tasks.line(app,details,status,15)
	if id=="duck":Tasks.line(app,details,"花斑鴨會在河畔淺水游泳，鴨蛋在飼料站領取。",15)
	if id=="cow":
		var follow_status:=Tasks.line(app,details,"摸頭後，奶糖牛會在站旁慢慢跟幾步；牛奶仍在原飼料站領取。",15)
		follow_status.name="CowFollowStatus"
	Tasks.line(app,details,"親密度 %d／%d"%[int(state.get("bond",0)),World.LIVESTOCK.BOND_LIMIT],15)
	var personality:Dictionary=World.LIVESTOCK.PERSONALITIES[id]
	Tasks.line(app,details,"%s · %s"%[personality.traits,personality.favorite],15)
	var bonus:=int(state.get("bonus_progress",0))
	if int(state.get("bond",0))>=World.LIVESTOCK.BONUS_BOND:
		Tasks.line(app,details,"優良%s進度 %d／%d"%[product,bonus,World.LIVESTOCK.BONUS_INTERVAL],15)
	else:
		Tasks.line(app,details,"親密度達 %d 後，每 %d 次產出多得一份優良品。"%[World.LIVESTOCK.BONUS_BOND,World.LIVESTOCK.BONUS_INTERVAL],15)
	if int(state.get("ready_quality",0))>0:
		Tasks.line(app,details,"待領產物含優良%s %d 份。"%[product,int(state.ready_quality)],15)
	Tasks.line(app,card,"圈舍已圍好，可由木門進出。" if enclosed else "在飼料站四周圍上木牆並留木門，可做成圈舍。",15)
	var collector:=World.LIVESTOCK.collector_cell(id)
	var box:Dictionary=snapshot.get("objects",{}).get(World.key(collector),{})
	var collector_unlocked:bool=snapshot.get("flower_nursery",{}).get("garden",{}).get("complete",false)
	if state.has("collector"):
		var equipment_row:=HBoxContainer.new()
		card.add_child(equipment_row)
		var equipment:=Shell.picture(LivestockArt.collector_texture(int(state.collector),World.LIVESTOCK.COLLECTOR_CAPACITY),28)
		equipment.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
		equipment_row.add_child(equipment)
		Tasks.line(app,equipment_row,"畜牧收集器 · %s %d／%d"%[product,int(state.collector),World.LIVESTOCK.COLLECTOR_CAPACITY],15)
		if int(state.get("collector_quality",0))>0:
			Tasks.line(app,card,"收集器內含優良品 %d 份。"%int(state.collector_quality),15)
		if int(state.collector)>=World.LIVESTOCK.COLLECTOR_CAPACITY:
			Tasks.line(app,card,"收集器已滿，新的產物會暫留在飼料站。",15)
	elif box.get("type","")=="chest":
		Tasks.line(app,card,"自動收集已啟用 · 到%s側共用箱取%s。"%[World.LIVESTOCK.collector_side(id),product],15)
	else:
		Tasks.line(app,card,"在飼料站正%s方一格放共用箱，就能自動收集。"%World.LIVESTOCK.collector_side(id),15)
	var actions:=HFlowContainer.new()
	card.add_child(actions)
	if id=="sheep":
		actions.add_child(app.button("棉球兔的小窩",func():companion_menu(app)))
	if enclosed and not managed:
		actions.add_child(app.button("登記為生產圈舍",func():app.session.perform("livestock_pen",spec.cell,id);app._close_modal()))
	var pet:Button=app.button("摸摸"+str(spec.name),func():app.session.perform("livestock_pet",spec.cell,id);app._close_modal())
	pet.name="LivestockPet"
	pet.disabled=float(snapshot.get("time",0))-float(state.get("last_pet",-World.LIVESTOCK.PET_INTERVAL))<World.LIVESTOCK.PET_INTERVAL
	actions.add_child(pet)
	if id=="sheep":
		app.modal.set_meta("sheep_brushing",true)
		var brush:Button=app.button("替雲朵羊梳毛",func():app.session.perform("livestock_brush",spec.cell,id);app._close_modal())
		brush.name="SheepBrush"
		brush.icon=preload("res://assets/livestock/grooming-brush.png")
		brush.expand_icon=true
		brush.custom_minimum_size.x=174
		brush.add_theme_constant_override("icon_max_width",32)
		brush.disabled=pet.disabled
		brush.tooltip_text="與摸摸共用照料間隔，增加親密度；不會直接產出羊毛。"
		actions.add_child(brush)
	var feed:Button=app.button("補充一份飼料",func():app.session.perform("livestock_feed",spec.cell,id);app._close_modal())
	feed.name="LivestockFeed"
	feed.icon=Art.icon("feed")
	feed.disabled=int(inventory.get("feed",0))<1 or int(state.feed)>=World.LIVESTOCK.LIMIT
	actions.add_child(feed)
	var collect:Button=app.button("領取一份"+product,func():app.session.perform("livestock_collect",spec.cell,id);app._close_modal())
	collect.name="LivestockCollect"
	collect.icon=Art.icon(spec.item)
	collect.disabled=int(state.ready)<1
	actions.add_child(collect)
	if state.has("collector"):
		var empty:Button=app.button("取出收集器產物",func():app.session.perform("livestock_empty",spec.cell,id);app._close_modal())
		empty.disabled=int(state.collector)==0
		actions.add_child(empty)
	elif collector_unlocked:
		var cost_text:=PackedStringArray()
		for item:String in World.LIVESTOCK.COLLECTOR_COST:
			cost_text.append("%s %d"%[World.NAMES[item],World.LIVESTOCK.COLLECTOR_COST[item]])
		var install:Button=app.button("裝設收集器 · "+"、".join(cost_text),func():app.session.perform("livestock_install",spec.cell,id);app._close_modal())
		for item:String in World.LIVESTOCK.COLLECTOR_COST:
			if int(inventory.get(item,0))<int(World.LIVESTOCK.COLLECTOR_COST[item]):install.disabled=true
		actions.add_child(install)

static func companion_menu(app,kind:="rabbit") -> void:
	var cat:=kind=="cat"
	var dog:=kind=="dog"
	var species=World.Dog if dog else (World.Cat if cat else World.Rabbit)
	var name:String=species.NAME
	var prefix:=kind+"_"
	var body:VBoxContainer=app._open_modal(name+"的小窩")
	var pet:Dictionary=Tasks.player(app).get(species.FIELD,{})
	var card:=Tasks.card(body)
	Tasks.add_icon(card,World.Dog.texture(pet.get("last_play")=="toy") if dog else (World.Cat.texture() if cat else World.Rabbit.texture(0.0,true)),48)
	Tasks.line(app,card,"活潑・忠心 · 喜歡叼著布玩具散步" if dog else ("好奇・慢熟 · 喜歡追毛線球" if cat else "膽小・黏人 · 喜歡輕柔的撫摸"),17)
	var site:Vector2i=World.Cat.site(app.session.snapshot) if cat else World.LIVESTOCK.ANIMALS.sheep.cell
	if dog:site=World.Dog.SITE
	if pet.is_empty():
		Tasks.line(app,card,"小柴犬在牧場外等著一起去散步。" if dog else ("圍巾貓喜歡在老屋曬太陽，可以帶牠一起出門。" if cat else "牧場籃子裡有一隻棉球兔，可以帶牠一起出門。"),16)
		card.add_child(app.button("領養"+name,func():app.session.perform(prefix+"adopt",site);app._close_modal()))
		return
	var following:bool=pet.following
	var rest_place:="在牧場休息" if dog else ("在老屋休息" if cat else "在牧場的籃子裡休息")
	Tasks.line(app,card,"親密度 %d／%d · %s"%[int(pet.bond),World.Rabbit.MAX_BOND,"正在同行" if following else rest_place],16)
	card.add_child(app.button("回小窩休息" if following else "叫"+name+"同行",func():
		app.session.perform(prefix+("rest" if following else "follow"),site)
		app._close_modal()))
	card.add_child(app.button("打招呼" if cat else "摸摸"+name,func():app.session.perform(prefix+"pet",site);app._close_modal()))
	if cat:card.add_child(app.button("一起玩毛線球",func():app.session.perform("cat_yarn",site);app._close_modal()))
	if dog:
		card.add_child(app.button("給小柴犬布玩具",func():app.session.perform("dog_toy",site);app._close_modal()))
		if following:card.add_child(app.button("和小柴犬合照",dog_take_photo.bind(app)))
		if FileAccess.file_exists(dog_photo_path(app)):card.add_child(app.button("翻看柴犬合照",dog_view_photo.bind(app)))

static func deer_menu(app) -> void:
	var body:VBoxContainer=app._open_modal("風鈴樹下的來客")
	var card:=Tasks.card(body)
	Tasks.add_icon(card,World.Deer.texture(),72)
	Tasks.line(app,card,"安靜・親人 · 喜歡停在開花的風鈴樹旁",17)
	if Tasks.player(app).get("windbell_deer_seen",false):
		Tasks.line(app,card,"樹上小鈴響起時，風鈴鹿也會抬起頭。",16)
	else:
		Tasks.line(app,card,"風鈴鹿沿著燈光走到樹下，低頭嗅了嗅落在地上的花。",16)
		card.add_child(app.button("在樹旁停一會兒",func():
			app.session.perform(World.Deer.ACTION,World.Deer.site(app.session.snapshot))
			app._close_modal()))
	card.add_child(app.button("重看風鈴節尾聲",festival_story.bind(app,false,FESTIVAL_SCENES.size())))

static func seal_photo_path(app) -> String:
	return "user://shore-seal-%s.png"%str(app.session.own_id).sha256_text().left(24)

static func seal_menu(app) -> void:
	var body:VBoxContainer=app._open_modal("南岸的胖海豹")
	var snapshot:Dictionary=app.session.snapshot
	var now:=float(snapshot.time)
	var card:=Tasks.card(body)
	Tasks.add_icon(card,World.Seal.texture(),48)
	Tasks.line(app,card,"悠閒・怕吵 · 喜歡在退潮時曬太陽",17)
	if not World.Seal.present(now):
		Tasks.line(app,card,"漲潮時牠會游回外海。"+World.WANGAN_COAST.next_tide_text(now),16)
	elif not Tasks.player(app).get("seal_seen",false):
		Tasks.line(app,card,"牠趴在沙灘上。靠近岸邊，靜靜看看牠。",16)
		card.add_child(app.button("觀察胖海豹",func():
			app.session.perform(World.Seal.ACTION,World.Seal.SITE)
			app._close_modal()))
	else:
		Tasks.line(app,card,"胖海豹還在曬太陽，可以站在岸邊合照。",16)
		card.add_child(app.button("和胖海豹合照",seal_take_photo.bind(app)))
	if FileAccess.file_exists(seal_photo_path(app)):
		card.add_child(app.button("翻看海豹合照",show_wildlife_photo.bind(app,seal_photo_path(app),"南岸合照",seal_menu.bind(app))))

static func seal_take_photo(app) -> void:
	var snapshot:Dictionary=app.session.snapshot
	var player:=Tasks.player(app)
	var nearby:=Vector2(float(player.get("x",-100)),float(player.get("y",-100))).distance_to(Vector2(World.Seal.SITE)+Vector2(0.5,0.5))<=3.2
	if snapshot.get("region_id","home")!="home" or not nearby or not player.get("seal_seen",false) or not World.Seal.present(float(snapshot.time)):
		app._notice("退潮時到南岸，才能和胖海豹合照。",false)
		return
	app._close_modal()
	var saved:=await Tasks.capture_island_photo(app,seal_photo_path(app))
	app._notice("合照已收進胖海豹的觀察卡。" if saved else "合照無法儲存，請再試一次。",saved)

static func squirrel_menu(app) -> void:
	var body:VBoxContainer=app._open_modal("林邊的橡果松鼠")
	var viewer:=Tasks.player(app)
	var now:=float(app.session.snapshot.time)
	var card:=Tasks.card(body)
	Tasks.add_icon(card,World.Squirrel.texture(),48)
	Tasks.line(app,card,"靈巧・謹慎 · 喜歡收集橡果",17)
	if not World.Squirrel.present(now):
		Tasks.line(app,card,"牠會在 08:00–18:00 到林邊活動。",16)
		return
	var inventory:Dictionary=viewer.get("inventory",{})
	var observed:=World.Squirrel.observed(viewer,now)
	var observe:Button=app.button("今天已撿過橡果" if observed else "觀察松鼠",func():
		app.session.perform("squirrel_observe",World.Squirrel.SITE)
		app._close_modal())
	observe.disabled=observed
	card.add_child(observe)
	var nuts:=int(inventory.get(World.Squirrel.ACORN,0))
	Tasks.material_progress(app,card,World.Squirrel.ACORN,nuts,World.Squirrel.COST)
	var exchange:Button=app.button("換橡果掛飾",func():
		app.session.perform("squirrel_exchange",World.Squirrel.SITE)
		app._close_modal())
	exchange.icon=World.Squirrel.texture(World.Squirrel.KIT)
	exchange.disabled=nuts<World.Squirrel.COST
	card.add_child(exchange)
	Tasks.line(app,card,"在建造選單的家具頁可擺放掛飾。",15)

static func hedgehog_menu(app) -> void:
	var body:VBoxContainer=app._open_modal("庭院的蘑菇刺蝟")
	var snapshot:Dictionary=app.session.snapshot
	var viewer:=Tasks.player(app)
	var status:=World.Hedgehog.phase(viewer,float(snapshot.time))
	var card:=Tasks.card(body)
	Tasks.add_icon(card,World.Hedgehog.texture(false) if status in ["visiting","visited"] else Art.icon("radish"),48)
	Tasks.line(app,card,"膽小・貪吃 · 喜歡安靜地吃蘿蔔",17)
	var site:=World.Hedgehog.site(snapshot)
	match status:
		"empty":
			Tasks.line(app,card,"留一顆普通奶白蘿蔔，隔天 06:00–11:00 可以來觀察。",16)
			var button:Button=app.button("留一顆奶白蘿蔔",func():
				app.session.perform("hedgehog_leave_food",site)
				app._close_modal())
			button.disabled=int(viewer.get("inventory",{}).get("radish",0))<1
			card.add_child(button)
		"waiting":Tasks.line(app,card,"盤裡已有蘿蔔，明早 06:00 後再來看看。" if int(viewer.hedgehog_visit_day)>int(World.WEATHER.day_index(float(snapshot.time))) else "盤裡已有蘿蔔，今天 06:00 後再來看看。",16)
		"visiting":
			Tasks.line(app,card,"牠來了。蹲在旁邊看，牠就會慢慢放鬆。",16)
			card.add_child(app.button("靜靜觀察",func():app.session.perform("hedgehog_observe",site);app._close_modal()))
		"visited":Tasks.line(app,card,"今天已經觀察過牠。牠會在 11:00 回林邊。",16)
	if viewer.has("hedgehog_observed_day"):
		Tasks.line(app,card,"上次觀察 · 第 %d 日"%[int(viewer.hedgehog_observed_day)+1],15)

static func fox_menu(app) -> void:
	var body:VBoxContainer=app._open_modal("葉耳狐的足印小徑")
	var player:=Tasks.player(app)
	var pet:Dictionary=player.get(World.Fox.FIELD,{})
	var card:=Tasks.card(body)
	Tasks.add_icon(card,World.Fox.texture(),48)
	Tasks.line(app,card,"機警・好奇 · 喜歡找出採集線索",17)
	var choices:Array=[]
	if pet.is_empty():
		var tracks:=int(player.get("fox_tracks",0))
		if tracks==0:
			Tasks.line(app,card,"葉耳狐停在竹澗旁，像是在等你跟上牠。",16)
			choices.append(["沿著足印走","fox_track"])
		elif tracks==7:
			Tasks.line(app,card,"兩處足印都記下了。葉耳狐願意一起出門。",16)
			choices.append(["領養葉耳狐","fox_adopt"])
		else:
			Tasks.line(app,card,"到西北側茶圃旁與東南側溪岸找足印，走近按互動鍵記下。",16)
			Tasks.line(app,card,"已記錄 %d／2 處"%[int((tracks&2)!=0)+int((tracks&4)!=0)],15)
	else:
		var following:bool=pet.following
		Tasks.line(app,card,"親密度 %d／%d · %s"%[int(pet.bond),World.Rabbit.MAX_BOND,
			"正在同行" if following else "在霧竹溪谷休息"],16)
		choices.append(["回溪谷休息" if following else "叫葉耳狐同行","fox_rest" if following else "fox_follow"])
		choices.append(["摸摸葉耳狐","fox_pet"])
		var snapshot:Dictionary=app.session.snapshot
		if following and snapshot.get("region_id","home")=="home":
			choices.append(["尋找採集線索","fox_hint"])
			var clues:=World.Fox.visible_clues(World,snapshot,player)
			if not clues.is_empty():
				if clues.has(World.SEAWEED_CELL):Tasks.line(app,card,"海苔 · 望安南岸，沿河往南走到岸邊。",16)
				if clues.has(World.WANGAN_COAST.SHELL_CELL):Tasks.line(app,card,"潮紋貝殼 · 望安南岸沙灘，退潮時可撿。",16)
				card.add_child(app.button("在島嶼地圖查看",app._map_menu))
	for choice:Array in choices:
		card.add_child(app.button(choice[0],func():app.session.perform(choice[1],World.Fox.SITE);app._close_modal()))

static func dog_photo_path(app) -> String:
	return "user://companion-dog-%s.png"%str(app.session.own_id).sha256_text().left(24)

static func dog_take_photo(app) -> void:
	if not Tasks.player(app).get(World.Dog.FIELD,{}).get("following",false):return
	app._close_modal()
	var saved:=await Tasks.capture_island_photo(app,dog_photo_path(app))
	app._notice("合照已收進小柴犬的小窩。" if saved else "合照無法儲存，請再試一次。",saved)

static func dog_view_photo(app) -> void:
	show_wildlife_photo(app,dog_photo_path(app),"柴犬合照",func():companion_menu(app,"dog"))

static func show_wildlife_photo(app,path:String,title:String,back:Callable) -> void:
	var image:=Image.load_from_file(path)
	if image==null or image.is_empty():
		app._notice("找不到這張合照。",false)
		return
	var body:VBoxContainer=app._open_modal(title)
	var photo:=TextureRect.new()
	photo.texture=ImageTexture.create_from_image(image)
	photo.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	photo.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	photo.custom_minimum_size.y=270
	body.add_child(photo)
	body.add_child(app.button("回上一頁",back))

static func animal_menu(app) -> void:
	var body: VBoxContainer = app._open_modal("糯米雞的小小日常")
	app.modal.set_meta("life_modal_layout", "animal_card")
	add_animal_sketch(app,body,"chicken",World.CHICKEN_CELL)
	var animal: Dictionary = app.session.snapshot.get("animal", {})
	var message := World.chicken_status(animal,float(app.session.snapshot.time))
	var card := Tasks.card(body)
	Tasks.add_icon(card, sketch_icon("chicken"), 72)
	Tasks.line(app, card, message, 20)
	var personality:Dictionary=World.LIVESTOCK.PERSONALITIES.chicken
	Tasks.line(app,card,"%s · %s"%[personality.traits,personality.favorite],15)
	Tasks.material_progress(app, card, "feed", int(Tasks.player(app).get("inventory", {}).get("feed", 0)), 1)
	Tasks.line(app, card, "親密度 %d · 小麥 1、纖維 2 可在小石灶做四份飼料。" % animal.get("bond", 0), 15)
	if int(animal.get("bond",0))>=World.LIVESTOCK.BONUS_BOND:
		Tasks.line(app,card,"優良雞蛋進度 %d／%d"%[int(animal.get("bonus_progress",0)),World.LIVESTOCK.BONUS_INTERVAL],15)
	var actions := HFlowContainer.new()
	card.add_child(actions)
	for entry in [["pet", "摸摸糯米雞", ""], ["feed", "餵一份飼料", "feed"], ["egg", "收取雞蛋", "egg"]]:
		var action: String = entry[0]
		var button: Button = app.button(entry[1], func(): app.session.perform(action, Vector2i(45, 34)); app._close_modal())
		button.icon = Art.icon(entry[2])
		actions.add_child(button)
	add_chicken_cuddle(app,card)
	if animal.has("basket_eggs"):
		Tasks.material_progress(app, card, "egg", int(animal.basket_eggs), World.EGG_BASKET_CAPACITY)
		if int(animal.get("basket_eggs_quality",0))>0:
			Tasks.line(app,card,"收集籃內含優良雞蛋 %d 顆。"%int(animal.basket_eggs_quality),15)
	else:
		var install:Button=app.button("裝設收集籃",func():app.session.perform("install_egg_basket",World.CHICKEN_CELL);app._close_modal())
		install.disabled=int(Tasks.player(app).get("inventory",{}).get("egg_basket",0))<1
		card.add_child(install)
		Tasks.line(app, card, "在工作台用木材 8、纖維 6 製作收集籃。",15)
	Tasks.line(app, body, "沒餵食只會暫停產蛋，糯米雞不會餓死，也不會因離線討厭你。", 15)

static func add_chicken_cuddle(app,parent:Container)->void:
	var care:=World.CHICKEN_CUDDLE
	var s:Dictionary=app.session.snapshot
	var actor:=care.holder(s)
	var holding:bool=actor==app.session.own_id
	var button:Button=app.button("讓糯米雞回雞圈" if holding else "輕輕抱抱糯米雞",func():
		app.gather_hold.clear()
		app.session.perform(care.RELEASE if holding else care.ACTION,World.CHICKEN_CELL)
		app._close_modal())
	button.name="ChickenRelease" if holding else "ChickenHug"
	button.icon=sketch_icon("chicken")
	button.expand_icon=true
	button.add_theme_constant_override("icon_max_width",32)
	button.disabled=not holding and (not actor.is_empty() or float(s.get("time",0))-float(s.get("animal",{}).get("last_pet",-30))<care.COOLDOWN)
	button.tooltip_text="抱著散步八秒，或按互動鍵提早送回雞圈；與摸摸共用照料間隔，不占背包、不增加產蛋。"
	parent.add_child(button)

## T055 order board. Reads the self-only `order_board` snapshot built by
## World.order_board (Session never sends other players' books). Falls back to
## a local estimate (no greenhouse/stations) only if a snapshot lacks it.
static func order_board_view(app,dock:=false) -> Dictionary:
	var snapshot: Dictionary = app.session.snapshot
	var view: Variant = snapshot.get("dock_order_board" if dock else "order_board")
	if view is Dictionary and (view as Dictionary).get("rows") is Array:return view
	var now := float(snapshot.get("time", 0.0))
	var ctx := World.ORDER_CATALOG.make_context(World.ORDER_CATALOG.day_of(now), snapshot.get("board", false) == true,
		false, [], World.CROP_SEASONS)
	ctx.channel="dock" if dock else "village"
	ctx.star_shore=snapshot.get("wangan_star_walk",false)
	return World.ORDER_CATALOG.snapshot(Tasks.player(app).get("orders", {}), now, ctx)

static func order_status_text(row: Dictionary) -> String:
	match str(row.get("status", "")):
		"active":
			# One world day is Village.DAY (1440 s) = 24 world hours of 60 s.
			var hours := ceili(float(row.get("remaining", 0.0)) / 60.0)
			return "已接單 · 剩 %d 日 %d 時" % [floori(hours / 24.0), hours % 24]
		"done":return "✓ 今日已完成"
		"open":return "可接單 · %d 個世界日內交貨" % World.ORDER_CATALOG.DEADLINE_DAYS
	var missing: Array = row.get("missing", [])
	if missing.is_empty():return "今日未派發"
	return "今日未派發 · 目前取不到" + "、".join(PackedStringArray(missing.map(func(item): return str(World.NAMES.get(item, item)))))

static func orders_menu(app,dock:=false) -> void:
	var body: VBoxContainer = app._open_modal("望安碼頭訂單" if dock else "公告板的生活訂單")
	app.modal.set_meta("life_modal_layout", "orders_board")
	var view := order_board_view(app,dock)
	var delivery_cell:=World.WANGAN_COAST.DOCK_ORDERS if dock else BOARD
	var inventory: Dictionary = Tasks.player(app).get("inventory", {})
	Tasks.line(app, body, "第 %d 日 · 接單後 %d 個世界日內交貨；過期只會取消，材料留在背包、不扣鈴幣。無人在線時期限暫停。" %
		[int(view.get("day", 0)) + 1, int(view.get("deadline_days", World.ORDER_CATALOG.DEADLINE_DAYS))], 15)
	var expired: Array = view.get("expired", [])
	if not expired.is_empty():
		Tasks.line(app, body, "已過期取消：" + "、".join(PackedStringArray(expired.map(func(id): return str(World.ORDER_CATALOG.find(str(id)).get("name", id))))), 15)
	var board := GridContainer.new()
	board.columns = 2 if dock or app.font_scale_factor() >= 1.2 else 3
	board.add_theme_constant_override("h_separation", 12)
	body.add_child(board)
	for order: Dictionary in view.get("rows", []):
		var id: String = str(order.id)
		var status: String = str(order.get("status", "unavailable"))
		var paper := Tasks.card(board)
		if dock:paper.name="DockOrder_"+id
		paper.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var pin := ColorRect.new()
		pin.color = Color("9c5c42")
		pin.custom_minimum_size = Vector2(8, 8)
		pin.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		pin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		paper.add_child(pin)
		Tasks.add_icon(paper, Art.icon(order.items.keys()[0]), 48)
		Tasks.line(app, paper, order.name, 18)
		var enough := true
		for item in order.items:
			var have := int(inventory.get(item, 0))
			var need := int(order.items[item])
			enough = enough and have >= need
			var row := HBoxContainer.new()
			paper.add_child(row)
			Tasks.add_icon(row, Art.icon(item), 22)
			Tasks.line(app, row, "%s %d／%d" % [World.NAMES[item], have, need], 15)
		Tasks.line(app, paper, order_status_text(order), 14)
		var spacer := Control.new()
		spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
		paper.add_child(spacer)
		var footer := HBoxContainer.new()
		paper.add_child(footer)
		Tasks.line(app, footer, "%d 鈴幣" % order.coins, 15)
		if status in ["open", "active"]:
			var action := "order_accept" if status == "open" else "order_cancel"
			var toggle: Button = app.button("接單" if status == "open" else "取消",
				func(): app.session.perform(action, delivery_cell, id); app._close_modal())
			toggle.name = "OrderAccept" if status == "open" else "OrderCancel"
			footer.add_child(toggle)
		var submit: Button = app.button("✓ 已完成" if status == "done" else "交件",
			func(): app.session.perform("order", delivery_cell, id); app._close_modal())
		submit.name = "OrderDeliver"
		submit.disabled = status != "active" or not enough
		if status == "open":submit.tooltip_text = "先接單再交件"
		footer.add_child(submit)
