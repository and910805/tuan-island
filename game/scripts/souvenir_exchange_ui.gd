extends RefCounted
## T071 「紀念品交換攤」 client: the booth in the world (art, label, interaction point)
## and the exchange page. Rules live in souvenir_exchange.gd; this file only reads
## snapshot.own_souvenir (my balances and catalogue) and the home snapshot (booth
## cell via World.souvenir_cell). The only action is
## Session.perform("souvenir_redeem", own_souvenir.point, entry.extra); the server
## reply reaches app.modal_feedback / the toast via app._notice like the sibling
## activity pages (harvest_relay_ui.gd / fishing_meet_ui.gd / showcase_ui.gd).
##
## Booth: drawn at home after the 渡口野餐 on the active cell (37,25 → 35,26 → 39,24),
## hidden before the picnic and while paused (all three cells occupied). Program-drawn
## 48×56 stall (souvenir_art.booth(): navy-and-gold awning, bunting, three tiny
## souvenirs, a yellow ticket on the counter) — clearly different from the green-and-
## cream 市集攤位 five tiles south and 小栗's red-and-cream shop. World label 「紀念品交換攤」, focused
## 「兌換紀念品」 + the interact-key badge. Interaction point order in
## main._interact / world_view.interaction_focus: existing residents → walk-up
## residents → market → harvest → fishing meet → showcase sign → this booth → objects.
##
## Page layout (no outer scrolling at 1024×640 / 1280×800 with all seven entries):
##   rule line;
##   four group rows — 豐收接力 / 河岸釣魚會 / 家園布置題 (balance column: 剩 N 張,
##   獲得 E・已用 S, then that activity's two entries) and 三活動 (the mixed entry);
##   each entry card: 32px icon, name, 背包・已擺・換過 counts, blurb, cost text, a state
##   line (票數足夠 / 還差 …) and the 兌換 button;
##   blocker line (wrong region / paused / too far), the paused cells to clear, and the
##   one-line placing hint (build folio → 「生活」).
## The page is built once per lock state and then updated in place, so after a
## redemption nothing moves and keyboard focus stays on the pressed 兌換 button (disabled
## 兌換 buttons stay focusable so the focus never jumps; their tooltip and the card's
## state line give the reason). Focus grid: left/right inside a group row, up/down
## between rows (column clamped), up from the first row reaches 「關閉」; controller
## d-pad uses the same neighbours through main._controller_menu_direction.
const World=preload("res://scripts/world.gd")
const Souv=preload("res://scripts/souvenir_exchange.gd")
const Art=preload("res://scripts/souvenir_art.gd")
const HarvestUI=preload("res://scripts/harvest_relay_ui.gd")
const Shell=preload("res://scripts/life_ui_shell.gd")
const Pixel=preload("res://scripts/inventory_pixel_theme.gd")
const TITLE:="紀念品交換攤"
const POINT:="souvenir:booth"
const LAYOUT:="souvenir_exchange"
const NO_CELL:=Vector2i(-1,-1)
const RULE:="用三種合作活動得到的紀念票換家園裝飾。三種票各自計算、不能互換；兌換後不退票，同一件可以重複兌換。"
const PLACE_HINT:="換到的裝飾放進背包：按 %s 打開家園工坊，在「生活」分頁選它擺到家園（不擋路，拆除會收回背包）。"
const WALK:="請走到紀念品交換攤前（3 格內）再兌換。"
const ENTRY_OPEN:="紀念品交換攤（廣場北邊）"
const ENTRY_LOCKED:="紀念品交換攤・渡口野餐後開放"
const GROUPS:=[["harvest_relay",["veg_basket_rack","relay_crate_stack"]],["fish_meet",["carp_banner","float_garland"]],["showcase",["lantern_post","flower_arch"]],["trio",["trio_keepsake"]]]
const INK:=Color("3d422d")
const MUTED:=Color("7a6f58")
const WARN:=Color("9c4b32")
const GOOD:=Color("3e664b")
const GROUP_WIDTH:=150
## Booth sprite offset from its cell's top-left and size (world px, unzoomed).
const BOOTH_OFFSET:=Vector2(-8,-24)
const BOOTH_SIZE:=Vector2(48,56)

# ------------------------------------------------------------------ state --

static func own(s:Dictionary)->Dictionary:
	var found:Variant=s.get("own_souvenir",{})
	return found if found is Dictionary else {}

static func at_home(s:Dictionary)->bool:
	return str(s.get("region_id","home"))=="home"

## Active booth cell in this (home) snapshot; NO_CELL before the picnic, while paused
## and outside home.
static func booth_cell(s:Dictionary)->Vector2i:
	return World.souvenir_cell(s) if at_home(s) else NO_CELL

static func booth_shown(s:Dictionary)->bool:
	return booth_cell(s)!=NO_CELL

static func near_booth(s:Dictionary,id:String)->bool:
	var cell:=booth_cell(s)
	if cell==NO_CELL:return false
	var person:Variant=s.get("players",{}).get(id)
	if not person is Dictionary:return false
	return Vector2(float(person.get("x",0.0)),float(person.get("y",0.0))).distance_to(Vector2(cell)+Vector2(0.5,0.5))<=Souv.REACH

## World label of the booth: the short name, or what the interact key does.
static func booth_title(focused:bool)->String:
	return "兌換紀念品" if focused else TITLE

static func entry_caption(unlocked:bool)->String:
	return ENTRY_OPEN if unlocked else ENTRY_LOCKED

static func short_text(short:Dictionary)->String:
	var parts:=PackedStringArray()
	for activity:String in Souv.ACTIVITIES:
		if short.has(activity):parts.append("%s %d"%[Souv.ACTIVITY_NAMES[activity],int(short[activity])])
	return "還差 "+"、".join(parts)+" 張" if not parts.is_empty() else ""

static func counts_text(entry:Dictionary)->String:
	return "背包 %d・已擺 %d・換過 %d"%[int(entry.get("held",0)),int(entry.get("placed",0)),int(entry.get("redeemed",0))]

## Page-wide reason every 兌換 button shares ("" when none).
static func blocker(s:Dictionary,id:String,m:Dictionary)->String:
	if not at_home(s):return Souv.WRONG_REGION
	if not bool(m.get("can_redeem",false)):return Souv.NO_POINT
	if not near_booth(s,id):return WALK
	return ""

## Why this entry's 兌換 button is disabled ("" = enabled).
static func entry_reason(entry:Dictionary,page_reason:String)->String:
	var short:Variant=entry.get("short",{})
	if short is Dictionary and not (short as Dictionary).is_empty():return short_text(short)
	if int(entry.get("redeemed",0))>=Souv.MAX_REDEEMED:return Souv.LIMIT
	return page_reason

static func blocked_text()->String:
	var names:=PackedStringArray()
	for cell:Vector2i in Souv.CANDIDATES:names.append("(%d,%d)"%[cell.x,cell.y])
	return "需要清理的格子：%s（三格任一格空出來即可）。拿走上面的物件、地板、屋頂、作物或樹，交換攤就會回來。"%"、".join(names)

# -------------------------------------------------------------------- art --

static func booth_rect(view,cell:Vector2i)->Rect2:
	return Rect2(view.screen(Vector2(cell))+BOOTH_OFFSET,BOOTH_SIZE)

static func draw_booth(view,at:Vector2)->void:
	view.draw_texture(Art.booth(),at+BOOTH_OFFSET)

# ---------------------------------------------------------------- actions --

static func redeem(app,entry_id:String)->void:
	var m:=own(app.session.snapshot)
	for entry:Dictionary in entries(m):
		if str(entry.get("id",""))==entry_id:
			app.session.perform("souvenir_redeem",m.get("point",NO_CELL),str(entry.get("extra","")))
			return

static func entries(m:Dictionary)->Array:
	var found:Variant=m.get("entries",[])
	return found if found is Array else []

static func entry_of(m:Dictionary,entry_id:String)->Dictionary:
	for entry:Variant in entries(m):
		if entry is Dictionary and str(entry.get("id",""))==entry_id:return entry
	return {}

static func activity_of(m:Dictionary,activity:String)->Dictionary:
	var found:Variant=m.get("activities",[])
	if found is Array:
		for row:Variant in found:
			if row is Dictionary and str(row.get("id",""))==activity:return row
	return {}

# ---------------------------------------------------------------- panel --

static func open(app)->void:
	var body:VBoxContainer=app._open_modal(TITLE)
	app.modal.name="SouvenirExchangePanel"
	app.modal.set_meta("life_modal_layout",LAYOUT)
	app.modal.set_meta("souvenir_body",body)
	if app.village_art_preview:
		app.modal.theme=Pixel.make(app.hud.theme)
		app.modal.add_theme_stylebox_override("panel",Pixel.frame_style())
	if is_instance_valid(app.modal_shade):app.modal_shade.color.a=0.26
	if is_instance_valid(app.modal_feedback):app.modal_feedback.text="Esc 回到島上 · 兌換後不退票"
	body.add_theme_constant_override("separation",6)
	refresh(app)
	app._layout_preview.call_deferred()
	focus_first.call_deferred(app)

## main._layout_preview: wide like the other activity pages, as tall as its content.
static func layout(app,bounds:Vector2)->void:
	HarvestUI.layout(app,bounds)

static func is_open(app)->bool:
	return is_instance_valid(app.modal) and app.modal.has_meta("souvenir_body")

static func redeem_buttons(app)->Array[Button]:
	var out:Array[Button]=[]
	if not is_open(app):return out
	var body:Control=app.modal.get_meta("souvenir_body")
	for group:Array in GROUPS:
		for entry_id:String in group[1]:
			var b:=body.find_child("SouvenirRedeem_"+entry_id,true,false) as Button
			if b!=null:out.append(b)
	return out

## First enabled 兌換 button, else the first 兌換 button, else 「關閉」.
static func focus_first(app)->void:
	if not is_open(app):return
	var all:=redeem_buttons(app)
	for b in all:
		if b.is_visible_in_tree() and not b.disabled:
			b.grab_focus()
			return
	if not all.is_empty() and all[0].is_visible_in_tree():
		all[0].grab_focus()
		return
	var close:=close_button(app)
	if close!=null:close.grab_focus()

static func close_button(app)->BaseButton:
	if not is_instance_valid(app.modal):return null
	var body:Control=app.modal.get_meta("souvenir_body") if app.modal.has_meta("souvenir_body") else null
	for node in app.modal.find_children("*","BaseButton",true,false):
		if body!=null and body.is_ancestor_of(node):continue
		return node as BaseButton
	return null

static func refresh(app)->void:
	if not is_open(app):return
	var s:Dictionary=app.session.snapshot
	var id:String=app.session.own_id
	var m:=own(s)
	var body:VBoxContainer=app.modal.get_meta("souvenir_body")
	var unlocked:=bool(m.get("unlocked",false))
	var signature:=JSON.stringify([m,at_home(s),near_booth(s,id),app.binding_label("build_menu")])
	if str(app.modal.get_meta("souvenir_signature",""))==signature:return
	app.modal.set_meta("souvenir_signature",signature)
	var mode:="open" if unlocked else "locked"
	if str(app.modal.get_meta("souvenir_mode",""))!=mode:
		app.modal.set_meta("souvenir_mode",mode)
		for child in body.get_children():body.remove_child(child);child.queue_free()
		if unlocked:
			build(app,body)
			focus_first.call_deferred(app)
		else:
			HarvestUI.wrapped(app,body,Souv.LOCKED,17).name="SouvenirLocked"
			HarvestUI.wrapped(app,body,RULE,14,MUTED).name="SouvenirRule"
	if unlocked:update(app,body,s,id,m)
	app._layout_preview.call_deferred()

## Structure only (texts are filled by update()).
static func build(app,body:VBoxContainer)->void:
	HarvestUI.wrapped(app,body,RULE,14,MUTED).name="SouvenirRule"
	var rows:Array=[]
	for group:Array in GROUPS:
		var activity:String=group[0]
		var row:=HBoxContainer.new();row.name="SouvenirRow_"+activity;row.add_theme_constant_override("separation",8);body.add_child(row)
		var head:=HarvestUI.paper(row,"SouvenirGroup_"+activity)
		var head_card:=head.get_parent() as Control
		head_card.size_flags_horizontal=Control.SIZE_FILL
		head_card.custom_minimum_size.x=GROUP_WIDTH
		head.alignment=BoxContainer.ALIGNMENT_CENTER
		if activity=="trio":
			HarvestUI.text(app,head,"三種都要",15).name="SouvenirGroupName_trio"
			HarvestUI.text(app,head,"各 3 張",16,INK).name="SouvenirBalance_trio"
			HarvestUI.text(app,head,"三種票各扣 3 張",12,MUTED).name="SouvenirLedger_trio"
		else:
			HarvestUI.text(app,head,str(Souv.ACTIVITY_NAMES[activity]),15).name="SouvenirGroupName_"+activity
			HarvestUI.text(app,head,"",16,GOOD).name="SouvenirBalance_"+activity
			HarvestUI.text(app,head,"",12,MUTED).name="SouvenirLedger_"+activity
		var buttons:Array[Button]=[]
		for entry_id:String in group[1]:buttons.append(card(app,row,entry_id))
		rows.append(buttons)
	var hint:=HarvestUI.wrapped(app,body,"",14,WARN);hint.name="SouvenirHint"
	var blocked:=HarvestUI.wrapped(app,body,blocked_text(),14,WARN);blocked.name="SouvenirBlocked"
	var place:=HarvestUI.wrapped(app,body,"",14,GOOD);place.name="SouvenirPlaceHint"
	link_focus(app,rows)

static func card(app,row:HBoxContainer,entry_id:String)->Button:
	var box:=PanelContainer.new()
	box.name="SouvenirCard_"+entry_id
	box.add_theme_stylebox_override("panel",Pixel.paper_style())
	box.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	row.add_child(box)
	var line:=HBoxContainer.new();line.add_theme_constant_override("separation",8);box.add_child(line)
	var picture:=Shell.picture(Art.piece(entry_id),32)
	picture.name="SouvenirIcon_"+entry_id
	picture.size_flags_vertical=Control.SIZE_SHRINK_BEGIN
	line.add_child(picture)
	var middle:=VBoxContainer.new();middle.size_flags_horizontal=Control.SIZE_EXPAND_FILL;middle.add_theme_constant_override("separation",1);line.add_child(middle)
	var top:=HBoxContainer.new();top.add_theme_constant_override("separation",6);middle.add_child(top)
	var title:=HarvestUI.text(app,top,str(Souv.ENTRIES[entry_id].name),15);title.name="SouvenirName_"+entry_id
	var spacer:=Control.new();spacer.size_flags_horizontal=Control.SIZE_EXPAND_FILL;top.add_child(spacer)
	HarvestUI.text(app,top,"",12,MUTED).name="SouvenirCounts_"+entry_id
	var blurb:=HarvestUI.wrapped(app,middle,str(Souv.ENTRIES[entry_id].blurb),12,MUTED);blurb.name="SouvenirBlurb_"+entry_id
	var bottom:=HBoxContainer.new();bottom.add_theme_constant_override("separation",6);middle.add_child(bottom)
	HarvestUI.text(app,bottom,Souv.cost_text(entry_id),12,INK).name="SouvenirCost_"+entry_id
	var gap:=Control.new();gap.size_flags_horizontal=Control.SIZE_EXPAND_FILL;bottom.add_child(gap)
	HarvestUI.text(app,bottom,"",12,GOOD).name="SouvenirState_"+entry_id
	var b:Button=app.button("兌換",func():redeem(app,entry_id))
	b.name="SouvenirRedeem_"+entry_id
	b.custom_minimum_size=Vector2(64,34)
	b.add_theme_font_size_override("font_size",15)
	b.size_flags_vertical=Control.SIZE_SHRINK_CENTER
	b.focus_mode=Control.FOCUS_ALL
	line.add_child(b)
	return b

## Fill every text / enabled state in place (nothing is rebuilt, nothing moves).
static func update(app,body:VBoxContainer,s:Dictionary,id:String,m:Dictionary)->void:
	var page_reason:=blocker(s,id,m)
	for activity:String in Souv.ACTIVITIES:
		var row:=activity_of(m,activity)
		var balance:=body.find_child("SouvenirBalance_"+activity,true,false) as Label
		if balance:
			balance.text="剩 %d 張"%int(row.get("balance",0))
			balance.add_theme_color_override("font_color",GOOD if int(row.get("balance",0))>0 else MUTED)
		var ledger:=body.find_child("SouvenirLedger_"+activity,true,false) as Label
		if ledger:ledger.text="獲得 %d・已用 %d"%[int(row.get("earned",0)),int(row.get("spent",0))]
	for group:Array in GROUPS:
		for entry_id:String in group[1]:
			var entry:=entry_of(m,entry_id)
			var counts:=body.find_child("SouvenirCounts_"+entry_id,true,false) as Label
			if counts:counts.text=counts_text(entry)
			var reason:=entry_reason(entry,page_reason)
			var short:=short_text(entry.get("short",{}) if entry.get("short",{}) is Dictionary else {})
			var state:=body.find_child("SouvenirState_"+entry_id,true,false) as Label
			if state:
				state.text=short if not short.is_empty() else "票數足夠"
				state.add_theme_color_override("font_color",WARN if not short.is_empty() else GOOD)
			var b:=body.find_child("SouvenirRedeem_"+entry_id,true,false) as Button
			if b:
				b.disabled=not reason.is_empty() or entry.is_empty()
				b.tooltip_text=reason if not reason.is_empty() else "用 %s 兌換「%s」"%[Souv.cost_text(entry_id),str(Souv.ENTRIES[entry_id].name)]
	var hint:=body.find_child("SouvenirHint",true,false) as Label
	if hint:
		hint.text=page_reason
		hint.visible=not page_reason.is_empty()
	var blocked:=body.find_child("SouvenirBlocked",true,false) as Label
	if blocked:blocked.visible=at_home(s) and not bool(m.get("can_redeem",false))
	var place:=body.find_child("SouvenirPlaceHint",true,false) as Label
	if place:place.text=PLACE_HINT%app.binding_label("build_menu")

## Keyboard / controller neighbours over the group rows (disabled 兌換 buttons stay in
## the grid so focus never has to jump when one becomes disabled).
static func link_focus(app,rows:Array)->void:
	var flat:Array[Button]=[]
	for row in rows:flat.append_array(row)
	var close:=close_button(app)
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
		close.focus_next=close.get_path_to(flat[0])
