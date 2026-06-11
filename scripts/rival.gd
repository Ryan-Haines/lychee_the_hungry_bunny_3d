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
var trapped := false   # the box has been pushed on top of this bunny (set by main)
var trap_t := 0.0
var bedtime := false   # end-of-day bed race (set by main): everyone wants the bed
var bed_spot := Vector3.ZERO


func _physics_process(delta: float) -> void:
	shove_cd = maxf(0.0, shove_cd - delta)
	if trapped and not frozen:
		# Squished under the box: no eating, no wandering, only regret.
		mode = "idle"
		timer = maxf(timer, 1.0)
		trap_t += delta
		if is_on_floor():
			anim_state = "squat"
		if trap_t > 6.0 and is_on_floor():
			# A desperate wriggle-free hop out from under the box.
			var ang := randf() * TAU
			try_hop(Vector3(sin(ang), 0, cos(ang)), 1.2, 1.1)
			trap_t = 0.0
	elif bedtime and not frozen:
		_bed_rush()
	elif not frozen:
		trap_t = 0.0
		if anim_state == "squat":
			anim_state = "idle"
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


func _bed_rush() -> void:
	# Bedtime: single-minded hops toward the bed. Once up on the mattress,
	# loaf there triumphantly until someone bumps them off.
	var to := bed_spot - global_position
	to.y = 0.0
	if global_position.y > 0.25 and to.length() < 1.15:
		if anim_state != "air":
			anim_state = "idle"
	elif is_on_floor() and hop_cooldown <= 0.0:
		var dir := to.normalized()
		# A little jitter so the two of them don't run the exact same line.
		dir = (dir + Vector3(randf_range(-0.2, 0.2), 0, randf_range(-0.2, 0.2))).normalized()
		# Extra height so the hop clears the mattress.
		try_hop(dir, maxf(hop_power, 0.8) * 1.2, 1.25)


func wants_hay() -> bool:
	return not trapped and (mode == "munch" or (mode == "go" and target.distance_to(hay_spot) < 0.1))
