extends Node
class_name RigBoneController

## Editing and interpolation utilities for an imported Skeleton3D.
var skeleton: Skeleton3D

func bind_skeleton(value: Skeleton3D) -> void:
    skeleton = value

func pick_bone(camera: Camera3D, screen_position: Vector2, radius: float = 68.0) -> int:
    if not is_instance_valid(skeleton) or not is_instance_valid(camera):
        return -1
    var best_index := -1
    var best_distance := radius
    for index in range(skeleton.get_bone_count()):
        var world_position: Vector3 = skeleton.global_transform * skeleton.get_bone_global_pose(index).origin
        if camera.is_position_behind(world_position):
            continue
        var distance := camera.unproject_position(world_position).distance_to(screen_position)
        if distance < best_distance:
            best_distance = distance
            best_index = index
    return best_index

func capture_pose() -> Dictionary:
    var result: Dictionary = {}
    if not is_instance_valid(skeleton):
        return result
    for index in range(skeleton.get_bone_count()):
        result[str(index)] = {
            "position": skeleton.get_bone_pose_position(index),
            "rotation": skeleton.get_bone_pose_rotation(index),
            "scale": skeleton.get_bone_pose_scale(index)
        }
    return result

func apply_pose(pose: Dictionary) -> void:
    if not is_instance_valid(skeleton):
        return
    for key in pose.keys():
        var index := int(key)
        if index < 0 or index >= skeleton.get_bone_count():
            continue
        var item: Dictionary = pose[key]
        skeleton.set_bone_pose_position(index, item.get("position", skeleton.get_bone_pose_position(index)))
        skeleton.set_bone_pose_rotation(index, item.get("rotation", skeleton.get_bone_pose_rotation(index)))
        skeleton.set_bone_pose_scale(index, item.get("scale", skeleton.get_bone_pose_scale(index)))

func interpolate_pose(from_pose: Dictionary, to_pose: Dictionary, weight: float) -> Dictionary:
    var result: Dictionary = {}
    var t := clampf(weight, 0.0, 1.0)
    for key in from_pose.keys():
        if not to_pose.has(key):
            continue
        var a: Dictionary = from_pose[key]
        var b: Dictionary = to_pose[key]
        var qa: Quaternion = a.get("rotation", Quaternion.IDENTITY)
        var qb: Quaternion = b.get("rotation", Quaternion.IDENTITY)
        result[key] = {
            "position": (a.get("position", Vector3.ZERO) as Vector3).lerp(b.get("position", Vector3.ZERO), t),
            "rotation": qa.slerp(qb, t).normalized(),
            "scale": (a.get("scale", Vector3.ONE) as Vector3).lerp(b.get("scale", Vector3.ONE), t)
        }
    return result

func rotate_bone_from_drag(index: int, relative: Vector2, camera: Camera3D, sensitivity: float = 0.010) -> bool:
    if not _valid_bone(index):
        return false
    var right := camera.global_basis.x.normalized() if is_instance_valid(camera) else Vector3.RIGHT
    var up := camera.global_basis.y.normalized() if is_instance_valid(camera) else Vector3.UP
    var world_delta := Quaternion(up, -relative.x * sensitivity) * Quaternion(right, -relative.y * sensitivity)
    var parent_basis := _parent_global_basis(index)
    var local_delta := Quaternion(parent_basis.inverse() * Basis(world_delta) * parent_basis)
    skeleton.set_bone_pose_rotation(index, (local_delta * skeleton.get_bone_pose_rotation(index)).normalized())
    return true

func move_bone_from_drag(index: int, relative: Vector2, camera: Camera3D, units_per_pixel: float = 0.004) -> bool:
    if not _valid_bone(index):
        return false
    var right := camera.global_basis.x.normalized() if is_instance_valid(camera) else Vector3.RIGHT
    var up := camera.global_basis.y.normalized() if is_instance_valid(camera) else Vector3.UP
    var world_delta := right * relative.x * units_per_pixel - up * relative.y * units_per_pixel
    skeleton.set_bone_pose_position(index, skeleton.get_bone_pose_position(index) + _parent_global_basis(index).inverse() * world_delta)
    return true

func scale_bone_from_drag(index: int, relative: Vector2, sensitivity: float = 0.006) -> bool:
    if not _valid_bone(index):
        return false
    var factor := exp(-relative.y * sensitivity)
    var value := skeleton.get_bone_pose_scale(index) * factor
    value.x = clampf(value.x, 0.1, 4.0)
    value.y = clampf(value.y, 0.1, 4.0)
    value.z = clampf(value.z, 0.1, 4.0)
    skeleton.set_bone_pose_scale(index, value)
    return true

func bone_name(index: int) -> String:
    return skeleton.get_bone_name(index) if _valid_bone(index) else ""

func _valid_bone(index: int) -> bool:
    return is_instance_valid(skeleton) and index >= 0 and index < skeleton.get_bone_count()

func _parent_global_basis(index: int) -> Basis:
    var parent_index := skeleton.get_bone_parent(index)
    if parent_index < 0:
        return skeleton.global_basis.orthonormalized()
    return (skeleton.global_transform * skeleton.get_bone_global_pose(parent_index)).basis.orthonormalized()
