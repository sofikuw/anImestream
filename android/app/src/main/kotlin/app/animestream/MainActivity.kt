package app.animestream

import android.widget.Toast
import android.os.Looper
import android.os.Handler
import android.os.Bundle
import android.content.Intent
import android.net.Uri
import android.content.ContentResolver
import android.provider.MediaStore
import androidx.annotation.NonNull

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel


class MainActivity: FlutterActivity() {

    private lateinit var channel: MethodChannel

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "animestream.app/utils")
        channel.setMethodCallHandler {
                call, result ->
            when (call.method) {
                "showToast" -> {
                val message = call.argument<String>("message")
                if(message == null || message.length == 0) {
                    result.error("MESSAGE_NOT_PROVIDED", "MESSAGE IS NULL OR EMPTY", null)
                }
                showToast(message ?: "")
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val intent = getIntent()
        if (intent?.action == Intent.ACTION_VIEW) {
            handleMangaFileIntent(intent)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (intent.action == Intent.ACTION_VIEW) {
            handleMangaFileIntent(intent)
        }
    }

    private fun handleMangaFileIntent(intent: Intent) {
        val uri = intent.data ?: return
        val path = resolveFilePath(uri) ?: return
        val marker = "/Download/animestream/manga/"
        val index = path.indexOf(marker)
        if (index < 0) return
        val remainder = path.substring(index + marker.length)
        val segments = remainder.split('/').filter { it.isNotBlank() }
        if (segments.size < 2) return
        val mangaFolder = segments[0]
        val chapterFolder = segments[1]
        val mangaId = mangaFolder.substringAfterLast('_')
        val chapterId = chapterFolder.substringAfterLast('_')
        val chapterTitle = chapterFolder.substringBeforeLast('_')
        if (mangaId.isEmpty() || chapterId.isEmpty()) return
        channel.invokeMethod(
            "openChapter",
            mapOf(
                "mangaId" to mangaId,
                "chapterId" to chapterId,
                "chapterTitle" to chapterTitle,
            ),
        )
    }

    private fun resolveFilePath(uri: Uri): String? {
        return try {
            if ("file".equals(uri.scheme)) {
                uri.path
            } else if ("content".equals(uri.scheme)) {
                val resolver = getContentResolver()
                resolver.query(
                    uri,
                    arrayOf(MediaStore.MediaColumns.DATA),
                    null,
                    null,
                    null,
                )?.use { cursor ->
                    if (cursor.moveToFirst()) cursor.getString(0) else null
                }
            } else {
                null
            }
        } catch (error: Exception) {
            null
        }
    }

    override fun onUserLeaveHint() {
         super.onUserLeaveHint()
         channel.invokeMethod("onUserLeaveHint", null);
    }

    fun showToast(message: String) {
        Handler(Looper.getMainLooper()).post {
            Toast.makeText(this, message, Toast.LENGTH_SHORT).show();
        }
    }
}
