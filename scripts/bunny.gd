class_name Bunny
extends CharacterBody3D

# A bunny built entirely from primitive meshes, with hop-based locomotion.
# Hops are fast and snappy: high gravity, strong impulse, dead stop on landing.
# Flopping hands the visuals to a temporary ragdoll RigidBody3D.
# anim_state: idle, air, flop, eat, squat

const GRAVITY := 26.0
const HOP_SPEED := 3.2
const HOP_IMPULSE := 4.2
const GROUND_PAUSE := 0.08

var anim_state := "idle"
var heading := 0.0
var spin := 0.0          # remaining binky spin (radians)
var hop_cooldown := 0.0
var binky_cd := 0.0      # binkies are joy, not a spam button
var squash_t := 0.0      # landing squash timer
var bounds := 9.2
var frozen := false
var t := 0.0             # animation clock

# Lop ears hang down the sides of the head and swing on little springs,
# so they flop around ragdoll-style with every hop. Set before setup().
var lop_ears := false
var ear_swing_l := 0.0
var ear_swing_vel_l := 0.0
var ear_swing_r := 0.0
var ear_swing_vel_r := 0.0

var body_pivot: Node3D
var ear_l: Node3D
var ear_r: Node3D
var nose: MeshInstance3D
var col_shape: CollisionShape3D
var flop_body: RigidBody3D = null

# Shared sound system (set once by main); only noisy bunnies make hop sounds.
static var audio: Node = null
var make_sound := false
var knock_cd := 0.0


func setup(fur_color: Color) -> void:
	_build_mesh(fur_color)
	col_shape = CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.38
	col_shape.shape = sphere
	col_shape.position = Vector3(0, 0.4, 0)
	add_child(col_shape)
	t = randf() * 10.0
	heading = randf() * TAU
	rotation.y = heading


func try_hop(dir: Vector3, power := 1.0, height := 1.0) -> bool:
	if flop_body != null or not is_on_floor() or hop_cooldown > 0.0:
		return false
	if anim_state == "eat":
		anim_state = "idle"
	velocity = Vector3(dir.x * HOP_SPEED * power, HOP_IMPULSE * height, dir.z * HOP_SPEED * power)
	heading = atan2(dir.x, dir.z)
	anim_state = "air"
	if make_sound and audio:
		audio.sfx("hop", 0.45, 0.15)
	return true


func binky() -> bool:
	if flop_body != null or not is_on_floor() or binky_cd > 0.0:
		return false
	binky_cd = 2.5
	velocity = Vector3(velocity.x * 0.3, 5.6, velocity.z * 0.3)
	anim_state = "air"
	spin = TAU * (1.0 if randf() < 0.5 else -1.0)
	return true


func set_flop(on: bool) -> void:
	if on and flop_body == null and is_on_floor():
		_start_flop()
	elif not on and flop_body != null:
		_end_flop()


func _start_flop() -> void:
	anim_state = "flop"
	velocity = Vector3.ZERO

	flop_body = RigidBody3D.new()
	flop_body.mass = 1.2
	flop_body.linear_damp = 0.8
	flop_body.angular_damp = 1.4
	var pmat := PhysicsMaterial.new()
	pmat.friction = 1.0
	pmat.bounce = 0.05
	flop_body.physics_material_override = pmat

	# Ragdoll colliders roughly matching the body: capsule torso + sphere head.
	var torso_col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = 1.0
	torso_col.shape = cap
	torso_col.rotation.x = PI / 2.0
	torso_col.position = Vector3(0, 0.4, 0)
	flop_body.add_child(torso_col)
	var head_col := CollisionShape3D.new()
	var hs := SphereShape3D.new()
	hs.radius = 0.26
	head_col.shape = hs
	head_col.position = Vector3(0, 0.66, 0.42)
	flop_body.add_child(head_col)

	get_parent().add_child(flop_body)
	flop_body.global_transform = global_transform

	# Hand the visuals to the ragdoll, mute our own collider so they don't fight.
	body_pivot.reparent(flop_body)
	col_shape.set_deferred("disabled", true)

	# The dramatic part: sideways shove plus a roll around the facing axis.
	var fwd := Vector3(sin(heading), 0, cos(heading))
	var side_sign := 1.0 if randf() < 0.5 else -1.0
	var side := Vector3(fwd.z, 0, -fwd.x) * side_sign
	flop_body.apply_central_impulse(side * 2.2 + Vector3(0, 1.7, 0))
	flop_body.apply_torque_impulse(fwd * side_sign * 4.5)
	if make_sound and audio:
		audio.sfx("flop", 0.9)


func _end_flop() -> void:
	var p := flop_body.global_position
	global_position = Vector3(clampf(p.x, -bounds, bounds), 0.05, clampf(p.z, -bounds, bounds))

	body_pivot.reparent(self)
	# Keep the tumbled tilt so the get-up animation smoothly rights itself,
	# but clear yaw/offset (the character body owns those again).
	var rot := body_pivot.rotation
	body_pivot.position = Vector3(0, clampf(body_pivot.position.y, -0.3, 0.5), 0)
	body_pivot.rotation = Vector3(rot.x, 0.0, rot.z)

	flop_body.queue_free()
	flop_body = null
	col_shape.set_deferred("disabled", false)

	# Little get-up hop.
	velocity = Vector3(0, 2.0, 0)
	anim_state = "air"
	hop_cooldown = 0.15


func _physics_process(delta: float) -> void:
	if frozen:
		return
	if flop_body != null:
		# Our logical position follows the ragdoll while flopped.
		global_position.x = flop_body.global_position.x
		global_position.z = flop_body.global_position.z
		return

	velocity.y -= GRAVITY * delta
	move_and_slide()

	# Bunnies don't slide between hops: dead stop whenever grounded.
	# (move_and_slide zeroes velocity.y against the floor itself, so we can't
	# gate this on downward velocity - just kill momentum every grounded frame.)
	if is_on_floor():
		var was_airborne := anim_state == "air"
		velocity = Vector3.ZERO
		if was_airborne:
			anim_state = "idle"
			hop_cooldown = GROUND_PAUSE
			squash_t = 0.11
			if lop_ears:
				# Landing whips the hanging ears forward.
				ear_swing_vel_l += 6.5
				ear_swing_vel_r += 7.5
			if make_sound and audio:
				audio.sfx("land", 0.3, 0.2)
		if absf(spin) > 0.01:
			heading = rotation.y
			spin = 0.0

	# Shove the ball (or any rigid body) we hopped into. Impulse lands at the
	# contact point, so tall things like the cardboard box can tip over.
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var rb := col.get_collider() as RigidBody3D
		if rb and rb != flop_body:
			rb.apply_impulse(-col.get_normal() * 1.2, col.get_position() - rb.global_position)
			if audio and knock_cd <= 0.0:
				audio.sfx("knock", 0.8)
				knock_cd = 0.3

	hop_cooldown = maxf(0.0, hop_cooldown - delta)
	binky_cd = maxf(0.0, binky_cd - delta)
	knock_cd = maxf(0.0, knock_cd - delta)
	global_position.x = clampf(global_position.x, -bounds, bounds)
	global_position.z = clampf(global_position.z, -bounds, bounds)


func _process(delta: float) -> void:
	t += delta
	squash_t = maxf(0.0, squash_t - delta)

	if flop_body != null:
		# Ragdoll owns the pose; we just let the ears go limp.
		if lop_ears:
			_update_lop_ears(delta, flop_body.linear_velocity.y)
		else:
			ear_l.rotation.x = lerpf(ear_l.rotation.x, -0.9, minf(1.0, 4.0 * delta))
			ear_r.rotation.x = lerpf(ear_r.rotation.x, -0.95, minf(1.0, 4.0 * delta))
		return

	if absf(spin) > 0.01:
		var step := signf(spin) * minf(absf(spin), 14.0 * delta)
		rotation.y += step
		spin -= step
		heading = rotation.y
	else:
		rotation.y = lerp_angle(rotation.y, heading, minf(1.0, 14.0 * delta))

	# Per-state pose targets.
	var target_scale := Vector3(1.0, 1.0 + sin(t * 3.0) * 0.015, 1.0)
	var target_rx := 0.0
	var target_rz := 0.0
	var target_py := 0.0
	match anim_state:
		"eat":
			target_rx = 0.35 + sin(t * 11.0) * 0.08
		"squat":
			# Crouched, trembling with concentration.
			target_scale = Vector3(1.08, 0.62, 1.06)
			target_rx = -0.12
			target_rz = sin(t * 28.0) * 0.04
		"air":
			# Stretch along the arc: nose up on the rise, nose down on the fall.
			target_scale = Vector3(0.92, 1.14, 1.05)
			target_rx = clampf(-velocity.y * 0.06, -0.32, 0.42)
		_:
			if squash_t > 0.0:
				target_scale = Vector3(1.14, 0.74, 1.1)

	body_pivot.scale = body_pivot.scale.lerp(target_scale, minf(1.0, 14.0 * delta))
	body_pivot.rotation.x = lerpf(body_pivot.rotation.x, target_rx, minf(1.0, 12.0 * delta))
	body_pivot.rotation.z = lerpf(body_pivot.rotation.z, target_rz, minf(1.0, 7.0 * delta))
	body_pivot.position.y = lerpf(body_pivot.position.y, target_py, minf(1.0, 7.0 * delta))

	if lop_ears:
		_update_lop_ears(delta, velocity.y)
	else:
		# Upright ears: pinned back in the air, flipped forward on landing,
		# relaxed wiggle otherwise.
		var on_floor := is_on_floor()
		var ear_target := -0.15 + sin(t * 2.1) * 0.06
		if not on_floor:
			ear_target = -0.85
		elif squash_t > 0.0:
			ear_target = 0.3
		ear_l.rotation.x = lerpf(ear_l.rotation.x, ear_target, minf(1.0, 11.0 * delta))
		ear_r.rotation.x = lerpf(ear_r.rotation.x, ear_target + sin(t * 1.7) * 0.05, minf(1.0, 11.0 * delta))

	var twitch := 1.0 + maxf(0.0, sin(t * 13.0)) * 0.3 * (0.5 + 0.5 * sin(t * 0.9))
	nose.scale = Vector3.ONE * twitch


func _update_lop_ears(delta: float, vert_vel: float) -> void:
	# Each hanging ear is an underdamped spring chasing a target swing angle:
	# rising drags them back, falling floats them up, landings kick them
	# forward (see the landing impulse in _physics_process). The result is a
	# loose ragdoll-ish flop with every hop.
	delta = minf(delta, 0.05)
	var target := clampf(-vert_vel * 0.16, -0.65, 0.95)
	var target_l := target + 0.15 + sin(t * 2.3) * 0.04
	var target_r := target + 0.15 + sin(t * 2.3 + 1.4) * 0.04
	ear_swing_vel_l += ((target_l - ear_l.rotation.x) * 70.0 - ear_swing_vel_l * 7.0) * delta
	ear_swing_vel_r += ((target_r - ear_r.rotation.x) * 58.0 - ear_swing_vel_r * 6.0) * delta
	ear_l.rotation.x = clampf(ear_l.rotation.x + ear_swing_vel_l * delta, -1.1, 1.3)
	ear_r.rotation.x = clampf(ear_r.rotation.x + ear_swing_vel_r * delta, -1.1, 1.3)


func _build_mesh(fur_color: Color) -> void:
	body_pivot = Node3D.new()
	add_child(body_pivot)

	var fur := StandardMaterial3D.new()
	fur.albedo_color = fur_color
	fur.roughness = 0.95
	var pink := StandardMaterial3D.new()
	pink.albedo_color = Color(0.94, 0.66, 0.72)
	pink.roughness = 0.8
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.16, 0.13, 0.12)
	dark.roughness = 0.4

	_sphere(0.42, fur, Vector3(0, 0.38, 0), Vector3(0.95, 0.8, 1.25))      # torso
	_sphere(0.28, fur, Vector3(0, 0.66, 0.42))                             # head
	_sphere(0.04, dark, Vector3(-0.17, 0.72, 0.6))                         # eyes
	_sphere(0.04, dark, Vector3(0.17, 0.72, 0.6))
	nose = _sphere(0.035, pink, Vector3(0, 0.63, 0.69))
	_sphere(0.11, fur, Vector3(0, 0.42, -0.52))                            # tail
	_sphere(0.11, fur, Vector3(-0.2, 0.06, 0.15), Vector3(0.8, 0.5, 1.6))  # feet
	_sphere(0.11, fur, Vector3(0.2, 0.06, 0.15), Vector3(0.8, 0.5, 1.6))
	ear_l = _make_ear(-0.11, fur, pink)
	ear_r = _make_ear(0.11, fur, pink)


func _sphere(radius: float, mat: Material, pos: Vector3, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	mi.mesh = m
	mi.material_override = mat
	mi.position = pos
	mi.scale = scl
	body_pivot.add_child(mi)
	return mi


func _make_ear(x: float, fur: Material, pink: Material) -> Node3D:
	var ear := Node3D.new()
	var outer := MeshInstance3D.new()
	var om := CapsuleMesh.new()
	om.radius = 0.07
	om.height = 0.52 if lop_ears else 0.48
	outer.mesh = om
	outer.material_override = fur
	outer.position = Vector3(0, 0.2, 0)
	ear.add_child(outer)
	var inner := MeshInstance3D.new()
	var im := CapsuleMesh.new()
	im.radius = 0.035
	im.height = 0.34
	inner.mesh = im
	inner.material_override = pink
	inner.position = Vector3(0, 0.2, 0.045)
	ear.add_child(inner)
	if lop_ears:
		# Lop ears: pivot at the top of the head, capsule hanging down past the
		# cheeks. rotation.x is the swing axis the spring animates.
		ear.position = Vector3(x * 1.7, 0.84, 0.36)
		ear.rotation.z = 2.55 if x < 0.0 else -2.55
		ear.rotation.x = 0.15
	else:
		ear.position = Vector3(x, 0.88, 0.36)
		ear.rotation.x = -0.15
		ear.rotation.z = -0.12 if x > 0.0 else 0.12
	body_pivot.add_child(ear)
	return ear
