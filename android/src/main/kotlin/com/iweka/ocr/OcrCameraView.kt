package com.iweka.ocr

import android.content.Context
import android.graphics.PixelFormat
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import io.flutter.plugin.platform.PlatformView

class OcrCameraView(
    context: Context,
    id: Int,
    creationParams: Map<String?, Any?>?,
    private val ppocrv5ncnn: PPOCRv5Ncnn
) : PlatformView, SurfaceHolder.Callback {

    private val surfaceView: SurfaceView = SurfaceView(context)

    init {
        surfaceView.holder.setFormat(PixelFormat.RGBA_8888)
        surfaceView.holder.addCallback(this)
    }

    override fun getView(): View {
        return surfaceView
    }

    override fun dispose() {
    }

    override fun surfaceCreated(holder: SurfaceHolder) {
    }

    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
        ppocrv5ncnn.setOutputWindow(holder.surface)
    }

    override fun surfaceDestroyed(holder: SurfaceHolder) {
        ppocrv5ncnn.clearOutputWindow()
    }
}
