extends RefCounted

const World=preload("res://scripts/world.gd")
const Art=preload("res://scripts/inventory_item_art.gd")

static func open(app)->void:
	var content:VBoxContainer=app._open_modal("我的訂單簿")
	app.modal.set_meta("life_modal_layout","order_journal")
	var list:=VBoxContainer.new()
	list.add_theme_constant_override("separation",10)
	content.add_child(list)
	var empty:Label=app.LifeTasks.line(app,content,"手邊沒有訂單。可以到渡口公告板或已開放的地方訂單點接單。",16)
	content.add_child(app.button("返回島民手冊",app._journal))
	app.modal.set_meta("order_journal",{"list":list,"empty":empty,"ids":[],"rows":{}})
	refresh(app)

static func refresh(app)->void:
	if not is_instance_valid(app.modal) or not app.modal.has_meta("order_journal"):return
	var view:Dictionary=app.modal.get_meta("order_journal")
	var snapshot:Dictionary=app.session.snapshot
	var resident:Dictionary=snapshot.get("players",{}).get(app.session.own_id,{})
	var orders:=World.ORDER_CATALOG.journal_rows(resident.get("orders",{}),float(snapshot.get("time",0.0)))
	var ids:=orders.map(func(order):return order.id)
	if ids!=view.ids:
		view.ids=ids
		view.rows.clear()
		for child:Node in view.list.get_children():
			view.list.remove_child(child)
			child.queue_free()
		for order:Dictionary in orders:view.rows[order.id]=make_row(app,view.list,order)
		app._layout_preview.call_deferred()
	view.empty.visible=orders.is_empty()
	var region:String=snapshot.get("region_id","home")
	var bag:Dictionary=resident.get("inventory",{})
	for order:Dictionary in orders:
		var entry:Dictionary=view.rows[order.id]
		var expired:bool=order.status=="expired"
		var ready:=true
		for item:String in order.items:
			var need:int=order.items[item]
			var have:int=bag.get(item,0)
			entry.materials[item].text="%s %d／%d"%[World.NAMES[item],have,need]
			ready=ready and have>=need
		entry.status.text="已過期。材料留在背包，沒有扣鈴幣。" if expired else app.LifeAlmanac.order_status_text(order)+(" · 可交件" if ready else "")
		entry.route.visible=not expired
		if not expired:
			if entry.destination.region!=region:entry.route.text="查看轉乘路線"
			else:entry.route.text="打開交件看板" if near(resident,entry.destination.cell) else "查看交件位置"

static func make_row(app,list:VBoxContainer,order:Dictionary)->Dictionary:
	var channel:String=order.get("channel","village")
	var destination:Dictionary=World.ORDER_BOARDS[channel]
	var paper:VBoxContainer=app.LifeTasks.card(list)
	paper.name="TrackedOrder_"+str(order.id)
	var title:=HBoxContainer.new()
	title.add_theme_constant_override("separation",10)
	paper.add_child(title)
	app.LifeTasks.add_icon(title,Art.icon(order.items.keys()[0]),32)
	app.LifeTasks.line(app,title,order.name,19)
	var details:=HFlowContainer.new()
	details.add_theme_constant_override("h_separation",12)
	paper.add_child(details)
	var materials:={}
	for item:String in order.items:materials[item]=app.LifeTasks.line(app,details,"",15)
	var status:Label=app.LifeTasks.line(app,paper,"",15)
	app.LifeTasks.line(app,paper,"交件地點・"+str(destination.location),15)
	var route:Button=app.button("",route_to.bind(app,channel))
	route.name="OrderRoute"
	route.size_flags_horizontal=Control.SIZE_SHRINK_END
	paper.add_child(route)
	return {"materials":materials,"status":status,"route":route,"destination":destination}

static func near(resident:Dictionary,cell:Vector2i)->bool:
	return not resident.is_empty() and Vector2(resident.x,resident.y).distance_to(Vector2(cell)+Vector2(0.5,0.5))<=3.2

static func route_to(app,channel:String)->void:
	var destination:Dictionary=World.ORDER_BOARDS[channel]
	var snapshot:Dictionary=app.session.snapshot
	if destination.region!=snapshot.get("region_id","home"):
		app.TravelUI.open_toward(app,destination.region)
	elif near(snapshot.get("players",{}).get(app.session.own_id,{}),destination.cell):
		app.LifeAlmanac.orders_menu(app,channel,true)
	else:
		app._map_menu(open.bind(app),"返回訂單簿")
