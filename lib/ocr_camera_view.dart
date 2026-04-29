import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class OcrCameraView extends StatelessWidget {
  const OcrCameraView({super.key});

  @override
  Widget build(BuildContext context) {
    return const AndroidView(
      viewType: 'ocr_camera_view',
      creationParamsCodec: StandardMessageCodec(),
    );
  }
}
