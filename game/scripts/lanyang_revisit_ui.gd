extends RefCounted
## 第 40 章「回訪・旱日分流」頁（規則在 lanyang_revisit.gd，這裡只讀快照、送動作）。
##
## 入口（都用一般互動鍵，沒有新按鍵）：
##  * 蘭陽：水圳修好且橋邊配水紀念牌已設（Revisit.unlocked）、自己也完成第一次分水
##    （Revisit.player_ready）之後，在岔口 (33,25)、上游 (33,22)、田尾 (33,32) 三格按互動鍵
##    （main._interact 的 "memory:" 點）開這一頁；還沒完成的人照舊開「觀察水路」。
##    星禾／中段的田 (33,29)（"gardener" 點）在還沒領分水木牌前開這一頁，領過後回到水圳手記。
##  * 星禾的水圳手記（lanyang_ui.gd）修好水圳之後有「回訪・旱日分流」按鈕（沒準備好的人
##    在這裡看到要先完成自己第一次分水的說明）。
## 版面（由上而下）：今天的季節＋天氣與星禾的理由 → 三塊田（目前 n 份／需要 m 份、✓ 已巡看）
##  → 岔口兩道閘（0～3 檔，只在岔口旁可按）→ 巡看站著的那塊田 → 完成狀態與領取分水木牌 →
##  免責說明。結構只建一次，refresh() 依快照原地更新（不重建），按鈕按下後焦點留在原處；
##  伺服器回覆由 main._notice 寫進頁底的 modal_feedback。
## 世界提示（world_view）與左上角追蹤卡（life_ui_shell.refresh_hud）也讀這裡的純函式。
const World=preload("res://scripts/world.gd")
const Revisit=preload("res://scripts/lanyang_revisit.gd")
const Weather=preload("res://scripts/weather.gd")
const Pixel=preload("res://scripts/inventory_pixel_theme.gd")
const Art=preload("res://scripts/lanyang_revisit_art.gd")

const LAYOUT:="lanyang_revisit"
const PAGE_TITLE:="回訪・旱日分流"
const INK:=Color("3d422d")
const MUTED:=Color("7a6f58")
const WARN:=Color("9c4b32")
const GOOD:=Color("3e664b")
const CLAIM_TEXT:="領取分水木牌"
const DONE_LINE:="謝謝大家！三塊田今天都喝得到水了。分水木牌帶回家，看到它就記得今天。"
const MARK_DONE:="✓ 已巡看"
const MARK_OPEN:="○ 還沒巡看"
const STATUS_OPEN:="分水木牌・三塊田同一天都巡看過，每人可領一塊"
const STATUS_DONE:="✓ 旱日分流完成・家園工作台可以做分流閘了"
const STATUS_CLAIMED:="✓ 已領分水木牌・在家園工坊「生活」頁擺放"
const HOME_HINT:="分流閘圖樣已解鎖\n到家園工作台製作分流閘"

# ------------------------------------------------------------ pure helpers --

static func in_lanyang(s:Dictionary) -> bool:
	return str(s.get("region_id","home"))==Revisit.REGION

## The revisit page replaces the observation page at the cells for ready players.
static func available(s:Dictionary) -> bool:
	return Revisit.unlocked(s) and Revisit.player_ready(s)

## 星禾 (33,29) opens the revisit page until the plaque is claimed.
static func gardener_opens(s:Dictionary) -> bool:
	return in_lanyang(s) and available(s) and not Revisit.claimed_own(s)

static func _field_name(id:String) -> String:
	return str(Revisit.FIELD_NAMES.get(id,""))

## Focused world prompt at one of the three observation cells ("" = keep the default).
static func cell_prompt(s:Dictionary,cell:Vector2i) -> String:
	if not available(s):return ""
	var id:=Revisit.field_at(cell)
	if Revisit.completed(s):return "旱日分流・已完成" if cell==Revisit.GATE_CELL else "%s・水已配好"%_field_name(id)
	if Revisit.waiting_for_return(s):return "蘭陽水圳・明天再來"
	if cell==Revisit.GATE_CELL:return "岔口分流閘・今天有雨" if Revisit.raining(s) else "調整岔口分流閘"
	if id.is_empty():return ""
	return "%s・已巡看"%_field_name(id) if id in Revisit.checked_today(s) else "巡看"+_field_name(id)

static func gardener_prompt(s:Dictionary) -> String:
	if not gardener_opens(s):return ""
	return "向星禾領分水木牌" if Revisit.completed(s) else "星禾・旱日分流"

## Lanyang tracker (two short lines; "" keeps the canal tracker).
static func tracker_text(s:Dictionary) -> String:
	if not Revisit.unlocked(s):return ""
	if not Revisit.player_ready(s):return "回訪・旱日分流\n先完成自己的第一次分水"
	if Revisit.completed(s):
		return "旱日分流完成\n工作台可做分流閘了" if Revisit.claimed_own(s) else "旱日分流完成\n到橋邊找星禾領木牌"
	if Revisit.waiting_for_return(s):return "回訪・旱日分流\n明天起找個晴天再來"
	if Revisit.raining(s):return "回訪・旱日分流\n今天有雨，等放晴再來"
	var need:=Revisit.demand(s)
	if not Revisit.gates_today(s) or Revisit.shares(s)!=need:
		return "回訪・旱日分流\n到岔口調閘：%d／%d／%d 份"%[int(need[0]),int(need[1]),int(need[2])]
	return "回訪・旱日分流\n巡看三塊田 %d／3"%Revisit.checked_today(s).size()

## Home tracker after the revisit while the player has no gate yet ("" otherwise).
static func home_hint(s:Dictionary,own_id:String) -> String:
	if not Revisit.completed(s):return ""
	var person:Variant=s.get("players",{}).get(own_id,{})
	if person is Dictionary and int(person.get("inventory",{}).get(World.INDUSTRY.GATE_KIT,0))>0:return ""
	var objects:Variant=s.get("objects",{})
	if objects is Dictionary:
		for obj in objects.values():
			if obj is Dictionary and obj.get("type")==World.INDUSTRY.GATE_KIND and obj.get("owner")==own_id:return ""
	return HOME_HINT

static func _person(app) -> Dictionary:
	var person:Variant=app.session.snapshot.get("players",{}).get(app.session.own_id,{})
	return person if person is Dictionary else {}

static func _near(person:Dictionary,cell:Vector2i) -> bool:
	if person.is_empty():return false
	return Vector2(float(person.get("x",0.0)),float(person.get("y",0.0))).distance_to(Vector2(cell)+Vector2(0.5,0.5))<=Revisit.REACH

## The field the player stands at (closest within reach), "" when none.
static func standing_field(person:Dictionary) -> String:
	var best:=""
	var best_distance:=Revisit.REACH+0.001
	if person.is_empty():return best
	var at:=Vector2(float(person.get("x",0.0)),float(person.get("y",0.0)))
	for id:String in Revisit.FIELDS:
		var d:=at.distance_to(Vector2(Revisit.FIELD_CELLS[id])+Vector2(0.5,0.5))
		if d<best_distance:best=id;best_distance=d
	return best

static func gate_reason(s:Dictionary,person:Dictionary) -> String:
	var block:=Revisit.gate_block(s)
	if not block.is_empty():return block
	return "" if _near(person,Revisit.GATE_CELL) else Revisit.WRONG_GATE_CELL

## [enabled, reason]: the 巡看 button stays pressable when only the split is wrong, so
## the server's own WRONG_SHARE / OTHER_WRONG / NO_GATES_TODAY reply is shown.
static func check_state(s:Dictionary,person:Dictionary) -> Array:
	var common:=Revisit.gate_block(s)
	if common in [Revisit.LOCKED,Revisit.NOT_READY,Revisit.RETURN_TOMORROW]:return [false,common]
	var field:=standing_field(person)
	if field.is_empty():
		if Revisit.completed(s):return [false,Revisit.ALREADY_DONE]
		if Revisit.raining(s):return [false,Revisit.RAINY]
		return [false,Revisit.WRONG_FIELD_CELL]
	var block:=Revisit.check_block(s,field)
	if block in [Revisit.ALREADY_DONE,Revisit.RAINY,Revisit.ALREADY_CHECKED]:return [false,block]
	return [true,block]

static func claim_reason(s:Dictionary,person:Dictionary) -> String:
	var block:=Revisit.claim_block(s,person.get("inventory",{}))
	if not block.is_empty():return block
	return "" if _near(person,Revisit.SERVICE) else Revisit.WRONG_SERVICE_CELL

# ---------------------------------------------------------------- structure --

static func is_open(app) -> bool:
	return is_instance_valid(app.modal) and app.modal.has_meta("revisit_body")

static func open(app,cell:Vector2i=Revisit.SERVICE) -> void:
	if not in_lanyang(app.session.snapshot):return
	var body:VBoxContainer=app._open_modal(PAGE_TITLE)
	app.modal.theme=Pixel.make(app.modal.theme if app.modal.theme else app.hud.theme)
	app.modal.add_theme_stylebox_override("panel",Pixel.frame_style())
	app.modal.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	app.modal.set_meta("life_modal_layout",LAYOUT)
	app.modal.set_meta("revisit_body",body)
	app.modal.set_meta("revisit_cell",cell)
	body.add_theme_constant_override("separation",4)
	build(app,body)
	refresh(app)
	if is_instance_valid(app.modal_feedback):app.modal_feedback.text="Esc 回到島上"
	app._layout_preview.call_deferred()
	focus_first.call_deferred(app)

## main._layout_preview: centred, as tall as its content.
static func layout(app,bounds:Vector2) -> void:
	var modal:Control=app.modal
	var width:=minf(820,bounds.x-48)
	var cap:=bounds.y-16
	var height:=minf(cap,600)
	modal.size.x=width
	var outer:=modal.find_child("ModalScroll",true,false) as Control
	var content:=modal.find_child("ModalContent",true,false) as Control
	if outer!=null and content!=null:
		var chrome:float=modal.get_combined_minimum_size().y-outer.get_combined_minimum_size().y
		height=minf(cap,chrome+content.get_combined_minimum_size().y+2)
	modal.size=Vector2(width,height)
	modal.position=Vector2(floorf((bounds.x-width)/2),floorf((bounds.y-height)/2))

static func _text(app,parent:Node,value:String,size:int,color:Color=INK) -> Label:
	var l:Label=app.label(value,size)
	l.autowrap_mode=TextServer.AUTOWRAP_OFF
	l.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color",color)
	parent.add_child(l)
	return l

static func _wrapped(app,parent:Node,value:String,size:int,color:Color=INK) -> Label:
	var l:Label=app.label(value,size)
	l.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	l.add_theme_color_override("font_color",color)
	parent.add_child(l)
	return l

static func _button(app,parent:Node,id:String,title:String,callback:Callable) -> Button:
	var b:Button=app.button(title,callback)
	b.name=id
	b.focus_mode=Control.FOCUS_ALL
	b.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	b.custom_minimum_size=Vector2(0,34)
	b.add_theme_font_size_override("font_size",15)
	parent.add_child(b)
	return b

## Nearest-filtered picture (same as LifeShell.picture; kept local so the HUD shell can
## read tracker_text without a preload cycle).
static func picture(texture:Texture2D,extent:int) -> TextureRect:
	var result:=TextureRect.new()
	result.texture=texture
	result.custom_minimum_size=Vector2(extent,extent)
	result.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	result.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	result.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	result.mouse_filter=Control.MOUSE_FILTER_IGNORE
	return result

static func _paper(parent:Node,id:String) -> VBoxContainer:
	var card:=PanelContainer.new()
	card.name=id
	card.add_theme_stylebox_override("panel",Pixel.paper_style())
	card.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	parent.add_child(card)
	var col:=VBoxContainer.new()
	col.add_theme_constant_override("separation",4)
	card.add_child(col)
	return col

static func build(app,body:VBoxContainer) -> void:
	# Today: season, weather and 星禾's reason.
	var head:=_paper(body,"RevisitHeader")
	var row:=HBoxContainer.new()
	row.add_theme_constant_override("separation",10)
	head.add_child(row)
	var portrait:=picture(preload("res://scripts/lanyang_life_art.gd").portrait(),56)
	portrait.name="RevisitPortrait"
	row.add_child(portrait)
	var words:=VBoxContainer.new()
	words.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override("separation",2)
	row.add_child(words)
	_text(app,words,"",17).name="RevisitDay"
	_wrapped(app,words,"",15).name="RevisitReason"
	_wrapped(app,words,"",14,WARN).name="RevisitWeather"
	# Locked / not ready.
	var hold:=_paper(body,"RevisitHold")
	_wrapped(app,hold,"",16,WARN).name="RevisitHoldText"
	var memory:=_button(app,hold,"RevisitMemory","查看地方記憶・往日分水",app._history_menu)
	memory.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
	# Three fields.
	var fields:=HBoxContainer.new()
	fields.name="RevisitFields"
	fields.add_theme_constant_override("separation",8)
	body.add_child(fields)
	for id:String in Revisit.FIELDS:
		var card:=_paper(fields,"RevisitField_"+id)
		_text(app,card,_field_name(id),16).name="RevisitFieldName_"+id
		_text(app,card,"",15).name="RevisitFieldShare_"+id
		_text(app,card,"",14,MUTED).name="RevisitFieldMark_"+id
	# The two gates at the fork.
	var gates:=_paper(body,"RevisitGates")
	var gate_row:=HBoxContainer.new()
	gate_row.name="RevisitGateRow"
	gate_row.add_theme_constant_override("separation",18)
	gates.add_child(gate_row)
	for which:String in ["a","b"]:
		var group:=HBoxContainer.new()
		group.add_theme_constant_override("separation",4)
		gate_row.add_child(group)
		_text(app,group,str(Revisit.GATE_NAMES[which]),16).name="RevisitGateName_"+which
		for level in Revisit.MAX_LEVEL+1:
			var b:=_button(app,group,"RevisitGate_%s_%d"%[which,level],"%d 檔"%level,func():_send_gate(app,which,level))
			b.toggle_mode=true
			b.custom_minimum_size.x=52
	_text(app,gates,"",15).name="RevisitSplit"
	_wrapped(app,gates,"",14,WARN).name="RevisitGateReason"
	# Check the field you stand at; completion and the plaque.
	var acts:=_paper(body,"RevisitActions")
	var check_row:=HBoxContainer.new()
	check_row.add_theme_constant_override("separation",10)
	acts.add_child(check_row)
	_button(app,check_row,"RevisitCheck","巡看這塊田",func():_send_check(app))
	var progress:=_text(app,check_row,"",15)
	progress.name="RevisitProgress"
	progress.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	_wrapped(app,acts,"",14,WARN).name="RevisitCheckReason"
	var claim_row:=HBoxContainer.new()
	claim_row.add_theme_constant_override("separation",8)
	acts.add_child(claim_row)
	var icon:=picture(Art.icon(Revisit.PLAQUE_ITEM),32)
	icon.name="RevisitPlaqueIcon"
	claim_row.add_child(icon)
	var status:=_wrapped(app,claim_row,"",15)
	status.name="RevisitStatus"
	_button(app,claim_row,"RevisitClaim",CLAIM_TEXT,func():_send_claim(app))
	_wrapped(app,acts,"",14,WARN).name="RevisitClaimReason"
	# Disclaimer and the way back to the canal notes.
	var foot:=HBoxContainer.new()
	foot.name="RevisitFooter"
	foot.add_theme_constant_override("separation",10)
	body.add_child(foot)
	_wrapped(app,foot,Revisit.DISCLAIMER,13,MUTED).name="RevisitDisclaimer"
	_button(app,foot,"RevisitCanal","星禾的水圳手記",app._gardener_menu)

# ------------------------------------------------------------------ actions --

static func _send_gate(app,which:String,level:int) -> void:
	app.session.perform(Revisit.GATE_ACTION,Revisit.GATE_CELL,Revisit.gate_extra(which,level))
	refresh(app,true)

static func _send_check(app) -> void:
	var field:=standing_field(_person(app))
	if not field.is_empty():app.session.perform(Revisit.CHECK_ACTION,Revisit.FIELD_CELLS[field])
	refresh(app,true)

static func _send_claim(app) -> void:
	app.session.perform(Revisit.CLAIM_ACTION,Revisit.SERVICE)
	refresh(app,true)

# ------------------------------------------------------------------ updates --

static func _node(app,id:String) -> Control:
	if not is_open(app):return null
	return (app.modal.get_meta("revisit_body") as Node).find_child(id,true,false) as Control

static func _put(app,id:String,value:String,color=null) -> Label:
	var l:=_node(app,id) as Label
	if l==null:return null
	l.text=value
	if color is Color:l.add_theme_color_override("font_color",color)
	l.visible=not value.is_empty()
	return l

static func _enable(app,id:String,enabled:bool,tip:String) -> Button:
	var b:=_node(app,id) as Button
	if b==null:return null
	b.disabled=not enabled
	b.tooltip_text=tip
	return b

static func refresh(app,force:=false) -> void:
	if not is_open(app):return
	var s:Dictionary=app.session.snapshot
	var person:=_person(app)
	var ready:=available(s)
	var done:=Revisit.completed(s)
	var waiting:=ready and Revisit.waiting_for_return(s)
	var raining:=Revisit.raining(s)
	var focus_before:=_focus_owner(app)
	var season:=Revisit.season(s)
	var weather:Dictionary=Weather.at(float(s.get("time",0.0)),Revisit.REGION)
	_put(app,"RevisitDay","%s季・第 %d 日・宜蘭%s"%[str(Weather.SEASON_LABELS.get(season,"")),Revisit.today(s),str(weather.label)])
	var line:=DONE_LINE if done else Revisit.reason(s)
	if waiting:line="剛才我們練的是怎麼分水。等田地喝過一晚，下一次就到真正的水口試試看。"
	_put(app,"RevisitReason","星禾　「"+line+"」")
	var weather_line:=Revisit.RAINY if raining and ready and not done and not waiting else ""
	_put(app,"RevisitWeather",weather_line)
	var hold_text:=""
	if not Revisit.unlocked(s):hold_text=Revisit.LOCKED
	elif not Revisit.player_ready(s):hold_text=Revisit.NOT_READY
	elif waiting:hold_text=Revisit.RETURN_TOMORROW
	(_node(app,"RevisitHold") as Control).visible=not hold_text.is_empty()
	_put(app,"RevisitHoldText",hold_text)
	(_node(app,"RevisitMemory") as Control).visible=hold_text==Revisit.NOT_READY
	for id in ["RevisitFields","RevisitGates","RevisitActions"]:(_node(app,id) as Control).visible=ready and not waiting
	# Fields.
	var here:=standing_field(person)
	for row:Dictionary in Revisit.fields(s):
		var id:String=row.id
		var share:=("分到 %d 份"%int(row.current)) if done else ("目前 %d 份／需要 %d 份"%[int(row.current),int(row.needed)])
		_put(app,"RevisitFieldShare_"+id,share,GOOD if bool(row.ok) or done else WARN)
		var mark:=MARK_DONE if bool(row.checked) else MARK_OPEN
		if id==here and not bool(row.checked):mark+="・你在這裡"
		_put(app,"RevisitFieldMark_"+id,mark,GOOD if bool(row.checked) else MUTED)
	# Gates.
	var gates:=Revisit.gates(s)
	var split:=Revisit.shares(s)
	var need:=Revisit.demand(s)
	var gate_block:=gate_reason(s,person)
	for which in ["a","b"]:
		var current:=int(gates[0 if which=="a" else 1])
		for level in Revisit.MAX_LEVEL+1:
			var b:=_enable(app,"RevisitGate_%s_%d"%[which,level],gate_block.is_empty(),gate_block if not gate_block.is_empty() else "把%s調到 %d 檔"%[Revisit.GATE_NAMES[which],level])
			if b!=null:b.set_pressed_no_signal(level==current)
	var split_text:="三塊田現在分到 %d／%d／%d 份・今天需要 %d／%d／%d 份"%[int(split[0]),int(split[1]),int(split[2]),int(need[0]),int(need[1]),int(need[2])]
	if done:split_text="完成那天三塊田分到 %d／%d／%d 份"%[int(split[0]),int(split[1]),int(split[2])]
	elif not Revisit.gates_today(s):split_text="今天還沒有人調整閘門・"+split_text
	_put(app,"RevisitSplit",split_text,GOOD if split==need or done else INK)
	# A reason already shown higher up is not repeated (buttons keep it as their tooltip).
	var gate_line:=gate_block if gate_block!=weather_line else ""
	_put(app,"RevisitGateReason",gate_line,MUTED if gate_block in [Revisit.ALREADY_DONE] else WARN)
	# Check.
	var check:=check_state(s,person)
	var check_button:=_enable(app,"RevisitCheck",bool(check[0]),str(check[1]) if not str(check[1]).is_empty() else "確認這塊田分到的水")
	if check_button!=null:check_button.text="巡看"+_field_name(here) if not here.is_empty() else "巡看這塊田"
	var check_line:=str(check[1])
	if check_line in [weather_line,gate_line]:check_line=""
	_put(app,"RevisitCheckReason",check_line,WARN)
	_put(app,"RevisitProgress","三塊田都巡看過了" if done else "今天已巡看 %d／3 塊田"%Revisit.checked_today(s).size(),GOOD if done else INK)
	# Completion and the plaque.
	var claimed:=Revisit.claimed_own(s)
	_put(app,"RevisitStatus",STATUS_CLAIMED if claimed else (STATUS_DONE if done else STATUS_OPEN),GOOD if done else INK)
	var claim_block:=claim_reason(s,person)
	_enable(app,"RevisitClaim",claim_block.is_empty(),claim_block if not claim_block.is_empty() else "向星禾領一塊分水木牌")
	_put(app,"RevisitClaimReason",claim_block,MUTED if claim_block in [Revisit.CLAIMED,Revisit.NOT_DONE] else WARN)
	link_focus(app)
	_restore_focus(app,focus_before)
	var signature:=JSON.stringify([ready,done,raining,gates,Revisit.checked_today(s),claimed,here,gate_block,check,claim_block])
	if force or str(app.modal.get_meta("revisit_signature",""))!=signature:
		app.modal.set_meta("revisit_signature",signature)
		app._layout_preview.call_deferred()

# -------------------------------------------------------------------- focus --

static func close_button(app) -> BaseButton:
	if not is_instance_valid(app.modal):return null
	var body:Control=app.modal.get_meta("revisit_body") if app.modal.has_meta("revisit_body") else null
	for node in app.modal.find_children("*","BaseButton",true,false):
		if body!=null and body.is_ancestor_of(node):continue
		return node as BaseButton
	return null

static func _shown(c:Control) -> bool:
	var node:Node=c
	while node!=null and node is Control:
		if not (node as Control).visible:return false
		if node.has_meta("revisit_body"):break
		node=node.get_parent()
	return true

static func focus_rows(app) -> Array:
	var rows:Array=[]
	var gate_ids:=[]
	for which in ["a","b"]:
		for level in Revisit.MAX_LEVEL+1:gate_ids.append("RevisitGate_%s_%d"%[which,level])
	for group:Array in [["RevisitMemory"],gate_ids,["RevisitCheck"],["RevisitClaim"],["RevisitCanal"]]:
		var row:Array[Button]=[]
		for id:String in group:
			var b:=_node(app,id) as Button
			if b!=null and _shown(b):row.append(b)
		if not row.is_empty():rows.append(row)
	return rows

static func link_focus(app) -> void:
	var rows:=focus_rows(app)
	var close:=close_button(app)
	var flat:Array[Button]=[]
	for row:Array in rows:
		for b:Button in row:flat.append(b)
	for r in rows.size():
		var row:Array=rows[r]
		for i in row.size():
			var b:Button=row[i]
			b.focus_neighbor_left=b.get_path_to(row[(i-1+row.size())%row.size()])
			b.focus_neighbor_right=b.get_path_to(row[(i+1)%row.size()])
			if r>0:b.focus_neighbor_top=b.get_path_to(rows[r-1][mini(i,rows[r-1].size()-1)])
			elif close!=null:b.focus_neighbor_top=b.get_path_to(close)
			b.focus_neighbor_bottom=b.get_path_to(rows[r+1][mini(i,rows[r+1].size()-1)] if r+1<rows.size() else b)
			var at:=flat.find(b)
			b.focus_next=b.get_path_to(flat[(at+1)%flat.size()])
			b.focus_previous=b.get_path_to(flat[(at-1+flat.size())%flat.size()])
	if close!=null and not flat.is_empty():
		close.focus_neighbor_bottom=close.get_path_to(flat[0])
		close.focus_neighbor_top=close.get_path_to(flat[flat.size()-1])

static func _focus_owner(app) -> Control:
	if not is_open(app):return null
	var owner:=(app.modal as Control).get_viewport().gui_get_focus_owner()
	if owner==null or not (app.modal as Node).is_ancestor_of(owner):return null
	return owner

## Claim, then 巡看, then the current level of the upstream gate, then the canal notes /
## memory page (opened at the fork the gate comes first).
static func preferred(app) -> Button:
	var s:Dictionary=app.session.snapshot
	var gates:=Revisit.gates(s)
	var gate_first:="RevisitGate_a_%d"%int(gates[0])
	var ids:=["RevisitClaim","RevisitCheck",gate_first,"RevisitMemory"]
	# Opened at the fork: the gate controls come first.
	if app.modal.get_meta("revisit_cell",Vector2i(-1,-1))==Revisit.GATE_CELL:ids=[gate_first,"RevisitClaim","RevisitCheck","RevisitMemory"]
	for id:String in ids:
		var b:=_node(app,id) as Button
		if b!=null and _shown(b) and not b.disabled:return b
	return _node(app,"RevisitCanal") as Button

static func focus_first(app) -> void:
	if not is_open(app):return
	var b:=preferred(app)
	if b!=null and b.is_visible_in_tree():b.grab_focus()

static func _restore_focus(app,before:Control) -> void:
	if before==null:return
	if not is_instance_valid(before) or not _shown(before):
		var next:=preferred(app)
		if next!=null:next.grab_focus.call_deferred()
