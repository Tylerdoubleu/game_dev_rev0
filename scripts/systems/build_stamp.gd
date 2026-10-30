extends CanvasLayer
## v0.6.3 build stamp: "v0.6.3 · <short commit>" in the bottom-right corner, on its own layer above the HUD (6-12),
## the arena lobby (10) and the LobbyEntryFlow lobby browser / waiting room (60), so the same label shows in the match
## HUD and in the lobby footer area without editing the lobby UI files. Text comes from build_info.gd, which the
## export step (tools/export_web.sh) generates with the source commit the build came from.

const BuildInfo = preload("res://scripts/systems/build_info.gd")
const LAYER := 61

var label: Label

static func stamp_text() -> String:
	return "%s · %s" % [BuildInfo.VERSION, BuildInfo.COMMIT]

func _ready() -> void:
	name = "BuildStamp"
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	label = TournamentSkin.led(stamp_text(), 12, TournamentSkin.MUTED)
	label.name = "BuildStampLabel"
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.modulate = Color(1, 1, 1, 0.55)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	label.offset_right = -8
	label.offset_bottom = -4
	label.tooltip_text = "built %s" % BuildInfo.BUILT_UTC if not BuildInfo.BUILT_UTC.is_empty() else ""
	add_child(label)
