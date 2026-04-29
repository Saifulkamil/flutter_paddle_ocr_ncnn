package com.iweka.ocr

import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/** OcrPlugin */
class OcrPlugin: FlutterPlugin, MethodCallHandler {
  private lateinit var channel : MethodChannel
  private lateinit var context: Context
  private val ppocrv5ncnn = PPOCRv5Ncnn()

  override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
    context = flutterPluginBinding.applicationContext
    channel = MethodChannel(flutterPluginBinding.binaryMessenger, "ocr")
    channel.setMethodCallHandler(this)

    flutterPluginBinding.platformViewRegistry.registerViewFactory(
        "ocr_camera_view", OcrCameraViewFactory(ppocrv5ncnn)
    )
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    when (call.method) {
        "getPlatformVersion" -> {
            result.success("Android ${android.os.Build.VERSION.RELEASE}")
        }
        "loadModel" -> {
            val detParam = call.argument<String>("detParam") ?: ""
            val detModel = call.argument<String>("detModel") ?: ""
            val recParam = call.argument<String>("recParam") ?: ""
            val recModel = call.argument<String>("recModel") ?: ""
            val sizeid = call.argument<Int>("sizeid") ?: 0
            val cpugpu = call.argument<Int>("cpugpu") ?: 0
            val success = ppocrv5ncnn.loadModel(detParam, detModel, recParam, recModel, sizeid, cpugpu)
            result.success(success)
        }
        "openCamera" -> {
            val facing = call.argument<Int>("facing") ?: 0
            val success = ppocrv5ncnn.openCamera(facing)
            result.success(success)
        }
        "closeCamera" -> {
            val success = ppocrv5ncnn.closeCamera()
            result.success(success)
        }
        "toggleFlash" -> {
            val success = ppocrv5ncnn.toggleFlash()
            result.success(success)
        }
        "takePhoto" -> {
            val savePath = call.argument<String>("savePath") ?: ""
            if (savePath.isEmpty()) {
                result.error("INVALID_PATH", "savePath is required", null)
                return
            }
            Thread {
                val photoPath = ppocrv5ncnn.takePhoto(savePath)
                android.os.Handler(android.os.Looper.getMainLooper()).post {
                    result.success(photoPath)
                }
            }.start()
        }
        "getOcrText" -> {
            val text = ppocrv5ncnn.getOcrText()
            result.success(text)
        }
        else -> {
            result.notImplemented()
        }
    }
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
  }
}
