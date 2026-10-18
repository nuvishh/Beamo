package com.nuvish.beamo

import android.content.ContentValues
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val channelName = "beamo/downloads"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                if (call.method == "saveToDownloads") {
                    val sourcePath = call.argument<String>("sourcePath")
                    val filename = call.argument<String>("filename") ?: "file"
                    if (sourcePath == null) {
                        result.error("ARG", "missing sourcePath", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val publicPath = saveToDownloads(File(sourcePath), filename)
                        if (publicPath != null) result.success(publicPath)
                        else result.error("IO", "could not save to Downloads", null)
                    } catch (e: Exception) {
                        result.error("IO", e.message, null)
                    }
                } else {
                    result.notImplemented()
                }
            }
    }

    /// Copies [source] into the public Downloads/Beamo folder.
    /// API 29+: MediaStore (no storage permission needed).
    /// Below 29: direct copy (needs WRITE_EXTERNAL_STORAGE, declared in manifest).
    private fun saveToDownloads(source: File, filename: String): String? {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, filename)
                put(MediaStore.Downloads.MIME_TYPE, "application/octet-stream")
                put(
                    MediaStore.Downloads.RELATIVE_PATH,
                    Environment.DIRECTORY_DOWNLOADS + "/Beamo"
                )
            }
            val uri = contentResolver.insert(
                MediaStore.Downloads.EXTERNAL_CONTENT_URI, values
            ) ?: return null
            contentResolver.openOutputStream(uri)?.use { out ->
                source.inputStream().use { input -> input.copyTo(out) }
            }
            // Display path (best effort; the MediaStore entry is canonical).
            @Suppress("DEPRECATION")
            return File(
                Environment.getExternalStoragePublicDirectory(
                    Environment.DIRECTORY_DOWNLOADS
                ),
                "Beamo/$filename"
            ).absolutePath
        } else {
            @Suppress("DEPRECATION")
            val dir = File(
                Environment.getExternalStoragePublicDirectory(
                    Environment.DIRECTORY_DOWNLOADS
                ),
                "Beamo"
            )
            if (!dir.exists()) dir.mkdirs()
            val target = uniqueFile(File(dir, filename))
            source.copyTo(target, overwrite = true)
            return target.absolutePath
        }
    }

    private fun uniqueFile(file: File): File {
        if (!file.exists()) return file
        val base = file.nameWithoutExtension
        val ext = file.extension.let { if (it.isEmpty()) "" else ".$it" }
        var i = 1
        while (true) {
            val candidate = File(file.parent, "$base ($i)$ext")
            if (!candidate.exists()) return candidate
            i++
        }
    }
}
