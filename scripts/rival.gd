class_name RivalBunny
extends Bunny

# A rival bunny: wanders the pen and periodically raids the hay rack.
# Personality knobs: hop_power (speed) and hay_chance (greed).
# mode: idle, go, munch

var bunny_name := "Bunny"
var mode := "idle"
var timer := 1.5
var target := Vector3.ZERO
var hay_spot := Vector3.ZERO
var hop_power := 0.7
var hay_chance := 0.45
var hay_available := true   # set by main; empty racks aren't worth visiting
var shove_cd := 0.0   # cooldown for shoving the player off the hay


func _physics_process(delta: float) -> void:
	shove_cd = maxf(0.0, shove_cd - delta)
	if not frozen:
		timer -= delta
		match mode:
			"idle":
				if timer <= 0.0:
					if hay_available and randf() < hay_chance:
						target = hay_spot
					else:
						target = Vector3(randf_range(-7.0, 7.0), 0, randf_range(-7.0, 7.0))
					mode = "go"
			"go":
				var to := target - global_position
				to.y = 0.0
				if to.length() < 1.2:
					if target.distance_to(hay_spot) < 0.1:
						mode = "munch"
						timer = randf_range(4.0, 7.0)
						anim_state = "eat"
					else:
						mode = "idle"
						timer = randf_range(1.0, 4.0)
				elif is_on_floor() and hop_cooldown <= 0.0:
					try_hop(to.normalized(), hop_power, 0.9)
			"munch":
				if timer <= 0.0:
					anim_state = "idle"
					mode = "idle"
					timer = randf_range(1.0, 3.0)
	super._physics_process(delta)


func wants_hay() -> bool:
	return mode == "munch" or (mode == "go" and target.distance_to(hay_spot) < 0.1)
