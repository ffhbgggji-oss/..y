extends RefCounted
class_name Tween2D

## Shared 2D pose interpolation helper for a cut-out / puppet editor.
## A pose is a Dictionary keyed by stable part name. Each part stores position,
## rotation (radians), and scale. Rotation follows the shortest angular path.
static func interpolate_pose(from_pose: Dictionary, to_pose: Dictionary, weight: float) -> Dictionary:
    var t := clampf(weight, 0.0, 1.0)
    var result: Dictionary = {}
    for part_name in from_pose.keys():
        if not to_pose.has(part_name):
            continue
        var a: Dictionary = from_pose[part_name]
        var b: Dictionary = to_pose[part_name]
        var angle_a := float(a.get("rotation", 0.0))
        var angle_b := float(b.get("rotation", 0.0))
        result[part_name] = {
            "position": (a.get("position", Vector2.ZERO) as Vector2).lerp(b.get("position", Vector2.ZERO), t),
            "rotation": lerp_angle(angle_a, angle_b, t),
            "scale": (a.get("scale", Vector2.ONE) as Vector2).lerp(b.get("scale", Vector2.ONE), t)
        }
    return result

static func make_tween_frames(from_pose: Dictionary, to_pose: Dictionary, count: int) -> Array[Dictionary]:
    var output: Array[Dictionary] = []
    var safe_count := clampi(count, 1, 120)
    for i in range(1, safe_count + 1):
        var t := float(i) / float(safe_count + 1)
        output.append(interpolate_pose(from_pose, to_pose, t))
    return output
