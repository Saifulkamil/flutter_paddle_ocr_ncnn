# Fast Paddle OCR 📸

[![pub package](https://img.shields.io/pub/v/fast_paddle_ocr.svg)](https://pub.dev/packages/fast_paddle_ocr)
[![License](https://img.shields.io/badge/License-Creative_Commons-blue.svg)](https://creativecommons.org/)

A high-performance Flutter plugin for performing **offline Optical Character Recognition (OCR)** on Android using **PaddleOCR** and **NCNN**.

This plugin supports real-time text scanning directly from the camera feed, photo capture with bounding box visualization, and on-device OCR text extraction. It processes everything locally using C++ (NCNN), meaning it is **extremely fast** and requires **zero internet connection**.

## ✨ Key Features

- ⚡ **Real-time OCR**: Read and detect text instantly from the live camera preview.
- 🚀 **Advanced Dual-Thread Architecture**: Decoupled Detection (DBNet) and Recognition (CRNN) threads for maximum performance.
- 🎯 **IoU Bounding Box Tracking**: Ultra-smooth 15-20 FPS box tracking that instantly locks onto moving text.
- 🔋 **Extreme Battery Efficiency**: Throttled recognition thread (~3 FPS) prevents overheating while maintaining fluid UI tracking.
- 🧠 **Dynamic CPU Allocation**: Smart detection of device CPU cores to allocate optimal threads between detection and recognition models.
- 🔤 **Native C++ Text Filtering**: Clean output out-of-the-box by automatically filtering out non-alphanumeric characters.
- 📸 **Photo Capture with OCR**: Save high-resolution images with bounding boxes and extracted text.
- 🔍 **Photo Mode Preview**: Detect-only bounding box preview while aiming the camera (no OCR until capture).
- 🖼️ **Full Sensor Frame Capture**: Saved images use the complete camera resolution, not the preview crop.
- 📴 **100% Offline**: Uses local NCNN models. No API calls or cloud dependencies.



---

## 🎥 Demo

Experience the plugin in action! *(Replace the placeholder links below with your uploaded media)*

### 📹 Video Demonstrations

<table align="center">
  <tr>
    <td align="center"><b>Real-Time Tracking & OCR</b></td>
    <td align="center"><b>Photo Mode (Auto-Crop)</b></td>
  </tr>
  <tr>
    <td align="center">
      <!-- REPLACE THIS LINK WITH YOUR REALTIME VIDEO -->
         <a href="#">
          <video src="https://github.com/user-attachments/assets/08221d92-b981-4315-ab59-4c61f2237e05" alt="Realtime Video Demo" width="250"" controls></video></a>
    </td>
    <td align="center">
      <!-- REPLACE THIS LINK WITH YOUR PHOTO MODE VIDEO -->
          <a href="#">
          <video src="https://github.com/user-attachments/assets/ba8db6cd-767a-4278-9271-81370ac13844" alt="Realtime Video Demo" width="250"" controls></video></a>
    </td>
  </tr>
</table>

### 📸 Screenshots

<table align="center">
  <tr>
    <td align="center"><b>Real-Time Scan UI</b></td>
    <td align="center"><b>Photo Capture Result</b></td>
  </tr>
  <tr>
    <td align="center">
      <!-- REPLACE THE SRC BELOW WITH YOUR REALTIME IMAGE -->
      <img src="https://github.com/user-attachments/assets/3251891a-7306-42f2-ba0b-0403e497a091" alt="Realtime OCR Interface" width="250">
    </td>
    <td align="center">
      <!-- REPLACE THE SRC BELOW WITH YOUR PHOTO MODE IMAGE -->
      <img src="https://github.com/user-attachments/assets/74dbfe35-3bbf-4de7-883a-e82a8297c123" alt="Photo Capture Result" width="250">
    </td>
  </tr>
</table>

---
 

## 📱 Platform Support

| Platform    | Support | Note                                               |
| :---------- | :-----: | :------------------------------------------------- |
| **Android** |   ✅    | Fully supported (Requires Android 7.0 / API 24+)   |
| **iOS**     |   ❌    | Not supported (Currently in development / Planned) |
| **Web**     |   ❌    | Not supported                                      |
| **Desktop** |   ❌    | Not supported                                      |

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

_(Make sure to also request permissions at runtime in your Flutter code using a package like `permission_handler`)._

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

### 5. Photo Mode with Scan Area Overlay

Use Photo Mode to show detect-only bounding boxes during preview and run full OCR only on capture. Set a target rect to limit OCR processing to a specific scan area.

```dart
// Enable photo mode (detect-only preview, full OCR on capture)
await ocrPlugin.setPhotoMode(true);

// Set scan area overlay (normalized 0.0–1.0 relative to camera widget)
// Example: scan area is 85% width and 70% height of the camera view
await ocrPlugin.setTargetRect(0.85, 0.70);
```

### 6. Get Real-time OCR Results

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

### 7. Capture Photo with OCR Results

Capture a full-resolution image with bounding boxes and text labels drawn on the detected text areas.

```dart
Future<void> captureImage() async {
  final dir = await getApplicationDocumentsDirectory();
  final savePath = '${dir.path}/ocr_photo.jpg';

  // Take photo — returns "originalPath|annotatedPath"
  final resultPaths = await ocrPlugin.takePhoto(savePath);

  if (resultPaths != null && resultPaths.isNotEmpty) {
    final paths = resultPaths.split('|');
    final originalPath = paths[0];        // Clean full-frame image
    final annotatedPath = paths.length > 1 ? paths[1] : ''; // Full-frame with bounding boxes

    // Get OCR text extracted during capture
    final ocrText = await ocrPlugin.getOcrText();

    print("Original photo: $originalPath");
    print("Annotated photo: $annotatedPath");
    print("OCR text: $ocrText");
  }
}
```

### 8. OCR from Static Image File

Run OCR on an existing image file (e.g., from gallery). The annotated image is saved as a separate `_bbox` file.

```dart
final text = await ocrPlugin.ocrFromImage('/path/to/image.jpg');
print("Recognized text: $text");
// Annotated image saved at: /path/to/image_bbox.jpg
```

---

## 📝 API Reference

| Method                | Description                                               |
| :-------------------- | :-------------------------------------------------------- |
| `loadModel(...)`      | Load OCR detection and recognition models from file paths |
| `openCamera(facing)`  | Open camera (0 = back, 1 = front)                         |
| `closeCamera()`       | Close the camera                                          |
| `toggleFlash()`       | Toggle camera flash/torch on/off                          |
| `setPhotoMode(bool)`  | Enable/disable photo mode (detect-only preview)           |
| `setTargetRect(w, h)` | Set normalized scan area overlay for OCR processing       |
| `takePhoto(savePath)` | Capture photo, returns `"originalPath\|annotatedPath"`    |
| `getOcrText()`        | Get latest OCR recognized text                            |
| `ocrFromImage(path)`  | Run OCR on a static image file, returns text              |
| `cropImage(path)`     | Launch native image cropper                               |

---

## 💡 Tips & Best Practices

1. **Memory Management**: Always call `stopOcrPolling()` and `closeCamera()` inside `dispose()` to prevent memory leaks and camera lock-ups.
2. **Model Choice**: Lightweight mobile PaddleOCR models (`PP-OCRv5_mobile`) are highly recommended. Heavier server-side models will require too much CPU/GPU overhead.
3. **Lighting**: Text is detected much more accurately with good lighting. Hook up `toggleFlash()` to a flashlight button for low-light scanning.
4. **GPU vs CPU**: If a device supports it, switching `cpugpu: 1` might speed up processing, but CPU is generally more stable across all Android devices.
5. **Photo Mode**: Use `setPhotoMode(true)` for battery-efficient scanning — the preview shows detection boxes only, and full OCR runs only when you capture.
6. **Scan Area**: Use `setTargetRect()` to focus OCR on a specific region, improving accuracy and speed by ignoring irrelevant text outside the scan area.

---

## 📄 License

This project is licensed under the [Creative Commons Legal Code](LICENSE).
