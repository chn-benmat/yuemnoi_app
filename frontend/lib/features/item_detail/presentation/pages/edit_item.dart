import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/navigation/app_routes.dart';
import '../../../rental_item/domain/entities/rental_item.dart';
import '../../../rental_item/presentation/widgets/rental_item_editor.dart';
import '../../../rental_item/presentation/widgets/rental_item_form_value.dart';
import '../../domain/entities/item_detail.dart';
import '../bloc/item_detail_bloc.dart';
import '../bloc/item_detail_event.dart';
import '../bloc/item_detail_state.dart';

class EditItemScreen extends StatefulWidget {
  const EditItemScreen({super.key, required this.item});
  final ItemDetail item;

  @override
  State<EditItemScreen> createState() => _EditItemScreenState();
}

class _EditItemScreenState extends State<EditItemScreen> {
  late final RentalItemFormValue _initialValue;
  bool _submitted = false;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    _initialValue = RentalItemFormValue(
      name: item.name,
      description: item.description,
      category: item.category,
      hourlyPrice: item.hourlyPrice?.toString() ?? '',
      dailyPrice: item.dailyPrice?.toString() ?? '',
      damageFee: item.penaltyTerms.damageFee > 0
          ? item.penaltyTerms.damageFee.toString()
          : '',
      lateReturnFee: item.penaltyTerms.lateReturnFee > 0
          ? item.penaltyTerms.lateReturnFee.toString()
          : '',
      damageTerms: item.penaltyTerms.damageTerms,
      photos: item.imageUrls
          .map(RentalItemPhoto.remote)
          .toList(growable: false),
      pickupLocation: item.pickupLocation,
    );
  }

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<ItemDetailBloc, ItemDetailState>(
        listenWhen: (previous, current) => previous.status != current.status,
        listener: (context, state) {
          if (_submitted && state.status == ItemDetailStatus.loaded) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;

              AppRoutes.pop(context, true);
            });
          }
        },
        builder: (context, state) => RentalItemEditor(
          initialValue: _initialValue,
          isEditing: true,
          onPreview: (value) => AppRoutes.openItemPreview(
            context,
            item: ItemDetail(
              id: widget.item.id,
              owner: widget.item.owner,
              name: value.name,
              imageUrls: value.photos
                  .where((photo) => photo.remoteUrl != null)
                  .map((photo) => photo.remoteUrl!)
                  .toList(),
              description: value.description,
              category: value.category ?? '',
              price: value.price ?? 0,
              additionalDailyPrice: value.additionalDailyPrice,
              penaltyTerms: value.penaltyTerms,
              status: widget.item.status,
              rentalType: value.rentalType,
              reviews: widget.item.reviews,
              isOwner: true,
              ownerHidden: widget.item.ownerHidden,
              pickupLocation: value.pickupLocation,
            ),
            photos: value.photos,
          ),
          isSaving: state.isBusy,
          didSave: _submitted && state.status == ItemDetailStatus.loaded,
          errorMessage: state.status == ItemDetailStatus.failure
              ? state.errorMessage ?? 'แก้ไขอุปกรณ์ไม่สำเร็จ กรุณาลองใหม่'
              : null,
          onSubmit: (value) {
            _submitted = true;
            context.read<ItemDetailBloc>().add(
              ItemDetailUpdateSubmitted(
                ItemEditDraft(
                  itemId: widget.item.id,
                  name: value.name,
                  category: value.category!,
                  description: value.description,
                  hourlyRate: value.hourlyRate,
                  dailyRate: value.dailyRate,
                  penaltyTerms: value.penaltyTerms,
                  retainedImageUrls: value.photos
                      .where((photo) => photo.remoteUrl != null)
                      .map((photo) => photo.remoteUrl!)
                      .toList(growable: false),
                  newImages: value.photos
                      .where((photo) => photo.localImage != null)
                      .map((photo) => photo.localImage!)
                      .toList(growable: false),
                  imageOrder: value.photos,
                  pickupLocation: value.pickupLocation,
                ),
              ),
            );
          },
        ),
      );
}
