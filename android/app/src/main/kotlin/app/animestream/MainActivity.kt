package app.animestream

import android.app.PendingIntent
import android.app.PictureInPictureParams
import android.app.RemoteAction
import android.content.BroadcastReceiver
import android.content.Context
import android.content.IntentFilter
import android.content.res.Configuration
import android.graphics.drawable.Icon
import android.util.Rational
import android.widget.Toast
import android.os.Looper
import android.os.Handler
import android.os.Build
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

    private var autoPip = false
    private var playing = true

    private val pipActionIntent = "app.animestream.PIP_ACTION"

    private val pipReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val action = intent?.getStringExtra("action") ?: return
            if (::channel.isInitialized) channel.invokeMethod("pipAction", action)
        }
    }

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
                "startDownloadService" -> {
                    val intent = Intent(this, DownloadService::class.java)
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        startForegroundService(intent)
                    } else {
                        startService(intent)
                    }
                    result.success(null)
                }
                "stopDownloadService" -> {
                    stopService(Intent(this, DownloadService::class.java))
                    result.success(null)
                }
                "setAutoPip" -> {
                    autoPip = call.argument<Boolean>("enabled") ?: false
                    updatePipParams()
                    result.success(null)
                }
                "setPipPlaying" -> {
                    playing = call.argument<Boolean>("playing") ?: true
                    updatePipParams()
                    result.success(null)
                }
                "enterPip" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        try {
                            enterPictureInPictureMode(buildPipParams())
                        } catch (e: Exception) {
                            // PiP unavailable on this device
                        }
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val filter = IntentFilter(pipActionIntent)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(pipReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(pipReceiver, filter)
        }
        val intent = getIntent()
        if (intent?.action == Intent.ACTION_VIEW) {
            handleMangaFileIntent(intent)
        }
    }

    override fun onDestroy() {
        unregisterReceiver(pipReceiver)
        super.onDestroy()
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

    private fun pipAction(action: String, iconRes: Int, title: String, requestCode: Int): RemoteAction {
        val intent = Intent(pipActionIntent).setPackage(packageName).putExtra("action", action)
        val pending = PendingIntent.getBroadcast(this, requestCode, intent, PendingIntent.FLAG_IMMUTABLE)
        return RemoteAction(Icon.createWithResource(this, iconRes), title, title, pending)
    }

    private fun buildPipParams(): PictureInPictureParams {
        val actions = listOf(
            pipAction("rewind", R.drawable.ic_pip_rewind, "Rewind", 0),
            if (playing) pipAction("playPause", R.drawable.ic_pip_pause, "Pause", 1)
            else pipAction("playPause", R.drawable.ic_pip_play, "Play", 1),
            pipAction("forward", R.drawable.ic_pip_forward, "Forward", 2),
        )
        val builder = PictureInPictureParams.Builder()
            .setAspectRatio(Rational(16, 9))
            .setActions(actions)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setAutoEnterEnabled(autoPip)
        }
        return builder.build()
    }

    private fun updatePipParams() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        try {
            setPictureInPictureParams(buildPipParams())
        } catch (e: Exception) {
            // device without PiP support
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        // Below Android 12 the system cannot auto-enter on its own.
        if (autoPip && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
            try {
                enterPictureInPictureMode(buildPipParams())
            } catch (e: Exception) {
            }
        }
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        if (::channel.isInitialized) {
            channel.invokeMethod("onPipChanged", isInPictureInPictureMode)
        }
    }

    fun showToast(message: String) {
        Handler(Looper.getMainLooper()).post {
            Toast.makeText(this, message, Toast.LENGTH_SHORT).show();
        }
    }
}
