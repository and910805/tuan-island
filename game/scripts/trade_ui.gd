extends RefCounted

const World = preload("res://scripts/world.gd")
const Tasks = preload("res://scripts/life_ui_tasks.gd")
const ItemArt = preload("res://scripts/inventory_item_art.gd")

static func refresh(app, snapshot: Dictionary) -> void:
	if is_instance_valid(app.modal) and app.modal.has_meta("trade_view"):
		if app.modal.get_meta("trade_view") != snapshot.get("own_trade", {}):
			open(app)

static func send(app, action: String, extra: String) -> void:
	app.session.perform(action, Vector2i.ZERO, extra)

static func open(app) -> void:
	var snapshot: Dictionary = app.session.snapshot
	var offer: Dictionary = snapshot.get("own_trade", {})
	var players: Dictionary = snapshot.get("players", {})
	var own: Dictionary = players.get(app.session.own_id, {})
	var body: VBoxContainer = app._open_modal("島民交換")
	app.modal.set_meta("trade_view", offer.duplicate(true))
	app.modal.set_meta("life_modal_layout", "trade_review")
	if offer.is_empty():
		Tasks.line(app,body,"靠近同區域的島民後，就可以邀請交換。",16)
		if own.is_empty():return
		for id: String in players:
			if id == app.session.own_id:continue
			var person: Dictionary = players[id]
			if str(person.get("region","home")) != str(own.get("region","home")):continue
			if Vector2(own.x,own.y).distance_to(Vector2(person.x,person.y))>3.2:continue
			var invite:Button=app.button("邀請 %s 交換"%person.name,send.bind(app,"trade_open",id))
			invite.name="TradeInvite_"+id
			body.add_child(invite)
		return
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation",12)
	body.add_child(columns)
	var mine := Tasks.card(columns)
	mine.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var theirs := Tasks.card(columns)
	theirs.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	describe(app,mine,"我的交換物",offer.mine,offer.i_confirmed)
	var partner: Dictionary = players.get(offer.partner,{})
	describe(app,theirs,str(partner.get("name","對方")),offer.theirs,offer.they_confirmed)
	var actions := HBoxContainer.new()
	body.add_child(actions)
	actions.add_child(app.button("修改交換內容",edit.bind(app,offer,own)))
	var payload := JSON.stringify({"offer":offer.id,"revision":offer.revision})
	var confirm: Button = app.button("確認這版內容",send.bind(app,"trade_confirm",payload))
	confirm.name="TradeConfirm"
	confirm.disabled = offer.i_confirmed or (offer.mine.items.is_empty() and offer.theirs.items.is_empty() and int(offer.mine.coins)==0 and int(offer.theirs.coins)==0)
	actions.add_child(confirm)
	actions.add_child(app.button("取消交易",send.bind(app,"trade_cancel",str(offer.id))))
	Tasks.line(app,body,"雙方確認後才會交換。內容變更時，兩邊都要重新確認。",15)

static func describe(app, card: VBoxContainer, title: String, side: Dictionary, confirmed: bool) -> void:
	Tasks.line(app,card,title,20)
	Tasks.line(app,card,"✓ 已確認" if confirmed else "等待確認",15)
	for item: String in side.items:
		var row := HBoxContainer.new()
		card.add_child(row)
		Tasks.add_icon(row,ItemArt.icon(item),32)
		Tasks.line(app,row,"%s ×%d"%[World.NAMES[item],side.items[item]],16)
	Tasks.line(app,card,"%d 鈴幣"%side.coins,16)

static func edit(app, offer: Dictionary, own: Dictionary) -> void:
	var body: VBoxContainer = app._open_modal("編輯我的交換物")
	# An incoming edit invalidates the displayed revision and returns to review.
	app.modal.set_meta("trade_view",offer.duplicate(true))
	app.modal.set_meta("life_modal_layout","trade_editor")
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation",10)
	body.add_child(actions)
	actions.add_child(app.button("返回交換",open.bind(app)))
	var coins := SpinBox.new()
	coins.max_value = mini(int(own.coins),World.TRADE.MAX_COINS)
	coins.value = int(offer.mine.coins)
	coins.suffix = "鈴幣"
	coins.get_line_edit().set_meta("trade_quantity",true)
	coins.custom_minimum_size.x = 140
	actions.add_child(coins)
	var amounts := {}
	var apply: Button = app.button("送出交換內容",func():
		var lines := []
		for item in amounts:
			var count := int(amounts[item].value)
			if count>0:lines.append([item,count])
		if lines.size()>World.TRADE.MAX_LINES:return
		send(app,"trade_edit",JSON.stringify({"offer":offer.id,"items":lines,"coins":int(coins.value)}))
		open(app)
	)
	apply.name="TradeSubmit"
	actions.add_child(apply)
	var summary: Label = app.label("最多可放 %d 種物品 · 手把 ←／→ 調整數量"%World.TRADE.MAX_LINES,15)
	body.add_child(summary)
	var inventory: Dictionary = own.inventory
	var tradable := World.trade_items()
	var pad_fields: Array[Control] = [coins.get_line_edit()]
	for item: String in inventory:
		if not tradable.has(item) or int(inventory[item])<=0:continue
		var row := HBoxContainer.new()
		body.add_child(row)
		Tasks.add_icon(row,ItemArt.icon(item),32)
		var caption: Label = app.label("%s（持有 %d）"%[World.NAMES[item],inventory[item]],16)
		caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(caption)
		var count := SpinBox.new()
		count.max_value = mini(int(inventory[item]),World.TRADE.MAX_QUANTITY)
		count.value = int(offer.mine.items.get(item,0))
		count.get_line_edit().set_meta("trade_quantity",true)
		amounts[item] = count
		row.add_child(count)
		pad_fields.append(count.get_line_edit())
		count.value_changed.connect(func(_value: float):
			var used := amounts.values().filter(func(field: SpinBox):return field.value>0).size()
			apply.disabled = used>World.TRADE.MAX_LINES
			summary.text = "%d／%d 種物品"%[used,World.TRADE.MAX_LINES]
		)
	app.modal.set_meta("trade_pad_fields",pad_fields)
	if app.controller_navigation:coins.get_line_edit().grab_focus()

static func navigate_editor(app, index: int) -> bool:
	if not is_instance_valid(app.modal) or not app.modal.has_meta("trade_pad_fields"):return false
	if index not in [JOY_BUTTON_DPAD_UP,JOY_BUTTON_DPAD_DOWN,JOY_BUTTON_Y]:return false
	var fields: Array = app.modal.get_meta("trade_pad_fields")
	var submit := app.modal.find_child("TradeSubmit",true,false) as Button
	var focus: Control = app.get_viewport().gui_get_focus_owner()
	var current := fields.find(focus)
	var next: Control
	if index==JOY_BUTTON_Y:
		if submit.disabled:return true
		next=submit
	elif current<0:
		next=fields.back() if index==JOY_BUTTON_DPAD_UP else fields.front()
	else:
		var offset := -1 if index==JOY_BUTTON_DPAD_UP else 1
		next=fields[posmod(current+offset,fields.size())]
	next.grab_focus()
	var scroll := app.modal.find_child("ModalScroll",true,false) as ScrollContainer
	if scroll!=null:scroll.ensure_control_visible(next)
	return true
