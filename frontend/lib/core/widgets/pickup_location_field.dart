import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:geolocator/geolocator.dart';

import '../constants/colors.dart';
import '../models/pickup_location.dart';
import '../navigation/app_routes.dart';
import '../services/map_device_position.dart';
import '../theme/app_form_field_styles.dart';
import 'longdo_map_view.dart';

class PickupLocationField extends StatefulWidget {
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
  State<PickupLocationField> createState() => _PickupLocationFieldState();
}

class _PickupLocationFieldState extends State<PickupLocationField> {
  Future<Position?>? _preparedPosition;
  DateTime? _positionRequestedAt;
  ScrollPosition? _scrollPosition;
  bool _nearViewport = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scrollPosition?.removeListener(_prepareWhenNearViewport);
    _scrollPosition = Scrollable.maybeOf(context)?.position;
    _scrollPosition?.addListener(_prepareWhenNearViewport);
    _nearViewport = false;
    _schedulePreparation();
  }

  @override
  void didUpdateWidget(covariant PickupLocationField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled &&
        (!oldWidget.enabled || widget.value != oldWidget.value)) {
      _nearViewport = false;
      _schedulePreparation();
    }
  }

  void _schedulePreparation() {
    if (_scrollPosition == null) {
      _preparePicker();
    } else {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _prepareWhenNearViewport(),
      );
    }
  }

  void _prepareWhenNearViewport() {
    if (!mounted || !widget.enabled || !LongdoMapView.isAvailable) return;
    final scroll = _scrollPosition;
    final render = context.findRenderObject();
    if (scroll == null ||
        !scroll.hasViewportDimension ||
        render is! RenderBox ||
        !render.attached ||
        !render.hasSize) {
      return;
    }
    final viewport = RenderAbstractViewport.maybeOf(render);
    if (viewport == null) return;
    final distance =
        viewport.getOffsetToReveal(render, 1).offset - scroll.pixels;
    final nearby = distance.abs() <= scroll.viewportDimension;
    if (nearby && !_nearViewport) _preparePicker();
    _nearViewport = nearby;
  }

  @override
  void dispose() {
    _scrollPosition?.removeListener(_prepareWhenNearViewport);
    super.dispose();
  }

  Future<Position?>? _preparePicker() {
    if (!widget.enabled || !LongdoMapView.isAvailable) return null;

    final saved = widget.value;
    if (saved != null) {
      unawaited(
        LongdoMapView.preloadPicker(
          Future.value(mapPoint(saved.latitude, saved.longitude)),
        ),
      );
      return null;
    }

    final now = DateTime.now();
    final requestedAt = _positionRequestedAt;
    if (requestedAt == null ||
        now.difference(requestedAt) >= const Duration(seconds: 25)) {
      _positionRequestedAt = now;
      _preparedPosition = _readDevicePosition();
    }
    final position = _preparedPosition!;
    unawaited(
      LongdoMapView.preloadPicker(
        position.then((value) => mapPoint(value?.latitude, value?.longitude)),
      ),
    );
    return position;
  }

  Future<Position?> _readDevicePosition() async {
    try {
      return await getMapDevicePosition(requestPermission: false);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) => FormField<PickupLocation>(
    initialValue: widget.value,
    autovalidateMode: AutovalidateMode.onUserInteraction,
    validator: (selected) =>
        selected?.isValid == true && selected?.hasCoordinates == true
        ? null
        : 'กรุณาระบุจุดนัดรับสินค้า',
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
          color: widget.variant == AppFormFieldVariant.outlined
              ? Colors.white
              : const Color(0xFFF0F1F2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
              widget.variant == AppFormFieldVariant.outlined ? 16 : 24,
            ),
            side: widget.variant == AppFormFieldVariant.outlined
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
            title: Text(widget.value?.name ?? 'ระบุจุดนัดรับสินค้า'),
            trailing:
                widget.variant == AppFormFieldVariant.outlined &&
                    widget.value != null
                ? const Text(
                    'เปลี่ยน',
                    style: TextStyle(
                      color: AppColors.primaryColor,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                : const Icon(Icons.chevron_right),
            onTap: !widget.enabled
                ? null
                : () async {
                    final selected = await AppRoutes.openPickupDetails(
                      context,
                      initialLocation: widget.value,
                      initialDevicePosition: _preparePicker(),
                    );
                    if (selected == null || !context.mounted) return;
                    field.didChange(selected);
                    widget.onChanged(selected);
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
  Widget build(BuildContext context) {
    final address = location.address.trim();
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(
        Icons.location_on_outlined,
        color: AppColors.primaryColor,
      ),
      title: const Text('จุดนัดรับสินค้า'),
      subtitle: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [Text(location.name), if (address.isNotEmpty) Text(address)],
      ),
    );
  }
}
