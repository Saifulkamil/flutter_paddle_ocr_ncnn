
import 'ocr_platform_interface.dart';

class Ocr {
  Future<String?> getPlatformVersion() {
    return OcrPlatform.instance.getPlatformVersion();
  }

  /// Load OCR model from file paths.
  ///
  /// [detParam] - path to detection model param file
  /// [detModel] - path to detection model bin file
  /// [recParam] - path to recognition model param file
  /// [recModel] - path to recognition model bin file
  /// [sizeid] - target size index (0=320, 1=400, 2=480, 3=560, 4=640)
  /// [cpugpu] - 0=CPU, 1=GPU, 2=GPU(Turnip)
  Future<bool> loadModel({
    required String detParam,
    required String detModel,
    required String recParam,
    required String recModel,
    int sizeid = 0,
    int cpugpu = 0,
  }) {
    return OcrPlatform.instance.loadModel(
      detParam: detParam,
      detModel: detModel,
      recParam: recParam,
      recModel: recModel,
      sizeid: sizeid,
      cpugpu: cpugpu,
    );
  }

  Future<bool> openCamera(int facing) {
    return OcrPlatform.instance.openCamera(facing);
  }

  Future<bool> closeCamera() {
    return OcrPlatform.instance.closeCamera();
  }

  /// Toggle camera flash/torch on/off.
  Future<bool> toggleFlash() {
    return OcrPlatform.instance.toggleFlash();
  }

  /// Take a photo and save to [savePath]. Returns the saved file path.
  Future<String?> takePhoto(String savePath) {
    return OcrPlatform.instance.takePhoto(savePath);
  }

  /// Get the latest OCR recognized text (newline-separated lines).
  Future<String?> getOcrText() {
    return OcrPlatform.instance.getOcrText();
  }
}
