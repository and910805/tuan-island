extends RefCounted
const World=preload("res://scripts/world.gd")
const Story=preload("res://scripts/history_story.gd")
const Pixel=preload("res://scripts/inventory_pixel_theme.gd")
const Shell=preload("res://scripts/life_ui_shell.gd")
const MemoryScene=preload("res://scripts/history_memory_scene.gd")
const SourceScene=preload("res://scripts/history_source_scene.gd")
const Wangan=World.WANGAN_MEMORY
const SERVICE:=Vector2i(33,29)
const MINE_TIMELINE_URL:="https://www.gep.ntpc.gov.tw/xmdoc/cont?xsmsid=0Q018377887368898201"
const MINE_EXHIBIT_URL:="https://tcmb.culture.tw/zh-tw/detail?id=561386&indexCode=Culture_Event"
const MINE_HERITAGE_URL:="https://twh.boch.gov.tw/taiwan/intro.aspx?id=6&lang=zh_tw"
const MINE_BEATS:={
	"MineHistoryPanning":[
		["1890","鐵路工人在基隆河發現砂金，掀起淘金熱。"],
		["1894","黃金博物館年表記載，採金者在金瓜石發現大金瓜露頭。"]],
	"MineHistoryHauling":[
		["1897","礦業公司開始有計畫地探礦與採礦。"],
		["1904","礦區發現銅礦，開採品項從金銀擴及銅。"],
		["1933","水湳洞興建選礦場，運礦鐵路通往八斗子。"]]
}
const DATE_COLOR:=Color("7a4a00")
## 金瓜石章節插畫（遊戲場景插畫）：[圖檔, 章節切換鈕文字]。
const MINE_ART:={
	"MineHistoryPanning":["res://assets/ui-life/jinguashi-memory-panning.png","淘洗河砂"],
	"MineHistoryHauling":["res://assets/ui-life/jinguashi-memory-hauling.png","沿軌道推礦車"]
}

static func own(app)->Dictionary:
	return app.session.snapshot.get("history_memory",{}).get("own_memory",{"seen":[],"round":0,"gates":[0,0],"completed":false})

static func near(app,cell:Vector2i)->bool:
	var s:Dictionary=app.session.snapshot
	var p:Dictionary=s.get("players",{}).get(app.session.own_id,{})
	return str(s.get("region_id","home"))=="lanyang" and not p.is_empty() and Vector2(p.x,p.y).distance_to(Vector2(cell)+Vector2(0.5,0.5))<=3.2

static func text(app,parent:Node,line:String,extent:int=16)->Label:
	var label:Label=app.label(line,extent)
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label

static func open(app,mode:String="journal",cell:Vector2i=Vector2i(-1,-1),return_to:Callable=Callable(),from_journal:=false)->void:
	var title:=Story.TITLE
	if mode=="wangan":title="望安花宅"
	if mode=="wangan_weir":title="望安石滬"
	if mode=="wangan_log":title="望安航記"
	if mode=="jinguashi":title="金瓜石・從河砂到礦車"
	var body:VBoxContainer=app._open_modal("地方記憶・"+title)
	app.modal.theme=Pixel.make(app.hud.theme)
	app.modal.add_theme_stylebox_override("panel",Pixel.frame_style())
	app.modal.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	app.modal.set_meta("life_modal_layout","history_memory")
	app.modal.set_meta("history_body",body)
	app.modal.set_meta("history_mode",mode)
	app.modal.set_meta("history_cell",cell)
	if return_to.is_valid():app.modal.set_meta("history_back",return_to)
	if mode=="jinguashi":
		app.modal.set_meta("suppress_world_prompts",true)
		add_mining_page(app,body,return_to,from_journal)
	refresh(app)
	app._layout_preview.call_deferred()

static func refresh(app)->void:
	if not is_instance_valid(app.modal) or not app.modal.has_meta("history_body"):return
	var record:=own(app)
	var s:Dictionary=app.session.snapshot
	var fieldwork:Dictionary=s.get("history_memory",{}).get("mine_fieldwork",{})
	var mode:String=app.modal.get_meta("history_mode")
	if mode=="jinguashi":
		var panning:=app.modal.find_child("MineHistoryPanning",true,false) as Label
		var hauling:=app.modal.find_child("MineHistoryHauling",true,false) as Label
		var panned:bool=fieldwork.get("panned",false)
		var delivered:bool=fieldwork.get("delivered",false)
		var beats_panning:=app.modal.find_child("MineHistoryPanningBeats",true,false) as Control
		var beats_hauling:=app.modal.find_child("MineHistoryHaulingBeats",true,false) as Control
		beats_panning.visible=panned
		beats_hauling.visible=delivered
		panning.visible=not panned
		hauling.visible=not delivered
		# One chapter illustration at a time; a chapter that is not (or no longer) recorded never shows its picture.
		var recorded:={"MineHistoryPanning":panned,"MineHistoryHauling":delivered}
		var chapter:String=app.modal.get_meta("mine_chapter","")
		if not recorded.get(chapter,false):
			chapter=""
			app.modal.set_meta("mine_chapter","")
		for node:Control in app.modal.get_meta("mine_index",[]):node.visible=chapter.is_empty()
		(app.modal.find_child("MineChapterView",true,false) as Control).visible=not chapter.is_empty()
		(app.modal.find_child("MineChapterArt",true,false) as TextureRect).texture=null if chapter.is_empty() else load(MINE_ART[chapter][0]) as Texture2D
		for key:String in MINE_ART:
			(app.modal.find_child(key+"Look",true,false) as Control).visible=recorded[key]
			(app.modal.find_child(key+"Chapter",true,false) as Control).visible=key==chapter
			var pick:=app.modal.find_child(key+"Pick",true,false) as Button
			pick.disabled=not recorded[key]
			pick.set_pressed_no_signal(key==chapter)
		if is_instance_valid(app.modal_feedback):
			var count:=int(fieldwork.get("panned",false))+int(fieldwork.get("delivered",false))
			app.modal_feedback.text="金瓜石地方記憶・已收錄 %d／2　Esc 關閉"%count
		return
	var cell:Vector2i=app.modal.get_meta("history_cell")
	var close_enough:=near(app,cell if mode=="observe" else SERVICE)
	var viewer:Dictionary=s.get("players",{}).get(app.session.own_id,{})
	var wangan_site:=Wangan.SITE
	var wangan_near:=false
	if s.get("region_id")=="home" and not viewer.is_empty():
		var position:=Vector2(viewer.x,viewer.y)
		wangan_site=Wangan.observation_site(s,position)
		wangan_near=position.distance_to(Vector2(wangan_site)+Vector2(0.5,0.5))<=3.2
	var wangan_seen:bool=s.get("own_wangan_house",false)
	var weir_site:=Vector2i(-1,-1)
	if s.get("region_id")=="home" and not viewer.is_empty():
		for site:Vector2i in Wangan.WEIR_SITES:
			if Vector2(viewer.x,viewer.y).distance_to(Vector2(site)+Vector2(0.5,0.5))<=3.2:
				weir_site=site
				break
	var weir_progress:=int(s.get("own_wangan_weir",0))
	var coast_time:=float(s.get("time",0.0))
	var coast_is_high:=World.WANGAN_COAST.high_tide(coast_time)
	var log_done:bool=s.get("own_wangan_log",false)
	var dock_cell:=World.RESIDENT_BOND.dock_cell(s)
	var dock_ready:=World.RESIDENT_BOND.present(s,"achao")
	var near_achao:bool=s.get("region_id")=="home" and not viewer.is_empty() and Vector2(viewer.x,viewer.y).distance_to(Vector2(dock_cell)+Vector2(0.5,0.5))<=3.2
	var repaired:bool=s.get("lanyang_life",{}).get("repaired",false)
	var plaque:bool=s.get("history_memory",{}).get("plaque",false)
	var mining_visited:bool=not fieldwork.is_empty() or s.get("region_id")=="jinguashi" or viewer.get("travel_book",{}).get("visited",{}).has("jinguashi")
	var fingerprint:=JSON.stringify([mode,record,close_enough,repaired,plaque,wangan_near,wangan_site,wangan_seen,weir_site,weir_progress,log_done,dock_ready,near_achao,dock_cell,mode=="wangan_weir" and coast_is_high,mining_visited])
	if app.modal.get_meta("history_fingerprint","")==fingerprint:
		if mode=="wangan_weir":
			var tide_clock:=app.modal.find_child("WanganWeirTideClock",true,false) as Label
			if tide_clock:tide_clock.text=World.WANGAN_COAST.next_tide_text(coast_time)
		return
	app.modal.set_meta("history_fingerprint",fingerprint)
	# Preserve the interactive scene on gate updates so focus and animation survive snapshots.
	var existing:Control=app.modal.find_child("MemoryScene",true,false)
	if mode=="play" and existing and not record.completed:
		var round_index:=int(record.round)
		existing.configure(record.gates,World.HISTORY_MEMORY.DEMANDS[round_index],round_index,app.sound.reduced_motion)
		existing.set_meta("near_service",close_enough)
		for control in existing.find_children("*","Button",true,false):control.disabled=not close_enough
		var voice:Label=app.modal.find_child("MemoryVoice",true,false)
		if voice:voice.text=Story.ROUNDS[round_index]
		if is_instance_valid(app.modal_feedback):app.modal_feedback.text="Esc 離開回顧・進度已保存" if close_enough else "回木橋旁找星禾，繼續分水體驗。"
		return
	var body:VBoxContainer=app.modal.get_meta("history_body")
	for child in body.get_children():body.remove_child(child);child.queue_free()
	var shelf_back:Callable=app.modal.get_meta("history_back",Callable()) if mode!="jinguashi" else Callable()
	var journal_back:=open.bind(app,"journal",Vector2i(-1,-1),shelf_back)
	if mode=="journal" and shelf_back.is_valid():
		var back:Button=app.button("返回書櫃",shelf_back)
		back.name="BookcaseBack"
		back.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
		body.add_child(back)
	if mode=="wangan_log":
		text(app,body,"潮水回來以前",22)
		text(app,body,"阿潮：「舊航記少了一頁。我只記得上面畫著一堵牆、一條彎彎的石堤。陪我找回來吧。」",16)
		var pages:=HBoxContainer.new()
		pages.add_theme_constant_override("separation",12)
		body.add_child(pages)
		var wall:=preload("res://assets/ui-life/wangan-wall-samples.png")
		var weir:=AtlasTexture.new()
		weir.atlas=preload("res://assets/ui-life/wangan-weir-tides.png")
		weir.region=Rect2(0,96,280,96)
		add_log_page(app,pages,wall,"花宅的兩種石頭",wangan_seen,"wangan",shelf_back)
		add_log_page(app,pages,weir,"石滬的漲潮與退潮",weir_progress==2,"wangan_weir",shelf_back)
		if log_done:
			text(app,body,"阿潮：「一堵牆替人擋風，一道石堤順著潮水。原來長輩要我記的，是看懂風和水以後，才知道能在哪裡靠岸。」",16)
			text(app,body,"✓ 望安航記已收錄｜阿潮與航記為遊戲原創。",15).name="WanganHarborLogComplete"
		elif not dock_ready:
			text(app,body,"修好風鈴渡口的碼頭後，就能在碼頭旁找到阿潮。",15)
		elif wangan_seen and weir_progress==2:
			var finish:Button=app.button("和阿潮寫下航記",func():app.session.perform(Wangan.LOG_ACTION,dock_cell))
			finish.name="WanganHarborLogFinish"
			finish.disabled=not near_achao
			body.add_child(finish)
			if not near_achao:text(app,body,"帶著兩項觀察回風鈴渡口找阿潮。",15)
		body.add_child(app.button("回到地方記憶",journal_back))
	elif mode=="wangan_weir":
		add_weir_page(app,body,weir_site,weir_progress,coast_time,journal_back)
	elif mode=="wangan":
		text(app,body,"花宅的兩種石頭",22)
		text(app,body,"望安中社村舊稱花宅。沿岸捕魚、農牧和帆船運輸，曾是聚落居民的主要生計。",16)
		var sample:=TextureRect.new()
		sample.texture=preload("res://assets/ui-life/wangan-wall-samples.png")
		sample.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
		sample.stretch_mode=TextureRect.STRETCH_SCALE
		sample.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
		sample.custom_minimum_size=Vector2(256,72)
		body.add_child(sample)
		text(app,body,"老屋會使用淺色、多孔的珊瑚礁岩，也會使用深色的玄武岩。從牆面看得出屋子如何取材於島上的環境。",16)
		if wangan_seen:
			text(app,body,"✓ 已收錄在地方記憶",17)
		elif wangan_near:
			text(app,body,"哪一組石料可以在花宅的老屋找到？",16)
			var options:=HBoxContainer.new()
			body.add_child(options)
			for option:Array in [[Wangan.ANSWER,"珊瑚礁岩和玄武岩"],["granite_marble","花崗岩和大理石"]]:
				var answer:String=option[0]
				var choice:Button=app.button(option[1],func():app.session.perform(Wangan.ACTION,wangan_site,answer))
				choice.name="WanganAnswer_"+answer
				options.add_child(choice)
		else:text(app,body,"到風鈴渡口的碼頭旁，可以查看花宅觀察牌並收錄這一頁。",16)
		var link:=LinkButton.new()
		link.text="文化部・望安花宅聚落"
		link.uri=Wangan.SOURCE_BOOK
		link.add_theme_color_override("font_color",Color("315840"))
		body.add_child(link)
		body.add_child(app.button("回到地方記憶",journal_back))
	elif mode=="sources":
		add_sources_page(app,body,journal_back)
	elif mode=="observe" and Story.CLUES.has(World.key(cell)):
		var clue:Dictionary=Story.CLUES[World.key(cell)]
		text(app,body,clue.title,22)
		text(app,body,clue.line,18)
		text(app,body,clue.lesson,16)
		var read:bool=World.key(cell) in record.seen
		text(app,body,"已記下 %d／3 處水路觀察"%record.seen.size(),16)
		var mark:Button=app.button("已記在手帳" if read else "記下這處水路",func():app.session.perform("memory_observe",cell))
		mark.name="MemoryObserve";mark.disabled=read or not close_enough or not repaired;body.add_child(mark)
		body.add_child(app.button("查看地方記憶",func():open(app)))
	elif mode=="play" and repaired and record.seen.size()==3 and not record.completed:
		text(app,body,Story.PERIOD+"・"+Story.DISCLAIMER,14)
		var voice:Label=text(app,body,Story.ROUNDS[int(record.round)],16)
		voice.name="MemoryVoice"
		var scene:=MemoryScene.new()
		scene.name="MemoryScene"
		body.add_child(scene)
		scene.configure(record.gates,World.HISTORY_MEMORY.DEMANDS[int(record.round)],int(record.round),app.sound.reduced_motion)
		scene.gate_changed.connect(func(which:String,level:int):app.session.perform("memory_gate",SERVICE,which+":"+str(level)))
		scene.flow_requested.connect(func():app.session.perform("memory_flow",SERVICE))
		for control in scene.find_children("*","Button",true,false):control.disabled=not close_enough
	else:
		var header:=HBoxContainer.new();body.add_child(header)
		header.add_child(Shell.picture(preload("res://scripts/lanyang_life_art.gd").portrait(),72))
		text(app,header,Story.AFTER if record.completed else "星禾：阿榆換下的分水板，還留著修補的痕跡。帶著鈴婆婆的筆記，沿水路看看吧。",17)
		if not repaired:text(app,body,"先完成水圳修復，再和星禾一起整理這段地方記憶。",18)
		elif record.completed:
			text(app,body,"✓ 三輪分水完成・地方記憶已收錄",20)
			text(app,body,"同一條水路，不同田塊的需要；協調和維修讓日子接得起來。",16)
			var place:Button=app.button("橋旁已有水路紀念牌" if plaque else "在木橋掛上水路紀念牌",func():app.session.perform("memory_plaque",SERVICE))
			place.name="MemoryPlaque";place.disabled=plaque or not close_enough;body.add_child(place)
		else:
			for key in Story.CLUES:text(app,body,("✓ " if key in record.seen else "○ ")+str(Story.CLUES[key].title),16)
			if record.seen.size()==3:
				var enter:Button=app.button("繼續往日分水" if int(record.round)>0 else "走進往日分水",func():open(app,"play"))
				enter.name="MemoryEnter";enter.disabled=not close_enough;body.add_child(enter)
			else:body.add_child(app.button("看地圖找三處水路",app._map_menu))
		var routes:=HBoxContainer.new();body.add_child(routes)
		routes.add_child(app.button("史實與改編說明",open.bind(app,"sources",Vector2i(-1,-1),shelf_back)))
		if record.completed:routes.add_child(app.button("再看分水場景",open_replay.bind(app,shelf_back)))
		var coast_stories:=HBoxContainer.new()
		coast_stories.add_theme_constant_override("separation",6)
		body.add_child(coast_stories)
		coast_stories.add_child(app.button("望安花宅・"+("已收錄" if wangan_seen else "觀察牌"),open.bind(app,"wangan",Vector2i(-1,-1),shelf_back)))
		coast_stories.add_child(app.button("望安石滬・"+("已收錄" if weir_progress==2 else "潮汐觀察"),open.bind(app,"wangan_weir",Vector2i(-1,-1),shelf_back)))
		var log_button:Button=app.button("望安航記・"+("已收錄" if log_done else "潮水回來以前"),open.bind(app,"wangan_log",Vector2i(-1,-1),shelf_back))
		log_button.name="WanganHarborLogJournal"
		coast_stories.add_child(log_button)
		if mining_visited:
			var mining:Button=app.button("金瓜石・從河砂到礦車",open.bind(app,"jinguashi",Vector2i(-1,-1),journal_back,true))
			mining.name="JinguashiHistoryJournal"
			body.add_child(mining)
	if is_instance_valid(app.modal_feedback):app.modal_feedback.text="Esc 回到島上・記憶可隨時再看" if close_enough or mode=="sources" else "可閱讀手帳；操作請回到蘭陽對應水口或木橋。"
	if mode in ["wangan","wangan_weir","wangan_log"] and is_instance_valid(app.modal_feedback):app.modal_feedback.text="Esc 回到島上・記憶可隨時再看"

static func add_mining_page(app,body:VBoxContainer,return_to:Callable,from_journal:bool)->void:
	body.add_theme_constant_override("separation",8)
	var pages:=[
		["清末・基隆河砂金","MineHistoryPanning","到西岸淘砂處，親手完成一盤淘洗，就能收錄這段歷史。",
			preload("res://scripts/gold_panning_art.gd").pan_texture(5)],
		["日治時期・礦山與運輸","MineHistoryHauling","從坑口裝上一車礦，沿軌道推到接駁站並卸下，就能收錄這段歷史。",
			preload("res://scripts/ore_route_art.gd").cart_texture(true)]
	]
	var index:Array[Control]=[]
	for page:Array in pages:
		var card:=PanelContainer.new()
		card.add_theme_stylebox_override("panel",Pixel.paper_style())
		body.add_child(card)
		index.append(card)
		var row:=HBoxContainer.new()
		row.add_theme_constant_override("separation",12)
		card.add_child(row)
		var side:=VBoxContainer.new()
		side.add_theme_constant_override("separation",2)
		row.add_child(side)
		var icon:=Shell.picture(page[3],64)
		icon.size_flags_vertical=Control.SIZE_EXPAND_FILL
		side.add_child(icon)
		var look:Button=app.button("看插畫",show_mine_chapter.bind(app,page[1]))
		look.name=page[1]+"Look"
		look.custom_minimum_size.y=30
		look.visible=false
		side.add_child(look)
		var lines:=VBoxContainer.new()
		lines.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		row.add_child(lines)
		text(app,lines,page[0],18)
		add_mine_beats(app,lines,page[1],true).visible=false
		text(app,lines,page[2],15).name=page[1]
	index.append(text(app,body,"遊戲改編｜西岸淘砂處、台車停靠點和工資是為山城玩法設計的。",14))
	app.modal.set_meta("mine_index",index)
	# Chapter view: the illustration and that chapter's timeline are shown, and switched, together.
	var chapter_view:=VBoxContainer.new()
	chapter_view.name="MineChapterView"
	chapter_view.add_theme_constant_override("separation",4)
	chapter_view.visible=false
	body.add_child(chapter_view)
	var picks:=HBoxContainer.new()
	picks.add_theme_constant_override("separation",6)
	chapter_view.add_child(picks)
	var group:=ButtonGroup.new()
	for key:String in MINE_ART:
		var pick:Button=app.button(MINE_ART[key][1],show_mine_chapter.bind(app,key))
		pick.name=key+"Pick"
		pick.toggle_mode=true
		pick.button_group=group
		pick.custom_minimum_size.y=34
		picks.add_child(pick)
	var caption:=text(app,picks,"遊戲場景插畫・波波的工作速寫",14)
	caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	caption.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	var close:Button=app.button("回到年表",show_mine_chapter.bind(app,""))
	close.name="MineChapterClose"
	close.custom_minimum_size.y=34
	picks.add_child(close)
	var art:=Shell.picture(null,144)
	art.name="MineChapterArt"
	chapter_view.add_child(art)
	for page:Array in pages:
		var chapter:=VBoxContainer.new()
		chapter.name=page[1]+"Chapter"
		chapter.add_theme_constant_override("separation",2)
		chapter.visible=false
		chapter_view.add_child(chapter)
		text(app,chapter,page[0],18)
		add_mine_beats(app,chapter,page[1],false)
	var links:=HFlowContainer.new()
	links.name="MineSourceLinks"
	links.add_theme_constant_override("h_separation",14)
	body.add_child(links)
	for pair:Array in [["年表出處・黃金博物館",MINE_TIMELINE_URL],
		["延伸閱讀・開山紀念展",MINE_EXHIBIT_URL],["文化資產局・水金九礦業遺址",MINE_HERITAGE_URL]]:
		var link:=LinkButton.new()
		link.text=pair[0]
		link.uri=pair[1]
		link.add_theme_color_override("font_color",Color("315840"))
		links.add_child(link)
	var back:Button=app.button("回到現場" if return_to.is_valid() and not from_journal else "回到地方記憶",
		return_to if return_to.is_valid() else func():open(app))
	back.name="JinguashiHistoryBack"
	back.size_flags_horizontal=Control.SIZE_SHRINK_END
	body.add_child(back)

## One chapter's dated timeline rows. The index card copy keeps the stable node names.
static func add_mine_beats(app,parent:Node,key:String,indexed:bool)->VBoxContainer:
	var beats:=VBoxContainer.new()
	if indexed:beats.name=key+"Beats"
	beats.add_theme_constant_override("separation",2)
	parent.add_child(beats)
	for beat:Array in MINE_BEATS[key]:
		var beat_row:=HBoxContainer.new()
		beat_row.add_theme_constant_override("separation",10)
		beats.add_child(beat_row)
		var prominent:bool=beat[0]=="1890"
		var date:Label=app.label(beat[0]+" 年",30 if prominent else 22)
		if indexed:date.name="%sDate%s"%[key,beat[0]]
		date.custom_minimum_size.x=104
		date.size_flags_horizontal=Control.SIZE_FILL
		date.autowrap_mode=TextServer.AUTOWRAP_OFF
		date.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
		date.add_theme_color_override("font_color",DATE_COLOR)
		beat_row.add_child(date)
		var event:=text(app,beat_row,beat[1],17)
		event.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		event.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	return beats

## Opens one recorded chapter's illustration ("" returns to the timeline index) and moves focus with it.
static func show_mine_chapter(app,key:String)->void:
	if not is_instance_valid(app.modal) or app.modal.get_meta("history_mode","")!="jinguashi":return
	var previous:String=app.modal.get_meta("mine_chapter","")
	app.modal.set_meta("mine_chapter",key)
	refresh(app)
	var shown:String=app.modal.get_meta("mine_chapter","")
	var scroll:=app.modal.find_child("ModalScroll",true,false) as ScrollContainer
	if scroll!=null:scroll.scroll_vertical=0
	var target:=app.modal.find_child(shown+"Pick" if not shown.is_empty() else previous+"Look",true,false) as Control
	if target!=null and target.is_visible_in_tree():target.grab_focus()
	app._layout_preview.call_deferred()

static func add_log_page(app,parent:Container,art:Texture2D,title:String,found:bool,mode:String,shelf_back:Callable)->void:
	var card:=PanelContainer.new()
	card.add_theme_stylebox_override("panel",Pixel.paper_style())
	card.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	parent.add_child(card)
	var contents:=VBoxContainer.new()
	card.add_child(contents)
	var preview:=TextureRect.new()
	preview.texture=art
	preview.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	preview.custom_minimum_size.y=72
	preview.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	contents.add_child(preview)
	contents.add_child(app.button(("✓ " if found else "○ ")+title,open.bind(app,mode,Vector2i(-1,-1),shelf_back)))

static func set_weir_picture(picture:AtlasTexture,caption:Label,high:bool)->void:
	picture.region=Rect2(0,0 if high else 96,280,96)
	caption.text="漲潮（水淹）｜水位抬高，魚群可以游進滬內。" if high else "退潮（水渴）｜石牆露出，有些魚仍留在滬房。"

static func add_weir_page(app,body:VBoxContainer,site:Vector2i,progress:int,coast_time:float,journal_back:Callable)->void:
	var coast_is_high:=World.WANGAN_COAST.high_tide(coast_time)
	text(app,body,"水淹與水渴",22)
	text(app,body,"望安東南岸的萬興滬以玄武岩砌成。這張遊戲示意圖用兩個水位來看石滬如何留住魚群。",15)
	if site.x>=0:
		var tide_row:=HBoxContainer.new()
		tide_row.add_theme_constant_override("separation",18)
		body.add_child(tide_row)
		var tide:=text(app,tide_row,"現場潮位偏高" if coast_is_high else "現場潮位偏低",15)
		tide.name="WanganWeirLiveTide"
		var tide_clock:=text(app,tide_row,World.WANGAN_COAST.next_tide_text(coast_time),15)
		tide_clock.name="WanganWeirTideClock"
	var picture:=TextureRect.new()
	var atlas:=AtlasTexture.new()
	atlas.atlas=preload("res://assets/ui-life/wangan-weir-tides.png")
	picture.texture=atlas
	picture.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	picture.custom_minimum_size.y=136
	picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	body.add_child(picture)
	var caption:=text(app,body,"",16)
	caption.name="WanganWeirCaption"
	set_weir_picture(atlas,caption,coast_is_high if site.x>=0 and progress<2 else progress<2)
	var controls:=HBoxContainer.new()
	body.add_child(controls)
	if progress==2:
		text(app,controls,"✓ 潮汐觀察已收錄",15)
		var high:Button=app.button("重看漲潮",set_weir_picture.bind(atlas,caption,true))
		high.name="WanganWeirReplayHigh"
		controls.add_child(high)
		var low:Button=app.button("重看退潮",set_weir_picture.bind(atlas,caption,false))
		low.name="WanganWeirReplayLow"
		controls.add_child(low)
	elif site.x>=0:
		var phase:="high" if progress==0 else "low"
		var observe:Button=app.button("記下漲潮" if progress==0 else "觀察退潮",func():app.session.perform(Wangan.WEIR_ACTION,site,phase))
		observe.name="WanganWeirObserve"
		observe.disabled=coast_is_high!=(progress==0)
		controls.add_child(observe)
		if observe.disabled:text(app,controls,"等潮水回來" if progress==0 else "等石滬露出水面",15)
	else:text(app,controls,"到風鈴渡口的石滬觀察牌或南岸觀潮點，就能開始記錄。",15)
	var sources:=HBoxContainer.new()
	sources.add_theme_constant_override("separation",14)
	body.add_child(sources)
	for pair:Array in [["萬興滬資料",Wangan.WEIR_SOURCE],["水垵石滬漁業",Wangan.SHUIAN_SOURCE],["文化部・澎湖石滬",Wangan.TIDE_SOURCE]]:
		var link:=LinkButton.new()
		link.text=pair[0]
		link.uri=pair[1]
		link.add_theme_color_override("font_color",Color("315840"))
		sources.add_child(link)
	body.add_child(app.button("回到地方記憶",journal_back))

static func open_replay(app,shelf_back:Callable=Callable())->void:
	open(app,"sources",Vector2i(-1,-1),shelf_back)
	var body:VBoxContainer=app.modal.get_meta("history_body")
	for child in body.get_children():body.remove_child(child);child.queue_free()
	if is_instance_valid(app.modal_feedback):app.modal_feedback.text="自由重看・不改世界進度，不發放額外獎勵・Esc 離開"
	var scene:=MemoryScene.new();scene.name="MemoryReplay";body.add_child(scene)
	var replay:={"gates":[0,0],"round":0}
	scene.configure(replay.gates,[4,4,4],0,app.sound.reduced_motion)
	scene.gate_changed.connect(func(which:String,level:int):
		replay.gates[0 if which=="a" else 1]=level
		scene.configure(replay.gates,World.HISTORY_MEMORY.DEMANDS[replay.round],replay.round,app.sound.reduced_motion))
	scene.flow_requested.connect(func():
		var a:int=replay.gates[0]*2;var b:int=mini(12-a,replay.gates[1]*2)
		if [a,b,12-a-b]==World.HISTORY_MEMORY.DEMANDS[replay.round]:replay.round=(replay.round+1)%3;replay.gates=[0,0]
		scene.configure(replay.gates,World.HISTORY_MEMORY.DEMANDS[replay.round],replay.round,app.sound.reduced_motion))
	body.add_child(app.button("回到地方記憶",open.bind(app,"journal",Vector2i(-1,-1),shelf_back)))

const BEATS:=[
	["1813・兩圳合一","1813年，長慶源圳與邱吳成圳合併，改用「萬長春」圳號。"],
	["共用水源","文化資產資料記載，兩圳共用水源，合併涉及旱時競水及維修成本。"],
	["日常的水路","二結圳也曾是附近居民洗滌、育苗等日常生活的場所。"]
]

## Builds the whole sources page into `body`. `back` is invoked by the return button.
static func add_sources_page(app,body:VBoxContainer,back:Callable)->void:
	var page:=body
	page.add_theme_constant_override("separation",7)
	var heading:=HBoxContainer.new()
	page.add_child(heading)
	_label(app,heading,Story.PERIOD,18)
	var credit:=_label(app,heading,"遊戲插圖 · 非歷史復原圖",13)
	credit.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT

	var scene:=SourceScene.new()
	scene.name="HistorySourceScene"
	scene.motion=not app.sound.reduced_motion
	page.add_child(scene)

	var card:=PanelContainer.new()
	card.add_theme_stylebox_override("panel",Pixel.paper_style())
	page.add_child(card)
	var row:=HBoxContainer.new()
	row.add_theme_constant_override("separation",10)
	card.add_child(row)
	row.add_child(Shell.picture(preload("res://scripts/lanyang_life_art.gd").portrait(),64))
	var lines:=VBoxContainer.new()
	lines.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	row.add_child(lines)
	_label(app,lines,"星禾・遊戲旁白（原創角色）",14).name="HistorySourceNarrator"
	var beat_title:=_label(app,lines,"",18)
	beat_title.name="HistorySourceBeatTitle"
	var beat_line:=_label(app,lines,"",16)
	beat_line.name="HistorySourceBeatLine"

	var state:={"index":0}
	var beat_buttons:Array[Button]=[]
	var step:Button=app.button("下一段",func():pass)
	step.name="HistorySourceNext"
	var show_beat:=func(index:int,restart:bool)->void:
		state.index=index
		beat_title.text="%d／%d　%s"%[index+1,BEATS.size(),BEATS[index][0]]
		beat_line.text=BEATS[index][1]
		for i in beat_buttons.size():
			beat_buttons[i].text=("● " if i==index else "○ ")+BEATS[i][0]
		step.text="重播" if index==BEATS.size()-1 else "下一段 ▶"
		if restart:scene.replay()
	var beats:=HBoxContainer.new()
	beats.name="HistorySourceBeats"
	beats.add_theme_constant_override("separation",6)
	page.add_child(beats)
	for i in BEATS.size():
		var pick:Button=app.button(BEATS[i][0],func():show_beat.call(i,false))
		pick.name="HistorySourceBeat%d"%i
		pick.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		pick.clip_text=true
		beats.add_child(pick)
		beat_buttons.append(pick)
	step.pressed.connect(func():
		var last:bool=state.index==BEATS.size()-1
		show_beat.call(0 if last else state.index+1,last))
	step.size_flags_horizontal=Control.SIZE_SHRINK_END
	beats.add_child(step)
	show_beat.call(0,false)

	# Full source text, collapsed by default; text and link are unchanged.
	var actions:=HBoxContainer.new()
	actions.add_theme_constant_override("separation",6)
	page.add_child(actions)
	var toggle:Button=app.button("▸ 史料全文",func():pass)
	toggle.name="HistorySourceFullToggle"
	toggle.toggle_mode=true
	toggle.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	actions.add_child(toggle)
	actions.add_child(app.button("回到記憶頁",back))
	var full:=VBoxContainer.new()
	full.name="HistorySourceFull"
	full.visible=false
	full.add_theme_constant_override("separation",8)
	page.add_child(full)
	_label(app,full,Story.FACTS,18)
	_label(app,full,Story.CONTEXT,15)
	_label(app,full,Story.DISCLAIMER+" 三輪配水數字是遊戲規則，不是歷史配水紀錄。",15)
	_label(app,full,"史料來源："+Story.SOURCE_NAME+"\n查核：2026-11-13",15)
	var link:=LinkButton.new()
	link.text="開啟文化資產資料"
	link.uri=Story.SOURCE_URL
	for state_color in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:link.add_theme_color_override(state_color,Color("315840"))
	link.custom_minimum_size.y=42
	full.add_child(link)
	toggle.toggled.connect(func(open:bool):
		full.visible=open
		toggle.text=("▾ " if open else "▸ ")+"史料全文"
		app._layout_preview.call_deferred())

static func _label(app,parent:Node,line:String,extent:int)->Label:
	var label:Label=app.label(line,extent)
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	parent.add_child(label)
	return label
