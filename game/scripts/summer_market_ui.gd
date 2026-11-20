extends RefCounted
## C12 D14 夏季市集 card inside the existing 市集攤位 panel (market_stall_ui.gd calls build() once, at the top
## of the stall body, only for the plaza stall). A view of snapshot.own_summer_market; the single write is
## Session.perform("summer_market_taste", stall cell, <root option id>), answered through app._notice
## like every other stall action. Rules live in summer_market.gd; nothing here decides anything.
##
## Node names (stable for tests / screenshots):
##   SummerMarketCard, SummerMarketStatus, SummerMarketGuide, SummerMarketReason,
##   SummerTaste_radish / SummerTaste_carrot / SummerTaste_booth (buttons), SummerRoot_<id> (option rows)
const Summer=preload("res://scripts/summer_market.gd")
const Market=preload("res://scripts/market_stall.gd")
const Pixel=preload("res://scripts/inventory_pixel_theme.gd")
const Items=preload("res://scripts/inventory_item_art.gd")
const Shell=preload("res://scripts/life_ui_shell.gd")
const INK:=Color("3d422d")
const MUTED:=Color("7a6f58")
const WARN:=Color("9c4b32")
const SEASON_TAG:=Color("b0622f")

static func own(app) -> Dictionary:
	var found:Variant=app.session.snapshot.get("own_summer_market",{})
	return found if found is Dictionary else {}

static func status_text(view:Dictionary) -> String:
	if bool(view.get("recipe",false)):return "夏季市集 · 已學會〈%s〉"%str(view.get("dish_name","彩虹蔬菜串"))
	if not bool(view.get("unlocked",false)):return "夏季市集 · 尚未開張"
	if bool(view.get("in_season",false)):return "夏季市集 · 進行中，剩 %d 天"%int(view.get("days_left",0))
	return "夏季市集 · 夏天開張（還有 %d 天）"%int(view.get("days_until",0))

static func label(app,parent:Node,value:String,size:int,color:Color,wrap:=false) -> Label:
	var l:Label=app.label(value,size)
	l.add_theme_color_override("font_color",color)
	l.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART if wrap else TextServer.AUTOWRAP_OFF
	if wrap:
		l.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	parent.add_child(l)
	return l

## Adds the card to `body`. `send` is the stall panel's send(app,action,extra) so the cell checks stay in one place.
static func build(app,body:VBoxContainer,send:Callable) -> void:
	var view:=own(app)
	if view.is_empty():return
	var card:=PanelContainer.new()
	card.name="SummerMarketCard"
	card.add_theme_stylebox_override("panel",Pixel.paper_style())
	card.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	body.add_child(card)
	var inner:=VBoxContainer.new()
	inner.add_theme_constant_override("separation",4)
	card.add_child(inner)
	var known:=bool(view.get("recipe",false))
	var season:=bool(view.get("in_season",false))
	var playable:=season and not known and bool(view.get("unlocked",false))
	# Not playable (before summer, after learning, stall locked): one compact row so the stall panel keeps its size.
	var head:Container
	if playable:head=VBoxContainer.new()
	else:head=HBoxContainer.new()
	head.add_theme_constant_override("separation",4 if playable else 14)
	inner.add_child(head)
	var heading:=HBoxContainer.new()
	heading.add_theme_constant_override("separation",7)
	head.add_child(heading)
	heading.add_child(Shell.picture(Items.icon(Summer.DISH),28))
	label(app,heading,status_text(view),15 if not playable else 17,SEASON_TAG if playable else INK).name="SummerMarketStatus"
	var guide:=label(app,head,str(view.get("guidance","")),13 if not playable else 14,MUTED,true)
	guide.name="SummerMarketGuide"
	if known and season:
		var roots:Button=app.button("根菜組 · %d 鈴幣"%int(view.roots_price),func():send.call(app,Summer.BUY_ROOTS,""))
		roots.name="SummerBuyRoots"
		roots.tooltip_text="奶白蘿蔔和糖心胡蘿蔔各 1，每位島民每天可買一組。"
		roots.disabled=not bool(view.can_buy_roots)
		if view.roots_sold_out:roots.text="今天已買過根菜組"
		head.add_child(roots)
	if not playable:return
	var reason:=str(view.get("reason",""))
	var roots:Array=view.get("roots",[])
	var row_box:=HBoxContainer.new()
	row_box.name="SummerMarketOptions"
	row_box.add_theme_constant_override("separation",8)
	inner.add_child(row_box)
	for entry:Variant in roots:
		if not entry is Dictionary:continue
		var id:=str(entry.get("id",""))
		var option:=VBoxContainer.new()
		option.name="SummerRoot_"+id
		option.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		option.add_theme_constant_override("separation",2)
		row_box.add_child(option)
		var cost:=("＋茄子 · %d 鈴幣（持有 %d）"%[int(entry.get("price",0)),int(entry.get("have",0))]) if id==Summer.BOOTH else "＋茄子 · 持有 %d"%int(entry.get("have",0))
		label(app,option,str(entry.get("name","")),15,INK)
		label(app,option,cost,13,MUTED)
		var enabled:=bool(view.get("can_taste",false)) and bool(entry.get("ok",false))
		var why:=reason
		if reason.is_empty() and not bool(entry.get("ok",false)):why="這個選項的材料不夠。"
		var action_caption:="用攤位材料試吃" if id==Summer.BOOTH else "帶%s試吃"%str(entry.get("name",""))
		var button:Button=app.button(action_caption,func():send.call(app,Summer.ACTION,id))
		button.name="SummerTaste_"+id
		button.disabled=not enabled
		button.custom_minimum_size=Vector2(0,34)
		button.focus_mode=Control.FOCUS_ALL
		if not enabled and not why.is_empty():button.tooltip_text=why
		option.add_child(button)
	label(app,inner,reason if not reason.is_empty() else "試吃要 1 個%s，加上一種根菜；材料會用掉，但食譜永久留著。"%str(view.get("eggplant_name","紫絨茄子")),13,WARN if not reason.is_empty() else MUTED,true).name="SummerMarketReason"
