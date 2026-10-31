extends RefCounted

## Phone-sized UI rules. A 2520x1080 phone shows the 720-high canvas at 1.5x,
## so one logical pixel is ~0.1 mm: desktop font sizes and 40 px buttons are
## unreadable or untappable there. Every helper returns its input unchanged on
## desktop, so the PC layout stays exactly as designed.
##
## Use: const MobileUi = preload("res://scripts/core/mobile_ui.gd")

const QualityRules = preload("res://scripts/core/graphics_quality.gd")

## Smallest logical font size that stays legible on a 6.9" phone (~11 sp).
const MIN_FONT_SIZE := 18
const FONT_SCALE := 1.25
## 48 dp at 1.5x ≈ 80 logical px: Android's minimum comfortable touch target.
const MIN_TOUCH_SIZE := 80.0
## Small widgets (sliders, swatches) that cannot reach 80 still need this much.
const MIN_TOUCH_SIZE_COMPACT := 56.0


static func is_touch_ui() -> bool:
	return QualityRules.is_mobile_target()


## Font size to pass to add_theme_font_size_override().
static func font(px: int) -> int:
	if not is_touch_ui():
		return px
	return maxi(roundi(float(px) * FONT_SCALE), MIN_FONT_SIZE)


## Minimum edge of a tappable control.
static func touch(px: float, compact: bool = false) -> float:
	if not is_touch_ui():
		return px
	return maxf(px, MIN_TOUCH_SIZE_COMPACT if compact else MIN_TOUCH_SIZE)


## Grows a control's minimum height (and width when it is narrower) to a
## comfortable touch target. No-op on desktop.
static func ensure_touch_size(control: Control, compact: bool = false) -> void:
	if control == null or not is_touch_ui():
		return
	var minimum := MIN_TOUCH_SIZE_COMPACT if compact else MIN_TOUCH_SIZE
	var size := control.custom_minimum_size
	control.custom_minimum_size = Vector2(maxf(size.x, minimum), maxf(size.y, minimum))


## Desktop key prompts ("Enter でスタート") read as touch prompts on phones.
static func prompt(desktop_text: String, touch_text: String) -> String:
	return touch_text if is_touch_ui() else desktop_text
