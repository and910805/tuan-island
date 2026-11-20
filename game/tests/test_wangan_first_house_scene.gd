extends "res://tests/test_wangan_first_repair_scene.gd"
## 望安第一間小屋 (headless, real app, the same earned save as the first repair):
## after the notice board is repaired the board's BoardStarterHouse button opens the
## illustrated workshop lesson (topic 4). The player then gathers every needed wood and
## fibre from real trees (parent gather_node), picks a clear, unprotected, reachable site
## near the village, and builds the lesson's 2x2 room with the real build tool: 4 floors,
## a ring of 11 walls + 1 door on the 4x4 perimeter (door at local (1,3)), a bed at (2,1);
## the door that seals the room pays the 4 automatic roofs. Then HouseRooms is inspected
## through the real HouseCheck button, the door is opened and closed with the interact key,
## the player walks in, the save is reloaded and the bed is reached.
## Nothing here grants materials, flags or positions, and no world action is called
## directly: every step is a key, a click, a held walk key or a real UI button.
const Layouts=preload("res://scripts/workshop_layouts.gd")
const HouseRooms=preload("res://scripts/house_rooms.gd")
const SITE_RADIUS:=14
const MAX_TREES:=18
const BUDGET_MS:=160000
const LAYERS:=["ground","objects","roofs"]
var origin:=Vector2i(-1,-1)

func first_repair()->void:
	await super.first_repair()
	if failures>0:
		check(false,"First repair failed; the house scene needs its earned save")
		return
	await first_house()

func in_budget()->bool:
	return check(Time.get_ticks_msec()-started_ms<BUDGET_MS,"House scene stays inside its time budget")

## wood/fibre cost of the whole room as the build recipes define it (roofs included).
func house_cost()->Dictionary:
	var parts:={"floor":4,"wall":11,"door":1,"bed":1,"roof":4}
	var total:={}
	for kind in parts:
		for item in World.BUILD[kind]:
			if item!="name":total[item]=int(total.get(item,0))+int(World.BUILD[kind][item])*int(parts[kind])
	return total

func negate(cost:Dictionary)->Dictionary:
	var out:={}
	for item in cost:out[item]=-int(cost[item])
	return out

func piece_cost(kind:String)->Dictionary:
	var cost:={}
	for item in World.BUILD[kind]:
		if item!="name":cost[item]=int(World.BUILD[kind][item])
	return cost

func ring_walls()->Array:
	var out:=[]
	for y in 4:
		for x in 4:
			var c:=Vector2i(x,y)
			if (x==0 or x==3 or y==0 or y==3) and c!=Layouts.HOUSE_DOOR:out.append(c)
	return out

func cell_key(local:Vector2i)->String:
	return World.key(origin+local)

## Compact, comparable picture of the site (server state or client snapshot).
func house_picture(src:Dictionary)->Dictionary:
	var out:={}
	for y in range(-1,6):
		for x in range(-1,5):
			var k:=cell_key(Vector2i(x,y))
			for layer in LAYERS:
				var v:Variant=src.get(layer,{}).get(k)
				if v is Dictionary:
					var owner:=str(v.get("owner",""))
					out["%s:%s"%[layer,k]]=[str(v.get("type","")),bool(v.get("open",false)),bool(v.get("auto",false)),"self" if owner in [tok,me] else owner]
	return out

func layer_counts()->Array:
	return [w.state.ground.size(),w.state.objects.size(),w.state.roofs.size()]

func first_house()->void:
	var expected:=house_cost()
	if not check(expected.get("wood",0)==66 and expected.get("fiber",0)==24 and expected.size()==2,"Room costs 66 wood + 24 fibre: %s"%JSON.stringify(expected)):return
	if not await house_lesson(expected):return
	if not in_budget() or not find_house_site():return
	# --- gather everything from real trees.
	var trees:=0
	while (int(bag().get("wood",0))<int(expected.wood) or int(bag().get("fiber",0))<int(expected.fiber)) and trees<MAX_TREES:
		if not in_budget() or not await gather_node("tree","axe"):return
		trees+=1
	var stock:=bag()
	if not check(int(stock.get("wood",0))>=int(expected.wood) and int(stock.get("fiber",0))>=int(expected.fiber),"%d trees gave enough wood and fibre: %s"%[trees,JSON.stringify(stock)]):return
	check(same(snap_bag(),stock) and int(person().coins)==int(snap_person().coins),"Client bag follows the gathering")
	# --- build.
	var counts:=layer_counts()
	var floors:=Layouts.HOUSE_FLOOR
	for c in floors:
		if not await place("floor",c):return
	for c in ring_walls():
		if not await place("wall",c):return
	var paid:=plus(plus(expected,negate(piece_cost("door"))),negate(plus(roof_cost(),piece_cost("bed"))))
	check(same(bag(),plus(stock,negate(paid))),"Before the door only floors and walls were paid: %s"%JSON.stringify(bag()))
	check(floors.all(func(c):return not w.state.roofs.has(cell_key(c))),"No roof exists while the ring still has its doorway")
	var door_before:=bag()
	if not await place("door",Layouts.HOUSE_DOOR,[origin+Layouts.HOUSE_DOOR+Vector2i.DOWN]):return
	for c in floors:
		var roof=w.state.roofs.get(cell_key(c),{})
		check(roof.get("type")=="roof" and roof.get("auto")==true and roof.get("owner")==tok and snap().roofs.has(cell_key(c)),"Automatic roof over %s"%str(origin+c))
	check(same(bag(),plus(door_before,negate(plus(piece_cost("door"),roof_cost())))) and same(snap_bag(),bag()),"The door seals the room and pays exactly its own cost plus 4 roofs: %s"%JSON.stringify(bag()))
	await shot("05-automatically-roofed")
	var door_stand:=origin+Layouts.HOUSE_DOOR+Vector2i.DOWN
	if not await toggle_door(true,door_stand):return
	if not await walk_to([origin+Vector2i(1,2)],"through the open door into the room"):return
	check(Vector2i(pos())-origin==Vector2i(1,2),"The player walks inside the room")
	if not await place("bed",Layouts.HOUSE_BED,[origin+Vector2i(1,2)]):return
	if not await toggle_door(false,origin+Vector2i(1,2)):return
	check(same(bag(),plus(stock,negate(expected))) and same(snap_bag(),bag()),"Finished house consumes exactly the lesson's materials")
	var after:=layer_counts()
	check(after==[counts[0]+4,counts[1]+13,counts[2]+4],"Exactly 4 floors, 11 walls + door + bed and 4 roofs were added: %s -> %s"%[str(counts),str(after)])
	check(same(house_picture(w.state),house_picture(snap())),"Client snapshot shows the same house as the server")
	await shot("06-inside")
	var kept:=house_picture(w.state)
	var kept_bag:=bag()
	var kept_coins:=int(person().coins)
	var kept_pos:=Vector2i(pos())
	if not await inspect_house("from inside"):return
	# --- save, reload, reach the bed.
	await close_app()
	var plain:=World.new()
	if not check(plain.load_world(path) and not plain.recovered_from_backup,"Plain load of the house save"):return
	var saved:=house_picture(plain.state)
	check(same(saved,kept) and same(nonzero(plain.state.players[tok].inventory),kept_bag),"Plain load keeps the exact house and bag")
	if not await open_app():return
	await hud_tick()
	check(same(house_picture(w.state),kept) and same(house_picture(snap()),kept),"Reloaded app keeps the exact house on server and client")
	check(same(bag(),kept_bag) and same(bag(),plus(stock,negate(expected))) and same(snap_bag(),kept_bag) and int(person().coins)==kept_coins,"Reloaded app keeps exact costs: %s"%JSON.stringify(bag()))
	check(Vector2i(pos())==kept_pos and not bool(w.state.objects[cell_key(Layouts.HOUSE_DOOR)].get("open",true)),"Player is still inside and the door is still closed")
	var bed:=origin+Layouts.HOUSE_BED
	if not await walk_to([bed+Vector2i.LEFT,bed+Vector2i.DOWN],"to the bed"):return
	var near:=Vector2i(pos())-bed
	check(absi(near.x)+absi(near.y)==1,"The player reaches the cell beside the bed at %s"%str(bed))
	var seen:=HouseRooms.inspect(snap(),Vector2i(pos()))
	check(bool(seen.get("found",false)) and bool(seen.get("complete",false)) and bool(seen.get("reachable_bed",false)),"HouseRooms: complete room with a reachable bed after reload: %s"%JSON.stringify(seen.get("missing",[])))
	await inspect_house("after reload")
	note("house built at %s from %d trees"%[str(origin),trees])

func roof_cost()->Dictionary:
	var out:={}
	for item in World.BUILD.roof:
		if item!="name":out[item]=int(World.BUILD.roof[item])*4
	return out

## The board's BoardStarterHouse button opens the illustrated first-house lesson.
func house_lesson(expected:Dictionary)->bool:
	if not await open_board("(first house lesson)"):return false
	var entry:=app.modal.find_child("BoardStarterHouse",true,false) as Button
	if not check(entry!=null and entry.is_visible_in_tree() and not entry.disabled,"The repaired board offers BoardStarterHouse"):return false
	entry.pressed.emit()
	await frames(4)
	var m:Control=app.modal
	if not check(is_instance_valid(m) and m.get_meta("life_modal_layout","")=="workshop_guide" and int(app.get_meta("workshop_guide_topic",-1))==Layouts.FIRST_HOUSE,"The button opens the workshop guide on topic 4"):return false
	var tab:=m.find_child("WorkshopLesson_%d"%Layouts.FIRST_HOUSE,true,false) as Button
	check(tab!=null and tab.button_pressed and tab.text==Layouts.TITLES[Layouts.FIRST_HOUSE],"Tab 4 is selected: %s"%(tab.text if tab else "<none>"))
	check(m.find_child("WorkshopDiagram",true,false)!=null and m.find_child("WorkshopPreview",true,false)!=null,"The lesson is illustrated")
	var lesson:=Layouts.lesson(Layouts.FIRST_HOUSE)
	var kinds:={}
	var at_door:=false
	var at_bed:=false
	for p:Dictionary in lesson.design.pieces:
		kinds[p.kind]=int(kinds.get(p.kind,0))+1
		at_door=at_door or (p.kind=="door" and Vector2i(p.x,p.y)==Layouts.HOUSE_DOOR)
		at_bed=at_bed or (p.kind=="bed" and Vector2i(p.x,p.y)==Layouts.HOUSE_BED)
	check(same(kinds,{"floor":4,"wall":11,"door":1,"bed":1}) and at_door and at_bed and int(lesson.design.width)==4,"Lesson design is the 4x4 room with the bottom door and bed: %s"%str(kinds))
	var steps:Array=lesson.guide
	check(steps.size()==4 and m.find_child("WorkshopStep_3",true,false)!=null and m.find_child("WorkshopStep_4",true,false)==null,"The lesson has four steps")
	var heading:=m.find_child("WorkshopStepHeading",true,false) as Label
	var next:=m.find_child("WorkshopNext",true,false) as Button
	if not check(heading!=null and next!=null,"Step heading and Next exist"):return false
	for i in steps.size():
		check(heading.text==str(steps[i].heading),"Step %d heading: %s"%[i+1,heading.text])
		if i<steps.size()-1:
			next.pressed.emit()
			await frames(2)
	check(same(Layouts.cost(Layouts.FIRST_HOUSE),expected),"Lesson cost equals the real build cost: %s"%JSON.stringify(Layouts.cost(Layouts.FIRST_HOUSE)))
	for item in expected:
		var label:=m.find_child("WorkshopCost_"+str(item),true,false) as Label
		check(label!=null and label.text.ends_with("／%d"%int(expected[item])),"Lesson shows the %s cost: %s"%[item,label.text if label else "<none>"])
	await shot("04-house-lesson")
	await close_modal_with_esc("first house lesson")
	return true

func site_clear(o:Vector2i)->bool:
	for y in 5:
		for x in 4:
			var c:=o+Vector2i(x,y)
			if not w.is_land(c) or w.water(c) or w.protected(c) or w.resource(c)!="" or not standable(c) or c in Chapter.STARTER_PLOT:return false
			var k:=World.key(c)
			for layer in ["ground","objects","roofs","crops","forest"]:
				if w.state[layer].has(k):return false
	return true

## Deterministic ring search around the notice board for a clear reachable 4x5 site.
func find_house_site()->bool:
	var c:=BOARD_STANDS[0]
	for d in range(2,SITE_RADIUS+1):
		for y in range(c.y-d,c.y+d+1):
			for x in range(c.x-d,c.x+d+1):
				var o:=Vector2i(x,y)
				if maxi(absi(x-c.x),absi(y-c.y))!=d or not site_clear(o) or route([o+Vector2i(1,4)]).is_empty():continue
				origin=o
				note("house site %s"%str(o))
				return true
	return check(false,"A clear, unprotected, reachable house site exists within %d cells of the board"%SITE_RADIUS)

## Walk to a stand cell, select the piece in the real build menu and click the cell once.
func place(kind:String,local:Vector2i,stands:Array=[])->bool:
	if not in_budget():return false
	var cell:=origin+local
	if stands.is_empty():
		for c in Layouts.HOUSE_FLOOR:
			if c!=local:stands.append(origin+c)
		if Vector2i(pos()) in stands:stands=[Vector2i(pos())]+stands
	if not await walk_to(stands,"to build %s at %s"%[kind,str(cell)]):return false
	if app.building!=kind or app.selected!="build" or app.building_on_edge:
		app._workshop_guide(Layouts.FIRST_HOUSE)
		await frames(3)
		var step:=["floor","wall","door","bed"].find(kind)
		var page:=app.modal.find_child("WorkshopStep_%d"%step,true,false) as Button
		var recipe:=app.modal.find_child("WorkshopBuild",true,false) as Button
		if not check(page!=null and recipe!=null,"The house lesson links to the "+kind+" recipe"):return false
		page.pressed.emit()
		await frames(2)
		recipe.pressed.emit()
		await frames(3)
		var whole:=app.modal.find_child("BuildOccupyTile",true,false) as CheckButton if is_instance_valid(app.modal) else null
		if kind in ["wall","door"]:
			if not check(whole!=null and whole.is_visible_in_tree() and whole.button_pressed,"The lesson recipe selects whole-tile "+kind+" by default"):return false
		var button:=app.modal.find_child("BuildPlace",true,false) as Button if is_instance_valid(app.modal) else null
		if not check(button!=null and not button.disabled,"The builder can select "+kind):return false
		button.pressed.emit()
		await frames(3)
		if not check(app.building==kind and app.selected=="build" and not app.building_on_edge,"The builder selects whole-tile "+kind):return false
	# A player cannot place two pieces within the game's click cooldown.
	await hud_tick()
	var before:=bag()
	notices.clear()
	var sent:int=app.session.counter
	await click(cell)
	if kind=="door":
		if not check(is_instance_valid(app.modal) and app.modal.get_meta("life_modal_layout","")=="roof_confirm","Closing the ring opens the real automatic-roof confirmation"):return false
		check(int(app.session.counter)==sent and same(before,bag()) and not w.state.objects.has(World.key(cell)),"Quoting does not build or charge anything")
		var quote:Dictionary=app.modal.get_meta("roof_quote",{})
		check(int(quote.get("add",0))==4 and same(quote.get("cost",{}),plus(piece_cost("door"),roof_cost())),"Quote includes exactly the door and four auto roofs")
		var confirm:=app.modal.find_child("RoofConfirm",true,false) as Button
		if not check(confirm!=null and not confirm.disabled,"Roof confirmation is available"):return false
		await shot("05-roof-confirmation")
		confirm.pressed.emit()
		await frames(4)
	sent=int(app.session.counter)-sent
	actions+=sent
	var layer:="ground" if kind=="floor" else "objects"
	var placed:bool=check(sent==1 and last_notice()[1]==true,"Click for %s at %s was accepted: %s"%[kind,str(cell),str(notices)])
	placed=check(w.state[layer].get(World.key(cell),{}).get("type")==kind and snap().get(layer,{}).get(World.key(cell),{}).get("type")==kind,"%s stands at %s on server and client"%[kind,str(cell)]) and placed
	if kind=="door":
		return placed
	return check(same(bag(),plus(before,negate(piece_cost(kind)))) and same(snap_bag(),bag()),"%s cost exactly %s: %s"%[kind,JSON.stringify(piece_cost(kind)),JSON.stringify(bag())]) and placed

## Interact key beside the door; the notice and both worlds agree.
func toggle_door(want_open:bool,stand:Vector2i)->bool:
	if not await walk_to([stand],"to the door (%s)"%("open" if want_open else "close")):return false
	notices.clear()
	await key(bound("interact"))
	await hud_tick()
	var k:=cell_key(Layouts.HOUSE_DOOR)
	return check(bool(w.state.objects[k].get("open",false))==want_open and bool(snap().objects[k].get("open",false))==want_open and str(last_notice()[0])==("門打開了" if want_open else "門關好了"),"Interact key %s the door: %s"%["opens" if want_open else "closes",str(notices)])

## HouseCheck in the real build catalog, plus the helper called on the same snapshot.
func inspect_house(label:String)->bool:
	app._build_menu()
	await frames(3)
	var entry:=app.modal.find_child("HouseCheck",true,false) as Button if is_instance_valid(app.modal) else null
	if not check(entry!=null and not entry.disabled,"HouseCheck is in the build catalog "+label):return false
	entry.pressed.emit()
	await frames(3)
	var r:Dictionary=app.modal.get_meta("house_check_result",{}) if is_instance_valid(app.modal) else {}
	var direct:Dictionary=HouseRooms.inspect(snap(),origin+Layouts.HOUSE_FLOOR[0])
	for result:Dictionary in [r,direct]:
		var cells:Array=result.get("cells",[])
		var exact:=cells.size()==4 and Layouts.HOUSE_FLOOR.all(func(c):return cells.has(origin+c))
		check(bool(result.get("found",false)) and bool(result.get("complete",false)) and exact,"Inspect %s: the exact 2x2 room is complete"%label)
		check(int(result.get("area",0))==4 and int(result.get("door_count",0))==1 and int(result.get("gap_count",-1))==0 and int(result.get("roof_missing",-1))==0 and int(result.get("bed_count",0))==1 and bool(result.get("reachable_bed",false)),"Inspect %s: door, sealed ring, 4 roofs, reachable bed: %s"%[label,JSON.stringify(result.get("missing",[]))])
	var status:=app.modal.find_child("HouseStatus",true,false) as Label if is_instance_valid(app.modal) else null
	check(status!=null and not status.text.is_empty() and r.get("complete",false)==true,"HouseCheck panel reports the room %s"%label)
	var actions:=app.modal.find_child("HouseFooter",true,false) as Control
	var scroll:=app.modal.find_child("ModalScroll",true,false) as ScrollContainer
	check(actions!=null and scroll!=null and not scroll.is_ancestor_of(actions) and root.get_visible_rect().encloses(actions.get_global_rect()),"Room inspection buttons sit in a fixed, fully visible footer")
	if label=="after reload":await shot("07-inspection-after-reload")
	await close_modal_with_esc("house check "+label)
	return true
