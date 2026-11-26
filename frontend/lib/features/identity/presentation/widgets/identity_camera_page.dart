import 'dart:async';

import 'package:frontend/core/widgets/app_popup.dart';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../../core/widgets/app_primary_button.dart';
import '../../data/camera_file_cleanup.dart';
import '../../data/identity_card_photo.dart';
import 'identity_widgets.dart';

enum IdentityCaptureKind { card, selfie, selfieWithCard }

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
    showAppPopup(
      context,
      content: Text('กรุณาใช้กล้องผ่านแอป Android หรือ iOS'),
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
  final _cardPreviewKey = GlobalKey();
  CameraController? _camera;
  Uint8List? _preview;
  String? _error;
  bool _starting = false, _taking = false, _permissionDenied = false;
  int _generation = 0;
  Future<void> _cameraOperation = Future<void>.value();
  bool get _face => widget.kind != IdentityCaptureKind.card;
  bool get _withCard => widget.kind == IdentityCaptureKind.selfieWithCard;
  String get _title => _withCard
      ? 'ถ่ายรูปคู่บัตรประชาชน'
      : _face
      ? 'ถ่ายใบหน้าของคุณ'
      : 'ถ่ายด้านหน้าบัตร';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  Future<void> _runCameraOperation(Future<void> Function() operation) {
    // CameraX ใช้ทรัพยากรร่วมกัน จึงต้องรอเปิดหรือคืนกล้องเดิมให้จบก่อน
    return _cameraOperation = _cameraOperation.then((_) => operation());
  }

  Future<void> _release() => _runCameraOperation(_releaseCamera);

  Future<void> _releaseCamera() async {
    final camera = _camera;
    _camera = null;
    await _disposeCamera(camera);
  }

  Future<void> _disposeCamera(CameraController? camera) async {
    try {
      await camera?.dispose();
    } on CameraException {
      // คืนกล้องที่เริ่มไม่สำเร็จอาจล้มเหลว แต่ต้องให้ผู้ใช้ลองใหม่ได้
    } on PlatformException {
      // CameraX อาจคืน surface ที่ยังไม่ถูกสร้างหรือถูกคืนไปแล้ว
    }
  }

  Future<void> _start() async {
    final generation = ++_generation;
    setState(() {
      _starting = true;
      _error = null;
      _permissionDenied = false;
    });
    await _runCameraOperation(() => _initializeCamera(generation));
  }

  Future<void> _initializeCamera(int generation) async {
    if (!mounted || generation != _generation) return;
    CameraController? candidate;
    try {
      await _releaseCamera();
      if (!mounted || generation != _generation) return;
      final cameras = await availableCameras();
      if (!mounted || generation != _generation) return;
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
      if (!mounted || generation != _generation) return;
      await candidate.lockCaptureOrientation(DeviceOrientation.portraitUp);
      if (!mounted || generation != _generation) return;
      setState(() {
        _camera = candidate;
        _starting = false;
      });
      candidate = null;
    } on CameraException catch (e) {
      if (mounted && generation == _generation) {
        setState(() {
          _starting = false;
          _permissionDenied = e.code.contains('Access');
          _error = _permissionDenied
              ? 'ยังเข้าใช้กล้องไม่ได้ กรุณาอนุญาตกล้องให้แอปในตั้งค่า แล้วลองอีกครั้ง'
              : 'เปิดกล้องไม่ได้ กรุณาลองใหม่บนอุปกรณ์ที่มีกล้อง';
        });
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() {
          _starting = false;
          _error = 'กล้องยังไม่พร้อม กรุณาลองใหม่';
        });
      }
    } finally {
      await _disposeCamera(candidate);
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
    final cardPreview = _face ? null : _cardPreviewKey.currentContext?.size;
    if (!_face && (cardPreview == null || cardPreview.isEmpty)) return;
    final generation = _generation;
    setState(() {
      _taking = true;
      _error = null;
    });
    try {
      final file = await camera.takePicture();
      Uint8List data;
      try {
        final raw = await file.readAsBytes();
        data = cardPreview == null
            ? await FlutterImageCompress.compressWithList(
                raw,
                minWidth: 1800,
                minHeight: 1800,
                quality: 90,
                keepExif: false,
              )
            : await cropIdentityCardPhoto((
                bytes: raw,
                preview: cardPreview,
                frame: _cardFrame(cardPreview),
              ));
      } finally {
        await clearCameraFile(file.path);
      }
      if (!mounted || generation != _generation) return;
      if (data.length > 5 * 1024 * 1024) throw const FormatException();
      setState(() => _preview = data);
      // แสดงรูปทันทีที่พร้อม ส่วนการถ่ายใหม่จะรอคืนกล้องผ่านคิวเดิม
      unawaited(_release());
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(
          () =>
              _error = 'ถ่ายภาพไม่สำเร็จ กรุณาลองอีกครั้ง ภาพต้องไม่เกิน 5 MB',
        );
      }
    } finally {
      if (mounted) setState(() => _taking = false);
    }
  }

  Widget _cardCameraPreview(CameraController camera) => Center(
    child: CameraPreview(
      camera,
      child: LayoutBuilder(
        key: _cardPreviewKey,
        builder: (context, constraints) {
          final frame = _cardFrame(constraints.biggest);
          return IgnorePointer(
            child: Stack(
              fit: StackFit.expand,
              children: [
                CustomPaint(painter: _CardFrameMask(frame)),
                Positioned.fromRect(
                  rect: frame,
                  child: const CustomPaint(
                    key: ValueKey('identity_card_capture_frame'),
                    painter: _CardAlignmentGuides(),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ),
  );

  Widget _livePreview(CameraController camera) {
    if (!_face) return _cardCameraPreview(camera);
    return Stack(
      fit: StackFit.expand,
      children: [
        Center(child: CameraPreview(camera)),
        IgnorePointer(
          child: Center(
            child: FractionallySizedBox(
              widthFactor: _withCard ? 0.95 : 0.72,
              child: AspectRatio(
                aspectRatio: 0.75,
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white, width: 2.5),
                    borderRadius: BorderRadius.circular(_withCard ? 18 : 180),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
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
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _face
                  ? _withCard
                        ? 'รูปคู่บัตรประชาชน'
                        : 'ใบหน้า · รูปที่ 2 จาก 2'
                  : 'บัตรประชาชน · รูปที่ 1 จาก 2',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
            child: Text(
              _preview != null
                  ? _face
                        ? _withCard
                              ? 'เห็นใบหน้าและข้อมูลบนบัตรชัดเจน ไม่มีแสงสะท้อน'
                              : 'เห็นใบหน้าครบและชัดเจน ไม่มืดหรือย้อนแสง'
                        : 'เห็นเอกสารครบ ข้อความชัด และไม่มีแสงสะท้อน'
                  : _face
                  ? _withCard
                        ? 'ถือบัตรข้างใบหน้า ให้เห็นครบทั้งใบหน้าและบัตร\nไม่บังข้อมูลบนบัตร ถอดหน้ากากและแว่นกันแดด'
                        : 'มองตรง ให้ใบหน้าอยู่ในกรอบ\nถอดหน้ากากและแว่นกันแดด'
                  : 'วางบัตรแนวนอนให้ครบทั้งสี่มุม\nให้ตราและรูปถ่ายอยู่ในช่องที่กำหนด',
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
                borderRadius: BorderRadius.circular(_face ? 24 : 12),
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
                    ? _livePreview(_camera!)
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
                  Column(
                    children: [
                      if (_permissionDenied)
                        TextButton(
                          onPressed: () async {
                            var opened = false;
                            try {
                              opened = await openAppSettings();
                            } catch (_) {
                              // หากเปิดตั้งค่าไม่ได้ ยังให้ผู้ใช้ลองเปิดกล้องซ้ำได้
                            }
                            if (!opened && mounted) {
                              setState(
                                () => _error =
                                    'เปิดตั้งค่าไม่ได้ กรุณาเปิดสิทธิ์กล้องในการตั้งค่าของอุปกรณ์',
                              );
                            }
                          },
                          child: const Text(
                            'เปิดการตั้งค่ากล้อง',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      AppPrimaryButton(
                        text: 'ลองเปิดกล้องอีกครั้ง',
                        onPressed: _starting ? null : _start,
                      ),
                    ],
                  )
                else
                  Container(
                    width: 72,
                    height: 72,
                    padding: _face ? null : const EdgeInsets.all(4),
                    decoration: _face
                        ? null
                        : BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
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
                          ? const SizedBox.square(
                              dimension: 24,
                              child: CircularProgressIndicator(
                                color: Colors.white70,
                                strokeWidth: 2.5,
                              ),
                            )
                          : Icon(
                              Icons.camera_alt_rounded,
                              size: _face ? 32 : 28,
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

Rect _cardFrame(Size preview) => Alignment.center.inscribe(
  applyBoxFit(
    BoxFit.contain,
    const Size(85.6, 53.98),
    preview * 0.94,
  ).destination,
  Offset.zero & preview,
);

class _CardFrameMask extends CustomPainter {
  const _CardFrameMask(this.frame);

  final Rect frame;

  @override
  void paint(Canvas canvas, Size size) {
    final outside = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addRect(frame);
    canvas.drawPath(outside, Paint()..color = const Color(0x99000000));
  }

  @override
  bool shouldRepaint(_CardFrameMask oldDelegate) => frame != oldDelegate.frame;
}

class _CardAlignmentGuides extends CustomPainter {
  const _CardAlignmentGuides();

  @override
  void paint(Canvas canvas, Size size) {
    const accent = Color(0xFF72DEFF);
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..color = const Color(0x99FFFFFF)
        ..style = PaintingStyle.stroke,
    );
    final length = size.shortestSide * 0.13;
    final corners = Path()
      ..moveTo(0, length)
      ..lineTo(0, 0)
      ..lineTo(length, 0)
      ..moveTo(size.width - length, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, length)
      ..moveTo(size.width, size.height - length)
      ..lineTo(size.width, size.height)
      ..lineTo(size.width - length, size.height)
      ..moveTo(length, size.height)
      ..lineTo(0, size.height)
      ..lineTo(0, size.height - length);
    canvas.drawPath(
      corners,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    final marks = Path()
      ..addOval(
        Rect.fromCircle(
          center: Offset(size.width * 0.085, size.height * 0.13),
          radius: size.height * 0.092,
        ),
      )
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(
            size.width * 0.75,
            size.height * 0.50,
            size.width * 0.975,
            size.height * 0.955,
          ),
          Radius.circular(size.height * 0.025),
        ),
      );
    final stroke = Paint()..style = PaintingStyle.stroke;
    canvas.drawPath(
      marks,
      stroke
        ..color = Colors.black54
        ..strokeWidth = 4,
    );
    canvas.drawPath(
      marks,
      stroke
        ..color = accent
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_CardAlignmentGuides oldDelegate) => false;
}
