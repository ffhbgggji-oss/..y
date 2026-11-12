extends Control
class_name BoneTransformGizmo

## Non-interactive screen-space visual guide for the currently selected joint.
## The editor routes touch gestures to the active Rotate/Move/Scale tool.

var gizmo_center := Vector2(-10000.0, -10000.0)
var tool_mode := "rotate"
var selected := false

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    queue_redraw()

func update_gizmo(center: Vector2, mode: String, has_selection: bool) -> void:
    gizmo_center = center
    tool_mode = mode
    selected = has_selection
    queue_redraw()

func _draw() -> void:
    if not selected or gizmo_center.x < -1000.0:
        return
    var c := gizmo_center
    var axis_x := Color("ff626b")
    var axis_y := Color("5be28b")
    var axis_z := Color("55baff")
    if tool_mode == "rotate":
        draw_arc(c, 34.0, 0.0, TAU, 48, Color("ffd45c"), 4.0, true)
        draw_arc(c, 42.0, 0.0, TAU, 48, Color(1.0, 1.0, 1.0, 0.3), 1.5, true)
        draw_circle(c, 6.0, Color.WHITE)
    elif tool_mode == "move":
        _draw_arrow(c, c + Vector2(62, 0), axis_x)
        _draw_arrow(c, c + Vector2(0, -62), axis_y)
        draw_circle(c, 7.0, axis_z)
        draw_string(ThemeDB.fallback_font, c + Vector2(66, 5), "X", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, axis_x)
        draw_string(ThemeDB.fallback_font, c + Vector2(5, -66), "Y", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, axis_y)
    elif tool_mode == "scale":
        _draw_arrow(c, c + Vector2(58, 0), axis_x)
        _draw_arrow(c, c + Vector2(0, -58), axis_y)
        draw_rect(Rect2(c + Vector2(24, 24), Vector2(14, 14)), axis_z, true)
        draw_circle(c, 7.0, Color.WHITE)

func _draw_arrow(from: Vector2, to: Vector2, color: Color) -> void:
    draw_line(from, to, color, 5.0, true)
    var direction := (to - from).normalized()
    var side := Vector2(-direction.y, direction.x) * 8.0
    draw_colored_polygon(PackedVector2Array([to, to - direction * 16.0 + side, to - direction * 16.0 - side]), color)
