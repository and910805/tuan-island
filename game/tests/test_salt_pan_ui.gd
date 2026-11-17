extends SceneTree
## SEEDED UI FIXTURE: snapshot.salt_pan (public) and snapshot.salt_pan.own are literal
## dictionaries in the shape of contract-corrections §7. Buttons are pressed for real;
## SaltPanUI.action_sink records each emitted action instead of reaching the world,
## so this suite checks the exact action/cell/extra the panels send, not server rules.

const World=preload("res://scripts/world.gd")
const Salt=preload("res://scripts/salt_pan.gd")
const Flower=preload("res://scripts/flower_nursery.gd")
const SaltUI=preload("res://scripts/salt_pan_ui.gd")
const Tasks=preload("res://scripts/life_ui_tasks.gd")
const SIZES:=[Vector2i(1024,640),Vector2i(1280,800)]
const FORBIDDEN:=["切片","設計選擇","lot","socket","tick","status","save","protocol","debug","存檔","協定"]
var app
var world
var checks:=0
var failures:=0
var sent:Array=[]
var seen_texts:={}

func _initialize()->void:
	run.call_deferred()

func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)

func control(id:String)->Control:
	if not is_instance_valid(app.modal):return null
	return app.modal.find_child(id,true,false) as Control

func text_of(id:String)->String:
	var item:=control(id)
	if item is Label:return (item as Label).text
	if item is Button:return (item as Button).text
	return ""

func button(id:String)->Button:
	return control(id) as Button

func visible(item:Control)->bool:
	if not item or not item.is_visible_in_tree() or not root.get_visible_rect().encloses(item.get_global_rect()):return false
	var parent:=item.get_parent()
	while parent:
		if parent is ScrollContainer and not parent.get_global_rect().grow(1).encloses(item.get_global_rect()):return false
		parent=parent.get_parent()
	return true

## Mirrors the future main.gd wiring: main refits the modal (deferred) whenever its
## minimum size changes; SaltUI.layout must run after it, as it will inside _layout_preview.
func follow_layout()->void:
	if is_instance_valid(app.modal) and not app.modal.has_meta("salt_follow"):
		app.modal.set_meta("salt_follow",true)
		app.modal.minimum_size_changed.connect(func():
			if SaltUI.is_open(app):SaltUI.layout.call_deferred(app,Vector2(root.size)))

## main.gd's "salt_pan" layout case is wired later by the scene worker; until then the
## test re-applies SaltUI.layout after main's own deferred layout until it is stable.
func settle()->void:
	for i in range(3):await process_frame
	app._layout_preview()
	for i in range(8):
		if not is_instance_valid(app.modal):return
		var before:Rect2=app.modal.get_rect()
		SaltUI.layout(app,Vector2(root.size))
		await process_frame
		if is_instance_valid(app.modal) and i>=2 and app.modal.get_rect()==before:return

# ── fixtures (contract-corrections §7 shapes) ───────────────

func pans(overrides:Dictionary={})->Array:
	var result:Array=[]
	for i in range(Salt.PAN_COUNT):result.append({"s":"empty","p":0.0,"t":0.0,"f":"hand"})
	for i in overrides:result[i]=overrides[i]
	return result

func lots(mine:int=-1,taken:Array=[])->Array:
	var result:Array=[]
	for i in range(Salt.LOT_COUNT):result.append({"taken":i==mine or i in taken,"wheel":false,"rake":false,"active":false,"mine":i==mine})
	return result

func record(fields:Dictionary={})->Dictionary:
	var result:Dictionary=Salt.RECORD.duplicate(true)
	for key in fields:result[key]=fields[key]
	return result

func unit(fields:Dictionary={})->Dictionary:
	var result:={"kind":"","index":-1,"wheel":false,"rake":false,"chest":"","cap":Salt.CAP_DEFAULT,"on":false,"status":{}}
	for key in fields:result[key]=fields[key]
	return result

func salt_state(phase:String,fields:Dictionary={})->Dictionary:
	var gates:Array=[]
	for g in range(3):gates.append({"plank":0,"resin":0,"stone":0})
	var shared:={"gates":gates,"needs":Salt.GATE_NEEDS_EACH.duplicate(),"repaired":false,"giver_count":0,"pans":pans(),"lots":lots(),
		"apprentice":{"taken":false,"wheel":false,"rake":false,"active":false,"ends_at":0.0},
		"weather":{"id":"sunny","label":"晴天","raining":false}}
	var own:={"record":record(fields.get("record",{})),"phase":phase,"guidance":{"phase":phase,"text":"往下一步前進。","region":"beimen","cell":Salt.SALT_WORKER},
		"lot":-1,"unit":unit(),"apprentice":{"eligible":false,"busy":false,"mine":false,"ends_in_minutes":0,"message":"還有空的鹽田區，請先認領自己的鹽田區。"},
		"coop_box":0,"free_lots":8,"can_craft":{"salt_wheel_kit":false,"salt_rake_kit":false},
		"order":{"need":Salt.ORDER.duplicate(),"have":{"sea_salt":0,"salt_grilled_fish":0},"pay":Salt.ORDER_PAY}}
	for key in fields.get("shared",{}):shared[key]=fields.shared[key]
	for key in fields.get("own",{}):own[key]=fields.own[key]
	shared["own"]=own
	return shared

## Publishes a literal snapshot: region, time, player position/bag, salt_pan and objects.
func publish(salt:Dictionary,region:String,at:Vector2,bag:Dictionary={},time:float=100.0,objects:Dictionary={})->void:
	var snap:Dictionary=world.state.duplicate(true)
	var p:Dictionary=snap.players.tester
	p.x=at.x
	p.y=at.y
	p.region=region
	p.inventory=bag.duplicate()
	snap["region_id"]=region
	snap["time"]=time
	snap["objects"]=objects
	snap["salt_pan"]=salt
	app.session.snapshot=snap
	SaltUI.refresh(app)

func open(site:String)->void:
	app._close_modal()
	SaltUI.open(app,site)
	follow_layout()
	await settle()
	check(SaltUI.is_open(app) and app.modal.get_meta("salt_site","")==site,"Opens salt site "+site)
	collect_texts()

func collect_texts()->void:
	if not is_instance_valid(app.modal):return
	for item in app.modal.find_children("*","Label",true,false):
		if not item.name.begins_with("SaltSource_"):seen_texts[item.text]=item.name
	for item in app.modal.find_children("*","Button",true,false):seen_texts[item.text+" "+item.tooltip_text]=item.name

func press(id:String)->void:
	await settle()
	var target:=button(id)
	check(target!=null and visible(target) and not target.disabled,"Enabled and visible "+id)
	if target and not target.disabled:target.pressed.emit()
	await settle()
	collect_texts()

func expect_sent(id:String,action:String,cell_ok:Callable,extra:String)->void:
	sent.clear()
	await press(id)
	check(sent.size()==1,"%s emits exactly one action (got %d)"%[id,sent.size()])
	if sent.size()!=1:return
	check(sent[0][0]==action,"%s emits %s (got %s)"%[id,action,sent[0][0]])
	check(cell_ok.call(sent[0][1]),"%s targets the right cell (got %s)"%[id,sent[0][1]])
	check(sent[0][2]==extra,"%s extra '%s' (got '%s')"%[id,extra,sent[0][2]])

func disabled_with(id:String,reason:String)->void:
	var target:=button(id)
	check(target!=null and target.disabled,id+" disabled")
	check(target!=null and reason in target.tooltip_text,"%s tooltip carries reason '%s' (got '%s')"%[id,reason,target.tooltip_text if target else "<none>"])

func in_rect(rect:Rect2i)->Callable:
	return func(cell:Vector2i):return rect.has_point(cell)

func is_cell(want:Vector2i)->Callable:
	return func(cell:Vector2i):return cell==want

## Fit + no overlap/clipping at both required window sizes.
func fit(name:String)->void:
	for size in SIZES:
		root.size=size
		await settle()
		var modal_rect:Rect2=app.modal.get_global_rect()
		check(root.get_visible_rect().encloses(modal_rect),"%s modal within %s"%[name,size])
		var kind:=SaltUI.site_kind(str(app.modal.get_meta("salt_site","")))
		if not kind in ["journal","heritage"]:
			check(app.modal.size.y<=SaltUI.SIZES[kind].y+0.5,"%s modal is compact at %s (%.0f > %.0f)"%[name,size,app.modal.size.y,SaltUI.SIZES[kind].y])
		var scroll:=control("ModalScroll") as ScrollContainer
		var bar:=scroll.get_v_scroll_bar()
		check(bar.max_value<=bar.page+1.0,"%s fits without scrolling at %s (content %.0f page %.0f)"%[name,size,bar.max_value,bar.page])
		for item in app.modal.find_children("*","BaseButton",true,false):
			if item.is_visible_in_tree():check(visible(item),"%s %s button visible: %s"%[name,size,item.name])
		for item in app.modal.find_children("*","Label",true,false):
			var label:=item as Label
			if not label.is_visible_in_tree() or label.text.is_empty():continue
			check(label.size.x+0.5>=label.get_minimum_size().x and label.size.y+0.5>=label.get_minimum_size().y,"%s %s label not clipped: %s '%s'"%[name,size,label.name,label.text.left(24)])
			check(modal_rect.grow(1).encloses(label.get_global_rect()),"%s %s label inside modal: %s"%[name,size,label.name])
		var overlaps:=0
		for box in app.modal.find_children("*","Container",true,false):
			if box is PanelContainer or box is ScrollContainer or not box.is_visible_in_tree():continue
			var kids:Array=[]
			for child in box.get_children():
				if child is Control and child.is_visible_in_tree() and child.size.x>0.5 and child.size.y>0.5:kids.append(child)
			for a in range(kids.size()):
				for b in range(a+1,kids.size()):
					var shared:Rect2=kids[a].get_global_rect().intersection(kids[b].get_global_rect())
					if shared.get_area()>1.0:
						overlaps+=1
						push_error("%s overlap at %s: %s / %s"%[name,size,kids[a].name,kids[b].name])
		check(overlaps==0,"%s no overlapping controls at %s"%[name,size])
	root.size=SIZES[0]
	await settle()

func focus_cycle(name:String)->void:
	var buttons:Array=[]
	for item in app.modal.find_children("*","BaseButton",true,false):
		if item.is_visible_in_tree() and not item.disabled:buttons.append(item)
	check(not buttons.is_empty(),name+" has enabled buttons")
	if buttons.is_empty():return
	var first:Control=buttons[0]
	first.grab_focus()
	await process_frame
	var seen:={}
	var current:Control=first
	for i in range(400):
		seen[current]=true
		current=current.find_next_valid_focus()
		if current==null or current==first:break
	for item in buttons:check(seen.has(item),"%s Tab focus reaches %s"%[name,item.name])
	await key_event(KEY_TAB)
	var after:=root.gui_get_focus_owner()
	check(after is BaseButton and app.modal.is_ancestor_of(after),name+" Tab keeps focus inside the salt panel")

func key_event(code:Key)->void:
	var event:=InputEventKey.new()
	event.keycode=code
	event.physical_keycode=code
	event.pressed=true
	root.push_input(event)
	await process_frame
	event=event.duplicate()
	event.pressed=false
	root.push_input(event)
	await settle()

## Presses one key (logical `code`, physical `physical`, optional modifiers) on the focused
## SaltFlood button and returns how many salt actions it emitted.
func flood_key(code:Key,physical:Key,ctrl:=false,alt:=false,shift:=false)->int:
	var target:=button("SaltFlood")
	if target==null:return -1
	target.grab_focus()
	await process_frame
	sent.clear()
	var event:=InputEventKey.new()
	event.keycode=code
	event.physical_keycode=physical
	event.ctrl_pressed=ctrl
	event.alt_pressed=alt
	event.shift_pressed=shift
	event.pressed=true
	root.push_input(event)
	await process_frame
	event=event.duplicate()
	event.pressed=false
	root.push_input(event)
	await settle()
	return sent.size()

func chord(code:Key,physical:Key,ctrl:=false,alt:=false,shift:=false)->InputEventKey:
	var event:=InputEventKey.new()
	event.keycode=code
	event.physical_keycode=physical
	event.ctrl_pressed=ctrl
	event.alt_pressed=alt
	event.shift_pressed=shift
	event.pressed=true
	return event

## Salt buttons answer exactly to the `interact` binding (logical key identity).
func interact_binding_cases()->void:
	var saved:Dictionary=app.bindings.keys.duplicate()
	app.bindings.keys["interact"]=KEY_E
	var count:int=await flood_key(KEY_E,KEY_E)
	check(count==1,"Default binding: E activates once (got %d)"%count)
	count=await flood_key(KEY_Q,KEY_E)
	check(count==0,"Default binding: physical E with logical Q does not activate (got %d)"%count)
	count=await flood_key(KEY_E,KEY_E,true)
	check(count==0,"Default binding: Ctrl+E does not activate (got %d)"%count)
	count=await flood_key(KEY_E,KEY_E,false,true)
	check(count==0,"Default binding: Alt+E does not activate (got %d)"%count)
	count=await flood_key(KEY_E,KEY_E,false,false,true)
	check(count==1,"Default binding: Shift+E activates like matches() (got %d)"%count)
	# Rebound in memory only (no config write): interact = Q.
	app.bindings.keys["interact"]=KEY_Q
	count=await flood_key(KEY_Q,KEY_Q)
	check(count==1,"Rebound Q activates once (got %d)"%count)
	count=await flood_key(KEY_E,KEY_E)
	check(count==0,"E no longer activates after rebinding interact to Q (got %d)"%count)
	count=await flood_key(KEY_Q,KEY_E)
	check(count==1,"Logical Q on physical E activates exactly once, no double trigger (got %d)"%count)
	count=await flood_key(KEY_E,KEY_Q)
	check(count==0,"Logical E on physical Q does not activate (got %d)"%count)
	count=await flood_key(KEY_Q,KEY_Q,true)
	check(count==0,"Rebound: Ctrl+Q does not activate (got %d)"%count)
	count=await flood_key(KEY_Q,KEY_Q,false,true)
	check(count==0,"Rebound: Alt+Q does not activate (got %d)"%count)
	count=await flood_key(KEY_Q,KEY_Q,false,false,true)
	check(count==1,"Rebound: Shift+Q activates like matches() (got %d)"%count)
	# is_interact_key returns matches() verbatim for every shape, including chords.
	for event in [chord(KEY_Q,KEY_Q),chord(KEY_E,KEY_E),chord(KEY_Q,KEY_E),chord(KEY_E,KEY_Q),chord(KEY_Q,KEY_Q,true),
			chord(KEY_Q,KEY_Q,false,true),chord(KEY_Q,KEY_Q,false,false,true),chord(KEY_NONE,KEY_Q),chord(KEY_NONE,KEY_E)]:
		check(SaltUI.is_interact_key(app,event)==app.bindings.matches("interact",event),
			"is_interact_key mirrors bindings.matches for keycode=%d physical=%d"%[event.keycode,event.physical_keycode])
	app.bindings.keys=saved
	# No binding API at all: logical E only, unmodified.
	var bare:=RefCounted.new()
	check(SaltUI.is_interact_key(bare,chord(KEY_E,KEY_E)),"Fallback host: logical E activates")
	check(not SaltUI.is_interact_key(bare,chord(KEY_Q,KEY_E)),"Fallback host: physical E with logical Q does not activate")
	check(not SaltUI.is_interact_key(bare,chord(KEY_E,KEY_E,true)) and not SaltUI.is_interact_key(bare,chord(KEY_E,KEY_E,false,true)),"Fallback host: Ctrl/Alt+E do not activate")

func scan_literals(source:String,label:String)->void:
	var pattern:=RegEx.new()
	pattern.compile("\"((?:[^\"\\\\]|\\\\.)*)\"")
	var count:=0
	for found in pattern.search_all(source):
		var text:=found.get_string(1)
		var player:=false
		for ch in text:
			if ch.unicode_at(0)>127:player=true;break
		if not player:continue
		count+=1
		for word in FORBIDDEN:
			check(not text.to_lower().contains(word),"%s player text has no '%s': %s"%[label,word,text])
	check(count>20,"%s player strings scanned (%d)"%[label,count])

## Own apprentice view in the staged waiting-list shape (work/salt/staged-apprentice-fix
## own_view().apprentice); message strings copied from the staged formats.
func apprentice(fields:Dictionary)->Dictionary:
	var result:={"eligible":false,"busy":false,"mine":false,"ends_in_minutes":0,"message":"",
		"queued":false,"position":0,"waiting":0,"offer":false,"offer_minutes":0,"can_join":false,
		"kits":{"salt_wheel_kit":0,"salt_rake_kit":0}}
	for key in fields:result[key]=fields[key]
	return result

func all_text()->String:
	var out:=""
	if not is_instance_valid(app.modal):return out
	for item in app.modal.find_children("*","Label",true,false):out+=item.text+"\n"
	for item in app.modal.find_children("*","Button",true,false):out+=item.text+" "+item.tooltip_text+"\n"
	return out

func apprentice_queue_cases(rec:Dictionary)->void:
	var app_lot:int=Salt.APPRENTICE_LOT
	var app_at:=Vector2(Salt.rake_socket(app_lot).position)+Vector2(1.0,1.5)
	var seat:=SaltUI.nearest_cell(Salt.rake_socket(app_lot),app_at)
	var full_lots:={"repaired":true,"lots":lots(-1,[0,1,2,3,4,5,6,7])}
	var busy_msg:="學徒區正由另一位島民輪班，最晚約 1234 分鐘後開放；先到保留手作池收鹽吧。"
	# Busy station, not listed: join the list (never phrased as taking the shift now).
	publish(salt_state("claim",{"record":rec,"shared":full_lots,"own":{"free_lots":0,"apprentice":apprentice({"busy":true,"ends_in_minutes":1234,"waiting":2,"can_join":true,"message":busy_msg})}}),"beimen",app_at)
	await open("lot:%d"%app_lot)
	check(text_of("SaltShift")=="排進輪班名單" and not button("SaltShift").disabled,"Busy + can_join: join button enabled with the join label")
	check(not "接下" in text_of("SaltShift") and control("SaltShiftLeave")==null,"Join never reads as an instant shift; no leave before joining")
	check(text_of("SaltShiftQueueNote")==busy_msg and control("SaltShiftReason")==null,"Join case shows the wait as info, not a refusal")
	check("1234 分鐘" in text_of("SaltShiftWait") and text_of("SaltShiftLine")=="名單上有 2 位","Busy badge and list length")
	await fit("apprentice-join")
	await focus_cycle("apprentice-join")
	await expect_sent("SaltShift","salt_claim",is_cell(seat),"")
	# Station free but held for the list head: join too.
	var held_msg:="學徒區正保留給名單上的島民接班；可以先排進輪班名單。"
	publish(salt_state("claim",{"record":rec,"shared":full_lots,"own":{"free_lots":0,"apprentice":apprentice({"waiting":1,"can_join":true,"message":held_msg})}}),"beimen",app_at)
	await settle()
	check(text_of("SaltLotOwner")=="保留給名單上的島民" and text_of("SaltShift")=="排進輪班名單","Held-for-head station offers joining")
	check(control("SaltShiftWait")==null,"Free station shows no shift countdown")
	await fit("apprentice-held")
	await expect_sent("SaltShift","salt_claim",is_cell(seat),"")
	# Queued (2nd of 3) while busy: position shown, only leaving is offered, via salt_release on the same seat.
	var queued_msg:="學徒區正由另一位島民輪班，最晚約 1234 分鐘後開放；你排在輪班名單第 2 位，先到保留手作池收鹽吧。"
	publish(salt_state("claim",{"record":rec,"shared":full_lots,"own":{"free_lots":0,"apprentice":apprentice({"busy":true,"ends_in_minutes":1234,"queued":true,"position":2,"waiting":3,"message":queued_msg})}}),"beimen",app_at)
	await settle()
	check(control("SaltShift")==null,"Queued player gets no shift button (no false instant shift)")
	check(text_of("SaltShiftQueue")=="名單第 2 位／共 3 位" and text_of("SaltShiftQueueNote")==queued_msg,"Queued position and wait text")
	check(text_of("SaltLotOwner")=="輪班中","Queued header keeps the busy state")
	await fit("apprentice-queued")
	await focus_cycle("apprentice-queued")
	await expect_sent("SaltShiftLeave","salt_release",is_cell(seat),"")
	publish(salt_state("claim",{"record":rec,"shared":full_lots,"own":{"free_lots":0,"apprentice":apprentice({"busy":true,"ends_in_minutes":1234,"queued":true,"position":2,"waiting":3,"message":queued_msg})}}),"beimen",app_at+Vector2(9,0))
	await settle()
	disabled_with("SaltShiftLeave",SaltUI.NEAR_REASON)
	# Offered window: take the shift or leave the list.
	var offer_msg:="學徒區輪到你了，請在約 9 分鐘內來接班。"
	publish(salt_state("claim",{"record":rec,"shared":full_lots,"own":{"free_lots":0,"apprentice":apprentice({"eligible":true,"queued":true,"position":1,"waiting":2,"offer":true,"offer_minutes":9,"message":offer_msg})}}),"beimen",app_at)
	await settle()
	check(text_of("SaltLotOwner")=="輪到你接班" and text_of("SaltShift")=="接下學徒輪班","Offer: take-shift button")
	check("約 9 分鐘內" in text_of("SaltShiftOffer") and text_of("SaltShiftQueue")=="名單第 1 位／共 2 位","Offer window minutes and position")
	await fit("apprentice-offer")
	await focus_cycle("apprentice-offer")
	await expect_sent("SaltShift","salt_claim",is_cell(seat),"")
	await expect_sent("SaltShiftLeave","salt_release",is_cell(seat),"")
	# Not a candidate (e.g. already has a lot): stays disabled with the server's reason.
	publish(salt_state("claim",{"record":rec,"shared":full_lots,"own":{"free_lots":0,"apprentice":apprentice({"busy":true,"ends_in_minutes":50,"waiting":1,"message":"學徒區正由另一位島民輪班，最晚約 50 分鐘後開放；先到保留手作池收鹽吧。"})}}),"beimen",app_at)
	await settle()
	disabled_with("SaltShift","另一位島民輪班")
	check(text_of("SaltShift")=="接下學徒輪班" and control("SaltShiftLeave")==null,"Non-joinable busy station stays a disabled shift button")
	# Retained kits only (no salt): take enabled; own kits shown with the item icons.
	var kits:={"salt_wheel_kit":1,"salt_rake_kit":2}
	var leak_shared:Dictionary=full_lots.duplicate(true)
	leak_shared["kit_box"]={"rivaltoken":{"salt_wheel_kit":7,"salt_rake_kit":7}}
	leak_shared["waitlist"]={"order":[{"token":"rivaltoken","missed":0}],"offer_at":0.0}
	leak_shared["coop_box"]={"rivaltoken":77}
	publish(salt_state("claim",{"record":rec,"shared":leak_shared,"own":{"free_lots":0,"coop_box":0,"apprentice":apprentice({"busy":true,"ends_in_minutes":20,"queued":true,"position":1,"waiting":1,"message":queued_msg,"kits":kits})}}),"beimen",app_at)
	await settle()
	check(not button("SaltBoxTake").disabled,"Kits alone enable 全部取出")
	check(text_of("SaltCoopKit_salt_wheel_kit")=="鹽田水車組 ×1" and text_of("SaltCoopKit_salt_rake_kit")=="收鹽台組 ×2","Own retained kits listed")
	for kit in ["salt_wheel_kit","salt_rake_kit"]:
		var icon:=control("SaltCoopKits").find_child("Icon_"+kit,true,false) as TextureRect
		check(icon!=null and icon.texture==preload("res://scripts/inventory_item_art.gd").icon(kit),"Kit shelf uses the existing %s icon"%kit)
	var shown:=all_text()
	check(not "rivaltoken" in shown and not "×7" in shown and not "77" in shown,"Other players' tokens/escrow/salt never rendered")
	await fit("apprentice-kits")
	var chest_at:=Vector2(Salt.APPRENTICE_CHEST)+Vector2(0.5,-0.5)
	publish(salt_state("claim",{"record":rec,"shared":leak_shared,"own":{"free_lots":0,"coop_box":0,"apprentice":apprentice({"kits":kits})}}),"beimen",chest_at)
	await open("coop_chest")
	check(text_of("SaltCoopKit_salt_rake_kit")=="收鹽台組 ×2" and "機器組" in text_of("SaltCoopAbout"),"Coop chest panel shows own kits")
	await fit("coop-chest-kits")
	await focus_cycle("coop-chest-kits")
	await expect_sent("SaltBoxTake","salt_box_take",is_cell(Salt.APPRENTICE_CHEST),"")
	# Key hint once; a later refresh keeps the server's answer to the action visible.
	check(app.modal_feedback.text==SaltUI.KEY_HINT,"Key hint on open")
	var refusal:="背包的這些物品已達上限，先整理背包再來取。"
	app._notice(refusal,false)
	publish(salt_state("claim",{"record":rec,"shared":full_lots,"own":{"free_lots":0,"coop_box":3,"apprentice":apprentice({"kits":kits})}}),"beimen",chest_at,{"plank":1})
	await settle()
	check(app.modal_feedback.text==refusal,"Refresh after an action keeps its result line (got '%s')"%app.modal_feedback.text)
	# Empty compartment.
	publish(salt_state("claim",{"record":rec,"shared":full_lots,"own":{"free_lots":0,"coop_box":0,"apprentice":apprentice({})}}),"beimen",chest_at)
	await settle()
	disabled_with("SaltBoxTake",SaltUI.TAKE_EMPTY_REASON)
	check(control("SaltCoopKits")==null and control("SaltCoopFull")==null,"Empty compartment: no shelf, no full warning")
	# Full bag: nothing fits => disabled with the honest reason.
	publish(salt_state("claim",{"record":rec,"shared":full_lots,"own":{"free_lots":0,"coop_box":5,"apprentice":apprentice({"kits":{"salt_wheel_kit":1,"salt_rake_kit":0}})}}),"beimen",chest_at,{"sea_salt":Salt.LIMIT,"salt_wheel_kit":Salt.LIMIT})
	await settle()
	disabled_with("SaltBoxTake",SaltUI.TAKE_FULL_REASON)
	check(text_of("SaltCoopFull")==SaltUI.TAKE_FULL_REASON,"Full bag warning shown")
	await fit("coop-chest-full")
	# Partial: salt cannot fit, a kit can => enabled, with a note that the rest stays.
	publish(salt_state("claim",{"record":rec,"shared":full_lots,"own":{"free_lots":0,"coop_box":5,"apprentice":apprentice({"kits":{"salt_wheel_kit":1,"salt_rake_kit":0}})}}),"beimen",chest_at,{"sea_salt":Salt.LIMIT})
	await settle()
	check(not button("SaltBoxTake").disabled and control("SaltCoopPartial")!=null and control("SaltCoopFull")==null,"Partial room: take enabled, rest-stays note")
	await fit("coop-chest-partial")
	await expect_sent("SaltBoxTake","salt_box_take",is_cell(Salt.APPRENTICE_CHEST),"")
	# Old snapshot (salt only, no kits key) with salt: unchanged behaviour.
	publish(salt_state("claim",{"record":rec,"shared":full_lots,"own":{"free_lots":0,"coop_box":4}}),"beimen",chest_at)
	await settle()
	check(not button("SaltBoxTake").disabled and control("SaltCoopKits")==null and control("SaltCoopPartial")==null,"Old salt-only snapshot still takes salt")
	# Pure helper agrees with the staged server rule.
	check(SaltUI.take_plan(0,{},{}).held==0,"take_plan empty")
	check(SaltUI.take_plan(3,{"salt_rake_kit":2},{"salt_rake_kit":Salt.LIMIT-1}).fits==4,"take_plan per-item ceiling")
	var defaults:=SaltUI.apprentice_info({"apprentice":{"eligible":true}})
	check(defaults.position==0 and not defaults.queued and not defaults.can_join and defaults.kits=={"salt_wheel_kit":0,"salt_rake_kit":0},"apprentice_info defaults for old snapshots")
	check(not SaltUI.apprentice_info({"apprentice":{"queued":true,"position":0}}).queued,"queued without a position is not shown as listed")

func run()->void:
	root.size=SIZES[0]
	app=preload("res://main.tscn").instantiate()
	app.village_art_preview=true
	root.add_child(app)
	app.set_process(false)
	app.session.set_physics_process(false)
	app.menu.hide()
	app.hud.show()
	world=World.new()
	world.add_player("tester","鹽田旅人")
	app.session.snapshot=world.state
	app.session.own_id="tester"
	app.session.world=world
	app.session.peers[1]="tester"
	app.playing=true
	app.sound.reduced_motion=true
	SaltUI.action_sink=func(action:String,cell:Vector2i,extra:String):sent.append([action,cell,extra])

	# ── pure data / API shape ──
	check(SaltUI.interaction_points("home").is_empty(),"No salt points at home")
	var points:=SaltUI.interaction_points("beimen")
	check(points.has("salt:worker") and points.has("salt:coop_chest") and points.has("salt:heritage"),"Worker, coop chest and heritage points")
	for g in range(3):check(Salt.gate_at(SaltUI.site_cell("gate:%d"%g))==g,"Gate %d cell belongs to the gate"%g)
	for i in range(Salt.PAN_COUNT):check(Salt.pan_at(SaltUI.site_cell("pan:%d"%i))==i and points.has("salt:pan:%d"%i),"Pan %d cell"%i)
	for l in range(Salt.LOT_COUNT):check(Salt.site_at(SaltUI.site_cell("lot:%d"%l))=="rake:%d"%l,"Lot %d opens at its rake seat"%l)
	check(Salt.site_at(SaltUI.site_cell("lot:%d"%Salt.APPRENTICE_LOT))=="rake:%d"%Salt.APPRENTICE_LOT,"Apprentice board at its rake seat")
	check(SaltUI.cfg_extra(Vector2i(47,23),1)=="47,23|3" and SaltUI.cfg_extra(Vector2i(5,6),5000)=="5,6|999","Cap clamps to 3..999 in the extra")
	for id in Salt.STATUS_IDS:check(SaltUI.STATUS_ICONS.has(id) and id in SaltUI.STATUS_IDS and Salt.STATUS_TEXT.has(id),"Status id %s has an icon and text"%id)

	# ── letter (小栗, home) ──
	publish(salt_state("letter"),"home",Vector2(Flower.RECEIVER_HOME)+Vector2(0.5,1.5))
	await open("letter")
	check(control("SaltPortrait")!=null and text_of("SaltSpeakerName")=="小栗","Letter shows 小栗 portrait and name plate")
	check(Salt.STORY.letter in text_of("SaltLine") or SaltUI.story("letter")==text_of("SaltLine"),"Letter shows story line")
	await fit("letter")
	await focus_cycle("letter")
	await expect_sent("SaltLetter","salt_letter",is_cell(Flower.RECEIVER_HOME),"")
	publish(salt_state("locked"),"home",Vector2(Flower.RECEIVER_HOME)+Vector2(0.5,1.5))
	await open("letter")
	disabled_with("SaltLetter","花園")

	# ── worker dialogue: name plate only without art, never a colour stand-in ──
	SaltUI.art_provider=Callable()
	var worker_at:=Vector2(Salt.SALT_WORKER)+Vector2(0.5,1.5)
	publish(salt_state("intro",{"record":{"letter":true}}),"beimen",worker_at)
	await open("worker")
	check(control("SaltPortrait")==null and control("SaltPortraitFrame")==null,"No portrait art: no portrait frame")
	check(text_of("SaltSpeakerName")==SaltUI.WORKER_NAME,"Name plate shows 阿曬")
	var speaker_row:=control("SaltSpeaker")
	check(speaker_row!=null and speaker_row.find_children("*","ColorRect",true,false).is_empty(),"No coloured rectangle stand-in for the portrait")
	await fit("worker-intro")
	await expect_sent("SaltIntro","salt_intro",is_cell(Salt.SALT_WORKER),"")
	var face:=ImageTexture.create_from_image(Image.create(32,48,false,Image.FORMAT_RGBA8))
	SaltUI.art_provider=func(kind:String,id:String):return face if kind=="portrait" and id=="salt_worker" else null
	publish(salt_state("report",{"record":{"letter":true,"intro":true,"order":true}}),"beimen",worker_at)
	await open("worker")
	var portrait:=control("SaltPortrait") as TextureRect
	check(portrait!=null and portrait.texture==face and portrait.custom_minimum_size==Vector2(64,64) and portrait.texture_filter==CanvasItem.TEXTURE_FILTER_NEAREST,"Injected portrait fills the 64px slot")
	await fit("worker-report")
	await expect_sent("SaltReport","salt_report",is_cell(Salt.SALT_WORKER),"")
	publish(salt_state("report",{"record":{"letter":true,"intro":true,"order":true}}),"beimen",worker_at+Vector2(9,0))
	await open("worker")
	disabled_with("SaltReport",SaltUI.NEAR_REASON)

	# ── gates ──
	var gate_one:=Vector2(SaltUI.gate_rect(1).position)+Vector2(2.5,0.5)
	var gate_shared:={"gates":[{"plank":6,"resin":1,"stone":4},{"plank":2,"resin":0,"stone":4},{"plank":0,"resin":0,"stone":0}],"giver_count":3}
	publish(salt_state("gates",{"record":{"letter":true,"intro":true},"shared":gate_shared}),"beimen",gate_one,{"plank":4,"stone":10})
	await open("gate:1")
	check(text_of("SaltGive_1_plank")=="捐 4","Give button shows how many will be given (min of bag and need)")
	check(text_of("SaltGateCount_1_plank")=="2／6" and text_of("SaltGateCount_1_stone")=="4／4 ✓","Donated/needed counts")
	check(control("SaltGive_1_stone")==null,"Full material has no give button")
	disabled_with("SaltGive_1_resin","背包沒有樹脂")
	disabled_with("SaltGive_2_plank","閘門旁")
	check(control("SaltGateStamp_0")!=null and control("SaltGateStamp_1")==null,"Finished gate shows repaired stamp")
	check("3 位島民" in text_of("SaltGiverCount"),"Giver count")
	for g in range(3):
		for id in ["plank","resin","stone"]:
			var art:=control("SaltGateNeed_%d_%s"%[g,id]).find_child("Icon_"+id,true,false) as TextureRect
			check(art!=null and art.texture==preload("res://scripts/inventory_item_art.gd").icon(id),"Gate %d shows %s icon"%[g,id])
	await fit("gates")
	await focus_cycle("gates")
	await expect_sent("SaltGive_1_plank","salt_gate_give",in_rect(SaltUI.gate_rect(1)),"plank")
	var full_gates:Array=[]
	for g in range(3):full_gates.append(Salt.GATE_NEEDS_EACH.duplicate())
	publish(salt_state("first_salt",{"record":{"letter":true,"intro":true},"shared":{"gates":full_gates,"repaired":true,"giver_count":4}}),"beimen",gate_one)
	await open("gate:1")
	check(control("SaltRepairedStamp")!=null and control("SaltGateStamp_2")!=null and text_of("SaltGateTitle").begins_with("✓"),"Repaired card shows stamps")
	await fit("gates-repaired")

	# ── pan card ──
	var pub:=Salt.PUBLIC_LOT*2
	var pan_at:=Vector2(Salt.pan_rect(pub).position)+Vector2(1.5,-0.5)
	var intro_rec:={"letter":true,"intro":true}
	publish(salt_state("first_salt",{"record":intro_rec,"shared":{"repaired":true,"pans":pans({pub:{"s":"brine","p":Salt.NEED*0.5,"t":100.0,"f":"hand"}})}}),"beimen",pan_at,{},100.0)
	await open("pan:%d"%pub)
	check("滷水 50%" in text_of("SaltPanState"),"Brine percent: "+text_of("SaltPanState"))
	check("晴天約" in text_of("SaltEta") and "分鐘" in text_of("SaltEta"),"Sunny ETA in game minutes: "+text_of("SaltEta"))
	check(control("SaltPanPreview")!=null,"Pan state preview")
	await fit("pan-brine")
	publish(salt_state("first_salt",{"record":intro_rec,"shared":{"repaired":true}}),"beimen",pan_at,{},100.0)
	await settle()
	await fit("pan-empty")
	await focus_cycle("pan-empty")
	await expect_sent("SaltFlood","salt_flood",in_rect(Salt.pan_rect(pub)),"")
	# Keyboard E activates the focused button.
	button("SaltFlood").grab_focus()
	sent.clear()
	await key_event(KEY_E)
	check(sent.size()==1 and sent[0][0]=="salt_flood","E activates the focused salt button")
	await interact_binding_cases()
	var rainy:=2*1440.0+100.0
	var rain:={"id":"rainy","label":"小雨","raining":true}
	publish(salt_state("first_salt",{"record":intro_rec,"shared":{"repaired":true,"weather":rain}}),"beimen",pan_at,{},rainy)
	await settle()
	disabled_with("SaltFlood",SaltUI.RAIN_FLOOD_REASON)
	publish(salt_state("first_salt",{"record":intro_rec,"shared":{"repaired":true,"weather":rain,"pans":pans({pub:{"s":"salt","p":Salt.NEED,"t":rainy-50.0,"f":"hand"}})}}),"beimen",pan_at,{},rainy)
	await settle()
	check("不會流失" in text_of("SaltRainNote") and "暫停" in text_of("SaltRainNote"),"Rain wording: filling paused, formed salt covered")
	check("草蓆" in text_of("SaltPanState"),"Formed salt shows straw-mat cover in rain")
	await fit("pan-rain-salt")
	await expect_sent("SaltRake","salt_rake",in_rect(Salt.pan_rect(pub)),"")
	publish(salt_state("first_salt",{"record":intro_rec,"shared":{"repaired":false}}),"beimen",pan_at,{},100.0)
	await settle()
	disabled_with("SaltFlood",SaltUI.GATE_REASON)
	var other_at:=Vector2(Salt.pan_rect(2).position)+Vector2(1.5,-0.5)
	publish(salt_state("claim",{"record":intro_rec,"shared":{"repaired":true,"lots":lots(-1,[1])}}),"beimen",other_at)
	await open("pan:2")
	check(text_of("SaltPanOther")=="其他島民照顧中" and control("SaltFlood")==null,"Other islander's pan is view-only")

	# ── my lot board ──
	var lot:=3
	var sockets:Array=Salt.chest_sockets(lot)
	var rake_at:=Vector2(Salt.rake_socket(lot).position)+Vector2(1.0,1.5)
	var mine_rec:={"letter":true,"intro":true,"raked":2,"wheel_raked":1}
	var objects:={SaltUI.cell_key(sockets[0]):{"type":"chest","items":{}},SaltUI.cell_key(sockets[1]):{"type":"chest","items":{}}}
	var full_unit:=unit({"kind":"lot","index":lot,"wheel":true,"rake":true,"chest":SaltUI.cell_key(sockets[0]),"cap":60,"on":false,"status":{"id":"off","text":Salt.STATUS_TEXT.off}})
	var lot_shared:={"repaired":true,"lots":lots(lot)}
	publish(salt_state("automate",{"record":mine_rec,"shared":lot_shared,"own":{"lot":lot,"unit":full_unit,"free_lots":7}}),"beimen",rake_at,{},100.0,objects)
	await open("lot:%d"%lot)
	check(text_of("SaltLotOwner")=="你照顧的鹽田區","Own lot header")
	check(control("SaltChestPick_0")!=null and control("SaltChestPick_1")!=null and (control("SaltChestPick_0") as Button).button_pressed,"Chest picker shows both chest spots, saved one selected")
	await fit("lot-full")
	await focus_cycle("lot-full")
	await press("SaltChestPick_1")
	check((button("SaltChestPick_1") as Button).button_pressed,"Picked second chest spot")
	await expect_sent("SaltCfg","salt_auto_cfg",in_rect(Salt.rake_socket(lot)),"%d,%d|60"%[sockets[1].x,sockets[1].y])
	for i in range(7):
		var minus:=button("SaltCapMinus10")
		if minus and not minus.disabled:await press("SaltCapMinus10")
	check(text_of("SaltCapValue")=="3 份","Cap stepper floors at 3 (got %s)"%text_of("SaltCapValue"))
	check(button("SaltCapMinus1").disabled and button("SaltCapMinus10").disabled,"Minus buttons disabled at the floor")
	await expect_sent("SaltCfg","salt_auto_cfg",in_rect(Salt.rake_socket(lot)),"%d,%d|3"%[sockets[1].x,sockets[1].y])
	await press("SaltCapPlus1")
	check(text_of("SaltCapValue")=="4 份","+1 step")
	await press("SaltCapPlus10")
	check(text_of("SaltCapValue")=="14 份","+10 step")
	app.modal.set_meta("salt_cap",995)
	SaltUI.refresh(app)
	await press("SaltCapPlus10")
	check(text_of("SaltCapValue")=="999 份" and button("SaltCapPlus10").disabled and button("SaltCapPlus1").disabled,"Cap stepper ceiling 999")
	await press("SaltCapMinus1")
	check(text_of("SaltCapValue")=="998 份","-1 step")
	await expect_sent("SaltToggle","salt_auto_toggle",in_rect(Salt.rake_socket(lot)),"")
	await expect_sent("SaltUninstall_rake","salt_uninstall",in_rect(Salt.rake_socket(lot)),"rake")
	disabled_with("SaltUninstall_wheel","先拆下收鹽台")
	disabled_with("SaltRelease","拆回背包")
	# Every status id renders as icon + text.
	for id in Salt.STATUS_IDS:
		if id=="reserve":continue
		var status_unit:=full_unit.duplicate(true)
		status_unit.status={"id":id,"text":str(Salt.STATUS_TEXT.get(id,""))}
		status_unit.on=id in ["running","waiting","rain","full"]
		publish(salt_state("automate",{"record":mine_rec,"shared":lot_shared,"own":{"lot":lot,"unit":status_unit}}),"beimen",rake_at,{},100.0,objects)
		await settle()
		var chip:=control("SaltStatusChip")
		check(chip!=null and chip.get_meta("status_id","")==id,"Status chip for "+id)
		check(control("SaltStatusIcon") is TextureRect and (control("SaltStatusIcon") as TextureRect).texture!=null,"Status icon for "+id)
		check(text_of("SaltStatusText")==str(Salt.STATUS_TEXT.get(id,"")) and not text_of("SaltStatusText").is_empty(),"Status text for "+id)
		collect_texts()
		if id=="running":
			disabled_with("SaltCfg","先暫停")
			check(text_of("SaltToggle")=="暫停","Running lot offers pause")
			await fit("lot-running")
	# Missing kits: owned/needed counts and craft hint.
	publish(salt_state("wheel",{"record":mine_rec,"shared":lot_shared,"own":{"lot":lot,"unit":unit({"kind":"lot","index":lot})}}),"beimen",rake_at,{},100.0,objects)
	await settle()
	check(text_of("SaltKitCount_wheel")=="鹽田水車組 持有 0／需 1","Wheel kit owned/needed")
	check(text_of("SaltCraftHint_wheel")==str(Salt.CRAFT_LOCKED_MESSAGE),"Locked craft hint")
	disabled_with("SaltInstall_wheel","背包裡沒有鹽田水車組")
	disabled_with("SaltInstall_rake","先裝好水車")
	disabled_with("SaltToggle","先裝好水車和收鹽台")
	await fit("lot-empty")
	var craftable:={"salt_wheel_kit":true,"salt_rake_kit":false}
	publish(salt_state("wheel",{"record":mine_rec,"shared":lot_shared,"own":{"lot":lot,"unit":unit({"kind":"lot","index":lot}),"can_craft":craftable}}),"beimen",rake_at,{},100.0,objects)
	await settle()
	check("木板" in text_of("SaltCraftHint_wheel") and "工作台" in text_of("SaltCraftHint_wheel"),"Craft hint lists the recipe when allowed: "+text_of("SaltCraftHint_wheel"))
	var wheel_at:=Vector2(Salt.wheel_socket(lot).position)+Vector2(0.5,-0.5)
	publish(salt_state("wheel",{"record":mine_rec,"shared":lot_shared,"own":{"lot":lot,"unit":unit({"kind":"lot","index":lot})}}),"beimen",wheel_at,{"salt_wheel_kit":1},100.0,objects)
	await settle()
	check(text_of("SaltSlotState_wheel")=="可以裝","Wheel slot shows installable")
	await expect_sent("SaltInstall_wheel","salt_install",in_rect(Salt.wheel_socket(lot)),"wheel")
	publish(salt_state("wheel",{"record":mine_rec,"shared":lot_shared,"own":{"lot":lot,"unit":unit({"kind":"lot","index":lot,"status":{"id":"manual","text":Salt.STATUS_TEXT.manual}})}}),"beimen",rake_at,{},100.0,objects)
	await settle()
	await expect_sent("SaltRelease","salt_release",in_rect(Salt.rake_socket(lot)),"")
	# Free lot: claim.
	publish(salt_state("claim",{"record":mine_rec,"shared":{"repaired":true,"lots":lots(-1,[0])}}),"beimen",rake_at)
	await open("lot:%d"%lot)
	check(text_of("SaltLotOwner")=="空著，可以認領","Free lot header")
	await fit("lot-free")
	await expect_sent("SaltClaim","salt_claim",in_rect(Rect2i(Salt.rake_socket(lot))),"")
	publish(salt_state("claim",{"record":mine_rec,"shared":{"repaired":true,"lots":lots(-1,[lot])}}),"beimen",rake_at)
	await settle()
	disabled_with("SaltClaim","已經有人照顧")
	# Public pool: reserve chip.
	publish(salt_state("claim",{"record":mine_rec,"shared":{"repaired":true},"own":{"free_lots":0}}),"beimen",Vector2(Salt.PUBLIC_SIGN)+Vector2(0.5,1.5))
	await open("lot:%d"%Salt.PUBLIC_LOT)
	check(control("SaltStatusChip").get_meta("status_id","")=="reserve" and text_of("SaltStatusText")==str(Salt.STATUS_TEXT.reserve),"Public pool shows reserve text")
	check(control("SaltClaim")==null and control("SaltInstall_wheel")==null,"Public pool offers no claim or machines")
	check("保留手作池" in text_of("SaltPublicFull"),"Saturated hint points at the public pool")
	await fit("lot-public")

	# ── apprentice station ──
	var app_lot:int=Salt.APPRENTICE_LOT
	var app_at:=Vector2(Salt.rake_socket(app_lot).position)+Vector2(1.0,1.5)
	var waiting:={"eligible":false,"busy":true,"mine":false,"ends_in_minutes":1234,"message":"學徒區正由另一位島民輪班，最晚約 1234 分鐘後開放；先到保留手作池收鹽吧。"}
	publish(salt_state("claim",{"record":mine_rec,"shared":{"repaired":true,"lots":lots(-1,[0,1,2,3,4,5,6,7])},"own":{"apprentice":waiting,"free_lots":0,"coop_box":0}}),"beimen",app_at)
	await open("lot:%d"%app_lot)
	disabled_with("SaltShift","另一位島民輪班")
	check("1234 分鐘" in text_of("SaltShiftWait"),"Busy shift shows remaining minutes")
	disabled_with("SaltBoxTake","還沒有海鹽")
	# Pre-waiting-list snapshot (no queued/position/offer/can_join/kits): safe defaults.
	check(text_of("SaltShift")=="接下學徒輪班" and control("SaltShiftLeave")==null and control("SaltShiftQueue")==null and control("SaltShiftOffer")==null and control("SaltShiftLine")==null,"Old busy snapshot: no list controls invented")
	check(control("SaltCoopKits")==null,"Old snapshot: no retained kit shelf")
	await fit("apprentice-busy")
	var eligible:={"eligible":true,"busy":false,"mine":false,"ends_in_minutes":0,"message":""}
	publish(salt_state("claim",{"record":mine_rec,"shared":{"repaired":true,"lots":lots(-1,[0,1,2,3,4,5,6,7])},"own":{"apprentice":eligible,"free_lots":0}}),"beimen",app_at)
	await settle()
	await expect_sent("SaltShift","salt_claim",in_rect(Salt.rake_socket(app_lot)),"")
	var shift:={"eligible":false,"busy":true,"mine":true,"ends_in_minutes":4000,"message":""}
	var app_unit:=unit({"kind":"apprentice","index":app_lot,"wheel":true,"rake":true,"chest":SaltUI.cell_key(Salt.APPRENTICE_CHEST),"cap":60,"on":false,"status":{"id":"off","text":Salt.STATUS_TEXT.off}})
	publish(salt_state("automate",{"record":mine_rec,"shared":{"repaired":true,"lots":lots(-1,[0,1,2,3,4,5,6,7])},"own":{"apprentice":shift,"unit":app_unit,"coop_box":9,"free_lots":0}}),"beimen",app_at)
	await open("lot:%d"%app_lot)
	check("4000 分鐘" in text_of("SaltShiftLeft"),"Own shift shows remaining minutes")
	check(control("SaltChestPick_0")!=null and control("SaltChestPick_1")==null,"Apprentice picker shows the fixed cooperative chest")
	check("9" in text_of("SaltCoopCount"),"Cooperative chest count")
	await fit("apprentice-mine")
	await focus_cycle("apprentice-mine")
	await expect_sent("SaltCfg","salt_auto_cfg",in_rect(Salt.rake_socket(app_lot)),"47,23|60")
	await expect_sent("SaltShiftEnd","salt_release",in_rect(Salt.rake_socket(app_lot)),"")
	var chest_at:=Vector2(Salt.APPRENTICE_CHEST)+Vector2(0.5,-0.5)
	publish(salt_state("automate",{"record":mine_rec,"shared":{"repaired":true},"own":{"apprentice":shift,"unit":app_unit,"coop_box":9}}),"beimen",chest_at)
	await open("coop_chest")
	await fit("coop-chest")
	await expect_sent("SaltBoxTake","salt_box_take",is_cell(Salt.APPRENTICE_CHEST),"")
	await apprentice_queue_cases(mine_rec)

	# ── Xiaoli order ──
	var home_at:=Vector2(Flower.RECEIVER_HOME)+Vector2(0.5,1.5)
	var order_rec:={"letter":true,"intro":true,"raked":3,"wheel_raked":1,"auto_raked":1}
	publish(salt_state("order",{"record":order_rec,"own":{"order":{"need":Salt.ORDER.duplicate(),"have":{"sea_salt":4,"salt_grilled_fish":1},"pay":Salt.ORDER_PAY}}}),"home",home_at)
	await open("order")
	check(text_of("SaltOrderCount_sea_salt").begins_with("✓") and "4／需 4" in text_of("SaltOrderCount_sea_salt"),"Order sea salt have/need")
	check(text_of("SaltOrderCount_salt_grilled_fish").begins_with("✗"),"Order fish short")
	check("%d"%Salt.ORDER_PAY in text_of("SaltOrderTitle") and "120" in text_of("SaltOrder"),"Order pays 120")
	disabled_with("SaltOrder","不夠")
	publish(salt_state("order",{"record":order_rec,"own":{"order":{"need":Salt.ORDER.duplicate(),"have":{"sea_salt":4,"salt_grilled_fish":2},"pay":Salt.ORDER_PAY}}}),"home",home_at)
	await settle()
	await fit("order")
	await expect_sent("SaltOrder","salt_order",is_cell(Flower.RECEIVER_HOME),"")

	# ── journal / heritage ──
	var done_rec:={"letter":true,"intro":true,"raked":3,"wheel_raked":1,"auto_raked":1,"order":true,"complete":true}
	var manual_target:=Salt.pan_rect(Salt.PUBLIC_LOT*2).position
	var first_plan:={"text":"到保留手作池引海水，等鹽結成後親手收一次鹽。","region":"beimen","cell":manual_target}
	publish(salt_state("first_salt",{"record":intro_rec,"own":{"guidance":first_plan},"shared":{"repaired":true}}),"beimen",Salt.ARRIVAL)
	app._map_menu()
	await settle()
	var map_data:Dictionary=app.map_view.salt_landmarks(app.map_view.data)
	check(map_data.target==manual_target and map_data.manual.has_point(manual_target) and not map_data.plot.has_area(),
		"The first-salt guidance points at the public pan")
	check(map_data.names.has(Salt.HERITAGE_SIGN) and map_data.names.has(Salt.BRINE_TANK) and map_data.names.has(Salt.APPRENTICE_CHEST),
		"The map shows the heritage view and the repaired saltworks equipment")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--beimen-map-shot=") and DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png(arg.trim_prefix("--beimen-map-shot="))==OK,"Capture the first salt route")
	publish(salt_state("complete",{"record":done_rec,"own":{"lot":2},"shared":{"repaired":true}}),"beimen",Vector2(Salt.HERITAGE_SIGN)+Vector2(0.5,-0.5))
	app.map_view.update_world(app.session.snapshot,app.session.own_id)
	map_data=app.map_view.salt_landmarks(app.map_view.data)
	check(map_data.plot.has_point(Salt.pan_rect(4).position) and map_data.plot.has_point(Salt.pan_rect(5).position),
		"The owned parcel outline includes both working pans")
	await press("BeimenMapHistory")
	follow_layout()
	await settle()
	check(SaltUI.is_open(app),"The Beimen local map opens the salt history spread")
	for i in SaltUI.SOURCES.size():
		var link:=control("SaltSource_%d"%i) as LinkButton
		var entry:Array=SaltUI.SOURCES[i]
		check(link!=null and link.uri==entry[1] and link.text==entry[0],"The journal links the source "+entry[0])
	check(SaltUI.ORIGINAL_NOTE in text_of("SaltOriginal") and "鹽風合作鹽田、阿曬與水車收鹽台是遊戲原創；井仔腳瓦盤鹽田是今日保存的文化景觀" in text_of("SaltOriginal"),"Originality statement")
	check("1818年遷至現址" in text_of("SaltFact_0") and not "可追溯" in text_of("SaltFact_0"),"Verified 1818 relocation wording")
	check(control("SaltJournalLeftPage").get_global_rect().end.x<control("SaltJournalRightPage").get_global_rect().position.x,"Journal is a two-page spread")
	await fit("journal-memory")
	await press("SaltTab_story")
	check(control("SaltStory_letter")!=null and control("SaltStory_complete")!=null,"Story replay lists unlocked lines")
	await press("SaltStory_intro")
	check(text_of("SaltLine")==SaltUI.story("intro"),"Story replay shows chosen line")
	await fit("journal-story")
	publish(salt_state("complete",{"record":done_rec,"shared":{"repaired":true}}),"beimen",Vector2(Salt.HERITAGE_SIGN)+Vector2(0.5,-0.5))
	await open("heritage")
	await fit("heritage")
	await expect_sent("SaltNote","salt_note",is_cell(Salt.HERITAGE_SIGN),"")

	# ── Esc closes; prompts suppressed only while open ──
	await open("worker")
	check(SaltUI.suppress_world_prompts(app) and app.modal.get_meta("suppress_world_prompts",false),"World prompts suppressed while open")
	await key_event(KEY_ESCAPE)
	check(not is_instance_valid(app.modal),"Esc closes the salt panel")
	check(not SaltUI.suppress_world_prompts(app),"Prompts return after closing")

	# ── life_ui_tasks: 阿曬 resident page + 北門瓦盤鹽田 local-memory page ──
	var first_rake:={"letter":true,"intro":true,"raked":1}
	publish(salt_state("wheel",{"record":first_rake,"shared":{"repaired":true}}),"home",home_at)
	Tasks.journal(app)
	await settle()
	check(control("SaltWorkerBookmark")==null and control("SaltMemoryBookmark")!=null,"The first manual rake unlocks salt memories before the report")
	await press("SaltMemoryBookmark")
	follow_layout()
	await settle()
	check("親手收過海鹽" in text_of("SaltFieldwork") and "瀨東鹽場" in text_of("SaltFact_0"),"The home journal records the fieldwork and the saltworks' former name")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--salt-memory-shot=") and DisplayServer.get_name()!="headless":
			await RenderingServer.frame_post_draw
			check(root.get_texture().get_image().save_png(arg.trim_prefix("--salt-memory-shot="))==OK,"Capture the earned salt memory")
	app._close_modal()
	publish(salt_state("complete",{"record":done_rec,"shared":{"repaired":true}}),"home",home_at)
	for size in SIZES:
		root.size=size
		Tasks.journal(app,"salt_worker")
		await settle()
		check(control("SaltWorkerBookmark")!=null and (control("SaltWorkerBookmark") as Button).button_pressed,"阿曬 bookmark selected at %s"%size)
		check(control("SaltMemoryBookmark")!=null and visible(control("SaltMemoryBookmark")),"北門瓦盤鹽田 bookmark visible at %s"%size)
		var page_text:=""
		for item in app.modal.find_children("*","Label",true,false):page_text+=item.text
		check("阿曬・照顧鹽風合作鹽田的鹽工" in page_text and "原創" in page_text,"阿曬 resident page at %s"%size)
		check(control("SaltWorkerMemory")!=null and visible(control("SaltWorkerMemory")),"Resident page links to the memory page at %s"%size)
		collect_texts()
	root.size=SIZES[0]
	await press("SaltMemoryBookmark")
	follow_layout()
	await settle()
	check(SaltUI.is_open(app) and app.modal.get_meta("salt_site","")=="journal","Memory bookmark opens the 北門瓦盤鹽田 page")
	app._close_modal()

	# ── forbidden jargon ──
	scan_literals(FileAccess.get_file_as_string("res://scripts/salt_pan_ui.gd"),"salt_pan_ui.gd")
	var tasks_source:=FileAccess.get_file_as_string("res://scripts/life_ui_tasks.gd")
	var start:=tasks_source.find("## 北門鹽田")
	var stop:=tasks_source.find("static func journal_story")
	check(start>=0 and stop>start,"life_ui_tasks salt section found")
	var section:=tasks_source.substr(start,stop-start)
	var pattern:=RegEx.new()
	pattern.compile("\"((?:[^\"\\\\]|\\\\.)*)\"")
	var tasks_count:=0
	for found in pattern.search_all(section):
		var text:=found.get_string(1)
		if text.begins_with("res://"):continue
		tasks_count+=1
		for word in FORBIDDEN:check(not text.to_lower().contains(word) or text in ["salt_pan","own","record","complete","salt_worker","journal"],"life_ui_tasks salt text has no '%s': %s"%[word,text])
	check(tasks_count>5,"life_ui_tasks salt strings scanned")
	var rendered:=0
	for text in seen_texts:
		rendered+=1
		for word in FORBIDDEN:check(not str(text).to_lower().contains(word),"Rendered text has no '%s': %s (%s)"%[word,text,seen_texts[text]])
	check(rendered>80,"Rendered player texts scanned (%d)"%rendered)

	SaltUI.action_sink=Callable()
	SaltUI.art_provider=Callable()
	app.queue_free()
	await process_frame
	print("SALT_PAN_UI_TESTS checks=%d failures=%d (seeded UI fixture)"%[checks,failures])
	quit(int(failures>0))
