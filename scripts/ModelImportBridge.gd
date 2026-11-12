extends Node
class_name ModelImportBridge

## Redirects the existing MainStudio import button to Android SAF on Android,
## while retaining the desktop FileDialog. This controller must be a child of
## MainStudio so it can call its existing _on_model_selected(path) importer.

const IMPORT_BUTTON_TEXT := "Импорт GLB/GLTF"

var studio: Node
var importer: AndroidModelImporter

func _ready() -> void:
    studio = get_parent()
    importer = AndroidModelImporter.new()
    importer.name = "AndroidModelImporter"
    add_child(importer)
    importer.model_path_selected.connect(_on_model_path_selected)
    importer.import_failed.connect(_on_import_failed)

    # MainStudio builds its controls in its _ready(), before child _ready().
    await get_tree().process_frame
    var import_button := _find_import_button(studio)
    if import_button == null:
        _report("Кнопка импорта не найдена в интерфейсе")
        return

    var old_callback := Callable(studio, "_open_import_dialog")
    if import_button.pressed.is_connected(old_callback):
        import_button.pressed.disconnect(old_callback)
    import_button.pressed.connect(importer.open_model_picker)
    _report("Импорт готов: выберите GLB через системный диалог Android" if OS.get_name() == "Android" else "Импорт готов")

func _find_import_button(node: Node) -> Button:
    for child in node.get_children():
        if child is Button and (child as Button).text == IMPORT_BUTTON_TEXT:
            return child as Button
        var found := _find_import_button(child)
        if found != null:
            return found
    return null

func _on_model_path_selected(path: String) -> void:
    if not studio.has_method("_on_model_selected"):
        _report("В MainStudio не найден обработчик GLTF")
        return
    studio.call("_on_model_selected", path)

func _on_import_failed(message: String) -> void:
    _report("Импорт: " + message)

func _report(message: String) -> void:
    if studio != null and studio.has_method("set_status"):
        studio.call("set_status", message)
    else:
        print(message)