extends RefCounted
## Client-local poses for stationary residents using existing directional PNGs.
## Opt-in at standing world sites; never used by boats, seated guests or players.
const STYLES:=["aru","milu","xiaoli","mianmian","achao","nuannuan","luoluo","lingpopo","diandian"]

static func facing(style:String,rest:Vector2i,foot:Vector2,visitor:Vector2,has_visitor:bool,elapsed:float,quiet:bool) -> Vector2i:
	if quiet or style not in STYLES:return rest
	var offset:=visitor-foot
	if has_visitor and offset.length()<=72.0:
		if offset.length()<8.0:return rest
		return Vector2i(int(signf(offset.x)),0) if absf(offset.x)>absf(offset.y) else Vector2i(0,int(signf(offset.y)))
	# Most of each ten-second cycle is a relaxed front pose. Residents glance
	# at different moments rather than turning together like a clockwork row.
	var moment:=fposmod(elapsed+STYLES.find(style)*1.17,10.0)
	if moment>=6.0 and moment<6.7:return Vector2i.LEFT
	if moment>=7.4 and moment<8.1:return Vector2i.RIGHT
	return rest
