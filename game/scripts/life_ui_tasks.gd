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

static func island_news(app) -> void:
	var body:VBoxContainer=app._open_modal("島嶼近況")
	app.modal.set_meta("life_modal_layout","community_board")
	var snapshot:Dictionary=app.session.snapshot
	var projects:=card(body)
	line(app,projects,"公共工程",20)
	var news:Dictionary=snapshot.get("island_news",{})
	var names:=World.ISLAND_NOTES.PROJECTS
	var completed:=int(news.get("completed",0))
	var unread:=completed & ~int(news.get("seen",0))
	for index in names.size():
		var bit:=1<<index
		var status:="未完成" if (completed & bit)==0 else ("新完成" if (unread & bit)!=0 else "已完成")
		line(app,projects,"%s · %s"%[names[index],status],16)
	if unread!=0:
		projects.add_child(app.button("標為已讀",func():
			app.session.perform("news_read",Vector2i.ZERO,str(completed))
			app._close_modal()
		))
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
	body.add_child(app.button("島民留言 · %d 則"%snapshot.get("island_notes",[]).size(),island_notes.bind(app)))
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
	if list.has_meta("entries") and list.get_meta("entries")==entries:return
	list.set_meta("entries",entries.duplicate(true))
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()
	for entry:Dictionary in entries:
		var paper:=card(list)
		line(app,paper,"%s · 第 %d 日"%[entry.sender,floori(float(entry.time)/World.Village.DAY)+1],15)
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
	if salt==null or not salt_complete(app):return
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
	line(app,page,"斗笠總是往後推，說話時會先看一眼天色。晴天催大家引海水，下雨就把草蓆蓋好，等雨停再收鹽。",16)
	var gates_done:bool=salt!=null and salt.repaired(app.session.snapshot)
	line(app,page,"✓ 三道閘門修好・海水引進鹽田" if gates_done else "○ 用木板、樹脂與石材修好三道閘門",15)
	line(app,page,"✓ 水車引水、收鹽台自動收進箱子",15)
	line(app,page,"✓ 海鹽與香煎溪魚送到小栗的攤位",15)
	line(app,page,"阿曬是遊戲原創的人物；觀景區的井仔腳瓦盤鹽田是今日保存的文化景觀，只供欣賞。",14)
	if salt:
		var memory:Button=app.button("翻開北門瓦盤鹽田",func():salt.open(app,"journal"))
		memory.name="SaltWorkerMemory"
		page.add_child(memory)

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
		details.hide()
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

static func board(app) -> void:
	var col:VBoxContainer=app._open_modal("渡口的共同工程")
	app.modal.set_meta("life_modal_layout","community_board")
	var s:Dictionary=app.session.snapshot
	var project:=card(col)
	var donations:Dictionary=s.get("donations",{})
	line(app,project,"渡口修繕",22)
	line(app,project,"河灣橋已開通。" if s.get("board",false) else "一起捐木材和石材，讓河灣橋重新開通。",16)
	if not s.get("board",false):
		material_progress(app,project,"wood",int(donations.get("wood",0)),30)
		material_progress(app,project,"stone",int(donations.get("stone",0)),10)
		project.add_child(app.button("捐入背包裡需要的材料",func():app.session.perform("donate",BOARD_CELL);app._close_modal()))
		line(app,project,"只捐工程尚缺的數量。",15)
	if s.get("board",false):
		var picnic:=card(col)
		var dishes:Dictionary=s.get("picnic_materials",{})
		line(app,picnic,"渡口野餐",22)
		if s.get("picnic",false):
			line(app,picnic,"湯和麵包已上桌，謝謝每一位準備料理的島民。",16)
		else:
			material_progress(app,picnic,"soup",int(dishes.get("soup",0)),2)
			material_progress(app,picnic,"bread",int(dishes.get("bread",0)),1)
			# T071 紀念品交換攤 (locked) shares the picnic button's row: it opens after
			# this picnic, and the board gains no height.
			var picnic_row:=HBoxContainer.new()
			picnic_row.name="BoardPicnicRow"
			picnic_row.add_theme_constant_override("separation",8)
			picnic.add_child(picnic_row)
			var serve:Button=app.button("把料理放到野餐桌上",func():app.session.perform("picnic",BOARD_CELL);app._close_modal())
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
			var festival_row:=HBoxContainer.new()
			festival_row.name="BoardFestivalRow"
			festival_row.add_theme_constant_override("separation",8)
			col.add_child(festival_row)
			var festival:Button=app.button("一起玩風鈴接力  %s"%app.binding_label("festival"),app._festival_menu)
			festival.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			festival_row.add_child(festival)
			var souvenir:Button=app.button(preload("res://scripts/souvenir_exchange_ui.gd").ENTRY_OPEN,app._souvenir_menu)
			souvenir.name="SouvenirEntry"
			souvenir.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			festival_row.add_child(souvenir)
			# 第 40 章地方記憶展 joins the same row (no new board height; locked caption
			# before the festival opening).
			festival_row.add_child(preload("res://scripts/memory_exhibit_ui.gd").entry_button(app))
			# T071：豐收接力與河岸釣魚會共用一列，公告板不增加高度。
			var activities:=HBoxContainer.new()
			activities.name="BoardActivities"
			activities.add_theme_constant_override("separation",8)
			col.add_child(activities)
			# T071 家園布置題也在同一列（不增加公告板高度）。
			for entry in [["一起玩豐收接力（廣場西側）",app._harvest_menu,"HarvestRelayBoardEntry"],["河岸釣魚會（河灣橋南岸）",app._fishmeet_menu,"FishingMeetEntry"],["家園布置題（渡口西南草地）",app._showcase_menu,"ShowcaseEntry"]]:
				var b:Button=app.button(entry[0],entry[1])
				b.name=entry[2]
				b.size_flags_horizontal=Control.SIZE_EXPAND_FILL
				activities.add_child(b)
		else:
			# 野餐前：鎖定的河岸釣魚會與生活訂單共用一列（不增加公告板高度）。
			var row:=HBoxContainer.new()
			row.name="BoardActivities"
			row.add_theme_constant_override("separation",8)
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

static func dock_route_description(snapshot:Dictionary) -> String:
	if World.TRANSIT.tea_unlocked(snapshot):
		return "到渡口站牌搭合作小船，直達霧竹溪谷或暖泉高地。兩地的站牌都能搭小船回渡口。"
	return "到渡口站牌搭合作小船，可往返暖泉高地。茶園路線開放後也能航往霧竹溪谷。"

static func dock_project(app,from_news:=false) -> void:
	var body:VBoxContainer=app._open_modal("第四章・群島的來信")
	app.modal.set_meta("life_modal_layout","community_board")
	var snapshot:Dictionary=app.session.snapshot
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
		var ready:bool=World.CHAPTER_ONE.phase(snapshot)=="complete" and snapshot.get("flower_nursery",{}).get("garden",{}).get("complete",false)
		if not ready:line(app,body,"渡口故事與田尾公共花園完成後，大家就能開始修碼頭。",15)
		var submit:Button=app.button("交付這期工程材料",func():
			app.session.perform("dock_repair",BOARD_CELL,str(stage));app._close_modal())
		submit.disabled=not ready
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

static func line(app,parent:Container,value:String,font_size:int) -> void:
	var label:Label=app.label(value,font_size)
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	parent.add_child(label)

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
		# 第三批：有紀念小物的行動顯示是否已領；還沒領（第三批之前完成）時多一個補領鈕。
		var keep:=goal_keepsake(app,id,stage)
		if keep.is_empty():
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
		var finish:Button=app.button("一起完成",do_goal.bind(app))
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

static func material_progress(app,parent:VBoxContainer,id:String,value:int,goal:int) -> void:
	var row:=HBoxContainer.new()
	row.add_theme_constant_override("separation",10)
	parent.add_child(row)
	add_icon(row,ItemArt.icon(id),32)
	var details:=VBoxContainer.new()
	details.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	row.add_child(details)
	progress(app,details,World.NAMES[id],value,goal)

static func progress(app,parent:VBoxContainer,title:String,value:int,goal:int) -> void:
	line(app,parent,"%s  %d / %d"%[title,value,goal],16)
	var meter:=ProgressBar.new()
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

