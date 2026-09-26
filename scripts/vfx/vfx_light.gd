class_name VfxLight
extends OmniLight3D
## Shadowless omni light for effects (fireballs, explosions, meteors). Counts against
## VfxUtil.MAX_VFX_LIGHTS (take the slot with VfxUtil.take_light() before creating one: the
## VfxUtil.flash_light / steady_light helpers do). A duration > 0 fades it out and frees it.
## OWNER: skills (wave 2).

var duration := 0.0
var base_energy := 1.0
var _age := 0.0
var _released := false


func setup(color: Color, energy: float, light_range: float, p_duration: float) -> void:
	light_color = color
	base_energy = energy
	light_energy = energy
	omni_range = light_range
	omni_attenuation = 1.4
	shadow_enabled = false
	light_specular = 0.2
	duration = p_duration


func _process(delta: float) -> void:
	if duration <= 0.0:
		return
	_age += delta
	var t := clampf(_age / duration, 0.0, 1.0)
	light_energy = base_energy * (1.0 - t) * (1.0 - t)
	if _age >= duration:
		queue_free()


## Fade out over `time` seconds and free (for steady lights whose owner is ending).
func fade_out(time: float) -> void:
	base_energy = light_energy
	duration = maxf(0.01, time)
	_age = 0.0


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and not _released:
		_released = true
		VfxUtil.release_light()
