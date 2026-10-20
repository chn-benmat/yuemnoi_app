import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/models/pickup_location.dart';
import '../../../../core/widgets/pickup_location_field.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../pages/location_picker_map_page.dart';

class BookingLocationCard extends StatelessWidget {
  const BookingLocationCard({
    super.key,
    required this.location,
    required this.locationNote,
    this.locationAddress,
    this.latitude,
    this.longitude,
    this.onLocationChanged,
    this.onLocationResultChanged,
    this.isEditable = true,
    this.showMiniMap = true,
    this.showError = false,
  });

  final String location;
  final String locationNote;
  final String? locationAddress;
  final double? latitude;
  final double? longitude;
  final ValueChanged<String>? onLocationChanged;
  final ValueChanged<LocationPickerResult>? onLocationResultChanged;
  final bool isEditable;
  final bool showMiniMap;
  final bool showError;

  LatLng? get _resolvedLatLng {
    if (latitude == null ||
        longitude == null ||
        !latitude!.isFinite ||
        !longitude!.isFinite ||
        latitude!.abs() > 90 ||
        longitude!.abs() > 180)
      return null;
    return LatLng(latitude!, longitude!);
  }

  void _openMapView(BuildContext context) {
    if (_resolvedLatLng == null) return;
    openPickupLocationInGoogleMaps(
      context,
      PickupLocation(
        name: location,
        address: locationAddress ?? '',
        note: locationNote,
        latitude: latitude!,
        longitude: longitude!,
      ),
    );
  }

  Future<void> _openRealMapPicker(BuildContext context) async {
    if (!isEditable) return;

    final result = await Navigator.of(context).push<LocationPickerResult>(
      MaterialPageRoute<LocationPickerResult>(
        builder: (_) => LocationPickerMapPage(
          initialLocationName: location,
          initialNote: locationNote,
          initialLatitude: latitude ?? _resolvedLatLng?.latitude,
          initialLongitude: longitude ?? _resolvedLatLng?.longitude,
        ),
      ),
    );

    if (result != null) {
      if (onLocationResultChanged != null) {
        onLocationResultChanged!(result);
      } else if (onLocationChanged != null) {
        onLocationChanged!(result.locationName);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final latLng = _resolvedLatLng;
    final resolvedAddress = locationAddress?.trim();
    final displaySubtitle =
        (resolvedAddress != null && resolvedAddress.isNotEmpty)
        ? resolvedAddress
        : locationNote.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'สถานที่นัดพบ',
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Color(0xFF595C5D),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
            border: Border.all(
              color: showError
                  ? const Color(0xFFDC2626)
                  : const Color(0xFFF1F5F9),
              width: showError ? 1.5 : 1,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: isEditable
                  ? () => _openRealMapPicker(context)
                  : () => _openMapView(context),
              borderRadius: BorderRadius.circular(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. หัวข้อและรายละเอียดสถานที่
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppColors.primaryColor.withValues(
                              alpha: 0.1,
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.place_rounded,
                            color: AppColors.primaryColor,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                location,
                                style: const TextStyle(
                                  fontFamily: AppTextStyles.fontFamily,
                                  fontSize: 15.5,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1E2022),
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (displaySubtitle.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  displaySubtitle,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontFamily: AppTextStyles.fontFamily,
                                    fontSize: 11.5,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 2. Mini Map Preview
                  if (showMiniMap && latLng != null) ...[
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(22),
                      ),
                      child: Stack(
                        children: [
                          SizedBox(
                            height: 125,
                            width: double.infinity,
                            child: IgnorePointer(
                              child: FlutterMap(
                                options: MapOptions(
                                  initialCenter: latLng,
                                  initialZoom: 15.2,
                                  interactionOptions: const InteractionOptions(
                                    flags: InteractiveFlag.none,
                                  ),
                                ),
                                children: [
                                  TileLayer(
                                    urlTemplate:
                                        'https://mt{s}.google.com/vt/lyrs=m&x={x}&y={y}&z={z}',
                                    subdomains: const ['0', '1', '2', '3'],
                                    userAgentPackageName:
                                        'com.example.frontend',
                                    maxZoom: 20,
                                  ),
                                  MarkerLayer(
                                    markers: [
                                      Marker(
                                        point: latLng,
                                        width: 36,
                                        height: 36,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: AppColors.primaryColor,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: Colors.white,
                                              width: 2.5,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: AppColors.primaryColor
                                                    .withValues(alpha: 0.4),
                                                blurRadius: 6,
                                                offset: const Offset(0, 2),
                                              ),
                                            ],
                                          ),
                                          child: const Icon(
                                            Icons.place_rounded,
                                            color: Colors.white,
                                            size: 20,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // Overlay Gradient & Tap Action
                          Positioned.fill(
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: isEditable
                                    ? () => _openRealMapPicker(context)
                                    : () => _openMapView(context),
                                child: Container(
                                  alignment: Alignment.bottomRight,
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [
                                        Colors.transparent,
                                        Colors.black.withValues(alpha: 0.45),
                                      ],
                                    ),
                                  ),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 9,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isEditable
                                          ? AppColors.primaryColor
                                          : Colors.black.withValues(
                                              alpha: 0.75,
                                            ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          isEditable
                                              ? Icons.edit_location_rounded
                                              : Icons.open_in_new_rounded,
                                          color: Colors.white,
                                          size: 13,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          isEditable
                                              ? 'แตะเพื่อเปลี่ยนจุดปักหมุด'
                                              : 'เปิดดูแผนที่',
                                          style: const TextStyle(
                                            fontFamily:
                                                AppTextStyles.fontFamily,
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (showError) ...[
          const SizedBox(height: 6),
          const Padding(
            padding: EdgeInsets.only(left: 16),
            child: Text(
              'กรุณาเลือกสถานที่นัดพบ',
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 12,
                color: Color(0xFFDC2626),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
