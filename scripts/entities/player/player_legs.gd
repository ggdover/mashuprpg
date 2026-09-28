extends SkeletonModifier3D
## Leg layer of the player model: poses the leg bones from the directional walk clips — walk
## (forward), walk_right, walk_back, walk_left — blended by the direction of movement relative to
## the facing, all at one shared cycle phase, on top of whatever the AnimationPlayer set this frame
## (an attack, a cast, the parry guard), blended in by `influence`. So the player walks, backs off
## or side-steps while using a skill. Child of the model's Skeleton3D; PlayerVisuals drives phase,
## direction, influence and active. Every clip starts with the right foot's touchdown, so blending
## two neighbours at the same phase keeps the feet in step.
## Internal helper: `const PlayerLegs := preload("res://scripts/entities/player/player_legs.gd")`.
## OWNER: player.

## The legs, toes and the hem panels that follow the thighs (missing bones are skipped).
const LEG_BONES: Array[String] = ["upper_leg_l", "lower_leg_l", "foot_l", "toe_l", "upper_leg_r", "lower_leg_r", "foot_r", "toe_r",
	"skirt_f", "skirt_b", "skirt_l", "skirt_r"]
## Clip name and direction (radians from the facing: 0 forward, +PI/2 right, PI back, -PI/2 left).
const CLIPS := [["walk", 0.0], ["walk_right", PI * 0.5], ["walk_back", PI], ["walk_left", -PI * 0.5]]
## Planted-foot speed of every walk clip (m/s), see cc_anim.WALK_SPEED.
const WALK_SPEED := 1.82

## Cycle phase, 0..1 (wraps around).
var phase := 0.0
## Movement direction relative to the facing (radians, see CLIPS).
var direction := 0.0

## Per available clip: {"name", "angle", "anim": Animation, "tracks": PackedInt32Array (track index
## per LEG_BONES entry, -1 = none)}. Always starts with the forward walk when there is one.
var _clips: Array = []
var _bones := PackedInt32Array()


## Use the walk clips of `player` for the legs of `skeleton`. False without a forward walk.
func setup(player: AnimationPlayer, skeleton: Skeleton3D) -> bool:
	_clips.clear()
	_bones.clear()
	if player == null or skeleton == null or not player.has_animation("walk"):
		return false
	for b in LEG_BONES:
		_bones.append(skeleton.find_bone(b))
	for c in CLIPS:
		var name_: String = c[0]
		if not player.has_animation(name_):
			continue
		var anim := player.get_animation(name_)
		var tracks := PackedInt32Array()
		for b in LEG_BONES:
			tracks.append(-1)
		for i in anim.get_track_count():
			if anim.track_get_type(i) != Animation.TYPE_ROTATION_3D:
				continue
			var bi := LEG_BONES.find(String(anim.track_get_path(i).get_concatenated_subnames()))
			if bi >= 0:
				tracks[bi] = i
		_clips.append({"name": name_, "angle": float(c[1]), "anim": anim, "tracks": tracks})
	return has_tracks()


func has_tracks() -> bool:
	if _clips.is_empty():
		return false
	for t in (_clips[0]["tracks"] as PackedInt32Array):
		if t >= 0:
			return true
	return false


## The two clips around `angle` and the weight of the second: [clip a, clip b, weight of b].
func blend_for(angle: float) -> Array:
	if _clips.size() == 1:
		return [_clips[0], _clips[0], 0.0]
	var best_a: Dictionary = _clips[0]
	var best_b: Dictionary = _clips[0]
	var da := INF
	var db := INF
	# the nearest clip on each side of the angle
	for c in _clips:
		var d := wrapf(angle - float(c["angle"]), -PI, PI)
		if d >= 0.0 and d < da:
			da = d
			best_a = c
		if d <= 0.0 and -d < db:
			db = -d
			best_b = c
	if best_a == best_b or da + db <= 0.0001:
		return [best_a, best_a, 0.0]
	return [best_a, best_b, da / (da + db)]


## The clip with the most weight at the current direction (tests / debugging).
func dominant_clip() -> String:
	var b := blend_for(direction)
	return String((b[1] if float(b[2]) > 0.5 else b[0])["name"]) if not _clips.is_empty() else ""


## Metres the character travels in one cycle at the current direction (the blend of the clips'
## cycles, each planted foot moving at WALK_SPEED): phase advances by distance / this.
func cycle_distance() -> float:
	if _clips.is_empty():
		return 1.0
	var b := blend_for(direction)
	var la := ((b[0] as Dictionary)["anim"] as Animation).length
	var lb := ((b[1] as Dictionary)["anim"] as Animation).length
	return maxf(0.05, WALK_SPEED * lerpf(la, lb, float(b[2])))


func _process_modification_with_delta(_delta: float) -> void:
	var sk := get_skeleton()
	if sk == null or _clips.is_empty():
		return
	var b := blend_for(direction)
	var ca: Dictionary = b[0]
	var cb: Dictionary = b[1]
	var w := float(b[2])
	var aa: Animation = ca["anim"]
	var ab: Animation = cb["anim"]
	var ta := fposmod(phase, 1.0) * aa.length
	var tb := fposmod(phase, 1.0) * ab.length
	var tra: PackedInt32Array = ca["tracks"]
	var trb: PackedInt32Array = cb["tracks"]
	for i in _bones.size():
		var bone := _bones[i]
		if bone < 0 or tra[i] < 0:
			continue
		var q := aa.rotation_track_interpolate(tra[i], ta)
		if w > 0.001 and trb[i] >= 0:
			q = q.slerp(ab.rotation_track_interpolate(trb[i], tb), w)
		sk.set_bone_pose_rotation(bone, q)
