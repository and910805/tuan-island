extends RefCounted
const World=preload("res://scripts/world.gd")
const Story=preload("res://scripts/history_story.gd")
const Pixel=preload("res://scripts/inventory_pixel_theme.gd")
const Shell=preload("res://scripts/life_ui_shell.gd")
const MemoryScene=preload("res://scripts/history_memory_scene.gd")
const Wangan=World.WANGAN_MEMORY
const SERVICE:=Vector2i(33,29)
const MINE_TIMELINE_URL:="https://www.gep.ntpc.gov.tw/xmdoc/cont?xsmsid=0Q018377887368898201"
const MINE_EXHIBIT_URL:="https://tcmb.culture.tw/zh-tw/detail?id=561386&indexCode=Culture_Event"
const MINE_PANNING_TEXT:="1890 年代，基隆河發現砂金後掀起淘金熱。1894 年，採金者發現大金瓜露頭，金瓜石由此得名。"
const MINE_HAULING_TEXT:="1897 年，金瓜石開始有規模地探礦與採礦。1933 年，礦業公司在水湳洞建選礦設施，並修築通往八斗子的運礦輕便鐵路。"

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

static func open(app,mode:String="journal",cell:Vector2i=Vector2i(-1,-1),return_to:Callable=Callable())->void:
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
	if mode=="jinguashi":
		app.modal.set_meta("suppress_world_prompts",true)
		add_mining_page(app,body,return_to)
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
		panning.text=MINE_PANNING_TEXT if fieldwork.get("panned",false) else "到西岸淘砂處，親手完成一盤淘洗，就能收錄這段歷史。"
		hauling.text=MINE_HAULING_TEXT if fieldwork.get("delivered",false) else "從坑口裝上一車礦，沿軌道推到接駁站並卸下，就能收錄這段歷史。"
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
		add_log_page(app,pages,wall,"花宅的兩種石頭",wangan_seen,"wangan")
		add_log_page(app,pages,weir,"石滬的漲潮與退潮",weir_progress==2,"wangan_weir")
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
		body.add_child(app.button("回到地方記憶",func():open(app)))
	elif mode=="wangan_weir":
		add_weir_page(app,body,weir_site,weir_progress,coast_time)
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
		body.add_child(app.button("回到地方記憶",func():open(app)))
	elif mode=="sources":
		text(app,body,Story.PERIOD,20)
		text(app,body,Story.FACTS,18)
		text(app,body,Story.CONTEXT,15)
		text(app,body,Story.DISCLAIMER+" 三輪配水數字是遊戲規則，不是歷史配水紀錄。",15)
		text(app,body,"史料來源："+Story.SOURCE_NAME+"\n查核：2026-11-13",15)
		var link:=LinkButton.new()
		link.text="開啟文化資產資料"
		link.uri=Story.SOURCE_URL
		for state in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:link.add_theme_color_override(state,Color("315840"))
		link.custom_minimum_size.y=42
		body.add_child(link)
		body.add_child(app.button("回到記憶頁",func():open(app)))
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
		routes.add_child(app.button("史實與改編說明",func():open(app,"sources")))
		if record.completed:routes.add_child(app.button("再看分水場景",func():open_replay(app)))
		body.add_child(app.button("望安花宅・"+("已收錄" if wangan_seen else "觀察牌"),func():open(app,"wangan")))
		body.add_child(app.button("望安石滬・"+("已收錄" if weir_progress==2 else "潮汐觀察"),func():open(app,"wangan_weir")))
		var log_button:Button=app.button("望安航記・"+("已收錄" if log_done else "潮水回來以前"),func():open(app,"wangan_log"))
		log_button.name="WanganHarborLogJournal"
		body.add_child(log_button)
		if mining_visited:
			var mining:Button=app.button("金瓜石・從河砂到礦車",func():open(app,"jinguashi"))
			mining.name="JinguashiHistoryJournal"
			body.add_child(mining)
	if is_instance_valid(app.modal_feedback):app.modal_feedback.text="Esc 回到島上・記憶可隨時再看" if close_enough or mode=="sources" else "可閱讀手帳；操作請回到蘭陽對應水口或木橋。"
	if mode in ["wangan","wangan_weir","wangan_log"] and is_instance_valid(app.modal_feedback):app.modal_feedback.text="Esc 回到島上・記憶可隨時再看"

static func add_mining_page(app,body:VBoxContainer,return_to:Callable)->void:
	body.add_theme_constant_override("separation",8)
	var pages:=[
		["清末・基隆河砂金","MineHistoryPanning",
			preload("res://scripts/gold_panning_art.gd").pan_texture(5)],
		["日治時期・礦山與運輸","MineHistoryHauling",
			preload("res://scripts/ore_route_art.gd").cart_texture(true)]
	]
	for page:Array in pages:
		var card:=PanelContainer.new()
		card.add_theme_stylebox_override("panel",Pixel.paper_style())
		body.add_child(card)
		var row:=HBoxContainer.new()
		row.add_theme_constant_override("separation",12)
		card.add_child(row)
		row.add_child(Shell.picture(page[2],64))
		var lines:=VBoxContainer.new()
		lines.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		row.add_child(lines)
		text(app,lines,page[0],18)
		text(app,lines,"",15).name=page[1]
	text(app,body,"遊戲改編｜西岸淘砂處、台車停靠點和工資是為這座山城設計的玩法。",14)
	for pair:Array in [["黃金博物館・歷史沿革",MINE_TIMELINE_URL],["國家文化記憶庫・開山 120 週年紀念展",MINE_EXHIBIT_URL]]:
		var link:=LinkButton.new()
		link.text=pair[0]
		link.uri=pair[1]
		link.add_theme_color_override("font_color",Color("315840"))
		body.add_child(link)
	var back:Button=app.button("回到現場" if return_to.is_valid() else "回到地方記憶",
		return_to if return_to.is_valid() else func():open(app))
	back.name="JinguashiHistoryBack"
	back.size_flags_horizontal=Control.SIZE_SHRINK_END
	body.add_child(back)

static func add_log_page(app,parent:Container,art:Texture2D,title:String,found:bool,mode:String)->void:
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
	contents.add_child(app.button(("✓ " if found else "○ ")+title,func():open(app,mode)))

static func set_weir_picture(picture:AtlasTexture,caption:Label,high:bool)->void:
	picture.region=Rect2(0,0 if high else 96,280,96)
	caption.text="漲潮（水淹）｜水位抬高，魚群可以游進滬內。" if high else "退潮（水渴）｜石牆露出，有些魚仍留在滬房。"

static func add_weir_page(app,body:VBoxContainer,site:Vector2i,progress:int,coast_time:float)->void:
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
	body.add_child(app.button("回到地方記憶",func():open(app)))

static func open_replay(app)->void:
	open(app,"sources")
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
	body.add_child(app.button("回到地方記憶",func():open(app)))
