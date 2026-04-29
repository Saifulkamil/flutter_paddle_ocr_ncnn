package com.iweka.ocr

import android.view.Surface

class PPOCRv5Ncnn {
    external fun loadModel(
        detParam: String, detModel: String,
        recParam: String, recModel: String,
        sizeid: Int, cpugpu: Int
    ): Boolean
    external fun openCamera(facing: Int): Boolean
    external fun closeCamera(): Boolean
    external fun setOutputWindow(surface: Surface): Boolean
    external fun clearOutputWindow(): Boolean
    external fun toggleFlash(): Boolean
    external fun takePhoto(savePath: String): String
    external fun getOcrText(): String

    companion object {
        init {
            System.loadLibrary("ppocrv5ncnn")
        }
    }
}
