extends SceneTree

const World=preload("res://scripts/world.gd")
const View=preload("res://scripts/world_view.gd")
const Preview=preload("res://scripts/village_preview_art.gd")
const HOME:=Rect2i(0,0,80,60)
# Colors the removed legacy feather blended toward (water, then land variants).
const LEGACY:=["76b9b4","7fc3ba","a8c88b","acce8d"]
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
	var world:=World.new()
	world.add_player("tester","島民")
	var snapshot:Dictionary=world.state
	for size in [Vector2i(1024,600),Vector2i(1280,800),Vector2i(1920,1080),Vector2i(3840,2160)]:
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
				for fixed_cam in [false,true]:
					view.fixed_area_camera=fixed_cam
					view.update_camera(World.SPAWN,true)
					var half:=view.view_interest_half().clamp(Vector2i.ONE,World.SIZE)
					var center:=Vector2i(World.SPAWN.floor())
					var interest:=Rect2i(center-half,half*2+Vector2i.ONE)
					var original_camera:=view.camera
					for direction in [Vector2(-1,-1),Vector2.ONE]:
						view.camera=original_camera+View.fixed_camera_margin(Vector2(size))*direction/zoom if fixed_cam else original_camera
						expect(interest.encloses(view.drawn_cells().intersection(HOME)),"Network interest covers drawn island cells for the current camera style and zoom")
				view.fixed_area_camera=false
	viewport.free()
	expect(World.SIZE==HOME.size,"Home bounds in this contract match World.SIZE")
	for inside in [Vector2i(0,0),Vector2i(79,0),Vector2i(0,59),Vector2i(79,59),Vector2i(24,19),Vector2i(61,19),Vector2i(25,18),Vector2i(60,59)]:
		expect(Preview.contains(inside),"Preview covers home cell %s, including the old preview seam"%inside)
	for outside in [Vector2i(-1,0),Vector2i(80,0),Vector2i(0,-1),Vector2i(79,60),Vector2i(25,62+1),Vector2i(80,60)]:
		expect(not Preview.contains(outside),"Preview excludes cells beyond home bounds %s"%outside)
	var covered:=0
	for x in range(-2,82):
		for y in range(-2,62):
			if Preview.contains(Vector2i(x,y)):covered+=1
	expect(covered==HOME.size.x*HOME.size.y,"Preview covers exactly the 80x60 home cells")

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
	expect(not World.land(Vector2i(51,59)) and world.water(Vector2i(51,59)),"Coastal prop is anchored in existing water")
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
			check_terrain_chunks(preview)
	print("VILLAGE_VISUAL_CONTRACT checks=%d failures=%d"%[checks,failures])
	quit(1 if failures else 0)

func check_terrain_chunks(preview:Preview) -> void:
	var last:=Preview.chunk_at(Preview.SHORE_BOUNDS.end-Vector2i.ONE)
	for row in range(last.y+1):
		for column in range(last.x+1):
			var chunk:=Vector2i(column,row)
			var bounds:=Preview.chunk_cells(chunk)
			var path:=Preview.chunk_path(chunk)
			var texture:Texture2D=load(path) if ResourceLoader.exists(path) else null
			expect(texture!=null and Vector2i(texture.get_size())==bounds.size*32,"Terrain chunk %s covers exactly its assigned cells"%chunk)
			if texture==null or Vector2i(texture.get_size())!=bounds.size*32:continue
			var pixels:=texture.get_image()
			for cell:Vector2i in [bounds.position,bounds.get_center(),bounds.end-Vector2i.ONE]:
				var original:=preview.compose_ground(cell,false)
				var patch:=pixels.get_region(Rect2i((cell-bounds.position)*32,Vector2i.ONE*32))
				patch.convert(original.get_format())
				expect(patch.get_data()==original.get_data(),"Terrain chunk %s matches composed cell %s"%[chunk,cell])

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
		check_home_edges(preview,bridge_built)
		check_old_seams(preview,bridge_built)
	check_shore_foam(preview)

func legacy_pixels(image:Image,column:int=-1) -> int:
	var count:=0
	for y in range(32):
		for x in ([column] if column>=0 else range(32)):
			var c:=image.get_pixel(x,y)
			for hex in LEGACY:
				var l:=Color(hex)
				if absf(c.r-l.r)<0.004 and absf(c.g-l.g)<0.004 and absf(c.b-l.b)<0.004:
					count+=1
					break
	return count

func distinct_colors(images:Array) -> int:
	var seen:Dictionary={}
	for image in images:
		for y in range(0,32,2):
			for x in range(0,32,2):
				seen[image.get_pixel(x,y).to_rgba32()]=true
	return seen.size()

func check_home_edges(preview:Preview,bridge_built:bool) -> void:
	# Sample every 5th cell along each of the four home edges plus both ends (~60 cells).
	var edges:Dictionary={"left":[],"right":[],"top":[],"bottom":[]}
	var xs:=range(0,HOME.size.x,5)+[HOME.end.x-1]
	var ys:=range(0,HOME.size.y,5)+[HOME.end.y-1]
	for y in ys:
		edges.left.append(Vector2i(HOME.position.x,y))
		edges.right.append(Vector2i(HOME.end.x-1,y))
	for x in xs:
		edges.top.append(Vector2i(x,HOME.position.y))
		edges.bottom.append(Vector2i(x,HOME.end.y-1))
	for edge in edges:
		var images:Array=[]
		for p in edges[edge]:
			var image:=preview.compose_ground(p,bridge_built)
			images.append(image)
			expect(image.get_size()==Vector2i(32,32),"Home %s edge cell %s composes a full tile"%[edge,p])
			# The legacy feather painted whole cells in one flat color; real art must never be that.
			expect(legacy_pixels(image)<512,"Home %s edge cell %s is not legacy-flat"%[edge,p])
		expect(distinct_colors(images)>8,"Home %s edge is illustrated, not flat (distinct colors across samples)"%edge)
		var again:=preview.compose_ground(edges[edge][0],bridge_built)
		expect(again.get_data()==images[0].get_data(),"Home %s edge terrain is deterministic"%edge)

func check_old_seams(preview:Preview,bridge_built:bool) -> void:
	# Cell pairs straddling the four old rectangle edges (25,19,36,44). The old bottom edge (y=62)
	# lies outside the 60-row home, so the equivalent home bottom seam (y=58|59) is used.
	var pairs:Array=[]
	for y in range(21,58,8):
		pairs.append([Vector2i(24,y),Vector2i(25,y)])
		pairs.append([Vector2i(60,y),Vector2i(61,y)])
	for x in range(27,60,8):
		pairs.append([Vector2i(x,18),Vector2i(x,19)])
		pairs.append([Vector2i(x,58),Vector2i(x,59)])
	for pair in pairs:
		for p in pair:
			var image:=preview.compose_ground(p,bridge_built)
			expect(legacy_pixels(image)<64,"No legacy feather/flat fill at old seam cell %s"%p)
			expect(distinct_colors([image])>2,"Old seam cell %s has terrain texture"%p)
		# Cells straddling the old edge of the same wetness are produced by the same rules: no hard flat band.
		if Preview.wet_at(pair[0],bridge_built)==Preview.wet_at(pair[1],bridge_built):
			var a:=preview.compose_ground(pair[0],bridge_built)
			var b:=preview.compose_ground(pair[1],bridge_built)
			expect(legacy_pixels(a,0)<32 and legacy_pixels(b,0)<32 and legacy_pixels(a,31)<32 and legacy_pixels(b,31)<32,"Old seam %s|%s has no flat legacy column"%[pair[0],pair[1]])

func check_shore_foam(preview:Preview) -> void:
	# Find water cells with exactly one dry orthogonal neighbor; there the shallow/foam band
	# (tile 9) must hug that side and deep water (tile 8) must remain on the opposite side.
	var dirs:Array=[[Vector2i.LEFT,Vector2i(0,16),Vector2i(31,16)],[Vector2i.RIGHT,Vector2i(31,16),Vector2i(0,16)],[Vector2i.UP,Vector2i(16,0),Vector2i(16,31)],[Vector2i.DOWN,Vector2i(16,31),Vector2i(16,0)]]
	var found:=0
	var per_dir:Dictionary={}
	for y in range(HOME.position.y+1,HOME.end.y-1):
		for x in range(HOME.position.x+1,HOME.end.x-1):
			var p:=Vector2i(x,y)
			if not Preview.wet_at(p,false):continue
			var dry:Array=[]
			for entry in dirs:
				if not Preview.wet_at(p+entry[0],false):dry.append(entry)
			if dry.size()!=1:continue
			var d:Array=dry[0]
			if per_dir.get(d[0],0)>=2:continue
			per_dir[d[0]]=per_dir.get(d[0],0)+1
			found+=1
			var image:=preview.compose_ground(p,false)
			var near:Vector2i=d[1]
			var far:Vector2i=d[2]
			expect(image.get_pixel(near.x,near.y).is_equal_approx(preview.tiles[9].get_pixel(near.x,near.y)),"Shore foam band at %s hugs the dry side"%p)
			expect(image.get_pixel(far.x,far.y).is_equal_approx(preview.tiles[8].get_pixel(far.x,far.y)),"Open water at %s stays deep on the far side"%p)
			expect(image.get_data()==preview.compose_ground(p,false).get_data(),"Shore cell %s is deterministic"%p)
	expect(found>0,"Home map has at least one single-sided shore cell to verify foam")
