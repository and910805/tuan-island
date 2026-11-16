extends SceneTree

const Art=preload("res://scripts/fishing_art.gd")

class Sample extends Node2D:
	var foot:=Vector2(120,102)
	var target:=Vector2(187,108)
	var state:Dictionary={}
	var reduced:=false
	var elapsed:=0.0

	func _draw()->void:
		Art.draw(self,foot,target,state,reduced,elapsed)

var viewport:SubViewport
var sample:=Sample.new()
var checks:=0
var failures:=0

func _initialize()->void:
	run.call_deferred()

func expect(ok:bool,message:String)->void:
	checks+=1
	if not ok:
		failures+=1
		push_error(message)

func frame(phase:String,age:float,clock:float,reduced:bool=false,fish:String="")->Image:
	sample.state={"phase":phase,"age":age,"fish":fish}
	sample.elapsed=clock
	sample.reduced=reduced
	sample.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()

func run()->void:
	if DisplayServer.get_name()=="headless":
		print("FISHING_ART_TESTS requires native rendering")
		quit(1)
		return
	viewport=SubViewport.new()
	viewport.size=Vector2i(240,150)
	viewport.transparent_bg=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	sample.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	viewport.add_child(sample)
	var distinct:Dictionary={}
	for phase in ["cast","wait","ready","catch"]:
		var regular:=await frame(phase,0.16,0.16,false,"carp")
		distinct[regular.get_data().hex_encode().sha256_text()]=true
		var first:=await frame(phase,0.1,0.1,true,"carp")
		var later:=await frame(phase,0.28,0.83,true,"carp")
		expect(first.get_data()==later.get_data(),"Reduced motion freezes "+phase)
	expect(distinct.size()==4,"Cast, wait, ready, and catch draw distinguishable frames")
	var fish:=await frame("catch",0.15,0.0,false,"carp")
	var generic:=await frame("catch",0.15,0.0)
	var trophy:Image=Art.ICONS.get_image().get_region(Rect2i(Art.TROPHY))
	expect(fish.get_data()!=generic.get_data(),"Unknown catch differs from actual carp")
	for species in ["sardine","flounder","moon_squid","gold_shrimp"]:
		var coastal:=await frame("catch",0.15,0.0,false,species)
		expect(coastal.get_data()!=generic.get_data(),"Catch uses the coastal item icon: "+species)
	var opaque:=0
	var matches:=0
	for y in range(32):
		for x in range(32):
			var color:=trophy.get_pixel(x,y)
			if color.a<1.0:continue
			opaque+=1
			if generic.get_pixel(129+x,46+y).is_equal_approx(color):matches+=1
	expect(opaque>0 and matches==opaque,"Unknown catch shows the official trophy")
	var right:=await frame("wait",0.0,0.0,true)
	sample.target=Vector2(53,108)
	var left:=await frame("wait",0.0,0.0,true)
	var right_rod:=right.get_region(Rect2i(122,60,25,32))
	var left_rod:=left.get_region(Rect2i(93,60,25,32))
	left_rod.flip_x()
	expect(right_rod.get_data()==left_rod.get_data(),"Left and right retain mirrored rod artwork")
	viewport.queue_free()
	print("FISHING_ART_TESTS checks=%d failures=%d"%[checks,failures])
	quit(int(failures>0))
