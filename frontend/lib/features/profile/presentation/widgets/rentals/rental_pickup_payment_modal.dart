import 'package:frontend/core/widgets/app_popup.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../../core/constants/colors.dart';
import '../../../../../core/network/api_client.dart';
import '../../../../../core/network/supabase_client.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../data/datasources/promptpay_app_launcher.dart';
import '../../../data/repositories/rental_management_repository_impl.dart';
import '../../../domain/entities/rental_handover_payment.dart';
import '../../../domain/usecases/update_booking_status_usecase.dart';
import '../../../../rental_return/data/datasources/rental_return_remote_data_source.dart';

/// Modal สำหรับกระบวนการ "ตรวจรับอุปกรณ์ & ชำระเงิน" เมื่อนัดพบกัน
class RentalPickupPaymentModal extends StatefulWidget {
  final int? bookingId;
  final String? conversationId;
  final int? itemId;
  final String itemTitle;
  final double totalPrice;
  final String paymentMethod; // 'promptpay' หรือ 'cash'
  final bool initialIsOwner;
  final int? initialStep;
  final bool openPaymentAppOnShow;
  final ValueChanged<int>? onStepChanged;
  final ValueChanged<String>? onFinished;
  final UpdateBookingStatusUseCase? updateBookingStatusUseCase;

  static final Map<String, int> _memoryProgressCache = {};
  static final Map<String, int> _memoryMaxStepCache = {};

  static String getStorageKey({
    int? bookingId,
    String? conversationId,
    int? itemId,
    String? itemTitle,
  }) {
    if (bookingId != null && bookingId > 0) {
      return 'handover_progress_step_booking_$bookingId';
    }
    if (conversationId != null && conversationId.isNotEmpty) {
      return 'handover_progress_step_conv_$conversationId';
    }
    if (itemId != null && itemId > 0) {
      return 'handover_progress_step_item_$itemId';
    }
    final clean = (itemTitle ?? 'default').replaceAll(
      RegExp(r'[^a-zA-Z0-9_]'),
      '_',
    );
    return 'handover_progress_step_title_$clean';
  }

  static int getCachedStep({
    int? bookingId,
    String? conversationId,
    int? itemId,
    String? itemTitle,
  }) {
    final key = getStorageKey(
      bookingId: bookingId,
      conversationId: conversationId,
      itemId: itemId,
      itemTitle: itemTitle,
    );
    return _memoryProgressCache[key] ?? 0;
  }

  static Future<int> getSavedStep({
    int? bookingId,
    String? conversationId,
    int? itemId,
    String? itemTitle,
  }) async {
    final key = getStorageKey(
      bookingId: bookingId,
      conversationId: conversationId,
      itemId: itemId,
      itemTitle: itemTitle,
    );
    final cached = _memoryProgressCache[key];
    if (cached != null) return cached;
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getInt(key) ?? 0).clamp(0, 1);
    } catch (_) {
      return 0;
    }
  }

  static Future<void> clearSavedStep({
    int? bookingId,
    String? conversationId,
    int? itemId,
    String? itemTitle,
  }) async {
    final key = getStorageKey(
      bookingId: bookingId,
      conversationId: conversationId,
      itemId: itemId,
      itemTitle: itemTitle,
    );
    _memoryProgressCache.remove(key);
    _memoryMaxStepCache.remove(key);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
      await prefs.remove('${key}_max');
    } catch (_) {}
  }

  const RentalPickupPaymentModal({
    super.key,
    this.bookingId,
    this.conversationId,
    this.itemId,
    required this.itemTitle,
    required this.totalPrice,
    this.paymentMethod = 'promptpay',
    this.initialIsOwner = false,
    this.initialStep,
    this.openPaymentAppOnShow = false,
    this.onStepChanged,
    this.onFinished,
    this.updateBookingStatusUseCase,
  });

  static Future<String?> show(
    BuildContext context, {
    int? bookingId,
    String? conversationId,
    int? itemId,
    required String itemTitle,
    required double totalPrice,
    String paymentMethod = 'promptpay',
    bool initialIsOwner = false,
    int? initialStep,
    bool openPaymentAppOnShow = false,
    ValueChanged<int>? onStepChanged,
    UpdateBookingStatusUseCase? updateBookingStatusUseCase,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => RentalPickupPaymentModal(
        bookingId: bookingId,
        conversationId: conversationId,
        itemId: itemId,
        itemTitle: itemTitle,
        totalPrice: totalPrice,
        paymentMethod: paymentMethod,
        initialIsOwner: initialIsOwner,
        initialStep: initialStep,
        openPaymentAppOnShow: openPaymentAppOnShow,
        onStepChanged: onStepChanged,
        onFinished: (status) => Navigator.of(context).pop(status),
        updateBookingStatusUseCase: updateBookingStatusUseCase,
      ),
    );
  }

  @override
  State<RentalPickupPaymentModal> createState() =>
      _RentalPickupPaymentModalState();
}

class _RentalPickupPaymentModalState extends State<RentalPickupPaymentModal> {
  bool get _isOwner => widget.initialIsOwner;
  late final UpdateBookingStatusUseCase _updateBookingStatusUseCase;
  int _currentStep = 0; // 0: ตรวจสภาพ, 1: ชำระเงิน
  int _maxStepReached = 0;

  RentalHandoverPayment? _handoverPayment;
  String? _finishedStatus;
  late final Future<void> _initialPaymentLoad;
  bool _isReadingPayment = false;
  bool _isConfirmingPayment = false;
  bool _isSavingPromptPayAccount = false;
  bool _isEditingPromptPayAccount = false;
  bool _usePromptPayNationalId = false;
  final _promptPayFormKey = GlobalKey<FormState>();
  final _promptPayIdentifierController = TextEditingController();
  String? _paymentError;
  bool _isChoosingPaymentApp = false;
  String? _paymentAppMessage;

  bool get _canOpenPaymentApp =>
      !_isOwner &&
      _currentStep == 1 &&
      _isPromptPay &&
      _finishedStatus == null &&
      _handoverPayment?.paymentConfirmed != true &&
      PromptPayAppLauncher.isSupported;

  Timer? _statusPollTimer;
  RealtimeChannel? _realtimeChannel;

  bool get _hasBooking => (widget.bookingId ?? 0) > 0;
  bool get _isPromptPay =>
      (_handoverPayment?.paymentMethod ?? widget.paymentMethod) == 'promptpay';

  String? get _ownerPaymentQr =>
      _isEditingPromptPayAccount || _handoverPayment?.canCollectPayment != true
      ? null
      : _handoverPayment?.promptPayQr;

  String get _paymentAmountLabel {
    final satang = _handoverPayment?.totalSatang;
    final amount = satang == null ? widget.totalPrice : satang / 100;
    return '฿${amount.toStringAsFixed(amount % 1 == 0 ? 0 : 2)}';
  }

  String get _storageKey {
    return RentalPickupPaymentModal.getStorageKey(
      bookingId: widget.bookingId,
      conversationId: widget.conversationId,
      itemId: widget.itemId,
      itemTitle: widget.itemTitle,
    );
  }

  @override
  void initState() {
    super.initState();
    _updateBookingStatusUseCase =
        widget.updateBookingStatusUseCase ??
        UpdateBookingStatusUseCase(RentalManagementRepositoryImpl());

    if (_isOwner) {
      _currentStep = 1;
    } else {
      final key = _storageKey;
      final cachedStep = RentalPickupPaymentModal._memoryProgressCache[key];
      final cachedMax = RentalPickupPaymentModal._memoryMaxStepCache[key];
      final initStep = widget.initialStep ?? cachedStep;
      if (initStep != null) {
        _currentStep = initStep.clamp(0, 1);
      }
      if (cachedMax != null) {
        _maxStepReached = cachedMax.clamp(_currentStep, 1);
      } else {
        _maxStepReached = _currentStep;
      }
      _loadSavedStep();
    }

    _initialPaymentLoad = _refreshHandoverPayment();
    if (widget.openPaymentAppOnShow) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          unawaited(_openPaymentApp());
        }
      });
    }
    if (_hasBooking && !_isOwner) {
      _statusPollTimer = Timer.periodic(
        const Duration(milliseconds: 1500),
        (_) => _refreshHandoverPayment(),
      );
    }
    if (_hasBooking && !_isOwner && SupabaseConfig.isInitialized) {
      _realtimeChannel = SupabaseConfig.client
          .channel('rental_payment_${widget.bookingId}')
          .onPostgresChanges(
            event: PostgresChangeEvent.update,
            schema: 'public',
            table: 'booking_tb',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'id',
              value: widget.bookingId,
            ),
            callback: (_) => _refreshHandoverPayment(),
          )
          .subscribe();
    }
  }

  Future<void> _refreshHandoverPayment({
    bool confirm = false,
    String? promptPayPhone,
    String? promptPayNationalId,
  }) async {
    if (!_hasBooking ||
        _finishedStatus != null ||
        _isReadingPayment ||
        _isConfirmingPayment ||
        _isSavingPromptPayAccount) {
      return;
    }

    final isSavingAccount =
        promptPayPhone != null || promptPayNationalId != null;
    final isUpdatingPayment = confirm || isSavingAccount;
    if (isUpdatingPayment) {
      setState(() {
        _isConfirmingPayment = confirm;
        _isSavingPromptPayAccount = isSavingAccount;
        _paymentError = null;
      });
    } else {
      _isReadingPayment = true;
    }
    try {
      final payment = await _updateBookingStatusUseCase.handoverPayment(
        bookingId: widget.bookingId!,
        confirm: confirm,
        promptPayPhone: promptPayPhone,
        promptPayNationalId: promptPayNationalId,
      );
      if (!mounted || _finishedStatus != null) return;
      if (payment.status != 'confirmed') {
        _finishWithStatus(payment.status);
        return;
      }
      if (isSavingAccount) _promptPayIdentifierController.clear();
      setState(() {
        _handoverPayment = payment;
        _paymentError = confirm
            ? 'ยังเริ่มการเช่าไม่ได้ กรุณาตรวจสอบสถานะแล้วลองอีกครั้ง'
            : null;
        if (isSavingAccount) _isEditingPromptPayAccount = false;
      });
    } catch (error) {
      if (mounted &&
          (isUpdatingPayment || _isOwner || _handoverPayment == null)) {
        setState(() => _paymentError = _userFacingPaymentError(error));
      }
    } finally {
      _isReadingPayment = false;
      if (mounted && _finishedStatus == null && isUpdatingPayment) {
        setState(() {
          _isConfirmingPayment = false;
          _isSavingPromptPayAccount = false;
        });
      }
    }
  }

  String _userFacingPaymentError(Object error) {
    if (error is ApiClientException) {
      return switch (error.type) {
        ApiClientErrorType.connection =>
          'ไม่มีการเชื่อมต่ออินเทอร์เน็ต กรุณาตรวจสอบแล้วลองใหม่',
        ApiClientErrorType.timeout =>
          'การเชื่อมต่อใช้เวลานานเกินไป กรุณาลองใหม่',
        ApiClientErrorType.invalidResponse =>
          'ระบบยังตอบกลับไม่สมบูรณ์ กรุณาลองใหม่',
      };
    }
    if (error is StateError) {
      return error.message.toString();
    }
    return 'ทำรายการไม่สำเร็จ กรุณาลองใหม่อีกครั้ง';
  }

  Future<void> _loadSavedStep() async {
    if (_isOwner) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _storageKey;
      final savedStep = prefs.getInt(key);
      final savedMax = prefs.getInt('${key}_max');
      if (mounted && _finishedStatus == null) {
        setState(() {
          if (savedStep != null) {
            _currentStep = savedStep.clamp(0, 1);
            RentalPickupPaymentModal._memoryProgressCache[key] = _currentStep;
          }
          if (savedMax != null) {
            _maxStepReached = savedMax.clamp(_currentStep, 1);
            RentalPickupPaymentModal._memoryMaxStepCache[key] = _maxStepReached;
          } else {
            _maxStepReached = _currentStep;
            RentalPickupPaymentModal._memoryMaxStepCache[key] = _currentStep;
          }
        });
        widget.onStepChanged?.call(_currentStep);
      }
    } catch (e) {
      debugPrint('โหลดขั้นตอนชำระเงินไม่สำเร็จ: $e');
    }
  }

  Future<void> _openPaymentApp() async {
    if (!_canOpenPaymentApp || _isChoosingPaymentApp) return;
    setState(() {
      _isChoosingPaymentApp = true;
      _paymentAppMessage = null;
    });
    try {
      await _initialPaymentLoad;
      if (!mounted || !_canOpenPaymentApp) return;
      final apps = await PromptPayAppLauncher.installedApps();
      if (!mounted || !_canOpenPaymentApp) return;
      if (apps.isEmpty) {
        setState(() {
          _paymentAppMessage = 'ไม่พบแอปชำระเงินที่รองรับบนเครื่องนี้';
        });
        return;
      }
      final app = apps.length == 1 ? apps.single : await _pickPaymentApp(apps);
      if (!mounted || !_canOpenPaymentApp) return;
      if (app == null) {
        _setStep(0);
        return;
      }
      final didOpen = await PromptPayAppLauncher.open(app);
      if (!didOpen && mounted) {
        setState(() {
          _paymentAppMessage =
              'เปิดแอปที่เลือกไม่ได้ ปิดหน้านี้แล้วกดชำระเงินอีกครั้ง';
        });
      }
    } on Exception {
      if (mounted) {
        setState(() {
          _paymentAppMessage =
              'เปิดแอปชำระเงินไม่สำเร็จ ปิดหน้านี้แล้วกดชำระเงินอีกครั้ง';
        });
      }
    } finally {
      if (mounted && _finishedStatus == null) {
        setState(() => _isChoosingPaymentApp = false);
      }
      _closeIfFinished();
    }
  }

  Future<PromptPayApp?> _pickPaymentApp(List<PromptPayApp> apps) {
    return showModalBottomSheet<PromptPayApp>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.65,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'เลือกแอปสำหรับสแกนจ่าย',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Text('เปิดแอปแล้วเลือกเมนูสแกน'),
                  ],
                ),
              ),
              for (final app in apps)
                ListTile(
                  leading: const Icon(Icons.account_balance_wallet_outlined),
                  title: Text(app.name),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).pop(app),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _setStep(int newStep) {
    setState(() {
      _currentStep = newStep;
      if (_currentStep > _maxStepReached) {
        _maxStepReached = _currentStep;
      }
    });

    widget.onStepChanged?.call(_currentStep);
    if (!_isOwner) {
      final key = _storageKey;
      RentalPickupPaymentModal._memoryProgressCache[key] = _currentStep;
      RentalPickupPaymentModal._memoryMaxStepCache[key] = _maxStepReached;
      SharedPreferences.getInstance()
          .then((prefs) {
            prefs.setInt(key, _currentStep);
            prefs.setInt('${key}_max', _maxStepReached);
          })
          .catchError((dynamic e) {
            debugPrint('บันทึกขั้นตอนชำระเงินไม่สำเร็จ: $e');
          });
    }
  }

  Future<void> _clearSavedStep() async {
    final key = _storageKey;
    RentalPickupPaymentModal._memoryProgressCache.remove(key);
    RentalPickupPaymentModal._memoryMaxStepCache.remove(key);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
      await prefs.remove('${key}_max');
    } catch (e) {
      debugPrint('ล้างขั้นตอนชำระเงินไม่สำเร็จ: $e');
    }
  }

  @override
  void dispose() {
    _statusPollTimer?.cancel();
    _realtimeChannel?.unsubscribe();
    _promptPayIdentifierController.dispose();
    super.dispose();
  }

  void _finishWithStatus(String status) {
    if (_finishedStatus != null) return;
    _finishedStatus = status;
    _statusPollTimer?.cancel();
    unawaited(_clearSavedStep());
    _closeIfFinished();
  }

  void _closeIfFinished() {
    final status = _finishedStatus;
    if (mounted &&
        status != null &&
        ModalRoute.of(context)?.isCurrent == true) {
      widget.onFinished?.call(status);
    }
  }

  Future<void> _openCancellationModal() async {
    if (_isOwner) return;
    if (widget.bookingId == null || widget.bookingId! <= 0) {
      showAppPopup(
        context,
        content: const Text('ไม่พบรายการเช่าที่ต้องการยกเลิก'),
      );
      return;
    }

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => RentalCancellationModal(
        bookingId: widget.bookingId,
        itemTitle: widget.itemTitle,
        updateBookingStatusUseCase: _updateBookingStatusUseCase,
      ),
    );

    if (!mounted) return;
    if (result == true) {
      _finishWithStatus('cancelled');
    } else {
      _closeIfFinished();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 12,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ขีดจับลาก
                Center(
                  child: Container(
                    width: 38,
                    height: 4.5,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),

                // หัวแถว: ชื่อหัวข้อ
                Text(
                  !_isOwner ? 'ตรวจรับ & ชำระเงิน' : 'ยืนยันการรับชำระเงิน',
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 10),

                // การ์ดแสดงชื่ออุปกรณ์ที่ตรวจรับ
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.inventory_2_outlined,
                        size: 16,
                        color: Color(0xFF64748B),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.itemTitle,
                          style: const TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF0F172A),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // สเต็ปบาร์ (Step Progress) - แสดงเฉพาะฝั่งผู้เช่า
                if (!_isOwner) ...[
                  Row(
                    children: [
                      _buildStepIndicator(stepIndex: 0, label: '1. ตรวจสภาพ'),
                      _buildStepLine(isActive: _currentStep >= 1),
                      _buildStepIndicator(stepIndex: 1, label: '2. ชำระเงิน'),
                    ],
                  ),
                  const SizedBox(height: 18),
                ],

                // เนื้อหาตามสเต็ป
                if (_currentStep == 0) _buildStepInspection(),
                if (_currentStep == 1) _buildStepPayment(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepIndicator({required int stepIndex, required String label}) {
    final isPassed = _currentStep > stepIndex;
    final isCurrent = _currentStep == stepIndex;
    final isAccessible = stepIndex <= _maxStepReached;

    final Color badgeBg = isCurrent
        ? AppColors.primaryColor
        : (isPassed ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9));
    final Color badgeFg = isCurrent || isPassed
        ? Colors.white
        : const Color(0xFF94A3B8);
    final Color textColor = isCurrent
        ? AppColors.primaryColor
        : (isPassed ? const Color(0xFF0F172A) : const Color(0xFF94A3B8));

    return InkWell(
      onTap: isAccessible && !isCurrent ? () => _setStep(stepIndex) : null,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Column(
          children: [
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: badgeBg,
                borderRadius: BorderRadius.circular(6),
              ),
              child: isPassed
                  ? const Icon(
                      Icons.check_rounded,
                      size: 13,
                      color: Colors.white,
                    )
                  : Text(
                      '${stepIndex + 1}',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: badgeFg,
                      ),
                    ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 11,
                fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                color: textColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepLine({required bool isActive}) {
    return Expanded(
      child: Container(
        height: 1.5,
        margin: const EdgeInsets.only(bottom: 16),
        color: isActive ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0),
      ),
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Step 0: ตรวจสภาพสินค้า (Inspection)
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildStepInspection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.info_outline_rounded,
                color: Color(0xFF64748B),
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'โปรดตรวจเช็กสภาพอุปกรณ์จริงและอุปกรณ์เสริมร่วมกับผู้ปล่อยเช่า',
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 13,
                    color: Color(0xFF334155),
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: () async {
              _setStep(1);
              await _openPaymentApp();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryColor,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'ชำระเงิน',
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 46,
          child: OutlinedButton(
            onPressed: _openCancellationModal,
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Color(0xFFFECACA)),
              backgroundColor: const Color(0xFFFFF5F5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            child: const Text(
              'ยกเลิกการเช่า (สินค้ามีปัญหา / ไม่พร้อมใช้งาน)',
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
                color: Color(0xFFDC2626),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Step 1: ชำระเงิน (Payment)
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildStepPayment() {
    final isPromptPay = _isPromptPay;
    final amount = _paymentAmountLabel;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // กล่องยอดเงิน - Solid Brand Purple with Clean Swiss Typography (No loud rainbow gradient)
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.primaryColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ยอดชำระสุทธิ',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        amount,
                        style: const TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isPromptPay ? 'พร้อมเพย์' : 'ชำระเงินสด',
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (!isPromptPay || _isOwner) const SizedBox(height: 14),

        if (isPromptPay && _isOwner)
          _buildOwnerPromptPay()
        else if (!isPromptPay)
          // กรณีเงินสด - Clean Swiss Neutral Card (No neon green pastel slop)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.payments_outlined,
                  color: Color(0xFF0F172A),
                  size: 28,
                ),
                const SizedBox(height: 8),
                Text(
                  _isOwner
                      ? 'กรุณารับเงินสดจำนวน $amount จากผู้เช่าและนับให้ถูกต้อง'
                      : 'กรุณาชำระเงินสดจำนวน $amount ให้แก่ผู้ปล่อยเช่า',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 13,
                    color: Color(0xFF0F172A),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

        if (_canOpenPaymentApp && _paymentAppMessage != null) ...[
          const SizedBox(height: 8),
          Text(_paymentAppMessage!, textAlign: TextAlign.center),
        ],
        if (_paymentError != null) ...[
          const SizedBox(height: 8),
          Text(
            _paymentError!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.red),
          ),
          if (_isOwner && _handoverPayment == null)
            TextButton(
              onPressed: () => _refreshHandoverPayment(),
              child: const Text('ลองตรวจสอบอีกครั้ง'),
            ),
        ],
        if (_isOwner &&
            _handoverPayment?.status == 'confirmed' &&
            (!isPromptPay ||
                _ownerPaymentQr != null ||
                _handoverPayment?.paymentConfirmed == true)) ...[
          const SizedBox(height: 18),
          _buildOwnerPaymentButton(
            onPressed: _isConfirmingPayment
                ? null
                : () => _refreshHandoverPayment(confirm: true),
            icon: Icons.verified_rounded,
            label: _isConfirmingPayment
                ? 'กำลังยืนยันการรับเงิน...'
                : 'ยืนยันว่าได้รับเงินครบถ้วนแล้ว [$amount]',
          ),
        ],
        if (!_isOwner) ...[
          const SizedBox(height: 14),
          const Text(
            'รอผู้ปล่อยเช่ายืนยันว่าได้รับเงินเพื่อเริ่มการเช่า',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 40,
            child: TextButton.icon(
              onPressed: () => _setStep(0),
              icon: const Icon(
                Icons.arrow_back_rounded,
                size: 16,
                color: Color(0xFF64748B),
              ),
              label: const Text(
                'ย้อนกลับไปตรวจสภาพ',
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildOwnerPaymentButton({
    required VoidCallback? onPressed,
    required IconData icon,
    required String label,
  }) {
    return SizedBox(
      height: 48,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(
          label,
          style: const TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontWeight: FontWeight.w700,
            fontSize: 13.5,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _buildOwnerPromptPay() {
    if (!_hasBooking) {
      return const Text(
        'ไม่พบรายการเช่าสำหรับสร้าง QR พร้อมเพย์',
        textAlign: TextAlign.center,
      );
    }
    final payment = _handoverPayment;
    if (payment == null) {
      return _paymentError == null
          ? const Center(child: CircularProgressIndicator())
          : const SizedBox.shrink();
    }
    if (payment.paymentConfirmed) {
      return const Text(
        'บันทึกการรับเงินแล้ว กดยืนยันเพื่อเริ่มการเช่า',
        textAlign: TextAlign.center,
      );
    }
    if (!payment.canCollectPayment) {
      return Column(
        children: [
          Text(
            (payment.totalSatang ?? 0) > 0
                ? 'สร้าง QR พร้อมเพย์ได้เมื่อยืนยันการจองและถึงเวลานัดรับ'
                : 'ไม่พบยอดเช่าสำหรับสร้าง QR พร้อมเพย์',
            textAlign: TextAlign.center,
          ),
          TextButton(
            onPressed: () => _refreshHandoverPayment(),
            child: const Text('ตรวจสอบสถานะอีกครั้ง'),
          ),
        ],
      );
    }

    final qr = _ownerPaymentQr;
    final savedNationalId = payment.promptPayIdType == 'national_id';
    if (qr != null) {
      return Column(
        children: [
          QrImageView(
            data: qr,
            size: 216,
            padding: const EdgeInsets.all(24),
            backgroundColor: Colors.white,
            semanticsLabel: 'QR พร้อมเพย์สำหรับชำระค่าเช่า',
          ),
          const Text(
            'ให้ผู้เช่าสแกนด้วยแอปธนาคารหรือวอลเล็ตที่รองรับพร้อมเพย์ ตรวจยอดเข้าก่อนกดยืนยัน',
            textAlign: TextAlign.center,
          ),
          TextButton(
            onPressed: _isConfirmingPayment
                ? null
                : () {
                    _promptPayIdentifierController.text = savedNationalId
                        ? ''
                        : payment.promptPayPhone ?? '';
                    setState(() {
                      _usePromptPayNationalId = savedNationalId;
                      _isEditingPromptPayAccount = true;
                    });
                  },
            child: Text(
              savedNationalId ? 'เปลี่ยนเลขพร้อมเพย์' : 'เปลี่ยนเบอร์พร้อมเพย์',
            ),
          ),
        ],
      );
    }

    return Form(
      key: _promptPayFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('เบอร์มือถือ')),
              ButtonSegment(value: true, label: Text('เลขบัตรประชาชน')),
            ],
            selected: {_usePromptPayNationalId},
            showSelectedIcon: false,
            onSelectionChanged: _isSavingPromptPayAccount
                ? null
                : (selection) {
                    if (selection.single == _usePromptPayNationalId) return;
                    _promptPayIdentifierController.clear();
                    setState(() {
                      _usePromptPayNationalId = selection.single;
                      _paymentError = null;
                    });
                  },
          ),
          const SizedBox(height: 8),
          TextFormField(
            key: ValueKey(_usePromptPayNationalId),
            controller: _promptPayIdentifierController,
            enabled: !_isSavingPromptPayAccount,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(
                _usePromptPayNationalId ? 13 : 10,
              ),
            ],
            decoration: InputDecoration(
              labelText: _usePromptPayNationalId
                  ? 'เลขบัตรประชาชนที่ผูกพร้อมเพย์'
                  : 'เบอร์มือถือที่ผูกพร้อมเพย์',
              hintText: _usePromptPayNationalId ? null : '08XXXXXXXX',
              helperText: 'บันทึกไว้ใช้กับรายการเช่าถัดไป',
              border: const OutlineInputBorder(),
            ),
            validator: (value) {
              if (_usePromptPayNationalId) {
                return value?.length == 13
                    ? null
                    : 'กรุณากรอกเลขบัตรประชาชน 13 หลัก';
              }
              return RegExp(r'^0[689][0-9]{8}$').hasMatch(value ?? '')
                  ? null
                  : 'กรุณากรอกเบอร์มือถือพร้อมเพย์ 10 หลัก';
            },
            onFieldSubmitted: (_) => _savePromptPayAccount(),
          ),
          if (_usePromptPayNationalId)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('QR จะมีเลขบัตรประชาชนสำหรับการสแกนโอน'),
            ),
          const SizedBox(height: 8),
          _buildOwnerPaymentButton(
            onPressed: _isSavingPromptPayAccount ? null : _savePromptPayAccount,
            icon: Icons.qr_code_rounded,
            label: _isSavingPromptPayAccount
                ? 'กำลังบันทึกข้อมูลพร้อมเพย์...'
                : _usePromptPayNationalId
                ? 'บันทึกเลขบัตรและสร้าง QR'
                : 'บันทึกเบอร์และสร้าง QR',
          ),
          if (_isEditingPromptPayAccount)
            TextButton(
              onPressed: _isSavingPromptPayAccount
                  ? null
                  : () => setState(() {
                      _promptPayIdentifierController.clear();
                      _isEditingPromptPayAccount = false;
                      _paymentError = null;
                    }),
              child: Text(savedNationalId ? 'ใช้เลขเดิม' : 'ใช้เบอร์เดิม'),
            ),
        ],
      ),
    );
  }

  void _savePromptPayAccount() {
    if (_promptPayFormKey.currentState?.validate() != true) return;
    FocusScope.of(context).unfocus();
    final identifier = _promptPayIdentifierController.text;
    _refreshHandoverPayment(
      promptPayPhone: _usePromptPayNationalId ? null : identifier,
      promptPayNationalId: _usePromptPayNationalId ? identifier : null,
    );
  }
}

/// Modal สำหรับการขอยกเลิกการเช่า พร้อมระบุปัญหาและแนบรูปภาพหลักฐาน
class RentalCancellationModal extends StatefulWidget {
  final int? bookingId;
  final String itemTitle;
  final UpdateBookingStatusUseCase updateBookingStatusUseCase;

  const RentalCancellationModal({
    super.key,
    this.bookingId,
    required this.itemTitle,
    required this.updateBookingStatusUseCase,
  });

  @override
  State<RentalCancellationModal> createState() =>
      _RentalCancellationModalState();
}

class _RentalCancellationModalState extends State<RentalCancellationModal> {
  // Checklist ปัญหาที่พบ
  bool _reasonPowerIssue = false;
  bool _reasonDamage = false;
  bool _reasonMissingAccessories = false;
  bool _reasonNotAsDescribed = false;
  bool _reasonOther = false;
  final TextEditingController _otherReasonController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();

  // ภาพถ่ายหลักฐาน (จำเป็น)
  final List<XFile> _attachedImages = [];
  final ImagePicker _imagePicker = ImagePicker();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _otherReasonController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  bool get _hasSelectedReason {
    return _reasonPowerIssue ||
        _reasonDamage ||
        _reasonMissingAccessories ||
        _reasonNotAsDescribed ||
        (_reasonOther && _otherReasonController.text.trim().isNotEmpty);
  }

  bool get _canSubmit {
    return _hasSelectedReason && _attachedImages.isNotEmpty && !_isSubmitting;
  }

  Future<void> _pickImage(ImageSource source) async {
    if (_attachedImages.length >= 5) {
      showAppPopup(context, content: const Text('แนบภาพถ่ายได้ไม่เกิน 5 รูป'));
      return;
    }

    try {
      final picked = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
      if (picked != null && mounted) {
        setState(() {
          _attachedImages.add(picked);
        });
      }
    } catch (e) {
      if (mounted) {
        showAppPopup(context, content: Text('ไม่สามารถเลือกรูปภาพได้'));
      }
    }
  }

  void _showImageSourceDialog() {
    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Text(
                'แนบภาพถ่ายหลักฐานปัญหา',
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E2022),
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.camera_alt_rounded,
                    color: Color(0xFF2563EB),
                  ),
                ),
                title: const Text(
                  'ถ่ายภาพด้วยกล้อง',
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.photo_library_rounded,
                    color: Color(0xFF64748B),
                  ),
                ),
                title: const Text(
                  'เลือกจากคลังรูปภาพ',
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _pickImage(ImageSource.gallery);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submitCancellation() async {
    if (!_canSubmit) return;

    final confirmed = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444)),
            SizedBox(width: 8),
            Text(
              'ยืนยันการยกเลิกการเช่า',
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: const Text(
          'คุณต้องการยกเลิกการเช่าอุปกรณ์นี้ใช่หรือไม่? ระบบจะบันทึกสาเหตุและรูปภาพหลักฐานไว้',
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 13.5,
            color: Color(0xFF475569),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'ย้อนกลับ',
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                color: Color(0xFF64748B),
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'ยืนยันยกเลิก',
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isSubmitting = true);

    try {
      if (widget.bookingId == null || widget.bookingId! <= 0) {
        throw StateError('ไม่พบรายการเช่าสำหรับการยกเลิก');
      }
      final reasons = <String>[
        if (_reasonPowerIssue) 'อุปกรณ์เปิดไม่ติดหรือทำงานผิดปกติ',
        if (_reasonDamage) 'อุปกรณ์มีรอยเสียหาย',
        if (_reasonMissingAccessories) 'อุปกรณ์เสริมไม่ครบ',
        if (_reasonNotAsDescribed) 'ไม่ตรงตามรายละเอียด',
        if (_reasonOther) _otherReasonController.text.trim(),
      ];
      await RentalReturnRemoteDataSource().cancelRental(
        rentalId: widget.bookingId!,
        reason: reasons.join(', '),
        note: _noteController.text.trim(),
        photos: _attachedImages,
      );
    } catch (error) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        final message = error is StateError
            ? error.message.toString()
            : 'ยกเลิกการเช่าไม่สำเร็จ กรุณาลองใหม่';
        showAppPopup(context, content: Text(message));
      }
      return;
    }

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ขีดจับลาก
              Center(
                child: Container(
                  width: 38,
                  height: 4.5,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),

              // หัวแถว: หัวข้อ + ปุ่มปิด
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'ระบุปัญหา & ขอยกเลิกการเช่า',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 17.5,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFEF4444),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context, false),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Color(0xFF64748B),
                      size: 22,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // การ์ดชื่อสินค้า
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.inventory_2_outlined,
                      size: 16,
                      color: Color(0xFF64748B),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.itemTitle,
                        style: const TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1E2022),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // คำแนะนำการยกเลิก
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFECACA)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      color: Color(0xFFEF4444),
                      size: 18,
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'กรุณาระบุปัญหาที่พบและแนบรูปภาพสภาพจริง เพื่อยืนยันว่าพบปัญหาและไม่พร้อมรับสินค้าจริง ไม่เช่นนั้นจะไม่สามารถกดยืนยันการยกเลิกได้',
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 12,
                          color: Color(0xFF991B1B),
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // หัวข้อเหตุผล
              const Text(
                'ปัญหาที่พบ (เลือกอย่างน้อย 1 ข้อ):',
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E2022),
                ),
              ),
              const SizedBox(height: 4),
              CheckboxListTile(
                value: _reasonPowerIssue,
                onChanged: (v) =>
                    setState(() => _reasonPowerIssue = v ?? false),
                title: const Text(
                  'เครื่องเปิดไม่ติด / ใช้งานไม่ได้',
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 13,
                  ),
                ),
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
                contentPadding: EdgeInsets.zero,
                activeColor: const Color(0xFFEF4444),
              ),
              CheckboxListTile(
                value: _reasonDamage,
                onChanged: (v) => setState(() => _reasonDamage = v ?? false),
                title: const Text(
                  'มีตำหนิ แตกหัก หรือชำรุดเสียหาย',
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 13,
                  ),
                ),
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
                contentPadding: EdgeInsets.zero,
                activeColor: const Color(0xFFEF4444),
              ),
              CheckboxListTile(
                value: _reasonMissingAccessories,
                onChanged: (v) =>
                    setState(() => _reasonMissingAccessories = v ?? false),
                title: const Text(
                  'อุปกรณ์เสริมไม่ครบตามที่ระบุไว้',
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 13,
                  ),
                ),
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
                contentPadding: EdgeInsets.zero,
                activeColor: const Color(0xFFEF4444),
              ),
              CheckboxListTile(
                value: _reasonNotAsDescribed,
                onChanged: (v) =>
                    setState(() => _reasonNotAsDescribed = v ?? false),
                title: const Text(
                  'สินค้าไม่ตรงกับรุ่นหรือสภาพที่ลงประกาศไว้',
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 13,
                  ),
                ),
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
                contentPadding: EdgeInsets.zero,
                activeColor: const Color(0xFFEF4444),
              ),
              CheckboxListTile(
                value: _reasonOther,
                onChanged: (v) => setState(() => _reasonOther = v ?? false),
                title: const Text(
                  'อื่นๆ',
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 13,
                  ),
                ),
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
                contentPadding: EdgeInsets.zero,
                activeColor: const Color(0xFFEF4444),
              ),
              if (_reasonOther) ...[
                Padding(
                  padding: const EdgeInsets.only(left: 32, bottom: 8),
                  child: TextField(
                    controller: _otherReasonController,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: 'โปรดระบุสาเหตุอื่นๆ...',
                      hintStyle: const TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 12.5,
                        color: Color(0xFF94A3B8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Color(0xFFEF4444)),
                      ),
                    ),
                    style: const TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 14),

              // ส่วนแนบรูปภาพ
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'แนบภาพถ่ายหลักฐานปัญหา (จำเป็น):',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E2022),
                    ),
                  ),
                  if (_attachedImages.isEmpty)
                    const Text(
                      '* ต้องแนบรูปถ่าย',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFEF4444),
                      ),
                    )
                  else
                    Text(
                      'แนบแล้ว ${_attachedImages.length} ภาพ',
                      style: const TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF10B981),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),

              // รายการรูปภาพ Thumbnail + ปุ่มเพิ่มรูป
              SizedBox(
                height: 84,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    // ปุ่มกดเพิ่มรูปภาพ
                    InkWell(
                      onTap: _showImageSourceDialog,
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _attachedImages.isEmpty
                                ? const Color(0xFFFCA5A5)
                                : const Color(0xFFCBD5E1),
                            width: 1.5,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.add_a_photo_rounded,
                              size: 24,
                              color: _attachedImages.isEmpty
                                  ? const Color(0xFFEF4444)
                                  : const Color(0xFF64748B),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'เพิ่มรูปภาพ',
                              style: TextStyle(
                                fontFamily: AppTextStyles.fontFamily,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: _attachedImages.isEmpty
                                    ? const Color(0xFFEF4444)
                                    : const Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    // รูปที่แนบแล้ว
                    for (int i = 0; i < _attachedImages.length; i++) ...[
                      Stack(
                        children: [
                          Container(
                            width: 80,
                            height: 80,
                            margin: const EdgeInsets.only(right: 8),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(11),
                              child: Image.file(
                                File(_attachedImages[i].path),
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                          Positioned(
                            top: 2,
                            right: 10,
                            child: GestureDetector(
                              onTap: () {
                                setState(() {
                                  _attachedImages.removeAt(i);
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.all(3),
                                decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.close,
                                  size: 13,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 14),

              // รายละเอียดเพิ่มเติม
              const Text(
                'หมายเหตุเพิ่มเติม (ถ้ามี):',
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E2022),
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _noteController,
                maxLines: 2,
                inputFormatters: [LengthLimitingTextInputFormatter(2000)],
                decoration: InputDecoration(
                  hintText: 'รายละเอียดเพิ่มเติมเพื่อแจ้งผู้ปล่อยเช่า...',
                  hintStyle: const TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 12.5,
                    color: Color(0xFF94A3B8),
                  ),
                  contentPadding: const EdgeInsets.all(12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFEF4444)),
                  ),
                ),
                style: const TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 13,
                ),
              ),

              const SizedBox(height: 20),

              // ปุ่มยืนยันการยกเลิก
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _canSubmit ? _submitCancellation : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEF4444),
                    disabledBackgroundColor: const Color(0xFFE2E8F0),
                    foregroundColor: Colors.white,
                    disabledForegroundColor: const Color(0xFF94A3B8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                    elevation: _canSubmit ? 2 : 0,
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          !_hasSelectedReason
                              ? 'กรุณาเลือกปัญหาอย่างน้อย 1 ข้อ'
                              : (_attachedImages.isEmpty
                                    ? 'แนบภาพถ่ายก่อนจึงจะกดยกเลิกได้'
                                    : 'ยืนยันการยกเลิกการเช่า'),
                          style: const TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
