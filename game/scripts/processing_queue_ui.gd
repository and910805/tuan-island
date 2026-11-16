extends RefCounted
## 鋸木台／木炭窯加工台（T036 手動排程 + 自動緩衝）。
##
## Display + intent only: every operation goes through Session.perform and World
## stays the sole authority. This script never writes snapshot, World, inventory
## or save data.
##
## Station sources (public snapshot of the sawmill / charcoal_kiln object):
## - `processing` {active, waiting, ready}: authoritative manual queue (CookingQueue
##   canonical shape). When it exists any `job` beside it is a display-only Session
##   projection and is ignored entirely, so nothing is double counted.
## - legacy manual `job` only (untouched station): shown as one active/ready entry;
##   its cancel keeps the original `cancel_processing` (ProcessingCancel_legacy).
##   Enqueueing always sends `queue_processing`; World converts the legacy job
##   atomically with the first successful enqueue.
## - automatic buffer: `auto_enabled`, `input_wood`, `items`, `job.auto` — driven by
##   the original feed_processing / unload_processing_input / toggle_auto_processing /
##   collect_processing_output actions, unchanged.
##
## Acknowledgement: pending clears only on Session.action_completed with the exact
## predicted sequence AND action. Notices and periodic snapshots are never acks.
## No automatic retry. Remote timeout reports an unknown outcome.
##
## Main integration is not required: the controller connects Session.changed,
## Session.action_completed and the viewport itself and disconnects on exit. It
## owns its own positioning (unique layout meta) and re-fits deferred whenever
## main's generic preview layout or a minimum-size change moves the panel.

const World=preload("res://scripts/world.gd")
const Items=preload("res://scripts/inventory_item_art.gd")
const Pixel=preload("res://scripts/inventory_pixel_theme.gd")
const SourcePicker=preload("res://scripts/material_source_ui.gd")
const LAYOUT:="processing_queue"
const META:="processing_queue"

## Entry point (IndustryUI.device routes sawmill / charcoal_kiln here).
static func open(app,cell:Vector2i)->void:
	var obj:Dictionary=app.session.snapshot.get("objects",{}).get(World.key(cell),{})
	var kind:=str(obj.get("type",""))
	if not Controller.STATIONS.has(kind):return
	var body:VBoxContainer=app._open_modal(str(World.BUILD[kind].name))
	var modal:Control=app.modal
	modal.name="ProcessingQueueUI"
	if not app.village_art_preview:
		# Classic HUD: main does not hide the world HUD; use the shared restore list.
		for child in app.hud.get_children():
			if child is Control and child!=modal and child.visible:
				app.inventory_hidden_controls.append(child)
				child.hide()
	modal.set_meta("life_modal_layout",LAYOUT)
	modal.theme=Controller.make_theme(app.hud.theme if app.hud.theme else app.theme())
	modal.add_theme_stylebox_override("panel",Pixel.frame_style())
	modal.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	body.size_flags_vertical=Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",8)
	var outer:=body.get_parent() as ScrollContainer
	if outer:outer.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	if is_instance_valid(app.modal_shade):app.modal_shade.color.a=0.28
	if is_instance_valid(app.modal_feedback):
		# Keep one correlated status line; Main's generic notice is otherwise
		# repeated underneath it after every operation.
		app.modal_feedback.hide()
		var shell:Node=app.modal_feedback.get_parent()
		var previous:int=app.modal_feedback.get_index()-1
		if previous>=0 and shell.get_child(previous) is HSeparator:
			shell.get_child(previous).hide()
	var controller:=Controller.new()
	controller.name="ProcessingQueueController"
	controller.app=app
	controller.cell=cell
	controller.kind=kind
	modal.set_meta(META,controller)
	modal.add_child(controller)
	controller.build(body)
	controller.refresh()
	controller.fit(app.get_viewport().get_visible_rect().size)

## Optional hooks; main does not need to call them.
static func refresh(app)->void:
	var controller:=_controller(app)
	if controller:controller.refresh()

static func layout(app,bounds:Vector2)->void:
	var controller:=_controller(app)
	if controller:controller.fit(bounds)

static func _controller(app)->Controller:
	if not is_instance_valid(app.modal) or str(app.modal.get_meta("life_modal_layout",""))!=LAYOUT:return null
	var found=app.modal.get_meta(META,null)
	if not is_instance_valid(found) or not found is Controller:return null
	return found

## Pure display model of one station. Never mutates `obj`.
static func model(obj:Dictionary,now:float,own:String)->Dictionary:
	return Controller.model(obj,now,own)


class Controller extends Node:
	## `input`/`field`: automatic buffer item and its persisted key (legacy wood
	## stations keep input_wood; the Q05 mill buffers wheat in input_wheat).
	const STATIONS:={"sawmill":{"kit":"sawmill_kit","output":"plank","input":"wood","field":"input_wood"},
		"charcoal_kiln":{"kit":"kiln_kit","output":"charcoal","input":"wood","field":"input_wood"},
		"mill":{"kit":"mill_kit","output":"flour","input":"wheat","field":"input_wheat"},
		"seed_maker":{},"loom":{},"glass_furnace":{}}
	## Owner-only manual stations: 10-slot queue, no conveyor/auto buffer section.
	const MANUAL_ONLY:=["seed_maker","loom","glass_furnace"]
	const ACK_TIMEOUT_MS:=10000
	const INK:=Color("3d422d")
	const MUTED:=Color("76694c")
	const WARN:=Color("9c4b32")
	const GOOD:=Color("3e664b")
	const LIGHT:=Color("fff0ce")
	const PALE:=Color("e6dfbd")

	var app
	var cell:=Vector2i.ZERO
	var kind:=""
	var selected:=""
	var recipes:Dictionary={}
	var tab:=""
	var pending:Dictionary={}
	var refs:Dictionary={}
	var recipe_buttons:Dictionary={}
	var cancel_buttons:Array[Button]=[]
	var gated:Array[Button]=[]
	var slot_styles:Dictionary={}
	var queue_signature:=""
	var material_signature:=""
	var applied_size:=Vector2(-1,-1)
	var applied_position:=Vector2(-1,-1)
	var compact_mode:=-1
	var last:Dictionary={}

	# ------------------------------------------------------------- lifecycle

	func _ready()->void:
		app.session.changed.connect(_on_changed)
		app.session.action_completed.connect(_on_completed)
		get_viewport().size_changed.connect(_on_resized,CONNECT_DEFERRED)
		var modal:=get_parent() as Control
		if modal:
			# Main's generic preview layout (and its own minimum_size_changed hook)
			# resize the panel first; these deferred calls run afterwards in the same
			# message flush, so the generic 860px size never reaches a frame.
			modal.resized.connect(_on_resized,CONNECT_DEFERRED)
			modal.minimum_size_changed.connect(_on_resized,CONNECT_DEFERRED)

	func _exit_tree()->void:
		if app and app.session:
			if app.session.changed.is_connected(_on_changed):app.session.changed.disconnect(_on_changed)
			if app.session.action_completed.is_connected(_on_completed):app.session.action_completed.disconnect(_on_completed)
		var viewport:=get_viewport()
		if viewport and viewport.size_changed.is_connected(_on_resized):viewport.size_changed.disconnect(_on_resized)
		var modal:=get_parent() as Control
		if modal:
			if modal.resized.is_connected(_on_resized):modal.resized.disconnect(_on_resized)
			if modal.minimum_size_changed.is_connected(_on_resized):modal.minimum_size_changed.disconnect(_on_resized)

	func _on_changed(_snapshot:Dictionary,_id:String)->void:
		refresh()

	func _on_resized()->void:
		if is_inside_tree():fit(get_viewport().get_visible_rect().size)

	func _process(_delta:float)->void:
		if not pending.is_empty() and not bool(pending.host) and Time.get_ticks_msec()-int(pending.at)>ACK_TIMEOUT_MS:
			var intent:=str(pending.intent)
			var sourced:=bool(pending.get("sourced",false))
			pending={}
			if sourced and refs.has("picker"):refs.picker.release()
			refresh()
			_status("「%s」還沒收到回應。請確認連線，並先看排程與庫存是否已更新，再決定要不要重試，以免重複操作。"%intent,false)
		# Safety net for layout passes that move the panel without resizing it.
		var modal:=get_parent() as Control
		if modal and (modal.size!=applied_size or modal.position!=applied_position):
			fit(get_viewport().get_visible_rect().size)

	## Centered, pixel-snapped panel: <=980x620, fits 1024x640 and 1280x800.
	func fit(bounds:Vector2)->void:
		var modal:=get_parent() as Control
		if modal==null:return
		var target:=Vector2(minf(980.0,bounds.x-32.0),minf(620.0,bounds.y-32.0)).floor()
		if modal.size!=target:modal.size=target
		applied_size=modal.size
		var place:=((bounds-applied_size)/2.0).floor()
		place.x=maxf(0.0,place.x)
		place.y=maxf(0.0,place.y)
		if modal.position!=place:modal.position=place
		applied_position=modal.position
		_compact(bounds.y<720.0)

	func _compact(enabled:bool)->void:
		var mode:=1 if enabled else 0
		if mode==compact_mode:return
		compact_mode=mode
		if refs.has("station_icon"):(refs.station_icon as TextureRect).custom_minimum_size=Vector2(48,48) if enabled else Vector2(64,64)
		if refs.has("hero"):(refs.hero as TextureRect).custom_minimum_size=Vector2(48,48) if enabled else Vector2(64,64)
		for slot in refs.get("slots",[]):
			(slot as Control).custom_minimum_size=Vector2(36,36) if enabled else Vector2(40,40)

	# ---------------------------------------------------------- model helpers

	static func capacity()->int:
		return int(World.COOKING_QUEUE.CAPACITY)

	static func recipes_for(station:String)->Array:
		return World.processing_recipes(station).keys()

	static func model(obj:Dictionary,now:float,own:String)->Dictionary:
		var station:=str(obj.get("type",""))
		var out:={"present":STATIONS.has(station),"owner":str(obj.get("owner","")),"mode":"empty",
			"active":{},"waiting":[],"ready":[],"total":0,
			"auto_enabled":bool(obj.get("auto_enabled",false)),"auto_job":{},
			"input":int(obj.get("input_wood",0)),"stored":0}
		out.mine=bool(out.present) and str(out.owner)==own
		if out.present and station not in MANUAL_ONLY:
			out.input=int(obj.get(str(STATIONS[station].field),0))
			var items=obj.get("items",{})
			if items is Dictionary:out.stored=int(items.get(STATIONS[station].output,0))
		var queue=obj.get("processing")
		if queue is Dictionary:
			# Authoritative queue: any `job` here is a display projection — ignore it.
			out.mode="queue"
			var active=queue.get("active",{})
			if active is Dictionary and not active.is_empty():out.active=_entry(active,"active",now)
			for lane in ["waiting","ready"]:
				var list=queue.get(lane,[])
				if not list is Array:continue
				for raw in list:
					if raw is Dictionary:(out[lane] as Array).append(_entry(raw,lane,now))
		else:
			var job=obj.get("job")
			if job is Dictionary and not job.is_empty():
				var job_kind:=str(job.get("kind",""))
				var recipe:Dictionary=World.INDUSTRY.PROCESS.get(job_kind,{})
				var ready_at:=float(job.get("ready",0.0))
				var duration:=float(recipe.get("time",1.0))
				if bool(job.get("auto",false)):
					out.auto_job={"kind":job_kind,"finish":ready_at,"started":ready_at-duration,"yield":int(job.get("yield",recipe.get("yield",1)))}
				else:
					out.mode="legacy"
					var ingredients=job.get("ingredients",recipe.get("ingredients",{}))
					var entry:={"id":"","kind":job_kind,"owner":str(job.get("owner","")),"legacy":true,
						"yield":int(job.get("yield",recipe.get("yield",1))),
						"ingredients":ingredients if ingredients is Dictionary else {}}
					if now>=ready_at:
						entry.state="ready"
						entry.completed=ready_at
						(out.ready as Array).append(entry)
					else:
						entry.state="active"
						entry.finish=ready_at
						entry.started=maxf(0.0,ready_at-duration)
						out.active=entry
		out.total=(0 if (out.active as Dictionary).is_empty() else 1)+(out.waiting as Array).size()+(out.ready as Array).size()
		return out

	static func _entry(raw:Dictionary,state:String,now:float)->Dictionary:
		var ingredients=raw.get("ingredients",{})
		var entry:={"id":str(raw.get("id","")),"kind":str(raw.get("kind","")),"owner":str(raw.get("owner","")),
			"yield":int(raw.get("yield",1)),"ingredients":ingredients if ingredients is Dictionary else {},
			"state":state,"legacy":false}
		if state=="active":
			entry.started=float(raw.get("started",now))
			entry.finish=float(raw.get("finish",now))
		elif state=="ready":
			entry.completed=float(raw.get("completed",now))
		return entry

	static func item_name(item:String)->String:
		return str(World.NAMES.get(item,item))

	static func ingredient_text(ingredients:Dictionary)->String:
		var parts:=PackedStringArray()
		for item in ingredients:parts.append("%s %d"%[item_name(str(item)),int(ingredients[item])])
		return "、".join(parts) if not parts.is_empty() else "無"

	static func who(snapshot:Dictionary,own:String,owner:String)->String:
		if owner.is_empty():return "不明島民"
		if owner==own:return "你"
		var person=snapshot.get("players",{}).get(owner)
		if person is Dictionary and not str(person.get("name","")).is_empty():return str(person.name)
		return "其他島民"

	static func make_theme(base:Theme)->Theme:
		var theme:=Pixel.make(base)
		var disabled:=Pixel.texture_style("button_normal",3,0)
		disabled.modulate_color=Color(1,1,1,0.55)
		for side in [SIDE_LEFT,SIDE_RIGHT]:disabled.set_content_margin(side,12)
		for side in [SIDE_TOP,SIDE_BOTTOM]:disabled.set_content_margin(side,8)
		theme.set_stylebox("disabled","Button",disabled)
		theme.set_color("font_disabled_color","Button",Color(INK,0.5))
		theme.set_stylebox("background","ProgressBar",Pixel.texture_style("normal",3,2))
		var fill:=StyleBoxFlat.new()
		fill.bg_color=Color("c98a45")
		fill.border_color=Color("8f5a2a")
		fill.set_border_width_all(2)
		fill.anti_aliasing=false
		theme.set_stylebox("fill","ProgressBar",fill)
		theme.set_color("font_color","Label",INK)
		return theme

	# ------------------------------------------------------------------ build

	func build(body:VBoxContainer)->void:
		for state in ["empty","active","waiting","ready"]:
			var asset:String={"empty":"normal","active":"selected","waiting":"pressed","ready":"hover"}[state]
			slot_styles[state]=Pixel.texture_style(asset,3,3)
		recipes=World.processing_recipes(kind)
		selected=str(recipes.keys()[0]) if not recipes.is_empty() else ""
		var s:Dictionary=app.session.snapshot
		var first:=model(s.get("objects",{}).get(World.key(cell),{}),float(s.get("time",0.0)),app.session.own_id)
		tab="auto" if bool(first.auto_enabled) or not (first.auto_job as Dictionary).is_empty() else "manual"
		_build_header(body)
		var pages:=Control.new()
		pages.name="ProcessingPages"
		pages.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		pages.size_flags_vertical=Control.SIZE_EXPAND_FILL
		body.add_child(pages)
		var manual:=HBoxContainer.new()
		manual.name="ProcessingManualPage"
		manual.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		manual.add_theme_constant_override("separation",12)
		pages.add_child(manual)
		refs.manual_page=manual
		_build_recipe(_column(manual,"ProcessingRecipeColumn",1.0,false))
		_build_queue(_column(manual,"ProcessingQueueColumn",1.3,true))
		var automatic:=HBoxContainer.new()
		automatic.name="ProcessingAutoPage"
		automatic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		automatic.add_theme_constant_override("separation",12)
		pages.add_child(automatic)
		refs.auto_page=automatic
		if kind not in MANUAL_ONLY:_build_auto(automatic)
		var status:=_text(body,"",14,MUTED)
		status.name="ProcessingStatus"
		status.custom_minimum_size.y=22
		status.autowrap_mode=TextServer.AUTOWRAP_OFF
		status.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
		refs.status=status
		_status("選好配方就能排入加工；材料預設只用背包。",true)
		(refs.status as Label).add_theme_color_override("font_color",MUTED)
		show_tab(tab)

	func _build_header(body:VBoxContainer)->void:
		var header:=HBoxContainer.new()
		header.name="ProcessingHeader"
		header.add_theme_constant_override("separation",10)
		body.add_child(header)
		var art:Texture2D=null
		# Glass furnace shows its own pale-brick body; kiln kit only if that fails.
		if kind=="glass_furnace":
			art=preload("res://scripts/glass_furnace_art.gd").texture()
			if art==null:art=Items.icon("kiln_kit")
		elif kind in MANUAL_ONLY:art=preload("res://assets/bakery/seed-maker.png")
		else:art=Items.icon(str(STATIONS[kind].kit))
		var icon:=_picture(art,64)
		icon.name="ProcessingStationIcon"
		header.add_child(icon)
		refs.station_icon=icon
		var info:=VBoxContainer.new()
		info.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		info.alignment=BoxContainer.ALIGNMENT_CENTER
		info.add_theme_constant_override("separation",2)
		header.add_child(info)
		refs.header_title=_text(info,"",19)
		refs.header_title.autowrap_mode=TextServer.AUTOWRAP_OFF
		refs.header_owner=_text(info,"",14,MUTED)
		refs.header_owner.autowrap_mode=TextServer.AUTOWRAP_OFF
		refs.header_owner.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
		if kind in MANUAL_ONLY:return
		var group:=ButtonGroup.new()
		for spec in [["ProcessingManualTab","手動排程","manual"],["ProcessingAutoTab","自動緩衝","auto"]]:
			var id:String=spec[2]
			var button:=Button.new()
			button.name=spec[0]
			button.text=spec[1]
			button.toggle_mode=true
			button.button_group=group
			button.focus_mode=Control.FOCUS_ALL
			button.custom_minimum_size=Vector2(112,38)
			button.size_flags_vertical=Control.SIZE_SHRINK_CENTER
			button.add_theme_font_size_override("font_size",15)
			button.pressed.connect(func():show_tab(id))
			header.add_child(button)
			refs["tab_"+id]=button

	func _column(parent:Control,id:String,ratio:float,dark:bool)->VBoxContainer:
		var frame:=PanelContainer.new()
		frame.name=id
		var paper:=Pixel.paper_style()
		if dark:paper.modulate_color=Color("46694f")
		frame.add_theme_stylebox_override("panel",paper)
		frame.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		frame.size_flags_vertical=Control.SIZE_EXPAND_FILL
		frame.size_flags_stretch_ratio=ratio
		parent.add_child(frame)
		var column:=VBoxContainer.new()
		column.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		column.add_theme_constant_override("separation",6)
		frame.add_child(column)
		return column

	func _scroll(parent:Control,id:String,minimum:float)->VBoxContainer:
		var scroll:=ScrollContainer.new()
		scroll.name=id
		scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
		scroll.custom_minimum_size.y=minimum
		scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
		parent.add_child(scroll)
		var column:=VBoxContainer.new()
		column.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		column.add_theme_constant_override("separation",6)
		scroll.add_child(column)
		return column

	func _build_recipe(column:VBoxContainer)->void:
		_text(column,"加工配方",18)
		var footer:=column
		column=_scroll(column,"ProcessingRecipeScroll",80)
		var recipes:=recipes_for(kind)
		if recipes.size()>1:
			var grid:=GridContainer.new()
			grid.name="ProcessingRecipes"
			grid.columns=5 if kind=="seed_maker" else 4
			grid.add_theme_constant_override("h_separation",6)
			column.add_child(grid)
			var group:=ButtonGroup.new()
			for id in recipes:
				var recipe_id:String=id
				var button:=Button.new()
				button.name="ProcessingRecipe_"+recipe_id
				button.theme_type_variation="ItemSlot"
				button.toggle_mode=true
				button.button_group=group
				button.focus_mode=Control.FOCUS_ALL
				button.custom_minimum_size=Vector2(48,48)
				button.tooltip_text=item_name(recipe_id)
				var art:=_picture(Items.icon(recipe_id),32)
				art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
				button.add_child(art)
				button.pressed.connect(func():select(recipe_id))
				grid.add_child(button)
				recipe_buttons[recipe_id]=button
		var card:=PanelContainer.new()
		card.name="ProcessingRecipeCard"
		card.add_theme_stylebox_override("panel",Pixel.texture_style("normal",3,8))
		column.add_child(card)
		var row:=HBoxContainer.new()
		row.add_theme_constant_override("separation",10)
		card.add_child(row)
		var hero:=_picture(null,64)
		hero.name="ProcessingSelectedIcon"
		row.add_child(hero)
		refs.hero=hero
		var info:=VBoxContainer.new()
		info.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		row.add_child(info)
		refs.hero_name=_text(info,"",19)
		refs.hero_info=_text(info,"",14,MUTED)
		_text(column,"所需材料（背包持有／需要）",14,MUTED)
		var materials:=VBoxContainer.new()
		materials.name="ProcessingMaterials"
		materials.add_theme_constant_override("separation",4)
		column.add_child(materials)
		refs.materials=materials
		# Material source (backpack only by default; one adjacent box on explicit choice).
		# Its status / refund lines replace the old "backpack only, no boxes" note.
		var picker=SourcePicker.create(app,cell,kind,"queue_processing",true)
		footer.add_child(picker)
		refs.picker=picker
		picker.state_changed.connect(refresh)
		var enqueue:=_action(footer,"ProcessingEnqueue","排入加工",func():
			var id:String=selected
			submit("queue_processing",id,"排入"+item_name(id),true))
		enqueue.custom_minimum_size.y=42
		refs.enqueue=enqueue
		gated.append(enqueue)

	func _build_queue(column:VBoxContainer)->void:
		var header:=HBoxContainer.new()
		column.add_child(header)
		_text(header,"加工排程",18,LIGHT)
		var capacity_label:=_text(header,"",16,LIGHT)
		capacity_label.name="ProcessingCapacity"
		capacity_label.size_flags_horizontal=Control.SIZE_SHRINK_END
		capacity_label.autowrap_mode=TextServer.AUTOWRAP_OFF
		capacity_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
		refs.capacity=capacity_label
		var slots:=HBoxContainer.new()
		slots.name="ProcessingSlots"
		slots.add_theme_constant_override("separation",4)
		column.add_child(slots)
		var slot_nodes:Array=[]
		for index in capacity():
			var slot:=PanelContainer.new()
			slot.name="ProcessingSlot_%d"%index
			slot.custom_minimum_size=Vector2(40,40)
			slot.add_theme_stylebox_override("panel",slot_styles.empty)
			slot.add_child(_picture(null,32))
			slots.add_child(slot)
			slot_nodes.append(slot)
		refs.slots=slot_nodes
		var card:=PanelContainer.new()
		card.name="ProcessingActive"
		card.add_theme_stylebox_override("panel",Pixel.texture_style("normal",3,8))
		column.add_child(card)
		var row:=HBoxContainer.new()
		row.add_theme_constant_override("separation",10)
		card.add_child(row)
		var icon:=_picture(null,32)
		icon.name="ProcessingActiveIcon"
		icon.size_flags_vertical=Control.SIZE_SHRINK_CENTER
		row.add_child(icon)
		refs.active_icon=icon
		var info:=VBoxContainer.new()
		info.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation",3)
		row.add_child(info)
		refs.active_title=_text(info,"",16)
		refs.active_title.autowrap_mode=TextServer.AUTOWRAP_OFF
		refs.active_title.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
		var gauge:=ProgressBar.new()
		gauge.name="ProcessingProgress"
		gauge.show_percentage=false
		gauge.max_value=100.0
		gauge.custom_minimum_size.y=14
		info.add_child(gauge)
		refs.progress=gauge
		refs.remaining=_text(info,"",13,MUTED)
		refs.remaining.autowrap_mode=TextServer.AUTOWRAP_OFF
		var actions:=HBoxContainer.new()
		actions.name="ProcessingActiveActions"
		actions.size_flags_vertical=Control.SIZE_SHRINK_CENTER
		row.add_child(actions)
		refs.active_actions=actions
		var lists:=_scroll(column,"ProcessingQueueScroll",64)
		refs.waiting_title=_text(lists,"",14,LIGHT)
		var waiting:=HFlowContainer.new()
		waiting.name="ProcessingWaiting"
		waiting.add_theme_constant_override("h_separation",5)
		waiting.add_theme_constant_override("v_separation",5)
		waiting.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		lists.add_child(waiting)
		refs.waiting=waiting
		refs.shelf_title=_text(lists,"",14,LIGHT)
		var shelf:=HFlowContainer.new()
		shelf.name="ProcessingShelf"
		shelf.add_theme_constant_override("h_separation",4)
		shelf.add_theme_constant_override("v_separation",4)
		shelf.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		lists.add_child(shelf)
		refs.shelf=shelf
		var claim:=_action(column,"ProcessingClaim","領取最早完成的成品",func():submit("claim_processing","","領取成品"))
		claim.custom_minimum_size.y=40
		refs.claim=claim
		gated.append(claim)

	func _build_auto(page:HBoxContainer)->void:
		var left:=_column(page,"ProcessingBufferColumn",1.0,false)
		_text(left,"自動緩衝",18)
		var footer:=left
		left=_scroll(left,"ProcessingBufferScroll",80)
		var output:String=STATIONS[kind].output
		var input:String=STATIONS[kind].input
		for spec in [["input",input,"料槽（投入%s）"%item_name(input)],["output",output,"產物庫"]]:
			var lane:String=spec[0]
			var card:=PanelContainer.new()
			card.name="ProcessingBuffer_"+lane
			card.add_theme_stylebox_override("panel",Pixel.texture_style("normal",3,8))
			left.add_child(card)
			var row:=HBoxContainer.new()
			row.add_theme_constant_override("separation",10)
			card.add_child(row)
			var art:=_picture(Items.icon(str(spec[1])),32)
			art.size_flags_vertical=Control.SIZE_SHRINK_CENTER
			row.add_child(art)
			var info:=VBoxContainer.new()
			info.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			info.add_theme_constant_override("separation",3)
			row.add_child(info)
			_text(info,str(spec[2]),13,MUTED)
			var amount:=_text(info,"",16)
			amount.autowrap_mode=TextServer.AUTOWRAP_OFF
			refs[lane+"_amount"]=amount
			var bar:=ProgressBar.new()
			bar.show_percentage=false
			bar.custom_minimum_size.y=12
			info.add_child(bar)
			refs[lane+"_bar"]=bar
		_text(left,"自動產物會先存進產物庫，需要時再領回背包；手動排程的成品不會進入產物庫。",13,MUTED)
		var supply:=HBoxContainer.new()
		supply.add_theme_constant_override("separation",8)
		footer.add_child(supply)
		var input_name:=item_name(input)
		var feed:=_action(supply,"ProcessingFeed","補入"+input_name,func():submit("feed_processing","","補入"+input_name))
		var unload:=_action(supply,"ProcessingUnload","取回"+input_name,func():submit("unload_processing_input","","取回"+input_name))
		var collect:=_action(supply,"ProcessingCollect","領取庫存",func():submit("collect_processing_output","","領取庫存"))
		for button in [feed,unload,collect]:
			button.size_flags_horizontal=Control.SIZE_EXPAND_FILL
			button.custom_minimum_size.y=40
			gated.append(button)
		refs.feed=feed
		refs.unload=unload
		refs.collect=collect
		var right:=_column(page,"ProcessingAutoColumn",1.1,true)
		_text(right,"自動加工",18,LIGHT)
		var footer_right:=right
		right=_scroll(right,"ProcessingAutoScroll",80)
		var card:=PanelContainer.new()
		card.name="ProcessingAutoJob"
		card.add_theme_stylebox_override("panel",Pixel.texture_style("normal",3,8))
		right.add_child(card)
		var row:=HBoxContainer.new()
		row.add_theme_constant_override("separation",10)
		card.add_child(row)
		var icon:=_picture(Items.icon(output),32)
		icon.size_flags_vertical=Control.SIZE_SHRINK_CENTER
		row.add_child(icon)
		refs.auto_icon=icon
		var info:=VBoxContainer.new()
		info.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation",3)
		row.add_child(info)
		refs.auto_title=_text(info,"",16)
		refs.auto_title.autowrap_mode=TextServer.AUTOWRAP_OFF
		var gauge:=ProgressBar.new()
		gauge.name="ProcessingAutoProgress"
		gauge.show_percentage=false
		gauge.max_value=100.0
		gauge.custom_minimum_size.y=14
		info.add_child(gauge)
		refs.auto_progress=gauge
		refs.auto_recipe=_text(info,"",13,MUTED)
		refs.auto_status=_text(right,"",15,LIGHT)
		refs.auto_status.name="ProcessingAutoStatus"
		var toggle:=_action(footer_right,"ProcessingToggleAuto","啟用自動加工",func():
			var enabled:bool=last.get("auto_enabled",false)
			submit("toggle_auto_processing","","停用自動加工" if enabled else "啟用自動加工"))
		toggle.custom_minimum_size.y=40
		refs.toggle=toggle
		gated.append(toggle)

	# ---------------------------------------------------------------- widgets

	func _text(parent:Node,value:String,size:int=15,color:Color=INK)->Label:
		var label:Label=app.label(value,size)
		label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_color_override("font_color",color)
		parent.add_child(label)
		return label

	func _picture(texture:Texture2D,extent:int)->TextureRect:
		var picture:=TextureRect.new()
		picture.texture=texture
		picture.custom_minimum_size=Vector2(extent,extent)
		picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
		picture.mouse_filter=Control.MOUSE_FILTER_IGNORE
		return picture

	func _action(parent:Node,id:String,title:String,callback:Callable)->Button:
		var button:=Button.new()
		button.name=id
		button.text=title
		button.focus_mode=Control.FOCUS_ALL
		button.add_theme_font_size_override("font_size",15)
		button.custom_minimum_size.y=36
		button.pressed.connect(callback)
		button.set_meta("allowed",false)
		parent.add_child(button)
		return button

	func _clear(container:Node)->void:
		for child in container.get_children():
			container.remove_child(child)
			child.queue_free()

	# ------------------------------------------------------------ interaction

	func show_tab(id:String)->void:
		tab=id
		(refs.manual_page as Control).visible=id=="manual"
		(refs.auto_page as Control).visible=id=="auto"
		if kind in MANUAL_ONLY:return
		(refs.tab_manual as Button).set_pressed_no_signal(id=="manual")
		(refs.tab_auto as Button).set_pressed_no_signal(id=="auto")

	func select(id:String)->void:
		if not recipes.has(id):return
		selected=id
		for key in recipe_buttons:(recipe_buttons[key] as Button).set_pressed_no_signal(key==id)
		material_signature=""
		refresh()

	## Sends one intent. Exact job IDs were captured when the control was built.
	## `sourced`: take the wire extra from the material source picker's frozen,
	## displayed split (plain recipe ID when backpack only). Never retried.
	func submit(action:String,extra:String,intent:String,sourced:bool=false)->void:
		if not pending.is_empty():
			_status("上一個加工操作還在等待回應，請稍候。",false)
			return
		var session=app.session
		var hosting:bool=session.world!=null
		if not hosting and not _connected():
			_status("與世界的連線已中斷，這次沒有送出。",false)
			return
		var picker=refs.get("picker")
		if sourced:
			if picker==null or str(picker.recipe_id)!=extra:return
			var frozen:Dictionary=picker.freeze()
			if not bool(frozen.get("ok",false)):
				_status(str(frozen.get("reason","目前不能排入。")),false)
				refresh()
				return
			extra=str(frozen.extra)
		# Predict the sequence first: a host completes synchronously inside perform().
		pending={"action":action,"extra":extra,"intent":intent,"at":Time.get_ticks_msec(),"host":hosting,"sequence":int(session.counter)+1,"sourced":sourced}
		_status(intent+"……等待回應",true)
		_sync_buttons()
		var sequence:int=session.perform(action,cell,extra)
		if pending.is_empty():return
		if sequence<=0:
			pending={}
			if sourced:picker.release()
			refresh()
			_status("世界正在關閉，這次沒有送出。",false)
			return
		pending.sequence=sequence
		if hosting:
			# Host returned without a matching completion: paused/not accepting, or this
			# action has no completion hook. Outcome is shown by the refreshed numbers.
			pending={}
			if sourced:picker.release()
			refresh()
			_status("「%s」沒有收到確認。請看畫面數值是否已更新；沒有變化時世界可能正在保存或暫停。"%intent,false)

	func _connected()->bool:
		var peer=app.session.multiplayer.multiplayer_peer
		return peer!=null and peer.get_connection_status()==MultiplayerPeer.CONNECTION_CONNECTED

	func _on_completed(sequence:int,action:String,result:Dictionary)->void:
		if pending.is_empty() or sequence!=int(pending.sequence) or action!=str(pending.action):return
		var message:=str(result.get("message","加工台已回覆。"))
		var success:=bool(result.get("ok",false))
		var sourced:=bool(pending.get("sourced",false))
		pending={}
		var note:=""
		if sourced and refs.has("picker"):note=refs.picker.release(result)
		if success:_status(message if note.is_empty() else "%s · %s"%[message,note],true)
		else:_status(note if not note.is_empty() else "沒有變更："+message,false)
		refresh()

	func _status(message:String,success:bool)->void:
		var label:Label=refs.get("status")
		if label==null:return
		label.text=message
		label.tooltip_text=message
		label.add_theme_color_override("font_color",GOOD if success else WARN)

	# ---------------------------------------------------------------- refresh

	func refresh()->void:
		if not refs.has("status") or not is_inside_tree():return
		var s:Dictionary=app.session.snapshot
		var own:String=app.session.own_id
		var bag:Dictionary=s.get("players",{}).get(own,{}).get("inventory",{})
		var now:=float(s.get("time",0.0))
		last=model(s.get("objects",{}).get(World.key(cell),{}),now,own)
		_sync_picker()
		_update_header(s,own)
		_update_recipe(bag)
		_update_queue(s,own,now,bag)
		if kind not in MANUAL_ONLY:_update_auto(now,bag)
		_sync_buttons()

	func _update_header(s:Dictionary,own:String)->void:
		var title:Label=refs.header_title
		var owner_label:Label=refs.header_owner
		if not last.present:
			title.text="加工台已移除"
			owner_label.text="這台設備已經不在目前區域。"
			return
		var mode:="自動加工中" if last.auto_enabled else ("手動排程" if last.total>0 else "閒置")
		title.text="%s · %s"%[World.BUILD[kind].name,mode]
		owner_label.text="擁有者：%s%s"%[who(s,own,str(last.owner)),"" if last.mine else " · 只有擁有者可以操作"]

	## Keeps the picker on the selected recipe and locked unless the owner can use
	## the station (prepare_material_box validates processing ownership too).
	## A frozen (pending) picker ignores recipe changes until acknowledged.
	func _sync_picker()->void:
		var picker=refs.get("picker")
		if picker==null or selected.is_empty():return
		var reason:=""
		if not last.present:reason="加工台不在這裡"
		elif not last.mine:reason="由擁有者操作"
		picker.set_locked(reason)
		if str(picker.recipe_id)!=selected and not picker.is_frozen():picker.set_recipe(selected,recipes[selected])
		else:picker.refresh()

	func _update_recipe(bag:Dictionary)->void:
		if selected.is_empty():return
		var recipe:Dictionary=recipes[selected]
		(refs.hero as TextureRect).texture=Items.icon(selected)
		(refs.hero_name as Label).text="%s ×%d"%[item_name(selected),int(recipe.yield)]
		(refs.hero_info as Label).text="每批 %d 秒 · 投入 %s"%[int(recipe.time),ingredient_text(recipe.ingredients)]
		var counts:Array=[selected]
		for item in recipe.ingredients:counts.append(int(bag.get(item,0)))
		var signature:=JSON.stringify(counts)
		if signature==material_signature:return
		material_signature=signature
		var list:VBoxContainer=refs.materials
		_clear(list)
		for item in recipe.ingredients:
			var need:=int(recipe.ingredients[item])
			var held:=int(bag.get(item,0))
			var row:=HBoxContainer.new()
			row.name="ProcessingMaterial_"+str(item)
			row.add_theme_constant_override("separation",8)
			list.add_child(row)
			row.add_child(_picture(Items.icon(str(item)),32))
			var title:=_text(row,item_name(str(item)),15)
			title.size_flags_vertical=Control.SIZE_SHRINK_CENTER
			var amount:=_text(row,"背包 %d／需 %d"%[held,need],15,GOOD if held>=need else WARN)
			amount.autowrap_mode=TextServer.AUTOWRAP_OFF
			amount.size_flags_horizontal=Control.SIZE_SHRINK_END
			amount.size_flags_vertical=Control.SIZE_SHRINK_CENTER
			amount.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT

	func _update_queue(s:Dictionary,own:String,now:float,_bag:Dictionary)->void:
		var cap:=capacity()
		var total:int=last.total
		var active:Dictionary=last.active
		var waiting:Array=last.waiting
		var ready:Array=last.ready
		var capacity_label:Label=refs.capacity
		capacity_label.text="%d／%d 格"%[total,cap]
		capacity_label.add_theme_color_override("font_color",Color("ffd59c") if total>=cap else LIGHT)
		var ordered:Array=[]
		ordered.append_array(ready)
		if not active.is_empty():ordered.append(active)
		ordered.append_array(waiting)
		var slots:Array=refs.slots
		for index in slots.size():
			var slot:PanelContainer=slots[index]
			var art:TextureRect=slot.get_child(0)
			if index<ordered.size():
				var entry:Dictionary=ordered[index]
				slot.add_theme_stylebox_override("panel",slot_styles[entry.state])
				art.texture=Items.icon(str(entry.kind))
				art.modulate=Color(1,1,1,0.6) if entry.state=="waiting" else Color.WHITE
				slot.tooltip_text="%s ×%d · %s"%[item_name(str(entry.kind)),int(entry.yield),{"active":"加工中","waiting":"等候中","ready":"完成待領"}[entry.state]]
			else:
				slot.add_theme_stylebox_override("panel",slot_styles.empty)
				art.texture=null
				art.modulate=Color.WHITE
				slot.tooltip_text="空位"
		var gauge:ProgressBar=refs.progress
		if active.is_empty():
			(refs.active_icon as TextureRect).texture=null
			(refs.active_title as Label).text="加工台空著"
			gauge.value=0
			if not (last.auto_job as Dictionary).is_empty():
				(refs.remaining as Label).text="自動加工正在進行，請到「自動緩衝」查看。"
			elif last.auto_enabled:
				(refs.remaining as Label).text="自動加工啟用中；停用後才能手動排程。"
			else:
				(refs.remaining as Label).text="排入的第一份會立刻開始。"
		else:
			var remaining:=maxf(0.0,float(active.finish)-now)
			var span:=maxf(0.001,float(active.finish)-float(active.started))
			(refs.active_icon as TextureRect).texture=Items.icon(str(active.kind))
			(refs.active_title as Label).text="加工中：%s ×%d%s"%[item_name(str(active.kind)),int(active.yield)," · 原有工作" if bool(active.legacy) else ""]
			gauge.value=100.0*clampf((now-float(active.started))/span,0.0,1.0)
			(refs.remaining as Label).text="已完成，稍後移到成品架" if remaining<=0.0 else "約剩 %d 秒"%ceili(remaining)
			(refs.active_title as Label).tooltip_text="投入材料："+ingredient_text(active.ingredients)
		(refs.waiting_title as Label).text="等候中（%d）"%waiting.size()
		(refs.shelf_title as Label).text="成品架（%d）"%ready.size()
		var claim:Button=refs.claim
		var finished_active:bool=not active.is_empty() and float(active.finish)<=now
		var claimable:bool=not ready.is_empty() or finished_active
		claim.set_meta("allowed",last.present and last.mine and claimable)
		if not ready.is_empty():
			var oldest:Dictionary=ready[0]
			claim.text="領取最早完成：%s ×%d"%[item_name(str(oldest.kind)),int(oldest.yield)]
		elif claimable:claim.text="領取剛完成的成品"
		else:claim.text="成品架上還沒有成品"
		if last.present and not last.mine:claim.text="由擁有者領取"
		var enqueue:Button=refs.enqueue
		var picker=refs.picker
		# Enabled when the displayed split (backpack first, then the chosen box) is
		# complete, even if the backpack alone is short; prepare/lock/no ID disable.
		var source_ok:bool=picker.can_submit()
		var auto_busy:bool=last.auto_enabled or not (last.auto_job as Dictionary).is_empty()
		enqueue.set_meta("allowed",last.present and last.mine and not auto_busy and total<cap and source_ok and not selected.is_empty())
		if not last.present:enqueue.text="加工台不在這裡"
		elif not last.mine:enqueue.text="由擁有者操作"
		elif last.auto_enabled:enqueue.text="先停用自動加工"
		elif auto_busy:enqueue.text="等自動批次完成"
		elif total>=cap:enqueue.text="排程已滿 %d／%d，請先領取"%[total,cap]
		elif not picker.plan_ok():enqueue.text="背包和箱子材料不足" if not str(picker.get_selected_cell()).is_empty() else "背包材料不足"
		elif not source_ok:enqueue.text=picker.block_reason()
		else:enqueue.text="排入加工 · %s%s"%[item_name(selected)," · 用箱子補足" if picker.uses_box() else ""]
		_rebuild_lists(s,own,now)

	## Rebuilds focusable rows only when the job set, ownership or cancelability changes.
	func _rebuild_lists(_s:Dictionary,own:String,now:float)->void:
		var active:Dictionary=last.active
		var parts:Array=[last.mode,own,last.present,last.mine]
		for entry in [active]+last.waiting+last.ready:
			if (entry as Dictionary).is_empty():continue
			parts.append([entry.id,entry.kind,entry.owner,entry.state,entry.yield,entry.state=="active" and float(entry.finish)>now])
		var signature:=JSON.stringify(parts)
		if signature==queue_signature:return
		queue_signature=signature
		var focus_owner:=get_viewport().gui_get_focus_owner()
		var focus_name:=""
		if is_instance_valid(focus_owner) and str(focus_owner.name).begins_with("ProcessingCancel_"):focus_name=str(focus_owner.name)
		cancel_buttons.clear()
		_clear(refs.active_actions)
		_clear(refs.waiting)
		_clear(refs.shelf)
		var mine:bool=last.present and last.mine
		if not active.is_empty() and mine:
			var target:String=active.id
			var legacy:bool=active.legacy
			var cancel:=_action(refs.active_actions,"ProcessingCancel_"+("legacy" if legacy else target),"取消並退回",func():
				submit("cancel_processing" if legacy else "cancel_processing_job",target,"取消"+item_name(str(active.kind))))
			cancel.tooltip_text="取消加工，退回"+ingredient_text(active.ingredients)
			# Legacy cancel keeps original behavior; queued active only before it finishes.
			cancel.set_meta("allowed",legacy or (float(active.finish)>now and not target.is_empty()))
			cancel_buttons.append(cancel)
		var position:=2 if not active.is_empty() else 1
		if (last.waiting as Array).is_empty():
			var empty_waiting:=_text(refs.waiting,"沒有等候中的工作。",13,PALE)
			empty_waiting.autowrap_mode=TextServer.AUTOWRAP_OFF
		for entry in last.waiting:
			var record:Dictionary=entry
			var card:=PanelContainer.new()
			card.name="ProcessingWaitingRow_"+str(record.id)
			card.custom_minimum_size.x=78
			card.add_theme_stylebox_override("panel",Pixel.texture_style("normal",3,3))
			card.tooltip_text="#%d · %s ×%d\n取消退回：%s"%[position,item_name(str(record.kind)),int(record.yield),ingredient_text(record.ingredients)]
			refs.waiting.add_child(card)
			var stack:=VBoxContainer.new()
			stack.add_theme_constant_override("separation",0)
			card.add_child(stack)
			var picture:=_picture(Items.icon(str(record.kind)),32)
			picture.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
			stack.add_child(picture)
			var row:=HBoxContainer.new()
			row.add_theme_constant_override("separation",2)
			stack.add_child(row)
			var order:=_text(row,"#%d ×%d"%[position,int(record.yield)],12,MUTED)
			order.autowrap_mode=TextServer.AUTOWRAP_OFF
			order.size_flags_vertical=Control.SIZE_SHRINK_CENTER
			position+=1
			if mine and not str(record.id).is_empty():
				var target:String=record.id
				var cancel:=_action(row,"ProcessingCancel_"+target,"×",func():
					submit("cancel_processing_job",target,"取消"+item_name(str(record.kind))))
				cancel.custom_minimum_size=Vector2(24,24)
				cancel.theme_type_variation="ItemSlot"
				cancel.tooltip_text="取消%s，退回%s"%[item_name(str(record.kind)),ingredient_text(record.ingredients)]
				cancel.size_flags_vertical=Control.SIZE_SHRINK_CENTER
				cancel.set_meta("allowed",true)
				cancel_buttons.append(cancel)
		if (last.ready as Array).is_empty():
			var empty_shelf:=_text(refs.shelf,"完成的成品會放在這裡，按領取放進背包。",13,PALE)
			empty_shelf.autowrap_mode=TextServer.AUTOWRAP_OFF
		var first:=true
		for entry in last.ready:
			var record:Dictionary=entry
			var legacy:bool=record.legacy
			var slot:=PanelContainer.new()
			slot.name="ProcessingReady_"+("legacy" if legacy else str(record.id))
			slot.custom_minimum_size=Vector2(52,52)
			slot.add_theme_stylebox_override("panel",slot_styles.active if first else slot_styles.ready)
			slot.tooltip_text="%s%s ×%d"%["下一份領取 · " if first else "",item_name(str(record.kind)),int(record.yield)]
			var next_to_claim:=first
			first=false
			var stack:=VBoxContainer.new()
			stack.add_theme_constant_override("separation",0)
			slot.add_child(stack)
			var art:=_picture(Items.icon(str(record.kind)),32)
			art.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
			stack.add_child(art)
			var amount:=Label.new()
			amount.text="×%d"%int(record.yield)
			amount.add_theme_font_size_override("font_size",12)
			amount.add_theme_color_override("font_color",LIGHT if next_to_claim else INK)
			amount.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
			amount.mouse_filter=Control.MOUSE_FILTER_IGNORE
			stack.add_child(amount)
			if legacy and mine:
				# Original UI allowed cancelling a finished legacy job (refunds materials).
				var cancel:=_action(stack,"ProcessingCancel_legacy","退回",func():
					submit("cancel_processing","","退回原有加工材料"))
				cancel.add_theme_font_size_override("font_size",12)
				cancel.custom_minimum_size=Vector2(0,24)
				cancel.tooltip_text="不領成品，改退回"+ingredient_text(record.ingredients)
				cancel.set_meta("allowed",true)
				cancel_buttons.append(cancel)
			refs.shelf.add_child(slot)
		if not focus_name.is_empty():
			var again=get_parent().find_child(focus_name,true,false) if get_parent() else null
			if again is Button and not again.disabled:again.grab_focus.call_deferred()

	func _update_auto(now:float,bag:Dictionary)->void:
		var output:String=STATIONS[kind].output
		var material:String=STATIONS[kind].input
		var material_name:=item_name(material)
		var recipe:Dictionary=World.INDUSTRY.PROCESS[output]
		var batch:=int(recipe.ingredients.get(material,0))
		var input:int=last.input
		var stored:int=last.stored
		var input_cap:=int(World.LOGISTICS.PROCESS_INPUT_CAP)
		var output_cap:=int(World.LOGISTICS.PROCESS_OUTPUT_CAP)
		(refs.input_amount as Label).text="%s %d／%d"%[material_name,input,input_cap]
		(refs.output_amount as Label).text="%s %d／%d"%[item_name(output),stored,output_cap]
		(refs.input_bar as ProgressBar).max_value=input_cap
		(refs.input_bar as ProgressBar).value=input
		(refs.output_bar as ProgressBar).max_value=output_cap
		(refs.output_bar as ProgressBar).value=stored
		var wood:=int(bag.get(material,0))
		var mine:bool=last.present and last.mine
		var feed:Button=refs.feed
		feed.set_meta("allowed",mine and input<input_cap and wood>0)
		feed.tooltip_text="從背包投入最多 4 份%s（背包 %d）"%[material_name,wood]
		(refs.unload as Button).set_meta("allowed",mine and input>0)
		(refs.collect as Button).set_meta("allowed",mine and stored>0)
		var toggle:Button=refs.toggle
		var enabled:bool=last.auto_enabled
		var queue_busy:bool=last.mode=="queue" and int(last.total)>0
		toggle.set_meta("allowed",mine and (enabled or not queue_busy))
		if not last.present:toggle.text="加工台不在這裡"
		elif not last.mine:toggle.text="由擁有者操作"
		elif enabled:toggle.text="停用自動加工"
		elif queue_busy:toggle.text="清空手動排程後才能啟用"
		else:toggle.text="啟用自動加工"
		(refs.auto_recipe as Label).text="%s %d → %s ×%d · %d 秒"%[material_name,batch,item_name(output),int(recipe.yield),int(recipe.time)]
		var job:Dictionary=last.auto_job
		var gauge:ProgressBar=refs.auto_progress
		var status:Label=refs.auto_status
		if not job.is_empty():
			var remaining:=maxf(0.0,float(job.finish)-now)
			var span:=maxf(0.001,float(job.finish)-float(job.started))
			gauge.value=100.0*clampf((now-float(job.started))/span,0.0,1.0)
			(refs.auto_title as Label).text="等待入庫" if remaining<=0.0 else "自動加工中 · 約剩 %d 秒"%ceili(remaining)
			status.text="本批完成後會存入產物庫。"
			status.add_theme_color_override("font_color",LIGHT)
			return
		gauge.value=0
		var color:=PALE
		if not last.present:
			(refs.auto_title as Label).text="加工台已移除"
			status.text=""
		elif not enabled:
			(refs.auto_title as Label).text="自動加工已停用"
			status.text="手動排程使用中，領完或取消全部工作後才能啟用自動加工。" if queue_busy else "啟用後，料槽裡的%s會自動加工並存入產物庫。"%material_name
		elif stored+int(recipe.yield)>output_cap:
			(refs.auto_title as Label).text="產物庫已滿"
			status.text="產物庫空間不足，請先領取庫存。"
			color=Color("ffd59c")
		elif input<batch:
			(refs.auto_title as Label).text="等待"+material_name
			status.text="料槽%s不足，請補入%s或用輸送帶送料。"%[material_name,material_name]
			color=Color("ffd59c")
		else:
			(refs.auto_title as Label).text="自動加工 · 待開始"
			status.text="等待開始下一批。"
		status.add_theme_color_override("font_color",color)

	func _sync_buttons()->void:
		var busy:=not pending.is_empty()
		var buttons:Array=[]
		buttons.append_array(gated)
		buttons.append_array(cancel_buttons)
		for button in buttons:
			if button is Button and is_instance_valid(button):
				button.disabled=busy or not bool(button.get_meta("allowed",false))
		if busy and refs.has("enqueue") and str(pending.action)=="queue_processing":
			(refs.enqueue as Button).text="等待加工台回應……"
