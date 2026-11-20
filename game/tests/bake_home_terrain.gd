extends SceneTree
## Rebuild the chunk textures from the original tile artwork and map geometry.
## godot --headless --path game --script res://tests/bake_home_terrain.gd

const Art=preload("res://scripts/village_preview_art.gd")

func _initialize() -> void:
	var art:=Art.new()
	if not art.setup():quit(1);return
	var directory:=ProjectSettings.globalize_path(Art.CHUNK_DIRECTORY)
	if DirAccess.make_dir_recursive_absolute(directory)!=OK:quit(1);return
	var last:=Art.chunk_at(Art.SHORE_BOUNDS.end-Vector2i.ONE)
	for y in range(last.y+1):
		for x in range(last.x+1):
			var chunk:=Vector2i(x,y)
			var cells:=Art.chunk_cells(chunk)
			var image:=Image.create_empty(cells.size.x*32,cells.size.y*32,false,Image.FORMAT_RGBA8)
			for row in range(cells.position.y,cells.end.y):
				for column in range(cells.position.x,cells.end.x):
					var tile:=Vector2i(column,row)
					var source:=art.compose_ground(tile,false)
					image.blit_rect(source,Rect2i(0,0,32,32),(tile-cells.position)*32)
			if image.save_png(ProjectSettings.globalize_path(Art.chunk_path(chunk)))!=OK:quit(1);return
	print("HOME_TERRAIN_BAKE chunks=%d"%((last.x+1)*(last.y+1)))
	quit()
