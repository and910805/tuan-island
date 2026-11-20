extends Control

## N02-2 米露食譜紙角的插畫草圖。純顯示：不讀 World／Session，也不改任何狀態。
##
##   var map:Control=preload("res://scripts/milu_recipe_map.gd").new()
##   map.configure({"board":Vector2i(40,29),"shop":Vector2i(43,29),"table":Vector2i(-1,-1)},found_mask)
##   parent.add_child(map)            # configure 可在 add_child 之前或之後呼叫
##
## cells   site 名稱（"board"／"shop"／"table"）→ Vector2i，通常是 World.milu_recipe_cell(snapshot,site)。
##         缺少的 site、非 Vector2i、或任一分量 <0（例如 Vector2i(-1,-1)）都視為「位置未開放」。
## found   已找到的紙角位元遮罩（Goals.RECIPE_PAGES 的 bit：board=1、shop=2、table=4）。
##
## 版面：最小 275×176，水平 EXPAND_FILL；上方是北在上的廣場草圖，下方是三格圖例。
## 草圖以格子座標的相對位置等比例縮放（x、y 同一比例），不依賴父節點的版面。

const FURNITURE:Texture2D=preload("res://assets/ui-life/furniture.png")
const PLAZA_PROPS:Texture2D=preload("res://assets/village-preview/props.png")

const MIN_SIZE:=Vector2(275,176)
const SITES:=["board","shop","table"]
const NAMES:={"board":"公告板","shop":"種子攤","table":"共餐桌"}
const BITS:={"board":1,"shop":2,"table":4}
const MISSING:=Vector2i(-1,-1)

const LEGEND_HEIGHT:=44.0
const ICON_W:=40.0
const ICON_H:=48.0
const MIN_SPAN:=Vector2(6,3)   # 格子數；站位很近時不把圖放大成誇張的比例
const MAX_UNIT:=40.0           # 每格最多畫幾像素

const INK:=Color("3a2718")
const INK_SOFT:=Color("7a5f35")
const PAPER:=Color("f0e2bd")
const PAPER_EDGE:=Color("b99a63")
const GROUND:=Color("e3d2a4")
const ROUTE:=Color("a98a52")
const PENDING:=Color("c98a2b")
const PENDING_FILL:=Color("fff1c4")
const DONE:=Color("3f7f3a")
const DONE_FILL:=Color("dff0c8")
const WHITE:=Color("ffffff")

# 圖示只建立一次，所有實例共用。
static var _icons:Dictionary={}

var _cells:Dictionary={}
var _found:=0
var _paper:=StyleBoxFlat.new()
var _ground:=StyleBoxFlat.new()

func _init() -> void:
	custom_minimum_size=MIN_SIZE
	size_flags_horizontal=Control.SIZE_EXPAND_FILL
	mouse_filter=Control.MOUSE_FILTER_PASS
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	_paper.bg_color=PAPER
	_paper.set_border_width_all(2)
	_paper.border_color=PAPER_EDGE
	_paper.set_corner_radius_all(6)
	_ground.bg_color=GROUND
	_ground.set_border_width_all(1)
	_ground.border_color=ROUTE
	_ground.set_corner_radius_all(10)
	_refresh_text()

func configure(cells:Dictionary,found:int) -> void:
	_cells={}
	for site:String in SITES:
		var value:Variant=cells.get(site,MISSING)
		_cells[site]=value if value is Vector2i and value.x>=0 and value.y>=0 else MISSING
	_found=found&7
	_refresh_text()
	queue_redraw()

func is_collected(site:String) -> bool:
	return (_found&int(BITS.get(site,0)))!=0

func has_site(site:String) -> bool:
	return _cells.get(site,MISSING)!=MISSING

func _refresh_text() -> void:
	var lines:PackedStringArray=[]
	for index in SITES.size():
		var site:String=SITES[index]
		lines.append("%d %s：%s"%[index+1,NAMES[site],_status(site)])
	tooltip_text="\n".join(lines)

func _status(site:String) -> String:
	if is_collected(site):return "已找到"
	return "尚未找到" if has_site(site) else "位置未開放"

# ── 圖示 ───────────────────────────────────────────────

static func _icon(site:String) -> Texture2D:
	if _icons.has(site):return _icons[site]
	var texture:Texture2D
	match site:
		"board":texture=_prop(9)
		"table":texture=_furniture(6)
		"shop":texture=_prop(8)
	_icons[site]=texture
	return texture

static func _furniture(index:int) -> Texture2D:
	var atlas:=AtlasTexture.new()
	atlas.atlas=FURNITURE
	atlas.region=Rect2((index%4)*32,(index/4)*48,32,48)
	return atlas

static func _prop(index:int) -> Texture2D:
	var tile:=PLAZA_PROPS.get_image().get_region(Rect2i((index%4)*64,(index/4)*64,64,64))
	return ImageTexture.create_from_image(tile.get_region(tile.get_used_rect()))

# ── 版面 ───────────────────────────────────────────────

func _map_rect() -> Rect2:
	return Rect2(Vector2.ZERO,Vector2(size.x,maxf(0.0,size.y-LEGEND_HEIGHT)))

## site → 像素中心點（草圖座標）。只含有位置的 site。
func _layout(map:Rect2) -> Dictionary:
	var placed:Dictionary={}
	var low:=Vector2(INF,INF)
	var high:=Vector2(-INF,-INF)
	for site:String in SITES:
		if not has_site(site):continue
		var cell:Vector2=Vector2(_cells[site])
		low=low.min(cell)
		high=high.max(cell)
	if low.x==INF:return placed
	var span:=(high-low).max(MIN_SPAN)
	var inner:=Rect2(map.position+Vector2(ICON_W*0.5+10,ICON_H*0.5+14),map.size-Vector2(ICON_W+20,ICON_H+34))
	var unit:=minf(minf(inner.size.x/span.x,inner.size.y/span.y),MAX_UNIT)
	var centre:=(low+high)*0.5
	for site:String in SITES:
		if has_site(site):
			placed[site]=(inner.get_center()+(Vector2(_cells[site])-centre)*unit).round()
	# 北在上：y 小的在上方。格子太近時只在水平方向把圖示推開，不改相對上下關係。
	for pass_index in 2:
		for a in SITES.size():
			for b in range(a+1,SITES.size()):
				var first:String=SITES[a]
				var second:String=SITES[b]
				if not placed.has(first) or not placed.has(second):continue
				var delta:Vector2=placed[second]-placed[first]
				if absf(delta.x)>=ICON_W+4 or absf(delta.y)>=ICON_H+4:continue
				var push:=(ICON_W+4-absf(delta.x))*0.5
				var direction:=1.0 if delta.x>=0.0 else -1.0
				placed[first]+=Vector2(-direction*push,0).round()
				placed[second]+=Vector2(direction*push,0).round()
	var bounds:=Rect2(map.position+Vector2(ICON_W*0.5+4,ICON_H*0.5+8),map.size-Vector2(ICON_W+8,ICON_H+16))
	for site:String in placed:
		placed[site]=Vector2(clampf(placed[site].x,bounds.position.x,bounds.end.x),clampf(placed[site].y,bounds.position.y,bounds.end.y))
	return placed

# ── 繪製 ───────────────────────────────────────────────

func _draw() -> void:
	var font:=get_theme_default_font()
	var font_size:=maxi(12,get_theme_default_font_size())
	var map:=_map_rect()
	draw_style_box(_paper,map.grow(-1))
	draw_style_box(_ground,map.grow(-8))
	var placed:=_layout(map)
	_draw_compass(font,font_size,map)
	if placed.is_empty():
		_draw_centered(font,"草圖還沒畫出來",map.get_center(),font_size,INK_SOFT)
	# 路線：1 → 2 → 3，只連有位置的點。
	var previous:=Vector2(-1,-1)
	var have_previous:=false
	for site:String in SITES:
		if not placed.has(site):continue
		if have_previous:draw_dashed_line(previous,placed[site],ROUTE,2.0,6.0)
		previous=placed[site]
		have_previous=true
	for index in SITES.size():
		if placed.has(SITES[index]):_draw_site(font,font_size,SITES[index],index+1,placed[SITES[index]])
	_draw_legend(font,font_size)

func _draw_compass(font:Font,font_size:int,map:Rect2) -> void:
	var tip:=Vector2(map.end.x-24,map.position.y+14)
	draw_colored_polygon(PackedVector2Array([tip,tip+Vector2(-5,10),tip+Vector2(0,7),tip+Vector2(5,10)]),INK)
	draw_line(tip+Vector2(0,7),tip+Vector2(0,17),INK,2.0)
	draw_string(font,tip+Vector2(-font_size*0.5-9,font_size-3),"北",HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,INK)

func _draw_site(font:Font,font_size:int,site:String,number:int,at:Vector2) -> void:
	var done:=is_collected(site)
	var tone:=DONE if done else PENDING
	var plate:=Rect2(at-Vector2(ICON_W,ICON_H)*0.5,Vector2(ICON_W,ICON_H))
	draw_rect(Rect2(plate.position+Vector2(2,3),plate.size),Color(0.16,0.09,0.04,0.22))
	draw_rect(plate,DONE_FILL if done else PENDING_FILL)
	draw_rect(plate,tone,false,2.0)
	var texture:=_icon(site)
	if texture!=null:
		var native:=texture.get_size()
		var extent:=(native*minf(34.0/native.x,40.0/native.y)).round()
		draw_texture_rect(texture,Rect2((at-extent*0.5).round(),extent),false)
	# 編號：左上角圓牌。已找到：右上角另外蓋一個綠色勾章（不只靠顏色分辨）。
	_draw_number(font,font_size,plate.position+Vector2(1,1),number,tone)
	if done:_draw_check_badge(plate.position+Vector2(plate.size.x-1,1),9.0)

func _draw_number(font:Font,font_size:int,at:Vector2,number:int,tone:Color) -> void:
	draw_circle(at,10.0,INK)
	draw_circle(at,8.5,WHITE)
	draw_circle(at,7.0,tone)
	_draw_centered(font,str(number),at,font_size,WHITE)

func _draw_check_badge(at:Vector2,radius:float) -> void:
	draw_circle(at,radius+1.5,WHITE)
	draw_circle(at,radius,DONE)
	_draw_check(at,radius*0.55,WHITE,2.0)

func _draw_check(at:Vector2,extent:float,colour:Color,width:float) -> void:
	draw_polyline(PackedVector2Array([at+Vector2(-extent,0),at+Vector2(-extent*0.25,extent*0.7),at+Vector2(extent,-extent*0.7)]),colour,width)

func _draw_legend(font:Font,font_size:int) -> void:
	var top:=maxf(0.0,size.y-LEGEND_HEIGHT)+4.0
	var column:=size.x/float(SITES.size())
	for index in SITES.size():
		var site:String=SITES[index]
		var left:=column*index
		var done:=is_collected(site)
		var placed:=has_site(site)
		var tone:=DONE if done else (PENDING if placed else INK_SOFT)
		var badge:=Vector2(left+16,top+17)
		draw_circle(badge,11.0,INK)
		draw_circle(badge,9.5,WHITE)
		draw_circle(badge,8.0,tone if placed else PAPER_EDGE)
		_draw_centered(font,str(index+1),badge,font_size,WHITE)
		var text_x:=left+32
		var width:=column-36
		draw_string(font,Vector2(text_x,top+13),NAMES[site],HORIZONTAL_ALIGNMENT_LEFT,width,font_size,INK)
		var status_y:=top+31
		var status_x:=text_x
		if done:
			_draw_check(Vector2(text_x+5,status_y-4),4.5,DONE,2.0)
			status_x+=14
		draw_string(font,Vector2(status_x,status_y),_status(site),HORIZONTAL_ALIGNMENT_LEFT,width-(status_x-text_x),font_size-1,tone if placed else INK_SOFT)

func _draw_centered(font:Font,text:String,at:Vector2,font_size:int,colour:Color) -> void:
	var extent:=font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size)
	var baseline:=at+Vector2(-extent.x*0.5,font.get_ascent(font_size)-extent.y*0.5)
	draw_string(font,baseline.round(),text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,colour)
