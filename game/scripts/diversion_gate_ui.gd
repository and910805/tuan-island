extends RefCounted
## 第 40 章家園「分流閘」小頁與「分水木牌」卡片（規則在 industry.gd 的 GATE_* 與
## lanyang_revisit.gd 的 PLAQUE_*；這裡只讀快照、送 gate_mode）。
##
##  * 分流閘：靠近自己（或別人）的分流閘按互動鍵（main._interact）。上方是目前設定與閘門圖，
##    三個設定按鈕（全開／餘水／關閉）經 app.session.perform("gate_mode") 送到伺服器，只有
##    主人能按；別人看到唯讀頁。下方用 INDUSTRY.zone_report 列出同一條水管上每一台灑水器／
##    水力加工台是「優先供水」「餘水」或「已截斷」，並說明儲水桶是同一池水。同一條水管上
##    若有水塔（第 40 章），另列每座水塔的補水區（zone_report().towers：優先補水／餘水才補／
##    補不到水／沒接儲水桶）；沒有水塔時這一段整個隱藏。
##    結構只建一次，refresh() 原地更新，焦點留在按下的按鈕上；伺服器回覆寫在頁底。
##  * 分水木牌：任何訪客靠近按互動鍵都能看：名稱、PLAQUE_BLURB、來源、對應工程、擺放者。
const World=preload("res://scripts/world.gd")
const Industry=preload("res://scripts/industry.gd")
const Revisit=preload("res://scripts/lanyang_revisit.gd")
const Art=preload("res://scripts/lanyang_revisit_art.gd")
const Shell=preload("res://scripts/lanyang_revisit_ui.gd")
const Pixel=preload("res://scripts/inventory_pixel_theme.gd")

const LAYOUT:="diversion_gate"
const PLAQUE_LAYOUT:="water_share_plaque"
const INK:=Color("3d422d")
const MUTED:=Color("7a6f58")
const WARN:=Color("9c4b32")
const GOOD:=Color("3e664b")
const MODE_HELP:={
	"open":"全開：水照常流過閘門，兩側的灑水器一起依序補水。",
	"low":"餘水：先補滿閘門這一側（儲水桶這邊），剩下的桶水才流到另一側。",
	"closed":"關閉：水流不到閘門另一側；那邊的灑水器只用自己已存的水。",
}
const ZONE_NAMES:={"full":"優先供水","low":"餘水","cut":"已截斷"}
const POOL_NOTE:="同一條水管上的儲水桶是同一池水；分流閘只決定先給誰、後給誰，不會把桶分開。河水泵照常把水送進桶裡。"
const NOT_OWNER:="這是另一位島民的分流閘，只有主人能切換。"
const GONE:="分流閘已移除。"
const NO_CONSUMERS:="這條水管還沒接上灑水器或水力加工台。"

static func is_open(app) -> bool:
	return is_instance_valid(app.modal) and app.modal.has_meta("gate_body")

static func plaque_open(app) -> bool:
	return is_instance_valid(app.modal) and app.modal.has_meta("plaque_body")

static func _style(app) -> void:
	app.modal.theme=Pixel.make(app.modal.theme if app.modal.theme else app.hud.theme)
	app.modal.add_theme_stylebox_override("panel",Pixel.frame_style())
	app.modal.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST

## main._layout_preview: centred, as tall as its content.
static func layout(app,bounds:Vector2) -> void:
	var modal:Control=app.modal
	var plaque:=plaque_open(app)
	var width:=minf(640.0 if plaque else 700.0,bounds.x-48)
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
	# The plaque card sits at the top so the plaque itself (beside the player, mid-screen)
	# stays in view under it.
	if plaque:modal.position.y=16.0

static func _text(app,parent:Node,id:String,value:String,size:int,color:Color=INK,wrap:=true) -> Label:
	var l:Label=app.label(value,size)
	l.name=id
	l.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	l.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	l.add_theme_color_override("font_color",color)
	parent.add_child(l)
	return l

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

static func _owner_name(s:Dictionary,owner:String) -> String:
	var person:Variant=s.get("players",{}).get(owner,{})
	var found:=str(person.get("name","")) if person is Dictionary else ""
	return found if not found.is_empty() else "另一位島民"

static func type_name(kind:String) -> String:
	return str(World.BUILD.get(kind,{}).get("name",kind))

# -------------------------------------------------------------------- gate --

static func open(app,cell:Vector2i) -> void:
	var body:VBoxContainer=app._open_modal(World.BUILD[Industry.GATE_KIND].name)
	_style(app)
	app.modal.set_meta("life_modal_layout",LAYOUT)
	app.modal.set_meta("gate_body",body)
	app.modal.set_meta("gate_cell",cell)
	body.add_theme_constant_override("separation",8)
	var head:=_paper(body,"GateHeader")
	var row:=HBoxContainer.new()
	row.add_theme_constant_override("separation",12)
	head.add_child(row)
	var picture:=Shell.picture(Art.gate_texture("open"),64)
	picture.name="GateIcon"
	row.add_child(picture)
	var words:=VBoxContainer.new()
	words.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override("separation",2)
	row.add_child(words)
	_text(app,words,"GateMode","",19)
	_text(app,words,"GateOwner","",14,MUTED)
	var modes:=HBoxContainer.new()
	modes.name="GateModes"
	modes.add_theme_constant_override("separation",8)
	head.add_child(modes)
	for mode:String in Industry.GATE_MODES:
		var b:Button=app.button(Industry.gate_mode_name(mode),func():_send(app,mode))
		b.name="GateMode_"+mode
		b.toggle_mode=true
		b.focus_mode=Control.FOCUS_ALL
		b.custom_minimum_size=Vector2(96,34)
		b.add_theme_font_size_override("font_size",15)
		b.icon=Art.gate_texture(mode)
		b.expand_icon=true
		b.add_theme_constant_override("icon_max_width",24)
		modes.add_child(b)
	for index in modes.get_child_count():
		var button:=modes.get_child(index) as Button
		button.focus_neighbor_left=button.get_path_to(modes.get_child(maxi(0,index-1)))
		button.focus_neighbor_right=button.get_path_to(modes.get_child(mini(modes.get_child_count()-1,index+1)))
	var help:=_paper(body,"GateHelp")
	for mode:String in Industry.GATE_MODES:_text(app,help,"GateHelp_"+mode,str(MODE_HELP[mode]),14,MUTED)
	var zones:=_paper(body,"GateZoneCard")
	_text(app,zones,"GateZoneTitle","這條水管上的灑水器",16)
	var list:=GridContainer.new()
	list.name="GateZones"
	list.columns=2
	list.add_theme_constant_override("h_separation",18)
	list.add_theme_constant_override("v_separation",2)
	zones.add_child(list)
	_text(app,zones,"GateTanks","",14)
	# 水塔（同一條水管上；zone_report().towers）：只有接了水塔才顯示。
	_text(app,zones,"GateTowerTitle","同一條水管上的水塔",16)
	var towers:=GridContainer.new()
	towers.name="GateTowers"
	towers.columns=2
	towers.add_theme_constant_override("h_separation",18)
	towers.add_theme_constant_override("v_separation",2)
	zones.add_child(towers)
	_text(app,zones,"GatePool",POOL_NOTE,13,MUTED)
	refresh(app)
	app._layout_preview.call_deferred()
	_focus_first.call_deferred(app)

static func _send(app,mode:String) -> void:
	if not is_open(app):return
	app.session.perform(Industry.GATE_ACTION,app.modal.get_meta("gate_cell"),mode)
	refresh(app)

static func _node(app,id:String) -> Control:
	if not is_open(app):return null
	return (app.modal.get_meta("gate_body") as Node).find_child(id,true,false) as Control

static func zone_line(row:Dictionary) -> String:
	return "%s（%s）・%s"%[type_name(str(row.type)),str(row.key),str(ZONE_NAMES.get(str(row.zone),""))]

## Tower refill zone as seen from the tanks (Industry.tower_refill_zones).
const TOWER_ZONE_NAMES:={"full":"優先補水","low":"餘水才補","cut":"補不到水","none":"沒接儲水桶"}

static func tower_line(row:Dictionary) -> String:
	return "水塔（%s）・%s"%[str(row.key),str(TOWER_ZONE_NAMES.get(str(row.zone),""))]

static func refresh(app) -> void:
	if not is_open(app):return
	var s:Dictionary=app.session.snapshot
	var cell:Vector2i=app.modal.get_meta("gate_cell")
	var key:=World.key(cell)
	var obj:Variant=s.get("objects",{}).get(key,{})
	var present:bool=obj is Dictionary and obj.get("type")==Industry.GATE_KIND
	var owner:bool=present and str(obj.get("owner",""))==str(app.session.own_id)
	var report:=Industry.zone_report(s,key)
	var mode:=str(report.get("mode","open")) if present else ""
	var signature:=JSON.stringify([present,owner,report])
	var focus_before:Control=null
	var focus_owner:=(app.modal as Control).get_viewport().gui_get_focus_owner()
	if focus_owner!=null and (app.modal as Node).is_ancestor_of(focus_owner):focus_before=focus_owner
	(_node(app,"GateMode") as Label).text=("目前：%s"%Industry.gate_mode_name(mode)) if present else GONE
	var owner_label:=_node(app,"GateOwner") as Label
	owner_label.text=("你的分流閘・接在自己的水管上" if owner else "%s的分流閘・只有主人能切換"%_owner_name(s,str(obj.get("owner","")))) if present else ""
	owner_label.add_theme_color_override("font_color",MUTED if owner else WARN)
	(_node(app,"GateIcon") as TextureRect).texture=Art.gate_texture(mode if present else "closed")
	for each:String in Industry.GATE_MODES:
		var b:=_node(app,"GateMode_"+each) as Button
		b.disabled=not owner
		b.set_pressed_no_signal(each==mode)
		b.tooltip_text=NOT_OWNER if present and not owner else (GONE if not present else str(MODE_HELP[each]))
		var help:=_node(app,"GateHelp_"+each) as Label
		help.add_theme_color_override("font_color",GOOD if each==mode else MUTED)
	if str(app.modal.get_meta("gate_signature",""))!=signature:
		app.modal.set_meta("gate_signature",signature)
		var list:=_node(app,"GateZones") as GridContainer
		for child in list.get_children():list.remove_child(child);child.queue_free()
		var consumers:Array=report.get("consumers",[])
		for i in consumers.size():
			var row:Dictionary=consumers[i]
			var zone:=str(row.zone)
			_text(app,list,"GateZone_%d"%i,zone_line(row),15,GOOD if zone==Industry.ZONE_FULL else (INK if zone==Industry.ZONE_LOW else WARN),false)
		if consumers.is_empty():_text(app,list,"GateZoneEmpty",NO_CONSUMERS,15,MUTED)
		(_node(app,"GateTanks") as Label).text="接通 %d 個儲水桶"%int(report.get("tanks",0)) if present else ""
		var tower_list:=_node(app,"GateTowers") as GridContainer
		for child in tower_list.get_children():tower_list.remove_child(child);child.queue_free()
		var towers:Array=report.get("towers",[]) if present else []
		for i in towers.size():
			var tower_zone:=str(towers[i].zone)
			_text(app,tower_list,"GateTower_%d"%i,tower_line(towers[i]),15,GOOD if tower_zone==Industry.ZONE_FULL else (INK if tower_zone==Industry.ZONE_LOW else WARN),false)
		tower_list.visible=not towers.is_empty()
		_node(app,"GateTowerTitle").visible=not towers.is_empty()
		app._layout_preview.call_deferred()
	if is_instance_valid(app.modal_feedback) and str(app.modal.get_meta("gate_context",""))!=str(owner):
		app.modal.set_meta("gate_context",str(owner))
		app.modal_feedback.text="Esc 回到島上" if owner else NOT_OWNER
	if focus_before!=null and not is_instance_valid(focus_before):_focus_first.call_deferred(app)

static func _focus_first(app) -> void:
	if not is_open(app):return
	var s:Dictionary=app.session.snapshot
	var obj:Variant=s.get("objects",{}).get(World.key(app.modal.get_meta("gate_cell")),{})
	var mode:=Art.mode_of(obj if obj is Dictionary else {})
	var b:=_node(app,"GateMode_"+mode) as Button
	if b!=null and not b.disabled:b.grab_focus()

# ------------------------------------------------------------------ plaque --

static func plaque(app,cell:Vector2i) -> void:
	var s:Dictionary=app.session.snapshot
	var obj:Variant=s.get("objects",{}).get(World.key(cell),{})
	var body:VBoxContainer=app._open_modal(Revisit.PLAQUE_NAME)
	_style(app)
	app.modal.set_meta("life_modal_layout",PLAQUE_LAYOUT)
	app.modal.set_meta("plaque_body",body)
	var card:=_paper(body,"PlaqueCard")
	var row:=HBoxContainer.new()
	row.add_theme_constant_override("separation",14)
	card.add_child(row)
	var picture:=Shell.picture(Art.plaque_texture(),96)
	picture.name="PlaqueIcon"
	row.add_child(picture)
	var words:=VBoxContainer.new()
	words.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override("separation",4)
	row.add_child(words)
	_text(app,words,"PlaqueName",Revisit.PLAQUE_NAME,21)
	_text(app,words,"PlaqueBlurb",Revisit.PLAQUE_BLURB,16)
	_text(app,words,"PlaqueSource",Revisit.PLAQUE_SOURCE,15,MUTED)
	_text(app,words,"PlaqueProject",Revisit.PLAQUE_PROJECT,15,MUTED)
	var owner:=_owner_name(s,str(obj.get("owner",""))) if obj is Dictionary else ""
	if not owner.is_empty():_text(app,words,"PlaqueOwner","擺放者・"+owner,14,MUTED)
	if is_instance_valid(app.modal_feedback):app.modal_feedback.text="紀念物・不能出售或交易・Esc 回到島上"
	app._layout_preview.call_deferred()
