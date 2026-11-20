extends RefCounted

const TEXTURE=preload("res://assets/ui-life/leaf-floor-mat.png")
const INDUSTRY=preload("res://scripts/industry.gd")

static func tint(shade:String) -> Color:
	return Color("83ad89") if shade=="dark" else Color.WHITE

static func own_mat_cell(data:Dictionary,player_id:String) -> Vector2i:
	var player:Dictionary=data.get("players",{}).get(player_id,{})
	if not player.is_empty() and not player.has("master_bench_seat"):
		var tile:=Vector2i(Vector2(player.x,player.y).floor())
		var mat:Dictionary=data.get("ground",{}).get("%d,%d"%[tile.x,tile.y],{})
		if mat.get("type")==INDUSTRY.LEAF_MAT and mat.get("owner")==player_id:return tile
	return Vector2i(-1,-1)
