class_name DayCycle

## Time-of-day lighting, driven by the day clock (LOOP-07). One in-game day
## is one full sun cycle: the phase the clock is at picks the sun's angle,
## the sunlight's colour and strength, and the sky/ambient tint, so a day
## visibly runs dawn -> morning -> midday -> afternoon -> sunset -> dusk ->
## night -> dawn while the player builds.
##
## Phase is 0 at the start of a day and 1 at the moment it rolls over. The
## first and last keyframes are deliberately identical, so the cycle is
## continuous across that rollover rather than snapping: night falls in the
## last stretch of a day and the sun comes back up exactly as the clock hits
## 0:00. That also means "Day N" always opens at dawn.
##
## Kept free of any node references so it can be sampled and asserted
## directly in the dev checks; Main just feeds it a phase and applies the
## result (see apply()).

## Keyframes in phase order. `pitch` is the sun's rotation about X in
## degrees (shallower = lower in the sky); `light`/`energy` are the
## directional light's colour and strength; `sky` is the background colour;
## `ambient`/`ambient_energy` fill the shadowed faces so nothing goes pure
## black at night.
const KEYFRAMES: Array[Dictionary] = [
	{"at": 0.00, "name": "Dawn", "pitch": -12.0, "light": Color("FFB27A"), "energy": 0.55, "sky": Color("7E8FA8"), "ambient": Color("6E7A96"), "ambient_energy": 0.35},
	{"at": 0.18, "name": "Morning", "pitch": -35.0, "light": Color("FFE0B8"), "energy": 1.00, "sky": Color("8FBBD9"), "ambient": Color("B9CBDD"), "ambient_energy": 0.55},
	{"at": 0.40, "name": "Midday", "pitch": -70.0, "light": Color("FFFFFF"), "energy": 1.35, "sky": Color("8CC6E8"), "ambient": Color("FFFFFF"), "ambient_energy": 0.60},
	{"at": 0.60, "name": "Afternoon", "pitch": -45.0, "light": Color("FFEBC4"), "energy": 1.10, "sky": Color("93C4E0"), "ambient": Color("E8EEF5"), "ambient_energy": 0.55},
	{"at": 0.76, "name": "Sunset", "pitch": -12.0, "light": Color("FF9046"), "energy": 0.80, "sky": Color("E2926B"), "ambient": Color("C08A78"), "ambient_energy": 0.40},
	{"at": 0.88, "name": "Dusk", "pitch": -6.0, "light": Color("8E7BC4"), "energy": 0.35, "sky": Color("4A4E75"), "ambient": Color("4E5378"), "ambient_energy": 0.28},
	{"at": 0.95, "name": "Night", "pitch": -50.0, "light": Color("7C93C8"), "energy": 0.18, "sky": Color("1E2440"), "ambient": Color("2A3352"), "ambient_energy": 0.22},
	{"at": 1.00, "name": "Dawn", "pitch": -12.0, "light": Color("FFB27A"), "energy": 0.55, "sky": Color("7E8FA8"), "ambient": Color("6E7A96"), "ambient_energy": 0.35},
]

## The lighting at `phase`, linearly interpolated between the two keyframes
## that bracket it. Phases outside [0,1) wrap, so a caller never has to
## normalise a running clock itself.
static func sample(phase: float) -> Dictionary:
	var p := fposmod(phase, 1.0)
	var previous: Dictionary = KEYFRAMES[0]
	for key in KEYFRAMES:
		if key.at > p:
			var span: float = key.at - previous.at
			var t: float = 0.0 if span <= 0.0 else (p - previous.at) / span
			return {
				"name": previous.name,
				"pitch": lerpf(previous.pitch, key.pitch, t),
				"light": previous.light.lerp(key.light, t),
				"energy": lerpf(previous.energy, key.energy, t),
				"sky": previous.sky.lerp(key.sky, t),
				"ambient": previous.ambient.lerp(key.ambient, t),
				"ambient_energy": lerpf(previous.ambient_energy, key.ambient_energy, t),
			}
		previous = key
	# p >= the last keyframe's `at` (only reachable at exactly 1.0, which the
	# wrap above turns into 0.0 -- kept for safety).
	return sample(0.0)

## The name of the stretch `phase` falls in ("Morning", "Sunset", ...), for
## showing beside the day counter.
static func label(phase: float) -> String:
	return sample(phase).name

## Pushes one sampled moment onto the scene's sun and environment. The sun's
## yaw is deliberately left alone -- swinging it too would have to snap back
## at the rollover, which reads as the light spinning.
static func apply(phase: float, sun: DirectionalLight3D, environment: Environment) -> void:
	var moment := sample(phase)
	if sun != null:
		sun.rotation_degrees.x = moment.pitch
		sun.light_color = moment.light
		sun.light_energy = moment.energy
	if environment != null:
		environment.background_color = moment.sky
		environment.ambient_light_color = moment.ambient
		environment.ambient_light_energy = moment.ambient_energy
