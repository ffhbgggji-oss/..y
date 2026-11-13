@tool
extends EditorPlugin

var export_plugin: EditorExportPlugin

func _enter_tree() -> void:
    export_plugin = AndroidFilePickerExport.new()
    add_export_plugin(export_plugin)

func _exit_tree() -> void:
    if export_plugin != null:
        remove_export_plugin(export_plugin)
        export_plugin = null

class AndroidFilePickerExport extends EditorExportPlugin:
    func _supports_platform(platform: EditorExportPlatform) -> bool:
        return platform is EditorExportPlatformAndroid

    func _get_android_libraries(platform: EditorExportPlatform, debug: bool) -> PackedStringArray:
        return PackedStringArray(["GodotAndroidFilePicker/bin/release/GodotAndroidFilePicker.aar"])

    func _get_name() -> String:
        return "GodotAndroidFilePicker"
