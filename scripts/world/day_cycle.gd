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

## Keyframes in phase order.
##
## - `minutes` is the wall-clock time of day, in minutes from midnight, so
##   the panel can read "6:24 pm". The last keyframe runs past 24h (1740 =
##   5:00 am the next morning) purely to keep the interpolation monotonic
##   across the rollover; clock_text() wraps it back into a real time.
## - `pitch`/`yaw` are the sun's rotation in degrees. Pitch is how high it
##   sits (shallower = nearer the horizon = longer shadows). Yaw sweeps
##   through a full turn over the day, which is what makes shadows visibly
##   travel; the last keyframe is -282, the same orientation as the first
##   (+78) one turn on, so the sweep never doubles back or snaps.
## - `light`/`energy` are the directional light's colour and strength, and
##   `shadow` its opacity -- shadows are crisp at midday, soft at dawn and
##   dusk, and barely there under moonlight.
## - `sky` is the background colour; `ambient`/`ambient_energy` fill the
##   shadowed faces so nothing goes pure black at night.
## - `window_glow` is how brightly a settlement's windows are lit, 0 by day
##   and 1 in the dark (see NodeMarker.set_window_glow). It lives here rather
##   than being derived from `energy` because "are the lights on" is not the
##   same question as "how bright is the sun": lamps come on at dusk while
##   there is still plenty of light, and stay on into a dawn that is already
##   brightening. Deriving one from the other would make the lights fade in
##   exactly as the sun faded out, which is the one thing they do not do.
const KEYFRAMES: Array[Dictionary] = [
	{"at": 0.00, "name": "Dawn", "minutes": 300, "pitch": -12.0, "yaw": 78.0, "light": Color("FFB27A"), "energy": 0.55, "shadow": 0.55, "sky": Color("7E8FA8"), "ambient": Color("6E7A96"), "ambient_energy": 0.35, "window_glow": 0.35},
	{"at": 0.18, "name": "Morning", "minutes": 480, "pitch": -35.0, "yaw": 50.0, "light": Color("FFE0B8"), "energy": 1.00, "shadow": 0.85, "sky": Color("8FBBD9"), "ambient": Color("B9CBDD"), "ambient_energy": 0.55, "window_glow": 0.0},
	{"at": 0.40, "name": "Midday", "minutes": 720, "pitch": -70.0, "yaw": 8.0, "light": Color("FFFFFF"), "energy": 1.35, "shadow": 1.00, "sky": Color("8CC6E8"), "ambient": Color("FFFFFF"), "ambient_energy": 0.60, "window_glow": 0.0},
	{"at": 0.60, "name": "Afternoon", "minutes": 900, "pitch": -45.0, "yaw": -30.0, "light": Color("FFEBC4"), "energy": 1.10, "shadow": 0.90, "sky": Color("93C4E0"), "ambient": Color("E8EEF5"), "ambient_energy": 0.55, "window_glow": 0.0},
	{"at": 0.76, "name": "Sunset", "minutes": 1110, "pitch": -12.0, "yaw": -70.0, "light": Color("FF9046"), "energy": 0.80, "shadow": 0.70, "sky": Color("E2926B"), "ambient": Color("C08A78"), "ambient_energy": 0.40, "window_glow": 0.3},
	{"at": 0.88, "name": "Dusk", "minutes": 1200, "pitch": -8.0, "yaw": -85.0, "light": Color("8E7BC4"), "energy": 0.35, "shadow": 0.35, "sky": Color("4A4E75"), "ambient": Color("4E5378"), "ambient_energy": 0.28, "window_glow": 0.85},
	{"at": 0.95, "name": "Night", "minutes": 1380, "pitch": -50.0, "yaw": -160.0, "light": Color("7C93C8"), "energy": 0.18, "shadow": 0.20, "sky": Color("1E2440"), "ambient": Color("2A3352"), "ambient_energy": 0.22, "window_glow": 1.0},
	{"at": 1.00, "name": "Dawn", "minutes": 1740, "pitch": -12.0, "yaw": -282.0, "light": Color("FFB27A"), "energy": 0.55, "shadow": 0.55, "sky": Color("7E8FA8"), "ambient": Color("6E7A96"), "ambient_energy": 0.35, "window_glow": 0.35},
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
				"minutes": lerpf(previous.minutes, key.minutes, t),
				"pitch": lerpf(previous.pitch, key.pitch, t),
				"yaw": lerpf(previous.yaw, key.yaw, t),
				"shadow": lerpf(previous.shadow, key.shadow, t),
				"light": previous.light.lerp(key.light, t),
				"energy": lerpf(previous.energy, key.energy, t),
				"sky": previous.sky.lerp(key.sky, t),
				"ambient": previous.ambient.lerp(key.ambient, t),
				"ambient_energy": lerpf(previous.ambient_energy, key.ambient_energy, t),
				"window_glow": lerpf(previous.window_glow, key.window_glow, t),
			}
		previous = key
	# p >= the last keyframe's `at` (only reachable at exactly 1.0, which the
	# wrap above turns into 0.0 -- kept for safety).
	return sample(0.0)

## The name of the stretch `phase` falls in ("Morning", "Sunset", ...), for
## showing beside the day counter.
static func label(phase: float) -> String:
	return sample(phase).name

## The wall-clock time at `phase`, as the panel shows it: "5:00 am",
## "12:30 pm", "11:47 pm". A day opens at 5:00 am (dawn) and the clock runs
## round to 5:00 am again as it rolls over.
static func clock_text(phase: float) -> String:
	var minutes := posmod(roundi(sample(phase).minutes), 1440)
	var hour := minutes / 60
	var minute := minutes % 60
	var suffix := "am" if hour < 12 else "pm"
	var display_hour := hour % 12
	if display_hour == 0:
		display_hour = 12
	return "%d:%02d %s" % [display_hour, minute, suffix]

## Whether this build can afford shadows at all.
##
## Everywhere except the web: false there, and not as a quality preference.
## A browser hands the page a much smaller GPU budget than a native build --
## on a phone, dramatically smaller -- and going over it doesn't degrade
## gracefully, the browser destroys the WebGL context outright and the game
## dies with "WebGL context lost, please reload the page". Shadows are the
## single largest allocation the scene asks for, so the web build goes
## without them; every other part of the sun cycle (angle, light colour and
## energy, sky and ambient tint) still runs, so a web day still visibly
## moves from dawn to night. Desktop keeps full-quality shadows.
##
## If a web build ever loses its context again, the next-largest lever is
## MSAA -- `rendering/anti_aliasing/quality/msaa_3d` is 4x, which is a
## multisampled framebuffer's worth of memory and bandwidth.
static func shadows_available() -> bool:
	return not OS.has_feature("web")

## Pushes one sampled moment onto the scene's sun and environment, and hands
## it back -- the caller still needs `window_glow` from it, which belongs to
## the settlement markers rather than to the sun or the environment, and
## re-sampling for that would be the same work twice every frame.
static func apply(phase: float, sun: DirectionalLight3D, environment: Environment) -> Dictionary:
	var moment := sample(phase)
	if sun != null:
		sun.rotation_degrees.x = moment.pitch
		sun.rotation_degrees.y = moment.yaw
		sun.light_color = moment.light
		sun.light_energy = moment.energy
		sun.shadow_opacity = moment.shadow
	if environment != null:
		environment.background_color = moment.sky
		environment.ambient_light_color = moment.ambient
		environment.ambient_light_energy = moment.ambient_energy
	return moment
