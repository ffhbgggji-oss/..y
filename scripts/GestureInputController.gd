extends Node
class_name GestureInputController

## Routes one-finger bone/orbit drags and two-finger pinch gestures.

signal bone_selected(index: int)
signal bone_dragged(index: int, relative: Vector2)
signal camera_dragged(relative: Vector2)
signal camera_pinched(previous_distance: float, current_distance: float)

var camera: Camera3D
var bone_controller: RigBoneController
var top_reserved := 82.0
var bottom_reserved := 150.0
var pick_radius := 64.0
var active_touch := -1
var touch_mode := ""
var touches: Dictionary = {}
var last_pinch_distance := 0.0

func configure(active_camera: Camera3D, bones: RigBoneController) -> void:
    camera = active_camera
    bone_controller = bones

func handle_input(event: InputEvent, viewport_size: Vector2) -> void:
    if event is InputEventScreenTouch:
        var touch := event as InputEventScreenTouch
        if touch.pressed:
            touches[touch.index] = touch.position
            if touches.size() == 1:
                _begin(touch.index, touch.position, viewport_size)
            elif touches.size() == 2:
                active_touch = -1
                touch_mode = "pinch"
                last_pinch_distance = _distance_between_touches()
        else:
            touches.erase(touch.index)
            if touch.index == active_touch:
                active_touch = -1
                touch_mode = ""
            if touches.size() < 2:
                last_pinch_distance = 0.0
    elif event is InputEventScreenDrag:
        var drag := event as InputEventScreenDrag
        touches[drag.index] = drag.position
        if touches.size() >= 2:
            var current := _distance_between_touches()
            if last_pinch_distance > 0.0 and current > 0.0:
                camera_pinched.emit(last_pinch_distance, current)
            last_pinch_distance = current
        elif drag.index == active_touch:
            _drag(drag.relative)
    elif event is InputEventMouseButton:
        var mouse := event as InputEventMouseButton
        if mouse.button_index == MOUSE_BUTTON_LEFT:
            if mouse.pressed:
                _begin(-2, mouse.position, viewport_size)
            elif active_touch == -2:
                active_touch = -1
                touch_mode = ""
    elif event is InputEventMouseMotion and active_touch == -2:
        _drag((event as InputEventMouseMotion).relative)

func _begin(index: int, position: Vector2, viewport_size: Vector2) -> void:
    if position.y < top_reserved or position.y > viewport_size.y - bottom_reserved:
        return
    active_touch = index
    var bone_index := bone_controller.pick_bone(camera, position, pick_radius) if bone_controller != null else -1
    if bone_index >= 0:
        touch_mode = "bone"
        bone_selected.emit(bone_index)
    else:
        touch_mode = "orbit"

func _drag(relative: Vector2) -> void:
    if touch_mode == "bone":
        bone_dragged.emit(bone_controller.selected_bone if bone_controller != null else -1, relative)
    elif touch_mode == "orbit":
        camera_dragged.emit(relative)

func _distance_between_touches() -> float:
    if touches.size() < 2:
        return 0.0
    var points: Array = touches.values()
    return (points[0] as Vector2).distance_to(points[1] as Vector2)
