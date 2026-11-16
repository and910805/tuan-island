extends SceneTree
## Tianwei world scene integration. Seeded in-process Session snapshots (not a
## socket test); the real WorldView draws them in the scene tree. Headless-capable.
const World=preload("res://scripts/world.gd")
const Flower=preload("res://scripts/flower_nursery.gd")
const View=preload("res://scripts/world_view.gd")
const FlowerWorldArt=preload("res://scripts/flower_world_art.gd")
const SceneArt=preload("res://scripts/flower_scene_art.gd")
const ACTOR:="flower-scene-PRIVATE-TOKEN"
class FixtureSession extends "res://scripts/session.gd":
	func _ready()->void:
		name="Session"
		session_nonce="flower-scene-audit"
var checks:=0
var failures:=0
var session
var view
func expect(ok:bool,label:String)->void:
	checks+=1
	if not ok:
		failures+=1
		push_error(label)
func _initialize()->void:run.call_deferred()

func place(region:String,at:Vector2)->void:
	var person:Dictionary=session.world.state.players[ACTOR]
	person.region=region
	person.x=at.x
	person.y=at.y
	session._send_snapshot(1)
	view.update_snapshot(session.snapshot,session.own_id)
	view.display_positions[session.own_id]=at

func render()->void:
	view.queue_redraw()
	await process_frame
	await process_frame

func label_ids()->Array:
	var ids:=[]
	for entry in view.world_labels:ids.append(str(entry.id))
	return ids

func run()->void:
	session=FixtureSession.new()
	root.add_child(session)
	session.set_physics_process(false)
	session.world=World.new()
	session.world.add_player(ACTOR,"花圃旅人")
	session.peers={1:ACTOR}
	var record:Dictionary=Flower.FRESH.duplicate(true)
	record.letter=true;record.intro=true
	session.world.state.flower_nursery.players[ACTOR]=record
	view=View.new()
	view.village_art_preview=true
	root.add_child(view)
	view.set_process(false)

	# Snapshot shape consumed by the scene.
	place(Flower.REGION,Flower.ARRIVAL)
	var nursery:Dictionary=session.snapshot.get("flower_nursery",{})
	expect(nursery.get("garden",{}).has("complete") and nursery.get("own",{}).has("own_record"),"snapshot carries garden + own record")
	expect(FlowerWorldArt.garden_complete({})==false and FlowerWorldArt.own_record({"flower_nursery":"bad"}).is_empty(),"defensive reads tolerate missing/bad snapshot fields")

	# Focus at every site, using the same 3.2 nearest rule as main.gd.
	var sites:={"farmer":Flower.FARMER,"seed":Flower.SEED_TABLE,"dye":Flower.DYE_TABLE,"market":Flower.MARKET,"garden":Flower.GARDEN_CELL,"xinghe":Flower.XINGHE}
	for site in sites:
		var cell:Vector2i=sites[site]
		place(Flower.REGION,Vector2(cell)+Vector2(0.5,1.5))
		var focus:String=view.interaction_focus()
		expect(focus=="flower:"+site,"focus %s near %s got %s"%[site,cell,focus])
		await render()
		expect(label_ids().has("flower:"+site),"focused %s label drawn"%site)
		var titles:=[]
		for entry in view.world_labels:if entry.id=="flower:"+site:titles.append(entry.title)
		expect(titles==[FlowerWorldArt.SITE_LABELS[site]],"%s label is Chinese site name %s"%[site,titles])
	place(Flower.REGION,Flower.ARRIVAL)
	expect(view.interaction_focus()=="transit:transfer","arrival focuses the shuttle stop")
	await render()
	var ids:=label_ids()
	expect(ids.has("transit:transfer"),"shuttle stop label shown when focused")
	expect(ids.has("flower:farmer") and ids.has("flower:xinghe"),"residents 阿蕾/星禾 always labelled")
	expect(not ids.has("flower:seed") and not ids.has("flower:market"),"unfocused stations unlabelled")
	place(Flower.REGION,Vector2(40.5,13.5))
	expect(view.interaction_focus()=="","far corner has no focus")

	# Tianwei never exposes Lanyang canal/memory/gardener focus or labels.
	var leaked:=false
	session.world.state.lanyang_life.repaired=true
	for y in range(Flower.LAND.position.y,Flower.LAND.end.y):
		for x in range(Flower.LAND.position.x,Flower.LAND.end.x):
			place(Flower.REGION,Vector2(x,y)+Vector2(0.5,0.5))
			var focus:String=view.interaction_focus()
			if focus.begins_with("ditch:") or focus.begins_with("memory:") or focus=="gardener" or focus=="travel":leaked=true
			if not (focus=="" or focus.begins_with("flower:") or focus.begins_with("transit:")):leaked=true
	expect(not leaked,"tianwei focus only flower:/transit: across the whole land")
	await render()
	for entry in view.world_labels:
		var id:=str(entry.id)
		expect(not (id.begins_with("ditch:") or id.begins_with("memory:") or id=="gardener" or entry.title in ["清理水圳","觀察水路","星禾的園藝服務"]),"no Lanyang label in tianwei (%s)"%id)

	# Market art follows garden completion.
	var daily:=SceneArt.market_texture(false)
	var bloom:=SceneArt.market_texture(true)
	expect(daily!=null and bloom!=null and daily!=bloom,"market has distinct daily/complete textures")
	place(Flower.REGION,Vector2(Flower.MARKET)+Vector2(0.5,1.5))
	expect(not FlowerWorldArt.garden_complete(view.data),"fresh garden not complete")
	await render()
	session.world.state.flower_nursery.garden.complete=true
	session.world.state.flower_nursery.garden.completed_at=1.0
	place(Flower.REGION,Vector2(Flower.MARKET)+Vector2(0.5,1.5))
	expect(FlowerWorldArt.garden_complete(view.data),"completed garden visible to the view")
	expect(SceneArt.market_texture(FlowerWorldArt.garden_complete(view.data))==bloom,"market switches to complete texture")
	await render()
	expect(label_ids().has("flower:market"),"complete scene still draws market")

	# Lanyang unchanged: blockage focus/label still present there.
	session.world.state.lanyang_life.repaired=false
	var blockage:Vector2i=World.LANYANG_LIFE.BLOCKAGES[0]
	place(World.REGIONS.LANYANG,Vector2(blockage)+Vector2(0.5,0.5))
	expect(view.interaction_focus()=="ditch:"+World.key(blockage),"lanyang blockage focus preserved")
	await render()
	expect(label_ids().has("ditch:"+World.key(blockage)),"lanyang blockage label preserved")
	place(World.REGIONS.LANYANG,Vector2(World.LANYANG_LIFE.SERVICE)+Vector2(0.5,0.5))
	expect(view.interaction_focus()=="gardener","lanyang gardener focus preserved")

	view.queue_free()
	session.queue_free()
	await process_frame
	print("FLOWER_SCENE_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures else 0)
