extends SceneTree
## Native rendering fixture; tests real sprites and camera alignment, not gameplay.
const Thumbnail = preload("res://scripts/blueprint_thumbnail.gd")
const Preview = preload("res://scripts/blueprint_preview.gd")
const View = preload("res://scripts/world_view.gd")
const BuildThumbnail = preload("res://scripts/pixel_build_thumbnail.gd")

class Intent extends Node:
	var mode := "placing"
	var draft := {"version":1,"name":"林務角落","width":3,"height":2,"pieces":[
		{"x":0,"y":0,"kind":"floor"},{"x":0,"y":0,"kind":"waterworks"},
		{"x":2,"y":1,"kind":"bed"}]}
	var origin := Vector2i(40,30)
	var turns := 0
	var locked := false
	var quote_waiting := false
	var quote: Dictionary = {}

var checks := 0
var failures := 0
var viewport: SubViewport
var output := ""

func _initialize() -> void:
	run.call_deferred()

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func frame() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()

func run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("Blueprint sprite verification requires native rendering")
		quit(1)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--qa-output="): output = arg.trim_prefix("--qa-output=")
	viewport = SubViewport.new()
	viewport.size = Vector2i(320,240)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var intent := Intent.new()
	root.add_child(intent)
	var thumbnail := Thumbnail.new()
	for badge in [Vector2(128,80),Vector2(56,44),Vector2(304,150)]:
		thumbnail.box_size = badge
		var largest := Vector2(16*32+16,16*32+24)
		var factor := thumbnail.fit_scale(largest)
		expect(factor>0 and largest.x*factor<=badge.x and largest.y*factor<=badge.y, "Maximum blueprint fits badge %s" % badge)
	thumbnail.box_size = Vector2(320,240)
	thumbnail.design = intent.draft
	viewport.add_child(thumbnail)
	var picture := await frame()
	var styled: Dictionary = intent.draft.duplicate(true)
	styled.pieces[0].style="coast"
	thumbnail.design=styled
	var styled_picture := await frame()
	expect(styled_picture.get_data()!=picture.get_data(),"Catalog thumbnail shows saved construction style")
	expect(picture.get_used_rect().has_area(), "Actual multi-piece sprites draw")
	expect(Rect2i(2,2,316,236).encloses(picture.get_used_rect()), "48px equipment stays within thumbnail margins")
	var arch_design:={"version":1,"name":"藤蔓花門","width":3,"height":1,"pieces":[
		{"kind":"vine_garden_arch","x":0,"y":0,"settings":{"vine_color":"lavender"}}]}
	thumbnail.design=arch_design
	var arch_thumbnail:=await frame()
	expect(arch_thumbnail.get_used_rect().size.y>=66 and Rect2i(2,2,316,236).encloses(arch_thumbnail.get_used_rect()),"The complete tall arch and crown fit within the thumbnail")
	var art = thumbnail.village_art
	thumbnail.design = {}
	var blank := await frame()
	expect(not blank.get_used_rect().has_area(), "Cleared design removes old thumbnail")
	thumbnail.free()
	var source := View.new()
	source.camera = Vector2(40,30)*32-Vector2(36,40)
	source.zoom = 1.0
	source.village_art = art
	source.data = {"region_id":"home"}
	var preview := Preview.new()
	preview.source_view = source
	preview.controller = intent
	viewport.add_child(preview)
	preview.queue_redraw()
	var neutral := await frame()
	expect(neutral.get_used_rect().has_area(), "Placement ghost uses actual sprites")
	intent.draft=styled
	preview.queue_redraw()
	var styled_preview := await frame()
	expect(styled_preview.get_data()!=neutral.get_data(),"Placement ghost shows saved construction style")
	intent.draft.pieces[0].erase("style")
	intent.turns = 1
	preview.queue_redraw()
	var rotated := await frame()
	expect(rotated.get_data() != neutral.get_data(), "Rotation changes asymmetric placement")
	intent.turns = 0
	source.camera += Vector2(8,0)
	preview.queue_redraw()
	var shifted := await frame()
	expect(shifted.get_used_rect().position.x == neutral.get_used_rect().position.x-8, "Ghost follows camera exactly")
	source.camera -= Vector2(8,0)
	intent.locked = true
	intent.quote = {"ok":false,"problems":[{"x":40,"y":30,"reason":"fixture collision"}]}
	preview.queue_redraw()
	var blocked := await frame()
	expect(blocked.get_data() != neutral.get_data(), "Authority collision changes preview marks")
	intent.quote_waiting = true
	preview.queue_redraw()
	var waiting := await frame()
	expect(waiting.get_data() == neutral.get_data(), "Waiting quote never shows stale collision marks")
	intent.draft=arch_design
	intent.turns=1
	intent.locked=false
	intent.quote_waiting=false
	preview.queue_redraw()
	var purple_arch:=await frame()
	intent.draft.pieces[0].settings.vine_color="cream"
	preview.queue_redraw()
	var cream_arch:=await frame()
	expect(purple_arch.get_data()!=cream_arch.get_data(),"The real rotated placement ghost uses the saved blossom palette")
	if not output.is_empty():
		expect(DirAccess.make_dir_recursive_absolute(output) == OK, "Create isolated render output")
		expect(picture.save_png(output.path_join("thumbnail.png")) == OK, "Save sprite thumbnail evidence")
		expect(blocked.save_png(output.path_join("collision-preview.png")) == OK, "Save collision evidence")
		expect(styled_preview.save_png(output.path_join("styled-preview.png")) == OK, "Save styled placement evidence")
		expect(purple_arch.save_png(output.path_join("rotated-vine-arch-preview.png"))==OK,"Save the arch's rotated placement ghost")
	preview.free()
	source.free()
	intent.free()
	art = null
	viewport.free()
	if root.has_meta(BuildThumbnail.CACHE_KEY): root.remove_meta(BuildThumbnail.CACHE_KEY)
	print("BLUEPRINT_ART_TESTS checks=%d failures=%d" % [checks,failures])
	quit(int(failures > 0))
