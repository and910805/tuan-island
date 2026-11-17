extends RefCounted
## 第 40 章家園「水塔」小頁（規則在 industry.gd 的 TOWER_*；這裡只讀快照、送 tower_toggle）。
##
## 靠近自己（或別人）的水塔按互動鍵（main._interact）打開。版面仿 diversion_gate_ui.gd：
##  * 上方：水塔圖（目前水位與設定）、存水 n／96 與水位條、目前設定、主人；一個切換按鈕
##    （出水 ⇄ 只蓄水）經 app.session.perform(TOWER_ACTION) 送到伺服器，只有主人能按，
##    別人看到唯讀頁與原因；
##  * 「補水」：依 Industry.tower_report 的 refill_zone 用白話說明現在怎麼補水，以及接通幾個儲水桶；
##  * 「供水」：這座水塔出水時送得到的灑水器／水力加工台（只走全開的分流閘），沒有時寫一行原因；
##  * 一段簡短說明水塔做什麼；頁底是伺服器回覆（main._notice 寫入 modal_feedback）。
## 結構只建一次，refresh() 原地更新，焦點留在切換按鈕上。
const World=preload("res://scripts/world.gd")
const Industry=preload("res://scripts/industry.gd")
const Art=preload("res://scripts/water_tower_art.gd")
const Gate=preload("res://scripts/diversion_gate_ui.gd")
const Shell=preload("res://scripts/lanyang_revisit_ui.gd")

const LAYOUT:="water_tower"
const INK:=Gate.INK
const MUTED:=Gate.MUTED
const WARN:=Gate.WARN
const GOOD:=Gate.GOOD
const REFILL:={
	"full":"儲水桶有剩水時會補進這座水塔。",
	"low":"水塔在「餘水」分流閘的另一側：只在儲水桶這一側補滿後才補。",
	"cut":"被關閉的分流閘擋住，現在補不到水。",
	"none":"這條水管沒有接儲水桶，水塔只會用掉已存的水。",
}
const MODE_HELP:={
	true:"出水：存水會送給下面這些灑水器和水力加工台。",
	false:"只蓄水：照常補水存起來，但不送水出去。",
}
const ABOUT:="水塔把儲水桶用剩的水存起來；餘水或關閉的分流閘另一側，靠水塔繼續供水。水塔不直接接河水泵，也不補儲水桶。"
const NOT_OWNER:="這是另一位島民的水塔，只有主人能切換。"
const GONE:="水塔已移除。"
const SUPPLY_TITLE:={true:"出水會送到",false:"改為出水後會送到"}
const RESERVE_HELP:="儲水桶合計超過這個量，多的才補進這座水塔。"
const QUOTA_HELP:="這座水塔每個世界日最多送出這麼多份水；午夜重新計算。"
const NO_CONSUMERS:="出水送不到任何灑水器或水力加工台（水塔出水只會經過全開的分流閘）。"

static func is_open(app) -> bool:
	return is_instance_valid(app.modal) and app.modal.has_meta("tower_body")

## main._layout_preview: centred, as tall as its content.
static func layout(app,bounds:Vector2) -> void:
	var modal:Control=app.modal
	var width:=minf(660.0,bounds.x-48)
	var cap:=bounds.y-40
	var height:=minf(cap,560)
	modal.size.x=width
	var outer:=modal.find_child("ModalScroll",true,false) as Control
	var content:=modal.find_child("ModalContent",true,false) as Control
	if outer!=null and content!=null:
		var chrome:float=modal.get_combined_minimum_size().y-outer.get_combined_minimum_size().y
		height=minf(cap,chrome+content.get_combined_minimum_size().y+2)
	modal.size=Vector2(width,height)
	modal.position=Vector2(floorf((bounds.x-width)/2),floorf((bounds.y-height)/2))

static func refill_text(zone:String) -> String:
	return str(REFILL.get(zone,REFILL.none))

static func consumer_line(row:Dictionary) -> String:
	return "%s（%s）"%[Gate.type_name(str(row.type)),str(row.key)]

static func toggle_text(enabled:bool) -> String:
	return "改為%s"%Industry.tower_enabled_name(not enabled)

static func reserve_text(reserve:int) -> String:
	return "桶水保留：不保留" if reserve<=0 else "桶水保留：儲水桶留 %d 份"%reserve

static func quota_text(quota:int,used:int) -> String:
	if quota<=0:return "每日配水：不限"
	if used>=quota:return "每日配水：%d 份・今天已送 %d（今天送完了）"%[quota,used]
	return "每日配水：%d 份・已送 %d・剩 %d"%[quota,used,quota-used]

## One settings row: a label plus 「－」「＋」 stepping through the rule's option list.
static func _setting_row(app,parent:Node,id:String,field:String) -> void:
	var row:=HBoxContainer.new()
	row.name=id+"Row"
	row.add_theme_constant_override("separation",8)
	parent.add_child(row)
	Gate._text(app,row,id,"",15)
	for step in [-1,1]:
		var b:Button=app.button("－" if step<0 else "＋",func():_step(app,field,step))
		b.name=id+("Less" if step<0 else "More")
		b.focus_mode=Control.FOCUS_ALL
		b.custom_minimum_size=Vector2(40,30)
		b.add_theme_font_size_override("font_size",15)
		b.size_flags_horizontal=Control.SIZE_SHRINK_END
		row.add_child(b)
	var less:=row.get_node(id+"Less") as Button
	var more:=row.get_node(id+"More") as Button
	less.focus_neighbor_right=less.get_path_to(more)
	more.focus_neighbor_left=more.get_path_to(less)

static func _options(field:String) -> Array:
	return Industry.TOWER_RESERVES if field=="reserve" else Industry.TOWER_QUOTAS

static func _step(app,field:String,step:int) -> void:
	if not is_open(app):return
	var cell:Vector2i=app.modal.get_meta("tower_cell")
	var report:=Industry.tower_report(app.session.snapshot,World.key(cell))
	if report.get("ok",false)!=true:return
	var options:=_options(field)
	var index:=options.find(int(report.get(field,0)))+step
	if index<0 or index>=options.size():return
	app.session.perform(Industry.TOWER_SET_ACTION,cell,"%s:%d"%[field,int(options[index])])
	refresh(app)

static func open(app,cell:Vector2i) -> void:
	var body:VBoxContainer=app._open_modal(World.BUILD[Industry.TOWER_KIND].name)
	Gate._style(app)
	app.modal.set_meta("life_modal_layout",LAYOUT)
	app.modal.set_meta("tower_body",body)
	app.modal.set_meta("tower_cell",cell)
	body.add_theme_constant_override("separation",5)
	var scroll:=body.get_parent() as ScrollContainer
	if scroll!=null:
		var shell:=scroll.get_parent() as VBoxContainer
		shell.add_theme_constant_override("separation",3)
		var divider:=shell.get_node_or_null("ModalFooterDivider") as HSeparator
		if divider!=null:divider.hide()
		if is_instance_valid(app.modal_feedback):app.modal_feedback.custom_minimum_size.y=0
	var head:=Gate._paper(body,"TowerHeader")
	var row:=HBoxContainer.new()
	row.add_theme_constant_override("separation",12)
	head.add_child(row)
	# Exactly 2× the 32×48 sprite so the pixels stay square.
	var picture:=Shell.picture(Art.tower_texture(0,true),64)
	picture.custom_minimum_size=Vector2(64,96)
	picture.name="TowerIcon"
	row.add_child(picture)
	var words:=VBoxContainer.new()
	words.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override("separation",3)
	row.add_child(words)
	Gate._text(app,words,"TowerWater","",19)
	var bar:=ProgressBar.new()
	bar.name="TowerBar"
	bar.max_value=Industry.TOWER_CAPACITY
	bar.show_percentage=false
	bar.custom_minimum_size=Vector2(0,14)
	bar.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	bar.mouse_filter=Control.MOUSE_FILTER_IGNORE
	words.add_child(bar)
	var mode_row:=HBoxContainer.new()
	mode_row.add_theme_constant_override("separation",12)
	words.add_child(mode_row)
	Gate._text(app,mode_row,"TowerMode","",16)
	var toggle:Button=app.button(toggle_text(true),func():_send(app))
	toggle.name="TowerToggle"
	toggle.focus_mode=Control.FOCUS_ALL
	toggle.custom_minimum_size=Vector2(128,32)
	toggle.add_theme_font_size_override("font_size",15)
	toggle.size_flags_horizontal=Control.SIZE_SHRINK_END
	mode_row.add_child(toggle)
	Gate._text(app,words,"TowerOwner","",14,MUTED)
	Gate._text(app,head,"TowerModeHelp","",14,MUTED)
	var refill:=Gate._paper(body,"TowerRefillCard")
	Gate._text(app,refill,"TowerRefillTitle","補水",16)
	Gate._text(app,refill,"TowerRefill","",15)
	Gate._text(app,refill,"TowerTanks","",14,MUTED)
	_setting_row(app,refill,"TowerReserve","reserve")
	var supply:=Gate._paper(body,"TowerSupplyCard")
	Gate._text(app,supply,"TowerSupplyTitle",str(SUPPLY_TITLE[true]),16)
	_setting_row(app,supply,"TowerQuota","quota")
	var list:=GridContainer.new()
	list.name="TowerConsumers"
	# Three columns: with the two settings rows, six consumers must still fit 1024×640.
	list.columns=3
	list.add_theme_constant_override("h_separation",14)
	list.add_theme_constant_override("v_separation",2)
	supply.add_child(list)
	var about:=Gate._paper(body,"TowerAboutCard")
	Gate._text(app,about,"TowerAbout",ABOUT,13,MUTED)
	refresh(app)
	app._layout_preview.call_deferred()
	_focus_first.call_deferred(app)

static func _send(app) -> void:
	if not is_open(app):return
	app.session.perform(Industry.TOWER_ACTION,app.modal.get_meta("tower_cell"))
	refresh(app)

static func _node(app,id:String) -> Control:
	if not is_open(app):return null
	return (app.modal.get_meta("tower_body") as Node).find_child(id,true,false) as Control

static func refresh(app) -> void:
	if not is_open(app):return
	var s:Dictionary=app.session.snapshot
	var cell:Vector2i=app.modal.get_meta("tower_cell")
	var key:=World.key(cell)
	var obj:Variant=s.get("objects",{}).get(key,{})
	var present:bool=obj is Dictionary and obj.get("type")==Industry.TOWER_KIND
	var owner:bool=present and str(obj.get("owner",""))==str(app.session.own_id)
	var report:=Industry.tower_report(s,key)
	var water:=int(report.get("water",0))
	var enabled:bool=report.get("enabled",false)==true
	var focus_before:Control=null
	var focus_owner:=(app.modal as Control).get_viewport().gui_get_focus_owner()
	if focus_owner!=null and (app.modal as Node).is_ancestor_of(focus_owner):focus_before=focus_owner
	(_node(app,"TowerWater") as Label).text=("存水 %d／%d"%[water,Industry.TOWER_CAPACITY]) if present else GONE
	var bar:=_node(app,"TowerBar") as ProgressBar
	bar.value=water if present else 0
	bar.visible=present
	var icon:=_node(app,"TowerIcon") as TextureRect
	icon.texture=Art.tower_texture(Art.level_of(water) if present else 0,enabled or not present)
	icon.modulate=Color.WHITE if present else Color(1,1,1,0.35)
	var mode:=_node(app,"TowerMode") as Label
	mode.text=("目前：%s"%Industry.tower_enabled_name(enabled)) if present else ""
	mode.add_theme_color_override("font_color",GOOD if enabled else WARN)
	var toggle:=_node(app,"TowerToggle") as Button
	toggle.text=toggle_text(enabled)
	toggle.visible=present
	toggle.disabled=not owner
	toggle.tooltip_text=str(MODE_HELP[not enabled]) if owner else (NOT_OWNER if present else GONE)
	var owner_label:=_node(app,"TowerOwner") as Label
	owner_label.text=("你的水塔・接在自己的水管上" if owner else "%s的水塔・只有主人能切換"%Gate._owner_name(s,str(obj.get("owner","")))) if present else ""
	owner_label.add_theme_color_override("font_color",MUTED if owner else WARN)
	owner_label.visible=present
	var help:=_node(app,"TowerModeHelp") as Label
	help.text=str(MODE_HELP[enabled]) if present else ""
	help.visible=present
	var zone:=str(report.get("refill_zone",Industry.TOWER_NONE))
	var refill:=_node(app,"TowerRefill") as Label
	refill.text=refill_text(zone) if present else ""
	refill.add_theme_color_override("font_color",GOOD if zone==Industry.ZONE_FULL else (INK if zone==Industry.ZONE_LOW else WARN))
	(_node(app,"TowerTanks") as Label).text="接通 %d 個儲水桶"%int(report.get("tanks",0))
	_node(app,"TowerRefillCard").visible=present
	(_node(app,"TowerSupplyTitle") as Label).text=str(SUPPLY_TITLE[enabled or not present])
	for setting in [["TowerReserve","reserve"],["TowerQuota","quota"]]:
		var field:=str(setting[1])
		var options:=_options(field)
		var index:=options.find(int(report.get(field,0)))
		var help_text:String=RESERVE_HELP if field=="reserve" else QUOTA_HELP
		var label:=_node(app,str(setting[0])) as Label
		label.text=reserve_text(int(report.get("reserve",0))) if field=="reserve" else quota_text(int(report.get("quota",0)),int(report.get("quota_used",0)))
		label.tooltip_text=help_text
		label.mouse_filter=Control.MOUSE_FILTER_PASS
		var less:=_node(app,str(setting[0])+"Less") as Button
		var more:=_node(app,str(setting[0])+"More") as Button
		less.disabled=not owner or index<=0
		more.disabled=not owner or index>=options.size()-1
		less.tooltip_text=help_text if owner else NOT_OWNER
		more.tooltip_text=less.tooltip_text
		_node(app,str(setting[0])+"Row").visible=present
	var signature:=JSON.stringify([present,report.get("consumers",[])])
	if str(app.modal.get_meta("tower_signature",""))!=signature:
		app.modal.set_meta("tower_signature",signature)
		var list:=_node(app,"TowerConsumers") as GridContainer
		for child in list.get_children():list.remove_child(child);child.queue_free()
		var consumers:Array=report.get("consumers",[]) if present else []
		for i in consumers.size():Gate._text(app,list,"TowerConsumer_%d"%i,consumer_line(consumers[i]),15,INK,false)
		if consumers.is_empty() and present:
			var empty:=Gate._text(app,list,"TowerConsumerEmpty",NO_CONSUMERS,15,MUTED)
			empty.custom_minimum_size.x=520
		_node(app,"TowerSupplyCard").visible=present
		app._layout_preview.call_deferred()
	if is_instance_valid(app.modal_feedback) and str(app.modal.get_meta("tower_context",""))!=str([present,owner]):
		app.modal.set_meta("tower_context",str([present,owner]))
		app.modal_feedback.text=("Esc 回到島上" if owner else NOT_OWNER) if present else GONE+"Esc 回到島上"
	if focus_before!=null and (not is_instance_valid(focus_before) or not focus_before.is_visible_in_tree() or (focus_before is BaseButton and focus_before.disabled)):
		var previous_name:=str(focus_before.name) if is_instance_valid(focus_before) else ""
		_restore_setting_focus.call_deferred(app,app.modal,previous_name)

static func _restore_setting_focus(app,page:Control,previous:String)->void:
	if not is_instance_valid(page) or app.modal!=page:return
	for prefix in ["TowerReserve","TowerQuota"]:
		if previous not in [prefix+"Less",prefix+"More"]:continue
		var sibling:=_node(app,prefix+("More" if previous.ends_with("Less") else "Less")) as Button
		if is_instance_valid(sibling) and sibling.is_visible_in_tree() and not sibling.disabled:
			sibling.grab_focus()
			return
	_focus_first(app)

## Owner: the toggle. Visitor / removed tower: the 關閉 button (Enter closes the page).
static func focus_toggle(app) -> bool:
	if not is_open(app):return false
	var toggle:=_node(app,"TowerToggle") as Button
	if is_instance_valid(toggle) and toggle.is_visible_in_tree() and not toggle.disabled:
		toggle.grab_focus()
		var scroll:=app.modal.find_child("ModalScroll",true,false) as ScrollContainer
		if scroll!=null and scroll.is_ancestor_of(toggle):scroll.ensure_control_visible(toggle)
	return true

static func _focus_first(app) -> void:
	if not is_open(app):return
	var toggle:=_node(app,"TowerToggle") as Button
	if toggle!=null and toggle.is_visible_in_tree() and not toggle.disabled:
		toggle.grab_focus()
		return
	for node in (app.modal as Node).find_children("*","Button",true,false):
		var b:=node as Button
		if b.is_visible_in_tree() and not b.disabled and b.text.contains("關閉"):
			b.grab_focus()
			return
