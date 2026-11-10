extends CanvasLayer
## ScreenFX (autoload): persistent CRT post-process, glitch pulses and scene fades.
## Honors the accessibility settings (distortion / flicker / noise).

var _rect: ColorRect
var _fade: ColorRect
var _mat: ShaderMaterial
var _glitch_tween: Tween
var _fade_tween: Tween


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_fade = ColorRect.new()
	_fade.color = Color(0.035, 0.051, 0.043, 0.0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_fade)
	_rect = ColorRect.new()
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://assets/shaders/crt.gdshader") as Shader
	_rect.material = _mat
	add_child(_rect)
	apply_settings()


func apply_settings() -> void:
	var s: Dictionary = SaveManager.settings
	_mat.set_shader_parameter("distortion", 1.0 if bool(s.get("screen_distortion", true)) else 0.0)
	_mat.set_shader_parameter("noise_amt", 1.0 if bool(s.get("visual_noise", true)) else 0.0)
	_mat.set_shader_parameter("flicker_amt", 1.0 if bool(s.get("flicker", true)) else 0.0)
	_mat.set_shader_parameter("scanline_amt", 1.0 if bool(s.get("visual_noise", true)) else 0.35)


## Baseline unease, 0..1. Rises with the in-game day.
func set_corruption(level: float) -> void:
	_mat.set_shader_parameter("corruption", clampf(level, 0.0, 1.0))


## A short horizontal-tear pulse. Not a flash: brightness is unchanged.
func pulse(strength: float = 0.6, duration: float = 0.5) -> void:
	if not bool(SaveManager.settings.get("screen_distortion", true)):
		return
	if _glitch_tween != null and _glitch_tween.is_valid():
		_glitch_tween.kill()
	_mat.set_shader_parameter("glitch", clampf(strength, 0.0, 1.0))
	_glitch_tween = create_tween()
	_glitch_tween.tween_method(_set_glitch, clampf(strength, 0.0, 1.0), 0.0, maxf(duration, 0.05))


func _set_glitch(v: float) -> void:
	_mat.set_shader_parameter("glitch", v)


func fade_out(duration: float = 0.4) -> void:
	await _fade_to(1.0, duration)


func fade_in(duration: float = 0.5) -> void:
	await _fade_to(0.0, duration)


func _fade_to(alpha: float, duration: float) -> void:
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(_fade, "color:a", alpha, duration)
	await _fade_tween.finished
