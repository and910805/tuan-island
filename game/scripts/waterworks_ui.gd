extends RefCounted
const World=preload("res://scripts/world.gd")
const Works=preload("res://scripts/waterworks.gd")
const Art=preload("res://scripts/waterworks_art.gd")
const Items=preload("res://scripts/inventory_item_art.gd")
const Shell=preload("res://scripts/life_ui_shell.gd")
const Pixel=preload("res://scripts/inventory_pixel_theme.gd")
const Helpers=preload("res://scripts/freight_ui.gd")

class MachinePreview extends TextureRect:
	var app
	var cell:Vector2i
	var elapsed:float=0.0
	func _process(delta:float)->void:
		elapsed+=delta
		if not is_instance_valid(app):return
		var snapshot:Dictionary=app.session.snapshot
		var device:Dictionary=snapshot.get("objects",{}).get(World.key(cell),{})
		var frame:int=Art.frame_for(device,float(snapshot.get("time",0)),elapsed,app.sound.reduced_motion)
		if texture is AtlasTexture:texture.region=Rect2(frame*48,0,48,48)

static func open(app,cell:Vector2i)->void:
	var body:VBoxContainer=app._open_modal("水力加工台")
	app.modal.set_meta("life_modal_layout","waterworks")
	app.modal.set_meta("waterworks_body",body)
	app.modal.set_meta("waterworks_cell",cell)
	app.modal.theme=Pixel.make(app.hud.theme)
	app.modal.add_theme_stylebox_override("panel",Pixel.frame_style())
	if is_instance_valid(app.modal_shade):app.modal_shade.color.a=0.22
	refresh(app)

static func refresh(app)->void:
	if not is_instance_valid(app.modal) or not app.modal.has_meta("waterworks_body"):return
	var s:Dictionary=app.session.snapshot
	var person:Dictionary=s.get("players",{}).get(app.session.own_id,{})
	if person.is_empty():return
	var cell:Vector2i=app.modal.get_meta("waterworks_cell")
	var device:Dictionary=s.get("objects",{}).get(World.key(cell),{})
	var present:bool=device.get("type","")=="waterworks"
	var near:=Vector2(person.x,person.y).distance_to(Vector2(cell)+Vector2(0.5,0.5))<=3.2
	var owner:bool=present and device.owner==app.session.own_id
	var network:=World.INDUSTRY.network_info(s,World.key(cell))
	var bag:Dictionary=person.inventory
	var signature:=JSON.stringify([device,near,owner,network,bag.get("wood",0),bag.get("copper_ore",0),bag.get("copper_joint",0)])
	if app.modal.get_meta("waterworks_signature","")==signature:
		progress(app,device,s)
		return
	app.modal.set_meta("waterworks_signature",signature)
	var body:VBoxContainer=app.modal.get_meta("waterworks_body")
	var focused:=body.get_viewport().gui_get_focus_owner()
	var focus_name:String=focused.name if is_instance_valid(focused) and body.is_ancestor_of(focused) else ""
	for child in body.get_children():body.remove_child(child);child.queue_free()
	if not present:
		Helpers.text(app,body,"加工台已移除。",20)
		return
	var permitted:=near and owner
	var flow:=HBoxContainer.new();flow.add_theme_constant_override("separation",18);body.add_child(flow)
	var inputs:=VBoxContainer.new();inputs.custom_minimum_size.x=225;flow.add_child(inputs)
	Helpers.text(app,inputs,"進料槽",18)
	for item in Works.INPUTS:
		var tray:=PanelContainer.new();tray.add_theme_stylebox_override("panel",Pixel.paper_style());inputs.add_child(tray)
		var row:=HBoxContainer.new();row.add_theme_constant_override("separation",10);tray.add_child(row)
		row.add_child(Shell.picture(Items.icon(item),64))
		var info:=VBoxContainer.new();info.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(info)
		Helpers.text(app,info,World.NAMES[item],16)
		Helpers.text(app,info,"%d / %d"%[int(device.input[item]),Works.INPUT_CAP],18).name="WorksInput_"+item
		Helpers.text(app,info,"背包 %d"%int(bag.get(item,0)),13)
		var feeding:=HBoxContainer.new();info.add_child(feeding)
		for quantity in [1,5]:
			var payload:="%s:%d"%[item,quantity]
			var button:=Helpers.action(app,feeding,"WorksFeed_"+item+"_"+str(quantity),"放 %d"%quantity,func():app.session.perform("waterworks_feed",cell,payload),permitted and int(bag.get(item,0))>0 and int(device.input[item])<Works.INPUT_CAP)
			button.tooltip_text="從背包放入，最多 %d 件。"%quantity
	var can_unload:=permitted
	var total:=0
	for item in Works.INPUTS:
		total+=int(device.input[item]);can_unload=can_unload and int(bag.get(item,0))<=1000000000-int(device.input[item])
	Helpers.action(app,inputs,"WorksUnload","取回料槽中的原料",func():app.session.perform("waterworks_unload_input",cell),can_unload and total>0)
	var arrow:=Helpers.text(app,flow,"→",26);arrow.custom_minimum_size.x=28;arrow.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	var machine:=VBoxContainer.new();machine.custom_minimum_size.x=220;machine.size_flags_horizontal=Control.SIZE_EXPAND_FILL;machine.add_theme_constant_override("separation",10);flow.add_child(machine)
	var preview:=MachinePreview.new();preview.name="WorksMachine";preview.app=app;preview.cell=cell
	preview.texture=Art.icon().duplicate();preview.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	preview.custom_minimum_size=Vector2(144,144);preview.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.size_flags_horizontal=Control.SIZE_SHRINK_CENTER;machine.add_child(preview)
	var status:=Helpers.text(app,machine,"",18);status.name="WorksStatus";status.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	status.custom_minimum_size.y=56;status.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	var gauge:=ProgressBar.new();gauge.name="WorksProgress";gauge.custom_minimum_size.y=18;gauge.show_percentage=false;machine.add_child(gauge)
	var cycle:=Helpers.text(app,machine,"每批 2 銅礦 + 1 木材 + 2 水\n12 秒 → 1 枚銅接頭",14);cycle.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	var toggle:=Helpers.action(app,machine,"WorksToggle","停用下一批" if device.enabled else "啟用自動加工",func():app.session.perform("waterworks_toggle",cell),permitted);toggle.custom_minimum_size.y=40
	var output_arrow:=Helpers.text(app,flow,"→",26);output_arrow.custom_minimum_size.x=28;output_arrow.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	var output:=VBoxContainer.new();output.custom_minimum_size.x=155;output.add_theme_constant_override("separation",10);flow.add_child(output)
	Helpers.text(app,output,"成品籃",18)
	output.add_child(Shell.picture(Items.icon("copper_joint"),96))
	var count:=int(device.items.get("copper_joint",0))
	Helpers.text(app,output,"銅接頭 %d / %d"%[count,Works.OUTPUT_CAP],17).name="WorksOutput"
	Helpers.text(app,output,"背包 %d"%int(bag.get("copper_joint",0)),14).name="WorksBagOutput"
	Helpers.action(app,output,"WorksCollect","收進背包",func():app.session.perform("waterworks_collect",cell),permitted and count>0 and int(bag.get("copper_joint",0))<=1000000000-count)
	Helpers.text(app,output,"接輸送帶後，\n成品可自動送入私人箱。",14)
	var water:=HBoxContainer.new();water.add_theme_constant_override("separation",10);body.add_child(water)
	water.add_child(Shell.picture(Items.icon("tank_kit"),32))
	Helpers.text(app,water,"機內水量 %d / %d"%[int(device.water),Works.CAPACITY],16).name="WorksWater"
	var pipe_text:="連接 %d 桶 · 桶中 %d 份水"%[int(network.connected_tanks),int(network.water)] if int(network.connected_tanks)>0 else "用水管連到自己的儲水桶"
	Helpers.text(app,water,pipe_text,14).name="WorksNetwork"
	Helpers.action(app,water,"WorksDrain","排空機內水",func():app.session.perform("waterworks_drain",cell),permitted and not device.enabled and not device.has("job") and int(device.water)>0)
	Helpers.text(app,body,"兩條進料帶分別送木材與銅礦，一條出料帶送銅接頭；留一側接水管。",14)
	var context:="這是另一位島民的加工台。" if not owner else ("靠近加工台才能操作。" if not near else "停用後會完成目前批次；清空原料、成品及水，才可搬移或拆除。")
	if is_instance_valid(app.modal_feedback) and app.modal.get_meta("waterworks_feedback_context","")!=context:
		app.modal.set_meta("waterworks_feedback_context",context)
		app.modal_feedback.text=context
		app.modal_feedback.remove_theme_color_override("font_color")
	progress(app,device,s)
	if not focus_name.is_empty():
		var next=body.find_child(focus_name,true,false)
		if next is Button and not next.disabled:next.grab_focus.call_deferred()
	app._layout_preview.call_deferred()

static func progress(app,device:Dictionary,snapshot:Dictionary)->void:
	if device.get("type")!="waterworks":return
	var status:=Works.status(device,float(snapshot.get("time",0)))
	var label=app.modal.find_child("WorksStatus",true,false)
	if label:
		label.text=str(status.text)+( " · %d 秒"%ceili(float(status.remaining)) if device.has("job") else "")
		if device.has("job") and not device.enabled:label.text+="\n完成後停止"
	var gauge=app.modal.find_child("WorksProgress",true,false)
	if gauge:gauge.value=100.0*(1.0-clampf(float(status.remaining)/Works.DURATION,0,1)) if device.has("job") else 0
