extends RefCounted

static var face:FontVariation

static func regular() -> FontVariation:
	if face==null:
		var source:=load("res://assets/fonts/NotoSansTC-VF.ttf") as FontFile
		source.antialiasing=TextServer.FONT_ANTIALIASING_GRAY
		source.hinting=TextServer.HINTING_NORMAL
		face=FontVariation.new()
		face.base_font=source
		face.variation_embolden=0.6
		face.variation_opentype={"wght":500.0}
	return face
