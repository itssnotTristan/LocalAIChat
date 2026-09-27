package com.localai.local_ai_chat

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import kotlin.math.max
import kotlin.math.roundToInt

class MainActivity : FlutterActivity() {
    private var speechBridge: SystemSpeechBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        speechBridge = SystemSpeechBridge(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "local_ai_chat/system_speech")
            .setMethodCallHandler { call, result -> speechBridge?.handle(call, result) ?: result.notImplemented() }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "local_ai_chat/media")
            .setMethodCallHandler { call, result ->
                if (call.method != "prepareImage") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val source = call.argument<String>("source")
                val destination = call.argument<String>("destination")
                val maxSide = call.argument<String>("maxSide")?.toIntOrNull() ?: 1536
                if (source.isNullOrBlank() || destination.isNullOrBlank() || maxSide !in 256..4096) {
                    result.error("bad_image_request", "Choose a valid photo and output location.", null)
                    return@setMethodCallHandler
                }
                Thread {
                    try {
                        val output = prepareImage(source, destination, maxSide)
                        runOnUiThread { result.success(output) }
                    } catch (error: Exception) {
                        runOnUiThread {
                            result.error("image_conversion_failed", error.message ?: "Could not read photo.", null)
                        }
                    }
                }.start()
            }
    }

    override fun onDestroy() {
        speechBridge?.close()
        speechBridge = null
        super.onDestroy()
    }

    private fun prepareImage(source: String, destination: String, maxSide: Int): String {
        val input = File(source)
        require(input.isFile) { "The chosen photo is no longer available." }
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(source, bounds)
        require(bounds.outWidth > 0 && bounds.outHeight > 0) { "This photo format is not supported on this Android device." }
        var sample = 1
        while (max(bounds.outWidth, bounds.outHeight) / sample > maxSide * 2) sample *= 2
        val options = BitmapFactory.Options().apply {
            inSampleSize = sample
            inPreferredConfig = Bitmap.Config.ARGB_8888
        }
        var bitmap = BitmapFactory.decodeFile(source, options)
            ?: error("The photo could not be decoded.")
        try {
            val orientation = try {
                ExifInterface(source).getAttributeInt(
                    ExifInterface.TAG_ORIENTATION,
                    ExifInterface.ORIENTATION_NORMAL,
                )
            } catch (_: IOException) {
                ExifInterface.ORIENTATION_NORMAL
            }
            val matrix = Matrix()
            when (orientation) {
                ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
                ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
                ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(270f)
                ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.postScale(-1f, 1f)
                ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.postScale(1f, -1f)
                ExifInterface.ORIENTATION_TRANSPOSE -> { matrix.postScale(-1f, 1f); matrix.postRotate(90f) }
                ExifInterface.ORIENTATION_TRANSVERSE -> { matrix.postScale(-1f, 1f); matrix.postRotate(270f) }
            }
            if (!matrix.isIdentity) {
                val rotated = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
                if (rotated !== bitmap) bitmap.recycle()
                bitmap = rotated
            }
            val scale = minOf(1.0, maxSide.toDouble() / max(bitmap.width, bitmap.height))
            if (scale < 1.0) {
                val resized = Bitmap.createScaledBitmap(
                    bitmap,
                    max(1, (bitmap.width * scale).roundToInt()),
                    max(1, (bitmap.height * scale).roundToInt()),
                    true,
                )
                if (resized !== bitmap) bitmap.recycle()
                bitmap = resized
            }
            val target = File(destination)
            target.parentFile?.mkdirs()
            FileOutputStream(target).use { stream ->
                check(bitmap.compress(Bitmap.CompressFormat.JPEG, 88, stream)) { "Could not save the photo." }
                stream.fd.sync()
            }
            return target.absolutePath
        } finally {
            if (!bitmap.isRecycled) bitmap.recycle()
        }
    }
}
