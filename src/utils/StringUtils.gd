## StringUtils.gd
## String formatting helpers used across UI scripts.
class_name StringUtils
extends RefCounted

static func capitalize_first(s: String) -> String:
	if s.is_empty():
		return s
	return s[0].to_upper() + s.substr(1)

## Convert snake_case to Title Case.
static func snake_to_title(s: String) -> String:
	var words: PackedStringArray = s.split("_")
	var result: String = ""
	for word in words:
		if result != "":
			result += " "
		result += capitalize_first(word)
	return result

## Returns a colour-coded BBCode string for a signed number.
static func signed_bbcolor(value: int, positive_color: String = "green", negative_color: String = "red") -> String:
	if value >= 0:
		return "[color=%s]+%d[/color]" % [positive_color, value]
	return "[color=%s]%d[/color]" % [negative_color, value]

## Format seconds into MM:SS display.
static func format_time(total_seconds: int) -> String:
	var m: int = total_seconds / 60
	var s: int = total_seconds % 60
	return "%02d:%02d" % [m, s]
