import 'package:frontend/core/widgets/app_popup.dart';
import 'package:flutter/material.dart';

import '../constants/colors.dart';
import '../models/pickup_location.dart';
import '../navigation/app_routes.dart';
import '../services/location_service.dart';
import '../theme/app_form_field_styles.dart';

class PickupLocationField extends StatelessWidget {
  const PickupLocationField({
    super.key,
    this.value,
    required this.onChanged,
    this.enabled = true,
    this.variant = AppFormFieldVariant.filled,
  });
  final PickupLocation? value;
  final ValueChanged<PickupLocation> onChanged;
  final bool enabled;
  final AppFormFieldVariant variant;

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
          color: variant == AppFormFieldVariant.outlined
              ? Colors.white
              : const Color(0xFFF0F1F2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
              variant == AppFormFieldVariant.outlined ? 16 : 24,
            ),
            side: variant == AppFormFieldVariant.outlined
                ? BorderSide(
                    color: field.hasError
                        ? Theme.of(context).colorScheme.error
                        : AppFormFieldStyles.outlinedBorderColor,
                  )
                : BorderSide.none,
          ),
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
            trailing: variant == AppFormFieldVariant.outlined && value != null
                ? const Text(
                    'เปลี่ยน',
                    style: TextStyle(
                      color: AppColors.primaryColor,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                : const Icon(Icons.chevron_right),
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
    subtitle: Text(location.name),
    trailing: const Icon(Icons.map_outlined),
    onTap: () => openPickupLocationInGoogleMaps(context, location),
  );
}

Future<void> openPickupLocationInGoogleMaps(
  BuildContext context,
  PickupLocation location,
) async {
  final opened = await LocationService.openInExternalMaps(
    location.latitude,
    location.longitude,
  );
  if (!opened && context.mounted) {
    showAppPopup(
      context,
      content: Text('ไม่สามารถเปิด Google Maps ได้ในขณะนี้'),
    );
  }
}
