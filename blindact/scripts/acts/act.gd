class_name Act
extends RefCounted
## One stretch of the night. `g` is the director (game.gd) with its helpers
## (wait, man_say, think, man_walk, ...), its people, props and state.

var g: Node
var gen := 0


func _init(p_game: Node, p_gen: int) -> void:
	g = p_game
	gen = p_gen


func alive() -> bool:
	return g._alive(gen)


func wait(secs: float) -> void:
	await g.wait(secs)


## A named place in the flat (FlatBuilder.spots), or `fallback`.
func spot(name: String, fallback := Vector3.ZERO) -> Vector3:
	return g.flat.spots.get(name, fallback)


func has_spot(name: String) -> bool:
	return g.flat.spots.has(name)


func near(pos: Vector3, r: float) -> bool:
	return g.player.global_position.distance_to(pos) < r


## Something held up in front of the camera (plates, a glass, a fork).
func hold(item: Node3D, at := Vector3(0.0, -0.32, -0.55)) -> void:
	drop_held()
	g.player.cam.add_child(item)
	item.position = at
	g.set_meta("held_item", item)


func drop_held() -> void:
	if g.has_meta("held_item"):
		var it: Node3D = g.get_meta("held_item")
		if is_instance_valid(it):
			it.queue_free()
		g.remove_meta("held_item")
