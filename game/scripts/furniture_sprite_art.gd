@static_unload
extends RefCounted

const PATH:="res://assets/ui-life/furniture.png"
const Bobo=preload("res://scripts/bobo_art.gd")
const KINDS:=["chest","bench","bed","lamp","door","window","table","chair","stove","private_chest","sign","sofa"]
static var atlas:Texture2D

static func clear_cache()->void:
	atlas=null

static func draw_sprite(canvas:CanvasItem,at:Vector2,kind:String,tint:=Color.WHITE) -> bool:
	if kind=="ore_display":return Bobo.draw(canvas,at+Vector2(-8,-16),kind)
	if kind=="flower_pot":
		canvas.draw_texture(preload("res://assets/ui-inventory/flower-pot.png"),at)
		return true
	if kind=="mill":return preload("res://scripts/bakery_art.gd").draw_mill(canvas,at)
	if preload("res://scripts/souvenir_art.gd").has_kind(kind):return preload("res://scripts/souvenir_art.gd").draw(canvas,at,kind,tint) # T071 紀念票兌換裝飾（souvenir_art.gd 程式繪製的 32px 圖）
	if preload("res://scripts/resident_keepsake_art.gd").has_kind(kind):return preload("res://scripts/resident_keepsake_art.gd").draw(canvas,at,kind,tint) # T066 居民紀念小物（程式繪製的 32px 圖）
	var index:=KINDS.find(kind)
	if index<0:return false
	if atlas==null:
		if not ResourceLoader.exists(PATH):return false
		atlas=load(PATH) as Texture2D
		if atlas==null:return false
	var region:=Rect2((index%4)*32,(index/4)*48,32,48)
	canvas.draw_texture_rect_region(atlas,Rect2(at+Vector2(0,-16),Vector2(32,48)),region,tint)
	return true
