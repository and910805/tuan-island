extends RefCounted
const World=preload("res://scripts/world.gd")
const Shell=preload("res://scripts/life_ui_shell.gd")
const Art=preload("res://scripts/mine_art.gd")
const Items=preload("res://scripts/inventory_item_art.gd")
const Slot=preload("res://scripts/item_slot.gd")
const Pixel=preload("res://scripts/inventory_pixel_theme.gd")
const Helpers=preload("res://scripts/freight_ui.gd")
const ORES:=["stone","copper_ore","gold_ore"]

class RouteTrack extends Control:
	var app
	var cart:TextureRect
	func _ready()->void:
		mouse_filter=Control.MOUSE_FILTER_IGNORE
		cart=Shell.picture(Art.freight_icon("loaded"),32)
		add_child(cart)
	func _process(_dt:float)->void:
		if not is_instance_valid(app) or not is_instance_valid(cart):return
		var s:Dictionary=app.session.snapshot
		var job:Dictionary=s.get("mine_freight",{}).get("own_job",{})
		var transit:bool=job.get("status","")=="transit"
		var fraction:=clampf(1.0-(float(job.get("ready",0))-float(s.get("time",0)))/60.0,0,1) if transit else 0.0
		cart.texture=Art.freight_icon("loaded" if transit else "cart")
		cart.position=Vector2(roundf((size.x-32)*(0.5 if app.sound.reduced_motion and transit else fraction)),0)

static func open(app)->void:
	var body:VBoxContainer=app._open_modal("礦場定期寄運")
	body.add_theme_constant_override("separation",6)
	if app.village_art_preview:body.get_parent().get_parent().add_theme_constant_override("separation",6)
	app.modal.set_meta("life_modal_layout","auto_freight")
	app.modal.theme=Pixel.make(app.hud.theme)
	app.modal.add_theme_stylebox_override("panel",Pixel.frame_style())
	app.modal.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	if is_instance_valid(app.modal_shade):app.modal_shade.color.a=0.2
	var ui:Dictionary={}
	app.modal.set_meta("auto_freight_ui",ui)
	app.modal.set_meta("auto_freight_draft",{"source":"","target":"","item":"copper_ore","reserve":0,"batch":8})
	var heading:=HBoxContainer.new();body.add_child(heading)
	heading.add_child(Shell.picture(Art.freight_icon("post"),48))
	var title:=VBoxContainer.new();title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;heading.add_child(title)
	ui.status=Helpers.text(app,title,"讓礦料自己搭車回家",19);ui.status.name="AutoFreightStatus"
	ui.status.custom_minimum_size.y=28
	ui.stock=Helpers.text(app,title,"",14);ui.stock.name="AutoFreightStock"
	Helpers.action(app,heading,"AutoManual","查看這一車",app._freight_menu)
	var endpoints:=HBoxContainer.new();endpoints.add_theme_constant_override("separation",12);body.add_child(endpoints)
	endpoint(app,endpoints,ui,"source","礦場收料箱","crate")
	var middle:=VBoxContainer.new();endpoints.add_child(middle)
	var track:=RouteTrack.new();track.name="AutoFreightTrack";track.app=app;track.custom_minimum_size=Vector2(64,32);middle.add_child(track)
	Helpers.text(app,middle,"60 秒",13)
	endpoint(app,endpoints,ui,"target","渡口收貨箱","post")
	var settings:=HBoxContainer.new();settings.add_theme_constant_override("separation",20);body.add_child(settings)
	var ores:=HBoxContainer.new();ores.add_theme_constant_override("separation",8);settings.add_child(ores)
	for item in ORES:
		var id:String=item
		var column:=VBoxContainer.new();ores.add_child(column)
		var slot=Slot.new();slot.name="AutoOre_"+id;slot.configure(id,Items.icon(id),1,World.NAMES[id]);slot.quantity.hide()
		slot.tooltip_text="寄運"+World.NAMES[id];slot.item_selected.connect(func(_kind):select_item(app,id))
		column.add_child(slot);ui["ore_"+id]=slot
		var label:=Helpers.text(app,column,World.NAMES[id],13);label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	var quantities:=VBoxContainer.new();quantities.size_flags_horizontal=Control.SIZE_EXPAND_FILL;settings.add_child(quantities)
	for key in ["reserve","batch"]:
		var field:String=key
		var row:=HBoxContainer.new();quantities.add_child(row)
		var label:=Helpers.text(app,row,"箱內保留" if key=="reserve" else "每車件數",15);label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		var spin:=SpinBox.new();spin.name="AutoReserve" if key=="reserve" else "AutoBatch"
		spin.min_value=0 if key=="reserve" else 1;spin.max_value=999999968 if key=="reserve" else 32
		spin.step=1;spin.custom_minimum_size=Vector2(142,40);row.add_child(spin);ui[field]=spin
		spin.value_changed.connect(func(value):
			var draft:Dictionary=app.modal.get_meta("auto_freight_draft");draft[field]=int(value);refresh(app))
	ui.rule=Helpers.text(app,body,"",15);ui.rule.name="AutoFreightRule";ui.rule.custom_minimum_size.y=24
	var controls:=HBoxContainer.new();controls.add_theme_constant_override("separation",10);body.add_child(controls)
	ui.save=Helpers.action(app,controls,"AutoSave","記下運送安排",func():save(app))
	ui.toggle=Helpers.action(app,controls,"AutoToggle","開始定期寄運",func():app.session.perform("mine_auto_toggle",World.MINES.SERVICE))
	ui.clear=Helpers.action(app,controls,"AutoClear","撤銷安排",func():app.session.perform("mine_auto_clear",World.MINES.SERVICE))
	for key in ["save","toggle","clear"]:
		ui[key].custom_minimum_size.y=42;ui[key].size_flags_horizontal=Control.SIZE_EXPAND_FILL
	ui.hint=Helpers.text(app,body,"",14);ui.hint.name="AutoFreightHint";ui.hint.custom_minimum_size.y=40
	refresh(app)
	app._layout_preview.call_deferred()

static func endpoint(app,parent:Control,ui:Dictionary,key:String,title:String,icon:String)->void:
	var card:=PanelContainer.new();card.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel",Pixel.paper_style());parent.add_child(card)
	var stack:=VBoxContainer.new();card.add_child(stack)
	var row:=HBoxContainer.new();stack.add_child(row)
	row.add_child(Shell.picture(Art.freight_icon(icon),32));Helpers.text(app,row,title,16)
	var chooser:=HBoxContainer.new();stack.add_child(chooser)
	ui[key+"_prev"]=Helpers.action(app,chooser,"Auto"+key.capitalize()+"Prev","‹",func():cycle_box(app,key,-1))
	var value:=Helpers.text(app,chooser,"尚未選擇",14);value.name="Auto"+key.capitalize()+"Label"
	value.size_flags_horizontal=Control.SIZE_EXPAND_FILL;value.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	ui[key+"_label"]=value
	ui[key+"_next"]=Helpers.action(app,chooser,"Auto"+key.capitalize()+"Next","›",func():cycle_box(app,key,1))

static func boxes(app,key:String)->Array:
	var s:Dictionary=app.session.snapshot
	return s.get("mine_auto_freight",{}).get("sources",[]) if key=="source" else s.get("mine_freight",{}).get("own_home_chests",[])

static func cycle_box(app,key:String,direction:int)->void:
	var options:=boxes(app,key)
	if options.is_empty():return
	var draft:Dictionary=app.modal.get_meta("auto_freight_draft")
	var index:=-1
	for i in range(options.size()):
		if options[i].cell==draft[key]:index=i
	draft[key]=options[posmod(index+direction,options.size())].cell
	refresh(app)

static func select_item(app,item:String)->void:
	var draft:Dictionary=app.modal.get_meta("auto_freight_draft")
	draft.item=item
	refresh(app)

static func save(app)->void:
	var draft:Dictionary=app.modal.get_meta("auto_freight_draft")
	app.session.perform("mine_auto_config",World.MINES.SERVICE,JSON.stringify(draft))

static func refresh(app)->void:
	if not is_instance_valid(app.modal) or not app.modal.has_meta("auto_freight_ui"):return
	var s:Dictionary=app.session.snapshot
	var person:Dictionary=s.get("players",{}).get(app.session.own_id,{})
	if person.is_empty():return
	var ui:Dictionary=app.modal.get_meta("auto_freight_ui")
	var data:Dictionary=s.get("mine_auto_freight",{})
	var route:Dictionary=data.get("route",{})
	var status:Dictionary=data.get("status",{})
	var draft:Dictionary=app.modal.get_meta("auto_freight_draft")
	var signature:=JSON.stringify(route)
	if app.modal.get_meta("auto_route_signature","initial")!=signature:
		app.modal.set_meta("auto_route_signature",signature)
		if not route.is_empty():
			draft.source=route.source.cell;draft.target=route.target.cell;draft.item=route.item;draft.reserve=route.reserve;draft.batch=route.batch
		ui.reserve.set_value_no_signal(float(draft.reserve));ui.batch.set_value_no_signal(float(draft.batch))
	var region:String=s.get("region_id","home")
	var mine:bool=region in ["mine_4","mine_5"] and int(s.get("mine_depths",{}).get("unlocked",0))>=5
	var near:bool=mine and Vector2(person.x,person.y).distance_to(Vector2(World.MINES.SERVICE)+Vector2(0.5,0.5))<=3.2
	var enabled:bool=route.get("enabled",false)
	var same_layer:bool=route.is_empty() or route.get("region","")==region
	var editable:bool=near and not enabled
	var choices_valid:=true
	for key in ["source","target"]:
		var options:=boxes(app,key)
		var found:=false
		for option in options:
			if option.cell==draft[key]:found=true
		if draft[key]=="" and not options.is_empty():draft[key]=options[0].cell;found=true
		ui[key+"_label"].text=("第 %s 層 · " % region.trim_prefix("mine_") if key=="source" and mine else "")+str(draft[key]) if found else ("請先放置私人箱" if draft[key]=="" else "原箱不在此處")
		ui[key+"_prev"].disabled=not editable or options.is_empty();ui[key+"_next"].disabled=not editable or options.is_empty()
		choices_valid=choices_valid and found
	for item in ORES:
		ui["ore_"+item].set_selected(draft.item==item);ui["ore_"+item].disabled=not editable
		if draft.item==item:ui["ore_"+item].add_theme_stylebox_override("disabled",Pixel.texture_style("button_pressed",3,0))
		else:ui["ore_"+item].remove_theme_stylebox_override("disabled")
	ui.reserve.editable=editable;ui.batch.editable=editable
	ui.save.disabled=not editable or not choices_valid
	var dirty:bool=not route.is_empty() and (draft.source!=route.source.cell or draft.target!=route.target.cell or draft.item!=route.item or int(draft.reserve)!=int(route.reserve) or int(draft.batch)!=int(route.batch))
	ui.toggle.text="暫停後續寄運" if enabled else "開始定期寄運"
	ui.toggle.disabled=not near or not same_layer or route.is_empty() or (not enabled and dirty)
	ui.clear.disabled=not near or not same_layer or route.is_empty() or enabled
	ui.status.text=status.get("text","選好箱子，礦料就能定期回家。")
	var job:Dictionary=s.get("mine_freight",{}).get("own_job",{})
	var stock:=int(s.get("objects",{}).get(draft.source,{}).get("items",{}).get(draft.item,0)) if mine else 0
	ui.stock.text="本車尚餘 %d 秒 · %d 件"%[maxi(0,ceili(float(job.get("ready",0))-float(s.get("time",0)))),World.MINE_FREIGHT.total(job.get("items",{}))] if job.get("status")=="transit" else ("所選箱內 %d 件 · 扣除保留可寄 %d 件"%[stock,maxi(0,stock-int(draft.reserve))] if mine else "每人一條寄運安排；回礦務站查看收料箱。")
	ui.rule.text="%s留 %d 件，湊滿 %d 件就出發。"%[World.NAMES[draft.item],int(draft.reserve),int(draft.batch)]
	var hint:="先記下安排，再開始寄運；只有選定的礦料會上車。"
	if status.get("id","") in ["missing_source","missing_target"]:hint="可以放回原箱；若要改用別箱，先暫停、重新選箱並記下安排。"
	elif enabled:hint="可以離開礦場繼續生活。暫停只停止新車，途中貨物仍會送達。"
	elif not route.is_empty():hint="安排已暫停。更換箱子或數量後，記得先記下新安排。"
	if dirty and not enabled:hint="新安排尚未記下；先儲存，再開始寄運。"
	if job.get("status")=="draft":hint="手動貨單優先；請先完成寄運或卸空並取消貨單。"
	if job.get("status")=="held":hint="上一車仍在等你：回渡口公告板領回後，才會再派新車。"
	ui.hint.text=hint
	var context:="在第四、五層礦務站安排寄運。" if not mine else ("走近礦務站才能更改。" if not near else ("既有安排在第 %s 層；回該層暫停後才能更改。"%str(route.get("region","")).trim_prefix("mine_") if enabled and not same_layer else "收料箱 → 礦務站 → 渡口私人箱；Esc 返回島上。"))
	if is_instance_valid(app.modal_feedback) and app.modal.get_meta("auto_context","")!=context:
		app.modal.set_meta("auto_context",context);app.modal_feedback.text=context;app.modal_feedback.remove_theme_color_override("font_color")
