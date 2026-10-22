import 'package:frontend/core/widgets/app_popup.dart';
import 'package:flutter/material.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../../../core/network/supabase_client.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../profile/data/datasources/profile_storefront_remote_data_source.dart';

/// หน้าจอ UI สำหรับรีวิวประสบการณ์การเช่าสินค้า (Rental Review Screen)
/// แบบฟอร์มรีวิวพร้อมบันทึกผลลง Supabase หลังยืนยันการส่ง
class RentalReviewScreen extends StatefulWidget {
  final String itemName;
  final int? itemId;
  final String itemSubtitle;
  final String ownerName;
  final String? itemImageUrl;
  final String? ownerAvatarUrl;
  final String? ownerId;
  final ProfileStorefrontRemoteDataSource? profileSource;

  const RentalReviewScreen({
    super.key,
    this.itemName = 'อุปกรณ์ที่เช่า',
    this.itemId,
    this.itemSubtitle = '',
    this.ownerName = 'ผู้ปล่อยเช่า',
    this.itemImageUrl,
    this.ownerAvatarUrl,
    this.ownerId,
    this.profileSource,
  });

  @override
  State<RentalReviewScreen> createState() => _RentalReviewScreenState();
}

class _RentalReviewScreenState extends State<RentalReviewScreen> {
  String? _ownerAvatarUrl;
  int _selectedRating = 0;
  bool _isSubmitting = false;
  late final TextEditingController _reviewController;
  final Set<String> _selectedTags = {};

  // ตัวเลือกข้อความประทับใจด่วน (2 คอลัมน์)
  static const List<String> _quickTags = [
    '📦 สภาพสินค้าดีเยี่ยม',
    '⏰ ส่งมอบตรงเวลา',
    '💬 ตอบแชตไว สื่อสารดี',
    '🤝 เป็นกันเอง ให้คำแนะนำดี',
  ];

  @override
  void initState() {
    super.initState();
    _reviewController = TextEditingController();
    _ownerAvatarUrl = widget.ownerAvatarUrl;
    _loadOwnerAvatar();
  }

  Future<void> _loadOwnerAvatar() async {
    final ownerId = widget.ownerId;
    if (_ownerAvatarUrl?.isNotEmpty == true ||
        ownerId == null ||
        ownerId.isEmpty) {
      return;
    }
    try {
      final profile =
          await (widget.profileSource ?? ProfileStorefrontRemoteDataSource())
              .getIdentity(ownerId);
      if (!mounted) return;
      setState(() => _ownerAvatarUrl = profile['user_image_url'] as String?);
    } catch (_) {
      // อ่านรูปไม่สำเร็จยังต้องรีวิวต่อได้โดยใช้รูปสำรอง
    }
  }

  @override
  void dispose() {
    _reviewController.dispose();
    super.dispose();
  }

  String _getSentimentLabel(int rating) {
    switch (rating) {
      case 5:
        return 'เป็นประสบการณ์ยอดเยี่ยมที่สุด ✨';
      case 4:
        return 'เป็นประสบการณ์ที่ดีมาก ประทับใจ 😊';
      case 3:
        return 'เป็นประสบการณ์พอใช้ได้ ปานกลาง 🙂';
      case 2:
        return 'เป็นประสบการณ์ที่ควรปรับปรุง 😕';
      case 1:
        return 'เป็นประสบการณ์ที่ไม่น่าประทับใจ 😞';
      default:
        return 'แตะดาวเพื่อให้คะแนน';
    }
  }

  void _onTagToggled(String tag) {
    setState(() {
      if (_selectedTags.contains(tag)) {
        _selectedTags.remove(tag);
      } else {
        _selectedTags.add(tag);
      }
    });
  }

  Future<void> _handleSubmitReview() async {
    FocusScope.of(context).unfocus();

    final client = SupabaseConfig.isInitialized ? SupabaseConfig.client : null;
    final itemId = widget.itemId;
    final userId = client?.auth.currentUser?.id;
    if (client == null ||
        itemId == null ||
        itemId <= 0 ||
        userId == null ||
        userId.isEmpty) {
      showAppPopup(
        context,
        content: Text(
          'ไม่พบข้อมูลการเช่าหรือบัญชีผู้ใช้ กรุณาเปิดรีวิวจากรายการเช่า',
        ),
      );
      return;
    }

    final comment = _reviewController.text.trim();
    final tags = _selectedTags.toList(growable: false);
    final description = [
      if (comment.isNotEmpty) comment,
      if (tags.isNotEmpty) 'จุดที่ประทับใจ: ${tags.join(', ')}',
    ].join('\n');

    setState(() => _isSubmitting = true);
    try {
      await client.from('review_tb').insert({
        'user_id': userId,
        'item_id': itemId,
        'rating': _selectedRating.toString(),
        'description': description.isEmpty ? null : description,
      });

      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => _buildSuccessModal(context),
      );
    } catch (error) {
      debugPrint('Failed to submit rental review: $error');
      if (!mounted) return;
      showAppPopup(
        context,
        content: Text('ส่งรีวิวไม่สำเร็จ กรุณาลองอีกครั้ง'),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFFCFF),
        elevation: 0,
        centerTitle: false,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 24),
          tooltip: 'ย้อนกลับ',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text(
          'รีวิว',
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            color: Color(0xFF24212A),
            fontSize: 20,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.3,
          ),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.primaryColor.withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(17),
                ),
                child: const Icon(
                  Icons.rate_review_rounded,
                  color: AppColors.primaryColor,
                  size: 27,
                ),
              ),
              const SizedBox(height: 16),

              // ── 1. Headline & Description ──
              const Text(
                'ประสบการณ์การเช่า\nของคุณเป็นอย่างไร',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 25,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF25212B),
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'แบ่งปันประสบการณ์จริงของคุณ เพื่อช่วยให้\nผู้เช่าคนต่อไปตัดสินใจได้ง่ายขึ้น',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 14,
                  fontWeight: FontWeight.normal,
                  color: Color(0xFF595C5D),
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 24),

              // ── 2. Rental Item & Owner Card ──
              _buildItemAndOwnerCard(),

              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(0xFFEDE7F2)),
                ),
                child: Column(
                  children: [
                    const Text(
                      'ให้คะแนนผู้ปล่อยเช่า',
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF34303A),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _buildInteractiveStars(),
                    const SizedBox(height: 8),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: Text(
                        _getSentimentLabel(_selectedRating),
                        key: ValueKey<int>(_selectedRating),
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: _selectedRating == 0
                              ? const Color(0xFF89838F)
                              : AppColors.primaryColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 22),

              // ── 4. Quick Impression Tag Chips ──
              _buildTagChipsSection(),

              const SizedBox(height: 24),

              // ── 5. Review Detail Text Input ──
              _buildReviewInputSection(),

              const SizedBox(height: 32),

              // ── 6. Submit Button ──
              _buildSubmitButton(),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildItemImageFallback() => const Center(
    child: Icon(Icons.camera_alt_rounded, color: Color(0xFF8C9098), size: 36),
  );

  /// การ์ดข้อมูลสินค้าและผู้ปล่อยเช่า สไตล์โมเดิร์น
  Widget _buildItemAndOwnerCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFEFF0F3), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          // รูปสินค้า
          Container(
            width: 86,
            height: 86,
            decoration: BoxDecoration(
              color: const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE9EAEF)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                widget.itemImageUrl?.isNotEmpty == true
                    ? Image.network(
                        widget.itemImageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => _buildItemImageFallback(),
                      )
                    : _buildItemImageFallback(),
              ],
            ),
          ),
          const SizedBox(width: 16),

          // รายละเอียดสินค้า & ผู้ให้เช่า
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.itemName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF1E2022),
                  ),
                ),
                if (widget.itemSubtitle.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    widget.itemSubtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 12,
                      color: Color(0xFF77717D),
                    ),
                  ),
                ],
                const SizedBox(height: 8),

                // ผู้ปล่อยเช่า row
                Row(
                  children: [
                    // Jessica Avatar with status dot
                    Stack(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.primaryColor.withValues(
                                alpha: 0.2,
                              ),
                              width: 1.5,
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: _ownerAvatarUrl?.isNotEmpty == true
                              ? Image.network(
                                  _ownerAvatarUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => Image.asset(
                                    'assets/images/user.png',
                                    fit: BoxFit.cover,
                                  ),
                                )
                              : Image.asset(
                                  'assets/images/user.png',
                                  fit: BoxFit.cover,
                                ),
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: const Color(0xFF9D44ED),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white,
                                width: 1.5,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        widget.ownerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF333638),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primaryColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'ผู้ปล่อยเช่า',
                        style: TextStyle(
                          fontFamily: AppTextStyles.fontFamily,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primaryColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// ดาว 5 ดวงแบบ Interactive และขยับได้เมื่อกด
  Widget _buildInteractiveStars() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(5, (index) {
        final starValue = index + 1;
        final isSelected = starValue <= _selectedRating;

        return GestureDetector(
          onTap: () {
            setState(() {
              _selectedRating = starValue;
            });
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: AnimatedScale(
              scale: isSelected ? 1.05 : 0.95,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutBack,
              child: Icon(
                Icons.star_rounded,
                size: 46,
                color: isSelected
                    ? AppColors.primaryColor
                    : const Color(0xFFE2E4E9),
              ),
            ),
          ),
        );
      }),
    );
  }

  /// แท็กความประทับใจด่วน จัดรูปแบบ 2 คอลัมน์ กึ่งกลางสวยงาม
  Widget _buildTagChipsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'จุดเด่นที่คุณประทับใจ',
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1E2022),
              ),
            ),
            Text(
              'เลือกได้หลายข้อ',
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 12,
                color: Colors.grey.shade500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Column(
          children: [
            Row(
              children: [
                Expanded(child: _buildTagItem(_quickTags[0])),
                const SizedBox(width: 10),
                Expanded(child: _buildTagItem(_quickTags[1])),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _buildTagItem(_quickTags[2])),
                const SizedBox(width: 10),
                Expanded(child: _buildTagItem(_quickTags[3])),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTagItem(String tag) {
    final isSelected = _selectedTags.contains(tag);
    return InkWell(
      onTap: () => _onTagToggled(tag),
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primaryColor.withValues(alpha: 0.08)
              : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? AppColors.primaryColor
                : const Color(0xFFE2E4E9),
            width: isSelected ? 1.5 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primaryColor.withValues(alpha: 0.12),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.02),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        alignment: Alignment.center,
        child: Text(
          tag,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 12.5,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            color: isSelected
                ? AppColors.primaryColor
                : const Color(0xFF4A4D4F),
          ),
        ),
      ),
    );
  }

  /// ส่วนกล่องกรอกข้อความรีวิว
  Widget _buildReviewInputSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'รายละเอียดการรีวิว',
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1E2022),
              ),
            ),
            AnimatedBuilder(
              animation: _reviewController,
              builder: (context, _) {
                return Text(
                  '${_reviewController.text.length}/500',
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 13,
                    color: Color(0xFF8A8E94),
                  ),
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE8E2ED)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: TextField(
            controller: _reviewController,
            maxLength: 500,
            maxLines: 5,
            minLines: 4,
            style: const TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 15,
              color: Color(0xFF1E2022),
              height: 1.45,
            ),
            decoration: const InputDecoration(
              hintText:
                  'บอกเล่าประสบการณ์การใช้งาน ข้อดี หรือสิ่งที่ประทับใจ...',
              hintStyle: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 14,
                color: Color(0xFF9EA2A8),
              ),
              border: InputBorder.none,
              isDense: true,
              counterText: '',
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
      ],
    );
  }

  /// ปุ่ม "ให้คะแนน" สไตล์พรีเมียมแคปซูล
  Widget _buildSubmitButton() {
    final canSubmit = _selectedRating > 0 && !_isSubmitting;
    return Container(
      width: double.infinity,
      height: 54,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        color: canSubmit ? null : const Color(0xFFE7E3EA),
        gradient: canSubmit
            ? const LinearGradient(
                colors: [Color(0xFF7400C9), Color(0xFF8F19E8)],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              )
            : null,
        boxShadow: canSubmit
            ? [
                BoxShadow(
                  color: AppColors.primaryColor.withValues(alpha: 0.22),
                  blurRadius: 14,
                  offset: const Offset(0, 5),
                ),
              ]
            : const [],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: canSubmit ? _handleSubmitReview : null,
          child: Center(
            child: _isSubmitting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    'ส่งรีวิว',
                    style: TextStyle(
                      fontFamily: AppTextStyles.fontFamily,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: canSubmit ? Colors.white : const Color(0xFF8E8993),
                      letterSpacing: 0.3,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  /// หน้าต่างยืนยันเมื่อบันทึกรีวิวสำเร็จ
  Widget _buildSuccessModal(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 44,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),

          // Icon สำเร็จ
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.primaryColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle_rounded,
              color: AppColors.primaryColor,
              size: 44,
            ),
          ),
          const SizedBox(height: 16),

          const Text(
            'ส่งรีวิวสำเร็จ',
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E2022),
            ),
          ),
          const SizedBox(height: 8),

          Text(
            'ขอบคุณที่ร่วมแชร์ประสบการณ์การเช่า\nเพื่อสร้างคอมมูนิตี้ที่ดีใน Yuemnoi',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: AppTextStyles.fontFamily,
              fontSize: 14,
              color: Colors.grey.shade600,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),

          // สรุปคะแนนที่ให้
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F8FA),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'คะแนนที่คุณเลือก:',
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 14,
                    color: Color(0xFF4A4D4F),
                  ),
                ),
                const SizedBox(width: 8),
                Row(
                  children: List.generate(
                    _selectedRating,
                    (_) => const Icon(
                      Icons.star_rounded,
                      color: AppColors.primaryColor,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
                elevation: 0,
              ),
              onPressed: () {
                Navigator.of(context).pop();
                AppRoutes.goToHome(this.context);
              },
              child: const Text(
                'ตกลง',
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
