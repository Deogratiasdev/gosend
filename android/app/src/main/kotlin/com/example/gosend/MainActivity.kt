package com.example.gosend

import android.content.ContentResolver
import android.content.Intent
import android.net.Uri
import android.os.Bundle
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
            val contentResolver = contentResolver
            val inputStream = contentResolver.openInputStream(uri)
            val fileName = getFileName(uri) ?: "shared_file_${System.currentTimeMillis()}"
            
            val tempDir = File(cacheDir, "shared_files")
            if (!tempDir.exists()) {
                tempDir.mkdirs()
            }
            
            val tempFile = File(tempDir, fileName)
            val outputStream = FileOutputStream(tempFile)
            
            inputStream?.use { input ->
                outputStream.use { output ->
                    input.copyTo(output)
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
}
