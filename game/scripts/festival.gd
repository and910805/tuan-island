extends RefCounted

const TREE_CELL := Vector2i(41,28)
const VISITORS := {
	Vector2i(38,28):"alei",
	Vector2i(39,28):"xinghe",
	Vector2i(43,28):"chacha",
	Vector2i(44,28):"potter",
}
const GOAL:=12
const COOLDOWN:=300.0
# All six locations are existing protected public tiles, so saved houses stay put.
const STOPS:=[Vector2i(38,30),Vector2i(42,28),Vector2i(40,31),Vector2i(44,30),Vector2i(39,28),Vector2i(41,30)]
static func fresh() -> Dictionary:
	return {"round":0,"active":false,"collected":0,"contributors":{},"started":0.0,"finished":0.0,"ready":0.0,"best":0.0}
static func target(f:Dictionary) -> Vector2i:
	return STOPS[(int(f.collected)+int(f.round)-1)%STOPS.size()]
static func ticket(f:Dictionary) -> String:
	return "%d:%d"%[int(f.round),int(f.collected)]
