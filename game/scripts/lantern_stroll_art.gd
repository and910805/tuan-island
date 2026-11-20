extends RefCounted

const Rules=preload("res://scripts/lantern_stroll.gd")
const Lamps=preload("res://scripts/warm_lantern_night_art.gd")
const Furniture=preload("res://scripts/furniture_sprite_art.gd")
const PREFIX:="lantern_stroll:"
const WISH_TINT:={"safe":"home","friends":"friends","growth":"harvest"}

static func points(snapshot:Dictionary) -> Dictionary:
	if snapshot.get("region_id")!="home" or not snapshot.get("picnic",false):return {}
	var result:Dictionary={PREFIX+"sign":Vector2(Rules.SIGN)+Vector2(0.5,0.5)}
	if snapshot.get(Rules.KEY,{}).get("phase")!="idle":
		for id:String in Rules.ORDER:
			result[PREFIX+id]=Vector2(Rules.SITES[id].cell)+Vector2(0.5,0.5)
	return result

static func markers(snapshot:Dictionary) -> Dictionary:
	var result:Dictionary={}
	for point:String in points(snapshot):
		var site:=point.trim_prefix(PREFIX)
		var cell:Vector2i=Rules.SIGN if site=="sign" else Rules.SITES[site].cell
		result[cell]=site
	return result

static func draw_marker(view,at:Vector2,id:String,snapshot:Dictionary) -> void:
	if id=="sign":
		Furniture.draw_sprite(view,at,"sign")
		view.draw_texture_rect(Lamps.LAMP,Rect2(at+Vector2(11,-10),Vector2(10,13)),false)
	else:
		var wish:String=snapshot.get(Rules.KEY,{}).get("blessings",{}).get(id,"")
		Lamps.draw_station(view,at,"" if view.stroll_dim else WISH_TINT.get(wish,""),view.elapsed,view.reduced_motion or view.photograph_mode or view.stroll_dim,Rules.ORDER.find(id))
		var stamps:Dictionary=snapshot.get(Rules.VIEW_KEY,{}).get("stamps",{})
		if stamps.has(id):
			view.draw_rect(Rect2(at+Vector2(22,7),Vector2(9,9)),Color("376447"))
			for offset:Vector2 in [Vector2(24,11),Vector2(25,12),Vector2(26,11),Vector2(27,10),Vector2(28,9)]:
				view.draw_rect(Rect2(at+offset,Vector2.ONE),Color("fff5cf"))
	if view.focused_label==PREFIX+id:
		var label:String="燈籠散步" if id=="sign" else Rules.SITES[id].name
		view.world_label(at+Vector2(16,-20),label,PREFIX+id)

static func draw_carried(view,at:Vector2) -> void:
	var still:bool=view.reduced_motion or view.photograph_mode or view.stroll_dim
	var lamp:=at+Vector2(9,-18)
	if not still:lamp.y+=roundf(sin(view.elapsed*4.0))
	var strength:=0.18 if view.stroll_dim else 0.54
	view.draw_texture_rect(Lamps.pool("home"),Rect2(lamp-Vector2(22,15),Vector2(52,39)),false,Color(1,1,1,strength))
	view.draw_texture_rect(Lamps.LAMP,Rect2(lamp.round(),Vector2(10,13)),false,Color("e1c69b") if view.stroll_dim else Color("ffe2aa"))
