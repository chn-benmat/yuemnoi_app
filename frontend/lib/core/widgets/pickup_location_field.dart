import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../constants/colors.dart';
import '../models/pickup_location.dart';
import '../navigation/app_routes.dart';

class PickupLocationField extends StatelessWidget {
  const PickupLocationField({
    super.key,
    this.value,
    required this.onChanged,
    this.enabled = true,
  });
  final PickupLocation? value;
  final ValueChanged<PickupLocation> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) => FormField<PickupLocation>(
    initialValue: value,
    autovalidateMode: AutovalidateMode.onUserInteraction,
    validator: (selected) =>
        selected?.isValid == true ? null : 'กรุณาเลือกจุดนัดรับสินค้า',
    builder: (field) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'จุดนัดรับสินค้า',
          style: TextStyle(
            color: AppColors.labelColor,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Material(
          color: const Color(0xFFF0F1F2),
          borderRadius: BorderRadius.circular(24),
          child: ListTile(
            key: const Key('pickup-location-field'),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            leading: const Icon(
              Icons.location_on_outlined,
              color: AppColors.primaryColor,
            ),
            title: Text(value?.name ?? 'เลือกจุดนัดรับบนแผนที่'),
            subtitle: value == null
                ? null
                : Text(
                    [
                      value!.address,
                      value!.note,
                    ].where((s) => s.isNotEmpty).join('\n'),
                  ),
            trailing: const Icon(Icons.chevron_right),
            onTap: !enabled
                ? null
                : () async {
                    final result = await AppRoutes.openLocationPicker(
                      context,
                      initialLocationName: value?.name ?? '',
                      initialNote: value?.note,
                      initialLatitude: value?.latitude,
                      initialLongitude: value?.longitude,
                    );
                    if (result == null || !context.mounted) return;
                    final selected = PickupLocation(
                      name: result.locationName,
                      address: result.fullAddress,
                      note: result.locationNote,
                      latitude: result.latitude,
                      longitude: result.longitude,
                    );
                    field.didChange(selected);
                    onChanged(selected);
                  },
          ),
        ),
        if (field.hasError)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 12),
            child: Text(
              field.errorText!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    ),
  );
}

class PickupLocationCard extends StatelessWidget {
  const PickupLocationCard({super.key, required this.location});
  final PickupLocation location;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: const Icon(
      Icons.location_on_outlined,
      color: AppColors.primaryColor,
    ),
    title: const Text('จุดนัดรับสินค้า'),
    subtitle: Text(
      [
        location.name,
        location.address,
        location.note,
      ].where((s) => s.isNotEmpty).join('\n'),
    ),
    trailing: const Icon(Icons.map_outlined),
    onTap: () => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PickupLocationMap(location: location),
      ),
    ),
  );
}

class PickupLocationMap extends StatelessWidget {
  const PickupLocationMap({super.key, required this.location});
  final PickupLocation location;

  @override
  Widget build(BuildContext context) {
    final point = LatLng(location.latitude, location.longitude);
    return Scaffold(
      appBar: AppBar(title: const Text('จุดนัดรับสินค้า')),
      body: Column(
        children: [
          Expanded(
            child: FlutterMap(
              options: MapOptions(initialCenter: point, initialZoom: 16),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.frontend',
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: point,
                      width: 48,
                      height: 48,
                      child: const Icon(
                        Icons.location_pin,
                        color: AppColors.primaryColor,
                        size: 48,
                      ),
                    ),
                  ],
                ),
                const RichAttributionWidget(
                  attributions: [
                    TextSourceAttribution('OpenStreetMap contributors'),
                  ],
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                [
                  location.name,
                  location.address,
                  location.note,
                ].where((s) => s.isNotEmpty).join('\n'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
