extends RefCounted
const World=preload("res://scripts/world.gd")
const Shell=preload("res://scripts/life_ui_shell.gd")
const Art=preload("res://scripts/mine_art.gd")
const Items=preload("res://scripts/inventory_item_art.gd")
const Slot=preload("res://scripts/item_slot.gd")
const Pixel=preload("res://scripts/inventory_pixel_theme.gd")
const ORES:=["stone","copper_ore","gold_ore"]

static func open(app)->void:
	var body:VBoxContainer=app._open_modal("礦車寄運")
	app.modal.set_meta("life_modal_layout","mine_freight")
	app.modal.set_meta("freight_body",body)
	app.modal.theme=Pixel.make(app.hud.theme)
	app.modal.add_theme_stylebox_override("panel",Pixel.frame_style())
	if is_instance_valid(app.modal_feedback):app.modal_feedback.text="裝車前可卸回背包；出發後會保留整批貨物。"
	if is_instance_valid(app.modal_shade):app.modal_shade.color.a=0.24
	refresh(app)
	app._layout_preview.call_deferred()

static func text(app,parent:Node,value:String,size:int=15)->Label:
	var label:Label=app.label(value,size)
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label

static func action(app,parent:Node,id:String,title:String,callback:Callable,enabled:bool=true)->Button:
	var button:Button=app.button(title,callback)
	button.name=id
	button.disabled=not enabled
	button.custom_minimum_size.y=34
	button.add_theme_font_size_override("font_size",14)
	parent.add_child(button)
	return button

static func refresh(app)->void:
	if not is_instance_valid(app.modal) or not app.modal.has_meta("freight_body"):return
	var s:Dictionary=app.session.snapshot
	var freight:Dictionary=s.get("mine_freight",{})
	var job:Dictionary=freight.get("own_job",{})
	var person:Dictionary=s.get("players",{}).get(app.session.own_id,{})
	if person.is_empty():return
	var region:=str(s.get("region_id","home"))
	var at_mine:=region in ["mine_4","mine_5"] and int(s.get("mine_depths",{}).get("unlocked",1))>=5
	var load_near:=at_mine and Vector2(person.x,person.y).distance_to(Vector2(World.MINE_FREIGHT.LOAD_CELL)+Vector2(0.5,0.5))<=3.2
	var claim_near:=region=="home" and Vector2(person.x,person.y).distance_to(Vector2(World.MINE_FREIGHT.CLAIM_CELL)+Vector2(0.5,0.5))<=3.2
	var homes:Array=freight.get("own_home_chests",[])
	var signature:=JSON.stringify([region,load_near,claim_near,person.inventory,job,homes])
	if app.modal.get_meta("freight_fingerprint","")==signature:
		update_transit(app,s,job)
		return
	app.modal.set_meta("freight_fingerprint",signature)
	var body:VBoxContainer=app.modal.get_meta("freight_body")
	var focused:=body.get_viewport().gui_get_focus_owner()
	var focus_name:String=focused.name if is_instance_valid(focused) and body.is_ancestor_of(focused) else ""
	for child in body.get_children():
		body.remove_child(child);child.queue_free()
	var status:=str(job.get("status","empty"))
	if is_instance_valid(app.modal_feedback):
		app.modal_feedback.text={"transit":"貨物運送中，可以關閉介面繼續探索。","held":"整批貨物已保留，請到渡口公告板領回。","delivered":"這張貨單已完成；裝入新礦料可開始下一車。"}.get(status,"裝車前可卸回背包；出發後會保留整批貨物。")
	var editable:=status in ["empty","draft","delivered"]
	app.modal.set_meta("freight_summary",not (at_mine and editable))
	var cargo:Dictionary=job.get("items",{}) if status=="draft" else {}
	var total:=0
	for amount in cargo.values():total+=int(amount)
	var heading:=HBoxContainer.new()
	body.add_child(heading)
	heading.add_child(Shell.picture(Art.freight_icon("loaded" if status in ["transit","held"] or total>0 else "cart"),64))
	var intro:=VBoxContainer.new();intro.size_flags_horizontal=Control.SIZE_EXPAND_FILL;heading.add_child(intro)
	text(app,intro,{"empty":"讓礦料先回家","draft":"裝好這一車，就繼續探索","transit":"礦料正往渡口前進","held":"貨物已保留，等你領回","delivered":"這一批已結清"}.get(status,"礦車寄運"),20)
	text(app,intro,"礦道軌車 → 升降口 → 金瓜石接駁 → 渡口",14)
	if app.has_method("_auto_freight_menu"):
		action(app,heading,"FreightAuto","定期寄運",app._auto_freight_menu)
	var columns:=HBoxContainer.new();columns.add_theme_constant_override("separation",20);body.add_child(columns)
	var left:=VBoxContainer.new();left.custom_minimum_size.x=290;left.size_flags_horizontal=Control.SIZE_EXPAND_FILL;columns.add_child(left)
	var address:=PanelContainer.new();address.custom_minimum_size.x=310;address.size_flags_horizontal=Control.SIZE_EXPAND_FILL;address.add_theme_stylebox_override("panel",Pixel.paper_style());columns.add_child(address)
	var right:=VBoxContainer.new();right.add_theme_constant_override("separation",8);address.add_child(right)
	if at_mine and editable:
		text(app,left,"車廂  %d / %d"%[total,World.MINE_FREIGHT.CAPACITY],18)
		if status=="draft" and total==0:
			action(app,left,"FreightCancel","取消空貨單",func():app.session.perform("freight_cancel",World.MINE_FREIGHT.LOAD_CELL),load_near)
		var row:=HBoxContainer.new();row.add_theme_constant_override("separation",12);left.add_child(row)
		for item in ORES:
			var kind:String=item
			var stack:=VBoxContainer.new();row.add_child(stack)
			var slot=Slot.new();slot.name="Cargo_"+kind;slot.configure(kind,Items.icon(kind),int(cargo.get(kind,0)),World.NAMES[kind]);stack.add_child(slot)
			slot.mouse_filter=Control.MOUSE_FILTER_IGNORE
			var label:=text(app,stack,World.NAMES[kind],13);label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
			label=text(app,stack,"背包 %d"%int(person.inventory.get(kind,0)),13);label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
			var amount:=mini(5,mini(int(person.inventory.get(kind,0)),World.MINE_FREIGHT.CAPACITY-total))
			var controls:=HBoxContainer.new();stack.add_child(controls)
			action(app,controls,"LoadOne_"+kind,"＋1",func():app.session.perform("freight_load",World.MINE_FREIGHT.LOAD_CELL,kind+":1"),load_near and amount>0)
			action(app,controls,"Load_"+kind,"＋%d"%maxi(amount,1),func():app.session.perform("freight_load",World.MINE_FREIGHT.LOAD_CELL,kind+":"+str(amount)),load_near and amount>0)
			var unload:=int(cargo.get(kind,0))
			action(app,stack,"Unload_"+kind,"卸回",func():app.session.perform("freight_unload",World.MINE_FREIGHT.LOAD_CELL,kind+":"+str(unload)),load_near and unload>0)
		var address_heading:=HBoxContainer.new();right.add_child(address_heading)
		address_heading.add_child(Shell.picture(Art.freight_icon("post"),32))
		text(app,address_heading,"寄到我的私人箱",18)
		if homes.is_empty():
			text(app,right,"渡口還沒有你的私人箱。先回家建一個，再來安排寄運；已裝的礦料可以卸回。")
		else:
			var scroll:=ScrollContainer.new();scroll.name="FreightDestinations";scroll.custom_minimum_size.y=minf(132,homes.size()*44);scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;right.add_child(scroll)
			var destinations:=VBoxContainer.new();destinations.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(destinations)
			for home in homes:
				var cell:=str(home.cell)
				var selected:=str(job.get("target",{}).get("cell",""))==cell
				action(app,destinations,"Target_"+cell.replace(",","_"),("✓ " if selected else "")+"私人箱 · "+cell,func():app.session.perform("freight_target",World.MINE_FREIGHT.LOAD_CELL,cell),load_near and status=="draft")
		text(app,right,"約 %d 遊戲秒送達。你可以留在礦場，貨物會送進選定的箱子。"%int(World.MINE_FREIGHT.TRANSIT),14)
		action(app,right,"FreightDispatch","封箱出發  →",func():app.session.perform("freight_dispatch",World.MINE_FREIGHT.LOAD_CELL),load_near and total>0 and not job.get("target",{}).is_empty())
		if not load_near:text(app,left,"靠近礦務站才可裝卸。",14)
	else:
		text(app,left,"這一批的礦料",18)
		var items:Dictionary=job.get("items",{})
		var row:=HBoxContainer.new();row.add_theme_constant_override("separation",12);left.add_child(row)
		for item in ORES:
			var count:=int(items.get(item,0))
			if count==0:continue
			var stack:=VBoxContainer.new();row.add_child(stack)
			var slot=Slot.new();slot.configure(item,Items.icon(item),count,World.NAMES[item]);slot.mouse_filter=Control.MOUSE_FILTER_IGNORE;stack.add_child(slot)
			text(app,stack,World.NAMES[item],13)
		if items.is_empty():text(app,left,"還沒有寄運紀錄。第四層工程完成後，可在第四、五層礦務站裝車。")
		if status=="transit":
			var label:=text(app,right,"",18);label.name="FreightCountdown"
			var bar:=ProgressBar.new();bar.name="FreightProgress";bar.custom_minimum_size.y=18;bar.show_percentage=false;right.add_child(bar)
			text(app,right,"出發後不能再拆箱。送達時會核對收貨箱；箱子無法收貨就整批保留。",14)
		elif status=="held":
			text(app,right,"收貨箱暫時無法收下這一批。貨物沒有遺失，請到渡口公告板領回。")
			action(app,right,"FreightClaim","領回整批礦料",func():app.session.perform("freight_claim",World.MINE_FREIGHT.CLAIM_CELL),claim_near)
		elif status=="delivered":text(app,right,"運送已完成。若剛從公告板領回，物品已在背包；否則請到收貨箱查看。")
		else:text(app,right,"收貨目的地使用你自己的私人箱，其他島民的物品不會被搬動。")
		if not job.get("target",{}).is_empty():text(app,right,"渡口私人箱 · "+str(job.target.cell),14)
	update_transit(app,s,job)
	if not focus_name.is_empty():
		var replacement=body.find_child(focus_name,true,false)
		if replacement is BaseButton and not replacement.disabled:replacement.grab_focus.call_deferred()
	app._layout_preview.call_deferred()

static func update_transit(app,s:Dictionary,job:Dictionary)->void:
	if str(job.get("status",""))!="transit":return
	var remaining:=maxf(0,float(job.get("ready",0))-float(s.get("time",0)))
	var label=app.modal.find_child("FreightCountdown",true,false)
	if label:label.text="還有 %d 遊戲秒"%ceili(remaining)
	var bar=app.modal.find_child("FreightProgress",true,false)
	if bar:bar.value=100.0*(1.0-clampf(remaining/World.MINE_FREIGHT.TRANSIT,0,1))
