import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/widgets/app_primary_button.dart';
import '../../data/datasources/item_auto_reply_remote_data_source.dart';
import '../../data/repositories/item_auto_reply_repository_impl.dart';
import '../../domain/entities/item_detail.dart';
import '../../domain/usecases/manage_item_auto_reply_usecase.dart';
import '../bloc/item_auto_reply_cubit.dart';

class ItemAutoReplyScreen extends StatefulWidget {
  const ItemAutoReplyScreen({super.key, required this.item, this.manage});
  final ItemDetail item;
  final ManageItemAutoReplyUseCase? manage;

  @override
  State<ItemAutoReplyScreen> createState() => _ItemAutoReplyScreenState();
}

class _ItemAutoReplyScreenState extends State<ItemAutoReplyScreen> {
  final _messageController = TextEditingController();
  late final ItemAutoReplyCubit _cubit;

  @override
  void initState() {
    super.initState();
    _cubit = ItemAutoReplyCubit(
      itemId: widget.item.id,
      manage:
          widget.manage ??
          ManageItemAutoReplyUseCase(
            ItemAutoReplyRepositoryImpl(ItemAutoReplyRemoteDataSource()),
          ),
    );
    if (widget.item.isOwner) _cubit.load();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _cubit.close();
    super.dispose();
  }

  Future<void> _leave() async {
    if (_cubit.state.saving) return;
    if (_cubit.state.dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('ยังไม่ได้บันทึกการตั้งค่า'),
          content: const Text('ต้องการออกโดยไม่บันทึกการเปลี่ยนแปลงไหม'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('แก้ไขต่อ'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('ไม่บันทึก'),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  void _showPreview() {
    FocusManager.instance.primaryFocus?.unfocus();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFF7F6FA),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * .75,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'ตัวอย่างในแชท',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.item.name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF817A91),
                  ),
                ),
                const SizedBox(height: 28),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Text(
                      'สนใจเช่าอุปกรณ์นี้ค่ะ',
                      style: TextStyle(fontSize: 14),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth:
                          (MediaQuery.sizeOf(sheetContext).width - 40) * .88,
                    ),
                    child: Container(
                      key: const ValueKey('auto-reply-preview-bubble'),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.primaryColor,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        _messageController.text.trim(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          height: 1.6,
                        ),
                      ),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                    'ตัวอย่างข้อความตอบกลับอัตโนมัติ',
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 11, color: Color(0xFF817A91)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) =>
      BlocConsumer<ItemAutoReplyCubit, ItemAutoReplyState>(
        bloc: _cubit,
        listener: (context, state) {
          if (_messageController.text != state.draft.message) {
            _messageController.value = TextEditingValue(
              text: state.draft.message,
              selection: TextSelection.collapsed(
                offset: state.draft.message.length,
              ),
            );
          }
        },
        builder: (context, state) => PopScope(
          canPop: !state.dirty && !state.saving,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _leave();
          },
          child: _buildScreen(state),
        ),
      );

  Widget _buildScreen(ItemAutoReplyState state) => Scaffold(
    backgroundColor: const Color(0xFFF7F6FA),
    appBar: AppBar(
      centerTitle: true,
      leading: IconButton(
        tooltip: 'ย้อนกลับ',
        onPressed: state.saving ? null : _leave,
        icon: const Icon(Icons.arrow_back_rounded),
      ),
      title: const Text(
        'ข้อความตอบกลับอัตโนมัติ',
        style: TextStyle(
          fontFamily: AppTextStyles.fontFamily,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    body: !widget.item.isOwner
        ? const Center(child: Text('เฉพาะเจ้าของเท่านั้นที่ตั้งค่าอุปกรณ์ได้'))
        : state.loading
        ? const Center(child: CircularProgressIndicator())
        : state.saved == null
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    state.error ?? 'โหลดการตั้งค่าไม่สำเร็จ',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _cubit.load,
                    child: const Text('ลองใหม่'),
                  ),
                ],
              ),
            ),
          )
        : SafeArea(
            top: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Text(
                      widget.item.name,
                      style: const TextStyle(
                        fontSize: 17,
                        height: 1.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      clipBehavior: Clip.antiAlias,
                      child: SwitchListTile.adaptive(
                        value: state.draft.enabled,
                        onChanged: state.saving
                            ? null
                            : (value) => _cubit.change(enabled: value),
                        activeTrackColor: AppColors.primaryColor,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        title: const Text(
                          'เปิดการตอบกลับอัตโนมัติ',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        subtitle: const Padding(
                          padding: EdgeInsets.only(top: 6),
                          child: Text(
                            'ตอบครั้งแรกเมื่อผู้เช่าสอบถามอุปกรณ์นี้',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF817A91),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Text(
                      'ข้อความตอบกลับ',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      key: const ValueKey('auto-reply-message'),
                      controller: _messageController,
                      enabled: !state.saving,
                      minLines: 4,
                      maxLines: 7,
                      onChanged: (value) => _cubit.change(message: value),
                      decoration: InputDecoration(
                        counterText: '${state.draft.message.runes.length}/500',
                        errorText: state.draft.message.runes.length > 500
                            ? 'ข้อความต้องไม่เกิน 500 ตัวอักษร'
                            : null,
                        hintText:
                            'พิมพ์ข้อความต้อนรับหรือข้อมูลที่อยากแจ้งผู้เช่า',
                        hintStyle: const TextStyle(
                          fontSize: 14,
                          height: 1.6,
                          color: Color(0xFF9C94A9),
                        ),
                        filled: true,
                        fillColor: !state.saving
                            ? Colors.white
                            : const Color(0xFFEEECF2),
                        contentPadding: const EdgeInsets.all(16),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(
                            color: Color(0xFFE7E3EE),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(
                            color: Color(0xFFE7E3EE),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: const BorderSide(
                            color: AppColors.primaryColor,
                          ),
                        ),
                        disabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextButton.icon(
                      onPressed:
                          !state.saving && state.draft.message.trim().isNotEmpty
                          ? _showPreview
                          : null,
                      icon: const Icon(
                        Icons.chat_bubble_outline_rounded,
                        size: 18,
                      ),
                      label: const Text('ดูตัวอย่างในแชท'),
                    ),
                    const SizedBox(height: 12),
                    if (state.error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          state.error!,
                          style: const TextStyle(color: Color(0xFFB3261E)),
                        ),
                      ),
                    AppPrimaryButton(
                      key: const ValueKey('save-auto-reply'),
                      text: 'บันทึก',
                      isLoading: state.saving,
                      onPressed: state.dirty && !state.saving
                          ? _cubit.save
                          : null,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      state.dirty
                          ? 'การเปลี่ยนแปลงจะมีผลเมื่อกดบันทึก'
                          : 'ส่งเพียงครั้งเดียวต่อผู้เช่าและอุปกรณ์ แม้เจ้าของไม่ได้เปิดแอป',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.6,
                        color: Color(0xFF817A91),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
  );
}
