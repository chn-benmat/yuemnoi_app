import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import '../../../../core/widgets/app_primary_button.dart';
import '../../data/camera_file_cleanup.dart';
import 'identity_widgets.dart';

enum IdentityCaptureKind { card, selfie, authority }

typedef IdentityCapture =
    Future<Uint8List?> Function(BuildContext context, IdentityCaptureKind kind);

Future<Uint8List?> captureIdentityPhoto(
  BuildContext context,
  IdentityCaptureKind kind,
) async {
  if (kIsWeb ||
      ![
        TargetPlatform.android,
        TargetPlatform.iOS,
      ].contains(defaultTargetPlatform)) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('กรุณาใช้กล้องผ่านแอป Android หรือ iOS')),
    );
    return null;
  }
  return Navigator.of(context).push<Uint8List>(
    MaterialPageRoute(builder: (_) => IdentityCameraPage(kind: kind)),
  );
}

class IdentityCameraPage extends StatefulWidget {
  const IdentityCameraPage({super.key, required this.kind});
  final IdentityCaptureKind kind;
  @override
  State<IdentityCameraPage> createState() => _IdentityCameraPageState();
}

class _IdentityCameraPageState extends State<IdentityCameraPage>
    with WidgetsBindingObserver {
  CameraController? _camera;
  Uint8List? _preview;
  String? _error;
  bool _starting = false, _taking = false;
  int _generation = 0;
  bool get _face => widget.kind == IdentityCaptureKind.selfie;
  String get _title => _face
      ? 'ถ่ายใบหน้าของคุณ'
      : widget.kind == IdentityCaptureKind.card
      ? 'ถ่ายด้านหน้าบัตร'
      : 'ถ่ายหลักฐานผู้ปกครอง';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  Future<void> _release() async {
    final camera = _camera;
    _camera = null;
    await camera?.dispose();
  }

  Future<void> _start() async {
    final generation = ++_generation;
    setState(() {
      _starting = true;
      _error = null;
    });
    CameraController? candidate;
    try {
      await _release();
      final cameras = await availableCameras();
      final lens = _face ? CameraLensDirection.front : CameraLensDirection.back;
      final matches = cameras.where((c) => c.lensDirection == lens);
      if (matches.isEmpty) throw CameraException('NoCamera', '');
      candidate = CameraController(
        matches.first,
        widget.kind == IdentityCaptureKind.card
            ? ResolutionPreset.veryHigh
            : ResolutionPreset.high,
        enableAudio: false,
      );
      await candidate.initialize();
      await candidate.lockCaptureOrientation(DeviceOrientation.portraitUp);
      if (!mounted || generation != _generation) {
        await candidate.dispose();
        return;
      }
      setState(() {
        _camera = candidate;
        _starting = false;
      });
    } on CameraException catch (e) {
      await candidate?.dispose();
      if (mounted && generation == _generation) {
        setState(() {
          _starting = false;
          _error = e.code.contains('Access')
              ? 'ยังเข้าใช้กล้องไม่ได้ กรุณาอนุญาตกล้องให้แอปในตั้งค่า แล้วลองอีกครั้ง'
              : 'เปิดกล้องไม่ได้ กรุณาลองใหม่บนอุปกรณ์ที่มีกล้อง';
        });
      }
    } catch (_) {
      await candidate?.dispose();
      if (mounted && generation == _generation) {
        setState(() {
          _starting = false;
          _error = 'กล้องยังไม่พร้อม กรุณาลองใหม่';
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _generation++;
      _release();
    } else if (state == AppLifecycleState.resumed && _preview == null) {
      _start();
    }
  }

  Future<void> _take() async {
    final camera = _camera;
    if (_taking || camera == null || !camera.value.isInitialized) return;
    setState(() => _taking = true);
    try {
      final file = await camera.takePicture();
      Uint8List data;
      try {
        final raw = await file.readAsBytes();
        data = await FlutterImageCompress.compressWithList(
          raw,
          minWidth: 1800,
          minHeight: 1800,
          quality: 90,
          keepExif: false,
        );
      } finally {
        await clearCameraFile(file.path);
      }
      if (!mounted) return;
      if (data.length > 5 * 1024 * 1024) throw const FormatException();
      await _release();
      if (mounted) setState(() => _preview = data);
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              _error = 'ถ่ายภาพไม่สำเร็จ กรุณาลองอีกครั้ง ภาพต้องไม่เกิน 5 MB',
        );
      }
    } finally {
      if (mounted) setState(() => _taking = false);
    }
  }

  @override
  void dispose() {
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    _release();
    _preview = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: IdentityColors.ink,
    appBar: AppBar(
      title: Text(_preview == null ? _title : 'ตรวจรูปก่อนใช้'),
      backgroundColor: IdentityColors.ink,
      foregroundColor: Colors.white,
    ),
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
            child: Text(
              _preview != null
                  ? 'เห็นครบ ชัดเจน และไม่มีแสงสะท้อน'
                  : _face
                  ? 'มองตรง ให้ใบหน้าอยู่ในกรอบ\nถอดหน้ากากและแว่นกันแดด'
                  : widget.kind == IdentityCaptureKind.authority
                  ? 'วางเอกสารให้เห็นครบทุกมุม\nข้อความชัดเจนและไม่มีสิ่งบดบัง'
                  : 'วางแนวนอนให้ครบทุกมุม\nใช้แสงสว่างพอดี ไม่ปิดข้อมูลบนบัตร',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                height: 1.7,
                fontSize: 14,
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: _preview != null
                    ? Image.memory(
                        _preview!,
                        fit: BoxFit.contain,
                        excludeFromSemantics: true,
                      )
                    : _starting
                    ? const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      )
                    : _camera != null
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          Center(child: CameraPreview(_camera!)),
                          IgnorePointer(
                            child: Center(
                              child: FractionallySizedBox(
                                widthFactor: _face ? 0.72 : 0.92,
                                child: AspectRatio(
                                  aspectRatio: _face
                                      ? 0.75
                                      : widget.kind ==
                                            IdentityCaptureKind.authority
                                      ? 0.707
                                      : 1.586,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 2.5,
                                      ),
                                      borderRadius: BorderRadius.circular(
                                        _face ? 180 : 18,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                    : const Center(
                        child: Icon(
                          Icons.no_photography_outlined,
                          size: 64,
                          color: Colors.white60,
                        ),
                      ),
              ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_preview != null) ...[
                  AppPrimaryButton(
                    text: 'ใช้รูปนี้',
                    onPressed: () => Navigator.of(context).pop(_preview),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() => _preview = null);
                      _start();
                    },
                    child: const Text(
                      'ถ่ายใหม่',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ] else if (_error != null && _camera == null)
                  AppPrimaryButton(
                    text: 'ลองเปิดกล้องอีกครั้ง',
                    onPressed: _starting ? null : _start,
                  )
                else
                  SizedBox(
                    width: 72,
                    height: 72,
                    child: Semantics(
                      label: 'ถ่ายภาพ',
                      button: true,
                      child: IconButton.filled(
                        tooltip: 'ถ่ายภาพ',
                        onPressed: _starting || _taking || _camera == null
                            ? null
                            : _take,
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: IdentityColors.ink,
                        ),
                        icon: _taking
                            ? const CircularProgressIndicator()
                            : const Icon(Icons.camera_alt_rounded, size: 32),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
