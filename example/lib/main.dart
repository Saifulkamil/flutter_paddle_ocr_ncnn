import 'dart:io';
import 'package:flutter/material.dart';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_paddle_ocr/ocr.dart';
import 'package:flutter_paddle_ocr/ocr_camera_view.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(debugShowCheckedModeBanner: false, theme: ThemeData.dark(), home: const OcrScanScreen());
  }
}

// Model untuk menyimpan hasil foto + OCR
class OcrCapture {
  final String photoPath;
  final String ocrText;
  final DateTime timestamp;

  OcrCapture({required this.photoPath, required this.ocrText, required this.timestamp});
}

class OcrScanScreen extends StatefulWidget {
  const OcrScanScreen({super.key});

  @override
  State<OcrScanScreen> createState() => _OcrScanScreenState();
}

class _OcrScanScreenState extends State<OcrScanScreen> with SingleTickerProviderStateMixin {
  final _ocrPlugin = Ocr();

  int _facing = 0;
  bool _cameraOpen = false;
  bool _flashOn = false;
  bool _modelLoaded = false;
  Timer? _ocrTimer;
  late AnimationController _scanAnimController;
  late Animation<double> _scanAnim;

  String _ocrResult = '';

  // Hasil capture terbaru
  OcrCapture? _latestCapture;

  // Semua riwayat capture
  final List<OcrCapture> _captureHistory = [];

  // Mode: true = tampilkan preview foto, false = tampilkan kamera
  bool _showPreview = false;

  @override
  void initState() {
    super.initState();
    _scanAnimController = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _scanAnim = Tween<double>(
      begin: 0.05,
      end: 0.90,
    ).animate(CurvedAnimation(parent: _scanAnimController, curve: Curves.easeInOut));
    _requestPermission();
  }

  Future<void> _requestPermission() async {
    final status = await Permission.camera.request();
    if (status.isGranted) {
      await _loadModel();
    }
  }

  Future<String> _copyAssetToFile(String assetName) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$assetName');
    if (!await file.exists()) {
      final data = await rootBundle.load('assets/$assetName');
      await file.writeAsBytes(data.buffer.asUint8List());
    }
    return file.path;
  }

  Future<void> _loadModel() async {
    try {
      final detParam = await _copyAssetToFile('PP_OCRv5_mobile_det.ncnn.param');
      final detModel = await _copyAssetToFile('PP_OCRv5_mobile_det.ncnn.bin');
      final recParam = await _copyAssetToFile('PP_OCRv5_mobile_rec.ncnn.param');
      final recModel = await _copyAssetToFile('PP_OCRv5_mobile_rec.ncnn.bin');

      await _ocrPlugin.loadModel(
        detParam: detParam,
        detModel: detModel,
        recParam: recParam,
        recModel: recModel,
        sizeid: 0,
        cpugpu: 0,
      );

      setState(() => _modelLoaded = true);
      await _openCamera();
    } catch (e) {
      debugPrint('Error loading model: $e');
    }
  }

  Future<void> _openCamera() async {
    try {
      await _ocrPlugin.openCamera(_facing);
      setState(() {
        _cameraOpen = true;
        _showPreview = false;
      });
      _startOcrPolling();
    } catch (e) {
      debugPrint('Error opening camera: $e');
    }
  }

  Future<void> _closeCamera() async {
    try {
      _stopOcrPolling();
      await _ocrPlugin.closeCamera();
      setState(() {
        _cameraOpen = false;
        _flashOn = false;
        _ocrResult = '';
        _showPreview = false;
      });
    } catch (e) {
      debugPrint('Error closing camera: $e');
    }
  }

  Future<void> _switchCamera() async {
    try {
      _stopOcrPolling();
      await _ocrPlugin.closeCamera();
      _facing = 1 - _facing;
      _flashOn = false;
      await _ocrPlugin.openCamera(_facing);
      setState(() => _cameraOpen = true);
      _startOcrPolling();
    } catch (e) {
      debugPrint('Error switching camera: $e');
    }
  }

  Future<void> _toggleFlash() async {
    try {
      await _ocrPlugin.toggleFlash();
      setState(() => _flashOn = !_flashOn);
    } catch (e) {
      debugPrint('Error toggling flash: $e');
    }
  }

  Future<void> _captureImage() async {
    // Jika sedang preview → ambil foto baru lagi
    if (_showPreview) {
      setState(() => _showPreview = false);
      return;
    }

    try {
      final dir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final savePath = '${dir.path}/ocr_photo_$timestamp.jpg';

      final results = await Future.wait([_ocrPlugin.takePhoto(savePath), _ocrPlugin.getOcrText()]);
      final photoPath = results[0] as String?;
      final ocrSnapshot = results[1] as String?;

      if (photoPath != null && photoPath.isNotEmpty) {
        final capture = OcrCapture(photoPath: photoPath, ocrText: ocrSnapshot ?? '', timestamp: DateTime.now());

        setState(() {
          _latestCapture = capture;
          _captureHistory.insert(0, capture); // simpan ke riwayat
          _ocrResult = ocrSnapshot ?? '';
          _showPreview = true; // tampilkan preview
        });
      }
    } catch (e) {
      debugPrint('Error taking photo: $e');
    }
  }

  void _startOcrPolling() {
    _ocrTimer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      if (!_cameraOpen || _showPreview) return;
      try {
        final text = await _ocrPlugin.getOcrText();
        if (mounted && text != null) {
          setState(() => _ocrResult = text);
        }
      } catch (_) {}
    });
  }

  void _stopOcrPolling() {
    _ocrTimer?.cancel();
    _ocrTimer = null;
  }

  void _showHistory() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      isScrollControlled: true,
      builder: (_) => _HistorySheet(captures: _captureHistory),
    );
  }

  @override
  void dispose() {
    _scanAnimController.dispose();
    _stopOcrPolling();
    _ocrPlugin.closeCamera();
    super.dispose();
  }

  Widget _buildScanArea() {
    const double frameW = 300;
    const double frameH = 220;
    const double cornerLen = 28;
    const double strokeW = 3.5;
    const double radius = 16.0;

    return SizedBox(
      width: frameW,
      height: frameH,
      child: Stack(
        children: [
          // Scan line animasi
          if (!_showPreview)
            AnimatedBuilder(
              animation: _scanAnim,
              builder: (_, __) {
                return Positioned(
                  top: _scanAnim.value * frameH,
                  left: 14,
                  right: 14,
                  child: Container(
                    height: 2.5,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          Colors.blueAccent.withOpacity(0.8),
                          Colors.white.withOpacity(0.95),
                          Colors.blueAccent.withOpacity(0.8),
                          Colors.transparent,
                        ],
                      ),
                      boxShadow: [BoxShadow(color: Colors.blueAccent.withOpacity(0.5), blurRadius: 8, spreadRadius: 2)],
                    ),
                  ),
                );
              },
            ),

          // Corner brackets
          CustomPaint(
            size: const Size(frameW, frameH),
            painter: _CornerBracketPainter(
              cornerLength: cornerLen,
              strokeWidth: strokeW,
              color: Colors.white,
              radius: radius,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Full-screen camera
          if (_cameraOpen && !_showPreview) const Positioned.fill(child: OcrCameraView()),

          // Full-screen preview foto
          if (_showPreview && _latestCapture != null)
            Positioned.fill(child: Image.file(File(_latestCapture!.photoPath), fit: BoxFit.cover)),

          // Dark overlay
          if (!_showPreview) Positioned.fill(child: Container(color: Colors.black.withOpacity(0.45))),

          // Light overlay saat preview
          if (_showPreview) Positioned.fill(child: Container(color: Colors.black.withOpacity(0.3))),

          // Main UI
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 20),

                // Title
                Text(
                  _showPreview ? "Hasil Foto" : "Arahkan kamera ke barcode",
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 6),
                Text(
                  _showPreview ? "Tekan foto lagi untuk scan baru" : "Pastikan barcode berada di dalam area",
                  style: const TextStyle(color: Colors.white60, fontSize: 13),
                ),

                const SizedBox(height: 28),

                // Scan frame overlay
                Center(child: _buildScanArea()),

                const Spacer(),

                // Flash + Switch Camera buttons
                if (_cameraOpen && !_showPreview)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Flash button
                        _ActionButton(
                          icon: _flashOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                          label: _flashOn ? "Flash On" : "Flash Off",
                          active: _flashOn,
                          activeColor: Colors.amber,
                          onTap: _toggleFlash,
                        ),

                        const SizedBox(width: 32),

                        // Switch Camera button
                        _ActionButton(
                          icon: Icons.cameraswitch_rounded,
                          label: "Putar",
                          active: false,
                          activeColor: Colors.blueAccent,
                          onTap: _switchCamera,
                        ),

                        // History button
                        if (_captureHistory.isNotEmpty) ...[
                          const SizedBox(width: 32),
                          _ActionButton(
                            icon: Icons.photo_library_outlined,
                            label: "Riwayat",
                            active: false,
                            activeColor: Colors.greenAccent,
                            onTap: _showHistory,
                          ),
                        ],
                      ],
                    ),
                  ),

                // Jika preview: history button
                if (_showPreview && _captureHistory.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: TextButton.icon(
                      onPressed: _showHistory,
                      icon: const Icon(Icons.photo_library_outlined, color: Colors.white70, size: 18),
                      label: Text(
                        "Lihat semua (${_captureHistory.length})",
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ),
                  ),

                const SizedBox(height: 12),

                // Tombol Ambil Gambar / Foto Baru
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _cameraOpen ? _captureImage : null,
                      icon: Icon(_showPreview ? Icons.camera_alt_outlined : Icons.camera_alt_rounded, size: 20),
                      label: Text(_showPreview ? "Foto Baru" : "Ambil Gambar", style: const TextStyle(fontSize: 15)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _showPreview ? const Color(0xFF1A3A5C) : const Color(0xFF2A2A2A),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // Hasil OCR box
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: const Color(0xFF1C1C1E), borderRadius: BorderRadius.circular(16)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              "Hasil OCR",
                              style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
                            ),
                            const Spacer(),
                            if (_showPreview)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.greenAccent.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.check_circle, color: Colors.greenAccent, size: 14),
                                    SizedBox(width: 4),
                                    Text("Tersimpan", style: TextStyle(color: Colors.greenAccent, fontSize: 11)),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                          constraints: const BoxConstraints(maxHeight: 100),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2C2C2E),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: SingleChildScrollView(
                            child: Text(
                              _ocrResult.isEmpty ? "Belum ada hasil" : _ocrResult,
                              style: TextStyle(
                                color: _ocrResult.isEmpty ? Colors.white38 : Colors.white,
                                fontSize: 16,
                                fontWeight: _ocrResult.isEmpty ? FontWeight.normal : FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 32),
              ],
            ),
          ),

          // Close / Open Camera Button
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            child: IconButton(
              icon: Icon(_cameraOpen ? Icons.close : Icons.videocam, color: Colors.white, size: 26),
              onPressed: _cameraOpen ? _closeCamera : (_modelLoaded ? _openCamera : null),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Reusable action button (flash/switch/history) ───────────────────────────

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final Color activeColor;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: active ? activeColor.withOpacity(0.2) : const Color(0xFF2A2A2A),
              shape: BoxShape.circle,
              border: Border.all(color: active ? activeColor : Colors.white24, width: 1.5),
            ),
            child: Icon(icon, color: active ? activeColor : Colors.white, size: 24),
          ),
          const SizedBox(height: 6),
          Text(label, style: TextStyle(color: active ? activeColor : Colors.white60, fontSize: 11)),
        ],
      ),
    );
  }
}

// ─── Bottom sheet riwayat capture ────────────────────────────────────────────

class _HistorySheet extends StatelessWidget {
  final List<OcrCapture> captures;

  const _HistorySheet({required this.captures});

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      expand: false,
      builder: (_, scrollController) {
        return Column(
          children: [
            // Handle
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(4)),
            ),
            const SizedBox(height: 16),
            const Text(
              "Riwayat Scan",
              style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: captures.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (_, i) {
                  final cap = captures[i];
                  return Container(
                    decoration: BoxDecoration(color: const Color(0xFF2C2C2E), borderRadius: BorderRadius.circular(14)),
                    child: Row(
                      children: [
                        // Thumbnail
                        ClipRRect(
                          borderRadius: const BorderRadius.horizontal(left: Radius.circular(14)),
                          child: Image.file(
                            File(cap.photoPath),
                            width: 90,
                            height: 90,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              width: 90,
                              height: 90,
                              color: Colors.grey[800],
                              child: const Icon(Icons.broken_image, color: Colors.white38),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Info
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  cap.ocrText.isEmpty ? "Tidak ada teks" : cap.ocrText,
                                  style: TextStyle(
                                    color: cap.ocrText.isEmpty ? Colors.white38 : Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _formatTime(cap.timestamp),
                                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '${dt.day}/${dt.month}/${dt.year}  $h:$m:$s';
  }
}

// ─── Corner bracket painter ───────────────────────────────────────────────────

class _CornerBracketPainter extends CustomPainter {
  final double cornerLength;
  final double strokeWidth;
  final Color color;
  final double radius;

  const _CornerBracketPainter({
    required this.cornerLength,
    required this.strokeWidth,
    required this.color,
    required this.radius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final w = size.width;
    final h = size.height;
    final r = radius;
    final c = cornerLength;
    const pi = 3.14159265358979;

    // Top-left
    canvas.drawLine(Offset(r, 0), Offset(r + c, 0), paint);
    canvas.drawArc(Rect.fromLTWH(0, 0, r * 2, r * 2), -pi / 2, -pi / 2, false, paint);
    canvas.drawLine(Offset(0, r), Offset(0, r + c), paint);

    // Top-right
    canvas.drawLine(Offset(w - r - c, 0), Offset(w - r, 0), paint);
    canvas.drawArc(Rect.fromLTWH(w - r * 2, 0, r * 2, r * 2), -pi / 2, pi / 2, false, paint);
    canvas.drawLine(Offset(w, r), Offset(w, r + c), paint);

    // Bottom-left
    canvas.drawLine(Offset(0, h - r - c), Offset(0, h - r), paint);
    canvas.drawArc(Rect.fromLTWH(0, h - r * 2, r * 2, r * 2), pi / 2, pi / 2, false, paint);
    canvas.drawLine(Offset(r, h), Offset(r + c, h), paint);

    // Bottom-right
    canvas.drawLine(Offset(w, h - r - c), Offset(w, h - r), paint);
    canvas.drawArc(Rect.fromLTWH(w - r * 2, h - r * 2, r * 2, r * 2), pi / 2, -pi / 2, false, paint);
    canvas.drawLine(Offset(w - r - c, h), Offset(w - r, h), paint);
  }

  @override
  bool shouldRepaint(_CornerBracketPainter old) => false;
}
