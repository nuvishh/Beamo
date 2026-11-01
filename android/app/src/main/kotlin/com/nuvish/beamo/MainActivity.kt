package com.nuvish.beamo

import android.content.ContentValues
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.MediaStore
import androidx.activity.result.contract.ActivityResultContracts
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val downloadsChannelName = "beamo/downloads"
    private val usbChannelName = "beamo/usb"

    // SAF folder pick (USB drive / external storage). The system picker is
    // D-pad navigable, so this works on TV sideloads too. Pick once: the
    // URI permission is persisted, later saves need no UI.
    private var pendingPickResult: MethodChannel.Result? = null
    private val openTreeLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { res ->
        val result = pendingPickResult
        pendingPickResult = null
        if (result == null) return@registerForActivityResult
        val uri = res.data?.data
        if (res.resultCode != RESULT_OK || uri == null) {
            result.error("CANCELLED", "folder pick cancelled", null)
            return@registerForActivityResult
        }
        try {
            val flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or
                Intent.FLAG_GRANT_WRITE_URI_PERMISSION
            contentResolver.takePersistableUriPermission(uri, flags)
            val name = queryTreeDisplayName(uri) ?: "USB folder"
            result.success(
                mapOf("uri" to uri.toString(), "name" to name)
            )
        } catch (e: Exception) {
            result.error("IO", e.message, null)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, downloadsChannelName)
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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, usbChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickFolder" -> {
                        if (pendingPickResult != null) {
                            result.error("BUSY", "folder pick already in progress", null)
                            return@setMethodCallHandler
                        }
                        pendingPickResult = result
                        val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                            addFlags(
                                Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION
                            )
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                addFlags(Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
                            }
                        }
                        try {
                            openTreeLauncher.launch(intent)
                        } catch (e: Exception) {
                            pendingPickResult = null
                            result.error("IO", e.message, null)
                        }
                    }
                    "writeFile" -> {
                        val treeUri = call.argument<String>("treeUri")
                        val filename = call.argument<String>("filename") ?: "file"
                        val sourcePath = call.argument<String>("sourcePath")
                        if (treeUri == null || sourcePath == null) {
                            result.error("ARG", "missing treeUri/sourcePath", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val display = writeToTree(
                                Uri.parse(treeUri), filename, File(sourcePath)
                            )
                            if (display != null) result.success(display)
                            else result.error("IO", "could not write file", null)
                        } catch (e: SecurityException) {
                            result.error("PERMISSION_LOST", e.message, null)
                        } catch (e: Exception) {
                            result.error("IO", e.message, null)
                        }
                    }
                    "releaseFolder" -> {
                        val treeUri = call.argument<String>("treeUri")
                        if (treeUri != null) {
                            try {
                                val flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                                contentResolver.releasePersistableUriPermission(
                                    Uri.parse(treeUri), flags
                                )
                            } catch (_) {
                            }
                        }
                        result.success(true)
                    }
                    else -> result.notImplemented()
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

    // ---------- SAF external-storage (USB) support ----------

    private fun queryTreeDisplayName(treeUri: Uri): String? {
        return try {
            val docId = DocumentsContract.getTreeDocumentId(treeUri)
            val docUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, docId)
            contentResolver.query(
                docUri,
                arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
                null, null, null
            )?.use { cursor ->
                if (cursor.moveToFirst()) {
                    cursor.getString(0)
                } else {
                    null
                }
            }
        } catch (_) {
            null
        }
    }

    /// Streams [source] into a new file inside the SAF tree folder.
    /// Returns a display string ("FolderName/filename") or null.
    /// Throws SecurityException when the persisted permission is gone.
    private fun writeToTree(treeUri: Uri, filename: String, source: File): String? {
        val docId = DocumentsContract.getTreeDocumentId(treeUri)
        val treeDocUri = DocumentsContract.buildDocumentUriUsingTree(treeUri, docId)
        val childrenUri =
            DocumentsContract.buildChildDocumentsUriUsingTree(treeUri, docId)

        val existing = mutableSetOf<String>()
        contentResolver.query(
            childrenUri,
            arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
            null, null, null
        )?.use { cursor ->
            val idx =
                cursor.getColumnIndex(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
            while (cursor.moveToNext()) {
                if (idx >= 0) existing.add(cursor.getString(idx))
            }
        }

        val unique = uniqueTreeName(filename, existing)
        val fileUri = DocumentsContract.createDocument(
            contentResolver, treeDocUri, "application/octet-stream", unique
        ) ?: return null
        contentResolver.openOutputStream(fileUri)?.use { out ->
            source.inputStream().use { input -> input.copyTo(out) }
        }
        val folderName = queryTreeDisplayName(treeUri) ?: "USB folder"
        return "$folderName/$unique"
    }

    private fun uniqueTreeName(filename: String, existing: Set<String>): String {
        if (!existing.contains(filename)) return filename
        val dot = filename.lastIndexOf('.')
        val base = if (dot > 0) filename.substring(0, dot) else filename
        val ext = if (dot > 0) filename.substring(dot) else ""
        var i = 1
        while (true) {
            val candidate = "$base ($i)$ext"
            if (!existing.contains(candidate)) return candidate
            i++
        }
    }
}
