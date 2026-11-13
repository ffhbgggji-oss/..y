package org.godotengine.plugin.filepicker;

import android.app.Activity;
import android.content.ContentValues;
import android.media.MediaCodec;
import android.media.MediaCodecInfo;
import android.media.MediaFormat;
import android.media.MediaMuxer;
import android.os.Build;
import android.provider.MediaStore;
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
import java.io.OutputStream;
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
    private static final int OPEN_AUDIO_REQUEST = 42044;

    private MediaCodec mp4Encoder;
    private MediaMuxer mp4Muxer;
    private MediaCodec.BufferInfo mp4BufferInfo;
    private File mp4OutputFile;
    private int mp4TrackIndex = -1;
    private boolean mp4MuxerStarted = false;
    private int mp4Width;
    private int mp4Height;
    private int mp4Fps;
    private long mp4FrameIndex = 0;

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
        signals.add(new SignalInfo("audio_selected", String.class));
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
                "application/gltf-buffer",
                "model/obj",
                "text/plain"
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

    @UsedByGodot
    public void open_audio_picker() {
        Activity activity = getActivity();
        activity.runOnUiThread(() -> {
            Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
            intent.addCategory(Intent.CATEGORY_OPENABLE);
            intent.setType("audio/*");
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
            try {
                activity.startActivityForResult(intent, OPEN_AUDIO_REQUEST);
            } catch (Exception exception) {
                emitSignal("file_picker_error", exception.getMessage() == null ? "Unable to open Android audio picker" : exception.getMessage());
            }
        });
    }

    @Override
    public void onMainActivityResult(int requestCode, int resultCode, Intent data) {
        if (requestCode != OPEN_DOCUMENT_REQUEST && requestCode != OPEN_IMAGE_REQUEST && requestCode != OPEN_AUDIO_REQUEST) {
            super.onMainActivityResult(requestCode, resultCode, data);
            return;
        }
        if (resultCode != Activity.RESULT_OK || data == null || data.getData() == null) {
            return; // User cancelled.
        }

        Uri uri = data.getData();
        try {
            File destination = copyToPrivateStorage(uri, requestCode == OPEN_IMAGE_REQUEST, requestCode == OPEN_AUDIO_REQUEST);
            if (requestCode == OPEN_IMAGE_REQUEST) {
                emitSignal("image_selected", destination.getAbsolutePath());
            } else if (requestCode == OPEN_AUDIO_REQUEST) {
                emitSignal("audio_selected", destination.getAbsolutePath());
            } else {
                emitSignal("file_selected", destination.getAbsolutePath());
            }
        } catch (Exception exception) {
            Log.e(TAG, "Could not copy selected document", exception);
            String message = exception.getMessage() == null ? "Could not read the selected model" : exception.getMessage();
            emitSignal("file_picker_error", message);
        }
    }


    /** Starts an H.264 MP4 encoder. Input frames are tightly packed RGBA8888. */
    @UsedByGodot
    public synchronized boolean start_mp4_export(int width, int height, int fps) {
        try {
            stopMp4Quietly();
            mp4Width = Math.max(2, width - (width % 2));
            mp4Height = Math.max(2, height - (height % 2));
            mp4Fps = Math.max(12, Math.min(60, fps));
            mp4FrameIndex = 0;
            mp4TrackIndex = -1;
            mp4MuxerStarted = false;
            mp4OutputFile = new File(getActivity().getFilesDir(), "cartoonstudio_export.mp4");
            if (mp4OutputFile.exists()) mp4OutputFile.delete();

            MediaFormat format = MediaFormat.createVideoFormat("video/avc", mp4Width, mp4Height);
            format.setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420SemiPlanar);
            format.setInteger(MediaFormat.KEY_BIT_RATE, Math.max(1000000, mp4Width * mp4Height * mp4Fps / 6));
            format.setInteger(MediaFormat.KEY_FRAME_RATE, mp4Fps);
            format.setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 2);
            mp4Encoder = MediaCodec.createEncoderByType("video/avc");
            mp4Encoder.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE);
            mp4Encoder.start();
            mp4Muxer = new MediaMuxer(mp4OutputFile.getAbsolutePath(), MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4);
            mp4BufferInfo = new MediaCodec.BufferInfo();
            return true;
        } catch (Exception exception) {
            Log.e(TAG, "Could not start MP4 encoder", exception);
            stopMp4Quietly();
            return false;
        }
    }

    /** Encodes one RGBA8888 frame. */
    @UsedByGodot
    public synchronized boolean encode_mp4_frame(byte[] rgba) {
        if (mp4Encoder == null || rgba == null || rgba.length < mp4Width * mp4Height * 4) return false;
        try {
            int inputIndex = mp4Encoder.dequeueInputBuffer(10000);
            if (inputIndex < 0) return false;
            java.nio.ByteBuffer input = mp4Encoder.getInputBuffer(inputIndex);
            if (input == null) return false;
            input.clear();
            rgbaToNv12(rgba, input, mp4Width, mp4Height);
            long ptsUs = mp4FrameIndex * 1000000L / mp4Fps;
            mp4Encoder.queueInputBuffer(inputIndex, 0, mp4Width * mp4Height * 3 / 2, ptsUs, 0);
            mp4FrameIndex++;
            drainMp4Encoder(false);
            return true;
        } catch (Exception exception) {
            Log.e(TAG, "Could not encode MP4 frame", exception);
            return false;
        }
    }

    @UsedByGodot
    public synchronized boolean finish_mp4_export() {
        if (mp4Encoder == null) return false;
        boolean success = true;
        try {
            int inputIndex = mp4Encoder.dequeueInputBuffer(10000);
            if (inputIndex >= 0) {
                long ptsUs = mp4FrameIndex * 1000000L / Math.max(1, mp4Fps);
                mp4Encoder.queueInputBuffer(inputIndex, 0, 0, ptsUs, MediaCodec.BUFFER_FLAG_END_OF_STREAM);
            }
            drainMp4Encoder(true);
            success = mp4OutputFile != null && mp4OutputFile.exists() && mp4OutputFile.length() > 1024 && mp4MuxerStarted;
        } catch (Exception exception) {
            Log.e(TAG, "Could not finish MP4 export", exception);
            success = false;
        } finally {
            stopMp4Quietly();
        }
        return success;
    }

    @UsedByGodot
    public synchronized String get_mp4_export_path() {
        return mp4OutputFile == null ? "" : mp4OutputFile.getAbsolutePath();
    }

    /** Publishes the encoded file in Movies/CartoonStudio and returns its content URI. */
    @UsedByGodot
    public synchronized String publish_mp4() {
        if (mp4OutputFile == null || !mp4OutputFile.exists()) return "";
        if (Build.VERSION.SDK_INT < 29) return mp4OutputFile.getAbsolutePath();
        try {
            ContentValues values = new ContentValues();
            values.put(MediaStore.Video.Media.DISPLAY_NAME, "CartoonStudio_" + System.currentTimeMillis() + ".mp4");
            values.put(MediaStore.Video.Media.MIME_TYPE, "video/mp4");
            values.put(MediaStore.Video.Media.RELATIVE_PATH, Environment.DIRECTORY_MOVIES + "/CartoonStudio");
            values.put(MediaStore.Video.Media.IS_PENDING, 1);
            Uri uri = getActivity().getContentResolver().insert(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, values);
            if (uri == null) return "";
            try (InputStream input = new java.io.FileInputStream(mp4OutputFile);
                 OutputStream output = getActivity().getContentResolver().openOutputStream(uri)) {
                if (output == null) return "";
                byte[] buffer = new byte[32768];
                int count;
                while ((count = input.read(buffer)) != -1) output.write(buffer, 0, count);
                output.flush();
            }
            ContentValues ready = new ContentValues();
            ready.put(MediaStore.Video.Media.IS_PENDING, 0);
            getActivity().getContentResolver().update(uri, ready, null, null);
            return uri.toString();
        } catch (Exception exception) {
            Log.e(TAG, "Could not publish MP4", exception);
            return "";
        }
    }

    private void drainMp4Encoder(boolean endOfStream) {
        boolean outputDone = false;
        while (!outputDone) {
            int outputIndex = mp4Encoder.dequeueOutputBuffer(mp4BufferInfo, endOfStream ? 10000 : 0);
            if (outputIndex == MediaCodec.INFO_TRY_AGAIN_LATER) {
                if (!endOfStream) break;
                continue;
            }
            if (outputIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                if (mp4MuxerStarted) throw new IllegalStateException("MP4 muxer format changed twice");
                mp4TrackIndex = mp4Muxer.addTrack(mp4Encoder.getOutputFormat());
                mp4Muxer.start();
                mp4MuxerStarted = true;
            } else if (outputIndex >= 0) {
                java.nio.ByteBuffer encoded = mp4Encoder.getOutputBuffer(outputIndex);
                if (encoded != null && mp4BufferInfo.size > 0 && mp4MuxerStarted &&
                    (mp4BufferInfo.flags & MediaCodec.BUFFER_FLAG_CODEC_CONFIG) == 0) {
                    encoded.position(mp4BufferInfo.offset);
                    encoded.limit(mp4BufferInfo.offset + mp4BufferInfo.size);
                    mp4Muxer.writeSampleData(mp4TrackIndex, encoded, mp4BufferInfo);
                }
                boolean eos = (mp4BufferInfo.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0;
                mp4Encoder.releaseOutputBuffer(outputIndex, false);
                if (eos) outputDone = true;
            }
        }
    }

    private static void rgbaToNv12(byte[] rgba, java.nio.ByteBuffer output, int width, int height) {
        int frameSize = width * height;
        // Y plane.
        for (int y = 0; y < height; y++) {
            for (int x = 0; x < width; x++) {
                int p = (y * width + x) * 4;
                int r = rgba[p] & 0xff, g = rgba[p + 1] & 0xff, b = rgba[p + 2] & 0xff;
                int yy = ((66 * r + 129 * g + 25 * b + 128) >> 8) + 16;
                output.put((byte) clampByte(yy));
            }
        }
        // Interleaved UV plane (NV12), one chroma sample per 2x2 pixels.
        for (int y = 0; y < height; y += 2) {
            for (int x = 0; x < width; x += 2) {
                int rSum = 0, gSum = 0, bSum = 0;
                for (int dy = 0; dy < 2; dy++) for (int dx = 0; dx < 2; dx++) {
                    int p = ((y + dy) * width + x + dx) * 4;
                    rSum += rgba[p] & 0xff; gSum += rgba[p + 1] & 0xff; bSum += rgba[p + 2] & 0xff;
                }
                int r = rSum / 4, g = gSum / 4, b = bSum / 4;
                int u = ((-38 * r - 74 * g + 112 * b + 128) >> 8) + 128;
                int v = ((112 * r - 94 * g - 18 * b + 128) >> 8) + 128;
                output.put((byte) clampByte(u));
                output.put((byte) clampByte(v));
            }
        }
    }

    private static int clampByte(int value) { return Math.max(0, Math.min(255, value)); }

    private void stopMp4Quietly() {
        try { if (mp4Encoder != null) { mp4Encoder.stop(); mp4Encoder.release(); } } catch (Exception ignored) { }
        try { if (mp4Muxer != null) { if (mp4MuxerStarted) mp4Muxer.stop(); mp4Muxer.release(); } } catch (Exception ignored) { }
        mp4Encoder = null;
        mp4Muxer = null;
        mp4BufferInfo = null;
        mp4MuxerStarted = false;
        mp4TrackIndex = -1;
    }

    private File copyToPrivateStorage(Uri uri, boolean imageFile, boolean audioFile) throws Exception {
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
        } else if (audioFile) {
            if (!lowerName.endsWith(".wav") && !lowerName.endsWith(".ogg") && !lowerName.endsWith(".mp3")) {
                safeName += ".mp3";
            }
        } else if (!lowerName.endsWith(".glb") && !lowerName.endsWith(".gltf") && !lowerName.endsWith(".obj")) {
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
