import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../../../../../core/constants/colors.dart';
import '../../../../../core/services/location_service.dart';
import '../../../../../core/services/recommendation_location_service.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../../booking/presentation/pages/location_picker_map_page.dart';

class RecommendationLocationSettingsPage extends StatefulWidget {
  const RecommendationLocationSettingsPage({super.key});

  @override
  State<RecommendationLocationSettingsPage> createState() =>
      _RecommendationLocationSettingsPageState();
}

class _RecommendationLocationSettingsPageState
    extends State<RecommendationLocationSettingsPage> {
  final _service = RecommendationLocationService.instance;
  RecommendationLocation? _savedLocation;
  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final location = await _service.load();
      if (!mounted) return;
      setState(() {
        _savedLocation = location;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _useGps() async {
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw const RecommendationLocationServiceException(
          'กรุณาเปิดบริการตำแหน่ง หรือเลือกตำแหน่งบนแผนที่',
        );
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw const RecommendationLocationServiceException(
          'ยังไม่ได้รับอนุญาตให้ใช้ GPS คุณเลือกตำแหน่งบนแผนที่แทนได้',
        );
      }
      final Position? position = await LocationService.instance
          .getCurrentPosition();
      if (position == null) {
        throw const RecommendationLocationServiceException(
          'รับตำแหน่ง GPS ไม่ได้ กรุณาเปิดบริการตำแหน่งหรือเลือกตำแหน่งบนแผนที่',
        );
      }
      final place = await LocationService.instance.reverseGeocode(
        position.latitude,
        position.longitude,
      );
      await _service.save(
        latitude: position.latitude,
        longitude: position.longitude,
        source: 'gps',
        label: place?.displayName ?? 'ตำแหน่งปัจจุบัน',
      );
      if (!mounted) return;
      setState(() {
        _savedLocation = RecommendationLocation(
          latitude: position.latitude,
          longitude: position.longitude,
          source: 'gps',
          label: place?.displayName ?? 'ตำแหน่งปัจจุบัน',
          recommendationEnabled: true,
          consentedAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        _isSaving = false;
      });
      _showMessage('บันทึกตำแหน่งปัจจุบันแล้ว');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _isSaving = false;
      });
    }
  }

  Future<void> _chooseManually() async {
    final current = _savedLocation;
    final picked = await Navigator.of(context).push<LocationPickerResult>(
      MaterialPageRoute(
        builder: (_) => LocationPickerMapPage(
          title: 'เลือกตำแหน่งแนะนำสินค้า',
          placeNameHint: 'ชื่อพื้นที่หรือย่าน...',
          confirmLabel: 'ใช้ตำแหน่งนี้',
          initialLocationName: current?.label,
          initialLatitude: current?.latitude,
          initialLongitude: current?.longitude,
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      final label = picked.fullAddress.trim().isEmpty
          ? picked.locationName
          : '${picked.locationName} • ${picked.fullAddress}';
      await _service.save(
        latitude: picked.latitude,
        longitude: picked.longitude,
        source: 'manual',
        label: label,
      );
      if (!mounted) return;
      setState(() {
        _savedLocation = RecommendationLocation(
          latitude: picked.latitude,
          longitude: picked.longitude,
          source: 'manual',
          label: label,
          recommendationEnabled: true,
          consentedAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        _isSaving = false;
      });
      _showMessage('บันทึกตำแหน่งที่เลือกแล้ว');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _isSaving = false;
      });
    }
  }

  Future<void> _clearLocation() async {
    final shouldClear = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ลบตำแหน่งที่บันทึกไว้?'),
        content: const Text(
          'ระบบจะลบพิกัดจากบัญชีและหยุดใช้ตำแหน่งนี้จัดอันดับสินค้า',
          style: TextStyle(fontFamily: AppTextStyles.fontFamily),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('ยกเลิก'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('ลบตำแหน่ง'),
          ),
        ],
      ),
    );
    if (shouldClear != true) return;
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      await _service.clear();
      if (!mounted) return;
      setState(() {
        _savedLocation = null;
        _isSaving = false;
      });
      _showMessage('ลบตำแหน่งแล้ว');
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _isSaving = false;
      });
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontFamily: AppTextStyles.fontFamily),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final saved = _savedLocation;
    return Scaffold(
      backgroundColor: const Color(0xFFF7F7F9),
      appBar: AppBar(
        title: const Text('ตำแหน่งแนะนำสินค้า'),
        backgroundColor: AppColors.primaryColor,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(18),
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.my_location_rounded,
                        color: AppColors.primaryColor,
                        size: 28,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        saved?.recommendationEnabled == true
                            ? 'กำลังใช้ตำแหน่งนี้'
                            : 'ยังไม่ได้ตั้งค่าตำแหน่ง',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          fontFamily: AppTextStyles.fontFamily,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        saved?.recommendationEnabled == true
                            ? (saved?.label?.isNotEmpty == true
                                  ? saved!.label!
                                  : '${saved!.latitude.toStringAsFixed(5)}, ${saved.longitude.toStringAsFixed(5)}')
                            : 'เลือกตำแหน่งเพื่อดูระยะทางและจัดอันดับอุปกรณ์ใกล้คุณ',
                        style: const TextStyle(
                          color: Colors.black54,
                          height: 1.4,
                          fontFamily: AppTextStyles.fontFamily,
                        ),
                      ),
                      if (saved != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          saved.source == 'gps'
                              ? 'ที่มาของตำแหน่ง: GPS'
                              : 'ที่มาของตำแหน่ง: เลือกเอง',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.black45,
                            fontFamily: AppTextStyles.fontFamily,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: _isSaving ? null : _useGps,
                  icon: const Icon(Icons.gps_fixed_rounded),
                  label: const Text('ใช้ตำแหน่งปัจจุบัน'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primaryColor,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _isSaving ? null : _chooseManually,
                  icon: const Icon(Icons.map_outlined),
                  label: const Text('เลือกตำแหน่งบนแผนที่'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primaryColor,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
                if (saved != null) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _isSaving ? null : _clearLocation,
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('ลบตำแหน่งและปิดการแนะนำใกล้ฉัน'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.red.shade700,
                    ),
                  ),
                ],
                if (_isSaving) ...[
                  const SizedBox(height: 14),
                  const Center(child: CircularProgressIndicator()),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Colors.red.shade700,
                      fontFamily: AppTextStyles.fontFamily,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                const Text(
                  'ตำแหน่งจะถูกบันทึกในบัญชีเพื่อใช้คำนวณระยะถึงจุดรับสินค้าเท่านั้น ไม่มีการติดตามตำแหน่งต่อเนื่อง คุณสามารถเปลี่ยนหรือลบได้ทุกเมื่อ',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.black54,
                    height: 1.45,
                    fontFamily: AppTextStyles.fontFamily,
                  ),
                ),
              ],
            ),
    );
  }
}
