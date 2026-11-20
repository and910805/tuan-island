extends SceneTree
## D16 糰糰火鍋: festival-preparation unlock on the C12 stove + optional shared-table photo helpers.
##
## Contract pinned here (host World is the only authority; the UI predicate is display only):
##   - the 2x2 公共廚房灶台 queues `trout_hotpot` only once the festival preparation is done: all six public
##     island projects (World.island_project_mask() == ISLAND_NOTES.project_mask()) OR the festival was
##     already opened (`festival_story_open`, permanent, so later seasons / old saves are never locked out);
##   - nothing is stored: the unlock is derived, so no save field, no migration;
##   - a refused request changes nothing (bag, queue); every other dish is unaffected; jobs queued before
##     are never touched (the gate is read only when a NEW job is queued);
##   - the early one-cell stove keeps cooking it with its old numbers;
##   - the client predicate (World.festival_prep_unlocked_in, Controller.festival_locked) agrees with the host;
##   - the optional photo helpers are local only (user:// path, hashed id, no network).
## Pure World + fake app dictionaries: works with --headless. Photo capture itself needs a window (Codex QA).

const World=preload("res://scripts/world.gd")
const K=World.KITCHEN_STOVE
const Cooking=preload("res://scripts/cooking_queue_ui.gd")
const Almanac=preload("res://scripts/life_ui_almanac.gd")
const KIND:="kitchen_stove"
const DISH:="trout_hotpot"
const BOARD:=Vector2i(40,29)
const HOME:=Vector2i(41,33)
const OLD:=Vector2i(43,33)
const STAND:=Vector2(41.5,36.5)
const EAST:=Vector2(43.5,34.5)
const MOVER:=Vector2(42.5,35.5)
const A:="festival-a"
const B:="festival-b"
const FULL:=63 # six public projects

class FestivalWorld extends World:
	var project_fixture:=0
	func island_project_mask() -> int:
		return project_fixture

var world:FestivalWorld
var path:String
var checks:=0
var failures:=0
var serial:=0

func _initialize()->void:
	run.call_deferred()

func expect(ok:bool,label:String)->void:
	checks+=1
	if not ok:
		failures+=1
		push_error(label)

func act(verb:String,tile:Vector2i,extra:="",w:World=null)->Dictionary:
	serial+=1
	var target:World=world if w==null else w
	return target.act(A,"festival-hotpot-%d"%serial,verb,tile,extra)

func bag(item:String,w:World=null)->int:
	var target:World=world if w==null else w
	return int(target.state.players[A].inventory.get(item,0))

func put(at:Vector2)->void:
	world.state.players[A].x=at.x
	world.state.players[A].y=at.y

func obj(tile:Vector2i)->Dictionary:
	return world.state.objects.get(World.key(tile),{})

func stock()->Dictionary:
	return {"wood":500,"stone":300,"fiber":100,"clay":30,"radish":20,"cabbage":10,"star_mushroom":20,"snow_trout":10}

func fresh()->void:
	for x in range(38,51):
		for y in range(32,41):
			var k:=World.key(Vector2i(x,y))
			world.state.objects.erase(k)
			world.state.crops.erase(k)
			world.state.ground.erase(k)
	var person:Dictionary=world.state.players[A]
	person.inventory=stock()
	person.builds=0
	person.region=World.REGIONS.HOME
	world.state.public_kitchen=World.SAVE_SCHEMA.public_kitchen_fresh()
	world.state.festival_story_open=false
	world.project_fixture=0
	put(STAND)

func open_island()->void:
	world.state.time=720.0
	var stories:Dictionary=world.state.players[A].get("stories",{})
	stories["aru"]=maxi(2,int(stories.get("aru",0)))
	world.state.players[A]["stories"]=stories
	for x in range(38,51):
		for y in range(32,41):world.state.removed[World.key(Vector2i(x,y))]=true
	put(Vector2(BOARD)+Vector2(0.5,1.5))
	expect(act("donate",BOARD).ok and world.state.board==true,"fixture: Q03 through the real donate")
	world.state.players[A].inventory.merge(World.CHAPTER_ONE.PICNIC_PORTIONS,true)
	expect(act("picnic",BOARD).ok and world.state.picnic==true,"fixture: the picnic through the real action")

func finish()->void:
	for suffix in ["",".bak",".tmp",".staged",".writer-lock",".corrupt"]:
		if FileAccess.file_exists(path+suffix):DirAccess.remove_absolute(path+suffix)
	print("FESTIVAL_HOTPOT_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

# -------------------------------------------------------------- scenarios --

func rule_scenario()->void:
	expect(K.FESTIVAL_DISH==DISH and K.dish(DISH).source=="風鈴節籌備","D16 keeps its stable id and its 風鈴節籌備 source")
	expect(K.festival_gated(KIND,DISH) and not K.festival_gated("stove",DISH) and not K.festival_gated(KIND,"soup") and not K.festival_gated(KIND,"seafood_rice"),"only D16 on the C12 stove is gated")
	expect(not K.festival_prep_done({},0,FULL) and not K.festival_prep_done({},FULL-1,FULL) and not K.festival_prep_done({},FULL-32,FULL),"no projects or five of six do not unlock")
	expect(K.festival_prep_done({},FULL,FULL) and K.festival_prep_done({},FULL|64,FULL),"all six public projects unlock (extra local-news bits are ignored)")
	expect(K.festival_prep_done({"festival_story_open":true},0,FULL),"an opened festival unlocks on its own, for later seasons and old saves")
	expect(not K.festival_prep_done({"festival_story_open":"yes"},0,FULL) and not K.festival_prep_done({},0,0) and not K.festival_prep_done({},FULL,0),"a malformed flag or an empty required mask never unlocks")
	expect(World.ISLAND_NOTES.project_mask()==FULL,"the required mask is the six listed public projects")
	expect(World.RECIPES[DISH].ingredients=={"snow_trout":1,"cabbage":1,"star_mushroom":1} and int(World.RECIPES[DISH].time)==60,"the early-stove recipe numbers are unchanged")
	var table:Dictionary=World.stove_recipes(KIND)[DISH]
	expect(table.ingredients=={"cabbage":1,"star_mushroom":2,"snow_trout":1} and float(table.time)==180.0 and int(table["yield"])==4 and K.restore_for(DISH)==50,"the C12 table still holds the canonical D16 numbers")

func host_scenario()->void:
	fresh()
	expect(act("build",HOME,KIND).ok,"fixture: C12 stove built")
	put(EAST)
	var cabbage:=bag("cabbage")
	var mushroom:=bag("star_mushroom")
	var trout:=bag("snow_trout")
	var before:=world.state.duplicate(true)
	expect(not world.festival_prep_unlocked(),"fixture: nothing prepared yet")
	var locked:=act("queue_cook",HOME+Vector2i.ONE,DISH)
	expect(not locked.ok and locked.message==K.LOCKED_MESSAGE,"locked: the host names the festival preparation: "+str(locked.get("message","")))
	expect(bag("cabbage")==cabbage and bag("star_mushroom")==mushroom and bag("snow_trout")==trout and not obj(HOME).has("cooking"),"locked: bag and queue are untouched")
	expect(not act("cook",HOME,DISH).ok and not obj(HOME).has("cooking") and bag("snow_trout")==trout,"locked: the older cook verb is gated the same way")
	expect(world.state.festival_story_open==before.festival_story_open,"locked: nothing about the festival changed")
	# Five of six projects are still not enough (each bit alone is missing in turn).
	for bit in 6:
		world.project_fixture=FULL&~(1<<bit)
		expect(not act("queue_cook",HOME,DISH).ok and not obj(HOME).has("cooking") and bag("snow_trout")==trout,"locked while project bit %d is missing"%bit)
	# Another dish is never affected by the lock.
	world.project_fixture=0
	var radish:=bag("radish")
	expect(act("queue_cook",HOME,"soup").ok and bag("radish")==radish-2,"locked: soup still queues on the same stove")
	expect(act("cancel_cook",HOME).ok and bag("radish")==radish,"locked: and cancels with an exact refund")
	# All six public projects: opens, canonical snapshot, exact debit.
	world.project_fixture=FULL
	expect(world.festival_prep_unlocked() and not world.festival_story_view().opened,"six projects unlock it BEFORE opening night")
	var queued:=act("queue_cook",HOME+Vector2i.DOWN,DISH)
	expect(queued.ok,"unlocked: D16 queues from another corner: "+str(queued.get("message","")))
	expect(bag("cabbage")==cabbage-1 and bag("star_mushroom")==mushroom-2 and bag("snow_trout")==trout-1,"unlocked: exactly 1 cabbage, 2 star mushrooms, 1 snow trout")
	var job:Dictionary=obj(HOME).get("cooking",{}).get("active",{})
	expect(not job.is_empty() and job.kind==DISH and float(job.duration)==180.0 and int(job["yield"])==4 and job.ingredients=={"cabbage":1,"star_mushroom":2,"snow_trout":1},"unlocked: the job is the canonical 180 s / 4 portions snapshot")
	expect(not world.festival_story_view().opened and not world.state.festival_story_open,"queueing the dish does not open the festival")
	# A queued job outlives the gate: it finishes and is claimed even if the unlock could not be proven any more.
	world.project_fixture=0
	expect(not act("queue_cook",HOME,DISH).ok and bag("snow_trout")==trout-1,"gate returns for a NEW job")
	expect(world.step(181.0,true) and (obj(HOME).cooking.ready as Array).size()==1,"the earlier job still finishes")
	var claimed:=act("claim_cook",HOME+Vector2i.ONE)
	expect(claimed.ok and bag(DISH)==4,"and is claimed: 4 portions of the stable item id: "+str(claimed.get("message","")))

func repeat_season_scenario()->void:
	fresh()
	expect(act("build",HOME,KIND).ok,"fixture: C12 stove built")
	put(EAST)
	# After opening night (set once, never cleared) the dish stays available whatever the project list says.
	world.state.festival_story_open=true
	world.project_fixture=0
	expect(world.festival_prep_unlocked(),"an opened festival keeps it unlocked")
	var queued:=act("queue_cook",HOME,DISH)
	expect(queued.ok and bag("snow_trout")==9,"a later season: still queues: "+str(queued.get("message","")))
	for repeat in 2:
		expect(world.step(181.0,true) and act("claim_cook",HOME).ok and act("queue_cook",HOME,DISH).ok,"repeat %d: finish, claim and queue again stay allowed"%repeat)
	# Existing save progress: the flag survives a save/reload and the PLAIN World (no fixture) reads it back.
	expect(world.save(),"the opened world saves")
	var back:=World.new()
	expect(back.load_world(path) and back.festival_prep_unlocked() and bool(back.festival_story_view().opened),"reload: an old opened save is unlocked without migration")
	expect(bag(DISH,back)==8 and bag("snow_trout",back)==7 and (back.state.objects[World.key(HOME)].cooking.active as Dictionary).kind==DISH,"reload: the two claimed rounds (8 portions) and the running D16 job survive")
	var plain:=World.new()
	expect(not plain.festival_prep_unlocked(),"a brand-new world is still locked (no stored flag appears by itself)")
	var shape:=plain.state.duplicate(true)
	expect(not shape.has("festival_prep") and not shape.has("hotpot_unlocked"),"no new save field exists")

func legacy_scenario()->void:
	fresh()
	put(MOVER)
	expect(act("build",OLD,"stove").ok and obj(OLD).type=="stove" and not obj(OLD).has("kitchen_stove_part"),"fixture: the early one-cell stove")
	var trout:=bag("snow_trout")
	expect(not world.festival_prep_unlocked(),"fixture: festival preparation not done")
	var queued:=act("queue_cook",OLD,DISH)
	expect(queued.ok and bag("snow_trout")==trout-1 and bag("star_mushroom")==19,"the legacy stove keeps cooking it with the old numbers (1 trout, 1 cabbage, 1 mushroom)")
	var job:Dictionary=obj(OLD).get("cooking",{}).get("active",{})
	expect(job.kind==DISH and float(job.duration)==60.0 and int(job["yield"])==4,"legacy job: 60 s, 4 portions")

func snapshot_scenario()->void:
	# The client predicate must agree with the host rule for every combination.
	for opened in [false,true]:
		for projects in [0,FULL-1,FULL,FULL|64]:
			var probe:={"festival_story_open":opened,"festival_story":{"opened":opened,"projects":projects}}
			var host_says:=K.festival_prep_done({"festival_story_open":opened},projects,World.ISLAND_NOTES.project_mask())
			expect(World.festival_prep_unlocked_in(probe)==host_says,"client and host agree (opened %s, projects %d)"%[str(opened),projects])
	expect(not World.festival_prep_unlocked_in({}) and not World.festival_prep_unlocked_in({"festival_story":"junk"}),"a missing or malformed snapshot stays locked")
	# The workbench of a C12 stove greys the dish out; the early stove and other dishes are never greyed.
	var c:=Cooking.Controller.new()
	c.cell=HOME
	var snap:={"objects":{World.key(HOME):{"type":KIND}},"festival_story":{"opened":false,"projects":0}}
	c.app={"session":{"snapshot":snap}}
	expect(c.festival_locked(DISH) and not c.festival_locked("soup") and not c.festival_locked("seafood_rice"),"C12 workbench: only D16 is held back")
	snap.festival_story.projects=FULL
	expect(not c.festival_locked(DISH),"C12 workbench: six projects release it")
	snap.festival_story.projects=0
	snap.festival_story_open=true
	expect(not c.festival_locked(DISH),"C12 workbench: an opened festival releases it")
	snap.festival_story_open=false
	snap.objects[World.key(HOME)].type="stove"
	expect(not c.festival_locked(DISH),"early-stove workbench: never held back")
	c.free()

func photo_scenario()->void:
	var app:={"session":{"own_id":"peer-secret-id"}}
	var photo:String=Almanac.hotpot_photo_path(app)
	expect(photo.begins_with("user://") and photo.ends_with(".png") and not photo.contains("peer-secret-id"),"the photo stays local under user:// and never carries the raw id")
	expect(photo==Almanac.hotpot_photo_path(app) and photo!=Almanac.hotpot_photo_path({"session":{"own_id":"someone-else"}}),"one stable file per player")
	expect(photo!=Almanac.dog_photo_path(app) and photo!=Almanac.seal_photo_path(app),"it never overwrites another photo")
	expect(not Almanac.hotpot_round_on_table({}) and not Almanac.hotpot_round_on_table({"community":{"hotpot":{"portions":0,"claimed":{}}}}),"no round on the table, no photo prompt")
	expect(Almanac.hotpot_round_on_table({"community":{"table":"39,30","hotpot":{"portions":3,"claimed":{}}}}),"a served round (even partly eaten) is a photo moment")
	expect(not FileAccess.file_exists(photo),"fixture: this test never writes a photo")

func coseat_scenario()->void:
	# Co-seated photo: read-only on the existing seat pose; serving and claiming keep working while seated.
	fresh()
	var table:=World.COMMUNITY.table_cell(world.state)
	expect(table!=World.COMMUNITY.NO_CELL,"fixture: the shared table exists after the picnic")
	if table==World.COMMUNITY.NO_CELL:return
	var seat_field:String=World.RESIDENT_GOALS.MASTER_BENCH_SEAT
	world.add_player(B,"同桌")
	world.state.players[B].region=World.REGIONS.HOME
	var chair_a:=table+Vector2i(-1,2)
	var chair_b:=table+Vector2i(1,2)
	var near_a:=World.key(chair_a)
	var near_b:=World.key(chair_b)
	var far:=World.key(Vector2i(50,40))
	for tile:Vector2i in [chair_a,chair_b]:
		world.state.removed[World.key(tile)]=true
		put(Vector2(table)+Vector2(0.5,1.5))
		var built:=act("build",tile,World.INDUSTRY.WOOD_CHAIR)
		expect(built.ok,"builds a usable shared chair: "+str(built.get("message","")))
	world.state.objects[far]={"type":World.INDUSTRY.WOOD_CHAIR,"owner":A,"items":{}}
	var snap:Dictionary=world.state
	var here:Dictionary=snap.players[A]
	expect(Almanac.hotpot_photo_mode(snap,A,here)==Almanac.MODE_NONE,"no round on the table: no photo, seated or not")
	world.state.players[A].inventory.trout_hotpot=4
	put(Vector2(table)+Vector2(0.5,1.5))
	var served:=act("serve_hotpot",table)
	expect(served.ok and Almanac.hotpot_round_on_table(snap),"fixture: a real hotpot round is served: "+str(served.get("message","")))
	# Solo, standing at the table: the original fallback, never blocked.
	expect(Almanac.hotpot_photo_mode(snap,A,here)==Almanac.MODE_SOLO,"standing at the table alone: solo photo")
	put(Vector2(table)+Vector2(9.5,9.5))
	expect(Almanac.hotpot_photo_mode(snap,A,here)==Almanac.MODE_NONE,"far from the table and not seated: no photo")
	# Seated alone near the table: solo.
	put(Vector2(table)+Vector2(0.5,1.5))
	expect(act(World.RESIDENT_GOALS.MASTER_BENCH_SIT,chair_a).ok,"the owner sits through the real action")
	expect(Almanac.hotpot_tablemates(snap,A)==0 and Almanac.hotpot_photo_mode(snap,A,here)==Almanac.MODE_SOLO,"seated near the table, nobody else: solo")
	# A second player on a real seat near the table: together.
	var other:Dictionary=snap.players[B]
	other.x=float(table.x)+1.5
	other.y=float(table.y)+1.5
	expect(world.act(B,"d16-guest-sit",World.RESIDENT_GOALS.MASTER_BENCH_SIT,chair_b).ok,"the second player sits through the real action")
	expect(Almanac.hotpot_tablemates(snap,A)==1 and Almanac.hotpot_photo_mode(snap,A,here)==Almanac.MODE_TOGETHER,"two players seated near the table: together")
	expect(Almanac.hotpot_tablemates(snap,B)==1,"the pairing is symmetric")
	put(Vector2(table)+Vector2(0.5,1.5))
	expect(act("claim_hotpot",table).ok and bag("trout_hotpot")==1,"seated, the player still claims a bowl through the normal action")
	expect(here[seat_field].cell==near_a and other[seat_field].cell==near_b,"the photo helpers never move or clear a seat")
	# Not co-seated: far seat, other region, stale seat object, malformed pose.
	other[seat_field]={"cell":far,"side":0}
	expect(Almanac.hotpot_photo_mode(snap,A,here)==Almanac.MODE_SOLO,"the other player seated far away: solo")
	other[seat_field]={"cell":near_b,"side":1}
	other.region="north"
	expect(Almanac.hotpot_photo_mode(snap,A,here)==Almanac.MODE_SOLO,"the other player in another region: solo")
	other.region=World.REGIONS.HOME
	world.state.objects.erase(near_b)
	expect(Almanac.hotpot_photo_mode(snap,A,here)==Almanac.MODE_SOLO,"a stale pose without its seat object does not count")
	world.state.objects[near_b]={"type":World.INDUSTRY.WOOD_CHAIR,"owner":A,"items":{}}
	for junk in [{"cell":7},{"cell":"x,y"},{"cell":"41"},"sit",null]:
		other[seat_field]=junk
		expect(Almanac.hotpot_tablemates(snap,A)==0,"a malformed pose is ignored: "+str(junk))
	# Solo fallback guest: a resident before opening night, nobody extra when together or once visitors stand there.
	expect(Almanac.hotpot_guest_for(snap,Almanac.MODE_SOLO)=="milu","solo before opening night: 米露 joins (existing sprite)")
	expect(World.Village.NPCS.has(Almanac.HOTPOT_SOLO_GUEST),"the guest is a real resident")
	expect(Almanac.hotpot_guest_for(snap,Almanac.MODE_TOGETHER)=="" and Almanac.hotpot_guest_for(snap,Almanac.MODE_NONE)=="","together or no photo: no extra guest")
	expect(Almanac.hotpot_guest_for({"festival_story_open":true},Almanac.MODE_SOLO)=="","after opening night the visitors already stand by the table")
	expect(Almanac.hotpot_guest_for({"festival_story_open":"yes"},Almanac.MODE_SOLO)=="milu","a malformed flag is not 'open' and raises no error")
	# The shipped manifest and every other photo path stay untouched by this feature.
	expect(not FileAccess.file_exists(Almanac.hotpot_photo_path({"session":{"own_id":A}})),"fixture: no photo file was written")

func run()->void:
	path="user://festival-hotpot-%d.json"%Time.get_ticks_usec()
	world=FestivalWorld.new()
	world.save_path=path
	world.add_player(A,"火鍋主")
	world.state.players[A].inventory=stock()
	open_island()
	rule_scenario()
	host_scenario()
	repeat_season_scenario()
	legacy_scenario()
	snapshot_scenario()
	photo_scenario()
	coseat_scenario()
	finish()
