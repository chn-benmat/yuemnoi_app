import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/services/location_service.dart';
import '../../../../core/services/recommendation_location_service.dart';
import '../../../../core/theme/app_text_styles.dart';

class RecommendationLocationOnboardingPage extends StatefulWidget {
  const RecommendationLocationOnboardingPage({super.key});

  @override
  State<RecommendationLocationOnboardingPage> createState() =>
      _RecommendationLocationOnboardingPageState();
}

class _RecommendationLocationOnboardingPageState
    extends State<RecommendationLocationOnboardingPage> {
  bool _busy = false;
  String? _message;

  Future<void> _continueWithoutLocation() async {
    await RecommendationLocationService.instance.completeFirstRunPrompt();
    if (mounted) AppRoutes.router?.go(AppRoutes.home);
  }

  Future<void> _allowLocation() async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw const RecommendationLocationServiceException(
          'กรุณาเปิดบริการตำแหน่งในเครื่อง แล้วลองอีกครั้ง หรือเลือกข้ามไปก่อน',
        );
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        await _continueWithoutLocation();
        return;
      }

      final position = await LocationService.instance.getCurrentPosition();
      if (position == null) {
        throw const RecommendationLocationServiceException(
          'รับตำแหน่งไม่ได้ คุณสามารถลองใหม่หรือข้ามไปก่อน',
        );
      }
      final place = await LocationService.instance.reverseGeocode(
        position.latitude,
        position.longitude,
      );
      final label = place?.displayName ?? 'ตำแหน่งปัจจุบัน';
      final service = RecommendationLocationService.instance;
      await service.savePendingForSignedInUser(
        latitude: position.latitude,
        longitude: position.longitude,
        source: 'gps',
        label: label,
      );
      try {
        await service.save(
          latitude: position.latitude,
          longitude: position.longitude,
          source: 'gps',
          label: label,
        );
        await service.clearPending();
      } on RecommendationLocationServiceException {
        // Guest users keep the consented point locally until they sign in.
      }
      await service.completeFirstRunPrompt();
      if (mounted) AppRoutes.router?.go(AppRoutes.home);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _message = error.toString().replaceFirst('Exception: ', '');
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F5FA),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.location_on_rounded,
                    color: AppColors.primaryColor,
                    size: 72,
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'หาอุปกรณ์ใกล้คุณ',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'อนุญาตให้ใช้ตำแหน่งปัจจุบันเพื่อแนะนำอุปกรณ์และแสดงระยะทางจากคุณ ระบบจะบันทึกตำแหน่งไว้ในบัญชีเมื่อเข้าสู่ระบบ และไม่ติดตามตำแหน่งต่อเนื่อง คุณเปลี่ยนหรือลบตำแหน่งได้ในหน้าแก้ไขโปรไฟล์',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      height: 1.55,
                      color: Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 28),
                  FilledButton.icon(
                    onPressed: _busy ? null : _allowLocation,
                    icon: const Icon(Icons.my_location_rounded),
                    label: const Text('ยินยอมและใช้ตำแหน่งปัจจุบัน'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primaryColor,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                  ),
                  TextButton(
                    onPressed: _busy ? null : _continueWithoutLocation,
                    child: const Text('ข้ามไปก่อน'),
                  ),
                  if (_busy) ...[
                    const SizedBox(height: 12),
                    const Center(child: CircularProgressIndicator()),
                  ],
                  if (_message != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _message!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.red.shade700,
                        fontFamily: AppTextStyles.fontFamily,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
