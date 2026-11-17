extends VBoxContainer
## MaterialSourcePicker — reusable "材料來源" selector + exact debit preview
## (material-source-contract.json, section13/T036). Shared by the bench
## (automation_ui.gd), stove (cooking_queue_ui.gd) and sawmill / charcoal kiln
## (processing_queue_ui.gd).
##
## Display + intent only. It never writes snapshot, World, inventory or save data.
## Allocation uses MaterialSupply.plan (pure); candidates / digest / encode come
## from MaterialSources (res://scripts/material_sources.gd). That helper is loaded
## lazily: while it is absent, only "只用背包" is offered and a box can never be
## submitted, so the original backpack-only behavior keeps working.
##
## Node layout (names are part of the test contract):
##   MaterialSourcePicker (this VBoxContainer)
##     MaterialSourceHeader (HBox): label · MaterialSourceSelect (OptionButton) ·
##                                  MaterialSourceRetry (Button, only after a failed/
##                                  missing box preparation)
##     MaterialSourceScroll (ScrollContainer, local scrolling)
##       MaterialSourceBreakdown (VBox of MaterialSourceRow_<item> labels)
##     MaterialSourceStatus (Label)
##     MaterialSourceRefund (Label, queue stations with a box selected)
##
## Selection rules
## - Every new picker starts at index 0 "只用背包". Nothing is persisted.
## - Options = MaterialSources.candidates(snapshot.objects, own_id, station_cell):
##   cardinal-adjacent shared chests and the player's own private chests. Nothing
##   is ever selected automatically (private or otherwise).
## - Explicitly selecting a box without box_id sends prepare_material_box through
##   Session.perform(p=station cell, extra=box cell). The picker predicts
##   counter+1 BEFORE perform because a host completes synchronously inside it,
##   then waits for Session.action_completed with the exact sequence AND action.
##   After an ok ack it still needs the snapshot to carry the id before a box
##   submit is allowed. Retry only happens through MaterialSourceRetry or
##   re-selecting (both explicit). Notices / snapshots are never acks.
##
## Submit protocol (host controller):
##   if not picker.can_submit(): return
##   var intent := picker.freeze()          # {ok, extra, sourced, summary, ...}
##   session.perform(action, cell, intent.extra)
##   ... on the exact correlated completion: picker.release(result)
## freeze() captures exactly the split currently on screen (its digest was computed
## from that displayed split). While frozen, snapshot refreshes neither change the
## frozen intent nor the displayed split; the select is locked. release() never
## re-sends anything. Backpack-only extra is the plain recipe ID (unchanged wire).
##
## Fixture helper: select_cell("x,y") (or select_cell(Vector2i)) behaves exactly
## like the player picking that row in MaterialSourceSelect; select_backpack()
## picks index 0. option_cells() lists the selectable cells in option order.

signal state_changed

const World=preload("res://scripts/world.gd")
const Supply=preload("res://scripts/material_supply.gd")
const Items=preload("res://scripts/inventory_item_art.gd")
const SOURCES_PATH:="res://scripts/material_sources.gd"
const PREPARE_ACTION:="prepare_material_box"
const BACKPACK_LABEL:="只用背包"
const ACK_TIMEOUT_MS:=10000
const EXTRA_MAX_BYTES:=96
const INK:=Color("3d422d")
const MUTED:=Color("76694c")
const WARN:=Color("9c4b32")
const GOOD:=Color("3e664b")

var app
var station_cell:=Vector2i.ZERO
var station_kind:=""
var action:=""
var refundable:=true
var recipe_id:=""
var recipe:Dictionary={}

var selected_cell:="" ## "" = backpack only; read via get_selected_cell()
var options:Array=[] ## [{cell,type,id,label,stale}] in OptionButton order after index 0
var quote:Dictionary={} ## Last displayed quote (see _compute)
var frozen:Dictionary={} ## Intent captured by freeze(); empty when idle
var prepare:Dictionary={} ## {cell,sequence,host,at,state:pending|acked|failed,message}
var locked_reason:=""
var _seen_id:="" ## box id observed when the current box was selected
var _row_signature:=""
var _option_signature:=""
var _sources=null
var _sources_checked:=false

var select:OptionButton
var retry:Button
var scroll:ScrollContainer
var breakdown:VBoxContainer
var status:Label
var refund:Label

# ------------------------------------------------------------------ factory

## Creates and builds a picker. `kind` is the World station type ("bench",
## "stove", "sawmill", "charcoal_kiln"); `submit_action` is the wire action
## ("craft", "queue_cook", "queue_processing").
static func create(app_ref,cell:Vector2i,kind:String,submit_action:String,can_refund:bool=true)->Node:
	var script:GDScript=load("res://scripts/material_source_ui.gd")
	var picker=script.new()
	picker.app=app_ref
	picker.station_cell=cell
	picker.station_kind=kind
	picker.action=submit_action
	picker.refundable=can_refund
	picker._build()
	return picker

func _build()->void:
	name="MaterialSourcePicker"
	size_flags_horizontal=Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation",3)
	var header:=HBoxContainer.new()
	header.name="MaterialSourceHeader"
	header.add_theme_constant_override("separation",6)
	add_child(header)
	var caption:=_label("材料來源",14,MUTED)
	caption.autowrap_mode=TextServer.AUTOWRAP_OFF
	caption.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	header.add_child(caption)
	select=OptionButton.new()
	select.name="MaterialSourceSelect"
	select.focus_mode=Control.FOCUS_ALL
	select.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	select.clip_text=true
	select.custom_minimum_size=Vector2(150,32)
	select.add_theme_font_size_override("font_size",14)
	select.tooltip_text="預設只用背包。可改選上下左右相鄰、你能使用的一個箱子補足不夠的材料。"
	select.add_item(BACKPACK_LABEL,0)
	select.select(0)
	select.item_selected.connect(_on_item_selected)
	header.add_child(select)
	retry=Button.new()
	retry.name="MaterialSourceRetry"
	retry.text="重新準備"
	retry.focus_mode=Control.FOCUS_ALL
	retry.add_theme_font_size_override("font_size",13)
	retry.custom_minimum_size.y=32
	retry.tooltip_text="再向世界準備一次這個箱子（不會送出製作）。"
	retry.visible=false
	retry.pressed.connect(func():_request_prepare())
	header.add_child(retry)
	scroll=ScrollContainer.new()
	scroll.name="MaterialSourceScroll"
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y=52
	scroll.visible=false
	add_child(scroll)
	breakdown=VBoxContainer.new()
	breakdown.name="MaterialSourceBreakdown"
	breakdown.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	breakdown.add_theme_constant_override("separation",2)
	scroll.add_child(breakdown)
	status=_label("",13,MUTED)
	status.name="MaterialSourceStatus"
	add_child(status)
	refund=_label("",13,MUTED)
	refund.name="MaterialSourceRefund"
	refund.visible=false
	add_child(refund)

func _ready()->void:
	if app and app.session and not app.session.action_completed.is_connected(_on_completed):
		app.session.action_completed.connect(_on_completed)

func _exit_tree()->void:
	if app and app.session and app.session.action_completed.is_connected(_on_completed):
		app.session.action_completed.disconnect(_on_completed)

func _process(_delta:float)->void:
	if str(prepare.get("state",""))=="pending" and not bool(prepare.get("host",false)) and Time.get_ticks_msec()-int(prepare.get("at",0))>ACK_TIMEOUT_MS:
		prepare.state="failed"
		prepare.message="還沒收到準備箱子的回應。請確認連線後按「重新準備」。"
		refresh()

# ------------------------------------------------------------- public API

## Sets the recipe being previewed. `definition` is the full recipe dictionary
## (World.CRAFT / World.RECIPES / World.INDUSTRY.PROCESS entry); it feeds the
## digest. Ignored while frozen (a pending submit never changes its intent).
func set_recipe(id:String,definition:Dictionary)->void:
	if not frozen.is_empty():return
	recipe_id=id
	recipe=definition
	_row_signature=""
	refresh()

## Host-supplied lock (station missing, not the owner, queue full is NOT a lock).
## Locked pickers keep their selection but cannot change it or prepare.
func set_locked(reason:String)->void:
	if reason==locked_reason:return
	locked_reason=reason
	_sync_controls()

func get_selected_cell()->String:
	return selected_cell

func selected_index()->int:
	return select.selected if select else 0

## Cells offered after "只用背包", in OptionButton order (index = position+1).
func option_cells()->PackedStringArray:
	var out:=PackedStringArray()
	for option in options:out.append(str(option.cell))
	return out

func selected_source()->Dictionary:
	for option in options:
		if str(option.cell)==selected_cell:return (option as Dictionary).duplicate()
	return {}

## Same as the player choosing row `index` of MaterialSourceSelect.
func select_index(index:int)->bool:
	if not _can_change() or index<0 or index>options.size():return false
	select.select(index)
	_choose(index)
	return true

func select_backpack()->bool:
	return select_index(0)

## Fixture helper: chooses the option for cell "x,y" (or Vector2i) exactly like an
## explicit player click. Returns false when the cell is not an eligible option.
func select_cell(cell)->bool:
	var target:String=World.key(cell) if cell is Vector2i else str(cell)
	for index in options.size():
		if str(options[index].cell)==target and not bool(options[index].get("stale",false)):
			return select_index(index+1)
	return false

func is_frozen()->bool:
	return not frozen.is_empty()

func is_preparing()->bool:
	return str(prepare.get("state",""))=="pending"

## True when the displayed quote can be submitted now.
func can_submit()->bool:
	return frozen.is_empty() and locked_reason.is_empty() and bool(quote.get("submittable",false))

## Whether the displayed split covers the recipe (ignores prepare/lock state).
## Hosts use it for "材料不足" wording; can_submit() gates the button.
func plan_ok()->bool:
	return bool(quote.get("ok",false))

## Whether backpack + the currently selected box (current snapshot) cover any
## recipe definition. Display hint for recipe tiles only; never a submit gate.
func covers(definition:Dictionary)->bool:
	var need=definition.get("ingredients",{})
	if not need is Dictionary or need.is_empty() or app==null:return false
	var s:Dictionary=app.session.snapshot
	var bag=s.get("players",{}).get(str(app.session.own_id),{}).get("inventory",{})
	var box:={}
	if not selected_cell.is_empty() and not bool(selected_source().get("stale",true)):
		var obj=s.get("objects",{}).get(selected_cell,{})
		if obj is Dictionary and obj.get("items",{}) is Dictionary:box=_subset(obj.items,need)
	return bool(Supply.plan(need,_subset(bag if bag is Dictionary else {},need),box).get("ok",false))

## True when the box (not the backpack) is needed for this recipe.
func uses_box()->bool:
	return not selected_cell.is_empty() and not (quote.get("from_chest",{}) as Dictionary).is_empty()

## Short wording for a host's disabled submit button, "" when submittable.
func block_reason()->String:
	if not frozen.is_empty():return "等待回應……"
	if not locked_reason.is_empty():return locked_reason
	return str(quote.get("reason",""))

## Captures exactly the displayed split + wire extra. Call right before perform.
## Returns {ok:false,reason} when not submittable. Never recomputes from snapshot.
func freeze()->Dictionary:
	if not can_submit():return {"ok":false,"reason":block_reason()}
	frozen={"ok":true,"action":action,"recipe_id":recipe_id,"extra":str(quote.extra),
		"sourced":bool(quote.sourced),"cell":str(quote.cell),"id":str(quote.id),
		"digest":str(quote.get("digest","")),
		"from_backpack":(quote.from_backpack as Dictionary).duplicate(),
		"from_chest":(quote.from_chest as Dictionary).duplicate(),
		"summary":str(quote.get("summary",""))}
	_sync_controls()
	_render()
	return frozen.duplicate(true)

## Ends the frozen intent after the host's correlated completion (or a definite
## non-send). Never re-sends. Returns the readable message for the host status.
func release(result:Dictionary={})->String:
	var was:=frozen
	frozen={}
	var message:=""
	if not result.is_empty() and not bool(result.get("ok",false)) and bool(result.get("requote",false)):
		message="背包或箱子的數量已變動，這次沒有扣除任何材料。請看新的分配後再按一次。"
	elif not result.is_empty() and bool(result.get("ok",false)) and bool(was.get("sourced",false)):
		message="已依確認的分配扣除："+str(was.get("summary",""))
	refresh()
	state_changed.emit()
	return message

## Re-reads Session.snapshot. Safe to call on every snapshot; while frozen only
## availability text changes, never the frozen split.
func refresh()->void:
	if select==null or app==null:return
	var s:Dictionary=app.session.snapshot
	_refresh_options(s)
	if _seen_id.is_empty():_seen_id=str(selected_source().get("id",""))
	elif frozen.is_empty() and not is_preparing() and str(selected_source().get("id",""))!=_seen_id:
		prepare={"cell":selected_cell,"state":"failed","message":"箱子已移走或更換。請重新選擇，或按「重新準備」確認這個箱子。"}
	if frozen.is_empty():quote=_compute(s)
	_render()
	_sync_controls()

# ------------------------------------------------------------ selection

func _on_item_selected(index:int)->void:
	if not _can_change():
		select.select(_index_of(selected_cell))
		return
	_choose(index)

func _choose(index:int)->void:
	var previous:=selected_cell
	selected_cell="" if index<=0 else str(options[index-1].cell)
	prepare={}
	if selected_cell!=previous:
		_row_signature=""
	_seen_id=str(selected_source().get("id",""))
	if not selected_cell.is_empty() and _seen_id.is_empty() and not bool(selected_source().get("stale",false)):
		_request_prepare()
	refresh()
	state_changed.emit()

func _can_change()->bool:
	return frozen.is_empty() and locked_reason.is_empty() and not is_preparing()

func _index_of(cell:String)->int:
	if cell.is_empty():return 0
	for index in options.size():
		if str(options[index].cell)==cell:return index+1
	return 0

## Explicit only: called from a player choice or MaterialSourceRetry.
func _request_prepare()->void:
	if selected_cell.is_empty() or is_preparing() or not frozen.is_empty() or not locked_reason.is_empty():return
	var session=app.session
	var hosting:bool=session.world!=null
	if not hosting and not _connected():
		prepare={"cell":selected_cell,"state":"failed","message":"與世界的連線已中斷，箱子還沒準備好。"}
		refresh()
		return
	var target:=selected_cell
	# Predict first: a host completes synchronously inside perform().
	prepare={"cell":target,"sequence":int(session.counter)+1,"host":hosting,"at":Time.get_ticks_msec(),"state":"pending","message":""}
	_sync_controls()
	var sequence:int=session.perform(PREPARE_ACTION,station_cell,target)
	if str(prepare.get("state",""))!="pending" or str(prepare.get("cell",""))!=target:return
	if sequence<=0:
		prepare={"cell":target,"state":"failed","message":"世界正在關閉，箱子沒有準備。"}
	elif hosting:
		prepare={"cell":target,"state":"failed","message":"世界暫時不接受操作，箱子沒有準備。稍後按「重新準備」。"}
	else:
		prepare.sequence=sequence
	refresh()
	state_changed.emit()

func _on_completed(sequence:int,completed_action:String,result:Dictionary)->void:
	if completed_action!=PREPARE_ACTION or str(prepare.get("state",""))!="pending":return
	if sequence!=int(prepare.get("sequence",-1)):return
	if bool(result.get("ok",false)):
		prepare.state="acked"
		prepare.source_id=str(result.get("source_id",""))
		_seen_id=str(prepare.source_id)
		prepare.message=""
	else:
		prepare.state="failed"
		prepare.message="箱子沒有準備好："+str(result.get("message","世界拒絕了這個箱子。"))
	refresh()
	state_changed.emit()

func _connected()->bool:
	var peer=app.session.multiplayer.multiplayer_peer
	return peer!=null and peer.get_connection_status()==MultiplayerPeer.CONNECTION_CONNECTED

# ------------------------------------------------------------- options

func _sources_script():
	if not _sources_checked:
		_sources_checked=true
		if ResourceLoader.exists(SOURCES_PATH):_sources=load(SOURCES_PATH)
	return _sources

func _refresh_options(s:Dictionary)->void:
	var found:Array=[]
	var helper=_sources_script()
	var objects=s.get("objects",{})
	if helper!=null and objects is Dictionary:
		var raw=helper.candidates(objects,str(app.session.own_id),station_cell)
		if raw is Array:
			for entry in raw:
				if entry is Dictionary and not str(entry.get("cell","")).is_empty():
					var cell:=str(entry.cell)
					found.append({"cell":cell,"type":str(entry.get("type","")),"id":str(entry.get("id","")),
						"label":_option_label(cell,str(entry.get("type",""))),"stale":false})
	var keep_stale:=not selected_cell.is_empty()
	for entry in found:
		if str(entry.cell)==selected_cell:keep_stale=false
	if keep_stale:
		var previous:=selected_source()
		found.append({"cell":selected_cell,"type":str(previous.get("type","chest")),"id":"",
			"label":_option_label(selected_cell,str(previous.get("type","chest")))+"（已不可用）","stale":true})
	options=found
	var signature:=JSON.stringify(options.map(func(o):return [o.cell,o.label]))
	if signature!=_option_signature:
		_option_signature=signature
		select.clear()
		select.add_item(BACKPACK_LABEL,0)
		for index in options.size():
			select.add_item(str(options[index].label),index+1)
			if bool(options[index].stale):select.set_item_disabled(index+1,true)
	select.select(_index_of(selected_cell))

func _option_label(cell:String,type:String)->String:
	var at:=World.cell(cell)-station_cell
	var sides:={Vector2i(0,-1):"北側",Vector2i(0,1):"南側",Vector2i(-1,0):"西側",Vector2i(1,0):"東側"}
	var side:String=str(sides.get(at,"旁邊"))
	var objects:Dictionary=app.session.snapshot.get("objects",{})
	if World.INDUSTRY.square_part(objects.get(World.key(station_cell),{}))==0:
		var width:=1 if World.INDUSTRY.is_vertical(objects[World.key(station_cell)]) else 2
		if at.x<0:side="西側"
		elif at.x>=width:side="東側"
		elif at.y<0:side="北側"
		else:side="南側"
		side+=" %s"%cell
	return ("我的私人箱" if type=="private_chest" else "共用箱")+" · "+side

# --------------------------------------------------------------- quote

## Builds the displayed quote:
## {ok, submittable, reason, sourced, cell, id, held, box, need, from_backpack,
##  from_chest, missing, digest, extra, summary}
func _compute(s:Dictionary)->Dictionary:
	var need:Dictionary=recipe.get("ingredients",{}) if recipe.get("ingredients",{}) is Dictionary else {}
	var bag_raw=s.get("players",{}).get(str(app.session.own_id),{}).get("inventory",{})
	var bag:Dictionary=bag_raw if bag_raw is Dictionary else {}
	var out:={"ok":false,"submittable":false,"reason":"","sourced":false,"cell":selected_cell,"id":"",
		"held":_subset(bag,need),"box":{},"need":need.duplicate(),"from_backpack":{},"from_chest":{},
		"missing":{},"digest":"","extra":"","summary":""}
	if recipe_id.is_empty() or need.is_empty():
		out.reason="沒有可製作的配方"
		return out
	var source:={}
	if not selected_cell.is_empty():
		source=selected_source()
		var box=s.get("objects",{}).get(selected_cell,{})
		if box is Dictionary and box.get("items",{}) is Dictionary:out.box=_subset(box.get("items",{}),need)
		out.id=str(source.get("id",""))
		if bool(source.get("stale",false)) or source.is_empty():
			out.reason="所選箱子已不在旁邊"
			return out
		if not _seen_id.is_empty() and str(out.id)!=_seen_id:
			out.reason="箱子已更換，請重新準備"
			return out
		if is_preparing():
			out.reason="正在準備箱子……"
			return out
		if str(out.id).is_empty():
			out.reason="箱子尚未準備"
			return out
	var plan:=Supply.plan(need,out.held,out.box)
	out.from_backpack=(plan.get("from_backpack",{}) as Dictionary).duplicate()
	out.from_chest=(plan.get("from_chest",{}) as Dictionary).duplicate()
	out.missing=(plan.get("missing",{}) as Dictionary).duplicate()
	out.ok=bool(plan.get("ok",false))
	if not out.ok:
		out.reason="背包和箱子材料不足" if not selected_cell.is_empty() else "背包材料不足"
		if not plan.has("missing"):out.reason=str(plan.get("message","材料資料無效"))
		return out
	if selected_cell.is_empty() or (out.from_chest as Dictionary).is_empty():
		# Backpack covers it: the original plain recipe ID (no box involved).
		out.extra=recipe_id
		out.summary=_split_text(out.from_backpack,{})
		out.submittable=true
		return out
	# A box share is needed: every gate below must pass before a sourced submit.
	if bool(source.get("stale",false)) or source.is_empty():
		out.reason="所選箱子已不在旁邊"
		return out
	if is_preparing():
		out.reason="正在準備箱子……"
		return out
	if str(out.id).is_empty():
		out.reason="箱子尚未準備"
		return out
	var helper=_sources_script()
	if helper==null:
		out.reason="材料箱功能尚未啟用"
		return out
	out.sourced=true
	out.digest=str(helper.digest(action,station_kind,World.key(station_cell),recipe_id,recipe,selected_cell,str(out.id),plan))
	out.extra=str(helper.encode(recipe_id,selected_cell,str(out.id),out.digest))
	if out.digest.is_empty() or out.extra.is_empty() or out.extra.to_utf8_buffer().size()>EXTRA_MAX_BYTES:
		out.sourced=false
		out.reason="無法建立這次的分配"
		return out
	out.summary=_split_text(out.from_backpack,out.from_chest)
	out.submittable=true
	return out

static func _subset(stock:Dictionary,need:Dictionary)->Dictionary:
	var out:={}
	for item in need:
		var value=stock.get(item,0)
		out[item]=maxi(0,int(value)) if (value is int or value is float) else 0
	return out

static func _split_text(from_backpack:Dictionary,from_chest:Dictionary)->String:
	var parts:=PackedStringArray()
	if not from_backpack.is_empty():parts.append("背包 "+_items_text(from_backpack))
	if not from_chest.is_empty():parts.append("箱子 "+_items_text(from_chest))
	return "；".join(parts)

static func _items_text(items:Dictionary)->String:
	var keys:=items.keys()
	keys.sort()
	var parts:=PackedStringArray()
	for item in keys:parts.append("%s %d"%[World.NAMES.get(item,item),int(items[item])])
	return "、".join(parts)

# -------------------------------------------------------------- display

func _render()->void:
	var shown:Dictionary=quote
	var box_mode:=not selected_cell.is_empty()
	scroll.visible=box_mode
	refund.visible=box_mode and refundable
	refund.text="取消時，全部材料退回背包（含箱子取用）。"
	if box_mode:_render_rows(shown)
	var message:=""
	var color:=MUTED
	var prep_state:=str(prepare.get("state",""))
	if not frozen.is_empty():
		message="已送出的分配："+str(frozen.get("summary","")) if bool(frozen.get("sourced",false)) else "已送出，只從背包扣除。"
	elif not locked_reason.is_empty() and box_mode:
		message=locked_reason
		color=WARN
	elif not box_mode:
		message="只從背包扣除。"+("取消時退回背包。" if refundable else "")
	elif bool(selected_source().get("stale",false)):
		message="所選箱子已移走或不能再使用。請改選其他來源。"
		color=WARN
	elif prep_state=="pending":
		message="正在準備這個箱子……完成前不能送出。"
	elif prep_state=="failed":
		message=str(prepare.get("message","箱子沒有準備好。"))
		color=WARN
	elif str(shown.get("id","")).is_empty():
		message="這個箱子還沒準備好。按「重新準備」後再送出。" if prep_state!="acked" else "箱子已準備，等待世界同步……"
		color=WARN if prep_state!="acked" else MUTED
	elif not _seen_id.is_empty() and str(shown.get("id",""))!=_seen_id:
		message="這個位置換了另一個箱子，請重新準備後確認材料分配。"
		color=WARN
	elif not bool(shown.get("ok",false)):
		message="背包加上這個箱子仍然不夠：缺 "+_items_text(shown.get("missing",{}))
		color=WARN
	elif (shown.get("from_chest",{}) as Dictionary).is_empty():
		message="背包已足夠，這次不會動用箱子。"
		color=GOOD
	else:
		message="確認後依上方分配，從背包與箱子扣料。"
		color=GOOD
	status.text=message
	# The bench's backpack-only selector already says this; queues retain refunds.
	status.visible=box_mode or refundable or not frozen.is_empty()
	status.tooltip_text=message
	status.add_theme_color_override("font_color",color)
	var identity_changed:=not _seen_id.is_empty() and str(selected_source().get("id",""))!=_seen_id
	var show_retry:=box_mode and frozen.is_empty() and prep_state!="pending" and not bool(selected_source().get("stale",false)) and (str(selected_source().get("id","")).is_empty() or identity_changed) and prep_state!="acked"
	retry.visible=show_retry

func _render_rows(shown:Dictionary)->void:
	var need:Dictionary=shown.get("need",{})
	var held:Dictionary=shown.get("held",{})
	var box:Dictionary=shown.get("box",{})
	var fb:Dictionary=shown.get("from_backpack",{}) if frozen.is_empty() else frozen.get("from_backpack",{})
	var fc:Dictionary=shown.get("from_chest",{}) if frozen.is_empty() else frozen.get("from_chest",{})
	var missing:Dictionary=shown.get("missing",{})
	var signature:=JSON.stringify([need,held,box,fb,fc,missing])
	if signature==_row_signature:return
	_row_signature=signature
	for child in breakdown.get_children():
		breakdown.remove_child(child)
		child.queue_free()
	var keys:=need.keys()
	keys.sort()
	# Local scrolling: at most three rows tall so the station stays inside 1024x640.
	scroll.custom_minimum_size.y=clampi(keys.size(),1,3)*34
	for item in keys:
		var row:=HBoxContainer.new()
		row.name="MaterialSourceRow_"+str(item)
		row.add_theme_constant_override("separation",6)
		breakdown.add_child(row)
		var icon:=TextureRect.new()
		icon.texture=Items.icon(str(item))
		icon.custom_minimum_size=Vector2(32,32)
		icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
		icon.mouse_filter=Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)
		var short:=int(missing.get(item,0))
		# Held backpack and box stock are separate numbers; never a combined "背包" total.
		var text:="%s 需%d｜背包扣%d（持有%d）｜箱扣%d（箱內%d）"%[World.NAMES.get(item,item),int(need[item]),
			int(fb.get(item,0)),int(held.get(item,0)),int(fc.get(item,0)),int(box.get(item,0))]
		if short>0:text+="｜缺%d"%short
		var label:=_label(text,13,WARN if short>0 else INK)
		label.autowrap_mode=TextServer.AUTOWRAP_OFF
		label.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS
		label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		label.size_flags_vertical=Control.SIZE_SHRINK_CENTER
		label.tooltip_text=text
		row.add_child(label)

func _sync_controls()->void:
	if select==null:return
	select.disabled=not _can_change()
	retry.disabled=not frozen.is_empty() or not locked_reason.is_empty() or is_preparing()

func _label(value:String,size:int,color:Color)->Label:
	var label:=Label.new()
	label.text=value
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size",size)
	label.add_theme_color_override("font_color",color)
	return label
