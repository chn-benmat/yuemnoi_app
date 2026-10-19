import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/navigation/app_routes.dart';
import '../../../../core/network/auth_session.dart';
import '../../../../core/utils/auth_guard.dart';
import '../../domain/entities/rental_item.dart';
import '../bloc/rental_item_bloc.dart';
import '../bloc/rental_item_event.dart';
import '../bloc/rental_item_state.dart';
import '../widgets/rental_item_editor.dart';
import '../widgets/rental_item_form_value.dart';

class AddRentalItemScreen extends StatefulWidget {
  const AddRentalItemScreen({super.key});

  @override
  State<AddRentalItemScreen> createState() => _AddRentalItemScreenState();
}

class _AddRentalItemScreenState extends State<AddRentalItemScreen> {
  late final RentalItemFormValue _initialValue;

  @override
  void initState() {
    super.initState();
    _initialValue = RentalItemFormValue(
      photos: context
          .read<RentalItemBloc>()
          .state
          .images
          .map(RentalItemPhoto.local)
          .toList(growable: false),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!AuthSession.isAuthenticated && mounted) {
        AuthGuard.requireAuth(
          context,
          title: 'เข้าสู่ระบบเพื่อปล่อยเช่าอุปกรณ์',
          message: 'กรุณาเข้าสู่ระบบก่อนลงประกาศปล่อยเช่าอุปกรณ์ของคุณ',
        ).then((authed) {
          if (!authed && mounted) AppRoutes.pop(context);
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<RentalItemBloc, RentalItemState>(
        listener: (context, state) {
          if (state.status == RentalItemSubmissionStatus.success) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('ลงประกาศให้เช่าเรียบร้อยแล้ว')),
              );
              AppRoutes.pop(context, state.createdItem);
            });
          }
        },
        builder: (context, state) => RentalItemEditor(
          initialValue: _initialValue,
          isSaving: state.status == RentalItemSubmissionStatus.submitting,
          didSave: state.status == RentalItemSubmissionStatus.success,
          errorMessage: state.status == RentalItemSubmissionStatus.failure
              ? state.errorMessage ?? 'เพิ่มอุปกรณ์ไม่สำเร็จ กรุณาลองใหม่'
              : null,
          onSubmit: (value) => context.read<RentalItemBloc>().add(
            RentalItemSubmitted(
              RentalItemDraft(
                name: value.name,
                category: value.category!,
                description: value.description,
                rentalType: value.rentalType!,
                price: int.parse(value.price),
                images: value.photos
                    .map((photo) => photo.localImage!)
                    .toList(growable: false),
                pickupLocation: value.pickupLocation,
              ),
            ),
          ),
        ),
      );
}
