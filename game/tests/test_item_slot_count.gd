extends SceneTree
const Slot=preload("res://scripts/item_slot.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var slot:=Slot.new()
	slot.configure("wood",null,1000000000,"木材")
	root.add_child(slot)
	var label:Label=slot.quantity
	var font:=label.get_theme_font("font")
	var size:=label.get_theme_font_size("font_size")
	var good:=label.text=="1000000000" and size>=10 and size<16
	good=good and font.get_string_size(label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x<=label.size.x-4
	good=good and slot.tooltip_text.contains("1000000000")
	slot.set_count(12345)
	good=good and label.get_theme_font_size("font_size")==16
	slot.set_count(0)
	good=good and label.text=="0" and slot.artwork.modulate.a<1.0
	print("ITEM_SLOT_COUNT passed=",good)
	quit(0 if good else 1)
