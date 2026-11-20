extends RefCounted
## N11-2 Diandian draft: three code-native pose icons (knees / grass / cup).
## Hand-authored maps; '.' is transparent. Sizes: knees 28x18, grass 28x20, cup 26x16.
## Callers must use TEXTURE_FILTER_NEAREST. Invalid option returns null.

const PALETTE:={
	"O":Color("4a3328"), # warm dark outline
	"S":Color("d9a47f"), # skin
	"s":Color("b87f5e"), # skin shade
	"H":Color("ecc59f"), # skin highlight
	"B":Color("5f86a3"), # blue cloth
	"b":Color("476b87"), # cloth shade
	"L":Color("7fa3bb"), # cloth light
	"G":Color("7d9a5a"), # grass
	"g":Color("5b7a45"), # grass shade
	"l":Color("a3b878"), # grass light
	"D":Color("8a6a4a"), # soil
	"T":Color("c8734d"), # terracotta
	"t":Color("a05a3a"), # terracotta shade
	"R":Color("e09a6e"), # terracotta light
	"I":Color("6a3a28"), # cup interior
	"W":Color("efe0bd"), # steam
}

const MAPS:={
	"knees":[
		"............................",
		".....OOOOO........OOOOO.....",
		"....OHHHSSO......OHHHSSO....",
		"...OHHSSSSsO....OHHSSSSsO...",
		"...OSSSSSSsO....OSSSSSSsO...",
		"...OSSSSSssO....OSSSSSssO...",
		"..OOSsSsSsOOO...OOSsSsSsOOO.",
		".OOBBBBBBBBOO...OOBBBBBBBBOO",
		"OLLLBBBBBBBBBBBOOBBBBBBBBBBO",
		"OLLBBBBBBBBBBBBOOBBBBBBBBBBO",
		"OLBBBBBBBBBBBBBOOBBBBBBBBBbO",
		"OBBBBBBBBBBBBBBOOBBBBBBBBBbO",
		"OBBBBBbbBBBBBBBOObbBBBBBBBbO",
		"ObBBBBBBBBBBBBBOOBBBBBBBBBbO",
		"ObbBBBBBBBBBBBbOObbBBBBBBbbO",
		"ObbbBBBBBBBBbbbOObbbbBBBbbbO",
		"ObbbbbbbbbbbbbbOObbbbbbbbbbO",
		".OOOOOOOOOOOOOO..OOOOOOOOOO.",
	],
	"grass":[
		"............................",
		"..OOOO......................",
		".OSSSSO.....................",
		".OHSSSSO....................",
		"..OHSSSSO...................",
		"...OHSSSsO..................",
		"....OSSSSsO.................",
		".....OSSSSsO................",
		"......OSSSSsOOOO............",
		".......OSSSSSSSsOO..........",
		"........OSSSSSSSSsOOO.......",
		"........OSSSSSSSSSSsO.......",
		".....GGlOSsSsSsSsSsOGG......",
		"..lGGGGGOOOOOOOOOOOGGGGlG...",
		"lGGgGGGlGGGGgGGGGGGlGGgGGGGl",
		"GGgGGGGGGlGGGGGGgGGGGGGGlGGG",
		"gGGGDDGGGGgGGGGGGGGGDDGGGgGG",
		"ggGGGGgggGGGGGGGGgggGGGGGGgg",
		"gggggggDDgggggggggggggDDgggg",
		"DDDDDDDDDDDDDDDDDDDDDDDDDDDD",
	],
	"cup":[
		"..........W...W...........",
		"...........W...W..........",
		"......OOOOOOOOOOOOOO......",
		"......ORRIIIIIIIIRRO......",
		"......ORRTTTTTTTTttO......",
		"..OOOOOOOTTTTTTTTOOOOOOO..",
		"..OHHSSSORTTTTTttOSSSSsO..",
		"..OHSSSsORTTTTTttOSSSssO..",
		"..OSsSsSOTTTTTTttOSsSsSO..",
		"...OSSSsOTTTTTTttOSSSsO...",
		"....OSSsOTTTTTTttOSSsO....",
		".....OOOOTTTTTTttOOOO.....",
		"......OTTTTTTTTTTttO......",
		".......OTTTTTTTTttO.......",
		"........OTTTTttttO........",
		"........OOOOOOOOOO........",
	],
}

static var cache:Dictionary={}

static func texture(option:String) -> Texture2D:
	if not MAPS.has(option):
		return null
	if cache.has(option):
		return cache[option]
	var rows:Array=MAPS[option]
	var w:int=(rows[0] as String).length()
	var art:=Image.create_empty(w,rows.size(),false,Image.FORMAT_RGBA8)
	for y in rows.size():
		var row:String=rows[y]
		for x in mini(w,row.length()):
			var key:=row[x]
			if key!="." and PALETTE.has(key):
				art.set_pixel(x,y,PALETTE[key])
	var tex:=ImageTexture.create_from_image(art)
	cache[option]=tex
	return tex
