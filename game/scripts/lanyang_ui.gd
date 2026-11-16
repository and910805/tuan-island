extends RefCounted
const World=preload("res://scripts/world.gd")
const Shell=preload("res://scripts/life_ui_shell.gd")
const Items=preload("res://scripts/inventory_item_art.gd")
const Pixel=preload("res://scripts/inventory_pixel_theme.gd")

static func open(app,mode:String="canal",cell:Vector2i=Vector2i(-1,-1))->void:
	if str(app.session.snapshot.get("region_id","home"))!="lanyang":return
	var body:VBoxContainer=app._open_modal("星禾的水圳手記" if mode!="nursery" else "星禾的育苗盤")
	app.modal.theme=Pixel.make(app.modal.theme if app.modal.theme else app.hud.theme)
	app.modal.add_theme_stylebox_override("panel",Pixel.frame_style())
	app.modal.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	app.modal.set_meta("life_modal_layout","lanyang_garden")
	app.modal.set_meta("garden_body",body)
	app.modal.set_meta("garden_mode",mode)
	app.modal.set_meta("garden_cell",cell)
	refresh(app)

static func words(app,text:String,extent:int=16)->Label:
	var result:Label=app.label(text,extent)
	result.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	return result

static func costs(app,parent:Node,cost:Dictionary,bag:Dictionary,donations:Dictionary={})->void:
	var row:=HBoxContainer.new()
	row.add_theme_constant_override("separation",18)
	parent.add_child(row)
	for item in cost:
		var tile:=VBoxContainer.new()
		tile.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		row.add_child(tile)
		tile.add_child(Shell.picture(Items.icon(item),40))
		var required:=maxi(0,int(cost[item])-int(donations.get(item,0)))
		tile.add_child(words(app,World.NAMES[item]+" %d／%d"%[int(bag.get(item,0)),required],14))

static func refresh(app)->void:
	if not is_instance_valid(app.modal) or not app.modal.has_meta("garden_body"):return
	var s:Dictionary=app.session.snapshot
	var person:Dictionary=s.get("players",{}).get(app.session.own_id,{})
	if person.is_empty():return
	var life:Dictionary=s.get("lanyang_life",World.LANYANG_LIFE.fresh())
	var job:Dictionary=life.get("own_job",{})
	var remaining:=maxi(0,ceili(float(job.get("ready",0))-float(s.time)))
	var timer:Label=app.modal.find_child("NurseryTime",true,false) as Label
	if timer:timer.text="嫩芽正慢慢長大・還要 %d 秒世界時間"%remaining
	var mode:String=app.modal.get_meta("garden_mode","canal")
	var target:Vector2i=app.modal.get_meta("garden_cell",World.LANYANG_LIFE.SERVICE) if mode=="clear" else World.LANYANG_LIFE.SERVICE
	var near:=Vector2(person.x,person.y).distance_to(Vector2(target)+Vector2(0.5,0.5))<=3.2
	var bag:Dictionary=person.inventory
	var ready_to_report:bool=person.get("greenhouse_glass_crafted",false) and World.CROPS.has(person.get("greenhouse_cross_season_crop",""))
	var reported:bool=person.get("greenhouse_reported",false)
	var fingerprint:=JSON.stringify([ready_to_report,reported,person.get("greenhouse_cross_season_crop",""),mode,life.get("cleared",{}),life.get("donations",{}),life.get("repaired",false),job,remaining==0,near,bag,s.get("resident_memories",[]),s.get("resident_participation",{}),World.LANYANG_REVISIT.unlocked(s)])
	if app.modal.get_meta("garden_fingerprint","")==fingerprint:return
	app.modal.set_meta("garden_fingerprint",fingerprint)
	var body:VBoxContainer=app.modal.get_meta("garden_body")
	for child in body.get_children():body.remove_child(child);child.queue_free()
	var greeting:=HBoxContainer.new()
	greeting.add_theme_constant_override("separation",14)
	body.add_child(greeting)
	var portrait:Texture2D=preload("res://scripts/lanyang_life_art.gd").portrait()
	greeting.add_child(Shell.picture(portrait,80))
	var line:="米露說，你們讓渡口又開飯了。這條圳也等著大家一起照顧。先把三處枯枝清開，再補好閘門吧。"
	if life.get("repaired",false):line="水走順了，苗才站得穩。留一棵樹苗給下一輪吧，我陪你把它育成三棵，讓林場一直有新芽。"
	elif life.get("cleared",{}).size()==3:line="水路清出來了！再補好這道木閘，就能讓田裡和育苗盤都有穩定的水。"
	if mode=="clear":line="把卡住的枯枝挪開，讓水往田裡走吧。還有 %d 處水口等著我們。"%(3-life.get("cleared",{}).size())
	var quote:Label=words(app,"星禾　「"+line+"」")
	quote.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	greeting.add_child(quote)
	if mode=="canal":app._resident_story_dialogue(body,"xinghe")
	var paper:=PanelContainer.new()
	paper.add_theme_stylebox_override("panel",Pixel.paper_style())
	body.add_child(paper)
	var note:=VBoxContainer.new()
	note.add_theme_constant_override("separation",8)
	paper.add_child(note)
	if mode=="canal" and ready_to_report:
		note.add_child(words(app,"冬天也開花",18))
		if reported:
			var crop_id:String=person.get("greenhouse_cross_season_crop","")
			note.add_child(words(app,"星禾：「我把%s記下來了。明年冬天，我們也有東西可盼了。」" % World.NAMES.get(crop_id,crop_id),15))
			note.add_child(words(app,"已解鎖圖樣：溫室花架。到家園工坊的「家具」建造。",14))
		else:
			var report:Button=app.button("和星禾分享跨季收成",func():app.session.perform("greenhouse_report",World.LANYANG_LIFE.SERVICE))
			report.name="GreenhouseReport"
			report.disabled=not near
			note.add_child(report)
	if mode=="nursery":
		if not life.get("repaired",false):
			note.add_child(words(app,"先修好水圳，星禾才有穩定水源照顧育苗盤。"))
		elif not job.is_empty():
			note.add_child(Shell.picture(Items.icon("sapling"),48))
			if remaining>0:
				timer=words(app,"嫩芽正慢慢長大・還要 %d 秒世界時間"%remaining)
				timer.name="NurseryTime"
				note.add_child(timer)
				note.add_child(words(app,"可以先回家。世界有人在線時，這盤苗會繼續成長；不會過期。",14))
			else:
				note.add_child(words(app,"三棵樹苗可以搬回自己的林場了。",18))
				var claim:Button=app.button("領回樹苗 ×3",func():app.session.perform("nursery_claim",World.LANYANG_LIFE.SERVICE))
				claim.name="NurseryClaim";claim.disabled=not near;note.add_child(claim)
		else:
			note.add_child(words(app,"留一份種苗，養出下一片人工林",18))
			costs(app,note,World.LANYANG_LIFE.NURSERY_COST,bag)
			note.add_child(words(app,"投入以上材料，60 秒世界時間後得到樹苗 ×3。每人一盤，材料與收成各自保存。",14))
			var enough:=true
			for item in World.LANYANG_LIFE.NURSERY_COST:
				if int(bag.get(item,0))<int(World.LANYANG_LIFE.NURSERY_COST[item]):enough=false
			var start:Button=app.button("交給星禾照顧",func():app.session.perform("nursery_start",World.LANYANG_LIFE.SERVICE))
			start.name="NurseryStart";start.disabled=not near or not enough;note.add_child(start)
	elif mode=="clear":
		var cleared:bool=life.get("cleared",{}).has(World.key(target))
		note.add_child(Shell.picture(Items.icon("wood"),40))
		note.add_child(words(app,"這段水路清好了。" if cleared else "枯枝擠在水口，把它們挪到岸邊吧。",18))
		note.add_child(words(app,"清理進度由大家共用，不扣背包材料。",14))
		if not cleared:
			var clear:Button=app.button("清開這處枯枝",func():app.session.perform("lanyang_clear",target))
			clear.name="ClearBlockage";clear.disabled=not near;note.add_child(clear)
	else:
		var count:int=life.get("cleared",{}).size()
		note.add_child(words(app,"清理水路 %d／3　→　補好閘門　→　育苗與林場"%count,18))
		if life.get("repaired",false):
			note.add_child(words(app,"水圳修好了！蘭陽河水泵每輪可抽水 12，原本為 8。",18))
			note.add_child(words(app,"既有水管和灑水器可繼續使用。下一步把樹苗種進人工林，長成後送鋸木台做木板。",14))
			# 第 40 章：配水紀念牌設好之後，星禾邀大家在放晴的日子回來調整分流。
			if World.LANYANG_REVISIT.unlocked(s):
				var revisit:Button=app.button("回訪・旱日分流",func():preload("res://scripts/lanyang_revisit_ui.gd").open(app,World.LANYANG_REVISIT.SERVICE))
				revisit.name="RevisitOpen"
				revisit.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
				note.add_child(revisit)
		elif count<3:
			note.add_child(words(app,"沿著水圳找三團枯枝，靠近後按互動鍵清理。M 地圖上的葉片標記會帶路。"))
		else:
			costs(app,note,World.LANYANG_LIFE.REPAIR_COST,bag,life.get("donations",{}))
			note.add_child(words(app,"左邊是隨身數量，右邊是公共工程還缺的數量。捐入只取缺少部分，朋友也能接著補。木板要先用鋸木台加工。",14))
			var donate:Button=app.button("捐入這次帶來的材料",func():app.session.perform("lanyang_donate",World.LANYANG_LIFE.SERVICE))
			var can_contribute:=false
			for item in World.LANYANG_LIFE.REPAIR_COST:
				if int(bag.get(item,0))>0 and int(life.get("donations",{}).get(item,0))<int(World.LANYANG_LIFE.REPAIR_COST[item]):can_contribute=true
			donate.name="CanalDonate";donate.disabled=not near or not can_contribute;note.add_child(donate)
			if not can_contribute:note.add_child(words(app,"帶一些還缺的材料回來，就能接著修閘門。",14))
	if is_instance_valid(app.modal_feedback):
		app.modal_feedback.text=("請先走到這處水口。" if mode=="clear" else "請先走到木橋旁找星禾，再交材料或領苗。") if not near else "Esc 回到島上"
	if mode=="clear":return
	var routes:=HBoxContainer.new()
	body.add_child(routes)
	if mode!="canal":routes.add_child(app.button("水圳手記",func():open(app,"canal")))
	if mode=="canal":
		var chat:Button=app.button("和星禾聊聊",app._resident_bond_menu.bind("xinghe"))
		chat.name="BondOpen"
		routes.add_child(chat)
		routes.add_child(app.button("看看育苗盤",func():open(app,"nursery")))
	routes.add_child(app.button("看地圖找水口",app._map_menu))
	if mode=="canal" and life.get("repaired",false):routes.add_child(app.button("地方記憶・舊分水板",app._history_menu))
