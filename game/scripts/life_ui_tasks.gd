extends RefCounted

const World=preload("res://scripts/world.gd")
const Village=World.Village
const Art=preload("res://scripts/life_ui_theme.gd")
const ItemArt=preload("res://scripts/inventory_item_art.gd")
const PixelTheme=preload("res://scripts/inventory_pixel_theme.gd")
const KitchenUI=preload("res://scripts/public_kitchen_ui.gd")
const ResidentStories=preload("res://scripts/resident_story_catalog.gd")
const Bond=World.RESIDENT_BOND
const Goals=World.RESIDENT_GOALS
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
	if goal_state(app,"chacha",4).get("state")=="done":
		bookmarks.add_child(app.button("茶茶手寫茶單",chacha_menu.bind(app)))
	if app.session.snapshot.has(Goals.MURAL_KEY):
		bookmarks.add_child(app.button("全島合畫",public_mural.bind(app)))
	if goal_state(app,"diandian",3).get("state")=="done":
		bookmarks.add_child(app.button("點點的第一幅合畫",painting_book.bind(app)))
	if goal_state(app,"xinghe",1).get("state")=="done":
		bookmarks.add_child(app.button("星禾的作物觀察簿",growth_book.bind(app)))
	if int(app.session.snapshot.get("own_luoluo_address",0))>0:
		bookmarks.add_child(app.button("洛洛的信封",address_letter.bind(app)))
	add_bell_history_bookmark(app,bookmarks)
	var news:Button=app.button("島嶼近況",island_news.bind(app))
	news.name="IslandNews"
	bookmarks.add_child(news)
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
	if recap.get("has_news",false):line(app,paper,"渡口有新消息，可在島嶼近況補看。",16)
	var links:=HBoxContainer.new()
	links.add_theme_constant_override("separation",10)
	body.add_child(links)
	links.add_child(app.button("島嶼近況",island_news.bind(app)))
	if notes>0:links.add_child(app.button("讀留言",island_notes.bind(app)))
	var memories:Array=snapshot.get("resident_memories",[])
	if not memories.is_empty() or snapshot.get("festival_story",{}).get("opened",false):
		links.add_child(app.button("重看故事",resident_memories.bind(app)))
	app._layout_preview.call_deferred()

static func island_news(app) -> void:
	var body:VBoxContainer=app._open_modal("島嶼近況")
	app.modal.set_meta("life_modal_layout","community_board")
	var snapshot:Dictionary=app.session.snapshot
	var projects:=card(body)
	line(app,projects,"公共工程",20)
	var news:Dictionary=snapshot.get("island_news",{})
	var names:=World.ISLAND_NOTES.PROJECTS
	var completed:=int(news.get("completed",0))
	var unread:=unread_projects(news)
	for index in names.size():
		var bit:=1<<index
		var status:="未完成" if (completed & bit)==0 else ("新完成" if (unread & bit)!=0 else "已完成")
		line(app,projects,"%s · %s"%[names[index],status],16)
	if unread!=0:
		projects.add_child(app.button("標為已讀",func():
			app.session.perform("news_read",Vector2i.ZERO,str(completed))
			app._close_modal()
		))
	var local_entry:VBoxContainer
	for index in World.ISLAND_NOTES.LOCAL_PROJECTS.size():
		var bit:=1<<(names.size()+index)
		if (completed & bit)==0:continue
		if local_entry==null:
			local_entry=card(body)
			local_entry.name="LocalProjectNews"
			line(app,local_entry,"地方工程",20)
		var details:Array=World.ISLAND_NOTES.LOCAL_PROJECTS[index]
		line(app,local_entry,("新完成 · " if (unread & bit)!=0 else "")+str(details[0]),17)
		line(app,local_entry,str(details[1]),15)
	if snapshot.get("picnic",false):
		var travel:=card(body)
		line(app,travel,"渡口近況",20)
		var recap:Dictionary=snapshot.get("ferry_story_recap",World.ISLAND_STORY_RECAP.build(snapshot))
		for entry:Dictionary in recap.entries:
			if entry.id=="festival_replay":continue
			line(app,travel,("新消息・" if entry.new else "")+str(entry.title),17)
			line(app,travel,str(entry.body),15)
		line(app,travel,str(recap.next_step),15)
		if recap.has_news:
			travel.add_child(app.button("渡口近況標為已讀",func():
				app.session.perform("ferry_news_read",Vector2i.ZERO,str(recap.marker))
				app._close_modal()
			))
		travel.add_child(app.button("查看群島來信",dock_project.bind(app,true)))
	var crops:=card(body)
	var counts:Dictionary=snapshot.get("own_crop_summary",{})
	line(app,crops,"我的農田",20)
	line(app,crops,"可收成 %d 格 · 生長中 %d 格，其中 %d 格目前未澆水"%[counts.get("ready",0),counts.get("growing",0),counts.get("dry",0)],16)
	# T071 手帳市集摘要：渡口野餐後列出本人攤位的今日主題、營業狀態、待領營收與上一輪結算
	# （只讀 snapshot.own_market；開著時依快照就地更新）。
	if not market_news_lines(app).is_empty():
		var market:=card(body)
		market.name="MarketNews"
		refresh_market_news(app)
	var stories:=card(body)
	line(app,stories,"可重看的故事",20)
	var memories:Array=snapshot.get("resident_memories",[])
	var replay:Button=app.button("居民回憶 · %d 段"%memories.size(),resident_memories.bind(app))
	stories.add_child(replay)
	if snapshot.get("festival_story",{}).get("opened",false):
		stories.add_child(app.button("重看風鈴節開幕",app._festival_memory))
	# 第 40 章：風鈴節開幕後，一行地方記憶展近況（按下開展覽頁；開著時依快照就地更新）。
	var exhibit_line:String=preload("res://scripts/memory_exhibit_ui.gd").news_line(snapshot)
	if not exhibit_line.is_empty():
		var exhibit:Button=app.button(exhibit_line,func():preload("res://scripts/memory_exhibit_ui.gd").open(app))
		exhibit.name="MemoryExhibitNews"
		stories.add_child(exhibit)
	var unread_notes:=int(news.get("notes_unread",0))
	var note_label:="島民留言 · %d 則未讀"%unread_notes if unread_notes>0 else "島民留言 · %d 則"%snapshot.get("island_notes",[]).size()
	body.add_child(app.button(note_label,island_notes.bind(app)))
	body.add_child(app.button("返回島民手帳",journal.bind(app)))

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

static func island_notes(app) -> void:
	var body:VBoxContainer=app._open_modal("島民留言")
	app.modal.set_meta("life_modal_layout","community_board")
	body.add_child(app.button("返回島嶼近況",island_news.bind(app)))
	var field:=LineEdit.new()
	field.name="IslandNoteDraft"
	field.max_length=World.ISLAND_NOTES.LENGTH
	field.placeholder_text="留下訊息，島上的朋友回來就能看到"
	body.add_child(field)
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
	refresh_market_news(app)
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

static func resident_memories(app) -> void:
	var body:VBoxContainer=app._open_modal("居民回憶")
	app.modal.set_meta("life_modal_layout","community_board")
	var unlocked:Array=app.session.snapshot.get("resident_memories",[])
	body.add_child(app.button("返回島民手帳",journal.bind(app)))
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
	var has_tool:=int(own.get("inventory",{}).get("reinforced_pick",0))>0
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
	body.add_child(app.button("返回島民手冊",app._journal))

static func board(app) -> void:
	var col:VBoxContainer=app._open_modal("渡口的共同工程")
	app.modal.set_meta("life_modal_layout","community_board")
	var s:Dictionary=app.session.snapshot
	var project:=card(col)
	col.add_child(app.button("看看圖鑑收藏展示",app._collection_gallery))
	var donations:Dictionary=s.get("donations",{})
	line(app,project,"渡口修繕",22)
	line(app,project,"河灣橋已開通。" if s.get("board",false) else "一起捐木材和石材，讓河灣橋重新開通。",16)
	if not s.get("board",false):
		material_progress(app,project,"wood",int(donations.get("wood",0)),30).name="BridgeWood"
		material_progress(app,project,"stone",int(donations.get("stone",0)),10).name="BridgeStone"
		var donate:Button=app.button("捐入背包裡需要的材料",func():app.session.perform("donate",BOARD_CELL);app._close_modal())
		donate.name="BoardDonateBridge"
		project.add_child(donate)
		line(app,project,"只捐工程尚缺的數量。",15)
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
			var serve:Button=app.button("把料理放到野餐桌上",func():app.session.perform("picnic",BOARD_CELL);app._close_modal())
			serve.name="BoardServePicnic"
			serve.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			picnic_row.add_child(serve)
			var souvenir_locked:Button=app.button(preload("res://scripts/souvenir_exchange_ui.gd").ENTRY_LOCKED,app._souvenir_menu)
			souvenir_locked.name="SouvenirEntry"
			souvenir_locked.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			picnic_row.add_child(souvenir_locked)
		var orders:Button=app.button("生活訂單  ·  每個世界日更新",app._orders_menu)
		if s.get("picnic",false):
			col.add_child(orders)
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
			orders.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			row.add_child(orders)
			var locked:Button=app.button("河岸釣魚會・渡口野餐後開放",app._fishmeet_menu)
			locked.name="FishingMeetEntry"
			locked.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			row.add_child(locked)
			var showcase:Button=app.button("家園布置題・渡口野餐後開放",app._showcase_menu)
			showcase.name="ShowcaseEntry"
			showcase.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			row.add_child(showcase)
	add_fund_controls(app,col,s)
	if s.get("picnic",false):col.add_child(app.button("群島的來信",dock_project.bind(app)))
	refresh_board_projects(app,s)

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
		var needs_wood:=int(donations.get("wood",0))<30 and int(bag.get("wood",0))>0
		var needs_stone:=int(donations.get("stone",0))<10 and int(bag.get("stone",0))>0
		update_project_meter(app.modal,"BridgeWood","wood",int(donations.get("wood",0)),30)
		update_project_meter(app.modal,"BridgeStone","stone",int(donations.get("stone",0)),10)
		var opened:bool=s.get("board",false)
		donate.disabled=opened or not (needs_wood or needs_stone)
		if opened and not donate.has_meta("reopening"):
			donate.set_meta("reopening",true)
			# A local donation closes the board through its normal button handler.
			var board_panel:Control=app.modal
			var reopen:=func():
				if is_instance_valid(board_panel) and app.modal==board_panel:board(app)
			reopen.call_deferred()
	refresh_board_picnic(app,s)

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
	serve.disabled=not World.CHAPTER_ONE.can_serve_picnic(s,app.session.own_id)
	if complete:
		serve.text="野餐料理已上桌"
		for entry in [["SouvenirEntry",preload("res://scripts/souvenir_exchange_ui.gd").entry_caption(true)],
			["FishingMeetEntry","河岸釣魚會（河灣橋南岸）"],["ShowcaseEntry","家園布置題（渡口西南草地）"]]:
			var button:=app.modal.find_child(entry[0],true,false) as Button
			if button:button.text=entry[1]
	elif serve.disabled:serve.text="先到小石灶準備料理"
	else:serve.text="把料理放到野餐桌上"

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
	if id=="aru" and (int(bond.get("stage",0))>=3 or app.session.snapshot.get("aru_bench_open",false)):
		var sit:Button=app.button("坐到阿榆身旁",aru_rest.bind(app,cell))
		sit.name="AruRest"
		actions.add_child(sit)

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
	var path:=aru_photo_path(app)
	if FileAccess.file_exists(path):
		var image:=Image.load_from_file(path)
		if image!=null and not image.is_empty():
			var photo_frame:=TextureRect.new()
			photo_frame.name="AruAlbumPhoto"
			photo_frame.texture=ImageTexture.create_from_image(image)
			photo_frame.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
			photo_frame.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			photo_frame.custom_minimum_size.y=120
			body.add_child(photo_frame)

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

static func aru_take_photo(app) -> void:
	app._close_modal()
	if not await capture_island_photo(app,aru_photo_path(app)):
		app._notice("照片無法儲存，請再試一次。",false)
		return
	app.session.perform(Goals.ARU_PARK_PHOTO,Goals.ARU_PARK_VIEW)
	app._notice("相片已留在公共長椅的相簿，可以回來翻看。",true)

static func aru_rest(app,cell:Vector2i) -> void:
	app.session.perform(Goals.ARU_REST_ACTION,cell)
	var page:VBoxContainer=app._open_modal("長椅上的片刻")
	app.modal.set_meta("life_modal_layout","keepsake_paper")
	var paper:=card(page)
	var bench:=AtlasTexture.new()
	bench.atlas=preload("res://assets/village-preview/props.png")
	bench.region=Rect2(192,128,64,64)
	var scene:=Control.new()
	scene.custom_minimum_size.y=110
	scene.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	paper.add_child(scene)
	var bench_art:=TextureRect.new()
	bench_art.texture=bench
	scene.add_child(bench_art)
	bench_art.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	bench_art.scale=Vector2(2,2)
	bench_art.position+=Vector2(-32,-5)
	for seat:Vector2i in [Vector2i(3,-15),Vector2i(0,15)]:
		var frame:=AtlasTexture.new()
		frame.atlas=preload("res://assets/life-art/characters.png")
		frame.region=Rect2(seat.x*48+10,4,28,35)
		var sitter:=TextureRect.new()
		sitter.texture=frame
		scene.add_child(sitter)
		sitter.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		sitter.scale=Vector2(2,2)
		sitter.position+=Vector2(seat.y*2-14,-7)
	line(app,paper,"阿榆把手裡的砂紙放下，往長椅的一邊挪了挪。",18)
	line(app,paper,"「你說不必磨掉？那這道痕就是我們今天留下的。」",18)
	line(app,paper,"附近的朋友可以自己找阿榆坐下。",15)
	var rise:Button=app.button("起身",func():app._close_modal())
	rise.name="AruRise"
	page.add_child(rise)

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
	var page:VBoxContainer=app._open_modal("暖暖的迎賓牌")
	var is_owner:bool=obj.get("owner")==app.session.own_id
	app.modal.set_meta("life_modal_layout","welcome_sign_edit" if is_owner else "welcome_sign_read")
	var copy:Array=obj.get("welcome",["","",""])
	var paper:=card(page)
	var heading:Label=app.label("",24)
	heading.name="WelcomeInnName"
	heading.text=copy[0] if not copy[0].is_empty() else "暖泉旅舍"
	paper.add_child(heading)
	for i in [1,2]:
		if copy[i].is_empty():continue
		var message:Label=app.label("",18)
		message.name="WelcomeInnLine%d"%i
		message.text=copy[i]
		paper.add_child(message)
	if not is_owner:return
	var fields:Array[LineEdit]=[]
	for i in World.WELCOME_SIGN.LIMITS.size():
		var captions:=["旅舍名稱","歡迎語第一行","歡迎語第二行"]
		line(app,page,"%s（%d 字內）"%[captions[i],World.WELCOME_SIGN.LIMITS[i]],15)
		var field:=LineEdit.new()
		field.name="WelcomeSignField%d"%i
		field.max_length=World.WELCOME_SIGN.LIMITS[i]
		field.text=copy[i]
		page.add_child(field)
		fields.append(field)
	var save:Button=app.button("儲存迎賓牌",func():
		var lines:=fields.map(func(field:LineEdit):return field.text.strip_edges())
		app.session.perform(World.WELCOME_SIGN.WRITE,cell,JSON.stringify(lines))
		app._close_modal())
	save.name="WelcomeSignSave"
	page.add_child(save)

static func aru_inscription(app,cell:Vector2i,obj:Dictionary) -> void:
	var page:VBoxContainer=app._open_modal(World.BUILD[obj.type].name)
	app.modal.set_meta("life_modal_layout","keepsake_paper")
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
		if goal_state(app,id,4).get("state")=="done":
			var menu:Button=app.button("翻看手寫茶單",chacha_menu.bind(app))
			menu.name="ChachaMenu"
			actions.add_child(menu)
		elif int(bond.get("stage",0))>=4:
			var reserve:Button=app.button("留一張椅子給來客",tea_guest_seat.bind(app))
			reserve.name="ChachaGuestSeat"
			actions.add_child(reserve)
	if id=="diandian" and int(bond.get("stage",0))>=3:
		var painting:Button=app.button("翻看第一幅合畫" if goal_state(app,id,3).get("state")=="done" else "翻開合畫草稿",painting_book.bind(app))
		painting.name="DiandianPainting"
		actions.add_child(painting)
	if id=="xinghe" and (int(bond.get("stage",0))>=4 or not app.session.snapshot.get(Goals.GARDEN_KEY,[]).is_empty()):
		var garden:Button=app.button("共同花園",shared_garden.bind(app))
		garden.name="XingheSharedGarden"
		actions.add_child(garden)
	if id=="xinghe" and goal_state(app,id,1).get("state")=="done":
		actions.add_child(app.button("星禾的作物觀察簿",growth_book.bind(app)))
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
	app.modal.set_meta("life_modal_layout","keepsake_paper")
	var snapshot:Dictionary=app.session.snapshot
	var bits:=int(snapshot.get("own_sheep_corner",0))
	var cell:Vector2i=World.LIVESTOCK.ANIMALS.sheep.cell
	var inventory:Dictionary=player(app).get("inventory",{})
	var paper:=card(body)
	line(app,paper,"棚下有乾燥的位置，纖維墊讓牠躲雨時也能躺得舒服。",16)
	if (int(snapshot.get("sheep_comfort_fixtures",0))&1)!=0:
		var shelter:=preload("res://scripts/sheep_shelter.gd").new()
		shelter.observe(snapshot,0.0)
		line(app,paper,shelter.status,15)
	for id:String in Goals.SHEEP_COMFORT_PARTS:
		var part:Dictionary=Goals.SHEEP_COMFORT_PARTS[id]
		if (bits&int(part.bit))!=0:
			line(app,paper,"✓ "+str(part.label),16)
			continue
		var costs:=PackedStringArray()
		var enough:=true
		for item:String in part.cost:
			costs.append("%s %d"%[World.NAMES[item],part.cost[item]])
			enough=enough and int(inventory.get(item,0))>=int(part.cost[item])
		var build:Button=app.button("%s · %s"%[part.label,"、".join(costs)],func():
			app.session.perform(Goals.SHEEP_SHELTER_ACTION,cell,id)
			app._close_modal())
		build.name="SheepComfort_"+id
		build.disabled=not enough
		paper.add_child(build)
	if goal_state(app,"mianmian",2).get("state")=="done":
		line(app,body,"棉棉留下的玩具",18)
		var choices:=HBoxContainer.new()
		body.add_child(choices)
		for toy:String in Goals.SHEEP_TOYS:
			var play:Button=app.button("拿%s陪牠玩"%Goals.SHEEP_TOYS[toy],func():
				app.session.perform(Goals.SHEEP_TOY_ACTION,cell,toy)
				app._close_modal())
			play.name="SheepToy_"+toy
			choices.add_child(play)
	elif bits==Goals.SHEEP_COMFORT_MASK:
		line(app,body,"兩件都準備好了，回去告訴棉棉。",16)

static func tea_guest_seat(app) -> void:
	var body:VBoxContainer=app._open_modal("替茶亭留個座位")
	app.modal.set_meta("life_modal_layout","keepsake_paper")
	var chosen:String=app.session.snapshot.get("own_chacha_tea_chair","")
	line(app,body,"挑一張和茶亭木椅不同的椅子，留給下一位來喝茶的人。",17)
	for choice:String in Goals.TEA_CHAIRS:
		var seat:Dictionary=Goals.TEA_CHAIRS[choice]
		var row:=card(body)
		var preview:=HBoxContainer.new()
		row.add_child(preview)
		var icon:=AtlasTexture.new()
		icon.atlas=preload("res://assets/ui-life/furniture.png")
		icon.region=Rect2(96,48,32,48)
		add_icon(preview,icon,44)
		preview.get_child(0).modulate=seat.tint
		var description:="保留木紋，坐在茶亭左側。" if choice=="wood" else "帶一點海邊的藍綠，坐在茶亭右側。"
		line(app,preview,"%s · %s"%[seat.name,description],16)
		if chosen.is_empty():
			var place:Button=app.button("放上%s"%seat.name,func():
				app.session.perform(Goals.TEA_CHAIR_ACTION,seat.cell,choice)
				app._close_modal())
			place.name="ChachaChair_"+choice
			row.add_child(place)
		elif choice==chosen:line(app,row,"✓ 已經留好這張椅子，回去告訴茶茶。",15)

static func chacha_menu(app) -> void:
	var body:VBoxContainer=app._open_modal("茶茶手寫茶單")
	app.modal.set_meta("life_modal_layout","keepsake_paper")
	var paper:=card(body)
	line(app,paper,"今天想喝點什麼？",20)
	for entry:Array in [
		["tea_light","淺焙茶","第一杯先別忙著說話，聞聞熱氣。"],
		["tea_deep","深焙茶","山風大時，讓杯子多坐一下。"],
		["tea_pudding","茶香布丁","留一小匙，配最後那口茶。"],
	]:
		var row:=HBoxContainer.new()
		row.add_theme_constant_override("separation",8)
		paper.add_child(row)
		add_icon(row,ItemArt.icon(entry[0]),32)
		line(app,row,"%s　%s"%[entry[1],entry[2]],16)
	line(app,body,"「椅子不必排得一樣整齊。坐得舒服就好。」——茶茶",15)

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
	body.add_child(app.button("回到茶茶",bond_dialogue.bind(app,"chacha")))

static func add_paint_invitation(app,actions:Container,id:String,cell:Vector2i) -> void:
	if id=="diandian" or int(bond_view(app,"diandian").get("stage",0))<3:return
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
	var can_hang:bool=goal_state(app,"diandian",3).get("state")=="done" and int(bond_view(app,"diandian").get("stage",0))>=4
	if not s.get("picnic",false) or (not s.has(Goals.MURAL_KEY) and not can_hang):return
	var body:=app.modal.find_child("ModalContent",true,false) as VBoxContainer
	if body==null:return
	var link:Button=app.button("看看全島合畫" if s.has(Goals.MURAL_KEY) else "布置公共合畫",public_mural.bind(app))
	link.name="PublicMural"
	body.add_child(link)
	body.move_child(link,0)

static func public_mural(app,page:=-1) -> void:
	var s:Dictionary=app.session.snapshot
	var mural:Dictionary=s.get(Goals.MURAL_KEY,{})
	var body:VBoxContainer=app._open_modal("全島合畫")
	app.modal.set_meta("life_modal_layout","community_board")
	var nearby:bool=s.get("region_id","home")=="home" and Vector2(float(player(app).get("x",0)),float(player(app).get("y",0))).distance_to(Vector2(Goals.MURAL_SITE)+Vector2(0.5,0.5))<=3.2
	if mural.is_empty():
		line(app,body,"在公告板旁掛上第一幅合畫，右邊留一個位置。",17)
		var hang:Button=app.button("掛上合畫，留一格空白",func():
			app.session.perform(Goals.MURAL_HANG_ACTION,Goals.MURAL_SITE)
			app._close_modal())
		hang.name="HangMural"
		hang.disabled=not nearby
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
		if index>0:pages.add_child(app.button("看上一位",public_mural.bind(app,index-1)))
		if index<names.size():pages.add_child(app.button("看下一位",public_mural.bind(app,index+1)))
		if index<names.size():pages.add_child(app.button("回到空白位置",public_mural.bind(app,names.size())))
	if nearby and not s.get("own_diandian_mural",false):
		var sign:Button=app.button("把我的身影加進畫裡",func():
			app.session.perform(Goals.MURAL_SIGN_ACTION,Goals.MURAL_SITE)
			app._close_modal())
		sign.name="SignMural"
		body.add_child(sign)
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

static func painting_book(app) -> void:
	var finished:bool=goal_state(app,"diandian",3).get("state")=="done"
	var body:VBoxContainer=app._open_modal("點點的第一幅合畫" if finished else "畫面外的位置")
	app.modal.set_meta("life_modal_layout","keepsake_paper")
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
	elif invited.size()<Goals.PAINT_INVITE_COUNT:
		line(app,body,"已邀請 %d／%d 位。靠近任一位居民，對話時選「邀請入畫」。"%[invited.size(),Goals.PAINT_INVITE_COUNT],16)
	else:
		line(app,body,"三個位置都有人了。回星芽庭園向點點回報。",16)

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

static func shared_garden(app) -> void:
	var snapshot:Dictionary=app.session.snapshot
	var pots:Array=snapshot.get(Goals.GARDEN_KEY,[])
	var body:VBoxContainer=app._open_modal("大家的花園日")
	app.modal.set_meta("life_modal_layout","keepsake_paper")
	var flowers:=HBoxContainer.new()
	flowers.add_theme_constant_override("separation",8)
	body.add_child(flowers)
	for index in Goals.GARDEN_POTS.size():
		var slot:=card(flowers)
		(slot.get_parent() as PanelContainer).size_flags_horizontal=Control.SIZE_EXPAND_FILL
		if index>=pots.size():
			line(app,slot,"留給下一位",16)
			continue
		var pot:Dictionary=pots[index]
		var art:=AtlasTexture.new()
		art.atlas=preload("res://assets/lanyang-life/shared-garden-pots.png")
		art.region=Rect2(Goals.GARDEN_FLOWERS.find(pot.flower)*32,0,32,32)
		add_icon(slot,art,48)
		line(app,slot,World.NAMES[pot.flower],16)
		line(app,slot,"由%s挑選"%pot.name,15)
	if pots.size()==Goals.GARDEN_POTS.size():
		var state:String=goal_state(app,"xinghe",4).get("state","locked")
		if state=="open":
			var report:Button=app.button("找星禾回報",bond_goal.bind(app,"xinghe",4))
			report.name="XingheGardenReport"
			body.add_child(report)
		else:line(app,body,"三盆花都在水圳旁了。",16)
		return
	var mine:=false
	var residents:=PackedStringArray()
	for pot:Dictionary in pots:
		if pot.npc:residents.append(pot.author)
		elif pot.author==app.session.own_id:mine=true
	var choices:=HFlowContainer.new()
	body.add_child(choices)
	if not mine:
		for flower:String in Goals.GARDEN_FLOWERS:
			var pick:Button=app.button("選"+World.NAMES[flower],shared_garden_pick.bind(app,flower))
			pick.name="XinghePlant_"+flower
			choices.add_child(pick)
	if int(bond_view(app,"xinghe").get("stage",0))>=4:
		for resident:String in Goals.GARDEN_NPCS:
			if resident in residents:continue
			var ask:Button=app.button("請%s挑一盆"%Goals.GARDEN_NPCS[resident].name,shared_garden_pick.bind(app,resident))
			ask.name="XingheInvite_"+resident
			choices.add_child(ask)
	line(app,body,"每位作者各選一盆。朋友可以從星禾的對話加入。",15)

static func shared_garden_pick(app,flower:String) -> void:
	app.session.perform(Goals.GARDEN_ACTION,World.LANYANG_LIFE.SERVICE,flower)
	app._close_modal()

static func growth_book(app) -> void:
	var body:VBoxContainer=app._open_modal("星禾的作物觀察簿")
	app.modal.set_meta("life_modal_layout","community_board")
	line(app,body,"渡口或蘭陽的自種作物都能收錄。從幼苗記起，等同一株成熟後再記一次。",16)
	var logbook:Dictionary=app.session.snapshot.get("own_xinghe_growth_log",{})
	var kinds:=logbook.keys()
	kinds.sort()
	for kind:String in kinds:
		var page:=card(body)
		var row:=HBoxContainer.new()
		row.add_theme_constant_override("separation",12)
		page.add_child(row)
		add_icon(row,ItemArt.icon(kind),32)
		var notes:=VBoxContainer.new()
		notes.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		row.add_child(notes)
		line(app,notes,"%s　✓ 幼苗　✓ 成熟"%World.CROPS[kind].name,17)
		var season:=World.crop_season_text(kind)
		if not season.is_empty():line(app,notes,"露天生長季 · %s"%season,14)

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

static func address_letter(app) -> void:
	var stage:=int(app.session.snapshot.get("own_luoluo_address",0))
	var title:="已送達的信" if stage==Goals.ADDRESS_DELIVERED else "洛洛的信封"
	var body:VBoxContainer=app._open_modal(title if stage>0 else "普通信箱")
	app.modal.set_meta("life_modal_layout","community_board")
	if stage==0:
		line(app,body,"信箱目前是空的。洛洛在渡口出貨箱附近整理信件。",16)
		return
	var paper:=card(body)
	line(app,paper,"收件人線索",20)
	var clues:Array[Label]=[]
	for hint:String in [
		"一、我常在村裡修木家具，長椅有一隻腳鬆了也可以來找我。",
		"二、從小栗的種子攤往西走，過了公告板，就能找到我平常站的位置。",
		"三、名字的第一個字是「阿」。",
	]:
		var clue:Label=app.label(hint,16)
		clue.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		clue.name="AddressClue%d"%(clues.size()+1)
		paper.add_child(clue)
		clues.append(clue)
	var zoom:=CheckButton.new()
	zoom.name="LuoluoAddressZoom"
	zoom.text="放大信件文字"
	zoom.toggled.connect(func(enlarged:bool):
		for clue:Label in clues:
			var base:=26 if enlarged else 16
			var pixels:int=app.scaled_font_size(base)
			clue.set_meta("font_scale_base",base)
			clue.set_meta("font_scale_applied",pixels)
			clue.add_theme_font_size_override("font_size",pixels))
	body.add_child(zoom)
	line(app,body,"阿榆已收到信。可以回去找洛洛。" if stage==Goals.ADDRESS_DELIVERED else "帶著信去找居民，當面確認是不是他收。",15)

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
	var body:VBoxContainer=app._open_modal(World.BUILD[kind].name)
	app.modal.set_meta("life_modal_layout","inn_wardrobe" if kind==Goals.INN_WARDROBE else "station_dialogue")
	var display:=HBoxContainer.new()
	display.add_theme_constant_override("separation",14)
	body.add_child(display)
	var art:=preload("res://assets/ui-inventory/inn-lattice-wardrobe.png") if kind==Goals.INN_WARDROBE else preload("res://assets/ui-inventory/guest-wardrobe.png")
	add_icon(display,art,64)
	var choices:=VBoxContainer.new()
	choices.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	display.add_child(choices)
	if kind==Goals.INN_WARDROBE:
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
	app.modal.set_meta("life_modal_layout","keepsake_paper" if has_notes else "station_dialogue")
	var note:=card(body)
	if tree:
		line(app,note,"一截空繩垂在低枝上，打的是雙結。其他小鈴都綁在同樣的高度。",17)
	else:
		add_icon(note,preload("res://assets/ui-inventory/cracked-dock-bell.png"),64)
		line(app,note,"鈴婆婆把舊鈴轉了過來。鈴口裂了一道，雙結還好好地留在細繩上。",17)
	var target:Vector2i=World.Festival.TREE_CELL if tree else Bond.bell_cell(app.session.snapshot)
	if tree:
		add_tree_notes(app,body)
		if int(app.session.snapshot.get("own_lingpopo_bell",0))&Goals.BELL_TREE_BIT:return
		if int(bond_view(app,"lingpopo").get("stage",0))<1:return
	var record:Button=app.button("記下空繩上的雙結" if tree else "記下鈴口的裂紋",func():
		app.session.perform(Goals.BELL_INSPECT_ACTION,target,site)
		app._close_modal())
	record.name="LingpopoRecordClue"
	body.add_child(record)

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

static func bell_history(app,page:=1) -> void:
	if not bell_history_unlocked(app,page):page=2 if page==1 else 1
	if not bell_history_unlocked(app,page):return
	var title:="島史第一頁 · 低枝上的空繩" if page==1 else "島史第二頁 · 三枚不同的鈴"
	var body:VBoxContainer=app._open_modal(title)
	app.modal.set_meta("life_modal_layout","keepsake_paper")
	var paper:=card(body)
	line(app,paper,"鈴婆婆口述・風鈴渡口的故事",15)
	if page==1:
		line(app,paper,"渡口還沒有夜燈的時候，送船的人會把鈴繫在低枝。晚歸的人伸手摸到繩結，就知道離上岸的石階不遠了。",18)
		line(app,paper,"後來船多起來，枝上還留著一截空繩。鈴婆婆把裂了的小鈴留在身邊，說等下一個想聽故事的人來，就借他看一眼。",16)
	else:
		line(app,paper,"圓鈴、角鈴和方鈴原本掛在三條回家的路上。小孩記得形狀，大人記得聲音，也有人只記得樹下等他的那盞燈。",18)
		line(app,paper,"鈴婆婆畫下 △、○、□，把三條路畫在同一張紙上。她說，認得回家的路，本來就有很多種辦法。",16)
	var other:=2 if page==1 else 1
	if bell_history_unlocked(app,other):body.add_child(app.button("翻到第二頁" if other==2 else "翻回第一頁",bell_history.bind(app,other)))
	body.add_child(app.button("回到島民手冊",journal.bind(app)))

static func add_milu_recipe_book(app,parent:Container) -> void:
	if int(bond_view(app,"milu").get("stage",0))<2:return
	var button:Button=app.button("翻開米露的食譜手記",milu_recipe_book.bind(app))
	button.name="MiluRecipeBook"
	parent.add_child(button)

static func milu_recipe_book(app) -> void:
	var snapshot:Dictionary=app.session.snapshot
	var done:bool=snapshot.get("resident_goals",{}).get("milu",{}).get("2",{}).get("state")=="done"
	var body:VBoxContainer=app._open_modal("米露的共餐桌手記" if done else "沾到麵粉的頁角")
	app.modal.set_meta("life_modal_layout","community_board")
	var found:=int(snapshot.get("own_milu_recipe_pages",0))
	if not done:
		var sketch:=card(body)
		line(app,sketch,"廣場草圖　↑ 北",15)
		var landmarks:=GridContainer.new()
		landmarks.columns=2
		landmarks.add_theme_constant_override("h_separation",18)
		sketch.add_child(landmarks)
		for site:String in ["board","shop","table"]:
			var pin:Dictionary=Goals.RECIPE_PAGES[site]
			var mark:="✓" if (found&int(pin.bit))!=0 else "◆"
			line(app,landmarks,"%s %s"%[mark,pin.name],16)
	for page:Dictionary in Goals.RECIPE_PAGES.values():
		var paper:=card(body)
		line(app,paper,"%s %s"%["✓" if (found&int(page.bit))!=0 else "○",page.name],17)
		line(app,paper,page.note if done else page.hint,15)
	if done:
		var cell:=World.milu_recipe_cell(snapshot,"table")
		var person:=player(app)
		var nearby:=Vector2(person.get("x",0),person.get("y",0)).distance_to(Vector2(cell)+Vector2(0.5,0.5))<=3.2
		if snapshot.get("region_id")==World.REGIONS.HOME and cell!=World.COMMUNITY.NO_CELL and nearby:
			body.add_child(app.button("打開共餐桌",app._community_menu))
		else:
			line(app,body,"帶好料理，走到廣場的共餐桌旁就能上桌。",15)
	elif found==Goals.RECIPE_PAGE_MASK:
		line(app,body,"三片紙角找齊了。回去找米露，在關係事件交給她。",16)
	body.add_child(app.button("回到米露",resident.bind(app,"milu")))

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
	var saved:=await capture_island_photo(app,achao_photo_path(app))
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
	app.modal.set_meta("life_modal_layout","keepsake_paper")
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
	var operation:="depart" if lit else "repair"
	var action:Button=app.button("出發試航" if lit else "修碼頭燈 · 木材 4、銅礦 1",func():
		app.session.perform(Goals.VOYAGE_ACTION,place,operation)
		app._close_modal())
	action.name="AchaoVoyage_"+operation
	body.add_child(action)
	if lit:
		var board:Button=app.button("加入剛出航的朋友",func():
			app.session.perform(Goals.VOYAGE_ACTION,place,"join")
			app._close_modal())
		board.name="AchaoVoyageJoin"
		body.add_child(board)
		var path:=achao_photo_path(app)
		if FileAccess.file_exists(path):
			var album:Button=app.button("翻看上次的船上合照",achao_album.bind(app,path))
			album.name="AchaoVoyageAlbum"
			body.add_child(album)
	if goal_state(app,"achao",3).get("state")=="done":
		var paint:Button=app.button("換回原木船身" if blue else "使用藍白船身",func():
			app.session.perform(Goals.VOYAGE_ACTION,place,"paint")
			app._close_modal())
		paint.name="AchaoVoyagePaint"
		body.add_child(paint)
		line(app,body,"海鮮燉飯已收進小石灶食譜。",16)

static func achao_album(app,path:String) -> void:
	var image:=Image.load_from_file(path)
	if image==null or image.is_empty():return
	var body:VBoxContainer=app._open_modal("河灣上的合照")
	app.modal.set_meta("life_modal_layout","keepsake_paper")
	var preview:=TextureRect.new()
	preview.name="AchaoAlbumPhoto"
	preview.texture=ImageTexture.create_from_image(image)
	preview.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.custom_minimum_size.y=275
	body.add_child(preview)

static func achao_route_book(app) -> void:
	var s:Dictionary=app.session.snapshot
	var done:bool=s.get("resident_goals",{}).get("achao",{}).get("2",{}).get("state")=="done"
	var body:VBoxContainer=app._open_modal("阿潮的手繪群島地圖" if done else "褪色的航線")
	app.modal.set_meta("life_modal_layout","community_board")
	var spread:=HBoxContainer.new()
	spread.add_theme_constant_override("separation",12)
	body.add_child(spread)
	var notes:=VBoxContainer.new()
	notes.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	spread.add_child(notes)
	var page:=card(notes)
	var marks:=int(s.get("own_achao_route_marks",0))
	for sign:Dictionary in World.RESIDENT_GOALS.ROUTE_SIGNS.values():
		var recorded:bool=(marks&int(sign.bit))!=0
		line(app,page,"%s %s"%["✓" if recorded else "○",sign.name],17)
		line(app,page,sign.hint,14)
	if done:
		var map:Control=preload("res://scripts/taiwan_map.gd").new()
		map.name="AchaoChart"
		map.set_meta("current_region",str(s.get("region_id","home")))
		map.set_meta("travel_book",player(app).get("travel_book",{}))
		spread.add_child(map)
	elif marks==World.RESIDENT_GOALS.ROUTE_MASK:
		line(app,notes,"三處方向都畫好了，回去跟阿潮說一聲。",16)
	notes.add_child(app.button("回到阿潮",bond_dialogue.bind(app,"achao")))

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
	var body:VBoxContainer=app._open_modal("米露的共餐食譜")
	app.modal.set_meta("life_modal_layout","community_board")
	var cover:=card(body)
	portrait_header(app,cover,"milu","",64)
	line(app,cover,"今天這一碗，先留給自己。",18)
	for dish:String in World.COMMUNITY.DISHES.values():
		var recipe:Dictionary=World.RECIPES[dish]
		var ingredients:=PackedStringArray()
		for item:String in recipe.ingredients:
			ingredients.append("%s ×%d"%[World.NAMES[item],recipe.ingredients[item]])
		var row:=HBoxContainer.new()
		row.add_theme_constant_override("separation",10)
		cover.add_child(row)
		add_icon(row,Art.icon(dish),32)
		var note:=VBoxContainer.new()
		note.add_theme_constant_override("separation",1)
		row.add_child(note)
		line(app,note,"%s · 每批 %d 份"%[recipe.name,recipe.yield],17)
		line(app,note,"、".join(ingredients),15)
	body.add_child(app.button("回到米露",resident.bind(app,"milu")))

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
	if entry.has("options") and Goals.option(entry,choice).is_empty():return GOAL_NEED_OPTION
	if entry.has("steps") and picks.size()<Goals.STEP_COUNT:return GOAL_NEED_STEPS
	for need_row:Dictionary in goal_needs(app,id,stage):
		if not bool(need_row.get("met",false)):return "要先「%s」。"%str(need_row.get("label",""))
	var held:Dictionary=player(app).get("inventory",{})
	var need:Dictionary=Goals.cost(entry,choice)
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

static func add_guest_cloth_claim(app,parent:Container) -> Button:
	var cloth:Button=app.button("領取旅舍布料 ×2",func():
		app.session.perform(Goals.GUEST_CLOTH_ACTION,Bond.SPRING_CELL)
		app._close_modal())
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
	add_icon(header,springs.INN_ART,128)
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
	if inn_resting(app):
		details.add_child(app.button("拍張旅舍合照",take_inn_photo.bind(app)))
	elif FileAccess.file_exists(inn_photo_path(app)):
		details.add_child(app.button("翻看旅舍合照",view_inn_photo.bind(app)))

static func inn_photo_path(app) -> String:
	return "user://nuannuan-inn-%s.png"%str(app.session.own_id).sha256_text().left(24)

static func inn_resting(app) -> bool:
	var springs:=World.REGIONS.Springs
	return app.session.snapshot.get("region_id")==springs.REGION and springs.REST_SEATS.has(player(app).get(springs.REST_SEAT_KEY,""))

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
	var page:={"id":id,"stage":stage,"state":state,"option":"","picks":[],"error":"","fp":""}
	app.modal.set_meta("bond_goal",page)
	var title:Label=app.label("%s・%s"%[Bond.stage_name(stage),str(entry.title)],18)
	title.name="BondGoalTitle"
	body.add_child(title)
	var task:Label=app.label(str(entry.task),15)
	task.name="BondGoalTask"
	task.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	body.add_child(task)
	if id=="milu" and stage==2 and state!="locked":
		add_milu_recipe_book(app,body)
	var actions:=HFlowContainer.new()
	actions.name="BondGoalActions"
	actions.add_theme_constant_override("h_separation",8)
	actions.add_theme_constant_override("v_separation",8)
	if state=="done":
		var done:=card(body)
		done.get_parent().name="BondGoalDone"
		done.add_theme_constant_override("separation",4)
		line(app,done,"✓ 已經一起完成",17)
		for quote in entry.quote:line(app,done,"「%s」"%str(quote),15)
		var picked:Dictionary=Goals.option(entry,str(goal_state(app,id,stage).get("choice","")))
		if not picked.is_empty():line(app,done,"當時選的是：%s"%str(picked.label),15)
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
		if id=="lingpopo" and stage<=2:
			var history:Button=app.button("閱讀%s"%entry.keepsake,bell_history.bind(app,stage))
			history.name="LingpopoHistoryPage"
			done.add_child(history)
		elif id=="aru" and stage==2:
			line(app,done,"紀念：%s。師父的長椅已加入家園工坊。"%str(entry.keepsake),15)
			var pattern:Button=app.button("翻看長椅圖樣",aru_bench_pattern.bind(app))
			pattern.name="AruBenchPattern"
			done.add_child(pattern)
		elif id=="bobo" and stage==3:
			line(app,done,"已解鎖%s。到工作台用木板 4、纖維 2 製作，再從建造目錄放置。"%str(entry.keepsake),15)
		elif id=="milu" and stage==2:
			line(app,done,"紀念：%s"%str(entry.keepsake),15)
		elif id=="nuannuan" and stage==3:
			line(app,done,"暖暖把兩塊布料留給你。搭配四塊木板，就能做一座旅舍更衣櫃。",15)
			if app.session.snapshot.get("own_guest_cloth",false):
				line(app,done,"✓ 旅舍布料已領取",15)
			else:
				var cloth:=add_guest_cloth_claim(app,done)
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
			if not claimed:
				var claim_reason:Label=app.label("",15)
				claim_reason.name="BondGoalClaimReason"
				claim_reason.add_theme_color_override("font_color",GOAL_WARN)
				body.add_child(claim_reason)
				var claim:Button=app.button("領取紀念小物",do_goal_claim.bind(app))
				claim.name="BondGoalClaim"
				actions.add_child(claim)
	elif state=="open":
		if id=="nuannuan" and stage==1:
			var clear:Button=app.button("掃落葉、整理碎石",func():
				app.session.perform(Goals.INN_CLEAR_ACTION,Bond.SPRING_CELL))
			clear.name="NuannuanClearEntrance"
			body.add_child(clear)
		if entry.has("options"):
			var options:=HFlowContainer.new()
			options.name="BondGoalOptions"
			options.add_theme_constant_override("h_separation",8)
			options.add_theme_constant_override("v_separation",8)
			body.add_child(options)
			var group:=ButtonGroup.new()
			for option:Dictionary in entry.options:
				var option_id:=str(option.id)
				var text:=str(option.label)
				var own:Dictionary=option.get("items",{})
				if not own.is_empty():text+="（%s）"%goal_items_text(own)
				var choice:Button=app.button(text,choose_goal_option.bind(app,option_id))
				choice.name="BondGoalOption_"+option_id
				choice.toggle_mode=true
				choice.button_group=group
				choice.add_theme_font_size_override("font_size",15)
				options.add_child(choice)
		if entry.has("steps"):
			line(app,body,"做完一步就按一下；按錯了可以按「重來」。",14)
			var steps:=HFlowContainer.new()
			steps.name="BondGoalSteps"
			steps.add_theme_constant_override("h_separation",8)
			steps.add_theme_constant_override("v_separation",8)
			body.add_child(steps)
			for index in range(entry.steps.size()):
				var step:Button=app.button(str(entry.steps[index]),pick_goal_step.bind(app,index))
				step.name="BondGoalStep_%d"%index
				step.add_theme_font_size_override("font_size",15)
				steps.add_child(step)
			var reset:Button=app.button("重來",reset_goal_steps.bind(app))
			reset.name="BondGoalStepsReset"
			reset.add_theme_font_size_override("font_size",15)
			steps.add_child(reset)
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
		var finish:Button=app.button("敲響風鈴" if id=="lingpopo" and stage==4 else "一起完成",do_goal.bind(app))
		finish.name="BondGoalDo"
		actions.add_child(finish)
	else:
		line(app,body,"和%s的關係到「%s」之後，才能一起做這件事。"%[npc_name,Bond.stage_name(stage)],15)
	var back:Button=app.button("回到關係事件",bond_events.bind(app,id,stage-1))
	back.name="BondGoalBack"
	actions.add_child(back)
	body.add_child(actions)
	if state=="open":refresh_goal_page(app,true)
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
	page.option=option_id
	refresh_goal_page(app,true)

static func pick_goal_step(app,index:int) -> void:
	var page:=goal_page(app)
	if page.is_empty():return
	var picks:Array=page.picks
	if index in picks:return
	page.error=""
	picks.append(index)
	var entry:Dictionary=Goals.goal(str(page.id),int(page.stage))
	if picks.size()>=Goals.STEP_COUNT and entry.has("order"):
		var order:Array=entry.order
		if picks!=order:
			page.error=GOAL_ORDER_WRONG
			picks.clear()
	refresh_goal_page(app,true)
	var next:Button=null
	if picks.size()<Goals.STEP_COUNT:
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
	var need:Dictionary=Goals.cost(entry,choice)
	var rows:Array=[]
	for item:String in need:rows.append([item,int(held.get(item,0)),int(need[item])])
	var reason:=goal_reason(app,id,stage,choice,picks,str(page.error))
	var need_rows:=goal_needs(app,id,stage)
	var clear:=goal_node(app,"NuannuanClearEntrance") as Button
	if clear!=null:
		var cleared:=false
		for row:Dictionary in need_rows:
			if row.id=="inn_entrance":cleared=bool(row.met)
		clear.text="✓ 旅舍門口已清理" if cleared else "掃落葉、整理碎石"
		clear.disabled=cleared or not goal_near(app,id)
	var fingerprint:=str([choice,picks,reason,rows,need_rows])
	if not force and fingerprint==str(page.fp):return
	page.fp=fingerprint
	var options:=goal_node(app,"BondGoalOptions")
	if options!=null:
		for child in options.get_children():
			var b:=child as Button
			if b!=null:b.set_pressed_no_signal(str(b.name)=="BondGoalOption_"+choice)
	if entry.has("steps"):
		for i in range(entry.steps.size()):
			var step:=goal_node(app,"BondGoalStep_%d"%i) as Button
			if step==null:continue
			var at:=picks.find(i)
			step.text=("%d. "%(at+1) if at>=0 else "")+str(entry.steps[i])
			step.disabled=at>=0
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
		note.text=reason
		note.visible=not reason.is_empty()
	var finish:=goal_node(app,"BondGoalDo") as Button
	if finish!=null:
		finish.disabled=not reason.is_empty()
		finish.tooltip_text=reason

static func do_goal(app) -> void:
	var page:=goal_page(app)
	if page.is_empty() or str(page.state)!="open":return
	var id:=str(page.id)
	var stage:=int(page.stage)
	var picks:Array=page.picks
	if not goal_reason(app,id,stage,str(page.option),picks,str(page.error)).is_empty():return
	var digits:=""
	for index in picks:digits+=str(index)
	var cell:Vector2i=World.bond_place(app.session.snapshot,id)[1]
	# 送出後頁面就要關閉；這期間到達的快照不必重畫本頁。
	page["sending"]=true
	app.session.perform(Goals.ACTION,cell,"%s:%d:%s:%s"%[id,stage,str(page.option),digits])
	app._close_modal()

## 每份新快照（main 透過 refresh_island_notes 呼叫）：行動狀態變了就重畫整頁，
## 否則只更新材料、站位原因與「一起完成」，保留已選的做法與步驟。
static func refresh_bond_goal(app) -> void:
	var page:=goal_page(app)
	if page.is_empty() or bool(page.get("sending",false)):return
	var id:=str(page.id)
	var stage:=int(page.stage)
	if str(goal_state(app,id,stage).get("state","locked"))!=str(page.state):
		bond_goal(app,id,stage)
		return
	if page.has("claimed") and bool(page.claimed)!=bool(goal_keepsake(app,id,stage).get("claimed",false)):
		bond_goal(app,id,stage)
		return
	refresh_goal_page(app)
	refresh_goal_claim(app)

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
