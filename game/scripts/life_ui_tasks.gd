extends RefCounted

const World=preload("res://scripts/world.gd")
const ToolFeedback=preload("res://scripts/tool_action_feedback.gd")
const Village=World.Village
const Art=preload("res://scripts/life_ui_theme.gd")
const Shell=preload("res://scripts/life_ui_shell.gd")
const ItemArt=preload("res://scripts/inventory_item_art.gd")
const HouseUI=preload("res://scripts/house_ui.gd")
const PixelTheme=preload("res://scripts/inventory_pixel_theme.gd")
const KitchenUI=preload("res://scripts/public_kitchen_ui.gd")
const SpringGardenUI=preload("res://scripts/spring_garden_ui.gd")
const SeaFairUI=preload("res://scripts/sea_breeze_fair_ui.gd")
const AutumnFeastUI=preload("res://scripts/autumn_feast_ui.gd")
const WarmNightUI=preload("res://scripts/warm_lantern_night_ui.gd")
const ResidentStories=preload("res://scripts/resident_story_catalog.gd")
const BoboRockGuide=preload("res://scripts/bobo_rock_guide.gd")
const BoboRestBoxPattern=preload("res://scripts/bobo_rest_box_pattern.gd")
const MianmianAnimalNotes=preload("res://scripts/mianmian_animal_notes.gd")
const MianmianToyPage=preload("res://scripts/mianmian_toy_page.gd")
const MianmianCareJournal=preload("res://scripts/mianmian_care_journal.gd")
const ChachaTeaPattern=preload("res://scripts/chacha_tea_pattern.gd")
const AruFirstFurniture=preload("res://scripts/aru_first_furniture.gd")
const MiluFirstSoup=preload("res://scripts/milu_first_soup.gd")
const MiluRecipePages=preload("res://scripts/milu_recipe_pages.gd")
const MiluTasting=preload("res://scripts/milu_tasting.gd")
const MiluSupper=preload("res://scripts/milu_supper_ui.gd")
const XingheGrowth=preload("res://scripts/xinghe_growth_notebook.gd")
const ChachaCurtainInspection=preload("res://scripts/chacha_curtain_inspection.gd")
const AruBenchInspection=preload("res://scripts/aru_bench_inspection.gd")
const AruRest=preload("res://scripts/aru_rest.gd")
const AruParkPhoto=preload("res://scripts/aru_park_photo.gd")
const ChachaCurtainReward=preload("res://scripts/chacha_curtain_reward.gd")
const ChachaTeaGathering=preload("res://scripts/chacha_tea_gathering.gd")
const ChachaHandwrittenMenu=preload("res://scripts/chacha_handwritten_menu.gd")
const AchaoKnotArt=preload("res://scripts/achao_knot_art.gd")
const AchaoKnotMemory=preload("res://scripts/achao_knot_memory.gd")
const AchaoVoyageReward=preload("res://scripts/achao_voyage_reward.gd")
const AchaoVoyageAlbum=preload("res://scripts/achao_voyage_album.gd")
const LingpopoBellScene=preload("res://scripts/lingpopo_bell_scene.gd")
const LuoluoLetterScene=preload("res://scripts/luoluo_letter_scene.gd")
const LuoluoCap=preload("res://scripts/luoluo_courier_cap_art.gd")
const DiandianPose=preload("res://scripts/diandian_pose_art.gd")
const XiaoliSiteChart=preload("res://scripts/xiaoli_site_chart.gd")
const XiaoliReturnGuest=preload("res://scripts/xiaoli_return_guest_art.gd")
const XiaoliShopArt=preload("res://scripts/xiaoli_shop_art.gd")
const MarketDecorArt=preload("res://scripts/market_decor_art.gd")
const Bond=World.RESIDENT_BOND
const Goals=World.RESIDENT_GOALS
const MillRestoration=World.MILL_RESTORATION
const BOARD_CELL:=Vector2i(40,29)

static func journal(app,selected_id:String="") -> void:
	if selected_id=="north":preload("res://scripts/station_life_ui.gd").memory(app);return
	if selected_id=="history":app._history_menu();return
	var col:VBoxContainer=app._open_modal("島民手冊  %s"%app.binding_label("journal"))
	app.modal.set_meta("life_modal_layout","resident_journal")
	app.modal.add_theme_stylebox_override("panel",StyleBoxEmpty.new())
	var scroll:Control=col.get_parent()
	for chrome in scroll.get_parent().get_children():
		if chrome!=scroll:
			chrome.hide()
	var person:Dictionary=player(app)
	var cover:=PanelContainer.new()
	cover.custom_minimum_size.y=540
	var leather:=StyleBoxTexture.new()
	leather.texture=preload("res://assets/ui-life/book.png")
	leather.set_content_margin(SIDE_LEFT,48)
	leather.set_content_margin(SIDE_RIGHT,48)
	leather.set_content_margin(SIDE_TOP,36)
	leather.set_content_margin(SIDE_BOTTOM,112)
	cover.add_theme_stylebox_override("panel",leather)
	cover.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	col.add_child(cover)
	var book:=HBoxContainer.new()
	book.add_theme_constant_override("separation",48)
	cover.add_child(book)
	var index_paper:=VBoxContainer.new()
	index_paper.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	index_paper.size_flags_stretch_ratio=0.36
	book.add_child(index_paper)
	line(app,index_paper,"島民手冊  %s"%app.binding_label("journal"),24)
	var bookmarks:=VBoxContainer.new()
	index_paper.add_child(bookmarks)
	var right_page:=VBoxContainer.new()
	right_page.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	right_page.size_flags_stretch_ratio=0.64
	book.add_child(right_page)
	var close:Button=app.button("關閉  Esc",app._close_modal)
	close.size_flags_horizontal=Control.SIZE_SHRINK_END
	var book_actions:=HBoxContainer.new()
	book_actions.alignment=BoxContainer.ALIGNMENT_END
	right_page.add_child(book_actions)
	var north:Button=app.button("三站便箋",func():preload("res://scripts/station_life_ui.gd").memory(app))
	north.name="NorthJourneyBookmark"
	north.icon=preload("res://scripts/life_ui_shell.gd").icon("letter")
	north.expand_icon=true;north.add_theme_constant_override("icon_max_width",24)
	book_actions.add_child(north)
	# Shared meal memories: read-only replay for every member, including late joiners.
	var kitchen:Button=app.button("共餐記憶",func():KitchenUI.open(app,"story"))
	kitchen.name="KitchenMemoryBookmark"
	kitchen.icon=KitchenUI.stove_icon()
	kitchen.expand_icon=true;kitchen.add_theme_constant_override("icon_max_width",24)
	kitchen.disabled=not bool(app.session.snapshot.get("picnic",false))
	kitchen.tooltip_text="渡口野餐之後才有共餐記憶" if kitchen.disabled else "重看渡口共餐與公共廚房的故事"
	book_actions.add_child(kitchen)
	var memories:Button=app.button("居民回憶",resident_memories.bind(app))
	memories.name="ResidentMemories"
	bookmarks.add_child(memories)
	var skills_button:Button=app.button("生活技能",skill_book.bind(app))
	skills_button.name="IslandSkillBook"
	bookmarks.add_child(skills_button)
	if ChachaHandwrittenMenu.available(app.session.snapshot):
		var menu:Button=app.button("茶茶手寫茶單",ChachaHandwrittenMenu.open.bind(app,journal.bind(app,""),"返回手帳"))
		menu.name="ChachaMenuBookmark"
		bookmarks.add_child(menu)
	if AruFirstFurniture.available(app.session.snapshot):
		var furniture:Button=app.button("原木床桌椅基礎圖樣",AruFirstFurniture.open.bind(app,journal.bind(app,""),"返回手帳"))
		furniture.name="AruFirstFurnitureBookmark"
		bookmarks.add_child(furniture)
	if MiluFirstSoup.event_state(app.session.snapshot)=="done":
		var first_soup:Button=app.button("米露的第一碗湯",MiluFirstSoup.open.bind(app,journal.bind(app,""),"返回手帳"))
		first_soup.name="MiluFirstSoupBookmark"
		bookmarks.add_child(first_soup)
	if int(bond_view(app,"milu").get("stage",0))>=2:
		var recipe:Button=app.button("米露的共餐桌手記" if MiluRecipePages.completed(app.session.snapshot) else "米露的食譜線索",MiluRecipePages.open.bind(app,journal.bind(app,""),"返回手帳"))
		recipe.name="MiluRecipeBookmark"
		bookmarks.add_child(recipe)
	if not MiluTasting.completed_dish(app.session.snapshot).is_empty():
		var tasting:Button=app.button("米露的試吃會",MiluTasting.open.bind(app,journal.bind(app,""),"返回手帳"))
		tasting.name="MiluTastingBookmark"
		bookmarks.add_child(tasting)
	if MiluSupper.done(app.session.snapshot):
		var supper:Button=app.button("米露的共餐食譜",MiluSupper.open_book.bind(app,journal.bind(app,""),"返回手帳"))
		supper.name="MiluSupperBookmark"
		bookmarks.add_child(supper)
	if app.session.snapshot.has(Goals.MURAL_KEY):
		bookmarks.add_child(app.button("全島合畫",public_mural.bind(app)))
	if painting_available(app):
		var painting:Button=app.button(painting_label(app),painting_book.bind(app,journal.bind(app,"")))
		painting.name="DiandianPaintingBookmark"
		bookmarks.add_child(painting)
	if int(bond_view(app,"diandian").get("stage",0))>=1:
		var sketchbook:Button=app.button("點點的速寫簿",diandian_sketchbook.bind(app,journal.bind(app,"")))
		sketchbook.name="DiandianSketchBookmark"
		bookmarks.add_child(sketchbook)
	if XingheGrowth.available(app.session.snapshot):
		var growth:Button=app.button("星禾的作物觀察簿",growth_book.bind(app,journal.bind(app,""),"返回手帳"))
		growth.name="XingheGrowthBookmark"
		bookmarks.add_child(growth)
	if int(app.session.snapshot.get("own_luoluo_address",0))>0:
		bookmarks.add_child(app.button("洛洛的信封",address_letter.bind(app)))
	if str(goal_state(app,"luoluo",2).get("state","locked")) in ["open","done"]:
		var clues:Button=app.button("無址信的訪談簿",postcard_notebook.bind(app,journal.bind(app,"")))
		clues.name="LuoluoPostcardBookmark"
		bookmarks.add_child(clues)
	if goal_state(app,"luoluo",3).get("state")=="done":
		var letter:Button=app.button("洛洛的回憶信",luoluo_memory_letter.bind(app,journal.bind(app,"")))
		letter.name="LuoluoMemoryBookmark"
		bookmarks.add_child(letter)
	if goal_state(app,"luoluo",4).get("state")=="done":
		var private_book:Button=app.button("個人回憶冊",luoluo_future_book.bind(app,journal.bind(app,"")))
		private_book.name="LuoluoFutureBookmark"
		bookmarks.add_child(private_book)
	add_bell_history_bookmark(app,bookmarks)
	var news:Button=app.button("島嶼近況",island_news.bind(app))
	news.name="IslandNews"
	bookmarks.add_child(news)
	var route:Button=app.button("五章故事",story_route.bind(app))
	route.name="StoryRouteBookmark"
	bookmarks.add_child(route)
	if app.session.snapshot.get("board",false):
		var orders:Button=app.button("我的訂單簿",app.OrderJournal.open.bind(app))
		orders.name="ActiveOrderJournal"
		bookmarks.add_child(orders)
	book_actions.add_child(close)
	var farming:=HBoxContainer.new()
	farming.add_theme_constant_override("separation",8)
	right_page.add_child(farming)
	add_icon(farming,ItemArt.icon("wheat"),24)
	var level:=World.farming_level(person)
	var farming_text:="農耕  %d 級"%level
	if level<World.FARMING_LEVEL_THRESHOLDS.size():
		farming_text+="  ·  %d／%d 經驗"%[int(person.get("harvests",0)),World.FARMING_LEVEL_THRESHOLDS[level]]
	farming.add_child(app.label(farming_text,15))
	var care:=int(person.get("crop_care",0))
	line(app,right_page,"作物照料 %d／%d · %s"%[care,World.CROP_CATALOG.CARE_TARGET,
		"下次可多收一件優良作物" if care>=World.CROP_CATALOG.CARE_TARGET else "手動替自家乾燥的生長作物澆水"],15)
	line(app,right_page,"土壤肥力 · 同一格田連著換種兩次，收成會多一件優良作物。",15)
	var angling:=HBoxContainer.new()
	angling.add_theme_constant_override("separation",8)
	right_page.add_child(angling)
	add_icon(angling,ItemArt.icon("minnow"),24)
	var angling_level:=World.Collections.angling_level(person)
	var angling_text:="漁獵觀察  %d 級"%angling_level
	if angling_level<World.Collections.ANGLING_THRESHOLDS.size():
		angling_text+="  ·  %d／%d 經驗"%[int(person.get("fish_caught",0)),World.Collections.ANGLING_THRESHOLDS[angling_level]]
	angling.add_child(app.label(angling_text,15))
	var gathering:=HBoxContainer.new()
	gathering.add_theme_constant_override("separation",8)
	right_page.add_child(gathering)
	add_icon(gathering,ItemArt.icon("sapling"),24)
	var gathering_level:=World.gathering_level(person)
	var gathering_text:="採集  %d 級"%gathering_level
	if gathering_level<World.GATHERING_LEVEL_THRESHOLDS.size():
		gathering_text+="  ·  %d／%d 經驗"%[int(person.get("gathering_points",0)),World.GATHERING_LEVEL_THRESHOLDS[gathering_level]]
	gathering.add_child(app.label(gathering_text,15))
	var crafting:=HBoxContainer.new()
	crafting.add_theme_constant_override("separation",8)
	right_page.add_child(crafting)
	add_icon(crafting,ItemArt.icon("plank"),24)
	var crafting_level:=World.crafting_level(person)
	var crafting_text:="手作  %d 級"%crafting_level
	if crafting_level<World.CRAFTING_LEVEL_THRESHOLDS.size():
		crafting_text+="  ·  %d／%d 經驗"%[int(person.get("crafting_points",0)),World.CRAFTING_LEVEL_THRESHOLDS[crafting_level]]
	crafting.add_child(app.label(crafting_text,15))
	var exploration_points:=int(person.get("exploration_points",0))
	var exploration_level:=World.exploration_level(exploration_points)
	var exploration_text:="探索  %d 級"%exploration_level
	if exploration_level<World.EXPLORATION_LEVEL_THRESHOLDS.size():
		exploration_text+="  ·  %d／%d 地區"%[exploration_points,World.EXPLORATION_LEVEL_THRESHOLDS[exploration_level]]
	right_page.add_child(app.label(exploration_text,15))
	crafting.tooltip_text="手作三級可保存 16×16 格藍圖，六級可成片施工 49 格。"
	gathering.tooltip_text="三級回收自種成熟樹苗，六級在周邊地圖看採集標記。"
	var page:=VBoxContainer.new()
	right_page.add_child(page)
	var index_details:=VBoxContainer.new()
	var group:=ButtonGroup.new()
	if not Village.NPCS.has(selected_id) and selected_id not in ["xinghe","history","salt_worker"]:selected_id="aru"
	if selected_id=="salt_worker" and not salt_complete(app):selected_id="aru"
	for id in ["aru","milu","xiaoli","bobo"]:
		var display_name:String="波波・金瓜石" if id=="bobo" else Village.NPCS[id].name
		var bookmark:Button=app.button("%s  %d／%d"%[display_name,story_stage(person,id),Village.QUESTS[id].size()],
			journal_page.bind(app,page,index_details,id,person))
		bookmark.icon=Art.icon(id)
		bookmark.expand_icon=true
		bookmark.add_theme_constant_override("icon_max_width",36)
		bookmark.toggle_mode=true
		bookmark.button_group=group
		bookmarks.add_child(bookmark)
		bookmark.set_pressed_no_signal(id==selected_id)
		if id=="bobo":bookmark.name="BoboBookmark"
	var gardener:Button=app.button("星禾・蘭陽",journal_page.bind(app,page,index_details,"xinghe",person))
	gardener.icon=preload("res://scripts/lanyang_life_art.gd").portrait()
	gardener.expand_icon=true
	gardener.add_theme_constant_override("icon_max_width",36)
	gardener.toggle_mode=true;gardener.button_group=group
	gardener.name="XingheBookmark"
	bookmarks.add_child(gardener)
	gardener.set_pressed_no_signal(selected_id=="xinghe")
	var history:Button=app.button("地方記憶・宜蘭",app._history_menu)
	history.icon=preload("res://scripts/life_ui_shell.gd").icon("journal")
	history.expand_icon=true;history.add_theme_constant_override("icon_max_width",32)
	bookmarks.add_child(history)
	salt_bookmarks(app,bookmarks,page,index_details,person,group,selected_id)
	index_paper.add_child(HSeparator.new())
	index_paper.add_child(index_details)
	journal_page(app,page,index_details,selected_id,person)

static func unread_projects(news:Dictionary) -> int:
	return int(news.get("completed",0)) & ~int(news.get("seen",0))

static func has_return_news(snapshot:Dictionary) -> bool:
	var news:Dictionary=snapshot.get("island_news",{})
	return unread_projects(news)!=0 or int(news.get("notes_unread",0))>0 \
		or bool(snapshot.get("ferry_story_recap",{}).get("has_news",false)) \
		or int(snapshot.get("own_crop_summary",{}).get("ready",0))>0

static func return_news(app,snapshot:Dictionary) -> void:
	var body:VBoxContainer=app._open_modal("歡迎回島")
	app.modal.set_meta("life_modal_layout","return_news")
	var news:Dictionary=snapshot.island_news
	var unread:=unread_projects(news)
	var projects:=PackedStringArray()
	var names:=World.ISLAND_NOTES.news_project_names()
	for index in names.size():
		if (unread & (1<<index))!=0:projects.append(names[index])
	var paper:=card(body)
	if not projects.is_empty():
		var project_summary:="、".join(projects.slice(0,3))
		if projects.size()>3:project_summary+="等 %d 項"%projects.size()
		line(app,paper,"工程完成 · "+project_summary,16)
	var notes:=int(news.get("notes_unread",0))
	if notes>0:line(app,paper,"留言板 · %d 則未讀"%notes,16)
	var crops:Dictionary=snapshot.get("own_crop_summary",{})
	line(app,paper,"我的農田 · %d 格可收成，%d 格生長中"%[crops.get("ready",0),crops.get("growing",0)],16)
	var recap:Dictionary=snapshot.get("ferry_story_recap",{})
	if recap.get("has_news",false):line(app,paper,str(recap.get("headline","渡口有新消息")),16)
	var links:=HFlowContainer.new()
	links.add_theme_constant_override("h_separation",10)
	links.add_theme_constant_override("v_separation",6)
	body.add_child(links)
	links.add_child(app.button("島嶼近況",island_news.bind(app)))
	if notes>0:links.add_child(app.button("讀留言",island_notes.bind(app)))
	var memories:Array=snapshot.get("resident_memories",[])
	if not memories.is_empty():
		links.add_child(app.button("重看故事",resident_memories.bind(app)))
	if snapshot.get("festival_story",{}).get("opened",false):
		links.add_child(app.button("重看風鈴節開幕",app.LifeAlmanac.festival_story.bind(app,true,0,func():return_news(app,app.session.snapshot),"返回回島近況")))
	app._layout_preview.call_deferred()

static func story_route(app) -> void:
	var body:VBoxContainer=app._open_modal("五章故事")
	app.modal.set_meta("life_modal_layout","chapter_letter")
	var shell=preload("res://scripts/life_ui_shell.gd")
	var titles:=["有燈的渡口","飯香與屋簷","重新運轉的工坊","群島的來信","風鈴節"]
	var chapters:=["第一章","第二章","第三章","第四章","第五章"]
	var icons:=["home","harvest","pick","letter","bell"]
	var rows:Array[Label]=[]
	var paper:=card(body)
	for index in titles.size():
		var row:=HBoxContainer.new()
		row.add_theme_constant_override("separation",12)
		paper.add_child(row)
		add_icon(row,shell.icon(icons[index]),32)
		var title:=line(app,row,"%s・%s"%[chapters[index],titles[index]],18)
		title.size_flags_stretch_ratio=0.9
		title.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
		var status:=line(app,row,"",15)
		status.size_flags_stretch_ratio=1.1
		status.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
		status.name="StoryRouteStatus%d"%index
		rows.append(status)
		if index<titles.size()-1:paper.add_child(HSeparator.new())
	var actions:=HFlowContainer.new()
	actions.add_theme_constant_override("h_separation",8)
	body.add_child(actions)
	actions.add_child(app.button("渡口故事",app._chapter_menu))
	var kitchen:Button=app.button("公共廚房",KitchenUI.open.bind(app))
	actions.add_child(kitchen)
	var mill:Button=app.button("磨坊",mill_project.bind(app,story_route.bind(app)))
	actions.add_child(mill)
	var dock:Button=app.button("群島來信",dock_project.bind(app))
	actions.add_child(dock)
	var festival:Button=app.button("風鈴節",app.LifeAlmanac.festival_story.bind(app,true,0,story_route.bind(app),"返回五章故事"))
	actions.add_child(festival)
	var back:Button=app.button("回手冊",journal.bind(app,""))
	back.name="StoryRouteBack"
	actions.add_child(back)
	app.modal.set_meta("story_route",{"statuses":rows,"kitchen":kitchen,"dock":dock,"festival":festival})
	refresh_story_route(app)

static func refresh_story_route(app) -> void:
	if not is_instance_valid(app.modal) or not app.modal.has_meta("story_route"):return
	var ui:Dictionary=app.modal.get_meta("story_route")
	var s:Dictionary=app.session.snapshot
	var first:=World.CHAPTER_ONE.next_step(s)
	var bridge:=World.STONE_WORKSHOP.bridge_open(s)
	var kitchen:bool=s.get("public_kitchen",{}).get("opened",false)
	var mines:Dictionary=s.get("mine_depths",{})
	var hoist:=World.MINES.hoist_ready(mines)
	var dock:=int(s.get("dock_stage",0))
	var festival:Dictionary=s.get("festival_story",{})
	ui.statuses[0].text="已完成 · 渡口野餐開席" if first.id=="complete" else str(first.action)
	if bridge and kitchen:
		ui.statuses[1].text="已完成 · 河灣橋通行，公共廚房開張"
	elif bridge:
		ui.statuses[1].text="河灣橋已通行，接著準備公共廚房"
	elif kitchen:
		ui.statuses[1].text="公共廚房已開張，接著到公告板修河灣橋"
	else:
		ui.statuses[1].text="到公告板修河灣橋，和米露準備公共廚房"
	var hoist_step:="升降台已修好" if hoist else ("到金瓜石下坑路牌修升降台" if int(mines.get("unlocked",1))>=World.MINES.HOIST_DEPTH else "礦道開到第六層後可修升降台")
	var mill:=MillRestoration.repaired(s)
	if mill and hoist:
		ui.statuses[2].text="已完成 · 舊磨坊與升降台都已恢復"
	else:
		ui.statuses[2].text=hoist_step+(" · 磨坊已修好" if mill else " · 待修舊磨坊")
	ui.statuses[3].text=["到公告板查看碼頭工程","碼頭已修好，接著準備小船","已完成 · 碼頭與小船都修好了"][clampi(dock,0,2)]
	var opened:bool=festival.get("opened",false)
	ui.statuses[4].text="已完成 · 可以重看開幕故事" if opened else "完成六項公共工程，備妥共餐和兩盞燈"
	ui.kitchen.disabled=not s.get("picnic",false)
	ui.dock.disabled=not s.get("picnic",false)
	ui.festival.disabled=not s.get("picnic",false) and not opened
	ui.festival.text="重看風鈴節" if opened else "籌備風鈴節"

static func island_news(app) -> void:
	var body:VBoxContainer=app._open_modal("島嶼近況")
	app.modal.set_meta("life_modal_layout","community_board")
	var snapshot:Dictionary=app.session.snapshot
	var travel:=card(body)
	line(app,travel,"渡口近況",20)
	var latest:=VBoxContainer.new()
	latest.name="FerryNewsEntries"
	travel.add_child(latest)
	var next:=line(app,travel,"",15)
	var ferry_read:Button=app.button("渡口近況標為已讀",func():
		app.session.perform("ferry_news_read",Vector2i.ZERO,str(latest.get_meta("recap_marker",-1)))
	)
	ferry_read.name="FerryNewsRead"
	travel.add_child(ferry_read)
	travel.add_child(app.button("查看群島來信",dock_project.bind(app,true)))
	body.add_child(app.button("查看五章故事",story_route.bind(app)))
	build_news_projects(app,body)
	var crops:=card(body)
	line(app,crops,"我的農田",20)
	var farm:=line(app,crops,"",16)
	# T071 手帳市集摘要：渡口野餐後列出本人攤位的今日主題、營業狀態、待領營收與上一輪結算
	# （只讀 snapshot.own_market；開著時依快照就地更新）。
	if not market_news_lines(app).is_empty():
		var market:=card(body)
		market.name="MarketNews"
		refresh_market_news(app)
	var stories:=card(body)
	line(app,stories,"可重看的故事",20)
	var replay:Button=app.button("居民回憶",resident_memories.bind(app))
	stories.add_child(replay)
	var festival_replay:Button=app.button("重看風鈴節開幕",app.LifeAlmanac.festival_story.bind(app,true,0,island_news.bind(app)))
	festival_replay.name="NewsFestivalReplay"
	stories.add_child(festival_replay)
	# 第 40 章：風鈴節開幕後，一行地方記憶展近況（按下開展覽頁；開著時依快照就地更新）。
	var exhibit_line:String=preload("res://scripts/memory_exhibit_ui.gd").news_line(snapshot)
	if not exhibit_line.is_empty():
		var exhibit:Button=app.button(exhibit_line,func():preload("res://scripts/memory_exhibit_ui.gd").open(app))
		exhibit.name="MemoryExhibitNews"
		stories.add_child(exhibit)
	var notes:Button=app.button("島民留言",island_notes.bind(app))
	body.add_child(notes)
	body.add_child(app.button("返回島民手帳",journal.bind(app)))
	app.modal.set_meta("live_island_news",{"ferry":travel.get_parent(),"entries":latest,"next":next,"read":ferry_read,
		"farm":farm,"memories":replay,"festival":festival_replay,"notes":notes})
	refresh_island_news(app)

static func refresh_island_news(app) -> void:
	if not is_instance_valid(app.modal) or not app.modal.has_meta("live_island_news"):return
	var rows:Dictionary=app.modal.get_meta("live_island_news")
	var snapshot:Dictionary=app.session.snapshot
	rows.ferry.visible=snapshot.get("picnic",false)
	if rows.ferry.visible:
		var recap:Dictionary=snapshot.get("ferry_story_recap",{})
		if recap.is_empty():recap=World.ISLAND_STORY_RECAP.build(snapshot)
		if rows.entries.get_meta("recap_entries",[])!=recap.entries:
			rows.entries.set_meta("recap_entries",recap.entries.duplicate(true))
			for child:Node in rows.entries.get_children():
				rows.entries.remove_child(child)
				child.queue_free()
			for entry:Dictionary in recap.entries:
				if entry.id=="festival_replay":continue
				line(app,rows.entries,("新消息・" if entry.new else "")+str(entry.title),17)
				line(app,rows.entries,str(entry.body),15)
		rows.entries.set_meta("recap_marker",int(recap.marker))
		rows.next.text=str(recap.next_step)
		rows.read.visible=recap.has_news
	var counts:Dictionary=snapshot.get("own_crop_summary",{})
	rows.farm.text="可收成 %d 格 · 生長中 %d 格，其中 %d 格目前未澆水"%[counts.get("ready",0),counts.get("growing",0),counts.get("dry",0)]
	rows.memories.text="居民回憶 · %d 段"%snapshot.get("resident_memories",[]).size()
	rows.festival.visible=snapshot.get("festival_story",{}).get("opened",false)
	var unread:=int(snapshot.get("island_news",{}).get("notes_unread",0))
	rows.notes.text="島民留言 · %d 則未讀"%unread if unread>0 else "島民留言 · %d 則"%snapshot.get("island_notes",[]).size()

static func build_news_projects(app,body:VBoxContainer) -> void:
	var projects:=card(body)
	line(app,projects,"公共工程",20)
	var public_rows:Array[Label]=[]
	for title:String in World.ISLAND_NOTES.PROJECTS:
		public_rows.append(line(app,projects,title,16))
	var public_read:=news_read_button(app,projects,"公共工程標為已讀")
	var local:=card(body)
	local.name="LocalProjectNews"
	line(app,local,"地方工程",20)
	var local_rows:Array[Label]=[]
	var local_details:Array[Label]=[]
	for details:Array in World.ISLAND_NOTES.LOCAL_PROJECTS:
		local_rows.append(line(app,local,str(details[0]),17))
		local_details.append(line(app,local,str(details[1]),15))
	var local_read:=news_read_button(app,local,"地方工程標為已讀")
	app.modal.set_meta("news_project_rows",{
		"public_rows":public_rows,"public_read":public_read,"local_card":local.get_parent(),
		"local_rows":local_rows,"local_details":local_details,"local_read":local_read,
	})
	refresh_news_projects(app)

static func news_read_button(app,rows:VBoxContainer,caption:String) -> Button:
	var button:Button=app.button(caption,func():
		var mask:=int(rows.get_meta("news_unread_mask",0))
		if mask!=0:app.session.perform("news_read",Vector2i.ZERO,str(mask))
	)
	button.size_flags_horizontal=Control.SIZE_SHRINK_END
	rows.add_child(button)
	return button

static func refresh_news_projects(app) -> void:
	if not is_instance_valid(app.modal) or not app.modal.has_meta("news_project_rows"):return
	var rows:Dictionary=app.modal.get_meta("news_project_rows")
	var news:Dictionary=app.session.snapshot.get("island_news",{})
	var completed:=int(news.get("completed",0))
	var unread:=unread_projects(news)
	var revision:=[completed,unread]
	if app.modal.get_meta("news_project_revision",[])==revision:return
	app.modal.set_meta("news_project_revision",revision)
	var public_mask:=World.ISLAND_NOTES.project_mask()
	var local_mask:=World.ISLAND_NOTES.news_project_limit() & ~public_mask
	for index in World.ISLAND_NOTES.PROJECTS.size():
		var bit:=1<<index
		var status:="未完成" if (completed & bit)==0 else ("新完成" if (unread & bit)!=0 else "已完成")
		rows.public_rows[index].text="%s · %s"%[World.ISLAND_NOTES.PROJECTS[index],status]
	for index in World.ISLAND_NOTES.LOCAL_PROJECTS.size():
		var bit:=1<<(World.ISLAND_NOTES.PROJECTS.size()+index)
		var visible:bool=(completed & bit)!=0
		rows.local_rows[index].visible=visible
		rows.local_details[index].visible=visible
		if visible:
			var title:String=World.ISLAND_NOTES.LOCAL_PROJECTS[index][0]
			rows.local_rows[index].text=("新完成 · " if (unread & bit)!=0 else "")+title
	rows.local_card.visible=(completed & local_mask)!=0
	for group:Array in [[rows.public_read,public_mask],[rows.local_read,local_mask]]:
		var button:Button=group[0]
		var mask:int=group[1]
		button.get_parent().set_meta("news_unread_mask",unread & mask)
		button.visible=(completed & mask)!=0
		button.disabled=(unread & mask)==0

static func market_news_lines(app) -> Array:
	var own:Variant=app.session.snapshot.get("own_market",{})
	return preload("res://scripts/market_visitors.gd").summary_lines(own if own is Dictionary else {},World.NAMES)

## 「島嶼近況」開著時的市集卡片；內容沒變就不重建。
static func refresh_market_news(app) -> void:
	if not is_instance_valid(app.modal):return
	var rows:=app.modal.find_child("MarketNews",true,false) as VBoxContainer
	if rows==null:return
	var lines:=market_news_lines(app)
	if lines.is_empty():return
	if rows.has_meta("lines") and rows.get_meta("lines")==lines:return
	rows.set_meta("lines",lines.duplicate())
	for child in rows.get_children():
		rows.remove_child(child)
		child.queue_free()
	var heading:=HBoxContainer.new()
	heading.add_theme_constant_override("separation",8)
	rows.add_child(heading)
	add_icon(heading,ItemArt.icon("coins"),24)
	line(app,heading,"我的市集攤位",20)
	for index in lines.size():
		line(app,rows,str(lines[index]),16 if index<3 else 15)
		rows.get_child(rows.get_child_count()-1).name="MarketNewsLine%d"%index

static func island_notes(app,back:Callable=Callable()) -> void:
	var body:VBoxContainer=app._open_modal("島民留言")
	app.modal.set_meta("life_modal_layout","community_board")
	var return_button:Button=app.button("返回回憶信" if back.is_valid() else "返回島嶼近況",back if back.is_valid() else island_news.bind(app))
	return_button.name="IslandNotesBack"
	body.add_child(return_button)
	if back.is_valid():line(app,body,"你貼出的留言會出現在同一座島的留言板。",15)
	var field:=LineEdit.new()
	field.name="IslandNoteDraft"
	field.max_length=World.ISLAND_NOTES.LENGTH
	field.placeholder_text="留下訊息，島上的朋友回來就能看到"
	body.add_child(field)
	var saved_draft:String=player(app).get(World.INDUSTRY.DESK_DRAFT_FIELD,"")
	if not saved_draft.is_empty():
		var apply_draft:Button=app.button("帶入書桌草稿",func():
			field.text=saved_draft
			field.grab_focus()
			field.caret_column=field.text.length())
		apply_draft.name="IslandNoteLoadDeskDraft"
		var update_draft_button:=func(_text:String):
			apply_draft.disabled=not field.text.is_empty()
		field.text_changed.connect(update_draft_button)
		apply_draft.pressed.connect(func():update_draft_button.call(field.text))
		body.add_child(apply_draft)
	var submit:Button=app.button("貼到留言板",func():field.text_submitted.emit(field.text))
	submit.name="IslandNoteSubmit"
	var post:=func(raw:String):
		var message:=World.ISLAND_NOTES.clean(raw)
		if message.is_empty() or submit.disabled:return
		app.modal.set_meta("island_note_sequence",app.session.counter+1)
		submit.disabled=true
		app.session.perform("news_note",Vector2i.ZERO,message)
	field.text_submitted.connect(post)
	body.add_child(submit)
	var list:=VBoxContainer.new()
	list.name="IslandNoteList"
	body.add_child(list)
	var read_button:Button=app.button("將這批留言標為已讀",func():
		var revision:int=int(list.get_meta("revision",0))
		app.session.perform("news_notes_read",Vector2i.ZERO,str(revision))
	)
	read_button.name="IslandNotesRead"
	body.add_child(read_button)
	body.move_child(read_button,list.get_index())
	refresh_island_notes(app)

static func finish_island_note(app,sequence:int,success:bool) -> void:
	if not is_instance_valid(app.modal) or app.modal.get_meta("island_note_sequence",-1)!=sequence:return
	app.modal.remove_meta("island_note_sequence")
	var field:=app.modal.find_child("IslandNoteDraft",true,false) as LineEdit
	var submit:=app.modal.find_child("IslandNoteSubmit",true,false) as Button
	if success and field!=null:field.clear()
	if submit!=null:submit.disabled=false

static func refresh_island_notes(app) -> void:
	# main 每份新快照都會呼叫這裡；順便讓開著的「一起做的事」頁原地更新。
	refresh_bond_goal(app)
	XingheGrowth.sync(app)
	refresh_sheep_corner(app)
	MiluSupper.refresh(app)
	refresh_shared_garden(app)
	refresh_market_news(app)
	refresh_news_projects(app)
	refresh_island_news(app)
	refresh_story_route(app)
	refresh_mill_project(app)
	refresh_luoluo_cap(app)
	refresh_public_mural(app)
	refresh_inn_entrance(app)
	HouseUI.refresh_guest_room(app)
	if not is_instance_valid(app.modal):return
	var list:=app.modal.find_child("IslandNoteList",true,false) as VBoxContainer
	if list==null:return
	var entries:Array=app.session.snapshot.get("island_notes",[])
	var news:Dictionary=app.session.snapshot.get("island_news",{})
	var unread:=int(news.get("notes_unread",0))
	list.set_meta("revision",int(news.get("note_revision",0)))
	var read_button:=app.modal.find_child("IslandNotesRead",true,false) as Button
	if read_button!=null:read_button.visible=unread>0
	if list.get_meta("entries",[])==entries and list.get_meta("unread",-1)==unread:return
	list.set_meta("entries",entries.duplicate(true))
	list.set_meta("unread",unread)
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()
	for index in entries.size():
		var entry:Dictionary=entries[index]
		var paper:=card(list)
		line(app,paper,("未讀 · " if index<unread else "")+"%s · 第 %d 日"%[entry.sender,floori(float(entry.time)/World.Village.DAY)+1],15)
		line(app,paper,entry.text,16)

static func bookcase_back(app,parent:Container,caption:String,callback:Callable) -> void:
	var back:Button=app.button(caption,callback)
	back.name="BookcaseBack"
	back.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	parent.add_child(back)

static func bookcase_page(app,title:String,compact:bool) -> VBoxContainer:
	var page:VBoxContainer=app._open_modal(title)
	app.modal.set_meta("life_modal_layout","bookcase_compact" if compact else "bookcase")
	app.modal.theme=PixelTheme.make(app.hud.theme)
	app.modal.add_theme_stylebox_override("panel",PixelTheme.frame_style())
	return page

static func cedar_bed(app,tile:Vector2i) -> void:
	var industry:=World.INDUSTRY
	var objects:Dictionary=app.session.snapshot.get("objects",{})
	var anchor:=World.key(World.station_anchor(objects,tile))
	var bed:Dictionary=objects.get(anchor,{})
	if bed.get("type")!=industry.CEDAR_BED:return
	var page:VBoxContainer=app._open_modal("原木小床")
	app.modal.set_meta("life_modal_layout","cedar_bed")
	app.modal.theme=PixelTheme.make(app.hud.theme)
	app.modal.add_theme_stylebox_override("panel",PixelTheme.frame_style())
	var row:=HBoxContainer.new()
	row.add_theme_constant_override("separation",16)
	page.add_child(row)
	add_icon(row,preload("res://assets/ui-life/cedar-bed-long.png"),128)
	var details:=VBoxContainer.new()
	details.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	row.add_child(details)
	if bed.get("owner")!=app.session.own_id:
		line(app,details,"這是其他島民的床，只有床主可以在這裡休息。",17)
	else:
		var person:=player(app)
		var marked:bool=person.get(industry.HOME_REST_FIELD)==anchor
		line(app,details,"這裡是你的個人休息處。" if marked else "在床邊歇一會兒，恢復探索體力。",17)
		var rest:Button=app.button("休息一下",func():
			app.session.perform(industry.CEDAR_BED,tile,"rest")
			app._close_modal())
		rest.name="CedarBedRest"
		details.add_child(rest)
		var mark:Button=app.button("已設為個人休息處" if marked else "設為個人休息處",func():
			app.session.perform(industry.CEDAR_BED,tile,"mark")
			app._close_modal())
		mark.disabled=marked
		mark.name="CedarBedMark"
		details.add_child(mark)
		line(app,details,"探索體力　%d／100"%int(person.get("mine_energy",100)),15)
		line(app,details,"房間的時間照常經過。",14)
	app._layout_preview.call_deferred()

static func grid_bookcase(app,tile:Vector2i) -> void:
	var objects:Dictionary=app.session.snapshot.get("objects",{})
	var anchor:=World.station_anchor(objects,tile)
	if objects.get(World.key(anchor),{}).get("type")!=World.INDUSTRY.GRID_BOOKCASE:
		app._close_modal()
		return
	var page:=bookcase_page(app,"格子書櫃",true)
	var back:=grid_bookcase.bind(app,anchor)
	var shelf:=HBoxContainer.new()
	shelf.add_theme_constant_override("separation",18)
	page.add_child(shelf)
	add_icon(shelf,preload("res://assets/ui-life/grid-bookcase-long.png"),128)
	var contents:=VBoxContainer.new()
	contents.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	contents.add_theme_constant_override("separation",8)
	shelf.add_child(contents)
	var entries:=[
		["BookcaseStories","已讀故事","journal",bookcase_stories.bind(app,back)],
		["BookcaseMemories","居民回憶","letter",resident_memories.bind(app,back)],
		["BookcaseHistory","地方記憶","map",app._history_menu.bind(back)],
	]
	for entry in entries:
		var choice:Button=app.button(entry[1],entry[3])
		choice.name=entry[0]
		choice.icon=Shell.icon(entry[2])
		choice.alignment=HORIZONTAL_ALIGNMENT_LEFT
		choice.icon_alignment=HORIZONTAL_ALIGNMENT_LEFT
		choice.add_theme_constant_override("h_separation",12)
		choice.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
		contents.add_child(choice)
	app._layout_preview.call_deferred()

static func bookcase_stories(app,back:Callable) -> void:
	var page:=bookcase_page(app,"已讀故事",false)
	bookcase_back(app,page,"返回書櫃",back)
	var person:=player(app)
	var count:=0
	for id:String in Village.QUESTS:
		var stage:=story_stage(person,id)
		if stage==0:continue
		var section:=card(page)
		line(app,section,Village.NPCS[id].name,18)
		for index in range(stage):
			var entry:Button=app.button(Village.QUESTS[id][index].title,bookcase_story.bind(app,id,index,back))
			entry.name="BookcaseStory_%s_%d"%[id,index]
			section.add_child(entry)
			count+=1
	if count==0:line(app,page,"和島民一起完成一段故事後，就能回家翻閱。",17)
	app._layout_preview.call_deferred()

static func bookcase_story(app,id:String,index:int,back:Callable) -> void:
	var person:=player(app)
	if index<0 or index>=story_stage(person,id):
		bookcase_stories(app,back)
		return
	var page:=bookcase_page(app,Village.NPCS[id].name+"的故事",true)
	bookcase_back(app,page,"返回已讀故事",bookcase_stories.bind(app,back))
	var row:=HBoxContainer.new()
	row.add_theme_constant_override("separation",12)
	page.add_child(row)
	add_icon(row,Art.icon(id),88)
	var paper:=card(row)
	paper.get_parent().size_flags_horizontal=Control.SIZE_EXPAND_FILL
	journal_story(app,paper,id,index,person)
	app._layout_preview.call_deferred()

static func resident_memories(app,return_to:Callable=Callable()) -> void:
	var body:VBoxContainer=app._open_modal("居民回憶")
	app.modal.set_meta("life_modal_layout","community_board")
	var unlocked:Array=app.session.snapshot.get("resident_memories",[])
	if return_to.is_valid():bookcase_back(app,body,"返回書櫃",return_to)
	else:body.add_child(app.button("返回島民手帳",journal.bind(app)))
	if app.session.snapshot.get("festival_story",{}).get("opened",false):
		var finale:Button=app.button("重看風鈴節開幕",app._festival_memory)
		finale.name="FestivalMemory"
		body.add_child(finale)
	# T066：地方居民（茶茶、星禾）的關係事件；認識之後才列出。
	for local_id:String in Bond.LOCAL_NAMES:
		var local_bond:=bond_view(app,local_id)
		if int(local_bond.get("stage",0))<1:continue
		var local_events:Button=app.button("%s的關係事件  %d／%d"%[Bond.name_of(local_id),int(local_bond.get("stage",0)),Bond.STAGES.size()],bond_events.bind(app,local_id))
		local_events.name="BondEvents_"+local_id
		body.add_child(local_events)
	if unlocked.is_empty():
		line(app,body,"完成故事和地方工作後，居民的回憶會收進這裡。",16)
		return
	for chapter:int in ResidentStories.CHAPTERS:
		var heading_added:=false
		for resident:Dictionary in ResidentStories.RESIDENTS.values():
			for entry:Dictionary in resident.beats:
				if entry.chapter!=chapter or not unlocked.has(entry.id):continue
				if not heading_added:
					line(app,body,"第 %d 章"%chapter,21)
					heading_added=true
				var paper:=card(body)
				line(app,paper,"%s・%s"%[resident.name,resident.role],17)
				line(app,paper,"「%s」"%ResidentStories.line_for(entry,app.session.snapshot.get("resident_participation",{}).get(entry.id,true)),16)
				line(app,paper,entry.local_work,14)

static func journal_page(app,page:VBoxContainer,index_details:VBoxContainer,id:String,person:Dictionary) -> void:
	for child in page.get_children():
		page.remove_child(child)
		child.queue_free()
	if id=="xinghe":
		for child in index_details.get_children():index_details.remove_child(child);child.queue_free()
		line(app,index_details,"「先替下一輪留一棵苗。」",15)
		line(app,index_details,"米露在田區的朋友",14)
		add_icon(page,preload("res://scripts/lanyang_life_art.gd").portrait(),96)
		line(app,page,"星禾・照顧水圳與幼苗的人",21)
		line(app,page,"習慣在每盤苗旁留一張手寫標籤。她記得哪一批樹苗去了誰家的林場，也相信手藝要留給下一個願意學的人。",16)
		var life:Dictionary=app.session.snapshot.get("lanyang_life",World.LANYANG_LIFE.fresh())
		line(app,page,"✓ 水口清理完成" if life.cleared.size()==3 else "○ 沿水圳清開三處枯枝",15)
		line(app,page,"✓ 閘門修復・育苗盤開放" if life.repaired else "○ 用木板、石材與樹脂修好閘門",15)
		# 第 40 章蘭陽回訪：配水紀念牌設好之後才出現這一行。
		if World.LANYANG_REVISIT.unlocked(app.session.snapshot):
			line(app,page,"✓ 旱日分流完成・家園工作台可做分流閘" if World.LANYANG_REVISIT.completed(app.session.snapshot) else "○ 放晴的日子回水圳，用岔口分流閘把水分給三塊田",15)
		line(app,page,"和米露在渡口做成的公共餐，成了這段合作的開始。木板修水圳，水養樹苗，人工林再把木材送回阿榆的鋸木台。",15)
		if str(app.session.snapshot.get("region_id","home"))=="lanyang":page.add_child(app.button("查看水圳手記",app._gardener_menu))
		else:page.add_child(app.button("查看往蘭陽的路線",app._travel_menu))
		var xinghe_bond:=bond_view(app,"xinghe")
		if not xinghe_bond.is_empty():
			var xinghe_events:Button=app.button("關係事件  %d／%d"%[int(xinghe_bond.get("stage",0)),Bond.STAGES.size()],bond_events.bind(app,"xinghe"))
			xinghe_events.name="BondEvents"
			page.add_child(xinghe_events)
		return
	if id=="salt_worker":
		salt_worker_page(app,page,index_details)
		return
	var stage:=story_stage(person,id)
	var stories:Array=Village.QUESTS[id]
	for child in index_details.get_children():
		index_details.remove_child(child)
		child.queue_free()
	line(app,index_details,"「"+Village.NPCS[id].hello+"」",15)
	line(app,index_details,"故事章節",16)
	for index in stories.size():
		var marker:="✓ " if index<stage else ("› " if index==stage else "○ ")
		line(app,index_details,marker+stories[index].title,14)
	portrait_header(app,page,id,"",96)
	progress(app,page,"故事",stage,stories.size())
	# 第 40 章金瓜石回訪：升降台修好之後，波波頁多一行礦料調度的進度（與星禾頁的旱日分流同位置）。
	if id=="bobo" and World.JINGUASHI_REVISIT.unlocked(app.session.snapshot):
		var jg_snapshot:Dictionary=app.session.snapshot
		var jg_text:="○ 到金瓜石波波的整理桌分揀三個貨箱，再分頭送到整理桌、山城接駁站和升降台"
		if World.JINGUASHI_REVISIT.completed(jg_snapshot):jg_text="✓ 礦料調度完成・礦燈已領，可擺在家園" if World.JINGUASHI_REVISIT.claimed_own(jg_snapshot) else "✓ 礦料調度完成・到波波的整理桌領礦燈"
		elif not World.JINGUASHI_REVISIT.sent(jg_snapshot).is_empty():jg_text="○ 礦料調度：已送出 %d／3 箱"%World.JINGUASHI_REVISIT.sent(jg_snapshot).size()
		line(app,page,jg_text,15)
		page.get_child(page.get_child_count()-1).name="BoboRevisitLine"
	var story_page:=VBoxContainer.new()
	page.add_child(story_page)
	var selector:=HFlowContainer.new()
	page.add_child(selector)
	var group:=ButtonGroup.new()
	for index in range(mini(stage+1,stories.size())):
		var label_text:="目前委託" if index==stage else "回憶 %d"%(index+1)
		var story_button:Button=app.button(label_text,journal_story.bind(app,story_page,id,index,person))
		story_button.toggle_mode=true
		story_button.button_group=group
		selector.add_child(story_button)
	selector.get_child(selector.get_child_count()-1).set_pressed_no_signal(true)
	var bond:=bond_view(app,id)
	if not bond.is_empty():
		var events:Button=app.button("關係事件  %d／%d"%[int(bond.get("stage",0)),Bond.STAGES.size()],bond_events.bind(app,id))
		events.name="BondEvents"
		selector.add_child(events)
	journal_story(app,story_page,id,mini(stage,stories.size()-1),person)

## 北門鹽田：salt_report 之後才出現的阿曬居民頁與「北門瓦盤鹽田」地方記憶頁。
## salt_pan_ui.gd 於執行時載入，鹽田檔案缺席時手冊其他頁照常運作。
const SALT_UI_PATH:="res://scripts/salt_pan_ui.gd"

static func salt_complete(app) -> bool:
	var own=app.session.snapshot.get("salt_pan",{}).get("own",{})
	if not (own is Dictionary):return false
	var record=own.get("record",{})
	return record is Dictionary and bool(record.get("complete",false))

static func salt_ui():
	return load(SALT_UI_PATH) if ResourceLoader.exists(SALT_UI_PATH) else null

static func salt_bookmarks(app,bookmarks:VBoxContainer,page:VBoxContainer,index_details:VBoxContainer,person:Dictionary,group:ButtonGroup,selected_id:String) -> void:
	var salt=salt_ui()
	if salt==null:return
	if salt_complete(app):
		var worker:Button=app.button("阿曬・北門",journal_page.bind(app,page,index_details,"salt_worker",person))
		worker.name="SaltWorkerBookmark"
		var face=salt.portrait("salt_worker")
		if face:
			worker.icon=face
			worker.expand_icon=true
			worker.add_theme_constant_override("icon_max_width",36)
		worker.toggle_mode=true;worker.button_group=group
		bookmarks.add_child(worker)
		worker.set_pressed_no_signal(selected_id=="salt_worker")
	var salt_record:Dictionary=salt.own_record(app.session.snapshot)
	if int(salt_record.get("raked",0))<1 and not salt_complete(app):return
	var memory:Button=app.button("地方記憶・北門瓦盤鹽田",func():salt.open(app,"journal"))
	memory.name="SaltMemoryBookmark"
	memory.icon=preload("res://scripts/life_ui_shell.gd").icon("journal")
	memory.expand_icon=true;memory.add_theme_constant_override("icon_max_width",32)
	bookmarks.add_child(memory)
	bookmarks.move_child(memory,2) # 放在「居民回憶」與「生活技能」之後，取得後可直接找到。

static func salt_worker_page(app,page:VBoxContainer,index_details:VBoxContainer) -> void:
	var salt=salt_ui()
	for child in index_details.get_children():index_details.remove_child(child);child.queue_free()
	line(app,index_details,"「機器替我們提水收鹽，我們才有空去看看前人留下的鹽田。」",15)
	line(app,index_details,"鹽風合作鹽田的鹽工",14)
	var face=salt.portrait("salt_worker") if salt else null
	if face:add_icon(page,face,96)
	line(app,page,"阿曬・照顧鹽風合作鹽田的鹽工",21)
	if salt:
		var memory:Button=app.button("翻開北門瓦盤鹽田",func():salt.open(app,"journal"))
		memory.name="SaltWorkerMemory"
		page.add_child(memory)
	line(app,page,"斗笠總是往後推，說話時會先看一眼天色。晴天催大家引海水，下雨就把草蓆蓋好，等雨停再收鹽。",16)
	var gates_done:bool=salt!=null and salt.repaired(app.session.snapshot)
	line(app,page,"✓ 三道閘門修好・海水引進鹽田" if gates_done else "○ 用木板、樹脂與石材修好三道閘門",15)
	line(app,page,"✓ 水車引水、收鹽台自動收進箱子",15)
	line(app,page,"✓ 海鹽與香煎溪魚送到小栗的攤位",15)
	line(app,page,"阿曬是遊戲原創的人物；觀景區的井仔腳瓦盤鹽田是今日保存的文化景觀，只供欣賞。",14)

static func journal_story(app,page:VBoxContainer,id:String,index:int,person:Dictionary) -> void:
	for child in page.get_children():
		page.remove_child(child)
		child.queue_free()
	var story:Dictionary=Village.QUESTS[id][index]
	if index<story_stage(person,id):
		line(app,page,story.title,22)
		line(app,page,"「"+story.line+"」",18)
	else:
		quest_details(app,page,story,person)
		var interaction:String=app.binding_label("interact")
		var hint:="到%s身邊按 %s 交件。"%[Village.NPCS[id].name,interaction]
		if id=="xiaoli":hint="到種子攤按 %s，再選「和小栗聊聊」交件。"%interaction
		elif id=="bobo":hint="到金瓜石的礦樣桌找波波，靠近後按 %s。"%interaction
		line(app,page,hint,15)

static func resident(app,id:String) -> void:
	if not Village.NPCS.has(id):return
	var npc:Dictionary=Village.NPCS[id]
	var col:VBoxContainer=app._open_modal(npc.name+"的島上日常")
	app.modal.set_meta("life_modal_layout","resident_dialogue")
	var person:Dictionary=player(app)
	var stage:=story_stage(person,id)
	var dialogue:=HBoxContainer.new()
	dialogue.add_theme_constant_override("separation",14)
	col.add_child(dialogue)
	add_icon(dialogue,Art.icon(id),104)
	var section:=VBoxContainer.new()
	section.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	dialogue.add_child(section)
	var response:String=World.COMMUNITY.resident_line(app.session.snapshot,id)
	line(app,section,"「"+(response if not response.is_empty() else str(npc.hello))+"」",18)
	add_resident_dialogue(app,section,id)
	var actions:=HFlowContainer.new()
	if stage<Village.QUESTS[id].size():
		quest_details(app,section,Village.QUESTS[id][stage],person)
		if id=="bobo":
			var status:String=Village.blocked_reason(app.session.snapshot,person,app.session.own_id,Village.QUESTS[id][stage])
			if not status.is_empty():line(app,section,status+"。",15)
		var request:=id+":"+str(stage)
		var cell:Vector2i=Village.resident_cell(app.session.snapshot,id)
		actions.add_child(app.button("交付這段委託",func():app.session.perform("quest",cell,request);app._close_modal()))
	else:
		line(app,section,"「"+Village.QUESTS[id].back().line+"」",18)
	if id=="milu":add_milu_recipe_book(app,actions)
	if id=="milu" and app.session.snapshot.get("resident_goals",{}).get("milu",{}).get("4",{}).get("state")=="done":
		var cookbook:Button=app.button("翻閱米露的共餐食譜",shared_meal_book.bind(app))
		cookbook.name="MiluCookbook"
		actions.add_child(cookbook)
		add_milu_apron_button(app,actions)
	if id=="xiaoli" and app.session.snapshot.has("own_shop_history"):
		var trade_book:Button=app.button("翻開交易簿",app.life_panels.trade_book.bind(app))
		trade_book.name="ResidentTradeBook"
		actions.add_child(trade_book)
	if id=="bobo" and stage>=1 and app.has_method("_bobo_sort_menu"):
		actions.add_child(app.button("到礦樣整理桌",app._bobo_sort_menu))
	if id=="bobo" and BoboRockGuide.available(app.session.snapshot):
		var rock_guide:Button=app.button("翻開礦石辨識頁",BoboRockGuide.open.bind(app,resident.bind(app,id)))
		rock_guide.name="BoboRockGuideEntry"
		actions.add_child(rock_guide)
	actions.add_child(app.button("打開島民手冊  %s"%app.binding_label("journal"),func():app._journal(id)))
	add_bond_controls(app,section,actions,id)
	add_address_delivery(app,actions,id)
	section.add_child(actions)
	var step:Dictionary=World.CHAPTER_ONE.next_step(app.session.snapshot)
	if step.get("npc")==id:
		var chapter:=card(col)
		if step.get("id")=="complete":
			var letter:Button=app.button("讀小栗介紹信",app._tea_home)
			letter.name="ChapterNpcTeaLetter"
			chapter.add_child(letter)
			return
		var details:=VBoxContainer.new()
		chapter.add_child(app.button("看渡口來信",func():
			details.visible=not details.visible
			if details.visible:
				var scroll:=col.get_parent() as ScrollContainer
				if scroll!=null:scroll.ensure_control_visible.call_deferred(details)
		))
		chapter.add_child(details)
		details.visible=id=="aru" and World.CHAPTER_ONE.needs_starter_kit(app.session.snapshot,app.session.own_id)
		line(app,details,"「"+str(step.get("line",""))+"」",16)
		if id=="aru" and step.get("id")=="water":chapter_starter(app,details,npc.cell)

static func chapter_starter(app,parent:VBoxContainer,cell:Vector2i) -> void:
	var costs:=HBoxContainer.new()
	parent.add_child(costs)
	var amounts:={}
	for item in World.CHAPTER_ONE.STARTER_COST:
		add_icon(costs,ItemArt.icon(item),24)
		var count:Label=app.label("",15)
		costs.add_child(count)
		amounts[item]=count
	line(app,parent,"可換灑水器 ×1、銅水管 ×2、儲水桶 ×1。已有設備也可直接接管。",15)
	var claim:Button=app.button("交材料換入門設備",func():app.session.perform("chapter_starter",cell))
	parent.add_child(claim)
	app.modal.set_meta("chapter_starter_controls",{"cell":cell,"amounts":amounts,"claim":claim})
	refresh_chapter_starter(app)

static func refresh_chapter_starter(app) -> void:
	if not is_instance_valid(app.modal) or not app.modal.has_meta("chapter_starter_controls"):return
	var controls:Dictionary=app.modal.get_meta("chapter_starter_controls")
	var person:=player(app)
	var held:Dictionary=person.get("inventory",{})
	for item in controls.amounts:
		controls.amounts[item].text="%d／%d"%[int(held.get(item,0)),World.CHAPTER_ONE.STARTER_COST[item]]
	var claimed:bool=app.session.snapshot.get("chapter_one",{}).get("starter_claims",{}).get(app.session.own_id,false)
	var nearby:=not person.is_empty() and Vector2(person.x,person.y).distance_to(Vector2(controls.cell)+Vector2(0.5,0.5))<3.2
	controls.claim.text="已換取入門設備" if claimed else "交材料換入門設備"
	controls.claim.disabled=claimed or not nearby

static func skill_book(app) -> void:
	var rules=preload("res://scripts/island_skill_book.gd")
	var body:VBoxContainer=app._open_modal("生活技能")
	var own:=player(app)
	var grid:=GridContainer.new()
	grid.columns=2 if app.font_scale_factor()>=1.2 or app.get_viewport_rect().size.x<1100 else 3
	grid.add_theme_constant_override("h_separation",12)
	grid.add_theme_constant_override("v_separation",10)
	body.add_child(grid)
	for skill:Dictionary in rules.skills(own):
		var entry:=card(grid)
		(entry.get_parent() as Control).size_flags_horizontal=Control.SIZE_EXPAND_FILL
		var heading:=HBoxContainer.new()
		heading.add_theme_constant_override("separation",8)
		entry.add_child(heading)
		var art:=ItemArt.icon(skill.icon) if skill.icon!="compass" else preload("res://scripts/life_ui_shell.gd").icon("map")
		add_icon(heading,art,28)
		line(app,heading,"%s · %d 級"%[skill.title,skill.level],18)
		if skill.title=="採集" and int(own.get("gathering_assists",0))>0:
			line(app,entry,"合作採集 %d 次"%int(own.gathering_assists),15)
		if int(skill.level)<10:
			line(app,entry,"%d／%d %s · 距下級 %d"%[skill.points,skill.next,skill.unit,int(skill.next)-int(skill.points)],15)
			var progress:=ProgressBar.new()
			progress.min_value=float(skill.previous)
			progress.max_value=float(skill.next)
			progress.value=float(skill.points)
			progress.show_percentage=false
			progress.custom_minimum_size.y=8
			entry.add_child(progress)
		else:line(app,entry,"已達十級 · %d %s"%[skill.points,skill.unit],15)
		for unlock:Array in skill.unlocks:
			line(app,entry,"%s %d 級 · %s"%["✓" if int(skill.level)>=int(unlock[0]) else "○",unlock[0],unlock[1]],15)
	var public_help:=card(grid)
	(public_help.get_parent() as Control).size_flags_horizontal=Control.SIZE_EXPAND_FILL
	line(app,public_help,"後來到島上的居民",18)
	var snapshot:Dictionary=app.session.snapshot
	line(app,public_help,"野餐後可在渡口練習礦料點、金瓜石下坑路牌或 B1–B5 休息站借公用鎬。",15)
	if World.PUBLIC_KITCHEN.stage(snapshot)=="open":
		var stove:=World.PUBLIC_KITCHEN.parse_cell(snapshot.public_kitchen.stove)
		var at_home:bool=snapshot.get("region_id","home")=="home"
		var by_stove:bool=at_home and Vector2(own.get("x",0),own.get("y",0)).distance_to(Vector2(stove)+Vector2(0.5,0.5))<=3.2
		line(app,public_help,"第一道菜可以做熱蘿蔔湯。用兩顆蘿蔔，在公共石灶煮成兩份。",15)
		if by_stove:public_help.add_child(app.button("使用公共石灶",app._cook_menu.bind(stove)))
		elif at_home:public_help.add_child(app.button("在地圖找公共廚房",app._map_menu))
		else:line(app,public_help,"回到風鈴渡口後，可從周邊地圖找到公共廚房。",15)
		public_help.add_child(app.button("查看公共廚房",func():KitchenUI.open(app)))
	var has_tool:=not World.active_mining_pick(own.get("inventory",{})).is_empty()
	var borrowed:bool=own.get("borrowed_mine_pick",false)
	var near:bool=snapshot.get("region_id","home")=="home" and Vector2(own.get("x",0),own.get("y",0)).distance_to(Vector2(World.COPPER_CELL)+Vector2(0.5,0.5))<=3.2
	if borrowed:line(app,public_help,"你已可借用公用鎬。這是使用資格，不會進背包。",15)
	elif snapshot.get("picnic",false) and not has_tool:
		var borrow:Button=app.button("借用公用鎬",func():
			app.session.perform("borrow_mine_pick",World.COPPER_CELL)
			app._close_modal())
		borrow.disabled=not near
		public_help.add_child(borrow)
		if not near:line(app,public_help,"走近渡口東北側的運入練習礦料點後，就能借用。",15)
	# T064 公用耕田機：野餐後才出現。用 load 而非 preload，避免與 public_tiller_ui.gd 互相預載。
	if World.PUBLIC_TILLER.open(snapshot):
		line(app,public_help,"公用耕田機",16)
		load("res://scripts/public_tiller_ui.gd").add_loan(app,public_help)
	body.add_child(app.button("返回島民手冊",app._journal))

static func board(app) -> void:
	var col:VBoxContainer=app._open_modal("渡口的共同工程")
	app.modal.set_meta("life_modal_layout","community_board")
	SpringGardenUI.add_board_link(app,col)
	SeaFairUI.add_board_link(app,col)
	AutumnFeastUI.add_board_link(app,col)
	WarmNightUI.add_board_link(app,col)
	var s:Dictionary=app.session.snapshot
	var project:=card(col)
	# The gallery link sits below the priority project cards (see gallery_button below).
	var donations:Dictionary=s.get("donations",{})
	line(app,project,"渡口修繕",22).name="BoardRepairTitle"
	if s.get("board",false) and World.STONE_WORKSHOP.project_pending(s):
		q05_card(app,col,s)
		line(app,project,"公告板已修好，現在可以接生活訂單。河灣橋的材料在下方另一張卡。",16).name="BridgeFoundationHint"
	else:
		line(app,project,"河灣橋已開通，往村東過橋探索。橋兩側的河面是「河灣橋釣點」，用釣竿能釣到橋邊限定的魚。" if s.get("board",false) else "捐木材和石材修好公告板，讓生活訂單重新開張。可以分次捐。",16).name="BridgeOpenHint"
	if s.get("board",false) and World.CHAPTER_ONE.needs_starter_kit(s,app.session.own_id):
		line(app,project,"下一步和阿榆談談，用材料換入門灌溉設備。",15)
	if s.get("board",false):
		var entries:=HBoxContainer.new()
		entries.add_theme_constant_override("separation",8)
		project.add_child(entries)
		var orders:Button=app.button("查看生活訂單",app._orders_menu)
		orders.name="BoardOrders"
		orders.icon=ItemArt.icon("paper")
		orders.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		entries.add_child(orders)
		var layouts=preload("res://scripts/workshop_layouts.gd")
		var starter_house:Button=app.button("怎麼蓋小屋",app._workshop_guide.bind(layouts.FIRST_HOUSE))
		starter_house.name="BoardStarterHouse"
		starter_house.icon=ItemArt.icon("wood")
		starter_house.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		entries.add_child(starter_house)
	if not s.get("board",false):
		var cost:=World.CHAPTER_ONE.BOARD_COST
		material_progress(app,project,"wood",int(donations.get("wood",0)),cost.wood).name="BridgeWood"
		material_progress(app,project,"stone",int(donations.get("stone",0)),cost.stone).name="BridgeStone"
		var donate:Button=app.button("捐材料",func():app.session.perform("donate",BOARD_CELL))
		donate.name="BoardDonateBridge"
		project.add_child(donate)
		line(app,project,"",15).name="BridgeDonationHint"
		col.add_child(app.button("看看圖鑑收藏展示",app._collection_gallery))
	if s.get("board",false):
		var picnic:=card(col)
		var dishes:Dictionary=s.get("picnic_materials",{})
		line(app,picnic,"渡口野餐",22)
		if s.get("picnic",false):
			line(app,picnic,"湯和麵包已上桌，謝謝每一位準備料理的島民。",16)
		else:
			material_progress(app,picnic,"soup",int(dishes.get("soup",0)),2).name="PicnicSoup"
			material_progress(app,picnic,"bread",int(dishes.get("bread",0)),1).name="PicnicBread"
			# T071 紀念品交換攤 (locked) shares the picnic button's row: it opens after
			# this picnic, and the board gains no height.
			var picnic_row:=HBoxContainer.new()
			picnic_row.name="BoardPicnicRow"
			picnic_row.add_theme_constant_override("separation",8)
			picnic.add_child(picnic_row)
			var serve:Button=app.button("端上料理",func():app.session.perform("picnic",BOARD_CELL))
			serve.name="BoardServePicnic"
			serve.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			picnic_row.add_child(serve)
			var souvenir_locked:Button=app.button(preload("res://scripts/souvenir_exchange_ui.gd").ENTRY_LOCKED,app._souvenir_menu)
			souvenir_locked.name="SouvenirEntry"
			souvenir_locked.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			picnic_row.add_child(souvenir_locked)
			line(app,picnic,"",15).name="PicnicContributionHint"
		col.add_child(app.button("看看圖鑑收藏展示",app._collection_gallery))
		if s.get("picnic",false):
			col.add_child(app.button("看看大家的餐桌",app._community_menu))
			# T071 紀念品交換攤 shares the 風鈴接力 row, right above the three activity
			# entries (no new board height).
			var festival_row:=board_activity_row(app)
			festival_row.name="BoardFestivalRow"
			col.add_child(festival_row)
			var festival:Button=app.button("一起玩風鈴接力  %s"%app.binding_label("festival"),app._festival_menu)
			festival.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			festival_row.add_child(festival)
			var souvenir:Button=app.button(preload("res://scripts/souvenir_exchange_ui.gd").ENTRY_OPEN,app._souvenir_menu)
			souvenir.name="SouvenirEntry"
			souvenir.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			festival_row.add_child(souvenir)
			festival_row.add_child(preload("res://scripts/memory_exhibit_ui.gd").entry_button(app))
			var activities:=board_activity_row(app)
			activities.name="BoardActivities"
			col.add_child(activities)
			for entry in [["一起玩豐收接力（廣場西側）",app._harvest_menu,"HarvestRelayBoardEntry"],["河岸釣魚會（河灣橋南岸）",app._fishmeet_menu,"FishingMeetEntry"],["家園布置題（渡口西南草地）",app._showcase_menu,"ShowcaseEntry"]]:
				var b:Button=app.button(entry[0],entry[1])
				b.name=entry[2]
				b.size_flags_horizontal=Control.SIZE_EXPAND_FILL
				activities.add_child(b)
		else:
			var row:=board_activity_row(app)
			row.name="BoardActivities"
			col.add_child(row)
			var locked:Button=app.button("河岸釣魚會・渡口野餐後開放",app._fishmeet_menu)
			locked.name="FishingMeetEntry"
			locked.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			row.add_child(locked)
			var showcase:Button=app.button("家園布置題・渡口野餐後開放",app._showcase_menu)
			showcase.name="ShowcaseEntry"
			showcase.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			row.add_child(showcase)
	add_fund_controls(app,col,s)
	if s.get("picnic",false):
		col.add_child(app.button("群島的來信",dock_project.bind(app)))
		col.add_child(app.button("渡口舊磨坊",mill_project.bind(app,board.bind(app))))
	refresh_board_projects(app,s)

static func mill_project(app,back:Callable,target:=MillRestoration.BOARD)->void:
	var content:VBoxContainer=app._open_modal("渡口舊磨坊")
	app.modal.set_meta("life_modal_layout","chapter_letter")
	var paper:=card(content)
	var header:=HBoxContainer.new()
	header.add_theme_constant_override("separation",12)
	paper.add_child(header)
	add_icon(header,preload("res://scripts/bakery_art.gd").village_mill_texture(0),72)
	var summary:=line(app,header,"",17)
	summary.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	var repair:=VBoxContainer.new()
	paper.add_child(repair)
	var materials:={}
	for item:String in MillRestoration.COST:
		materials[item]=material_progress(app,repair,item,0,MillRestoration.COST[item])
	var donate:Button=app.button("交材料修磨坊",func():app.session.perform(MillRestoration.ACTION,target))
	repair.add_child(donate)
	var service:=VBoxContainer.new()
	paper.add_child(service)
	var status:=line(app,service,"",16)
	var buttons:={}
	for recipe:String in MillRestoration.RECIPES:
		var process:Dictionary=World.INDUSTRY.PROCESS[recipe]
		var ingredients:=PackedStringArray()
		for item:String in process.ingredients:ingredients.append("%s %d"%[World.NAMES[item],process.ingredients[item]])
		var use:Button=app.button("%s ×%d · %s"%[World.NAMES[recipe],process.yield,"＋".join(ingredients)],func():app.session.perform(MillRestoration.SERVICE,target,recipe))
		use.name="PublicMill_"+recipe
		buttons[recipe]=use
		service.add_child(use)
	var claim:Button=app.button("領取成品",func():app.session.perform(MillRestoration.SERVICE,target,"claim"))
	claim.name="PublicMillClaim"
	service.add_child(claim)
	content.add_child(app.button("返回",back))
	app.modal.set_meta("mill_project",{"summary":summary,"repair":repair,"materials":materials,"donate":donate,"service":service,"status":status,"buttons":buttons,"claim":claim,"target":target})
	refresh_mill_project(app)

static func refresh_mill_project(app)->void:
	if not is_instance_valid(app.modal) or not app.modal.has_meta("mill_project"):return
	var ui:Dictionary=app.modal.get_meta("mill_project")
	var s:Dictionary=app.session.snapshot
	var person_data:=player(app)
	var inventory:Dictionary=person_data.get("inventory",{})
	var near:=str(s.get("region_id",World.REGIONS.HOME))==World.REGIONS.HOME and Vector2(person_data.get("x",0),person_data.get("y",0)).distance_to(Vector2(ui.target)+Vector2(0.5,0.5))<=3.2
	var open:=MillRestoration.available(s)
	var ready:=MillRestoration.repaired(s)
	ui.summary.text="磨坊重新轉起來了。送入原料後，等一分鐘就能領取。" if ready else "阿榆想把渡口舊磨坊修好，讓鄰居都能磨小麥、做飼料。"
	if not open:ui.summary.text+=" 先和米露把公共廚房開張。"
	elif not near:ui.summary.text+=" 請走到磨坊門口，或到風鈴渡口公告板辦理。"
	ui.repair.visible=not ready
	ui.donate.disabled=not near or not open or MillRestoration.contribution(s,inventory).is_empty()
	ui.service.visible=ready
	for item:String in MillRestoration.COST:
		var collected:=int(s.get(MillRestoration.FIELD,{}).get(item,0))
		var row:Control=ui.materials[item]
		row.find_child("ProgressCaption",true,false).text="%s  %d / %d"%[World.NAMES[item],collected,MillRestoration.COST[item]]
		row.find_child("ProgressMeter",true,false).value=collected
	var job:Dictionary=person_data.get(MillRestoration.JOB,{})
	var waiting:=ceili(float(job.get("ready",0))-float(s.get("time",0)))
	ui.status.text="目前沒有加工中的原料" if job.is_empty() else "%s · %s"%[World.NAMES[job.kind],"剩下 %d 秒"%waiting if waiting>0 else "可領取"]
	ui.claim.disabled=not near or job.is_empty() or waiting>0
	for recipe:String in MillRestoration.RECIPES:
		var ingredients:Dictionary=World.INDUSTRY.PROCESS[recipe].ingredients
		ui.buttons[recipe].disabled=not near or not job.is_empty() or ingredients.keys().any(func(item):return int(inventory.get(item,0))<int(ingredients[item]))

static func board_activity_row(app) -> Container:
	if app.font_scale_factor()>1.0:
		var flow:=HFlowContainer.new()
		flow.add_theme_constant_override("h_separation",8)
		flow.add_theme_constant_override("v_separation",8)
		return flow
	var row:=HBoxContainer.new()
	row.add_theme_constant_override("separation",8)
	return row

static func refresh_board_projects(app,s:Dictionary) -> void:
	if not is_instance_valid(app.modal) or app.modal.get_meta("life_modal_layout","")!="community_board":return
	var donate:=app.modal.find_child("BoardDonateBridge",true,false) as Button
	if donate:
		var donations:Dictionary=s.get("donations",{})
		var bag:Dictionary=s.get("players",{}).get(app.session.own_id,{}).get("inventory",{})
		var wood:=int(donations.get("wood",0))
		var stone:=int(donations.get("stone",0))
		var cost:=World.CHAPTER_ONE.BOARD_COST
		var give:=World.CHAPTER_ONE.board_contribution(s,bag)
		update_project_meter(app.modal,"BridgeWood","wood",wood,cost.wood)
		update_project_meter(app.modal,"BridgeStone","stone",stone,cost.stone)
		var opened:bool=s.get("board",false)
		var materials:=PackedStringArray()
		if give.wood>0:materials.append("木材 %d"%give.wood)
		if give.stone>0:materials.append("石材 %d"%give.stone)
		donate.disabled=opened or materials.is_empty()
		donate.text="捐入 "+"、".join(materials) if not materials.is_empty() else "捐材料"
		var hint:=app.modal.find_child("BridgeDonationHint",true,false) as Label
		var gathering:=PackedStringArray()
		if wood+give.wood<cost.wood:gathering.append("%s 砍樹"%app.binding_label("axe"))
		if stone+give.stone<cost.stone:gathering.append("%s 敲岩石"%app.binding_label("pick"))
		hint.text="　".join(gathering)+"，走近撿材料。" if not gathering.is_empty() else ""
		if opened and not donate.has_meta("reopening"):
			donate.set_meta("reopening",true)
			# Switch to the completed project on either a local or remote donation.
			var board_panel:Control=app.modal
			var reopen:=func():
				if is_instance_valid(board_panel) and app.modal==board_panel:board(app)
			reopen.call_deferred()
	refresh_q05_card(app,s)
	refresh_board_picnic(app,s)

## Q05 河對岸的鈴聲: the compact project card under the Q03 card. Counts come from the server snapshot only;
## the button previews exactly what this backpack would give (server caps the same way) and sends `bridge_donate`.
static func q05_card(app,col:VBoxContainer,s:Dictionary) -> void:
	var stone=World.STONE_WORKSHOP
	var box:=card(col)
	box.name="BridgeProjectCard"
	line(app,box,"河對岸的鈴聲 · 河灣橋",20).name="BridgeProjectTitle"
	line(app,box,"",14).name="BridgeProjectGuide"
	material_progress(app,box,"wood",0,stone.WOOD_NEEDED).name="BridgeProjectWood"
	material_progress(app,box,"rope",0,stone.ROPE_NEEDED).name="BridgeProjectRope"
	var row:=HBoxContainer.new()
	row.name="BridgeProjectFoundation"
	row.add_theme_constant_override("separation",10)
	box.add_child(row)
	add_icon(row,ItemArt.icon("stone"),32)
	var details:=VBoxContainer.new()
	details.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	row.add_child(details)
	progress(app,details,"%s（每個石材 %d，石工台製作）"%[stone.FOUNDATION_NAME,int(stone.FOUNDATION_COST.stone)],0,stone.FOUNDATIONS_NEEDED)
	var donate:Button=app.button("捐給河灣橋",func():app.session.perform(stone.DONATE_ACTION,BOARD_CELL))
	donate.name="BoardDonateQ05"
	box.add_child(donate)
	line(app,box,"",14).name="BridgeProjectHint"
	refresh_q05_card(app,s)

static func refresh_q05_card(app,s:Dictionary) -> void:
	var box:=app.modal.find_child("BridgeProjectCard",true,false) as Control
	if box==null:return
	var stone=World.STONE_WORKSHOP
	if not stone.project_pending(s):
		# Completed (here or by a friend): rebuild the board once so it shows the opened bridge and the fishing spot.
		if not box.has_meta("reopening"):
			box.set_meta("reopening",true)
			var board_panel:Control=app.modal
			var reopen:=func():
				if is_instance_valid(board_panel) and app.modal==board_panel:board(app)
			reopen.call_deferred()
		return
	var project:Dictionary=s.get(stone.PROJECT_KEY,{})
	var bag:Dictionary=s.get("players",{}).get(app.session.own_id,{}).get("inventory",{})
	var wood:=int(project.get("wood",0))
	var rope:=int(project.get("rope",0))
	var foundations:=int(project.get("foundations",0))
	update_project_meter(app.modal,"BridgeProjectWood","wood",wood,stone.WOOD_NEEDED)
	update_project_meter(app.modal,"BridgeProjectRope","rope",rope,stone.ROPE_NEEDED)
	var found_row:=app.modal.find_child("BridgeProjectFoundation",true,false) as Control
	(found_row.find_child("ProgressCaption",true,false) as Label).text="%s  %d / %d（每個石材 %d，石工台製作）"%[stone.FOUNDATION_NAME,foundations,stone.FOUNDATIONS_NEEDED,int(stone.FOUNDATION_COST.stone)]
	(found_row.find_child("ProgressMeter",true,false) as ProgressBar).value=foundations
	var gift:Dictionary=stone.contribution(s,bag)
	var parts:=PackedStringArray()
	if int(gift.wood)>0:parts.append("木材 %d"%int(gift.wood))
	if int(gift.rope)>0:parts.append("繩索 %d"%int(gift.rope))
	var donate:=app.modal.find_child("BoardDonateQ05",true,false) as Button
	donate.disabled=parts.is_empty()
	donate.text="捐入 "+"、".join(parts) if not parts.is_empty() else "捐給河灣橋"
	var missing:Dictionary=stone.missing(s)
	var next:=PackedStringArray()
	var sourcing:=PackedStringArray()
	if int(missing.wood)>0:sourcing.append("木材按 %s 砍樹"%app.binding_label("axe"))
	if int(missing.rope)>0:sourcing.append("草叢纖維可在背包手作繩索（5 纖維做 1 繩）")
	if not sourcing.is_empty():next.append("。".join(sourcing)+"。")
	if int(missing.foundations)>0:
		if World.STONE_WORKSHOP.has_station(s.get("objects",{})):next.append("到家園的石工台製作橋基。")
		else:next.append("在建造選單蓋石工台（20 石材、8 木材）。石材可到東北採石點找。")
	(app.modal.find_child("BridgeProjectGuide",true,false) as Label).text="在公告板捐木材與繩索，到石工台製作橋基。備齊後，東岸與新釣點就能開放。"
	(app.modal.find_child("BridgeProjectHint",true,false) as Label).text="\n".join(next)

static func update_project_meter(panel:Control,row_name:String,item:String,amount:int,goal:int) -> void:
	var row:=panel.find_child(row_name,true,false)
	var caption:=row.find_child("ProgressCaption",true,false) as Label
	var meter:=row.find_child("ProgressMeter",true,false) as ProgressBar
	caption.text="%s  %d / %d"%[World.NAMES[item],amount,goal]
	meter.value=amount

static func refresh_board_picnic(app,s:Dictionary) -> void:
	var serve:=app.modal.find_child("BoardServePicnic",true,false) as Button
	if serve==null:return
	var dishes:Dictionary=s.get("picnic_materials",{})
	var complete:bool=s.get("picnic",false)
	for item in [["soup","PicnicSoup",2],["bread","PicnicBread",1]]:
		update_project_meter(app.modal,item[1],item[0],int(dishes.get(item[0],0)),item[2])
	var contribution:=World.CHAPTER_ONE.picnic_contribution(s,app.session.own_id)
	var hint:=app.modal.find_child("PicnicContributionHint",true,false) as Label
	serve.disabled=contribution.is_empty()
	if complete:
		serve.text="野餐料理已上桌"
		hint.text="可以開始參加渡口活動。小栗還有下一站的消息。"
		for entry in [["SouvenirEntry",preload("res://scripts/souvenir_exchange_ui.gd").entry_caption(true)],
			["FishingMeetEntry","河岸釣魚會（河灣橋南岸）"],["ShowcaseEntry","家園布置題（渡口西南草地）"]]:
			var button:=app.modal.find_child(entry[0],true,false) as Button
			if button:button.text=entry[1]
	else:
		var portions:=PackedStringArray()
		var remaining:=PackedStringArray()
		for item in World.CHAPTER_ONE.PICNIC_PORTIONS:
			var amount:=int(contribution.get(item,0))
			var need:=int(World.CHAPTER_ONE.PICNIC_PORTIONS[item])-int(dishes.get(item,0))-amount
			if amount>0:portions.append("%s ×%d"%[World.NAMES[item],amount])
			if need>0:remaining.append("%s ×%d"%[World.NAMES[item],need])
		serve.text="先到小石灶準備料理" if serve.disabled else "端上料理"
		if serve.disabled:hint.text="桌上還缺 "+"、".join(remaining)
		else:
			hint.text="這次端上 "+"、".join(portions)
			if not remaining.is_empty():hint.text+="。之後還缺 "+"、".join(remaining)

static func dock_route_description(snapshot:Dictionary) -> String:
	if World.TRANSIT.tea_unlocked(snapshot):
		return "到渡口站牌搭合作小船，直達霧竹溪谷或暖泉高地。兩地的站牌都能搭小船回渡口。"
	return "到渡口站牌搭合作小船，可往返暖泉高地。茶園路線開放後也能航往霧竹溪谷。"

static func dock_project_status(snapshot:Dictionary) -> Array:
	return [snapshot.get("dock_stage",0),snapshot.get("dock_project_started",false),snapshot.get("can_start_large_projects"),
		World.CHAPTER_ONE.phase(snapshot)=="complete" and snapshot.get("flower_nursery",{}).get("garden",{}).get("complete",false)]

static func dock_project(app,from_news:=false) -> void:
	var body:VBoxContainer=app._open_modal("第四章・群島的來信")
	app.modal.set_meta("life_modal_layout","community_board")
	var snapshot:Dictionary=app.session.snapshot
	app.modal.set_meta("dock_project_status",dock_project_status(snapshot))
	app.modal.set_meta("dock_project_from_news",from_news)
	var stage:=int(snapshot.get("dock_stage",0))
	if stage>=World.DOCK_REPAIRS.size():
		line(app,body,"碼頭與小船都修好了。",20)
		line(app,body,dock_route_description(snapshot),18)
		var commissions:Dictionary=snapshot.get("own_outlying_commissions",{})
		for id:String in World.OUTLYING_COMMISSIONS.ids():
			var definition:Dictionary=World.OUTLYING_COMMISSIONS.DEFS[id]
			var record:Dictionary=commissions.get(id,{})
			var letter:=card(body)
			line(app,letter,str(definition.place)+"・"+str(definition.title),16)
			if record.get("done",false):
				line(app,letter,"已交件 · "+str(definition.thanks),15)
			else:
				line(app,letter,str(definition.hint)+" 到當地接駁站交件。",15)
	else:
		line(app,body,"修復渡口碼頭" if stage==0 else "修復渡口小船",20)
		var inventory:Dictionary=player(app).get("inventory",{})
		var cost:Dictionary=World.DOCK_REPAIRS[stage]
		for item in cost:material_progress(app,body,item,int(inventory.get(item,0)),cost[item])
		var ready:bool=app.modal.get_meta("dock_project_status")[3]
		if not ready:line(app,body,"渡口故事與田尾公共花園完成後，大家就能開始修碼頭。",15)
		var waiting:bool=snapshot.has("can_start_large_projects") and stage==0 and not snapshot.get("dock_project_started",false)
		if waiting and snapshot.can_start_large_projects:
			var launch:Button=app.button("宣布碼頭工程開工",func():
				app.session.perform("dock_project_start",BOARD_CELL);app._close_modal())
			launch.disabled=not ready
			body.add_child(launch)
		if waiting and not snapshot.can_start_large_projects:
			line(app,body,"等島主或管理員宣布開工後，就能交付材料。",15)
		var submit:Button=app.button("交付這期工程材料",func():
			app.session.perform("dock_repair",BOARD_CELL,str(stage));app._close_modal())
		submit.disabled=not ready or waiting
		body.add_child(submit)
	if from_news:body.add_child(app.button("返回島嶼近況",island_news.bind(app)))
	else:body.add_child(app.button("返回公共工程",app._board))

static func add_fund_controls(app,col:VBoxContainer,snapshot:Dictionary)->void:
	var fund:=card(col)
	line(app,fund,"公共基金",18)
	var info:Dictionary=snapshot.get("public_fund",{})
	var balance:=int(info.get("balance",0))
	line(app,fund,"餘額 %d 鈴幣 · 你的累計捐款 %d"%[balance,int(info.get("own_given",0))],15)
	var buttons:=HBoxContainer.new()
	fund.add_child(buttons)
	for amount:String in World.FUND_DONATIONS:
		var donate:Button=app.button("捐 %s"%amount,func():app.session.perform("fund_donate",BOARD_CELL,amount);app._close_modal())
		donate.name="FundDonate"+amount
		donate.disabled=int(player(app).get("coins",0))<int(amount)
		buttons.add_child(donate)
	if not snapshot.get("board",false):
		var price:=World.bridge_fund_cost(snapshot)
		var pay:Button=app.button("用基金補齊橋梁材料 · %d 鈴幣"%price,func():app.session.perform("fund_bridge",BOARD_CELL);app._close_modal())
		pay.disabled=balance<price
		fund.add_child(pay)

static func player(app) -> Dictionary:
	return app.session.snapshot.get("players",{}).get(app.session.own_id,{})

static func story_stage(person:Dictionary,id:String) -> int:
	return clampi(int(person.get("stories",{}).get(id,0)),0,Village.QUESTS[id].size())

static func card(parent:Container) -> VBoxContainer:
	var panel:=PanelContainer.new()
	panel.add_theme_stylebox_override("panel",PixelTheme.paper_style())
	parent.add_child(panel)
	var rows:=VBoxContainer.new()
	rows.add_theme_constant_override("separation",8)
	panel.add_child(rows)
	return rows

static func line(app,parent:Container,value:String,font_size:int) -> Label:
	var label:Label=app.label(value,font_size)
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	return label

static func add_resident_dialogue(app, parent: Container, id: String) -> void:
	var snapshot: Dictionary = app.session.snapshot
	var quote := ResidentStories.dialogue(snapshot.get("resident_memories",[]),id,str(snapshot.get("region_id","home")),snapshot.get("resident_participation",{}))
	if not quote.is_empty():line(app,parent,"「"+quote+"」",16)

## T066 好感：只讀自己的摘要（snapshot.resident_bonds），其他島民的進度不會送來。
static func bond_view(app,id:String) -> Dictionary:
	var bonds:Variant=app.session.snapshot.get("resident_bonds",{})
	var found:Variant=bonds.get(id,{}) if bonds is Dictionary else {}
	return found if found is Dictionary else {}

static func bond_text(bond:Dictionary) -> String:
	var stage:=int(bond.get("stage",0))
	if stage>=Bond.STAGES.size():return "好感・%s（四階事件都已展開）"%Bond.STAGES.back()
	return "好感・%s  %d／%d"%[str(bond.get("stage_name",Bond.stage_name(stage))),int(bond.get("points",0)),int(bond.get("next",Bond.THRESHOLDS[stage]))]

static func add_bond_controls(app,section:Container,actions:Container,id:String) -> void:
	add_forest_commission(app,actions,id,app._resident_menu.bind(id))
	var bond:=bond_view(app,id)
	if bond.is_empty():return
	var summary:Label=app.label(bond_text(bond),15)
	summary.name="BondSummary"
	section.add_child(summary)
	var cell:Vector2i=World.bond_place(app.session.snapshot,id)[1]
	var talked:bool=bond.get("talked_today",false)
	var talk:Button=app.button("今天聊過了" if talked else "聊聊近況",func():app.session.perform("resident_talk",cell,id);app._close_modal())
	talk.name="BondTalk"
	talk.disabled=talked
	actions.add_child(talk)
	var gift:Button=app.button("送禮物",bond_gifts.bind(app,id))
	gift.name="BondGift"
	actions.add_child(gift)
	add_paint_invitation(app,actions,id,cell)
	add_postcard_clue(app,actions,id,cell,int(bond.get("stage",0)))
	if id=="aru":add_aru_rest_controls(app,actions,int(bond.get("stage",0)))

## T066 N01-3：長椅按鈕只依伺服器 snapshot 決定。
## 已入座→起身；有人坐在主位且還有空位→加入；閒置→信任達標者可以先坐。
## 舊伺服器沒有 aru_bench_scene 欄位時，退回原本的 stage／aru_bench_open 判斷。
static func add_aru_rest_controls(app,actions:Container,stage:int) -> void:
	var snapshot:Dictionary=app.session.snapshot
	var own:String=app.session.own_id
	var button:Button=null
	if AruRest.seated(snapshot,own):
		button=app.button("起身",aru_leave.bind(app))
		button.name="AruRise"
	elif AruRest.joinable(snapshot,own):
		button=app.button("加入阿榆的長椅",aru_rest.bind(app))
		button.name="AruRest"
	elif not AruRest.active(snapshot) and (stage>=3 or (not snapshot.has(AruRest.FIELD) and snapshot.get("aru_bench_open",false))):
		button=app.button("坐到阿榆身旁",aru_rest.bind(app))
		button.name="AruRest"
	if button!=null:actions.add_child(button)

static func add_forest_commission(app,actions:Container,id:String,back:Callable) -> void:
	if id!=World.FOREST_MUSHROOM.RESIDENT or not World.FOREST_MUSHROOM.open(app.session.snapshot):return
	var forest:Button=app.button("林間的濕氣（森林菇湯）",preload("res://scripts/forest_mushroom_ui.gd").open.bind(app,back))
	forest.name="ForestMushroomCommission"
	actions.add_child(forest)

static func aru_park(app) -> void:
	var snapshot:Dictionary=app.session.snapshot
	var body:VBoxContainer=app._open_modal("有人坐的地方")
	app.modal.set_meta("life_modal_layout","keepsake_paper")
	var tools:=card(body)
	var can_help:=int(bond_view(app,"aru").get("stage",0))>=4
	var ready:=true
	for kind:String in Goals.ARU_PARK_SLOTS:
		var name:String=World.BUILD[kind].name
		if Goals.aru_park_has(snapshot.objects,kind):
			line(app,tools,"✓ "+name,17)
			continue
		ready=false
		var slot:Vector2i=Goals.ARU_PARK_SLOTS[kind]
		var key:=World.key(slot)
		if snapshot.objects.has(key) or snapshot.crops.has(key) or snapshot.get("forest",{}).has(key):
			line(app,tools,"%s的位置已有東西，請先清出這一格。"%name,16)
			continue
		var cost:=PackedStringArray()
		for item:String in World.BUILD[kind]:
			if item!="name":cost.append("%s %d"%[World.NAMES[item],World.BUILD[kind][item]])
		var place:Button=app.button("放置%s · %s"%[name,"、".join(cost)],func():
			app.session.perform(Goals.ARU_PARK_PLACE,slot,kind)
			app._close_modal())
		place.name="AruParkPlace_"+kind
		place.disabled=not can_help
		tools.add_child(place)
	if not can_help:line(app,body,"成為阿榆的好友後，可以加入布置。",16)
	elif ready:
		var photo:Button=app.button("拍一張照片",aru_take_photo.bind(app))
		photo.name="AruParkPhoto"
		body.add_child(photo)
	add_aru_album_photo(app,body,160)

static func add_aru_album_photo(app,body:Container,height:float) -> bool:
	var path:=aru_photo_path(app)
	AruParkPhoto.recover_album(path)
	if not FileAccess.file_exists(path):return false
	var image:=Image.load_from_file(path)
	if image==null or image.is_empty():return false
	var photo_frame:=TextureRect.new()
	photo_frame.name="AruAlbumPhoto"
	photo_frame.texture=ImageTexture.create_from_image(image)
	photo_frame.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	photo_frame.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	photo_frame.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	photo_frame.custom_minimum_size.y=height
	body.add_child(photo_frame)
	return true

static func aru_park_album(app) -> void:
	var body:VBoxContainer=app._open_modal("渡口長椅相簿")
	app.modal.set_meta("life_modal_layout","keepsake_paper")
	if not add_aru_album_photo(app,body,250):
		line(app,body,"這台裝置還沒有留影。到渡口長椅旁可以再拍一張。",16)
	body.add_child(app.button("返回關係事件",bond_goal.bind(app,"aru",4)))

static func aru_photo_path(app) -> String:
	return "user://aru-public-bench-%s.png"%str(app.session.own_id).sha256_text().left(24)

static func capture_island_photo(app,path:String,framing:=1.0) -> bool:
	var viewport:Viewport=app.get_viewport()
	if DisplayServer.get_name()=="headless":return false
	var was_visible:bool=app.hud.visible
	var toast_was_visible:bool=app.toast.visible
	app.hud.hide()
	app.toast.hide()
	app.view.photograph_mode=true
	app.view.queue_redraw()
	await RenderingServer.frame_post_draw
	var image:=viewport.get_texture().get_image()
	if was_visible:app.hud.show()
	app.toast.visible=toast_was_visible and app.toast_time>0
	app.view.photograph_mode=false
	app.view.queue_redraw()
	if image!=null and framing<1.0:
		var size:=Vector2i(Vector2(image.get_size())*framing)
		image=image.get_region(Rect2i((image.get_size()-size)/2,size))
	return image!=null and image.save_png(path)==OK

## 「拍一張照片」只開預覽：不寫檔、不送進度；確認後才由 AruParkPhoto 流程處理（見 aru_park_photo.gd）。
static func aru_take_photo(app) -> void:
	await AruParkPhoto.open(app,aru_photo_path(app),aru_park.bind(app))

## 送出「坐下／加入」請求後直接關閉選單，讓玩家在世界裡看見伺服器確認的場景；
## 這裡不先假設成功，入座回饋由 main.gd 比對前後 snapshot 後顯示（AruRest.transition_notice）。
## 位置一律用阿榆實際所在格，不是長椅 anchor。
static func aru_rest(app) -> void:
	app.session.perform(Goals.ARU_REST_ACTION,AruRest.aru_cell(app.session.snapshot))
	app._close_modal()

static func aru_leave(app) -> void:
	app.session.perform(AruRest.LEAVE_ACTION,AruRest.aru_cell(app.session.snapshot))
	app._close_modal()

static func copper_flower_rack(app,cell:Vector2i,obj:Dictionary) -> void:
	var body:VBoxContainer=app._open_modal("銅框花架")
	app.modal.set_meta("life_modal_layout","inn_tea_table")
	var industry:=World.INDUSTRY
	var pots:Array=obj.get("rack_pots",["","",""])
	var own:bool=obj.get("owner")==app.session.own_id
	var tray:=HBoxContainer.new()
	tray.add_theme_constant_override("separation",8)
	body.add_child(tray)
	var picker:OptionButton
	if own and "" in pots:
		var bag:Dictionary=player(app).get("inventory",{})
		if int(bag.get(industry.POT_RACK_EMPTY,0))>0:
			picker=OptionButton.new()
			picker.name="CopperRackPicker"
			for flower:String in [industry.POT_RACK_EMPTY]+industry.POT_RACK_FLOWERS:
				if int(bag.get(flower,0))<1:continue
				picker.add_item("只擺陶花盆" if flower==industry.POT_RACK_EMPTY else World.NAMES[flower])
				picker.set_item_metadata(picker.item_count-1,flower)
			body.add_child(picker)
		else:line(app,body,"背包有陶花盆後，就能在空位擺上盆花。",15)
	for index in industry.POT_RACK_SLOTS:
		var pot:String=pots[index]
		var section:=card(tray)
		(section.get_parent() as Control).size_flags_horizontal=Control.SIZE_EXPAND_FILL
		if not pot.is_empty():
			var preview:=ItemArt.icon(pot)
			if pot==industry.POT_RACK_EMPTY:
				var bare:=AtlasTexture.new()
				bare.atlas=preview
				bare.region=Rect2(4,18,24,13)
				preview=bare
			add_icon(section,preview,42)
		var caption:=line(app,section,"空展示位" if pot.is_empty() else World.NAMES[pot],16)
		caption.name="CopperRackSlot_%d"%index
		caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		if not own:continue
		var button:Button
		if pot.is_empty():
			button=app.button("擺在這裡",func():
				var choice:String=picker.get_item_metadata(picker.selected)
				app.session.perform(industry.POT_RACK_PUT,cell,"%d:%s"%[index,choice])
				app._close_modal())
			button.name="CopperRackPut_%d"%index
			button.disabled=picker==null
		else:
			button=app.button("收回花盆",func():
				app.session.perform(industry.POT_RACK_TAKE,cell,str(index))
				app._close_modal())
			button.name="CopperRackTake_%d"%index
		section.add_child(button)
	app.LifeShell.reveal(app,tray)

static func mushroom_mailbox(app,cell:Vector2i,box:Dictionary)->void:
	var body:VBoxContainer=app._open_modal("蘑菇門邊郵箱")
	app.modal.set_meta("life_modal_layout","mushroom_mail")
	if box.get("owner")!=app.session.own_id:
		line(app,body,"這是另一位島民的郵箱。",16)
		return
	var layout:=HBoxContainer.new()
	layout.add_theme_constant_override("separation",14)
	body.add_child(layout)
	var inbox:=card(layout)
	inbox.custom_minimum_size.x=245
	var total:Label=app.label("",16)
	total.name="MushroomMailCount"
	inbox.add_child(total)
	var letter:=card(layout)
	(letter.get_parent() as Control).size_flags_horizontal=Control.SIZE_EXPAND_FILL
	add_icon(letter,app.LifeShell.icon("letter"),48)
	var heading:Label=app.label("選一封信",22)
	heading.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	letter.add_child(heading)
	var message:Label=app.label("",17)
	message.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	letter.add_child(message)
	var parcel:Label=app.label("",16)
	parcel.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	letter.add_child(parcel)
	var selection:={"id":""}
	var claim:Button=app.button("領取包裹",func():
		app.session.perform(World.MUSHROOM_MAIL.CLAIM,cell,selection.id))
	claim.name="MushroomMailClaim"
	letter.add_child(claim)
	var entries:Dictionary={}
	for id:String in World.MUSHROOM_MAIL.LETTERS:
		var button:Button=app.button("",func():
			selection.id=id
			refresh_mushroom_mailbox(app)
			if app.session.snapshot.get("own_mushroom_mail",{}).get(id)=="new":
				app.session.perform(World.MUSHROOM_MAIL.READ,cell,id))
		button.name="MushroomLetter_"+id
		button.toggle_mode=true
		entries[id]=button
		inbox.add_child(button)
	var refresh:=func():
		var current:Dictionary=app.session.snapshot.get("objects",{}).get(World.key(cell),{})
		var active:bool=current.get("type")==World.INDUSTRY.MUSHROOM_POST and current.get("owner")==app.session.own_id
		var in_mail:Dictionary=app.session.snapshot.get("own_mushroom_mail",{}) if active else {}
		total.text="%d 封信 · %d 封未讀"%[in_mail.size(),in_mail.values().count("new")] if active else "郵箱已搬離"
		for id:String in entries:
			var entry:Button=entries[id]
			var data:Dictionary=World.MUSHROOM_MAIL.LETTERS[id]
			entry.visible=in_mail.has(id)
			var flag:String={"new":"未讀","read":"已讀","claimed":"已領取"}.get(in_mail.get(id),"")
			entry.text="%s  ·  %s\n%s"%[data.sender,flag,data.title]
			entry.set_pressed_no_signal(id==selection.id)
		var selected:Dictionary=World.MUSHROOM_MAIL.LETTERS.get(selection.id,{}) if in_mail.has(selection.id) else {}
		heading.text=selected.get("title","選一封信")
		message.text=selected.get("body","")
		parcel.visible=not selected.get("items",{}).is_empty()
		claim.visible=parcel.visible
		var received:bool=in_mail.get(selection.id)=="claimed"
		claim.disabled=received or not active
		claim.text="已領取包裹" if received else "領取包裹"
		if parcel.visible:
			var names:=PackedStringArray()
			for item:String in selected.items:names.append("%s ×%d"%[World.NAMES[item],selected.items[item]])
			parcel.text="、".join(names)
	app.modal.set_meta("refresh_mushroom_mail",refresh)
	refresh.call()

static func refresh_mushroom_mailbox(app)->void:
	if is_instance_valid(app.modal) and app.modal.has_meta("refresh_mushroom_mail"):
		var update:Callable=app.modal.get_meta("refresh_mushroom_mail")
		update.call()

static func leaf_desk(app,cell:Vector2i) -> void:
	var body:VBoxContainer=app._open_modal("落葉書桌")
	app.modal.set_meta("life_modal_layout","leaf_desk")
	var input:=LineEdit.new()
	input.name="LeafDeskDraft"
	input.max_length=World.ISLAND_NOTES.LENGTH
	input.placeholder_text="想留給島民的話，可以先寫在這裡"
	var person:Dictionary=app.session.snapshot.get("players",{}).get(app.session.own_id,{})
	input.text=person.get(World.INDUSTRY.DESK_DRAFT_FIELD,"")
	input.add_theme_font_size_override("font_size",20)
	body.add_child(input)
	var state:Label=app.label("",15)
	state.name="LeafDeskState"
	body.add_child(state)
	var actions:=HBoxContainer.new()
	actions.add_theme_constant_override("separation",8)
	body.add_child(actions)
	var save:Button=app.button("儲存草稿",func():
		app.session.perform(World.INDUSTRY.DESK_DRAFT_ACTION,cell,input.text))
	save.name="LeafDeskSave"
	save.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	actions.add_child(save)
	var journal_link:Button=app.button("翻開島民手冊",func():app._journal())
	journal_link.name="LeafDeskJournal"
	journal_link.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	actions.add_child(journal_link)
	line(app,body,"草稿只供自己查看。要分享時，可在島民留言板帶入草稿再貼出。",16)
	input.text_changed.connect(func(_text:String):refresh_leaf_desk(app))
	input.text_submitted.connect(func(_text:String):
		if not save.disabled:save.pressed.emit())
	refresh_leaf_desk(app)

static func refresh_leaf_desk(app) -> void:
	if not is_instance_valid(app.modal) or app.modal.get_meta("life_modal_layout","")!="leaf_desk":return
	var input:=app.modal.find_child("LeafDeskDraft",true,false) as LineEdit
	var state:=app.modal.find_child("LeafDeskState",true,false) as Label
	var save:=app.modal.find_child("LeafDeskSave",true,false) as Button
	if input==null or state==null or save==null:return
	var person:Dictionary=app.session.snapshot.get("players",{}).get(app.session.own_id,{})
	var stored:String=person.get(World.INDUSTRY.DESK_DRAFT_FIELD,"")
	var clean:=World.ISLAND_NOTES.clean(input.text)
	var invalid:=clean.is_empty() and not input.text.is_empty()
	save.disabled=invalid or clean==stored
	save.text="清除草稿" if clean.is_empty() and not stored.is_empty() else "儲存草稿"
	var status:="尚未儲存" if clean!=stored else ("已儲存" if not stored.is_empty() else "沒有草稿")
	if invalid:status="請輸入可儲存的文字"
	state.text="%s · %d / %d 字"%[status,input.text.length(),World.ISLAND_NOTES.LENGTH]

static func bark_frame(app,cell:Vector2i,frame:Dictionary) -> void:
	var body:VBoxContainer=app._open_modal("樹皮畫框")
	app.modal.set_meta("life_modal_layout","bark_frame")
	var art:=preload("res://scripts/bark_frame_art.gd")
	var value:String=frame.get(World.BARK_FRAME.FIELD,"")
	var picture:=art.content(value)
	var row:=HBoxContainer.new()
	row.add_theme_constant_override("separation",14)
	body.add_child(row)
	var display:=VBoxContainer.new()
	display.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	row.add_child(display)
	var preview:=TextureRect.new()
	preview.name="BarkFramePicture"
	preview.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	preview.custom_minimum_size=Vector2(220,144)
	preview.texture=picture if picture!=null else art.FRAME
	display.add_child(preview)
	var caption:Label=app.label("點點・畫著放鬆的手" if value==World.BARK_FRAME.SKETCH else ("島上留影" if picture!=null else "尚未展示"),17)
	caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	display.add_child(caption)
	if frame.get("owner")!=app.session.own_id:return
	var controls:=VBoxContainer.new()
	controls.custom_minimum_size.x=235
	controls.add_theme_constant_override("separation",6)
	row.add_child(controls)
	var choose_sketch:Button=app.button("掛上點點的速寫",func():
		app.session.perform(World.BARK_FRAME.ACTION,cell,World.BARK_FRAME.SKETCH)
		app._close_modal())
	choose_sketch.name="BarkFrameSketch"
	choose_sketch.disabled=app.session.snapshot.get("resident_goals",{}).get("diandian",{}).get("2",{}).get("state")!="done"
	choose_sketch.tooltip_text="完成點點的第二段故事後可展示。"
	controls.add_child(choose_sketch)
	var photos:Dictionary={
		"長椅相簿":aru_photo_path(app),
		"阿潮船上合照":achao_photo_path(app),
		"暖泉旅舍合照":inn_photo_path(app),
		"柴犬合照":app.LifeAlmanac.dog_photo_path(app),
		"南岸海豹合照":app.LifeAlmanac.seal_photo_path(app),
	}
	var saved:=0
	for title:String in photos:
		var path:String=photos[title]
		if not FileAccess.file_exists(path):continue
		saved+=1
		var choose:Button=app.button(title,_hang_saved_photo.bind(app,cell,path))
		choose.name="BarkPhoto_"+str(photos.keys().find(title))
		controls.add_child(choose)
	app.modal.set_meta("photo_choices",saved)
	if saved>0:line(app,controls,"同島玩家看得到掛上的照片。",14)
	else:line(app,controls,"在旅舍、長椅或與動物合照後，可從這裡選照片。",14)
	if not value.is_empty():
		var clear:Button=app.button("收起展示",func():
			app.session.perform(World.BARK_FRAME.ACTION,cell)
			app._close_modal())
		clear.name="BarkFrameClear"
		controls.add_child(clear)

static func _hang_saved_photo(app,cell:Vector2i,path:String) -> void:
	var image:=Image.load_from_file(path)
	var value:=World.BARK_FRAME.from_image(image)
	if value.is_empty():
		app._notice("這張照片無法讀取。",false)
		return
	app.session.perform(World.BARK_FRAME.ACTION,cell,value)
	app._close_modal()

static func leaf_mat_colors(app,cell:Vector2i,mat:Dictionary) -> void:
	var body:VBoxContainer=app._open_modal("葉片地墊")
	app.modal.set_meta("life_modal_layout","leaf_mat")
	var art:=preload("res://scripts/leaf_mat_art.gd")
	var current:String=mat.get("leaf_mat_shade","light")
	var swatches:=HBoxContainer.new()
	swatches.add_theme_constant_override("separation",8)
	body.add_child(swatches)
	for shade:String in World.INDUSTRY.MAT_SHADES:
		var swatch:=card(swatches)
		(swatch.get_parent() as Control).size_flags_horizontal=Control.SIZE_EXPAND_FILL
		var preview:=TextureRect.new()
		preview.custom_minimum_size=Vector2(64,64)
		preview.texture=art.TEXTURE
		preview.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
		preview.stretch_mode=TextureRect.STRETCH_KEEP_CENTERED
		preview.modulate=art.tint(shade)
		swatch.add_child(preview)
		var title:String=World.INDUSTRY.MAT_SHADES[shade]
		var option:Button=app.button(title+"（目前）" if shade==current else title,func():
			app.session.perform(World.INDUSTRY.MAT_SHADE_ACTION,cell,shade)
			app._close_modal())
		option.name="LeafMat_"+shade
		option.disabled=shade==current
		swatch.add_child(option)
	app.LifeShell.reveal(app,swatches)

static func vine_arch_colors(app,cell:Vector2i,obj:Dictionary) -> void:
	var body:VBoxContainer=app._open_modal("藤蔓花門")
	app.modal.set_meta("life_modal_layout","inn_tea_table")
	var industry:=World.INDUSTRY
	var art:=preload("res://scripts/vine_arch_art.gd")
	var current:String=obj.get("vine_color","pink")
	var own:bool=obj.get("owner")==app.session.own_id
	var swatches:=HBoxContainer.new()
	swatches.add_theme_constant_override("separation",8)
	body.add_child(swatches)
	for color:String in industry.VINE_COLORS:
		if not own and color!=current:continue
		var swatch:=card(swatches)
		(swatch.get_parent() as Control).size_flags_horizontal=Control.SIZE_EXPAND_FILL
		add_icon(swatch,art.image(color),92)
		var name:String=industry.VINE_COLORS[color]
		if own:
			var button:Button=app.button(name,func():
				app.session.perform(industry.VINE_COLOR_ACTION,cell,color)
				app._close_modal())
			button.name="VineColor_"+color
			button.disabled=color==current
			swatch.add_child(button)
		else:line(app,swatch,name,17)
	app.LifeShell.reveal(app,swatches)

static func small_aquarium(app,cell:Vector2i,obj:Dictionary) -> void:
	var body:VBoxContainer=app._open_modal("小型觀賞魚缸")
	app.modal.set_meta("life_modal_layout","return_news")
	var industry:=World.INDUSTRY
	var fish:=industry.AQUARIUM_FISH
	var has_fish:bool=obj.get("items",{}).has(fish)
	var page:=card(body)
	var row:=HBoxContainer.new()
	row.add_theme_constant_override("separation",12)
	page.add_child(row)
	add_icon(row,ItemArt.icon(fish) if has_fish else preload("res://assets/ui-life/small-aquarium.png"),56)
	var notes:=VBoxContainer.new()
	notes.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	row.add_child(notes)
	line(app,notes,World.FISH[fish].name if has_fish else "魚缸空著",20)
	line(app,notes,"住著一尾紅尾小鯉，不用餵食。" if has_fish else "到渡口的河邊釣一尾紅尾小鯉，就能放進來。",15)
	app.LifeShell.reveal(app,page)
	if obj.get("owner")!=app.session.own_id:return
	var control:Button=app.button("取回紅尾小鯉" if has_fish else "放入紅尾小鯉",func():
		app.session.perform(industry.AQUARIUM_TAKE if has_fish else industry.AQUARIUM_STOCK,cell)
		app._close_modal())
	control.name="AquariumTake" if has_fish else "AquariumStock"
	control.disabled=not has_fish and int(player(app).get("inventory",{}).get(fish,0))<1
	body.add_child(control)

static func fish_counter(app,cell:Vector2i) -> void:
	var body:VBoxContainer=app._open_modal("冰藍魚貨台")
	app.modal.set_meta("life_modal_layout","fish_counter")
	var slots:=HBoxContainer.new()
	slots.add_theme_constant_override("separation",10)
	body.add_child(slots)
	var box:Dictionary=app.session.snapshot.get("objects",{}).get(World.key(cell),{})
	var own:bool=box.get("owner","")==app.session.own_id
	var cards:Array[Dictionary]=[]
	for index in World.INDUSTRY.COUNTER_CAPACITY:
		var tray:=card(slots)
		(tray.get_parent() as Control).size_flags_horizontal=Control.SIZE_EXPAND_FILL
		var icon:=TextureRect.new()
		icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
		icon.custom_minimum_size=Vector2(48,48)
		tray.add_child(icon)
		var title:=line(app,tray,"空展示位",17)
		title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		var take:Button
		if own:
			take=app.button("取回",func():
				var items:=World.INDUSTRY.counter_fish(app.session.snapshot.get("objects",{}).get(World.key(cell),{}))
				if index<items.size():app.session.perform(World.INDUSTRY.COUNTER_TAKE,cell,items[index]))
			take.name="FishCounterTake_%d"%index
			tray.add_child(take)
		cards.append({"icon":icon,"title":title,"take":take})
	var picker:=OptionButton.new()
	var put:Button
	if own:
		var actions:=HBoxContainer.new()
		body.add_child(actions)
		picker.name="FishCounterPicker"
		picker.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		actions.add_child(picker)
		put=app.button("放上展示台",func():
			if picker.selected>=0:
				app.session.perform(World.INDUSTRY.COUNTER_PUT,cell,str(picker.get_item_metadata(picker.selected))))
		put.name="FishCounterPut"
		actions.add_child(put)
	else:picker.free()
	line(app,body,"漁獲可以一直留在冰面上。要料理或出貨時，再取回背包。",14)
	app.modal.set_meta("fish_counter_ui",{"region":app.session.snapshot.get("region_id","home"),"tile":World.key(cell),"cards":cards,"picker":picker if own else null,"put":put,"bag":{}})
	refresh_fish_counter(app)

static func refresh_fish_counter(app) -> void:
	if not is_instance_valid(app.modal) or not app.modal.has_meta("fish_counter_ui"):return
	var ui:Dictionary=app.modal.get_meta("fish_counter_ui")
	var snapshot:Dictionary=app.session.snapshot
	var counter:Dictionary=snapshot.get("objects",{}).get(ui.tile,{})
	if counter.get("type")!=World.INDUSTRY.COAST_FISH_COUNTER or snapshot.get("region_id","home")!=ui.region:
		app._close_modal()
		return
	var displayed:=World.INDUSTRY.counter_fish(counter)
	for i in ui.cards.size():
		var slot:Dictionary=ui.cards[i]
		var fish:String=displayed[i] if i<displayed.size() else ""
		slot.title.text=World.FISH[fish].name if fish!="" else "空展示位"
		slot.icon.texture=ItemArt.icon(fish) if fish!="" else null
		if is_instance_valid(slot.take):slot.take.disabled=fish==""
	if ui.picker==null:return
	var picker:OptionButton=ui.picker
	var inventory:Dictionary=player(app).get("inventory",{})
	var available:Dictionary={}
	for fish in World.FISH:
		var count:=int(inventory.get(fish,0))
		if count>0 and fish not in displayed:available[fish]=count
	if ui.bag!=available or picker.item_count==0:
		var prior:Variant=picker.get_item_metadata(picker.selected) if picker.selected>=0 else ""
		picker.clear()
		for fish:String in available:
			picker.add_item("%s ×%d"%[World.FISH[fish].name,available[fish]])
			picker.set_item_metadata(picker.item_count-1,fish)
			if fish==prior:picker.select(picker.item_count-1)
		if available.is_empty():picker.add_item("背包裡沒有其他漁獲")
		ui.bag=available
	var full:=displayed.size()>=World.INDUSTRY.COUNTER_CAPACITY
	picker.disabled=full or available.is_empty()
	ui.put.disabled=picker.disabled
	ui.put.text="展示位已滿" if full else "放上展示台"

## T06 茶葉展示櫃: three numbered spaces; every displayed unit takes one space and stays in the cabinet's real items.
static func tea_display_cabinet(app,cell:Vector2i) -> void:
	var body:VBoxContainer=app._open_modal("茶葉展示櫃")
	app.modal.set_meta("life_modal_layout","tea_display_cabinet")
	app.modal.theme=PixelTheme.make(app.hud.theme)
	app.modal.add_theme_stylebox_override("panel",PixelTheme.frame_style())
	var slots:=HBoxContainer.new()
	slots.add_theme_constant_override("separation",10)
	body.add_child(slots)
	var box:Dictionary=app.session.snapshot.get("objects",{}).get(World.key(cell),{})
	var own:bool=box.get("owner","")==app.session.own_id
	var cards:Array[Dictionary]=[]
	for index in World.INDUSTRY.TEA_CABINET_SLOTS:
		var tray:=card(slots)
		(tray.get_parent() as Control).size_flags_horizontal=Control.SIZE_EXPAND_FILL
		var number:=line(app,tray,"展示位 %d"%(index+1),14)
		number.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		var icon:=TextureRect.new()
		icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
		icon.custom_minimum_size=Vector2(48,48)
		icon.name="TeaCabinetIcon_%d"%index
		tray.add_child(icon)
		var title:=line(app,tray,"空展示位",17)
		title.name="TeaCabinetTitle_%d"%index
		title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		var take:Button
		if own:
			take=app.button("取回一份",func():
				var shown:=World.INDUSTRY.tea_cabinet_slots(app.session.snapshot.get("objects",{}).get(World.key(cell),{}).get("items",{}))
				if index<shown.size():app.session.perform(World.INDUSTRY.TEA_CABINET_TAKE,cell,shown[index]))
			take.name="TeaCabinetTake_%d"%index
			tray.add_child(take)
		cards.append({"icon":icon,"title":title,"take":take})
	var summary:=line(app,body,"",15)
	summary.name="TeaCabinetCount"
	var picker:=OptionButton.new()
	var put:Button
	if own:
		var actions:=HBoxContainer.new()
		body.add_child(actions)
		picker.name="TeaCabinetPicker"
		picker.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		actions.add_child(picker)
		put=app.button("放上展示櫃",func():
			if picker.selected>=0 and picker.get_item_metadata(picker.selected)!=null:
				app.session.perform(World.INDUSTRY.TEA_CABINET_PUT,cell,str(picker.get_item_metadata(picker.selected))))
		put.name="TeaCabinetPut"
		actions.add_child(put)
	else:picker.free()
	var hint:=line(app,body,"每個展示位放一份茶，同種茶可擺多份。" if own else "歡迎參觀。只有櫃主能更換展示。",14)
	hint.name="TeaCabinetHint"
	app.modal.set_meta("tea_cabinet_ui",{"region":app.session.snapshot.get("region_id","home"),"tile":World.key(cell),"cards":cards,"summary":summary,"picker":picker if own else null,"put":put,"bag":{}})
	refresh_tea_display_cabinet(app)

static func refresh_tea_display_cabinet(app) -> void:
	if not is_instance_valid(app.modal) or not app.modal.has_meta("tea_cabinet_ui"):return
	var ui:Dictionary=app.modal.get_meta("tea_cabinet_ui")
	var snapshot:Dictionary=app.session.snapshot
	var cabinet:Dictionary=snapshot.get("objects",{}).get(ui.tile,{})
	if cabinet.get("type")!=World.INDUSTRY.TEA_DISPLAY_CABINET or snapshot.get("region_id","home")!=ui.region:
		app._close_modal()
		return
	var items:Dictionary=cabinet.get("items",{})
	var displayed:=World.INDUSTRY.tea_cabinet_slots(items)
	for i in ui.cards.size():
		var slot:Dictionary=ui.cards[i]
		var tea:String=displayed[i] if i<displayed.size() else ""
		slot.title.text=World.NAMES.get(tea,tea) if tea!="" else "空展示位"
		slot.icon.texture=ItemArt.icon(tea) if tea!="" else null
		if is_instance_valid(slot.take):slot.take.disabled=tea==""
	var counts:PackedStringArray=[]
	var ids:=items.keys()
	ids.sort()
	for tea:String in ids:counts.append("%s ×%d"%[World.NAMES.get(tea,tea),int(items[tea])])
	ui.summary.text="已展示 %d／%d　%s"%[displayed.size(),World.INDUSTRY.TEA_CABINET_SLOTS,"　".join(counts) if not counts.is_empty() else "尚未展示茶葉"]
	if ui.picker==null:return
	var picker:OptionButton=ui.picker
	var inventory:Dictionary=player(app).get("inventory",{})
	var available:Dictionary={}
	for tea:String in World.INDUSTRY.TEA_CABINET_TEAS:
		var count:=int(inventory.get(tea,0))
		if count>0:available[tea]=count
	if ui.bag!=available or picker.item_count==0:
		var prior:Variant=picker.get_item_metadata(picker.selected) if picker.selected>=0 else ""
		picker.clear()
		for tea:String in available:
			picker.add_item("%s ×%d"%[World.NAMES.get(tea,tea),available[tea]])
			picker.set_item_metadata(picker.item_count-1,tea)
			if tea==prior:picker.select(picker.item_count-1)
		if available.is_empty():picker.add_item("背包裡沒有可展示的茶葉")
		ui.bag=available
	var full:=displayed.size()>=World.INDUSTRY.TEA_CABINET_SLOTS
	picker.disabled=full or available.is_empty()
	ui.put.disabled=picker.disabled
	ui.put.text="展示位已滿" if full else "放上展示櫃"

## T07: the two pouring emotes, shown to anyone (owner or visitor) while the table displays a
## tea set. They only send an emote request; the host re-checks that a set is actually nearby.
static func tea_set_emote_row(app,page:Control) -> HBoxContainer:
	var row:=HBoxContainer.new()
	row.name="TeaSetEmotes"
	row.visible=false
	row.add_theme_constant_override("separation",8)
	page.add_child(row)
	var title:=Label.new()
	title.text="小陶茶具"
	row.add_child(title)
	for id:String in World.INDUSTRY.TEA_SET_EMOTE_BUTTONS:
		var emote:Button=app.button(World.INDUSTRY.TEA_SET_EMOTE_BUTTONS[id],func():
			app.session.perform("emote",Vector2i.ZERO,id)
			app._close_modal())
		emote.name="TeaSetEmote_"+id
		emote.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		row.add_child(emote)
	return row

static func refresh_tea_set_emotes(app,table:Dictionary) -> void:
	var row:Control=app.modal.find_child("TeaSetEmotes",true,false) as Control
	if row!=null:row.visible=World.INDUSTRY.has_tea_set(table)

static func four_seat_table(app,cell:Vector2i) -> void:
	var tile:=World.key(cell)
	var snapshot:Dictionary=app.session.snapshot
	var table:Dictionary=snapshot.get("objects",{}).get(tile,{})
	var kind:String=table.get("type","")
	if kind not in World.INDUSTRY.FOUR_SEAT_TABLES:return
	var tea:=kind==World.INDUSTRY.BAMBOO_TEA_TABLE
	var prefix:="BambooTeaTable" if tea else "MushroomTable"
	var page:VBoxContainer=app._open_modal(World.BUILD[kind].name)
	app.modal.set_meta("life_modal_layout","bamboo_tea_table" if tea else "mushroom_table")
	if tea:
		app.modal.theme=PixelTheme.make(app.hud.theme)
		app.modal.add_theme_stylebox_override("panel",PixelTheme.frame_style())
		line(app,page,"選一邊坐下，就能享用桌上的茶點。",16)
	var seating:=GridContainer.new()
	seating.columns=3 if tea else 2
	seating.add_theme_constant_override("h_separation",8)
	seating.add_theme_constant_override("v_separation",6)
	page.add_child(seating)
	var seats:Array[Button]=[]
	seats.resize(4)
	var slots:=[-1,0,-1,3,-2,1,-1,2,-1] if tea else [0,1,2,3]
	for side:int in slots:
		if side==-2:
			var art:Texture2D=preload("res://assets/ui-life/bamboo-tea-table-long.png") if World.INDUSTRY.is_vertical(table) else preload("res://assets/ui-life/bamboo-tea-table-wide.png")
			seating.add_child(Shell.picture(art,68))
			continue
		if side==-1:
			seating.add_child(Control.new())
			continue
		var button:Button=app.button("",func():
			var pose:Dictionary=player(app).get(World.RESIDENT_GOALS.MASTER_BENCH_SEAT,{})
			var choice:="leave" if pose.get("cell")==tile and int(pose.side)==side else str(side)
			app.session.perform(World.INDUSTRY.MUSHROOM_SIT,cell,choice))
		button.name=prefix+"Seat%d"%side
		button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		seating.add_child(button)
		seats[side]=button
	var meals:=card(page)
	var service:=HBoxContainer.new()
	var picker:OptionButton
	var serve:Button
	if table.get("owner")==app.session.own_id:
		page.add_child(service)
		if tea:page.move_child(service,meals.get_parent().get_index())
		picker=OptionButton.new()
		picker.name=prefix+"Meal"
		picker.clip_text=true
		picker.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		service.add_child(picker)
		serve=app.button("上菜",func():
			if picker.selected>=0:
				var item:Variant=picker.get_item_metadata(picker.selected)
				if item is String:app.session.perform(World.INDUSTRY.MUSHROOM_SERVE,cell,item))
		serve.name=prefix+"Serve"
		service.add_child(serve)
	else:service.free()
	if tea:
		var emotes:=tea_set_emote_row(app,page)
		page.move_child(emotes,meals.get_parent().get_index())
		if table.get("owner")==app.session.own_id:
			var toggle:Button=app.button("",func():
				var current:Dictionary=app.session.snapshot.get("objects",{}).get(tile,{})
				var action:=World.INDUSTRY.MUSHROOM_TAKE if World.INDUSTRY.has_tea_set(current) else World.INDUSTRY.MUSHROOM_SERVE
				app.session.perform(action,cell,World.INDUSTRY.TEA_SET))
			toggle.name="BambooTeaTableSetToggle"
			page.add_child(toggle)
			page.move_child(toggle,meals.get_parent().get_index())
	app.modal.set_meta("four_seat_table_ui",{"region":snapshot.get("region_id","home"),"tile":tile,"kind":kind,"prefix":prefix,"seats":seats,"meals":meals,"picker":picker,"serve":serve,"bag":{},"meal_state":{}})
	refresh_four_seat_table(app)

static func refresh_four_seat_table(app) -> void:
	if not is_instance_valid(app.modal) or not app.modal.has_meta("four_seat_table_ui"):return
	var ui:Dictionary=app.modal.get_meta("four_seat_table_ui")
	var snapshot:Dictionary=app.session.snapshot
	var table:Dictionary=snapshot.get("objects",{}).get(ui.tile,{})
	if table.get("type")!=ui.kind or snapshot.get("region_id","home")!=ui.region:
		app._close_modal()
		return
	var occupied:=["","","",""]
	var tile:=World.cell(ui.tile)
	var seat_field:=World.RESIDENT_GOALS.MASTER_BENCH_SEAT
	for person_id:String in snapshot.get("players",{}):
		var seat:Dictionary=snapshot.players[person_id].get(seat_field,{})
		if seat.get("cell")==ui.tile and int(seat.side) in range(4):occupied[int(seat.side)]=person_id
	var own_pose:Dictionary=player(app).get(seat_field,{})
	var resting:bool=own_pose.get("cell")==ui.tile
	var tea:bool=ui.kind==World.INDUSTRY.BAMBOO_TEA_TABLE
	var seat_names:=["北側","東側","南側","西側"] if tea else ["後左","後右","前左","前右"]
	for index in range(4):
		var mine:bool=occupied[index]==app.session.own_id
		ui.seats[index].disabled=not mine and (not occupied[index].is_empty() or not own_pose.is_empty())
		ui.seats[index].text=seat_names[index]+"座・"+("起身" if mine else ("有人" if not occupied[index].is_empty() else "坐下"))
	var items:Dictionary=table.items
	var total:=0
	for amount in items.values():total+=int(amount)
	if tea:
		refresh_tea_set_emotes(app,table)
		var toggle:Button=app.modal.find_child("BambooTeaTableSetToggle",true,false) as Button
		if toggle!=null:
			var placed:=World.INDUSTRY.has_tea_set(table)
			var spare:=int(player(app).get("inventory",{}).get(World.INDUSTRY.TEA_SET,0))
			toggle.text="取回小陶茶具" if placed else "擺上小陶茶具 ×%d"%spare
			toggle.disabled=not placed and spare<1
	var status:={"items":items.duplicate(),"resting":resting}
	if ui.meal_state!=status:
		ui.meal_state=status
		for row:Node in ui.meals.get_children():
			ui.meals.remove_child(row)
			row.queue_free()
		if items.is_empty():line(app,ui.meals,"桌上還沒有茶點" if tea else "桌上還沒有餐點",16)
		for id:String in items:
			var row:=HBoxContainer.new()
			row.add_theme_constant_override("separation",8)
			ui.meals.add_child(row)
			var icon:=TextureRect.new()
			icon.texture=ItemArt.icon(id)
			icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			icon.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
			icon.custom_minimum_size=Vector2(32,32)
			row.add_child(icon)
			var label:=line(app,row,"%s ×%d"%[World.NAMES[id],items[id]],16)
			label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
			var eat:Button=app.button("享用" if resting else "入座後享用",func():app.session.perform(World.INDUSTRY.MUSHROOM_EAT,tile,id))
			eat.name=ui.prefix+"Eat_"+id
			eat.disabled=not resting
			row.add_child(eat)
			if ui.picker!=null:
				var take:Button=app.button("收回",func():app.session.perform(World.INDUSTRY.MUSHROOM_TAKE,tile,id))
				take.name=ui.prefix+"Take_"+id
				row.add_child(take)
	if ui.picker==null:return
	var picker:OptionButton=ui.picker
	var inventory:Dictionary=player(app).get("inventory",{})
	var available:Dictionary={}
	for item:String in World.RECIPES:
		if int(inventory.get(item,0))>0 and World.INDUSTRY.four_seat_meal(ui.kind,item,World.RECIPES):available[item]=int(inventory[item])
	if available!=ui.bag or picker.item_count==0:
		ui.bag=available
		var previous:Variant=picker.get_item_metadata(picker.selected) if picker.selected>=0 else null
		picker.clear()
		for id:String in available:
			picker.add_item("%s ×%d"%[World.NAMES[id],available[id]])
			picker.set_item_metadata(picker.item_count-1,id)
			if id==previous:picker.select(picker.item_count-1)
		if available.is_empty():picker.add_item("背包裡沒有可上桌的茶點" if tea else "背包裡沒有可上桌的料理")
		elif picker.selected<0:picker.select(0)
	picker.disabled=available.is_empty() or total>=World.INDUSTRY.MUSHROOM_TABLE_CAPACITY
	ui.serve.disabled=picker.disabled
	ui.serve.text=("%s %d／%d")%["擺茶點" if tea else "上菜",total,World.INDUSTRY.MUSHROOM_TABLE_CAPACITY]

static func shell_table(app,cell:Vector2i) -> void:
	var tile:=World.key(cell)
	var snapshot:Dictionary=app.session.snapshot
	var table:Dictionary=snapshot.get("objects",{}).get(tile,{})
	var own:bool=table.get("owner")==app.session.own_id
	var kind:=str(table.get("type",""))
	var round_table:=kind==World.INDUSTRY.SHELL_TABLE
	var page:VBoxContainer=app._open_modal("貝殼圓桌" if round_table else "木桌・桌面展示")
	app.modal.set_meta("life_modal_layout","shell_table")
	var display:=card(page)
	var row:=HBoxContainer.new()
	row.add_theme_constant_override("separation",12)
	display.add_child(row)
	var icon:=TextureRect.new()
	icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	icon.custom_minimum_size=Vector2(48,48)
	row.add_child(icon)
	var title:=line(app,row,"桌上還沒有展示品",17)
	title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	title.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	var picker:OptionButton
	var put:Button
	var take:Button
	var bloom_row:HBoxContainer
	var bloom_picker:OptionButton
	var swap:Button
	if own:
		take=app.button("取回",func():
			var items:Dictionary=app.session.snapshot.get("objects",{}).get(tile,{}).get("items",{})
			if not items.is_empty():app.session.perform(World.INDUSTRY.SHELL_TAKE,cell,str(items.keys()[0])))
		take.name="ShellTableTake"
		row.add_child(take)
		var actions:=HBoxContainer.new()
		display.add_child(actions)
		picker=OptionButton.new()
		picker.name="ShellTablePicker"
		picker.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		picker.clip_text=true
		actions.add_child(picker)
		put=app.button("擺上桌面",func():
			if picker.selected>=0:
				var item:Variant=picker.get_item_metadata(picker.selected)
				if item is String:app.session.perform(World.INDUSTRY.SHELL_PUT,cell,item))
		put.name="ShellTablePut"
		actions.add_child(put)
		bloom_row=HBoxContainer.new()
		bloom_row.visible=false
		display.add_child(bloom_row)
		bloom_picker=OptionButton.new()
		bloom_picker.name="TableVaseBloom"
		bloom_picker.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		bloom_picker.clip_text=true
		bloom_row.add_child(bloom_picker)
		for flower:String in World.INDUSTRY.TABLE_VASE_BLOOMS.values():
			bloom_picker.add_icon_item(ItemArt.icon(flower),World.NAMES[flower])
			bloom_picker.set_item_metadata(bloom_picker.item_count-1,flower)
		swap=app.button("換一枝花",func():
			if bloom_picker.selected>=0:
				app.session.perform(World.INDUSTRY.TABLE_VASE_SWAP,cell,bloom_picker.get_item_metadata(bloom_picker.selected)))
		swap.name="TableVaseSwap"
		bloom_row.add_child(swap)
	var seating:=HBoxContainer.new()
	seating.add_theme_constant_override("separation",10)
	page.add_child(seating)
	seating.visible=round_table
	tea_set_emote_row(app,page)
	var seats:Array[Button]=[]
	for side in range(2 if round_table else 0):
		var seat:Button=app.button("",func():
			app._close_modal()
			app.session.perform(World.INDUSTRY.SHELL_SIT,cell,str(side)))
		seat.name="ShellTableSeat%d"%side
		seat.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		seating.add_child(seat)
		seats.append(seat)
	app.modal.set_meta("shell_table_ui",{"region":snapshot.get("region_id","home"),"tile":tile,"kind":kind,"icon":icon,"title":title,"seats":seats,"picker":picker,"put":put,"take":take,"bag":{}})
	if own:app.modal.set_meta("table_vase_ui",{"row":bloom_row,"picker":bloom_picker,"swap":swap})
	refresh_shell_table(app)

static func refresh_shell_table(app) -> void:
	if not is_instance_valid(app.modal) or not app.modal.has_meta("shell_table_ui"):return
	var ui:Dictionary=app.modal.get_meta("shell_table_ui")
	var snapshot:Dictionary=app.session.snapshot
	var table:Dictionary=snapshot.get("objects",{}).get(ui.tile,{})
	if table.get("type")!=ui.kind or snapshot.get("region_id","home")!=ui.region:
		app._close_modal()
		return
	var items:Dictionary=table.items
	var shown:=str(items.keys()[0]) if not items.is_empty() else ""
	refresh_tea_set_emotes(app,table)
	ui.title.text="桌上還沒有展示品" if shown.is_empty() else World.NAMES.get(shown,shown)
	ui.icon.texture=ItemArt.icon("seashell" if shown.is_empty() else shown)
	ui.icon.modulate.a=0.42 if shown.is_empty() else 1.0
	var occupied:=[false,false]
	for person:Dictionary in snapshot.get("players",{}).values():
		var seat:Dictionary=person.get(World.RESIDENT_GOALS.MASTER_BENCH_SEAT,{})
		if seat.get("cell")==ui.tile and int(seat.side) in [0,1]:occupied[int(seat.side)]=true
	for index in ui.seats.size():
		ui.seats[index].disabled=occupied[index]
		ui.seats[index].text=["左側座位","右側座位"][index]+("・有人" if occupied[index] else "・坐下")
	if ui.picker==null:return
	var picker:OptionButton=ui.picker
	var inventory:Dictionary=player(app).get("inventory",{})
	var available:Dictionary={}
	for item:String in inventory:
		if ui.kind=="table" and item not in World.INDUSTRY.WOOD_TABLE_DISPLAY:continue
		if int(inventory[item])>0 and World.ITEM_CATALOG.is_known(item):available[item]=int(inventory[item])
	if ui.bag!=available or picker.item_count==0:
		var prior:Variant=picker.get_item_metadata(picker.selected) if picker.selected>=0 else null
		var keys:=available.keys()
		keys.sort()
		picker.clear()
		for item:String in keys:
			picker.add_item("%s ×%d"%[World.NAMES.get(item,item),available[item]])
			picker.set_item_metadata(picker.item_count-1,item)
			if item==prior:picker.select(picker.item_count-1)
		if keys.is_empty():picker.add_item("可在工作台製作花瓶或貝殼瓶" if ui.kind=="table" else "背包裡沒有可以展示的物品")
		elif picker.selected<0:picker.select(0)
		ui.bag=available
	ui.take.visible=not shown.is_empty()
	picker.get_parent().visible=shown.is_empty()
	picker.disabled=available.is_empty()
	ui.put.disabled=picker.disabled
	var vase:Dictionary=app.modal.get_meta("table_vase_ui",{})
	if vase.is_empty():return
	var current:String=World.INDUSTRY.TABLE_VASE_BLOOMS.get(shown,"")
	vase.row.visible=not current.is_empty()
	if current.is_empty():return
	var flowers:OptionButton=vase.picker
	var first_available:=-1
	for index in flowers.item_count:
		var flower:String=flowers.get_item_metadata(index)
		var amount:=int(inventory.get(flower,0))
		var disabled:=flower==current or amount<=0
		flowers.set_item_disabled(index,disabled)
		flowers.set_item_text(index,"%s · 瓶中"%World.NAMES[flower] if flower==current else "%s ×%d"%[World.NAMES[flower],amount])
		if not disabled and first_available<0:first_available=index
	if flowers.selected<0 or flowers.is_item_disabled(flowers.selected):flowers.select(first_available)
	flowers.disabled=first_available<0
	vase.swap.disabled=flowers.disabled

static func nursery_box(app,cell:Vector2i) -> void:
	var page:VBoxContainer=app._open_modal("溫室育苗箱")
	app.modal.set_meta("life_modal_layout","nursery_box")
	var box:Dictionary=app.session.snapshot.get("objects",{}).get(World.key(cell),{})
	var own:bool=box.get("owner","")==app.session.own_id
	var picker:=OptionButton.new()
	picker.name="NurserySeedPicker"
	picker.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	picker.visible=own
	page.add_child(picker)
	var grid:=GridContainer.new()
	grid.columns=2
	grid.add_theme_constant_override("h_separation",10)
	grid.add_theme_constant_override("v_separation",8)
	page.add_child(grid)
	var rows:Array[Dictionary]=[]
	for slot in World.NURSERY_BOX.SLOT_COUNT:
		var panel:=card(grid)
		(panel.get_parent() as Control).size_flags_horizontal=Control.SIZE_EXPAND_FILL
		var heading:=HBoxContainer.new()
		panel.add_child(heading)
		var icon:=TextureRect.new()
		icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size=Vector2(26,26)
		icon.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
		heading.add_child(icon)
		var title:=line(app,heading,"第 %d 格"%(slot+1),18)
		title.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
		var status:=line(app,panel,"空床",15)
		var action:Button=app.button("播種",func():
			var field:=str(slot)
			var op:="nursery_sow"
			var live:Dictionary=app.session.snapshot.get("objects",{}).get(World.key(cell),{}).get(World.NURSERY_BOX.SLOTS,{}).get(field,{})
			if live.get("kind","")!="":
				op=World.NURSERY_BOX.HARVEST if float(live.growth)>=float(World.CROPS[live.kind].time) else World.NURSERY_BOX.WATER
			elif picker.selected>=0:field+=":"+str(picker.get_item_metadata(picker.selected))
			else:return
			app.session.perform(op,cell,field))
		action.name="NurserySlot_%d"%slot
		action.visible=own
		panel.add_child(action)
		rows.append({"title":title,"status":status,"action":action,"icon":icon})
	line(app,page,"各格獨立成長。封閉溫室可跨季，仍要澆水。" if own else "這座育苗箱由箱主照料。",14)
	app.modal.set_meta("nursery_box_ui",{"cell":cell,"region":app.session.snapshot.get("region_id","home"),"picker":picker,"rows":rows,"seed_amounts":{}})
	picker.item_selected.connect(func(_index:int):refresh_nursery_box(app))
	refresh_nursery_box(app)

static func refresh_nursery_box(app) -> void:
	if not is_instance_valid(app.modal) or not app.modal.has_meta("nursery_box_ui"):return
	var ui:Dictionary=app.modal.get_meta("nursery_box_ui")
	var snapshot:Dictionary=app.session.snapshot
	var cell:Vector2i=ui.cell
	var box:Dictionary=snapshot.get("objects",{}).get(World.key(cell),{})
	if box.get("type")!=World.NURSERY_BOX.KIND or snapshot.get("region_id","home")!=ui.region:
		app._close_modal()
		return
	var picker:OptionButton=ui.picker
	if picker.visible:
		var bag:Dictionary=player(app).get("inventory",{})
		var seeds:Dictionary={}
		for crop:String in World.CROPS:
			if int(bag.get(crop+"_seed",0))>0:seeds[crop]=int(bag[crop+"_seed"])
		if seeds!=ui.seed_amounts or picker.item_count==0:
			var selected:Variant=picker.get_item_metadata(picker.selected) if picker.selected>=0 else ""
			picker.clear()
			for crop:String in seeds:
				picker.add_item("%s種子 ×%d"%[World.CROPS[crop].name,seeds[crop]])
				picker.set_item_metadata(picker.item_count-1,crop)
				if crop==selected:picker.select(picker.item_count-1)
			if seeds.is_empty():picker.add_item("背包裡沒有種子")
			picker.disabled=seeds.is_empty()
			ui.seed_amounts=seeds
	for slot in World.NURSERY_BOX.SLOT_COUNT:
		var row:Dictionary=ui.rows[slot]
		var crop:Dictionary=box.get(World.NURSERY_BOX.SLOTS,{}).get(str(slot),{})
		var kind:String=crop.get("kind","")
		var plot:=World.NURSERY_BOX.plot_cell(cell,slot,World.INDUSTRY.is_vertical(box))
		row.title.text="第 %d 格"%(slot+1) if kind=="" else "%d · %s"%[slot+1,World.CROPS[kind].name]
		row.icon.texture=ItemArt.icon(kind) if kind!="" else ItemArt.icon("glass")
		if kind=="":
			var seed:=str(picker.get_item_metadata(picker.selected)) if not picker.disabled and picker.selected>=0 else ""
			var terrain:=World.crop_terrain_problem(seed,plot,ui.region) if seed!="" else ""
			row.status.text="空床"
			row.action.text="播種"
			row.action.tooltip_text=terrain
			row.action.disabled=seed=="" or terrain!=""
			continue
		var ready:=float(crop.growth)>=float(World.CROPS[kind].time)
		var dormant:=World.plot_dormant(crop,snapshot.get("roofs",{}).get(World.key(plot),{}),ui.region,plot,float(snapshot.get("time",0)),World.GREENHOUSE_GLASS.covered(snapshot,World.key(plot)))
		var percent:=mini(99,floori(float(crop.growth)*100.0/float(World.CROPS[kind].time)))
		row.status.text="成熟，可採收" if ready else ("%d%% · "%percent+("休眠" if dormant else ("已澆水" if crop.wet else "待澆水")))
		row.action.text="採收" if ready else "澆水"
		row.action.tooltip_text=""
		row.action.disabled=not ready and crop.wet

static func seed_specimen_cabinet(app,cell:Vector2i,obj:Dictionary) -> void:
	var body:VBoxContainer=app._open_modal("種子標本櫃")
	app.modal.set_meta("life_modal_layout","inn_tea_table")
	var industry:=World.INDUSTRY
	var samples:Array=obj.get(industry.SEED_SAMPLES,[])
	var own:bool=obj.get("owner")==app.session.own_id
	var display:=HBoxContainer.new()
	display.add_theme_constant_override("separation",8)
	body.add_child(display)
	for index in industry.SEED_SAMPLE_SLOTS:
		var tray:=card(display)
		(tray.get_parent() as Control).size_flags_horizontal=Control.SIZE_EXPAND_FILL
		if index>=samples.size():
			var empty:=line(app,tray,"空展示位",15)
			empty.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
			empty.custom_minimum_size.y=42
			continue
		var crop:String=samples[index]
		add_icon(tray,ItemArt.icon(crop+"_seed"),42)
		var caption:=line(app,tray,World.CROPS[crop].name,16)
		caption.name="SeedSample_"+crop
		caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		if own:
			var clear:Button=app.button("收起",func():
				app.session.perform(industry.SEED_CLEAR,cell,crop)
				app._close_modal())
			clear.name="SeedClear_"+crop
			tray.add_child(clear)
	app.LifeShell.reveal(app,display)
	if not own:return
	line(app,body,"展示菜園圖鑑裡的種子標本，背包物品會保留。",15)
	if samples.size()>=industry.SEED_SAMPLE_SLOTS:return
	var known:Dictionary=player(app).get("collection",{}).get("crops",{})
	var available:=World.CROPS.keys().filter(func(crop):return known.has(crop) and crop not in samples)
	if available.is_empty():
		line(app,body,"收成新的作物後，就能在這裡加入標本。",15)
		return
	var choices:=HBoxContainer.new()
	var picker:=OptionButton.new()
	picker.name="SeedCabinetPicker"
	picker.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	for crop:String in available:
		picker.add_item(World.CROPS[crop].name)
		picker.set_item_metadata(picker.item_count-1,crop)
	body.add_child(choices)
	choices.add_child(picker)
	var put:Button=app.button("放上標本",func():
		app.session.perform(industry.SEED_DISPLAY,cell,str(picker.get_item_metadata(picker.selected)))
		app._close_modal())
	put.name="SeedCabinetDisplay"
	choices.add_child(put)

static func luggage_rack(app,cell:Vector2i,obj:Dictionary) -> void:
	var page:VBoxContainer=app._open_modal("旅人行李架")
	app.modal.set_meta("life_modal_layout","inn_tea_table")
	var items:Dictionary=obj.get("items",{})
	var shown:=World.luggage_count(items)
	var own:bool=obj.get("owner")==app.session.own_id
	line(app,page,"展示品 · %d／%d"%[shown,World.INDUSTRY.LUGGAGE_SLOTS],19)
	for item:String in items:
		var row:=HBoxContainer.new()
		page.add_child(row)
		add_icon(row,preload("res://scripts/inventory_item_art.gd").icon(item),32)
		line(app,row,"%s ×%d"%[World.NAMES.get(item,item),items[item]],16)
		if own:row.add_child(app.button("取回一件",func():app.session.perform("inn_luggage_take",cell,item);app._close_modal()))
	if not own or shown>=World.INDUSTRY.LUGGAGE_SLOTS:return
	var open_picker:=Button.new()
	open_picker.text="從背包選擇展示品"
	open_picker.pressed.connect(func():
		open_picker.hide()
		var bag:Dictionary=player(app).get("inventory",{})
		var picker:=OptionButton.new()
		picker.name="LuggageItemPicker"
		for item:String in World.NAMES:
			if int(bag.get(item,0))<1:continue
			picker.add_item(World.NAMES[item])
			picker.set_item_metadata(picker.item_count-1,item)
		if picker.item_count==0:
			line(app,page,"背包裡還沒有可以展示的物品。",16)
			return
		page.add_child(picker)
		var put:Button=app.button("放上一件",func():
			app.session.perform("inn_luggage_place",cell,str(picker.get_item_metadata(picker.selected)))
			app._close_modal())
		put.name="LuggagePlace"
		page.add_child(put))
	open_picker.name="LuggageOpenPicker"
	page.add_child(open_picker)

static func inn_tea_table(app,cell:Vector2i,obj:Dictionary) -> void:
	var page:VBoxContainer=app._open_modal("暖薑茶小桌")
	app.modal.set_meta("life_modal_layout","inn_tea_table")
	var items:Dictionary=obj.get("items",{})
	var cups:=World.inn_tea_count(items)
	var tray:=card(page)
	line(app,tray,"桌上茶杯 · %d／%d"%[cups,World.INN_TEA_SLOTS],19)
	for tea:String in World.INN_TEA_ITEMS:
		var count:=int(items.get(tea,0))
		if count>0:line(app,tray,"%s ×%d"%[World.NAMES[tea],count],15)
	if obj.get("owner")!=app.session.own_id:return
	var bag:Dictionary=player(app).get("inventory",{})
	for tea:String in World.INN_TEA_ITEMS:
		var choices:=HBoxContainer.new()
		page.add_child(choices)
		var put:Button=app.button("擺一杯"+str(World.NAMES[tea]),func():app.session.perform("inn_tea_place",cell,tea);app._close_modal())
		put.name="InnTeaPlace" if tea==World.INN_TEA_ITEM else "InnGingerPlace"
		put.disabled=cups>=World.INN_TEA_SLOTS or int(bag.get(tea,0))<=0
		choices.add_child(put)
		var take:Button=app.button("收回一杯",func():app.session.perform("inn_tea_take",cell,tea);app._close_modal())
		take.name="InnTeaTake" if tea==World.INN_TEA_ITEM else "InnGingerTake"
		take.disabled=int(items.get(tea,0))==0
		choices.add_child(take)

static func welcome_sign(app,cell:Vector2i,obj:Dictionary) -> void:
	var home_sign:bool=obj.type==World.WALL_FIXTURES.HOME_SIGN
	var page:VBoxContainer=app._open_modal("手刻門牌" if home_sign else "暖暖的迎賓牌")
	var is_owner:bool=obj.get("owner")==app.session.own_id
	app.modal.set_meta("life_modal_layout","welcome_sign_edit" if is_owner else "welcome_sign_read")
	var copy:Array=obj.get("welcome",["","",""])
	var paper:=card(page)
	var heading:Label=app.label("",24)
	heading.name="WelcomeInnName"
	heading.text=copy[0] if not copy[0].is_empty() else ("我的家園" if home_sign else "暖泉旅舍")
	paper.add_child(heading)
	if home_sign:
		var author:=line(app,paper,"建造者 · "+str(obj.get("author","")),15)
		author.name="HomeSignAuthor"
	for i in [1,2]:
		if copy[i].is_empty():continue
		var message:Label=app.label("",18)
		message.name="WelcomeInnLine%d"%i
		message.text=copy[i]
		paper.add_child(message)
	if not is_owner:return
	var fields:Array[LineEdit]=[]
	var captions:=["家園名稱" if home_sign else "旅舍名稱","歡迎語第一行","歡迎語第二行"]
	for i in World.WELCOME_SIGN.LIMITS.size():
		line(app,page,"%s（%d 字內）"%[captions[i],World.WELCOME_SIGN.LIMITS[i]],15)
		var field:=LineEdit.new()
		field.name="WelcomeSignField%d"%i
		field.max_length=World.WELCOME_SIGN.LIMITS[i]
		field.text=copy[i]
		page.add_child(field)
		fields.append(field)
	var save:Button=app.button("儲存門牌" if home_sign else "儲存迎賓牌",func():
		var lines:=fields.map(func(field:LineEdit):return field.text.strip_edges())
		app.session.perform(World.WELCOME_SIGN.WRITE,cell,JSON.stringify(lines))
		app._close_modal())
	save.name="WelcomeSignSave"
	page.add_child(save)

static func tool_board(app,tile:Vector2i)->void:
	var data:Dictionary=app.session.snapshot
	var anchor:=World.key(World.station_anchor(data.get("objects",{}),tile))
	var fixtures:=World.WALL_FIXTURES
	var board:Dictionary=data.get("objects",{}).get(anchor,{})
	if board.get("type")!=fixtures.TOOL_BOARD:return
	var own:bool=board.get("owner")==app.session.own_id
	var page:VBoxContainer=app._open_modal("壁掛工具板")
	app.modal.set_meta("life_modal_layout","tool_board")
	var tray:=card(page)
	var rows:Array[Dictionary]=[]
	for side in [0,1]:
		var row:=HBoxContainer.new()
		row.add_theme_constant_override("separation",9)
		tray.add_child(row)
		var icon:=TextureRect.new()
		icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
		icon.custom_minimum_size=Vector2(42,42)
		row.add_child(icon)
		var name:=line(app,row,"",17)
		name.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		name.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
		var picker:OptionButton
		if own:
			picker=OptionButton.new()
			picker.name="ToolBoardPicker%d"%side
			picker.custom_minimum_size.x=128
			row.add_child(picker)
			for tool:String in fixtures.TOOL_LOOKS:
				picker.add_icon_item(ToolFeedback.held_icon(tool),fixtures.TOOL_LOOKS[tool])
				picker.set_item_metadata(picker.item_count-1,tool)
			var save:Button=app.button("套用",func():
				var tool:String=picker.get_item_metadata(picker.selected)
				app.session.perform(fixtures.TOOL_BOARD_WRITE,tile,"%d:%s"%[side,tool]))
			save.name="ToolBoardSave%d"%side
			row.add_child(save)
		rows.append({"icon":icon,"name":name,"picker":picker})
	if own:line(app,page,"挑選工具外觀，不會取用背包道具。",15)
	app.modal.set_meta("tool_board_ui",{"anchor":anchor,"region":data.get("region_id","home"),"rows":rows,"shown":[null,null]})
	refresh_tool_board(app)

static func refresh_tool_board(app)->void:
	if not is_instance_valid(app.modal) or not app.modal.has_meta("tool_board_ui"):return
	var ui:Dictionary=app.modal.get_meta("tool_board_ui")
	var data:Dictionary=app.session.snapshot
	var fixtures:=World.WALL_FIXTURES
	var board:Dictionary=data.get("objects",{}).get(ui.anchor,{})
	if board.get("type")!=fixtures.TOOL_BOARD or data.get("region_id","home")!=ui.region:
		app._close_modal()
		return
	var looks:Array=board.get(fixtures.TOOL_BOARD_FIELD,["",""])
	for side in [0,1]:
		var tool:String=looks[side]
		if ui.shown[side]==tool:continue
		ui.shown[side]=tool
		var row:Dictionary=ui.rows[side]
		row.icon.texture=ToolFeedback.held_icon(tool)
		row.name.text=(["左側","右側"][side])+" · "+fixtures.TOOL_LOOKS[tool]
		if row.picker!=null:row.picker.select(fixtures.TOOL_LOOKS.keys().find(tool))

static func cotton_sofa(app,anchor:Vector2i)->void:
	## Shared by every independent two-seat piece (Goals.INDEPENDENT_TWO_SEATS); the title follows the furniture.
	var kind:String=app.session.snapshot.get("objects",{}).get(World.key(anchor),{}).get("type",Goals.COTTON_SOFA)
	var page:VBoxContainer=app._open_modal(World.BUILD[kind].name if kind in Goals.INDEPENDENT_TWO_SEATS else World.BUILD[Goals.COTTON_SOFA].name)
	app.modal.set_meta("life_modal_layout","cotton_sofa")
	var canvas:=HBoxContainer.new()
	canvas.add_theme_constant_override("separation",10)
	card(page).add_child(canvas)
	var choices:Array[Button]=[]
	for side in [0,1]:
		var button:Button=app.button("",func():
			var obj:Dictionary=app.session.snapshot.get("objects",{}).get(World.key(anchor),{})
			app.session.perform(Goals.MASTER_BENCH_SIT,anchor+World.master_bench_offset(obj)*side)
			app._close_modal())
		button.name="CottonSofaSeat%d"%side
		button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		canvas.add_child(button)
		choices.append(button)
	app.modal.set_meta("cotton_sofa_ui",{"tile":World.key(anchor),"region":app.session.snapshot.get("region_id","home"),"kind":kind,"choices":choices})
	refresh_cotton_sofa(app)

static func refresh_cotton_sofa(app)->void:
	if not is_instance_valid(app.modal) or not app.modal.has_meta("cotton_sofa_ui"):return
	var ui:Dictionary=app.modal.get_meta("cotton_sofa_ui")
	var snapshot:Dictionary=app.session.snapshot
	var obj:Dictionary=snapshot.get("objects",{}).get(ui.tile,{})
	if obj.get("type") not in Goals.INDEPENDENT_TWO_SEATS or obj.get("type")!=ui.get("kind",obj.get("type")) or snapshot.get("region_id","home")!=ui.region:
		app._close_modal()
		return
	var own_pose:Dictionary=player(app).get(Goals.MASTER_BENCH_SEAT,{})
	var occupied:=[false,false]
	for resident:Dictionary in snapshot.get("players",{}).values():
		var pose:Dictionary=resident.get(Goals.MASTER_BENCH_SEAT,{})
		if pose.get("cell")==ui.tile and int(pose.get("side",-1)) in [0,1]:occupied[int(pose.side)]=true
	var sides:=["上側","下側"] if obj.get("bench_vertical",false) else ["左側","右側"]
	for side in [0,1]:
		var button:Button=ui.choices[side]
		var own:bool=own_pose.get("cell")==ui.tile and int(own_pose.get("side",-1))==side
		button.text="起身" if own else sides[side]+("・有人" if occupied[side] else "・坐下")
		button.disabled=not own and (occupied[side] or not own_pose.is_empty())

static func aru_inscription(app,cell:Vector2i,obj:Dictionary) -> void:
	var page:VBoxContainer=app._open_modal(World.BUILD[obj.type].name)
	app.modal.set_meta("life_modal_layout","keepsake_paper")
	if Goals.aru_public_bench(obj):
		var sit:Button=app.button("坐在公共長椅",func():
			app.session.perform(Goals.MASTER_BENCH_SIT,cell)
			app._close_modal())
		sit.name="AruParkBenchSit"
		page.add_child(sit)
	if obj.type in Goals.DOUBLE_BENCHES:
		var rider:Dictionary=player(app).get(Goals.MASTER_BENCH_SEAT,{})
		for side in [0,1]:
			if side==1 and not rider.is_empty():break
			var seats:=["坐上側","坐下側"] if obj.get("bench_vertical",false) else ["坐左邊","坐右邊"]
			var caption:String="起身" if not rider.is_empty() else seats[side]
			var sit:Button=app.button(caption,func():
				app.session.perform(Goals.MASTER_BENCH_SIT,cell+World.master_bench_offset(obj)*side)
				app._close_modal())
			sit.name="MasterBenchSeat_%d"%side
			page.add_child(sit)
	if obj.type==Goals.STONE_BENCH:return
	var engraving:String=obj.get("inscription","")
	line(app,card(page),"木紋上還沒有刻字。" if engraving.is_empty() else engraving,22)
	if obj.get("owner")!=app.session.own_id or goal_state(app,"aru",3).get("state")!="done":return
	var draft:=LineEdit.new()
	draft.name="AruInscription"
	draft.max_length=Goals.INSCRIPTION_LIMIT
	draft.text=engraving
	draft.placeholder_text="留下門牌名稱或一句話（18 字內）"
	page.add_child(draft)
	var commit:=func():
		app.session.perform(Goals.INSCRIBE_ACTION,cell,draft.text.strip_edges())
		app._close_modal()
	draft.text_submitted.connect(func(_text:String):commit.call())
	var button:Button=app.button("儲存刻字",commit)
	button.name="AruSaveInscription"
	page.add_child(button)

static func send_gift(app,cell:Vector2i,id:String,item:String) -> void:
	app.session.perform("resident_gift",cell,id+":"+item)
	app._close_modal()

## 茶茶、星禾（不在 Village.NPCS 的地方居民）從茶園、水圳對話頁進入的好感頁。
static func bond_dialogue(app,id:String) -> void:
	var bond:=bond_view(app,id)
	if bond.is_empty():return
	var npc_name:String=Bond.name_of(id)
	var body:VBoxContainer=app._open_modal("和%s聊聊"%npc_name)
	app.modal.set_meta("life_modal_layout","community_board")
	line(app,body,"%s・%s"%[npc_name,str(Bond.LOCAL_PLACES.get(id,""))],18)
	line(app,body,"%s喜歡：%s"%[npc_name,Bond.LIKE_TEXT[id]],15)
	var actions:=HFlowContainer.new()
	add_bond_controls(app,body,actions,id)
	var events:Button=app.button("關係事件  %d／%d"%[int(bond.get("stage",0)),Bond.STAGES.size()],bond_events.bind(app,id))
	events.name="BondEvents"
	actions.add_child(events)
	if id=="chacha" and int(bond.get("stage",0))>=1:
		var tea:Button=app.button("布置茶桌",tea_arrangement.bind(app))
		tea.name="ChachaArrangement"
		actions.add_child(tea)
		if ChachaHandwrittenMenu.available(app.session.snapshot):
			var menu:Button=app.button("翻看手寫茶單",ChachaHandwrittenMenu.open.bind(app,bond_dialogue.bind(app,id),"回到茶茶"))
			menu.name="ChachaMenu"
			actions.add_child(menu)
		elif int(bond.get("stage",0))>=4:
			var reserve:Button=app.button("留一張椅子給來客",tea_guest_seat.bind(app))
			reserve.name="ChachaGuestSeat"
			actions.add_child(reserve)
	if id=="mianmian" and MianmianAnimalNotes.available(app.session.snapshot):
		var notes:Button=app.button("翻開糯米雞的偏好筆記",MianmianAnimalNotes.open.bind(app,bond_dialogue.bind(app,id),"回到棉棉"))
		notes.name="MianmianNotesEntry"
		actions.add_child(notes)
	if id=="mianmian" and MianmianToyPage.available(app.session.snapshot):
		var toy:Button=app.button("翻看棉棉縫的布玩具",MianmianToyPage.open.bind(app,bond_dialogue.bind(app,id),"回到棉棉"))
		toy.name="MianmianToyEntry"
		actions.add_child(toy)
	if id=="mianmian" and MianmianCareJournal.available(app.session.snapshot):
		var journal:Button=app.button("翻開棉棉的照料手札",MianmianCareJournal.open.bind(app,bond_dialogue.bind(app,id),"回到棉棉"))
		journal.name="MianmianJournalEntry"
		actions.add_child(journal)
	if id=="diandian" and painting_available(app):
		var painting:Button=app.button(painting_label(app),painting_book.bind(app,bond_dialogue.bind(app,id)))
		painting.name="DiandianPainting"
		actions.add_child(painting)
	if id=="xinghe" and (int(bond.get("stage",0))>=4 or not app.session.snapshot.get(Goals.GARDEN_KEY,[]).is_empty()):
		var garden:Button=app.button("共同花園",shared_garden.bind(app))
		garden.name="XingheSharedGarden"
		actions.add_child(garden)
	if id=="xinghe" and XingheGrowth.available(app.session.snapshot):
		actions.add_child(app.button("星禾的作物觀察簿",growth_book.bind(app,bond_dialogue.bind(app,id),"回到星禾")))
	if id=="luoluo" and int(bond.get("stage",0))>=1:add_address_control(app,actions)
	if id=="nuannuan" and goal_state(app,id,3).get("state")=="done" and not app.session.snapshot.get("own_guest_cloth",false):
		add_guest_cloth_claim(app,actions)
	if id=="nuannuan" and inn_resting(app):
		actions.add_child(app.button("拍張旅舍合照",take_inn_photo.bind(app)))
	if id=="lingpopo":
		if int(bond.get("stage",0))>=1 and (int(app.session.snapshot.get("own_lingpopo_bell",0))&Goals.BELL_CRACK_BIT)==0:
			var inspect:Button=app.button("查看裂開的小鈴",bell_inspection.bind(app,"bell"))
			inspect.name="LingpopoBrokenBell"
			actions.add_child(inspect)
		add_bell_history_bookmark(app,actions)
	if id=="achao" and int(bond.get("stage",0))>=3:
		var voyage:Button=app.button("碼頭燈與小船",achao_voyage.bind(app))
		voyage.name="AchaoVoyage"
		actions.add_child(voyage)
	if id=="achao":
		var log:Button=app.button("一起整理望安航記",func():preload("res://scripts/history_ui.gd").open(app,"wangan_log"))
		log.name="WanganHarborLog"
		actions.add_child(log)
	if id=="achao" and int(bond.get("stage",0))>=2:
		var chart:Button=app.button("翻開阿潮的航線",achao_route_book.bind(app))
		chart.name="AchaoRouteBook"
		actions.add_child(chart)
	add_forest_commission(app,actions,id,bond_dialogue.bind(app,id))
	body.add_child(actions)
	line(app,body,"每個世界日第一次聊天和第一份禮物會增加好感。要站在%s身邊才能聊天或送禮。"%npc_name,14)
	# 棉棉、阿潮、暖暖沒有另一張對話頁，好感頁就是入口，不放返回鈕。
	if id in Bond.WALK_UP:return
	var back:Button=app.button("回到%s"%("茶園" if id=="chacha" else "水圳手記"),bond_site.bind(app,id))
	back.name="BondSiteBack"
	body.add_child(back)

## 回到該居民原本的對話頁。
static func bond_site(app,id:String) -> void:
	if id=="chacha":app._tea_host()
	elif id in Bond.WALK_UP:bond_dialogue(app,id)
	elif id=="xinghe":
		if str(app.session.snapshot.get("region_id","home"))=="lanyang":app._gardener_menu()
		else:app._journal(id)
	else:app._resident_menu(id)

static func bond_gifts(app,id:String) -> void:
	var npc_name:String=Bond.name_of(id)
	var body:VBoxContainer=app._open_modal("送給%s的禮物"%npc_name)
	app.modal.set_meta("life_modal_layout","community_board")
	app.modal.set_meta("resident_gift_picker",true)
	var bond:=bond_view(app,id)
	line(app,body,"%s喜歡：%s"%[npc_name,Bond.LIKE_TEXT[id]],16)
	line(app,body,"今天已經送過禮物。再送也會收下，但好感明天再算。" if bond.get("gifted_today",false) else "每天第一份禮物會增加好感，喜歡的東西加得更多。作物、花和家常料理也可以送。",15)
	var held:Dictionary=player(app).get("inventory",{})
	var cell:Vector2i=World.bond_place(app.session.snapshot,id)[1]
	var list:=HFlowContainer.new()
	list.name="BondGiftList"
	body.add_child(list)
	for item:String in Bond.gift_items(id):
		var count:=int(held.get(item,0))
		if count<1:continue
		var choice:Button=app.button("%s%s ×%d"%["喜歡・" if Bond.liked(id,item) else "",World.NAMES[item],count],send_gift.bind(app,cell,id,item))
		choice.name="BondGift_"+item
		choice.icon=ItemArt.icon(item)
		choice.expand_icon=true
		choice.add_theme_constant_override("icon_max_width",24)
		list.add_child(choice)
	if list.get_child_count()==0:line(app,body,"背包裡目前沒有可以送的東西。",15)
	body.add_child(app.button("回到%s身邊"%npc_name,bond_dialogue.bind(app,id) if Bond.LOCAL_NAMES.has(id) else app._resident_menu.bind(id)))

## 一次只翻開一階事件：上排四個分頁（BondEventTab_0..3），下方一張 BondEventCard。
## selected<0 時預設最新展開的一階（都沒展開就是第一階）；未展開的分頁仍可選，顯示門檻。
static func add_milu_apron_button(app,actions:Container) -> void:
	if app.session.snapshot.get("resident_goals",{}).get("milu",{}).get("4",{}).get("state")!="done":return
	var wearing:=bool(player(app).get(World.RESIDENT_GOALS.APRON_KEY,false))
	var button:Button=app.button("收起米露的圍裙" if wearing else "穿上米露的圍裙",func():
		var at:Vector2i=World.bond_place(app.session.snapshot,"milu")[1]
		app.session.perform(World.RESIDENT_GOALS.APRON_ACTION,at)
		app._close_modal())
	button.name="MiluApron"
	actions.add_child(button)

static func sheep_corner(app) -> void:
	var body:VBoxContainer=app._open_modal("雲朵羊的遮雨角落")
	app.modal.name="SheepComfortProject"
	app.modal.set_meta("life_modal_layout","sheep_comfort_project")
	app.modal.theme=PixelTheme.make(app.hud.theme)
	app.modal.add_theme_stylebox_override("panel",PixelTheme.frame_style())
	var cell:Vector2i=World.LIVESTOCK.ANIMALS.sheep.cell
	line(app,body,"替小羊留一處乾燥、柔軟的地方。關閉音效也能完成。",16)
	var project:=HBoxContainer.new()
	project.add_theme_constant_override("separation",12)
	body.add_child(project)
	for id:String in Goals.SHEEP_COMFORT_PARTS:
		var paper:=card(project)
		paper.name="SheepComfortCard_"+id
		var panel:=paper.get_parent() as PanelContainer
		panel.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		var feature:=HBoxContainer.new()
		feature.add_theme_constant_override("separation",10)
		paper.add_child(feature)
		add_icon(feature,sheep_corner_texture(0 if id=="shelter" else 1),64)
		var detail:=VBoxContainer.new()
		detail.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		detail.size_flags_vertical=Control.SIZE_SHRINK_CENTER
		feature.add_child(detail)
		line(app,detail,"遮雨棚" if id=="shelter" else "纖維墊",19)
		var part:Dictionary=Goals.SHEEP_COMFORT_PARTS[id]
		for item:String in part.cost:
			var material:=HBoxContainer.new()
			material.add_theme_constant_override("separation",5)
			detail.add_child(material)
			add_icon(material,ItemArt.icon(item),24)
			line(app,material,"",15).name="SheepComfortCost_%s_%s"%[id,item]
		var build:Button=app.button(str(part.label),func():app.session.perform(Goals.SHEEP_SHELTER_ACTION,cell,id))
		build.name="SheepComfort_"+id
		paper.add_child(build)
	line(app,body,"",16).name="SheepComfortStatus"
	var watch:Button=app.button("安靜看小羊走出屋簷",func():
		app.session.perform(Goals.SHEEP_STEP_ACTION,cell,"calm" if app.sound.reduced_motion else "")
		app._close_modal())
	watch.name="SheepStepWatch"
	body.add_child(watch)
	var toys:=VBoxContainer.new()
	toys.name="SheepComfortToys"
	body.add_child(toys)
	line(app,toys,"棉棉留下的玩具",18)
	var choices:=HBoxContainer.new()
	choices.add_theme_constant_override("separation",12)
	toys.add_child(choices)
	for toy:String in Goals.SHEEP_TOYS:
		var play:Button=app.button("拿%s陪牠玩"%Goals.SHEEP_TOYS[toy],func():
			app.session.perform(Goals.SHEEP_TOY_ACTION,cell,toy)
			app._close_modal())
		play.name="SheepToy_"+toy
		play.icon=sheep_corner_texture(2 if toy=="ball" else 3)
		play.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		choices.add_child(play)
	refresh_sheep_corner(app)
	app._layout_preview.call_deferred()

static func sheep_corner_texture(frame:int) -> AtlasTexture:
	var icon:=AtlasTexture.new()
	icon.atlas=preload("res://assets/ui-inventory/sheep-comfort.png")
	icon.region=Rect2(frame*32,0,32,32)
	icon.filter_clip=true
	return icon

static func refresh_sheep_corner(app) -> void:
	if not is_instance_valid(app.modal) or app.modal.name!="SheepComfortProject":return
	var snapshot:Dictionary=app.session.snapshot
	var bits:=int(snapshot.get("own_sheep_corner",0))
	var inventory:Dictionary=player(app).get("inventory",{})
	var fixtures:=int(snapshot.get("sheep_comfort_fixtures",0))
	var can_build:=int(bond_view(app,"mianmian").get("stage",0))>=2
	var reported:bool=goal_state(app,"mianmian",2).get("state")=="done"
	for id:String in Goals.SHEEP_COMFORT_PARTS:
		var part:Dictionary=Goals.SHEEP_COMFORT_PARTS[id]
		var built:bool=(bits&int(part.bit))!=0
		var enough:=true
		for item:String in part.cost:
			var count:=int(inventory.get(item,0))
			var required:=int(part.cost[item])
			enough=enough and count>=required
			var cost:=app.modal.find_child("SheepComfortCost_%s_%s"%[id,item],true,false) as Label
			cost.text="%s  %d / %d"%[World.NAMES[item],count,required] if not built else "材料已用於布置"
		var build:=app.modal.find_child("SheepComfort_"+id,true,false) as Button
		build.text="已準備" if built else str(part.label)
		build.disabled=built or not enough or not can_build
	var status:=app.modal.find_child("SheepComfortStatus",true,false) as Label
	if not can_build:
		status.text="先和棉棉熟悉一些，就能替小羊布置。"
	elif bits==Goals.SHEEP_COMFORT_MASK and not reported:
		status.text="遮雨棚和纖維墊都準備好了。回牧場找棉棉。"
	elif (fixtures&1)!=0:
		var shelter:=preload("res://scripts/sheep_shelter.gd").new()
		shelter.observe(snapshot,0.0)
		status.text=shelter.status
	else:
		status.text="準備好木材和纖維後，就能在這裡布置。"
	var watch_state:=str(goal_state(app,"mianmian",4).get("state","locked"))
	var watch:=app.modal.find_child("SheepStepWatch",true,false) as Button
	watch.visible=watch_state!="locked" and (fixtures&1)!=0
	watch.text="再安靜看小羊走出屋簷" if watch_state=="done" else "安靜看小羊走出屋簷"
	(app.modal.find_child("SheepComfortToys",true,false) as Control).visible=reported
	var extra:float=(84.0 if reported else 0.0)+(54.0 if watch.visible else 0.0)
	if app.modal.get_meta("sheep_project_extra_height",-1.0)!=extra:
		app.modal.set_meta("sheep_project_extra_height",extra)
		app._layout_preview.call_deferred()

static func tea_guest_seat(app) -> void:
	var body:VBoxContainer=app._open_modal("替茶亭留個座位")
	app.modal.set_meta("life_modal_layout","keepsake_paper")
	var chosen:String=app.session.snapshot.get("own_chacha_tea_chair","")
	line(app,body,"挑一張和茶亭木椅不同的椅子，留給下一位來喝茶的人。",16)
	var choices:=HBoxContainer.new()
	choices.add_theme_constant_override("separation",12)
	body.add_child(choices)
	for choice:String in Goals.TEA_CHAIRS:
		var seat:Dictionary=Goals.TEA_CHAIRS[choice]
		var panel:=card(choices)
		(panel.get_parent() as Control).size_flags_horizontal=Control.SIZE_EXPAND_FILL
		var icon:=AtlasTexture.new()
		icon.atlas=preload("res://assets/ui-life/furniture.png")
		icon.region=Rect2(96,48,32,48)
		add_icon(panel,icon,68)
		var art:=panel.get_child(0) as TextureRect
		art.modulate=seat.tint
		var title:=line(app,panel,str(seat.name),17)
		title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		var location:=line(app,panel,"茶亭左側" if choice=="wood" else "茶亭右側",14)
		location.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		if chosen.is_empty():
			var place:Button=app.button("放上"+str(seat.name),func():
				app.session.perform(Goals.TEA_CHAIR_ACTION,seat.cell,choice)
				app._close_modal())
			place.name="ChachaChair_"+choice
			place.tooltip_text="在%s放上%s"%[location.text,seat.name]
			panel.add_child(place)
		elif choice==chosen:line(app,panel,"已留好座位，回去告訴茶茶吧。",15)

static func tea_arrangement(app) -> void:
	var body:VBoxContainer=app._open_modal("茶茶的一席茶")
	app.modal.set_meta("life_modal_layout","community_board")
	var saved:String=app.session.snapshot.get("own_chacha_tea_setup","")
	var setup:Dictionary={"axis":saved,"cups":2 if not saved.is_empty() else 0}
	var paper:=card(body)
	var preview:=preload("res://scripts/tea_arrangement_preview.gd").new()
	preview.name="TeaArrangementPreview"
	paper.add_child(preview)
	var caption:Label=app.label("",15)
	paper.add_child(caption)
	var actions:=HFlowContainer.new()
	body.add_child(actions)
	var cups:Button
	var submit:Button
	var choices:=ButtonGroup.new()
	var update:=func():
		preview.axis=setup.axis
		preview.cups=setup.cups
		preview.queue_redraw()
		if setup.axis.is_empty():
			caption.text="先選方向，再放上兩只杯子。"
		else:
			caption.text="%s茶桌 · 杯子 %d／2"%["直放" if setup.axis=="vertical" else "橫放",setup.cups]
		for axis:String in Goals.TEA_AXES:
			var direction:=actions.get_node_or_null("TeaAxis_"+axis) as Button
			if direction!=null:direction.set_pressed_no_signal(setup.axis==axis)
		var cup_button:=actions.get_node_or_null("TeaPlaceCup") as Button
		var confirm_button:=body.get_node_or_null("TeaConfirmArrangement") as Button
		if cup_button!=null:cup_button.disabled=setup.axis.is_empty() or setup.cups>=2
		if confirm_button!=null:confirm_button.disabled=setup.cups!=2
	if saved.is_empty():
		for axis:String in Goals.TEA_AXES:
			var direction:Button=app.button("橫擺茶桌" if axis=="horizontal" else "直擺茶桌",func():
				setup.axis=axis
				update.call())
			direction.name="TeaAxis_"+axis
			direction.toggle_mode=true
			direction.button_group=choices
			actions.add_child(direction)
		cups=app.button("放上一只杯子",func():
			setup.cups+=1
			update.call())
		cups.name="TeaPlaceCup"
		actions.add_child(cups)
		submit=app.button("確認布置",func():
			app.session.perform(Goals.TEA_SETUP_ACTION,World.TEA_CERAMICS.TEA_NPC,"%s:%d"%[setup.axis,setup.cups])
			app._close_modal())
		submit.name="TeaConfirmArrangement"
		body.add_child(submit)
	update.call()
	preview.reduced_motion=app.sound.reduced_motion
	body.add_child(app.button("回到茶茶",bond_dialogue.bind(app,"chacha")))

static func add_paint_invitation(app,actions:Container,id:String,cell:Vector2i) -> void:
	if id=="diandian" or not painting_can_invite(app):return
	var snapshot:Dictionary=app.session.snapshot
	var spot:=World.bond_place(snapshot,id)
	if snapshot.get("region_id","home")!=spot[0] or not Bond.present(snapshot,id):return
	var person:=player(app)
	if Vector2(float(person.get("x",0)),float(person.get("y",0))).distance_to(Vector2(cell)+Vector2(0.5,0.5))>3.2:return
	var invited:Array=app.session.snapshot.get("own_diandian_invites",[])
	if invited.size()>=Goals.PAINT_INVITE_COUNT or id in invited:return
	var invite:Button=app.button("邀請入畫",func():
		app.session.perform(Goals.PAINT_INVITE_ACTION,cell,id)
		app._close_modal())
	invite.name="DiandianInvite"
	actions.add_child(invite)

static func add_public_mural_link(app) -> void:
	var s:Dictionary=app.session.snapshot
	if not public_mural_available(app):return
	var body:=app.modal.find_child("ModalContent",true,false) as VBoxContainer
	if body==null:return
	var link:Button=app.button("看看全島合畫" if s.has(Goals.MURAL_KEY) else "布置公共合畫",public_mural.bind(app))
	link.name="PublicMural"
	body.add_child(link)
	body.move_child(link,0)

static func public_mural_available(app) -> bool:
	var s:Dictionary=app.session.snapshot
	return bool(s.get("picnic",false)) and (s.has(Goals.MURAL_KEY) or (painting_finished(app) and int(bond_view(app,"diandian").get("stage",0))>=4))

static func public_mural_stamp(app) -> Array:
	var s:Dictionary=app.session.snapshot
	return [s.get(Goals.MURAL_KEY,{}),s.get("own_diandian_mural",false),public_mural_available(app),public_mural_near(app)]

static func public_mural_near(app) -> bool:
	if app.session.snapshot.get("region_id","home")!="home":return false
	var person:=player(app)
	return Vector2(float(person.get("x",0)),float(person.get("y",0))).distance_to(Vector2(Goals.MURAL_SITE)+Vector2(0.5,0.5))<=3.2

static func refresh_public_mural(app) -> void:
	if not is_instance_valid(app.modal) or not app.modal.has_meta("mural_page"):return
	var stamp:=public_mural_stamp(app)
	if app.modal.get_meta("mural_stamp")!=stamp:public_mural.call_deferred(app,app.modal.get_meta("mural_page"),app.modal.get_meta("mural_back"),app.modal.get_instance_id())

static func public_mural(app,page:=-1,back:=Callable(),previous_id:=0) -> void:
	if previous_id!=0 and (not is_instance_valid(app.modal) or app.modal.get_instance_id()!=previous_id):return
	var s:Dictionary=app.session.snapshot
	var mural:Dictionary=s.get(Goals.MURAL_KEY,{})
	var body:VBoxContainer=app._open_modal("全島合畫")
	app.modal.set_meta("life_modal_layout","community_board")
	app.modal.set_meta("mural_page",page)
	app.modal.set_meta("mural_stamp",public_mural_stamp(app).duplicate(true))
	app.modal.set_meta("mural_back",back)
	var nearby:=public_mural_near(app)
	var actions:=mural_footer(app,body)
	if back.is_valid():actions.add_child(app.button("返回",back))
	if mural.is_empty():
		var preview:=preload("res://scripts/resident_painting.gd").new()
		preview.subjects=s.get("own_diandian_invites",[]).duplicate()
		preview.subjects.append("")
		preview.finished=true
		card(body).add_child(preview)
		line(app,body,"在風鈴渡口公告板旁掛上合畫，留一個位置給下一位島民。",17)
		var hang:Button=app.button("掛上合畫，留一格空白",func():
			app.session.perform(Goals.MURAL_HANG_ACTION,Goals.MURAL_SITE))
		hang.name="HangMural"
		hang.disabled=not nearby or not public_mural_available(app)
		body.add_child(hang)
		return
	var names:Array=mural.names
	var index:=names.size() if page<0 else clampi(page,0,names.size())
	var paper:=card(body)
	var art:=preload("res://scripts/resident_painting.gd").new()
	art.name="ResidentPainting"
	art.subjects=mural.subjects.duplicate()
	art.subjects.append("farmer" if index<names.size() else "")
	art.finished=true
	paper.add_child(art)
	var credits:=HBoxContainer.new()
	paper.add_child(credits)
	for id:String in mural.subjects:
		add_mural_caption(app,credits,Bond.name_of(id))
	add_mural_caption(app,credits,str(names[index]) if index<names.size() else "留給下一位")
	line(app,body,"作者落款 · 點點與 %s　　入畫島民 %d 位"%[mural.author_name,names.size()],16)
	if not names.is_empty():
		var pages:=HFlowContainer.new()
		body.add_child(pages)
		if index>0:pages.add_child(app.button("看上一位",public_mural.bind(app,index-1,back)))
		if index<names.size():pages.add_child(app.button("看下一位",public_mural.bind(app,index+1,back)))
		if index<names.size():pages.add_child(app.button("回到空白位置",public_mural.bind(app,-1,back)))
	if nearby and not s.get("own_diandian_mural",false):
		var sign:Button=app.button("把我的身影加進畫裡",func():
			app.session.perform(Goals.MURAL_SIGN_ACTION,Goals.MURAL_SITE))
		sign.name="SignMural"
		body.add_child(sign)
	elif s.get("own_diandian_mural",false):
		line(app,body,"你的名字已留在合畫上。",15)
	elif not nearby:
		line(app,body,"到渡口公告板旁，可以留下自己的身影和落款。",15)

static func add_mural_caption(app,parent:HBoxContainer,caption:String) -> void:
	var label:Label=app.label(caption,15)
	label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	label.autowrap_mode=TextServer.AUTOWRAP_OFF
	label.custom_minimum_size.y=28
	label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
	parent.add_child(label)

static func painting_can_invite(app) -> bool:
	return int(bond_view(app,"diandian").get("stage",0))>=3 and (goal_state(app,"diandian",2).get("state")=="done" or goal_state(app,"diandian",3).get("state")=="done")

static func painting_available(app) -> bool:
	return painting_can_invite(app) or goal_state(app,"diandian",3).get("state")=="done" or not app.session.snapshot.get("own_diandian_invites",[]).is_empty()

static func painting_label(app) -> String:
	return "點點的第一幅合畫" if painting_finished(app) else "合畫草稿"

static func painting_finished(app) -> bool:
	return goal_state(app,"diandian",3).get("state")=="done" and app.session.snapshot.get("own_diandian_invites",[]).size()==Goals.PAINT_INVITE_COUNT

static func mural_footer(app,body:VBoxContainer) -> HBoxContainer:
	var footer:=HBoxContainer.new()
	if is_instance_valid(app.modal_feedback) and app.modal.is_ancestor_of(app.modal_feedback):
		var feedback:Label=app.modal_feedback
		feedback.get_parent().add_child(footer)
		feedback.reparent(footer,false)
		feedback.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		feedback.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	else:body.add_child(footer)
	return footer

static func painting_book(app,back:Callable) -> void:
	var finished:=painting_finished(app)
	var body:VBoxContainer=app._open_modal("點點的第一幅合畫" if finished else "畫面外的位置")
	app.modal.set_meta("life_modal_layout","diandian_painting")
	var invited:Array=app.session.snapshot.get("own_diandian_invites",[])
	var paper:=card(body)
	var art:=preload("res://scripts/resident_painting.gd").new()
	art.name="ResidentPainting"
	art.subjects=invited
	art.finished=finished
	paper.add_child(art)
	var credits:=HBoxContainer.new()
	paper.add_child(credits)
	for i in Goals.PAINT_INVITE_COUNT:
		var nameplate:Label=app.label(Bond.name_of(invited[i]) if i<invited.size() else "留給下一位",16)
		nameplate.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		nameplate.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		credits.add_child(nameplate)
	if finished:
		line(app,body,"「我想把每個人都畫進去，紙卻不夠大。」——點點",16)
		if public_mural_available(app):body.add_child(app.button("前往公共展區",public_mural.bind(app,-1,painting_book.bind(app,back))))
	elif invited.size()<Goals.PAINT_INVITE_COUNT and not painting_can_invite(app):
		line(app,body,"已邀請 %d／%d 位。先到映星池邊完成〈沒畫好的手〉。"%[invited.size(),Goals.PAINT_INVITE_COUNT],16)
	elif invited.size()<Goals.PAINT_INVITE_COUNT:
		line(app,body,"已邀請 %d／%d 位。靠近任一位居民，對話時選「邀請入畫」。"%[invited.size(),Goals.PAINT_INVITE_COUNT],16)
	else:
		line(app,body,"三個位置都有人了。回星芽庭園向點點回報。",16)
	var footer:=mural_footer(app,body)
	var back_button:Button=app.button("返回",back)
	back_button.name="DiandianPaintingBack"
	footer.add_child(back_button)

static func add_growth_observation(app,body:VBoxContainer,tile:Vector2i,crop:Dictionary) -> void:
	var s:Dictionary=app.session.snapshot
	var region:=str(s.get("region_id","home"))
	var kind:=str(crop.get("kind",""))
	if region not in Goals.GROWTH_REGIONS or not World.CROPS.has(kind) or crop.get("other_sown",false) or int(bond_view(app,"xinghe").get("stage",0))<1:return
	var logbook:Dictionary=s.get("own_xinghe_growth_log",{})
	if logbook.has(kind):
		line(app,body,"星禾觀察簿 · 已收錄%s"%World.NAMES[kind],15)
		return
	if not logbook.is_empty() and goal_state(app,"xinghe",1).get("state")!="done":
		line(app,body,"第一份觀察已完成，回蘭陽找星禾。",15)
		return
	var phase:=Goals.growth_phase(crop,float(World.CROPS[kind].time))
	var tracked:Dictionary=s.get("own_xinghe_growth",{})
	var same:bool=tracked=={"region":region,"tile":World.key(tile),"kind":kind}
	if phase=="growing" or (phase=="mature" and not same) or (phase=="early" and same):
		line(app,body,"幼苗已記錄，等這一株成熟。" if same else "觀察請從剛種下的幼苗開始。",15)
		return
	var title:="記下成熟的樣子" if phase=="mature" else ("改觀察這株幼苗" if not tracked.is_empty() else "記下幼苗")
	var record:Button=app.button(title,func():
		app.session.perform(Goals.GROWTH_ACTION,tile)
		app._close_modal())
	record.name="XingheGrowthObservation"
	body.add_child(record)

static func shared_garden_view(app) -> Array:
	return [app.session.snapshot.get(Goals.GARDEN_KEY,[]),str(goal_state(app,"xinghe",4).get("state","locked")),goal_near(app,"xinghe")]

static func refresh_shared_garden(app) -> void:
	if not is_instance_valid(app.modal) or not app.modal.has_meta("xinghe_garden_view"):return
	var view:=shared_garden_view(app)
	if app.modal.get_meta("xinghe_garden_view")==view:return
	var body:VBoxContainer=app.modal.get_meta("xinghe_garden_body")
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()
	draw_shared_garden(app,body,view,app.modal.get_meta("xinghe_garden_back"))

static func shared_garden(app,back:=Callable()) -> void:
	var body:VBoxContainer=app._open_modal("大家的花園日")
	app.modal.set_meta("life_modal_layout","xinghe_shared_garden")
	app.modal.set_meta("xinghe_garden_back",back)
	app.modal.set_meta("xinghe_garden_body",body)
	draw_shared_garden(app,body,shared_garden_view(app),back)

static func draw_shared_garden(app,body:VBoxContainer,view:Array,back:Callable) -> void:
	var pots:Array=view[0]
	var state:String=view[1]
	var nearby:bool=view[2]
	app.modal.set_meta("xinghe_garden_view",view.duplicate(true))
	line(app,body,"水圳旁的花盆  %d／%d"%[pots.size(),Goals.GARDEN_POTS.size()],18)
	var flowers:=HBoxContainer.new()
	flowers.add_theme_constant_override("separation",8)
	body.add_child(flowers)
	for index in Goals.GARDEN_POTS.size():
		var slot:=card(flowers)
		var tile:=slot.get_parent() as PanelContainer
		tile.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		tile.custom_minimum_size.y=112
		if index>=pots.size():
			line(app,slot,"留給下一位",16)
			continue
		var pot:Dictionary=pots[index]
		var art:=AtlasTexture.new()
		art.atlas=preload("res://assets/lanyang-life/shared-garden-pots.png")
		art.region=Rect2(Goals.GARDEN_FLOWERS.find(pot.flower)*32,0,32,32)
		add_icon(slot,art,48)
		line(app,slot,World.NAMES[pot.flower],16)
		line(app,slot,"%s挑選"%pot.name,15)
	if pots.size()==Goals.GARDEN_POTS.size():
		if state in ["open","done"]:
			var report:Button=app.button("查看共同花園牌" if state=="done" else "找星禾回報",bond_goal.bind(app,"xinghe",4))
			report.name="XingheGardenReport"
			body.add_child(report)
		else:line(app,body,"三盆花都在水圳旁了。",16)
	elif not nearby:
		line(app,body,"到蘭陽水圳旁找星禾，就能在花園選一盆花。",15)
	else:
		var mine:=false
		var residents:=PackedStringArray()
		for pot:Dictionary in pots:
			if pot.npc:residents.append(pot.author)
			elif pot.author==app.session.own_id:mine=true
		line(app,body,"每人各選一盆。朋友可以從星禾的對話加入。",15)
		var choices:=HFlowContainer.new()
		body.add_child(choices)
		if not mine and (state!="locked" or not pots.is_empty()):
			for flower:String in Goals.GARDEN_FLOWERS:
				var pick:Button=app.button(World.NAMES[flower],shared_garden_pick.bind(app,flower))
				pick.name="XinghePlant_"+flower
				pick.icon=ItemArt.icon(flower)
				pick.expand_icon=true
				pick.custom_minimum_size.x=160
				pick.add_theme_constant_override("icon_max_width",24)
				choices.add_child(pick)
		if state!="locked":
			var invites:=HFlowContainer.new()
			body.add_child(invites)
			for resident:String in Goals.GARDEN_NPCS:
				if resident in residents:continue
				var ask:Button=app.button("請%s挑一盆"%Goals.GARDEN_NPCS[resident].name,shared_garden_pick.bind(app,resident))
				ask.name="XingheInvite_"+resident
				invites.add_child(ask)
		elif pots.is_empty():line(app,body,"請星禾的好友選第一盆花。",15)
	var return_button:Button=app.button("返回",back if back.is_valid() else bond_dialogue.bind(app,"xinghe"))
	return_button.name="XingheGardenBack"
	return_button.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	body.add_child(return_button)

static func shared_garden_pick(app,flower:String) -> void:
	app.session.perform(Goals.GARDEN_ACTION,World.LANYANG_LIFE.SERVICE,flower)

static func crop_observation_desk(app) -> void:
	var body:VBoxContainer=app._open_modal("觀察記錄桌")
	app.modal.set_meta("life_modal_layout","return_news")
	var page:=card(body)
	page.name="DeskNotes"
	var header:=HBoxContainer.new()
	header.add_theme_constant_override("separation",12)
	page.add_child(header)
	add_icon(header,preload("res://assets/ui-life/crop-observation-desk.png"),64)
	var notes:=VBoxContainer.new()
	notes.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	header.add_child(notes)
	line(app,notes,"我的種植紀錄",19)
	var farm:Dictionary=app.session.snapshot.get("own_crop_summary",{})
	line(app,notes,"可收成 %d 格・生長中 %d 格"%[farm.get("ready",0),farm.get("growing",0)],15)
	var routes:=HBoxContainer.new()
	routes.add_theme_constant_override("separation",10)
	body.add_child(routes)
	var almanac:Button=app.button("作物圖鑑",app.LifeAlmanac.collection_menu.bind(app,1,crop_observation_desk.bind(app)))
	almanac.name="DeskCropAlmanac"
	routes.add_child(almanac)
	var growth:Button=app.button("種植觀察簿",growth_book.bind(app,crop_observation_desk.bind(app)))
	growth.name="DeskGrowthLog"
	routes.add_child(growth)
	app.LifeShell.reveal(app,page)

static func growth_book(app,return_to:=Callable(),back_label:="返回觀察記錄桌") -> void:
	XingheGrowth.open(app,return_to,back_label)

static func diandian_sketchbook(app,back:Callable) -> void:
	var body:VBoxContainer=app._open_modal("點點的速寫簿")
	app.modal.set_meta("life_modal_layout","diandian_sketchbook")
	var sketches:Dictionary=app.session.snapshot.get("own_crop_sketches",{})
	var finished:bool=goal_state(app,"diandian",1).get("state")=="done"
	var paper:=card(body)
	var count:=line(app,paper,"觀察紀錄 · %d／%d"%[sketches.size(),Goals.SKETCH_TARGET],19)
	count.name="DiandianSketchCount"
	var subjects:Array=sketches.keys()
	if not finished:
		while subjects.size()<Goals.SKETCH_TARGET:subjects.append("")
	app.LifeAlmanac.add_sketch_stickers(app,paper,subjects)
	if finished:
		line(app,paper,"畫過的動物和作物已收進圖鑑貼紙。",15)
	elif sketches.size()>=Goals.SKETCH_TARGET:
		line(app,paper,"把速寫帶回星芽庭園給點點看。",15)
	else:
		line(app,paper,"在渡口靠近作物、糯米雞或飼料站旁的動物，按互動鍵，再選擇畫下來。",15)
		line(app,paper,"同一種只記一次，速寫可以留著作物和動物原樣。",14)
	if finished:add_diandian_sketch_rewards(app,body,diandian_sketchbook.bind(app,back),"返回速寫簿")
	bookcase_back(app,body,"返回上一頁",back)

static func add_diandian_sketch_rewards(app,parent:Container,back:Callable,caption:="返回點點的故事") -> void:
	var row:=HFlowContainer.new()
	row.add_theme_constant_override("h_separation",8)
	row.add_theme_constant_override("v_separation",6)
	parent.add_child(row)
	var easel:Button=app.button("翻看小畫架圖樣",func():app.life_panels.build_menu(app,"sketch_easel"))
	easel.name="DiandianSketchEaselPattern"
	easel.icon=Shell.icon("blueprint")
	easel.add_theme_constant_override("icon_max_width",28)
	row.add_child(easel)
	var stickers:Button=app.button("翻開圖鑑貼紙",app.LifeAlmanac.collection_menu.bind(app,1,back,caption))
	stickers.name="DiandianSketchStickerAlbum"
	row.add_child(stickers)

static func add_postcard_clue(app,parent:Container,id:String,cell:Vector2i,bond_stage:int) -> void:
	if bond_stage<1 or not Goals.POSTCARD_CLUES.has(id) or goal_state(app,"luoluo",2).get("state")!="open":return
	if goal_state(app,"luoluo",1).get("state")!="done":return
	var clues:Array=app.session.snapshot.get("own_luoluo_postcard_clues",[])
	if id in clues or clues.size()>=Goals.KNOWN_NEEDED:return
	var ask:Button=app.button("詢問無址信的線索",func():
		app.session.perform(Goals.POSTCARD_CLUE_ACTION,cell,id)
		app._close_modal())
	ask.name="LuoluoAskPostcardClue"
	parent.add_child(ask)

static func luoluo_memory_letter(app,back:Callable) -> void:
	var story:=goal_state(app,"luoluo",3)
	if story.get("state")!="done":return
	var handed:bool=story.get("choice")=="letter"
	var body:VBoxContainer=app._open_modal("洛洛的回憶信")
	app.modal.set_meta("life_modal_layout","luoluo_memory_letter")
	body.add_theme_constant_override("separation",8)
	var paper:=card(body)
	paper.add_theme_constant_override("separation",6)
	var scene:=LuoluoLetterScene.new()
	scene.reduced=app.sound.reduced_motion
	scene.handed=handed
	scene.envelope=Shell.icon("letter")
	paper.add_child(scene)
	var captions:=[ "洛洛在碼頭找到米露，把摺過好幾次的紙拿了出來。",
		"洛洛把信交給米露。米露靠在欄邊讀完。" if handed else "洛洛攤開信紙，把寫好的話念給米露聽。",
		"米露把信收好，說下次等船時，還要一起坐在老樹下。" ]
	if scene.reduced:
		captions[2]="洛洛把信交給米露。她讀完，把它收好。" if handed else "洛洛把信念給米露。她聽完，把信收好。"
	var caption:=line(app,paper,captions[0],15)
	caption.name="LuoluoMemoryBeat"
	scene.beat_changed.connect(func(index:int):caption.text=captions[index])
	var message:=card(body)
	line(app,message,"留給米露",18)
	var words:=line(app,message,"那天我在碼頭等船，你陪我坐了一會兒。我一直記得。謝謝你，讓那段等候的時間也有個好去處。",16)
	words.name="LuoluoMemoryMessage"
	var actions:=HFlowContainer.new()
	actions.add_theme_constant_override("h_separation",8)
	body.add_child(actions)
	var replay:Button=app.button("重看這一幕",scene.play)
	replay.name="LuoluoMemoryReplay"
	actions.add_child(replay)
	var notes:Button=app.button("前往島民留言板",island_notes.bind(app,luoluo_memory_letter.bind(app,back)))
	notes.name="LuoluoMemoryOpenNotes"
	actions.add_child(notes)
	var return_button:Button=app.button("返回上一頁",back)
	return_button.name="LuoluoMemoryBack"
	actions.add_child(return_button)
	scene.play()

static func luoluo_future_book(app,back:Callable) -> void:
	if goal_state(app,"luoluo",4).get("state")!="done":return
	var body:VBoxContainer=app._open_modal("個人回憶冊")
	app.modal.set_meta("life_modal_layout","luoluo_future_book")
	var paper:=card(body)
	var heading:=HBoxContainer.new()
	heading.add_theme_constant_override("separation",12)
	paper.add_child(heading)
	add_icon(heading,Shell.icon("letter"),44)
	var title:=line(app,heading,"寫給未來的我",21)
	title.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	var message:=str(app.session.snapshot.get("own_luoluo_future_note",""))
	var letter:=line(app,paper,"這封信留了一張空白的紙。" if message.is_empty() else message,18)
	letter.name="LuoluoFutureWords"
	line(app,paper,"收在這座島的個人回憶冊，只有你可以翻閱。",14)
	var display:=card(body)
	var row:=HBoxContainer.new()
	row.add_theme_constant_override("separation",14)
	display.add_child(row)
	add_icon(row,LuoluoCap.texture(),72)
	var cap:=VBoxContainer.new()
	cap.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	row.add_child(cap)
	line(app,cap,"洛洛的信差帽",19)
	var wear:Button=app.button("",func():
		var person:=player(app)
		if person.is_empty():return
		var site:=Vector2i(floori(float(person.x)),floori(float(person.y)))
		app.session.perform(Goals.COURIER_CAP_ACTION,site,"remove" if person.get(Goals.COURIER_CAP_KEY,false) else "wear"))
	wear.name="LuoluoCourierCapToggle"
	wear.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	cap.add_child(wear)
	bookcase_back(app,body,"返回上一頁",back)
	refresh_luoluo_cap(app)

static func refresh_luoluo_cap(app) -> void:
	var button:=goal_node(app,"LuoluoCourierCapToggle") as Button
	if button!=null:button.text="脫下信差帽" if player(app).get(Goals.COURIER_CAP_KEY,false) else "戴上信差帽"

static func luoluo_future_input(app,parent:Container) -> void:
	var paper:=card(parent)
	paper.get_parent().name="LuoluoFutureInputPanel"
	line(app,paper,"這句話只會存在自己的回憶冊。",14)
	var field:=LineEdit.new()
	field.name="LuoluoFutureInput"
	field.placeholder_text="親愛的未來的我……"
	field.max_length=World.ISLAND_NOTES.LENGTH
	paper.add_child(field)
	field.text_changed.connect(func(_value:String):refresh_goal_page(app,true))
	paper.get_parent().hide()

static func postcard_notebook(app,back:Callable) -> void:
	var clues:Array=app.session.snapshot.get("own_luoluo_postcard_clues",[])
	var finished:bool=goal_state(app,"luoluo",2).get("state")=="done"
	var body:VBoxContainer=app._open_modal("沒有地址的信")
	app.modal.set_meta("life_modal_layout","luoluo_postcard_notebook")
	body.add_theme_constant_override("separation",8)
	var intro:=card(body)
	var header:=HBoxContainer.new()
	header.add_theme_constant_override("separation",12)
	intro.add_child(header)
	add_icon(header,Shell.icon("letter"),42)
	var summary:=VBoxContainer.new()
	summary.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	header.add_child(summary)
	var progress:=line(app,summary,"訪談筆記 · %d／%d"%[clues.size(),Goals.KNOWN_NEEDED] if not finished or not clues.is_empty() else "手冊收藏 · 已完成",19)
	progress.name="LuoluoPostcardProgress"
	line(app,summary,"洛洛在信裡找到一片壓乾的葉子。",15)
	var notes:=card(body) if not clues.is_empty() else null
	if notes!=null:notes.add_theme_constant_override("separation",5)
	for id:String in clues:
		if id!=clues[0]:notes.add_child(HSeparator.new())
		var row:=HBoxContainer.new()
		row.name="PostcardClue_"+id
		row.add_theme_constant_override("separation",12)
		notes.add_child(row)
		var portrait:=Art.icon(id)
		add_icon(row,portrait if portrait!=null else Shell.icon("letter"),38)
		var words:=VBoxContainer.new()
		words.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		words.add_theme_constant_override("separation",0)
		row.add_child(words)
		line(app,words,Bond.name_of(id),17)
		line(app,words,"「%s」"%Goals.POSTCARD_CLUES[id],15)
	if finished and clues.is_empty():
		line(app,body,"洛洛把信收在碼頭旁，讓帶回來的風景都有個可以留下的位置。",16)
	elif not finished:
		if goal_state(app,"luoluo",1).get("state")!="done":
			line(app,body,"先把上一封信送達，再回渡口找洛洛開始訪談。",16)
		elif clues.size()<Goals.KNOWN_NEEDED:
			line(app,body,"走到任何已認識的居民身邊，選「詢問無址信的線索」。",16)
		elif not is_instance_valid(app.modal_feedback):
			line(app,body,"回渡口把這三段話說給洛洛聽。",16)
	var close:Button=app.button("返回上一頁",back)
	close.name="LuoluoPostcardNotebookBack"
	if is_instance_valid(app.modal_feedback):
		var footer:=HBoxContainer.new()
		footer.add_theme_constant_override("separation",10)
		app.modal_feedback.get_parent().add_child(footer)
		app.modal_feedback.reparent(footer,false)
		app.modal_feedback.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		if not finished and clues.size()>=Goals.KNOWN_NEEDED:
			app.modal_feedback.text="線索已集齊，回渡口找洛洛。"
		footer.add_child(close)
		if app.controller_navigation:close.grab_focus()
	else:
		body.add_child(close)

static func add_address_control(app,parent:Container) -> void:
	var stage:=int(app.session.snapshot.get("own_luoluo_address",0))
	var action:Button
	if stage==0:
		action=app.button("收下待送的信",func():
			var site:Vector2i=World.bond_place(app.session.snapshot,"luoluo")[1]
			app.session.perform(Goals.ADDRESS_ACTION,site,"take")
			app._close_modal())
		action.name="LuoluoTakeLetter"
	else:
		action=app.button("打開洛洛的信封",address_letter.bind(app))
		action.name="LuoluoReadLetter"
	parent.add_child(action)

static func add_address_delivery(app,parent:Container,resident:String) -> void:
	if resident not in Goals.ADDRESS_CANDIDATES or int(app.session.snapshot.get("own_luoluo_address",0))!=Goals.ADDRESS_CARRIED:return
	var deliver:Button=app.button("問這封信是不是你的",func():
		app.session.perform(Goals.ADDRESS_ACTION,Village.resident_cell(app.session.snapshot,resident),resident)
		app._close_modal())
	deliver.name="LuoluoDeliverLetter"
	parent.add_child(deliver)

static func address_letter(app,back:Callable=Callable()) -> void:
	var stage:=int(app.session.snapshot.get("own_luoluo_address",0))
	var title:="已送達的信" if stage==Goals.ADDRESS_DELIVERED else "洛洛的信封"
	var body:VBoxContainer=app._open_modal(title if stage>0 else "普通信箱")
	app.modal.set_meta("life_modal_layout","luoluo_letter")
	app.modal.set_meta("luoluo_letter_back",back.is_valid())
	body.add_theme_constant_override("separation",8)
	if stage==0:
		line(app,body,"信箱目前是空的。洛洛在渡口出貨箱附近整理信件。",16)
		return
	var paper:=card(body)
	var header:=HBoxContainer.new()
	header.add_theme_constant_override("separation",12)
	paper.add_child(header)
	add_icon(header,Shell.icon("letter"),48)
	var heading:=line(app,header,"信封上的三條線索",20)
	heading.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	var clues:Array[Label]=[]
	for hint:String in Goals.ADDRESS_CLUES:
		var clue:Label=app.label("%d. %s"%[clues.size()+1,hint],16)
		clue.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		clue.name="AddressClue%d"%(clues.size()+1)
		paper.add_child(clue)
		clues.append(clue)
	var zoom:=CheckButton.new()
	zoom.name="LuoluoAddressZoom"
	zoom.text="放大信件文字"
	zoom.toggled.connect(func(enlarged:bool):
		app.set_meta("luoluo_envelope_zoom",enlarged)
		app.modal.set_meta("luoluo_letter_enlarged",enlarged)
		for clue:Label in clues:
			var base:=26 if enlarged else 16
			var pixels:int=app.scaled_font_size(base)
			clue.set_meta("font_scale_base",base)
			clue.set_meta("font_scale_applied",pixels)
			clue.add_theme_font_size_override("font_size",pixels)
		app._layout_preview.call_deferred())
	body.add_child(zoom)
	zoom.button_pressed=bool(app.get_meta("luoluo_envelope_zoom",false))
	var recorded:bool=goal_state(app,"luoluo",1).get("state")=="done"
	var message:="阿榆已收到信。送達紀錄已收進手冊。" if recorded else "阿榆已收到信。可以回去找洛洛。"
	line(app,body,message if stage==Goals.ADDRESS_DELIVERED else "帶著信去找居民，當面確認是不是他收。",15)
	if back.is_valid():
		var back_button:Button=app.button("回到關係事件",back)
		back_button.name="LuoluoAddressBack"
		body.add_child(back_button)

static func foot_bath(app,at:Vector2i,anchor:Vector2i) -> void:
	var body:VBoxContainer=app._open_modal("暖石泡腳池")
	app.modal.set_meta("life_modal_layout","inn_tea_table")
	var own:Dictionary=player(app).get(Goals.MASTER_BENCH_SEAT,{})
	var key:=World.key(anchor)
	if own.get("cell")==key:
		body.add_child(app.button("起身",func():app.session.perform("inn_pool_sit",at);app._close_modal()))
		return
	line(app,body,"挑一個位子坐下歇一會兒。",16)
	var occupied:Dictionary={}
	for guest:Dictionary in app.session.snapshot.players.values():
		var seat:Dictionary=guest.get(Goals.MASTER_BENCH_SEAT,{})
		if seat.get("cell")==key:occupied[int(seat.side)]=true
	var seats:=GridContainer.new()
	seats.columns=2
	body.add_child(seats)
	for index in World.INDUSTRY.FOOT_BATH_SEATS.size():
		var used:=occupied.has(index)
		var choice:Button=app.button(("座位 %d 已有人" if used else "座位 %d")%[index+1],func():
			app.session.perform("inn_pool_sit",at,str(index))
			app._close_modal())
		choice.name="FootBathSeat%d"%index
		choice.disabled=used
		choice.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		seats.add_child(choice)

static func guest_wardrobe(app,cell:Vector2i,kind:=Goals.WARDROBE_KIND) -> void:
	if kind==Goals.FOREST_WARDROBE:
		forest_wardrobe(app,cell)
		return
	var body:VBoxContainer=app._open_modal(World.BUILD[kind].name)
	var workwear:=kind in Goals.WORKWEAR_WARDROBES
	app.modal.set_meta("life_modal_layout","inn_wardrobe" if workwear else "station_dialogue")
	var display:=HBoxContainer.new()
	display.add_theme_constant_override("separation",14)
	body.add_child(display)
	var art:Texture2D
	match kind:
		Goals.COAST_WARDROBE:art=preload("res://assets/ui-life/coast-changing-booth.png")
		Goals.INN_WARDROBE:art=preload("res://assets/ui-inventory/inn-lattice-wardrobe.png")
		_:art=preload("res://assets/ui-inventory/guest-wardrobe.png")
	add_icon(display,art,64)
	var choices:=VBoxContainer.new()
	choices.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	display.add_child(choices)
	if workwear:
		var person:Dictionary=player(app)
		var blue:bool=person.get("blue_outfit",false)
		if World.FLOWER_NURSERY.blue_outfit_unlocked(person):
			line(app,choices,"目前穿著藍染工作服。" if blue else "目前穿著原色工作服。",16)
			var outfit:Button=app.button("換回原色工作服" if blue else "換上藍染工作服",func():
				app.session.perform("inn_outfit",cell,"original" if blue else "blue")
				app._close_modal())
			outfit.name="InnWardrobeOutfit"
			choices.add_child(outfit)
		else:
			line(app,choices,"先在田尾染製藍染工作服，就可以回來換穿。",16)
	wardrobe_apron(app,choices,cell)

static func forest_wardrobe(app,cell:Vector2i) -> void:
	var body:VBoxContainer=app._open_modal(World.BUILD[Goals.FOREST_WARDROBE].name)
	app.modal.set_meta("life_modal_layout","forest_wardrobe")
	app.modal.theme=PixelTheme.make(app.hud.theme)
	app.modal.add_theme_stylebox_override("panel",PixelTheme.frame_style())
	var person:=player(app)
	var wearing_blue:bool=person.get("blue_outfit",false)
	var unlocked:=World.FLOWER_NURSERY.blue_outfit_unlocked(person)
	var has_apron:bool=goal_state(app,"milu",4).get("state")=="done"
	app.modal.set_meta("forest_wardrobe_apron",has_apron)
	var options:=HBoxContainer.new()
	options.add_theme_constant_override("separation",12)
	body.add_child(options)
	for use_blue:bool in [false,true]:
		var name:="藍染工作服" if use_blue else "原色工作服"
		var active:=wearing_blue==use_blue
		var locked:=use_blue and not unlocked
		var outfit_card:=card(options)
		outfit_card.get_parent().size_flags_horizontal=Control.SIZE_EXPAND_FILL
		if app.view.character_art:
			var image:=Shell.picture(app.view.character_art.workwear_preview(use_blue),96)
			if locked:image.modulate=Color("aaa59c")
			outfit_card.add_child(image)
		var status:=line(app,outfit_card,name,18)
		status.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		status.add_theme_color_override("font_color",Color("294d65") if use_blue else Color("713f32"))
		var outfit:Button=app.button("穿著中" if active else ("尚未取得" if locked else "換穿"),func():
			app.session.perform("inn_outfit",cell,"blue" if use_blue else "original")
			app._close_modal())
		outfit.name="ForestWardrobeBlue" if use_blue else "ForestWardrobeOriginal"
		outfit.disabled=active or locked
		outfit.add_theme_color_override("font_disabled_color",Color("473e2d"))
		outfit_card.add_child(outfit)
	line(app,body,"換穿不消耗材料。" if unlocked else "在田尾染製工作服，就能解鎖藍染配色。",15)
	if has_apron:
		wardrobe_apron(app,body,cell)
	app._layout_preview.call_deferred()

static func wardrobe_apron(app,choices:VBoxContainer,cell:Vector2i) -> void:
	if goal_state(app,"milu",4).get("state")!="done":
		line(app,choices,"米露的圍裙會收在這裡。先完成她的共餐事件，就能在更衣櫃換穿。",16)
		return
	var wearing:bool=player(app).get(Goals.APRON_KEY,false)
	line(app,choices,"目前穿著米露的圍裙。" if wearing else "米露的圍裙收在櫃裡。",16)
	var apron:Button=app.button("收起米露的圍裙" if wearing else "換上米露的圍裙",func():
		app.session.perform(Goals.APRON_ACTION,cell)
		app._close_modal())
	apron.name="GuestWardrobeApron"
	choices.add_child(apron)

static func aru_bench_pattern(app) -> void:
	if goal_state(app,"aru",2).get("state")!="done":return
	var body:VBoxContainer=app._open_modal("師父長椅的鉛筆圖樣")
	app.modal.set_meta("life_modal_layout","keepsake_paper")
	var paper:=card(body)
	var sketch:=TextureRect.new()
	sketch.name="AruBenchSketch"
	sketch.texture=preload("res://assets/ui-life/aru-bench-pattern.png")
	sketch.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	sketch.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	sketch.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	sketch.custom_minimum_size.y=136
	paper.add_child(sketch)
	line(app,paper,"左椅腳、椅背橫木、右椅腳。阿榆把一起檢查過的三處接點都圈了起來。",16)
	var recipe:Dictionary=World.BUILD[Goals.MASTER_BENCH]
	line(app,paper,"師父的長椅占橫向兩格，需要木材 %d、硬木 %d。"%[recipe.wood,recipe.hardwood],16)
	var open_folio:Button=app.button("到家園工坊看師父的長椅",func():app.life_panels.build_menu(app,Goals.MASTER_BENCH))
	open_folio.name="AruBenchPatternBuild"
	body.add_child(open_folio)

static func bell_tree_available(snapshot:Dictionary) -> bool:
	if not snapshot.get(Goals.TREE_NOTES,[]).is_empty() or snapshot.get("resident_goals",{}).get("lingpopo",{}).get("4",{}).get("state")=="done":return true
	return bool(snapshot.get("picnic",false)) and int(snapshot.get("resident_bonds",{}).get("lingpopo",{}).get("stage",0))>=1 and (int(snapshot.get("own_lingpopo_bell",0))&Goals.BELL_TREE_BIT)==0

static func bell_inspection(app,site:String) -> void:
	var tree:=site=="tree"
	var body:VBoxContainer=app._open_modal("風鈴樹" if tree else "裂開的小鈴")
	var has_notes:bool=tree and (not app.session.snapshot.get(Goals.TREE_NOTES,[]).is_empty() or goal_state(app,"lingpopo",4).get("state")=="done")
	app.modal.set_meta("life_modal_layout","keepsake_paper" if has_notes else "lingpopo_clue")
	var note:=card(body)
	if tree:
		bell_history_panel(app,note,"低枝上的空繩","一截空繩垂在低枝上，打的是雙結。其他小鈴都綁在同樣的高度。",bell_tree_icon())
	else:
		bell_history_panel(app,note,"鈴口與細繩","鈴婆婆把舊鈴轉了過來。鈴口裂了一道，雙結還好好地留在細繩上。",preload("res://assets/ui-inventory/cracked-dock-bell.png"))
	var target:Vector2i=World.Festival.TREE_CELL if tree else Bond.bell_cell(app.session.snapshot)
	if tree:
		add_tree_notes(app,body)
		if int(app.session.snapshot.get("own_lingpopo_bell",0))&Goals.BELL_TREE_BIT:return
		if int(bond_view(app,"lingpopo").get("stage",0))<1:return
	var record:Button=app.button("記下空繩上的雙結" if tree else "記下鈴口的裂紋",func():
		app.session.perform(Goals.BELL_INSPECT_ACTION,target,site)
		app._close_modal())
	record.name="LingpopoRecordClue"
	record.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	body.add_child(record)

static func bell_tree_icon() -> Texture2D:
	return Art.atlas_region("res://assets/village-preview/props.png",Rect2(0,0,64,64))

static func bell_history_panel(app,parent:VBoxContainer,title:String,copy:String,texture:Texture2D) -> void:
	var row:=HBoxContainer.new()
	row.add_theme_constant_override("separation",14)
	parent.add_child(row)
	add_icon(row,texture,64)
	var text:=VBoxContainer.new()
	text.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation",5)
	row.add_child(text)
	line(app,text,title,17)
	line(app,text,copy,15)

static func bell_pattern_reward(app,parent:VBoxContainer) -> void:
	var paper:=card(parent)
	paper.get_parent().name="LingpopoBellPatternCard"
	var row:=HBoxContainer.new()
	row.add_theme_constant_override("separation",14)
	paper.add_child(row)
	add_icon(row,ItemArt.icon(Goals.FESTIVAL_BELL),72)
	var text:=VBoxContainer.new()
	text.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	row.add_child(text)
	var recipe:Dictionary=World.BUILD[Goals.FESTIVAL_BELL]
	line(app,text,recipe.name+"圖樣",17)
	var materials:=HFlowContainer.new()
	materials.add_theme_constant_override("h_separation",12)
	text.add_child(materials)
	for id:String in recipe:
		if id=="name":continue
		var material:=HBoxContainer.new()
		material.add_theme_constant_override("separation",4)
		materials.add_child(material)
		add_icon(material,ItemArt.icon(id),24)
		var amount:=line(app,material,"%s ×%d"%[World.NAMES[id],recipe[id]],14)
		amount.autowrap_mode=TextServer.AUTOWRAP_OFF
	var workshop:Button=app.button("到工坊查看圖樣",func():app.life_panels.build_menu(app,Goals.FESTIVAL_BELL))
	workshop.name="LingpopoBellPattern"
	workshop.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	row.add_child(workshop)

static func add_tree_notes(app,body:VBoxContainer) -> void:
	var notes:Array=app.session.snapshot.get(Goals.TREE_NOTES,[])
	var writable:bool=goal_state(app,"lingpopo",4).get("state")=="done"
	if not writable and notes.is_empty():return
	line(app,body,"低枝上的留言",19)
	if not notes.is_empty():
		show_tree_note(app,body,notes[0])
	if writable:
		var field:=LineEdit.new()
		field.name="FestivalTreeDraft"
		field.max_length=World.ISLAND_NOTES.LENGTH
		field.placeholder_text="留一句話給下一個經過的人"
		body.add_child(field)
		var post:=func():
			var message:=World.ISLAND_NOTES.clean(field.text)
			if message.is_empty():return
			app.session.perform(Goals.TREE_NOTE_ACTION,World.Festival.TREE_CELL,message)
			app._close_modal()
		var send:Button=app.button("把留言綁上低枝",post)
		send.name="FestivalTreePost"
		field.text_submitted.connect(func(_value:String):post.call())
		body.add_child(send)

	for index in range(1,notes.size()):show_tree_note(app,body,notes[index])

static func show_tree_note(app,body:VBoxContainer,entry:Dictionary) -> void:
	var paper:=card(body)
	line(app,paper,str(entry.text),16)
	line(app,paper,str(entry.sender),14)

static func bell_history_unlocked(app,page:int) -> bool:
	return goal_state(app,"lingpopo",page).get("state")=="done"

static func add_bell_history_bookmark(app,parent:Container) -> void:
	if not bell_history_unlocked(app,1) and not bell_history_unlocked(app,2):return
	var bookmark:Button=app.button("風鈴渡口島史",bell_history.bind(app))
	bookmark.name="LingpopoIslandHistory"
	parent.add_child(bookmark)

static func bell_history(app,page:=1,back:=Callable()) -> void:
	if not bell_history_unlocked(app,page):page=2 if page==1 else 1
	if not bell_history_unlocked(app,page):return
	var title:="島史第一頁 · 低枝上的空繩" if page==1 else "島史第二頁 · 三枚不同的鈴"
	var body:VBoxContainer=app._open_modal(title)
	app.modal.set_meta("life_modal_layout","lingpopo_history")
	line(app,body,"鈴婆婆口述・風鈴渡口的故事",15)
	var paper:=card(body)
	if page==1:
		bell_history_panel(app,paper,"給晚歸人的繩結","渡口還沒有夜燈時，送船的人會把鈴繫在低枝。晚歸的人摸到繩結，就知道上岸的石階不遠了。",bell_tree_icon())
		bell_history_panel(app,paper,"鈴婆婆留下的小鈴","後來船多了，低枝上還留著一截空繩。鈴婆婆收著裂開的小鈴，等下一個想聽故事的人來。",preload("res://assets/ui-inventory/cracked-dock-bell.png"))
	else:
		bell_history_panel(app,paper,"掛在三條路上的鈴","圓鈴、角鈴和方鈴原本各掛在一條回家的路上。有人記得形狀，有人記得聲音，也有人記得樹下那盞燈。",preload("res://assets/ui-inventory/memorial-bell-copper.png"))
		bell_history_panel(app,paper,"一起畫下的回家路","鈴婆婆把 △、○、□ 畫在同一張紙上。她說，認得回家的路，本來就有很多種辦法。",preload("res://assets/ui-life/paper-tea-lamp.png"))
	var other:=2 if page==1 else 1
	var actions:=HFlowContainer.new()
	actions.add_theme_constant_override("h_separation",8)
	body.add_child(actions)
	if bell_history_unlocked(app,other):actions.add_child(app.button("翻到第二頁" if other==2 else "翻回第一頁",bell_history.bind(app,other,back)))
	var return_button:Button=app.button("返回關係事件" if back.is_valid() else "回到島民手冊",back if back.is_valid() else journal.bind(app))
	return_button.name="LingpopoHistoryBack"
	actions.add_child(return_button)

static func bell_order_guide(app,body:VBoxContainer,entry:Dictionary) -> void:
	var guide:=card(body)
	line(app,guide,"照著圖案，由左到右排鈴",16)
	var order:=HBoxContainer.new()
	order.add_theme_constant_override("separation",8)
	guide.add_child(order)
	for index in entry.order.size():
		var slot:=card(order)
		(slot.get_parent() as PanelContainer).size_flags_horizontal=Control.SIZE_EXPAND_FILL
		var symbol:=line(app,slot,str(entry.steps[entry.order[index]]),19)
		symbol.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		var status:=line(app,slot,"尚未放入",13)
		status.name="LingpopoBellSlot_%d"%index
		status.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER

static func add_milu_recipe_book(app,parent:Container) -> void:
	if int(bond_view(app,"milu").get("stage",0))<2:return
	var button:Button=app.button("翻開米露的食譜手記",milu_recipe_book.bind(app))
	button.name="MiluRecipeBook"
	parent.add_child(button)

static func milu_recipe_book(app) -> void:
	MiluRecipePages.open(app,resident.bind(app,"milu"),"回到米露")

static func add_milu_recipe_page(app,site:String) -> void:
	var snapshot:Dictionary=app.session.snapshot
	if snapshot.get("region_id")!=World.REGIONS.HOME or int(bond_view(app,"milu").get("stage",0))<2:return
	if not is_instance_valid(app.modal):return
	var cell:=World.milu_recipe_cell(snapshot,site)
	var person:=player(app)
	if cell==World.COMMUNITY.NO_CELL or Vector2(person.get("x",0),person.get("y",0)).distance_to(Vector2(cell)+Vector2(0.5,0.5))>3.2:return
	var page:Dictionary=Goals.RECIPE_PAGES[site]
	var found:=int(snapshot.get("own_milu_recipe_pages",0))
	var body:=app.modal.find_child("ModalContent",true,false) as VBoxContainer
	if body==null:return
	if site=="table" and snapshot.get("resident_goals",{}).get("milu",{}).get("2",{}).get("state")=="done":
		add_milu_recipe_book(app,body)
	if (found&int(page.bit))!=0:return
	var button:Button=app.button("拾起沾到麵粉的紙角",func():
		app.session.perform(Goals.RECIPE_PAGE_ACTION,cell,site)
		app._close_modal())
	button.name="MiluRecipePage"
	body.add_child(button)
	body.move_child(button,0)

static func achao_photo_path(app) -> String:
	return "user://achao-voyage-%s.png"%str(app.session.own_id).sha256_text().left(24)

static func achao_take_photo(app) -> void:
	if not app.voyage_photo.visible:return
	app.voyage_photo.hide()
	app.voyage_return.hide()
	var saved:=await capture_island_photo(app,achao_photo_path(app),0.65)
	app._sync_voyage_controls()
	if not saved:
		app._notice("照片無法儲存，請再試一次。",false)
		return
	app.session.perform(Goals.VOYAGE_ACTION,World.RESIDENT_BOND.dock_cell(app.session.snapshot),"photo")

static func achao_return_if_sailing(app) -> bool:
	var snapshot:Dictionary=app.session.snapshot
	if not snapshot.get("players",{}).get(app.session.own_id,{}).get("at_sea",false):return false
	app.session.perform(Goals.VOYAGE_ACTION,World.RESIDENT_BOND.dock_cell(snapshot),"return")
	return true

static func achao_voyage(app) -> void:
	var snapshot:Dictionary=app.session.snapshot
	var place:=World.RESIDENT_BOND.dock_cell(snapshot)
	var body:VBoxContainer=app._open_modal("遠方亮起的燈")
	app.modal.set_meta("life_modal_layout","achao_voyage")
	var paper:=card(body)
	var blue:bool=player(app).get(Goals.VOYAGE_PAINT,false)
	var ship:=AtlasTexture.new()
	ship.atlas=preload("res://assets/transit/achao-voyage.png")
	ship.region=Rect2(48 if blue else 0,0,48,48)
	add_icon(paper,ship,72)
	if not World.TRANSIT.boat_open(snapshot):
		line(app,paper,"先到渡口公告板完成碼頭與小船工程。",17)
		return
	var lit:bool=snapshot.get(Goals.DOCK_LIGHT,false)
	line(app,paper,"碼頭燈亮著，沿著河灣繞一圈就會回到這裡。" if lit else "要先把燈修好，才能看見返航的方向。",17)
	line(app,paper,"試航中按 Esc 或互動鍵可提前返航。",15)
	var controls:=HFlowContainer.new()
	controls.add_theme_constant_override("h_separation",8)
	controls.add_theme_constant_override("v_separation",8)
	body.add_child(controls)
	var operation:="depart" if lit else "repair"
	var action:Button=app.button("出發試航" if lit else "修碼頭燈 · 木材 4、銅礦 1",func():
		app.session.perform(Goals.VOYAGE_ACTION,place,operation)
		app._close_modal())
	action.name="AchaoVoyage_"+operation
	controls.add_child(action)
	if lit:
		var board:Button=app.button("加入剛出航的朋友",func():
			app.session.perform(Goals.VOYAGE_ACTION,place,"join")
			app._close_modal())
		board.name="AchaoVoyageJoin"
		controls.add_child(board)
		var path:=achao_photo_path(app)
		if FileAccess.file_exists(path):
			var album:Button=app.button("翻看上次的船上合照",AchaoVoyageAlbum.open.bind(app,path,achao_voyage.bind(app),"回到碼頭"))
			album.name="AchaoVoyageAlbum"
			controls.add_child(album)
	if AchaoVoyageReward.available(snapshot):
		var paint:Button=app.button("換回原木船身" if blue else "使用藍白船身",func():
			app.session.perform(Goals.VOYAGE_ACTION,place,"paint")
			app._close_modal())
		paint.name="AchaoVoyagePaint"
		controls.add_child(paint)
		var reward:Button=app.button("翻看航海手記",AchaoVoyageReward.open.bind(app,achao_voyage.bind(app),Callable(),"回到碼頭"))
		reward.name="AchaoVoyageRewardFromDock"
		controls.add_child(reward)

static func achao_route_book(app,back:Callable=Callable()) -> void:
	var snapshot:Dictionary=app.session.snapshot
	var done:bool=goal_state(app,"achao",2).get("state")=="done"
	var body:VBoxContainer=app._open_modal("阿潮的手繪群島地圖" if done else "褪色的航線")
	app.modal.set_meta("life_modal_layout","achao_route_chart")
	body.add_theme_constant_override("separation",8)
	var spread:=HBoxContainer.new()
	spread.add_theme_constant_override("separation",12)
	body.add_child(spread)
	var chart:Control=preload("res://scripts/achao_local_chart.gd").make(snapshot,app.sound.reduced_motion)
	chart.name="AchaoLocalChart"
	chart.custom_minimum_size.y=252
	chart.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	chart.size_flags_vertical=Control.SIZE_SHRINK_BEGIN
	spread.add_child(chart)
	var notes:=card(spread)
	var notes_panel:=notes.get_parent() as Control
	notes_panel.custom_minimum_size.x=270
	var marks:=int(snapshot.get("own_achao_route_marks",0))
	var count:=0
	for sign:Dictionary in Goals.ROUTE_SIGNS.values():
		if (marks&int(sign.bit))!=0:count+=1
	line(app,notes,"渡口路標 · %d／3"%count,17)
	var choices:=ButtonGroup.new()
	var hint:=app.label("",15) as Label
	hint.name="AchaoRouteHint"
	hint.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var first_site:=""
	for site:String in Goals.ROUTE_SIGNS:
		var sign:Dictionary=Goals.ROUTE_SIGNS[site]
		var seen:bool=(marks&int(sign.bit))!=0
		var pin:Button=app.button(("✓ " if seen else "○ ")+str(sign.name),func():
			for option:BaseButton in choices.get_buttons():
				option.set_pressed_no_signal(option.name=="AchaoRouteSite_"+site)
			chart.call("select_site",site)
			hint.text=sign.hint)
		pin.name="AchaoRouteSite_"+site
		pin.toggle_mode=true
		pin.button_group=choices
		notes.add_child(pin)
		if not seen and first_site.is_empty():first_site=site
	notes.add_child(hint)
	if first_site.is_empty():first_site=str(Goals.ROUTE_SIGNS.keys()[0])
	var first:=notes.get_node("AchaoRouteSite_"+first_site) as Button
	first.set_pressed_no_signal(true)
	chart.call("select_site",first_site)
	hint.text=Goals.ROUTE_SIGNS[first_site].hint
	if not done and marks==Goals.ROUTE_MASK:
		var report:Button=app.button("回報阿潮",bond_goal.bind(app,"achao",2))
		report.name="AchaoRouteReport"
		body.add_child(report)
	if done:
		var tabs:=HBoxContainer.new()
		tabs.add_theme_constant_override("separation",8)
		body.add_child(tabs)
		body.move_child(tabs,0)
		var regional:=HBoxContainer.new()
		regional.alignment=BoxContainer.ALIGNMENT_CENTER
		body.add_child(regional)
		var map:Control=preload("res://scripts/taiwan_map.gd").new()
		map.name="AchaoChart"
		map.set_meta("current_region",str(snapshot.get("region_id","home")))
		map.set_meta("travel_book",player(app).get("travel_book",{}))
		regional.add_child(map)
		regional.hide()
		var local:Button=app.button("渡口路標",func():achao_chart_tab(app,spread,regional,false))
		local.name="AchaoLocalMapTab"
		tabs.add_child(local)
		var regions:Button=app.button("群島航線",func():achao_chart_tab(app,spread,regional,true))
		regions.name="AchaoRegionMapTab"
		tabs.add_child(regions)
		var view_choice:=ButtonGroup.new()
		for tab:Button in [local,regions]:
			tab.toggle_mode=true
			tab.button_group=view_choice
		local.set_pressed_no_signal(true)
	var actions:=HBoxContainer.new()
	actions.alignment=BoxContainer.ALIGNMENT_END
	if is_instance_valid(app.modal_feedback) and app.modal.is_ancestor_of(app.modal_feedback):
		var footer:Label=app.modal_feedback
		footer.get_parent().add_child(actions)
		footer.reparent(actions,false)
		footer.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		footer.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	else:body.add_child(actions)
	var close:Button=app.button("返回",back if back.is_valid() else bond_dialogue.bind(app,"achao"))
	close.name="AchaoRouteBookBack"
	actions.add_child(close)
	first.grab_focus.call_deferred()
	app._layout_preview.call_deferred()

static func achao_chart_tab(app,local:Control,regional:Control,show_regional:bool) -> void:
	local.visible=not show_regional
	regional.visible=show_regional
	app.modal.set_meta("achao_regional_map",show_regional)
	for tab_name:String in ["AchaoLocalMapTab","AchaoRegionMapTab"]:
		var tab:=app.modal.find_child(tab_name,true,false) as Button
		tab.set_pressed_no_signal((tab_name=="AchaoRegionMapTab")==show_regional)
	app._layout_preview.call_deferred()

static func add_achao_route_marker(app,site:String) -> void:
	var s:Dictionary=app.session.snapshot
	if s.get("region_id")!=World.REGIONS.HOME or int(s.get("resident_bonds",{}).get("achao",{}).get("stage",0))<2:return
	if is_instance_valid(app.modal)==false:return
	var cell:=World.achao_route_cell(site)
	var person:=player(app)
	var at:=Vector2(person.get("x",0),person.get("y",0))
	if at.distance_to(Vector2(cell)+Vector2(0.5,0.5))>3.2:return
	var sign:Dictionary=World.RESIDENT_GOALS.ROUTE_SIGNS[site]
	if (int(s.get("own_achao_route_marks",0))&int(sign.bit))!=0:return
	var body:=app.modal.find_child("ModalContent",true,false) as VBoxContainer
	if body==null:return
	var button:Button=app.button("把%s記進阿潮的航線"%sign.name,func():
		app.session.perform(World.RESIDENT_GOALS.ROUTE_ACTION,cell,site)
		app._close_modal())
	button.name="AchaoRouteMarker"
	body.add_child(button)
	body.move_child(button,0)

static func shared_meal_book(app) -> void:
	MiluSupper.open_book(app,resident.bind(app,"milu"),"回到米露")

static func bond_events(app,id:String,selected:=-1) -> void:
	var npc_name:String=Bond.name_of(id)
	var body:VBoxContainer=app._open_modal("%s的關係事件"%npc_name)
	app.modal.set_meta("life_modal_layout","community_board")
	var bond:=bond_view(app,id)
	var stage:=int(bond.get("stage",0))
	if selected<0 or selected>=Bond.STAGES.size():selected=clampi(stage-1,0,Bond.STAGES.size()-1)
	var header:=HBoxContainer.new()
	header.add_theme_constant_override("separation",12)
	body.add_child(header)
	# 茶茶與棉棉沒有手冊居民頁，改回「居民回憶」；星禾回到自己的手冊頁。
	var back:Button
	if id=="chacha" or id in Bond.WALK_UP:back=app.button("返回居民回憶",resident_memories.bind(app))
	else:back=app.button("返回島民手帳",func():app._journal(id))
	back.name="BondEventsBack"
	header.add_child(back)
	var summary:Label=app.label(bond_text(bond),17)
	summary.name="BondEventsSummary"
	summary.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	header.add_child(summary)
	# T066「一起做的事」：這位居民的行動完成數（n 已完成／m 項）。
	if Goals.GOALS.has(id):
		var goal_count:Label=app.label(goal_count_text(app,id),15)
		goal_count.name="BondGoalCount"
		goal_count.autowrap_mode=TextServer.AUTOWRAP_OFF
		goal_count.size_flags_horizontal=Control.SIZE_SHRINK_END
		goal_count.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
		header.add_child(goal_count)
	var tabs:=HBoxContainer.new()
	tabs.name="BondEventTabs"
	tabs.add_theme_constant_override("separation",8)
	body.add_child(tabs)
	var paper:=card(body)
	paper.get_parent().name="BondEventCard"
	# 卡片正下方：所選那一階的「一起做的事」入口（BondGoalOpen），換分頁時重畫。
	var goal_slot:=HBoxContainer.new()
	goal_slot.name="BondGoalSlot"
	goal_slot.visible=false
	body.add_child(goal_slot)
	var group:=ButtonGroup.new()
	for index in Bond.STAGES.size():
		# 與手帳章節同一套記號：✓ 已展開、○ 尚未展開。
		var tab:Button=app.button(("✓ " if index<stage else "○ ")+str(Bond.STAGES[index]),bond_event_page.bind(app,tabs,paper,id,index))
		tab.name="BondEventTab_%d"%index
		tab.toggle_mode=true
		tab.button_group=group
		tab.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		tabs.add_child(tab)
	bond_event_page(app,tabs,paper,id,selected)
	line(app,body,"聊天、送禮和完成委託都會增加好感。好感不會因為沒上線而下降，朋友的進度也不影響你。",14)

## 換頁只重畫卡片內容，焦點留在剛按下的分頁上。
static func bond_event_page(app,tabs:HBoxContainer,paper:VBoxContainer,id:String,index:int) -> void:
	var stage:=int(bond_view(app,id).get("stage",0))
	for tab:Button in tabs.get_children():tab.set_pressed_no_signal(str(tab.name)=="BondEventTab_%d"%index)
	paper.set_meta("bond_event_index",index)
	for child in paper.get_children():
		paper.remove_child(child)
		child.queue_free()
	if index<stage:
		var event:Dictionary=Bond.EVENTS[id][index]
		line(app,paper,"%s・%s"%[Bond.STAGES[index],event.title],18)
		for text:String in event.lines:line(app,paper,text,15)
	else:
		line(app,paper,"%s・尚未展開（好感 %d）"%[Bond.STAGES[index],Bond.THRESHOLDS[index]],15)
	var slot:=paper.get_parent().get_parent().get_node_or_null("BondGoalSlot") as HBoxContainer
	if slot!=null:goal_entry(app,tabs,slot,id,index)

# ------------------------------------------------- T066「一起做的事」 --
## 只讀自己的摘要 snapshot.resident_goals={居民:{"階數":{"state","choice"[,"needs"]}}}。
## 入口在關係事件頁卡片下方（BondGoalOpen），頁面是 bond_goal(app,id,stage)。
const GOAL_WARN:=Color("9c4b32")
## 與 World.act() 的一般距離檢查相同：玩家位置到居民格中心 3.2 格以內。
const GOAL_REACH:=3.2
const GOAL_ORDER_WRONG:="順序不太對，再看一次圖示。"
const GOAL_NEED_OPTION:="先選一個做法。"
const GOAL_NEED_STEPS:="三個步驟都要做過一次。"
## T066 波波第四階「最後一趟空車」：先推空車，抵達後才能刻字（伺服器與 needs 也會擋）。
const BOBO_CART_NOTE:="靠近空車後按互動鍵推一段。這趟沒有運礦工資。"
const GOAL_BED_RULE:="兩種花各放兩格。"
const BOBO_CART_IDLE:="還沒推空車：先按「開始推空車」，推到展覽位置才能刻字。"
const BOBO_CART_PUSHING:="空車還在路上（已推 %d／6 段），推到展覽位置才能刻字。"
const BOBO_CART_ORE_JOB:="你的運礦台車還在路上，先卸完礦再推波波的空車。"

static func bobo_cart_goal(id:String,stage:int) -> bool:
	return id=="bobo" and stage==4

## 空車的進度說明；已抵達（7）時為空字串。
static func bobo_cart_reason(app) -> String:
	var at:int=World.BOBO_EMPTY_CART.stage(app.session.snapshot)
	if at>=World.ORE_ROUTE.LAST:return ""
	if at<=0:return BOBO_CART_IDLE
	return BOBO_CART_PUSHING%(at-1)

## 「開始推空車」不能按的原因（站位、地區、已開始、運礦中）；空字串＝可以按。
static func bobo_cart_start_reason(app) -> String:
	var s:Dictionary=app.session.snapshot
	var at:int=World.BOBO_EMPTY_CART.stage(s)
	if at>=World.ORE_ROUTE.LAST:return "空車已經推到展覽位置了。"
	if at>0:return "空車已經在路上了，到軌道上的空車旁按互動鍵往前推。"
	var away:=goal_away_reason(app,"bobo")
	if not away.is_empty():return away
	if World.ORE_ROUTE.stage(s)>0:return BOBO_CART_ORE_JOB
	return ""

static func start_bobo_cart(app) -> void:
	if not bobo_cart_start_reason(app).is_empty():return
	var cell:Vector2i=World.bond_place(app.session.snapshot,"bobo")[1]
	app.session.perform(World.BOBO_EMPTY_CART.ACTION,cell,"start")
	app._close_modal()

static func goal_state(app,id:String,stage:int) -> Dictionary:
	var all:Variant=app.session.snapshot.get("resident_goals",{})
	var own:Variant=all.get(id,{}) if all is Dictionary else {}
	var found:Variant=own.get(str(stage),{}) if own is Dictionary else {}
	return found if found is Dictionary else {}

static func goal_count_text(app,id:String) -> String:
	var finished:=0
	var stages:Dictionary=Goals.GOALS.get(id,{})
	for stage:int in stages:
		if str(goal_state(app,id,stage).get("state",""))=="done":finished+=1
	return "一起做的事 %d／%d"%[finished,stages.size()]

## 關係事件頁：所選分頁那一階有行動、而且已到該階（open／done）才放 BondGoalOpen。
## 焦點：分頁 ↓ BondGoalOpen ↓ 返回鈕（Tab／Shift+Tab 同一圈）；BondGoalOpen ↑ 目前的分頁。
static func goal_entry(app,tabs:HBoxContainer,slot:HBoxContainer,id:String,index:int) -> void:
	for child in slot.get_children():
		slot.remove_child(child)
		child.queue_free()
	var back:=tabs.get_parent().find_child("BondEventsBack",true,false) as Button
	for tab:Button in tabs.get_children():tab.focus_neighbor_bottom=NodePath()
	if back!=null:back.focus_previous=NodePath()
	var stage:=index+1
	var state:=str(goal_state(app,id,stage).get("state",""))
	var shown:=Goals.has_goal(id,stage) and state in ["open","done"]
	slot.visible=shown
	if not shown:return
	var entry:Dictionary=Goals.goal(id,stage)
	var open:Button=app.button(("✓ " if state=="done" else "○ ")+"一起做的事・"+str(entry.title),bond_goal.bind(app,id,stage))
	open.name="BondGoalOpen"
	slot.add_child(open)
	for tab:Button in tabs.get_children():tab.focus_neighbor_bottom=tab.get_path_to(open)
	var selected:=tabs.get_node_or_null("BondEventTab_%d"%index) as Button
	if selected!=null:
		open.focus_neighbor_top=open.get_path_to(selected)
		open.focus_previous=open.focus_neighbor_top
	if back!=null:
		open.focus_neighbor_bottom=open.get_path_to(back)
		open.focus_next=open.focus_neighbor_bottom
		back.focus_previous=back.get_path_to(open)

static func goal_items_text(items:Dictionary) -> String:
	var parts:=PackedStringArray()
	for item:String in items:parts.append("%s ×%d"%[str(World.NAMES.get(item,item)),int(items[item])])
	return "、".join(parts)

static func goal_place_text(app,id:String) -> String:
	if Bond.LOCAL_PLACES.has(id):return str(Bond.LOCAL_PLACES[id])
	return World.REGIONS.label(str(World.bond_place(app.session.snapshot,id)[0]))

## 和伺服器相同的站位規則：同一地區、居民已出現、離居民格中心 GOAL_REACH 以內。
static func goal_near(app,id:String) -> bool:
	var s:Dictionary=app.session.snapshot
	var place:Array=World.bond_place(s,id)
	if str(s.get("region_id","home"))!=str(place[0]):return false
	var person:=player(app)
	if person.is_empty():return false
	var cell:Vector2i=place[1]
	return Vector2(float(person.get("x",0.0)),float(person.get("y",0.0))).distance_to(Vector2(cell)+Vector2(0.5,0.5))<=GOAL_REACH

static func goal_away_reason(app,id:String) -> String:
	var locked:String=Bond.locked_reason(app.session.snapshot,id)
	if not locked.is_empty():return locked
	if goal_near(app,id):return ""
	return "要站在%s身邊（%s）才能一起做。"%[Bond.name_of(id),goal_place_text(app,id)]

## 第一個讓「一起完成」不能按的原因；空字串表示可以按。
static func goal_reason(app,id:String,stage:int,choice:String,picks:Array,error:String) -> String:
	if not error.is_empty():return error
	var away:=goal_away_reason(app,id)
	if not away.is_empty():return away
	var entry:Dictionary=Goals.goal(id,stage)
	if bobo_cart_goal(id,stage):
		var cart_note:=bobo_cart_reason(app)
		if not cart_note.is_empty():return cart_note
	if entry.has("options") and Goals.option(entry,choice).is_empty():return GOAL_NEED_OPTION
	if id=="luoluo" and stage==4 and choice=="write":
		var field:=goal_node(app,"LuoluoFutureInput") as LineEdit
		if field==null or World.ISLAND_NOTES.clean(field.text).is_empty():return Goals.FUTURE_NOTE_REQUIRED
	if entry.get("layout",false) and Goals.choice_layout(choice).is_empty():return GOAL_BED_RULE
	if entry.has("steps") and picks.size()<Goals.STEP_COUNT:return GOAL_NEED_STEPS
	for need_row:Dictionary in goal_needs(app,id,stage):
		if not bool(need_row.get("met",false)):return "要先「%s」。"%str(need_row.get("label",""))
	var held:Dictionary=player(app).get("inventory",{})
	var need:Dictionary=Goals.layout_cost(entry,choice,app.session.snapshot)
	for item:String in need:
		if int(held.get(item,0))<int(need[item]):
			return "還差%s %d／%d。"%[str(World.NAMES.get(item,item)),int(held.get(item,0)),int(need[item])]
	return ""

## 第二批：這項行動的前提（伺服器隨本人摘要送來的 needs＝[{"id","label","met"}]）。
## 沒有前提、已完成或快照還沒帶到時為空陣列。
static func goal_needs(app,id:String,stage:int) -> Array:
	var rows:Array=[]
	var found:Variant=goal_state(app,id,stage).get("needs")
	if not found is Array:return rows
	for row:Variant in found:
		if row is Dictionary and row.has("id"):rows.append(row)
	return rows

static func goal_page(app) -> Dictionary:
	if not is_instance_valid(app.modal) or not app.modal.has_meta("bond_goal"):return {}
	var page:Variant=app.modal.get_meta("bond_goal")
	return page if page is Dictionary else {}

static func goal_node(app,name:String) -> Node:
	if not is_instance_valid(app.modal):return null
	return app.modal.find_child(name,true,false)

static func add_guest_cloth_claim(app,parent:Container,keep_open:=false) -> Button:
	var cloth:Button=app.button("領取旅舍布料 ×2",func():
		app.session.perform(Goals.GUEST_CLOTH_ACTION,Bond.SPRING_CELL)
		if not keep_open:app._close_modal())
	cloth.name="NuannuanGuestCloth"
	parent.add_child(cloth)
	return cloth

static func warm_springs_inn(app) -> void:
	var springs:=World.WARM_SPRINGS
	var body:VBoxContainer=app._open_modal("暖泉旅舍")
	app.modal.set_meta("life_modal_layout","keepsake_paper")
	var header:=HBoxContainer.new()
	header.add_theme_constant_override("separation",18)
	body.add_child(header)
	var preview:=Control.new()
	preview.name="InnEntrancePreview"
	preview.custom_minimum_size=Vector2(128,144)
	preview.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	preview.draw.connect(func():springs.draw_inn(preview,Vector2(0,32),0.0,true,springs.entrance_progress(app.session.snapshot)))
	header.add_child(preview)
	var details:=VBoxContainer.new()
	details.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	header.add_child(details)
	var pool_open:bool=app.session.snapshot.get(springs.BATH_KEY,false)
	var description:Label=app.label("溪畔的公共泡腳池已開放。池邊有四個座位。" if pool_open else "溪畔的公共泡腳池暫停使用。到溪邊找暖暖，可以一起修補裂縫。",16)
	description.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	details.add_child(description)
	var enter:Button=app.button("走進旅舍",func():
		app.session.perform(springs.INN_PORTAL,springs.INN_DOOR)
		app._close_modal())
	enter.name="WarmSpringsInnEnter"
	details.add_child(enter)
	var story:Button=app.button("翻開暖暖的故事",bond_events.bind(app,"nuannuan"))
	story.name="WarmSpringsInnStory"
	details.add_child(story)
	var entry_note:Label=app.label("",16)
	entry_note.name="InnEntranceNote"
	entry_note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	body.add_child(entry_note)
	var sweep:Button=app.button("掃開門口落葉",func():app.session.perform(Goals.INN_CLEAR_ACTION,springs.INN_DOOR))
	sweep.name="InnEntranceSweep"
	body.add_child(sweep)
	if inn_resting(app):
		details.add_child(app.button("拍張旅舍合照",take_inn_photo.bind(app)))
	elif FileAccess.file_exists(inn_photo_path(app)):
		details.add_child(app.button("翻看旅舍合照",view_inn_photo.bind(app)))
	refresh_inn_entrance(app)

static func refresh_inn_entrance(app) -> void:
	if not is_instance_valid(app.modal):return
	var preview:=app.modal.find_child("InnEntrancePreview",true,false) as Control
	if preview==null:return
	var springs:=World.WARM_SPRINGS
	var progress:=springs.entrance_progress(app.session.snapshot)
	var met:bool=goal_state(app,"nuannuan",1).get("state")=="open"
	var stamp:=[progress,met]
	if preview.get_meta("entrance_progress",[])==stamp:return
	preview.set_meta("entrance_progress",stamp)
	preview.queue_redraw()
	var note:=app.modal.find_child("InnEntranceNote",true,false) as Label
	var sweep:=app.modal.find_child("InnEntranceSweep",true,false) as Button
	sweep.visible=met and progress==springs.Entrance.LEAVES
	match progress:
		springs.Entrance.LEAVES:note.text="門前積了些落葉和碎石。" if met else "門前積了些落葉。可以先到溪邊認識暖暖。"
		springs.Entrance.SWEPT:note.text="門口清好了。帶石材 8、木材 8 去找溪邊的暖暖。"
		springs.Entrance.LIT:note.text="門口的燈亮了。"

static func inn_photo_path(app) -> String:
	return "user://nuannuan-inn-%s.png"%str(app.session.own_id).sha256_text().left(24)

static func inn_resting(app) -> bool:
	var springs:=World.REGIONS.Springs
	# 主位（choice）與第二個座位（"friend:"+choice）都算坐在旅舍休息處。
	return app.session.snapshot.get("region_id")==springs.REGION and not springs.rest_choice(str(player(app).get(springs.REST_SEAT_KEY,""))).is_empty()

static func take_inn_photo(app) -> void:
	if not inn_resting(app):return
	app._close_modal()
	var saved:=await capture_island_photo(app,inn_photo_path(app),0.65)
	app._notice("旅舍合照已收進暖暖的故事頁。" if saved else "合照無法儲存，請再試一次。",saved)

static func view_inn_photo(app) -> void:
	var image:=Image.load_from_file(inn_photo_path(app))
	if image==null or image.is_empty():
		app._notice("找不到這張旅舍合照。",false)
		return
	var page:VBoxContainer=app._open_modal("旅舍合照")
	app.modal.set_meta("life_modal_layout","keepsake_paper")
	var photo:=TextureRect.new()
	photo.name="NuannuanInnPhoto"
	photo.texture=ImageTexture.create_from_image(image)
	photo.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	photo.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	photo.custom_minimum_size.y=210
	page.add_child(photo)
	page.add_child(app.button("回到故事",bond_goal.bind(app,"nuannuan",4)))

## 「和<名字>一起做的事」：一項行動的頁面（open：選項、步驟、材料、原因、一起完成；
## done：台詞與紀念）。頁面狀態放在 modal 的 meta "bond_goal"。
static func bond_goal(app,id:String,stage:int) -> void:
	var entry:Dictionary=Goals.goal(id,stage)
	if entry.is_empty():return
	var npc_name:String=Bond.name_of(id)
	var body:VBoxContainer=app._open_modal("和%s一起做的事"%npc_name)
	app.modal.set_meta("life_modal_layout","community_board")
	var state:=str(goal_state(app,id,stage).get("state","locked"))
	var bed_plan:=id=="xinghe" and stage==2
	var greenhouse_story:=id=="xinghe" and stage==3
	var bell_order:=id=="lingpopo" and stage==2
	var bell_pattern:=id=="lingpopo" and stage==3
	var bell_ringing:=id=="lingpopo" and stage==4
	var cart_site:=id=="xiaoli" and stage==2
	var returning_guest:=id=="xiaoli" and stage==3
	var shop_sign:=id=="xiaoli" and stage==4
	var letter_goal:=id=="luoluo" and stage==1
	if id=="diandian" and stage==2:
		if state=="open":app.modal.set_meta("fit_diandian_pose",true)
		elif state=="done":app.modal.set_meta("fit_goal_illustration",true)
	if id=="milu" and stage==3:
		if state=="open":app.modal.set_meta("life_modal_layout","milu_tasting")
		elif state=="done":app.modal.set_meta("fit_goal_illustration",true)
	if bed_plan:
		app.modal.set_meta("life_modal_layout","xinghe_bed_plan")
	elif greenhouse_story:
		app.modal.set_meta("life_modal_layout","xinghe_greenhouse_story")
	elif ((bell_pattern or bell_ringing) and state=="done") or ((cart_site or returning_guest or shop_sign) and state!="locked"):
		app.modal.set_meta("fit_goal_illustration",true)
		if cart_site or returning_guest or shop_sign:body.add_theme_constant_override("separation",8)
	var page:={"id":id,"stage":stage,"state":state,"option":"","base":"","layout":"0011","picks":[],"error":"","fp":""}
	app.modal.set_meta("bond_goal",page)
	var title:Label=app.label("%s・%s"%[Bond.stage_name(stage),str(entry.title)],18)
	title.name="BondGoalTitle"
	body.add_child(title)
	if state!="done" or not (bed_plan or greenhouse_story or bell_pattern or bell_ringing or cart_site or returning_guest or shop_sign):
		var task:Label=app.label(str(entry.task),15)
		task.name="BondGoalTask"
		task.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		body.add_child(task)
	if bell_ringing and state!="locked":
		body.add_child(LingpopoBellScene.make(app.sound.reduced_motion))
	if cart_site and state!="locked":
		var map_row:=HBoxContainer.new()
		map_row.add_theme_constant_override("separation",10)
		body.add_child(map_row)
		var chart:=XiaoliSiteChart.make(Goals.XIAOLI_CART_SITES,app.sound.reduced_motion)
		chart.name="XiaoliSiteChart"
		chart.custom_minimum_size.y=132
		chart.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		map_row.add_child(chart)
		var notes:=card(map_row)
		(notes.get_parent() as Control).custom_minimum_size.x=218
		var hint:=line(app,notes,"選一處，看看附近有哪些地標。",14)
		hint.size_flags_vertical=Control.SIZE_EXPAND_FILL
		hint.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
		hint.name="XiaoliSiteHint"
		if state=="done":show_xiaoli_site(app,str(goal_state(app,id,stage).get("choice","")))
	if returning_guest and state!="locked":
		var visit:=VBoxContainer.new()
		visit.name="XiaoliReturnGuestVisit"
		body.add_child(visit)
		var illustration:=XiaoliReturnGuest.make(app.sound.reduced_motion)
		illustration.name="XiaoliReturnGuestArt"
		visit.add_child(illustration)
		line(app,visit,"米露回來了。她想看看你今天在攤上擺了什麼。",15)
	if id=="lingpopo" and stage==1 and state=="open":
		var clues:=int(app.session.snapshot.get("own_lingpopo_bell",0))
		var found_tree:=(clues&Goals.BELL_TREE_BIT)!=0
		var found_bell:=(clues&Goals.BELL_CRACK_BIT)!=0
		var clue_card:=card(body)
		line(app,clue_card,"已記下線索  %d／2"%[int(found_tree)+int(found_bell)],16)
		line(app,clue_card,("✓ " if found_tree else "○ ")+"廣場北側的風鈴樹",15)
		line(app,clue_card,("✓ " if found_bell else "○ ")+"鈴婆婆身邊的小鈴",15)
	if id=="achao" and stage==2 and state!="locked":
		var chart:Button=app.button("翻開阿潮的航線",achao_route_book.bind(app,bond_goal.bind(app,id,stage)))
		chart.name="AchaoGoalRouteBook"
		body.add_child(chart)
	if id=="milu" and stage==2 and state!="locked":
		add_milu_recipe_book(app,body)
	if id=="xinghe" and stage==1 and state!="locked":
		var notebook:Button=app.button("翻開作物觀察簿",growth_book.bind(app,bond_goal.bind(app,id,stage),"返回關係事件"))
		notebook.name="XingheGrowthEntry"
		body.add_child(notebook)
	if id=="milu" and stage==1 and state=="open" and MiluFirstSoup.available(app.session.snapshot):
		var soup_help:Button=app.button("翻看熱蘿蔔湯的做法",MiluFirstSoup.open.bind(app,bond_goal.bind(app,id,stage),"返回關係事件"))
		soup_help.name="MiluFirstSoupEntry"
		body.add_child(soup_help)
	if id=="aru" and stage==1 and state=="open":
		var furniture_note:Label=app.label("完成後收進手帳：原木床桌椅基礎圖樣（小床、小木桌、矮背木椅，附材料與工坊連結）。",14)
		furniture_note.name="AruFirstFurnitureOpenNote"
		furniture_note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		body.add_child(furniture_note)
	if id==World.PAVILION.RESIDENT and stage==World.PAVILION.STAGE and state!="done":
		# T12: say what finishing this unlocks (and why the builder still shows it locked).
		var unlock_note:Label=app.label("完成後解鎖：不完美的茶亭圖樣（家園工坊・茶屋，3×3，竹材 30、木材 10、布料 8）。",14)
		unlock_note.name="BondGoalPavilionUnlock"
		unlock_note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		body.add_child(unlock_note)
	var actions:=HFlowContainer.new()
	actions.name="BondGoalActions"
	actions.add_theme_constant_override("h_separation",8)
	actions.add_theme_constant_override("v_separation",8)
	if id=="xinghe" and stage==4 and state!="locked":
		var garden:Button=app.button("翻看共同花園",shared_garden.bind(app,bond_goal.bind(app,id,stage)))
		garden.name="XingheGardenFromGoal"
		actions.add_child(garden)
	if id=="diandian" and stage==3 and state!="locked":
		if painting_available(app):
			var painting:Button=app.button(painting_label(app),painting_book.bind(app,bond_goal.bind(app,id,stage)))
			painting.name="DiandianPaintingFromGoal"
			actions.add_child(painting)
		else:
			line(app,body,"先到映星池邊完成〈沒畫好的手〉，再開始邀畫。",15)
	if id=="diandian" and stage==4 and state!="locked" and public_mural_available(app):
		var exhibit:Button=app.button("查看全島合畫",public_mural.bind(app,-1,bond_goal.bind(app,id,stage)))
		exhibit.name="DiandianExhibitFromGoal"
		actions.add_child(exhibit)
	if id=="nuannuan" and stage==3 and state=="open" and app.session.snapshot.get("region_id","")==World.REGIONS.HOME and not HouseUI.guest_room_registered(app.session.snapshot):
		var check_room:Button=app.button("檢查身邊的客房",HouseUI.open.bind(app))
		check_room.name="NuannuanCheckGuestRoom"
		actions.add_child(check_room)
	if id=="aru" and stage==3 and state=="open":
		# N01-3：直接在這一頁坐下；選單會關閉，讓場景顯示在世界裡。
		if AruRest.seated(app.session.snapshot,app.session.own_id):
			line(app,body,"你正坐在長椅上，阿榆就在身旁。",15)
		else:
			var rest:Button=app.button("坐到阿榆身旁",aru_rest.bind(app))
			rest.name="AruRestFromGoal"
			actions.add_child(rest)
	if state=="done":
		if id=="aru" and stage==4:
			var album:Button=app.button("翻看長椅相簿",aru_park_album.bind(app))
			album.name="AruParkAlbum"
			actions.add_child(album)
		if id=="aru" and stage==3:
			var sign:Button=app.button("查看可題字的門牌",func():app.life_panels.build_menu(app,"sign"))
			sign.name="AruSignPattern"
			actions.add_child(sign)
		if id=="diandian" and stage==1:
			add_diandian_sketch_rewards(app,actions,bond_goal.bind(app,id,stage))
		if id=="diandian" and stage==2:
			var pattern:Button=app.button("翻看樹皮畫框圖樣",func():app.life_panels.build_menu(app,World.WALL_FIXTURES.BARK_FRAME))
			pattern.name="DiandianBarkFramePattern"
			pattern.icon=Shell.icon("blueprint")
			pattern.add_theme_constant_override("icon_max_width",28)
			actions.add_child(pattern)
		if id=="luoluo" and stage==4:
			var book:Button=app.button("翻開個人回憶冊",luoluo_future_book.bind(app,bond_goal.bind(app,id,stage)))
			book.icon=LuoluoCap.texture()
			book.add_theme_constant_override("icon_max_width",28)
			book.name="LuoluoFutureBook"
			actions.add_child(book)
		if id=="luoluo" and stage==3:
			var letter:Button=app.button("打開洛洛的回憶信",luoluo_memory_letter.bind(app,bond_goal.bind(app,id,stage)))
			letter.icon=Shell.icon("letter")
			letter.add_theme_constant_override("icon_max_width",28)
			letter.name="LuoluoMemoryLetter"
			actions.add_child(letter)
		var done:=card(body)
		done.get_parent().name="BondGoalDone"
		done.add_theme_constant_override("separation",4)
		line(app,done,"✓ 已經一起完成",17)
		for quote in entry.quote:line(app,done,"「%s」"%str(quote),15)
		var picked:Dictionary=Goals.option(entry,str(goal_state(app,id,stage).get("choice","")))
		var custom_sign:bool=shop_sign and not str(app.session.snapshot.get("own_xiaoli_shop",{}).get("input","")).is_empty() and str(picked.get("id",""))=="none"
		if not picked.is_empty() and not custom_sign:
			var selection:Container=done
			if id=="diandian" and stage==2:
				var reference:=HBoxContainer.new()
				reference.add_theme_constant_override("separation",8)
				done.add_child(reference)
				add_icon(reference,DiandianPose.texture(str(picked.id)),40)
				selection=reference
			var recorded_pose:=line(app,selection,"當時選的是：%s"%str(picked.label),15)
			recorded_pose.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
		if id=="xinghe" and stage==2:
			var plan:=Goals.choice_layout(str(goal_state(app,id,stage).get("choice","")))
			var pair:Array=picked.get("items",{}).keys()
			if not plan.is_empty() and pair.size()==2:
				var names:PackedStringArray=[]
				for index in Goals.BED_CELLS:names.append(str(World.NAMES.get(str(pair[int(plan[index])]),"")))
				var layout_line:=line(app,done,"四格排法：左上%s、右上%s、左下%s、右下%s。"%[names[0],names[1],names[2],names[3]],15)
				layout_line.name="XingheBedLayout"
			line(app,done,"花園餅乾配方已解鎖，可在公共廚房灶台製作。",15)
			var rack:Button=app.button("翻看溫室花架圖樣",func():app.life_panels.build_menu(app,"greenhouse_rack"))
			rack.name="XingheRackPattern"
			done.add_child(rack)
		if id=="nuannuan" and stage==1:
			var pattern:Button=app.button("翻看旅舍迎賓牌圖樣",func():app.life_panels.build_menu(app,World.WELCOME_SIGN.KIND))
			pattern.name="NuannuanWelcomeSignPattern"
			done.add_child(pattern)
		if id=="nuannuan" and stage==2:
			line(app,done,"溪畔的公共池已重新開放。走到池邊按 {interact}，有空位就能坐下泡腳。",15)
			var pattern:Button=app.button("翻看暖石泡腳池圖樣",func():app.life_panels.build_menu(app,World.INDUSTRY.FOOT_BATH))
			pattern.name="NuannuanFootBathPattern"
			done.add_child(pattern)
		if id=="nuannuan" and stage==4:
			if inn_resting(app):
				var photo:Button=app.button("拍張旅舍合照",take_inn_photo.bind(app))
				photo.name="NuannuanTakePhoto"
				actions.add_child(photo)
			elif goal_near(app,id):
				var rest:Button=app.button("再陪暖暖坐一會兒",func():
					app.session.perform(World.REGIONS.Springs.REST_REPLAY,Bond.SPRING_CELL)
					app._close_modal())
				rest.name="NuannuanRestReplay"
				actions.add_child(rest)
			if FileAccess.file_exists(inn_photo_path(app)):
				var album:Button=app.button("翻看旅舍合照",view_inn_photo.bind(app))
				album.name="NuannuanViewPhoto"
				actions.add_child(album)
		# 第三批：有紀念小物的行動顯示是否已領；還沒領（第三批之前完成）時多一個補領鈕。
		var keep:=goal_keepsake(app,id,stage)
		if id=="bobo" and stage==1 and BoboRockGuide.available(app.session.snapshot):
			var rock_guide:Button=app.button("翻開礦石辨識頁",BoboRockGuide.open.bind(app,bond_goal.bind(app,id,stage)))
			rock_guide.name="BoboRockGuideEntry"
			done.add_child(rock_guide)
		if id=="mianmian" and stage==4 and MianmianCareJournal.available(app.session.snapshot):
			var journal:Button=app.button("翻開棉棉的照料手札",MianmianCareJournal.open.bind(app,bond_goal.bind(app,id,stage),"返回關係事件"))
			journal.name="MianmianJournalGoalEntry"
			done.add_child(journal)
		if id=="mianmian" and stage==3 and MianmianToyPage.available(app.session.snapshot):
			var toy:Button=app.button("翻看棉棉縫的布玩具",MianmianToyPage.open.bind(app,bond_goal.bind(app,id,stage),"返回關係事件"))
			toy.name="MianmianToyGoalEntry"
			done.add_child(toy)
		if id=="mianmian" and stage==1 and MianmianAnimalNotes.available(app.session.snapshot):
			var notes:Button=app.button("翻開糯米雞的偏好筆記",MianmianAnimalNotes.open.bind(app,bond_goal.bind(app,id,stage),"返回關係事件"))
			notes.name="MianmianNotesGoalEntry"
			done.add_child(notes)
		if id=="bobo" and stage==2:
			line(app,done,"礦山口的礦車入口修好了，隨時可以一起玩。",15)
			done.get_child(done.get_child_count()-1).name="BoboCartUnlockLine"
		if id=="milu" and stage==1 and MiluFirstSoup.available(app.session.snapshot):
			var soup_note:Button=app.button("翻開熱蘿蔔湯的便條",MiluFirstSoup.open.bind(app,bond_goal.bind(app,id,stage),"返回關係事件"))
			soup_note.name="MiluFirstSoupEntry"
			done.add_child(soup_note)
		if id=="milu" and stage==3 and not MiluTasting.completed_dish(app.session.snapshot).is_empty():
			var tasting:Button=app.button("重看試吃會",MiluTasting.open.bind(app,bond_goal.bind(app,id,stage),"返回關係事件"))
			tasting.name="MiluTastingMemory"
			done.add_child(tasting)
		if id=="milu" and stage==4:
			var supper:Button=app.button("翻閱米露的共餐食譜",MiluSupper.open_book.bind(app,bond_goal.bind(app,id,stage),"返回關係事件"))
			supper.name="MiluSupperMemory"
			done.add_child(supper)
		if id=="aru" and stage==1 and AruFirstFurniture.available(app.session.snapshot):
			var furniture:Button=app.button("翻看原木床桌椅基礎圖樣",AruFirstFurniture.open.bind(app,bond_goal.bind(app,id,stage),"返回關係事件"))
			furniture.name="AruFirstFurnitureEntry"
			done.add_child(furniture)
		if id=="lingpopo" and stage<=2:
			var history:Button=app.button("閱讀%s"%entry.keepsake,bell_history.bind(app,stage,bond_goal.bind(app,id,stage)))
			history.name="LingpopoHistoryPage"
			done.add_child(history)
		elif id=="aru" and stage==2:
			line(app,done,"紀念：%s。師父的長椅已加入家園工坊。"%str(entry.keepsake),15)
			var pattern:Button=app.button("翻看長椅圖樣",aru_bench_pattern.bind(app))
			pattern.name="AruBenchPattern"
			done.add_child(pattern)
		elif id=="bobo" and stage==3 and BoboRestBoxPattern.available(app.session.snapshot):
			var rest_pattern:Button=app.button("翻看休息站便攜箱圖樣",BoboRestBoxPattern.open.bind(app,bond_goal.bind(app,id,stage)))
			rest_pattern.name="BoboRestPatternEntry"
			done.add_child(rest_pattern)
		elif id=="milu" and stage==2:
			line(app,done,"紀念：%s"%str(entry.keepsake),15)
		elif id=="chacha" and stage==1 and ChachaTeaPattern.available(app.session.snapshot):
			var tea_pattern:Button=app.button("翻看基本茶具圖樣",ChachaTeaPattern.open.bind(app,bond_goal.bind(app,id,stage)))
			tea_pattern.name="ChachaTeaPatternEntry"
			done.add_child(tea_pattern)
		elif id=="chacha" and stage==4 and ChachaHandwrittenMenu.available(app.session.snapshot):
			var menu:Button=app.button("翻看茶茶手寫茶單",ChachaHandwrittenMenu.open.bind(app,bond_goal.bind(app,id,stage),"返回關係事件"))
			menu.name="ChachaMenuGoalEntry"
			done.add_child(menu)
		elif id=="achao" and stage==3 and AchaoVoyageReward.available(app.session.snapshot):
			var dock:=achao_voyage.bind(app) if goal_near(app,"achao") and World.TRANSIT.boat_open(app.session.snapshot) else Callable()
			var reward:Button=app.button("翻看阿潮的航海手記",AchaoVoyageReward.open.bind(app,bond_goal.bind(app,id,stage),dock))
			reward.name="AchaoVoyageRewardEntry"
			done.add_child(reward)
		elif letter_goal:
			var recipe:Dictionary=World.BUILD[Goals.MAILBOX_KIND]
			var pattern:Button=app.button("到工坊查看信箱圖樣",func():app.life_panels.build_menu(app,Goals.MAILBOX_KIND))
			pattern.icon=ItemArt.icon(Goals.MAILBOX_KIND)
			pattern.add_theme_constant_override("icon_max_width",28)
			pattern.name="LuoluoMailboxPattern"
			line(app,done,"普通信箱 · 木材 %d、纖維 %d。放在家門口可重讀信封。"%[recipe.wood,recipe.fiber],15)
			actions.add_child(pattern)
			var letter:Button=app.button("重讀送達的信",address_letter.bind(app,bond_goal.bind(app,id,stage)))
			letter.name="LuoluoReplayLetter"
			actions.add_child(letter)
		elif id=="luoluo" and stage==2:
			line(app,done,"洛洛留了一個位置給旅行帶回的風景。家園工坊已收錄明信片架圖樣。",15)
			var postcard_pattern:Button=app.button("翻看海風明信片架",func():app.life_panels.build_menu(app,World.POSTCARDS.RACK))
			postcard_pattern.name="LuoluoPostcardPattern"
			postcard_pattern.icon=ItemArt.icon(World.POSTCARDS.RACK)
			postcard_pattern.add_theme_constant_override("icon_max_width",28)
			done.add_child(postcard_pattern)
			var notebook:Button=app.button("重看訪談簿",postcard_notebook.bind(app,bond_goal.bind(app,id,stage)))
			notebook.name="LuoluoPostcardNotebook"
			actions.add_child(notebook)
		elif id=="xinghe" and stage==3:
			line(app,done,"星禾把銅框邊料留給你，家園工坊已收錄兩份圖樣。",15)
			line(app,done,"先用玻璃頂、牆窗和關好的門圍成溫室，再放入育苗箱。四格可以分開照顧。",15)
			var patterns:=HFlowContainer.new()
			patterns.add_theme_constant_override("h_separation",8)
			patterns.add_theme_constant_override("v_separation",6)
			done.add_child(patterns)
			var roof_pattern:Button=app.button("翻看星禾的溫室頂",func():app.life_panels.build_menu(app,World.GREENHOUSE_GLASS.XINGHE_ROOF))
			roof_pattern.name="XingheGreenhousePattern"
			roof_pattern.icon=preload("res://assets/ui-life/xinghe-greenhouse-roof.png")
			var nursery_pattern:Button=app.button("翻看溫室育苗箱",func():app.life_panels.build_menu(app,World.NURSERY_BOX.KIND))
			nursery_pattern.name="XingheNurseryPattern"
			nursery_pattern.icon=preload("res://assets/ui-life/greenhouse-nursery-box.png")
			for pattern in [roof_pattern,nursery_pattern]:
				pattern.expand_icon=true
				pattern.custom_minimum_size.x=272
				pattern.add_theme_constant_override("icon_max_width",36)
				patterns.add_child(pattern)
		elif id==World.PAVILION.RESIDENT and stage==World.PAVILION.STAGE:
			line(app,done,"紀念：%s。%s走到茶亭邊按 {interact}，可以重讀這一場茶會。"%[str(entry.keepsake),World.PAVILION.UNLOCK_NOTE],15)
			var gathering:Button=app.button("重看茶會",ChachaTeaGathering.open.bind(app,bond_goal.bind(app,id,stage)))
			gathering.name="ChachaGatheringEntry"
			done.add_child(gathering)
			var pavilion_pattern:Button=app.button("翻看不完美的茶亭圖樣",func():app.life_panels.build_menu(app,World.INDUSTRY.IMPERFECT_TEA_PAVILION))
			pavilion_pattern.name="ChachaPavilionPattern"
			done.add_child(pavilion_pattern)
		elif id=="nuannuan" and stage==3:
			line(app,done,"暖暖把兩塊布料留給你。搭配四塊木板，就能做一座旅舍更衣櫃。",15)
			page["guest_cloth_claimed"]=bool(app.session.snapshot.get("own_guest_cloth",false))
			if page.guest_cloth_claimed:
				line(app,done,"✓ 旅舍布料已領取",15)
			else:
				var cloth:=add_guest_cloth_claim(app,done,true)
				cloth.disabled=not goal_near(app,id)
				if cloth.disabled:line(app,done,"到礁溪找暖暖領取旅舍布料。",15)
			var wardrobe:Button=app.button("翻看旅舍更衣櫃圖樣",func():app.life_panels.build_menu(app,Goals.WARDROBE_KIND))
			wardrobe.name="NuannuanGuestWardrobePattern"
			done.add_child(wardrobe)
		elif keep.is_empty():
			line(app,done,"紀念：%s（收在手帳裡，沒有其他用途）"%str(entry.keepsake),15)
		else:
			var claimed:=bool(keep.get("claimed",false))
			page["claimed"]=claimed
			var keep_row:=HBoxContainer.new()
			keep_row.name="BondGoalKeepsake"
			keep_row.add_theme_constant_override("separation",8)
			done.add_child(keep_row)
			add_icon(keep_row,ItemArt.icon(str(keep.get("item",""))),32)
			var keep_text:Label=app.label(("紀念小物：%s（已放進背包；按 {build_menu} 打開家園工坊，在「生活」頁可以擺到家園）" if claimed else "紀念小物：%s（還沒領）")%str(keep.get("name",entry.keepsake)),15)
			keep_text.name="BondGoalKeepsakeText"
			keep_text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
			keep_text.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			keep_text.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
			keep_row.add_child(keep_text)
			if id=="chacha" and stage==2 and ChachaCurtainReward.available(app.session.snapshot):
				var reward:Button=app.button("翻看布丁食譜與竹簾圖樣",ChachaCurtainReward.open.bind(app,bond_goal.bind(app,id,stage)))
				reward.name="ChachaCurtainRewardEntry"
				done.add_child(reward)
			if id=="achao" and stage==1 and AchaoKnotMemory.available(app.session.snapshot):
				var guide:Button=app.button("重看阿潮的繩結圖解",AchaoKnotMemory.open.bind(app,bond_goal.bind(app,id,stage)))
				guide.name="AchaoKnotMemoryEntry"
				done.add_child(guide)
			if id=="achao" and stage==4:
				var album:Button=app.button("翻開河灣合照",AchaoVoyageAlbum.open.bind(app,achao_photo_path(app),bond_goal.bind(app,id,stage),"返回關係事件"))
				album.name="AchaoGoalAlbum"
				done.add_child(album)
			if not claimed:
				var claim_reason:Label=app.label("",15)
				claim_reason.name="BondGoalClaimReason"
				claim_reason.add_theme_color_override("font_color",GOAL_WARN)
				body.add_child(claim_reason)
				var claim:Button=app.button("領取紀念小物",do_goal_claim.bind(app))
				claim.name="BondGoalClaim"
				actions.add_child(claim)
		if bell_pattern:bell_pattern_reward(app,body)
		if id=="xiaoli" and stage==1 and app.session.snapshot.has("own_shop_history"):
			var book:Button=app.button("翻開交易簿",app.life_panels.trade_book.bind(app,true,bond_goal.bind(app,id,stage)))
			book.name="XiaoliStoryTradeBook"
			actions.add_child(book)
		if cart_site:
			var pattern:Button=app.button("到工坊查看攤車圖樣",func():app.life_panels.build_menu(app,World.INDUSTRY.COAST_CART))
			pattern.name="XiaoliCartPattern"
			pattern.icon=ItemArt.icon(World.INDUSTRY.COAST_CART)
			pattern.add_theme_constant_override("icon_max_width",28)
			actions.add_child(pattern)
		if returning_guest:
			var reward:Button=app.button("試看新攤布與招牌",xiaoli_market_reward.bind(app))
			reward.name="XiaoliMarketReward"
			actions.add_child(reward)
			var replay:Button=app.button("重看米露回訪",play_xiaoli_visit.bind(app))
			replay.name="XiaoliReplayVisit"
			actions.add_child(replay)
		if shop_sign:xiaoli_shop_rewards(app,body,actions)
		if bell_ringing:
			line(app,body,"到廣場北邊的風鈴樹下，可以留話給下一位經過的人。",15)
			var replay:Button=app.button("再敲一次",ring_story_bell.bind(app,true))
			replay.name="LingpopoRingAgain"
			actions.add_child(replay)
	elif state=="open":
		if id=="milu" and stage==4:
			line(app,body,"料理上桌後，可從共餐桌安排居民座位，再回來找米露。",15)
		if id=="diandian" and stage==2:
			var sit:Button=app.button("在池邊坐下",func():app.session.perform(Goals.DIANDIAN_SEAT_ACTION,Bond.GARDEN_CELL))
			sit.name="DiandianSit"
			actions.add_child(sit)
		if id=="diandian" and stage==1:
			var sketchbook:Button=app.button("打開速寫簿",diandian_sketchbook.bind(app,bond_goal.bind(app,id,stage)))
			sketchbook.name="DiandianSketchBook"
			actions.add_child(sketchbook)
		if id=="luoluo" and stage==2:
			var notebook:Button=app.button("打開訪談簿",postcard_notebook.bind(app,bond_goal.bind(app,id,stage)))
			notebook.name="LuoluoPostcardNotebook"
			actions.add_child(notebook)
		if letter_goal and int(app.session.snapshot.get("own_luoluo_address",0))>0:
			var letter:Button=app.button("查看洛洛的信封",address_letter.bind(app,bond_goal.bind(app,id,stage)))
			letter.name="LuoluoGoalLetter"
			actions.add_child(letter)
		if id=="bobo" and stage==2:
			line(app,body,"銅錠可用小熔爐熔煉，木工零件可在木工台製作。",14)
		if id=="nuannuan" and stage==1:
			var clear:Button=app.button("掃落葉、整理碎石",func():
				app.session.perform(Goals.INN_CLEAR_ACTION,Bond.SPRING_CELL))
			clear.name="NuannuanClearEntrance"
			body.add_child(clear)
		if id=="nuannuan" and stage==2:
			var marks:Label=app.label("",15)
			marks.name="NuannuanCrackProgress"
			marks.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
			body.add_child(marks)
		if bobo_cart_goal(id,stage):
			var route:=VBoxContainer.new()
			route.name="BoboEmptyCartSteps"
			route.add_theme_constant_override("separation",2)
			body.add_child(route)
			var cart_note:Label=app.label(BOBO_CART_NOTE,14)
			cart_note.name="BoboEmptyCartNote"
			cart_note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
			route.add_child(cart_note)
			var cart_status:Label=app.label("",15)
			cart_status.name="BoboEmptyCartStatus"
			cart_status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
			route.add_child(cart_status)
			var cart_start:Button=app.button("開始推空車",start_bobo_cart.bind(app))
			cart_start.name="BoboEmptyCartStart"
			route.add_child(cart_start)
		if entry.has("options"):
			var options:=HFlowContainer.new()
			options.name="BondGoalOptions"
			options.add_theme_constant_override("h_separation",8)
			options.add_theme_constant_override("v_separation",8)
			body.add_child(options)
			var group:=ButtonGroup.new()
			var option_index:=0
			for option:Dictionary in entry.options:
				option_index+=1
				var option_id:=str(option.id)
				var text:=str(option.label)
				if cart_site:text="%d. %s"%[option_index,text]
				var own:Dictionary=option.get("items",{})
				if id=="milu" and stage==3:
					text="%s ×%d"%[text,int(own.get(option_id,0))]
				elif not own.is_empty() and not entry.get("layout",false):
					text+="（%s）"%goal_items_text(own)
				var choice:Button=app.button(text,choose_goal_option.bind(app,option_id))
				choice.name="BondGoalOption_"+option_id
				choice.toggle_mode=true
				choice.button_group=group
				choice.add_theme_font_size_override("font_size",15)
				if id=="diandian" and stage==2:
					choice.icon=DiandianPose.texture(option_id)
					choice.add_theme_constant_override("icon_max_width",40)
				if id=="milu" and stage==3:
					choice.icon=ItemArt.icon(option_id)
					choice.add_theme_constant_override("icon_max_width",28)
				options.add_child(choice)
			if id=="milu" and stage==3:
				var soup_preparation:=line(app,body,MiluTasting.preparation(""),15)
				soup_preparation.name="MiluTastingPreparation"
			if entry.get("layout",false):
				var bed:=GridContainer.new()
				bed.name="BondGoalBed"
				bed.columns=2
				bed.add_theme_constant_override("h_separation",8)
				bed.add_theme_constant_override("v_separation",8)
				body.add_child(bed)
				for index in Goals.BED_CELLS:
					var cell_button:Button=app.button("？",toggle_bed_cell.bind(app,index))
					cell_button.tooltip_text="%s・點一下換花"%["左上","右上","左下","右下"][index]
					cell_button.name="BondGoalBedCell_%d"%index
					cell_button.add_theme_font_size_override("font_size",15)
					cell_button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
					cell_button.disabled=true
					bed.add_child(cell_button)
		if shop_sign:
			var name_input:=xiaoli_name_input(body)
			name_input.text_changed.connect(func(value:String):
				var draft:=goal_page(app)
				draft.error="" if World.XIAOLI_SHOP.valid_name(value.strip_edges()) else World.XIAOLI_SHOP.BAD_NAME
				if not value.strip_edges().is_empty() and str(draft.option).is_empty():draft.option="none"
				refresh_goal_page(app,true))
		if id=="luoluo" and stage==4:luoluo_future_input(app,body)
		if entry.has("steps"):
			var knot_goal:=id=="achao" and stage==1
			var bench_goal:=id=="aru" and stage==2
			if bench_goal:
				app.modal.set_meta("fit_goal_illustration",true)
				body.add_theme_constant_override("separation",6)
				var bench:Control=AruBenchInspection.make(app,app.sound.reduced_motion,func(index:int):pick_goal_step(app,index))
				body.add_child(bench)
				var bench_note:=line(app,body,AruBenchInspection.progress_text([]),14)
				bench_note.name="AruBenchFinding"
			elif id=="chacha" and stage==2:
				app.modal.set_meta("fit_goal_illustration",true)
				body.add_theme_constant_override("separation",8)
				var curtains:Control=ChachaCurtainInspection.make(app.sound.reduced_motion)
				curtains.name="ChachaCurtainInspection"
				body.add_child(curtains)
				var finding:=line(app,body,"點一幅遮簾看看。",14)
				finding.name="ChachaCurtainFinding"
			elif knot_goal:
				app.modal.set_meta("fit_knot_exercise",true)
				body.add_theme_constant_override("separation",8)
				var knots:Control=AchaoKnotArt.make(app.sound.reduced_motion)
				knots.name="AchaoKnotArt"
				body.add_child(knots)
			elif id==World.PAVILION.RESIDENT and stage==World.PAVILION.STAGE:
				line(app,body,"依你想聊的順序選三個話題。",14)
			elif bell_order:
				bell_order_guide(app,body,entry)
			else:
				line(app,body,"做完一步就按一下；按錯了可以按「重來」。",14)
			var steps:Container
			if bench_goal:
				steps=null
			elif knot_goal:
				steps=HBoxContainer.new()
				steps.add_theme_constant_override("separation",8)
			else:
				steps=HFlowContainer.new()
				steps.add_theme_constant_override("h_separation",8)
				steps.add_theme_constant_override("v_separation",8)
			if steps!=null:
				steps.name="BondGoalSteps"
				body.add_child(steps)
				for index in range(entry.steps.size()):
					var step:Button=app.button(str(entry.steps[index]),pick_goal_step.bind(app,index))
					step.name="BondGoalStep_%d"%index
					step.add_theme_font_size_override("font_size",15)
					if knot_goal:step.size_flags_horizontal=Control.SIZE_EXPAND_FILL
					if bell_order:step.custom_minimum_size.x=116
					steps.add_child(step)
			var reset:Button=app.button("重來",reset_goal_steps.bind(app))
			reset.name="BondGoalStepsReset"
			reset.add_theme_font_size_override("font_size",15)
			if knot_goal or bench_goal:actions.add_child(reset)
			else:steps.add_child(reset)
		if entry.has("needs"):
			var needs:=VBoxContainer.new()
			needs.name="BondGoalNeeds"
			needs.add_theme_constant_override("separation",2)
			body.add_child(needs)
		var cost:=HFlowContainer.new()
		cost.name="BondGoalCost"
		cost.add_theme_constant_override("h_separation",16)
		cost.add_theme_constant_override("v_separation",4)
		body.add_child(cost)
		var reason:Label=app.label("",15)
		reason.name="BondGoalReason"
		reason.add_theme_color_override("font_color",GOAL_WARN)
		body.add_child(reason)
		var finish_caption:="敲響風鈴" if bell_ringing else ("招呼米露" if returning_guest else "一起完成")
		if id=="milu" and stage==3:finish_caption="端湯試吃"
		var finish:Button=app.button(finish_caption,do_goal.bind(app))
		finish.name="BondGoalDo"
		actions.add_child(finish)
	else:
		line(app,body,"和%s的關係到「%s」之後，才能一起做這件事。"%[npc_name,Bond.stage_name(stage)],15)
	var back:Button=app.button("回到關係事件",bond_events.bind(app,id,stage-1))
	back.name="BondGoalBack"
	actions.add_child(back)
	body.add_child(actions)
	if state=="open":refresh_goal_page(app,true)
	if shop_sign and state=="done":sync_xiaoli_shop_rewards(app)
	refresh_goal_claim(app)
	focus_goal.call_deferred(app)

## 第三批：本人摘要裡這項行動的紀念小物 {"kind","item","name","claimed"}；沒有時為 {}。
static func goal_keepsake(app,id:String,stage:int) -> Dictionary:
	var found:Variant=goal_state(app,id,stage).get("keepsake")
	return found if found is Dictionary else {}

## 補領鈕（BondGoalClaim）只看站位：要在居民身邊才能按，原因寫在 BondGoalClaimReason。
static func refresh_goal_claim(app) -> void:
	var page:=goal_page(app)
	var claim:=goal_node(app,"BondGoalClaim") as Button
	if page.is_empty() or claim==null:return
	var reason:=goal_away_reason(app,str(page.id))
	if not reason.is_empty():reason=reason.replace("才能一起做。","才能領取。")
	claim.disabled=not reason.is_empty()
	claim.tooltip_text=reason
	var note:=goal_node(app,"BondGoalClaimReason") as Label
	if note!=null:
		note.text=reason
		note.visible=not reason.is_empty()

## 送出補領；頁面留著，下一份快照把這一項標成已領之後由 refresh_bond_goal 重畫。
static func do_goal_claim(app) -> void:
	var page:=goal_page(app)
	if page.is_empty() or str(page.state)!="done" or bool(page.get("claimed",true)):return
	var id:=str(page.id)
	if not goal_away_reason(app,id).is_empty():return
	var cell:Vector2i=World.bond_place(app.session.snapshot,id)[1]
	app.session.perform(Goals.CLAIM_ACTION,cell,"%s:%d"%[id,int(page.stage)])

## 第一個可以操作的控制項：第一個選項 → 第一個步驟 → 一起完成 → 回到關係事件。
static func focus_goal(app) -> void:
	if goal_page(app).is_empty():return
	if goal_node(app,"AchaoKnotArt")!=null:
		var order:Array=Goals.goal("achao",1).order
		var first:=goal_node(app,"BondGoalStep_%d"%order[0]) as Button
		if first!=null and not first.disabled:
			first.grab_focus()
			return
	var cart_first:=goal_node(app,"BoboEmptyCartStart") as Button
	if cart_first!=null and cart_first.is_visible_in_tree() and not cart_first.disabled:
		cart_first.grab_focus()
		return
	for name:String in ["BondGoalOptions","BondGoalSteps"]:
		var holder:=goal_node(app,name)
		if holder==null:continue
		for child in holder.get_children():
			var b:=child as Button
			if b!=null and b.is_visible_in_tree() and not b.disabled:
				b.grab_focus()
				return
	for name:String in ["BondGoalDo","BondGoalClaim","BondGoalBack"]:
		var b:=goal_node(app,name) as Button
		if b!=null and b.is_visible_in_tree() and not b.disabled:
			b.grab_focus()
			return

static func choose_goal_option(app,option_id:String) -> void:
	var page:=goal_page(app)
	if page.is_empty():return
	page.base=option_id
	sync_goal_choice(page)
	refresh_goal_page(app,true)
	if page.id=="luoluo" and int(page.stage)==4 and option_id=="write":
		var field:=goal_node(app,"LuoluoFutureInput") as LineEdit
		if field!=null and field.is_visible_in_tree():field.grab_focus()

## N07-2: the effective choice is "<pair>-<cells>" once the layout holds two of each flower.
static func sync_goal_choice(page:Dictionary) -> void:
	var entry:Dictionary=Goals.goal(str(page.id),int(page.stage))
	var base:=str(page.get("base",""))
	var layout:=str(page.get("layout","0011"))
	page.option=base+"-"+layout if entry.get("layout",false) and not base.is_empty() and Goals.valid_layout(layout) else base

static func toggle_bed_cell(app,index:int) -> void:
	var page:=goal_page(app)
	if page.is_empty() or index<0 or index>=Goals.BED_CELLS:return
	var layout:=str(page.layout)
	page.layout=layout.substr(0,index)+("0" if layout[index]=="1" else "1")+layout.substr(index+1)
	sync_goal_choice(page)
	refresh_goal_page(app,true)

static func pick_goal_step(app,index:int) -> void:
	var page:=goal_page(app)
	if page.is_empty():return
	var picks:Array=page.picks
	var entry:Dictionary=Goals.goal(str(page.id),int(page.stage))
	if index<0 or index>=entry.get("steps",[]).size() or index in picks:return
	page.error=""
	var knots:=str(page.id)=="achao" and int(page.stage)==1
	if knots and index!=entry.order[picks.size()]:
		page.error=GOAL_ORDER_WRONG
		picks.clear()
	else:
		picks.append(index)
	if picks.size()>=Goals.STEP_COUNT and entry.has("order"):
		var order:Array=entry.order
		if picks!=order:
			page.error=GOAL_ORDER_WRONG
			picks.clear()
	refresh_goal_page(app,true)
	var next:Button=null
	if picks.size()<Goals.STEP_COUNT:
		if knots:
			next=goal_node(app,"BondGoalStep_%d"%entry.order[picks.size()]) as Button
		else:
			for i in range(Goals.STEP_COUNT):
				var step:=goal_node(app,"BondGoalStep_%d"%i) as Button
				if step!=null and not step.disabled:
					next=step
					break
	else:
		var finish:=goal_node(app,"BondGoalDo") as Button
		var reset:=goal_node(app,"BondGoalStepsReset") as Button
		next=finish if finish!=null and not finish.disabled else reset
	if next!=null:next.grab_focus()

static func reset_goal_steps(app) -> void:
	var page:=goal_page(app)
	if page.is_empty():return
	var picks:Array=page.picks
	picks.clear()
	page.error=""
	refresh_goal_page(app,true)
	if goal_node(app,"AchaoKnotArt")!=null or goal_node(app,"AruBenchInspection")!=null:focus_goal(app)

## 依目前的選擇、步驟、背包與站位更新選項、步驟、材料列、原因和「一起完成」。
static func refresh_goal_page(app,force:=false) -> void:
	var page:=goal_page(app)
	if page.is_empty() or str(page.state)!="open":return
	var id:=str(page.id)
	var stage:=int(page.stage)
	var entry:Dictionary=Goals.goal(id,stage)
	var choice:=str(page.option)
	var picks:Array=page.picks
	var held:Dictionary=player(app).get("inventory",{})
	var need:Dictionary=Goals.layout_cost(entry,choice,app.session.snapshot)
	var rows:Array=[]
	for item:String in need:rows.append([item,int(held.get(item,0)),int(need[item])])
	var reason:=goal_reason(app,id,stage,choice,picks,str(page.error))
	var need_rows:=goal_needs(app,id,stage)
	var sit:=goal_node(app,"DiandianSit") as Button
	if sit!=null:
		var ready:bool=goal_state(app,id,1).get("state")=="done"
		var seated:bool=player(app).get(Goals.DIANDIAN_SEAT_KEY,false)
		sit.disabled=seated or not ready or not goal_near(app,id)
		sit.text="已在池邊坐下" if seated else "在池邊坐下"
		sit.tooltip_text="先向點點回報三張速寫。" if not ready else ""
	var clear:=goal_node(app,"NuannuanClearEntrance") as Button
	if clear!=null:
		var cleared:=false
		for row:Dictionary in need_rows:
			if row.id=="inn_entrance":cleared=bool(row.met)
		clear.text="✓ 旅舍門口已清理" if cleared else "掃落葉、整理碎石"
		clear.disabled=cleared or not goal_near(app,id)
	var crack_progress:=goal_node(app,"NuannuanCrackProgress") as Label
	if crack_progress!=null:
		var springs:=World.WARM_SPRINGS
		var mask:=int(app.session.snapshot.get("own_inn_cracks",0))
		var spots:PackedStringArray=[]
		for index in springs.CRACK_NAMES.size():spots.append(("✓ " if springs.crack_marked(mask,index) else "○ ")+springs.CRACK_NAMES[index])
		crack_progress.text="　".join(spots)
	var cart_start_reason:=bobo_cart_start_reason(app) if bobo_cart_goal(id,stage) else ""
	var fingerprint:=str([choice,picks,reason,rows,need_rows,cart_start_reason,page.get("layout","")])
	if not force and fingerprint==str(page.fp):return
	page.fp=fingerprint
	var future_input:=goal_node(app,"LuoluoFutureInputPanel") as Control
	if future_input!=null:future_input.visible=choice=="write"
	var cart_start:=goal_node(app,"BoboEmptyCartStart") as Button
	if cart_start!=null:
		var at:int=World.BOBO_EMPTY_CART.stage(app.session.snapshot)
		cart_start.disabled=not cart_start_reason.is_empty()
		cart_start.tooltip_text=cart_start_reason
		cart_start.text="空車已出發" if at>0 and at<World.ORE_ROUTE.LAST else ("空車已抵達" if at>=World.ORE_ROUTE.LAST else "開始推空車")
		var cart_status:=goal_node(app,"BoboEmptyCartStatus") as Label
		if cart_status!=null:
			cart_status.text=("✓ 空車已推到展覽位置，可以選一句話刻字了。" if at>=World.ORE_ROUTE.LAST else (bobo_cart_reason(app)+("" if cart_start_reason.is_empty() or at>0 else "\n"+cart_start_reason)))
			cart_status.add_theme_color_override("font_color",Color("3e664b") if at>=World.ORE_ROUTE.LAST else GOAL_WARN)
	var options:=goal_node(app,"BondGoalOptions")
	if options!=null:
		for child in options.get_children():
			var b:=child as Button
			if b!=null:b.set_pressed_no_signal(str(b.name)=="BondGoalOption_"+str(page.get("base",choice)))
	var preparation:=goal_node(app,"MiluTastingPreparation") as Label
	if preparation!=null:preparation.text=MiluTasting.preparation(choice)
	if id=="xiaoli" and stage==2:show_xiaoli_site(app,choice)
	if id=="xiaoli" and stage==3:
		var visit:=goal_node(app,"XiaoliReturnGuestVisit") as Control
		if visit!=null:visit.visible=need_rows.all(func(row:Dictionary):return row.get("met",false))
	if entry.has("steps"):
		var knots:=goal_node(app,"AchaoKnotArt") as Control
		if knots!=null:knots.call("sync",picks)
		var curtains:=goal_node(app,"ChachaCurtainInspection") as ChachaCurtainInspection
		if curtains!=null:
			curtains.sync(picks)
			var finding:=goal_node(app,"ChachaCurtainFinding") as Label
			var observations:=["靠山這幅的細繩鬆了。","中間缺了一片竹，日光從縫裡落到地板。","靠路這幅的下緣磨毛了。"]
			finding.text="點一幅遮簾看看。" if picks.is_empty() else observations[int(picks.back())]
		var bench:=goal_node(app,"AruBenchInspection") as AruBenchInspection
		if bench!=null:
			bench.sync(picks)
			var bench_note:=goal_node(app,"AruBenchFinding") as Label
			if bench_note!=null:bench_note.text=AruBenchInspection.progress_text(picks)
		for i in range(entry.steps.size()):
			if bench!=null:break
			var bell_slot:=goal_node(app,"LingpopoBellSlot_%d"%i) as Label
			if bell_slot!=null:bell_slot.text="✓ 已放入" if i<picks.size() and picks[i]==entry.order[i] else "尚未放入"
			var step:=goal_node(app,"BondGoalStep_%d"%i) as Button
			if step==null:continue
			var at:=picks.find(i)
			step.text=("%d. "%(at+1) if at>=0 else "")+str(entry.steps[i])
			step.disabled=at>=0
	var bed:=goal_node(app,"BondGoalBed") as GridContainer
	if bed!=null:
		var pair:Array=Goals.option(entry,str(page.get("base",""))).get("items",{}).keys()
		var cells:=str(page.get("layout","0011"))
		for index in Goals.BED_CELLS:
			var cell_button:=goal_node(app,"BondGoalBedCell_%d"%index) as Button
			if cell_button==null:continue
			cell_button.disabled=pair.size()<2
			if pair.size()<2:
				cell_button.text="？"
				cell_button.icon=null
				continue
			var flower:String=str(pair[int(cells[index])])
			cell_button.icon=ItemArt.icon(flower)
			cell_button.text=str(World.NAMES.get(flower,flower))+("" if Goals.flower_in_season(flower,app.session.snapshot) else "・教學苗")
	var needs:=goal_node(app,"BondGoalNeeds") as VBoxContainer
	if needs!=null:
		for child in needs.get_children():
			needs.remove_child(child)
			child.queue_free()
		for need_row:Dictionary in need_rows:
			var met:=bool(need_row.get("met",false))
			var need_line:Label=app.label(("✓ " if met else "○ ")+"要先：%s"%str(need_row.get("label","")),15)
			need_line.name="BondGoalNeed_"+str(need_row.id)
			need_line.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
			if not met:need_line.add_theme_color_override("font_color",GOAL_WARN)
			needs.add_child(need_line)
		needs.visible=not need_rows.is_empty()
	var cost:=goal_node(app,"BondGoalCost") as HFlowContainer
	if cost!=null:
		for child in cost.get_children():
			cost.remove_child(child)
			child.queue_free()
		for row:Array in rows:
			var item:=str(row[0])
			var have:=int(row[1])
			var want:=int(row[2])
			var holder:=HBoxContainer.new()
			holder.name="BondGoalCost_"+item
			holder.add_theme_constant_override("separation",6)
			cost.add_child(holder)
			add_icon(holder,ItemArt.icon(item),24)
			var amount:Label=app.label("%s %d／%d"%[str(World.NAMES.get(item,item)),have,want],15)
			amount.autowrap_mode=TextServer.AUTOWRAP_OFF
			amount.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
			amount.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
			if have<want:amount.add_theme_color_override("font_color",GOAL_WARN)
			holder.add_child(amount)
		cost.visible=not rows.is_empty()
	var note:=goal_node(app,"BondGoalReason") as Label
	if note!=null:
		var knot_goal:=id=="achao" and stage==1
		var bell_order:=id=="lingpopo" and stage==2
		var show_progress:=(knot_goal or bell_order) and reason==GOAL_NEED_STEPS
		note.text=reason
		if show_progress:
			var format:="已鬆開 %d／%d 段" if knot_goal else "已排好 %d／%d 枚鈴"
			note.text=format%[picks.size(),Goals.STEP_COUNT]
		if knot_goal or bell_order:
			note.add_theme_color_override("font_color",Color("3e664b") if show_progress else GOAL_WARN)
		note.visible=not reason.is_empty()
	var finish:=goal_node(app,"BondGoalDo") as Button
	if finish!=null:
		finish.disabled=not reason.is_empty()
		finish.tooltip_text=reason

static func show_xiaoli_site(app,choice:String) -> void:
	var chart:=goal_node(app,"XiaoliSiteChart") as XiaoliSiteChart
	var hint:=goal_node(app,"XiaoliSiteHint") as Label
	if chart==null or hint==null:return
	chart.select_site(choice)
	var site:Dictionary=Goals.XIAOLI_CART_SITES.get(choice,{})
	hint.text="選一處，看看附近有哪些地標。" if site.is_empty() else "%s · %s"%[site.name,site.hint]

static func play_xiaoli_visit(app) -> void:
	var illustration:=goal_node(app,"XiaoliReturnGuestArt") as XiaoliReturnGuest
	if illustration!=null:illustration.play()

static func xiaoli_name_input(parent:Container) -> LineEdit:
	var field:=LineEdit.new()
	field.name="XiaoliShopNameInput"
	field.placeholder_text="輸入店名（可留空）"
	field.max_length=World.XIAOLI_SHOP.MAX_NAME
	parent.add_child(field)
	return field

static func xiaoli_shop_rewards(app,body:VBoxContainer,actions:Container) -> void:
	var summary:=card(body)
	var row:=HBoxContainer.new()
	row.add_theme_constant_override("separation",10)
	summary.add_child(row)
	add_icon(row,XiaoliShopArt.scale_texture(),38)
	var sign:=line(app,row,"",17)
	sign.name="XiaoliShopSignTitle"
	sign.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	var scale:Button=app.button("領取紀念秤",xiaoli_shop_action.bind(app,World.XIAOLI_SHOP.SCALE_ACTION,""))
	scale.name="XiaoliCollectScale"
	row.add_child(scale)
	var rename:Button=app.button("修改店名",xiaoli_rename_page.bind(app))
	rename.name="XiaoliRenameShop"
	actions.add_child(rename)
	var photo:Button=app.button("拍店門合照",xiaoli_take_photo.bind(app))
	photo.name="XiaoliTakeShopPhoto"
	actions.add_child(photo)
	if FileAccess.file_exists(xiaoli_photo_path(app)):
		var album:Button=app.button("看店門照片",xiaoli_view_photo.bind(app))
		album.name="XiaoliViewShopPhoto"
		actions.add_child(album)

static func sync_xiaoli_shop_rewards(app) -> void:
	var sign:=goal_node(app,"XiaoliShopSignTitle") as Label
	if sign==null:return
	var details:Dictionary=app.session.snapshot.get("own_xiaoli_shop",{})
	var near:=goal_near(app,"xiaoli")
	sign.text="店門招牌 · "+str(details.get("name",World.XIAOLI_SHOP.DEFAULT_NAME))
	var scale:=goal_node(app,"XiaoliCollectScale") as Button
	var claimed:=bool(details.get("scale",false))
	scale.disabled=claimed or not near
	scale.text="紀念秤已領取" if claimed else "領取紀念秤"
	for name in ["XiaoliRenameShop","XiaoliTakeShopPhoto"]:
		var action:=goal_node(app,name) as Button
		if action==null:continue
		action.disabled=not near
		action.tooltip_text="請到小栗的渡口小店。" if not near else ""

static func xiaoli_shop_action(app,action:String,value:String) -> void:
	var cell:Vector2i=World.bond_place(app.session.snapshot,"xiaoli")[1]
	app.session.perform(action,cell,value)

static func xiaoli_rename_page(app) -> void:
	if not goal_near(app,"xiaoli"):return
	var body:VBoxContainer=app._open_modal("修改店門招牌")
	app.modal.set_meta("life_modal_layout","keepsake_paper")
	line(app,body,"最多 12 字。留空時使用「渡口小店」。",15)
	var input:=xiaoli_name_input(body)
	input.text=str(app.session.snapshot.get("own_xiaoli_shop",{}).get("input",""))
	var submit:Button=app.button("掛上招牌",func():
		xiaoli_shop_action(app,World.XIAOLI_SHOP.SIGN_ACTION,input.text.strip_edges())
		bond_goal(app,"xiaoli",4))
	submit.name="XiaoliRenameConfirm"
	input.text_changed.connect(func(value:String):submit.disabled=not World.XIAOLI_SHOP.valid_name(value.strip_edges()))
	body.add_child(submit)
	body.add_child(app.button("回到關係事件",bond_goal.bind(app,"xiaoli",4)))
	input.grab_focus()

static func xiaoli_photo_path(app) -> String:
	return "user://xiaoli-shop-%s.png"%str(app.session.own_id).sha256_text().left(24)

static func xiaoli_take_photo(app) -> void:
	if not goal_near(app,"xiaoli"):return
	app._close_modal()
	if await capture_island_photo(app,xiaoli_photo_path(app),0.72):xiaoli_view_photo(app)
	else:app._notice("照片無法儲存，請再試一次。",false)

static func xiaoli_view_photo(app) -> void:
	var image:=Image.load_from_file(xiaoli_photo_path(app))
	if image==null or image.is_empty():return
	var body:VBoxContainer=app._open_modal("小栗的店門合照")
	app.modal.set_meta("life_modal_layout","lingpopo_history")
	var photo:=TextureRect.new()
	photo.name="XiaoliShopPhoto"
	photo.texture=ImageTexture.create_from_image(image)
	photo.custom_minimum_size.y=214
	photo.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	photo.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	body.add_child(photo)
	var back:Button=app.button("回到關係事件",bond_goal.bind(app,"xiaoli",4))
	back.name="XiaoliPhotoBack"
	body.add_child(back)

static func xiaoli_market_reward(app) -> void:
	if goal_state(app,"xiaoli",3).get("state")!="done":return
	var body:VBoxContainer=app._open_modal("小栗的栗果攤位")
	app.modal.set_meta("life_modal_layout","keepsake_paper")
	var spread:=HBoxContainer.new()
	spread.add_theme_constant_override("separation",16)
	body.add_child(spread)
	spread.add_child(MarketDecorArt.preview(World.MARKET_DECOR.REWARD_STYLE))
	var notes:=card(spread)
	(notes.get_parent() as Control).size_flags_horizontal=Control.SIZE_EXPAND_FILL
	line(app,notes,"栗棕攤布與栗果招牌",18)
	line(app,notes,"到廣場的市集攤位，打開「攤位布置」就能換上。兩款都可以和你原有的布置搭配。",15)
	var back:Button=app.button("回到關係事件",bond_goal.bind(app,"xiaoli",3))
	back.name="XiaoliMarketRewardBack"
	body.add_child(back)

static func ring_story_bell(app,replay:bool) -> void:
	var scene:=goal_node(app,"LingpopoBellScene") as LingpopoBellScene
	if scene==null:return
	scene.ring()
	if replay:app.sound.defer_action("memorial_bell")

static func do_goal(app) -> void:
	var page:=goal_page(app)
	if page.is_empty() or str(page.state)!="open":return
	var id:=str(page.id)
	var stage:=int(page.stage)
	if int(page.get("story_submission",0))>0:return
	var picks:Array=page.picks
	if not goal_reason(app,id,stage,str(page.option),picks,str(page.error)).is_empty():return
	var digits:=""
	for index in picks:digits+=str(index)
	if id=="xiaoli" and stage==4:
		var input:=goal_node(app,"XiaoliShopNameInput") as LineEdit
		if input!=null:digits=input.text.strip_edges()
		if not World.XIAOLI_SHOP.valid_name(digits):return
	if id=="luoluo" and stage==4 and str(page.option)=="write":
		digits=World.ISLAND_NOTES.clean((goal_node(app,"LuoluoFutureInput") as LineEdit).text)
	var cell:Vector2i=World.bond_place(app.session.snapshot,id)[1]
	if (id=="bobo" and stage==1) or (id=="diandian" and stage in [1,2,3]) or (id==World.PAVILION.RESIDENT and stage==World.PAVILION.STAGE) or (id=="xinghe" and stage==4) or (id=="lingpopo" and stage in [3,4]) or id=="xiaoli" or (id=="luoluo" and stage in [1,3,4]) or (id=="nuannuan" and stage==3) or (id=="milu" and stage in [3,4]):
		var sequence:int=app.session.counter+1
		page["story_submission"]=sequence
		var submit:=goal_node(app,"BondGoalDo") as Button
		if submit:submit.disabled=true
		app.get_tree().create_timer(5.0).timeout.connect(retry_story_hand_in.bind(app,sequence))
		app.session.perform(Goals.ACTION,cell,"%s:%d:%s:%s"%[id,stage,str(page.option),digits])
		return
	# 送出後頁面就要關閉；這期間到達的快照不必重畫本頁。
	page["sending"]=true
	app.session.perform(Goals.ACTION,cell,"%s:%d:%s:%s"%[id,stage,str(page.option),digits])
	app._close_modal()

static func retry_story_hand_in(app,sequence:int) -> void:
	if not is_instance_valid(app):return
	var page:=goal_page(app)
	if int(page.get("story_submission",0))!=sequence:return
	page.erase("story_submission")
	refresh_goal_page(app,true)

static func inspect_tea_pavilion(app,result:Dictionary) -> void:
	if not result.get("ok",false) or result.get("region")!=app.view.region_id():return
	if is_instance_valid(app.modal) or not ChachaTeaGathering.available(app.session.snapshot):return
	ChachaTeaGathering.open(app,app._close_modal,"回到島上")

## 每份新快照（main 透過 refresh_island_notes 呼叫）：行動狀態變了就重畫整頁，
## 否則只更新材料、站位原因與「一起完成」，保留已選的做法與步驟。
static func refresh_bond_goal(app) -> void:
	var page:=goal_page(app)
	if page.is_empty() or bool(page.get("sending",false)):return
	var id:=str(page.id)
	var stage:=int(page.stage)
	if int(page.get("story_submission",0))>0:
		if id=="bobo" and BoboRockGuide.available(app.session.snapshot):
			BoboRockGuide.open(app,bond_goal.bind(app,id,stage),true)
		elif id==World.PAVILION.RESIDENT and ChachaTeaGathering.available(app.session.snapshot):
			ChachaTeaGathering.open(app,bond_goal.bind(app,id,stage))
		elif id=="diandian" and stage==3 and goal_state(app,id,stage).get("state")=="done":
			painting_book(app,bond_goal.bind(app,id,stage))
		elif id=="milu" and stage==3 and not MiluTasting.completed_dish(app.session.snapshot).is_empty():
			MiluTasting.open(app,bond_goal.bind(app,id,stage),"返回關係事件")
			app.sound.defer_action("meal_serve")
		elif id=="milu" and stage==4 and MiluSupper.done(app.session.snapshot):
			MiluSupper.open_book(app,bond_goal.bind(app,id,stage),"返回關係事件")
			app.sound.defer_action("meal_serve")
		elif ((id=="diandian" and stage in [1,2]) or (id=="xinghe" and stage==4) or (id=="lingpopo" and stage in [3,4]) or id=="xiaoli" or (id=="luoluo" and stage in [1,3,4]) or (id=="nuannuan" and stage==3)) and goal_state(app,id,stage).get("state")=="done":
			bond_goal(app,id,stage)
			if id=="lingpopo" and stage==4:ring_story_bell(app,false)
			if id=="xiaoli" and stage==3:play_xiaoli_visit(app)
		return
	if str(goal_state(app,id,stage).get("state","locked"))!=str(page.state):
		bond_goal(app,id,stage)
		return
	if page.has("claimed") and bool(page.claimed)!=bool(goal_keepsake(app,id,stage).get("claimed",false)):
		bond_goal(app,id,stage)
		return
	if page.has("guest_cloth_claimed") and bool(page.guest_cloth_claimed)!=bool(app.session.snapshot.get("own_guest_cloth",false)):
		bond_goal(app,id,stage)
		return
	refresh_goal_page(app)
	refresh_goal_claim(app)
	if id=="xiaoli" and stage==4:sync_xiaoli_shop_rewards(app)

static func portrait_header(app,parent:VBoxContainer,id:String,greeting:String,pixels:int) -> void:
	var row:=HBoxContainer.new()
	row.add_theme_constant_override("separation",12)
	parent.add_child(row)
	add_icon(row,Art.icon(id),pixels)
	var description:=VBoxContainer.new()
	description.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	row.add_child(description)
	line(app,description,Village.NPCS[id].name,22)
	if not greeting.is_empty():line(app,description,"「"+greeting+"」",16)

static func add_icon(parent:Container,texture:Texture2D,pixels:int) -> void:
	var icon:=TextureRect.new()
	icon.texture=texture
	icon.custom_minimum_size=Vector2(pixels,pixels)
	icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	parent.add_child(icon)

static func material_progress(app,parent:VBoxContainer,id:String,value:int,goal:int) -> HBoxContainer:
	var row:=HBoxContainer.new()
	row.add_theme_constant_override("separation",10)
	parent.add_child(row)
	add_icon(row,ItemArt.icon(id),32)
	var details:=VBoxContainer.new()
	details.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	row.add_child(details)
	progress(app,details,World.NAMES[id],value,goal)
	return row

static func progress(app,parent:VBoxContainer,title:String,value:int,goal:int) -> void:
	var caption:=line(app,parent,"%s  %d / %d"%[title,value,goal],16)
	caption.name="ProgressCaption"
	var meter:=ProgressBar.new()
	meter.name="ProgressMeter"
	meter.max_value=goal
	meter.value=value
	meter.show_percentage=false
	meter.custom_minimum_size.y=10
	meter.mouse_filter=Control.MOUSE_FILTER_IGNORE
	parent.add_child(meter)

static func quest_details(app,parent:VBoxContainer,quest:Dictionary,person:Dictionary) -> void:
	line(app,parent,quest.title,20)
	line(app,parent,quest.goal,16)
	var inventory:Dictionary=person.get("inventory",{})
	var materials:=HFlowContainer.new()
	materials.add_theme_constant_override("separation",16)
	parent.add_child(materials)
	for item in quest.items:
		var material:=HBoxContainer.new()
		materials.add_child(material)
		add_icon(material,ItemArt.icon(item),24)
		var amount:Label=app.label("%s  %d / %d"%[World.NAMES[item],int(inventory.get(item,0)),int(quest.items[item])],15)
		amount.autowrap_mode=TextServer.AUTOWRAP_OFF
		amount.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		amount.add_to_group("quest_material_text")
		material.add_child(amount)
	if quest.has("counter"):
		line(app,parent,"完成次數  %d / %d"%[int(person.get(quest.counter,0)),int(quest.target)],16)
	var rewards:=PackedStringArray(["%d 鈴幣"%quest.coins])
	for item in quest.reward:
		rewards.append("%s ×%d"%[World.NAMES[item],int(quest.reward[item])])
	if quest.has("unlock"):rewards.append(World.BUILD[quest.unlock].name+"圖樣")
	line(app,parent,"獎勵  "+"、".join(rewards),15)
