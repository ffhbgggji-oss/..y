extends MeshInstance3D
class_name SkeletonOverlay3D

## Runtime target_skeleton display: parent-child bone lines and joint markers.
var target_skeleton: Skeleton3D
var selected_bone := -1
var overlay_enabled := true
var bone_material: StandardMaterial3D
var selected_material: StandardMaterial3D

func _ready() -> void:
    mesh = ImmediateMesh.new()
    bone_material = StandardMaterial3D.new()
    bone_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    bone_material.albedo_color = Color(0.25, 0.85, 1.0, 1.0)
    bone_material.no_depth_test = true
    bone_material.render_priority = 2
    selected_material = StandardMaterial3D.new()
    selected_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    selected_material.albedo_color = Color(1.0, 0.72, 0.12, 1.0)
    selected_material.no_depth_test = true
    selected_material.render_priority = 3
    cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func configure(value: Skeleton3D, selected: int, enabled: bool) -> void:
    target_skeleton = value
    selected_bone = selected
    overlay_enabled = enabled
    _rebuild()

func _process(_delta: float) -> void:
    if overlay_enabled and is_instance_valid(target_skeleton):
        _rebuild()

func _rebuild() -> void:
    var immediate := mesh as ImmediateMesh
    if immediate == null:
        return
    immediate.clear_surfaces()
    if not overlay_enabled or not is_instance_valid(target_skeleton):
        return
    var inverse_transform := global_transform.affine_inverse()
    # Batch all ordinary bones into one surface to reduce mobile rendering overhead.
    immediate.surface_begin(Mesh.PRIMITIVE_LINES, bone_material)
    for bone_index in range(target_skeleton.get_bone_count()):
        if bone_index == selected_bone:
            continue
        _append_bone_lines(immediate, bone_index, inverse_transform)
    immediate.surface_end()
    if selected_bone >= 0 and selected_bone < target_skeleton.get_bone_count():
        immediate.surface_begin(Mesh.PRIMITIVE_LINES, selected_material)
        _append_bone_lines(immediate, selected_bone, inverse_transform)
        immediate.surface_end()

func _append_bone_lines(immediate: ImmediateMesh, bone_index: int, inverse_transform: Transform3D) -> void:
    var parent_index := target_skeleton.get_bone_parent(bone_index)
    if parent_index < 0:
        return
    var child_world := target_skeleton.global_transform * target_skeleton.get_bone_global_pose(bone_index).origin
    var parent_world := target_skeleton.global_transform * target_skeleton.get_bone_global_pose(parent_index).origin
    immediate.surface_add_vertex(inverse_transform * parent_world)
    immediate.surface_add_vertex(inverse_transform * child_world)
    var center := inverse_transform * child_world
    var r := 0.025
    immediate.surface_add_vertex(center + Vector3(-r, 0, 0))
    immediate.surface_add_vertex(center + Vector3(r, 0, 0))
    immediate.surface_add_vertex(center + Vector3(0, -r, 0))
    immediate.surface_add_vertex(center + Vector3(0, r, 0))
    immediate.surface_add_vertex(center + Vector3(0, 0, -r))
    immediate.surface_add_vertex(center + Vector3(0, 0, r))
