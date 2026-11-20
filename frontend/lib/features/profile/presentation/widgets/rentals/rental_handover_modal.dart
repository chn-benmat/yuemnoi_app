import 'package:frontend/core/widgets/app_popup.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../../core/constants/colors.dart';
import '../../../../../core/navigation/app_routes.dart';
import '../../../../../core/network/supabase_client.dart';
import '../../../../../core/services/booking_confirmation_tracker.dart';
import '../../../../../core/theme/app_text_styles.dart';
import '../../../data/repositories/rental_management_repository_impl.dart';
import '../../../domain/usecases/update_booking_status_usecase.dart';
import '../../pages/rentals/rental_payment_success_screen.dart';
import '../../../../rental_return/data/datasources/rental_return_remote_data_source.dart';

/// Modal สำหรับกระบวนการ "ตรวจรับอุปกรณ์ & ชำระเงิน" เมื่อนัดพบกัน (In-Person Handover)
class RentalHandoverModal extends StatefulWidget {
  final int? bookingId;
  final String? conversationId;
  final int? itemId;
  final String itemTitle;
  final String? itemImageUrl;
  final String ownerName;
  final String? renterName;
  final double totalPrice;
  final String paymentMethod; // 'promptpay' หรือ 'cash'
  final bool initialIsOwner;
  final int? initialStep;
  final ValueChanged<int>? onStepChanged;
  final ValueChanged<String>? onHandoverSuccess;
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
      return prefs.getInt(key) ?? 0;
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

  const RentalHandoverModal({
    super.key,
    this.bookingId,
    this.conversationId,
    this.itemId,
    required this.itemTitle,
    this.itemImageUrl,
    required this.ownerName,
    this.renterName,
    required this.totalPrice,
    this.paymentMethod = 'promptpay',
    this.initialIsOwner = false,
    this.initialStep,
    this.onStepChanged,
    this.onHandoverSuccess,
    this.updateBookingStatusUseCase,
  });

  static Future<void> show(
    BuildContext context, {
    int? bookingId,
    String? conversationId,
    int? itemId,
    required String itemTitle,
    String? itemImageUrl,
    required String ownerName,
    String? renterName,
    required double totalPrice,
    String paymentMethod = 'promptpay',
    bool initialIsOwner = false,
    int? initialStep,
    ValueChanged<int>? onStepChanged,
    ValueChanged<String>? onHandoverSuccess,
    UpdateBookingStatusUseCase? updateBookingStatusUseCase,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => RentalHandoverModal(
        bookingId: bookingId,
        conversationId: conversationId,
        itemId: itemId,
        itemTitle: itemTitle,
        itemImageUrl: itemImageUrl,
        ownerName: ownerName,
        renterName: renterName,
        totalPrice: totalPrice,
        paymentMethod: paymentMethod,
        initialIsOwner: initialIsOwner,
        initialStep: initialStep,
        onStepChanged: onStepChanged,
        onHandoverSuccess: onHandoverSuccess,
        updateBookingStatusUseCase: updateBookingStatusUseCase,
      ),
    );
  }

  @override
  State<RentalHandoverModal> createState() => _RentalHandoverModalState();
}

class _RentalHandoverModalState extends State<RentalHandoverModal> {
  late bool _isOwner;
  late final UpdateBookingStatusUseCase _updateBookingStatusUseCase;
  int _currentStep =
      0; // 0: ตรวจสภาพ, 1: ชำระเงิน, 2: รหัสยืนยัน PIN, 3: สำเร็จ
  int _maxStepReached = 0;

  // สเต็ป 3: Handover PIN & QR Code
  late final String _generatedPin;
  final TextEditingController _pinController = TextEditingController();
  String? _pinErrorMessage;
  bool _isSubmitting = false;
  bool _handoverCompleted = false;

  Timer? _statusPollTimer;
  RealtimeChannel? _realtimeChannel;

  String get _storageKey {
    return RentalHandoverModal.getStorageKey(
      bookingId: widget.bookingId,
      conversationId: widget.conversationId,
      itemId: widget.itemId,
      itemTitle: widget.itemTitle,
    );
  }

  String get _handoverChannelName {
    if (widget.bookingId != null && widget.bookingId! > 0) {
      return 'handover_b_${widget.bookingId}';
    }
    if (widget.conversationId != null && widget.conversationId!.isNotEmpty) {
      return 'handover_c_${widget.conversationId}';
    }
    if (widget.itemId != null && widget.itemId! > 0) {
      return 'handover_i_${widget.itemId}';
    }
    final clean = widget.itemTitle.replaceAll(
      RegExp(r'[^a-zA-Z0-9_\u0E00-\u0E7F]'),
      '_',
    );
    return 'handover_$clean';
  }

  @override
  void initState() {
    super.initState();
    _isOwner = widget.initialIsOwner;
    _updateBookingStatusUseCase =
        widget.updateBookingStatusUseCase ??
        UpdateBookingStatusUseCase(RentalManagementRepositoryImpl());

    if (_isOwner) {
      _currentStep =
          2; // ฝั่งผู้ปล่อยเช่าเริ่มที่ขั้นตอนเดียวคือ รับรหัสส่งมอบ ทันที
      _maxStepReached = 2;
    } else {
      final key = _storageKey;
      final cachedStep = RentalHandoverModal._memoryProgressCache[key];
      final cachedMax = RentalHandoverModal._memoryMaxStepCache[key];
      final initStep = widget.initialStep ?? cachedStep;
      if (initStep != null) {
        _currentStep = initStep.clamp(0, 2);
      }
      if (cachedMax != null) {
        _maxStepReached = cachedMax.clamp(_currentStep, 2);
      } else {
        _maxStepReached = _currentStep;
      }
      _loadSavedStep();
    }

    if (widget.bookingId != null && widget.bookingId! > 0) {
      _generatedPin = (1000 + (widget.bookingId! * 137) % 9000).toString();
    } else if (widget.itemId != null && widget.itemId! > 0) {
      _generatedPin = (1000 + (widget.itemId! * 137) % 9000).toString();
    } else {
      _generatedPin = '8492';
    }

    // เริ่มการซิงก์สถานะส่งมอบแบบ Realtime (ทั้งสองฝั่ง)
    _initHandoverSync();
  }

  Future<void> _loadSavedStep() async {
    if (_isOwner) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _storageKey;
      final savedStep = prefs.getInt(key);
      final savedMax = prefs.getInt('${key}_max');
      if (mounted) {
        setState(() {
          if (savedStep != null) {
            _currentStep = savedStep.clamp(0, 2);
            RentalHandoverModal._memoryProgressCache[key] = _currentStep;
          }
          if (savedMax != null) {
            _maxStepReached = savedMax.clamp(_currentStep, 2);
            RentalHandoverModal._memoryMaxStepCache[key] = _maxStepReached;
          } else {
            _maxStepReached = _currentStep;
            RentalHandoverModal._memoryMaxStepCache[key] = _currentStep;
          }
        });
        widget.onStepChanged?.call(_currentStep);
      }
    } catch (e) {
      debugPrint('Error loading saved handover step: $e');
    }
  }

  void _setStep(int newStep) {
    final clamped = newStep.clamp(0, 3);
    setState(() {
      _currentStep = clamped;
      if (_currentStep > _maxStepReached && _currentStep <= 2) {
        _maxStepReached = _currentStep;
      }
    });

    widget.onStepChanged?.call(_currentStep);

    if (!_isOwner && _currentStep < 3) {
      final key = _storageKey;
      RentalHandoverModal._memoryProgressCache[key] = _currentStep;
      RentalHandoverModal._memoryMaxStepCache[key] = _maxStepReached;
      SharedPreferences.getInstance()
          .then((prefs) {
            prefs.setInt(key, _currentStep);
            prefs.setInt('${key}_max', _maxStepReached);
          })
          .catchError((dynamic e) {
            debugPrint('Error saving handover step: $e');
          });
    }
  }

  Future<void> _clearSavedStep() async {
    final key = _storageKey;
    RentalHandoverModal._memoryProgressCache.remove(key);
    RentalHandoverModal._memoryMaxStepCache.remove(key);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
      await prefs.remove('${key}_max');
    } catch (e) {
      debugPrint('Error clearing saved handover step: $e');
    }
  }

  void _initHandoverSync() {
    if (!SupabaseConfig.isInitialized) return;

    try {
      final channelName = _handoverChannelName;
      _realtimeChannel = SupabaseConfig.client.channel(channelName);

      // 1. รับฟัง Realtime Broadcast เมื่อผู้ปล่อยเช่ายืนยัน PIN หรือสแกน QR Code สำเร็จ
      _realtimeChannel!.onBroadcast(
        event: 'handover_completed',
        callback: (payload) {
          debugPrint('Handover Broadcast received: $payload');
          if (mounted && !_isOwner) {
            _onHandoverCompleted();
          }
        },
      );

      // 2. รับฟัง Postgres Changes บน booking_tb เมื่อ status เปลี่ยนเป็น active
      if (widget.bookingId != null && widget.bookingId! > 0) {
        _realtimeChannel!.onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'booking_tb',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: widget.bookingId,
          ),
          callback: (payload) {
            final newStatus = payload.newRecord['status']?.toString();
            if (newStatus == 'active' && mounted && !_isOwner) {
              _onHandoverCompleted();
            }
          },
        );
      }

      _realtimeChannel!.subscribe();
    } catch (e) {
      debugPrint('Realtime channel init error: $e');
    }

    // 3. Fallback Polling ตรวจสอบทุก 1.5 วินาที สำหรับฝั่งผู้เช่า
    if (!_isOwner) {
      _statusPollTimer?.cancel();
      _statusPollTimer = Timer.periodic(const Duration(milliseconds: 1500), (
        _,
      ) async {
        if (!mounted) return;
        try {
          if (widget.bookingId != null && widget.bookingId! > 0) {
            final res = await SupabaseConfig.client
                .from('booking_tb')
                .select('status')
                .eq('id', widget.bookingId!)
                .maybeSingle();
            if (res != null && res['status'] == 'active' && mounted) {
              _onHandoverCompleted();
            }
          }
        } catch (_) {}
      });
    }
  }

  @override
  void dispose() {
    _statusPollTimer?.cancel();
    _realtimeChannel?.unsubscribe();
    _pinController.dispose();
    super.dispose();
  }

  void _onHandoverCompleted() {
    if (_handoverCompleted || !mounted) return;
    _handoverCompleted = true;
    _statusPollTimer?.cancel();
    _realtimeChannel?.unsubscribe();
    _clearSavedStep();
    if (!mounted) return;

    widget.onHandoverSuccess?.call('active');

    // นำทางทั้งสองฝั่งไปยังหน้าชำระเงินเสร็จสิ้น
    _navigateToPaymentSuccess();
  }

  void _navigateToPaymentSuccess() {
    if (!mounted) return;
    final nav = Navigator.of(context, rootNavigator: true);
    Navigator.of(context).pop(); // ปิด Modal
    nav.push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: AppRoutes.rentalPaymentSuccess),
        builder: (_) => RentalPaymentSuccessScreen(returnToChat: !_isOwner),
      ),
    );
  }

  Future<void> _completeHandover() async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);

    // บันทึกให้สำเร็จก่อนประกาศผล เพื่อไม่ให้สองเครื่องเห็นสถานะที่ server ปฏิเสธ
    try {
      if (widget.bookingId == null || widget.bookingId! <= 0) {
        throw StateError('ไม่พบรายการเช่าสำหรับการส่งมอบ');
      }
      await _updateBookingStatusUseCase.execute(
        bookingId: widget.bookingId!,
        status: 'active',
      );
      await BookingConfirmationTracker.markHandoverStarted(
        bookingId: widget.bookingId,
        startTime: DateTime.now(),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        showAppPopup(context, content: Text('ยืนยันส่งมอบไม่สำเร็จ: $e'));
      }
      return;
    }

    // 1. ส่ง Realtime Broadcast แจ้งฝั่งผู้เช่าทันที
    try {
      if (_realtimeChannel != null) {
        await _realtimeChannel!.sendBroadcastMessage(
          event: 'handover_completed',
          payload: {
            'status': 'active',
            'bookingId': widget.bookingId,
            'pin': _generatedPin,
            'completedAt': DateTime.now().toIso8601String(),
          },
        );
      }
    } catch (e) {
      debugPrint('Error sending realtime broadcast: $e');
    }

    // 3. แจ้งในข้อความแชต (ถ้ามี conversationId) เพื่อให้สถานะทั้งสองฝั่งตรงกัน
    if (widget.conversationId != null &&
        widget.conversationId!.isNotEmpty &&
        SupabaseConfig.isInitialized) {
      try {
        await SupabaseConfig.client
            .schema('messaging')
            .from('chat_message_tb')
            .insert({
              'conversation_id': widget.conversationId,
              'sender_id': SupabaseConfig.client.auth.currentUser?.id,
              'message':
                  '✅ ยืนยันการส่งมอบอุปกรณ์เรียบร้อยแล้ว เริ่มต้นช่วงเวลาเช่า',
              'is_read': false,
            });
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    _onHandoverCompleted();
  }

  void _verifyPinAndSubmit() {
    if (_pinController.text.trim() == _generatedPin) {
      setState(() => _pinErrorMessage = null);
      _completeHandover();
    } else {
      setState(() {
        _pinErrorMessage =
            'รหัส PIN ไม่ถูกต้อง (รหัสตัวอย่างคือ $_generatedPin)';
      });
    }
  }

  void _openQrScannerSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _OwnerQrScannerDialog(
        expectedPin: _generatedPin,
        onSuccess: () {
          Navigator.pop(ctx);
          _completeHandover();
        },
      ),
    );
  }

  Future<void> _openCancellationModal() async {
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

    if (result == true && mounted) {
      _clearSavedStep();
      Navigator.of(context).pop();
      widget.onHandoverSuccess?.call('cancelled');
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
                  _isOwner ? 'รับรหัสส่งมอบ' : 'ตรวจรับ & ชำระเงิน',
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

                // สเต็ปบาร์ (Step Progress) - แสดงเฉพาะฝั่งผู้เช่าที่มี 3 ขั้นตอน
                if (!_isOwner && _currentStep < 3) ...[
                  Row(
                    children: [
                      _buildStepIndicator(stepIndex: 0, label: '1. ตรวจสภาพ'),
                      _buildStepLine(isActive: _currentStep >= 1),
                      _buildStepIndicator(stepIndex: 1, label: '2. ชำระเงิน'),
                      _buildStepLine(isActive: _currentStep >= 2),
                      _buildStepIndicator(stepIndex: 2, label: '3. รหัสส่งมอบ'),
                    ],
                  ),
                  const SizedBox(height: 18),
                ],

                // เนื้อหาตามสเต็ป
                if (_currentStep == 0) _buildStepInspection(),
                if (_currentStep == 1) _buildStepPayment(),
                if (_currentStep == 2) _buildStepPinVerification(),
                if (_currentStep == 3) _buildStepSuccess(),
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
    final isAccessible = _currentStep < 2 && stepIndex <= _maxStepReached;

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
                  _isOwner
                      ? 'โปรดนำอุปกรณ์ให้ผู้เช่าตรวจสอบการทำงาน และถ่ายภาพเก็บเป็นหลักฐาน'
                      : 'โปรดตรวจเช็กสภาพอุปกรณ์จริงและอุปกรณ์เสริมร่วมกับผู้ปล่อยเช่า',
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
            onPressed: () => _setStep(1),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryColor,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'ไปยังการชำระเงิน',
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
    final isPromptPay = widget.paymentMethod == 'promptpay';

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
              Column(
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
                  Text(
                    '฿${widget.totalPrice.toStringAsFixed(0)}',
                    style: const TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
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
                  isPromptPay ? 'พร้อมเพย์ QR' : 'ชำระเงินสด',
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
        const SizedBox(height: 14),

        if (isPromptPay) ...[
          // Mockup PromptPay QR Code
          Center(
            child: Container(
              width: 170,
              height: 170,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.qr_code_2_rounded,
                    size: 105,
                    color: Color(0xFF0F172A),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'PromptPay: ${widget.ownerName}',
                    style: const TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 10.5,
                      color: Color(0xFF64748B),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _isOwner
                ? 'ให้ผู้เช่าสแกน QR Code นี้ผ่านแอปธนาคาร เมื่อเงินเข้าบัญชีแล้วให้กดยืนยันด้านล่าง'
                : 'สแกน QR Code เพื่อโอนเงินยอด ฿${widget.totalPrice.toStringAsFixed(0)} แล้วกดยืนยันการโอนเงิน',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 12.5,
              color: Color(0xFF64748B),
            ),
          ),
        ] else ...[
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
                      ? 'กรุณารับเงินสดจำนวน ฿${widget.totalPrice.toStringAsFixed(0)} จากผู้เช่าและนับให้ถูกต้อง'
                      : 'กรุณาส่งมอบเงินสดจำนวน ฿${widget.totalPrice.toStringAsFixed(0)} ให้แก่ผู้ปล่อยเช่า',
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
        ],

        const SizedBox(height: 18),

        // ปุ่มกดยืนยันการชำระเงิน
        if (!_isOwner) ...[
          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              onPressed: () {
                _setStep(2);
              },
              icon: const Icon(Icons.check_rounded, size: 18),
              label: Text(
                isPromptPay
                    ? 'ฉันโอนเงินเรียบร้อยแล้ว'
                    : 'ฉันส่งมอบเงินสดเรียบร้อยแล้ว',
                style: const TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
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
        ] else ...[
          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              onPressed: () {
                _setStep(2);
              },
              icon: const Icon(Icons.verified_rounded, size: 18),
              label: Text(
                'ยืนยันว่าได้รับเงินครบถ้วนแล้ว [฿${widget.totalPrice.toStringAsFixed(0)}]',
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
          ),
        ],
      ],
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Step 2: รหัสยืนยันการส่งมอบสองฝั่ง (Handover PIN & QR Code)
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildStepPinVerification() {
    final qrData =
        'yuemnoi://handover?bookingId=${widget.bookingId ?? 0}&pin=$_generatedPin';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _isOwner
              ? 'รับรหัสส่งมอบอุปกรณ์'
              : 'รหัสยืนยันการรับมอบอุปกรณ์ (Handover Code)',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 15.5,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1E2022),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          _isOwner
              ? 'สแกน QR Code หรือกรอกรหัส PIN 4 หลักจากหน้าจอของผู้เช่า เพื่อยืนยันเริ่มการเช่า'
              : 'แสดง QR Code หรือบอกรหัส PIN 4 หลักนี้แก่ผู้ปล่อยเช่า\nเพื่อให้ผู้ปล่อยเช่าสแกนยืนยันเริ่มการเช่าของสำเร็จ',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 12.5,
            color: Color(0xFF64748B),
            height: 1.4,
          ),
        ),
        const SizedBox(height: 16),

        if (!_isOwner) ...[
          // ── ฝั่งผู้เช่า: สร้าง QR Code และรหัส PIN ให้ผู้ปล่อยเช่าสแกน ─────────────
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // QR Code
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      color: Colors.white,
                      child: QrImageView(
                        data: qrData,
                        version: QrVersions.auto,
                        size: 160.0,
                        backgroundColor: Colors.white,
                        eyeStyle: const QrEyeStyle(
                          eyeShape: QrEyeShape.square,
                          color: AppColors.primaryColor,
                        ),
                        dataModuleStyle: const QrDataModuleStyle(
                          dataModuleShape: QrDataModuleShape.square,
                          color: Color(0xFF1E2022),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // แถบแยก
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 28,
                        height: 1,
                        color: const Color(0xFFE2E8F0),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          'หรือบอกรหัส PIN 4 หลัก',
                          style: TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 11.5,
                            color: Color(0xFF94A3B8),
                          ),
                        ),
                      ),
                      Container(
                        width: 28,
                        height: 1,
                        color: const Color(0xFFE2E8F0),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // แสดงรหัส PIN 4 หลักเป็นกล่องตัวเลข
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: _generatedPin.split('').map((digit) {
                      return Container(
                        width: 44,
                        height: 50,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F3FF),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.primaryColor.withValues(
                              alpha: 0.35,
                            ),
                            width: 1.5,
                          ),
                        ),
                        child: Text(
                          digit,
                          style: const TextStyle(
                            fontFamily: AppTextStyles.fontFamily,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryColor,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 8),
                  // ปุ่มคัดลอกรหัส PIN
                  InkWell(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: _generatedPin));
                    },
                    borderRadius: BorderRadius.circular(12),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.copy_rounded,
                            size: 14,
                            color: AppColors.primaryColor,
                          ),
                          SizedBox(width: 4),
                          Text(
                            'คัดลอกรหัส PIN',
                            style: TextStyle(
                              fontFamily: AppTextStyles.fontFamily,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primaryColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          // แถบสถานะรอผู้ปล่อยเช่าสแกน
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppColors.primaryColor,
                    ),
                  ),
                  SizedBox(width: 8),
                  Text(
                    'กำลังรอผู้ปล่อยเช่าสแกนหรือใส่รหัส PIN...',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 12,
                      color: Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
        ] else ...[
          // ── ฝั่งผู้ปล่อยเช่า: สแกน QR Code หรือกรอกรหัส PIN จากผู้เช่า ────────
          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _openQrScannerSheet,
              icon: const Icon(Icons.qr_code_scanner_rounded, size: 20),
              label: const Text(
                'เปิดกล้องสแกน QR Code ของผู้เช่า',
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          // แถบแยก
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(width: 28, height: 1, color: const Color(0xFFE2E8F0)),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  'หรือกรอกรหัส PIN 4 หลักจากผู้เช่า',
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 11.5,
                    color: Color(0xFF94A3B8),
                  ),
                ),
              ),
              Container(width: 28, height: 1, color: const Color(0xFFE2E8F0)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 180,
                child: TextField(
                  controller: _pinController,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 8,
                  ),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: '••••',
                    hintStyle: const TextStyle(
                      letterSpacing: 8,
                      color: Color(0xFFCBD5E1),
                    ),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(
                        color: AppColors.primaryColor,
                        width: 2,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (_pinErrorMessage != null) ...[
            const SizedBox(height: 6),
            Text(
              _pinErrorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 12,
                color: Color(0xFFEF4444),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Center(
            child: TextButton(
              onPressed: () {
                _pinController.text = _generatedPin;
              },
              child: Text(
                'คลิกเพื่อใส่รหัสทดสอบ ($_generatedPin)',
                style: const TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 12,
                  color: AppColors.primaryColor,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _isSubmitting ? null : _verifyPinAndSubmit,
              icon: _isSubmitting
                  ? const SizedBox.shrink()
                  : const Icon(Icons.check_circle_rounded, size: 18),
              label: _isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      'ยืนยันรหัส & เริ่มการเช่า',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
        ],
      ],
    );
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Step 3: ส่งมอบสำเร็จ (Success)
  // ───────────────────────────────────────────────────────────────────────────
  Widget _buildStepSuccess() {
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: const Color(0xFF10B981).withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.check_circle_rounded,
            color: Color(0xFF10B981),
            size: 48,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          _isOwner ? 'ส่งมอบอุปกรณ์สำเร็จ!' : 'ส่งมอบและเริ่มการเช่าสำเร็จ!',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1E2022),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _isOwner
              ? 'สถานะการเช่าเปลี่ยนเป็น "กำลังปล่อยเช่า" เรียบร้อยแล้ว ระบบได้บันทึกการส่งมอบอุปกรณ์เสร็จสมบูรณ์'
              : 'สถานะการเช่าเปลี่ยนเป็น "กำลังเช่า" เรียบร้อยแล้ว ตัวนับเวลาการเช่าเริ่มต้นขึ้นแล้ว',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 13,
            color: Color(0xFF64748B),
            height: 1.45,
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
            ),
            child: const Text(
              'เสร็จสิ้น',
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Dialog สแกน QR Code ของผู้เช่าสำหรับผู้ปล่อยเช่า (Camera Scanner Simulation)
/// Dialog สแกน QR Code ของผู้เช่าสำหรับผู้ปล่อยเช่า ด้วยกล้องจริง (MobileScanner)
class _OwnerQrScannerDialog extends StatefulWidget {
  final String expectedPin;
  final VoidCallback onSuccess;

  const _OwnerQrScannerDialog({
    required this.expectedPin,
    required this.onSuccess,
  });

  @override
  State<_OwnerQrScannerDialog> createState() => _OwnerQrScannerDialogState();
}

class _OwnerQrScannerDialogState extends State<_OwnerQrScannerDialog>
    with SingleTickerProviderStateMixin {
  late final MobileScannerController _scannerController;
  late final AnimationController _animationController;
  late final Animation<double> _scanLineAnimation;
  bool _hasScanned = false;
  bool _isTorchOn = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
    );
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _scanLineAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  void _handleBarcode(BarcodeCapture capture) {
    if (_hasScanned) return;

    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue ?? barcode.displayValue;
      if (raw != null && raw.isNotEmpty) {
        final pin = _extractPin(raw);
        if (pin == widget.expectedPin || raw.contains(widget.expectedPin)) {
          _hasScanned = true;
          HapticFeedback.mediumImpact();
          widget.onSuccess();
          return;
        } else {
          setState(() {
            _errorMessage = 'QR Code นี้ไม่ใช่รหัสส่งมอบที่ถูกต้อง (พบ: $pin)';
          });
        }
      }
    }
  }

  String _extractPin(String raw) {
    final trimmed = raw.trim();
    if (trimmed == widget.expectedPin) return trimmed;
    try {
      final uri = Uri.tryParse(trimmed);
      if (uri != null && uri.queryParameters.containsKey('pin')) {
        final p = uri.queryParameters['pin'];
        if (p != null && p.isNotEmpty) return p;
      }
    } catch (_) {}
    if (trimmed.contains(widget.expectedPin)) return widget.expectedPin;
    final match = RegExp(r'\b\d{4}\b').firstMatch(trimmed);
    if (match != null) return match.group(0)!;
    return trimmed;
  }

  @override
  Widget build(BuildContext context) {
    const scanSize = 240.0;
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.qr_code_scanner_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'สแกน QR Code ของผู้เช่า',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  IconButton(
                    tooltip: 'เปิด/ปิดแฟลช',
                    icon: Icon(
                      _isTorchOn
                          ? Icons.flash_on_rounded
                          : Icons.flash_off_rounded,
                      color: _isTorchOn
                          ? const Color(0xFFFFD700)
                          : Colors.white70,
                    ),
                    onPressed: () async {
                      await _scannerController.toggleTorch();
                      setState(() => _isTorchOn = !_isTorchOn);
                    },
                  ),
                  IconButton(
                    tooltip: 'สลับกล้องหน้า/หลัง',
                    icon: const Icon(
                      Icons.flip_camera_ios_rounded,
                      color: Colors.white70,
                    ),
                    onPressed: () => _scannerController.switchCamera(),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'ส่องกล้องไปที่ QR Code บนหน้าจอโทรศัพท์ของผู้เช่า เพื่อตรวจสอบรหัสการรับมอบ',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 12.5,
              color: Colors.white70,
            ),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 12,
                color: Color(0xFFEF4444),
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
          const SizedBox(height: 20),

          // Viewfinder box พร้อมกล้องจริง MobileScanner
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: SizedBox(
                width: scanSize,
                height: scanSize,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    MobileScanner(
                      controller: _scannerController,
                      onDetect: _handleBarcode,
                      errorBuilder: (context, error) {
                        return Container(
                          color: const Color(0xFF1E293B),
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.camera_alt_outlined,
                                color: Colors.white54,
                                size: 40,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'ไม่สามารถเปิดกล้องได้: ${error.errorCode.name}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontFamily: AppTextStyles.fontFamily,
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    // Corner guides
                    SizedBox(
                      width: scanSize,
                      height: scanSize,
                      child: CustomPaint(
                        painter: _ScannerCornerPainter(
                          color: const Color(0xFFC084FC),
                        ),
                      ),
                    ),
                    // Animated scan line
                    AnimatedBuilder(
                      animation: _scanLineAnimation,
                      builder: (context, child) {
                        return Positioned(
                          top: 10 + (scanSize - 20) * _scanLineAnimation.value,
                          left: 12,
                          right: 12,
                          child: Container(
                            height: 3,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  Colors.transparent,
                                  Color(0xFFC084FC),
                                  Colors.white,
                                  Color(0xFFC084FC),
                                  Colors.transparent,
                                ],
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(
                                    0xFFC084FC,
                                  ).withValues(alpha: 0.8),
                                  blurRadius: 8,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // ปุ่มจำลอง/สำรองกรณีทดสอบบน Emulator หรือไม่สามารถใช้กล้องได้
          SizedBox(
            width: double.infinity,
            height: 46,
            child: OutlinedButton.icon(
              onPressed: () {
                _hasScanned = true;
                widget.onSuccess();
              },
              icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
              label: Text(
                'จำลองสแกนสำเร็จ (PIN: ${widget.expectedPin})',
                style: const TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFC084FC),
                side: const BorderSide(color: Color(0xFFC084FC), width: 1.2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScannerCornerPainter extends CustomPainter {
  final Color color;
  const _ScannerCornerPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const length = 24.0;
    // Top-Left
    canvas.drawLine(const Offset(0, 0), const Offset(length, 0), paint);
    canvas.drawLine(const Offset(0, 0), const Offset(0, length), paint);

    // Top-Right
    canvas.drawLine(
      Offset(size.width, 0),
      Offset(size.width - length, 0),
      paint,
    );
    canvas.drawLine(Offset(size.width, 0), Offset(size.width, length), paint);

    // Bottom-Left
    canvas.drawLine(Offset(0, size.height), Offset(length, size.height), paint);
    canvas.drawLine(
      Offset(0, size.height),
      Offset(0, size.height - length),
      paint,
    );

    // Bottom-Right
    canvas.drawLine(
      Offset(size.width, size.height),
      Offset(size.width - length, size.height),
      paint,
    );
    canvas.drawLine(
      Offset(size.width, size.height),
      Offset(size.width, size.height - length),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
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
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        showAppPopup(context, content: Text('ยกเลิกไม่สำเร็จ: $e'));
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
