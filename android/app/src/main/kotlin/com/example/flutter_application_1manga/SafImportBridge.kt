package com.example.flutter_application_1manga

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.os.SystemClock
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.math.BigInteger
import java.util.Locale
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/** SAF URIs stay URIs: no conversion to /storage paths and no media permission. */
class SafImportBridge(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "com.gunbook.storage")
    private val main = Handler(Looper.getMainLooper())
    private val executor = Executors.newSingleThreadExecutor()
    private val ownedJobs = ConcurrentHashMap.newKeySet<String>()
    private var picker: MethodChannel.Result? = null
    @Volatile private var attached = true

    init {
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "activeImportSessions" -> result.success(jobs.keys.toList())
                    "pickDirectory" -> {
                        if (picker != null || jobs.isNotEmpty()) {
                            result.error("BUSY", "已有匯入作業進行中", null)
                        } else {
                            picker = result
                            try {
                                activity.startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                                    addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                        Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION)
                                }, REQUEST_DIRECTORY)
                            } catch (error: Exception) {
                                picker = null
                                result.error("PICKER_FAILED", error.message, null)
                            }
                        }
                    }
                    "cancelImport" -> {
                        jobs[call.argument<String>("sessionId")]?.set(true)
                        result.success(null)
                    }
                    "releaseDirectory" -> {
                        val uri = Uri.parse(requireNotNull(call.argument<String>("uri")))
                        try {
                            activity.contentResolver.releasePersistableUriPermission(
                                uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        } catch (_: SecurityException) { /* temporary grant only */ }
                        result.success(null)
                    }
                    "importTree" -> {
                        val uri = Uri.parse(requireNotNull(call.argument<String>("uri")))
                        require(uri.scheme == "content" && DocumentsContract.isTreeUri(uri))
                        val id = requireNotNull(call.argument<String>("sessionId"))
                        require(UUID.fromString(id).toString() == id)
                        val root = File(requireNotNull(call.argument<String>("booksRoot"))).canonicalFile
                        require(root == File(activity.applicationInfo.dataDir, "books").canonicalFile)
                        require(jobs.isEmpty()) { "已有匯入作業進行中" }
                        val perf = call.argument<Boolean>("perf") == true
                        val cancelled = AtomicBoolean(false)
                        jobs[id] = cancelled
                        ownedJobs.add(id)
                        executor.execute {
                            try {
                                val books = copyTree(uri, root, id, cancelled, perf)
                                main.post { if (attached) result.success(books) }
                            } catch (_: Cancelled) {
                                main.post { if (attached) result.error("CANCELLED", "已取消匯入", null) }
                            } catch (error: Exception) {
                                main.post { if (attached) result.error("IMPORT_FAILED",
                                    "匯入未提交：${error.message}", null) }
                            } finally {
                                jobs.remove(id)
                                ownedJobs.remove(id)
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            } catch (error: Exception) {
                result.error("STORAGE_ERROR", error.message, null)
            }
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_DIRECTORY) return false
        val result = picker ?: return true
        picker = null
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            result.success(null)
            return true
        }
        try {
            val flags = data?.flags ?: 0
            if (flags and Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION != 0) {
                activity.contentResolver.takePersistableUriPermission(uri,
                    flags and Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            result.success(uri.toString())
        } catch (error: Exception) {
            result.error("PERMISSION_DENIED", "無法取得資料夾讀取授權：${error.message}", null)
        }
        return true
    }

    fun dispose() {
        attached = false
        ownedJobs.forEach { jobs[it]?.set(true) }
        picker?.error("DETACHED", "畫面已關閉", null)
        picker = null
        channel.setMethodCallHandler(null)
        executor.shutdownNow()
    }

    private data class Document(val uri: Uri, val name: String, val size: Long?)
    private data class Folder(val documentId: String, val name: String, val relative: String)
    private class Cancelled : Exception()
    private fun check(cancelled: AtomicBoolean) {
        if (cancelled.get() || Thread.currentThread().isInterrupted) throw Cancelled()
    }

    private fun copyTree(tree: Uri, root: File, sessionId: String,
                         cancelled: AtomicBoolean, perf: Boolean): List<Map<String, Any>> {
        val scanStart = SystemClock.elapsedRealtime()
        val resolver = activity.contentResolver
        val rootId = DocumentsContract.getTreeDocumentId(tree)
        val rootDocument = DocumentsContract.buildDocumentUriUsingTree(tree, rootId)
        val rootName = resolver.query(rootDocument,
            arrayOf(DocumentsContract.Document.COLUMN_DISPLAY_NAME), null, null, null)?.use {
            if (!it.moveToFirst()) throw IOException("無法讀取所選資料夾")
            it.getString(0) ?: "漫畫"
        } ?: throw IOException("無法列出所選資料夾")
        val folders = ArrayDeque<Folder>()
        folders.add(Folder(rootId, rootName, ""))
        val visited = mutableSetOf<String>()
        val grouped = mutableListOf<Pair<Folder, List<Document>>>()
        var total = 0
        var lastProgress = 0L
        fun progress(text: String, value: Double) {
            val now = System.currentTimeMillis()
            if (now - lastProgress < 100 && value < 1) return
            lastProgress = now
            main.post { if (attached) channel.invokeMethod("progress",
                mapOf("sessionId" to sessionId, "text" to text, "value" to value)) }
        }
        while (folders.isNotEmpty()) {
            check(cancelled)
            val folder = folders.removeFirst()
            if (!visited.add(folder.documentId)) throw IOException("資料夾供應者回傳循環目錄")
            val children = DocumentsContract.buildChildDocumentsUriUsingTree(tree, folder.documentId)
            val pages = mutableListOf<Document>()
            resolver.query(children, arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_MIME_TYPE,
                DocumentsContract.Document.COLUMN_SIZE), null, null, null)?.use { cursor ->
                while (cursor.moveToNext()) {
                    check(cancelled)
                    val id = cursor.getString(0) ?: throw IOException("圖片沒有文件識別碼")
                    val name = cursor.getString(1) ?: throw IOException("文件沒有名稱")
                    if (name.startsWith('.')) continue
                    if (cursor.getString(2) == DocumentsContract.Document.MIME_TYPE_DIR) {
                        folders.add(Folder(id, name, "${folder.relative}/$name"))
                    } else if (name.substringAfterLast('.', "").lowercase(Locale.ROOT) in EXTENSIONS) {
                        pages.add(Document(DocumentsContract.buildDocumentUriUsingTree(tree, id),
                            name, if (cursor.isNull(3)) null else cursor.getLong(3)))
                        total++
                    }
                    progress("掃描圖片中…（$total 張）", 0.0)
                }
            } ?: throw IOException("無法列出資料夾：${folder.name}")
            if (pages.isNotEmpty()) grouped.add(folder to pages.sortedWith { a, b -> natural(a.name, b.name) })
        }
        if (perf) Log.i("GUNBOOK_PERF", "event=import_scan_saf elapsed_ms=${SystemClock.elapsedRealtime() - scanStart} folders=${grouped.size} pages=$total")
        val copyStart = SystemClock.elapsedRealtime()
        var totalBytes = 0L
        var syncMillis = 0L
        if (grouped.isEmpty()) throw IOException("所選資料夾沒有支援的圖片")
        val session = File(root, ".imports/$sessionId")
        require(session.isDirectory && session.canonicalFile == session.absoluteFile)
        val books = mutableListOf<Map<String, Any>>()
        var copied = 0
        // The worker copies one stream at a time; reuse its buffer across files.
        val buffer = ByteArray(64 * 1024)
        for ((folder, pages) in grouped.sortedWith { a, b -> natural(a.first.relative, b.first.relative) }) {
            check(cancelled)
            val id = UUID.randomUUID().toString()
            // Ownership is durable before the first byte is copied.
            FileOutputStream(File(session, id)).use { it.fd.sync() }
            val target = File(root, id)
            if (!target.mkdir()) throw IOException("無法建立書籍目錄（請確認可用空間）")
            val paths = mutableListOf<String>()
            for ((index, page) in pages.withIndex()) {
                check(cancelled)
                val extension = page.name.substringAfterLast('.').lowercase(Locale.ROOT)
                val safeName = page.name.toByteArray(Charsets.UTF_8).size <= 240 &&
                    !page.name.contains('/') && !page.name.contains('\\') && !page.name.contains('\u0000')
                val named = if (safeName) File(target, page.name) else null
                val output = if (named != null && !named.exists()) named
                    else File(target, "${index.toString().padStart(8, '0')}-${UUID.randomUUID()}.$extension")
                var bytes = 0L
                try {
                    resolver.openInputStream(page.uri)?.use { input ->
                        FileOutputStream(output).use { stream ->
                            while (true) {
                                check(cancelled)
                                val size = input.read(buffer)
                                if (size < 0) break
                                stream.write(buffer, 0, size)
                                bytes += size
                            }
                            val syncStart = if (perf) SystemClock.elapsedRealtime() else 0L
                            stream.fd.sync()
                            if (perf) syncMillis += SystemClock.elapsedRealtime() - syncStart
                        }
                    } ?: throw IOException("無法開啟圖片")
                    if (bytes == 0L || (page.size != null && page.size >= 0 && page.size != bytes)) {
                        throw IOException("圖片複製大小不符（預期${page.size}，實際$bytes）")
                    }
                } catch (error: Cancelled) {
                    throw error
                } catch (error: Exception) {
                    throw IOException("${folder.name}/${page.name}：${error.message}", error)
                }
                totalBytes += bytes
                paths.add(output.path)
                copied++
                progress("複製中：${folder.name}（$copied/$total）", copied.toDouble() / total)
            }
            books.add(mapOf("id" to id, "title" to folder.name,
                "coverPath" to paths.first(), "filePaths" to paths))
        }
        check(cancelled)
        if (perf) Log.i("GUNBOOK_PERF", "event=import_copy_saf elapsed_ms=${SystemClock.elapsedRealtime() - copyStart} sync_ms=$syncMillis bytes=$totalBytes pages=$copied")
        return books
    }

    companion object {
        // Retain worker ownership across Activity/FlutterEngine recreation.
        // A new Dart isolate must not clean directories still being written by
        // an old engine's worker. Process death naturally clears this map.
        private val jobs = ConcurrentHashMap<String, AtomicBoolean>()
        private const val REQUEST_DIRECTORY = 0x4755
        private val EXTENSIONS = setOf("jpg", "jpeg", "png", "webp", "bmp", "gif", "heic", "jfif")
        private val TOKENS = Regex("[0-9]+|[^0-9]+")
        internal fun natural(a: String, b: String): Int {
            val left = TOKENS.findAll(a.lowercase(Locale.ROOT)).map { it.value }.toList()
            val right = TOKENS.findAll(b.lowercase(Locale.ROOT)).map { it.value }.toList()
            for (i in 0 until minOf(left.size, right.size)) {
                val x = left[i]; val y = right[i]
                val compare = if (x[0].isDigit() && y[0].isDigit())
                    BigInteger(x).compareTo(BigInteger(y)) else x.compareTo(y)
                if (compare != 0) return compare
            }
            val size = left.size.compareTo(right.size)
            return if (size != 0) size else a.compareTo(b)
        }
    }
}
