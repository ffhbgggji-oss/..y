# Android SAF import plugin (Godot 4.2.1)

The Android plugin uses the Storage Access Framework. It opens a system document picker and copies only the selected file into the app-private files directory. It does not request broad storage permissions.

## Supported selections

- 3D model picker: `.glb` and `.gltf` are accepted by the native picker; the current Android model importer uses self-contained `.glb` files.
- 2D image picker: PNG, JPG/JPEG and WebP. The 2D editor copies the selected image into `user://CartoonStudio2D/assets/` for project persistence.

## Build and package

- Java source and Gradle library: `android-plugin/`.
- Godot editor export plugin: `addons/GodotAndroidFilePicker/`.
- CI builds `GodotAndroidFilePicker-release.aar` and stages it at `addons/GodotAndroidFilePicker/bin/release/GodotAndroidFilePicker.aar`.
- The export plugin returns the AAR path relative to `res://addons/`, as required by `EditorExportPlugin._get_android_libraries()`.
- Android export requires `gradle_build/use_gradle_build=true`.

The generated AAR is intentionally not committed. GitHub Actions creates it on every build.

## Godot and Android version alignment

The plugin compiles against `org.godotengine:godot:4.2.1.stable`; the Android Gradle build template and editor/export templates are also Godot 4.2.1 stable. Keep these versions aligned.

## Validation required

After CI creates the APK, install it on Android, test the GLB picker and image picker, and verify that selected files can be imported after the picker closes. `.gltf` files that reference external `.bin` buffers or textures still need a multi-file package importer; use a self-contained `.glb` for now.
