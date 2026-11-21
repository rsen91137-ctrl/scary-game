extends "res://scratch_test/plan_col_base.gd"

func step_direct(v: Vector2) -> void:
	walker.velocity.x = v.x
	walker.velocity.z = v.y
	if walker.is_on_floor():
		walker.velocity.y = -0.1
	else:
		walker.velocity.y -= 9.8 * DT
	walker.move_and_slide()

func _ready() -> void:
	await build_world(true)
	var pos := stairs.to_global(Vector3(-0.68, 0.0, 0.9))
	for it in 8:
		place(pos)
		var a := walker.global_position
		var onf := walker.is_on_floor()
		var log := ""
		for f in 7:
			step_direct(Vector2(0, 1) * 1.05)
			log += " %.3f/%.3f%s" % [stairs.to_local(walker.global_position).z, walker.global_position.y, "F" if walker.is_on_floor() else ("W" if walker.is_on_wall() else "-")]
		print("from ", v3(stairs.to_local(pos)), " placed ", v3(stairs.to_local(a)), " floor=", onf, " :", log)
		pos = walker.global_position
	get_tree().quit()
