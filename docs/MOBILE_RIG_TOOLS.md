# Mobile rig posing and puppet-frame prototype

The rig editor has a compact original mobile animation layout: viewport, import/camera/save controls, a tool selector, and a frame/playback strip. It is not a pixel-for-pixel copy of another application.

## Bone tools

1. Import a self-contained, skinned `.glb` containing a `Skeleton3D`.
2. Tap a joint to select it. The on-screen gizmo shows the current tool.
3. Tap **Поворот ◯ / Стрелки ↔ / Масштаб □** to cycle tools. Drag in the viewport to edit the selected joint. Drag empty space when no joint is selected to orbit the camera; two fingers pinch to zoom.
4. Tap **＋ Кадр**, change the pose, add more frames, and press Play. Playback interpolates each stored frame at 24 fps by default; the editor uses a configurable authored frame rate.

Move mode translates the selected bone pose in the camera-facing plane. Scale mode uniformly scales the selected bone. These are prototype editing operations; some production skeletons may constrain or visually distort when translating/scaling joints.

## Android import and testing

The SAF plugin source is in `android-plugin/`; CI builds a matching-version AAR and stages it at `addons/GodotAndroidFilePicker/bin/release/GodotAndroidFilePicker.aar`. The enabled Godot export plugin packages it into the custom Android Gradle build. The project still needs a device run using a skinned GLB to verify the Android picker, touch hit testing, bone transforms, and playback.


## 2D mode

Tap `2D` in the top toolbar to open the 2D workspace. Add image/shape layers, use `Рисовать` for touch drawing, add joints to create a simple connected joint chain, edit X/Y/rotation/scale, then create key poses and Tween frames. Tap `3D` to return to the 3D rig workspace.
