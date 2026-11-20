extends SceneTree
## Standalone test for the shy mushroom drawing helpers. Preloads only the pure Shy module
## and the art script (no World/Session). Draw calls run inside a real CanvasItem draw pass.
## Headless has no pixels to read back, so pixel assertions run only with a real renderer
## (drop --headless); headless still proves every draw path executes to completion.

const Shy=preload("res://scripts/shy_mushroom.gd")
const ShyArt=preload("res://scripts/shy_mushroom_art.gd")
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
	check_pips()
	check_texture()
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
	ShyArt.force_fallback=false
	ShyArt.reset_cache()
	print("SHY_MUSHROOM_ART_TESTS checks=%d failures=%d"%[checks,failures])
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
	expect(ShyArt.sprite_rect(Vector2(116,230))==Rect2(100,192,32,40),"Sprite rect puts the foot point on the given pixel")
	expect(ShyArt.sprite_rect(Vector2(116.4,229.6))==Rect2(100,192,32,40),"Sprite rect snaps to whole pixels")
	# world_view convention: tile top-left `at`, foot at at+(16,30) -> 8px above the tile, bottom flush.
	var at:=Vector2(320,160)
	expect(ShyArt.sprite_rect(at+Vector2(16,30))==Rect2(at+Vector2(0,-8),Vector2(32,40)),"Foot convention matches the 32px tile")
	var sprite:=ShyArt.sprite_rect(FOOT)
	var ring:=ShyArt.ring_rect(FOOT)
	var reach:=ShyArt.RING_RADIUS+4.0
	expect(ring.encloses(Rect2(FOOT+ShyArt.RING_OFFSET-Vector2(reach,reach),Vector2(reach,reach)*2.0)),"Ring rect covers the ring and its pips")
	var spark:=ShyArt.MARKER_RADIUS+2.0
	expect(ring.encloses(Rect2(FOOT+ShyArt.MARKER_OFFSET-Vector2(spark,spark+1.0),Vector2(spark*2.0,spark*2.0+1.0))),"Ring rect covers the bobbing ready marker")
	expect(ring.encloses(sprite),"Ring rect covers the sprite")
	expect(FOOT.y+ShyArt.MARKER_OFFSET.y+spark<=sprite.position.y+1.0,"Ready marker sits above the sprite instead of covering it")
	expect(ShyArt.RING_RADIUS>=15.0 and ShyArt.RING_RADIUS<=17.0,"Ring stays compact")
	expect(FOOT+ShyArt.RING_OFFSET==sprite.get_center(),"Ring is centred on the sprite")
	for index in 4:
		expect(Rect2i(Vector2i.ZERO,Shy.ATLAS_SIZE).encloses(Shy.frame_rect(index)),"Frame %d stays inside the atlas"%index)

func check_pips() -> void:
	expect(ShyArt.PIPS==int(Shy.WAIT_SECONDS),"One pip per world-second of the wait")
	var cases:=[[-1.0,0],[0.0,0],[0.1,0],[0.249,0],[0.25,1],[0.3,1],[0.499,1],[0.5,2],[0.6,2],[0.749,2],[0.75,3],[0.99,3],[1.0,4],[7.0,4],[NAN,0],[INF,0]]
	for case in cases:
		expect(ShyArt.pip_count(case[0])==case[1],"pip_count(%s) is %d"%[case[0],case[1]])
	# Driven the way the host will: Shy.progress over the real wait.
	var watch:={"x":0.0,"y":0.0,"since":10.0}
	for second in 5:
		expect(ShyArt.pip_count(Shy.progress(watch,10.0+second))==second,"%d pips after %d quiet seconds"%[second,second])

func check_texture() -> void:
	ShyArt.force_fallback=false
	ShyArt.reset_cache()
	var atlas:=ShyArt.texture()
	expect(atlas!=null,"Mushroom atlas ships with the project and loads")
	expect(atlas!=null and Vector2i(atlas.get_width(),atlas.get_height())==Vector2i(64,80),"Mushroom atlas is 64x80")
	expect(ShyArt.texture()==atlas,"Texture is cached")
	expect(ShyArt._cache.has(Shy.ATLAS_PATH),"The lookup is remembered, hit or miss")
	ShyArt.force_fallback=true
	expect(ShyArt.texture()==null,"force_fallback hides the atlas")
	ShyArt.force_fallback=false
	expect(ShyArt.texture()==atlas,"Leaving force_fallback restores the cached atlas")
	ShyArt.reset_cache()
	expect(ShyArt._cache.is_empty(),"reset_cache forgets everything")

func draw_everything() -> void:
	for reduced:bool in [false,true]:
		for frame in range(-1,6):
			ShyArt.draw(canvas,FOOT+Vector2(0.4,0.6),frame,1.37,reduced)
		for progress:float in [-1.0,0.0,0.01,0.3,0.6,0.99,1.0,3.0,NAN]:
			for ready:bool in [false,true]:
				ShyArt.draw_ring(canvas,FOOT,progress,ready,reduced)
				ShyArt.draw_ring(canvas,FOOT,progress,ready,reduced,2.11)
	ShyArt.draw(canvas,FOOT,0)

func check_draw_matrix() -> void:
	for fallback:bool in [false,true]:
		ShyArt.force_fallback=fallback
		ShyArt.reset_cache()
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

func ring_shot(progress:float,ready:bool,reduced:bool,elapsed:float=0.0) -> Image:
	return await render(func():ShyArt.draw_ring(canvas,FOOT,progress,ready,reduced,elapsed))

func check_pixels() -> void:
	if not pixels_available():
		print("SHY_MUSHROOM_ART pixel checks skipped (headless renderer)")
		return
	for fallback:bool in [false,true]:
		ShyArt.force_fallback=fallback
		ShyArt.reset_cache()
		var path:="fallback" if fallback else "atlas"
		var frames:Array[Image]=[]
		for frame in 4:
			var shot:Image=await render(func():ShyArt.draw(canvas,FOOT,frame,0.0,true))
			var later:Image=await render(func():ShyArt.draw(canvas,FOOT,frame,0.5,true))
			var moving:Image=await render(func():ShyArt.draw(canvas,FOOT,frame,0.5,false))
			var resting:Image=await render(func():ShyArt.draw(canvas,FOOT,frame,0.0,false))
			expect(ink(shot)>120,"Mushroom frame %d is visible (%s)"%[frame,path])
			expect(shot.get_used_rect().size.x>0 and Rect2i(ShyArt.sprite_rect(FOOT)).encloses(shot.get_used_rect()),"Mushroom frame %d stays inside its sprite rect (%s)"%[frame,path])
			expect(same(shot,later),"Reduced motion keeps frame %d still (%s)"%[frame,path])
			expect(not same(shot,moving),"Frame %d breathes when motion is allowed (%s)"%[frame,path])
			expect(same(shot,resting),"Frame %d rests on the foot point between breaths (%s)"%[frame,path])
			expect(absi(moving.get_used_rect().position.y-shot.get_used_rect().position.y)<=1 and moving.get_used_rect().position.x==shot.get_used_rect().position.x,"Frame %d breath is at most 1px (%s)"%[frame,path])
			frames.append(shot)
		for a in 4:
			for b in range(a+1,4):
				expect(not same(frames[a],frames[b]),"Frames %d and %d look different (%s)"%[a,b,path])
	ShyArt.force_fallback=false
	ShyArt.reset_cache()
	# Wait ring.
	for reduced:bool in [false,true]:
		var mode:="reduced" if reduced else "motion"
		var none:Image=await ring_shot(0.0,false,reduced)
		expect(ink(none)==0,"No ring before the wait starts (%s)"%mode)
		var some:Image=await ring_shot(0.3,false,reduced)
		var more:Image=await ring_shot(0.6,false,reduced)
		var nearly:Image=await ring_shot(0.99,false,reduced)
		var full:Image=await ring_shot(1.0,false,reduced)
		var ready:Image=await ring_shot(1.0,true,reduced)
		expect(ink(some)>80,"Ring at 0.3 is visible (%s)"%mode)
		expect(Rect2i(ShyArt.ring_rect(FOOT)).encloses(ready.get_used_rect()),"Ready ring stays inside ring_rect (%s)"%mode)
		var shots:Array[Image]=[some,more,nearly,full,ready]
		for a in shots.size():
			for b in range(a+1,shots.size()):
				expect(not same(shots[a],shots[b]),"Ring states %d and %d look different (%s)"%[a,b,mode])
		expect(not same(ready,nearly),"Ready differs from 0.99 not ready (%s)"%mode)
		expect(ink(ready)>ink(nearly)+60,"Ready adds a clearly larger shape, not just a tint (%s)"%mode)
		# Not colour-only: the lit arc is bright where reached and absent/dim where not.
		var centre:=Vector2i(FOOT+ShyArt.RING_OFFSET)
		var radius:=int(ShyArt.RING_RADIUS)
		var reached:=some.get_pixel(centre.x+11,centre.y-11)
		var ahead:=some.get_pixel(centre.x-11,centre.y-11)
		expect(reached.a>0.5 and reached.get_luminance()>0.8,"Arc is pale where the wait has reached (%s)"%mode)
		expect(ahead.get_luminance()*ahead.a<0.3,"Arc is dark where the wait has not reached (%s)"%mode)
		# Pips: filled is pale and larger, empty is dark. Right pip = first second.
		expect(some.get_pixel(centre.x+radius,centre.y).get_luminance()>0.8,"First pip is filled at 0.3 (%s)"%mode)
		expect(some.get_pixel(centre.x,centre.y+radius).get_luminance()<0.5,"Second pip is empty at 0.3 (%s)"%mode)
		expect(more.get_pixel(centre.x,centre.y+radius).get_luminance()>0.8,"Second pip is filled at 0.6 (%s)"%mode)
		expect(some.get_pixel(centre.x+radius+3,centre.y+3).a>0.5 and more.get_pixel(centre.x-radius-4,centre.y+3).a<0.5,"Filled pips are larger than empty ones (%s)"%mode)
		var marker:=Vector2i(FOOT+ShyArt.MARKER_OFFSET)
		expect(ready.get_pixel(marker.x,marker.y).a>0.5 and ready.get_pixel(marker.x,marker.y).get_luminance()>0.8,"Ready marker is drawn (%s)"%mode)
		expect(full.get_pixel(marker.x,marker.y).a<0.5,"No marker until ready (%s)"%mode)
	var still_a:Image=await ring_shot(1.0,true,true,0.0)
	var still_b:Image=await ring_shot(1.0,true,true,0.26)
	var pulse:Image=await ring_shot(1.0,true,false,0.26)
	expect(same(still_a,still_b),"Reduced motion keeps the ready ring still")
	expect(not same(still_a,pulse),"Ready marker pulses when motion is allowed")
	var part_a:Image=await ring_shot(0.6,false,false,0.0)
	var part_b:Image=await ring_shot(0.6,false,false,0.26)
	expect(same(part_a,part_b),"The filling ring itself never pulses")
