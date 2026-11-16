extends RefCounted
## T071 「市集攤位」 client panel (plan ch.20 市集營業). One shared prop on the
## 風鈴渡口 plaza; every player manages a personal stall through it. The panel is
## a view of snapshot.own_market only: every change goes through
## Session.perform(market_stock / market_take / market_open / market_collect) at
## the stall cell, and the panel re-renders from the next snapshot without closing.
## Server replies reach app.modal_feedback through app._notice (same as the other
## life panels). Rules live in market_stall.gd; nothing here decides prices or sales.
const World=preload("res://scripts/world.gd")
const Market=preload("res://scripts/market_stall.gd")
const Display=preload("res://scripts/market_display.gd")
const Items=preload("res://scripts/inventory_item_art.gd")
const Shell=preload("res://scripts/life_ui_shell.gd")
const Pixel=preload("res://scripts/inventory_pixel_theme.gd")
const TITLE:="市集攤位"
const RULE:="每個世界日營業一輪，午夜結算；沒賣完的留在攤上，可以拿回。"
const INK:=Color("3d422d")
const MUTED:=Color("7a6f58")
const WARN:=Color("9c4b32")
const THEME_TAG:=Color("b0622f")
const ROW_HEIGHT:=40

static func open(app)->void:
	var body:VBoxContainer=app._open_modal(TITLE)
	app.modal.name="MarketStallPanel"
	app.modal.set_meta("life_modal_layout","market_stall")
	app.modal.set_meta("market_body",body)
	app.modal.theme=Pixel.make(app.hud.theme)
	app.modal.add_theme_stylebox_override("panel",Pixel.frame_style())
	if is_instance_valid(app.modal_shade):app.modal_shade.color.a=0.26
	if is_instance_valid(app.modal_feedback):app.modal_feedback.text="Esc 回到島上 · 上架、拿回與領取都會立即保存"
	body.add_theme_constant_override("separation",8)
	refresh(app)
	app._layout_preview.call_deferred()
	focus_first.call_deferred(app)

## main._layout_preview: wide general window, capped like the other life panels.
## The panel is as tall as its content (never taller than 620 or the viewport); spare
## height goes to the 可上架 list so tall windows show more rows before it scrolls.
static func layout(app,bounds:Vector2)->void:
	var cap:=Vector2(minf(1000,bounds.x-24),minf(620,bounds.y-20))
	var modal:Control=app.modal
	modal.size.x=cap.x
	var outer:=modal.find_child("ModalScroll",true,false) as Control
	var content:=modal.find_child("ModalContent",true,false) as Control
	var list_scroll:=modal.find_child("MarketStockScroll",true,false) as Control
	var list:=modal.find_child("MarketStockList",true,false) as Control
	var height:=cap.y
	if outer!=null and content!=null:
		var chrome:float=modal.get_combined_minimum_size().y-outer.get_combined_minimum_size().y
		var base:float=ROW_HEIGHT*4+12
		if list_scroll!=null:
			var others:float=content.get_combined_minimum_size().y-list_scroll.custom_minimum_size.y
			var wanted:float=list.get_combined_minimum_size().y+4 if list!=null else base
			list_scroll.custom_minimum_size.y=clampf(wanted,base,maxf(base,cap.y-chrome-others-2))
		height=minf(cap.y,chrome+content.get_combined_minimum_size().y+2)
	modal.size=Vector2(cap.x,height)
	modal.position=((bounds-modal.size)/2).floor()

static func is_open(app)->bool:
	return is_instance_valid(app.modal) and app.modal.has_meta("market_body")

static func market(app)->Dictionary:
	var found:Variant=app.session.snapshot.get("own_market",{})
	return found if found is Dictionary else {}

static func cell(app)->Vector2i:
	return Market.active_cell(app.session.snapshot)

static func send(app,action:String,extra:String="")->void:
	var at:=cell(app)
	if at==Market.NO_CELL:
		app._notice("市集攤位目前不在渡口廣場上。",false)
		return
	app.session.perform(action,at,extra)

static func focus_first(app)->void:
	if not is_open(app):return
	var body:Control=app.modal.get_meta("market_body")
	for node in body.find_children("*","BaseButton",true,false):
		var b:=node as BaseButton
		if b.is_visible_in_tree() and not b.disabled and b.focus_mode!=Control.FOCUS_NONE:
			b.grab_focus()
			return
	var close:=first_button(app.modal)
	if close!=null:close.grab_focus()

static func first_button(scope:Node)->BaseButton:
	for node in scope.find_children("*","BaseButton",true,false):
		var b:=node as BaseButton
		if b.is_visible_in_tree() and not b.disabled:return b
	return null

# ------------------------------------------------------------------ widgets --

static func text(app,parent:Node,value:String,size:int=15,color:Color=INK)->Label:
	var l:Label=Shell.text(app,value,size)
	l.size_flags_horizontal=Control.SIZE_FILL
	l.add_theme_color_override("font_color",color)
	l.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	parent.add_child(l)
	return l

static func wrapped(app,parent:Node,value:String,size:int=14,color:Color=INK)->Label:
	var l:Label=app.label(value,size)
	l.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color",color)
	parent.add_child(l)
	return l

static func action(app,parent:Node,id:String,title:String,callback:Callable,enabled:bool,reason:String="")->Button:
	var b:Button=app.button(title,callback)
	b.name=id
	b.disabled=not enabled
	b.custom_minimum_size=Vector2(0,34)
	b.add_theme_font_size_override("font_size",14)
	b.focus_mode=Control.FOCUS_ALL
	if not enabled and not reason.is_empty():b.tooltip_text=reason
	parent.add_child(b)
	return b

static func paper(parent:Node,id:String)->VBoxContainer:
	var card:=PanelContainer.new()
	card.name=id
	card.add_theme_stylebox_override("panel",Pixel.paper_style())
	card.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	card.size_flags_vertical=Control.SIZE_EXPAND_FILL
	parent.add_child(card)
	var inner:=VBoxContainer.new()
	inner.add_theme_constant_override("separation",4)
	card.add_child(inner)
	return inner

static func category_name(category:String)->String:
	return str(Market.CATEGORY_NAMES.get(category,category)) if not category.is_empty() else "—"

static func item_name(item:String)->String:
	return str(World.NAMES.get(item,item))

static func theme_tag(app,parent:Node,themed:bool)->void:
	var tag:=text(app,parent,"主題" if themed else "",13,THEME_TAG)
	tag.custom_minimum_size.x=30
	tag.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER

# ------------------------------------------------------------------ refresh --

static func refresh(app)->void:
	if not is_open(app):return
	var s:Dictionary=app.session.snapshot
	var person:Dictionary=s.get("players",{}).get(app.session.own_id,{})
	if person.is_empty():return
	var own:=market(app)
	var bag:Dictionary=person.get("inventory",{})
	var signature:=JSON.stringify([own,bag,Market.active_cell(s)])
	if str(app.modal.get_meta("market_signature",""))==signature:return
	app.modal.set_meta("market_signature",signature)
	var body:VBoxContainer=app.modal.get_meta("market_body")
	var focused:Control=body.get_viewport().gui_get_focus_owner() if body.is_inside_tree() else null
	var focus_name:String=str(focused.name) if is_instance_valid(focused) and body.is_ancestor_of(focused) else ""
	for child in body.get_children():body.remove_child(child);child.queue_free()
	if not bool(own.get("unlocked",false)) or Market.active_cell(s)==Market.NO_CELL:
		wrapped(app,body,Market.LOCKED if not Market.unlocked(s) else Market.NO_STALL,17).name="MarketLocked"
		return
	build(app,body,own,bag)
	if not focus_name.is_empty():
		var next:=body.find_child(focus_name,true,false) as BaseButton
		if next!=null and not next.disabled:next.grab_focus.call_deferred()
		else:focus_first.call_deferred(app)
	app._layout_preview.call_deferred()

static func build(app,body:VBoxContainer,own:Dictionary,bag:Dictionary)->void:
	var stock:Dictionary=own.get("stock",{})
	var prices:Dictionary=own.get("prices",{})
	var stock_count:=int(own.get("stock_count",0))
	var is_open_today:=bool(own.get("open",false))
	# 1. Header: theme today/tomorrow, stalls and visitors, the rule sentence.
	var header:=HBoxContainer.new();header.add_theme_constant_override("separation",18);body.add_child(header)
	header.add_child(Shell.picture(Items.icon("coins"),32))
	var theme_label:=text(app,header,"今日主題：%s（主題商品＋30%%）"%category_name(str(own.get("theme",""))),17)
	theme_label.name="MarketTheme"
	text(app,header,"明日主題：%s"%category_name(str(own.get("next_theme",""))),15,MUTED).name="MarketNextTheme"
	var spacer:=Control.new();spacer.size_flags_horizontal=Control.SIZE_EXPAND_FILL;header.add_child(spacer)
	text(app,header,"今日已開張 %d 攤 · 預估來客 %d 位"%[int(own.get("stalls_today",0)),int(own.get("visitors_estimate",0))],15).name="MarketVisitors"
	text(app,body,RULE,14,MUTED).name="MarketRule"
	# 2 + 3. Stall shelf (left) and what can be stocked (right).
	var columns:=HBoxContainer.new();columns.add_theme_constant_override("separation",12)
	columns.size_flags_vertical=Control.SIZE_EXPAND_FILL;body.add_child(columns)
	shelf(app,paper(columns,"MarketShelfCard"),stock,prices,stock_count,is_open_today)
	stockable(app,paper(columns,"MarketStockCard"),stock,prices,stock_count,bag,is_open_today)
	guest_remark(app,body,own)
	# 4. Footer: open, till, last report.
	footer(app,body,own,stock_count,is_open_today)

static func shelf(app,box:VBoxContainer,stock:Dictionary,prices:Dictionary,stock_count:int,is_open_today:bool)->void:
	var heading:=HBoxContainer.new();box.add_child(heading)
	var title:=text(app,heading,"攤上商品",18);title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	text(app,heading,"%d／%d 件 · %d／%d 種"%[stock_count,Market.MAX_STOCK,stock.size(),Market.MAX_KINDS],15).name="MarketShelfCount"
	var rows:=VBoxContainer.new();rows.name="MarketShelf";rows.add_theme_constant_override("separation",4);box.add_child(rows)
	var items:Array=stock.keys()
	items.sort()
	var take_reason:=""
	for index in range(Market.MAX_KINDS):
		var row:=HBoxContainer.new();row.add_theme_constant_override("separation",6)
		row.custom_minimum_size.y=ROW_HEIGHT;rows.add_child(row)
		if index>=items.size():
			row.name="MarketShelfEmpty_%d"%index
			var slot:=Shell.picture(null,32);row.add_child(slot)
			text(app,row,"空位",14,MUTED)
			continue
		var item:String=str(items[index])
		var count:=int(stock[item])
		var info:Dictionary=prices.get(item,{})
		row.name="MarketShelfRow_"+item
		row.add_child(Shell.picture(Items.icon(item),32))
		var name_label:=text(app,row,item_name(item),15);name_label.custom_minimum_size.x=96
		var detail:=text(app,row,"×%d · 每份 %d"%[count,int(info.get("price",0))],14)
		detail.name="MarketShelfDetail_"+item;detail.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		theme_tag(app,row,bool(info.get("themed",false)))
		var one:="%s:1"%item
		var all:="%s:%d"%[item,count]
		action(app,row,"MarketTake_%s_1"%item,"拿回 1",func():send(app,"market_take",one),take_reason.is_empty(),take_reason)
		action(app,row,"MarketTake_%s_all"%item,"全部拿回",func():send(app,"market_take",all),take_reason.is_empty(),take_reason)
	var note:=text(app,box,"營業中：午夜結算前仍可補貨或拿回。" if is_open_today else "主題商品先賣；售價＝出貨價×1.1，主題×1.3。",13,MUTED)
	note.name="MarketShelfNote"

## T071 攤位布置：今天廣場有客人時，依攤上擺了什麼顯示一句客人的話（純呈現）。
static func guest_remark(app,body:VBoxContainer,own:Dictionary)->void:
	var said:=Display.remark_line(own,World.NAMES)
	if said.is_empty():return
	var row:=HBoxContainer.new();row.name="MarketGuestRemarkRow";row.add_theme_constant_override("separation",6);body.add_child(row)
	var label:=wrapped(app,row,said,14,INK)
	label.name="MarketGuestRemark"
	label.size_flags_horizontal=Control.SIZE_EXPAND_FILL

static func stockable(app,box:VBoxContainer,stock:Dictionary,prices:Dictionary,stock_count:int,bag:Dictionary,is_open_today:bool)->void:
	var heading:=HBoxContainer.new();box.add_child(heading)
	var title:=text(app,heading,"可上架",18);title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	var room:=maxi(0,Market.MAX_STOCK-stock_count)
	var reason:=""
	if room<=0:reason="攤上已放滿 %d 件，先拿回一些再上架。"%Market.MAX_STOCK
	elif stock.size()>=Market.MAX_KINDS:reason="攤上已有 %d 種商品，只能補已上架的品項。"%Market.MAX_KINDS
	var hint:=text(app,box,reason if not reason.is_empty() else "背包裡能在市集賣的東西（顯示今天的單價）。",13,WARN if not reason.is_empty() else MUTED)
	hint.name="MarketStockReason"
	var scroll:=ScrollContainer.new();scroll.name="MarketStockScroll"
	scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus=true
	scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size.y=ROW_HEIGHT*4+12
	box.add_child(scroll)
	var list:=VBoxContainer.new();list.name="MarketStockList";list.add_theme_constant_override("separation",4)
	list.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(list)
	var themed:Array=[];var plain:Array=[]
	for item in prices:
		if int(bag.get(item,0))<=0:continue
		if bool(prices[item].get("themed",false)):themed.append(str(item))
		else:plain.append(str(item))
	var ordered:Array=themed+plain
	if ordered.is_empty():
		text(app,list,"背包裡沒有能上架的收成、料理或花。",14,MUTED).name="MarketStockEmpty"
		return
	for item:String in ordered:
		var held:=int(bag.get(item,0))
		var info:Dictionary=prices[item]
		var row:=HBoxContainer.new();row.name="MarketStockRow_"+item;row.add_theme_constant_override("separation",6)
		row.custom_minimum_size.y=ROW_HEIGHT;list.add_child(row)
		row.add_child(Shell.picture(Items.icon(item),32))
		var name_label:=text(app,row,item_name(item),15);name_label.custom_minimum_size.x=96
		var detail:=text(app,row,"持有 %d · 每份 %d"%[held,int(info.get("price",0))],14)
		detail.name="MarketStockDetail_"+item;detail.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		theme_tag(app,row,bool(info.get("themed",false)))
		var row_reason:=reason
		if row_reason.begins_with("攤上已有") and stock.has(item):row_reason=""
		var fits:=mini(5,mini(held,room))
		var one:="%s:1"%item
		var many:="%s:%d"%[item,maxi(fits,1)]
		action(app,row,"MarketStock_%s_1"%item,"上架 1",func():send(app,"market_stock",one),row_reason.is_empty(),row_reason)
		action(app,row,"MarketStock_%s_5"%item,"上架 %d"%(fits if fits>=2 else 5),func():send(app,"market_stock",many),row_reason.is_empty() and fits>=2,row_reason if not row_reason.is_empty() else "數量不足 2 件，用「上架 1」。")

static func footer(app,body:VBoxContainer,own:Dictionary,stock_count:int,is_open_today:bool)->void:
	var bar:=HBoxContainer.new();bar.name="MarketFooter";bar.add_theme_constant_override("separation",14);body.add_child(bar)
	var left:=VBoxContainer.new();left.add_theme_constant_override("separation",4);bar.add_child(left)
	var open_reason:=""
	if is_open_today:open_reason="今天已開張，午夜結算。"
	elif bool(own.get("pending",false)):open_reason="上一輪還在結算，稍等一下。"
	elif stock_count<=0:open_reason="攤上還沒有商品。"
	var open_button:=action(app,left,"MarketOpen","今天已開張" if is_open_today else "開張營業",func():send(app,"market_open"),open_reason.is_empty(),open_reason)
	open_button.custom_minimum_size=Vector2(150,40)
	text(app,left,open_reason if not open_reason.is_empty() else "開張後今晚午夜結算。",13,WARN if not open_reason.is_empty() else MUTED).name="MarketOpenReason"
	var till_box:=VBoxContainer.new();till_box.add_theme_constant_override("separation",4);bar.add_child(till_box)
	var till:=int(own.get("till",0))
	var till_row:=HBoxContainer.new();till_row.add_theme_constant_override("separation",6);till_box.add_child(till_row)
	till_row.add_child(Shell.picture(Items.icon("coins"),32))
	text(app,till_row,"待領營收 %d 鈴幣"%till,16).name="MarketTill"
	var collect:=action(app,till_row,"MarketCollect","領取",func():send(app,"market_collect"),till>0,"目前沒有待領的營收。")
	collect.custom_minimum_size.x=64
	text(app,till_box,"累計營收 %d 鈴幣"%int(own.get("total",0)),13,MUTED).name="MarketTotal"
	var report_card:=PanelContainer.new();report_card.add_theme_stylebox_override("panel",Pixel.paper_style())
	report_card.size_flags_horizontal=Control.SIZE_EXPAND_FILL;bar.add_child(report_card)
	var report_box:=VBoxContainer.new();report_box.add_theme_constant_override("separation",2);report_card.add_child(report_box)
	var report:Dictionary=own.get("report",{}) if own.get("report",{}) is Dictionary else {}
	if report.is_empty():
		text(app,report_box,"上一輪結算",15)
		text(app,report_box,"還沒有結算紀錄",14,MUTED).name="MarketReport"
		return
	text(app,report_box,"上一輪結算・第 %d 日（%s）"%[int(report.get("day",0))+1,category_name(str(report.get("theme","")))],15).name="MarketReportTitle"
	text(app,report_box,"來客 %d 位 · %d 攤同場 · 收入 %d 鈴幣"%[int(report.get("visitors",0)),int(report.get("stalls",0)),int(report.get("coins",0))],14).name="MarketReport"
	var sold:Dictionary=report.get("sold",{})
	var parts:=PackedStringArray()
	var keys:Array=sold.keys();keys.sort()
	for item in keys:parts.append("%s ×%d"%[item_name(str(item)),int(sold[item])])
	var sold_label:=wrapped(app,report_box,"賣出：%s"%("、".join(parts) if not parts.is_empty() else "這一輪沒有賣出"),14)
	sold_label.name="MarketReportSold"
