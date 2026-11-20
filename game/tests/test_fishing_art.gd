extends SceneTree

const Art=preload("res://scripts/fishing_art.gd")
const Fish=preload("res://scripts/collections.gd")

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

func splash_coverage(image:Image,sheet:Image,cell:Vector2i,origin:Vector2i)->float:
	# Share of a splash cell's opaque pixels shown unchanged (line, float, or fish may cover a few).
	var opaque:=0
	var shown:=0
	for y in 32:
		for x in 32:
			var color:=sheet.get_pixel(cell.x*32+x,cell.y*32+y)
			if color.a<1.0:continue
			opaque+=1
			if image.get_pixel(origin.x+x,origin.y+y).is_equal_approx(color):shown+=1
	return float(shown)/maxf(1.0,float(opaque))

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
	var swim_left:=await frame("wait",0.0,2.4)
	var swim_right:=await frame("wait",0.0,0.8)
	var still_water:=await frame("wait",0.0,0.8,true)
	var shadow_area:=Rect2i(173,116,29,8)
	expect(swim_left.get_region(shadow_area).get_used_rect().has_area() and swim_right.get_region(shadow_area).get_used_rect().has_area(),
		"Waiting shows a fish under the bobber")
	expect(swim_left.get_region(shadow_area).get_data()!=swim_right.get_region(shadow_area).get_data(),
		"Underwater shadow swims past distinct positions while waiting")
	expect(not still_water.get_region(shadow_area).get_used_rect().has_area(),
		"Reduced motion omits the decorative underwater shadow")
	var splash:=await frame("ready",0.17,4.55)
	var calm:=await frame("ready",0.55,4.55)
	var quiet:=await frame("ready",0.17,4.55,true)
	expect(splash.get_pixel(179,98).a>0.0 and calm.get_pixel(179,98).a==0.0 and quiet.get_pixel(179,98).a==0.0,
		"Bite droplets rise, fade, and stay hidden with reduced motion")
	expect(Art.bite_pull(0.17)>Art.bite_pull(1.07) and Art.bite_pull(0.55)==0.0,
		"The first bite is stronger than following tugs and releases between pulls")
	var bobber_area:=Rect2i(184,101,6,11)
	expect(splash.get_region(bobber_area).get_data()!=calm.get_region(bobber_area).get_data(),
		"The tug pulls the bobber below its waiting height")
	var fish:=await frame("catch",0.15,0.0,false,"carp")
	var generic:=await frame("catch",0.15,0.0,true)
	var reel_start:=await frame("catch",0.0,0.0,false,"carp")
	var surface_pull:=await frame("catch",0.12,0.0,false,"carp")
	var mid_lift:=await frame("catch",0.31,0.0,false,"carp")
	var reel_end:=await frame("catch",0.56,0.0,false,"carp")
	expect(reel_start.get_region(Rect2i(165,95,45,28)).get_data()!=surface_pull.get_region(Rect2i(165,95,45,28)).get_data()
		and surface_pull.get_region(Rect2i(155,50,32,33)).get_data()!=mid_lift.get_region(Rect2i(155,50,32,33)).get_data(),
		"The surface pull and airborne lift render distinct stages")
	expect(Art.angler_lean({"phase":"catch","age":0.27},0.0,false)<-6.0,
		"The angler braces against the direction of the pull")
	expect(reel_start.get_pixel(187,108).a>0.0 and reel_end.get_pixel(187,108).a==0.0 and reel_end.get_pixel(145,60).a>0.0,
		"Fish starts at the float and finishes by the player")
	expect(reel_start.get_pixel(166,85).is_equal_approx(Art.LINE_COLOR) and reel_end.get_pixel(166,85).a==0.0,
		"The line pulls taut during the reel and disappears after it")
	var cancel_start:=await frame("cancel",0.0,0.0)
	var cancel_pull:=await frame("cancel",0.22,0.0)
	var cancel_reduced:=await frame("cancel",0.22,0.0,true)
	expect(cancel_start.get_pixel(166,85).is_equal_approx(Art.LINE_COLOR) and cancel_pull.get_pixel(166,85).a==0.0,
		"Cancellation retracts an empty line from the former target")
	expect(cancel_pull.get_used_rect().has_area() and not cancel_reduced.get_used_rect().has_area(),
		"Reduced motion skips the cancellation effect")
	# Splash sheet: top row plays on landing, bottom row on the hook-up; cell (16,28) sits on the water point.
	var sheet:Image=Art.SPLASH_ATLAS.get_image()
	expect(sheet.get_size()==Vector2i(96,64),"Splash sheet holds six 32px frames")
	var splash_area:=Rect2i(171,80,32,32)
	var no_landing:=await frame("wait",0.0,0.8)
	var landings:Array[Image]=[]
	for step in 3:
		sample.state={"phase":"wait","age":0.0,"fish":"","landing_age":Art.Feedback.LANDING_DURATION*(0.1+step/3.0)}
		sample.elapsed=0.8
		sample.reduced=false
		sample.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		landings.append(viewport.get_texture().get_image())
	expect(splash_coverage(landings[0],sheet,Vector2i(0,0),splash_area.position)>=0.5
		and splash_coverage(landings[1],sheet,Vector2i(1,0),splash_area.position)>=0.5
		and splash_coverage(landings[1],sheet,Vector2i(0,0),splash_area.position)<0.2
		and splash_coverage(no_landing,sheet,Vector2i(0,0),splash_area.position)<0.2,
		"Bobber landing plays the top row of the splash sheet")
	expect(landings[0].get_region(splash_area).get_data()!=landings[1].get_region(splash_area).get_data()
		and landings[1].get_region(splash_area).get_data()!=landings[2].get_region(splash_area).get_data()
		and landings[2].get_region(splash_area).get_data()!=no_landing.get_region(splash_area).get_data(),
		"Landing splash advances through three distinct frames")
	expect(splash_coverage(reel_start,sheet,Vector2i(0,1),splash_area.position)>=0.5
		and splash_coverage(reel_start,sheet,Vector2i(0,0),splash_area.position)<0.2,
		"Hook-up plays the bottom row of the splash sheet")
	sample.state={"phase":"wait","age":0.0,"fish":"","landing_age":0.02}
	sample.reduced=true
	sample.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var landing_reduced:=viewport.get_texture().get_image()
	expect(landing_reduced.get_data()==still_water.get_data() and generic.get_region(Rect2i(171,80,32,18)).get_used_rect().size==Vector2i.ZERO,
		"Reduced motion omits the landing and hook-up splash frames")
	var cast_back:=await frame("cast",0.10,0.10)
	var cast_forward:=await frame("cast",0.31,0.31)
	var rod_area:=Rect2i(110,43,48,45)
	expect(cast_back.get_region(rod_area).get_data()!=cast_forward.get_region(rod_area).get_data(),
		"Rod swings through distinct cast poses")
	var breathe_in:=await frame("wait",0.0,0.87)
	var breathe_out:=await frame("wait",0.0,2.62)
	expect(breathe_in.get_region(rod_area).get_data()!=breathe_out.get_region(rod_area).get_data(),
		"Waiting moves the held rod, not only the water")
	expect(Art.angler_lean({"phase":"wait"},0.87,false)>0.0 and Art.angler_lean({"phase":"wait"},2.62,false)<0.0,
		"Waiting breathes gently in both directions")
	expect(Art.angler_lean({"phase":"wait"},0.87,true)==0.0,
		"Reduced motion keeps the waiting character still")
	var flutter_a:=await frame("catch",0.60,0.0,false,"carp")
	var flutter_b:=await frame("catch",0.74,0.0,false,"carp")
	expect(flutter_a.get_region(Rect2i(125,30,45,55)).get_data()!=flutter_b.get_region(Rect2i(125,30,45,55)).get_data(),
		"Landed catch settles through distinct frames")
	var trophy:Image=Art.ICONS.get_image().get_region(Rect2i(Art.TROPHY))
	expect(fish.get_data()!=generic.get_data(),"Unknown catch differs from actual carp")
	for species in ["sardine","flounder","moon_squid","gold_shrimp"]:
		var coastal:=await frame("catch",0.15,0.0,false,species)
		expect(coastal.get_data()!=generic.get_data(),"Catch uses the coastal item icon: "+species)
	var individual:Dictionary={}
	for species:String in Fish.FISH:
		var texture:=Art.Items.icon(species)
		expect(texture!=null and texture.get_size()==Vector2(32,32),"Fish has a 32px item icon: "+species)
		var caught:=await frame("catch",0.4,0.0,true,species)
		var rendered:=caught.get_region(Rect2i(129,50,32,32)).get_data().hex_encode().sha256_text()
		expect(not individual.has(rendered),"Catch badge is unique: "+species)
		individual[rendered]=true
	var opaque:=0
	var matches:=0
	for y in range(32):
		for x in range(32):
			var color:=trophy.get_pixel(x,y)
			if color.a<1.0:continue
			opaque+=1
			if generic.get_pixel(129+x,50+y).is_equal_approx(color):matches+=1
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
