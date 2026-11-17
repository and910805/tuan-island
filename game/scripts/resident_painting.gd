extends Control
## The sketch uses the same resident pixel art the player sees on the island.
const People=preload("res://scripts/character_sprite_art.gd")
const Bobo=preload("res://scripts/bobo_art.gd")
const Xinghe=preload("res://scripts/lanyang_life_art.gd")
const Tea=preload("res://scripts/tea_resident_art.gd")
const Ground:Texture2D=preload("res://assets/village-preview/terrain.png")
const Props:Texture2D=preload("res://assets/village-preview/props.png")
const Crops=preload("res://scripts/inventory_item_art.gd")

var subjects:Array=[]
var finished:=false
var people=People.new()

func _ready() -> void:
	custom_minimum_size=Vector2(0,164)
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	people.setup()

func _draw() -> void:
	var height:=size.y
	draw_rect(Rect2(Vector2.ZERO,size),Color("ead8ac"))
	var grass_start:=height-43
	for x in range(6,floori(size.x)-6,64):
		var width:=minf(64,size.x-6-x)
		draw_texture_rect_region(Ground,Rect2(x,grass_start,width,37),Rect2(0,0,width/2,19),Color("bac092"))
	for prop in [[0.025,0],[0.22,1],[0.39,2],[0.62,1],[0.79,2],[0.89,3]]:
		var x:=floorf(size.x*float(prop[0]))
		draw_texture_rect_region(Props,Rect2(x,grass_start-51,56,56),Rect2(int(prop[1])*64,0,64,64),Color(0.8,0.76,0.58,0.62))
	draw_rect(Rect2(5,5,size.x-10,height-10),Color("987e54"),false)
	if not finished:
		for index in range(1,3):
			var x:=floorf(size.x*index/3)
			draw_dashed_line(Vector2(x,12),Vector2(x,height-9),Color("b3a074"),1.0,3.0)
	var flower:=Crops.icon("bluebell")
	for offset in [Vector2(0.09,0.74),Vector2(0.28,0.83),Vector2(0.42,0.75),Vector2(0.61,0.81),Vector2(0.76,0.74),Vector2(0.91,0.82)]:
		draw_texture_rect(flower,Rect2(size*offset,Vector2(19,19)),false,Color(1,1,1,0.85))
	var columns:=maxi(3,subjects.size())
	for index in subjects.size():
		var id:String=subjects[index]
		var anchor:=Vector2(roundf(size.x*(index+0.5)/columns),roundf(height-20))
		if id.is_empty():
			var blank:=Rect2(anchor-Vector2(37,114),Vector2(74,116))
			draw_rect(blank,Color(0.90,0.82,0.65,0.8))
			draw_rect(blank,Color("aa9267"),false)
			continue
		var portrait:Texture2D
		match id:
			"bobo":portrait=Bobo.icon("portrait")
			"xinghe":portrait=Xinghe.portrait()
			"chacha":portrait=Tea.portrait("host")
		if portrait!=null:
			var dimensions:=portrait.get_size()
			var extent:=dimensions*maxf(1.0,floorf(110.0/maxf(dimensions.x,dimensions.y)))
			draw_texture_rect(portrait,Rect2(anchor-Vector2(extent.x*0.5,extent.y),extent),false)
		else:
			draw_set_transform(anchor,0.0,Vector2(3,3))
			people.draw_person(self,Vector2.ZERO,Color.WHITE,id,Vector2i.DOWN,0.0,false,true)
			draw_set_transform(Vector2.ZERO)
