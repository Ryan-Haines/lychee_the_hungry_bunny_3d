extends Node3D

# Lychee the Hungry Bunny - one full bunny day.
# Owns the title screen flow, the world, the meters, the poop QTE, the pee
# system, the human, evidence tracking, rivals, scoring, and the day cycle.

enum Urgency { NONE, POOP_URGENT, POOP_QTE, PEE_URGENT }

const DAY_LENGTH := 300.0
const BOUNDS := 9.2
const LITTER_RADIUS := 1.7

const POOP_WINDOW := 10.0      # seconds to reach the box once POOP TIME starts
const PEE_WINDOW := 8.0
const PEE_HOLD_TIME := 1.2
const QTE_PROMPTS := 3
const QTE_SWEEP := 0.9         # seconds per prompt sweep
const QTE_ZONE_START := 0.55
const QTE_ZONE_END := 0.85
const QTE_ACTIONS = ["move_forward", "move_left", "move_back", "move_right"]
const QTE_KEYS = {"move_forward": "W", "move_left": "A", "move_back": "S", "move_right": "D"}

const PHASES = [
	[0.0, "Morning"],
	[0.2, "Midday"],
	[0.45, "Afternoon"],
	[0.65, "Evening"],
	[0.85, "Night"],
]

const PHASE_OBJECTIVES = {
	"Morning": "MORNING. EAT EVERYTHING.",
	"Midday": "MIDDAY. CAUSE MISCHIEF.",
	"Afternoon": "TREAT TIME SOON. STAY ALERT.",
	"Evening": "ZOOMIE HOUR. MAXIMUM SPEED.",
	"Night": "NIGHT. FIND GOOD LOAF SPOT.",
}

# phase -> [sun color, sun energy, ambient energy]
const PHASE_LIGHT = {
	"Morning": [Color(1.0, 0.9, 0.77), 1.1, 0.7],
	"Midday": [Color(1.0, 1.0, 1.0), 1.4, 0.9],
	"Afternoon": [Color(1.0, 0.91, 0.75), 1.2, 0.8],
	"Evening": [Color(1.0, 0.7, 0.48), 0.85, 0.55],
	"Night": [Color(0.56, 0.64, 1.0), 0.35, 0.35],
}

# meters
var hunger := 35.0
var water := 60.0
var poop_meter := 30.0
var bladder := 25.0
var suspicion := 10.0

# stats
var score := 0.0
var clean_poops := 0
var clean_pees := 0
var qte_perfects := 0
var poop_messes := 0
var pee_messes := 0
var binkies := 0
var hay_eaten := 0.0

# urgency state machine
var urgency := Urgency.NONE
var urgency_timer := 0.0
var qte_prompts := []
var qte_index := 0
var qte_hits := 0
var qte_t := 0.0
var pee_hold := 0.0
# E must be released after an urgency starts before it counts as the squat
# input - otherwise holding E from eating/drinking would squat instantly.
var interact_released := false

# the human
var human_checking := false
var human_timer := 35.0
var check_timer := 0.0

# evidence on the floor: [{ "node": Node3D, "kind": "poop"|"pee" }]
var messes: Array = []

# game flow
var started := false
var game_over := false
var bedtime := false      # end-of-day bed race: claim the bed to finish
var bed_claim_t := 0.0
var time_of_day := 0.0
var current_phase := "Morning"
var menu_cam_angle := 0.0

var gi_stasis := false
var nudge_cd := 0.0
var theft_msg_cd := 10.0

# the chewable cardboard box
const BOX_SIZE := Vector3(1.1, 0.9, 1.1)
var chew_box: RigidBody3D
var chew_box_shape: BoxShape3D
var box_visual: Node3D
var box_scale := 1.0
var box_bits: Array = []
var box_bits_torn := 0
var box_chew_t := 0.0
var box_msg_done := false
var box_trap_msg_cd := 0.0
var box_bit_mat: StandardMaterial3D

# the hay economy
var hay_supply := 100.0
var gate_shakes := 0
var gate_shake_t := 0.0
var gate_shake_reset := 0.0
var gate_call_cd := 0.0
var hay_refill_timer := 0.0
var munch_cd := 0.0
var sip_cd := 0.0
var bed_bonus_cd := 0.0
var tunnel_last_mouth := ""
var tunnel_last_time := -10.0

var player: PlayerBunny
var rivals: Array = []
var hud: HUD
var audio: GameAudio
var camera: Camera3D
var cam_look := Vector3.ZERO
var sun: DirectionalLight3D
var env: Environment
var litter_ring: MeshInstance3D
var gate_node: Node3D
var straw_meshes: Array = []
var poop_mat: StandardMaterial3D
var pee_mat: StandardMaterial3D

var hay_pos := Vector3(-6, 0, -6)
var box_pos := Vector3(-3.2, 0, 3.2)
var water_pos := Vector3(6, 0, -6)
var litter_pos := Vector3(6.5, 0, 6.5)
var bed_pos := Vector3(0, 0, -7)
var tunnel_pos := Vector3(-6, 0, 6)
var gate_pos := Vector3(0, 0, BOUNDS + 0.72)


func _ready() -> void:
	Engine.time_scale = 1.0
	_setup_input()
	_build_environment()
	_build_pen()
	_spawn_bunnies()
	hud = HUD.new()
	add_child(hud)
	hud.start_game.connect(_on_start_game)
	hud.quit_to_menu.connect(_on_quit_to_menu)
	audio = GameAudio.new()
	add_child(audio)
	Bunny.audio = audio
	camera = Camera3D.new()
	camera.fov = 60.0
	add_child(camera)
	camera.position = Vector3(10.5, 5.5, 0)
	camera.look_at(Vector3(0, 0.5, 0))
	player.frozen = true
	hud.show_title()


func _process(delta: float) -> void:
	if not started:
		_update_menu_camera(delta)
		return

	if game_over:
		if Input.is_action_just_pressed("restart"):
			_on_quit_to_menu()
		return

	time_of_day += delta
	if not bedtime and time_of_day >= DAY_LENGTH:
		_start_bedtime()

	_handle_actions()
	if bedtime:
		_update_bedtime(delta)
		if game_over:
			return
	else:
		_update_meters(delta)
		_update_interactions(delta)
		_update_hay(delta)
		_update_urgency(delta)
		_update_human(delta)
		_update_social(delta)
	_update_box(delta)
	_update_lighting(delta)
	_update_camera(delta)
	_update_audio()
	_update_hud()


# --- game flow ----------------------------------------------------------------

func _on_start_game() -> void:
	started = true
	player.frozen = false
	hud.show_game()
	hud.message("HUNGER DETECTED. THE DAY BEGINS.")
	camera.global_position = player.global_position + Vector3(0, 3.8, 5.8)
	cam_look = player.global_position + Vector3(0, 0.5, 0)
	camera.look_at(cam_look)


func _on_quit_to_menu() -> void:
	get_tree().paused = false
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()


func _update_menu_camera(delta: float) -> void:
	menu_cam_angle += delta * 0.12
	camera.global_position = Vector3(sin(menu_cam_angle) * 10.5, 5.5, cos(menu_cam_angle) * 10.5)
	camera.look_at(Vector3(0, 0.5, 0))


# --- per-frame systems --------------------------------------------------------

func _handle_actions() -> void:
	if player.frozen:
		return
	if Input.is_action_just_pressed("binky"):
		if player.binky():
			audio.sfx("binky", 0.6)
			if not bedtime:
				binkies += 1
				score += 5.0
				if binkies % 3 == 1:
					hud.message("BINKY! JOY ACHIEVED.")
	if Input.is_action_just_pressed("flop"):
		var was_flopped := player.anim_state == "flop"
		player.set_flop(not was_flopped)
		if not bedtime and not was_flopped and player.anim_state == "flop" \
				and bed_bonus_cd <= 0.0 and _on_bed(player.global_position):
			score += 15.0
			bed_bonus_cd = 20.0
			audio.sfx("ding", 0.5)
			hud.message("BED FLOP. SUPREME COMFORT. +15.")


func _update_meters(delta: float) -> void:
	hunger = clampf(hunger - 0.8 * delta, 0.0, 100.0)
	water = clampf(water - 0.6 * delta, 0.0, 100.0)
	poop_meter = clampf(poop_meter + 0.4 * delta, 0.0, 100.0)
	bladder = clampf(bladder + 0.35 * delta, 0.0, 100.0)
	bed_bonus_cd = maxf(0.0, bed_bonus_cd - delta)

	# Suspicion only decays when there is no evidence on the floor.
	# Flopping looks innocent and drains it faster.
	if messes.is_empty():
		var susp_decay := 3.0 if player.anim_state == "flop" else 0.5
		suspicion = clampf(suspicion - susp_decay * delta, 0.0, 100.0)
	elif player.anim_state == "flop":
		suspicion = clampf(suspicion - 0.8 * delta, 0.0, 100.0)

	# Empty stomach = GI stasis: movement halved until hunger recovers.
	if not gi_stasis and hunger <= 0.5:
		gi_stasis = true
		audio.sfx("buzz", 0.8)
		hud.message("GI STASIS. MOVEMENT HALVED. EAT HAY NOW.")
	elif gi_stasis and hunger >= 25.0:
		gi_stasis = false
		hud.message("DIGESTION RESUMES. CRISIS AVERTED.")
	if gi_stasis:
		player.power_scale = 0.5
	else:
		player.power_scale = 0.65 if hunger < 15.0 else 1.0


func _update_interactions(delta: float) -> void:
	if urgency != Urgency.NONE or player.frozen:
		hud.set_prompt("")
		if player.anim_state == "eat":
			player.anim_state = "idle"
		return

	var near_hay := player.global_position.distance_to(hay_pos) < 1.9
	var near_water := player.global_position.distance_to(water_pos) < 1.6
	var near_box := is_instance_valid(chew_box) \
			and player.global_position.distance_to(chew_box.global_position) < 1.35
	var near_gate := Vector2(player.global_position.x - gate_pos.x, player.global_position.z - gate_pos.z).length() < 1.7
	var prompt := ""
	if near_hay:
		prompt = "Hold E to eat hay" if hay_supply > 0.0 else "Hay box EMPTY - shake the gate!"
	elif near_water:
		prompt = "Hold E to drink"
	elif near_box:
		prompt = "Hold E to chew the box (zero nutrition)"
	elif near_gate:
		prompt = "Press E to shake the gate (x%d)" % (3 - gate_shakes)
	hud.set_prompt(prompt)

	# Shaking the gate summons the human... if the hay is actually low.
	if near_gate and not near_hay and not near_water and not near_box and gate_call_cd <= 0.0 \
			and Input.is_action_just_pressed("interact"):
		gate_shakes += 1
		gate_shake_t = 0.4
		gate_shake_reset = 4.0
		audio.sfx("rattle", 0.9, 0.2)
		if gate_shakes >= 3:
			gate_shakes = 0
			gate_call_cd = 4.0
			if hay_supply > 50.0:
				_add_suspicion(15.0)
				audio.sfx("buzz", 0.8)
				hud.message("THE HAY IS FINE. THE HUMAN IS ANNOYED. +15 SUSPICION.")
			else:
				hay_refill_timer = 2.5
				audio.sfx("steps", 0.8)
				hud.message("THE HUMAN HEARD. HAY INCOMING.")

	var eating := false
	var chewing_box := false
	if Input.is_action_pressed("interact") and player.is_on_floor():
		if near_hay and hunger < 100.0 and hay_supply > 0.0:
			eating = true
			hunger = clampf(hunger + 14.0 * delta, 0.0, 100.0)
			poop_meter = clampf(poop_meter + 8.0 * delta, 0.0, 100.0)
			hay_eaten += 14.0 * delta
			hay_supply = maxf(0.0, hay_supply - 5.0 * delta)
			score += 2.0 * delta
			munch_cd -= delta
			if munch_cd <= 0.0:
				audio.sfx("eat", 0.85, 0.25)
				munch_cd = 0.22
		elif near_water and water < 100.0:
			eating = true
			water = clampf(water + 22.0 * delta, 0.0, 100.0)
			bladder = clampf(bladder + 12.0 * delta, 0.0, 100.0)
			sip_cd -= delta
			if sip_cd <= 0.0:
				audio.sfx("drink", 0.6, 0.15)
				sip_cd = 0.4
		elif near_box:
			# Chewing cardboard: zero nutrition, pure destruction.
			eating = true
			chewing_box = true
			box_chew_t -= delta
			if box_chew_t <= 0.0:
				box_chew_t = 0.45
				_tear_box_bit()
	if not chewing_box:
		box_chew_t = 0.3  # small wind-up before the first bite
	if eating:
		player.anim_state = "eat"
	elif player.anim_state == "eat":
		player.anim_state = "idle"


func _update_hay(delta: float) -> void:
	gate_call_cd = maxf(0.0, gate_call_cd - delta)
	gate_shake_reset -= delta
	if gate_shake_reset <= 0.0:
		gate_shakes = 0

	# Gate wobble while freshly shaken.
	if gate_shake_t > 0.0:
		gate_shake_t = maxf(0.0, gate_shake_t - delta)
		gate_node.position.x = sin(gate_shake_t * 55.0) * 0.06 * (gate_shake_t / 0.4)
	else:
		gate_node.position.x = 0.0

	# Rivals eat the hay too, and give up when it runs out.
	for r in rivals:
		r.hay_available = hay_supply > 0.5
		if r.mode == "munch":
			if hay_supply <= 0.0:
				r.mode = "idle"
				r.anim_state = "idle"
				r.timer = randf_range(1.0, 3.0)
			else:
				hay_supply = maxf(0.0, hay_supply - 2.0 * delta)

	# Human delivering fresh hay after a successful gate call.
	if hay_refill_timer > 0.0:
		hay_refill_timer -= delta
		if hay_refill_timer <= 0.0:
			hay_supply = 100.0
			audio.sfx("ding", 0.6)
			hud.message("FRESH HAY DELIVERED. FEAST.")

	# Straw visuals empty out with the supply.
	var visible_straws := int(ceil(hay_supply / 100.0 * straw_meshes.size()))
	for i in straw_meshes.size():
		straw_meshes[i].visible = i < visible_straws


# --- urgency: poop QTE and pee hold --------------------------------------------

func _update_urgency(delta: float) -> void:
	var real_delta := delta / maxf(Engine.time_scale, 0.05)
	if not Input.is_action_pressed("interact"):
		interact_released = true
	match urgency:
		Urgency.NONE:
			litter_ring.visible = false
			if poop_meter >= 100.0:
				_start_poop_urgent()
			elif bladder >= 100.0:
				_start_pee_urgent()
		Urgency.POOP_URGENT:
			urgency_timer -= real_delta
			hud.set_urgent("POOP IMMINENT!  %.1fs   |   PRESS E TO SQUAT" % maxf(0.0, urgency_timer))
			_pulse_ring()
			# Held input, not just-pressed: a press mid-hop sticks and the squat
			# starts the moment Lychee lands.
			if interact_released and Input.is_action_pressed("interact") and player.is_on_floor() and player.flop_body == null:
				_start_poop_qte()
			elif urgency_timer <= 0.0:
				_resolve_poop(-1)
		Urgency.POOP_QTE:
			_update_qte(delta)
		Urgency.PEE_URGENT:
			urgency_timer -= real_delta
			hud.set_urgent("BLADDER CRITICAL!  %.1fs   |   HOLD E TO PEE" % maxf(0.0, urgency_timer))
			_pulse_ring()
			if interact_released and Input.is_action_pressed("interact") and player.is_on_floor() and player.flop_body == null:
				player.anim_state = "squat"
				player.velocity = Vector3.ZERO
				pee_hold += real_delta
				hud.set_hold(pee_hold / PEE_HOLD_TIME)
				if pee_hold >= PEE_HOLD_TIME:
					_resolve_pee(false)
			else:
				if player.anim_state == "squat":
					player.anim_state = "idle"
				pee_hold = maxf(0.0, pee_hold - real_delta * 2.0)
				hud.set_hold(pee_hold / PEE_HOLD_TIME if pee_hold > 0.0 else -1.0)
				if urgency_timer <= 0.0:
					_resolve_pee(true)


func _start_poop_urgent() -> void:
	urgency = Urgency.POOP_URGENT
	urgency_timer = POOP_WINDOW
	interact_released = not Input.is_action_pressed("interact")
	Engine.time_scale = 0.55  # dramatic slow motion: the world holds its breath
	litter_ring.visible = true
	audio.sfx("alert", 0.8)
	hud.message("POOP TIME!")


func _start_pee_urgent() -> void:
	urgency = Urgency.PEE_URGENT
	urgency_timer = PEE_WINDOW
	pee_hold = 0.0
	interact_released = not Input.is_action_pressed("interact")
	litter_ring.visible = true
	audio.sfx("alert", 0.8)
	hud.message("BLADDER AT CAPACITY. THIS IS NOT A DRILL.")


func _start_poop_qte() -> void:
	urgency = Urgency.POOP_QTE
	Engine.time_scale = 1.0
	player.frozen = true
	player.velocity = Vector3.ZERO
	player.anim_state = "squat"
	qte_prompts = []
	for i in QTE_PROMPTS:
		qte_prompts.append(QTE_ACTIONS[randi() % QTE_ACTIONS.size()])
	qte_index = 0
	qte_hits = 0
	qte_t = 0.0
	hud.set_urgent("")
	hud.show_qte(true)
	hud.update_qte(QTE_KEYS[qte_prompts[0]], 0.0, 0, QTE_PROMPTS)


func _update_qte(delta: float) -> void:
	qte_t += delta / QTE_SWEEP
	var advance := false
	for action in QTE_ACTIONS:
		if Input.is_action_just_pressed(action):
			if action == qte_prompts[qte_index] and qte_t >= QTE_ZONE_START and qte_t <= QTE_ZONE_END:
				qte_hits += 1
				audio.sfx("ding", 0.7)
			else:
				audio.sfx("buzz", 0.7)
			advance = true
			break
	if qte_t > 1.0 and not advance:
		audio.sfx("buzz", 0.7)
		advance = true
	if advance:
		qte_index += 1
		qte_t = 0.0
		if qte_index >= QTE_PROMPTS:
			hud.show_qte(false)
			player.frozen = false
			player.anim_state = "idle"
			_resolve_poop(qte_hits)
			return
	hud.update_qte(QTE_KEYS[qte_prompts[qte_index]], qte_t, qte_hits, QTE_PROMPTS)


func _resolve_poop(hits: int) -> void:
	audio.sfx("plop", 0.9)
	var in_litter := player.global_position.distance_to(litter_pos) < LITTER_RADIUS
	if hits < 0:
		# Timer ran out wherever Lychee was standing.
		_spawn_mess("poop", player.global_position)
		_add_suspicion(30.0)
		hud.message("PANIC POOP. DIGNITY LOST.")
	elif hits >= QTE_PROMPTS:
		qte_perfects += 1
		if in_litter:
			clean_poops += 1
			score += 150.0
			suspicion = clampf(suspicion - 20.0, 0.0, 100.0)
			_spawn_poop_pile(_litter_spot(), true)
			audio.sfx("fanfare", 0.6)
			hud.message("LEGENDARY POOP. +150. FLAWLESS TECHNIQUE.")
		else:
			_spawn_mess("poop", player.global_position)
			score += 20.0
			_add_suspicion(10.0)
			hud.message("PERFECT TACTICAL POOP. TERRITORY CLAIMED.")
	elif hits == QTE_PROMPTS - 1:
		if in_litter:
			clean_poops += 1
			score += 100.0
			suspicion = clampf(suspicion - 12.0, 0.0, 100.0)
			_spawn_poop_pile(_litter_spot(), true)
			hud.message("CLEAN POOP. +100. THE LITTER BOX IS HONORED.")
		else:
			_spawn_mess("poop", player.global_position)
			score += 10.0
			_add_suspicion(18.0)
			hud.message("TACTICAL POOP. THE HUMAN WILL NOT BE PLEASED.")
	else:
		if in_litter:
			clean_poops += 1
			score += 40.0
			_spawn_poop_pile(_litter_spot(), true)
			_add_suspicion(5.0)
			hud.message("MESSY POOP. BARELY CONTAINED. +40.")
		else:
			_spawn_mess("poop", player.global_position)
			_spawn_mess("poop", player.global_position + Vector3(randf_range(-0.7, 0.7), 0, randf_range(-0.7, 0.7)))
			_add_suspicion(25.0)
			hud.message("SCATTERED POOP. ABSOLUTE CHAOS.")
	poop_meter = 0.0
	urgency = Urgency.NONE
	Engine.time_scale = 1.0
	hud.set_urgent("")


func _resolve_pee(panicked: bool) -> void:
	audio.sfx("pee", 0.8)
	hud.set_hold(-1.0)
	if player.anim_state == "squat":
		player.anim_state = "idle"
	var in_litter := player.global_position.distance_to(litter_pos) < LITTER_RADIUS
	if panicked:
		_spawn_mess("pee", player.global_position)
		_add_suspicion(30.0)
		hud.message("BLADDER FAILURE. SHAME.")
	elif in_litter:
		clean_pees += 1
		score += 60.0
		suspicion = clampf(suspicion - 10.0, 0.0, 100.0)
		audio.sfx("ding", 0.6)
		hud.message("DIGNIFIED PEE. +60.")
	else:
		_spawn_mess("pee", player.global_position)
		score += 5.0
		_add_suspicion(20.0)
		hud.message("TERRITORY MOISTENED. BOLD MOVE.")
	bladder = 0.0
	pee_hold = 0.0
	urgency = Urgency.NONE
	Engine.time_scale = 1.0
	hud.set_urgent("")


func _pulse_ring() -> void:
	litter_ring.visible = true
	var pulse := 1.0 + sin(time_of_day * 8.0) * 0.08
	litter_ring.scale = Vector3(pulse, 0.15, pulse)


func _litter_spot() -> Vector3:
	return litter_pos + Vector3(randf_range(-0.5, 0.5), 0, randf_range(-0.35, 0.35))


# --- the human ------------------------------------------------------------------

func _update_human(delta: float) -> void:
	if human_checking:
		check_timer -= delta
		var warning := "THE HUMAN IS LOOKING..."
		if not messes.is_empty():
			warning += "   FLOP (F) TO LOOK INNOCENT!"
		hud.set_human(warning)
		if check_timer <= 0.0:
			_finish_check()
	else:
		hud.set_human("")
		human_timer -= delta
		if human_timer <= 0.0:
			human_checking = true
			check_timer = 4.0
			audio.sfx("steps", 0.8)
			hud.message("FOOTSTEPS. THE HUMAN APPROACHES.")


func _finish_check() -> void:
	human_checking = false
	human_timer = randf_range(35.0, 60.0)
	hud.set_human("")

	var penalty := 0.0
	for m in messes:
		penalty += 16.0 if m["kind"] == "pee" else 10.0
	if penalty > 0.0:
		if player.anim_state == "flop":
			penalty *= 0.5
			hud.message("CUTE DEFENSE SUCCESSFUL. SUSPICION HALVED.")
		_add_suspicion(penalty)
	else:
		suspicion = clampf(suspicion - 12.0, 0.0, 100.0)
		hud.message("HUMAN SEES NOTHING. INNOCENT BUNNY.")

	if suspicion >= 90.0:
		_human_bust()
	elif messes.size() >= 4:
		_clean_messes()
		suspicion = clampf(suspicion - 10.0, 0.0, 100.0)
		hud.message("THE HUMAN CLEANS UP. EVIDENCE DESTROYED.")


func _human_bust() -> void:
	audio.sfx("bust", 0.9)
	score = maxf(0.0, score - 150.0)
	_clean_messes()
	suspicion = 35.0
	hud.message("\"LYCHEE. I KNOW THAT WAS YOU.\"  -150.")


func _clean_messes() -> void:
	for m in messes:
		var n: Node3D = m["node"]
		if is_instance_valid(n):
			n.queue_free()
	messes.clear()


func _add_suspicion(amount: float) -> void:
	suspicion = clampf(suspicion + amount, 0.0, 100.0)
	if amount >= 1.0:
		hud.flash_suspicion()


# --- social: nudging and the hay war ---------------------------------------------

func _update_social(delta: float) -> void:
	nudge_cd -= delta
	theft_msg_cd -= delta
	var player_at_hay := player.global_position.distance_to(hay_pos) < 1.9

	for r in rivals:
		var rival: RivalBunny = r
		var dist := player.global_position.distance_to(rival.global_position)

		# Player nudges a rival. Knocking one off the hay is worth points.
		if nudge_cd <= 0.0 and dist < 0.9 and not player.frozen:
			var away := rival.global_position - player.global_position
			away.y = 0.0
			if away.length() > 0.01:
				away = away.normalized()
				rival.velocity = Vector3(away.x * 3.5, 3.2, away.z * 3.5)
				rival.heading = atan2(away.x, away.z)
				rival.anim_state = "air"
				nudge_cd = 1.5
				audio.sfx("boop", 0.7)
				if rival.mode == "munch":
					rival.mode = "idle"
					rival.timer = randf_range(2.0, 4.0)
					score += 10.0
					hud.message("%s NUDGED OFF THE HAY. +10." % rival.bunny_name.to_upper())
				else:
					score += 2.0
					hud.message("NUDGE. DOMINANCE ASSERTED.")

		# A rival that wants the hay shoves YOU off it.
		if rival.shove_cd <= 0.0 and dist < 0.95 and player_at_hay and rival.wants_hay() \
				and rival.is_on_floor() and player.is_on_floor() \
				and not player.frozen and player.flop_body == null:
			var push := player.global_position - rival.global_position
			push.y = 0.0
			if push.length() > 0.01:
				push = push.normalized()
				player.velocity = Vector3(push.x * 4.0, 3.4, push.z * 4.0)
				player.heading = atan2(push.x, push.z)
				player.anim_state = "air"
				rival.shove_cd = 5.0
				audio.sfx("boop", 0.8)
				hud.message("%s SHOVED YOU OFF THE HAY. OUTRAGEOUS." % rival.bunny_name.to_upper())

	if theft_msg_cd <= 0.0:
		for r in rivals:
			if r.mode == "munch":
				hud.message("%s HAS THE HAY. UNACCEPTABLE." % r.bunny_name.to_upper())
				theft_msg_cd = 30.0
				break


# --- the cardboard box --------------------------------------------------------------

func _update_box(delta: float) -> void:
	box_trap_msg_cd = maxf(0.0, box_trap_msg_cd - delta)
	if not is_instance_valid(chew_box):
		return
	# A rival under the box footprint is pinned: no hay for them. The box
	# ignores rival collision, so Lychee can shove it right over one.
	var bp := chew_box.global_position
	for r in rivals:
		var rival: RivalBunny = r
		var was_trapped: bool = rival.trapped
		var horiz := Vector2(bp.x - rival.global_position.x, bp.z - rival.global_position.z).length()
		rival.trapped = horiz < 0.62 * box_scale and bp.y < 1.05
		if rival.trapped and not was_trapped and box_trap_msg_cd <= 0.0:
			box_trap_msg_cd = 3.0
			audio.sfx("ding", 0.6)
			if bedtime:
				hud.message("%s IS UNDER THE BOX. ONE LESS BED RIVAL." % rival.bunny_name.to_upper())
			else:
				score += 25.0
				hud.message("%s IS UNDER THE BOX. NO HAY FOR THEM. +25." % rival.bunny_name.to_upper())


func _tear_box_bit() -> void:
	box_bits_torn += 1
	score += 1.0
	audio.sfx("eat", 0.8, 0.3)
	if not box_msg_done:
		box_msg_done = true
		hud.message("CARDBOARD. ZERO NUTRITION. INFINITE JOY.")

	# A little scrap flutters to the floor near the box.
	if box_bit_mat == null:
		box_bit_mat = _mat(Color(0.64, 0.45, 0.26), 1.0)
	var bit := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(randf_range(0.08, 0.16), 0.012, randf_range(0.08, 0.16))
	bit.mesh = bm
	bit.material_override = box_bit_mat
	add_child(bit)
	var ang := randf() * TAU
	var dist := randf_range(0.55, 1.1)
	bit.global_position = Vector3(
		chew_box.global_position.x + sin(ang) * dist,
		0.03 + (box_bits.size() % 5) * 0.004,
		chew_box.global_position.z + cos(ang) * dist)
	bit.rotation.y = randf() * TAU
	box_bits.append(bit)
	if box_bits.size() > 40:
		var oldest: Node = box_bits.pop_front()
		if is_instance_valid(oldest):
			oldest.queue_free()

	# Each bite rocks the box - chew enough and over it goes.
	var away := chew_box.global_position - player.global_position
	away.y = 0.0
	away = away.normalized() if away.length() > 0.01 else Vector3(1, 0, 0)
	chew_box.apply_impulse(away * 0.5 + Vector3(0, 0.35, 0), Vector3(0, BOX_SIZE.y * 0.5 * box_scale, 0))
	chew_box.apply_torque_impulse(Vector3(randf_range(-0.8, 0.8), randf_range(-0.6, 0.6), randf_range(-0.8, 0.8)))

	# The box slowly shrinks as it is devoured (but never quite disappears).
	box_scale = maxf(0.55, box_scale - 0.015)
	chew_box_shape.size = BOX_SIZE * box_scale
	box_visual.scale = Vector3.ONE * box_scale


# --- tunnel and bed ---------------------------------------------------------------

func _on_tunnel_mouth(body: Node3D, side: String) -> void:
	if body != player or not started or game_over or bedtime:
		return
	if tunnel_last_mouth != "" and tunnel_last_mouth != side and (time_of_day - tunnel_last_time) < 4.0:
		score += 15.0
		audio.sfx("ding", 0.6)
		hud.message("TUNNEL RUN. +15.")
		tunnel_last_mouth = ""
	else:
		tunnel_last_mouth = side
		tunnel_last_time = time_of_day


func _on_bed(p: Vector3) -> bool:
	return absf(p.x - bed_pos.x) < 1.3 and absf(p.z - bed_pos.z) < 1.0 and p.y > 0.25


# --- presentation -----------------------------------------------------------------

func _update_lighting(delta: float) -> void:
	current_phase = _phase_at(time_of_day / DAY_LENGTH)
	var pl: Array = PHASE_LIGHT[current_phase]
	var k := minf(1.0, delta * 1.2)
	sun.light_color = sun.light_color.lerp(pl[0], k)
	sun.light_energy = lerpf(sun.light_energy, pl[1], k)
	env.ambient_light_energy = lerpf(env.ambient_light_energy, pl[2], k)


func _update_camera(delta: float) -> void:
	var desired := player.global_position + Vector3(0, 3.8, 5.8)
	camera.global_position = camera.global_position.lerp(desired, minf(1.0, 6.0 * delta))
	cam_look = cam_look.lerp(player.global_position + Vector3(0, 0.5, 0), minf(1.0, 8.0 * delta))
	camera.look_at(cam_look)


func _update_audio() -> void:
	# Music mood follows what is about to go wrong.
	var m := "calm"
	if bedtime:
		m = "zoomie"
	elif urgency != Urgency.NONE:
		m = "urgent"
	elif human_checking:
		m = "human"
	elif suspicion > 60.0 or not messes.is_empty():
		m = "sneaky"
	elif current_phase == "Night":
		m = "night"
	elif current_phase == "Evening":
		m = "zoomie"
	audio.set_mood(m)


func _update_hud() -> void:
	hud.set_meters(hunger, water, poop_meter, bladder, suspicion)
	hud.set_score(score)
	hud.set_clock(current_phase)
	var obj: String
	match urgency:
		Urgency.POOP_URGENT, Urgency.POOP_QTE:
			obj = "POOP IMMINENT. LITTER BOX. GO. GO. GO."
		Urgency.PEE_URGENT:
			obj = "BLADDER CRITICAL. LITTER BOX. NOW."
		_:
			if bedtime:
				obj = "BEDTIME. BUMP THE RIVALS. FLOP ON THE BED."
			elif human_checking:
				obj = "HUMAN WATCHING. BECOME INNOCENT."
			elif gi_stasis:
				obj = "GI STASIS. MOVEMENT HALVED. EAT HAY NOW."
			elif hay_supply <= 0.0:
				obj = "HAY GONE. SHAKE THE GATE. SUMMON THE HUMAN."
			elif hunger < 30.0:
				obj = "HUNGER CRITICAL. HAY REQUIRED."
			elif water < 30.0:
				obj = "WATER LOW. SIP NOW."
			elif not messes.is_empty():
				obj = "EVIDENCE ON THE FLOOR. RISKY."
			elif suspicion > 60.0:
				obj = "HUMAN SUSPICIOUS. BECOME INNOCENT. (FLOP)"
			else:
				obj = PHASE_OBJECTIVES[current_phase]
	hud.set_objective(obj)


# --- messes and visuals ------------------------------------------------------------

func _spawn_mess(kind: String, pos: Vector3) -> void:
	var node: Node3D
	if kind == "pee":
		node = _spawn_puddle(pos)
		pee_messes += 1
	else:
		node = _spawn_poop_pile(pos, false)
		poop_messes += 1
	messes.append({"node": node, "kind": kind})


func _spawn_poop_pile(pos: Vector3, in_litter: bool) -> Node3D:
	if poop_mat == null:
		poop_mat = _mat(Color(0.29, 0.2, 0.16), 1.0)
	var g := Node3D.new()
	add_child(g)
	g.global_position = Vector3(pos.x, 0.22 if in_litter else 0.0, pos.z)
	for i in 3:
		var p := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.07
		sm.height = 0.14
		p.mesh = sm
		p.material_override = poop_mat
		p.position = Vector3(randf_range(-0.12, 0.12), 0.06, randf_range(-0.12, 0.12))
		g.add_child(p)
	return g


func _spawn_puddle(pos: Vector3) -> Node3D:
	if pee_mat == null:
		pee_mat = _mat(Color(0.95, 0.88, 0.4, 0.55), 0.1)
		pee_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var puddle := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.45
	cm.bottom_radius = 0.45
	cm.height = 0.02
	puddle.mesh = cm
	puddle.material_override = pee_mat
	add_child(puddle)
	puddle.global_position = Vector3(pos.x, 0.015, pos.z)
	return puddle


# --- day end: the bed race -------------------------------------------------------

func _start_bedtime() -> void:
	bedtime = true
	bed_claim_t = 0.0
	# Bedtime forgives everything in flight: urgencies, the human, GI stasis.
	urgency = Urgency.NONE
	Engine.time_scale = 1.0
	player.frozen = false
	gi_stasis = false
	player.power_scale = 1.0
	human_checking = false
	litter_ring.visible = false
	hud.show_qte(false)
	hud.set_urgent("")
	hud.set_hold(-1.0)
	hud.set_human("")
	for r in rivals:
		r.bedtime = true
		r.mode = "idle"
		if r.anim_state == "eat":
			r.anim_state = "idle"
	audio.sfx("alert", 0.7)
	hud.message("SUNSET. ONE BED. THREE BUNNIES. CLAIM IT.")


func _update_bedtime(delta: float) -> void:
	# The bed race: everyone converges on the bed. Bump rivals away, they bump
	# you back, and the day only ends once Lychee flops on the mattress.
	# Nothing scores in here - the day's tally is already locked in.
	nudge_cd -= delta
	hud.set_prompt("BUMP THE RIVALS AWAY - FLOP (F) ON THE BED TO END THE DAY")

	var p := player.flop_body.global_position if player.flop_body != null else player.global_position
	if player.flop_body != null and _on_bed(p):
		bed_claim_t += delta
		if bed_claim_t >= 1.0:   # let the flop settle on the mattress
			_finish_day()
			return
	else:
		bed_claim_t = 0.0

	for r in rivals:
		var rival: RivalBunny = r
		var dist := player.global_position.distance_to(rival.global_position)

		# Bump a rival - they get launched away from the BED, not just from you.
		if nudge_cd <= 0.0 and dist < 0.95 and not player.frozen and player.flop_body == null:
			var away := rival.global_position - bed_pos
			away.y = 0.0
			if away.length() < 0.01:
				away = rival.global_position - player.global_position
				away.y = 0.0
			if away.length() > 0.01:
				away = away.normalized()
				rival.velocity = Vector3(away.x * 4.5, 3.6, away.z * 4.5)
				rival.heading = atan2(away.x, away.z)
				rival.anim_state = "air"
				nudge_cd = 1.2
				audio.sfx("boop", 0.7)
				hud.message("%s BUMPED AWAY FROM THE BED." % rival.bunny_name.to_upper())

		# Rivals bump Lychee away whenever the bed is being contested.
		if rival.shove_cd <= 0.0 and dist < 0.95 and not rival.trapped \
				and rival.is_on_floor() and player.flop_body == null and not player.frozen \
				and player.global_position.distance_to(bed_pos) < 3.2:
			var push := player.global_position - bed_pos
			push.y = 0.0
			if push.length() < 0.01:
				push = player.global_position - rival.global_position
				push.y = 0.0
			if push.length() > 0.01:
				push = push.normalized()
				player.velocity = Vector3(push.x * 4.2, 3.4, push.z * 4.2)
				player.heading = atan2(push.x, push.z)
				player.anim_state = "air"
				rival.shove_cd = 3.0
				audio.sfx("boop", 0.8)
				hud.message("%s WANTS THE BED TOO. RUDE." % rival.bunny_name.to_upper())


func _finish_day() -> void:
	game_over = true
	Engine.time_scale = 1.0
	audio.sfx("fanfare", 0.8)
	audio.set_mood("night")
	player.frozen = true
	for r in rivals:
		r.frozen = true
	hud.set_urgent("")
	hud.set_human("")
	hud.set_hold(-1.0)
	hud.show_qte(false)
	hud.set_prompt("")
	var stats := "Score: %d\nClean poops: %d  (perfect: %d)\nDignified pees: %d\nFloor poops: %d   Puddles: %d\nBinkies: %d\nHay devoured: %d\nCardboard shredded: %d bits" % [
		int(score), clean_poops, qte_perfects, clean_pees, poop_messes, pee_messes, binkies, int(hay_eaten), box_bits_torn
	]
	hud.show_end(_pick_title(), stats)


func _pick_title() -> String:
	if poop_messes + pee_messes == 0 and clean_poops >= 2:
		return "Lord of the Litter Box"
	if qte_perfects >= 2:
		return "The Poop Sniper"
	if pee_messes >= 2:
		return "Puddle Bandit"
	if poop_messes >= 3:
		return "Carpet Criminal"
	if box_bits_torn >= 25:
		return "Cardboard Connoisseur"
	if hay_eaten >= 150.0:
		return "Hay Vacuum"
	if binkies >= 6:
		return "Zoomie Legend"
	if suspicion >= 70.0:
		return "Tiny Menace"
	if clean_poops >= 1:
		return "Litter Apprentice"
	return "Supreme Loaf"


func _phase_at(f: float) -> String:
	var phase: String = PHASES[0][1]
	for entry in PHASES:
		if f >= entry[0]:
			phase = entry[1]
	return phase


# --- setup ----------------------------------------------------------------------

func _setup_input() -> void:
	var actions := {
		"move_forward": [KEY_W, KEY_UP],
		"move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT],
		"move_right": [KEY_D, KEY_RIGHT],
		"sprint": [KEY_SHIFT],
		"binky": [KEY_SPACE],
		"interact": [KEY_E],
		"flop": [KEY_F],
		"restart": [KEY_R],
		"menu": [KEY_ESCAPE],
	}
	for action in actions:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key in actions[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)


func _build_environment() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.93, 0.89, 0.81)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1.0, 0.96, 0.9)
	env.ambient_light_energy = 0.7
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.shadow_enabled = true
	sun.light_energy = 1.1
	sun.light_color = Color(1.0, 0.9, 0.77)
	add_child(sun)


func _spawn_bunnies() -> void:
	player = PlayerBunny.new()
	player.lop_ears = true   # Lychee is a lop
	player.setup(Color(0.96, 0.93, 0.88))
	player.position = Vector3(0, 0.2, 3)
	player.bounds = BOUNDS
	player.make_sound = true
	player.collision_mask = 1 | 2 | 4   # world + rivals + the chew box
	add_child(player)

	var potato := RivalBunny.new()
	potato.bunny_name = "Potato"
	potato.setup(Color(0.72, 0.54, 0.37))
	potato.position = Vector3(4, 0.2, -2)
	potato.bounds = BOUNDS
	potato.hay_spot = hay_pos
	add_child(potato)

	var gravy := RivalBunny.new()
	gravy.bunny_name = "Gravy"
	gravy.setup(Color(0.17, 0.16, 0.17))
	gravy.position = Vector3(-3, 0.2, 1)
	gravy.bounds = BOUNDS
	gravy.hay_spot = hay_pos
	gravy.hop_power = 0.55   # the big loaf is slow
	gravy.hay_chance = 0.6   # but extremely food-motivated
	add_child(gravy)

	rivals = [potato, gravy]
	for r in rivals:
		# Rivals live on layer 2, which the chew box's mask skips - that's what
		# lets the box be pushed right over a rival to pin it.
		r.collision_layer = 2
		r.collision_mask = 1 | 2
		r.bed_spot = bed_pos


func _mat(color: Color, rough := 0.9) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	return m


func _mesh_box(size: Vector3, color: Color, pos: Vector3, parent: Node3D = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	mi.mesh = m
	mi.material_override = _mat(color)
	mi.position = pos
	var p := parent if parent != null else self
	p.add_child(mi)
	return mi


func _round_rug(pos: Vector3, radius: float, color: Color) -> MeshInstance3D:
	var rug := MeshInstance3D.new()
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = 0.02
	rug.mesh = m
	rug.material_override = _mat(color, 1.0)
	rug.position = pos
	add_child(rug)
	return rug


func _rect_rug(pos: Vector3, size: Vector2, yaw: float, color: Color) -> MeshInstance3D:
	var rug := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = Vector3(size.x, 0.02, size.y)
	rug.mesh = m
	rug.material_override = _mat(color, 1.0)
	rug.position = pos
	rug.rotation.y = yaw
	add_child(rug)
	return rug


func _build_rugs() -> void:
	# Patchwork floor: a pile of mismatched rugs in different shapes, sizes and
	# colors, each at its own tiny height so the overlaps don't z-fight.
	_round_rug(Vector3(0, 0.006, 0.5), 4.6, Color(0.78, 0.68, 0.52))                    # big jute base
	_rect_rug(Vector3(2.5, 0.012, 2.1), Vector2(3.4, 2.4), 0.3, Color(0.72, 0.34, 0.30))  # dusty red
	_rect_rug(Vector3(-4.8, 0.012, 1.4), Vector2(2.6, 1.8), -0.5, Color(0.45, 0.56, 0.38)) # olive
	_round_rug(Vector3(4.4, 0.012, -3.4), 1.5, Color(0.36, 0.60, 0.58))                 # teal round
	_round_rug(Vector3(-4.3, 0.018, -2.6), 0.95, Color(0.58, 0.45, 0.66))               # little purple
	var oval := _round_rug(Vector3(0, 0.018, -4.4), 1.3, Color(0.92, 0.88, 0.78))       # cream oval by the ramp
	oval.scale = Vector3(1.5, 1.0, 0.85)

	# striped runner leading up to the gate
	var runner := _rect_rug(Vector3(0, 0.012, 7.6), Vector2(1.6, 2.8), 0.0, Color(0.30, 0.36, 0.50))
	for i in 3:
		var stripe := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(1.4, 0.012, 0.3)
		stripe.mesh = sm
		stripe.material_override = _mat(Color(0.85, 0.78, 0.60) if i % 2 == 0 else Color(0.70, 0.40, 0.35), 1.0)
		stripe.position = Vector3(0, 0.012, -0.8 + i * 0.8)
		runner.add_child(stripe)

	# little checkered patch rug
	var checker := Node3D.new()
	checker.position = Vector3(-2.4, 0.024, -1.4)
	checker.rotation.y = 0.4
	add_child(checker)
	for ix in 3:
		for iz in 2:
			var sq := MeshInstance3D.new()
			var qm := BoxMesh.new()
			qm.size = Vector3(0.62, 0.012, 0.62)
			sq.mesh = qm
			sq.material_override = _mat(Color(0.82, 0.62, 0.30) if (ix + iz) % 2 == 0 else Color(0.40, 0.32, 0.45), 1.0)
			sq.position = Vector3((ix - 1) * 0.64, 0, (iz - 0.5) * 0.64)
			checker.add_child(sq)


func _build_chew_box() -> void:
	# The cardboard box is a real rigid body: chewing rocks it until it topples,
	# and Lychee can shove it across the pen. It lives on its own collision
	# layer that rivals ignore, so it can be pushed right over one to pin it.
	chew_box = RigidBody3D.new()
	chew_box.mass = 0.5
	chew_box.linear_damp = 1.0
	chew_box.angular_damp = 0.8
	chew_box.collision_layer = 4
	chew_box.collision_mask = 1
	var pmat := PhysicsMaterial.new()
	pmat.friction = 0.6
	pmat.bounce = 0.05
	chew_box.physics_material_override = pmat
	var cs := CollisionShape3D.new()
	chew_box_shape = BoxShape3D.new()
	chew_box_shape.size = BOX_SIZE
	cs.shape = chew_box_shape
	chew_box.add_child(cs)

	box_visual = Node3D.new()
	chew_box.add_child(box_visual)
	_mesh_box(BOX_SIZE, Color(0.71, 0.52, 0.31), Vector3.ZERO, box_visual)
	_mesh_box(Vector3(0.3, BOX_SIZE.y + 0.02, BOX_SIZE.z + 0.02), Color(0.60, 0.43, 0.25), Vector3.ZERO, box_visual)  # tape
	var flap_l := _mesh_box(Vector3(0.5, 0.04, 1.04), Color(0.66, 0.47, 0.27), Vector3(-0.45, 0.52, 0), box_visual)
	flap_l.rotation.z = -0.55
	var flap_r := _mesh_box(Vector3(0.5, 0.04, 1.04), Color(0.66, 0.47, 0.27), Vector3(0.45, 0.52, 0), box_visual)
	flap_r.rotation.z = 0.55

	chew_box.position = box_pos + Vector3(0, BOX_SIZE.y * 0.5 + 0.05, 0)
	add_child(chew_box)


func _build_pen() -> void:
	# floor collision + visible carpet
	var floor_body := StaticBody3D.new()
	var fcol := CollisionShape3D.new()
	var fshape := BoxShape3D.new()
	fshape.size = Vector3(60, 1, 60)
	fcol.shape = fshape
	fcol.position = Vector3(0, -0.5, 0)
	floor_body.add_child(fcol)
	add_child(floor_body)

	var floor_mesh := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	floor_mesh.mesh = pm
	floor_mesh.material_override = _mat(Color(0.71, 0.58, 0.42), 1.0)
	add_child(floor_mesh)

	_build_rugs()

	# pen fence (visible + collision, also keeps the ball in)
	var fence_len := BOUNDS * 2.0 + 1.6
	for i in 4:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(fence_len, 1.2, 0.15)
		shape.shape = bs
		shape.position = Vector3(0, 0.6, 0)
		body.add_child(shape)
		var mesh := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(fence_len, 1.1, 0.12)
		mesh.mesh = bm
		mesh.material_override = _mat(Color(0.62, 0.66, 0.7), 0.5)
		mesh.position = Vector3(0, 0.55, 0)
		body.add_child(mesh)
		var r := BOUNDS + 0.8
		match i:
			0: body.position = Vector3(0, 0, -r)
			1: body.position = Vector3(0, 0, r)
			2:
				body.position = Vector3(-r, 0, 0)
				body.rotation.y = PI / 2.0
			3:
				body.position = Vector3(r, 0, 0)
				body.rotation.y = PI / 2.0
		add_child(body)

	# hay rack
	var hay := Node3D.new()
	hay.position = hay_pos
	add_child(hay)
	_mesh_box(Vector3(1.8, 0.5, 1.2), Color(0.54, 0.42, 0.28), Vector3(0, 0.25, 0), hay)
	var straw_mat := _mat(Color(0.85, 0.76, 0.37), 1.0)
	for i in 26:
		var straw := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.02
		cm.bottom_radius = 0.02
		cm.height = randf_range(0.45, 0.75)
		straw.mesh = cm
		straw.material_override = straw_mat
		straw.position = Vector3(randf_range(-0.75, 0.75), randf_range(0.55, 0.7), randf_range(-0.45, 0.45))
		straw.rotation = Vector3(randf_range(-0.45, 0.45), randf_range(0.0, TAU), randf_range(-0.45, 0.45))
		hay.add_child(straw)
		straw_meshes.append(straw)

	# the gate at the front of the pen: shake it to summon the human
	gate_node = Node3D.new()
	gate_node.position = gate_pos
	add_child(gate_node)
	var gate_col := Color(0.93, 0.93, 0.96)
	_mesh_box(Vector3(0.12, 1.2, 0.12), gate_col, Vector3(-1.1, 0.6, 0), gate_node)
	_mesh_box(Vector3(0.12, 1.2, 0.12), gate_col, Vector3(1.1, 0.6, 0), gate_node)
	_mesh_box(Vector3(2.3, 0.1, 0.1), gate_col, Vector3(0, 1.15, 0), gate_node)
	for i in 5:
		_mesh_box(Vector3(0.06, 1.05, 0.06), gate_col, Vector3(-0.75 + i * 0.375, 0.58, 0), gate_node)

	# water bowl
	var bowl := MeshInstance3D.new()
	var bowl_mesh := CylinderMesh.new()
	bowl_mesh.top_radius = 0.7
	bowl_mesh.bottom_radius = 0.55
	bowl_mesh.height = 0.3
	bowl.mesh = bowl_mesh
	bowl.material_override = _mat(Color(0.85, 0.85, 0.88), 0.35)
	bowl.position = water_pos + Vector3(0, 0.15, 0)
	add_child(bowl)
	var water_disc := MeshInstance3D.new()
	var wm := CylinderMesh.new()
	wm.top_radius = 0.6
	wm.bottom_radius = 0.6
	wm.height = 0.05
	water_disc.mesh = wm
	water_disc.material_override = _mat(Color(0.31, 0.62, 0.85), 0.05)
	water_disc.position = water_pos + Vector3(0, 0.28, 0)
	add_child(water_disc)

	# litter box (the sacred zone)
	var lb := Node3D.new()
	lb.position = litter_pos
	add_child(lb)
	_mesh_box(Vector3(2.2, 0.18, 1.7), Color(0.5, 0.55, 0.6), Vector3(0, 0.09, 0), lb)
	_mesh_box(Vector3(2.2, 0.5, 0.12), Color(0.56, 0.61, 0.66), Vector3(0, 0.43, -0.8), lb)
	_mesh_box(Vector3(2.2, 0.5, 0.12), Color(0.56, 0.61, 0.66), Vector3(0, 0.43, 0.8), lb)
	_mesh_box(Vector3(0.12, 0.5, 1.7), Color(0.56, 0.61, 0.66), Vector3(-1.05, 0.43, 0), lb)
	_mesh_box(Vector3(0.12, 0.5, 1.7), Color(0.56, 0.61, 0.66), Vector3(1.05, 0.43, 0), lb)
	_mesh_box(Vector3(1.9, 0.1, 1.4), Color(0.81, 0.78, 0.7), Vector3(0, 0.23, 0), lb)

	# litter target ring, shown during urgency
	litter_ring = MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 1.25
	ring_mesh.outer_radius = 1.55
	litter_ring.mesh = ring_mesh
	var ring_mat := _mat(Color(0.45, 0.9, 0.45), 0.6)
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(0.3, 0.9, 0.3)
	ring_mat.emission_energy_multiplier = 0.8
	litter_ring.material_override = ring_mat
	litter_ring.position = litter_pos + Vector3(0, 0.06, 0)
	litter_ring.scale = Vector3(1, 0.15, 1)
	litter_ring.visible = false
	add_child(litter_ring)

	# the bed: raised platform, reachable by ramp (or a perfect sprint hop).
	# Solid, so a ragdoll flop lands on it and stays.
	var bed := StaticBody3D.new()
	bed.position = bed_pos
	var bed_col := CollisionShape3D.new()
	var bed_shape := BoxShape3D.new()
	bed_shape.size = Vector3(2.5, 0.42, 1.9)
	bed_col.shape = bed_shape
	bed_col.position = Vector3(0, 0.21, 0)
	bed.add_child(bed_col)
	add_child(bed)
	_mesh_box(Vector3(2.6, 0.16, 2.0), Color(0.45, 0.32, 0.22), Vector3(0, 0.08, 0), bed)   # frame
	_mesh_box(Vector3(2.4, 0.26, 1.8), Color(0.93, 0.89, 0.8), Vector3(0, 0.29, 0), bed)    # mattress
	_mesh_box(Vector3(0.9, 0.14, 0.5), Color(1.0, 1.0, 0.98), Vector3(0, 0.49, -0.6), bed)  # pillow
	_mesh_box(Vector3(2.3, 0.06, 1.0), Color(0.45, 0.62, 0.65), Vector3(0, 0.45, 0.35), bed) # blanket

	# ramp up to the bed
	var ramp := StaticBody3D.new()
	ramp.position = Vector3(0, 0.19, -5.3)
	ramp.rotation.x = 0.27
	var ramp_col := CollisionShape3D.new()
	var ramp_shape := BoxShape3D.new()
	ramp_shape.size = Vector3(1.2, 0.1, 1.8)
	ramp_col.shape = ramp_shape
	ramp.add_child(ramp_col)
	var ramp_mesh := MeshInstance3D.new()
	var rm := BoxMesh.new()
	rm.size = Vector3(1.2, 0.1, 1.8)
	ramp_mesh.mesh = rm
	ramp_mesh.material_override = _mat(Color(0.52, 0.38, 0.26))
	ramp.add_child(ramp_mesh)
	add_child(ramp)

	# cardboard tunnel (CSG tube, open ends, real collision)
	var tunnel := CSGCombiner3D.new()
	tunnel.use_collision = true
	var outer := CSGCylinder3D.new()
	outer.radius = 0.9
	outer.height = 2.6
	outer.sides = 20
	outer.material = _mat(Color(0.71, 0.52, 0.31), 1.0)
	tunnel.add_child(outer)
	var inner := CSGCylinder3D.new()
	inner.radius = 0.76
	inner.height = 3.0
	inner.sides = 20
	inner.operation = CSGShape3D.OPERATION_SUBTRACTION
	tunnel.add_child(inner)
	tunnel.rotation_degrees = Vector3(0, 0, 90)
	tunnel.position = tunnel_pos + Vector3(0, 0.78, 0)
	add_child(tunnel)

	# tunnel-run sensors, one inside each mouth of the bore
	for side in ["west", "east"]:
		var area := Area3D.new()
		var acs := CollisionShape3D.new()
		var abs_shape := BoxShape3D.new()
		abs_shape.size = Vector3(0.4, 1.2, 1.2)
		acs.shape = abs_shape
		area.add_child(acs)
		area.position = tunnel_pos + Vector3(-1.0 if side == "west" else 1.0, 0.6, 0)
		add_child(area)
		area.body_entered.connect(_on_tunnel_mouth.bind(side))

	# the chewable cardboard box (moved out of the tunnel corner, onto open floor)
	_build_chew_box()

	# the ball (pushable)
	var ball := RigidBody3D.new()
	var bcol := CollisionShape3D.new()
	var bshape := SphereShape3D.new()
	bshape.radius = 0.35
	bcol.shape = bshape
	ball.add_child(bcol)
	var bmesh := MeshInstance3D.new()
	var bm2 := SphereMesh.new()
	bm2.radius = 0.35
	bm2.height = 0.7
	bmesh.mesh = bm2
	bmesh.material_override = _mat(Color(0.85, 0.36, 0.31), 0.4)
	ball.add_child(bmesh)
	ball.mass = 0.4
	ball.linear_damp = 0.5
	ball.angular_damp = 0.3
	ball.position = Vector3(0, 0.6, -3)
	var pmat := PhysicsMaterial.new()
	pmat.bounce = 0.3
	ball.physics_material_override = pmat
	add_child(ball)
