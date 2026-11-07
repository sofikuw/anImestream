package app.animestream

import android.content.Context
import android.view.View
import io.github.assrender.SubtitleOverlayView
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class SubtitleOverlayPlatformView(context: Context) : PlatformView {
    private val subtitleOverlayView: SubtitleOverlayView = SubtitleOverlayView(context, null, 0).apply {
        // Transparent background so video shows through
        setBackgroundColor(android.graphics.Color.TRANSPARENT)
    }

    init {
        ExternalAssRenderer.activeOverlayView = subtitleOverlayView
    }

    override fun getView(): View = subtitleOverlayView

    override fun dispose() {
        if (ExternalAssRenderer.activeOverlayView == subtitleOverlayView) {
            ExternalAssRenderer.activeOverlayView = null
        }
    }
}

class SubtitleOverlayViewFactory : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        return SubtitleOverlayPlatformView(context)
    }
}
