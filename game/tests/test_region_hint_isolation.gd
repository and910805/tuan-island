extends SceneTree
const World=preload("res://scripts/world.gd")
const View=preload("res://scripts/world_view.gd")
var checks:=0
var failures:=0
func _initialize()->void:
	var world:=World.new()
	world.add_player("viewer","旅人")
	var view:=View.new()
	view.player_id="viewer"
	for region in ["lanyang","tianwei"]:
		view.data=world.state.duplicate(true)
		view.data.region_id=region
		for cell in World.LANYANG_LIFE.BLOCKAGES:
			view.data.players.viewer.x=cell.x+0.5
			view.data.players.viewer.y=cell.y+0.5
			var focused:=view.interaction_focus()
			var expected:="ditch:"+World.key(cell)
			checks+=1
			if (region=="lanyang" and focused!=expected) or (region=="tianwei" and focused.begins_with("ditch:")):
				failures+=1;push_error("%s at%s unexpected focus%s"%[region,cell,focused])
	view.free()
	print("REGION_HINT_ISOLATION checks=%d failures=%d"%[checks,failures])
	quit(1 if failures else 0)
