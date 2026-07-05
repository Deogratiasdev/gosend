package com.example.gosend

import android.app.DownloadManager
import android.content.ContentResolver
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.gosend/share"
    private var sharedFiles: ArrayList<String>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getSharedFiles") {
                result.success(sharedFiles)
                sharedFiles = null
            } else if (call.method == "openReceiveDirectory") {
                val path = call.argument<String>("path")
                openReceiveDirectory(path)
                result.success(true)
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        if (intent?.action == Intent.ACTION_SEND || intent?.action == Intent.ACTION_SEND_MULTIPLE) {
            sharedFiles = ArrayList()
            
            if (intent.action == Intent.ACTION_SEND) {
                val uri = intent.getParcelableExtra<android.net.Uri>(Intent.EXTRA_STREAM)
                uri?.let {
                    val copiedPath = copyUriToTempFile(it)
                    if (copiedPath != null) {
                        sharedFiles?.add(copiedPath)
                    }
                }
            } else if (intent.action == Intent.ACTION_SEND_MULTIPLE) {
                val uris = intent.getParcelableArrayListExtra<android.net.Uri>(Intent.EXTRA_STREAM)
                uris?.forEach {
                    val copiedPath = copyUriToTempFile(it)
                    if (copiedPath != null) {
                        sharedFiles?.add(copiedPath)
                    }
                }
            }
        }
    }

    private fun copyUriToTempFile(uri: Uri): String? {
        return try {
            val inputStream = contentResolver.openInputStream(uri) ?: return null
            val fileName = sanitizeFileName(
                getFileName(uri) ?: "shared_file_${System.currentTimeMillis()}"
            )
            
            val tempDir = File(cacheDir, "shared_files")
            if (!tempDir.exists()) {
                tempDir.mkdirs()
            }
            
            val tempFile = uniqueFile(tempDir, fileName)
            val outputStream = FileOutputStream(tempFile)
            
            inputStream.use { input ->
                outputStream.use { output ->
                    input.copyTo(output, 64 * 1024)
                }
            }
            
            tempFile.absolutePath
        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }

    private fun getFileName(uri: Uri): String? {
        var result: String? = null
        if (uri.scheme == "content") {
            val cursor = contentResolver.query(uri, null, null, null, null)
            cursor?.use {
                if (it.moveToFirst()) {
                    val index = it.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                    if (index >= 0) {
                        result = it.getString(index)
                    }
                }
            }
        }
        if (result == null) {
            result = uri.path?.lastIndexOf('/')?.let { uri.path?.substring(it + 1) }
        }
        return result
    }

    private fun sanitizeFileName(fileName: String): String {
        val sanitized = fileName.replace(Regex("[\\\\/:*?\"<>|]"), "_").trim()
        return sanitized.ifBlank { "shared_file_${System.currentTimeMillis()}" }
    }

    private fun uniqueFile(directory: File, fileName: String): File {
        val dotIndex = fileName.lastIndexOf('.')
        val baseName = if (dotIndex > 0) fileName.substring(0, dotIndex) else fileName
        val extension = if (dotIndex > 0) fileName.substring(dotIndex) else ""
        var candidate = File(directory, fileName)
        var index = 1

        while (candidate.exists()) {
            candidate = File(directory, "${baseName}_${index}$extension")
            index++
        }

        return candidate
    }

    private fun openReceiveDirectory(path: String?) {
        val directory = File(path ?: "/storage/emulated/0/Download/GoSend/received")
        if (!directory.exists()) {
            directory.mkdirs()
        }

        val documentUri = buildDocumentUri(path)
        val treeUri = buildTreeUri(path)

        val viewDirectoryIntent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(documentUri, DocumentsContract.Document.MIME_TYPE_DIR)
            addCategory(Intent.CATEGORY_DEFAULT)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
        }

        if (startIfAvailable(viewDirectoryIntent)) {
            return
        }

        val pickDirectoryIntent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            putExtra(DocumentsContract.EXTRA_INITIAL_URI, treeUri)
        }

        if (startIfAvailable(pickDirectoryIntent)) {
            return
        }

        val downloadsIntent = Intent(DownloadManager.ACTION_VIEW_DOWNLOADS).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(downloadsIntent)
    }

    private fun startIfAvailable(intent: Intent): Boolean {
        return try {
            if (intent.resolveActivity(packageManager) == null) {
                false
            } else {
                startActivity(intent)
                true
            }
        } catch (e: Exception) {
            false
        }
    }

    private fun buildDocumentUri(path: String?): Uri {
        return DocumentsContract.buildDocumentUri(
            "com.android.externalstorage.documents",
            buildDocumentId(path),
        )
    }

    private fun buildTreeUri(path: String?): Uri {
        return DocumentsContract.buildTreeDocumentUri(
            "com.android.externalstorage.documents",
            buildDocumentId(path),
        )
    }

    private fun buildDocumentId(path: String?): String {
        val relativePath = path
            ?.removePrefix("/storage/emulated/0/")
            ?.trim('/')
            ?.takeIf { it.isNotBlank() }
            ?: "Download/GoSend/received"
        return "primary:$relativePath"
    }
}
