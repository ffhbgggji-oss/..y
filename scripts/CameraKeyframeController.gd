extends Node
class_name CameraKeyframeController

const MIN_DISTANCE := 1.5
const MAX_DISTANCE := 30.0
var camera: Camera3D
var target := Vector3(0.0, 1.2, 0.0)
var yaw := 0.0
var pitch := 0.12
var distance := 7.5

func bind_camera(value: Camera3D) -> void:
    camera = value
    sync_orbit_from_camera()

func reset_view() -> void:
    target = Vector3(0.0, 1.2, 0.0)
    yaw = 0.0
    pitch = 0.12
    distance = 7.5
    update_orbit()

func orbit_drag(relative: Vector2, sensitivity: float = 0.007) -> void:
    yaw -= relative.x * sensitivity
    pitch = clampf(pitch + relative.y * sensitivity, -1.35, 1.35)
    update_orbit()

func pinch_zoom(previous_distance: float, current_distance: float) -> void:
    if previous_distance <= 0.0 or current_distance <= 0.0:
        return
    distance = clampf(distance * previous_distance / current_distance, MIN_DISTANCE, MAX_DISTANCE)
    update_orbit()

func update_orbit() -> void:
    if not is_instance_valid(camera):
        return
    var direction := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
    camera.global_position = target + direction * distance
    camera.look_at(target, Vector3.UP)

func sync_orbit_from_camera() -> void:
    if not is_instance_valid(camera):
        return
    var offset := camera.global_position - target
    distance = clampf(offset.length(), MIN_DISTANCE, MAX_DISTANCE)
    if distance > 0.001:
        yaw = atan2(offset.x, offset.z)
        pitch = asin(clampf(offset.y / distance, -1.0, 1.0))

func capture_key() -> Dictionary:
    if not is_instance_valid(camera):
        return {"position": Vector3.ZERO, "rotation": Quaternion.IDENTITY}
    return {"position": camera.global_position, "rotation": camera.global_basis.get_rotation_quaternion()}

func apply_key(key: Dictionary) -> void:
    if not is_instance_valid(camera) or key.is_empty():
        return
    camera.global_position = key.get("position", camera.global_position)
    camera.global_basis = Basis(key.get("rotation", camera.global_basis.get_rotation_quaternion()))
    sync_orbit_from_camera()

func interpolate_keys(a: Dictionary, b: Dictionary, weight: float) -> Dictionary:
    var t := clampf(weight, 0.0, 1.0)
    return {
        "position": (a.get("position", Vector3.ZERO) as Vector3).lerp(b.get("position", Vector3.ZERO), t),
        "rotation": (a.get("rotation", Quaternion.IDENTITY) as Quaternion).slerp(b.get("rotation", Quaternion.IDENTITY) as Quaternion, t).normalized()
    }
