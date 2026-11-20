extends RefCounted

const ACTION:="bark_frame_display"
const FIELD:="frame_display"
const SKETCH:="sketch"
const PHOTO_PREFIX:="photo:"
const SIZE:=Vector2i(48,30)
const PHOTO_BYTES:=SIZE.x*SIZE.y*2
const PHOTO_TEXT_LENGTH:=3840

static func packet_allowed(value:String)->bool:
	return value.is_empty() or value==SKETCH or (value.length()==PHOTO_PREFIX.length()+PHOTO_TEXT_LENGTH and value.begins_with(PHOTO_PREFIX))

static func photo_bytes(value:String)->PackedByteArray:
	if not packet_allowed(value) or not value.begins_with(PHOTO_PREFIX):return PackedByteArray()
	var encoded:=value.trim_prefix(PHOTO_PREFIX)
	var decoded:=Marshalls.base64_to_raw(encoded)
	if decoded.size()!=PHOTO_BYTES or Marshalls.raw_to_base64(decoded)!=encoded:return PackedByteArray()
	return decoded

static func valid_display(value:Variant)->bool:
	return value is String and (value==SKETCH or not photo_bytes(value).is_empty())

static func from_image(image:Image)->String:
	if image==null or image.is_empty():return ""
	var source:=image.get_size()
	var width:=mini(source.x,maxi(1,roundi(float(source.y)*SIZE.aspect())))
	var height:=mini(source.y,maxi(1,roundi(float(source.x)/SIZE.aspect())))
	var area:=Vector2i(width,height)
	var small:=image.get_region(Rect2i((source-area)/2,area))
	small.resize(SIZE.x,SIZE.y,Image.INTERPOLATE_LANCZOS)
	var pixels:=PackedByteArray()
	pixels.resize(PHOTO_BYTES)
	for y in SIZE.y:
		for x in SIZE.x:
			var color:=small.get_pixel(x,y)
			var red:=clampi(roundi(color.r*31.0),0,31)
			var green:=clampi(roundi(color.g*63.0),0,63)
			var blue:=clampi(roundi(color.b*31.0),0,31)
			pixels.encode_u16((y*SIZE.x+x)*2,(red<<11)|(green<<5)|blue)
	return PHOTO_PREFIX+Marshalls.raw_to_base64(pixels)
