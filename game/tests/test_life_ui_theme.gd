extends SceneTree

const Art=preload("res://scripts/life_ui_theme.gd")

func _initialize() -> void:
	var base:=Theme.new()
	base.default_font=SystemFont.new()
	base.default_font_size=17
	var original:=StyleBoxFlat.new()
	base.set_stylebox("normal","Button",original)
	var result:=Art.apply(base)
	assert(result.default_font==base.default_font and result.default_font_size==17)
	assert(base.get_stylebox("normal","Button")==original)
	for state in ["normal","hover","pressed","disabled","focus"]:
		assert(result.has_stylebox(state,"Button"))
	assert(result.has_stylebox("tab_selected","TabBar"))
	assert(result.has_stylebox("grabber_pressed","VScrollBar"))
	assert(result.has_stylebox("fill","ProgressBar"))
	assert(Art.panel_style() is StyleBoxTexture)
	assert(Art.compact_style().texture!=null)
	for kind in ["radish","lettuce","wheat","carrot","potato","tomato_seed"]:
		var crop:=Art.icon(kind)
		assert(crop is AtlasTexture and crop.get_size()==Vector2(32,32))
	for kind in ["aru","milu","xiaoli"]:
		assert(Art.icon(kind) is AtlasTexture)
	assert(Art.icon("unknown")==null)
	print("LIFE_UI_THEME_TESTS passed")
	quit()
