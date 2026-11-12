extends Node
class_name AndroidModelImporter

## Android SAF picker + desktop FileDialog. SAF copies selected content to app-private storage.
signal model_path_selected(path: String)
signal import_failed(message: String)

var desktop_dialog: FileDialog
var android_picker: Object

func _ready() -> void:
    if OS.get_name() == "Android":
        if Engine.has_singleton("GodotAndroidFilePicker"):
            android_picker = Engine.get_singleton("GodotAndroidFilePicker")
            var selected_callback := Callable(self, "_on_android_file_selected")
            var error_callback := Callable(self, "_on_android_file_error")
            if not android_picker.is_connected("file_selected", selected_callback):
                android_picker.connect("file_selected", selected_callback)
            if not android_picker.is_connected("file_picker_error", error_callback):
                android_picker.connect("file_picker_error", error_callback)
        else:
            push_warning("GodotAndroidFilePicker AAR не подключён к APK")
    else:
        desktop_dialog = FileDialog.new()
        desktop_dialog.name = "ModelFileDialog"
        desktop_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
        desktop_dialog.access = FileDialog.ACCESS_FILESYSTEM
        desktop_dialog.filters = PackedStringArray(["*.glb ; glTF Binary", "*.gltf ; glTF JSON"])
        desktop_dialog.file_selected.connect(_on_android_file_selected)
        add_child(desktop_dialog)

func open_model_picker() -> void:
    if OS.get_name() == "Android":
        if android_picker == null:
            import_failed.emit("В APK отсутствует SAF-плагин. Пересоберите APK через GitHub Actions.")
            return
        android_picker.call("open_file_picker")
    elif desktop_dialog != null:
        desktop_dialog.popup_centered_ratio(0.85)

func _on_android_file_selected(path: String) -> void:
    if path.is_empty() or not FileAccess.file_exists(path):
        import_failed.emit("Не удалось прочитать выбранный файл")
        return
    var extension := path.get_extension().to_lower()
    if extension != "glb" and extension != "gltf":
        import_failed.emit("Выберите файл .glb или .gltf")
        return
    if extension == "gltf":
        import_failed.emit("Выбран .gltf. Для надёжного импорта на Android используйте .glb: внешние .bin/текстуры пока не копируются вместе с файлом.")
        return
    model_path_selected.emit(path)

func _on_android_file_error(message: String) -> void:
    import_failed.emit(message)
