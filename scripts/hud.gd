class_name HUD
extends CanvasLayer

# All UI is built in code. The whole HUD lives under `root`, which gets scaled
# by the UI Scale setting (size is compensated so anchors keep working).
# Gameplay widgets live under `game_ui`; title/howto/settings/end are overlays.

signal start_game
signal quit_to_menu

const SETTINGS_PATH := "user://settings.cfg"
const RESOLUTIONS = [Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160)]
const RESOLUTION_LABELS = ["1920 x 1080  (1080p)", "2560 x 1440  (1440p)", "3840 x 2160  (4K)"]
const DISPLAY_MODES = ["fullscreen", "borderless", "windowed"]
const DISPLAY_MODE_LABELS = ["Fullscreen", "Borderless Window", "Windowed"]

const HOWTO_TEXT := """YOU ARE LYCHEE. EAT. DRINK. POOP WITH DIGNITY.

WASD / Arrows - hop   |   Shift - zoomies   |   Space - binky
E - eat hay, drink water, squat when it is TIME
F - dramatic flop (ragdoll). Lowers suspicion. Try it on the bed.

Eating fills the POOP meter, drinking fills the BLADDER.
When one is full, get to the litter box FAST.
Poop is a quick-time event: hit the keys in the green zone. 3/3 is legendary.

SUSPICION: the human checks the pen regularly. Every mess on the floor
raises suspicion during a check (flop to halve it - the Cute Defense).
If suspicion is nearly full when the human looks, you are BUSTED:
-150 score and all your evidence gets cleaned up.
Suspicion only goes back down while the floor is clean.

THE HAY BOX RUNS OUT as everyone eats. When it gets low, hop to the gate
at the front of the pen and shake it (press E three times) to call the
human for a refill. But shake it while the box is still over half full
and the human is ANNOYED: +15 suspicion and no hay.

Run out of food entirely and GI STASIS halves your movement. Eat hay.

Nudge Potato and Gravy off the hay (+10). They will shove you right back.
Run through the tunnel (+15). Flop on the bed (+15). Live gloriously."""


# Timing bar for the poop QTE: sweeping marker, green hit zone.
class QTEBar extends Control:
	var t := 0.0
	var zone_start := 0.55
	var zone_end := 0.85

	func _draw() -> void:
		var s := size
		draw_rect(Rect2(Vector2.ZERO, s), Color(0, 0, 0, 0.55))
		draw_rect(Rect2(Vector2(zone_start * s.x, 0), Vector2((zone_end - zone_start) * s.x, s.y)), Color(0.3, 0.85, 0.3, 0.85))
		var x := clampf(t, 0.0, 1.0) * s.x
		draw_rect(Rect2(Vector2(x - 2.0, -3.0), Vector2(4.0, s.y + 6.0)), Color(1, 1, 1))

	func set_t(v: float) -> void:
		t = v
		queue_redraw()


var ui_scale := 2.0
var in_game := false
var root: Control
var game_ui: Control
var bars := {}
var objective_label: Label
var clock_label: Label
var score_label: Label
var prompt_label: Label
var message_label: Label
var urgent_label: Label
var human_label: Label
var hold_bar: ProgressBar
var qte_box: CenterContainer
var qte_key_label: Label
var qte_bar: QTEBar
var qte_progress_label: Label
var end_box: CenterContainer
var end_title: Label
var end_stats: Label
var title_box: CenterContainer
var howto_box: CenterContainer
var settings_box: CenterContainer
var display_mode_option: OptionButton
var res_option: OptionButton
var scale_slider: HSlider
var scale_value_label: Label
var quit_menu_button: Button
var scale_confirm_box: CenterContainer
var scale_confirm_label: Label
var pending_prev_scale := -1.0   # scale to revert to; -1 = no pending change
var confirm_timer := 0.0
var msg_time := 0.0
var susp_flash := 0.0
var display_mode := "fullscreen"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	game_ui = Control.new()
	game_ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(game_ui)
	_build_top_bar()
	_build_meters()
	_build_center()
	_build_bottom()
	_build_qte()
	_build_end_screen()
	_build_title()
	_build_howto()
	_build_settings()
	_build_scale_confirm()
	_load_settings()
	get_window().size_changed.connect(_apply_layout)
	_apply_layout()


func _process(delta: float) -> void:
	# Pending UI-scale change: countdown, then auto-revert (monitor-style).
	if scale_confirm_box.visible:
		confirm_timer -= delta
		scale_confirm_label.text = "UI scale %.2fx - keep these settings?\nReverting in %d..." % [ui_scale, ceili(maxf(confirm_timer, 0.0))]
		if confirm_timer <= 0.0:
			_revert_scale()
	if Input.is_action_just_pressed("menu"):
		if scale_confirm_box.visible:
			_revert_scale()
		elif in_game:
			var paused := not get_tree().paused
			get_tree().paused = paused
			quit_menu_button.visible = true
			settings_box.visible = paused
		elif settings_box.visible:
			settings_box.visible = false
			title_box.visible = true
		elif howto_box.visible:
			howto_box.visible = false
			title_box.visible = true
	msg_time -= delta
	message_label.modulate.a = clampf(msg_time / 0.6, 0.0, 1.0)
	# Suspicion bar flashes white briefly when it jumps.
	if susp_flash > 0.0:
		susp_flash = maxf(0.0, susp_flash - delta * 3.0)
		var f := susp_flash
		bars["suspicion"].modulate = Color(1.0 + f * 1.5, 1.0 + f * 1.5, 1.0 + f * 1.5)


# --- screen flow -------------------------------------------------------------

func show_title() -> void:
	in_game = false
	game_ui.visible = false
	end_box.visible = false
	settings_box.visible = false
	howto_box.visible = false
	title_box.visible = true


func show_game() -> void:
	in_game = true
	title_box.visible = false
	howto_box.visible = false
	settings_box.visible = false
	end_box.visible = false
	game_ui.visible = true


func _on_start_pressed() -> void:
	title_box.visible = false
	start_game.emit()


func _on_howto_pressed() -> void:
	title_box.visible = false
	howto_box.visible = true


func _on_howto_back_pressed() -> void:
	howto_box.visible = false
	title_box.visible = true


func _on_title_settings_pressed() -> void:
	title_box.visible = false
	quit_menu_button.visible = false
	settings_box.visible = true


func _on_settings_back_pressed() -> void:
	settings_box.visible = false
	if in_game:
		get_tree().paused = false
	else:
		title_box.visible = true


func _on_quit_to_menu_pressed() -> void:
	settings_box.visible = false
	get_tree().paused = false
	quit_to_menu.emit()


func _on_quit_game_pressed() -> void:
	get_tree().quit()


# --- public API -------------------------------------------------------------

func set_meters(hunger: float, water: float, poop: float, bladder: float, suspicion: float) -> void:
	bars["hunger"].value = hunger
	bars["water"].value = water
	bars["poop"].value = poop
	bars["bladder"].value = bladder
	bars["suspicion"].value = suspicion


func flash_suspicion() -> void:
	susp_flash = 1.0


func set_objective(text: String) -> void:
	if objective_label.text != text:
		objective_label.text = text


func set_score(score: float) -> void:
	score_label.text = "Score %d" % int(score)


func set_clock(text: String) -> void:
	if clock_label.text != text:
		clock_label.text = text


func set_prompt(text: String) -> void:
	prompt_label.text = text


func message(text: String) -> void:
	message_label.text = text
	msg_time = 2.6


func set_urgent(text: String) -> void:
	urgent_label.visible = text != ""
	if urgent_label.visible:
		urgent_label.text = text


func set_human(text: String) -> void:
	human_label.visible = text != ""
	if human_label.visible:
		human_label.text = text


func set_hold(progress: float) -> void:
	hold_bar.visible = progress >= 0.0
	if hold_bar.visible:
		hold_bar.value = clampf(progress, 0.0, 1.0) * 100.0


func show_qte(active: bool) -> void:
	qte_box.visible = active


func update_qte(key: String, t: float, hits: int, total: int) -> void:
	qte_key_label.text = "PRESS  %s" % key
	qte_bar.set_t(t)
	qte_progress_label.text = "%d / %d good pushes" % [hits, total]


func show_end(title: String, stats: String) -> void:
	end_title.text = title
	end_stats.text = stats
	end_box.visible = true


# --- settings ---------------------------------------------------------------

func _apply_layout() -> void:
	# Crisp scaling: use the window's content-scale system (canvas_items mode)
	# so fonts re-rasterize at the effective scale instead of being stretched.
	# 3D still renders at full window resolution; only the UI canvas scales.
	var w := get_window()
	w.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	w.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	w.content_scale_size = w.size
	w.content_scale_factor = ui_scale


func _on_resolution_selected(idx: int) -> void:
	_apply_resolution(RESOLUTIONS[idx])
	_save_settings()


func _on_display_mode_selected(idx: int) -> void:
	display_mode = DISPLAY_MODES[idx]
	_apply_display_mode()
	_save_settings()


func _apply_resolution(res: Vector2i) -> void:
	var w := get_window()
	if w.mode == Window.MODE_WINDOWED:
		w.size = res
		var scr := w.current_screen
		var spos := DisplayServer.screen_get_position(scr)
		var ssize := DisplayServer.screen_get_size(scr)
		w.position = spos + (ssize - w.size) / 2
	var idx := RESOLUTIONS.find(Vector2i(res))
	if idx >= 0:
		res_option.select(idx)
	_apply_layout()


func _apply_display_mode() -> void:
	var w := get_window()
	var mode_idx := DISPLAY_MODES.find(display_mode)
	if mode_idx < 0:
		mode_idx = 0
	display_mode_option.select(mode_idx)

	match display_mode:
		"fullscreen":
			w.borderless = false
			w.mode = Window.MODE_FULLSCREEN
		"borderless":
			w.mode = Window.MODE_WINDOWED
			w.borderless = true
			var scr := w.current_screen
			w.position = DisplayServer.screen_get_position(scr)
			w.size = DisplayServer.screen_get_size(scr)
		_:
			w.mode = Window.MODE_WINDOWED
			w.borderless = false
			var res_idx := res_option.selected if res_option.selected >= 0 else 0
			_apply_resolution(RESOLUTIONS[res_idx])
	_apply_layout()


func _on_ui_scale_changed(value: float) -> void:
	# Moving the slider only previews the number; nothing changes until Apply.
	scale_value_label.text = "%.2fx" % value


func _on_apply_scale_pressed() -> void:
	var value: float = scale_slider.value
	if absf(value - ui_scale) < 0.01:
		return
	pending_prev_scale = ui_scale
	ui_scale = value
	_apply_layout()
	confirm_timer = 8.0
	scale_confirm_box.visible = true


func _confirm_scale() -> void:
	pending_prev_scale = -1.0
	scale_confirm_box.visible = false
	_save_settings()


func _revert_scale() -> void:
	if pending_prev_scale >= 0.0:
		ui_scale = pending_prev_scale
		pending_prev_scale = -1.0
		scale_slider.set_value_no_signal(ui_scale)
		scale_value_label.text = "%.2fx" % ui_scale
		_apply_layout()
	scale_confirm_box.visible = false


func _load_settings() -> void:
	var res := Vector2i(1920, 1080)
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) == OK:
		ui_scale = clampf(cf.get_value("display", "ui_scale", 2.0), 1.0, 3.0)
		res = cf.get_value("display", "resolution", res)
		display_mode = cf.get_value("display", "display_mode", display_mode)
	scale_slider.set_value_no_signal(ui_scale)
	scale_value_label.text = "%.2fx" % ui_scale
	_apply_resolution(res)
	_apply_display_mode()


func _save_settings() -> void:
	var cf := ConfigFile.new()
	cf.set_value("display", "ui_scale", ui_scale)
	cf.set_value("display", "resolution", Vector2i(get_window().size))
	cf.set_value("display", "display_mode", display_mode)
	cf.save(SETTINGS_PATH)


# --- builders ---------------------------------------------------------------

func _label(text: String, font_size: int, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.1, 0.08, 0.06, 0.9))
	l.add_theme_constant_override("outline_size", 6)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(280, 46)
	b.focus_mode = Control.FOCUS_NONE  # Space is for binkies, not buttons
	b.add_theme_font_size_override("font_size", 20)
	return b


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _stylebox(color: Color, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(radius)
	return sb


func _panel_box() -> Array:
	# Returns [CenterContainer, VBoxContainer] - a centered dark panel.
	var box := CenterContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.visible = false
	root.add_child(box)
	var panel := PanelContainer.new()
	var sb := _stylebox(Color(0.12, 0.09, 0.07, 0.92), 16)
	sb.set_content_margin_all(28)
	panel.add_theme_stylebox_override("panel", sb)
	box.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)
	return [box, vb]


func _build_top_bar() -> void:
	var bar := MarginContainer.new()
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	bar.add_theme_constant_override("margin_left", 16)
	bar.add_theme_constant_override("margin_right", 16)
	bar.add_theme_constant_override("margin_top", 12)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game_ui.add_child(bar)
	var hb := HBoxContainer.new()
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(hb)
	clock_label = _label("Morning", 18)
	clock_label.custom_minimum_size = Vector2(160, 0)
	hb.add_child(clock_label)
	objective_label = _label("", 24, Color(1.0, 0.95, 0.7))
	objective_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	objective_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hb.add_child(objective_label)
	score_label = _label("Score 0", 18)
	score_label.custom_minimum_size = Vector2(160, 0)
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hb.add_child(score_label)


func _build_meters() -> void:
	var panel := PanelContainer.new()
	panel.position = Vector2(16, 56)
	var sb := _stylebox(Color(0.08, 0.06, 0.05, 0.4), 10)
	sb.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game_ui.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	panel.add_child(vb)
	var defs = [
		["hunger", "HUNGER", Color(0.95, 0.6, 0.25)],
		["water", "WATER", Color(0.35, 0.65, 0.95)],
		["poop", "POOP", Color(0.55, 0.4, 0.28)],
		["bladder", "BLADDER", Color(0.93, 0.85, 0.3)],
		["suspicion", "SUSPICION", Color(0.85, 0.3, 0.3)],
	]
	for d in defs:
		var hb := HBoxContainer.new()
		var lab := _label(d[1], 13)
		lab.custom_minimum_size = Vector2(92, 0)
		hb.add_child(lab)
		var pbar := ProgressBar.new()
		pbar.custom_minimum_size = Vector2(170, 16)
		pbar.max_value = 100.0
		pbar.show_percentage = false
		pbar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		pbar.add_theme_stylebox_override("background", _stylebox(Color(0, 0, 0, 0.45), 7))
		pbar.add_theme_stylebox_override("fill", _stylebox(d[2], 7))
		pbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(pbar)
		vb.add_child(hb)
		bars[d[0]] = pbar


func _build_center() -> void:
	urgent_label = _label("", 38, Color(1.0, 0.45, 0.3))
	urgent_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	urgent_label.offset_top = 80
	urgent_label.offset_bottom = 140
	urgent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	urgent_label.visible = false
	game_ui.add_child(urgent_label)

	human_label = _label("", 24, Color(1.0, 0.55, 0.55))
	human_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	human_label.offset_top = 142
	human_label.offset_bottom = 184
	human_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	human_label.visible = false
	game_ui.add_child(human_label)

	message_label = _label("", 26, Color(1.0, 0.92, 0.65))
	message_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	message_label.offset_top = 190
	message_label.offset_bottom = 240
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.modulate.a = 0.0
	game_ui.add_child(message_label)


func _build_bottom() -> void:
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	box.offset_top = -120
	box.offset_bottom = -16
	box.add_theme_constant_override("separation", 8)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game_ui.add_child(box)

	hold_bar = ProgressBar.new()
	hold_bar.custom_minimum_size = Vector2(240, 14)
	hold_bar.max_value = 100.0
	hold_bar.show_percentage = false
	hold_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	hold_bar.add_theme_stylebox_override("background", _stylebox(Color(0, 0, 0, 0.5), 7))
	hold_bar.add_theme_stylebox_override("fill", _stylebox(Color(0.93, 0.85, 0.3), 7))
	hold_bar.visible = false
	hold_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(hold_bar)

	prompt_label = _label("", 22, Color(0.75, 1.0, 0.75))
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(prompt_label)
	var controls := _label("WASD hop  |  Shift zoomies  |  Space binky  |  E eat / drink / squat  |  F flop  |  Esc menu", 14, Color(1, 1, 1, 0.75))
	controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(controls)


func _build_qte() -> void:
	qte_box = CenterContainer.new()
	qte_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	qte_box.visible = false
	qte_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game_ui.add_child(qte_box)
	var panel := PanelContainer.new()
	var sb := _stylebox(Color(0.12, 0.09, 0.07, 0.9), 16)
	sb.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", sb)
	qte_box.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)
	var header := _label("POOP IN PROGRESS", 16, Color(1, 1, 1, 0.7))
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(header)
	qte_key_label = _label("PRESS  W", 48, Color(1.0, 0.85, 0.4))
	qte_key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(qte_key_label)
	qte_bar = QTEBar.new()
	qte_bar.custom_minimum_size = Vector2(340, 22)
	qte_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(qte_bar)
	qte_progress_label = _label("0 / 3 good pushes", 16)
	qte_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(qte_progress_label)
	var tip := _label("Hit the key while the marker is in the green zone!", 14, Color(1, 1, 1, 0.6))
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(tip)


func _build_end_screen() -> void:
	var parts := _panel_box()
	end_box = parts[0]
	var vb: VBoxContainer = parts[1]
	var day_done := _label("DAY COMPLETE", 18, Color(1, 1, 1, 0.7))
	day_done.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(day_done)
	end_title = _label("Supreme Loaf", 36, Color(1.0, 0.85, 0.4))
	end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(end_title)
	end_stats = _label("", 18)
	end_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(end_stats)
	var hint := _label("Press R to return to the title screen", 16, Color(0.75, 1.0, 0.75))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(hint)


func _build_title() -> void:
	var parts := _panel_box()
	title_box = parts[0]
	var vb: VBoxContainer = parts[1]
	var title := _label("LYCHEE THE HUNGRY BUNNY", 44, Color(1.0, 0.85, 0.4))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var sub := _label("A Very Serious Rabbit Simulator", 18, Color(1, 1, 1, 0.8))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(sub)
	vb.add_child(_spacer(12))
	var start := _button("Start Game")
	start.pressed.connect(_on_start_pressed)
	vb.add_child(start)
	var howto := _button("How to Play")
	howto.pressed.connect(_on_howto_pressed)
	vb.add_child(howto)
	var settings := _button("Settings")
	settings.pressed.connect(_on_title_settings_pressed)
	vb.add_child(settings)
	var quit := _button("Quit")
	quit.pressed.connect(_on_quit_game_pressed)
	vb.add_child(quit)


func _build_howto() -> void:
	var parts := _panel_box()
	howto_box = parts[0]
	var vb: VBoxContainer = parts[1]
	var title := _label("HOW TO PLAY", 30, Color(1.0, 0.85, 0.4))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)
	var body := _label(HOWTO_TEXT, 16)
	vb.add_child(body)
	vb.add_child(_spacer(8))
	var back := _button("Back")
	back.pressed.connect(_on_howto_back_pressed)
	vb.add_child(back)


func _build_settings() -> void:
	var parts := _panel_box()
	settings_box = parts[0]
	var vb: VBoxContainer = parts[1]
	var title := _label("SETTINGS", 28, Color(1.0, 0.85, 0.4))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(title)

	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 12)
	vb.add_child(mode_row)
	var mode_lab := _label("Display", 18)
	mode_lab.custom_minimum_size = Vector2(130, 0)
	mode_row.add_child(mode_lab)
	display_mode_option = OptionButton.new()
	for txt in DISPLAY_MODE_LABELS:
		display_mode_option.add_item(txt)
	display_mode_option.custom_minimum_size = Vector2(230, 0)
	display_mode_option.focus_mode = Control.FOCUS_NONE
	display_mode_option.item_selected.connect(_on_display_mode_selected)
	mode_row.add_child(display_mode_option)

	var res_row := HBoxContainer.new()
	res_row.add_theme_constant_override("separation", 12)
	vb.add_child(res_row)
	var res_lab := _label("Resolution", 18)
	res_lab.custom_minimum_size = Vector2(130, 0)
	res_row.add_child(res_lab)
	res_option = OptionButton.new()
	for txt in RESOLUTION_LABELS:
		res_option.add_item(txt)
	res_option.custom_minimum_size = Vector2(230, 0)
	res_option.focus_mode = Control.FOCUS_NONE
	res_option.item_selected.connect(_on_resolution_selected)
	res_row.add_child(res_option)

	var scale_row := HBoxContainer.new()
	scale_row.add_theme_constant_override("separation", 12)
	vb.add_child(scale_row)
	var scale_lab := _label("UI Scale", 18)
	scale_lab.custom_minimum_size = Vector2(130, 0)
	scale_row.add_child(scale_lab)
	scale_slider = HSlider.new()
	scale_slider.min_value = 1.0
	scale_slider.max_value = 3.0
	scale_slider.step = 0.25
	scale_slider.value = 2.0
	scale_slider.custom_minimum_size = Vector2(180, 0)
	scale_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	scale_slider.focus_mode = Control.FOCUS_NONE
	scale_slider.value_changed.connect(_on_ui_scale_changed)
	scale_row.add_child(scale_slider)
	scale_value_label = _label("2.00x", 18)
	scale_value_label.custom_minimum_size = Vector2(56, 0)
	scale_row.add_child(scale_value_label)
	var apply := _button("Apply")
	apply.custom_minimum_size = Vector2(100, 40)
	apply.pressed.connect(_on_apply_scale_pressed)
	scale_row.add_child(apply)

	vb.add_child(_spacer(6))
	var back := _button("Back")
	back.pressed.connect(_on_settings_back_pressed)
	vb.add_child(back)
	quit_menu_button = _button("Quit to Menu")
	quit_menu_button.pressed.connect(_on_quit_to_menu_pressed)
	vb.add_child(quit_menu_button)
	var quit := _button("Quit Game")
	quit.pressed.connect(_on_quit_game_pressed)
	vb.add_child(quit)


func _build_scale_confirm() -> void:
	var parts := _panel_box()
	scale_confirm_box = parts[0]
	var vb: VBoxContainer = parts[1]
	scale_confirm_label = _label("", 20)
	scale_confirm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(scale_confirm_label)
	var keep := _button("Keep  (Confirm)")
	keep.pressed.connect(_confirm_scale)
	vb.add_child(keep)
	var revert := _button("Revert  (Esc)")
	revert.pressed.connect(_revert_scale)
	vb.add_child(revert)
