extends SceneTree
## Reproduction of the root finding (work/salt/root-apprentice-probe): an
## expired / released apprentice shift whose kit refund would exceed LIMIT.
## Baseline-API only, so it runs unchanged on the production snapshot (expected
## to FAIL there) and on the staged patch (expected to PASS). Exit 1 on any
## failure.

const SP=preload("res://scripts/salt_pan.gd")
const F=preload("res://tests/salt_apprentice_fixture.gd")
var checks:=0
var failures:=0

func expect(c:bool,detail:String) -> void:
	checks+=1
	if not c:
		failures+=1
		print("FAIL: "+detail)

func _initialize() -> void:
	expiry_at_limit_with_waiter()
	release_at_limit()
	graduation_at_limit()
	print("APPRENTICE_LIMIT_REPRO_TESTS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures>0 else 0)

## Tenant with wheel+rake installed and both kits at LIMIT in inventory; a
## waiting 10th player. Probe times 4320/8640/12960 after `since`.
func full_tenant(s:Dictionary) -> float:
	var since:=float(s.time)
	expect(F.act(s,F.LATE,"salt_claim",F.pan_cell(18)).ok,"late joiner takes the shift")
	F.bag(s,F.LATE).merge({"salt_wheel_kit":1,"salt_rake_kit":1},true)
	expect(F.act(s,F.LATE,"salt_install",SP.wheel_socket(9).position,"wheel").ok,"wheel installed")
	s.salt_pan.players[F.LATE].wheel_raked=1
	expect(F.act(s,F.LATE,"salt_install",SP.rake_socket(9).position,"rake").ok,"rake installed")
	F.bag(s,F.LATE).merge({"salt_wheel_kit":SP.LIMIT,"salt_rake_kit":SP.LIMIT},true)
	F.act(s,F.TENTH,"salt_claim",F.pan_cell(18)) # baseline: refused; patch: joins the queue
	return since

func expiry_at_limit_with_waiter() -> void:
	var s:=F.saturated()
	var since:=full_tenant(s)
	var wheels:=F.kit_total(s,"salt_wheel_kit")
	var rakes:=F.kit_total(s,"salt_rake_kit")
	var released_at:=-1.0
	for k in 3:
		var t:=since+SP.SHIFT_SECONDS*float(k+1)
		var r:=F.tick(s,t)
		expect(r.ok,"step to %s ok"%t)
		if released_at<0.0 and s.salt_pan.apprentice.tenant=="":released_at=t
		expect(F.kit_total(s,"salt_wheel_kit")==wheels and F.kit_total(s,"salt_rake_kit")==rakes,"kits conserved at %s"%t)
	expect(released_at==since+SP.SHIFT_SECONDS,"expired tenant released at the first expiry (released_at=%s, tenant=%s)"%[released_at,s.salt_pan.apprentice.tenant])
	expect(int(F.bag(s,F.LATE).salt_wheel_kit)==SP.LIMIT and int(F.bag(s,F.LATE).salt_rake_kit)==SP.LIMIT,"inventory never exceeds LIMIT")
	var take:=F.act(s,F.TENTH,"salt_claim",F.pan_cell(18))
	expect(take.ok and s.salt_pan.apprentice.tenant==F.TENTH,"waiting 10th player gets the shift after expiry (%s)"%take.message)
	expect(SP.valid(s.duplicate(true)),"state valid after release at LIMIT")

func release_at_limit() -> void:
	var s:=F.saturated()
	full_tenant(s)
	var wheels:=F.kit_total(s,"salt_wheel_kit")
	var r:=F.act(s,F.LATE,"salt_release",F.pan_cell(18))
	expect(r.ok and s.salt_pan.apprentice.tenant=="","voluntary release at LIMIT succeeds (%s)"%r.message)
	expect(F.kit_total(s,"salt_wheel_kit")==wheels,"release conserves kits")

func graduation_at_limit() -> void:
	var s:=F.saturated()
	full_tenant(s)
	expect(F.act(s,F.LATE,"salt_auto_cfg",SP.rake_socket(9).position,"47,23|30").ok,"cfg")
	expect(F.act(s,F.LATE,"salt_auto_toggle",SP.rake_socket(9).position).ok,"on")
	var rakes:=F.kit_total(s,"salt_rake_kit")
	var t:=float(s.time)
	# wheel refill + crystallise + collect -> graduation within one sunny/cloudy day budget
	F.tick(s,t+3.0*F.DAY)
	expect(int(s.salt_pan.players[F.LATE].auto_raked)>=1,"automatic delivery happened")
	expect(s.salt_pan.apprentice.tenant=="","graduated tenant released even at LIMIT")
	expect(F.kit_total(s,"salt_rake_kit")==rakes,"graduation conserves kits")
