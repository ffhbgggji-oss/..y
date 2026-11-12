package org.godotengine.plugin.filepicker;

import android.app.Activity;
import android.content.Intent;
import android.net.Uri;
import android.os.Environment;
import android.provider.DocumentsContract;
import android.util.Log;

import org.godotengine.godot.Godot;
import org.godotengine.godot.plugin.GodotPlugin;
import org.godotengine.godot.plugin.SignalInfo;
import org.godotengine.godot.plugin.UsedByGodot;

import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.util.Collections;
import java.util.HashSet;
import java.util.Set;

/**
 * SAF document picker for user-selected GLB/GLTF files.
 * The selected content URI is copied immediately to app-private storage; no
 * broad storage permission is requested or needed.
 */
public final class GodotAndroidFilePicker extends GodotPlugin {
    private static final String TAG = "GodotFilePicker";
    private static final int OPEN_DOCUMENT_REQUEST = 42042;
    private static final int OPEN_IMAGE_REQUEST = 42043;

    public GodotAndroidFilePicker(Godot godot) {
        super(godot);
    }

    @Override
    public String getPluginName() {
        return "GodotAndroidFilePicker";
    }

    @Override
    public Set<SignalInfo> getPluginSignals() {
        Set<SignalInfo> signals = new HashSet<>();
        signals.add(new SignalInfo("file_selected", String.class));
        signals.add(new SignalInfo("file_picker_error", String.class));
        signals.add(new SignalInfo("image_selected", String.class));
        return Collections.unmodifiableSet(signals);
    }

    @UsedByGodot
    public void open_file_picker() {
        Activity activity = getActivity();
        activity.runOnUiThread(() -> {
            Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
            intent.addCategory(Intent.CATEGORY_OPENABLE);
            intent.setType("*/*");
            intent.putExtra(Intent.EXTRA_MIME_TYPES, new String[] {
                "model/gltf-binary",
                "model/gltf+json",
                "application/octet-stream",
                "application/gltf-buffer"
            });
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
            try {
                activity.startActivityForResult(intent, OPEN_DOCUMENT_REQUEST);
            } catch (Exception exception) {
                emitSignal("file_picker_error", exception.getMessage() == null ? "Unable to open Android file picker" : exception.getMessage());
            }
        });
    }

    @UsedByGodot
    public void open_image_picker() {
        Activity activity = getActivity();
        activity.runOnUiThread(() -> {
            Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
            intent.addCategory(Intent.CATEGORY_OPENABLE);
            intent.setType("image/*");
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
            try {
                activity.startActivityForResult(intent, OPEN_IMAGE_REQUEST);
            } catch (Exception exception) {
                emitSignal("file_picker_error", exception.getMessage() == null ? "Unable to open Android image picker" : exception.getMessage());
            }
        });
    }

    @Override
    public void onMainActivityResult(int requestCode, int resultCode, Intent data) {
        if (requestCode != OPEN_DOCUMENT_REQUEST && requestCode != OPEN_IMAGE_REQUEST) {
            super.onMainActivityResult(requestCode, resultCode, data);
            return;
        }
        if (resultCode != Activity.RESULT_OK || data == null || data.getData() == null) {
            return; // User cancelled.
        }

        Uri uri = data.getData();
        try {
            File destination = copyToPrivateStorage(uri, requestCode == OPEN_IMAGE_REQUEST);
            if (requestCode == OPEN_IMAGE_REQUEST) {
                emitSignal("image_selected", destination.getAbsolutePath());
            } else {
                emitSignal("file_selected", destination.getAbsolutePath());
            }
        } catch (Exception exception) {
            Log.e(TAG, "Could not copy selected document", exception);
            String message = exception.getMessage() == null ? "Could not read the selected model" : exception.getMessage();
            emitSignal("file_picker_error", message);
        }
    }

    private File copyToPrivateStorage(Uri uri, boolean imageFile) throws Exception {
        Activity activity = getActivity();
        String displayName = "model.glb";
        android.database.Cursor cursor = null;
        try {
            cursor = activity.getContentResolver().query(uri, new String[] {"_display_name"}, null, null, null);
            if (cursor != null && cursor.moveToFirst()) {
                int column = cursor.getColumnIndex("_display_name");
                if (column >= 0) {
                    String candidate = cursor.getString(column);
                    if (candidate != null && !candidate.trim().isEmpty()) {
                        displayName = candidate;
                    }
                }
            }
        } finally {
            if (cursor != null) cursor.close();
        }

        String safeName = displayName.replaceAll("[^A-Za-z0-9._-]", "_");
        String lowerName = safeName.toLowerCase();
        if (imageFile) {
            if (!lowerName.endsWith(".png") && !lowerName.endsWith(".jpg") &&
                !lowerName.endsWith(".jpeg") && !lowerName.endsWith(".webp")) {
                safeName += ".png";
            }
        } else if (!lowerName.endsWith(".glb") && !lowerName.endsWith(".gltf")) {
            safeName += ".glb";
        }
        File destination = new File(activity.getFilesDir(), safeName);
        try (InputStream input = activity.getContentResolver().openInputStream(uri);
             FileOutputStream output = new FileOutputStream(destination)) {
            if (input == null) throw new IllegalStateException("Android could not open the selected document");
            byte[] buffer = new byte[16384];
            int count;
            while ((count = input.read(buffer)) != -1) {
                output.write(buffer, 0, count);
            }
            output.flush();
        }
        return destination;
    }
}
