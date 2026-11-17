extends "res://scripts/blueprint_thumbnail.gd"
## Same real sprites/whole-pixel fitting as the blueprint book, plus guide marks.
const GuideItems=preload("res://scripts/inventory_item_art.gd")
var markers:Array=[]
var selected_kind:=""
func _draw()->void:
	super._draw()
	if _cells==Vector2i.ZERO:return
	var content:=Vector2(_cells)*TILE+MARGIN_TOP_LEFT+MARGIN_BOTTOM_RIGHT
	var factor:=fit_scale(content)
	var offset:=((box_size-content*factor)*0.5).floor()
	draw_set_transform(offset,0,Vector2.ONE*factor)
	for marker:Dictionary in markers:
		var texture:=GuideItems.icon(str(marker.icon))
		if texture:draw_texture_rect(texture,Rect2(MARGIN_TOP_LEFT+Vector2(marker.x,marker.y)*TILE,Vector2(32,32)),false,Color(1,1,1,0.7))
	for entry:Dictionary in _pieces:
		var at:=MARGIN_TOP_LEFT+Vector2(entry.x,entry.y)*TILE
		if str(entry.kind)==selected_kind:draw_rect(Rect2(at+Vector2(1,1),Vector2(30,30)),Color("d9ab57"),false,1.0)
		if entry.kind=="conveyor":
			var arrow:String=["↑","→","↓","←"][int(entry.settings.dir)]
			var point:=at+Vector2(9,23)
			draw_string_outline(ThemeDB.fallback_font,point,arrow,HORIZONTAL_ALIGNMENT_LEFT,-1,20,3,Color("314c3b"))
			draw_string(ThemeDB.fallback_font,point,arrow,HORIZONTAL_ALIGNMENT_LEFT,-1,20,Color("fff5d5"))
