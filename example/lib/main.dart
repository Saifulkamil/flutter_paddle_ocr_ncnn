import 'dart:io';
import 'package:flutter/material.dart';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:fast_paddle_ocr/ocr.dart';
import 'package:fast_paddle_ocr/ocr_camera_view.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(debugShowCheckedModeBanner: false, theme: ThemeData.light(), home: const OcrScanScreen());
  }
}

// Model untuk menyimpan hasil foto + OCR
class OcrCapture {
  final String photoPath;
  final String croppedPath;
  final String ocrText;
  final DateTime timestamp;

  OcrCapture({required this.photoPath, this.croppedPath = '', required this.ocrText, required this.timestamp});
}

enum OcrMode { realtime, photo }

class OcrScanScreen extends StatefulWidget {
  const OcrScanScreen({super.key});

  @override
  State<OcrScanScreen> createState() => _OcrScanScreenState();
}

class _OcrScanScreenState extends State<OcrScanScreen> with SingleTickerProviderStateMixin {
  final _ocrPlugin = Ocr();

  OcrMode _mode = OcrMode.realtime;
  int _facing = 0;
  bool _cameraOpen = false;
  bool _flashOn = false;
  bool _modelLoaded = false;
  bool _isLoadingModel = false;
  String _modelSource = 'assets'; // 'assets' atau 'phone'
  Timer? _ocrTimer;
  late AnimationController _scanAnimController;
  late Animation<double> _scanAnim;

  String _ocrResult = '';

  // Path model yang sedang aktif
  String? _activeDetParam;
  String? _activeDetModel;
  String? _activeRecParam;
  String? _activeRecModel;

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
      setState(() => _isLoadingModel = true);
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

      setState(() {
        _modelLoaded = true;
        _isLoadingModel = false;
        _modelSource = 'assets';
        _activeDetParam = detParam;
        _activeDetModel = detModel;
        _activeRecParam = recParam;
        _activeRecModel = recModel;
      });
      await _openCamera();
    } catch (e) {
      setState(() => _isLoadingModel = false);
      debugPrint('Error loading model: $e');
    }
  }

  /// Tampilkan dialog untuk memilih model dari HP
  Future<void> _loadModelFromPhone() async {
    // Tutup kamera dulu jika sedang terbuka
    if (_cameraOpen) {
      await _closeCamera();
    }

    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ModelPickerSheet(
        activeDetParam: _activeDetParam,
        activeDetModel: _activeDetModel,
        activeRecParam: _activeRecParam,
        activeRecModel: _activeRecModel,
        modelSource: _modelSource,
      ),
    );

    if (result == null) return; // User membatalkan

    // Load model dari path yang dipilih
    try {
      setState(() => _isLoadingModel = true);

      await _ocrPlugin.loadModel(
        detParam: result['det_param']!,
        detModel: result['det_model']!,
        recParam: result['rec_param']!,
        recModel: result['rec_model']!,
        sizeid: 0,
        cpugpu: 0,
      );

      setState(() {
        _modelLoaded = true;
        _isLoadingModel = false;
        _modelSource = 'phone';
        _activeDetParam = result['det_param'];
        _activeDetModel = result['det_model'];
        _activeRecParam = result['rec_param'];
        _activeRecModel = result['rec_model'];
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(backgroundColor: Colors.green, content: Text('✅ Model berhasil dimuat dari HP!')),
        );
      }

      await _openCamera();
    } catch (e) {
      setState(() => _isLoadingModel = false);
      debugPrint('Error loading model from phone: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(backgroundColor: Colors.red, content: Text('Gagal memuat model: $e')));
      }
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
    if (_showPreview) {
      setState(() => _showPreview = false);
      return;
    }
    if (_mode == OcrMode.realtime && _ocrResult.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(backgroundColor: Colors.red, content: Text("Tidak ada hasil OCR")));
      return;
    }

    try {
      final dir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final savePath = '${dir.path}/ocr_photo_$timestamp.jpg';

      if (_mode == OcrMode.photo) {
        setState(() => _isLoadingModel = true); // use loading state for UI
        
        // Ensure target rect is set before capture
        // Use the known overlay dimensions vs the camera area
        final screenW = MediaQuery.of(context).size.width;
        final cameraW = screenW - 32; // margin 16 each side
        final normW = 300.0 / cameraW;
        final normH = 220.0 / 300.0; // safe approximate ratio
        debugPrint('[PhotoMode] setTargetRect normW=$normW, normH=$normH');
        await _ocrPlugin.setTargetRect(normW, normH);
        
        final resultPaths = await _ocrPlugin.takePhoto(savePath);
        debugPrint('[PhotoMode] takePhoto result: $resultPaths');
        
        if (resultPaths != null && resultPaths.isNotEmpty) {
          final paths = resultPaths.split('|');
          final origPath = paths[0];
          final cropPath = paths.length > 1 ? paths[1] : '';
          debugPrint('[PhotoMode] origPath=$origPath, cropPath=$cropPath');
          
          // Try getOcrText first (set during native capture)
          String text = await _ocrPlugin.getOcrText() ?? '';
          debugPrint('[PhotoMode] getOcrText: "$text"');
          
          // If no text from native capture, run ocrFromImage on cropped file as fallback
          if (text.isEmpty && cropPath.isNotEmpty) {
            debugPrint('[PhotoMode] fallback: ocrFromImage on cropPath');
            text = await _ocrPlugin.ocrFromImage(cropPath) ?? '';
          }
          // If still no text and no crop, try on original
          if (text.isEmpty) {
            debugPrint('[PhotoMode] fallback: ocrFromImage on origPath');
            text = await _ocrPlugin.ocrFromImage(origPath) ?? '';
          }

          final capture = OcrCapture(photoPath: origPath, croppedPath: cropPath, ocrText: text, timestamp: DateTime.now());
          setState(() {
            _latestCapture = capture;
            _captureHistory.insert(0, capture);
            _ocrResult = text;
          });
          if (mounted) {
            _showPhotoResultDialog(capture);
          }
        }
        setState(() => _isLoadingModel = false);
      } else {
        // Realtime mode
        final results = await Future.wait([_ocrPlugin.takePhoto(savePath), _ocrPlugin.getOcrText()]);
        final photoPath = results[0] as String?;
        final ocrSnapshot = results[1] as String?;

        if (photoPath != null && photoPath.isNotEmpty) {
          final capture = OcrCapture(photoPath: photoPath, ocrText: ocrSnapshot ?? '', timestamp: DateTime.now());
          setState(() {
            _latestCapture = capture;
            _captureHistory.insert(0, capture);
            _ocrResult = ocrSnapshot ?? '';
            _showPreview = true;
          });
          if (mounted) {
            _showPhotoResultDialog(capture);
          }
        }
      }
    } catch (e) {
      debugPrint("Gagal mengambil foto: $e");
      if (mounted) setState(() => _isLoadingModel = false);
    }
  }

  void _showPhotoResultDialog(OcrCapture capture) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text("Hasil Auto-Crop & OCR", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              
              // Gambar
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        const Text("Gambar Asli", style: TextStyle(fontSize: 12, color: Colors.black54)),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(File(capture.photoPath), height: 140, fit: BoxFit.cover),
                        ),
                      ],
                    ),
                  ),
                  if (capture.croppedPath.isNotEmpty) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        children: [
                          const Text("Hasil Crop", style: TextStyle(fontSize: 12, color: Colors.black54)),
                          const SizedBox(height: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(File(capture.croppedPath), height: 140, fit: BoxFit.cover),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
              
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(10)),
                constraints: const BoxConstraints(maxHeight: 120),
                child: SingleChildScrollView(
                  child: Text(
                    capture.ocrText.isEmpty ? "Tidak ada teks terdeteksi" : capture.ocrText,
                    style: TextStyle(fontSize: 15, color: capture.ocrText.isEmpty ? Colors.black54 : Colors.black87),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: const Text("Tutup", style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Polling hanya untuk realtime mode
  void _startOcrPolling() {
    _ocrTimer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
      if (!_cameraOpen || _showPreview || _mode == OcrMode.photo) return;
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
      backgroundColor: Colors.white,
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

  double _lastSentTargetW = -1;
  double _lastSentTargetH = -1;

  Widget _buildCameraArea() {
    const double frameW = 300;
    const double frameH = 220;
    const double cornerLen = 28;
    const double strokeW = 3.5;
    const double radius = 16.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final double cameraW = constraints.maxWidth - 32; // margin 16 on each side
        final double cameraH = constraints.maxHeight;

        if (cameraW > 0 && cameraH > 0) {
          final normW = frameW / cameraW;
          final normH = frameH / cameraH;
          if (normW != _lastSentTargetW || normH != _lastSentTargetH) {
            _lastSentTargetW = normW;
            _lastSentTargetH = normH;
            _ocrPlugin.setTargetRect(normW, normH);
          }
        }

        return Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              alignment: Alignment.center,
              children: [
                // 1. Camera preview filling the container
                if (_cameraOpen && !_showPreview)
                  const Positioned.fill(child: OcrCameraView()),
                
                // 2. Corner brackets as an overlay in the center
                if (_cameraOpen && !_showPreview)
                  CustomPaint(
                    size: const Size(frameW, frameH),
                    painter: _CornerBracketPainter(
                      cornerLength: cornerLen,
                      strokeWidth: strokeW,
                      color: Colors.lightGreen,
                      radius: radius,
                    ),
                  ),

                // If camera is closed
                if (!_cameraOpen && !_showPreview)
                  Container(
                    color: Colors.grey[200],
                    child: Center(
                      child: Icon(
                        _mode == OcrMode.photo ? Icons.image_outlined : Icons.videocam_off_rounded, 
                        size: 48, 
                        color: Colors.black26
                      )
                    ),
                  ),
              ],
            ),
          ),
        );
      }
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Main UI
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 50),

                // Mode Switcher
                Container(
                  margin: const EdgeInsets.symmetric(horizontal: 24),
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() {
                            _mode = OcrMode.realtime;
                            _ocrPlugin.setPhotoMode(false);
                            _showPreview = false;
                          }),
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: _mode == OcrMode.realtime ? Colors.white : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: _mode == OcrMode.realtime 
                                  ? [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4)]
                                  : null,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              "Realtime",
                              style: TextStyle(
                                color: _mode == OcrMode.realtime ? Colors.blue.shade700 : Colors.black54,
                                fontWeight: _mode == OcrMode.realtime ? FontWeight.w600 : FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setState(() {
                              _mode = OcrMode.photo;
                              _ocrPlugin.setPhotoMode(true);
                              _showPreview = false;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            decoration: BoxDecoration(
                              color: _mode == OcrMode.photo ? Colors.white : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                              boxShadow: _mode == OcrMode.photo 
                                  ? [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4)]
                                  : null,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              "Photo & Crop",
                              style: TextStyle(
                                color: _mode == OcrMode.photo ? Colors.blue.shade700 : Colors.black54,
                                fontWeight: _mode == OcrMode.photo ? FontWeight.w600 : FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Title
                Text(
                  _mode == OcrMode.photo ? "Ambil Foto untuk Di-Crop" : (_showPreview ? "Hasil Foto" : "Arahkan kamera ke teks"),
                  style: const TextStyle(color: Colors.black87, fontSize: 18, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 6),
                Text(
                  _mode == OcrMode.photo ? "Pilih dari galeri atau kamera" : (_showPreview ? "Tekan foto lagi untuk scan baru" : "Pastikan teks berada di dalam area"),
                  style: const TextStyle(color: Colors.black45, fontSize: 13),
                ),

                const SizedBox(height: 28),

                // Scan frame with camera inside
                Expanded(child: Center(child: _buildCameraArea())),

                const SizedBox(height: 24),

                // Hasil OCR box
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              "Hasil OCR",
                              style: TextStyle(color: Colors.black, fontSize: 15, fontWeight: FontWeight.w600),
                            ),
                            const Spacer(),
                            if (_showPreview)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.green.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.check_circle, color: Colors.green, size: 14),
                                    SizedBox(width: 4),
                                    Text("Tersimpan", style: TextStyle(color: Colors.green, fontSize: 11)),
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
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.black12),
                          ),
                          child: SingleChildScrollView(
                            child: Text(
                              _ocrResult.isEmpty ? "Belum ada hasil" : _ocrResult,
                              style: TextStyle(
                                color: _ocrResult.isEmpty ? Colors.black38 : Colors.black87,
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
                const Spacer(),

                // Flash + Switch Camera buttons
                if (_cameraOpen && !_showPreview)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _ActionButton(
                          icon: _flashOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                          label: _flashOn ? "Flash On" : "Flash Off",
                          active: _flashOn,
                          activeColor: Colors.amber,
                          onTap: _toggleFlash,
                        ),
                        const SizedBox(width: 32),
                        _ActionButton(
                          icon: Icons.cameraswitch_rounded,
                          label: "Putar",
                          active: false,
                          activeColor: Colors.green,
                          onTap: _switchCamera,
                        ),
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
                      icon: const Icon(Icons.photo_library_outlined, color: Colors.black54, size: 18),
                      label: Text(
                        "Lihat semua (${_captureHistory.length})",
                        style: const TextStyle(color: Colors.black54, fontSize: 13),
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
                      icon: Icon(
                        _mode == OcrMode.photo ? Icons.add_photo_alternate_rounded : (_showPreview ? Icons.camera_alt_outlined : Icons.camera_alt_rounded), 
                        size: 20
                      ),
                      label: Text(
                        _mode == OcrMode.photo ? "Ambil Foto" : (_showPreview ? "Foto Baru" : "Ambil Gambar"), 
                        style: const TextStyle(fontSize: 15)
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        elevation: 0,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 24),
              ],
            ),
          ),

          // Top-left: Close / Open Camera Button
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 12,
            child: IconButton.filled(
              style: IconButton.styleFrom(backgroundColor: Colors.grey[100]),
              icon: Icon(_cameraOpen ? Icons.close : Icons.videocam, color: Colors.black87, size: 24),
              onPressed: _cameraOpen ? _closeCamera : (_modelLoaded ? _openCamera : null),
            ),
          ),

          // Top-right: Load Model dari HP Button
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 12,
            child: _isLoadingModel
                ? Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(color: Colors.grey[100], shape: BoxShape.circle),
                    child: const Padding(
                      padding: EdgeInsets.all(10),
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
                      ),
                    ),
                  )
                : Column(
                    children: [
                      IconButton.filled(
                        style: IconButton.styleFrom(backgroundColor: Colors.grey[100]),
                        icon: const Icon(Icons.folder_open_rounded, color: Colors.black87, size: 22),
                        onPressed: _loadModelFromPhone,
                        tooltip: 'Muat model dari HP',
                      ),
                      if (_modelLoaded)
                        Container(
                          margin: const EdgeInsets.only(top: 2),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: _modelSource == 'phone' ? Colors.green.withOpacity(0.85) : Colors.grey[200],
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _modelSource == 'phone' ? '📱 HP' : '📦 Assets',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: _modelSource == 'phone' ? Colors.white : Colors.black54,
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

// ─── Model Picker Bottom Sheet ───────────────────────────────────────────────

class _ModelPickerSheet extends StatefulWidget {
  final String? activeDetParam;
  final String? activeDetModel;
  final String? activeRecParam;
  final String? activeRecModel;
  final String modelSource;

  const _ModelPickerSheet({
    this.activeDetParam,
    this.activeDetModel,
    this.activeRecParam,
    this.activeRecModel,
    required this.modelSource,
  });

  @override
  State<_ModelPickerSheet> createState() => _ModelPickerSheetState();
}

class _ModelPickerSheetState extends State<_ModelPickerSheet> {
  late String? _detParam;
  late String? _detModel;
  late String? _recParam;
  late String? _recModel;

  @override
  void initState() {
    super.initState();
    // Mulai dengan file yang sedang aktif (jika dari phone, tampilkan; jika dari assets, kosongkan agar user pilih baru)
    _detParam = widget.modelSource == 'phone' ? widget.activeDetParam : null;
    _detModel = widget.modelSource == 'phone' ? widget.activeDetModel : null;
    _recParam = widget.modelSource == 'phone' ? widget.activeRecParam : null;
    _recModel = widget.modelSource == 'phone' ? widget.activeRecModel : null;
  }

  bool get _allSelected => _detParam != null && _detModel != null && _recParam != null && _recModel != null;

  String _fileName(String? path) {
    if (path == null) return '';
    return path.split('/').last;
  }

  Future<void> _pickFile(String key) async {
    final result = await FilePicker.platform.pickFiles(type: FileType.any);
    if (result != null && result.files.single.path != null) {
      setState(() {
        switch (key) {
          case 'det_param':
            _detParam = result.files.single.path;
            break;
          case 'det_model':
            _detModel = result.files.single.path;
            break;
          case 'rec_param':
            _recParam = result.files.single.path;
            break;
          case 'rec_model':
            _recModel = result.files.single.path;
            break;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(4)),
          ),
          const SizedBox(height: 16),

          // Title
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.folder_open_rounded, color: Colors.green, size: 22),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Muat Model dari HP',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.black87),
                    ),
                    Text(
                      'Pilih file model NCNN dari penyimpanan',
                      style: TextStyle(fontSize: 12, color: Colors.black45),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Info model yang sedang aktif
          if (widget.activeDetParam != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: widget.modelSource == 'phone' ? Colors.green.withOpacity(0.06) : Colors.blue.withOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: widget.modelSource == 'phone' ? Colors.green.withOpacity(0.2) : Colors.blue.withOpacity(0.2),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    widget.modelSource == 'phone' ? Icons.smartphone : Icons.inventory_2_outlined,
                    size: 16,
                    color: widget.modelSource == 'phone' ? Colors.green : Colors.blue,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Aktif: ${widget.modelSource == 'phone' ? 'Model dari HP' : 'Model dari Assets'}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: widget.modelSource == 'phone' ? Colors.green[700] : Colors.blue[700],
                      ),
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 16),

          // ── Detection Section ──
          _buildSectionHeader('Detection Model', Icons.search_rounded),
          const SizedBox(height: 8),
          _buildFileSlot(
            label: 'Param (.param)',
            path: _detParam,
            onPick: () => _pickFile('det_param'),
            onClear: () => setState(() => _detParam = null),
          ),
          const SizedBox(height: 8),
          _buildFileSlot(
            label: 'Model (.bin)',
            path: _detModel,
            onPick: () => _pickFile('det_model'),
            onClear: () => setState(() => _detModel = null),
          ),

          const SizedBox(height: 16),

          // ── Recognition Section ──
          _buildSectionHeader('Recognition Model', Icons.text_fields_rounded),
          const SizedBox(height: 8),
          _buildFileSlot(
            label: 'Param (.param)',
            path: _recParam,
            onPick: () => _pickFile('rec_param'),
            onClear: () => setState(() => _recParam = null),
          ),
          const SizedBox(height: 8),
          _buildFileSlot(
            label: 'Model (.bin)',
            path: _recModel,
            onPick: () => _pickFile('rec_model'),
            onClear: () => setState(() => _recModel = null),
          ),

          const SizedBox(height: 20),

          // ── Buttons ──
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(null),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.grey[700],
                    side: BorderSide(color: Colors.grey[300]!),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Batal'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: _allSelected
                      ? () => Navigator.of(context).pop({
                          'det_param': _detParam!,
                          'det_model': _detModel!,
                          'rec_param': _recParam!,
                          'rec_model': _recModel!,
                        })
                      : null,
                  icon: const Icon(Icons.upload_rounded, size: 18),
                  label: Text(_allSelected ? 'Muat Model' : 'Pilih semua file dulu'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey[200],
                    disabledForegroundColor: Colors.grey[500],
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),

          // Extra bottom padding for safe area
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.black54),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.black54),
        ),
      ],
    );
  }

  Widget _buildFileSlot({
    required String label,
    required String? path,
    required VoidCallback onPick,
    required VoidCallback onClear,
  }) {
    final hasFile = path != null;
    return InkWell(
      onTap: onPick,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: hasFile ? Colors.green.withOpacity(0.06) : Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: hasFile ? Colors.green.withOpacity(0.4) : Colors.black12),
        ),
        child: Row(
          children: [
            Icon(
              hasFile ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
              color: hasFile ? Colors.green : Colors.grey[400],
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(fontSize: 11, color: Colors.grey[500], fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hasFile ? _fileName(path) : 'Tap untuk pilih file',
                    style: TextStyle(
                      fontSize: 13,
                      color: hasFile ? Colors.black87 : Colors.grey,
                      fontWeight: hasFile ? FontWeight.w600 : FontWeight.normal,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (hasFile)
              GestureDetector(
                onTap: onClear,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.close_rounded, size: 18, color: Colors.grey[400]),
                ),
              )
            else
              Icon(Icons.folder_open_rounded, size: 18, color: Colors.grey[400]),
          ],
        ),
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
              color: active ? activeColor.withOpacity(0.2) : Colors.white,
              shape: BoxShape.circle,
              border: Border.all(color: active ? activeColor : Colors.black12, width: 1.5),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))],
            ),
            child: Icon(icon, color: active ? activeColor : Colors.black87, size: 24),
          ),
          const SizedBox(height: 6),
          Text(label, style: TextStyle(color: active ? activeColor : Colors.black54, fontSize: 11)),
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
              decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(4)),
            ),
            const SizedBox(height: 16),
            const Text(
              "Riwayat Scan",
              style: TextStyle(color: Colors.black87, fontSize: 17, fontWeight: FontWeight.bold),
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
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.black12),
                      boxShadow: [
                        BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 4, offset: const Offset(0, 2)),
                      ],
                    ),
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
                              color: Colors.grey[200],
                              child: const Icon(Icons.broken_image, color: Colors.black26),
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
                                    color: cap.ocrText.isEmpty ? Colors.black38 : Colors.black87,
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _formatTime(cap.timestamp),
                                  style: const TextStyle(color: Colors.black54, fontSize: 12),
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
