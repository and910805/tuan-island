extends RefCounted
## 第三章「花開之前，先留下種子」田尾合作花圃介面（W4）。API 比照 tea_ceramics_ui.gd：
## unlocked(snapshot)、interaction_points(region)、open(app,site,cell)、refresh(app)、
## journal(app,parent,snapshot)，另有 layout(app,bounds)、counter_link(app,content)、
## next_step(snapshot,own_id)。所有數值一律取自 FlowerNursery（flower_nursery.gd）。
##
## ── main.gd 需要的接線（由 flower_exec_scene 加入；本檔不改 main.gd）──
## 對照既有茶陶接線（main.gd:15、628、916、1013、1628、1668-1672、1755-1760、1794、2014-2023）：
##  1. 常數：        const FlowerUI=preload("res://scripts/flower_nursery_ui.gd")
##  2. _state_changed（TeaUI.refresh(self) 之後）：      FlowerUI.refresh(self)
##  3. _refresh_hud（village_art_preview 分支 TeaUI.refresh(self) 之後）：FlowerUI.refresh(self)
##  4. _interact：   points.merge(TeaUI.interaction_points(region)) 之後加
##                   points.merge(FlowerUI.interaction_points(region))
##                   （注意 home 分支會用 points={...} 重設；田尾互動點只在 tianwei 出現，home 的信件走第 7 項）
##     closest 分派（tea: 分派之後）：
##                   if closest.begins_with("flower:"):FlowerUI.open(self,closest.trim_prefix("flower:"));return
##  5. _layout_preview 的 match（"tea_ceramics" 分支旁）：
##                   "flower_nursery":FlowerUI.layout(self,bounds)
##  6. 第二章手帳下的第三章連結（_add_tea_chapter_link 之後，同樣在 _chapter_menu 與兩處 refresh 呼叫）：
##                   FlowerUI.chapter_link(self)   # 會加上按鈕 "ChapterFlowerJournal"
##  7. 小栗攤位：_shop() 在 _add_tea_counter_link(content) 之後加 FlowerUI.counter_link(self,content)
##                   （按鈕 "XiaoliFlowerLetter"，開啟 site "letter"）
##  8. _journal：region=="tianwei" 時 FlowerUI.open(self,"journal")（比照 maokong/yingge）
##  9. HUD 下一步：FlowerUI.next_step(s,session.own_id) 回傳 FlowerNursery.guidance() 的字典
##     {phase,title,detail,region,site,cell}；在 tianwei 時可取代 objective.text。
## 10. 舊版 main.gd:1997 非預覽攤位清單：花卉種子以 FlowerUI.stall_locked(snapshot,kind) 判斷鎖定，
##     顯示 FlowerUI.STALL_LOCK_REASON，不提供購買按鈕。
## 送出動作一律用 app.session.perform(action,cell,extra)（與 tea_ceramics_ui 相同）。

const Flower=preload("res://scripts/flower_nursery.gd")
const Tea=preload("res://scripts/tea_ceramics.gd")
const Weather=preload("res://scripts/weather.gd")
const FlowerArt=preload("res://scripts/flower_art.gd")
const SceneArt=preload("res://scripts/flower_scene_art.gd")
const Items=preload("res://scripts/inventory_item_art.gd")
const Pixel=preload("res://scripts/inventory_pixel_theme.gd")
const Shell=preload("res://scripts/life_ui_shell.gd")
const LifeTheme=preload("res://scripts/life_ui_theme.gd")
const Lanyang=preload("res://scripts/lanyang_life_art.gd")
const Helpers=preload("res://scripts/freight_ui.gd")
const Folio=preload("res://scripts/kitchen_folio_art.gd")
const Resident=preload("res://scripts/flower_resident_art.gd")
const LAYOUT:="flower_nursery"
## Open field-journal art (448x224) drawn at an exact 2x; only the page middle
## band stretches vertically so corners, binding ends and bookmark stay crisp.
const BOOK_ASSET:="res://assets/ui-life/book.png"
const BOOK_SIZE:=Vector2(896,512)
const BOOK_LEFT_PAGE:=268
const BOOK_SPINE:=50
const TITLES:={"letter":"小栗的花圃介紹信","farmer":"田尾合作花圃・阿蕾","seed":"留種台","dye":"染色桌","market":"田尾花卉市集","garden":"公共花園","xinghe":"向星禾回報","journal":"第三章・田尾花圃手帳"}
const FARMER_NAME:="阿蕾"
const STALL_LOCK_REASON:=Flower.HOME_SEED_MESSAGE
const NEAR_REASON:="請靠近工作點再操作。"
const INTRO_REASON:="先向花農阿蕾報到。"
const SEED_NOTE:="種子不會被拿走"
## Width and maximum height per site. Heights shrink to the content (see layout),
## so short dialogues never leave an empty beige bottom; the journal is the book.
const SIZES:={"letter":Vector2(700,440),"farmer":Vector2(700,440),"xinghe":Vector2(700,440),"seed":Vector2(660,560),"dye":Vector2(620,520),"market":Vector2(900,592),"garden":Vector2(720,592),"journal":BOOK_SIZE}
const PHASE_LABELS:={"locked":"完成第二章茶陶比較","letter":"收下小栗的介紹信","travel":"轉乘前往田尾","intro":"向阿蕾報到","plant":"在育苗床種下三種花","harvest":"採收三種花","save":"替三種花各留一包種子","ship":"交付花圃訂單","garden":"合力完成公共花園","report":"向星禾回報","complete":"第三章田尾段落完成"}
## Short stepping-stone names for the journal route and story bookmarks.
const PHASE_SHORT:={"letter":"收信","travel":"轉乘","intro":"報到","plant":"種花","harvest":"採收","save":"留種","ship":"交貨","garden":"花園","report":"回報","complete":"完成","opening":"開園"}
const ROUTE:=["letter","travel","intro","plant","harvest","save","ship","garden","report"]
const INK:=Color("3d422d")
const BROWN:=Color("7a4e2b")
const FADED:=Color("8f7a5e")
const SEASON_DORMANT:="季節休眠尚未開放"
const CREAM:=Color("f9e8be")
const GOLD:=Color("f0bb72")
const OK_TINT:=Color("3e664b")
const WARN_TINT:=Color("9c4b32")

# ── 純資料（測試與 HUD 共用） ──────────────────────────────

static func unlocked(snapshot:Dictionary)->bool:
	return bool(snapshot.get("tea_ceramics",{}).get("own_record",{}).get("comparison_complete",false))

static func own_record(snapshot:Dictionary)->Dictionary:
	var record=snapshot.get("flower_nursery",{}).get("own",{}).get("own_record",{})
	if not (record is Dictionary) or record.is_empty():return Flower.FRESH.duplicate(true)
	return record

static func garden(snapshot:Dictionary)->Dictionary:
	var shared=snapshot.get("flower_nursery",{}).get("garden",{})
	if not (shared is Dictionary) or shared.is_empty():
		return {"given":Flower.garden_fresh().given,"complete":false,"completed_at":-1.0,"contributor_count":0}
	return shared

static func own_given(snapshot:Dictionary)->int:
	return int(snapshot.get("flower_nursery",{}).get("own",{}).get("own_given",0))

static func stall_locked(snapshot:Dictionary,kind:String)->bool:
	return kind in Flower.FLOWERS and not bool(own_record(snapshot).get("complete",false))

## Client-side mirror of the server state shape so FlowerNursery.guidance() (pure)
## can run on a snapshot. Only the recipient's own record/tea record/travel book exist here.
static func client_state(snapshot:Dictionary,own_id:String)->Dictionary:
	var actor:Dictionary=snapshot.get("players",{}).get(own_id,{}).duplicate(true)
	var shared:=garden(snapshot)
	var tea_record:Dictionary=snapshot.get("tea_ceramics",{}).get("own_record",{})
	return {
		"time":snapshot.get("time",0),
		"players":{own_id:actor},
		"tea_ceramics":{"players":{own_id:tea_record} if not tea_record.is_empty() else {}},
		"flower_nursery":{"players":{own_id:own_record(snapshot)} if snapshot.get("flower_nursery",{}).get("own",{}).has("own_record") else {},
			"garden":{"given":shared.get("given",{}).duplicate(),"contributors":{},"complete":bool(shared.get("complete",false)),"completed_at":shared.get("completed_at",-1.0)}},
	}

static func next_step(snapshot:Dictionary,own_id:String)->Dictionary:
	if not snapshot.get("players",{}).has(own_id):return {}
	return Flower.guidance(client_state(snapshot,own_id),own_id)

static func phase(snapshot:Dictionary,own_id:String)->String:
	if not snapshot.get("players",{}).has(own_id):return "locked"
	return Flower.phase(client_state(snapshot,own_id),own_id)

static func interaction_points(region:String)->Dictionary:
	var points:Dictionary={}
	if region!=Flower.REGION:return points
	for site in ["farmer","seed","dye","market","garden","xinghe"]:
		points["flower:"+site]=Vector2(site_cell(site))+Vector2(0.5,0.5)
	return points

static func site_cell(site:String)->Vector2i:
	match site:
		"letter":return Flower.RECEIVER_HOME
		"farmer":return Flower.FARMER
		"seed":return Flower.SEED_TABLE
		"dye":return Flower.DYE_TABLE
		"market":return Flower.MARKET
		"garden":return Flower.GARDEN_CELL
		"xinghe":return Flower.XINGHE
	return Vector2i(-1,-1)

static func site_region(site:String)->String:
	if site=="letter":return "home"
	if site=="journal":return ""
	return Flower.REGION

static func item_icon(id:String)->Texture2D:
	if FlowerArt.has_item(id):return FlowerArt.item_texture(id)
	return Items.icon(id)

static func item_name(id:String)->String:
	if Flower.NAMES.has(id):return Flower.NAMES[id]
	return {"flour":"麵粉","coins":"鈴幣"}.get(id,id)

static func sugar_left(record:Dictionary,now:float)->int:
	var today:=int(Weather.day_index(now))
	if int(record.get("sugar_day",-1))!=today:return Flower.SUGAR_DAILY
	return maxi(0,Flower.SUGAR_DAILY-int(record.get("sugar_bought",0)))

## Order card checks, in the same order the server rejects (contract actions.flower_ship).
static func order_checks(record:Dictionary,bag:Dictionary,coins:int=0)->Dictionary:
	var saved:Dictionary=record.get("saved",{})
	var all_saved:=true
	for kind in Flower.FLOWERS:all_saved=all_saved and saved.get(kind,false)
	var short:Array[String]=[]
	for kind in Flower.ORDER:
		var missing:=int(Flower.ORDER[kind])-int(bag.get(kind,0))
		if missing>0:short.append("%s還差 %d"%[item_name(kind),missing])
	var reserve:Array=[]
	var reserve_ok:=true
	for seed in Flower.RESERVE:
		var held:=int(bag.get(seed,0))
		var ok:=held>=int(Flower.RESERVE[seed])
		reserve_ok=reserve_ok and ok
		reserve.append({"id":seed,"ok":ok,"text":"%s 交貨後留下 %s %d 包（目前 %d）"%["✓" if ok else "✗",item_name(seed),int(Flower.RESERVE[seed]),held],
			"short":"%s 交貨後留下 %d 包\n目前 %d"%["✓" if ok else "✗",int(Flower.RESERVE[seed]),held]})
	var reason:=""
	if record.get("shipped",false):reason="已出貨"
	elif not all_saved:reason=Flower.UNSAVED_MESSAGE
	elif not short.is_empty():reason="成花不足："+"、".join(short)
	elif not reserve_ok:reason=Flower.RESERVE_MESSAGE
	elif coins>Flower.LIMIT-Flower.ORDER_PAY:reason="鈴幣已達上限，訂單暫不結算。"
	return {"all_saved":all_saved,"short":short,"reserve":reserve,"reserve_ok":reserve_ok,"reason":reason}

static func garden_preview(shared:Dictionary,bag:Dictionary)->Dictionary:
	var take:Dictionary={}
	var given:Dictionary=shared.get("given",{})
	for id in Flower.GARDEN_NEEDS:
		var amount:=mini(int(Flower.GARDEN_NEEDS[id])-int(given.get(id,0)),int(bag.get(id,0)))
		if amount>0:take[id]=amount
	return take

static func story_entries(record:Dictionary,shared:Dictionary)->Array:
	# Replay is client-only: shows story lines the player's own record has unlocked.
	var reached:Array[String]=[]
	if record.get("letter",false):reached.append("letter")
	if record.get("intro",false):reached.append("intro")
	if record.get("intro",false) and not record.get("planted",{}).is_empty():reached.append("plant")
	if not record.get("harvested",{}).is_empty():reached.append("harvest")
	if not record.get("saved",{}).is_empty():reached.append("save")
	if record.get("shipped",false):reached.append_array(["ship","garden"])
	if record.get("shipped",false) and shared.get("complete",false):reached.append("report")
	if record.get("complete",false):reached.append("complete")
	var entries:Array=[]
	for id in reached:
		if Flower.STORY.has(id):entries.append({"id":id,"title":PHASE_LABELS.get(id,id),"text":story_text(Flower.STORY[id])})
	if shared.get("complete",false) and record.get("intro",false):
		entries.append({"id":"opening","title":"公共花園開園","text":opening_text()})
	return entries

static func opening_text()->String:
	return Flower.GARDEN_EVENT+"。
"+str(Flower.STORY.report)

static func story_text(value)->String:
	if value is Array:return "\n".join(PackedStringArray(value.map(func(line):return str(line))))
	if value is Dictionary:return str(value.get("text",value.get("line",JSON.stringify(value))))
	return str(value)

static func plan_text(kind:String)->String:
	return "目前全年可種，澆水後約 %d 秒成熟"%int(Flower.CROPS[kind].time)

# ── main.gd 掛點 ───────────────────────────────────────────

static func counter_link(app,content:VBoxContainer)->void:
	if not unlocked(app.session.snapshot) or content.find_child("XiaoliFlowerLetter",true,false):return
	var link:Button=app.button("田尾花圃介紹信",func():open(app,"letter"))
	link.name="XiaoliFlowerLetter"
	link.icon=Shell.icon("letter")
	var tea_link:=content.find_child("XiaoliTeaOrder",false,false)
	var counter:=content.find_child("ShopCounter",false,false)
	if counter:
		if tea_link:
			content.remove_child(tea_link)
			counter.add_child(tea_link)
		counter.add_child(link)
		return
	if tea_link:
		var letters:=HBoxContainer.new()
		letters.name="XiaoliCorrespondence"
		letters.add_theme_constant_override("separation",8)
		content.remove_child(tea_link)
		content.add_child(letters)
		content.move_child(letters,0)
		tea_link.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		link.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		letters.add_child(tea_link)
		letters.add_child(link)
	else:
		content.add_child(link)
		content.move_child(link,0)

static func chapter_link(app)->void:
	if not unlocked(app.session.snapshot) or not is_instance_valid(app.modal) or not app.modal.has_meta("chapter_content"):return
	var content:VBoxContainer=app.modal.get_meta("chapter_content")
	if content.find_child("ChapterFlowerJournal",false,false):return
	var link:Button=app.button("第三章・田尾花圃手帳",func():open(app,"journal"))
	link.name="ChapterFlowerJournal"
	link.icon=Shell.icon("letter")
	content.add_child(link)

static func layout(app,bounds:Vector2)->void:
	if not is_instance_valid(app.modal) or not app.modal.has_meta("flower_site"):return
	var site:String=app.modal.get_meta("flower_site","journal")
	var wanted:Vector2=SIZES.get(site,Vector2(700,480))
	var height:=wanted.y
	if site!="journal":
		var fitted:=content_height(app)
		if fitted>0.0:height=minf(wanted.y,fitted)
	app.modal.size=Vector2(minf(wanted.x,bounds.x-48),minf(height,bounds.y-48))
	app.modal.position=((bounds-app.modal.size)/2).floor()
	if site in ["letter","farmer","xinghe"]:app.modal.position.y=bounds.y-app.modal.size.y-28

## Modal chrome (title, rules, status line) plus the scrolled content's minimum
## height at the current width: the modal is exactly as tall as what it shows.
static func content_height(app)->float:
	var scroll:=app.modal.find_child("ModalScroll",true,false) as ScrollContainer
	if scroll==null or scroll.get_child_count()==0:return 0.0
	var content:=scroll.get_child(0) as Control
	return ceilf(app.modal.get_combined_minimum_size().y+content.get_combined_minimum_size().y)

# ── 介面 ───────────────────────────────────────────────────

static func open(app,site:String,_cell:=Vector2i.ZERO)->void:
	if not TITLES.has(site):return
	var body:VBoxContainer=app._open_modal(TITLES[site])
	app.modal.theme=Pixel.make(app.hud.theme)
	app.modal.add_theme_stylebox_override("panel",Pixel.frame_style())
	app.modal.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	app.modal.set_meta("life_modal_layout",LAYOUT)
	app.modal.set_meta("flower_body",body)
	app.modal.set_meta("flower_site",site)
	if site in ["letter","farmer","xinghe"] and is_instance_valid(app.modal_shade):app.modal_shade.color.a=0.24
	var shell:=app.modal.get_child(0) as VBoxContainer
	if shell:shell.add_theme_constant_override("separation",6)
	if site=="journal":book_chrome(app,shell)
	refresh(app)
	app._layout_preview.call_deferred()

static func refresh(app)->void:
	if not is_instance_valid(app.modal) or not app.modal.has_meta("flower_body"):return
	var snapshot:Dictionary=app.session.snapshot
	var own_id:String=app.session.own_id
	var actor:Dictionary=snapshot.get("players",{}).get(own_id,{})
	var record:=own_record(snapshot)
	var shared:=garden(snapshot)
	var now:=float(snapshot.get("time",0))
	var site:String=app.modal.get_meta("flower_site")
	var cell:=site_cell(site)
	var region:=site_region(site)
	var nearby:bool=site=="journal" or (str(snapshot.get("region_id","home"))==region and not actor.is_empty() and Vector2(actor.x,actor.y).distance_to(Vector2(cell)+Vector2(0.5,0.5))<=3.2)
	var bag:Dictionary=actor.get("inventory",{})
	var coins:=int(actor.get("coins",0))
	var remaining:={"saving":0,"dyeing":0}
	for job in remaining:
		var work:Dictionary=record.get(job,{})
		if not work.is_empty():remaining[job]=maxi(0,ceili(float(work.get("ready",0))-now))
	var view:={"tab":app.modal.get_meta("flower_tab","progress"),"story":app.modal.get_meta("flower_story","")}
	var fingerprint:=JSON.stringify([record,shared,own_given(snapshot),bag,coins,remaining,nearby,unlocked(snapshot),view,sugar_left(record,now),actor.get("travel_book",{}),snapshot.get("resident_memories",[]), snapshot.get("resident_participation",{})])
	if app.modal.get_meta("flower_fingerprint","")==fingerprint:return
	app.modal.set_meta("flower_fingerprint",fingerprint)
	var body:VBoxContainer=app.modal.get_meta("flower_body")
	var viewport:=body.get_viewport()
	var focus:=viewport.gui_get_focus_owner() if viewport else null
	var focus_name:String=focus.name if is_instance_valid(focus) and body.is_ancestor_of(focus) else ""
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()
	if site=="journal":
		journal(app,body,snapshot)
		restore_focus(body,focus_name)
		app._layout_preview.call_deferred()
		return
	var card:=PanelContainer.new()
	card.name="FlowerCard"
	card.add_theme_stylebox_override("panel",Pixel.paper_style())
	body.add_child(card)
	var page:=VBoxContainer.new()
	page.name="FlowerPage"
	page.add_theme_constant_override("separation",8)
	card.add_child(page)
	var ctx:={"app":app,"snapshot":snapshot,"own_id":own_id,"record":record,"garden":shared,"bag":bag,"coins":coins,"now":now,"cell":cell,"nearby":nearby,"remaining":remaining,"intro":bool(record.get("intro",false))}
	match site:
		"letter":letter_panel(ctx,page)
		"farmer":farmer_panel(ctx,page)
		"seed":seed_panel(ctx,page)
		"dye":dye_panel(ctx,page)
		"market":market_panel(ctx,page)
		"garden":garden_panel(ctx,page)
		"xinghe":xinghe_panel(ctx,page)
	if site in ["farmer","xinghe"]:app._resident_story_dialogue(page,"alei" if site=="farmer" else "xinghe")
	# Panels may tuck the journal link into their own header (market does).
	if not page.find_child("FlowerJournal",true,false):
		var footer:=HBoxContainer.new()
		footer.name="FlowerFooter"
		footer.add_theme_constant_override("separation",8)
		page.add_child(footer)
		journal_link(app,footer)
	if is_instance_valid(app.modal_feedback):
		app.modal_feedback.text=NEAR_REASON if not nearby else "Esc 回到島上 · 田尾花圃進度隨島民存檔保存"
	restore_focus(body,focus_name)
	app._layout_preview.call_deferred()

static func restore_focus(body:Control,focus_name:String)->void:
	if focus_name.is_empty():return
	var next:=body.find_child(focus_name,true,false) as BaseButton
	if not next or next.disabled:
		for button:BaseButton in body.find_children("*","BaseButton",true,false):
			if not button.disabled:
				next=button
				break
	if next and not next.disabled:next.grab_focus.call_deferred()

static func journal_link(app,parent:Node)->Button:
	var link:=Helpers.action(app,parent,"FlowerJournal","翻閱花圃手帳",func():open(app,"journal"),true)
	link.icon=Folio.life_icon("journal")
	link.expand_icon=true
	link.add_theme_constant_override("icon_max_width",22)
	link.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	return link

# ── 元件 ───────────────────────────────────────────────────

static func label(app,parent:Node,value:String,size:int=15,tint=null)->Label:
	var result:=Helpers.text(app,parent,value,size)
	if tint is Color:result.add_theme_color_override("font_color",tint)
	return result

## Icon then text. Missing art => no picture at all (name only), never a substitute icon.
static func icon_into(parent:Node,id:String,extent:int=32)->TextureRect:
	var texture:=item_icon(id)
	if texture==null:return null
	var picture:=Shell.picture(texture,extent)
	picture.name="Icon_"+id
	parent.add_child(picture)
	return picture

static func row(parent:Node,name:String="")->HBoxContainer:
	var result:=HBoxContainer.new()
	if not name.is_empty():result.name=name
	result.add_theme_constant_override("separation",8)
	parent.add_child(result)
	return result

## Button plus visible reason label. Disabled buttons always carry the reason
## both as tooltip and as a sibling label named <id>Reason.
static func act(ctx:Dictionary,parent:Node,id:String,title:String,action:String,reason:String,extra:="")->Button:
	var app=ctx.app
	var cell:Vector2i=ctx.cell
	var why:=reason
	if why.is_empty() and not ctx.nearby:why=NEAR_REASON
	var button:=Helpers.action(app,parent,id,title,func():app.session.perform(action,cell,extra),why.is_empty())
	button.tooltip_text=why if not why.is_empty() else title
	button.accessibility_name=title+("（"+why+"）" if not why.is_empty() else "")
	if not why.is_empty():
		var note:=label(app,parent,why,13,WARN_TINT)
		note.name=id+"Reason"
		note.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	return button

static func portrait_row(app,parent:Node,texture:Texture2D,name:String,line:String,extent:int=96)->VBoxContainer:
	var line_row:=row(parent,"FlowerSpeaker")
	line_row.add_theme_constant_override("separation",14)
	if texture:
		var frame:=PanelContainer.new()
		frame.name="FlowerPortraitFrame"
		frame.add_theme_stylebox_override("panel",Folio.portrait_style())
		frame.size_flags_vertical=Control.SIZE_SHRINK_CENTER
		line_row.add_child(frame)
		var art:=Shell.picture(texture,extent)
		art.name="FlowerPortrait"
		frame.add_child(art)
	var words:=VBoxContainer.new()
	words.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override("separation",5)
	line_row.add_child(words)
	label(app,words,name,18,Color("7a4e2b")).name="FlowerSpeakerName"
	label(app,words,line,16).name="FlowerLine"
	return words

## Small pixel tag (price, held count, daily allowance). Never wraps.
static func badge(app,parent:Node,id:String,value:String,fill:Color=Color("fbefcf"),ink:Color=BROWN,texture:Texture2D=null)->Label:
	var tag:=PanelContainer.new()
	tag.name=id+"Tag"
	tag.add_theme_stylebox_override("panel",LifeTheme.surface(fill,fill.darkened(0.28),5,1))
	tag.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	tag.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	parent.add_child(tag)
	var line:=HBoxContainer.new()
	line.add_theme_constant_override("separation",3)
	tag.add_child(line)
	if texture:line.add_child(Shell.picture(texture,16))
	var text:=label(app,line,value,12,ink)
	text.name=id
	text.autowrap_mode=TextServer.AUTOWRAP_OFF
	return text

## Picture of a fixed footprint, or an equal empty gap when the art is missing.
static func picture_or_gap(parent:Node,texture:Texture2D,extent:int,name:String="")->Control:
	var result:Control
	if texture:result=Shell.picture(texture,extent)
	else:
		result=Control.new()
		result.custom_minimum_size=Vector2(extent,extent)
		result.mouse_filter=Control.MOUSE_FILTER_IGNORE
	if not name.is_empty():result.name=name
	result.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
	parent.add_child(result)
	return result

static func counts_row(app,parent:Node,items:Dictionary,name:String)->HBoxContainer:
	var line:=row(parent,name)
	for id in items:
		icon_into(line,id,32)
		var text:=label(app,line,"%s ×%d"%[item_name(id),int(items[id])],14)
		text.autowrap_mode=TextServer.AUTOWRAP_OFF
		text.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	return line

static func bag_has_room(bag:Dictionary,items:Dictionary)->bool:
	return Flower.can_grant(bag,items)

static func progress(parent:Node,name:String,value:float,maximum:float)->ProgressBar:
	var bar:=ProgressBar.new()
	bar.name=name
	bar.show_percentage=false
	bar.max_value=maxf(1.0,maximum)
	bar.value=value
	bar.custom_minimum_size=Vector2(140,12)
	bar.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	parent.add_child(bar)
	return bar

# ── 各站點 ─────────────────────────────────────────────────

static func letter_panel(ctx:Dictionary,page:VBoxContainer)->void:
	var app=ctx.app
	var record:Dictionary=ctx.record
	var line:=story_text(Flower.STORY.letter if unlocked(ctx.snapshot) else Flower.STORY.locked)
	portrait_row(app,page,LifeTheme.icon("xiaoli"),"小栗",line)
	if record.get("letter",false):
		label(app,page,"介紹信已收下，可從手帳重看。",15,OK_TINT).name="FlowerLetterDone"
		return
	var reason:=""
	if not unlocked(ctx.snapshot):reason="完成第二章的茶陶包裝比較後，小栗才會交給你介紹信。"
	act(ctx,page,"FlowerLetter","收下介紹信","flower_letter",reason)

static func farmer_panel(ctx:Dictionary,page:VBoxContainer)->void:
	var app=ctx.app
	var record:Dictionary=ctx.record
	var guide:=next_step(ctx.snapshot,ctx.own_id)
	if not ctx.intro:
		portrait_row(app,page,Resident.portrait_texture(),FARMER_NAME,"歡迎來到田尾合作花圃。我這裡有三種花的起始種子，種下去之前，先想好要留哪一朵回來。",128)
		counts_row(app,page,Flower.STARTER,"FlowerStarter")
		var reason:=""
		if not record.get("letter",false):reason="先在家鄉渡口向小栗收下田尾的介紹信。"
		elif not ctx.snapshot.get("players",{}).get(ctx.own_id,{}).get("travel_book",{}).get("visited",{}).get(Flower.REGION,false):reason="先經轉乘抵達田尾合作花圃。"
		elif not bag_has_room(ctx.bag,Flower.STARTER):reason="背包放不下起始種子，請先騰出空間。"
		act(ctx,page,"FlowerIntro","收下起始種子","flower_intro",reason)
		return
	var words:=portrait_row(app,page,Resident.portrait_texture(),FARMER_NAME,str(guide.get("detail","育苗床在棚子南邊，每人可照顧 %d 格。"%Flower.PLOT_CAP)),128)
	label(app,words,"下一步：%s"%str(guide.get("title","")),14,Color("7a4e2b")).name="FlowerFarmerNext"
	label(app,page,"育苗床每人最多 %d 格，只能種花、只收自己的花。"%Flower.PLOT_CAP,14)

static func seed_panel(ctx:Dictionary,page:VBoxContainer)->void:
	var app=ctx.app
	var record:Dictionary=ctx.record
	var bag:Dictionary=ctx.bag
	var saving:Dictionary=record.get("saving",{})
	var saved:Dictionary=record.get("saved",{})
	var art:=SceneArt.prop_texture("seed_saving_table") if SceneArt.has_prop("seed_saving_table") else null
	var head:=row(page,"FlowerSeedHead")
	if art:head.add_child(Shell.picture(art,64))
	label(app,head,"1 朵成花 → 1 包同種種子（%d 秒）"%int(Flower.SAVE_SECONDS),16)
	for kind in Flower.FLOWERS:
		var seed:String=Flower.SEEDS[kind]
		var line:=row(page,"FlowerSeedRow_"+kind)
		icon_into(line,kind,32)
		var info:=VBoxContainer.new()
		info.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		line.add_child(info)
		label(app,info,item_name(kind)+("　✓ 已留過種" if saved.get(kind,false) else ""),16)
		label(app,info,"成花 %d · 種子 %d"%[int(bag.get(kind,0)),int(bag.get(seed,0))],14).name="FlowerSeedCount_"+kind
		var buttons:=VBoxContainer.new()
		buttons.custom_minimum_size.x=230
		line.add_child(buttons)
		if not saving.is_empty() and str(saving.get("kind",""))==kind:
			var left:int=ctx.remaining.saving
			label(app,buttons,"留種中 · 剩 %d 秒"%left if left>0 else "可以領取",14).name="FlowerSaveTimer"
			var reason:=""
			if left>0:reason="還要 %d 秒"%left
			elif not bag_has_room(bag,{seed:1}):reason="背包上限，工作保留，不會消失。"
			act(ctx,buttons,"FlowerSaveTake","領取",  "flower_save_take",reason)
			continue
		var why:=""
		if not ctx.intro:why=INTRO_REASON
		elif not saving.is_empty():why="留種台正在處理另一包"
		elif not record.get("harvested",{}).has(kind):why="先在田尾育苗床採收過%s"%item_name(kind)
		elif int(bag.get(kind,0))<1:why="沒有%s成花"%item_name(kind)
		act(ctx,buttons,"FlowerSave_"+kind,"留 1 包（%d 秒）"%int(Flower.SAVE_SECONDS),"flower_save",why,kind)
	label(app,page,"出貨前每種至少留 1 包",14,Color("7a4e2b")).name="FlowerSeedHint"

static func dye_panel(ctx:Dictionary,page:VBoxContainer)->void:
	var app=ctx.app
	var record:Dictionary=ctx.record
	var bag:Dictionary=ctx.bag
	var dyeing:Dictionary=record.get("dyeing",{})
	var inputs:Dictionary=Flower.DYE.ingredients
	var output:String=Flower.DYE.item
	var head:=row(page,"FlowerDyeRecipe")
	var art:=SceneArt.prop_texture("dye_table") if SceneArt.has_prop("dye_table") else null
	if art:head.add_child(Shell.picture(art,64))
	for id in inputs:
		icon_into(head,id,48)
		var need:=label(app,head,"%s ×%d"%[item_name(id),int(inputs[id])],15)
		need.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
		need.autowrap_mode=TextServer.AUTOWRAP_OFF
	var arrow:=label(app,head,"→",15,BROWN)
	arrow.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	arrow.autowrap_mode=TextServer.AUTOWRAP_OFF
	icon_into(head,output,48)
	label(app,head,"%s ×%d（%d 秒）"%[item_name(output),int(Flower.DYE.yield),int(Flower.DYE.time)],15)
	label(app,page,"花色染料配方",14,Color("7a4e2b")).name="FlowerDyeSource"
	var first:String=inputs.keys()[0]
	label(app,page,"%s %d · %s %d"%[item_name(first),int(bag.get(first,0)),item_name(output),int(bag.get(output,0))],15).name="FlowerDyeStock"
	if not dyeing.is_empty():
		var left:int=ctx.remaining.dyeing
		progress(page,"FlowerDyeProgress",float(Flower.DYE.time)-left,float(Flower.DYE.time))
		label(app,page,"染色中 · 剩 %d 秒"%left if left>0 else "染料已完成，可以領取",14).name="FlowerDyeTimer"
		var reason:=""
		if left>0:reason="還要 %d 秒"%left
		elif not bag_has_room(bag,{output:int(Flower.DYE.yield)}):reason="背包上限，工作保留，不會消失。"
		act(ctx,page,"FlowerDyeTake","領取藍色染料","flower_dye_take",reason)
		return
	var why:=""
	if not ctx.intro:why=INTRO_REASON
	elif int(bag.get(first,0))<int(inputs[first]):why="%s不足 %d 朵（目前 %d）"%[item_name(first),int(inputs[first]),int(bag.get(first,0))]
	act(ctx,page,"FlowerDye","開始染色（%d 秒）"%int(Flower.DYE.time),"flower_dye",why)
	var snapshot:Dictionary=app.session.snapshot
	var person:Dictionary=snapshot.get("players",{}).get(app.session.own_id,{})
	if person.get("blue_outfit",false):
		act(ctx,page,"FlowerOutfit","換回原色工作服","flower_outfit","","original")
	else:
		var outfit_reason:=INTRO_REASON if not ctx.intro else ("需要藍色染料 ×1" if int(bag.get("blue_dye",0))<1 else "")
		act(ctx,page,"FlowerOutfit","藍染工作服 · 染料 ×1","flower_outfit",outfit_reason,"blue")

static func market_panel(ctx:Dictionary,page:VBoxContainer)->void:
	var app=ctx.app
	var record:Dictionary=ctx.record
	var bag:Dictionary=ctx.bag
	var columns:=HBoxContainer.new()
	columns.name="FlowerMarketColumns"
	columns.add_theme_constant_override("separation",14)
	page.add_child(columns)
	var shop:=VBoxContainer.new()
	shop.name="FlowerMarketShop"
	shop.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	shop.add_theme_constant_override("separation",8)
	columns.add_child(shop)
	# Stall header: delivered market art, purse and the journal bookmark.
	var head:=row(shop,"FlowerMarketHead")
	var stall:=SceneArt.market_texture(bool(ctx.garden.get("complete",false)))
	if stall:
		var art:=Shell.picture(stall,64)
		art.name="FlowerMarketArt"
		head.add_child(art)
	var hello:=VBoxContainer.new()
	hello.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	hello.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	hello.add_theme_constant_override("separation",4)
	head.add_child(hello)
	label(app,hello,"今天的種子與糖",17,BROWN).name="FlowerMarketGreeting"
	var purse:=HBoxContainer.new()
	purse.add_theme_constant_override("separation",6)
	hello.add_child(purse)
	badge(app,purse,"FlowerCoins","鈴幣 %d"%ctx.coins,Color("f6d98c"),Color("5a3a12"),Items.icon("coins"))
	journal_link(app,purse)
	var grid:=GridContainer.new()
	grid.name="FlowerMarketGrid"
	grid.columns=2
	grid.add_theme_constant_override("h_separation",8)
	grid.add_theme_constant_override("v_separation",8)
	shop.add_child(grid)
	var left_today:=sugar_left(record,ctx.now)
	for id in Flower.MARKET_PRICES:
		var price:=int(Flower.MARKET_PRICES[id])
		var card:=PanelContainer.new()
		card.name="FlowerBuyRow_"+id
		card.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		card.add_theme_stylebox_override("panel",Folio.padded("paper",3,8,7))
		grid.add_child(card)
		var stack:=VBoxContainer.new()
		stack.add_theme_constant_override("separation",5)
		card.add_child(stack)
		var top:=row(stack)
		top.add_theme_constant_override("separation",8)
		var slot:=PanelContainer.new()
		slot.add_theme_stylebox_override("panel",Folio.padded("normal",3,2,2))
		slot.size_flags_vertical=Control.SIZE_SHRINK_CENTER
		top.add_child(slot)
		if not icon_into(slot,id,64):picture_or_gap(slot,null,64)
		var info:=VBoxContainer.new()
		info.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		info.size_flags_vertical=Control.SIZE_SHRINK_CENTER
		info.add_theme_constant_override("separation",4)
		top.add_child(info)
		label(app,info,item_name(id),15,INK).name="FlowerBuyName_"+id
		var tags:=HFlowContainer.new()
		tags.add_theme_constant_override("h_separation",4)
		tags.add_theme_constant_override("v_separation",4)
		info.add_child(tags)
		badge(app,tags,"FlowerPrice_"+id,"%d 鈴幣"%price,Color("f6d98c"),Color("5a3a12"))
		if id=="sugar":
			badge(app,tags,"FlowerHeld_"+id,"持有 %d"%int(bag.get(id,0)),Color("efe4cb"),INK)
			badge(app,tags,"FlowerBuyInfo_"+id,"今日剩 %d 份"%left_today,Color("dfeccf") if left_today>0 else Color("f6dcc0"),OK_TINT if left_today>0 else WARN_TINT)
		else:
			badge(app,tags,"FlowerBuyInfo_"+id,"持有 %d"%int(bag.get(id,0)),Color("efe4cb"),INK)
		var why:=""
		if not ctx.intro:why=INTRO_REASON
		elif id=="sugar" and left_today<=0:why="今日糖已達 %d 份（新的遊戲日才重置）"%Flower.SUGAR_DAILY
		elif ctx.coins<price:why="鈴幣不足"
		elif not bag_has_room(bag,{id:1}):why="背包上限"
		var buy:=act(ctx,stack,"FlowerBuy_"+id,"買 1 份","flower_buy",why,id)
		buy.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		var note:=stack.find_child("FlowerBuy_%sReason"%id,false,false) as Label
		if note:
			note.add_theme_font_size_override("font_size",12)
			note.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	order_board(ctx,columns,record,bag)

## Packing board: wooden frame, paper slip, one crate per ordered flower,
## one seed-reserve chip per seed and the single ship action.
static func order_board(ctx:Dictionary,columns:HBoxContainer,record:Dictionary,bag:Dictionary)->void:
	var app=ctx.app
	var order:=PanelContainer.new()
	order.name="FlowerOrderCard"
	order.custom_minimum_size.x=400
	order.add_theme_stylebox_override("panel",Pixel.texture_style("hud_wood",8,7))
	columns.add_child(order)
	var slip:=PanelContainer.new()
	slip.name="FlowerOrderSlip"
	slip.add_theme_stylebox_override("panel",Folio.page_style())
	order.add_child(slip)
	var card:=VBoxContainer.new()
	card.add_theme_constant_override("separation",7)
	slip.add_child(card)
	var ribbon:=PanelContainer.new()
	ribbon.add_theme_stylebox_override("panel",Folio.ribbon_style())
	card.add_child(ribbon)
	var title:=label(app,ribbon,"合作花圃訂單 · %d 鈴幣"%Flower.ORDER_PAY,16,Folio.RIBBON_INK)
	title.name="FlowerOrderTitle"
	title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	var crates:=HBoxContainer.new()
	crates.name="FlowerOrderCrates"
	crates.add_theme_constant_override("separation",6)
	card.add_child(crates)
	for kind in Flower.ORDER:
		var held:=int(bag.get(kind,0))
		var need:=int(Flower.ORDER[kind])
		var crate:=PanelContainer.new()
		crate.name="FlowerOrderNeed_"+kind
		crate.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		crate.add_theme_stylebox_override("panel",LifeTheme.surface(Color("e6f0d6") if held>=need else Color("f8e6cf"),OK_TINT if held>=need else Color("c49a6c"),4,5))
		crates.add_child(crate)
		var stack:=VBoxContainer.new()
		stack.add_theme_constant_override("separation",2)
		crate.add_child(stack)
		var art:=icon_into(stack,kind,56)
		if art:art.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
		else:picture_or_gap(stack,null,56)
		var name_label:=label(app,stack,item_name(kind),13,INK)
		name_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		name_label.autowrap_mode=TextServer.AUTOWRAP_OFF
		var count:=label(app,stack,"%s 持有 %d／需 %d"%["✓" if held>=need else "✗",held,need],12,OK_TINT if held>=need else WARN_TINT)
		count.name="FlowerOrderCount_"+kind
		count.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		count.autowrap_mode=TextServer.AUTOWRAP_OFF
	var checks:=order_checks(record,bag,ctx.coins)
	label(app,card,"%s 三種花都已留過種"%("✓" if checks.all_saved else "✗"),14,OK_TINT if checks.all_saved else WARN_TINT).name="FlowerOrderSaved"
	var chips:=HBoxContainer.new()
	chips.name="FlowerReserveChips"
	chips.add_theme_constant_override("separation",6)
	card.add_child(chips)
	for index in checks.reserve.size():
		var entry:Dictionary=checks.reserve[index]
		var chip:=PanelContainer.new()
		chip.name="FlowerReserveChip_"+str(entry.id)
		chip.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		chip.tooltip_text=entry.text
		var fill:=Color("dfeccf") if entry.ok else Color("f6dcc0")
		chip.add_theme_stylebox_override("panel",LifeTheme.surface(fill,OK_TINT if entry.ok else WARN_TINT,5,4))
		chips.add_child(chip)
		var line:=VBoxContainer.new()
		line.add_theme_constant_override("separation",2)
		chip.add_child(line)
		var seed_art:=icon_into(line,str(entry.id),32)
		if seed_art:seed_art.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
		var text:=label(app,line,entry.short,12,OK_TINT if entry.ok else WARN_TINT)
		text.name="FlowerReserve_"+str(entry.id)
		text.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		text.accessibility_name=entry.text
	if record.get("shipped",false):
		label(app,card,"✓ 訂單已交付，鈴幣已入帳。",15,OK_TINT).name="FlowerShipped"
		return
	var ship:=act(ctx,card,"FlowerShip","交貨 · %d 鈴幣"%Flower.ORDER_PAY,"flower_ship",checks.reason if ctx.intro else INTRO_REASON)
	ship.custom_minimum_size.y=38
	ship.icon=Folio.life_icon("chest")
	ship.expand_icon=true
	ship.add_theme_constant_override("icon_max_width",24)

static func garden_panel(ctx:Dictionary,page:VBoxContainer)->void:
	var app=ctx.app
	var shared:Dictionary=ctx.garden
	var bag:Dictionary=ctx.bag
	var given:Dictionary=shared.get("given",{})
	var complete:bool=shared.get("complete",false)
	var head:=row(page,"FlowerGardenHead")
	var art:=SceneArt.prop_texture("community_flower_trellis") if SceneArt.has_prop("community_flower_trellis") and complete else null
	if art:head.add_child(Shell.picture(art,64))
	var status:=label(app,head,"✓ 公共花園已開園" if complete else "公共花園整理中",18,OK_TINT if complete else Color("7a4e2b"))
	status.name="FlowerGardenStatus"
	status.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	status.autowrap_mode=TextServer.AUTOWRAP_OFF
	var helpers:=label(app,head,"合力島民 %d 位 · 你已捐 %d 份"%[int(shared.get("contributor_count",0)),own_given(ctx.snapshot)],15)
	helpers.name="FlowerContributors"
	helpers.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	for id in Flower.GARDEN_NEEDS:
		var line:=row(page,"FlowerGardenBar_"+id)
		icon_into(line,id,24)
		var need:=int(Flower.GARDEN_NEEDS[id])
		var have:=int(given.get(id,0))
		var name_label:=label(app,line,item_name(id),15)
		name_label.custom_minimum_size.x=96
		name_label.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
		progress(line,"FlowerGardenProgress_"+id,have,need)
		var amount:=label(app,line,"%d/%d%s"%[have,need," ✓" if have>=need else ""],15)
		amount.name="FlowerGardenCount_"+id
		amount.autowrap_mode=TextServer.AUTOWRAP_OFF
		amount.size_flags_horizontal=Control.SIZE_SHRINK_END
	if complete:
		if ctx.app.sound and not ctx.app.sound.reduced_motion:
			status.modulate.a=0.4
			var tween:=status.create_tween()
			tween.tween_property(status,"modulate:a",1.0,1.2).set_trans(Tween.TRANS_SINE)
		var replay:String=ctx.app.modal.get_meta("flower_story","")
		var shown:=replay=="opening"
		Helpers.action(app,page,"FlowerReplayOpening","收起開園事件" if shown else "重看開園事件",func():
			app.modal.set_meta("flower_story","" if shown else "opening")
			refresh(app),true)
		if shown:label(app,page,opening_text(),15).name="FlowerOpeningStory"
		label(app,page,SEED_NOTE+"；捐獻只收染料、橙花和香草。",13).name="FlowerSeedNote"
		return
	var take:=garden_preview(shared,bag)
	var preview:=row(page,"FlowerGivePreview")
	var give_head:=label(app,preview,"這次會捐出：",14)
	give_head.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	give_head.autowrap_mode=TextServer.AUTOWRAP_OFF
	if take.is_empty():label(app,preview,"沒有可捐的物品",14)
	for id in take:
		icon_into(preview,id,24)
		var bit:=label(app,preview,"%s ×%d"%[item_name(id),int(take[id])],14)
		bit.autowrap_mode=TextServer.AUTOWRAP_OFF
		bit.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	var why:=""
	if not ctx.intro:why=INTRO_REASON
	elif take.is_empty():why="沒有可捐的染料、橙花或香草（種子不會被拿走）"
	var give_row:=row(page,"FlowerGiveRow")
	var give:=act(ctx,give_row,"FlowerGive","捐出",  "flower_give",why)
	give.custom_minimum_size.x=120
	give.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	if why.is_empty():label(app,give_row,SEED_NOTE+"；只會拿走還缺的數量。",13,OK_TINT).name="FlowerSeedNote"
	else:label(app,page,SEED_NOTE+"；只會拿走還缺的數量。",13,OK_TINT).name="FlowerSeedNote"

static func xinghe_panel(ctx:Dictionary,page:VBoxContainer)->void:
	var app=ctx.app
	var record:Dictionary=ctx.record
	var shared:Dictionary=ctx.garden
	var line:="星禾正在花架旁記錄留種的方法。"
	if record.get("complete",false):line=story_text(Flower.STORY.complete)
	elif shared.get("complete",false):line=story_text(Flower.STORY.report)
	portrait_row(app,page,Lanyang.portrait(),"星禾",line)
	if record.get("complete",false):
		label(app,page,"✓ 已回報。小栗的攤位開始進花卉種子。",15,OK_TINT).name="FlowerReportDone"
		return
	counts_row(app,page,Flower.MEMENTO,"FlowerMemento")
	var why:=""
	if not ctx.intro:why=INTRO_REASON
	elif not record.get("shipped",false):why="先完成市集的合作訂單。"
	elif not shared.get("complete",false):why="公共花園尚未完成。"
	elif not bag_has_room(ctx.bag,Flower.MEMENTO):why="背包上限"
	act(ctx,page,"FlowerReport","向星禾回報","flower_report",why)

# ── 手帳（只讀；劇情重看只在客戶端） ────────────────────────
## The journal is an open field journal (ui-life/book.png) instead of a framed
## window: the generic modal title/rules/status line are hidden and the close
## bookmark lives on the right page. Esc still closes through main.gd.

static var book_cache:Texture2D

static func book_texture()->Texture2D:
	if book_cache:return book_cache
	if not ResourceLoader.exists(BOOK_ASSET):return null
	var source:=load(BOOK_ASSET) as Texture2D
	if source==null:return null
	var image:=source.get_image()
	if image==null or image.is_empty():return null
	if image.is_compressed():image.decompress()
	image.resize(image.get_width()*2,image.get_height()*2,Image.INTERPOLATE_NEAREST)
	book_cache=ImageTexture.create_from_image(image)
	return book_cache

static func book_style()->StyleBox:
	var texture:=book_texture()
	if texture==null:return Folio.story_style()
	var style:=StyleBoxTexture.new()
	style.texture=texture
	# Exact 2x: the left/right slices meet in the right page, so horizontal size
	# is never resampled; the vertical middle band (plain page) absorbs height.
	style.texture_margin_left=440
	style.texture_margin_right=440
	style.texture_margin_top=56
	style.texture_margin_bottom=148
	style.content_margin_left=50
	style.content_margin_right=50
	style.content_margin_top=40
	style.content_margin_bottom=90
	return style

static func book_chrome(app,shell:VBoxContainer)->void:
	app.modal.add_theme_stylebox_override("panel",StyleBoxEmpty.new())
	if shell==null:return
	shell.add_theme_constant_override("separation",0)
	for chrome in shell.get_children():
		if chrome is ScrollContainer:continue
		chrome.hide()
		for item in chrome.find_children("*","Control",true,false):item.hide()

static func journal(app,parent:Control,snapshot:Dictionary)->void:
	var record:=own_record(snapshot)
	var shared:=garden(snapshot)
	var own_id:String=app.session.own_id
	var tab:String=app.modal.get_meta("flower_tab","progress") if is_instance_valid(app.modal) else "progress"
	var book:=PanelContainer.new()
	book.name="FlowerJournalBook"
	book.custom_minimum_size=BOOK_SIZE
	book.add_theme_stylebox_override("panel",book_style())
	book.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	parent.add_child(book)
	var spread:=HBoxContainer.new()
	spread.name="FlowerJournalSpread"
	spread.add_theme_constant_override("separation",BOOK_SPINE)
	book.add_child(spread)
	var left:=VBoxContainer.new()
	left.name="FlowerJournalLeftPage"
	left.custom_minimum_size.x=BOOK_LEFT_PAGE
	left.add_theme_constant_override("separation",7)
	spread.add_child(left)
	var right:=VBoxContainer.new()
	right.name="FlowerJournalRightPage"
	right.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation",8)
	spread.add_child(right)
	route_page(app,left,snapshot,own_id)
	# Right page: bookmark tabs + closing bookmark, then the chosen page.
	var tabs:=row(right,"FlowerJournalTabs")
	tabs.add_theme_constant_override("separation",4)
	for entry in [["progress","花圃近況"],["plan","作物筆記"],["story","故事重看"]]:
		var id:String=entry[0]
		var button:=Helpers.action(app,tabs,"FlowerTab_"+id,entry[1],func():
			app.modal.set_meta("flower_tab",id)
			app.modal.remove_meta("flower_story")
			refresh(app),true)
		Folio.apply_tab(button)
		button.custom_minimum_size.y=30
		button.add_theme_font_size_override("font_size",13)
		button.toggle_mode=true
		button.set_pressed_no_signal(tab==id)
		button.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	var gap:=Control.new()
	gap.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	tabs.add_child(gap)
	var close:=Helpers.action(app,tabs,"FlowerBookClose","闔上  Esc",app._close_modal,true)
	Folio.apply_tab(close)
	close.custom_minimum_size.y=30
	close.add_theme_font_size_override("font_size",13)
	var page:=VBoxContainer.new()
	page.name="FlowerJournalPage"
	page.size_flags_vertical=Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation",7)
	right.add_child(page)
	match tab:
		"plan":plan_page(app,page,record)
		"story":story_page(app,page,record,shared)
		_:status_page(app,page,snapshot,record,shared)

static func ribbon(app,parent:Node,id:String,texture:Texture2D,value:String)->Label:
	var band:=PanelContainer.new()
	band.name=id
	band.add_theme_stylebox_override("panel",Folio.ribbon_style())
	parent.add_child(band)
	var line:=HBoxContainer.new()
	line.add_theme_constant_override("separation",6)
	band.add_child(line)
	if texture:line.add_child(Shell.picture(texture,22))
	var text:=label(app,line,value,15,Folio.RIBBON_INK)
	text.autowrap_mode=TextServer.AUTOWRAP_OFF
	return text

static func step_texture(id:String)->Texture2D:
	match id:
		"letter":return Shell.icon("letter")
		"travel":return Shell.icon("map")
		"intro":return Resident.portrait_texture()
		"plant":return FlowerArt.item_texture("bluebell_seed")
		"harvest":return FlowerArt.item_texture("bluebell")
		"save":return SceneArt.prop_texture("seed_saving_table") if SceneArt.has_prop("seed_saving_table") else null
		"ship":return SceneArt.market_texture(false)
		"garden":return SceneArt.prop_texture("community_flower_trellis") if SceneArt.has_prop("community_flower_trellis") else null
		"report":return Lanyang.portrait()
	return null

## Left page: the chapter as a short illustrated route of stepping stones,
## read left-to-right in three rows, with the next step pinned below.
static func route_page(app,left:VBoxContainer,snapshot:Dictionary,own_id:String)->void:
	var current:=phase(snapshot,own_id)
	var guide:=next_step(snapshot,own_id)
	ribbon(app,left,"FlowerChapterRibbon",Folio.life_icon("journal"),"第三章 · 田尾花圃")
	label(app,left,"花開之前，先留下種子",13,BROWN).name="FlowerChapterMotto"
	var route:=VBoxContainer.new()
	route.name="FlowerPhases"
	route.add_theme_constant_override("separation",4)
	left.add_child(route)
	var at:=Flower.PHASES.find(current)
	var line:HBoxContainer
	for index in ROUTE.size():
		var id:String=ROUTE[index]
		if index%3==0:
			line=row(route,"FlowerRouteRow%d"%(index/3))
			line.add_theme_constant_override("separation",2)
		else:
			var arrow:=label(app,line,"→",13,FADED)
			arrow.autowrap_mode=TextServer.AUTOWRAP_OFF
			arrow.size_flags_vertical=Control.SIZE_SHRINK_CENTER
			arrow.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
		var order:=Flower.PHASES.find(id)
		var done:=current=="complete" or order<at
		var here:=order==at
		var stone:=PanelContainer.new()
		stone.name="FlowerStep_"+id
		stone.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		var look:StyleBox
		if here:look=Folio.padded("button_pressed",3,4,4)
		elif done:look=Folio.padded("normal",3,4,4)
		else:
			look=StyleBoxEmpty.new()
			for side in [SIDE_LEFT,SIDE_RIGHT,SIDE_TOP,SIDE_BOTTOM]:look.set_content_margin(side,4)
		stone.add_theme_stylebox_override("panel",look)
		stone.tooltip_text=PHASE_LABELS[id]
		line.add_child(stone)
		var stack:=VBoxContainer.new()
		stack.add_theme_constant_override("separation",2)
		stone.add_child(stack)
		var art:=picture_or_gap(stack,step_texture(id),32)
		if not done and not here:art.modulate=Color(1,1,1,0.45)
		var mark:="✓" if done else ("▶" if here else "・")
		var tint:Color=Folio.RIBBON_INK if here else (OK_TINT if done else FADED)
		var name_label:=label(app,stack,"%s %s"%[mark,PHASE_SHORT[id]],13,tint)
		name_label.name="FlowerPhase_"+id
		name_label.autowrap_mode=TextServer.AUTOWRAP_OFF
		name_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		name_label.accessibility_name="%s %s"%[mark,PHASE_LABELS[id]]
	var next:=PanelContainer.new()
	next.name="FlowerNextStep"
	next.add_theme_stylebox_override("panel",Folio.story_style())
	left.add_child(next)
	var words:=VBoxContainer.new()
	words.add_theme_constant_override("separation",3)
	next.add_child(words)
	var heading:String=PHASE_LABELS.get(current,"")
	label(app,words,"下一步：%s"%str(guide.get("title",heading)) if current!="complete" else "✓ %s"%PHASE_LABELS.complete,15,BROWN).name="FlowerNextTitle"
	label(app,words,str(guide.get("detail","")),13,INK).name="FlowerNextDetail"

static func status_mark(record:Dictionary,kind:String)->Array:
	return [["種下",record.get("planted",{}).has(kind)],["採收",record.get("harvested",{}).has(kind)],["留種",record.get("saved",{}).has(kind)]]

## Right page "花圃近況": one little crop card per flower plus the shared garden.
static func status_page(app,page:VBoxContainer,snapshot:Dictionary,record:Dictionary,shared:Dictionary)->void:
	label(app,page,"三種花的這一輪",15,BROWN).name="FlowerStatusHeading"
	var tally:=row(page,"FlowerJournalTally")
	tally.add_theme_constant_override("separation",6)
	for kind in Flower.FLOWERS:
		var card:=PanelContainer.new()
		card.name="FlowerTally_"+kind
		card.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		card.add_theme_stylebox_override("panel",Folio.card_style())
		tally.add_child(card)
		var stack:=VBoxContainer.new()
		stack.add_theme_constant_override("separation",2)
		card.add_child(stack)
		var grown:=FlowerArt.crop_texture(kind,3) if FlowerArt.has_crop(kind) else null
		picture_or_gap(stack,grown if grown else item_icon(kind),48)
		var name_label:=label(app,stack,item_name(kind),13,INK)
		name_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		name_label.autowrap_mode=TextServer.AUTOWRAP_OFF
		for entry in status_mark(record,kind):
			var mark:=label(app,stack,"%s %s"%["✓" if entry[1] else "・",entry[0]],12,OK_TINT if entry[1] else FADED)
			mark.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
			mark.autowrap_mode=TextServer.AUTOWRAP_OFF
	var plot:=PanelContainer.new()
	plot.name="FlowerJournalGardenCard"
	plot.add_theme_stylebox_override("panel",Folio.story_style())
	page.add_child(plot)
	var line:=HBoxContainer.new()
	line.add_theme_constant_override("separation",10)
	plot.add_child(line)
	var complete:=bool(shared.get("complete",false))
	var trellis:=SceneArt.prop_texture("community_flower_trellis") if complete and SceneArt.has_prop("community_flower_trellis") else null
	if trellis:line.add_child(Shell.picture(trellis,48))
	var words:=VBoxContainer.new()
	words.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override("separation",4)
	line.add_child(words)
	label(app,words,"公共花園：%s · 合力 %d 位"%["已開園 ✓" if complete else "整理中",int(shared.get("contributor_count",0))],14,OK_TINT if complete else BROWN).name="FlowerJournalGarden"
	var needs:=HFlowContainer.new()
	needs.add_theme_constant_override("h_separation",10)
	words.add_child(needs)
	var given:Dictionary=shared.get("given",{})
	for id in Flower.GARDEN_NEEDS:
		var bit:=HBoxContainer.new()
		bit.add_theme_constant_override("separation",3)
		needs.add_child(bit)
		picture_or_gap(bit,item_icon(id),24)
		var amount:=label(app,bit,"%d/%d"%[mini(int(given.get(id,0)),int(Flower.GARDEN_NEEDS[id])),int(Flower.GARDEN_NEEDS[id])],13,INK)
		amount.autowrap_mode=TextServer.AUTOWRAP_OFF
		amount.size_flags_vertical=Control.SIZE_SHRINK_CENTER
		amount.tooltip_text=item_name(id)
	# A word from whoever is waiting at the current step of the route.
	var current:=phase(snapshot,app.session.own_id)
	var who:=speaker_for(current)
	var said_text:=story_text(Flower.STORY.get(current,Flower.STORY.save))
	var note:=PanelContainer.new()
	note.name="FlowerStatusNote"
	note.add_theme_stylebox_override("panel",Folio.page_style())
	page.add_child(note)
	var note_words:=portrait_row(app,note,who[1],who[0],said_text,64)
	var said:=note_words.find_child("FlowerLine",false,false) as Label
	if said:
		said.add_theme_font_size_override("font_size",14)
		said.name="FlowerStatusLine"

## Right page "作物筆記": crop pages with growth art, plan text and own status,
## then the three recipes of the chapter.
static func plan_page(app,page:VBoxContainer,record:Dictionary)->void:
	for kind in Flower.FLOWERS:
		var line:=row(page,"FlowerPlan_"+kind)
		line.add_theme_constant_override("separation",8)
		icon_into(line,kind,48)
		var info:=VBoxContainer.new()
		info.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation",1)
		line.add_child(info)
		label(app,info,item_name(kind),14,INK)
		label(app,info,plan_text(kind),12,BROWN).name="FlowerPlanText_"+kind
		var marks:=PackedStringArray()
		for entry in status_mark(record,kind):marks.append("%s%s"%["✓" if entry[1] else "・",entry[0]])
		label(app,info," ".join(marks),12,OK_TINT if record.get("saved",{}).has(kind) else FADED).name="FlowerPlanStatus_"+kind
		var growth:=HBoxContainer.new()
		growth.name="FlowerGrowth_"+kind
		growth.add_theme_constant_override("separation",0)
		growth.size_flags_vertical=Control.SIZE_SHRINK_CENTER
		line.add_child(growth)
		if FlowerArt.has_crop(kind):
			for stage in range(4):
				var sprout:=FlowerArt.crop_texture(kind,stage)
				if sprout:growth.add_child(Shell.picture(sprout,24))
	label(app,page,"乾土上的花會暫停成長；記得澆水，或等雨水滋潤露天育苗床。",12,FADED).name="FlowerProvisional"
	var notes:=PanelContainer.new()
	notes.name="FlowerDesignNotes"
	notes.add_theme_stylebox_override("panel",Folio.story_style())
	page.add_child(notes)
	var choice:=VBoxContainer.new()
	choice.add_theme_constant_override("separation",3)
	notes.add_child(choice)
	var cookie:Dictionary=Flower.COOKIE.garden_cookie
	var cookie_line:="花園餅乾： "+"＋".join(PackedStringArray(cookie.ingredients.keys().map(func(id):return "%s %d"%[item_name(id),int(cookie.ingredients[id])])))+" → %d 份，%d 秒。"%[int(cookie.yield),int(cookie.time)]
	for entry in [[Flower.SEEDS[Flower.FLOWERS[0]],"FlowerDesignSave","留種方法： 1 朵成花 → 1 包同種種子，%d 秒。"%int(Flower.SAVE_SECONDS)],
			[str(Flower.DYE.item),"FlowerPlanDye","染料配方：鈴蘭藍花 %d → 藍色染料 %d。"%[int(Flower.DYE.ingredients.values()[0]),int(Flower.DYE.yield)]],
			["garden_cookie","FlowerDesignCookie",cookie_line]]:
		var recipe:=row(choice)
		recipe.add_theme_constant_override("separation",6)
		picture_or_gap(recipe,item_icon(entry[0]),24).size_flags_vertical=Control.SIZE_SHRINK_CENTER
		var text:=label(app,recipe,entry[2],12,INK)
		text.name=entry[1]
		text.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		text.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	label(app,choice,"麵粉來自公共廚房開張後的磨坊；花園餅乾不是本章必做。",12,FADED).name="FlowerCookieNote"

static func speaker_for(id:String)->Array:
	match id:
		"letter","locked":return ["小栗",LifeTheme.icon("xiaoli")]
		"report","complete","opening":return ["星禾",Lanyang.portrait()]
	return [FARMER_NAME,Resident.portrait_texture()]

## Right page "故事重看": bookmarks for unlocked lines, the speaker's portrait
## and the line itself. Replay is local to this screen.
static func story_page(app,page:VBoxContainer,record:Dictionary,shared:Dictionary)->void:
	var entries:=story_entries(record,shared)
	if entries.is_empty():
		portrait_row(app,page,Resident.portrait_texture(),FARMER_NAME,"讀過小栗的介紹信後，這裡會留下劇情。",64)
		var words:=page.find_child("FlowerLine",true,false)
		if words:words.name="FlowerStoryEmpty"
		return
	var chosen:String=app.modal.get_meta("flower_story",entries[-1].id)
	var picks:=HFlowContainer.new()
	picks.name="FlowerStoryPicks"
	picks.add_theme_constant_override("h_separation",4)
	picks.add_theme_constant_override("v_separation",4)
	page.add_child(picks)
	var shown:Dictionary=entries[-1]
	for entry in entries:
		var id:String=entry.id
		var button:=Helpers.action(app,picks,"FlowerStory_"+id,PHASE_SHORT.get(id,entry.title),func():
			app.modal.set_meta("flower_story",id)
			refresh(app),true)
		Folio.apply_tab(button)
		button.custom_minimum_size.y=28
		button.add_theme_font_size_override("font_size",13)
		button.tooltip_text=entry.title
		button.toggle_mode=true
		button.set_pressed_no_signal(id==chosen)
		if id==chosen:shown=entry
	var sheet:=PanelContainer.new()
	sheet.name="FlowerStorySheet"
	sheet.add_theme_stylebox_override("panel",Folio.story_style())
	page.add_child(sheet)
	var holder:=VBoxContainer.new()
	sheet.add_child(holder)
	var who:=speaker_for(shown.id)
	var words:=portrait_row(app,holder,who[1],who[0],shown.text,128)
	var line:=words.find_child("FlowerLine",false,false) as Label
	if line:line.name="FlowerStoryText"
	label(app,words,str(shown.title),12,FADED).name="FlowerStoryTitle"
	label(app,page,"重看只在你的畫面播放，不會改變進度。",12,FADED).name="FlowerStoryNote"
	# Pressed flowers along the foot of the page (decoration only).
	var filler:=Control.new()
	filler.size_flags_vertical=Control.SIZE_EXPAND_FILL
	filler.mouse_filter=Control.MOUSE_FILTER_IGNORE
	page.add_child(filler)
	var pressed:=HBoxContainer.new()
	pressed.name="FlowerStoryPressed"
	pressed.alignment=BoxContainer.ALIGNMENT_CENTER
	pressed.add_theme_constant_override("separation",28)
	pressed.mouse_filter=Control.MOUSE_FILTER_IGNORE
	page.add_child(pressed)
	for kind in Flower.FLOWERS:
		var bloom:=FlowerArt.crop_texture(kind,3) if FlowerArt.has_crop(kind) else null
		if bloom:pressed.add_child(Shell.picture(bloom,48))
