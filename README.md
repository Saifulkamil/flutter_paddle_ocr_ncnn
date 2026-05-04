# Flutter Paddle OCR 📸

[![pub package](https://img.shields.io/pub/v/flutter_paddle_ocr.svg)](https://pub.dev/packages/flutter_paddle_ocr)

A high-performance Flutter plugin for performing **offline Optical Character Recognition (OCR)** on Android using **PaddleOCR** and **NCNN**. 

This plugin supports real-time text scanning directly from the camera feed and capturing photos with immediate, on-device OCR text extraction. It processes everything locally using C++ (NCNN), meaning it is **extremely fast** and requires **zero internet connection**.

## ✨ Key Features
- ⚡ **Real-time OCR**: Read and detect text instantly from the live camera preview.
- 📸 **Photo Capture with OCR**: Save high-resolution images from the camera along with the extracted text.
- 📴 **100% Offline**: Uses local NCNN models. No API calls or cloud dependencies.
- 🎛️ **Camera Controls**: Seamlessly switch between front and back cameras and toggle the flash (torch).
- 🔋 **Optimized for Mobile**: Leverages C++ and NDK for minimal latency and memory usage.

---

## 📱 Platform Support

| Platform | Support | Note |
| :--- | :---: | :--- |
| **Android** | ✅ | Fully supported (Requires Android 7.0 / API 24+) |
| **iOS** | ❌ | Not supported (Currently in development / Planned) |
| **Web** | ❌ | Not supported |
| **Desktop** | ❌ | Not supported |

---

## ⚙️ Android Setup (Required)

### 1. Minimum SDK Version
Ensure your `android/app/build.gradle` has a `minSdkVersion` of at least `24`:
```gradle
android {
    defaultConfig {
        minSdkVersion 24
    }
}
```

### 2. Reduce APK Size (Crucial) 🚨
By default, Flutter builds for multiple architectures. NCNN libraries can drastically increase your APK size if you build for all of them (including emulators). **To keep your APK size small**, filter the architectures to only physical ARM devices.

Add `abiFilters` in your application's `android/app/build.gradle` (or `build.gradle.kts`):
```kotlin
android {
    defaultConfig {
        ndk {
            // Only build for physical ARM devices, ignore x86/x86_64 (Emulators)
            abiFilters += listOf("arm64-v8a", "armeabi-v7a")
        }
    }
}
```

### 3. Testing on Android Emulators (x86 / x86_64) 🖥️
To keep this plugin lightweight for pub.dev, the massive `x86` and `x86_64` pre-compiled C++ libraries for NCNN and OpenCV have been removed. By default, you can only build and run this plugin on **physical Android devices** (ARM architectures).

If you want to test your app on a PC Android Emulator, you need to manually restore these architectures:
1. **Remove `abiFilters`**: Remove the `abiFilters` block shown in Step 2 from your app's `build.gradle`.
2. **Download NCNN**: Go to [Tencent/ncnn releases](https://github.com/Tencent/ncnn/releases) and download the `ncnn-android-vulkan.zip`. Extract the `x86` and `x86_64` folders into your Flutter plugin directory at: `android/src/main/jni/ncnn-[version]-android-vulkan/`.
3. **Download OpenCV Mobile**: Go to [nihui/opencv-mobile](https://github.com/nihui/opencv-mobile) and download the `opencv-mobile-android.zip`. Extract the `abi-x86` and `abi-x86_64` folders (both in `sdk/native/jni/` and `sdk/native/staticlibs/`) into your plugin directory at: `android/src/main/jni/opencv-mobile-[version]-android/`.
4. Run `flutter clean` and build your app again.

### 4. Camera Permissions
Add the camera permission to your `android/app/src/main/AndroidManifest.xml`:
```xml
<uses-permission android:name="android.permission.CAMERA" />
<uses-feature android:name="android.hardware.camera" />
```
*(Make sure to also request permissions at runtime in your Flutter code using a package like `permission_handler`).*

---

## 🛠 Getting Started

### 1. Prepare NCNN Model Files
This plugin requires 4 PaddleOCR model files converted to the NCNN format:
- **Detection Model**: `det.ncnn.param` & `det.ncnn.bin`
- **Recognition Model**: `rec.ncnn.param` & `rec.ncnn.bin`

Place these files inside the `assets/` folder of your Flutter project, and declare them in your `pubspec.yaml`:
```yaml
flutter:
  assets:
    - assets/det.ncnn.param
    - assets/det.ncnn.bin
    - assets/rec.ncnn.param
    - assets/rec.ncnn.bin
```

---

## 🚀 Usage

### 1. Import the Plugin
```dart
import 'package:fast_paddle_ocr/ocr.dart';
import 'package:fast_paddle_ocr/ocr_camera_view.dart';
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

### 4. Camera Controls
Once the model is loaded, you can control the camera:

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

## 💡 Tips & Best Practices
1. **Memory Management**: Always ensure you call `stopOcrPolling()` and `closeCamera()` inside the `dispose()` method of your `StatefulWidget` to prevent memory leaks and camera lock-ups.
2. **Model Choice**: Lightweight mobile PaddleOCR models (`ch_PP-OCRv3_det_opt`, etc.) are highly recommended. Heavier server-side models will require too much CPU/GPU overhead.
3. **Lighting**: Text is detected much more accurately with good lighting. Hook up the `toggleFlash()` method to a flashlight button in your UI for low-light scanning.
4. **GPU vs CPU**: If a device supports it, switching `cpugpu: 1` might speed up processing, but CPU is generally more stable across all Android devices.
