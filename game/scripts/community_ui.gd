extends RefCounted
## 渡口的共餐桌頁（共餐桌旁按互動鍵）。
##
## 版面（由上而下）：今日餐點與米露的一句話 → 三道共享菜（火鍋一列；西瓜盤與玉米濃湯並排一列）→
## 「保溫底座」卡（T067 暖岩片，table_warmer.gd）→「茶陶上桌」卡（第 40 章，tea_service.gd）→
## 其他入口（來信、訂單、風鈴接力、公共廚房）。
## 茶陶上桌卡刻意壓成三列以便 1024×640 不必捲動：標題列（圖、名稱、狀態小牌、按鈕）→
## 一句狀態＋規則／出借人說明＋免責聲明 → 擋住的原因（紅字；全部來自 tea_service 的常數）。
## 茶陶上桌的按鈕列只有在桌上已有茶陶組、或「擺上茶陶組」可以按時才加入方向鍵導覽。
## 結構只建一次，之後 refresh() 依快照原地更新文字與按鈕（不重建、不移動），
## 所以按下按鈕後焦點留在原處；按鈕被隱藏時（例如加裝完成）焦點移到下一個可用的動作。
## 所有動作都經 app.session.perform 送到伺服器（與先前上桌／領取相同的路徑），
## 伺服器回覆由 main._notice 寫進頁底的 modal_feedback（以及非預覽版面的提示列）。
## 份數一律用 table_warmer.round_total（保溫一輪 6 份，一般 4 份）。
const Art=preload("res://scripts/life_ui_theme.gd")
const Shell=preload("res://scripts/life_ui_shell.gd")
const Items=preload("res://scripts/inventory_item_art.gd")
const Pixel=preload("res://scripts/inventory_pixel_theme.gd")
const World=preload("res://scripts/world.gd")
const KitchenUI=preload("res://scripts/public_kitchen_ui.gd")
const Warmer=preload("res://scripts/table_warmer.gd")
const TeaService=preload("res://scripts/tea_service.gd")
const TeaArt=preload("res://scripts/tea_revisit_art.gd")

const LAYOUT:="community_table"
const TITLE:="渡口的共餐桌"
const INK:=Color("3d422d")
const MUTED:=Color("7a6f58")
const WARN:=Color("9c4b32")
const GOOD:=Color("3e664b")

const PLAIN_SERVE:="上桌四份"
const CLAIM:="領一份"
const WARM_SERVE:="保溫上桌六份"
const INSTALL:="加裝保溫底座"
const WARMER_RULE:="在桌下鋪一層暖岩片，火鍋就能保溫：一次端上六份，大家各領一份。全島共用，裝一次就好。"
const WARMER_SOURCE:="暖岩片：金瓜石合作礦場第 12、13 層敲礦時另得。"
const WARMER_DONE:="桌下的暖岩片讓火鍋一直熱著，可以用「保溫上桌六份」一次端上六份。"
const STATUS_OPEN:="尚未加裝"
const STATUS_DONE:="已加裝"
const DISH_ORDER:=["hotpot","watermelon","chowder"]
const TEA_PLACE:="擺上茶陶組"
const TEA_BREW:={"light":"泡淺焙茶","deep":"泡深焙茶"}
const TEA_SIP:="喝一杯"
const TEA_TAKE:="收回茶陶組"
const TEA_RULE:="借一組茶陶組給共餐桌，帶焙茶來泡一壺，六人各喝一杯。"
const TEA_OWN_NOTE:="這組茶陶組是你借出的。"
const TEA_OTHER_NOTE:="這組茶陶組是別的島民借出的。"
const TEA_CHIP_NONE:="未擺上"
const TEA_CHIP_EMPTY:="空壺"
const TEA_CHIP_DONE:="喝完了"
const TEA_CHIP_COLD:="茶涼了"
const TEA_ROW:=["TeaPlace","TeaBrew_light","TeaBrew_deep","TeaSip","TeaTake"]
const TEA_PREFERRED:=["TeaSip","TeaBrew_light","TeaBrew_deep","TeaPlace"]

static func open(app) -> void:
	var snapshot:Dictionary=app.session.snapshot
	if not snapshot.get("picnic",false):return
	var body:VBoxContainer=app._open_modal(TITLE)
	app.modal.set_meta("life_modal_layout",LAYOUT)
	app.modal.set_meta("community_body",body)
	body.add_theme_constant_override("separation",8)
	build(app,body)
	refresh(app)
	app._layout_preview.call_deferred()
	focus_first.call_deferred(app)

static func is_open(app) -> bool:
	return is_instance_valid(app.modal) and app.modal.has_meta("community_body")

## main._layout_preview: bottom-anchored like before, as tall as its content.
## 860 wide (was 760) so the 茶陶上桌 title row holds all four tea buttons on one line,
## and up to bounds.y-16 tall (was -40) so the page still needs no scrolling at 1024×640
## with an un-installed 保溫底座 card plus the 茶陶上桌 card (top edge never above 8 px).
static func layout(app,bounds:Vector2) -> void:
	var modal:Control=app.modal
	var width:=minf(860,bounds.x-48)
	var cap:=bounds.y-16
	modal.size.x=width
	var height:=minf(cap,560)
	var outer:=modal.find_child("ModalScroll",true,false) as Control
	var content:=modal.find_child("ModalContent",true,false) as Control
	if outer!=null and content!=null:
		var chrome:float=modal.get_combined_minimum_size().y-outer.get_combined_minimum_size().y
		height=minf(cap,chrome+content.get_combined_minimum_size().y+2)
	modal.size=Vector2(width,height)
	modal.position=Vector2(floorf((bounds.x-modal.size.x)/2),maxf(8.0,floorf(bounds.y-modal.size.y-28)))

# ---------------------------------------------------------------- structure --

static func _text(app,parent:Node,value:String,size:int,color:Color=INK) -> Label:
	var l:Label=app.label(value,size)
	l.autowrap_mode=TextServer.AUTOWRAP_OFF
	l.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color",color)
	parent.add_child(l)
	return l

static func _wrapped(app,parent:Node,value:String,size:int,color:Color=INK) -> Label:
	var l:Label=app.label(value,size)
	l.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	l.add_theme_color_override("font_color",color)
	parent.add_child(l)
	return l

static func _button(app,parent:Node,id:String,title:String,callback:Callable) -> Button:
	var b:Button=app.button(title,callback)
	b.name=id
	b.focus_mode=Control.FOCUS_ALL
	b.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	b.custom_minimum_size=Vector2(0,34)
	b.add_theme_font_size_override("font_size",15)
	parent.add_child(b)
	return b

static func _paper(parent:Node,id:String) -> PanelContainer:
	var card:=PanelContainer.new()
	card.name=id
	card.add_theme_stylebox_override("panel",Pixel.paper_style())
	card.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	parent.add_child(card)
	return card

static func build(app,body:VBoxContainer) -> void:
	var snapshot:Dictionary=app.session.snapshot
	# Today's spread and 米露's line.
	var table:=_paper(body,"CommunityTable")
	var place:=HBoxContainer.new()
	place.add_theme_constant_override("separation",10)
	table.add_child(place)
	place.add_child(Shell.picture(Art.icon("milu"),48))
	var words:=VBoxContainer.new()
	words.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	words.add_theme_constant_override("separation",2)
	place.add_child(words)
	var meal:=HBoxContainer.new()
	meal.add_theme_constant_override("separation",6)
	words.add_child(meal)
	meal.add_child(Shell.picture(Items.icon("soup"),28))
	meal.add_child(Shell.picture(Items.icon("bread"),28))
	_text(app,meal,"蘿蔔湯與麵包已上桌",16).name="CommunityMenu"
	var line:="湯還暖著。坐一會兒吧，今天有大家一起做的飯。"
	if snapshot.get("chapter_one",{}).get("watered",false):
		line="田裡有水，桌上有飯。下次也一起留個位子吧。"
	_wrapped(app,words,"米露　「"+line+"」",15).name="CommunityQuote"
	# Shared dishes.
	var servings:=VBoxContainer.new()
	servings.name="CommunityServings"
	servings.add_theme_constant_override("separation",4)
	body.add_child(servings)
	# 火鍋自己一列（右邊還有「保溫上桌六份」）；西瓜盤與玉米濃湯並排在第二列（DishPair），
	# 這樣 1024×640 仍不必捲動。
	var pair:=HBoxContainer.new()
	pair.name="DishPair"
	pair.add_theme_constant_override("separation",16)
	for dish:String in DISH_ORDER:
		var item:String=World.COMMUNITY.DISHES[dish]
		var row:=HBoxContainer.new()
		row.name="Dish_"+dish
		row.add_theme_constant_override("separation",8)
		row.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		if dish=="hotpot":
			servings.add_child(row)
			servings.add_child(pair)
		else:pair.add_child(row)
		var icon:=Shell.picture(Items.icon(item),32)
		icon.name="DishIcon_"+dish
		row.add_child(icon)
		var text:=_text(app,row,"",16)
		text.name="DishText_"+dish
		text.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		_button(app,row,"DishMain_"+dish,PLAIN_SERVE,func():_dish_main(app,dish))
		if dish=="hotpot":_button(app,row,"HotpotWarm",WARM_SERVE,func():_send(app,Warmer.SERVE_ACTION))
	# 保溫底座 (T067).
	var card:=_paper(body,"WarmerCard")
	var inner:=VBoxContainer.new()
	inner.add_theme_constant_override("separation",3)
	card.add_child(inner)
	var head:=HBoxContainer.new()
	head.add_theme_constant_override("separation",8)
	inner.add_child(head)
	var icon:=Shell.picture(Items.icon(Warmer.ITEM),32)
	icon.name="WarmerIcon"
	head.add_child(icon)
	_text(app,head,Warmer.NAME,17).name="WarmerTitle"
	var status:=_text(app,head,STATUS_OPEN,15,MUTED)
	status.name="WarmerStatus"
	status.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	status.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	_wrapped(app,inner,WARMER_RULE,14,INK).name="WarmerRule"
	var materials:=HBoxContainer.new()
	materials.name="WarmerMaterials"
	materials.add_theme_constant_override("separation",10)
	inner.add_child(materials)
	for item:String in Warmer.COST_ORDER:
		var chip:=HBoxContainer.new()
		chip.name="WarmerChip_"+item
		chip.add_theme_constant_override("separation",4)
		materials.add_child(chip)
		var picture:=Shell.picture(Items.icon(item),28)
		picture.name="WarmerMatIcon_"+item
		chip.add_child(picture)
		_text(app,chip,"",15).name="WarmerMat_"+item
	var gap:=Control.new()
	gap.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	materials.add_child(gap)
	_button(app,materials,"WarmerInstall",INSTALL,func():_send(app,Warmer.INSTALL_ACTION))
	_wrapped(app,inner,WARMER_SOURCE,13,MUTED).name="WarmerSource"
	_wrapped(app,inner,"",13,WARN).name="WarmerReason"
	# 茶陶上桌 (第 40 章): title row with the actions, one info line, one reason line.
	var tea:=_paper(body,"TeaCard")
	var tea_inner:=VBoxContainer.new()
	tea_inner.add_theme_constant_override("separation",3)
	tea.add_child(tea_inner)
	var tea_head:=HBoxContainer.new()
	tea_head.name="TeaHead"
	tea_head.add_theme_constant_override("separation",8)
	tea_inner.add_child(tea_head)
	var tea_icon:=Shell.picture(TeaArt.teaware_texture(),32)
	tea_icon.name="TeaIcon"
	tea_head.add_child(tea_icon)
	_text(app,tea_head,TeaService.NAME,17).name="TeaTitle"
	_text(app,tea_head,TEA_CHIP_NONE,14,MUTED).name="TeaChip"
	var tea_gap:=Control.new()
	tea_gap.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	tea_head.add_child(tea_gap)
	_button(app,tea_head,"TeaPlace",TEA_PLACE,func():_send(app,TeaService.PLACE_ACTION))
	for style:String in TeaService.STYLES:
		_button(app,tea_head,"TeaBrew_"+style,str(TEA_BREW[style]),func():_send(app,TeaService.BREW_ACTION,style))
	_button(app,tea_head,"TeaSip",TEA_SIP,func():_send(app,TeaService.SIP_ACTION))
	_button(app,tea_head,"TeaTake",TEA_TAKE,func():_send(app,TeaService.TAKE_ACTION))
	var tea_info:=HBoxContainer.new()
	tea_info.name="TeaInfo"
	tea_info.add_theme_constant_override("separation",8)
	tea_inner.add_child(tea_info)
	_text(app,tea_info,"",13).name="TeaStatus"
	_wrapped(app,tea_info,TEA_RULE,13,INK).name="TeaNote"
	_text(app,tea_info,TeaService.DISCLAIMER,12,MUTED).name="TeaDisclaimer"
	_wrapped(app,tea_inner,"",13,WARN).name="TeaReason"
	# Other routes from the table.
	var actions:=HBoxContainer.new()
	actions.name="CommunityRoutes"
	body.add_child(actions)
	for entry in [["letter","渡口來信",app._chapter_menu],["journal","生活訂單",app._orders_menu],["bell","風鈴接力",app._festival_menu]]:
		var button:Button=app.button(entry[1],entry[2])
		button.name="Route_"+str(entry[0])
		button.icon=Shell.icon(entry[0])
		button.focus_mode=Control.FOCUS_ALL
		actions.add_child(button)
	# Public kitchen (Q04/T042): opens its own two-page scrapbook; nothing is sent here.
	var kitchen:Button=app.button("公共廚房",func():KitchenUI.open(app,"kitchen"))
	kitchen.name="KitchenEntry"
	kitchen.icon=KitchenUI.stove_icon()
	kitchen.expand_icon=true
	kitchen.add_theme_constant_override("icon_max_width",24)
	kitchen.tooltip_text="將自己的小石灶與兩張長椅永久捐作公用、一起備餐，或重看共餐記憶"
	kitchen.focus_mode=Control.FOCUS_ALL
	actions.add_child(kitchen)

# ------------------------------------------------------------------ actions --

static func _cell(app) -> Vector2i:
	return World.COMMUNITY.table_cell(app.session.snapshot)

static func _send(app,action:String,extra:String="") -> void:
	var cell:=_cell(app)
	if cell==World.COMMUNITY.NO_CELL:return
	app.session.perform(action,cell,extra)

static func _dish_main(app,dish:String) -> void:
	var meal:=_meal(app.session.snapshot,dish)
	_send(app,("claim_" if int(meal.get("portions",0))>0 else "serve_")+dish)

# ------------------------------------------------------------------ updates --

static func _meal(snapshot:Dictionary,dish:String) -> Dictionary:
	var community:Variant=snapshot.get("community",{})
	if not community is Dictionary:return {}
	var meal:Variant=community.get(dish,{})
	return meal if meal is Dictionary else {}

static func _inventory(app) -> Dictionary:
	var person:Variant=app.session.snapshot.get("players",{}).get(app.session.own_id,{})
	if not person is Dictionary:return {}
	var inventory:Variant=person.get("inventory",{})
	return inventory if inventory is Dictionary else {}

static func portion_text(dish:String,meal:Dictionary,held:int) -> String:
	var name:String=World.NAMES[World.COMMUNITY.DISHES[dish]]
	var portions:=int(meal.get("portions",0))
	if portions<=0:return "%s · 還沒上桌・背包 %d 份"%[name,held]
	var text:="%s · 剩 %d / %d 份"%[name,portions,Warmer.round_total(meal)]
	if bool(meal.get("claimed_own",false)):text+="・你已領過"
	return text

## Short state for the 茶陶上桌 chip: 未擺上 / 空壺 / 淺焙茶 4／6 杯 / 喝完了 / 茶涼了
## (cups still in the pot but brewed on an earlier world day — tea_service.current_round).
static func tea_chip(snapshot:Dictionary) -> String:
	if not TeaService.placed(snapshot):return TEA_CHIP_NONE
	var now:Dictionary=TeaService.current_round(snapshot)
	if now.is_empty():return TEA_CHIP_EMPTY
	if int(now.get("left",0))<=0:return TEA_CHIP_DONE
	if tea_cold(snapshot):return TEA_CHIP_COLD
	return "%s %d／%d 杯"%[TeaService.style_name(str(now.get("style",""))),int(now.get("portions",0)),TeaService.CUPS]

## Cold tea still in the pot (current_round.cold with left > 0).
static func tea_cold(snapshot:Dictionary) -> bool:
	var now:Dictionary=TeaService.current_round(snapshot)
	return now.get("cold",false)==true and int(now.get("left",0))>0

## Every distinct reason a visible tea button is disabled, in button order (module texts).
static func tea_reasons(snapshot:Dictionary,inventory:Dictionary) -> String:
	var list:Array=[]
	if not TeaService.placed(snapshot):
		list.append(TeaService.place_block(snapshot,inventory))
	else:
		for style:String in TeaService.STYLES:list.append(TeaService.brew_block(snapshot,style,inventory))
		list.append(TeaService.sip_block(snapshot))
		if TeaService.lender_own(snapshot):list.append(TeaService.take_block(snapshot,inventory))
	var found:=PackedStringArray()
	for value:Variant in list:
		var reason:=str(value)
		if not reason.is_empty() and not found.has(reason):found.append(reason)
	return "　".join(found)

static func tea_held(inventory:Dictionary,style:String) -> int:
	var value:Variant=inventory.get(TeaService.TEA_ITEMS[style],0)
	return int(value) if (value is int or value is float) else 0

static func _node(app,id:String) -> Control:
	if not is_open(app):return null
	return (app.modal.get_meta("community_body") as Node).find_child(id,true,false) as Control

static func refresh(app) -> void:
	if not is_open(app):return
	var s:Dictionary=app.session.snapshot
	var inventory:=_inventory(app)
	var installed:=Warmer.installed(s)
	var cell:=World.COMMUNITY.table_cell(s)
	var signature:=JSON.stringify([installed,cell,_meal(s,"hotpot"),_meal(s,"watermelon"),_meal(s,"chowder"),inventory,s.get("picnic",false),s.get(TeaService.STATE_KEY,{}),TeaService.TEA_REVISIT.completed(s),TeaService.today(s)])
	if str(app.modal.get_meta("community_signature",""))==signature:return
	app.modal.set_meta("community_signature",signature)
	var focus_before:=_focus_owner(app)
	var focus_was_enabled:=focus_before is BaseButton and not (focus_before as BaseButton).disabled
	(_node(app,"CommunityServings") as Control).visible=cell!=World.COMMUNITY.NO_CELL
	for dish:String in DISH_ORDER:
		var item:String=World.COMMUNITY.DISHES[dish]
		var meal:=_meal(s,dish)
		var portions:=int(meal.get("portions",0))
		var held:=int(inventory.get(item,0))
		(_node(app,"DishText_"+dish) as Label).text=portion_text(dish,meal,held)
		var main:=_node(app,"DishMain_"+dish) as Button
		if portions>0:
			main.text=CLAIM
			main.disabled=bool(meal.get("claimed_own",false))
			main.tooltip_text="這一輪你已經領過了" if main.disabled else "從桌上領一份%s"%World.NAMES[item]
		else:
			main.text=PLAIN_SERVE
			main.disabled=held<World.COMMUNITY.HOTPOT_PORTIONS
			main.tooltip_text=("需要 %d 份%s才能上桌"%[World.COMMUNITY.HOTPOT_PORTIONS,World.NAMES[item]]) if main.disabled else "端上四份%s"%World.NAMES[item]
	var warm:=_node(app,"HotpotWarm") as Button
	var serve_reason:=Warmer.serve_block(s,inventory)
	warm.visible=installed
	warm.disabled=not serve_reason.is_empty()
	warm.tooltip_text=serve_reason if not serve_reason.is_empty() else "用 %d 份雪點鱒魚火鍋保溫上桌"%Warmer.WARM_PORTIONS
	# Warmer card.
	var status:=_node(app,"WarmerStatus") as Label
	status.text=STATUS_DONE if installed else STATUS_OPEN
	status.add_theme_color_override("font_color",GOOD if installed else MUTED)
	(_node(app,"WarmerRule") as Label).text=WARMER_DONE if installed else WARMER_RULE
	(_node(app,"WarmerMaterials") as Control).visible=not installed
	(_node(app,"WarmerSource") as Control).visible=not installed
	for row:Dictionary in Warmer.materials(inventory):
		var l:=_node(app,"WarmerMat_"+str(row.item)) as Label
		l.text="%s %d／%d"%[str(row.name),int(row.have),int(row.need)]
		l.add_theme_color_override("font_color",GOOD if int(row.short)==0 else WARN)
	var install_reason:=Warmer.install_block(s,inventory)
	var install:=_node(app,"WarmerInstall") as Button
	install.disabled=not install_reason.is_empty()
	install.tooltip_text=install_reason if not install_reason.is_empty() else "用暖岩片 6、銅接頭 2、石材 4 替共餐桌加裝保溫底座"
	var reason:=_node(app,"WarmerReason") as Label
	reason.text=serve_reason if installed else install_reason
	reason.visible=not reason.text.is_empty()
	_refresh_tea(app,s,inventory)
	link_focus(app)
	_restore_focus(app,focus_before,focus_was_enabled)
	app._layout_preview.call_deferred()

## 茶陶上桌 card from the client snapshot (token "": the module reads lender_own /
## sipped_own that Session adds for the recipient).
static func _refresh_tea(app,s:Dictionary,inventory:Dictionary) -> void:
	var tea_placed:=TeaService.placed(s)
	var own:=TeaService.lender_own(s)
	var chip:=_node(app,"TeaChip") as Label
	chip.text=tea_chip(s)
	chip.add_theme_color_override("font_color",GOOD if TeaService.portions(s)>0 else (WARN if tea_cold(s) else MUTED))
	(_node(app,"TeaStatus") as Label).text=TeaService.status_text(s)
	(_node(app,"TeaNote") as Label).text=TEA_RULE if not tea_placed else (TEA_OWN_NOTE if own else TEA_OTHER_NOTE)
	var place_reason:=TeaService.place_block(s,inventory)
	var place:=_node(app,"TeaPlace") as Button
	place.visible=not tea_placed
	place.disabled=not place_reason.is_empty()
	place.tooltip_text=place_reason if not place_reason.is_empty() else "把背包裡的一組茶陶組借給共餐桌"
	for style:String in TeaService.STYLES:
		var brew:=_node(app,"TeaBrew_"+style) as Button
		var why:=TeaService.brew_block(s,style,inventory)
		brew.visible=tea_placed
		brew.text="%s・有 %d"%[str(TEA_BREW[style]),tea_held(inventory,style)]
		brew.disabled=not why.is_empty()
		brew.tooltip_text=why if not why.is_empty() else "用 1 份%s泡一壺，分成 %d 杯"%[TeaService.style_name(style),TeaService.CUPS]
	var sip_reason:=TeaService.sip_block(s)
	var sip:=_node(app,"TeaSip") as Button
	sip.visible=tea_placed
	sip.disabled=not sip_reason.is_empty()
	sip.tooltip_text=sip_reason if not sip_reason.is_empty() else "從壺裡倒一杯來喝"
	var take_reason:=TeaService.take_block(s,inventory)
	var take:=_node(app,"TeaTake") as Button
	take.visible=tea_placed and own
	take.disabled=not take_reason.is_empty()
	take.tooltip_text=take_reason if not take_reason.is_empty() else "把茶陶組收回背包"
	var reason:=_node(app,"TeaReason") as Label
	reason.text=tea_reasons(s,inventory)
	reason.visible=not reason.text.is_empty()

# -------------------------------------------------------------------- focus --

static func close_button(app) -> BaseButton:
	if not is_instance_valid(app.modal):return null
	var body:Control=app.modal.get_meta("community_body") if app.modal.has_meta("community_body") else null
	for node in app.modal.find_children("*","BaseButton",true,false):
		if body!=null and body.is_ancestor_of(node):continue
		return node as BaseButton
	return null

static func _shown(c:Control) -> bool:
	var node:Node=c
	while node!=null and node is Control:
		if not (node as Control).visible:return false
		if node.has_meta("community_body"):break
		node=node.get_parent()
	return true

## The 茶陶上桌 row joins arrow-key navigation once a set is on the table (then its
## disabled buttons stay, as elsewhere) or while 擺上茶陶組 can be pressed; a lone
## disabled 擺上茶陶組 (reason shown in red under it) is skipped.
static func _tea_navigable(app) -> bool:
	var place:=_node(app,"TeaPlace") as Button
	return place!=null and (not _shown(place) or not place.disabled)

## Visible buttons in navigation rows (disabled ones stay so focus never jumps).
static func focus_rows(app) -> Array:
	var rows:Array=[]
	var names:=[["DishMain_hotpot","HotpotWarm"],["DishMain_watermelon","DishMain_chowder"],["WarmerInstall"]]
	if _tea_navigable(app):names.append(TEA_ROW)
	names.append(["Route_letter","Route_journal","Route_bell","KitchenEntry"])
	for group:Array in names:
		var row:Array[Button]=[]
		for id:String in group:
			var b:=_node(app,id) as Button
			if b!=null and _shown(b):row.append(b)
		if not row.is_empty():rows.append(row)
	return rows

static func link_focus(app) -> void:
	var rows:=focus_rows(app)
	var close:=close_button(app)
	var flat:Array[Button]=[]
	for row:Array in rows:
		for b:Button in row:flat.append(b)
	for r in rows.size():
		var row:Array=rows[r]
		for i in row.size():
			var b:Button=row[i]
			b.focus_neighbor_left=b.get_path_to(row[(i-1+row.size())%row.size()])
			b.focus_neighbor_right=b.get_path_to(row[(i+1)%row.size()])
			if r>0:b.focus_neighbor_top=b.get_path_to(rows[r-1][mini(i,rows[r-1].size()-1)])
			elif close!=null:b.focus_neighbor_top=b.get_path_to(close)
			b.focus_neighbor_bottom=b.get_path_to(rows[r+1][mini(i,rows[r+1].size()-1)] if r+1<rows.size() else b)
			var at:=flat.find(b)
			b.focus_next=b.get_path_to(flat[(at+1)%flat.size()])
			b.focus_previous=b.get_path_to(flat[(at-1+flat.size())%flat.size()])
	if close!=null and not flat.is_empty():
		close.focus_neighbor_bottom=close.get_path_to(flat[0])
		close.focus_neighbor_top=close.get_path_to(flat[flat.size()-1])

static func _focus_owner(app) -> Control:
	if not is_open(app):return null
	var owner:=(app.modal as Control).get_viewport().gui_get_focus_owner()
	if owner==null or not (app.modal as Node).is_ancestor_of(owner):return null
	return owner

## First enabled table action (warm serve, plain serve / claim, watermelon, install,
## tea sip / brew / place — never 收回茶陶組), else the first route.
static func preferred(app) -> Button:
	for id:String in ["HotpotWarm","DishMain_hotpot","DishMain_watermelon","DishMain_chowder","WarmerInstall"]+TEA_PREFERRED:
		var b:=_node(app,id) as Button
		if b!=null and _shown(b) and not b.disabled:return b
	return _node(app,"Route_letter") as Button

## Where focus goes when a tea button it was on disappears: the first enabled tea
## action (not 收回), else the first visible button of the tea row, else preferred().
static func _tea_preferred(app) -> Button:
	for id:String in TEA_PREFERRED:
		var b:=_node(app,id) as Button
		if b!=null and _shown(b) and not b.disabled:return b
	if _tea_navigable(app):
		for id:String in TEA_ROW:
			var b:=_node(app,id) as Button
			if b!=null and _shown(b):return b
	return preferred(app)

static func focus_first(app) -> void:
	if not is_open(app):return
	var b:=preferred(app)
	if b!=null and b.is_visible_in_tree():b.grab_focus()

## After an update: a hidden focus owner (e.g. 加裝 once installed) moves to the next
## table action; a warm serve that just went out moves to 領一份. In the tea card a
## hidden button (擺上 after placing, the brew / sip / 收回 row after taking the set
## back) moves to the next tea action, and a brew that just went out moves to 喝一杯.
static func _restore_focus(app,before:Control,was_enabled:bool=true) -> void:
	if before==null:return
	var tea:=is_instance_valid(before) and TEA_ROW.has(str(before.name))
	if not is_instance_valid(before) or not _shown(before) or (tea and not _tea_navigable(app)):
		var next:=_tea_preferred(app) if tea else preferred(app)
		if next!=null:next.grab_focus.call_deferred()
		return
	if before.name=="HotpotWarm" and (before as Button).disabled:
		var claim:=_node(app,"DishMain_hotpot") as Button
		if claim!=null and _shown(claim) and not claim.disabled:claim.grab_focus.call_deferred()
	if was_enabled and str(before.name).begins_with("TeaBrew_") and (before as Button).disabled:
		var sip:=_node(app,"TeaSip") as Button
		if sip!=null and _shown(sip) and not sip.disabled:sip.grab_focus.call_deferred()
