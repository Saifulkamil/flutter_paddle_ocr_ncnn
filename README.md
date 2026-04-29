# Flutter Paddle OCR

A Flutter plugin for performing offline Optical Character Recognition (OCR) on Android using **PaddleOCR** and **NCNN**. This plugin supports real-time text scanning via the camera and capturing photos with immediate OCR text extraction.

## Key Features
- **Real-time OCR**: Read and detect text directly from the camera preview.
- **Photo Capture**: Save images from the camera along with the extracted OCR text.
- **Offline / On-Device**: Uses local NCNN models, making the process extremely fast and requiring no internet connection.
- **Camera Controls**: Supports camera switching (front/back) and flash (torch) control.

---

## 🛠 Getting Started

### 1. Prepare NCNN Model Files
This plugin requires 4 PaddleOCR model files that have been converted to NCNN format:
- Detection Model: `det.ncnn.param` & `det.ncnn.bin`
- Recognition Model: `rec.ncnn.param` & `rec.ncnn.bin`

Place these files inside the `assets/` folder of your Flutter project, and make sure to declare them in your `pubspec.yaml` file:
```yaml
assets:
  - assets/det.ncnn.param
  - assets/det.ncnn.bin
  - assets/rec.ncnn.param
  - assets/rec.ncnn.bin
```

### 2. Camera Permission
Your app needs camera access. Use a package like `permission_handler` to request permission before opening the camera.

---

## 🚀 Usage

### 1. Import the Plugin
```dart
import 'package:flutter_paddle_ocr/ocr.dart';
import 'package:flutter_paddle_ocr/ocr_camera_view.dart';
```

### 2. Initialize and Load Model
Native C++ (NCNN) requires a physical file path (not an asset bundle). Therefore, you must **copy the model files from assets to the app's internal storage** first.

```dart
final ocrPlugin = Ocr();

// Helper function to copy assets to local storage
Future<String> copyAssetToFile(String assetName) async {
  final dir = await getApplicationDocumentsDirectory();
  final file = File('${dir.path}/$assetName');
  if (!await file.exists()) {
    final data = await rootBundle.load('assets/$assetName');
    await file.writeAsBytes(data.buffer.asUint8List());
  }
  return file.path;
}

// Model loading process
Future<void> initModel() async {
  final detParam = await copyAssetToFile('det.ncnn.param');
  final detModel = await copyAssetToFile('det.ncnn.bin');
  final recParam = await copyAssetToFile('rec.ncnn.param');
  final recModel = await copyAssetToFile('rec.ncnn.bin');

  await ocrPlugin.loadModel(
    detParam: detParam,
    detModel: detModel,
    recParam: recParam,
    recModel: recModel,
    sizeid: 0, // Size options: 0=320, 1=400, 2=480, 3=560, 4=640
    cpugpu: 0, // Computing options: 0=CPU, 1=GPU, 2=GPU(Turnip)
  );
}
```

### 3. Display Camera Preview (UI)
Use the `OcrCameraView` widget inside a `Scaffold` or your layout widget to display the camera feed.

```dart
@override
Widget build(BuildContext context) {
  return Scaffold(
    body: Stack(
      children: [
        OcrCameraView(), // Displays fullscreen camera
        // Add overlay UI (scan frame, buttons) on top here
      ],
    ),
  );
}
```

### 4. Camera Controls (Open, Close, Flash, Switch)
Once the model is loaded, you can control the camera.

```dart
// Open camera (0 = Back Camera, 1 = Front Camera)
await ocrPlugin.openCamera(0);

// Toggle Flash (Torch)
await ocrPlugin.toggleFlash();

// Close camera
await ocrPlugin.closeCamera();
```

### 5. Get Real-time OCR Results
Use `Timer.periodic` to continuously monitor the OCR results detected by the camera.

```dart
Timer? ocrTimer;

void startOcrPolling() {
  ocrTimer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
    final text = await ocrPlugin.getOcrText();
    if (text != null && text.isNotEmpty) {
      print("Detection Result: $text");
      // Update UI (setState) here
    }
  });
}

void stopOcrPolling() {
  ocrTimer?.cancel();
}
```

### 6. Capture Photo with OCR Results
You can capture a full-resolution image and automatically get the photo file along with the OCR text caught at the moment of capture.

```dart
Future<void> captureImage() async {
  final dir = await getApplicationDocumentsDirectory();
  final savePath = '${dir.path}/ocr_photo.jpg';

  // Run in parallel: Save photo & Get the latest OCR text
  final results = await Future.wait([
    ocrPlugin.takePhoto(savePath),
    ocrPlugin.getOcrText(),
  ]);

  final savedPhotoPath = results[0];
  final ocrText = results[1];

  print("Photo saved at: $savedPhotoPath");
  print("Text in photo: $ocrText");
}
```

---

## 💡 Tips & Notes
1. **Memory and Performance**: Always make sure to call `stopOcrPolling()` and `closeCamera()` inside the `dispose()` method of your `StatefulWidget` to prevent memory leaks.
2. **Model Suitability**: Mobile/Lightweight PaddleOCR models are recommended. Heavier models require higher CPU/GPU resources.
3. **Camera Quality**: Text will be detected more accurately with sufficient lighting. Use the `toggleFlash()` function in low-light conditions.
