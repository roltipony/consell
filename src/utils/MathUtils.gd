## MathUtils.gd
## Pure-function math helpers used across systems.
class_name MathUtils
extends RefCounted

static func lerp01(a: float, b: float, t: float) -> float:
	return lerpf(a, b, clampf(t, 0.0, 1.0))

static func remap(value: float, from_min: float, from_max: float,
		to_min: float, to_max: float) -> float:
	if is_equal_approx(from_max, from_min):
		return to_min
	return to_min + (value - from_min) / (from_max - from_min) * (to_max - to_min)

static func chance(probability: float) -> bool:
	return randf() < clampf(probability, 0.0, 1.0)

static func weighted_choice(options: Dictionary) -> Variant:
	var total: float = 0.0
	for key in options:
		total += float(options[key])
	var roll: float = randf() * total
	var cumulative: float = 0.0
	for key in options:
		cumulative += float(options[key])
		if roll <= cumulative:
			return key
	return options.keys().back()

static func format_number(value: int) -> String:
	if value >= 1_000_000:
		return "%.1fM" % (value / 1_000_000.0)
	if value >= 1_000:
		return "%.1fK" % (value / 1_000.0)
	return str(value)
