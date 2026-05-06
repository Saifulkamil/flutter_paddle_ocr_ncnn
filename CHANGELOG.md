## 0.0.4

- Added detect-only bounding box preview in photo mode (no OCR until capture).
- Full sensor frame capture: saved images now use the complete camera resolution.
- OCR processing limited to overlay/scan area only for accurate text detection.
- Bounding boxes and text labels drawn on full-frame output image.
- Added full-screen image viewer with pinch-to-zoom in example app.
- Fixed `ocrFromImage` to save annotated image as separate file (no overwrite).

## 0.0.3

- Added `abiFilters` documentation to significantly reduce Android APK size.
- Added Platform Support table to README.md.
- Updated homepage and repository links in pubspec.yaml.

## 0.0.2

- Added flash (torch) control and camera toggle features.
- Optimized camera polling mechanism for real-time OCR.
- Improved Android NDK camera stability.

## 0.0.1

- Initial release of the Flutter Paddle OCR plugin.
- Integrated C++ NCNN backend for offline OCR processing.
- Added real-time text scanning and high-resolution photo capture functionality.
