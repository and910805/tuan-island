extends RefCounted

const DURATION:=3.0
const BITE_SECONDS:=3.0
const HALF_WIDTH:=0.22
const SWEEP_SECONDS:=3.0
const ALIGN_SECONDS:=2.4
const MIN_SHADOW:=0.12
const MAX_SHADOW:=0.88
const ROD_TIERS:=["precision_rod","iron_rod","copper_rod"]
const ROD_EFFECTS:={
	"copper_rod":{"bite":2.6,"half_width":0.26},
	"iron_rod":{"bite":2.2,"half_width":0.30},
	"precision_rod":{"bite":1.8,"half_width":0.34},
}

static func bite_wait(rod:String)->float:
	return float(ROD_EFFECTS.get(rod,{}).get("bite",BITE_SECONDS))

static func band_half_width(cast:Dictionary)->float:
	return float(ROD_EFFECTS.get(str(cast.get("rod","")),{}).get("half_width",HALF_WIDTH))

static func shadow(ready:float,now:float) -> float:
	var phase:=fposmod(maxf(0.0,now-ready),2.0*SWEEP_SECONDS)/SWEEP_SECONDS
	return lerpf(MIN_SHADOW,MAX_SHADOW,1.0-absf(1.0-phase))

## Each adjustment gives the line a short settling window. Progress accrues
## only while the fish stays within the band during that window.
static func progress(cast:Dictionary,now:float) -> float:
	var start:=float(cast.aligned_at)-float(cast.ready)
	var end:=minf(now-float(cast.ready),start+ALIGN_SECONDS)
	var half_width:=band_half_width(cast)
	var lower:=clampf((float(cast.band)-half_width-MIN_SHADOW)/(MAX_SHADOW-MIN_SHADOW),0.0,1.0)
	var upper:=clampf((float(cast.band)+half_width-MIN_SHADOW)/(MAX_SHADOW-MIN_SHADOW),0.0,1.0)
	var total:=float(cast.tracked)
	var first:=floori(start/SWEEP_SECONDS)
	for sweep in range(first,floori(end/SWEEP_SECONDS)+1):
		var origin:=sweep*SWEEP_SECONDS
		var enter:=origin+(lower if sweep%2==0 else 1.0-upper)*SWEEP_SECONDS
		var leave:=origin+(upper if sweep%2==0 else 1.0-lower)*SWEEP_SECONDS
		total+=maxf(0.0,minf(end,leave)-maxf(start,enter))
	return minf(DURATION,total)
