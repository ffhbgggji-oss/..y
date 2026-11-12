# Rig animation editor architecture (Godot 4.2)

This branch adds a first modular, mobile-oriented skeletal-animation prototype. It is intentionally separate from `MainStudio.gd` so the existing timeline/editor can remain a fallback while the rig workflow is validated.

## Scene/module boundaries

- `MainStudio.gd` remains the project/bootstrap and GLB/GLTF import owner.
- `RigAnimationEditor.gd` is attached under `MainStudio`; it discovers `PuppetRoot`, the active `Camera3D`, and an imported `Skeleton3D` at runtime.
- The editor owns touch picking, bone pose edits, camera orbit/zoom, its compact mobile UI, rig/camera keyframes, playback, and `user://rig_animation.json` persistence.
- Model loading stays in the existing importer. The model must contain an actual glTF skin/armature that imports as `Skeleton3D`; unrigged meshes can only be viewed/transformed, not posed as bones.

## Touch interaction

- Tap/drag close to a projected skeleton joint to select and rotate that bone.
- Drag empty viewport space to orbit the viewer camera.
- Pinch with two fingers to zoom.
- UI strips at the top and bottom reserve gesture areas for buttons and timeline.
- Touch pose edits update the selected rig key. Tap “+ Ключ позы / камеры” to capture a new bone-and-camera pose.

## Animation/camera data

Each key stores bone-local position, quaternion rotation and scale by skeleton bone index, plus camera world position and quaternion. Playback interpolates vectors linearly and rotations with quaternion slerp. JSON is versioned and kept separate from the legacy puppet project format. Bone indices are valid only for the same model/skeleton ordering; a production format should also store skeleton/model identity and bone names, then validate/remap on load.

## UI direction

The prototype uses a compact dark, rounded mobile toolbar and a bottom timeline inspired by common animation-app workflows. It does not copy proprietary artwork/layout. A later UI pass should add selectable tool modes (pose/orbit), visible selection highlights, undo/redo, frame thumbnails, and model-specific bone hierarchy.

## Validation / next steps

1. Run the existing Godot 4.2 headless project validation and Android export workflow.
2. Test with a known small GLB that includes a skin, verify picking and bone rotations on-device.
3. Add rig identity/name-based remapping, safe archive/Storage Access Framework import for Android, undo/redo, and export of animation to glTF/PNG or MP4 via a supported Android encoder.
4. Add a proper retargeting/IK layer only after the basic per-bone keying workflow is reliable.

The prototype is not a full Blender-like rigging tool: it edits existing bone poses, and does not create rigs, edit skin weights, or provide IK/retargeting yet.


## 2D workspace

The `2D` button opens a separate layer-based editor. It supports image layers (PNG/JPG/WebP), rectangle/circle primitives, freehand Line2D strokes, transform controls, a frame slider, keyframe editing, generated Tween frames, playback FPS, and JSON save/load. The `Сустав` tool creates joint markers; joints are connected sequentially with visual Line2D bones and these links follow joint transforms. This is a lightweight puppet guide, not weighted image-mesh deformation.

## Camera, model transform and runtime skeleton display
- The editor now creates two independent cameras: `Camera3D` for animation keyframes and `ExportCamera3D` for a fixed export composition.
- Use `Камера: Анимация` / `Камера: Экспорт` to choose the viewport camera. Orbit and pinch zoom affect only the selected camera. Export camera framing is saved in `user://cartoonstudio_export_camera.cfg` and is not inserted into animation keyframes.
- `Камера ↑` / `Камера ↓` moves the selected camera's look-at target vertically. Vertical finger drag still changes camera elevation.
- `Кости: Вкл/Выкл` displays the imported skeleton as runtime bone lines. The selected bone is highlighted.
- The `Ось` selector constrains bone move/rotate/scale operations to screen plane or X/Y/Z. Model transform controls apply position, rotation, or scale to the imported model root.
- These additions have been statically inspected but still require a Godot 4.2.1 Android build and on-device interaction test. The export camera is a separate composition camera; a video-render/export pipeline is not added by this change.
- Touch gestures: one finger orbits the active camera; two fingers pan the camera target and pinch to zoom.
