extends RefCounted
const World=preload("res://scripts/world.gd")
const Story=preload("res://scripts/history_story.gd")
const Pixel=preload("res://scripts/inventory_pixel_theme.gd")
const Shell=preload("res://scripts/life_ui_shell.gd")
const MemoryScene=preload("res://scripts/history_memory_scene.gd")
const SERVICE:=Vector2i(33,29)

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

static func open(app,mode:String="journal",cell:Vector2i=Vector2i(-1,-1))->void:
	var body:VBoxContainer=app._open_modal("地方記憶・"+Story.TITLE)
	app.modal.theme=Pixel.make(app.hud.theme)
	app.modal.add_theme_stylebox_override("panel",Pixel.frame_style())
	app.modal.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	app.modal.set_meta("life_modal_layout","history_memory")
	app.modal.set_meta("history_body",body)
	app.modal.set_meta("history_mode",mode)
	app.modal.set_meta("history_cell",cell)
	refresh(app)
	app._layout_preview.call_deferred()

static func refresh(app)->void:
	if not is_instance_valid(app.modal) or not app.modal.has_meta("history_body"):return
	var record:=own(app)
	var s:Dictionary=app.session.snapshot
	var mode:String=app.modal.get_meta("history_mode")
	var cell:Vector2i=app.modal.get_meta("history_cell")
	var close_enough:=near(app,cell if mode=="observe" else SERVICE)
	var repaired:bool=s.get("lanyang_life",{}).get("repaired",false)
	var plaque:bool=s.get("history_memory",{}).get("plaque",false)
	var fingerprint:=JSON.stringify([mode,record,close_enough,repaired,plaque])
	if app.modal.get_meta("history_fingerprint","")==fingerprint:return
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
	if mode=="sources":
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
	if is_instance_valid(app.modal_feedback):app.modal_feedback.text="Esc 回到島上・記憶可隨時再看" if close_enough or mode=="sources" else "可閱讀手帳；操作請回到蘭陽對應水口或木橋。"

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
