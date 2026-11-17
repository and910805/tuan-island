extends SceneTree

const World = preload("res://scripts/world.gd")

func _initialize() -> void:
	var world := World.new()
	if not world.load_world(OS.get_cmdline_user_args()[0]):
		quit(1)
		return
	world.add_player("legacy-character-original", "Original")
	world.state.players["legacy-character-original"].coins = 271
	if "--outdoor-visits" in OS.get_cmdline_user_args():
		var owner:Dictionary=world.state.players["legacy-character-original"]
		owner.x=26.5
		owner.y=22.5
		for tile:Vector2i in [Vector2i(27,21),Vector2i(28,21)]:
			world.state.ground[World.key(tile)]={"type":"floor","owner":"legacy-character-original","items":{}}
			if not World.base_resource(tile).is_empty():world.state.removed[World.key(tile)]=true
	if "--indoor-visits" in OS.get_cmdline_user_args():
		var token:="legacy-character-original"
		var owner:Dictionary=world.state.players[token]
		owner.x=27.5
		owner.y=22.5
		for y in range(20,24):
			for x in range(25,30):
				var tile:=Vector2i(x,y)
				var key:=World.key(tile)
				if not World.base_resource(tile).is_empty():world.state.removed[key]=true
				if x==25:continue
				if x in [26,29] or y in [20,23]:
					var kind:="door" if tile==Vector2i(26,21) else "wall"
					world.state.objects[key]={"type":kind,"owner":token,"items":{}}
				else:
					world.state.ground[key]={"type":"floor","owner":token,"items":{}}
					world.state.roofs[key]={"type":"roof","owner":token,"items":{}}
	quit(0 if world.save() else 1)
