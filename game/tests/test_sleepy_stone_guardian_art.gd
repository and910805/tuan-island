extends SceneTree
## Standalone test for the guardian drawing helpers. Preloads only the pure Guardian module
## and the art script (no World/Session). Draw calls run inside a real CanvasItem draw pass.
## Headless has no pixels to read back, so pixel assertions run only with a real renderer
## (drop --headless); headless still proves every draw path executes to completion.

const Guardian=preload("res://scripts/sleepy_stone_guardian.gd")
const GuardianArt=preload("res://scripts/sleepy_stone_guardian_art.gd")
const FOOT:=Vector2(32,70)
const VIEW:=Vector2i(64,80)
var checks:=0
var failures:=0
var job:=Callable()
var completed:=0
var viewport:SubViewport
var canvas:Node2D

func expect(ok:bool,message:String) -> void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)

func _initialize() -> void:
	check_rects()
	check_textures()
	viewport=SubViewport.new()
	viewport.size=VIEW
	viewport.transparent_bg=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	canvas=Node2D.new()
	canvas.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	viewport.add_child(canvas)
	canvas.draw.connect(_on_draw)
	await check_draw_matrix()
	await check_pixels()
	GuardianArt.force_fallback=false
	GuardianArt.reset_cache()
	print("SLEEPY_STONE_GUARDIAN_ART_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))

func _on_draw() -> void:
	if job.is_valid():
		job.call()
		completed+=1

## Runs `work` inside the canvas draw pass; returns the rendered image (null when headless).
func render(work:Callable) -> Image:
	var before:=completed
	job=work
	canvas.queue_redraw()
	await process_frame
	await process_frame
	expect(completed>before,"The draw pass ran the job to completion")
	var image:Image=null
	if pixels_available():
		await RenderingServer.frame_post_draw
		image=viewport.get_texture().get_image()
	job=Callable()
	return image

func pixels_available() -> bool:
	return DisplayServer.get_name()!="headless"

func check_rects() -> void:
	expect(GuardianArt.BELL_ATLAS_PATH=="res://assets/mine/sleepy-stone-bells.png","Bell atlas path")
	for index in 3:
		expect(GuardianArt.bell_rect(index)==Rect2i(index*32,0,32,40),"Bell rect %d"%index)
		expect(Rect2i(Vector2i.ZERO,GuardianArt.BELL_ATLAS_SIZE).encloses(GuardianArt.bell_rect(index)),"Bell rect %d stays inside the atlas"%index)
	expect(GuardianArt.BELL_ATLAS_SIZE==Vector2i(Guardian.BELLS.size(),1)*Guardian.FRAME_SIZE,"One cell per bell")
	expect(GuardianArt.GUARDIAN_ATLAS_SIZE==Guardian.FRAME_SIZE*2,"Statue atlas is 2x2 frames")
	expect(GuardianArt.sprite_rect(Vector2(116,230))==Rect2(100,192,32,40),"Sprite rect puts the foot point on the given pixel")
	var plain:=GuardianArt.bell_bounds(FOOT)
	var lit:=GuardianArt.bell_bounds(FOOT,true)
	expect(plain==GuardianArt.sprite_rect(FOOT),"Unlit bell stays inside its sprite cell")
	expect(lit.encloses(plain),"Lit bounds cover the sprite")
	var marker:=FOOT+GuardianArt.MARKER_OFFSET
	var reach:=GuardianArt.MARKER_RADIUS+3.5
	expect(lit.encloses(Rect2(marker-Vector2(reach,reach+2.0),Vector2(reach*2.0,reach*2.0+2.0))),"Lit bounds cover the bobbing marker")
	var ring:=GuardianArt.RING_RADIUS+3.0
	expect(lit.encloses(Rect2(FOOT+GuardianArt.RING_OFFSET-Vector2(ring,ring),Vector2(ring,ring)*2.0)),"Lit bounds cover the pulsing ring")
	expect(marker.y+reach<=plain.position.y+1.0,"Lit marker sits above the sprite instead of covering it")

func check_textures() -> void:
	GuardianArt.force_fallback=false
	GuardianArt.reset_cache()
	var statue:=GuardianArt.guardian_texture()
	expect(statue==null or Vector2i(statue.get_width(),statue.get_height())==Vector2i(64,80),"Statue texture is null or 64x80")
	expect(statue!=null,"Statue atlas ships with the project and loads")
	expect(GuardianArt.guardian_texture()==statue,"Statue texture is cached")
	var bells:=GuardianArt.bell_texture()
	expect(bells==null or Vector2i(bells.get_width(),bells.get_height())==Vector2i(96,40),"Bell texture is null or 96x40")
	expect(GuardianArt.bell_texture()==bells,"Bell texture (or its absence) is cached")
	expect(GuardianArt._cache.has(GuardianArt.BELL_ATLAS_PATH) and GuardianArt._cache.has(Guardian.ATLAS_PATH),"Both lookups are remembered, hit or miss")
	print("SLEEPY_STONE_GUARDIAN_ART bell atlas: %s"%("loaded" if bells!=null else "absent, code-drawn bells in use"))
	# Missing file and wrong size are quiet nulls, never errors.
	expect(GuardianArt.load_sized("res://assets/mine/sleepy-stone-none.png",Vector2i(96,40))==null,"Missing atlas gives null")
	expect(GuardianArt.load_sized(Guardian.ATLAS_PATH,Vector2i(96,40))==null,"Wrong-sized atlas gives null")
	expect(GuardianArt._texture("res://assets/mine/sleepy-stone-none.png",Vector2i(96,40))==null and GuardianArt._cache.has("res://assets/mine/sleepy-stone-none.png"),"A miss is cached")
	# Raw PNG with no .import beside it (atlas dropped in but not imported yet).
	var raw:="user://sleepy-stone-art-test.png"
	if Image.create_empty(96,40,false,Image.FORMAT_RGBA8).save_png(raw)==OK:
		var loose:=GuardianArt.load_sized(raw,Vector2i(96,40))
		expect(loose is ImageTexture and loose.get_width()==96 and loose.get_height()==40,"Un-imported PNG loads from disk")
		expect(GuardianArt.load_sized(raw,Vector2i(64,80))==null,"Un-imported PNG of the wrong size gives null")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(raw))
	else:
		expect(false,"Could not write the temporary PNG")
	GuardianArt.force_fallback=true
	expect(GuardianArt.guardian_texture()==null and GuardianArt.bell_texture()==null,"force_fallback hides both atlases")
	GuardianArt.force_fallback=false
	expect(GuardianArt.guardian_texture()==statue,"Leaving force_fallback restores the cached atlas")
	GuardianArt.reset_cache()
	expect(GuardianArt._cache.is_empty(),"reset_cache forgets everything")

func draw_everything() -> void:
	for motion:bool in [false,true]:
		for frame in range(-1,6):
			GuardianArt.draw_guardian(canvas,FOOT,frame,1.37,motion)
		for bell in range(-1,5):
			for lit:bool in [false,true]:
				GuardianArt.draw_bell(canvas,FOOT+Vector2(0.4,0.6),bell,lit,2.11,motion)
				GuardianArt.draw_shape(canvas,Vector2(20,20),bell,5.0,lit)
	GuardianArt.draw_guardian(canvas,FOOT,0)
	GuardianArt.draw_bell(canvas,FOOT,0)
	GuardianArt.draw_shape(canvas,FOOT,0,4.0)

func check_draw_matrix() -> void:
	for fallback:bool in [false,true]:
		GuardianArt.force_fallback=fallback
		GuardianArt.reset_cache()
		var before:=completed
		await render(draw_everything)
		expect(completed==before+1,"Every draw call returns (%s path)"%("fallback" if fallback else "atlas"))

func ink(image:Image) -> int:
	var count:=0
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x,y).a>0.5:count+=1
	return count

func same(a:Image,b:Image) -> bool:
	return a.get_data()==b.get_data()

func check_pixels() -> void:
	if not pixels_available():
		print("SLEEPY_STONE_GUARDIAN_ART pixel checks skipped (headless renderer)")
		return
	for fallback:bool in [false,true]:
		GuardianArt.force_fallback=fallback
		GuardianArt.reset_cache()
		var path:="fallback" if fallback else "atlas"
		var frames:Array[Image]=[]
		for frame in 4:
			var shot:Image=await render(func():GuardianArt.draw_guardian(canvas,FOOT,frame,0.0,true))
			expect(ink(shot)>150,"Statue frame %d is visible (%s)"%[frame,path])
			frames.append(shot)
		expect(not same(frames[0],frames[3]) and not same(frames[1],frames[2]),"Asleep and awake statue frames differ (%s)"%path)
		var plain:Array[Image]=[]
		for bell in 3:
			var off:Image=await render(func():GuardianArt.draw_bell(canvas,FOOT,bell,false,0.0,true))
			var on:Image=await render(func():GuardianArt.draw_bell(canvas,FOOT,bell,true,0.0,true))
			var later:Image=await render(func():GuardianArt.draw_bell(canvas,FOOT,bell,true,0.31,true))
			var moving:Image=await render(func():GuardianArt.draw_bell(canvas,FOOT,bell,true,0.31,false))
			expect(ink(off)>60,"Bell %d is visible (%s)"%[bell,path])
			expect(ink(on)>ink(off)+150,"Lit bell %d adds a clear highlight (%s)"%[bell,path])
			expect(same(on,later),"Reduced motion keeps the lit bell %d still (%s)"%[bell,path])
			expect(not same(on,moving),"Lit bell %d animates when motion is allowed (%s)"%[bell,path])
			# Greyscale legibility: the lit marker has a pale rim and dark outline, not just hue.
			var centre:=Vector2i(FOOT+GuardianArt.MARKER_OFFSET)
			var rim:=on.get_pixel(centre.x,centre.y-int(GuardianArt.MARKER_RADIUS)-3)
			expect(rim.a>0.5 and rim.get_luminance()>0.8,"Lit bell %d marker has a pale rim (%s)"%[bell,path])
			expect(off.get_pixel(centre.x,centre.y).a<0.5,"Unlit bell %d has no marker (%s)"%[bell,path])
			plain.append(off)
		expect(not same(plain[0],plain[1]) and not same(plain[1],plain[2]) and not same(plain[0],plain[2]),"The three bells look different (%s)"%path)
	# Shape silhouettes differ by geometry alone: compare coverage with colour ignored.
	var masks:Array[int]=[]
	for bell in 3:
		var chip:Image=await render(func():GuardianArt.draw_shape(canvas,Vector2(32,40),bell,10.0))
		masks.append(ink(chip))
		expect(chip.get_pixel(32,40).a>0.5,"Shape %d is filled at its centre"%bell)
	expect(masks[1]<masks[0] and masks[1]<masks[2],"Triangle covers the least area of the three chips")
	var corner:Image=await render(func():GuardianArt.draw_shape(canvas,Vector2(32,40),0,10.0))
	expect(corner.get_pixel(41,31).a<0.5,"Circle leaves its corners empty")
	corner=await render(func():GuardianArt.draw_shape(canvas,Vector2(32,40),2,10.0))
	expect(corner.get_pixel(40,32).a>0.5,"Square fills its corners")
	corner=await render(func():GuardianArt.draw_shape(canvas,Vector2(32,40),1,10.0))
	expect(corner.get_pixel(40,32).a<0.5 and corner.get_pixel(40,47).a>0.5,"Triangle is narrow on top and wide at the base")
