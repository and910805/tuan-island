extends RefCounted
## Shared walkable layout for the illustrated home village. Rendering and
## world collision use this same geometry so natural resources cannot spawn
## in the middle of a road.

static func path_at(p:Vector2) -> bool:
	var n:=sin(p.x*4.3+p.y*1.7)*0.13+sin(p.x*1.1-p.y*3.4)*0.12
	# Compact central square, with a narrow eastbound shore lane and a southern
	# footpath. The smaller square keeps the open farm from reading as a plaza.
	# The west edge includes the market's fallback pitch.
	var plaza_radius_x:=5.2 if p.x<40.4 else 4.9
	var plaza:=Vector2((p.x-40.4)/plaza_radius_x,(p.y-30.5)/2.7).length()<1.0+n*0.12
	var east_center:=30.5+sin(p.x*0.23)*0.14
	var east:=p.x>=43.5 and p.x<=57.0 and absf(p.y-east_center)<0.82+n*0.45
	var south_center:=40.0+maxf(0,p.y-36.0)*0.64+sin((p.y-36.0)*0.43)*0.18
	var south:=p.y>=32.0 and p.y<52.0 and absf(p.x-south_center)<0.82+n*0.45
	return plaza or east or south
