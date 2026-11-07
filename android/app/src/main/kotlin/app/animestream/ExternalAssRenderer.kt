package app.animestream

import android.graphics.Bitmap
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.github.assrender.AssDirectBridge
import io.github.assrender.SubtitleOverlayView

class ExternalAssRenderer : MethodChannel.MethodCallHandler {
    private var handle: Long = 0
    private var width = 1280
    private var height = 720
    private var bitmap: Bitmap? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    companion object {
        var activeOverlayView: SubtitleOverlayView? = null
    }

    private val supported: Boolean by lazy {
        try {
            (Build.SUPPORTED_ABIS.any { it == "arm64-v8a" || it == "armeabi-v7a" }) &&
                runCatching { System.loadLibrary("assrender") }.isSuccess
        } catch (t: Throwable) {
            Log.w("ASSRENDER", "assrender unavailable on this ABI", t)
            false
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "supported" -> result.success(supported)
                "load" -> {
                    if (!supported) {
                        result.success(false)
                        return
                    }
                    release()
                    val script = call.argument<ByteArray>("script")
                        ?: throw IllegalArgumentException("Missing ASS script")
                    width = (call.argument<Int>("width") ?: 1280).coerceIn(1, 3840)
                    height = (call.argument<Int>("height") ?: 720).coerceIn(1, 2160)
                    handle = AssDirectBridge.nativeInit(width, height, 1.0f)
                    if (handle == 0L) throw IllegalStateException("libass initialization failed")
                    if (AssDirectBridge.nativeLoadScript(handle, script) != 0) {
                        release()
                        throw IllegalArgumentException("Invalid ASS/SSA script")
                    }
                    bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                    Log.i("ASSRENDER", "Script loaded: bytes=${script.size}, size=${width}x{height}")
                    result.success(true)
                }
                "render" -> {
                    val target = bitmap
                    if (handle == 0L || target == null) {
                        result.success(null)
                    } else {
                        val timeMs = (call.argument<Number>("timeMs") ?: 0).toLong()
                        val hasContent = AssDirectBridge.nativeRender(handle, timeMs, target)
                        mainHandler.post {
                            val view = activeOverlayView
                            if (view != null) {
                                if (hasContent) {
                                    view.updateBitmap(target)
                                } else {
                                    view.clear()
                                }
                            }
                        }
                        result.success(hasContent)
                    }
                }
                "dispose" -> {
                    release()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (t: Throwable) {
            release()
            result.error("ASS_RENDER_FAILED", t.message ?: t.toString(), null)
        }
    }

    private fun release() {
        if (handle != 0L) {
            AssDirectBridge.nativeDestroy(handle)
            handle = 0
        }
        mainHandler.post {
            activeOverlayView?.clear()
        }
        bitmap?.recycle()
        bitmap = null
    }
}
