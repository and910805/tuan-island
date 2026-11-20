@static_unload
extends RefCounted

const HOUSE=preload("res://assets/ui-life/quiet-birdhouse.png")
const Weather=preload("res://scripts/weather.gd")
const PALETTE:={
	"o":Color("293d41"),"b":Color("557d86"),"d":Color("3d5869"),"c":Color("ffe5a8"),
	"e":Color("221e24"),"g":Color("df9957"),"h":Color("80acaa"),
}
const PERCH:=[
	"..............",
	"........ooo...",
	".......obhbo..",
	".....oobcecg..",
	"....obbbccoo..",
	".ooodbbbcco...",
	"..oodddcoo....",
	".....oooo.....",
	"......g.g.....",
]
const FLY:=[
	"....ooo.......",
	"...obho.......",
	"...obdo.ooo...",
	"....oobobhbo..",
	".ooodbbceccg..",
	"..ooddcbccoo..",
	"....oooooo....",
	"..............",
	"..............",
]
const PECK:=[
	"..............",
	"..............",
	"..............",
	"....ooooooo...",
	"...obbbhbbco..",
	".ooodbbcoceo..",
	"..ooddccoogg..",
	".....oooo.....",
	"......g.g.....",
]
const PERCH_AT:=Vector2(5,4)
static var frames:Dictionary={}

static func pose(cell:Vector2i,world_time:float,elapsed:float,still:bool)->Dictionary:
	var minute:=fposmod(world_time,Weather.DAY_SECONDS)
	if minute<360.0 or minute>=1080.0:return {}
	if still:return {"offset":PERCH_AT,"frame":"perch"}
	var phase:=fposmod(elapsed+float(posmod(cell.x*17+cell.y*31,80))*0.1,9.0)
	if phase<4.5:
		return {"offset":PERCH_AT,"frame":"peck" if phase>3.9 else "perch"}
	if phase<5.3:
		var hop:=(phase-4.5)/0.8
		return {"offset":PERCH_AT+Vector2(5.0*sin(PI*hop),-3.0*sin(PI*hop)).round(),"frame":"perch"}
	if phase<7.0:
		var loop:=(phase-5.3)/1.7
		return {"offset":PERCH_AT+Vector2(16.0*sin(TAU*loop),-17.0*sin(PI*loop)).round(),"frame":"fly" if int(loop*12.0)%2==0 else "perch"}
	return {"offset":PERCH_AT,"frame":"perch"}

static func texture(frame:String)->Texture2D:
	if not frames.has(frame):
		var pixels:Array={"perch":PERCH,"peck":PECK,"fly":FLY}.get(frame,PERCH)
		var image:=Image.create_empty(14,9,false,Image.FORMAT_RGBA8)
		for y in pixels.size():
			for x in pixels[y].length():
				var ink:String=pixels[y][x]
				if PALETTE.has(ink):image.set_pixel(x,y,PALETTE[ink])
		frames[frame]=ImageTexture.create_from_image(image)
	return frames[frame]
