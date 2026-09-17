import 'package:flutter/material.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/theme/app_text_styles.dart';

/// หน้าจอ UI สำหรับรีวิวประสบการณ์การเช่าสินค้า (Rental Review Screen)
/// ออกแบบตามแบบและเสริมลูกเล่นระดับ Senior Frontend (Interactive Rating, Quick Tags, Real-time Counter, Success Dialog)
class RentalReviewScreen extends StatefulWidget {
  final String itemName;
  final String itemSubtitle;
  final String ownerName;
  final String? itemImageUrl;
  final String? ownerAvatarUrl;

  const RentalReviewScreen({
    super.key,
    this.itemName = 'Sony Alpha A7 III',
    this.itemSubtitle = 'กล้องดิจิทัล Mirrorless ฟูลเฟรม',
    this.ownerName = 'Jessica',
    this.itemImageUrl,
    this.ownerAvatarUrl,
  });

  @override
  State<RentalReviewScreen> createState() => _RentalReviewScreenState();
}

class _RentalReviewScreenState extends State<RentalReviewScreen> {
  int _selectedRating = 5;
  late final TextEditingController _reviewController;
  final Set<String> _selectedTags = {'📦 สภาพสินค้าดีเยี่ยม'};

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
    // ค่าเริ่มต้นจำลองตามภาพตัวอย่าง
    _reviewController = TextEditingController(text: 'สุดยอดสุดยอดเยี่ยมจริงๆ');
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
        return 'เป็นประสบการณ์';
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

  void _handleSubmitReview() {
    FocusScope.of(context).unfocus();

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _buildSuccessModal(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FA),
      appBar: AppBar(
        backgroundColor: AppColors.primaryColor,
        elevation: 0,
        centerTitle: false,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white, size: 24),
          tooltip: 'ย้อนกลับ',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text(
          'รีวิว',
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            color: Colors.white,
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

              // ── 1. Headline & Description ──
              const Text(
                'ประสบการณ์การเช่า\nของคุณเป็นอย่างไร',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF1E2022),
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'ช่วยให้คำรีวิว และ คะแนนให้กับผู้ปล่อยเช่า\nจากประสบการณ์การเช่าของคุณ',
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

              const SizedBox(height: 28),

              // ── 3. Star Rating Section ──
              const Text(
                'การให้คะแนนของคุณ',
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF4A4D4F),
                ),
              ),
              const SizedBox(height: 14),

              // 5 Stars Row
              _buildInteractiveStars(),

              const SizedBox(height: 10),

              // Sentiment dynamic feedback text
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                transitionBuilder: (child, animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.2),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  );
                },
                child: Text(
                  _getSentimentLabel(_selectedRating),
                  key: ValueKey<int>(_selectedRating),
                  style: const TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryColor,
                  ),
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
                Image.asset(
                  'assets/images/chat_lens_set.png',
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const Center(
                    child: Icon(
                      Icons.camera_alt_rounded,
                      color: Color(0xFF8C9098),
                      size: 36,
                    ),
                  ),
                ),
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
                              color: AppColors.primaryColor.withValues(alpha: 0.2),
                              width: 1.5,
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Image.asset(
                            'assets/images/chat_sarah.png',
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Image.asset(
                              'assets/images/user.png',
                              fit: BoxFit.cover,
                            ),
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
                              border: Border.all(color: Colors.white, width: 1.5),
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
            color: const Color(0xFFEFF1F4),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFE5E7EB)),
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
              hintText: 'บอกเล่าประสบการณ์การใช้งาน ข้อดี หรือสิ่งที่ประทับใจ...',
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
    return Container(
      width: double.infinity,
      height: 54,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(
          colors: [
            Color(0xFF7400C9),
            Color(0xFF8F19E8),
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7400C9).withValues(alpha: 0.32),
            blurRadius: 18,
            offset: const Offset(0, 7),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: _handleSubmitReview,
          child: const Center(
            child: Text(
              'ให้คะแนน',
              style: TextStyle(
                fontFamily: AppTextStyles.fontFamily,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// หน้าต่าง Modal สรุปผลการรีวิวแบบจำลอง
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
            'ส่งรีวิวสำเร็จ! (ตัวอย่าง UI)',
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
                ScaffoldMessenger.of(this.context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'การจำลองให้คะแนนรีวิวเรียบร้อยแล้ว',
                      style: TextStyle(fontFamily: AppTextStyles.fontFamily),
                    ),
                    behavior: SnackBarBehavior.floating,
                    backgroundColor: AppColors.primaryColor,
                  ),
                );
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
