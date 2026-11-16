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
	var categories := ["里程碑", "菜園", "魚類", "料理"]
	for index in categories.size():
		var page := VBoxContainer.new()
		page.visible = index == initial_tab
		body.add_child(page)
		pages.append(page)
		var tab: Button = app.button(categories[index], func():
			for page_index in pages.size():
				pages[page_index].visible = page_index == index
		)
		tab.toggle_mode = true
		tab.icon = Art.icon(["coins", "radish", "carp", "soup"][index])
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
	var keys := ["crops", "fish", "meals"]
	var catalogs := [World.CROPS, World.FISH, World.RECIPES]
	var observation:=World.Collections.angling_level(person)
	Tasks.line(app,pages[2],"漁獵觀察 %d 級 · 三級解鎖水域線索，六級解鎖北門釣點預報。" % observation,15)
	Tasks.line(app,pages[2],"北門東岸釣點 · 北側碼頭水面夜釣月光小魷，南側潮池全天可釣金邊蝦。",15)
	Tasks.line(app,pages[2],"礁溪暖泉溪 · 白天可釣玻璃小蝦；冬季到高地冷泉找雪點鱒魚。",15)
	for water in Collections.RARE_WATERS.values():
		Tasks.line(app,pages[2],"%s · %s · 保底進度 %d／%d" % [World.FISH[water.fish].name,water.hint,int(person.get(water.counter,0)),Collections.RARE_FISH_LIMIT],15)
	for index in keys.size():
		var grid := GridContainer.new()
		grid.columns = 3
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
			var field:String=keys[index]+"_discoveries"
			var first:Dictionary=app.session.snapshot.get("island_"+field,{}).get(id,{})
			if not first.is_empty():
				Tasks.line(app,cell,"全島首位 %s・%s" % [first.name,discovery_location(first)],13)
			var discovery:Dictionary=person.get(field,{}).get(id,{})
			if not discovery.is_empty():
				Tasks.line(app,cell,"個人首次 "+discovery_location(discovery),13)
	Tasks.line(app, body, "記錄親手採收、釣到與領取的料理。出售或使用後仍保留，舊背包不會自動算入。", 15)

static func sketch_icon(kind:String) -> Texture2D:
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

static func discovery_location(discovery:Dictionary) -> String:
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
	var body:VBoxContainer=app._open_modal("給大家的風鈴節")
	app.modal.set_meta("life_modal_layout","community_board")
	var story:Dictionary=app.session.snapshot.get("festival_story",{})
	var paper:=Tasks.card(body)
	if story.get("opened",false):
		var scene:Array=FESTIVAL_SCENES[scene_index]
		Tasks.portrait_header(app,paper,scene[0],"",80)
		Tasks.line(app,paper,"「%s」"%scene[2],18)
		var pages:=HBoxContainer.new()
		body.add_child(pages)
		if scene_index>0:pages.add_child(app.button("上一幕",festival_story.bind(app,from_journal,scene_index-1)))
		if scene_index+1<FESTIVAL_SCENES.size():pages.add_child(app.button("下一幕",festival_story.bind(app,from_journal,scene_index+1)))
	else:
		var mask:=int(story.get("projects",0))
		var boat_ready:bool=story.get("boat_ready",false)
		Tasks.line(app,paper,"第四章・碼頭與小船 · %s"%("已完成" if boat_ready else "待完成"),15)
		for index in World.ISLAND_NOTES.PROJECTS.size():
			var status:="已完成" if (mask & (1<<index))!=0 else "待完成"
			Tasks.line(app,paper,"%s · %s"%[World.ISLAND_NOTES.PROJECTS[index],status],15)
		Tasks.line(app,paper,"共餐桌上有料理 · %s"%("已備妥" if story.get("meal",false) else "待準備"),15)
		Tasks.line(app,paper,"共餐桌三格內的燈飾 · %d／2"%mini(int(story.get("lights",0)),2),15)
		app.modal.set_meta("festival_opening",story.duplicate(true))
		var start:Button=app.button("在公告板宣布開幕",func():app.session.perform("festival_story_open",BOARD))
		start.disabled=not boat_ready or mask!=World.ISLAND_NOTES.project_mask() or not story.get("meal",false) or int(story.get("lights",0))<2
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
	add_animal_sketch(app,body,id,spec.cell)
	var card:=Tasks.card(body)
	var row:=HBoxContainer.new()
	row.add_theme_constant_override("separation",16)
	card.add_child(row)
	var portrait:=Shell.picture(LivestockArt.texture(id,LivestockArt.state_for(state)),80)
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
	Tasks.line(app,details,"親密度 %d／%d"%[int(state.get("bond",0)),World.LIVESTOCK.BOND_LIMIT],15)
	var bonus:=int(state.get("bonus_progress",0))
	if int(state.get("bond",0))>=World.LIVESTOCK.BONUS_BOND:
		Tasks.line(app,details,"額外產物 %d／%d"%[bonus,World.LIVESTOCK.BONUS_INTERVAL],15)
	else:
		Tasks.line(app,details,"親密度達 %d 後，每 %d 次產出多得一份。"%[World.LIVESTOCK.BONUS_BOND,World.LIVESTOCK.BONUS_INTERVAL],15)
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
		if int(state.collector)>=World.LIVESTOCK.COLLECTOR_CAPACITY:
			Tasks.line(app,card,"收集器已滿，新的產物會暫留在飼料站。",15)
	elif box.get("type","")=="chest":
		Tasks.line(app,card,"自動收集已啟用 · 到南側共用箱取%s。"%product,15)
	else:
		Tasks.line(app,card,"在飼料站正南方一格放共用箱，就能自動收集。",15)
	var actions:=HFlowContainer.new()
	card.add_child(actions)
	if enclosed and not managed:
		actions.add_child(app.button("登記為生產圈舍",func():app.session.perform("livestock_pen",spec.cell,id);app._close_modal()))
	var pet:Button=app.button("摸摸"+str(spec.name),func():app.session.perform("livestock_pet",spec.cell,id);app._close_modal())
	pet.disabled=float(snapshot.get("time",0))-float(state.get("last_pet",-World.LIVESTOCK.PET_INTERVAL))<World.LIVESTOCK.PET_INTERVAL
	actions.add_child(pet)
	var feed:Button=app.button("補充一份飼料",func():app.session.perform("livestock_feed",spec.cell,id);app._close_modal())
	feed.icon=Art.icon("feed")
	feed.disabled=int(inventory.get("feed",0))<1 or int(state.feed)>=World.LIVESTOCK.LIMIT
	actions.add_child(feed)
	var collect:Button=app.button("領取一份"+product,func():app.session.perform("livestock_collect",spec.cell,id);app._close_modal())
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

static func animal_menu(app) -> void:
	var body: VBoxContainer = app._open_modal("糯米雞的小小日常")
	app.modal.set_meta("life_modal_layout", "animal_card")
	add_animal_sketch(app,body,"chicken",World.CHICKEN_CELL)
	var animal: Dictionary = app.session.snapshot.get("animal", {})
	var message := World.chicken_status(animal,float(app.session.snapshot.time))
	var card := Tasks.card(body)
	Tasks.add_icon(card, Art.icon("egg"), 72)
	Tasks.line(app, card, message, 20)
	Tasks.material_progress(app, card, "feed", int(Tasks.player(app).get("inventory", {}).get("feed", 0)), 1)
	Tasks.line(app, card, "親密度 %d · 小麥 1、纖維 2 可在小石灶做四份飼料。" % animal.get("bond", 0), 15)
	var actions := HBoxContainer.new()
	card.add_child(actions)
	for entry in [["pet", "摸摸糯米雞", ""], ["feed", "餵一份飼料", "feed"], ["egg", "收取雞蛋", "egg"]]:
		var action: String = entry[0]
		var button: Button = app.button(entry[1], func(): app.session.perform(action, Vector2i(45, 34)); app._close_modal())
		button.icon = Art.icon(entry[2])
		actions.add_child(button)
	if animal.has("basket_eggs"):
		Tasks.material_progress(app, card, "egg", int(animal.basket_eggs), World.EGG_BASKET_CAPACITY)
	else:
		var install:Button=app.button("裝設收集籃",func():app.session.perform("install_egg_basket",World.CHICKEN_CELL);app._close_modal())
		install.disabled=int(Tasks.player(app).get("inventory",{}).get("egg_basket",0))<1
		card.add_child(install)
		Tasks.line(app, card, "在工作台用木材 8、纖維 6 製作收集籃。",15)
	Tasks.line(app, body, "沒餵食只會暫停產蛋，糯米雞不會餓死，也不會因離線討厭你。", 15)

## T055 order board. Reads the self-only `order_board` snapshot built by
## World.order_board (Session never sends other players' books). Falls back to
## a local estimate (no greenhouse/stations) only if a snapshot lacks it.
static func order_board_view(app) -> Dictionary:
	var snapshot: Dictionary = app.session.snapshot
	var view: Variant = snapshot.get("order_board")
	if view is Dictionary and (view as Dictionary).get("rows") is Array:return view
	var now := float(snapshot.get("time", 0.0))
	var ctx := World.ORDER_CATALOG.make_context(World.ORDER_CATALOG.day_of(now), snapshot.get("board", false) == true,
		false, [], World.CROP_SEASONS)
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

static func orders_menu(app) -> void:
	var body: VBoxContainer = app._open_modal("公告板的生活訂單")
	app.modal.set_meta("life_modal_layout", "orders_board")
	var view := order_board_view(app)
	var inventory: Dictionary = Tasks.player(app).get("inventory", {})
	Tasks.line(app, body, "第 %d 日 · 接單後 %d 個世界日內交貨；過期只會取消，材料留在背包、不扣鈴幣。無人在線時期限暫停。" %
		[int(view.get("day", 0)) + 1, int(view.get("deadline_days", World.ORDER_CATALOG.DEADLINE_DAYS))], 15)
	var expired: Array = view.get("expired", [])
	if not expired.is_empty():
		Tasks.line(app, body, "已過期取消：" + "、".join(PackedStringArray(expired.map(func(id): return str(World.ORDER_CATALOG.find(str(id)).get("name", id))))), 15)
	var board := GridContainer.new()
	board.columns = 3
	board.add_theme_constant_override("h_separation", 12)
	body.add_child(board)
	for order: Dictionary in view.get("rows", []):
		var id: String = str(order.id)
		var status: String = str(order.get("status", "unavailable"))
		var paper := Tasks.card(board)
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
				func(): app.session.perform(action, BOARD, id); app._close_modal())
			toggle.name = "OrderAccept" if status == "open" else "OrderCancel"
			footer.add_child(toggle)
		var submit: Button = app.button("✓ 已完成" if status == "done" else "交件",
			func(): app.session.perform("order", BOARD, id); app._close_modal())
		submit.name = "OrderDeliver"
		submit.disabled = status != "active" or not enough
		if status == "open":submit.tooltip_text = "先接單再交件"
		footer.add_child(submit)
