extends SceneTree

const World=preload("res://scripts/world.gd")
const View=preload("res://scripts/world_view.gd")
const Preview=preload("res://scripts/village_preview_art.gd")
var checks:=0
var failures:=0

func _initialize() -> void:
	call_deferred("run")

func expect(condition:bool,detail:String) -> void:
	checks+=1
	if not condition:
		failures+=1
		push_error(detail)

func run() -> void:
	var view:=View.new()
	expect(not view.village_art_preview,"Village preview is opt-in")
	var viewport:=SubViewport.new()
	root.add_child(viewport)
	viewport.add_child(view)
	var snapshot:Dictionary={"players":{"tester":{"x":World.SPAWN.x,"y":World.SPAWN.y}}}
	for size in [Vector2i(1024,600),Vector2i(1280,800),Vector2i(1920,1080)]:
		viewport.size=size
		for preview_mode in [false,true]:
			view.village_art_preview=preview_mode
			for zoom in [1.0,2.0]:
				view.zoom=zoom
				view.update_snapshot(snapshot,"tester")
				view._process(0.1)
				var anchor:=Vector2(size)*0.5+Vector2(0,40) if preview_mode else Vector2(740,460)
				expect((view.screen(World.SPAWN)*zoom).is_equal_approx(anchor),"Camera retains the anchor for its mode")
				for point in [Vector2i(25,19),Vector2i(40,29),Vector2i(55,31),Vector2i(60,56)]:
					var center:=Vector2(point)+Vector2(0.5,0.5)
					expect(view.to_cell(view.screen(center)*zoom)==point,"Cell center round-trips at either zoom")
	viewport.free()
	for inside in [Vector2i(25,19),Vector2i(60,19),Vector2i(25,56),Vector2i(60,56)]:
		expect(Preview.contains(inside),"Preview includes all four corner cells")
	for outside in [Vector2i(24,19),Vector2i(61,19),Vector2i(25,18),Vector2i(25,57)]:
		expect(not Preview.contains(outside),"Preview excludes neighboring cells")

	var world:=World.new()
	world.state.board=true
	# Search the artwork's road at quarter-tile resolution, respecting real foot collision.
	var origin:=Vector2i(World.SPAWN*4.0)
	var reached:Dictionary={origin:true}
	var queue:Array[Vector2i]=[origin]
	var cursor:=0
	expect(Preview.path_at(World.SPAWN),"Spawn lies on the illustrated lane")
	while cursor<queue.size():
		var point:=queue[cursor]
		cursor+=1
		for direction in [Vector2i.UP,Vector2i.DOWN,Vector2i.LEFT,Vector2i.RIGHT]:
			var candidate:Vector2i=point+direction
			var position:=Vector2(candidate)/4.0
			if reached.has(candidate) or not Preview.contains(Vector2i(position.floor())):continue
			if not world.can_stand(position) or not Preview.path_at(position):continue
			reached[candidate]=true
			queue.append(candidate)
	for entry in [Vector2(38.5,30.5),Vector2(40.5,30.5),Vector2(43.5,30.5),Vector2(44.5,30.5),Vector2(56.5,30.5)]:
		expect(reached.has(Vector2i(entry*4.0)),"Illustrated lane reaches the interaction approach at %s"%entry)
	expect(not World.land(Vector2i(51,55)) and world.water(Vector2i(51,55)),"Coastal prop is anchored in existing water")
	for x in [49,50]:
		for y in range(51,55):
			expect(World.land(Vector2i(x,y)) and not world.water(Vector2i(x,y)),"Landing boards stay on existing dry land")

	var preview:=Preview.new()
	var terrain_path:="res://assets/village-preview/terrain.png"
	var props_path:="res://assets/village-preview/props.png"
	if not ResourceLoader.exists(terrain_path) or not ResourceLoader.exists(props_path):
		expect(false,"Preview PNG assets must be present and imported")
	else:
		preview.setup()
		check_atlas(load(terrain_path),load(props_path))
		expect(preview.tiles.size()==16 and preview.tile_textures.size()==16 and preview.props.size()==16,"Renderer loads all 16 terrain and prop tiles")
		if preview.tiles.size()==16:
			check_ground(preview,world)
	print("VILLAGE_VISUAL_CONTRACT checks=%d failures=%d"%[checks,failures])
	quit(1 if failures else 0)

func check_atlas(terrain:Texture2D,props:Texture2D) -> void:
	expect(terrain.get_size()==Vector2(128,128),"Terrain atlas contains a 4×4 grid of 32 px tiles")
	expect(props.get_size()==Vector2(256,256),"Prop atlas contains a 4×4 grid of 64 px sprites")
	if props.get_size()!=Vector2(256,256):return
	var pixels:=props.get_image()
	for i in range(16):
		var region:=pixels.get_region(Rect2i((i%4)*64,(i/4)*64,64,64))
		var used:=region.get_used_rect()
		expect(used.has_area() and used.position.x>0 and used.position.y>0 and used.end.x<64 and used.end.y<64,"Prop %d has art and a transparent border on every side"%i)

func check_ground(preview:Preview,world:World) -> void:
	# Use an isolated virtual path to detect any accidental persistence while composing.
	world.save_path="user://village-visual-contract-%s.json"%Time.get_ticks_usec()
	for bridge_built in [false,true]:
		world.state.board=bridge_built
		var state_before:=var_to_bytes(world.state)
		for x in [55,56]:
			for y in range(28,33):
				var point:=Vector2i(x,y)
				var result:=preview.compose_ground(point,bridge_built)
				var source:=preview.tiles[8 if world.water(point) else 10]
				expect(result.get_size()==Vector2i(32,32),"Composed terrain is one world tile")
				expect(result.get_pixel(16,16).is_equal_approx(source.get_pixel(16,16)),"Bridge and water agree with World.water at %s"%point)
		var coast:=Vector2i(51,55)
		var first:=preview.compose_ground(coast,bridge_built)
		expect(first.get_data()==preview.compose_ground(coast,bridge_built).get_data(),"Terrain composition is deterministic")
		expect(state_before==var_to_bytes(world.state),"Terrain composition leaves persistent state unchanged")
		expect(not FileAccess.file_exists(world.save_path) and not FileAccess.file_exists(world.save_path+".bak"),"Terrain composition never writes a save")
