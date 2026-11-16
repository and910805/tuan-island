extends Button

signal item_selected(item_id:String)

const PixelTheme=preload("res://scripts/inventory_pixel_theme.gd")
var item_id:=""
var count:=0
var item_title:=""
var artwork:=TextureRect.new()
var quantity:=Label.new()

func _init() -> void:
	custom_minimum_size=Vector2(80,80)
	size_flags_horizontal=Control.SIZE_SHRINK_CENTER
	size_flags_vertical=Control.SIZE_SHRINK_CENTER
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	theme_type_variation=&"ItemSlot"
	toggle_mode=true
	pressed.connect(func():item_selected.emit(item_id))
	artwork.position=Vector2(8,8)
	artwork.size=Vector2(64,64)
	artwork.mouse_filter=Control.MOUSE_FILTER_IGNORE
	artwork.expand_mode=TextureRect.EXPAND_IGNORE_SIZE
	artwork.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	add_child(artwork)
	quantity.position=Vector2(4,56)
	quantity.size=Vector2(70,20)
	quantity.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	quantity.mouse_filter=Control.MOUSE_FILTER_IGNORE
	quantity.add_theme_font_size_override("font_size",16)
	quantity.add_theme_color_override("font_color",Color("fff5d5"))
	quantity.add_theme_color_override("font_outline_color",Color("4c3828"))
	quantity.add_theme_constant_override("outline_size",4)
	add_child(quantity)

func _ready() -> void:
	if not has_theme_stylebox("normal","ItemSlot"):
		theme=PixelTheme.make(null)
	_fit_quantity()

func configure(id:String,texture:Texture2D,amount:int,title:String) -> void:
	item_id=id
	artwork.texture=texture
	item_title=title
	set_count(amount)
	_update_tooltip()

func set_count(amount:int) -> void:
	var value:=str(amount)
	if quantity.text==value:return
	count=amount
	quantity.text=value
	artwork.modulate.a=0.45 if count==0 else 1.0
	_update_tooltip()
	if is_node_ready():_fit_quantity()

func _update_tooltip() -> void:
	tooltip_text="%s\n持有 %d"%[item_title,count]

func _fit_quantity() -> void:
	var font:=quantity.get_theme_font("font")
	var font_size:=16
	while font_size>10 and font.get_string_size(quantity.text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x>66.0:
		font_size-=1
	quantity.add_theme_font_size_override("font_size",font_size)
	quantity.size.x=70

func set_selected(value:bool) -> void:
	set_pressed_no_signal(value)

