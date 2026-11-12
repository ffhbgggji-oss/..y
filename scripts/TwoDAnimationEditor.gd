extends Node

const TWEEN_2D = preload("res://scripts/Tween2D.gd")
const SAVE_PATH := "user://cartoonstudio_2d.json"
const ASSET_DIR := "user://CartoonStudio2D/assets"
const MAX_TWEEN_FRAMES := 120

var studio: Node3D
var mobile_ui: CanvasLayer
var active := false
var playing := false
var fps := 24.0
var playback_phase := 0.0
var world_layer: CanvasLayer
var stage_root: Node2D
var stage_background: Polygon2D
var ui_layer: CanvasLayer
var status_label: Label
var timeline_slider: HSlider
var frame_label: Label
var layer_selector: OptionButton
var tween_count: SpinBox
var fps_box: SpinBox
var x_box: SpinBox
var y_box: SpinBox
var rotation_box: SpinBox
var scale_box: SpinBox
var play_button: Button
var image_dialog: FileDialog
var android_picker: Object
var parts: Dictionary = {}
var joint_nodes: Array[Node2D] = []
var bone_links: Array[Dictionary] = []
var frames: Array[Dictionary] = []
var current_frame := 0
var selected_name := ""
var next_part_id := 1
var draw_mode := false
var pointer_down := false
var drawing_line: Line2D
var dragged_part: Node2D
var drag_offset := Vector2.ZERO
var suppress_controls := false

func configure(main_studio: Node3D, ui: CanvasLayer) -> void:
    studio = main_studio
    mobile_ui = ui
    _build_world()
    _build_ui()
    _connect_android_picker()
    frames.append({"kind": "key", "pose": _capture_pose()})
    _refresh_timeline()
    set_active(false)

func _build_world() -> void:
    world_layer = CanvasLayer.new()
    world_layer.name = "TwoDWorldLayer"
    world_layer.layer = 1
    studio.add_child(world_layer)
    stage_root = Node2D.new()
    stage_root.name = "TwoDStage"
    world_layer.add_child(stage_root)
    stage_background = Polygon2D.new()
    stage_background.name = "CanvasBackground"
    var viewport_size := get_viewport().get_visible_rect().size
    stage_background.polygon = PackedVector2Array([
        Vector2(12, 84), Vector2(viewport_size.x - 12, 84),
        Vector2(viewport_size.x - 12, viewport_size.y - 190), Vector2(12, viewport_size.y - 190)
    ])
    stage_background.color = Color("f1f3f8")
    stage_background.z_index = -100
    stage_root.add_child(stage_background)
    for x in range(32, int(viewport_size.x), 32):
        var line := Line2D.new()
        line.points = PackedVector2Array([Vector2(x, 84), Vector2(x, viewport_size.y - 190)])
        line.width = 1.0
        line.default_color = Color(0.2, 0.25, 0.35, 0.055)
        line.z_index = -99
        stage_root.add_child(line)
    for y in range(96, int(viewport_size.y - 190), 32):
        var line := Line2D.new()
        line.points = PackedVector2Array([Vector2(12, y), Vector2(viewport_size.x - 12, y)])
        line.width = 1.0
        line.default_color = Color(0.2, 0.25, 0.35, 0.055)
        line.z_index = -99
        stage_root.add_child(line)
    world_layer.visible = false

func _build_ui() -> void:
    ui_layer = CanvasLayer.new()
    ui_layer.name = "TwoDEditorUI"
    ui_layer.layer = 10
    studio.add_child(ui_layer)
    var root := Control.new()
    root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    root.mouse_filter = Control.MOUSE_FILTER_PASS
    ui_layer.add_child(root)

    var top := PanelContainer.new()
    top.anchor_right = 1.0
    top.offset_left = 8
    top.offset_top = 8
    top.offset_right = -8
    top.offset_bottom = 76
    root.add_child(top)
    var top_row := HFlowContainer.new()
    top.add_child(top_row)
    var title := Label.new()
    title.text = "CARTOONSTUDIO  ·  2D"
    title.custom_minimum_size = Vector2(190, 38)
    top_row.add_child(title)
    _button(top_row, "3D", _exit_mode)
    _button(top_row, "+ Изображение", _open_image_picker)
    _button(top_row, "Прямоугольник", _add_rectangle)
    _button(top_row, "Круг", _add_circle)
    _button(top_row, "Сустав", _add_joint)
    var draw_button := _button(top_row, "Рисовать", _toggle_draw)
    draw_button.name = "DrawModeButton"
    _button(top_row, "Удалить слой", _delete_selected_part)
    _button(top_row, "Сохранить", _save_project)
    _button(top_row, "Загрузить", _load_project)

    var bottom := PanelContainer.new()
    bottom.anchor_top = 1.0
    bottom.anchor_right = 1.0
    bottom.anchor_bottom = 1.0
    bottom.offset_left = 8
    bottom.offset_top = -190
    bottom.offset_right = -8
    bottom.offset_bottom = -8
    root.add_child(bottom)
    var layout := VBoxContainer.new()
    bottom.add_child(layout)

    var layer_row := HFlowContainer.new()
    layout.add_child(layer_row)
    var layer_label := Label.new()
    layer_label.text = "Слой:"
    layer_row.add_child(layer_label)
    layer_selector = OptionButton.new()
    layer_selector.custom_minimum_size.x = 150
    layer_selector.item_selected.connect(_on_layer_selected)
    layer_row.add_child(layer_selector)
    x_box = _spin(layer_row, "X", -2000, 3000, 1, _on_transform_changed)
    y_box = _spin(layer_row, "Y", -2000, 3000, 1, _on_transform_changed)
    rotation_box = _spin(layer_row, "Угол", -360, 360, 1, _on_transform_changed)
    scale_box = _spin(layer_row, "Масштаб", 0.05, 8, 0.05, _on_transform_changed)

    var actions := HFlowContainer.new()
    layout.add_child(actions)
    play_button = _button(actions, "▶", _toggle_playback)
    _button(actions, "+ Кадр", _add_key_frame)
    _button(actions, "Дубль", _duplicate_frame)
    _button(actions, "Удалить кадр", _delete_frame)
    tween_count = SpinBox.new()
    tween_count.min_value = 1
    tween_count.max_value = MAX_TWEEN_FRAMES
    tween_count.step = 1
    tween_count.value = 12
    tween_count.custom_minimum_size.x = 76
    actions.add_child(tween_count)
    _button(actions, "Создать Tween", _generate_tweens)
    fps_box = SpinBox.new()
    fps_box.min_value = 1
    fps_box.max_value = 60
    fps_box.step = 1
    fps_box.value = fps
    fps_box.prefix = "FPS "
    fps_box.custom_minimum_size.x = 100
    fps_box.value_changed.connect(func(value: float): fps = value)
    actions.add_child(fps_box)

    frame_label = Label.new()
    layout.add_child(frame_label)
    timeline_slider = HSlider.new()
    timeline_slider.min_value = 0
    timeline_slider.max_value = 0
    timeline_slider.step = 1
    timeline_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    timeline_slider.value_changed.connect(_on_timeline_changed)
    layout.add_child(timeline_slider)
    status_label = Label.new()
    status_label.text = "Добавьте изображение, фигуру или нарисуйте слой."
    status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    layout.add_child(status_label)

    image_dialog = FileDialog.new()
    image_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
    image_dialog.access = FileDialog.ACCESS_FILESYSTEM
    image_dialog.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp ; Images"])
    image_dialog.file_selected.connect(_on_image_selected)
    ui_layer.add_child(image_dialog)
    ui_layer.visible = false

func _button(parent: Control, caption: String, callback: Callable) -> Button:
    var button := Button.new()
    button.text = caption
    button.custom_minimum_size = Vector2(84, 38)
    button.pressed.connect(callback)
    parent.add_child(button)
    return button

func _spin(parent: Control, caption: String, minimum: float, maximum: float, step: float, callback: Callable) -> SpinBox:
    var box := SpinBox.new()
    box.min_value = minimum
    box.max_value = maximum
    box.step = step
    box.custom_minimum_size.x = 92
    box.prefix = caption + " "
    box.value_changed.connect(callback)
    parent.add_child(box)
    return box

func _connect_android_picker() -> void:
    if OS.get_name() != "Android" or not Engine.has_singleton("GodotAndroidFilePicker"):
        return
    android_picker = Engine.get_singleton("GodotAndroidFilePicker")
    var callback := Callable(self, "_on_image_selected")
    if android_picker.has_signal("image_selected") and not android_picker.is_connected("image_selected", callback):
        android_picker.connect("image_selected", callback)

func set_active(value: bool) -> void:
    active = value
    if world_layer != null:
        world_layer.visible = value
    if ui_layer != null:
        ui_layer.visible = value
    if mobile_ui != null:
        mobile_ui.visible = not value
    if studio != null:
        var puppet := studio.get_node_or_null("PuppetRoot") as Node3D
        if puppet != null:
            puppet.visible = not value
    if value:
        _refresh_timeline()
        _set_status("2D-редактор: слои, рисование, кадры и автоматические Tween")

func _exit_mode() -> void:
    _stop_playback()
    set_active(false)

func _process(delta: float) -> void:
    if not active or not playing or frames.size() < 2:
        return
    playback_phase = fposmod(playback_phase + delta * fps, float(frames.size()))
    var from_index := int(floor(playback_phase))
    var to_index := (from_index + 1) % frames.size()
    var weight := playback_phase - float(from_index)
    var a: Dictionary = frames[from_index].get("pose", {})
    var b: Dictionary = frames[to_index].get("pose", {})
    _apply_pose(TWEEN_2D.interpolate_pose(a, b, weight))
    current_frame = from_index
    _update_timeline_display()

func _input(event: InputEvent) -> void:
    if not active or playing:
        return
    if event is InputEventScreenTouch:
        var touch := event as InputEventScreenTouch
        if touch.pressed:
            _pointer_down(touch.position)
        else:
            _pointer_up()
    elif event is InputEventScreenDrag:
        _pointer_move((event as InputEventScreenDrag).position)
    elif event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
        if (event as InputEventMouseButton).pressed:
            _pointer_down((event as InputEventMouseButton).position)
        else:
            _pointer_up()
    elif event is InputEventMouseMotion and pointer_down:
        _pointer_move((event as InputEventMouseMotion).position)

func _pointer_down(screen_position: Vector2) -> void:
    var size := get_viewport().get_visible_rect().size
    if screen_position.y < 82.0 or screen_position.y > size.y - 198.0:
        return
    pointer_down = true
    if draw_mode:
        drawing_line = Line2D.new()
        drawing_line.name = "Drawing%d" % next_part_id
        next_part_id += 1
        drawing_line.width = 7.0
        drawing_line.default_color = Color("24314a")
        drawing_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
        drawing_line.end_cap_mode = Line2D.LINE_CAP_ROUND
        drawing_line.position = screen_position
        drawing_line.points = PackedVector2Array([Vector2.ZERO])
        stage_root.add_child(drawing_line)
        _register_part(drawing_line, "draw")
        dragged_part = drawing_line
        selected_name = str(drawing_line.name)
        return
    dragged_part = _pick_part(screen_position)
    if dragged_part != null:
        selected_name = str(dragged_part.name)
        drag_offset = dragged_part.position - screen_position
        _refresh_layer_selector()
        _refresh_transform_controls()

func _pointer_move(screen_position: Vector2) -> void:
    if not pointer_down:
        return
    if drawing_line != null and is_instance_valid(drawing_line):
        var points := drawing_line.points
        var local_position := drawing_line.to_local(screen_position)
        if points.is_empty() or points[points.size() - 1].distance_to(local_position) >= 2.0:
            points.append(local_position)
            drawing_line.points = points
    elif dragged_part != null and is_instance_valid(dragged_part):
        dragged_part.position = screen_position + drag_offset
        _sync_bones()
        _store_current_frame()
        _refresh_transform_controls()

func _pointer_up() -> void:
    pointer_down = false
    drawing_line = null
    dragged_part = null
    if active and not playing:
        _store_current_frame()

func _pick_part(point: Vector2) -> Node2D:
    var keys: Array = parts.keys()
    keys.reverse()
    for key in keys:
        var node := parts[key] as Node2D
        if not is_instance_valid(node):
            continue
        var local_point := node.to_local(point)
        if node is Sprite2D:
            var sprite := node as Sprite2D
            if sprite.texture != null and sprite.get_rect().has_point(local_point):
                return node
        elif node is Polygon2D:
            if Geometry2D.is_point_in_polygon(local_point, (node as Polygon2D).polygon):
                return node
        elif node is Line2D:
            var line := node as Line2D
            for p in line.points:
                if p.distance_to(local_point) < 24.0:
                    return node
    return null

func _register_part(node: Node2D, kind: String) -> void:
    parts[str(node.name)] = node
    node.set_meta("kind", kind)
    if kind == "joint" and not joint_nodes.has(node):
        joint_nodes.append(node)
    var initial_pose := {"position": node.position, "rotation": node.rotation, "scale": node.scale}
    for frame in frames:
        var frame_pose: Dictionary = frame.get("pose", {})
        if not frame_pose.has(str(node.name)):
            frame_pose[str(node.name)] = initial_pose.duplicate(true)
    selected_name = str(node.name)
    _refresh_layer_selector()
    _refresh_transform_controls()
    _store_current_frame()
    _sync_bones()

func _add_rectangle() -> void:
    var polygon := Polygon2D.new()
    polygon.name = "Rectangle%d" % next_part_id
    next_part_id += 1
    polygon.position = _canvas_center()
    polygon.polygon = PackedVector2Array([Vector2(-75, -50), Vector2(75, -50), Vector2(75, 50), Vector2(-75, 50)])
    polygon.color = Color("5c8fe8")
    stage_root.add_child(polygon)
    _register_part(polygon, "rectangle")
    _set_status("Добавлен прямоугольный слой")

func _add_circle() -> void:
    var polygon := Polygon2D.new()
    polygon.name = "Circle%d" % next_part_id
    next_part_id += 1
    polygon.position = _canvas_center()
    var points := PackedVector2Array()
    for i in range(40):
        var angle := TAU * float(i) / 40.0
        points.append(Vector2(cos(angle), sin(angle)) * 58.0)
    polygon.polygon = points
    polygon.color = Color("f0a45b")
    stage_root.add_child(polygon)
    _register_part(polygon, "circle")
    _set_status("Добавлен круглый слой")

func _add_joint() -> void:
    var joint := Polygon2D.new()
    joint.name = "Joint%d" % next_part_id
    next_part_id += 1
    joint.position = _canvas_center() + Vector2(float(joint_nodes.size()) * 42.0, 0.0)
    var points := PackedVector2Array()
    for i in range(24):
        var angle := TAU * float(i) / 24.0
        points.append(Vector2(cos(angle), sin(angle)) * 12.0)
    joint.polygon = points
    joint.color = Color("ffd45c")
    joint.z_index = 20
    stage_root.add_child(joint)
    _register_part(joint, "joint")
    if joint_nodes.size() >= 2:
        _create_bone_link(joint_nodes[joint_nodes.size() - 2], joint)
    _set_status("Сустав добавлен. Суставы соединяются костями по порядку создания.")

func _create_bone_link(a: Node2D, b: Node2D) -> void:
    if not is_instance_valid(a) or not is_instance_valid(b):
        return
    var line := Line2D.new()
    line.name = "Bone_%s_%s" % [a.name, b.name]
    line.width = 5.0
    line.default_color = Color("63718a")
    line.z_index = 10
    line.points = PackedVector2Array([a.position, b.position])
    stage_root.add_child(line)
    bone_links.append({"a": str(a.name), "b": str(b.name), "line": line})
    line.show_behind_parent = true
    _sync_bones()

func _sync_bones() -> void:
    for link in bone_links:
        var a_name := str(link.get("a", ""))
        var b_name := str(link.get("b", ""))
        if not parts.has(a_name) or not parts.has(b_name):
            continue
        var a := parts[a_name] as Node2D
        var b := parts[b_name] as Node2D
        var line := link.get("line") as Line2D
        if is_instance_valid(a) and is_instance_valid(b) and is_instance_valid(line):
            line.points = PackedVector2Array([a.position, b.position])

func _toggle_draw() -> void:
    draw_mode = not draw_mode
    var button := ui_layer.find_child("DrawModeButton", true, false) as Button
    if button != null:
        button.text = "Рисование: ВКЛ" if draw_mode else "Рисовать"
    _set_status("Рисуйте пальцем по холсту" if draw_mode else "Выбор и перемещение слоёв")

func _delete_selected_part() -> void:
    if selected_name.is_empty() or not parts.has(selected_name):
        _set_status("Сначала выберите слой")
        return
    var node := parts[selected_name] as Node2D
    if is_instance_valid(node):
        node.queue_free()
    parts.erase(selected_name)
    var kept_joints: Array[Node2D] = []
    for joint_node in joint_nodes:
        if is_instance_valid(joint_node) and str(joint_node.name) != selected_name:
            kept_joints.append(joint_node)
    joint_nodes = kept_joints
    for link_index in range(bone_links.size() - 1, -1, -1):
        var link: Dictionary = bone_links[link_index]
        if str(link.get("a", "")) == selected_name or str(link.get("b", "")) == selected_name:
            var link_line := link.get("line") as Line2D
            if is_instance_valid(link_line):
                link_line.queue_free()
            bone_links.remove_at(link_index)
    for frame in frames:
        var pose: Dictionary = frame.get("pose", {})
        pose.erase(selected_name)
    selected_name = ""
    _refresh_layer_selector()
    _store_current_frame()
    _set_status("Слой удалён")

func _open_image_picker() -> void:
    if OS.get_name() == "Android":
        if android_picker != null and android_picker.has_method("open_image_picker"):
            android_picker.call("open_image_picker")
        else:
            _set_status("Android Photo Picker недоступен: пересоберите APK с обновлённым плагином")
    else:
        image_dialog.popup_centered_ratio(0.85)

func _on_image_selected(path: String) -> void:
    if path.is_empty() or not FileAccess.file_exists(path):
        _set_status("Не удалось открыть изображение")
        return
    var extension := path.get_extension().to_lower()
    if not (extension in ["png", "jpg", "jpeg", "webp"]):
        _set_status("Поддерживаются PNG, JPG и WebP")
        return
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(ASSET_DIR))
    var destination := ASSET_DIR.path_join("image_%d.%s" % [next_part_id, extension])
    var source := FileAccess.open(path, FileAccess.READ)
    if source == null:
        _set_status("Не удалось прочитать изображение")
        return
    var bytes := source.get_buffer(source.get_length())
    source.close()
    var target := FileAccess.open(destination, FileAccess.WRITE)
    if target == null:
        _set_status("Не удалось сохранить изображение в проект")
        return
    target.store_buffer(bytes)
    target.close()
    var image := Image.new()
    var error := image.load(destination)
    if error != OK:
        _set_status("Формат изображения не удалось декодировать")
        return
    var sprite := Sprite2D.new()
    sprite.name = "Image%d" % next_part_id
    next_part_id += 1
    sprite.texture = ImageTexture.create_from_image(image)
    sprite.position = _canvas_center()
    var longest := maxf(float(image.get_width()), float(image.get_height()))
    if longest > 420.0:
        sprite.scale = Vector2.ONE * (420.0 / longest)
    sprite.set_meta("asset_path", destination)
    stage_root.add_child(sprite)
    _register_part(sprite, "image")
    _set_status("Изображение добавлено как отдельный слой")

func _canvas_center() -> Vector2:
    var size := get_viewport().get_visible_rect().size
    return Vector2(size.x * 0.5, (size.y - 100.0) * 0.5)

func _capture_pose() -> Dictionary:
    var pose: Dictionary = {}
    for key in parts.keys():
        var node := parts[key] as Node2D
        if is_instance_valid(node):
            pose[str(key)] = {"position": node.position, "rotation": node.rotation, "scale": node.scale}
    return pose

func _apply_pose(pose: Dictionary) -> void:
    for key in pose.keys():
        if not parts.has(key):
            continue
        var node := parts[key] as Node2D
        var item: Dictionary = pose[key]
        node.position = item.get("position", node.position)
        node.rotation = float(item.get("rotation", node.rotation))
        node.scale = item.get("scale", node.scale)
    _refresh_transform_controls()
    _sync_bones()

func _store_current_frame() -> void:
    if frames.is_empty() or playing:
        return
    frames[current_frame]["pose"] = _capture_pose()

func _add_key_frame() -> void:
    _stop_playback()
    frames.insert(current_frame + 1, {"kind": "key", "pose": _capture_pose()})
    current_frame += 1
    _refresh_timeline()
    _set_status("Добавлен ключевой кадр")

func _duplicate_frame() -> void:
    _stop_playback()
    frames.insert(current_frame + 1, frames[current_frame].duplicate(true))
    current_frame += 1
    _apply_pose(frames[current_frame].get("pose", {}))
    _refresh_timeline()

func _delete_frame() -> void:
    if frames.size() <= 1:
        _set_status("Нельзя удалить последний кадр")
        return
    _stop_playback()
    frames.remove_at(current_frame)
    current_frame = clampi(current_frame, 0, frames.size() - 1)
    _apply_pose(frames[current_frame].get("pose", {}))
    _refresh_timeline()

func _generate_tweens() -> void:
    _stop_playback()
    if frames.size() < 2 or frames[current_frame].get("kind", "key") == "tween":
        _set_status("Выберите ключевой кадр, после которого есть следующая поза")
        return
    var end_index := -1
    for i in range(current_frame + 1, frames.size()):
        if frames[i].get("kind", "key") != "tween":
            end_index = i
            break
    if end_index < 0:
        _set_status("Сначала добавьте следующую ключевую позу")
        return
    var start_pose: Dictionary = frames[current_frame].get("pose", {})
    var end_pose: Dictionary = frames[end_index].get("pose", {})
    var generated := TWEEN_2D.make_tween_frames(start_pose, end_pose, int(tween_count.value))
    for i in range(end_index - 1, current_frame, -1):
        frames.remove_at(i)
    for i in range(generated.size()):
        frames.insert(current_frame + 1 + i, {"kind": "tween", "pose": generated[i]})
    current_frame += 1
    _apply_pose(frames[current_frame].get("pose", {}))
    _refresh_timeline()
    _set_status("Создано %d автоматических Tween-кадров" % generated.size())

func _toggle_playback() -> void:
    if frames.size() < 2:
        _set_status("Добавьте минимум два кадра")
        return
    playing = not playing
    playback_phase = float(current_frame)
    play_button.text = "⏸" if playing else "▶"

func _stop_playback() -> void:
    playing = false
    if play_button != null:
        play_button.text = "▶"

func _on_timeline_changed(value: float) -> void:
    _stop_playback()
    current_frame = clampi(int(value), 0, frames.size() - 1)
    _apply_pose(frames[current_frame].get("pose", {}))
    _refresh_timeline()

func _refresh_timeline() -> void:
    _update_timeline_display()
    _refresh_layer_selector()
    _refresh_transform_controls()

func _update_timeline_display() -> void:
    if timeline_slider == null or frames.is_empty():
        return
    timeline_slider.max_value = maxi(0, frames.size() - 1)
    timeline_slider.set_value_no_signal(current_frame)
    var kind := "Tween" if frames[current_frame].get("kind", "key") == "tween" else "Ключ"
    frame_label.text = "%s  %d / %d" % [kind, current_frame + 1, frames.size()]

func _refresh_layer_selector() -> void:
    if layer_selector == null:
        return
    layer_selector.clear()
    var keys: Array = parts.keys()
    keys.sort()
    for key in keys:
        layer_selector.add_item(str(key))
    if keys.is_empty():
        selected_name = ""
        return
    if not parts.has(selected_name):
        selected_name = str(keys[0])
    layer_selector.select(maxi(0, keys.find(selected_name)))

func _on_layer_selected(index: int) -> void:
    if index < 0 or index >= layer_selector.item_count:
        return
    selected_name = layer_selector.get_item_text(index)
    _refresh_transform_controls()

func _refresh_transform_controls() -> void:
    if not parts.has(selected_name):
        return
    var node := parts[selected_name] as Node2D
    if not is_instance_valid(node):
        return
    suppress_controls = true
    x_box.set_value_no_signal(node.position.x)
    y_box.set_value_no_signal(node.position.y)
    rotation_box.set_value_no_signal(rad_to_deg(node.rotation))
    scale_box.set_value_no_signal(node.scale.x)
    suppress_controls = false

func _on_transform_changed(_value: float) -> void:
    if suppress_controls or not parts.has(selected_name):
        return
    var node := parts[selected_name] as Node2D
    node.position = Vector2(x_box.value, y_box.value)
    node.rotation = deg_to_rad(rotation_box.value)
    node.scale = Vector2.ONE * scale_box.value
    _sync_bones()
    _store_current_frame()

func _save_project() -> void:
    _store_current_frame()
    var serialized_parts: Array = []
    for key in parts.keys():
        var node := parts[key] as Node2D
        if not is_instance_valid(node):
            continue
        var kind := str(node.get_meta("kind", "rectangle"))
        var data: Dictionary = {"name": str(key), "kind": kind}
        if node is Sprite2D:
            data["asset_path"] = str(node.get_meta("asset_path", ""))
        elif node is Polygon2D:
            data["color"] = (node as Polygon2D).color.to_html(true)
        elif node is Line2D:
            var points: Array = []
            for point in (node as Line2D).points:
                points.append([point.x, point.y])
            data["points"] = points
            data["color"] = (node as Line2D).default_color.to_html(true)
            data["width"] = (node as Line2D).width
        serialized_parts.append(data)
    var encoded_frames: Array = []
    for frame in frames:
        var encoded_pose: Dictionary = {}
        var pose: Dictionary = frame.get("pose", {})
        for key in pose.keys():
            var item: Dictionary = pose[key]
            var p: Vector2 = item.get("position", Vector2.ZERO)
            var s: Vector2 = item.get("scale", Vector2.ONE)
            encoded_pose[str(key)] = {"p": [p.x, p.y], "r": float(item.get("rotation", 0.0)), "s": [s.x, s.y]}
        encoded_frames.append({"kind": frame.get("kind", "key"), "pose": encoded_pose})
    var serialized_bones: Array = []
    for link in bone_links:
        serialized_bones.append({"a": link.get("a", ""), "b": link.get("b", "")})
    var payload := {"version": 1, "fps": fps, "parts": serialized_parts, "bones": serialized_bones, "frames": encoded_frames}
    var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
    if file == null:
        _set_status("Не удалось сохранить проект")
        return
    file.store_string(JSON.stringify(payload))
    _set_status("2D-проект сохранён")

func _load_project() -> void:
    if not FileAccess.file_exists(SAVE_PATH):
        _set_status("Сохранённый 2D-проект не найден")
        return
    var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
    if file == null:
        _set_status("Не удалось открыть проект")
        return
    var parser := JSON.new()
    if parser.parse(file.get_as_text()) != OK or not (parser.data is Dictionary):
        _set_status("Файл проекта повреждён")
        return
    var data: Dictionary = parser.data
    _clear_parts()
    await get_tree().process_frame
    for raw in data.get("parts", []):
        _restore_part(raw)
    for raw_bone in data.get("bones", []):
        var a_name := str(raw_bone.get("a", ""))
        var b_name := str(raw_bone.get("b", ""))
        if parts.has(a_name) and parts.has(b_name):
            _create_bone_link(parts[a_name], parts[b_name])
    frames.clear()
    for raw_frame in data.get("frames", []):
        var pose: Dictionary = {}
        var raw_pose: Dictionary = raw_frame.get("pose", {})
        for key in raw_pose.keys():
            var item: Dictionary = raw_pose[key]
            var p: Array = item.get("p", [0.0, 0.0])
            var s: Array = item.get("s", [1.0, 1.0])
            if p.size() >= 2 and s.size() >= 2:
                pose[str(key)] = {"position": Vector2(p[0], p[1]), "rotation": float(item.get("r", 0.0)), "scale": Vector2(s[0], s[1])}
        frames.append({"kind": raw_frame.get("kind", "key"), "pose": pose})
    if frames.is_empty():
        frames.append({"kind": "key", "pose": _capture_pose()})
    fps = float(data.get("fps", 24.0))
    fps_box.value = fps
    current_frame = 0
    next_part_id = parts.size() + 1
    _apply_pose(frames[0].get("pose", {}))
    _refresh_timeline()
    _set_status("2D-проект загружен")

func _restore_part(data: Dictionary) -> void:
    var kind := str(data.get("kind", "rectangle"))
    var node: Node2D
    if kind == "image":
        var path := str(data.get("asset_path", ""))
        var image := Image.new()
        if path.is_empty() or image.load(path) != OK:
            return
        var sprite := Sprite2D.new()
        sprite.texture = ImageTexture.create_from_image(image)
        sprite.set_meta("asset_path", path)
        node = sprite
    elif kind == "circle" or kind == "rectangle" or kind == "joint":
        var polygon := Polygon2D.new()
        if kind == "joint":
            var joint_points := PackedVector2Array()
            for i in range(24):
                var joint_angle := TAU * float(i) / 24.0
                joint_points.append(Vector2(cos(joint_angle), sin(joint_angle)) * 12.0)
            polygon.polygon = joint_points
            polygon.z_index = 20
        elif kind == "circle":
            var points := PackedVector2Array()
            for i in range(40):
                var angle := TAU * float(i) / 40.0
                points.append(Vector2(cos(angle), sin(angle)) * 58.0)
            polygon.polygon = points
        else:
            polygon.polygon = PackedVector2Array([Vector2(-75, -50), Vector2(75, -50), Vector2(75, 50), Vector2(-75, 50)])
        polygon.color = Color.from_string(str(data.get("color", "5c8fe8")), Color("5c8fe8"))
        node = polygon
    elif kind == "draw":
        var line := Line2D.new()
        var points := PackedVector2Array()
        for point in data.get("points", []):
            if point is Array and point.size() >= 2:
                points.append(Vector2(point[0], point[1]))
        line.points = points
        line.width = float(data.get("width", 7.0))
        line.default_color = Color.from_string(str(data.get("color", "24314a")), Color("24314a"))
        node = line
    else:
        return
    node.name = str(data.get("name", "Layer%d" % next_part_id))
    next_part_id += 1
    node.set_meta("kind", kind)
    stage_root.add_child(node)
    parts[str(node.name)] = node
    if kind == "joint":
        joint_nodes.append(node)

func _clear_parts() -> void:
    for link in bone_links:
        var line := link.get("line") as Line2D
        if is_instance_valid(line):
            line.queue_free()
    bone_links.clear()
    joint_nodes.clear()
    for key in parts.keys():
        var node := parts[key] as Node2D
        if is_instance_valid(node):
            node.queue_free()
    parts.clear()

func _set_status(message: String) -> void:
    if status_label != null:
        status_label.text = message
