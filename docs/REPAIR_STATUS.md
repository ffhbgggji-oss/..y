# CartoonStudio repair and implementation status

## Implemented in this pass

- Added a dedicated 2D workspace accessible from the 3D toolbar.
- Added image layers (PNG/JPG/WebP), rectangle/circle layers, touch/mouse drawing, transform controls, frame strip, keyframe editing, duplicate/delete, generated Tween frames, FPS playback, and local JSON save/load.
- Added simple 2D joint markers and visual bone links. Links follow the animated joint positions. This is a lightweight 2D puppet guide, not mesh deformation/skin weighting.
- Extended the Android SAF plugin with a separate image picker signal and image-only document selection.
- Added a valid project icon and configured `application/config/icon`, addressing Android export's attempt to load an empty project icon path.
- Replaced invalid Android architecture/keystore preset keys with Godot 4.2.1 option names.
- Corrected the Gradle template preparation to create `android/.build_version` containing `4.2.1.stable` and `android/build/.gdignore` before extracting `android_source.zip`.
- Updated GitHub Actions to verify the template files, generate a temporary debug keystore, export the APK, check ZIP integrity and verify its signature.

## Existing 3D features retained

- GLB import, Skeleton3D bone selection, rotate/move/scale tools, camera orbit/pinch, keyframes, Tween generation, quaternion slerp playback and JSON save/load.

## Not yet verified

- This environment does not have Godot 4.2.1 or Android SDK installed and cannot download the engine binary, so it cannot execute Godot's GDScript parser or build an APK locally.
- The GitHub Actions workflow must run to verify Gradle, Android plugin packaging and APK export end-to-end.
- A successful CI export still needs a real Android install test for touch layout, SAF permissions, image decoding, GLB loading and playback.

## Known scope limits

- 2D bones are visual joint links; image mesh deformation and weighted skinning are not implemented.
- 3D models must already contain a valid Skeleton3D and skin weights.
- Android model import currently supports self-contained GLB; multi-file GLTF packages are not imported yet.
- MP4 export is not implemented on Android; desktop export depends on FFmpeg.
