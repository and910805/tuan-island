extends RefCounted
## 小石灶料理工作台（T036 排程介面）。
##
## Display + intent only: every operation goes through Session.perform and World
## stays the sole authority. This script never writes snapshot, World, inventory
## or save data.
##
## Station sources (from the public snapshot of the stove object):
## - `cooking` {active, waiting, ready}: authoritative queue. A display-only `job`
##   projection added by Session beside it is ignored so nothing is double counted.
## - legacy `job` only (untouched stove): shown as one active or ready entry; its
##   cancel keeps the original `cancel_cook`. Enqueueing always sends `queue_cook`,
##   which World converts atomically together with the new job.
##
## Acknowledgement: match Session.action_completed by sequence AND action.
## World notices and periodic snapshots never acknowledge a cooking intent.
## Host replies are synchronous; a remote timeout reports an unknown outcome.

const World=preload("res://scripts/world.gd")
const Items=preload("res://scripts/inventory_item_art.gd")
const Pixel=preload("res://scripts/inventory_pixel_theme.gd")
const SourcePicker=preload("res://scripts/material_source_ui.gd")
const LAYOUT:="cooking_queue"
const META:="cooking_queue"
const ACK_TIMEOUT_MS:=10000
const INK:=Color("3d422d")
const MUTED:=Color("76694c")
const WARN:=Color("9c4b32")
const GOOD:=Color("3e664b")

static func capacity()->int:
	return int(World.COOKING_QUEUE.CAPACITY)

## Entry point used by main.gd (both HUD modes) and life_ui_panels.gd.
static func open(app,cell:Vector2i)->void:
	var body:VBoxContainer=app._open_modal("小石灶料理工作台")
	var modal:Control=app.modal
	modal.name="CookingQueueUI"
	if not app.village_art_preview:
		for child in app.hud.get_children():
			if child is Control and child!=modal and child.visible:
				app.inventory_hidden_controls.append(child)
				child.hide()
	modal.set_meta("life_modal_layout",LAYOUT)
	modal.theme=_theme(app.hud.theme)
	modal.add_theme_stylebox_override("panel",Pixel.frame_style())
	modal.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	body.size_flags_vertical=Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation",8)
	var outer:=body.get_parent() as ScrollContainer
	if outer:
		outer.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_AUTO
	if is_instance_valid(app.modal_shade):app.modal_shade.color.a=0.28
	if is_instance_valid(app.modal_feedback):
		app.modal_feedback.text="預設只用背包，可選一個相鄰箱子補足 · Esc 回到島上"
		app.modal_feedback.remove_theme_color_override("font_color")
	var controller:=Controller.new()
	controller.name="CookingQueueController"
	controller.app=app
	controller.cell=cell
	modal.set_meta(META,controller)
	modal.add_child(controller)
	if not app.village_art_preview:
		modal.minimum_size_changed.connect(controller._on_resized,CONNECT_DEFERRED)
	controller.build(body)
	controller.refresh()
	layout(app,app.get_viewport().get_visible_rect().size)
	if app.village_art_preview:app._layout_preview.call_deferred()

## Called from main._state_changed for every snapshot.
static func refresh(app)->void:
	var controller:=_controller(app)
	if controller:controller.refresh()

## Called from main._layout_preview (preview HUD) and on viewport resize.
static func layout(app,bounds:Vector2)->void:
	var controller:=_controller(app)
	if controller==null:return
	controller.fit(bounds)

static func _controller(app)->Controller:
	if not is_instance_valid(app.modal) or str(app.modal.get_meta("life_modal_layout",""))!=LAYOUT:return null
	var found=app.modal.get_meta(META,null)
	if not is_instance_valid(found) or not found is Controller:return null
	return found

static func _theme(base:Theme)->Theme:
	var theme:=Pixel.make(base)
	var disabled:=Pixel.texture_style("button_normal",3,0)
	disabled.modulate_color=Color(1,1,1,0.55)
	for side in [SIDE_LEFT,SIDE_RIGHT]:disabled.set_content_margin(side,12)
	for side in [SIDE_TOP,SIDE_BOTTOM]:disabled.set_content_margin(side,8)
	theme.set_stylebox("disabled","Button",disabled)
	theme.set_color("font_disabled_color","Button",Color(INK,0.5))
	theme.set_stylebox("background","ProgressBar",Pixel.texture_style("normal",3,2))
	var fill:=StyleBoxFlat.new()
	fill.bg_color=Color("dd8f3e")
	fill.border_color=Color("a65a28")
	fill.set_border_width_all(2)
	fill.anti_aliasing=false
	theme.set_stylebox("fill","ProgressBar",fill)
	theme.set_color("font_color","Label",INK)
	return theme

## Pure display model of one stove. Never mutates `stove`.
## Returns {present, mode: queue|legacy|empty, active:{}, waiting:[], ready:[], total}.
static func model(stove:Dictionary,now:float)->Dictionary:
	return Controller.model(stove,now)


class Controller extends Node:
	var app
	var cell:=Vector2i.ZERO
	var selected:=""
	var pending:Dictionary={}
	var refs:Dictionary={}
	var recipe_buttons:Dictionary={}
	var cancel_buttons:Array[Button]=[]
	var queue_signature:=""
	var ingredient_signature:=""
	var slot_styles:Dictionary={}
	var elapsed:=0.0
	var compact_mode:=false
	var last:Dictionary={}

	func _ready()->void:
		app.session.action_completed.connect(_on_completed)
		get_viewport().size_changed.connect(_on_resized)

	func _exit_tree()->void:
		if app and app.session and app.session.action_completed.is_connected(_on_completed):app.session.action_completed.disconnect(_on_completed)
		var viewport:=get_viewport()
		if viewport and viewport.size_changed.is_connected(_on_resized):viewport.size_changed.disconnect(_on_resized)

	func _on_resized()->void:
		# Preview HUD also re-runs main._layout_preview, which calls fit() again.
		fit(get_viewport().get_visible_rect().size)

	func fit(bounds:Vector2)->void:
		var modal:=get_parent() as Control
		if modal==null:return
		compact(bounds.y<720.0)
		CookingLayout.fit(modal,bounds)

	func _process(delta:float)->void:
		elapsed+=delta
		if not pending.is_empty() and not bool(pending.host) and Time.get_ticks_msec()-int(pending.at)>ACK_TIMEOUT_MS:
			var sourced:bool=bool(pending.get("sourced",false))
			pending={}
			if sourced and refs.has("picker"):refs.picker.release()
			refresh()
			_status("還沒收到石灶回應。請確認連線；重試前先看排程是否已更新，以免重複排入。",false)
		var icon:TextureRect=refs.get("active_icon")
		if icon==null:return
		var motion:bool=app.sound!=null and not app.sound.reduced_motion
		if motion and not (last.get("active",{}) as Dictionary).is_empty():
			var glow:=0.5+0.5*sin(elapsed*PI)
			icon.modulate=Color(1.0+0.06*glow,1.0+0.03*glow,1.0-0.02*glow)
		else:
			icon.modulate=Color.WHITE

	func compact(enabled:bool)->void:
		compact_mode=enabled
		for id in recipe_buttons:
			(recipe_buttons[id] as Button).custom_minimum_size=Vector2(80,68) if enabled else Vector2(84,70)

	# ----------------------------------------------------------- model helpers

	static func model(stove:Dictionary,now:float)->Dictionary:
		var out:={"present":str(stove.get("type",""))=="stove","mode":"empty","active":{},"waiting":[],"ready":[],"total":0}
		var queue=stove.get("cooking")
		if queue is Dictionary:
			out.mode="queue"
			var active=queue.get("active",{})
			if active is Dictionary and not active.is_empty():out.active=_entry(active,"active",now)
			for lane in ["waiting","ready"]:
				var list=queue.get(lane,[])
				if not list is Array:continue
				for raw in list:
					if raw is Dictionary:(out[lane] as Array).append(_entry(raw,lane,now))
		else:
			var job=stove.get("job")
			if job is Dictionary and not job.is_empty():
				out.mode="legacy"
				var kind:=str(job.get("kind",""))
				var recipe:Dictionary=World.RECIPES.get(kind,{})
				var ready_at:=float(job.get("ready",0.0))
				var entry:={"id":"","kind":kind,"owner":str(job.get("owner","")),"legacy":true,
					"yield":int(job.get("yield",recipe.get("yield",1))),
					"ingredients":job.get("ingredients",recipe.get("ingredients",{}))}
				if now>=ready_at:
					entry.state="ready"
					entry.completed=ready_at
					(out.ready as Array).append(entry)
				else:
					entry.state="active"
					entry.finish=ready_at
					entry.started=maxf(0.0,ready_at-float(recipe.get("time",1.0)))
					entry.remaining=ready_at-now
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
			entry.remaining=float(entry.finish)-now
		elif state=="ready":
			entry.completed=float(raw.get("completed",now))
		return entry

	static func dish_name(kind:String)->String:
		if World.RECIPES.has(kind):return str(World.RECIPES[kind].name)
		return str(World.NAMES.get(kind,"未知料理"))

	static func item_name(item:String)->String:
		return str(World.NAMES.get(item,item))

	static func ingredient_text(ingredients:Dictionary)->String:
		var parts:=PackedStringArray()
		for item in ingredients:parts.append("%s %d"%[item_name(str(item)),int(ingredients[item])])
		return "、".join(parts)

	## Friendly contributor name from the public (hashed) actor id.
	static func who(snapshot:Dictionary,own_id:String,owner:String)->String:
		if owner.is_empty():return "不明島民"
		if owner==own_id:return "你"
		var person=snapshot.get("players",{}).get(owner)
		if person is Dictionary and not str(person.get("name","")).is_empty():return str(person.name)
		var helper=snapshot.get("festival",{}).get("contributors",{}).get(owner)
		if helper is Dictionary and not str(helper.get("name","")).is_empty():return str(helper.name)
		return "其他島民"

	# ------------------------------------------------------------------ build

	func build(body:VBoxContainer)->void:
		for state in ["empty","active","waiting","ready"]:
			var asset:String={"empty":"normal","active":"selected","waiting":"pressed","ready":"hover"}[state]
			slot_styles[state]=Pixel.texture_style(asset,3,3)
		var root:=HBoxContainer.new()
		root.name="CookingWorkArea"
		root.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		root.size_flags_vertical=Control.SIZE_EXPAND_FILL
		root.add_theme_constant_override("separation",12)
		body.add_child(root)
		_build_book(_column(root,"CookingCookbook",1.0))
		_build_station(_column(root,"CookingStation",1.2))
		var status:Label=app.modal_feedback if is_instance_valid(app.modal_feedback) else _text(body,"",14)
		status.text="選一道喜歡的料理，讓小石灶暖起來。材料預設只用背包。"
		status.name="CookingStatus"
		status.custom_minimum_size.y=24
		refs.status=status
		select(World.RECIPES.keys()[0] if selected.is_empty() else selected)

	func _column(parent:Control,id:String,ratio:float)->VBoxContainer:
		var frame:=PanelContainer.new()
		frame.name=id
		var paper:=Pixel.paper_style()
		if id=="CookingStation":paper.modulate_color=Color("526b50")
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

	func _scroll_column(parent:Control,id:String)->VBoxContainer:
		var scroll:=ScrollContainer.new()
		scroll.name=id
		scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
		parent.add_child(scroll)
		var column:=VBoxContainer.new()
		column.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		column.add_theme_constant_override("separation",6)
		scroll.add_child(column)
		return column

	func _build_book(column:VBoxContainer)->void:
		_text(column,"食譜本",19)
		var footer:VBoxContainer=column
		column=_scroll_column(column,"CookingCookbookScroll")
		# Keep a full recipe card visible even when the ingredient panel grows.
		(column.get_parent() as ScrollContainer).custom_minimum_size.y=72
		var grid:=GridContainer.new()
		grid.name="CookingRecipes"
		grid.columns=4
		grid.add_theme_constant_override("h_separation",6)
		grid.add_theme_constant_override("v_separation",6)
		column.add_child(grid)
		var group:=ButtonGroup.new()
		for id in World.RECIPES:
			var kind:String=id
			var button:=Button.new()
			button.name="CookingRecipe_"+kind
			button.theme_type_variation="ItemSlot"
			button.toggle_mode=true
			button.button_group=group
			button.focus_mode=Control.FOCUS_ALL
			button.custom_minimum_size=Vector2(84,70)
			button.tooltip_text=dish_name(kind)
			var stack:=VBoxContainer.new()
			stack.mouse_filter=Control.MOUSE_FILTER_IGNORE
			stack.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			stack.alignment=BoxContainer.ALIGNMENT_CENTER
			stack.add_theme_constant_override("separation",0)
			button.add_child(stack)
			var art:=_picture(Items.icon(kind),44)
			art.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
			stack.add_child(art)
			var title:=Label.new()
			title.text=dish_name(kind)
			title.add_theme_font_size_override("font_size",13)
			title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
			title.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
			title.mouse_filter=Control.MOUSE_FILTER_IGNORE
			stack.add_child(title)
			button.pressed.connect(func():select(kind))
			grid.add_child(button)
			recipe_buttons[kind]=button
			refs["recipe_art_"+kind]=art
			refs["recipe_title_"+kind]=title
		var card:=PanelContainer.new()
		card.name="CookingRecipeCard"
		card.add_theme_stylebox_override("panel",Pixel.texture_style("normal",3,8))
		# Keep the chosen output, yield and duration visible while browsing recipes.
		footer.add_child(card)
		var row:=HBoxContainer.new()
		row.add_theme_constant_override("separation",10)
		card.add_child(row)
		var hero:=_picture(null,64)
		hero.name="CookingSelectedIcon"
		row.add_child(hero)
		refs.hero=hero
		var info:=VBoxContainer.new()
		info.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		row.add_child(info)
		refs.hero_name=_text(info,"",20)
		refs.hero_name.name="CookingSelectedName"
		refs.hero_info=_text(info,"",14,MUTED)
		refs.hero_info.name="CookingSelectedInfo"
		# Keep the selected recipe's debit visible beside the submit control.
		# Only the recipe catalogue scrolls; three-ingredient meals must not hide costs.
		_text(footer,"所需食材（背包持有／需要）",14,MUTED)
		var ingredients:=VBoxContainer.new()
		ingredients.name="CookingIngredients"
		ingredients.add_theme_constant_override("separation",4)
		footer.add_child(ingredients)
		refs.ingredients=ingredients
		# Material source (backpack only by default; one adjacent box on explicit choice).
		var picker=SourcePicker.create(app,cell,"stove","queue_cook",true)
		# The confirmed debit must remain visible beside the submit button,
		# even when the cookbook above needs scrolling at 1024x640.
		footer.add_child(picker)
		refs.picker=picker
		picker.state_changed.connect(refresh)
		var enqueue:=_action(footer,"CookingEnqueue","排入石灶",func():
			var kind:String=selected
			submit("queue_cook",kind,"排入"+dish_name(kind),true)
		)
		enqueue.custom_minimum_size.y=42
		refs.enqueue=enqueue

	func _build_station(column:VBoxContainer)->void:
		var header:=HBoxContainer.new()
		column.add_child(header)
		_text(header,"小灶房",19,Color("fff0ce"))
		var capacity_label:=_text(header,"",16,Color("fff0ce"))
		capacity_label.name="CookingCapacity"
		capacity_label.size_flags_horizontal=Control.SIZE_SHRINK_END
		capacity_label.autowrap_mode=TextServer.AUTOWRAP_OFF
		capacity_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
		refs.capacity=capacity_label
		var slots:=HBoxContainer.new()
		slots.name="CookingSlots"
		slots.add_theme_constant_override("separation",4)
		column.add_child(slots)
		var slot_nodes:Array=[]
		for index in CookingLayout.capacity():
			var slot:=PanelContainer.new()
			slot.name="CookingSlot_%d"%index
			slot.custom_minimum_size=Vector2(38,38)
			slot.add_theme_stylebox_override("panel",slot_styles.empty)
			var art:=_picture(null,32)
			slot.add_child(art)
			slots.add_child(slot)
			slot_nodes.append(slot)
		refs.slots=slot_nodes
		refs.legend=_text(column,"",13,Color("e6dfbd"))
		var card:=PanelContainer.new()
		card.name="CookingActive"
		card.add_theme_stylebox_override("panel",Pixel.texture_style("normal",3,8))
		column.add_child(card)
		var row:=HBoxContainer.new()
		row.add_theme_constant_override("separation",10)
		card.add_child(row)
		var pot:=_picture(null,64)
		pot.name="CookingActiveIcon"
		row.add_child(pot)
		refs.active_icon=pot
		var info:=VBoxContainer.new()
		info.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		info.add_theme_constant_override("separation",4)
		row.add_child(info)
		refs.active_title=_text(info,"",18)
		refs.active_title.name="CookingActiveTitle"
		refs.active_owner=_text(info,"",13,MUTED)
		refs.active_owner.name="CookingActiveOwner"
		var gauge:=ProgressBar.new()
		gauge.name="CookingProgress"
		gauge.show_percentage=false
		gauge.min_value=0.0
		gauge.max_value=100.0
		gauge.custom_minimum_size.y=14
		info.add_child(gauge)
		refs.progress=gauge
		refs.remaining=_text(info,"",14)
		refs.remaining.name="CookingRemaining"
		var actions:=HBoxContainer.new()
		actions.name="CookingActiveActions"
		actions.size_flags_vertical=Control.SIZE_SHRINK_CENTER
		row.add_child(actions)
		refs.active_actions=actions
		refs.waiting_title=_text(column,"",14,Color("fff0ce"))
		var waiting_scroll:=ScrollContainer.new()
		waiting_scroll.name="CookingWaitingScroll"
		waiting_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
		waiting_scroll.custom_minimum_size.y=66
		waiting_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
		column.add_child(waiting_scroll)
		var waiting:=GridContainer.new()
		waiting.name="CookingWaiting"
		waiting.columns=5
		waiting.add_theme_constant_override("h_separation",5)
		waiting.add_theme_constant_override("v_separation",5)
		waiting_scroll.add_child(waiting)
		refs.waiting=waiting
		refs.shelf_title=_text(column,"",14,Color("fff0ce"))
		var shelf_scroll:=ScrollContainer.new()
		shelf_scroll.name="CookingShelfScroll"
		shelf_scroll.custom_minimum_size.y=56
		shelf_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
		column.add_child(shelf_scroll)
		var shelf:=HFlowContainer.new()
		shelf.name="CookingShelf"
		shelf.add_theme_constant_override("h_separation",4)
		shelf.add_theme_constant_override("v_separation",4)
		shelf.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		shelf_scroll.add_child(shelf)
		refs.shelf=shelf
		var claim:=_action(column,"CookingClaim","領取最早完成的料理",func():submit("claim_cook","","領取完成料理"))
		claim.custom_minimum_size.y=40
		refs.claim=claim

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

	func select(kind:String)->void:
		if not World.RECIPES.has(kind):return
		selected=kind
		for id in recipe_buttons:(recipe_buttons[id] as Button).set_pressed_no_signal(id==kind)
		ingredient_signature=""
		if refs.has("hero"):refresh()

	## Sends one intent. The caller captured exact IDs when the control was built.
	## `sourced`: take the wire extra from the material source picker's frozen,
	## displayed split (plain recipe ID when backpack only). Never retried.
	func submit(action:String,extra:String,intent:String,sourced:bool=false)->void:
		if not pending.is_empty():
			_status("上一個石灶操作還在等待回應，請稍候。",false)
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
		pending={"action":action,"extra":extra,"intent":intent,"at":Time.get_ticks_msec(),"host":hosting,"sequence":int(session.counter)+1,"sourced":sourced}
		_status(intent+"……等待石灶回應",true)
		_sync_buttons()
		var sequence:int=session.perform(action,cell,extra)
		if pending.is_empty():return # Host answered synchronously through completion.
		if sequence<=0:
			pending={}
			if sourced:picker.release()
			refresh()
			_status("世界正在關閉，這次沒有送出。",false)
			return
		pending.sequence=sequence
		if hosting:
			# Host _action returned before World without a result (paused / not accepting).
			pending={}
			if sourced:picker.release()
			refresh()
			_status("世界暫時不接受操作（可能正在保存或恢復），這次沒有變更。",false)

	func _connected()->bool:
		var peer=app.session.multiplayer.multiplayer_peer
		return peer!=null and peer.get_connection_status()==MultiplayerPeer.CONNECTION_CONNECTED

	func _on_completed(sequence:int,action:String,result:Dictionary)->void:
		if pending.is_empty() or sequence!=int(pending.sequence) or action!=str(pending.action):return
		var message:String=str(result.get("message","石灶已回覆。"))
		var success:bool=bool(result.get("ok",false))
		var sourced:bool=bool(pending.get("sourced",false))
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
		label.add_theme_color_override("font_color",GOOD if success else WARN)

	# ---------------------------------------------------------------- refresh

	func refresh()->void:
		if not refs.has("status"):return
		var s:Dictionary=app.session.snapshot
		var own:String=app.session.own_id
		var person:Dictionary=s.get("players",{}).get(own,{})
		var stove:Dictionary=s.get("objects",{}).get(World.key(cell),{})
		var now:=float(s.get("time",0.0))
		last=model(stove,now)
		_sync_picker()
		_update_book(person.get("inventory",{}))
		_update_station(s,own,now)
		_sync_buttons()

	## Keeps the material source picker on the selected dish; a frozen (pending)
	## picker ignores recipe changes until its submit is acknowledged.
	func _sync_picker()->void:
		var picker=refs.get("picker")
		if picker==null:return
		picker.set_locked("" if last.present else "小石灶不在這裡")
		if str(picker.recipe_id)!=selected and not picker.is_frozen():picker.set_recipe(selected,World.RECIPES[selected])
		else:picker.refresh()

	func _update_book(bag:Dictionary)->void:
		var picker=refs.get("picker")
		var with_box:bool=picker!=null and not str(picker.get_selected_cell()).is_empty()
		for id in recipe_buttons:
			var enough:bool=picker.covers(World.RECIPES[id]) if with_box else _enough(id,bag)
			(refs["recipe_art_"+id] as TextureRect).modulate=Color.WHITE if enough else Color(1,1,1,0.45)
			(refs["recipe_title_"+id] as Label).add_theme_color_override("font_color",Color("fff0ce") if id==selected else (INK if enough else MUTED))
			(recipe_buttons[id] as Button).tooltip_text=dish_name(id)+("" if enough else ("（背包和所選箱子食材不足）" if with_box else "（背包食材不足）"))
		var recipe:Dictionary=World.RECIPES[selected]
		(refs.hero as TextureRect).texture=Items.icon(selected)
		(refs.hero_name as Label).text=dish_name(selected)
		(refs.hero_info as Label).text="每次製作 %d 份 · %d 秒"%[int(recipe.yield),int(recipe.time)]
		var counts:Array=[selected]
		for item in recipe.ingredients:counts.append(int(bag.get(item,0)))
		var signature:=JSON.stringify(counts)
		if signature==ingredient_signature:return
		ingredient_signature=signature
		var list:VBoxContainer=refs.ingredients
		_clear(list)
		for item in recipe.ingredients:
			var need:=int(recipe.ingredients[item])
			var held:=int(bag.get(item,0))
			var row:=HBoxContainer.new()
			row.name="CookingIngredient_"+str(item)
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

	func _enough(kind:String,bag:Dictionary)->bool:
		var recipe:Dictionary=World.RECIPES[kind]
		for item in recipe.ingredients:
			if int(bag.get(item,0))<int(recipe.ingredients[item]):return false
		return true

	func _update_station(s:Dictionary,own:String,now:float)->void:
		var cap:=CookingLayout.capacity()
		var total:int=last.total
		var active:Dictionary=last.active
		var waiting:Array=last.waiting
		var ready:Array=last.ready
		var capacity_label:Label=refs.capacity
		capacity_label.text="%d／%d 格"%[total,cap]
		capacity_label.add_theme_color_override("font_color",Color("ffd59c") if total>=cap else Color("fff0ce"))
		# Slots: ready (oldest first), then the pot, then waiting, then free.
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
				slot.tooltip_text="%s ×%d · %s · 投入：%s"%[dish_name(str(entry.kind)),int(entry.yield),{"active":"爐上","waiting":"等候中","ready":"完成待領"}[entry.state],who(s,own,str(entry.owner))]
			else:
				slot.add_theme_stylebox_override("panel",slot_styles.empty)
				art.texture=null
				slot.tooltip_text="空位"
		(refs.legend as Label).text="完成待領 %d · 爐上 %d · 等候 %d · 空位 %d"%[ready.size(),0 if active.is_empty() else 1,waiting.size(),maxi(0,cap-total)]
		if not last.present:
			(refs.legend as Label).text="這座小石灶已經移除或不在目前區域。"
		# Active pot (in-place updates only).
		var gauge:ProgressBar=refs.progress
		if active.is_empty():
			(refs.active_icon as TextureRect).texture=null
			(refs.active_title as Label).text="爐上空著"
			(refs.active_owner as Label).text="從左側食譜排入料理，就會立刻開始。"
			gauge.value=0
			(refs.remaining as Label).text=""
		else:
			var remaining:=maxf(0.0,float(active.finish)-now)
			var span:=maxf(0.001,float(active.finish)-float(active.started))
			(refs.active_icon as TextureRect).texture=Items.icon(str(active.kind))
			(refs.active_title as Label).text="爐上：%s ×%d"%[dish_name(str(active.kind)),int(active.yield)]
			var owner_text:="投入：%s"%who(s,own,str(active.owner))
			if str(active.owner)!=own:owner_text+=" · 僅投入者可取消"
			(refs.active_owner as Label).text=owner_text
			(refs.active_owner as Label).tooltip_text="投入食材："+ingredient_text(active.ingredients)
			gauge.value=100.0*clampf((now-float(active.started))/span,0.0,1.0)
			var timing:="已完成，等石灶更新後放上料理架" if remaining<=0.0 else "約剩 %d 秒"%ceili(remaining)
			if bool(active.legacy):timing+=" · 原有料理"
			(refs.remaining as Label).text=timing
		(refs.waiting_title as Label).text="等候中（%d）"%waiting.size()
		(refs.shelf_title as Label).text="完成料理架（%d）"%ready.size()
		var claim:Button=refs.claim
		var claimable:bool=not ready.is_empty() or (last.mode=="queue" and not active.is_empty() and float(active.finish)<=now)
		claim.set_meta("allowed",last.present and claimable)
		if not ready.is_empty():
			var oldest:Dictionary=ready[0]
			claim.text="領取最早完成：%s ×%d"%[dish_name(str(oldest.kind)),int(oldest.yield)]
		elif claimable:claim.text="領取剛完成的料理"
		else:claim.text="料理架上還沒有料理"
		var enqueue:Button=refs.enqueue
		var picker=refs.picker
		# Enabled when the displayed split (backpack first, then the chosen box) is
		# complete, even if the backpack alone is short; prepare/lock/no ID disable.
		var source_ok:bool=picker.can_submit()
		enqueue.set_meta("allowed",last.present and total<cap and source_ok)
		if not last.present:enqueue.text="小石灶不在這裡"
		elif total>=cap:enqueue.text="排程已滿 %d／%d，請先領取"%[total,cap]
		elif not picker.plan_ok():enqueue.text="背包和箱子食材不足" if not str(picker.get_selected_cell()).is_empty() else "背包食材不足"
		elif not source_ok:enqueue.text=picker.block_reason()
		else:enqueue.text="排入石灶 · %s%s"%[dish_name(selected)," · 用箱子補足" if picker.uses_box() else ""]
		_rebuild_lists(s,own,now)

	## Rebuilds focusable rows only when the job set, ownership or cancelability changed.
	func _rebuild_lists(s:Dictionary,own:String,now:float)->void:
		var active:Dictionary=last.active
		var parts:Array=[last.mode,own,last.present]
		for entry in [active]+last.waiting+last.ready:
			if (entry as Dictionary).is_empty():continue
			parts.append([entry.id,entry.kind,entry.owner,entry.state,entry.yield,entry.state=="active" and float(entry.finish)>now,who(s,own,str(entry.owner))])
		var signature:=JSON.stringify(parts)
		if signature==queue_signature:return
		queue_signature=signature
		var focus_owner:=get_viewport().gui_get_focus_owner()
		var focus_name:=""
		if is_instance_valid(focus_owner) and str(focus_owner.name).begins_with("CookingCancel_"):focus_name=str(focus_owner.name)
		cancel_buttons.clear()
		_clear(refs.active_actions)
		_clear(refs.waiting)
		_clear(refs.shelf)
		if not active.is_empty() and str(active.owner)==own:
			var target:String=active.id
			var legacy:bool=active.legacy
			var action:="cancel_cook" if legacy else "cancel_queued_cook"
			var cancel:=_action(refs.active_actions,"CookingCancel_"+("legacy" if legacy else target),"取消",func():
				submit(action,target,"取消"+dish_name(str(active.kind))))
			cancel.tooltip_text="取消料理，退回"+ingredient_text(active.ingredients)
			cancel.set_meta("allowed",last.present and float(active.finish)>now and (legacy or not target.is_empty()))
			cancel_buttons.append(cancel)
		var position:=2 if not active.is_empty() else 1
		if (last.waiting as Array).is_empty():
			var empty_waiting:=_text(refs.waiting,"下一道，想煮什麼？",13,Color("e6dfbd"))
			empty_waiting.autowrap_mode=TextServer.AUTOWRAP_OFF
		for entry in last.waiting:
			var record:Dictionary=entry
			var card:=PanelContainer.new()
			card.name="CookingWaitingRow_"+str(record.id)
			card.custom_minimum_size.x=74
			card.add_theme_stylebox_override("panel",Pixel.texture_style("normal",3,3))
			card.tooltip_text="#%d · %s ×%d\n投入：%s\n取消退回：%s"%[position,dish_name(str(record.kind)),int(record.yield),who(s,own,str(record.owner)),ingredient_text(record.ingredients)]
			refs.waiting.add_child(card)
			var stack:=VBoxContainer.new()
			stack.add_theme_constant_override("separation",0)
			card.add_child(stack)
			var picture:=_picture(Items.icon(str(record.kind)),32)
			picture.mouse_filter=Control.MOUSE_FILTER_IGNORE
			stack.add_child(picture)
			var row:=HBoxContainer.new()
			row.add_theme_constant_override("separation",2)
			stack.add_child(row)
			var order:=_text(row,"#%d ×%d"%[position,int(record.yield)],12,MUTED)
			order.autowrap_mode=TextServer.AUTOWRAP_OFF
			order.size_flags_horizontal=Control.SIZE_SHRINK_BEGIN
			order.size_flags_vertical=Control.SIZE_SHRINK_CENTER
			position+=1
			if str(record.owner)==own:
				var target:String=record.id
				var cancel:=_action(row,"CookingCancel_"+target,"×",func():
					submit("cancel_queued_cook",target,"取消"+dish_name(str(record.kind))))
				cancel.custom_minimum_size=Vector2(24,24)
				cancel.theme_type_variation="ItemSlot"
				cancel.tooltip_text="取消%s，退回%s"%[dish_name(str(record.kind)),ingredient_text(record.ingredients)]
				cancel.size_flags_vertical=Control.SIZE_SHRINK_CENTER
				cancel.set_meta("allowed",last.present and not target.is_empty())
				cancel_buttons.append(cancel)
		if (last.ready as Array).is_empty():
			_text(refs.shelf,"香氣快要飄出來了。",13,Color("e6dfbd"))
		var first:=true
		for entry in last.ready:
			var record:Dictionary=entry
			var slot:=PanelContainer.new()
			slot.name="CookingReady_"+(str(record.id) if not str(record.id).is_empty() else "legacy")
			slot.custom_minimum_size=Vector2(48,52)
			slot.add_theme_stylebox_override("panel",slot_styles.active if first else slot_styles.ready)
			slot.tooltip_text="%s%s ×%d · 投入：%s"%["下一份領取 · " if first else "",dish_name(str(record.kind)),int(record.yield),who(s,own,str(record.owner))]
			var next_to_claim:=first
			first=false
			var stack:=VBoxContainer.new()
			stack.add_theme_constant_override("separation",0)
			stack.mouse_filter=Control.MOUSE_FILTER_IGNORE
			slot.add_child(stack)
			var art:=_picture(Items.icon(str(record.kind)),32)
			art.size_flags_horizontal=Control.SIZE_SHRINK_CENTER
			stack.add_child(art)
			var amount:=Label.new()
			amount.text="×%d"%int(record.yield)
			amount.add_theme_font_size_override("font_size",12)
			amount.add_theme_color_override("font_color",Color("fff0ce") if next_to_claim else INK)
			amount.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
			amount.mouse_filter=Control.MOUSE_FILTER_IGNORE
			stack.add_child(amount)
			refs.shelf.add_child(slot)
		if not focus_name.is_empty():
			var again=find_parent_modal().find_child(focus_name,true,false)
			if again is Button and not again.disabled:again.grab_focus.call_deferred()

	func find_parent_modal()->Node:
		return get_parent() if get_parent() else self

	func _sync_buttons()->void:
		var busy:=not pending.is_empty()
		var buttons:Array=[refs.get("enqueue"),refs.get("claim")]
		buttons.append_array(cancel_buttons)
		for button in buttons:
			if button is Button and is_instance_valid(button):
				button.disabled=busy or not bool(button.get_meta("allowed",false))
		if busy and refs.has("enqueue"):(refs.enqueue as Button).text="等待石灶回應……"


## Shared helpers reachable from Controller without preloading this script from itself.
class CookingLayout:
	static func capacity()->int:
		return int(World.COOKING_QUEUE.CAPACITY)

	## Centered, pixel-snapped workbench that fits 1024x640 and 1280x800.
	static func fit(modal:Control,bounds:Vector2)->void:
		modal.size=Vector2(minf(980.0,bounds.x-32.0),minf(620.0,bounds.y-32.0)).floor()
		modal.position=((bounds-modal.size)/2.0).floor()
