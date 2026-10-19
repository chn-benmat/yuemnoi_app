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
      rentalType: item.rentalType,
      price: item.price.toString(),
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
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('บันทึกการแก้ไขเรียบร้อยแล้ว')),
              );
              AppRoutes.pop(context, true);
            });
          }
        },
        builder: (context, state) => RentalItemEditor(
          initialValue: _initialValue,
          isEditing: true,
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
                  rentalType: value.rentalType!,
                  price: int.parse(value.price),
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
