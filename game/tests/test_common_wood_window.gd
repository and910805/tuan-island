extends SceneTree
## C04 木窗: the existing "window" ID gets a new recipe (4 wood + 1 glass) while untagged windows
## from older saves keep their original 6 wood + 1 stone dismantle refund.
## Run: --headless --path game --script res://tests/test_common_wood_window.gd

const World=preload("res://scripts/world.gd")
const Fixtures=World.WALL_FIXTURES
const A:="wood-window-alice"
const NEW_WINDOW:=Vector2i(41,35)
const OLD_WINDOW:=Vector2i(42,35)
const THIRD:=Vector2i(43,35)
const BLUEPRINT_AT:=Vector2i(40,35)
const NEW_COST:={"wood":4,"glass":1}
const OLD_COST:={"wood":6,"stone":1}

var world:World
var serial:=0
var checks:=0
var failures:=0
var path:=""

func _initialize()->void:
	run.call_deferred()

func expect(ok:bool,label:String)->void:
	checks+=1
	if not ok:
		failures+=1
		push_error(label)

func key(c:Vector2i)->String:
	return World.key(c)

func obj(c:Vector2i)->Dictionary:
	return world.state.objects.get(key(c),{})

func inv()->Dictionary:
	var out:={}
	var bag:Dictionary=world.state.players[A].inventory
	for item in bag:
		if int(bag[item])!=0:out[str(item)]=int(bag[item])
	return out

func stock(items:Dictionary)->void:
	world.state.players[A].inventory=items.duplicate(true)

func act(action:String,c:Vector2i,extra:="")->Dictionary:
	serial+=1
	var person:Dictionary=world.state.players[A]
	person.x=float(c.x)+0.5
	person.y=float(c.y)+2.5
	return world.act(A,"wood-window-%d"%serial,action,c,extra)

func valid(state:Dictionary)->bool:
	return bool(World.SAVE_SCHEMA.validate(state,World.CROPS,World.BUILD,World.RECIPES,World.SIZE,World.TREE_TIME))

func legacy_window(c:Vector2i)->void:
	world.state.objects[key(c)]={"type":"window","owner":A,"items":{}}

func run()->void:
	path="user://common-wood-window-%d.json"%Time.get_ticks_usec()
	world=World.new()
	world.save_path=path
	world.add_player(A,"Alice")
	world.state.time=740.0

	# --- recipe contract
	var recipe:Dictionary=World.BUILD.window
	expect(recipe.name=="木窗" and int(recipe.wood)==4 and int(recipe.glass)==1 and recipe.size()==3,"Window recipe is 木窗: 4 wood + 1 glass only")
	expect(World.LEGACY_WINDOW_COST=={"wood":6,"stone":1},"Legacy window cost is kept for old dismantles")

	# --- new build: exact cost, discriminator, collision, validation
	stock({"wood":20,"glass":3,"stone":5})
	expect(act("build",NEW_WINDOW,"window").ok,"Build a new window")
	expect(obj(NEW_WINDOW).get("type")=="window" and obj(NEW_WINDOW).get("owner")==A and obj(NEW_WINDOW).get(World.WOOD_WINDOW_FIELD)==true,"New window carries the discriminator")
	expect(inv()=={"wood":16,"glass":2,"stone":5},"New window charges exactly 4 wood + 1 glass: "+str(inv()))
	expect(world.blocked(NEW_WINDOW),"Window tile still collides")
	expect(valid(world.state.duplicate(true)),"State with a new window validates")
	stock({"wood":20,"stone":9})
	var short:=act("build",THIRD,"window")
	expect(not short.ok and not world.state.objects.has(key(THIRD)) and inv()=={"wood":20,"stone":9},"Stone cannot replace glass and nothing is charged")

	# --- legacy window: untagged object, validates, refunds original materials
	stock({"wood":1})
	legacy_window(OLD_WINDOW)
	expect(valid(world.state.duplicate(true)),"Untagged legacy window still validates")
	expect(world.blocked(OLD_WINDOW),"Legacy window collides")
	expect(act("remove",OLD_WINDOW).ok and not obj(OLD_WINDOW).has("type"),"Dismantle the legacy window")
	expect(inv()=={"wood":7,"stone":1},"Legacy window refunds 6 wood + 1 stone and no free glass: "+str(inv()))

	# --- new window dismantle returns exactly the new cost
	stock({"wood":1})
	expect(act("remove",NEW_WINDOW).ok and not obj(NEW_WINDOW).has("type"),"Dismantle the new window")
	expect(inv()=={"wood":5,"glass":1},"New window refunds exactly 4 wood + 1 glass: "+str(inv()))

	# --- validator rejects a malformed discriminator
	stock({"wood":20,"glass":3})
	expect(act("build",NEW_WINDOW,"window").ok,"Rebuild a window for validation checks")
	for bad in [false,"true",1]:
		var broken:=world.state.duplicate(true)
		broken.objects[key(NEW_WINDOW)][World.WOOD_WINDOW_FIELD]=bad
		expect(not valid(broken),"Validator rejects wood_window=%s"%str(bad))
	var wrong:=world.state.duplicate(true)
	wrong.objects[key(NEW_WINDOW)].type="wall"
	expect(not valid(wrong),"Validator rejects wood_window on a non-window")

	# --- load keeps the discriminator and legacy windows as they were
	legacy_window(OLD_WINDOW)
	expect(world.save(),"Save mixed windows")
	var loaded:=World.new()
	expect(loaded.load_world(path) and loaded.state.objects[key(NEW_WINDOW)].get(World.WOOD_WINDOW_FIELD)==true and not loaded.state.objects[key(OLD_WINDOW)].has(World.WOOD_WINDOW_FIELD),"Reload never migrates a legacy window to the new cost")

	# --- curtain still hangs on both kinds and protects them from dismantling
	stock({"bamboo":20,"fiber":10,"wood":0})
	var old_hook:=OLD_WINDOW+Vector2i.DOWN
	var new_hook:=NEW_WINDOW+Vector2i.DOWN
	expect(act("build",new_hook,Fixtures.BAMBOO_CURTAIN).ok and act("build",old_hook,Fixtures.BAMBOO_CURTAIN).ok,"Curtain hangs on a new and on a legacy window")
	expect(act("remove",NEW_WINDOW).message==Fixtures.CURTAIN_REMOVE_MESSAGE and act("remove",OLD_WINDOW).message==Fixtures.CURTAIN_REMOVE_MESSAGE,"Windows with curtains cannot be dismantled")
	expect(act("remove",new_hook).ok and act("remove",old_hook).ok,"Curtains come down")
	expect(obj(NEW_WINDOW).get(World.WOOD_WINDOW_FIELD)==true and not obj(OLD_WINDOW).has(World.WOOD_WINDOW_FIELD),"Curtain handling leaves both discriminators untouched")

	# --- blueprint: capture copies style but not provenance; quote/apply use the new cost
	world.state.objects[key(OLD_WINDOW)].style="coast"
	var design:=World.BLUEPRINT_DESIGN.capture(world.state,A,Rect2i(OLD_WINDOW,Vector2i.ONE),"舊窗",World.BUILD,World.NAMES)
	expect(design.ok and design.blueprint.pieces.size()==1,"Capture a legacy styled window")
	if design.ok:
		var piece:Dictionary=design.blueprint.pieces[0]
		expect(piece.kind=="window" and piece.get("style")=="coast","Capture keeps style")
		expect(not var_to_str(design.blueprint).contains(World.WOOD_WINDOW_FIELD),"Capture carries no refund provenance")
		stock({"wood":10,"glass":2,"stone":4})
		world.state.players[A].x=float(BLUEPRINT_AT.x)+0.5
		world.state.players[A].y=float(BLUEPRINT_AT.y)+2.5
		var quote:=world.quote_blueprint(A,design.blueprint,BLUEPRINT_AT)
		expect(quote.get("ok")==true and quote.cost=={"wood":4,"glass":1},"Authoritative quote uses the new cost: "+str(quote))
		expect(inv()=={"wood":10,"glass":2,"stone":4} and not obj(BLUEPRINT_AT).has("type"),"Quote is read-only")
		var applied:=world.apply_blueprint(A,"c".repeat(32),design.blueprint,BLUEPRINT_AT,0,str(quote.get("hash","")))
		expect(applied.get("ok")==true,"Apply the blueprint: "+str(applied.get("message","")))
		expect(obj(BLUEPRINT_AT).get(World.WOOD_WINDOW_FIELD)==true and obj(BLUEPRINT_AT).get("style")=="coast","Applied copy is a new-cost window with the copied style")
		expect(inv()=={"wood":6,"glass":1,"stone":4},"Apply charges 4 wood + 1 glass, no stone: "+str(inv()))
		expect(valid(world.state.duplicate(true)),"State after apply validates")
		# Undo of the blueprint returns the new cost exactly and closes the entry.
		var summary:=world.undo_summary(A)
		expect(summary.get("available")==true,"Blueprint is undoable")
		expect(act(World.UNDO_ACTION,BLUEPRINT_AT,str(summary.get("id",""))).ok and not obj(BLUEPRINT_AT).has("type") and inv()=={"wood":10,"glass":2,"stone":4},"Undo refunds exactly the new cost: "+str(inv()))

	# --- construction undo: historical type/refund survive, changed histories close
	stock({"wood":20,"glass":2})
	expect(act("build",THIRD,"window").ok,"Build a window to undo")
	var build_undo:=world.undo_summary(A)
	expect(act(World.UNDO_ACTION,THIRD,str(build_undo.get("id",""))).ok and not obj(THIRD).has("type") and inv()=={"wood":20,"glass":2},"Undoing a new window build refunds the new cost")

	legacy_window(THIRD)
	stock({"wood":0})
	expect(act("remove",THIRD).ok and inv()=={"wood":6,"stone":1},"Dismantle a legacy window for undo")
	var remove_undo:=world.undo_summary(A)
	expect(act(World.UNDO_ACTION,THIRD,str(remove_undo.get("id",""))).ok,"Undo the legacy dismantle")
	expect(obj(THIRD).get("type")=="window" and not obj(THIRD).has(World.WOOD_WINDOW_FIELD),"Undo restores the legacy window without the new tag")
	expect(inv().is_empty(),"Undo takes back the legacy refund exactly: "+str(inv()))
	expect(act("remove",THIRD).ok and inv()=={"wood":6,"stone":1},"The restored window is still legacy on dismantle")

	stock({"wood":20,"glass":2})
	expect(act("build",THIRD,"window").ok,"Build another window")
	var stale:=world.undo_summary(A)
	expect(act("remove",THIRD).ok,"Dismantle it, changing the watched tile")
	var late:=act(World.UNDO_ACTION,THIRD,str(stale.get("id","")))
	expect(not late.ok and not obj(THIRD).has("type") and inv()=={"wood":20,"glass":2},"A changed history closes without refunding twice")

	expect(valid(world.state.duplicate(true)),"Final state validates")
	for file in [path,path+".bak",path+".tmp"]:
		if FileAccess.file_exists(file):DirAccess.remove_absolute(file)
	print("COMMON_WOOD_WINDOW_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 else 0)
