extends RefCounted
## 北門・鹽風合作鹽田介面（W5）。公開 API 比照 flower_nursery_ui.gd：
## unlocked(snapshot)、interaction_points(region)、open(app,site)、refresh(app)、
## layout(app,bounds)、chapter_link(app)、counter_link(app,content)、next_step(snapshot)。
## 只讀快照的 snapshot.salt_pan（公開）與 snapshot.salt_pan.own（契約修正 §7），以及時間／天氣。
##
## ── main.gd 需要的接線（由 flower_exec_salt_scene 加入；本檔不改 main.gd）──
##  1. 常數：        const SaltUI=preload("res://scripts/salt_pan_ui.gd")
##  2. _state_changed 與 _refresh_hud（FlowerUI.refresh(self) 之後）：SaltUI.refresh(self)
##  3. _interact：   points.merge(SaltUI.interaction_points(region))
##                   if closest.begins_with("salt:"):SaltUI.open(self,closest.trim_prefix("salt:"));return
##     （site 字串："worker"、"gate:G"、"pan:I"、"lot:L"、"lot:L:w"、"coop_chest"、"heritage"、"lot:8"）
##  4. _layout_preview 的 match：   "salt_pan":SaltUI.layout(self,bounds)
##  5. 章節手帳連結：FlowerUI.chapter_link(self) 之後 SaltUI.chapter_link(self)（按鈕 "ChapterSaltJournal"）
##  6. 小栗攤位：_shop() 在 FlowerUI.counter_link 之後 SaltUI.counter_link(self,content)
##                   （按鈕 "XiaoliSaltLetter" 開 "letter"，"XiaoliSaltOrder" 開 "order"）
##  7. _journal：region=="beimen" 時 SaltUI.open(self,"journal")
##  8. 鹽田對話框開著時隱藏與鹽田無關的世界提示：if SaltUI.suppress_world_prompts(self): ...
##     （modal 也帶 meta "suppress_world_prompts"=true）
##  9. 美術：SaltUI.art_provider=func(kind:String,id:String)->Texture2D（kind："portrait"、"pan"、
##     "heritage"、"status"）。未注入或回傳 null 時：肖像只顯示名牌，鹽田用像素示意圖。
## 送出動作一律經 send()：預設 app.session.perform(action,cell,extra)；測試可設 action_sink。

const Salt=preload("res://scripts/salt_pan.gd")
const Flower=preload("res://scripts/flower_nursery.gd")
const FlowerUI=preload("res://scripts/flower_nursery_ui.gd")
const Items=preload("res://scripts/inventory_item_art.gd")
const Pixel=preload("res://scripts/inventory_pixel_theme.gd")
const Shell=preload("res://scripts/life_ui_shell.gd")
const LifeTheme=preload("res://scripts/life_ui_theme.gd")
const Helpers=preload("res://scripts/freight_ui.gd")
const Folio=preload("res://scripts/kitchen_folio_art.gd")
const Revisit=preload("res://scripts/salt_revisit_ui.gd")
const LAYOUT:="salt_pan"
const REGION:="beimen"
const WORKER_NAME:="阿曬"
const XIAOLI_NAME:="小栗"
const PORTRAIT:=64
const NEAR_REASON:="請走近一點再操作。"
const KEY_HINT:="Tab 切換 · E 或 Enter 確認 · Esc 回到島上"
const INTRO_REASON:="先到工寮旁和阿曬打聲招呼。"
const GATE_REASON:="三道閘門修好之後，鹽田才引得進海水。"
const RAIN_FLOOD_REASON:="下雨天先不引海水，雨停再來。"
const OTHER_REASON:="這是其他島民照顧的鹽田。"
const ORIGINAL_NOTE:="鹽風合作鹽田、阿曬與水車收鹽台是遊戲原創；井仔腳瓦盤鹽田是今日保存的文化景觀"
const RAIN_PAN_NOTE:="下雨了：引水先暫停；已經成的鹽蓋上草蓆，不會流失，照樣可以收。"
const TITLES:={"letter":"北門寄來的信","worker":"鹽風合作鹽田・阿曬","gate":"三道閘門","pan":"鹽田","lot":"鹽田區","order":"小栗的海鹽委託","coop_chest":"合作社收鹽箱","heritage":"井仔腳瓦盤鹽田觀景區","journal":"北門瓦盤鹽田・手帳"}
const SIZES:={"letter":Vector2(760,320),"worker":Vector2(760,320),"gate":Vector2(940,560),"pan":Vector2(560,470),"lot":Vector2(580,600),"order":Vector2(600,460),"coop_chest":Vector2(500,340),"heritage":FlowerUI.BOOK_SIZE,"journal":FlowerUI.BOOK_SIZE}
const PHASES:=["locked","letter","travel","intro","gates","first_salt","claim","wheel","rake","automate","order","report","complete"]
const PHASE_SHORT:={"letter":"收信","travel":"南下","intro":"見面","gates":"閘門","first_salt":"收鹽","claim":"認領","wheel":"水車","rake":"收鹽台","automate":"自動","order":"委託","report":"回報","complete":"完成"}
const ROUTE:=["letter","travel","intro","gates","first_salt","claim","wheel","rake","automate","order","report"]
const MATERIALS:=["plank","resin","stone"]
## Own retained machine kits shown in the cooperative chest (staged escrow; same ids as the items).
const KIT_IDS:=["salt_wheel_kit","salt_rake_kit"]
const TAKE_FULL_REASON:="背包的這些物品已達上限，先整理背包再來取。"
const TAKE_EMPTY_REASON:="你的格子裡還沒有海鹽或機器組。"
const NAMES:={"plank":"木板","resin":"樹脂","stone":"石材","sea_salt":"海鹽","salt_wheel_kit":"鹽田水車組","salt_rake_kit":"收鹽台組","salt_grilled_fish":"香煎溪魚","copper_joint":"銅接頭","fiber":"纖維","minnow":"銀線溪魚","coins":"鈴幣"}
## Every status id the server can report (契約修正 §2) plus the public pool's reserve.
const STATUS_IDS:=["unset","off","invalid","owner","full","rain","waiting","running","wheel_only","reserve","manual"]
const STATUS_ICONS:={"unset":"chest","off":"bell","invalid":"sign","owner":"home","full":"chest","rain":"weather","waiting":"calendar","running":"harvest","wheel_only":"water","reserve":"hoe","manual":"hoe"}
const STATUS_TINTS:={"running":Color("dfeccf"),"waiting":Color("e8eef0"),"wheel_only":Color("e8eef0"),"manual":Color("efe4cb"),"rain":Color("dde6ef"),"reserve":Color("efe4cb")}
## Paraphrased from work/salt/geography-evidence.json verified_sources (root browse 2026-11-14).
const FACTS:=["井仔腳前身是清代的瀨東鹽場，因水患於1818年遷至現址，成為北門的第一座鹽田。",
	"今日保存下來的瓦盤鹽田，讓人參觀並體驗傳統的日曬收鹽。",
	"遊戲裡的引海水、日曬、收鹽三步驟是簡化的玩法；水量、天數與產量都不是真實的工法或產量。"]
const SOURCES:=[["交通部觀光署雲嘉南濱海國家風景區管理處","https://www.swcoast-nsa.gov.tw/zh-tw/attraction/details/369"],
	["交通部觀光署","https://www.tad.gov.tw/m1.aspx?id=A12-00023&sno=0001016"],
	["臺南市北門區公所","https://beimen.tainan.gov.tw/cp.aspx?n=6186"]]
const INK:=Color("3d422d")
const BROWN:=Color("7a4e2b")
const FADED:=Color("8f7a5e")
const OK_TINT:=Color("3e664b")
const WARN_TINT:=Color("9c4b32")
const SEA:=Color("5f9fb0")

## Optional art injection: func(kind:String,id:String)->Texture2D. Null => name plate / pixel preview.
static var art_provider:Callable
## Optional action interception: func(action:String,cell:Vector2i,extra:String)->void.
static var action_sink:Callable

# ── 純資料 ─────────────────────────────────────────────────

static func shared(snapshot:Dictionary)->Dictionary:
	var value=snapshot.get("salt_pan",{})
	return value if value is Dictionary else {}

static func own(snapshot:Dictionary)->Dictionary:
	var value=shared(snapshot).get("own",{})
	return value if value is Dictionary else {}

static func own_record(snapshot:Dictionary)->Dictionary:
	var value=own(snapshot).get("record",{})
	return value if value is Dictionary else {}

static func phase(snapshot:Dictionary)->String:
	var mine:=own(snapshot)
	if mine.is_empty():return "locked"
	return str(mine.get("phase","locked"))

static func unlocked(snapshot:Dictionary)->bool:
	return phase(snapshot)!="locked"

static func reached(snapshot:Dictionary,id:String)->bool:
	return PHASES.find(phase(snapshot))>=PHASES.find(id)

static func next_step(snapshot:Dictionary)->Dictionary:
	var guide=own(snapshot).get("guidance",{})
	return guide if guide is Dictionary else {}

static func item_name(id:String)->String:
	return NAMES.get(id,id)

static func item_icon(id:String)->Texture2D:
	return Items.icon(id)

static func art(kind:String,id:String)->Texture2D:
	if art_provider.is_valid():
		var texture=art_provider.call(kind,id)
		if texture is Texture2D:return texture
	return null

static func portrait(id:String)->Texture2D:
	if id=="xiaoli":return LifeTheme.icon("xiaoli")
	return art("portrait",id)

static func story_text(value)->String:
	return FlowerUI.story_text(value)

static func story(id:String)->String:
	return story_text(Salt.STORY.get(id,"")) if Salt.STORY.has(id) else ""

static func status_text(status:Dictionary)->String:
	var id:=str(status.get("id",""))
	var text:=str(status.get("text",""))
	if text.is_empty():text=str(Salt.STATUS_TEXT.get(id,""))
	return text

static func cell_key(cell:Vector2i)->String:
	return "%d,%d"%[cell.x,cell.y]

static func parse_cell(value)->Vector2i:
	if value is Vector2i:return value
	if value is Vector2:return Vector2i(value)
	var text:=str(value)
	if text.count(",")!=1:return Vector2i(-1,-1)
	var parts:=text.split(",")
	if not parts[0].strip_edges().is_valid_int() or not parts[1].strip_edges().is_valid_int():return Vector2i(-1,-1)
	return Vector2i(int(parts[0]),int(parts[1]))

static func cfg_extra(chest:Vector2i,cap:int)->String:
	return "%d,%d|%d"%[chest.x,chest.y,clamp_cap(cap)]

static func clamp_cap(cap:int)->int:
	return clampi(cap,int(Salt.CAP_MIN),int(Salt.CAP_MAX))

static func site_kind(site:String)->String:
	return site.get_slice(":",0)

static func site_index(site:String)->int:
	var part:=site.get_slice(":",1) if site.contains(":") else ""
	return int(part) if part.is_valid_int() else -1

static func rect_center(rect:Rect2i)->Vector2:
	return Vector2(rect.position)+Vector2(rect.size)/2.0

static func gate_rect(gate:int)->Rect2i:
	return Rect2i(8,int(Salt.GATE_ROWS[gate])+1,2,1)

static func interaction_points(region:String)->Dictionary:
	var points:Dictionary={}
	if region!=REGION:return points
	points["salt:worker"]=Vector2(Salt.SALT_WORKER)+Vector2(0.5,0.5)
	for gate in range(Salt.GATE_ROWS.size()):points["salt:gate:%d"%gate]=rect_center(gate_rect(gate))
	for pan in range(Salt.PAN_COUNT):points["salt:pan:%d"%pan]=rect_center(Salt.pan_rect(pan))
	for lot in range(Salt.LOT_COUNT):
		points["salt:lot:%d"%lot]=rect_center(Salt.rake_socket(lot))
		points["salt:lot:%d:w"%lot]=rect_center(Salt.wheel_socket(lot))
	points["salt:lot:%d"%Salt.APPRENTICE_LOT]=rect_center(Salt.rake_socket(Salt.APPRENTICE_LOT))
	points["salt:lot:%d:w"%Salt.APPRENTICE_LOT]=rect_center(Salt.wheel_socket(Salt.APPRENTICE_LOT))
	points["salt:lot:%d"%Salt.PUBLIC_LOT]=Vector2(Salt.PUBLIC_SIGN)+Vector2(0.5,0.5)
	points["salt:coop_chest"]=Vector2(Salt.APPRENTICE_CHEST)+Vector2(0.5,0.5)
	points["salt:heritage"]=Vector2(Salt.HERITAGE_SIGN)+Vector2(0.5,0.5)
	return points

static func site_region(site:String)->String:
	match site_kind(site):
		"letter","order":return "home"
		"journal":return ""
	return REGION

## Representative cell of the place the panel was opened for (nearness + default target).
static func site_cell(site:String)->Vector2i:
	var index:=site_index(site)
	match site_kind(site):
		"letter","order":return Flower.RECEIVER_HOME
		"worker":return Salt.SALT_WORKER
		"gate":return gate_rect(clampi(index,0,Salt.GATE_ROWS.size()-1)).position
		"pan":return Salt.pan_rect(clampi(index,0,Salt.PAN_COUNT-1)).position
		"lot":
			if index==Salt.PUBLIC_LOT:return Salt.PUBLIC_SIGN
			return Salt.rake_socket(clampi(index,0,Salt.APPRENTICE_LOT)).position
		"coop_chest":return Salt.APPRENTICE_CHEST
		"heritage":return Salt.HERITAGE_SIGN
	return Vector2i(-1,-1)

## The cell of `rect` nearest the player: the server accepts any cell of the facility.
static func nearest_cell(rect:Rect2i,pos:Vector2)->Vector2i:
	var best:=rect.position
	var gap:=INF
	for y in range(rect.position.y,rect.end.y):
		for x in range(rect.position.x,rect.end.x):
			var d:=pos.distance_to(Vector2(x,y)+Vector2(0.5,0.5))
			if d<gap:
				gap=d
				best=Vector2i(x,y)
	return best

static func pan_owner_ok(snapshot:Dictionary,pan:int)->bool:
	var lot:=pan/2
	var mine:=own(snapshot)
	if lot==Salt.PUBLIC_LOT:return true
	if lot==Salt.APPRENTICE_LOT:return bool(mine.get("apprentice",{}).get("mine",false))
	var lots:Array=shared(snapshot).get("lots",[])
	if lot<lots.size() and bool(lots[lot].get("mine",false)):return true
	return int(mine.get("lot",-1))==lot

static func pan_view(snapshot:Dictionary,pan:int)->Dictionary:
	var pans:Array=shared(snapshot).get("pans",[])
	var data:Dictionary=pans[pan] if pan<pans.size() and pans[pan] is Dictionary else {"s":"empty","p":0.0,"t":0.0,"f":"hand"}
	var view=Salt.pan_view(data,float(snapshot.get("time",0.0)))
	return view if view is Dictionary else {"s":"empty","ratio":0.0,"diluted":false,"covered":false,"eta_minutes":-1}

static func pan_state_text(view:Dictionary)->String:
	match str(view.get("s","empty")):
		"brine":
			var percent:=int(floor(clampf(float(view.get("ratio",0.0)),0.0,1.0)*100.0))
			return ("滷水被雨水稀釋 %d%%" if view.get("diluted",false) else "滷水 %d%%")%percent
		"salt":return "成鹽・草蓆覆蓋中" if view.get("covered",false) else "白白的成鹽"
	return "空鹽田"

static func eta_text(view:Dictionary,weather:Dictionary)->String:
	var state:=str(view.get("s","empty"))
	if state=="salt":return "可以收鹽了"
	if state!="brine":return "引海水後開始曬"
	if bool(weather.get("raining",false)):return "雨停後繼續曬"
	var minutes:=int(view.get("eta_minutes",-1))
	if minutes<0:return "天氣好轉後繼續曬"
	return "%s約 %d 分鐘成鹽"%[str(weather.get("label","今天")),minutes]

static func kit_spec(kit:String)->Dictionary:
	var spec=Salt.CRAFT.get(kit,{})
	if not (spec is Dictionary):return {}
	var inputs=spec.get("ingredients",spec)
	return inputs if inputs is Dictionary else {}

static func craft_hint(snapshot:Dictionary,kit:String)->String:
	if not bool(own(snapshot).get("can_craft",{}).get(kit,false)):return str(Salt.CRAFT_LOCKED_MESSAGE)
	var parts:=PackedStringArray()
	var inputs:=kit_spec(kit)
	for id in inputs:parts.append("%s %d"%[item_name(str(id)),int(inputs[id])])
	return "回家的工作台可做%s：%s"%[item_name(kit),"、".join(parts)]

static func gate_take(gates:Array,gate:int,bag:Dictionary,id:String)->int:
	var given:Dictionary=gates[gate] if gate<gates.size() and gates[gate] is Dictionary else {}
	var need:=int(Salt.GATE_NEEDS_EACH.get(id,0))
	return maxi(0,mini(need-int(given.get(id,0)),int(bag.get(id,0))))

static func gate_done(gates:Array,gate:int)->bool:
	var given:Dictionary=gates[gate] if gate<gates.size() and gates[gate] is Dictionary else {}
	for id in MATERIALS:
		if int(given.get(id,0))<int(Salt.GATE_NEEDS_EACH.get(id,0)):return false
	return true

static func repaired(snapshot:Dictionary)->bool:
	var value=shared(snapshot).get("repaired",false)
	if value is bool:return value
	return float(value)>=0.0

# ── main.gd 掛點 ───────────────────────────────────────────

static func is_open(app)->bool:
	return is_instance_valid(app.modal) and app.modal.has_meta("salt_site")

## True while a salt panel is open; the scene hides unrelated world prompts then.
static func suppress_world_prompts(app)->bool:
	return is_open(app)

static func send(app,action:String,cell:Vector2i,extra:String="")->void:
	if action_sink.is_valid():
		action_sink.call(action,cell,extra)
		return
	app.session.perform(action,cell,extra)

static func counter_link(app,content:VBoxContainer)->void:
	var snapshot:Dictionary=app.session.snapshot
	if not unlocked(snapshot) or content.find_child("XiaoliSaltLetter",true,false):return
	var holder:Node=content.find_child("ShopCounter",false,false)
	if holder==null:holder=content
	var letter:Button=app.button("北門寄來的信",func():open(app,"letter"))
	letter.name="XiaoliSaltLetter"
	letter.icon=Shell.icon("letter")
	holder.add_child(letter)
	if bool(own_record(snapshot).get("letter",false)):
		var order:Button=app.button("海鹽委託",func():open(app,"order"))
		order.name="XiaoliSaltOrder"
		order.icon=Folio.life_icon("chest")
		holder.add_child(order)
	if holder==content:
		content.move_child(letter,0)

static func chapter_link(app)->void:
	if not unlocked(app.session.snapshot) or not is_instance_valid(app.modal) or not app.modal.has_meta("chapter_content"):return
	var content:VBoxContainer=app.modal.get_meta("chapter_content")
	if content.find_child("ChapterSaltJournal",false,false):return
	var link:Button=app.button("北門鹽風合作鹽田手帳",func():open(app,"journal"))
	link.name="ChapterSaltJournal"
	link.icon=Shell.icon("letter")
	content.add_child(link)

static func layout(app,bounds:Vector2)->void:
	if not is_open(app):return
	var kind:=site_kind(str(app.modal.get_meta("salt_site","")))
	var wanted:Vector2=SIZES.get(kind,Vector2(640,480))
	var height:=wanted.y
	if not kind in ["journal","heritage"]:
		var fitted:=FlowerUI.content_height(app)
		if fitted>0.0:height=minf(wanted.y,fitted)
	app.modal.size=Vector2(minf(wanted.x,bounds.x-48),minf(height,bounds.y-48))
	app.modal.position=((bounds-app.modal.size)/2).floor()
	if kind in ["letter","worker"]:app.modal.position.y=bounds.y-app.modal.size.y-24
	elif kind=="lot":app.modal.position.x=bounds.x-app.modal.size.x-24

# ── 開啟與刷新 ─────────────────────────────────────────────

static func open(app,site:String,_cell:=Vector2i.ZERO)->void:
	var kind:=site_kind(site)
	if not TITLES.has(kind):return
	var title:String=TITLES[kind]
	var index:=site_index(site)
	if kind=="lot":title=lot_title(index)
	elif kind=="pan":title="鹽田 %d"%(index+1)
	var body:VBoxContainer=app._open_modal(title)
	app.modal.theme=Pixel.make(app.hud.theme)
	app.modal.add_theme_stylebox_override("panel",Pixel.frame_style())
	app.modal.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	app.modal.set_meta("life_modal_layout",LAYOUT)
	app.modal.set_meta("salt_body",body)
	app.modal.set_meta("salt_site",site)
	app.modal.set_meta("suppress_world_prompts",true)
	if kind in ["letter","worker"] and is_instance_valid(app.modal_shade):app.modal_shade.color.a=0.24
	var shell:=app.modal.get_child(0) as VBoxContainer
	if shell:shell.add_theme_constant_override("separation",6)
	if kind in ["journal","heritage"]:FlowerUI.book_chrome(app,shell)
	refresh(app)
	focus_first(app)
	app._layout_preview.call_deferred()

static func lot_title(lot:int)->String:
	if lot==Salt.PUBLIC_LOT:return "保留手作池"
	if lot==Salt.APPRENTICE_LOT:return "合作社學徒區"
	return "第 %d 鹽田區"%(lot+1)

static func refresh(app)->void:
	if not is_open(app):return
	var snapshot:Dictionary=app.session.snapshot
	var own_id:String=app.session.own_id
	var actor:Dictionary=snapshot.get("players",{}).get(own_id,{})
	var site:String=app.modal.get_meta("salt_site")
	var kind:=site_kind(site)
	var view_state:={"tab":app.modal.get_meta("salt_tab","memory"),"story":app.modal.get_meta("salt_story",""),"chest":app.modal.get_meta("salt_chest",""),"cap":app.modal.get_meta("salt_cap",-1)}
	var fingerprint:=JSON.stringify([shared(snapshot),snapshot.get("salt_revisit",{}),actor.get("inventory",{}),actor.get("coins",0),actor.get("x",0),actor.get("y",0),snapshot.get("region_id",""),floor(float(snapshot.get("time",0))/60.0),view_state])
	if app.modal.get_meta("salt_fingerprint","")==fingerprint:return
	app.modal.set_meta("salt_fingerprint",fingerprint)
	var body:VBoxContainer=app.modal.get_meta("salt_body")
	var viewport:=body.get_viewport()
	var focus:=viewport.gui_get_focus_owner() if viewport else null
	var focus_name:String=focus.name if is_instance_valid(focus) and body.is_ancestor_of(focus) else ""
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()
	var pos:=Vector2(float(actor.get("x",-100.0)),float(actor.get("y",-100.0)))
	var ctx:={"app":app,"snapshot":snapshot,"own":own(snapshot),"record":own_record(snapshot),"shared":shared(snapshot),
		"bag":actor.get("inventory",{}),"coins":int(actor.get("coins",0)),"now":float(snapshot.get("time",0.0)),
		"pos":pos,"region":str(snapshot.get("region_id","home")),"site":site,"index":site_index(site),"has_actor":not actor.is_empty()}
	if kind in ["journal","heritage"]:
		journal(ctx,body)
	else:
		var card:=PanelContainer.new()
		card.name="SaltCard"
		card.add_theme_stylebox_override("panel",Pixel.paper_style())
		body.add_child(card)
		var page:=VBoxContainer.new()
		page.name="SaltPage"
		page.add_theme_constant_override("separation",7)
		card.add_child(page)
		match kind:
			"letter":letter_panel(ctx,page)
			"worker":worker_panel(ctx,page)
			"gate":gate_panel(ctx,page)
			"pan":pan_panel(ctx,page)
			"lot":lot_panel(ctx,page)
			"order":order_panel(ctx,page)
			"coop_chest":coop_panel(ctx,page)
		# Key hint once per panel: later refreshes must not erase the server's answer to an
		# action (e.g. a refused take with a full bag) that main.gd shows in the same line.
		if is_instance_valid(app.modal_feedback) and not app.modal.has_meta("salt_hint_shown"):
			app.modal.set_meta("salt_hint_shown",true)
			app.modal_feedback.text=KEY_HINT
	wire_keys(app,body)
	FlowerUI.restore_focus(body,focus_name)
	app._layout_preview.call_deferred()

static func focus_first(app)->void:
	if not is_open(app):return
	var body:Control=app.modal.get_meta("salt_body")
	for button:BaseButton in body.find_children("*","BaseButton",true,false):
		if not button.disabled and button.is_visible_in_tree():
			button.grab_focus.call_deferred()
			return

## E (the interact binding) activates the focused button, like Enter.
static func wire_keys(app,body:Control)->void:
	for button:BaseButton in body.find_children("*","BaseButton",true,false):
		if button.has_meta("salt_keys"):continue
		button.set_meta("salt_keys",true)
		button.focus_mode=Control.FOCUS_ALL
		button.gui_input.connect(func(event:InputEvent):
			if is_interact_key(app,event) and not button.disabled:
				button.accept_event()
				button.pressed.emit())

static func is_interact_key(app,event:InputEvent)->bool:
	if not (event is InputEventKey) or not event.pressed or event.echo:return false
	var key:=event as InputEventKey
	var bindings=app.get("bindings")
	# The binding API is authoritative: a rebound interact never also answers to E.
	if bindings!=null and bindings.has_method("matches"):return bindings.matches("interact",key)
	# No binding API (bare test hosts): logical E only, unmodified, matching matches().
	if key.ctrl_pressed or key.alt_pressed or key.meta_pressed:return false
	return key.keycode==KEY_E

# ── 元件 ───────────────────────────────────────────────────

static func label(app,parent:Node,value:String,size:int=15,tint=null)->Label:
	var result:=Helpers.text(app,parent,value,size)
	if tint is Color:result.add_theme_color_override("font_color",tint)
	return result

static func tight(app,parent:Node,value:String,size:int=14,tint=null)->Label:
	var result:=label(app,parent,value,size,tint)
	result.autowrap_mode=TextServer.AUTOWRAP_OFF
	result.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	result.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	return result

static func row(parent:Node,name:String="",gap:int=8)->HBoxContainer:
	var result:=HBoxContainer.new()
	if not name.is_empty():result.name=name
	result.add_theme_constant_override("separation",gap)
	parent.add_child(result)
	return result

static func column(parent:Node,name:String="",gap:int=4)->VBoxContainer:
	var result:=VBoxContainer.new()
	if not name.is_empty():result.name=name
	result.add_theme_constant_override("separation",gap)
	parent.add_child(result)
	return result

static func tile(parent:Node,name:String,fill:Color,border:Color)->PanelContainer:
	var result:=PanelContainer.new()
	result.name=name
	result.add_theme_stylebox_override("panel",LifeTheme.surface(fill,border,6,5))
	parent.add_child(result)
	return result

static func icon_into(parent:Node,id:String,extent:int=32)->TextureRect:
	var texture:=item_icon(id)
	if texture==null:return null
	var picture:=Shell.picture(texture,extent)
	picture.name="Icon_"+id
	picture.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	parent.add_child(picture)
	return picture

static func near(ctx:Dictionary,cell:Vector2i,region:String=REGION)->bool:
	if not ctx.has_actor or ctx.region!=region:return false
	return Vector2(ctx.pos).distance_to(Vector2(cell)+Vector2(0.5,0.5))<=3.2

## Button that sends one contract action. A disabled button always shows its reason
## (tooltip + sibling label <id>Reason). Nearness is checked against the target cell.
static func act(ctx:Dictionary,parent:Node,id:String,title:String,action:String,cell:Vector2i,extra:String,reason:String,region:String=REGION,show_reason:=true)->Button:
	var app=ctx.app
	var why:=reason
	if why.is_empty() and not near(ctx,cell,region):why=NEAR_REASON
	var button:=Helpers.action(app,parent,id,title,func():send(app,action,cell,extra),why.is_empty())
	button.set_meta("salt_action",action)
	button.set_meta("salt_cell",cell)
	button.set_meta("salt_extra",extra)
	button.tooltip_text=why if not why.is_empty() else title
	button.accessibility_name=title+("（"+why+"）" if not why.is_empty() else "")
	if not why.is_empty() and show_reason:
		var note:=label(app,parent,why,12,WARN_TINT)
		note.name=id+"Reason"
		note.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	return button

static func local(ctx:Dictionary,parent:Node,id:String,title:String,callback:Callable,enabled:=true)->Button:
	var button:=Helpers.action(ctx.app,parent,id,title,callback,enabled)
	return button

## 64px portrait slot. No art => the name plate only (never a coloured stand-in).
static func speaker(ctx:Dictionary,parent:Node,id:String,name:String,line:String)->VBoxContainer:
	var app=ctx.app
	var line_row:=row(parent,"SaltSpeaker",12)
	var texture:=portrait(id)
	if texture:
		var frame:=PanelContainer.new()
		frame.name="SaltPortraitFrame"
		frame.add_theme_stylebox_override("panel",Folio.portrait_style())
		frame.size_flags_vertical=Control.SIZE_SHRINK_BEGIN
		line_row.add_child(frame)
		var face:=Shell.picture(texture,PORTRAIT)
		face.name="SaltPortrait"
		frame.add_child(face)
	var words:=VBoxContainer.new()
	words.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override("separation",4)
	line_row.add_child(words)
	var plate:=PanelContainer.new()
	plate.name="SaltNamePlate"
	plate.add_theme_stylebox_override("panel",Folio.ribbon_style())
	plate.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	words.add_child(plate)
	var plate_text:=tight(app,plate,name,15,Folio.RIBBON_INK)
	plate_text.name="SaltSpeakerName"
	label(app,words,line,15,INK).name="SaltLine"
	return words

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

## Status chip: icon + text for every status id (and the public pool's reserve).
static func status_chip(ctx:Dictionary,parent:Node,status:Dictionary)->PanelContainer:
	var app=ctx.app
	var id:=str(status.get("id",""))
	var fill:Color=STATUS_TINTS.get(id,Color("f6dcc0") if id in ["invalid","owner","full","unset"] else Color("f3e7c9"))
	var chip:=tile(parent,"SaltStatusChip",fill,fill.darkened(0.3))
	chip.set_meta("status_id",id)
	var line:=row(chip,"",6)
	var texture:=art("status",id)
	if texture==null:texture=Folio.life_icon(str(STATUS_ICONS.get(id,"sign")))
	if texture:
		var picture:=Shell.picture(texture,20)
		picture.name="SaltStatusIcon"
		picture.size_flags_vertical=Control.SIZE_SHRINK_CENTER
		line.add_child(picture)
	var text:=label(app,line,status_text(status),13,INK)
	text.name="SaltStatusText"
	text.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	return chip

# ── 對話（小栗・阿曬） ─────────────────────────────────────

static func letter_panel(ctx:Dictionary,page:VBoxContainer)->void:
	var current:=phase(ctx.snapshot)
	var line:=story("letter") if unlocked(ctx.snapshot) else story("locked")
	var words:=speaker(ctx,page,"xiaoli",XIAOLI_NAME,line)
	if bool(ctx.record.get("letter",false)):
		label(ctx.app,words,"信已收下，可從手帳重看。",13,OK_TINT).name="SaltLetterDone"
		return
	var reason:=""
	if current=="locked":reason="田尾公共花園開花之後，小栗才會收到這封信。"
	elif current!="letter":reason="信已經收過了。"
	var line_row:=row(words,"SaltLetterActions")
	act(ctx,line_row,"SaltLetter","收下北門的信","salt_letter",Flower.RECEIVER_HOME,"",reason,"home")

static func worker_panel(ctx:Dictionary,page:VBoxContainer)->void:
	var app=ctx.app
	var current:=phase(ctx.snapshot)
	var guide:=next_step(ctx.snapshot)
	var line:=story(current)
	if line.is_empty():line=str(guide.get("text",""))
	var words:=speaker(ctx,page,"salt_worker",WORKER_NAME,line)
	if current!="complete" and not str(guide.get("text","")).is_empty() and str(guide.get("text",""))!=line:
		label(app,words,"下一步："+str(guide.get("text","")),13,BROWN).name="SaltWorkerNext"
	var actions:=HFlowContainer.new()
	actions.name="SaltWorkerActions"
	actions.add_theme_constant_override("h_separation",8)
	actions.add_theme_constant_override("v_separation",6)
	words.add_child(actions)
	if current=="intro" or (not bool(ctx.record.get("intro",false)) and reached(ctx.snapshot,"intro")):
		act(ctx,actions,"SaltIntro","和阿曬打招呼","salt_intro",Salt.SALT_WORKER,"","",REGION,false)
	elif current=="report":
		act(ctx,actions,"SaltReport","告訴阿曬委託送到了","salt_report",Salt.SALT_WORKER,"","",REGION,false)
	elif current in ["locked","letter","travel"]:
		label(app,words,"先收下小栗轉來的信，再一路南下到北門。",13,WARN_TINT).name="SaltWorkerLocked"
	if current=="gates":
		local(ctx,actions,"SaltOpenGates","看三道閘門",func():open(app,"gate:0"))
	var book:=local(ctx,actions,"SaltJournal","翻閱鹽田手帳",func():open(app,"journal"))
	book.icon=Folio.life_icon("journal")
	book.expand_icon=true
	book.add_theme_constant_override("icon_max_width",20)
	# 第 40 章臺南北門回訪：認識阿曬之後多一個「臺南北門回訪・鹽籃批次」（閘門修好前寫明鎖定）。
	if bool(ctx.record.get("intro",false)):actions.add_child(Revisit.entry_button(app,"worker"))
	var nudge:=actions.find_child("SaltIntro",false,false) as Button
	if nudge==null:nudge=actions.find_child("SaltReport",false,false) as Button
	if nudge and nudge.disabled:
		label(app,words,nudge.tooltip_text,12,WARN_TINT).name=nudge.name+"Reason"

# ── 閘門 ───────────────────────────────────────────────────

static func gate_panel(ctx:Dictionary,page:VBoxContainer)->void:
	var app=ctx.app
	var data:Dictionary=ctx.shared
	var gates:Array=data.get("gates",[])
	var bag:Dictionary=ctx.bag
	var all_done:=repaired(ctx.snapshot)
	var head:=row(page,"SaltGateHead")
	var title:=tight(app,head,"✓ 三道閘門都修好了" if all_done else "閘門需要木板、樹脂和石材，可以分次帶來",15,OK_TINT if all_done else BROWN)
	title.name="SaltGateTitle"
	var strip:=row(page,"SaltGateRow",8)
	for gate in range(Salt.GATE_ROWS.size()):
		var done:=gate_done(gates,gate)
		var card:=tile(strip,"SaltGate_%d"%gate,Color("e6f0d6") if done else Color("fbefcf"),OK_TINT if done else Color("c49a6c"))
		card.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		var stack:=column(card,"",5)
		var top:=row(stack,"",6)
		tight(app,top,"第 %d 道閘門"%(gate+1),15,INK).name="SaltGateName_%d"%gate
		if done:
			var stamp:=badge(app,top,"SaltGateStamp_%d"%gate,"✓ 已修好",Color("dfeccf"),OK_TINT)
			stamp.accessibility_name="第 %d 道閘門已修好"%(gate+1)
		var given:Dictionary=gates[gate] if gate<gates.size() and gates[gate] is Dictionary else {}
		var target:=nearest_cell(gate_rect(gate),ctx.pos)
		for id in MATERIALS:
			var need:=int(Salt.GATE_NEEDS_EACH.get(id,0))
			var have:=mini(int(given.get(id,0)),need)
			var line:=row(stack,"SaltGateNeed_%d_%s"%[gate,id],6)
			icon_into(line,id,32)
			var info:=column(line,"",1)
			info.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			tight(app,info,item_name(id),13,INK)
			tight(app,info,"%d／%d%s"%[have,need," ✓" if have>=need else ""],12,OK_TINT if have>=need else BROWN).name="SaltGateCount_%d_%s"%[gate,id]
			if have>=need:continue
			var take:=gate_take(gates,gate,bag,id)
			var why:=""
			if not bool(ctx.record.get("intro",false)):why=INTRO_REASON
			elif int(bag.get(id,0))<=0:why="背包沒有%s"%item_name(id)
			elif not near(ctx,target):why="走到這道閘門旁"
			var give:=act(ctx,line,"SaltGive_%d_%s"%[gate,id],"捐 %d"%take if take>0 else "捐出","salt_gate_give",target,id,why,REGION,false)
			give.custom_minimum_size.x=64
			give.size_flags_vertical=Control.SIZE_SHRINK_CENTER
		var hint:=label(app,stack,"",11,WARN_TINT)
		hint.name="SaltGateHint_%d"%gate
		if not done and not bool(ctx.record.get("intro",false)):hint.text=INTRO_REASON
		elif not done and not near(ctx,target):hint.text="走到這道閘門旁再捐"
		else:hint.text="捐的數量只算還缺的部分" if not done else "海水從這裡引進鹽田"
	var foot:=row(page,"SaltGateFoot")
	tight(app,foot,"已有 %d 位島民出過力"%int(data.get("giver_count",0)),14,BROWN).name="SaltGiverCount"
	if all_done:badge(app,foot,"SaltRepairedStamp","閘門已開",Color("dfeccf"),OK_TINT,Folio.life_icon("trophy"))

# ── 鹽田小卡 ───────────────────────────────────────────────

class PanPreview extends Control:
	var state:="empty"
	var ratio:=0.0
	var covered:=false
	var diluted:=false
	var raining:=false
	func _init()->void:
		custom_minimum_size=Vector2(120,80)
		mouse_filter=Control.MOUSE_FILTER_IGNORE
		texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	func _draw()->void:
		var u:=4.0
		var full:=Rect2(Vector2.ZERO,size)
		draw_rect(full,Color("8a5a34"))
		draw_rect(full.grow(-u),Color("b78a58"))
		var bed:=full.grow(-u*2)
		draw_rect(bed,Color("9a8f7e"))
		var y:=bed.position.y
		var row_index:=0
		while y<bed.end.y:
			var x:=bed.position.x+(u*2 if row_index%2==1 else 0.0)
			while x<bed.end.x:
				draw_rect(Rect2(Vector2(x,y),Vector2(minf(u*4-1,bed.end.x-x),minf(u*2-1,bed.end.y-y))),Color("a99f8d"))
				x+=u*4
			y+=u*2
			row_index+=1
		if state=="brine":
			var water:=Color("6fa9b8")
			water.a=0.85-0.35*ratio
			draw_rect(bed,water)
			var band:=Rect2(bed.position.x,bed.end.y-u,bed.size.x*clampf(ratio,0.0,1.0),u)
			draw_rect(band,Color("eef4f2"))
		elif state=="salt":
			for py in range(int(bed.position.y)+2,int(bed.end.y)-2,int(u*2)):
				for px in range(int(bed.position.x)+2+(py%3),int(bed.end.x)-2,int(u*2)):
					draw_rect(Rect2(px,py,u,u),Color("f7f5ee"))
			if covered:
				var mat:=bed.grow(-u)
				draw_rect(mat,Color("c9a24f"))
				var sx:=mat.position.x
				while sx<mat.end.x:
					draw_rect(Rect2(sx,mat.position.y,1,mat.size.y),Color("a57f35"))
					sx+=u
		if raining or diluted:
			for i in range(9):
				var rx:=bed.position.x+fmod(i*17.0,bed.size.x)
				var ry:=bed.position.y+fmod(i*11.0,maxf(1.0,bed.size.y-u*2))
				draw_rect(Rect2(rx,ry,1,u*2),Color("dbe8f0"))

## Delivered pan art ids for the live view (same mapping as SaltWorldArt.view_state):
## rain shows diluted brine / mat-covered salt; brine shows its evaporation stage.
static func art_state(state:String,view:Dictionary)->String:
	match state:
		"salt":return "covered" if bool(view.get("covered",false)) else "salt"
		"brine":
			if bool(view.get("diluted",false)):return "diluted"
			var ratio:=float(view.get("ratio",0.0))
			if ratio>=2.0/3.0:return "evaporating_2"
			if ratio>=1.0/3.0:return "evaporating_1"
			return "brine"
	return "empty"

static func pan_picture(state:String,view:Dictionary,raining:bool)->Control:
	var texture:=art("pan",art_state(state,view))
	if texture:
		var picture:=Shell.picture(texture,80)
		picture.name="SaltPanPreview"
		return picture
	var preview:=PanPreview.new()
	preview.name="SaltPanPreview"
	preview.state=state
	preview.ratio=float(view.get("ratio",0.0))
	preview.covered=bool(view.get("covered",false))
	preview.diluted=bool(view.get("diluted",false))
	preview.raining=raining
	preview.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	return preview

static func pan_panel(ctx:Dictionary,page:VBoxContainer)->void:
	var app=ctx.app
	var pan:=clampi(int(ctx.index),0,Salt.PAN_COUNT-1)
	var lot:=pan/2
	var view:=pan_view(ctx.snapshot,pan)
	var weather:Dictionary=ctx.shared.get("weather",{})
	var raining:=bool(weather.get("raining",false))
	var state:=str(view.get("s","empty"))
	var mine:=pan_owner_ok(ctx.snapshot,pan)
	var head:=row(page,"SaltPanHead",12)
	head.add_child(pan_picture(state,view,raining))
	var info:=column(head,"SaltPanInfo",4)
	info.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	tight(app,info,lot_title(lot),13,FADED).name="SaltPanLot"
	if not mine:
		label(app,info,"其他島民照顧中",16,BROWN).name="SaltPanOther"
		label(app,info,"這方鹽田由其他島民照顧，只能在旁邊看看。",13,INK)
		return
	label(app,info,pan_state_text(view),17,INK).name="SaltPanState"
	if state=="brine":
		var bar:=ProgressBar.new()
		bar.name="SaltPanProgress"
		bar.show_percentage=false
		bar.max_value=1.0
		bar.step=0.001
		bar.value=clampf(float(view.get("ratio",0.0)),0.0,1.0)
		bar.custom_minimum_size=Vector2(160,12)
		info.add_child(bar)
	var sky:=row(info,"SaltPanWeather",6)
	badge(app,sky,"SaltWeather","今天%s"%str(weather.get("label","")),Color("e8eef0") if not raining else Color("dde6ef"),INK,Folio.life_icon("weather"))
	badge(app,sky,"SaltEta",eta_text(view,weather),Color("fbefcf"),BROWN)
	if raining:label(app,page,RAIN_PAN_NOTE,13,BROWN).name="SaltRainNote"
	var target:=nearest_cell(Salt.pan_rect(pan),ctx.pos)
	var actions:=row(page,"SaltPanActions")
	match state:
		"empty":
			var why:=""
			if not bool(ctx.record.get("intro",false)):why=INTRO_REASON
			elif not repaired(ctx.snapshot):why=GATE_REASON
			elif raining:why=RAIN_FLOOD_REASON
			var flood:=act(ctx,actions,"SaltFlood","引海水","salt_flood",target,"",why)
			flood.custom_minimum_size.x=140
			flood.icon=Folio.life_icon("water")
			flood.expand_icon=true
			flood.add_theme_constant_override("icon_max_width",20)
		"salt":
			var why:=""
			if int(ctx.bag.get("sea_salt",0))>int(Salt.LIMIT)-int(Salt.YIELD):why="背包放不下更多海鹽。"
			var rake:=act(ctx,actions,"SaltRake","收鹽 · 海鹽 ×%d"%int(Salt.YIELD),"salt_rake",target,"",why)
			rake.custom_minimum_size.x=160
			rake.icon=Folio.life_icon("harvest")
			rake.expand_icon=true
			rake.add_theme_constant_override("icon_max_width",20)
		_:
			label(app,actions,"晴天曬得最快，多雲慢一些；結成白白的鹽就能收。",13,FADED).name="SaltPanWait"
	var held:=row(page,"SaltPanHeld",6)
	icon_into(held,"sea_salt",24)
	tight(app,held,"背包裡的海鹽 %d"%int(ctx.bag.get("sea_salt",0)),13,INK).name="SaltPanSalt"

# ── 鹽田區面板 ─────────────────────────────────────────────

static func lot_panel(ctx:Dictionary,page:VBoxContainer)->void:
	var lot:=int(ctx.index)
	if lot==Salt.PUBLIC_LOT:public_board(ctx,page)
	elif lot==Salt.APPRENTICE_LOT:apprentice_board(ctx,page)
	else:private_board(ctx,page,clampi(lot,0,Salt.LOT_COUNT-1))

static func pan_strip(ctx:Dictionary,parent:Node,lot:int)->HBoxContainer:
	var strip:=row(parent,"SaltLotPans",8)
	var weather:Dictionary=ctx.shared.get("weather",{})
	for i in range(2):
		var pan:=lot*2+i
		var view:=pan_view(ctx.snapshot,pan)
		var cell:=column(strip,"SaltLotPan_%d"%pan,2)
		var preview:=pan_picture(str(view.get("s","empty")),view,bool(weather.get("raining",false)))
		preview.custom_minimum_size=Vector2(72,44)
		cell.add_child(preview)
		tight(ctx.app,cell,pan_state_text(view),11,INK).name="SaltLotPanState_%d"%pan
	return strip

static func public_board(ctx:Dictionary,page:VBoxContainer)->void:
	var app=ctx.app
	status_chip(ctx,page,{"id":"reserve","text":str(Salt.STATUS_TEXT.get("reserve",""))})
	pan_strip(ctx,page,Salt.PUBLIC_LOT)
	label(app,page,"走到池邊按互動鍵就能引海水或收鹽，先到先收。",13,BROWN).name="SaltPublicHint"
	var mine:=own(ctx.snapshot)
	if int(mine.get("lot",-1))<0 and int(mine.get("free_lots",0))<=0:
		label(app,page,"目前鹽田區都有人照顧，可先在保留手作池收鹽。",13,FADED).name="SaltPublicFull"

static func lot_header(ctx:Dictionary,page:VBoxContainer,line:String,tint:Color)->HBoxContainer:
	var head:=row(page,"SaltLotHead",8)
	var text:=tight(ctx.app,head,line,15,tint)
	text.name="SaltLotOwner"
	var gap:=Control.new()
	gap.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	head.add_child(gap)
	return head

static func private_board(ctx:Dictionary,page:VBoxContainer,lot:int)->void:
	var app=ctx.app
	var lots:Array=ctx.shared.get("lots",[])
	var public_lot:Dictionary=lots[lot] if lot<lots.size() and lots[lot] is Dictionary else {}
	var mine_lot:=int(ctx.own.get("lot",-1))
	var mine:=mine_lot==lot or bool(public_lot.get("mine",false))
	var claim_cell:=nearest_cell(Salt.rake_socket(lot),ctx.pos)
	if not mine:
		var taken:=bool(public_lot.get("taken",false))
		var head:=lot_header(ctx,page,"其他島民照顧中" if taken else "空著，可以認領",BROWN if taken else OK_TINT)
		pan_strip(ctx,page,lot)
		var why:=""
		if taken:why="這區已經有人照顧了。"
		elif mine_lot>=0:why="你已經有自己的鹽田區（第 %d 區）。"%(mine_lot+1)
		elif int(ctx.record.get("raked",0))<1:why="先在保留手作池親手收過一次鹽。"
		act(ctx,head,"SaltClaim","認領這區","salt_claim",claim_cell,"",why,REGION,false)
		if not why.is_empty():label(app,page,why,12,WARN_TINT).name="SaltClaimReason"
		elif not near(ctx,claim_cell):label(app,page,NEAR_REASON,12,WARN_TINT).name="SaltClaimReason"
		return
	var unit:Dictionary=ctx.own.get("unit",{})
	var head:=lot_header(ctx,page,"你照顧的鹽田區",OK_TINT)
	var release_why:=""
	if bool(unit.get("wheel",false)) or bool(unit.get("rake",false)):release_why="先把水車和收鹽台拆回背包。"
	elif not lot_pans_empty(ctx,lot):release_why="兩方鹽田都要先收乾淨。"
	act(ctx,head,"SaltRelease","歸還這區","salt_release",claim_cell,"",release_why,REGION,false)
	machine_board(ctx,page,lot,unit,release_why)

static func lot_pans_empty(ctx:Dictionary,lot:int)->bool:
	var pans:Array=ctx.shared.get("pans",[])
	for i in range(2):
		var pan:=lot*2+i
		if pan<pans.size() and str(pans[pan].get("s","empty"))!="empty":return false
	return true

## The recipient's own apprentice view with safe defaults for snapshots that predate
## the waiting list (queued/position/waiting/offer/offer_minutes/can_join/kits).
static func apprentice_info(own_view:Dictionary)->Dictionary:
	var raw=own_view.get("apprentice",{})
	var info:Dictionary=raw if raw is Dictionary else {}
	var kits=info.get("kits",{})
	var position:=maxi(0,int(info.get("position",0)))
	return {"eligible":bool(info.get("eligible",false)),"busy":bool(info.get("busy",false)),"mine":bool(info.get("mine",false)),
		"ends_in_minutes":maxi(0,int(info.get("ends_in_minutes",0))),"message":str(info.get("message","")),
		"queued":bool(info.get("queued",false)) and position>0,"position":position,"waiting":maxi(position,int(info.get("waiting",0))),
		"offer":bool(info.get("offer",false)),"offer_minutes":maxi(0,int(info.get("offer_minutes",0))),"can_join":bool(info.get("can_join",false)),
		"kits":kit_counts(kits if kits is Dictionary else {})}

static func kit_counts(kits:Dictionary)->Dictionary:
	var result:={}
	for kit in KIT_IDS:result[kit]=maxi(0,int(kits.get(kit,0)))
	return result

static func apprentice_board(ctx:Dictionary,page:VBoxContainer)->void:
	var app=ctx.app
	var lot:int=Salt.APPRENTICE_LOT
	var info:=apprentice_info(ctx.own)
	var claim_cell:=nearest_cell(Salt.rake_socket(lot),ctx.pos)
	if not info.mine:
		var busy:bool=info.busy
		var queued:bool=info.queued
		var offer:bool=info.offer and info.eligible
		var eligible:bool=info.eligible
		var can_join:bool=info.can_join and not queued and not eligible
		var held:=not busy and not eligible and int(info.waiting)>0
		var title:="輪班中" if busy else ("輪到你接班" if offer else ("保留給名單上的島民" if held else "等待下一位學徒"))
		var head:=lot_header(ctx,page,title,OK_TINT if offer else BROWN)
		var why:=""
		var notice:=""
		if queued and not offer:
			# Listed but not offered yet: no shift button, only leaving the list.
			act(ctx,head,"SaltShiftLeave","離開名單","salt_release",claim_cell,"","",REGION,false)
			notice=str(info.message)
		else:
			if not (eligible or can_join):why=str(info.message)
			if why.is_empty() and not (eligible or can_join):why="現在還不能接學徒輪班。"
			act(ctx,head,"SaltShift","排進輪班名單" if can_join else "接下學徒輪班","salt_claim",claim_cell,"",why,REGION,false)
			if offer:act(ctx,head,"SaltShiftLeave","離開名單","salt_release",claim_cell,"","",REGION,false)
			if can_join or offer:notice=str(info.message)
		label(app,page,"八個鹽田區都有人照顧時，還沒有自己區的島民照名單輪流用這裡練習水車與收鹽台；每班最多三天。",12,INK).name="SaltShiftAbout"
		if not why.is_empty():label(app,page,why,12,WARN_TINT).name="SaltShiftReason"
		elif not notice.is_empty():label(app,page,notice,12,BROWN).name="SaltShiftQueueNote"
		if why.is_empty() and not near(ctx,claim_cell):label(app,page,NEAR_REASON,12,WARN_TINT).name="SaltShiftReason"
		var tags:=row(page,"SaltShiftTags",6)
		if busy:badge(app,tags,"SaltShiftWait","約 %d 分鐘後開放"%int(info.ends_in_minutes),Color("fbefcf"),BROWN,Folio.life_icon("calendar"))
		if offer:badge(app,tags,"SaltShiftOffer","請在約 %d 分鐘內接班"%maxi(1,int(info.offer_minutes)),Color("e6f0d6"),OK_TINT,Folio.life_icon("bell"))
		if queued:badge(app,tags,"SaltShiftQueue","名單第 %d 位／共 %d 位"%[int(info.position),int(info.waiting)],Color("fbefcf"),BROWN,Folio.life_icon("sign"))
		elif int(info.waiting)>0:badge(app,tags,"SaltShiftLine","名單上有 %d 位"%int(info.waiting),Color("fbefcf"),BROWN,Folio.life_icon("sign"))
		if tags.get_child_count()==0:
			page.remove_child(tags)
			tags.free()
		coop_take_row(ctx,page)
		return
	var unit:Dictionary=ctx.own.get("unit",{})
	var head:=lot_header(ctx,page,"你的學徒輪班",OK_TINT)
	badge(app,head,"SaltShiftLeft","剩約 %d 分鐘"%maxi(0,int(info.get("ends_in_minutes",0))),Color("fbefcf"),BROWN,Folio.life_icon("calendar"))
	act(ctx,head,"SaltShiftEnd","結束輪班","salt_release",claim_cell,"","",REGION,false)
	machine_board(ctx,page,lot,unit,"")
	coop_take_row(ctx,page)

static func coop_take_row(ctx:Dictionary,page:VBoxContainer)->void:
	var app=ctx.app
	var count:=maxi(0,int(ctx.own.get("coop_box",0)))
	var kits:Dictionary=apprentice_info(ctx.own).kits
	var line:=row(page,"SaltCoopRow",6)
	var chest:=Folio.life_icon("chest")
	if chest:line.add_child(Shell.picture(chest,24))
	var text:=label(app,line,"合作社收鹽箱裡你的海鹽 %d"%count,13,INK)
	text.name="SaltCoopCount"
	text.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	var plan:=take_plan(count,kits,ctx.bag)
	var why:=TAKE_EMPTY_REASON if plan.held<=0 else (TAKE_FULL_REASON if plan.fits<=0 else "")
	act(ctx,line,"SaltBoxTake","全部取出","salt_box_take",Salt.APPRENTICE_CHEST,"",why,REGION,false)
	var kit_total:=0
	for kit in KIT_IDS:kit_total+=int(kits[kit])
	if kit_total>0:
		# Own retained kits only (returned when the bag had no room at shift end).
		var shelf:=row(page,"SaltCoopKits",6)
		tight(app,shelf,"你的機器組",12,BROWN).name="SaltCoopKitsTitle"
		for kit in KIT_IDS:
			if int(kits[kit])<=0:continue
			icon_into(shelf,kit,24)
			tight(app,shelf,"%s ×%d"%[item_name(kit),int(kits[kit])],12,INK).name="SaltCoopKit_"+kit
	if plan.held>0 and plan.fits<=0:label(app,page,TAKE_FULL_REASON,12,WARN_TINT).name="SaltCoopFull"
	elif plan.fits<plan.held:label(app,page,"背包放不下的部分會留在你的格子裡，整理背包後再來取。",12,WARN_TINT).name="SaltCoopPartial"

## What 全部取出 can move: held = items in the own compartment, fits = how many the bag
## can still take (each item limited by the bag's per-item ceiling). Mirrors the server
## rule so the button never promises a take that would be refused.
static func take_plan(count:int,kits:Dictionary,bag:Dictionary)->Dictionary:
	var held:=maxi(0,count)
	var fits:=mini(held,maxi(0,Salt.LIMIT-int(bag.get("sea_salt",0))))
	for kit in KIT_IDS:
		var n:=maxi(0,int(kits.get(kit,0)))
		held+=n
		fits+=mini(n,maxi(0,Salt.LIMIT-int(bag.get(kit,0))))
	return {"held":held,"fits":fits}

## Wheel slot, rake slot, chest picker mini-map, cap stepper, start/pause and status chip.
static func machine_board(ctx:Dictionary,page:VBoxContainer,lot:int,unit:Dictionary,release_why:String)->void:
	var app=ctx.app
	if not release_why.is_empty():
		var note:=label(app,page,release_why,12,FADED)
		note.name="SaltReleaseReason"
	var slots:=row(page,"SaltSlots",8)
	var has_wheel:=bool(unit.get("wheel",false))
	var has_rake:=bool(unit.get("rake",false))
	var on:=bool(unit.get("on",false))
	machine_slot(ctx,slots,"wheel","salt_wheel_kit","水車座",Salt.wheel_socket(lot),has_wheel,"",
		"先拆下收鹽台。" if has_rake else "")
	machine_slot(ctx,slots,"rake","salt_rake_kit","收鹽台座",Salt.rake_socket(lot),has_rake,"" if has_wheel else "先裝好水車。",
		"先暫停收鹽台。" if on else "")
	var setup:=row(page,"SaltSetup",10)
	chest_picker(ctx,setup,lot,unit)
	var right:=column(setup,"SaltSetupRight",6)
	right.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	cap_stepper(ctx,right,unit)
	var cfg_why:=""
	if not has_rake:cfg_why="裝好收鹽台後才能選收鹽箱。"
	elif on:cfg_why="先暫停，才能改收鹽箱或上限。"
	var chest:=chosen_chest(ctx,lot,unit)
	if cfg_why.is_empty() and chest==Vector2i(-1,-1):cfg_why="先在小地圖選一個收鹽箱位置。"
	var target:=nearest_cell(Salt.rake_socket(lot),ctx.pos)
	var cap:=chosen_cap(ctx,unit)
	var save:=act(ctx,right,"SaltCfg","存下：上限 %d 份"%cap,"salt_auto_cfg",target,cfg_extra(chest,cap),cfg_why,REGION,false)
	save.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var toggle_why:=""
	if not has_rake and has_wheel:toggle_why="水車會自己引水；裝收鹽台後才有暫停開關。"
	elif not has_rake:toggle_why="先裝好水車和收鹽台。"
	elif parse_cell(unit.get("chest","")).x<0:toggle_why="先存下收鹽箱位置。"
	var toggle:=act(ctx,right,"SaltToggle","暫停" if on else "啟用","salt_auto_toggle",target,"",toggle_why,REGION,false)
	toggle.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var reason:=cfg_why if not cfg_why.is_empty() else toggle_why
	if reason.is_empty() and not near(ctx,target):reason=NEAR_REASON
	if not reason.is_empty():label(app,right,reason,11,WARN_TINT).name="SaltSetupReason"
	var status:Dictionary=unit.get("status",{})
	if not str(status.get("id","")).is_empty():status_chip(ctx,page,status)

static func machine_slot(ctx:Dictionary,parent:Node,kind:String,kit:String,title:String,socket:Rect2i,installed:bool,install_block:String,remove_block:String)->void:
	var app=ctx.app
	var held:=int(ctx.bag.get(kit,0))
	var card:=tile(parent,"SaltSlot_"+kind,Color("e6f0d6") if installed else Color("fbefcf"),OK_TINT if installed else Color("c49a6c"))
	card.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var stack:=column(card,"",3)
	var top:=row(stack,"",6)
	if not icon_into(top,kit,32):
		var gap:=Control.new()
		gap.custom_minimum_size=Vector2(0,32)
		top.add_child(gap)
	var info:=column(top,"",1)
	info.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	tight(app,info,title,13,INK)
	var state:="✓ 已裝上" if installed else ("可以裝" if held>=1 and install_block.is_empty() else "缺%s"%item_name(kit) if held<1 else install_block)
	tight(app,info,state,12,OK_TINT if installed or held>=1 else WARN_TINT).name="SaltSlotState_"+kind
	tight(app,stack,"%s 持有 %d／需 1"%[item_name(kit),held],12,BROWN).name="SaltKitCount_"+kind
	var target:=nearest_cell(socket,ctx.pos)
	if installed:
		act(ctx,stack,"SaltUninstall_"+kind,"拆回背包","salt_uninstall",target,kind,remove_block,REGION,false)
	else:
		var why:=install_block
		if why.is_empty() and held<1:why="背包裡沒有%s"%item_name(kit)
		act(ctx,stack,"SaltInstall_"+kind,"裝上","salt_install",target,kind,why,REGION,false)
		if held<1:
			var hint:=label(app,stack,craft_hint(ctx.snapshot,kit),11,FADED)
			hint.name="SaltCraftHint_"+kind

static func chest_options(lot:int)->Array:
	if lot==Salt.APPRENTICE_LOT:return [Salt.APPRENTICE_CHEST]
	var result:Array=[]
	for cell in Salt.chest_sockets(lot):result.append(cell)
	return result

static func chosen_chest(ctx:Dictionary,lot:int,unit:Dictionary)->Vector2i:
	var options:=chest_options(lot)
	var picked:=parse_cell(ctx.app.modal.get_meta("salt_chest",""))
	if picked in options:return picked
	var saved:=parse_cell(unit.get("chest",""))
	if saved in options:return saved
	if lot==Salt.APPRENTICE_LOT:return Salt.APPRENTICE_CHEST
	return Vector2i(-1,-1)

static func chosen_cap(ctx:Dictionary,unit:Dictionary)->int:
	var pending:=int(ctx.app.modal.get_meta("salt_cap",-1))
	if pending>=0:return clamp_cap(pending)
	return clamp_cap(int(unit.get("cap",Salt.CAP_DEFAULT)))

## Small map of the lot: pans, machine seats and the chest spots (buttons).
static func chest_picker(ctx:Dictionary,parent:Node,lot:int,unit:Dictionary)->void:
	var app=ctx.app
	var origin:Vector2i=Salt.LOT_ORIGINS[lot]
	var frame:=tile(parent,"SaltChestMap",Color("efe4cb"),Color("a78452"))
	var stack:=column(frame,"",3)
	tight(app,stack,"收鹽箱位置" if lot!=Salt.APPRENTICE_LOT else "合作社收鹽箱（固定）",12,BROWN).name="SaltChestMapTitle"
	var grid:=GridContainer.new()
	grid.name="SaltChestGrid"
	grid.columns=9
	grid.add_theme_constant_override("h_separation",1)
	grid.add_theme_constant_override("v_separation",1)
	stack.add_child(grid)
	var options:=chest_options(lot)
	var chosen:=chosen_chest(ctx,lot,unit)
	var objects:Dictionary=ctx.snapshot.get("objects",{}) if ctx.region==REGION else {}
	var pans:=[Salt.pan_rect(lot*2),Salt.pan_rect(lot*2+1)]
	var wheel:=Salt.wheel_socket(lot)
	var rake:=Salt.rake_socket(lot)
	for y in range(origin.y,origin.y+4):
		for x in range(origin.x-1,origin.x+8):
			var cell:=Vector2i(x,y)
			var index:=options.find(cell)
			if index>=0:
				var pick:=Button.new()
				pick.name="SaltChestPick_%d"%index
				pick.custom_minimum_size=Vector2(26,26)
				pick.toggle_mode=true
				pick.set_pressed_no_signal(cell==chosen)
				pick.icon=Folio.life_icon("chest")
				pick.expand_icon=true
				var placed:=objects.has(cell_key(cell))
				var where:="%d 號位置"%(index+1)
				pick.tooltip_text=where+("（已放箱子）" if placed else "（還沒放箱子）") if lot!=Salt.APPRENTICE_LOT else "合作社收鹽箱"
				pick.accessibility_name=pick.tooltip_text
				pick.set_meta("salt_chest_cell",cell)
				pick.pressed.connect(func():
					app.modal.set_meta("salt_chest",cell_key(cell))
					refresh(app))
				grid.add_child(pick)
				continue
			var fill:=Color(0,0,0,0)
			if pans[0].has_point(cell) or pans[1].has_point(cell):fill=SEA
			elif wheel.has_point(cell):fill=Color("9b6a3c")
			elif rake.has_point(cell):fill=Color("c08a4a")
			else:fill=Color("d9c49a")
			var spot:=Panel.new()
			spot.custom_minimum_size=Vector2(26,26)
			spot.mouse_filter=Control.MOUSE_FILTER_IGNORE
			spot.add_theme_stylebox_override("panel",LifeTheme.surface(fill,fill.darkened(0.2),0,0))
			grid.add_child(spot)
	var legend:=row(stack,"SaltChestLegend",4)
	tight(app,legend,"藍＝鹽田　深木＝水車座　淺木＝收鹽台座",10,FADED)
	if chosen.x>=0:
		var placed_text:=""
		if lot!=Salt.APPRENTICE_LOT:placed_text="（已放箱子）" if objects.has(cell_key(chosen)) else "（請先放一個箱子）"
		tight(app,stack,"已選 %d,%d%s"%[chosen.x,chosen.y,placed_text],11,INK).name="SaltChestChosen"

static func cap_stepper(ctx:Dictionary,parent:Node,unit:Dictionary)->void:
	var app=ctx.app
	var cap:=chosen_cap(ctx,unit)
	tight(app,parent,"存量上限（收鹽箱裡的海鹽）",12,BROWN)
	var line:=row(parent,"SaltCapStepper",3)
	for entry in [["SaltCapMinus10","−10",-10],["SaltCapMinus1","−1",-1]]:
		var delta:int=entry[2]
		local(ctx,line,entry[0],entry[1],func():step_cap(app,unit,delta),cap+delta>=int(Salt.CAP_MIN) or cap>int(Salt.CAP_MIN)).custom_minimum_size.x=40
	var value:=tile(line,"SaltCapValueTile",Color("fffaf0"),Color("a78452"))
	value.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var text:=label(app,value,"%d 份"%cap,14,INK)
	text.name="SaltCapValue"
	text.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	text.autowrap_mode=TextServer.AUTOWRAP_OFF
	for entry in [["SaltCapPlus1","+1",1],["SaltCapPlus10","+10",10]]:
		var delta:int=entry[2]
		local(ctx,line,entry[0],entry[1],func():step_cap(app,unit,delta),cap<int(Salt.CAP_MAX)).custom_minimum_size.x=40
	for name in ["SaltCapMinus10","SaltCapMinus1"]:
		var minus:=line.find_child(name,false,false) as Button
		if minus:minus.disabled=cap<=int(Salt.CAP_MIN)

static func step_cap(app,unit:Dictionary,delta:int)->void:
	var current:=int(app.modal.get_meta("salt_cap",-1))
	if current<0:current=int(unit.get("cap",Salt.CAP_DEFAULT))
	app.modal.set_meta("salt_cap",clamp_cap(current+delta))
	refresh(app)

# ── 小栗委託 ───────────────────────────────────────────────

static func order_panel(ctx:Dictionary,page:VBoxContainer)->void:
	var app=ctx.app
	var order:Dictionary=ctx.own.get("order",{})
	var need:Dictionary=order.get("need",Salt.ORDER)
	var have:Dictionary=order.get("have",{})
	var pay:=int(order.get("pay",Salt.ORDER_PAY))
	var ribbon:=PanelContainer.new()
	ribbon.name="SaltOrderRibbon"
	ribbon.add_theme_stylebox_override("panel",Folio.ribbon_style())
	page.add_child(ribbon)
	var title:=label(app,ribbon,"南邊攤子的海鹽委託 · %d 鈴幣"%pay,16,Folio.RIBBON_INK)
	title.name="SaltOrderTitle"
	title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	var crates:=row(page,"SaltOrderCrates",8)
	var ready:=true
	for id in need:
		var want:=int(need[id])
		var held:=int(have.get(id,ctx.bag.get(id,0)))
		ready=ready and held>=want
		var crate:=tile(crates,"SaltOrderNeed_"+str(id),Color("e6f0d6") if held>=want else Color("f8e6cf"),OK_TINT if held>=want else Color("c49a6c"))
		crate.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		var stack:=column(crate,"",2)
		var art_icon:=icon_into(stack,str(id),48)
		if art_icon:art_icon.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
		var name_label:=label(app,stack,item_name(str(id)),14,INK)
		name_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		var count:=label(app,stack,"%s 持有 %d／需 %d"%["✓" if held>=want else "✗",held,want],12,OK_TINT if held>=want else WARN_TINT)
		count.name="SaltOrderCount_"+str(id)
		count.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		count.autowrap_mode=TextServer.AUTOWRAP_OFF
	label(app,page,"香煎溪魚：銀線溪魚 1＋海鹽 1，在爐灶上煎好。海鹽不能出貨，只用在料理和委託。",12,FADED).name="SaltOrderRecipe"
	if bool(ctx.record.get("order",false)):
		label(app,page,"✓ 委託已交付，鈴幣已入帳。",15,OK_TINT).name="SaltOrderDone"
		return
	var current:=phase(ctx.snapshot)
	var why:=""
	if not reached(ctx.snapshot,"order"):why="先在北門讓收鹽台自動收進一次箱子。"
	elif current!="order":why="委託已經交過了。"
	elif not ready:why="海鹽或香煎溪魚還不夠。"
	var deliver:=act(ctx,page,"SaltOrder","交付委託 · %d 鈴幣"%pay,"salt_order",Flower.RECEIVER_HOME,"",why,"home")
	deliver.icon=Folio.life_icon("chest")
	deliver.expand_icon=true
	deliver.add_theme_constant_override("icon_max_width",22)

static func coop_panel(ctx:Dictionary,page:VBoxContainer)->void:
	label(ctx.app,page,"合作社的收鹽箱分成每位島民一格，只有格子的主人能取出自己的海鹽和代管的機器組；輪班結束後也會一直留著。",13,INK).name="SaltCoopAbout"
	coop_take_row(ctx,page)
	# 第 40 章臺南北門回訪：鹽籃在收鹽箱旁裝籃（閘門修好前寫明鎖定）。
	if bool(ctx.record.get("intro",false)):page.add_child(Revisit.entry_button(ctx.app,"chest"))

# ── 手帳（地方記憶頁） ─────────────────────────────────────

static func journal(ctx:Dictionary,parent:Control)->void:
	var app=ctx.app
	var tab:String=app.modal.get_meta("salt_tab","memory")
	var book:=PanelContainer.new()
	book.name="SaltJournalBook"
	book.custom_minimum_size=FlowerUI.BOOK_SIZE
	book.add_theme_stylebox_override("panel",FlowerUI.book_style())
	book.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	parent.add_child(book)
	var spread:=HBoxContainer.new()
	spread.name="SaltJournalSpread"
	spread.add_theme_constant_override("separation",FlowerUI.BOOK_SPINE)
	book.add_child(spread)
	var left:=column(spread,"SaltJournalLeftPage",6)
	left.custom_minimum_size.x=FlowerUI.BOOK_LEFT_PAGE
	var right:=column(spread,"SaltJournalRightPage",6)
	right.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	route_page(ctx,left)
	var tabs:=row(right,"SaltJournalTabs",4)
	for entry in [["memory","地方記憶"],["story","故事重看"]]:
		var id:String=entry[0]
		var button:=local(ctx,tabs,"SaltTab_"+id,entry[1],func():
			app.modal.set_meta("salt_tab",id)
			app.modal.remove_meta("salt_story")
			refresh(app))
		Folio.apply_tab(button)
		button.custom_minimum_size.y=28
		button.add_theme_font_size_override("font_size",13)
		button.toggle_mode=true
		button.set_pressed_no_signal(tab==id)
		button.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	var gap:=Control.new()
	gap.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	tabs.add_child(gap)
	var close:=local(ctx,tabs,"SaltBookClose","闔上  Esc",app._close_modal)
	Folio.apply_tab(close)
	close.custom_minimum_size.y=28
	close.add_theme_font_size_override("font_size",13)
	var page:=column(right,"SaltJournalPage",5)
	page.size_flags_vertical=Control.SIZE_EXPAND_FILL
	if tab=="story":story_page(ctx,page)
	else:memory_page(ctx,page)

static func route_page(ctx:Dictionary,left:VBoxContainer)->void:
	var app=ctx.app
	FlowerUI.ribbon(app,left,"SaltChapterRibbon",Folio.life_icon("journal"),"北門・鹽風合作鹽田")
	var picture:=art("heritage","jingzaijiao")
	if picture:
		var view:=Shell.picture(picture,96)
		view.name="SaltHeritageArt"
		view.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
		left.add_child(view)
	var current:=phase(ctx.snapshot)
	var at:=PHASES.find(current)
	var route:=GridContainer.new()
	route.name="SaltPhases"
	route.columns=4
	route.add_theme_constant_override("h_separation",4)
	route.add_theme_constant_override("v_separation",3)
	left.add_child(route)
	for id in ROUTE:
		var order:=PHASES.find(id)
		var done:=current=="complete" or order<at
		var here:=order==at
		var mark:="✓" if done else ("▶" if here else "・")
		var step:=label(app,route,"%s %s"%[mark,PHASE_SHORT[id]],12,Folio.RIBBON_INK if here else (OK_TINT if done else FADED))
		step.name="SaltPhase_"+id
		step.autowrap_mode=TextServer.AUTOWRAP_OFF
		if here:
			var holder:=PanelContainer.new()
			holder.add_theme_stylebox_override("panel",Folio.padded("button_pressed",3,3,1))
			route.remove_child(step)
			holder.add_child(step)
			route.add_child(holder)
	var next:=PanelContainer.new()
	next.name="SaltNextStep"
	next.add_theme_stylebox_override("panel",Folio.story_style())
	left.add_child(next)
	var words:=column(next,"",2)
	var guide:=next_step(ctx.snapshot)
	label(app,words,"✓ 這段故事完成了" if current=="complete" else "下一步",13,BROWN).name="SaltNextTitle"
	label(app,words,str(guide.get("text",story(current))),12,INK).name="SaltNextDetail"
	# 第 40 章臺南北門回訪：鹽籃批次的進度一行（閘門修好之後）。
	var basket_line:=Revisit.journal_line(ctx.snapshot)
	if not basket_line.is_empty():label(app,left,basket_line,12,OK_TINT if basket_line.begins_with("✓") else BROWN).name="SaltRevisitLine"
	if int(ctx.record.get("raked",0))>0:
		label(app,left,"✓ 親手收過海鹽・瓦盤鹽田已收入手冊",12,OK_TINT).name="SaltFieldwork"

static func memory_page(ctx:Dictionary,page:VBoxContainer)->void:
	var app=ctx.app
	label(app,page,"北門瓦盤鹽田",15,BROWN).name="SaltMemoryTitle"
	for index in FACTS.size():
		var fact:=label(app,page,"・"+FACTS[index],12,INK)
		fact.name="SaltFact_%d"%index
	var claim:=PanelContainer.new()
	claim.name="SaltOriginalCard"
	claim.add_theme_stylebox_override("panel",Folio.story_style())
	page.add_child(claim)
	label(app,claim,ORIGINAL_NOTE+"。",12,BROWN).name="SaltOriginal"
	tight(app,page,"資料來源",12,FADED)
	for index in SOURCES.size():
		var entry:Array=SOURCES[index]
		var source:=LinkButton.new()
		source.text=entry[0]
		source.uri=entry[1]
		source.add_theme_font_size_override("font_size",12)
		source.add_theme_color_override("font_color",OK_TINT)
		source.name="SaltSource_%d"%index
		page.add_child(source)
	if site_kind(ctx.site)=="heritage":
		var line:=row(page,"SaltNoteRow",6)
		if bool(ctx.record.get("note",false)):
			tight(app,line,"✓ 解說牌讀過了，可以隨時重看",12,OK_TINT).name="SaltNoteDone"
		else:
			act(ctx,line,"SaltNote","讀完解說牌","salt_note",Salt.HERITAGE_SIGN,"","",REGION,false)
		tight(app,line,"觀景區只供欣賞，不能採收",11,FADED)

static func story_entries(snapshot:Dictionary)->Array:
	var entries:Array=[]
	var at:=PHASES.find(phase(snapshot))
	for id in ROUTE+["complete"]:
		if PHASES.find(id)<=at and at>=PHASES.find("letter") and Salt.STORY.has(id):
			entries.append({"id":id,"title":PHASE_SHORT.get(id,id),"text":story(id)})
	return entries

static func story_page(ctx:Dictionary,page:VBoxContainer)->void:
	var app=ctx.app
	var entries:=story_entries(ctx.snapshot)
	if entries.is_empty():
		label(app,page,"收下北門寄來的信之後，這裡會留下故事。",13,FADED).name="SaltStoryEmpty"
		return
	var chosen:String=app.modal.get_meta("salt_story",entries[-1].id)
	var picks:=HFlowContainer.new()
	picks.name="SaltStoryPicks"
	picks.add_theme_constant_override("h_separation",3)
	picks.add_theme_constant_override("v_separation",3)
	page.add_child(picks)
	var shown:Dictionary=entries[-1]
	for entry in entries:
		var id:String=entry.id
		var button:=local(ctx,picks,"SaltStory_"+id,entry.title,func():
			app.modal.set_meta("salt_story",id)
			refresh(app))
		Folio.apply_tab(button)
		button.custom_minimum_size.y=26
		button.add_theme_font_size_override("font_size",12)
		button.toggle_mode=true
		button.set_pressed_no_signal(id==chosen)
		if id==chosen:shown=entry
	var sheet:=PanelContainer.new()
	sheet.name="SaltStorySheet"
	sheet.add_theme_stylebox_override("panel",Folio.story_style())
	page.add_child(sheet)
	var who:="xiaoli" if shown.id in ["letter","order","report"] else "salt_worker"
	speaker(ctx,sheet,who,XIAOLI_NAME if who=="xiaoli" else WORKER_NAME,str(shown.text))
	label(app,page,"重看只在你的畫面播放，不會改變進度。",11,FADED).name="SaltStoryNote"
