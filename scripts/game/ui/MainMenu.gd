## MainScene.gd
## ─────────────────────────────────────────────────────────────────────────────
## Sci-fi nebula screensaver / loading screen.
## Attach to a plain Node root in MainScene.tscn — builds everything in code.
##
## Project setup:
##   1. Create MainScene.tscn with a plain Node root, attach this script.
##   2. Project Settings → Run → Main Scene → res://Scenes/MainScene.tscn
##   3. GameManager.cs line ~76: MainLobbyScenePath = "res://Scenes/MainScene.tscn"
## ─────────────────────────────────────────────────────────────────────────────
extends Node

# ─── Colours ──────────────────────────────────────────────────────────────────
const C_CYAN   := Color(0.00, 0.898, 0.784, 1.0)
const C_PURPLE := Color(0.45, 0.18,  0.90,  1.0)
const C_DARK   := Color(0.04, 0.05,  0.10,  1.0)
const C_MUTED  := Color(0.50, 0.55,  0.65,  1.0)
const C_RED    := Color(0.90, 0.25,  0.25,  1.0)

# ─── Nebula GLSL shader ───────────────────────────────────────────────────────
const NEBULA_SHADER := """
shader_type canvas_item;

uniform float u_time : hint_range(0.0, 3000.0) = 0.0;

vec2 hash2(vec2 p) {
    p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
    return -1.0 + 2.0 * fract(sin(p) * 43758.5453123);
}

float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return mix(
        mix(dot(hash2(i + vec2(0,0)), f - vec2(0,0)),
            dot(hash2(i + vec2(1,0)), f - vec2(1,0)), u.x),
        mix(dot(hash2(i + vec2(0,1)), f - vec2(0,1)),
            dot(hash2(i + vec2(1,1)), f - vec2(1,1)), u.x), u.y);
}

float fbm(vec2 p) {
    float v = 0.0;
    float a = 0.5;
    for (int i = 0; i < 6; i++) {
        v += a * noise(p);
        p  = p * 2.1 + vec2(1.7, 9.2);
        a *= 0.5;
    }
    return v;
}

void fragment() {
    float t  = u_time;
    vec2  uv = UV - 0.5;
    uv.x    *= (1.0 / TEXTURE_PIXEL_SIZE.y) * TEXTURE_PIXEL_SIZE.x;

    // Slow rotation
    float ang = t * 0.014;
    vec2 ruv = vec2(
        uv.x * cos(ang) - uv.y * sin(ang),
        uv.x * sin(ang) + uv.y * cos(ang)
    );

    // Multi-octave clouds
    float n1 = fbm(ruv * 2.1 + vec2(t * 0.035, t * 0.020));
    float n2 = fbm(ruv * 3.4 - vec2(t * 0.025, t * 0.012) + n1 * 0.5);
    float n3 = fbm(ruv * 1.3 + vec2(n2 * 0.7,  t * 0.008));

    // Base deep-space colour
    vec3 col = mix(vec3(0.03, 0.04, 0.09), vec3(0.07, 0.03, 0.14), n3 * 0.6 + 0.4);

    // Cyan cloud
    float c1 = smoothstep(0.02, 0.65, n1 * 0.5 + 0.5);
    col = mix(col, vec3(0.00, 0.52, 0.52), c1 * 0.55);

    // Purple cloud
    float c2 = smoothstep(0.12, 0.72, n2 * 0.5 + 0.5);
    col = mix(col, vec3(0.28, 0.04, 0.52), c2 * 0.42);

    // Central glow
    float dist = length(uv);
    float glow = exp(-dist * 3.2) * (0.65 + 0.35 * sin(t * 0.45 + 1.0));
    col += vec3(0.03, 0.18, 0.25) * glow;

    // Vignette
    col *= 1.0 - smoothstep(0.30, 0.85, length(uv * vec2(0.95, 1.05)));

    // Subtle scanline flicker
    col *= 0.96 + 0.04 * sin(UV.y * 720.0 + t * 1.8);

    COLOR = vec4(col, 1.0);
}
"""

# ─── Node references ──────────────────────────────────────────────────────────
var _nebula_mat  : ShaderMaterial
var _status_lbl  : Label
var _sub_lbl     : Label
var _dot_lbl     : Label
var _err_panel   : PanelContainer
var _err_lbl     : Label
var _retry_btn   : Button

# ─── Runtime state ────────────────────────────────────────────────────────────
var _shader_t  : float  = 0.0
var _dot_t     : float  = 0.0
var _last_ip   : String = ""
var _last_port : int    = 0
var _gm        : Node   = null


func _ready() -> void:
	_build_ui()

	_gm = get_node_or_null("/root/GameManager")
	if _gm == null:
		_set_status("ERROR", "GameManager autoload not found.", true)
		return

	if _gm.has_signal("ConnectionFailed"):
		_gm.ConnectionFailed.connect(_on_connection_failed)
	if _gm.has_signal("GameStateChanged"):
		_gm.GameStateChanged.connect(_on_game_state_changed)

	_parse_args()


func _process(delta: float) -> void:
	_shader_t += delta
	if _nebula_mat:
		_nebula_mat.set_shader_parameter("u_time", _shader_t)

	# Animate loading dots
	if _dot_lbl and _dot_lbl.visible:
		_dot_t += delta * 1.6
		if _dot_t >= PI * 2.0:
			_dot_t -= PI * 2.0
		var n := int((_dot_t / (PI * 2.0)) * 4.0) % 4
		_dot_lbl.text = ".".repeat(n + 1)


# ─────────────────────────────────────────────────────────────────────────────
# UI construction
# ─────────────────────────────────────────────────────────────────────────────
func _build_ui() -> void:
	var vp_size := get_viewport().get_visible_rect().size

	# ── Nebula background ColorRect ──────────────────────────────────────────
	var bg := ColorRect.new()
	bg.name = "NebulaBackground"
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sh        := Shader.new()
	sh.code        = NEBULA_SHADER
	_nebula_mat    = ShaderMaterial.new()
	_nebula_mat.shader = sh
	bg.material    = _nebula_mat
	add_child(bg)

	# ── Star particle layers ─────────────────────────────────────────────────
	_make_stars(vp_size, 150, 0.8,  1.5,  Color(1.0,  1.0,  1.0,  0.35))   # distant
	_make_stars(vp_size,  70, 1.4,  2.5,  Color(0.80, 0.90, 1.00, 0.65))   # mid
	_make_stars(vp_size,  25, 2.2,  4.0,  C_CYAN * Color(1, 1, 1, 0.85))   # foreground cyan

	# ── Canvas layer for HUD ─────────────────────────────────────────────────
	var canvas := CanvasLayer.new()
	add_child(canvas)

	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(root)

	# Corner brackets
	_corner(root, Vector2(28,  28),  Vector2(55, 2),  false)
	_corner(root, Vector2(28,  28),  Vector2(2, 55),  false)
	_corner(root, Vector2(-83, 28),  Vector2(55, 2),  true)
	_corner(root, Vector2(-30, 28),  Vector2(2, 55),  true)
	_corner(root, Vector2(28, -83),  Vector2(55, 2),  false, true)
	_corner(root, Vector2(28, -83),  Vector2(2, 55),  false, true)
	_corner(root, Vector2(-83, -83), Vector2(55, 2),  true,  true)
	_corner(root, Vector2(-30, -83), Vector2(2, 55),  true,  true)

	# Game logo
	var logo := _label("GS  NEBULA", 56, C_CYAN, HORIZONTAL_ALIGNMENT_CENTER)
	logo.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	logo.position = Vector2(-450, 80)
	logo.size     = Vector2(900, 72)
	root.add_child(logo)

	# Separator
	var sep := ColorRect.new()
	sep.color = C_CYAN * Color(1, 1, 1, 0.30)
	sep.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	sep.size     = Vector2(540, 1)
	sep.position = Vector2(-270, 162)
	root.add_child(sep)

	# Subtitle
	var sub := _label("NETWORK INTERFACE  //  GODOTSTATION", 11, C_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	sub.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	sub.position = Vector2(-300, 170)
	sub.size     = Vector2(600, 22)
	root.add_child(sub)

	# ── Centre status area ───────────────────────────────────────────────────
	_status_lbl = _label("INITIALISING", 22, C_CYAN, HORIZONTAL_ALIGNMENT_CENTER)
	_status_lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_status_lbl.size     = Vector2(700, 38)
	_status_lbl.position = Vector2(-350, -58)
	root.add_child(_status_lbl)

	_dot_lbl = _label("...", 22, C_CYAN, HORIZONTAL_ALIGNMENT_LEFT)
	_dot_lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_dot_lbl.size     = Vector2(60, 38)
	_dot_lbl.position = Vector2(-30, -19)
	root.add_child(_dot_lbl)

	_sub_lbl = _label("", 13, C_MUTED, HORIZONTAL_ALIGNMENT_CENTER)
	_sub_lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_sub_lbl.size          = Vector2(620, 60)
	_sub_lbl.position      = Vector2(-310, 8)
	_sub_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(_sub_lbl)

	# ── Error panel ──────────────────────────────────────────────────────────
	_err_panel = PanelContainer.new()
	_err_panel.visible = false
	_err_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_err_panel.size     = Vector2(520, 150)
	_err_panel.position = Vector2(-260, 56)

	var sbox := StyleBoxFlat.new()
	sbox.bg_color = Color(0.10, 0.02, 0.05, 0.94)
	sbox.border_color = C_RED * Color(1, 1, 1, 0.85)
	sbox.set_border_width_all(1)
	sbox.set_corner_radius_all(4)
	_err_panel.add_theme_stylebox_override("panel", sbox)
	root.add_child(_err_panel)

	var ev := VBoxContainer.new()
	ev.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ev.alignment = BoxContainer.ALIGNMENT_CENTER
	ev.add_theme_constant_override("separation", 12)
	_err_panel.add_child(ev)

	_err_lbl = _label("Connection failed.", 14, C_RED, HORIZONTAL_ALIGNMENT_CENTER)
	_err_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ev.add_child(_err_lbl)

	_retry_btn = Button.new()
	_retry_btn.text = "RETRY CONNECTION"
	_retry_btn.custom_minimum_size = Vector2(200, 36)
	_retry_btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_retry_btn.pressed.connect(_on_retry_pressed)
	ev.add_child(_retry_btn)

	# Version watermark
	var ver := _label("GS-NEBULA", 10, C_MUTED * Color(1, 1, 1, 0.4), HORIZONTAL_ALIGNMENT_RIGHT)
	ver.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	ver.position = Vector2(-130, -28)
	ver.size     = Vector2(110, 18)
	root.add_child(ver)


# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────
func _label(text: String, size: int, col: Color, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.horizontal_alignment = align
	return l


func _corner(parent: Control, pos: Vector2, sz: Vector2,
			 flip_x: bool = false, flip_y: bool = false) -> void:
	var r := ColorRect.new()
	r.color = C_CYAN * Color(1, 1, 1, 0.55)
	r.size  = sz
	var anchor := Control.PRESET_TOP_LEFT
	if flip_x and flip_y: anchor = Control.PRESET_BOTTOM_RIGHT
	elif flip_x:           anchor = Control.PRESET_TOP_RIGHT
	elif flip_y:           anchor = Control.PRESET_BOTTOM_LEFT
	r.set_anchors_preset(anchor)
	r.position = pos
	parent.add_child(r)


func _make_stars(vp_size: Vector2, count: int,
				 sz_min: float, sz_max: float, col: Color) -> void:
	var p := CPUParticles2D.new()
	p.emitting              = true
	p.amount                = count
	p.lifetime              = 6.0 + randf() * 4.0
	p.one_shot              = false
	p.explosiveness         = 0.0
	p.randomness            = 1.0
	p.emission_shape        = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = vp_size * 0.5
	p.position              = vp_size * 0.5
	p.gravity               = Vector2.ZERO
	p.direction             = Vector2.ZERO
	p.spread                = 180.0
	p.initial_velocity_min  = 0.0
	p.initial_velocity_max  = 1.2
	p.scale_amount_min      = sz_min
	p.scale_amount_max      = sz_max
	p.color                 = col

	var cv := Curve.new()
	cv.add_point(Vector2(0.0, 0.1))
	cv.add_point(Vector2(0.2, 1.0))
	cv.add_point(Vector2(0.8, 0.7))
	cv.add_point(Vector2(1.0, 0.0))
	p.scale_amount_curve = cv

	add_child(p)


# ─────────────────────────────────────────────────────────────────────────────
# Logic
# ─────────────────────────────────────────────────────────────────────────────
func _parse_args() -> void:
	var args      := OS.get_cmdline_args()
	var join_ip   := ""
	var join_port := 0
	var is_host   := false

	for i in range(args.size()):
		match args[i]:
			"--join-server":
				if i + 1 < args.size():
					var parts := args[i + 1].split(":")
					join_ip = parts[0]
					if parts.size() > 1:
						join_port = int(parts[1])
			"--host":
				is_host = true

	_last_ip   = join_ip
	_last_port = join_port

	if join_ip != "":
		_set_status("CONNECTING", "→  %s : %d" % [join_ip, join_port])
	elif is_host:
		_set_status("STARTING SERVER", "Initialising listen server…")
	else:
		_set_status("AWAITING SIGNAL",
			"Launch via GS-Nebula hub, or pass  --join-server <ip>:<port>  --auth-token <token>")


func _set_status(main: String, sub: String = "", is_error: bool = false) -> void:
	if _status_lbl:
		_status_lbl.text = main
		_status_lbl.add_theme_color_override("font_color", C_RED if is_error else C_CYAN)
	if _sub_lbl:
		_sub_lbl.text = sub
	if _dot_lbl:
		_dot_lbl.visible = not is_error


func _on_connection_failed() -> void:
	_set_status("CONNECTION FAILED", "", true)
	if _err_lbl:
		var detail := ("Could not reach  %s : %d" % [_last_ip, _last_port]) if _last_ip != "" \
					  else "Could not start listen server."
		_err_lbl.text = detail + "\nCheck IP, port, and that the server is running."
	if _err_panel:
		_err_panel.visible = true
	if _retry_btn:
		_retry_btn.visible = _last_ip != ""


func _on_game_state_changed(state_int: int) -> void:
	# GameState: 0=Menu  1=Lobby  2=Playing  3=Hosting
	match state_int:
		1: _set_status("ENTERING LOBBY",  "Connection established.")
		3: _set_status("HOSTING",         "Listen server active.")


func _on_retry_pressed() -> void:
	if _last_ip == "":
		return
	if _err_panel:
		_err_panel.visible = false
	_set_status("RECONNECTING", "→  %s : %d" % [_last_ip, _last_port])
	if _gm and _gm.has_method("JoinGame"):
		_gm.call("JoinGame", _last_ip, _last_port)
