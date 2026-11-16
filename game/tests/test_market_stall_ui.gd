extends SceneTree
## T071 市集攤位 UI test (headless) at 1024×640 and 1280×800. Same harness as
## test_resident_bond_plaza_ui.gd: real Session host, real snapshot round trips.
##
## The stall cell is NEVER hard-coded: it comes from MarketStall.active_cell(snapshot)
## (another worker owns the rules and may tune CANDIDATES).
##
## PRESET / FIXTURE (not human play):
##  * isolated host save in %TEMP% (deleted at the end); app.village_art_preview=true;
##  * state.picnic written directly (false for the locked checks, then true);
##  * player.market erased before each viewport size;
##  * backpack written directly: every market-sellable item set to 0, then five picked
##    sellable items (different categories where possible) 8 each; for the
##    "long inventory" layout check every sellable item is set to 3;
##  * the player is teleported by writing region/x/y next to the stall cell;
##  * world time: set to 0.5 s before the next world midnight (time-of-day preset),
##    then World.step(1.0) is called (the normal tick) to cross midnight.
## REALLY EXERCISED:
##  * the interact key (KEY_E pushed through root.push_input -> main._unhandled_input
##    -> _interact) opens 「市集攤位」; Esc (KEY_ESCAPE through push_input) closes it;
##  * 上架 1 / 上架 N / 拿回 1 / 全部拿回 / 開張營業 / 領取 buttons are pressed by
##    emitting `pressed` (real Session.perform -> World -> snapshot -> panel refresh);
##  * the world tick that settles the stall at midnight.
##
## Journal 「島嶼近況」 market card (MarketNews, news_flow) — extra PRESETS:
##  * player.market erased again and the backpack re-preset (stock_bag) before the card flow;
##  * state.picnic written directly (false, then true) as above;
##  * time-of-day preset to 0.5 s before midnight, then the normal World.step(1.0) tick;
##  * a SECOND player record is added with World.add_player (then removed from
##    active_tokens = offline) and its player.market (stock / open_day / pending / till /
##    total / report) is WRITTEN DIRECTLY; it is erased again before midnight.
## Journal card — REALLY EXERCISED:
##  * the journal is opened with LifeTasks.journal(app) (not the journal key) and the
##    「島嶼近況」 bookmark button (IslandNews) is pressed by emitting `pressed`;
##  * the stall is stocked / opened / collected with the real panel buttons (same press());
##  * one 拿回 goes through app.session.perform("market_take",cell,"item:1") while the
##    news page is open (real World.act -> snapshot -> main._state_changed ->
##    LifeTasks.refresh_island_notes -> refresh_market_news, in place);
##  * the midnight tick settles the stall while the news page is open (in-place update).
##
## T071 攤位布置 「客人的話」 row (MarketGuestRemarkRow / MarketGuestRemark) in the stall
## panel, checked in main_flow at both sizes. Expected text always comes from
## MarketDisplay.remark_line(snapshot.own_market, World.NAMES) — never hard-coded except
## the fixed REMARK_CLOSED / REMARK_EMPTY sentences and the 客人的話： / （閒聊，不影響結算）
## frame. PRESETS used: the same fresh stall / backpack presets as above, plus the
## neighbour stall (add_neighbour_stall: World.add_player + offline + player.market
## WRITTEN DIRECTLY, removed again before I open) and the midnight time-of-day preset.
## REALLY EXERCISED: 上架 / 全部拿回 / 開張營業 panel button presses and the midnight tick.
##  * nobody open today (fresh, and stocked but not opened): no MarketGuestRemark node;
##  * neighbour's stall open, mine not: REMARK_CLOSED line; gone again after removal;
##  * after 開張營業: label text == remark_line, framed, inside the panel, not cut,
##    panel still fits with no outer scroll (layout_ok);
##  * while the panel stays open (same modal): 全部拿回 item by item updates the line in
##    place; once my (only) stall is empty Market.stalls_on no longer counts it, so the
##    row disappears; with the neighbour PRESET open it shows REMARK_EMPTY; re-stocking
##    the same 12 pieces (a 5, b 5, c 1, d 1) brings back the opened line;
##  * after the midnight tick (no stalls today): the row is gone.
## NOT covered: mouse clicks / scroll-wheel input, the journal hotkey, a remote client.
const World=preload("res://scripts/world.gd")
const Market=preload("res://scripts/market_stall.gd")
const Display=preload("res://scripts/market_display.gd")
const Weather=preload("res://scripts/weather.gd")
const MarketVisitors=preload("res://scripts/market_visitors.gd")
const LifeTasks=preload("res://scripts/life_ui_tasks.gd")
const NEIGHBOUR:="market-news-neighbour-token"
const SIDES:=[Vector2(0.5,1.4),Vector2(0.5,-0.4),Vector2(-0.4,0.5),Vector2(1.4,0.5),Vector2(0.5,0.5)]
var app
var w
var id:String=""
var path:String=""
var checks:=0
var failures:=0
var finished:=false
var picks:Array=[]

func _initialize()->void:run.call_deferred()

func check(value:bool,message:String)->void:
	checks+=1
	if not value:failures+=1;push_error(message)

func finish()->void:
	if finished:return
	finished=true
	print("MARKET_STALL_UI_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 or checks==0 else 0)

func note(message:String)->void:
	print("NOTE MARKET_STALL_UI "+message)

# ------------------------------------------------------------------ helpers --

func control(name:String)->Control:
	if not is_instance_valid(app.modal):return null
	return (app.modal as Node).find_child(name,true,false) as Control

func button(name:String)->Button:
	return control(name) as Button

func label_text(name:String)->String:
	var l:=control(name) as Label
	return l.text if l!=null else ""

func layout_meta()->String:
	if not is_instance_valid(app.modal):return ""
	return str((app.modal as Node).get_meta("life_modal_layout",""))

func panel_open()->bool:
	return is_instance_valid(app.modal) and layout_meta()=="market_stall" and control("MarketShelf")!=null

func texts()->String:
	var out:=PackedStringArray()
	if not is_instance_valid(app.modal):return ""
	for node in (app.modal as Node).find_children("*","Label",true,false):
		if (node as Control).is_visible_in_tree():out.append((node as Label).text)
	for node in (app.modal as Node).find_children("*","Button",true,false):
		if (node as Control).is_visible_in_tree():out.append((node as Button).text)
	return "\n".join(out)

func scrolled_out(c:Control)->bool:
	var parent:=c.get_parent()
	while parent:
		if parent is ScrollContainer and not (parent as Control).get_global_rect().grow(0.5).encloses(c.get_global_rect()):return true
		parent=parent.get_parent()
	return false

func in_stock_scroll(c:Control)->bool:
	var scroll:=control("MarketStockScroll")
	return scroll!=null and scroll.is_ancestor_of(c)

func not_cut(l:Label)->bool:
	if l==null:return false
	if l.text_overrun_behavior!=TextServer.OVERRUN_NO_TRIMMING:return false
	if l.get_visible_line_count()<l.get_line_count():return false
	if l.autowrap_mode==TextServer.AUTOWRAP_OFF or l.clip_text:
		var font:Font=l.get_theme_font("font")
		var font_size:int=l.get_theme_font_size("font_size")
		for part:String in l.text.split("\n"):
			if font.get_string_size(part,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x>l.size.x+1.0:return false
	return true

func button_not_cut(b:Button)->bool:
	if b==null:return false
	if b.clip_text or b.text_overrun_behavior!=TextServer.OVERRUN_NO_TRIMMING:return false
	return b.size.x+0.5>=b.get_combined_minimum_size().x

func rect_info(c:Control)->String:
	var modal_rect:="none"
	if is_instance_valid(app.modal):modal_rect=str((app.modal as Control).get_global_rect())
	return "modal=%s control=%s"%[modal_rect,str(c.get_global_rect()) if c!=null else "null"]

func settle()->void:
	for i in range(6):await process_frame
	app._layout_preview();await process_frame

func refresh()->void:
	app.session._send_snapshot(1)
	if app.view!=null and app.view.has_method("_process"):app.view._process(0.0)
	await settle()

func own()->Dictionary:
	var found:Variant=app.session.snapshot.get("own_market",{})
	return found if found is Dictionary else {}

func inventory()->Dictionary:
	return w.state.players[id].inventory

func held(item:String)->int:
	return int(inventory().get(item,0))

func stock_of(item:String)->int:
	return int(own().get("stock",{}).get(item,0))

func feedback()->String:
	if app.modal_feedback==null or not is_instance_valid(app.modal_feedback):return ""
	return str((app.modal_feedback as Label).text)

func focus()->String:
	return str(app.view.interaction_focus()) if app.view!=null and app.view.has_method("interaction_focus") else "?"

func stand(at:Vector2)->void:
	var person:Dictionary=w.state.players[id]
	person.region=World.REGIONS.HOME
	person.x=at.x;person.y=at.y
	await refresh()

func standable(tile:Vector2i)->bool:
	return World.land(tile) and not w.blocked(tile)

func stand_next_to(cell:Vector2i,label:String)->bool:
	for off:Vector2 in SIDES:
		var at:Vector2=Vector2(cell)+off
		if not standable(Vector2i(at.floor())):continue
		await stand(at)
		if focus()=="market":
			if off!=SIDES[0]:note("stall: standing at offset %s (%s)"%[str(off),label])
			return true
	check(false,"Some side of the stall %s focuses the market (%s): last focus %s"%[str(cell),label,focus()])
	return false

func key(code:Key)->void:
	for pressed in [true,false]:
		var e:=InputEventKey.new()
		e.keycode=code;e.physical_keycode=code;e.pressed=pressed
		root.push_input(e)
	await settle()

func press(name:String,label:String)->bool:
	var b:=control(name) as BaseButton
	check(b!=null and not b.disabled,"Enabled %s (%s)"%[name,label])
	if b==null or b.disabled:return false
	b.grab_focus()  # as a keyboard/controller press would
	await create_timer(0.08).timeout
	b.pressed.emit()
	await settle()
	check(panel_open(),"Panel stays open after %s (%s)"%[name,label])
	return true

func disabled_with(name:String,_reason_part:String,label:String)->void:
	var b:=button(name)
	check(b!=null and b.disabled,"%s disabled (%s)"%[name,label])

# ------------------------------------------------------------------- layout --

func layout_ok(label:String)->void:
	if not panel_open():
		check(false,"Panel open for layout: "+label)
		return
	var modal:Control=app.modal
	var view_rect:=root.get_visible_rect()
	check(view_rect.encloses(modal.get_global_rect()),"Panel fits the viewport (%s) %s"%[label,rect_info(null)])
	check(modal.size.x<=1000.5 and modal.size.y<=620.5,"Panel within 1000×620 (%s) %s"%[label,str(modal.size)])
	var outer:=control("ModalScroll") as ScrollContainer
	if outer!=null:
		var bar:=outer.get_v_scroll_bar()
		check(bar.max_value<=bar.page+1.0,"Outer panel needs no scrolling (%s) max=%.0f page=%.0f"%[label,bar.max_value,bar.page])
	for name in ["MarketTheme","MarketNextTheme","MarketVisitors","MarketRule","MarketShelf","MarketShelfCount","MarketStockReason","MarketStockScroll","MarketOpen","MarketOpenReason","MarketTill","MarketCollect","MarketReport"]:
		var c:=control(name)
		check(c!=null and c.is_visible_in_tree(),"%s present (%s)"%[name,label])
		if c==null:continue
		check(view_rect.encloses(c.get_global_rect()) and modal.get_global_rect().grow(0.5).encloses(c.get_global_rect()),"%s inside viewport and panel (%s) %s"%[name,label,rect_info(c)])
	for node in modal.find_children("*","Control",true,false):
		var c:=node as Control
		if not c.is_visible_in_tree() or c is ScrollBar or c.get_parent() is ScrollBar:continue
		if not (c is BaseButton or c is Label or c is TextureRect):continue
		if scrolled_out(c):continue
		check(view_rect.encloses(c.get_global_rect()),"%s inside the viewport (%s) %s"%[c.name,label,rect_info(c)])
		check(modal.get_global_rect().grow(0.5).encloses(c.get_global_rect()),"%s inside the panel (%s) %s"%[c.name,label,rect_info(c)])
		if c is Label:check(not_cut(c as Label),"Label not cut: %s 「%s」 (%s)"%[c.name,(c as Label).text,label])
		if c is Button:check(button_not_cut(c as Button),"Button caption not cut: %s 「%s」 (%s)"%[c.name,(c as Button).text,label])
	check(not texts().contains("…"),"No ellipsis anywhere in the panel (%s)"%label)
	# Fixed shelf rows never scroll and keep 4 slots.
	var shelf:=control("MarketShelf")
	if shelf!=null:
		check(shelf.get_child_count()==Market.MAX_KINDS,"Shelf has %d fixed rows (%s): %d"%[Market.MAX_KINDS,label,shelf.get_child_count()])
		for row in shelf.get_children():
			check(not scrolled_out(row as Control) and not in_stock_scroll(row as Control),"Shelf row %s never scrolls (%s)"%[row.name,label])
	var footer:=control("MarketFooter")
	if footer!=null:check(footer.get_combined_minimum_size().x<=footer.size.x+0.5,"Footer does not overflow (%s)"%label)

func focus_ok(label:String,require_first:bool=true)->void:
	var owner:=root.gui_get_focus_owner()
	check(owner!=null and is_instance_valid(app.modal) and (app.modal as Node).is_ancestor_of(owner) and owner is BaseButton and not (owner as BaseButton).disabled,"Keyboard focus is on an enabled button inside the panel (%s): %s"%[label,str(owner.name) if owner else "none"])
	var body:Node=control("ModalContent")
	if body==null or not require_first:return
	var first:BaseButton=null
	for node in body.find_children("*","BaseButton",true,false):
		var b:=node as BaseButton
		if b.is_visible_in_tree() and not b.disabled:first=b;break
	if first!=null:check(owner==first,"First actionable button %s is focused (%s): %s"%[first.name,label,str(owner.name) if owner else "none"])

# ------------------------------------------------------- 客人的話 (T071 布置) --

func remark_label()->Label:
	return control("MarketGuestRemark") as Label

func expected_remark()->String:
	var said:String=Display.remark_line(own(),World.NAMES)
	return said

func remark_frame(said:String)->String:
	return "客人的話："+said+"（閒聊，不影響結算）"

func no_remark(label:String)->void:
	var l:Label=remark_label()
	var shown:String=l.text if l!=null else ""
	check(l==null and control("MarketGuestRemarkRow")==null,"No MarketGuestRemark while nobody opened today (%s): stalls_today=%s text=「%s」"%[label,str(own().get("stalls_today","?")),shown])
	check(expected_remark().is_empty(),"remark_line empty while nobody opened today (%s): 「%s」"%[label,expected_remark()])

## Checks the remark row against MarketDisplay.remark_line(own_market); when `said` is
## given, the expected line must also be that fixed sentence. Returns the shown text.
func remark_ok(label:String,said:String="")->String:
	var want:String=expected_remark()
	check(not want.is_empty(),"remark_line non-empty once a stall is open today (%s): stalls_today=%s"%[label,str(own().get("stalls_today","?"))])
	if not said.is_empty():check(want==remark_frame(said),"Expected remark is the fixed sentence (%s): want=「%s」 got=「%s」"%[label,remark_frame(said),want])
	var l:Label=remark_label()
	check(l!=null and l.is_visible_in_tree() and control("MarketGuestRemarkRow")!=null,"MarketGuestRemark shown in MarketGuestRemarkRow (%s)"%label)
	if l==null or not is_instance_valid(app.modal):return ""
	check(l.text==want,"MarketGuestRemark == MarketDisplay.remark_line(own_market) (%s): got=「%s」 want=「%s」"%[label,l.text,want])
	check(l.text.begins_with("客人的話：") and l.text.ends_with("（閒聊，不影響結算）"),"Remark framed by 客人的話：…（閒聊，不影響結算） (%s): 「%s」"%[label,l.text])
	var modal:Control=app.modal
	var r:Rect2=l.get_global_rect()
	check(root.get_visible_rect().grow(0.5).encloses(r) and modal.get_global_rect().grow(0.5).encloses(r) and not scrolled_out(l),"MarketGuestRemark inside the viewport and panel (%s) %s"%[label,rect_info(l)])
	check(r.size.x>1.0 and r.size.y>1.0,"MarketGuestRemark has a real size (%s) %s"%[label,str(r.size)])
	check(not_cut(l),"MarketGuestRemark not cut (%s): visible=%d lines=%d"%[label,l.get_visible_line_count(),l.get_line_count()])
	var footer:=control("MarketFooter")
	if footer!=null:check(r.end.y<=footer.get_global_rect().position.y+0.5,"Remark sits above the footer (%s) %s footer=%s"%[label,rect_info(l),str(footer.get_global_rect())])
	return l.text

## PRESET: a second (offline) player whose stall is open today, written directly.
func add_neighbour_stall()->void:
	var today:=Market.day(float(w.state.time))
	w.add_player(NEIGHBOUR,"隔壁攤主")  # PRESET second player record
	w.active_tokens.erase(NEIGHBOUR)  # PRESET offline (its stall still counts, like any offline stall)
	var neighbour:Dictionary=w.state.players[NEIGHBOUR]
	neighbour["market"]={"stock":{picks[4]:3,picks[2]:2},"open_day":today,"pending":true,"till":4321,"total":9876,
		"report":{"day":today-1,"visitors":2,"stalls":1,"theme":Market.theme_of(today-1),"sold":{picks[3]:2},"coins":4321}}  # PRESET written directly
	await refresh()

func remove_neighbour_stall()->void:
	w.state.players.erase(NEIGHBOUR)
	w.active_tokens.erase(NEIGHBOUR)
	await refresh()

# --------------------------------------------------------------------- flows --

func set_picnic(on:bool)->void:
	w.state.picnic=on
	await refresh()

func choose_picks()->void:
	picks.clear()
	var by_category:={}
	for item:String in Market.sellable_items():
		var category:=Market.category_of(item)
		if not by_category.has(category):by_category[category]=[]
		by_category[category].append(item)
	var order:=["produce","dish","flower"]
	var index:=0
	while picks.size()<5 and index<12:
		for category in order:
			var list:Array=by_category.get(category,[])
			if index<list.size() and picks.size()<5:picks.append(list[index])
		index+=1
	note("picked items: %s"%str(picks))
	check(picks.size()==5,"Five sellable items available for the fixture")

func stock_bag(amount:int=8)->void:
	var inv:Dictionary=inventory()
	for item:String in Market.sellable_items():inv[item]=0
	for item in picks:inv[item]=amount

func locked_flow(label:String)->void:
	await set_picnic(false)
	check(Market.active_cell(app.session.snapshot)==Market.NO_CELL,"No active stall cell before the picnic (%s)"%label)
	check(not bool(own().get("unlocked",true)) or own().is_empty(),"own_market says locked before the picnic (%s): %s"%[label,str(own().get("unlocked","?"))])
	var cell:Vector2i=Market.CANDIDATES[0]
	for off:Vector2 in SIDES:
		await stand(Vector2(cell)+off)
		check(focus()!="market","No market focus at %s before the picnic (%s): %s"%[str(off),label,focus()])
	var has_label:=false
	for entry in app.view.world_labels:
		if str(entry.id)=="market":has_label=true
	check(not has_label,"No 「市集攤位」 world label before the picnic (%s)"%label)
	await key(KEY_E)
	check(not panel_open(),"E at the stall spot before the picnic opens no 市集攤位 (%s)"%label)
	if is_instance_valid(app.modal):app._close_modal();await settle()

func open_by_key(label:String)->bool:
	if is_instance_valid(app.modal):app._close_modal();await settle()
	var cell:=Market.active_cell(app.session.snapshot)
	if not await stand_next_to(cell,label):return false
	await key(KEY_E)
	var ok:=panel_open()
	check(ok,"Interact key next to the stall opens 市集攤位 (%s) texts=%s"%[label,texts().left(60).replace("\n"," | ")])
	if ok:
		check(texts().contains("市集攤位"),"Panel titled 市集攤位 (%s)"%label)
		check(not app._world_keyboard_allowed() and not app._world_pointer_allowed(Vector2(root.size)/2.0),"World keys and pointer are blocked while the panel is open (%s)"%label)
	return ok

func main_flow(label:String)->void:
	var person:Dictionary=w.state.players[id]
	person.erase("market")  # PRESET fresh stall
	stock_bag()
	await set_picnic(true)
	var cell:=Market.active_cell(app.session.snapshot)
	check(cell!=Market.NO_CELL and cell==Market.cell_for(w.state),"Stall cell from the server after the picnic (%s): %s"%[label,str(cell)])
	if not await open_by_key("open "+label):return
	focus_ok("empty "+label)
	layout_ok("empty "+label)
	var m:=own()
	check(texts().contains("今日主題：%s"%Market.CATEGORY_NAMES[str(m.theme)]) and texts().contains("明日主題：%s"%Market.CATEGORY_NAMES[str(m.next_theme)]),"Header shows today/tomorrow themes (%s)"%label)
	check(label_text("MarketVisitors")=="今日已開張 %d 攤 · 預估來客 %d 位"%[int(m.stalls_today),int(m.visitors_estimate)],"Header shows stalls and visitors (%s): %s"%[label,label_text("MarketVisitors")])
	check(label_text("MarketRule").contains("午夜結算"),"Rule sentence shown (%s)"%label)
	check(label_text("MarketShelfCount").begins_with("0／12"),"Shelf count 0／12 (%s): %s"%[label,label_text("MarketShelfCount")])
	disabled_with("MarketOpen","",label)
	check(label_text("MarketOpenReason")=="攤上還沒有商品。","Open disabled reason: no stock (%s): %s"%[label,label_text("MarketOpenReason")])
	disabled_with("MarketCollect","",label)
	check(label_text("MarketReport")=="還沒有結算紀錄","No report yet (%s)"%label)
	for item in picks:
		check(control("MarketStockRow_"+item)!=null,"%s offered in 可上架 (%s)"%[item,label])
		check(texts().contains("持有 8 · 每份 %d"%int(m.prices[item].price)),"%s row shows held and today's price (%s)"%[item,label])
	check(control("MarketStockRow_wood")==null,"wood not offered (%s)"%label)
	# 客人的話: nobody on the island has opened yet -> no remark row.
	no_remark("fresh "+label)
	# Another player's stall open today while mine is not -> REMARK_CLOSED (PRESET neighbour).
	await add_neighbour_stall()
	check(panel_open(),"Panel stays open when another player's stall opens (%s)"%label)
	check(int(own().get("stalls_today",0))==1 and not bool(own().get("open",false)),"Only the neighbour's stall is open today (%s): stalls=%s open=%s"%[label,str(own().get("stalls_today","?")),str(own().get("open","?"))])
	remark_ok("neighbour open, mine closed "+label,Display.REMARK_CLOSED)
	layout_ok("neighbour remark "+label)
	await remove_neighbour_stall()
	check(panel_open(),"Panel stays open when the neighbour's stall is removed (%s)"%label)
	no_remark("neighbour removed "+label)
	var a:String=picks[0];var b:String=picks[1];var c:String=picks[2];var d:String=picks[3];var e:String=picks[4]
	# 上架 1, 上架 5, 拿回 1, 全部拿回 on item a.
	if await press("MarketStock_%s_1"%a,label):
		check(stock_of(a)==1 and held(a)==7,"上架 1 moves one %s (%s)"%[a,label])
		check(feedback().contains("擺上攤位"),"Server reply shown in the panel (%s): %s"%[label,feedback()])
		check(control("MarketShelfRow_"+a)!=null and label_text("MarketShelfDetail_"+a)=="×1 · 每份 %d"%int(own().prices[a].price),"Shelf row for %s shows ×1 and price (%s)"%[a,label])
	if await press("MarketStock_%s_5"%a,label):check(stock_of(a)==6 and held(a)==2,"上架 5 moves five %s (%s)"%[a,label])
	if await press("MarketTake_%s_1"%a,label):
		check(stock_of(a)==5 and held(a)==3,"拿回 1 returns one %s (%s)"%[a,label])
		check(feedback().contains("收回"),"Take reply shown (%s): %s"%[label,feedback()])
	if await press("MarketTake_%s_all"%a,label):check(stock_of(a)==0 and held(a)==8 and control("MarketShelfRow_"+a)==null,"全部拿回 empties %s (%s)"%[a,label])
	# Four kinds.
	await press("MarketStock_%s_5"%a,label)
	for item in [b,c,d]:await press("MarketStock_%s_1"%item,label)
	check(own().get("stock",{}).size()==4 and int(own().stock_count)==8,"Four kinds, eight pieces (%s): %s"%[label,str(own().get("stock",{}))])
	disabled_with("MarketStock_%s_1"%e,"",label)
	check(label_text("MarketStockReason").contains("%d 種"%Market.MAX_KINDS),"Kinds limit reason shown (%s): %s"%[label,label_text("MarketStockReason")])
	check(button("MarketStock_%s_1"%a)!=null and not button("MarketStock_%s_1"%a).disabled,"Already stocked %s can still be topped up (%s)"%[a,label])
	# After a refresh the pressed (still enabled) button keeps keyboard focus.
	var kept:=root.gui_get_focus_owner()
	check(kept!=null and str(kept.name)=="MarketStock_%s_1"%d,"Focus stays on the pressed 上架 1 after the refresh (%s): %s"%[label,str(kept.name) if kept else "none"])
	focus_ok("four kinds "+label,false)
	layout_ok("four kinds "+label)
	no_remark("stocked, not open "+label)
	# Fill to twelve: 上架 N shows what fits.
	var big:=button("MarketStock_%s_5"%b)
	check(big!=null and big.text=="上架 4","上架 N caps at what fits (%s): %s"%[label,big.text if big else "?"])
	await press("MarketStock_%s_5"%b,label)
	check(int(own().stock_count)==12,"Stall full at 12 pieces (%s): %d"%[label,int(own().stock_count)])
	check(label_text("MarketShelfCount").begins_with("12／12"),"Shelf count 12／12 (%s)"%label)
	for item in picks:
		var one:=button("MarketStock_%s_1"%item)
		if one!=null:check(one.disabled,"上架 1 for %s disabled when full (%s)"%[item,label])
	check(label_text("MarketStockReason").contains("已放滿"),"Full reason shown (%s): %s"%[label,label_text("MarketStockReason")])
	# Long inventory with a full stall still fits.
	for item:String in Market.sellable_items():
		if held(item)==0:inventory()[item]=3  # PRESET long list
	await refresh()
	var list:=control("MarketStockList")
	check(list!=null and list.get_child_count()>=Market.sellable_items().size()-4,"Long 可上架 list rendered (%s): %d rows"%[label,list.get_child_count() if list else -1])
	layout_ok("full stall + long inventory "+label)
	var scroll:=control("MarketStockScroll") as ScrollContainer
	if scroll!=null:
		note("可上架 list scrolls internally=%s (%s)"%[str(scroll.get_v_scroll_bar().max_value>scroll.get_v_scroll_bar().page+1.0),label])
		var last:Control=null
		if list!=null and list.get_child_count()>0:last=list.get_child(list.get_child_count()-1) as Control
		if last!=null:
			scroll.ensure_control_visible(last)
			await settle()
			check(not scrolled_out(last) and (app.modal as Control).get_global_rect().encloses(last.get_global_rect()),"Last 可上架 row reachable by scrolling the list (%s)"%label)
			scroll.scroll_vertical=0
			await settle()
	stock_bag()
	await refresh()
	# Open.
	if await press("MarketOpen",label):
		check(bool(own().open) and bool(own().pending),"Stall open and pending (%s)"%label)
		check(feedback().contains("開張"),"Open reply shown (%s): %s"%[label,feedback()])
		var open_button:=button("MarketOpen")
		check(open_button!=null and open_button.disabled and open_button.text=="今天已開張","開張營業 disabled as 今天已開張 (%s)"%label)
		check(label_text("MarketOpenReason")=="今天已開張，午夜結算。","Open reason: already open (%s)"%label)
		check(label_text("MarketVisitors")=="今日已開張 %d 攤 · 預估來客 %d 位"%[int(own().stalls_today),int(own().visitors_estimate)] and int(own().stalls_today)==1,"Header counts our stall (%s): %s"%[label,label_text("MarketVisitors")])
		focus_ok("opened "+label)
		layout_ok("opened "+label)
		# 客人的話 after a real 開張營業.
		var opened_line:String=remark_ok("opened "+label)
		var remark_page:int=modal_id()
		# Take everything back while the panel stays open: the line follows the stock in place.
		for item:String in [a,b,c,d]:
			if not await press("MarketTake_%s_all"%item,"remark take "+label):continue
			check(remark_page!=0 and modal_id()==remark_page and panel_open(),"Same panel after 全部拿回 %s (%s)"%[item,label])
			check(stock_of(item)==0 and bool(own().get("open",false)),"%s taken back, stall still open today (%s): stock=%s"%[item,label,str(own().get("stock",{}))])
			var stock_now:Dictionary=own().get("stock",{})
			if not stock_now.is_empty():remark_ok("took back %s %s"%[item,label])
		# Market.stalls_on only counts open stalls that still hold goods: my emptied stall is
		# no longer counted, so with nobody else open there are no guests and no remark.
		check(own().get("stock",{}).is_empty() and int(own().get("stalls_today",-1))==0,"Emptied open stall no longer counts in stalls_today (%s): %s"%[label,str(own().get("stalls_today","?"))])
		no_remark("open but emptied, alone "+label)
		# REMARK_EMPTY needs guests on the plaza: PRESET neighbour stall while mine is open and empty.
		await add_neighbour_stall()
		check(modal_id()==remark_page and panel_open(),"Same panel after the neighbour opens (%s)"%label)
		var empty_line:String=remark_ok("open, empty shelf, neighbour open "+label,Display.REMARK_EMPTY)
		check(empty_line!=opened_line,"Remark changed from the opened line after taking everything back (%s): 「%s」"%[label,opened_line])
		layout_ok("open, empty shelf "+label)
		await remove_neighbour_stall()
		check(modal_id()==remark_page and panel_open(),"Same panel after the neighbour is removed (%s)"%label)
		no_remark("neighbour removed, empty shelf "+label)
		# Re-stock the same twelve pieces (a 5, b 5, c 1, d 1) so the midnight checks below are unchanged.
		for step:Array in [[a,5],[b,5],[c,1],[d,1]]:
			await press("MarketStock_%s_%d"%[str(step[0]),int(step[1])],"remark restock "+label)
			check(modal_id()==remark_page and panel_open(),"Same panel after re-stocking %s (%s)"%[str(step[0]),label])
			remark_ok("restock %s %s"%[str(step[0]),label])
		check(int(own().get("stock_count",0))==12 and own().get("stock",{}).size()==4 and int(own().get("stock",{}).get(a,0))==5 and int(own().get("stock",{}).get(b,0))==5,"Re-stocked to the same 12 pieces (%s): %s"%[label,str(own().get("stock",{}))])
		check(remark_ok("restocked "+label)==opened_line,"Same stock composition -> same remark as when opened (%s)"%label)
		layout_ok("restocked "+label)
	# Midnight: preset time to just before the next world day, then the normal tick.
	var today:=Market.day(float(w.state.time))
	w.state.time=float(today+1)*Weather.DAY_SECONDS-0.5
	check(w.step(1.0,true),"World tick across midnight succeeds (%s)"%label)
	await refresh()
	var report:Dictionary=own().get("report",{})
	check(not report.is_empty() and int(report.get("day",-1))==today,"Report for day %d after midnight (%s): %s"%[today,label,str(report)])
	var expected_visitors:=Market.visitors_for(1)
	check(int(report.get("visitors",0))==expected_visitors and int(report.get("stalls",0))==1,"One stall -> %d visitors (%s)"%[expected_visitors,label])
	var till:=int(own().get("till",0))
	check(till>0 and till==int(report.get("coins",-1)),"Till holds the day's coins (%s): %d"%[label,till])
	check(panel_open(),"Panel survives the midnight refresh (%s)"%label)
	check(int(own().get("stalls_today",-1))==0,"No stalls open on the new day (%s): %s"%[label,str(own().get("stalls_today","?"))])
	no_remark("after midnight "+label)
	check(label_text("MarketReportTitle").begins_with("上一輪結算・第 %d 日"%(today+1)),"Report title (%s): %s"%[label,label_text("MarketReportTitle")])
	check(label_text("MarketReport")=="來客 %d 位 · %d 攤同場 · 收入 %d 鈴幣"%[int(report.visitors),int(report.stalls),int(report.coins)],"Report line (%s): %s"%[label,label_text("MarketReport")])
	var sold:Dictionary=report.get("sold",{})
	for item in sold:check(label_text("MarketReportSold").contains("%s ×%d"%[World.NAMES[item],int(sold[item])]),"Report lists %s ×%d (%s)"%[item,int(sold[item]),label])
	check(label_text("MarketTill")=="待領營收 %d 鈴幣"%till,"Till label (%s): %s"%[label,label_text("MarketTill")])
	var open_again:=button("MarketOpen")
	check(open_again!=null and open_again.text=="開張營業","A new day offers 開張營業 again (%s)"%label)
	layout_ok("report "+label)
	# Collect.
	var coins_before:=int(w.state.players[id].coins)
	if await press("MarketCollect",label):
		check(int(w.state.players[id].coins)==coins_before+till and int(own().till)==0,"領取 moves %d coins to the wallet (%s)"%[till,label])
		check(feedback().contains("鈴幣"),"Collect reply shown (%s): %s"%[label,feedback()])
		disabled_with("MarketCollect","",label)
		check(label_text("MarketTill")=="待領營收 0 鈴幣","Till back to 0 (%s)"%label)
		check(label_text("MarketReport").begins_with("來客"),"Report stays after collecting (%s)"%label)
	layout_ok("collected "+label)
	# Esc closes.
	await key(KEY_ESCAPE)
	check(not is_instance_valid(app.modal) or app.modal==null,"Esc closes the panel (%s)"%label)

# ------------------------------------------------- journal 「我的市集攤位」 card --

func news_card()->VBoxContainer:
	return control("MarketNews") as VBoxContainer

func news_labels()->Array:
	var out:=[]
	var card:=news_card()
	if card==null:return out
	for index in range(32):
		var l:=card.find_child("MarketNewsLine%d"%index,true,false) as Label
		if l==null:break
		out.append(l)
	return out

func news_texts()->Array:
	var out:=[]
	for node in news_labels():out.append((node as Label).text)
	return out

func news_ids()->Array:
	var out:=[]
	for node in news_labels():out.append((node as Object).get_instance_id())
	return out

func news_heading()->String:
	var card:=news_card()
	if card==null or card.get_child_count()==0:return ""
	var head:Node=card.get_child(0)
	if not head is HBoxContainer:return ""
	for node in head.find_children("*","Label",true,false):return (node as Label).text
	return ""

func expected_news()->Array:
	return MarketVisitors.summary_lines(own(),World.NAMES)

func modal_id()->int:
	return (app.modal as Object).get_instance_id() if is_instance_valid(app.modal) else 0

func open_news(label:String)->bool:
	if is_instance_valid(app.modal):app._close_modal();await settle()
	LifeTasks.journal(app)
	await settle()
	var bookmark:=button("IslandNews")
	check(bookmark!=null and bookmark.is_visible_in_tree() and not bookmark.disabled,"Journal shows an enabled 島嶼近況 bookmark (%s)"%label)
	if bookmark!=null:
		bookmark.grab_focus()
		bookmark.pressed.emit()
	else:
		LifeTasks.island_news(app)
	await settle()
	var ok:bool=is_instance_valid(app.modal) and layout_meta()=="community_board"
	check(ok,"島嶼近況 page open (%s): layout=%s"%[label,layout_meta()])
	return ok

func close_news()->void:
	if is_instance_valid(app.modal):app._close_modal()
	await settle()

func news_matches(label:String)->Array:
	var lines:=news_texts()
	var want:=expected_news()
	check(lines==want,"MarketNews lines == MarketVisitors.summary_lines(own_market) (%s): got=%s want=%s"%[label,str(lines),str(want)])
	return lines

func news_same_modal(before:int,label:String)->void:
	check(before!=0 and modal_id()==before and layout_meta()=="community_board","Same 島嶼近況 modal still open after the snapshot (%s): layout=%s"%[label,layout_meta()])

func news_fit(label:String)->void:
	if not is_instance_valid(app.modal):
		check(false,"Page open for the card fit check (%s)"%label)
		return
	var modal:Control=app.modal
	var view_rect:=root.get_visible_rect()
	check(view_rect.grow(0.5).encloses(modal.get_global_rect()),"島嶼近況 page inside the viewport (%s) %s"%[label,rect_info(null)])
	var card:=news_card()
	check(card!=null and card.is_visible_in_tree(),"MarketNews visible (%s)"%label)
	if card==null:return
	var scroll:ScrollContainer=null
	var parent:Node=card.get_parent()
	while parent!=null and parent!=modal:
		if parent is ScrollContainer:
			scroll=parent as ScrollContainer
			break
		parent=parent.get_parent()
	if scroll==null:
		note("MarketNews has no scrolling ancestor inside the page (%s)"%label)
		check(modal.get_global_rect().grow(0.5).encloses(card.get_global_rect()),"MarketNews inside the page (%s) %s"%[label,rect_info(card)])
	else:
		var bar:=scroll.get_v_scroll_bar()
		note("島嶼近況 page scrolls vertically=%s (%s)"%[str(bar.max_value>bar.page+1.0),label])
		check(scroll.is_ancestor_of(card),"MarketNews is inside the page's scroll content (%s)"%label)
	var labels:=news_labels()
	check(labels.size()>=4,"MarketNews has at least 4 line labels for the fit check (%s): %d"%[label,labels.size()])
	for node in labels:
		var l:=node as Label
		if scroll!=null:
			scroll.ensure_control_visible(l)
			await settle()
		var r:=l.get_global_rect()
		var m:=modal.get_global_rect()
		check(l.is_visible_in_tree(),"%s visible (%s)"%[l.name,label])
		check(r.position.x>=m.position.x-0.5 and r.end.x<=m.end.x+0.5,"%s inside the page horizontally (%s) %s"%[l.name,label,rect_info(l)])
		check(view_rect.grow(0.5).encloses(r) and m.grow(0.5).encloses(r) and not scrolled_out(l),"%s reachable on screen after scrolling to it (%s) %s"%[l.name,label,rect_info(l)])
		check(l.get_visible_line_count()>=l.get_line_count(),"%s not clipped (%s): visible=%d lines=%d 「%s」"%[l.name,label,l.get_visible_line_count(),l.get_line_count(),l.text])
		check(l.text_overrun_behavior==TextServer.OVERRUN_NO_TRIMMING and not l.text.contains("…"),"%s not trimmed (%s)"%[l.name,label])
	if scroll!=null:
		scroll.scroll_vertical=0
		await settle()

func news_flow(label:String)->void:
	# 1. Before the picnic: no card.
	await set_picnic(false)
	check(expected_news().is_empty(),"summary_lines is empty before the picnic (%s)"%label)
	if await open_news("locked "+label):
		check(news_card()==null,"No MarketNews card on 島嶼近況 before the picnic (%s)"%label)
		check(not texts().contains("我的市集攤位"),"No 我的市集攤位 text before the picnic (%s)"%label)
	await close_news()
	# 2. Fresh stall after the picnic.
	var person:Dictionary=w.state.players[id]
	person.erase("market")  # PRESET fresh stall
	stock_bag()  # PRESET backpack
	await set_picnic(true)
	if not await open_news("fresh "+label):return
	check(news_card()!=null,"MarketNews card on 島嶼近況 after the picnic (%s)"%label)
	check(news_heading()=="我的市集攤位","Card heading 我的市集攤位 (%s): 「%s」"%[label,news_heading()])
	var lines:=news_matches("fresh "+label)
	check(lines.size()==4,"Fresh card has 4 lines (%s): %d"%[label,lines.size()])
	check(lines.size()==4 and str(lines[3]).contains("還沒有結算紀錄"),"Fresh card: 還沒有結算紀錄 in the last line (%s): %s"%[label,str(lines)])
	check(lines.size()>=2 and str(lines[1]).begins_with("今天還沒開張"),"Fresh card: not open yet (%s): %s"%[label,str(lines)])
	await news_fit("fresh "+label)
	# 3. Stock and open through the stall panel buttons, then reopen the page.
	if not await open_by_key("news stall "+label):return
	var a:String=picks[0];var b:String=picks[1]
	await press("MarketStock_%s_5"%a,"news "+label)
	await press("MarketStock_%s_1"%b,"news "+label)
	await press("MarketOpen","news "+label)
	check(bool(own().get("open",false)) and int(own().get("stock_count",0))==6,"Stall stocked with 6 and opened through the panel (%s): %s"%[label,str(own().get("stock",{}))])
	if not await open_news("opened "+label):return
	lines=news_matches("opened "+label)
	check(lines.size()==4 and str(lines[1]).begins_with("今天營業中") and str(lines[1]).contains("攤上 6 件"),"Opened card: 今天營業中 · 攤上 6 件 in line 1 (%s): %s"%[label,str(lines)])
	# 4. In-place update through the real server path while the page stays open.
	var page:=modal_id()
	var ids_before:=news_ids()
	var cell:=Market.active_cell(app.session.snapshot)
	app.session.perform("market_take",cell,"%s:1"%a)
	await refresh()
	check(stock_of(a)==4 and held(a)==4,"market_take via Session.perform returned one %s (%s): stock=%d held=%d"%[a,label,stock_of(a),held(a)])
	news_same_modal(page,"take "+label)
	lines=news_matches("in place take "+label)
	check(lines.size()==4 and str(lines[1]).contains("攤上 5 件"),"Card updated in place to 攤上 5 件 (%s): %s"%[label,str(lines)])
	var ids_after:=news_ids()
	check(ids_after.size()==4 and ids_after!=ids_before,"Changed snapshot rebuilt the card lines (%s)"%label)
	await refresh()
	news_same_modal(page,"unchanged "+label)
	check(news_ids()==ids_after,"Unchanged snapshot does not rebuild the card (same Label instances) (%s)"%label)
	# 7. Another player's stall never shows on my card (only island-wide numbers move).
	var before_own:Dictionary=own().duplicate(true)
	var before_lines:=news_texts()
	await add_neighbour_stall()  # PRESET second player's open stall (see helper)
	news_same_modal(page,"neighbour "+label)
	var after_own:=own()
	check(int(after_own.get("stalls_today",0))==int(before_own.get("stalls_today",0))+1,"Island-wide stalls_today counts the neighbour's stall (%s): %s -> %s"%[label,str(before_own.get("stalls_today")),str(after_own.get("stalls_today"))])
	for field in ["stock","stock_count","till","total","report","open","pending","theme","next_theme"]:
		check(after_own.get(field)==before_own.get(field),"own_market.%s unchanged by another player's stall (%s)"%[field,label])
	var island:Dictionary=before_own.duplicate(true)
	island["stalls_today"]=after_own.get("stalls_today",0)
	island["visitors_estimate"]=after_own.get("visitors_estimate",0)
	var want:Array=MarketVisitors.summary_lines(island,World.NAMES)
	lines=news_texts()
	check(lines==want,"Card differs only by island-wide stalls_today/visitors_estimate (%s): got=%s want=%s"%[label,str(lines),str(want)])
	check(lines.size()==before_lines.size(),"Same number of card lines with a neighbour stall (%s)"%label)
	for i in range(mini(lines.size(),before_lines.size())):
		if i!=1:check(lines[i]==before_lines[i],"Card line %d unchanged by the neighbour (%s): %s"%[i,label,str(lines[i])])
	var joined:="\n".join(PackedStringArray(lines))
	check(not joined.contains("4321") and not joined.contains("9876"),"Neighbour's till/total never appear on my card (%s)"%label)
	check(lines.size()==4 and str(lines[3]).contains("還沒有結算紀錄"),"Neighbour's report never appears on my card (%s): %s"%[label,str(lines)])
	await remove_neighbour_stall()  # remove the PRESET before midnight so the existing report numbers stay 1-stall
	check(news_texts()==before_lines and int(own().get("stalls_today",-1))==int(before_own.get("stalls_today",0)),"Card back to its own numbers after the neighbour is removed (%s): %s"%[label,str(news_texts())])
	# 5. Midnight settlement while the page is open (in place).
	var day_before:=Market.day(float(w.state.time))
	w.state.time=float(day_before+1)*Weather.DAY_SECONDS-0.5  # PRESET time of day
	check(w.step(1.0,true),"World tick across midnight succeeds (news %s)"%label)
	await refresh()
	news_same_modal(page,"midnight "+label)
	lines=news_matches("midnight "+label)
	var till:=int(own().get("till",0))
	check(lines.size()==5,"Settled card has 5 lines (%s): %s"%[label,str(lines)])
	if lines.size()==5:
		check(str(lines[3]).contains("上一輪結算・第") and str(lines[3]).begins_with("上一輪結算・第 %d 日"%(day_before+1)),"Report line (%s): %s"%[label,str(lines[3])])
		check(str(lines[4]).begins_with("賣出："),"Sold line starts with 賣出： (%s): %s"%[label,str(lines[4])])
		check(till>0 and str(lines[2]).begins_with("待領營收 %d 鈴幣"%till) and str(lines[2]).ends_with("（到攤位領取）"),"Money line shows the till and （到攤位領取） (%s): till=%d %s"%[label,till,str(lines[2])])
	await news_fit("report "+label)
	# Collect at the stall, then reopen the page: the hint is gone.
	if await open_by_key("news collect "+label):
		if await press("MarketCollect","news "+label):
			check(int(own().get("till",-1))==0,"領取 empties the till (news %s)"%label)
	if await open_news("collected "+label):
		lines=news_matches("collected "+label)
		check(lines.size()==5 and str(lines[2]).begins_with("待領營收 0 鈴幣") and not str(lines[2]).ends_with("（到攤位領取）"),"Money line without （到攤位領取） after collecting (%s): %s"%[label,str(lines)])
		await news_fit("collected "+label)
	await close_news()

func run()->void:
	create_timer(115.0).timeout.connect(func():
		check(false,"Watchdog: suite exceeded 115 s")
		finish())
	var started:=Time.get_ticks_msec()
	path=OS.get_environment("TEMP").path_join("market-stall-ui-%s.json"%Crypto.new().generate_random_bytes(8).hex_encode())
	app=preload("res://main.tscn").instantiate();app.village_art_preview=true;root.add_child(app)
	app.set_process(false);app.session.set_physics_process(false)
	if app.session.host(0,"市集旅人",path)!=OK:check(false,"Host starts");finish();return
	await settle()
	w=app.session.world;id=app.session.profile.token
	if not app.playing:note("app.playing was false after host; set true for key input");app.playing=true
	choose_picks()
	for size in [Vector2i(1024,640),Vector2i(1280,800)]:
		root.size=size
		var tag:="%dx%d"%[size.x,size.y]
		await locked_flow(tag)
		await main_flow(tag)
		await news_flow(tag)
		note("size %s done at %.1f s"%[tag,(Time.get_ticks_msec()-started)/1000.0])
	app.session.shutdown();await create_timer(0.3).timeout
	app.queue_free();await process_frame;await process_frame
	for suffix in ["",".bak",".writer-lock"]:DirAccess.remove_absolute(path+suffix)
	finish()
