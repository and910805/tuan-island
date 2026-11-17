extends RefCounted
const World=preload("res://scripts/world.gd")
const Drill=preload("res://scripts/mine_drill.gd")
const Art=preload("res://scripts/mine_drill_art.gd")
const Items=preload("res://scripts/inventory_item_art.gd")
const Shell=preload("res://scripts/life_ui_shell.gd")
const Pixel=preload("res://scripts/inventory_pixel_theme.gd")
const Helpers=preload("res://scripts/freight_ui.gd")
const FACING:=["北","東","南","西"]

class MachinePreview extends TextureRect:
	var app
	var cell:Vector2i
	var elapsed:=0.0
	func _process(delta:float)->void:
		elapsed+=delta
		if not is_instance_valid(app):return
		var s:Dictionary=app.session.snapshot
		var device:Dictionary=s.get("objects",{}).get(World.key(cell),{})
		var frame:int=Art.frame_for(device,float(s.get("time",0)),elapsed,app.sound.reduced_motion)
		texture=Art.frame_texture(frame,int(device.get("dir",0)))

static func open(app,cell:Vector2i)->void:
	var body:VBoxContainer=app._open_modal("採掘工作牌")
	body.add_theme_constant_override("separation",6)
	app.modal.set_meta("life_modal_layout","mine_drill")
	app.modal.set_meta("mine_drill_body",body)
	app.modal.set_meta("mine_drill_cell",cell)
	app.modal.theme=Pixel.make(app.hud.theme)
	app.modal.add_theme_stylebox_override("panel",Pixel.frame_style())
	app.modal.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	if is_instance_valid(app.modal_shade):app.modal_shade.color.a=0.16
	refresh(app)

static func refresh(app)->void:
	if not is_instance_valid(app.modal) or not app.modal.has_meta("mine_drill_body"):return
	var s:Dictionary=app.session.snapshot
	var person:Dictionary=s.get("players",{}).get(app.session.own_id,{})
	if person.is_empty():return
	var cell:Vector2i=app.modal.get_meta("mine_drill_cell")
	var device:Dictionary=s.get("objects",{}).get(World.key(cell),{})
	var region:String=s.get("region_id","home")
	var present:bool=device.get("type","")=="mine_drill" and region in World.MINES.IDS
	var owner:bool=present and device.get("owner","")==app.session.own_id
	var near:bool=Vector2(person.x,person.y).distance_to(Vector2(cell)+Vector2(0.5,0.5))<=3.2
	var bag:Dictionary=person.inventory
	var product:Dictionary=Drill.output(region) if present else {"item":"stone","quantity":0}
	var item:String=product.item
	var signature:=JSON.stringify([device,region,near,owner,bag.get("charcoal",0),bag.get(item,0)])
	if app.modal.get_meta("mine_drill_signature","")==signature:
		progress(app,device,s,region)
		return
	app.modal.set_meta("mine_drill_signature",signature)
	var body:VBoxContainer=app.modal.get_meta("mine_drill_body")
	var focused:=body.get_viewport().gui_get_focus_owner()
	var focus_name:String=focused.name if is_instance_valid(focused) and body.is_ancestor_of(focused) else ""
	for child in body.get_children():body.remove_child(child);child.queue_free()
	if not present:
		Helpers.text(app,body,"這處採掘設備已移除。",18)
		return
	var permitted:=owner and near
	Helpers.text(app,body,"第 %d 層 · %s工作面"%[World.MINES.IDS.find(region)+1,World.NAMES[item]],18).name="DrillLocation"
	var header:=HBoxContainer.new();header.add_theme_constant_override("separation",14);body.add_child(header)
	var preview:=MachinePreview.new();preview.name="DrillMachine";preview.app=app;preview.cell=cell
	preview.texture=Art.frame_texture(0,int(device.dir));preview.custom_minimum_size=Vector2(96,96)
	preview.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;preview.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;header.add_child(preview)
	var info:=VBoxContainer.new();info.size_flags_horizontal=Control.SIZE_EXPAND_FILL;header.add_child(info)
	var status:=Helpers.text(app,info,"",18);status.name="DrillStatus";status.custom_minimum_size.y=64
	var gauge:=ProgressBar.new();gauge.name="DrillProgress";gauge.show_percentage=false;gauge.custom_minimum_size.y=16;info.add_child(gauge)
	Helpers.text(app,info,"機頭朝%s · 對準礦脈"%FACING[int(device.dir)],14)
	var fuel_panel:=PanelContainer.new();fuel_panel.add_theme_stylebox_override("panel",Pixel.paper_style());body.add_child(fuel_panel)
	var fuel_row:=HBoxContainer.new();fuel_row.add_theme_constant_override("separation",12);fuel_panel.add_child(fuel_row)
	fuel_row.add_child(Shell.picture(Items.icon("charcoal"),52))
	var fuel_info:=VBoxContainer.new();fuel_info.size_flags_horizontal=Control.SIZE_EXPAND_FILL;fuel_row.add_child(fuel_info)
	Helpers.text(app,fuel_info,"木炭 %d / %d · 背包 %d"%[int(device.fuel),Drill.FUEL_CAP,int(bag.get("charcoal",0))],16).name="DrillFuel"
	var fuel_actions:=HBoxContainer.new();fuel_info.add_child(fuel_actions)
	for quantity in [1,5]:
		var payload:=str(quantity)
		Helpers.action(app,fuel_actions,"DrillFeed_"+payload,"放 %d"%quantity,func():app.session.perform("mine_drill_feed",cell,payload),permitted and int(device.fuel)<Drill.FUEL_CAP and int(bag.get("charcoal",0))>0)
	Helpers.action(app,fuel_actions,"DrillUnload","取回",func():app.session.perform("mine_drill_unload_fuel",cell),permitted and int(device.fuel)>0 and int(bag.get("charcoal",0))<=1000000000-int(device.fuel))
	var output_panel:=PanelContainer.new();output_panel.add_theme_stylebox_override("panel",Pixel.paper_style());body.add_child(output_panel)
	var output_row:=HBoxContainer.new();output_row.add_theme_constant_override("separation",12);output_panel.add_child(output_row)
	output_row.add_child(Shell.picture(Items.icon(item),52))
	var output_info:=VBoxContainer.new();output_info.size_flags_horizontal=Control.SIZE_EXPAND_FILL;output_row.add_child(output_info)
	var count:=int(device.items.get(item,0))
	Helpers.text(app,output_info,"%s %d / %d"%[World.NAMES[item],count,Drill.OUTPUT_CAP],17).name="DrillOutput"
	Helpers.text(app,output_info,"背包 %d"%int(bag.get(item,0)),14).name="DrillBagOutput"
	Helpers.action(app,output_row,"DrillCollect","收取",func():app.session.perform("mine_drill_collect",cell),permitted and count>0 and int(bag.get(item,0))<=1000000000-count)
	var toggle:=Helpers.action(app,body,"DrillToggle","停用下一批" if device.enabled else "啟用採掘",func():app.session.perform("mine_drill_toggle",cell),permitted)
	toggle.custom_minimum_size.y=42
	Helpers.text(app,body,"每批 %d 秒 · 1 木炭 → %d %s"%[int(Drill.DURATION),int(product.quantity),World.NAMES[item]],14)
	Helpers.text(app,body,"木炭與礦料可接輸送帶，另兩處礦點仍可手採。",14).name="DrillHint"
	var context:="這是其他島民的設備。" if not owner else ("靠近設備才能操作。" if not near else "停用並取完燃料、礦料後，才可搬移或拆除。")
	if is_instance_valid(app.modal_feedback) and app.modal.get_meta("mine_drill_context","")!=context:
		app.modal.set_meta("mine_drill_context",context);app.modal_feedback.text=context
		app.modal_feedback.remove_theme_color_override("font_color")
	progress(app,device,s,region)
	if not focus_name.is_empty():
		var next=body.find_child(focus_name,true,false)
		if next is Button and not next.disabled:next.grab_focus.call_deferred()
	app._layout_preview.call_deferred()

static func progress(app,device:Dictionary,s:Dictionary,region:String)->void:
	if device.get("type","")!="mine_drill":return
	var cooldown:=float(s.get("mine_depths",{}).get("ready",{}).get(region,{}).get(World.key(Drill.NODE),0))
	var state:Dictionary=Drill.status(device,region,float(s.get("time",0)),cooldown)
	var label=app.modal.find_child("DrillStatus",true,false)
	if label:
		label.text=str(state.text)
		if float(state.remaining)>0:label.text+=" · %d 秒"%ceili(float(state.remaining))
		if device.has("job") and not device.enabled:label.text+="\n完成後停止"
	var gauge=app.modal.find_child("DrillProgress",true,false)
	if gauge:gauge.value=100.0*(1.0-clampf(float(state.remaining)/Drill.DURATION,0,1)) if device.has("job") else 0
