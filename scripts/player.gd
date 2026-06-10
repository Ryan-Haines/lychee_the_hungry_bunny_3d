class_name PlayerBunny
extends "res://scripts/bunny.gd"

# Set by main.gd: hops weaken when Lychee is starving.
var power_scale := 1.0


func _physics_process(delta: float) -> void:
	if not frozen:
		var iv := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		if iv.length() > 0.1 and is_on_floor():
			set_flop(false)
			var sprint := Input.is_action_pressed("sprint")
			var dir := Vector3(iv.x, 0, iv.y).normalized()
			try_hop(dir, (1.6 if sprint else 1.0) * power_scale, 1.12 if sprint else 1.0)
	super._physics_process(delta)
