extends Node3D

const MAX_TWEEN_FRAMES := 120
const MAX_PARTICLES := 64
const CLOTH_SCRIPT := preload("res://scripts/SoftCloth.gd")
const SAVE_FILE := "user://animation_project.json"

var camera: Camera3D
var puppet_root: Node3D
var puppet_parts: Dictionary = {}
var frame_states: Array[Dictionary] = []
var current_frame_index := 0
var selected_part_name := "Torso"
var is_playing := false
var playback_timer := 0.0
var playback_fps := 24.0
var suppress_ui_events := false

var ui_layer: CanvasLayer
var timeline_slider: HSlider
var frame_label: Label
var status_label: Label
var play_button: Button
var tween_count: SpinBox
var part_selector: OptionButton
var transform_controls: Dictionary = {}
var file_dialog: FileDialog
var cloth_instance: Node3D

func _ready() -> void:
    camera = get_node_or_null("Camera3D") as Camera3D
    puppet_root = get_node_or_null("PuppetRoot") as Node3D
    if puppet_root == null:
        puppet_root = Node3D.new()
        puppet_root.name = "PuppetRoot"
        add_child(puppet_root)
    if camera != null:
        camera.current = true
        camera.look_at(Vector3(0.0, 1.25, 0.0), Vector3.UP)

    build_default_puppet()
    build_ui()
    frame_states.append({"kind": "key", "pose": get_pose_snapshot(), "tween_count": 5})
    refresh_timeline()
    set_status("Редактор готов: задайте позы и создайте промежуточные кадры")

func build_default_puppet() -> void:
    for child in puppet_root.get_children():
        child.queue_free()
    puppet_parts.clear()
    cloth_instance = null
    puppet_parts["Torso"] = make_part("Torso", Vector3(0, 1.2, 0), Vector3(1.0, 1.4, 0.45), Color(0.34, 0.61, 0.88))
    puppet_parts["Head"] = make_part("Head", Vector3(0, 2.25, 0), Vector3(0.62, 0.62, 0.62), Color(0.94, 0.78, 0.62), true)
    puppet_parts["LeftArm"] = make_part("LeftArm", Vector3(-0.78, 1.62, 0), Vector3(0.28, 0.9, 0.28), Color(0.82, 0.52, 0.40))
    puppet_parts["RightArm"] = make_part("RightArm", Vector3(0.78, 1.62, 0), Vector3(0.28, 0.9, 0.28), Color(0.82, 0.52, 0.40))
    puppet_parts["LeftLeg"] = make_part("LeftLeg", Vector3(-0.3, 0.42, 0), Vector3(0.32, 0.9, 0.32), Color(0.25, 0.43, 0.70))
    puppet_parts["RightLeg"] = make_part("RightLeg", Vector3(0.3, 0.42, 0), Vector3(0.32, 0.9, 0.32), Color(0.25, 0.43, 0.70))
    (puppet_parts["LeftArm"] as Node3D).rotation_degrees.z = -24.0
    (puppet_parts["RightArm"] as Node3D).rotation_degrees.z = 24.0

func make_part(part_name: String, position: Vector3, size: Vector3, color: Color, sphere := false) -> Node3D:
    var pivot := Node3D.new()
    pivot.name = part_name
    pivot.position = position
    puppet_root.add_child(pivot)
    var mesh_instance := MeshInstance3D.new()
    mesh_instance.name = part_name + "Mesh"
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = 0.82
    material.specular = 0.18
    if sphere:
        var sphere_mesh := SphereMesh.new()
        sphere_mesh.radius = 0.5
        sphere_mesh.height = 1.0
        mesh_instance.mesh = sphere_mesh
    else:
        var box_mesh := BoxMesh.new()
        box_mesh.size = Vector3.ONE
        mesh_instance.mesh = box_mesh
    mesh_instance.scale = size
    mesh_instance.material_override = material
    pivot.add_child(mesh_instance)
    return pivot

func build_ui() -> void:
    ui_layer = CanvasLayer.new()
    add_child(ui_layer)
    var panel := PanelContainer.new()
    panel.anchor_left = 0.0
    panel.anchor_top = 0.62
    panel.anchor_right = 1.0
    panel.anchor_bottom = 1.0
    panel.offset_left = 8
    panel.offset_top = 0
    panel.offset_right = -8
    panel.offset_bottom = -8
    ui_layer.add_child(panel)

    var scroll := ScrollContainer.new()
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    panel.add_child(scroll)
    var layout := VBoxContainer.new()
    layout.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.add_child(layout)

    var actions := HFlowContainer.new()
    layout.add_child(actions)
    play_button = add_button(actions, "▶", _toggle_playback)
    add_button(actions, "+ Поза", _add_key_pose)
    add_button(actions, "Дублировать", _duplicate_frame)
    add_button(actions, "Удалить", _delete_frame)
    add_button(actions, "Создать твины", _generate_tweens)
    add_button(actions, "Куб", _add_box)
    add_button(actions, "Шар", _add_sphere)
    add_button(actions, "Импорт GLB/GLTF", _open_import_dialog)
    add_button(actions, "Частицы", _toggle_particles)
    add_button(actions, "Ткань", _toggle_cloth)
    add_button(actions, "Экспорт MP4", _export_mp4)
    add_button(actions, "Сохранить", save_project)
    add_button(actions, "Загрузить", load_project)
    add_button(actions, "Сброс", _reset_pose)

    var tween_row := HBoxContainer.new()
    layout.add_child(tween_row)
    var tween_label := Label.new()
    tween_label.text = "Твинов после выбранной позы:"
    tween_row.add_child(tween_label)
    tween_count = SpinBox.new()
    tween_count.min_value = 1
    tween_count.max_value = MAX_TWEEN_FRAMES
    tween_count.value = 5
    tween_count.step = 1
    tween_count.custom_minimum_size.x = 100
    tween_count.value_changed.connect(_on_tween_count_changed)
    tween_row.add_child(tween_count)

    frame_label = Label.new()
    layout.add_child(frame_label)
    timeline_slider = HSlider.new()
    timeline_slider.min_value = 0
    timeline_slider.max_value = 0
    timeline_slider.step = 1
    timeline_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    timeline_slider.value_changed.connect(_on_timeline_changed)
    layout.add_child(timeline_slider)

    part_selector = OptionButton.new()
    part_selector.item_selected.connect(_on_part_selected)
    layout.add_child(part_selector)
    _add_transform_editor(layout, "Position", "position", -5.0, 5.0, 0.05)
    _add_transform_editor(layout, "Rotation °", "rotation_degrees", -180.0, 180.0, 1.0)
    _add_transform_editor(layout, "Scale", "scale", 0.05, 5.0, 0.05)

    status_label = Label.new()
    status_label.text = "Готово"
    layout.add_child(status_label)

    file_dialog = FileDialog.new()
    file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
    file_dialog.access = FileDialog.ACCESS_FILESYSTEM
    file_dialog.filters = PackedStringArray(["*.glb ; glTF Binary", "*.gltf ; glTF Scene"])
    file_dialog.file_selected.connect(_on_model_selected)
    ui_layer.add_child(file_dialog)
    _refresh_part_selector()

func _add_transform_editor(parent: VBoxContainer, title: String, key: String, minimum: float, maximum: float, step: float) -> void:
    var row := HBoxContainer.new()
    parent.add_child(row)
    var title_label := Label.new()
    title_label.text = title
    title_label.custom_minimum_size.x = 82
    row.add_child(title_label)
    for axis in ["x", "y", "z"]:
        var spin := SpinBox.new()
        spin.min_value = minimum
        spin.max_value = maximum
        spin.step = step
        spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        spin.value_changed.connect(_on_transform_changed.bind(key, axis))
        row.add_child(spin)
        transform_controls["%s_%s" % [key, axis]] = spin

func add_button(parent: Control, title: String, callback: Callable) -> Button:
    var button := Button.new()
    button.text = title
    button.custom_minimum_size = Vector2(90, 40)
    button.pressed.connect(callback)
    parent.add_child(button)
    return button

func set_status(message: String) -> void:
    if status_label != null:
        status_label.text = message

func _add_key_pose() -> void:
    _stop_playback()
    var insert_at := clampi(current_frame_index + 1, 0, frame_states.size())
    frame_states.insert(insert_at, {"kind": "key", "pose": get_pose_snapshot(), "tween_count": int(tween_count.value)})
    current_frame_index = insert_at
    refresh_timeline()
    set_status("Ключевая поза добавлена")

func _duplicate_frame() -> void:
    if frame_states.is_empty():
        return
    var copy: Dictionary = frame_states[current_frame_index].duplicate(true)
    frame_states.insert(current_frame_index + 1, copy)
    current_frame_index += 1
    refresh_timeline()
    set_status("Кадр продублирован")

func _delete_frame() -> void:
    if frame_states.size() <= 1:
        set_status("Нельзя удалить последний кадр")
        return
    frame_states.remove_at(current_frame_index)
    current_frame_index = clampi(current_frame_index, 0, frame_states.size() - 1)
    refresh_timeline()
    set_status("Кадр удалён")

func _generate_tweens() -> void:
    _stop_playback()
    if frame_states.is_empty() or frame_states[current_frame_index].get("kind", "key") != "key":
        set_status("Выберите ключевую позу")
        return
    var next_key := -1
    for i in range(current_frame_index + 1, frame_states.size()):
        if frame_states[i].get("kind", "key") == "key":
            next_key = i
            break
    if next_key < 0:
        set_status("Сначала добавьте следующую ключевую позу")
        return
    var count := clampi(int(tween_count.value), 1, MAX_TWEEN_FRAMES)
    frame_states[current_frame_index]["tween_count"] = count
    var start_pose: Dictionary = frame_states[current_frame_index]["pose"]
    var end_pose: Dictionary = frame_states[next_key]["pose"]
    var generated: Array[Dictionary] = []
    for step in range(1, count + 1):
        generated.append({"kind": "tween", "pose": interpolate_pose(start_pose, end_pose, float(step) / float(count + 1))})
    for i in range(next_key - 1, current_frame_index, -1):
        frame_states.remove_at(i)
    for i in range(generated.size()):
        frame_states.insert(current_frame_index + 1 + i, generated[i])
    refresh_timeline()
    set_status("Добавлено %d твин-кадров; каждый можно править отдельно" % count)

func interpolate_pose(from_pose: Dictionary, to_pose: Dictionary, t: float) -> Dictionary:
    var result: Dictionary = {}
    for part_name in puppet_parts.keys():
        if not from_pose.has(part_name) or not to_pose.has(part_name):
            continue
        var a: Dictionary = from_pose[part_name]
        var b: Dictionary = to_pose[part_name]
        var qa: Quaternion = a["rotation"]
        var qb: Quaternion = b["rotation"]
        result[part_name] = {
            "position": (a["position"] as Vector3).lerp(b["position"] as Vector3, t),
            "rotation": qa.slerp(qb, t),
            "scale": (a["scale"] as Vector3).lerp(b["scale"] as Vector3, t)
        }
    return result

func _toggle_playback() -> void:
    if frame_states.size() < 2:
        set_status("Добавьте минимум две позы")
        return
    is_playing = not is_playing
    if is_playing:
        playback_timer = 0.0
    play_button.text = "⏸" if is_playing else "▶"
    set_status("Воспроизведение" if is_playing else "Пауза")

func _stop_playback() -> void:
    is_playing = false
    if play_button != null:
        play_button.text = "▶"

func _process(delta: float) -> void:
    if not is_playing or frame_states.size() < 2:
        return

    # Keep the authored frame rate, but interpolate between frame poses on every
    # render update. This removes visible stepping when the device renders at 60 Hz.
    playback_timer += delta * maxf(1.0, playback_fps)
    var total_frames := frame_states.size()
    var phase := fposmod(playback_timer, float(total_frames))
    var from_index := int(floor(phase))
    var to_index := (from_index + 1) % total_frames
    var blend := phase - float(from_index)
    current_frame_index = from_index
    var from_pose: Dictionary = frame_states[from_index].get("pose", {})
    var to_pose: Dictionary = frame_states[to_index].get("pose", {})
    apply_pose_snapshot(interpolate_pose(from_pose, to_pose, blend))
    if timeline_slider != null:
        suppress_ui_events = true
        timeline_slider.set_value_no_signal(float(from_index))
        suppress_ui_events = false

func refresh_timeline() -> void:
    if timeline_slider == null:
        return
    suppress_ui_events = true
    timeline_slider.max_value = max(0, frame_states.size() - 1)
    timeline_slider.value = clampi(current_frame_index, 0, max(0, frame_states.size() - 1))
    suppress_ui_events = false
    _apply_frame(current_frame_index)
    _refresh_part_selector()

func _on_timeline_changed(value: float) -> void:
    if suppress_ui_events:
        return
    _stop_playback()
    current_frame_index = clampi(int(value), 0, max(0, frame_states.size() - 1))
    _apply_frame(current_frame_index)

func _apply_frame(index: int) -> void:
    if frame_states.is_empty() or index < 0 or index >= frame_states.size():
        return
    apply_pose_snapshot(frame_states[index]["pose"])
    var kind := "Поза" if frame_states[index].get("kind", "key") == "key" else "Твин"
    frame_label.text = "Кадр %d / %d — %s" % [index + 1, frame_states.size(), kind]
    suppress_ui_events = true
    tween_count.value = int(frame_states[index].get("tween_count", 5))
    suppress_ui_events = false
    _refresh_transform_controls()

func get_pose_snapshot() -> Dictionary:
    var snapshot: Dictionary = {}
    for part_name in puppet_parts.keys():
        var part := puppet_parts[part_name] as Node3D
        snapshot[part_name] = {"position": part.position, "rotation": part.quaternion, "scale": part.scale}
    return snapshot

func apply_pose_snapshot(snapshot: Dictionary) -> void:
    for part_name in puppet_parts.keys():
        if not snapshot.has(part_name):
            continue
        var part := puppet_parts[part_name] as Node3D
        var pose: Dictionary = snapshot[part_name]
        part.position = pose["position"]
        part.quaternion = pose["rotation"]
        part.scale = pose["scale"]

func _refresh_part_selector() -> void:
    if part_selector == null:
        return
    var previous := selected_part_name
    part_selector.clear()
    var names: Array = puppet_parts.keys()
    names.sort()
    for name in names:
        part_selector.add_item(str(name))
    if names.is_empty():
        return
    if not puppet_parts.has(previous):
        selected_part_name = str(names[0])
    else:
        selected_part_name = previous
    var selected_index := names.find(selected_part_name)
    suppress_ui_events = true
    part_selector.select(maxi(0, selected_index))
    suppress_ui_events = false
    _refresh_transform_controls()

func _on_part_selected(index: int) -> void:
    if suppress_ui_events or index < 0:
        return
    selected_part_name = part_selector.get_item_text(index)
    _refresh_transform_controls()

func _refresh_transform_controls() -> void:
    if not puppet_parts.has(selected_part_name):
        return
    var part := puppet_parts[selected_part_name] as Node3D
    suppress_ui_events = true
    _set_vector_controls("position", part.position)
    _set_vector_controls("rotation_degrees", part.rotation_degrees)
    _set_vector_controls("scale", part.scale)
    suppress_ui_events = false

func _set_vector_controls(key: String, value: Vector3) -> void:
    (transform_controls["%s_x" % key] as SpinBox).value = value.x
    (transform_controls["%s_y" % key] as SpinBox).value = value.y
    (transform_controls["%s_z" % key] as SpinBox).value = value.z

func _on_transform_changed(value: float, key: String, axis: String) -> void:
    if suppress_ui_events or not puppet_parts.has(selected_part_name):
        return
    var part := puppet_parts[selected_part_name] as Node3D
    var vector: Vector3 = part.position if key == "position" else (part.rotation_degrees if key == "rotation_degrees" else part.scale)
    if axis == "x":
        vector.x = value
    elif axis == "y":
        vector.y = value
    else:
        vector.z = value
    if key == "position":
        part.position = vector
    elif key == "rotation_degrees":
        part.rotation_degrees = vector
    else:
        part.scale = vector
    _store_current_pose()

func _on_tween_count_changed(value: float) -> void:
    if suppress_ui_events or frame_states.is_empty():
        return
    if frame_states[current_frame_index].get("kind", "key") == "key":
        frame_states[current_frame_index]["tween_count"] = int(value)

func _store_current_pose() -> void:
    if frame_states.is_empty():
        return
    frame_states[current_frame_index]["pose"] = get_pose_snapshot()

func _add_box() -> void:
    _add_primitive("Box", false)

func _add_sphere() -> void:
    _add_primitive("Sphere", true)

func _add_primitive(base_name: String, is_sphere: bool) -> void:
    var part_name := "%s%d" % [base_name, puppet_parts.size() + 1]
    puppet_parts[part_name] = make_part(part_name, Vector3(0, 1, 0), Vector3(0.6, 0.6, 0.6), Color(0.8, 0.72, 0.32), is_sphere)
    selected_part_name = part_name
    _refresh_part_selector()
    _add_key_pose()

func _reset_pose() -> void:
    _stop_playback()
    build_default_puppet()
    frame_states = [{"kind": "key", "pose": get_pose_snapshot(), "tween_count": 5}]
    current_frame_index = 0
    refresh_timeline()
    set_status("Кукла и таймлайн сброшены")

func _open_import_dialog() -> void:
    file_dialog.popup_centered_ratio(0.85)

func _on_model_selected(path: String) -> void:
    var document := GLTFDocument.new()
    var state := GLTFState.new()
    var error := document.append_from_file(path, state)
    if error != OK:
        set_status("Не удалось импортировать модель: %s" % error_string(error))
        return
    var imported := document.generate_scene(state)
    if imported == null:
        set_status("GLTF-файл не содержит сцены")
        return
    for child in puppet_root.get_children():
        child.queue_free()
    puppet_parts.clear()
    puppet_root.add_child(imported)
    imported.name = "ImportedModel"
    _collect_editable_nodes(imported)
    if puppet_parts.is_empty():
        puppet_parts["ImportedModel"] = imported
    selected_part_name = str(puppet_parts.keys()[0])
    frame_states = [{"kind": "key", "pose": get_pose_snapshot(), "tween_count": 5}]
    current_frame_index = 0
    refresh_timeline()
    set_status("Модель импортирована. Для скелетного рига импортируйте модель с костями")

func _collect_editable_nodes(node: Node) -> void:
    if node is Node3D:
        puppet_parts[str(node.name)] = node
    for child in node.get_children():
        _collect_editable_nodes(child)

func _toggle_particles() -> void:
    var existing := puppet_root.get_node_or_null("MobileParticles") as CPUParticles3D
    if existing != null:
        existing.queue_free()
        set_status("Частицы выключены")
        return
    var particles := CPUParticles3D.new()
    particles.name = "MobileParticles"
    particles.position = Vector3(0, 2.5, 0)
    particles.amount = MAX_PARTICLES
    particles.lifetime = 1.4
    particles.emitting = true
    particles.direction = Vector3(0, 1, 0)
    particles.spread = 35.0
    particles.gravity = Vector3(0, -1.5, 0)
    var particle_mesh := SphereMesh.new()
    particle_mesh.radius = 0.035
    particle_mesh.height = 0.07
    particles.mesh = particle_mesh
    puppet_root.add_child(particles)
    set_status("Лёгкие CPU-частицы включены")

func _toggle_cloth() -> void:
    if cloth_instance != null and is_instance_valid(cloth_instance):
        cloth_instance.queue_free()
        cloth_instance = null
        set_status("Ткань выключена")
        return
    cloth_instance = Node3D.new()
    cloth_instance.name = "SoftCloth"
    cloth_instance.set_script(CLOTH_SCRIPT)
    puppet_root.add_child(cloth_instance)
    set_status("Лёгкая экспериментальная симуляция ткани включена")

func save_project() -> void:
    var file := FileAccess.open(SAVE_FILE, FileAccess.WRITE)
    if file == null:
        set_status("Не удалось сохранить проект")
        return
    file.store_string(JSON.stringify({"version": 1, "fps": playback_fps, "frames": _frames_to_json()}))
    set_status("Проект сохранён в user://animation_project.json")

func _frames_to_json() -> Array:
    var output: Array = []
    for frame in frame_states:
        var pose_json: Dictionary = {}
        var pose: Dictionary = frame["pose"]
        for part_name in pose.keys():
            var item: Dictionary = pose[part_name]
            var p: Vector3 = item["position"]
            var q: Quaternion = item["rotation"]
            var s: Vector3 = item["scale"]
            pose_json[part_name] = {"p": [p.x, p.y, p.z], "q": [q.x, q.y, q.z, q.w], "s": [s.x, s.y, s.z]}
        output.append({"kind": frame.get("kind", "key"), "tween_count": frame.get("tween_count", 5), "pose": pose_json})
    return output

func load_project() -> void:
    if not FileAccess.file_exists(SAVE_FILE):
        set_status("Сохранённый проект не найден")
        return
    var file := FileAccess.open(SAVE_FILE, FileAccess.READ)
    var parser := JSON.new()
    if parser.parse(file.get_as_text()) != OK:
        set_status("Файл проекта повреждён")
        return
    var data: Dictionary = parser.data
    var loaded: Array[Dictionary] = []
    for raw_frame in data.get("frames", []):
        var pose: Dictionary = {}
        for part_name in raw_frame.get("pose", {}).keys():
            if not puppet_parts.has(part_name):
                continue
            var raw_pose: Dictionary = raw_frame["pose"][part_name]
            var p: Array = raw_pose["p"]
            var q: Array = raw_pose["q"]
            var s: Array = raw_pose["s"]
            pose[part_name] = {"position": Vector3(p[0], p[1], p[2]), "rotation": Quaternion(q[0], q[1], q[2], q[3]), "scale": Vector3(s[0], s[1], s[2])}
        loaded.append({"kind": raw_frame.get("kind", "key"), "tween_count": raw_frame.get("tween_count", 5), "pose": pose})
    if loaded.is_empty():
        set_status("В файле нет кадров, подходящих текущей модели")
        return
    frame_states = loaded
    playback_fps = float(data.get("fps", 8.0))
    current_frame_index = 0
    refresh_timeline()
    set_status("Проект загружен")

func _export_mp4() -> void:
    if frame_states.is_empty():
        set_status("Нет кадров для экспорта")
        return
    if OS.has_feature("android"):
        set_status("На Android доступен экспорт PNG-кадров; MP4 требует встроенного FFmpeg-плагина")
        await _export_png_sequence()
        return
    var ffmpeg := OS.get_environment("FFMPEG_PATH")
    if ffmpeg.is_empty():
        ffmpeg = "ffmpeg"
    var frames_dir := ProjectSettings.globalize_path("user://animation_export")
    DirAccess.make_dir_recursive_absolute(frames_dir)
    var old_pose := get_pose_snapshot()
    var old_index := current_frame_index
    var old_ui_visibility := ui_layer.visible
    _stop_playback()
    ui_layer.visible = false
    for i in range(frame_states.size()):
        _apply_frame(i)
        await RenderingServer.frame_post_draw
        var image := get_viewport().get_texture().get_image()
        var save_error := image.save_png(frames_dir.path_join("frame_%05d.png" % i))
        if save_error != OK:
            ui_layer.visible = old_ui_visibility
            apply_pose_snapshot(old_pose)
            set_status("Не удалось записать PNG-кадры")
            return
    ui_layer.visible = old_ui_visibility
    apply_pose_snapshot(old_pose)
    current_frame_index = old_index
    refresh_timeline()
    var output_video := ProjectSettings.globalize_path("user://animation_export.mp4")
    var args := PackedStringArray(["-y", "-framerate", str(int(playback_fps)), "-i", frames_dir.path_join("frame_%05d.png"), "-vf", "scale=trunc(iw/2)*2:trunc(ih/2)*2", "-c:v", "libx264", "-preset", "ultrafast", "-pix_fmt", "yuv420p", output_video])
    var process_output: Array = []
    var exit_code := OS.execute(ffmpeg, args, process_output, true)
    if exit_code == 0:
        set_status("MP4 экспортирован: user://animation_export.mp4")
    else:
        set_status("FFmpeg не найден/ошибка. PNG-кадры: user://animation_export")

func _export_png_sequence() -> void:
    var frames_dir := ProjectSettings.globalize_path("user://animation_export")
    DirAccess.make_dir_recursive_absolute(frames_dir)
    var old_pose := get_pose_snapshot()
    var old_index := current_frame_index
    var old_ui_visibility := ui_layer.visible
    ui_layer.visible = false
    for i in range(frame_states.size()):
        _apply_frame(i)
        await RenderingServer.frame_post_draw
        var image := get_viewport().get_texture().get_image()
        image.save_png(frames_dir.path_join("frame_%05d.png" % i))
    ui_layer.visible = old_ui_visibility
    apply_pose_snapshot(old_pose)
    current_frame_index = old_index
    refresh_timeline()
    set_status("Кадры сохранены в user://animation_export; MP4 на Android требует FFmpeg-плагина")
