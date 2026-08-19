import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/services/media_download_service.dart';
import '../../domain/entities/item_detail.dart';

/// หน้าต่างแชร์สินค้า (Share Bottom Sheet) สไตล์ Shopee
class ItemShareBottomSheet extends StatelessWidget {
  const ItemShareBottomSheet({
    super.key,
    required this.item,
  });

  final ItemDetail item;

  static Future<void> show(
    BuildContext context, {
    required ItemDetail item,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalContext) => ItemShareBottomSheet(item: item),
    );
  }

  String get _shareUrl => 'https://yuemnoi.app/items/${item.id}';

  void _copyLink(BuildContext context) {
    Clipboard.setData(ClipboardData(text: _shareUrl));
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('คัดลอกลิงก์อุปกรณ์แล้ว'),
          duration: Duration(seconds: 2),
        ),
      );
  }

  Future<void> _saveImages(BuildContext context) async {
    Navigator.of(context).pop();
    if (item.imageUrls.isEmpty) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('ไม่มีรูปภาพสำหรับบันทึก'),
            duration: Duration(seconds: 2),
          ),
        );
      return;
    }

    final count = await MediaDownloadService.instance
        .saveMultipleImagesFromUrls(item.imageUrls);

    if (context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              count > 1
                  ? 'บันทึก $count รูปภาพลงในแกลเลอรีเรียบร้อยแล้ว'
                  : count == 1
                      ? 'บันทึกรูปภาพลงในแกลเลอรีเรียบร้อยแล้ว'
                      : 'บันทึกรูปภาพไม่สำเร็จ กรุณาอนุญาตการเข้าถึงรูปภาพ',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
    }
  }

  void _shareToSocial(BuildContext context, String platformName) {
    Clipboard.setData(
      ClipboardData(
        text: 'ดูอุปกรณ์ ${item.name} ราคา ฿${item.price}/${item.unitLabel} ได้ที่: $_shareUrl',
      ),
    );
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('คัดลอกลิงก์พร้อมแชร์ไปยัง $platformName แล้ว'),
          duration: const Duration(seconds: 2),
        ),
      );
  }

  void _openMoreOptions(BuildContext context) {
    Navigator.of(context).pop();
    final desc = item.description.isNotEmpty ? ' ${item.description}' : '';
    final shareText =
        'ลองเข้ามาดูสินค้า ${item.name}$desc ราคา ฿${item.price}/${item.unitLabel} ดูรายละเอียดได้ที่: $_shareUrl';
    SharePlus.instance.share(
      ShareParams(
        text: shareText,
        subject: item.name,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ─── Header ────────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 10),
              child: Row(
                children: [
                  const Spacer(),
                  const Text(
                    'แชร์สินค้า',
                    style: TextStyle(
                      color: Color(0xFF1E293B),
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Color(0xFF475569),
                      size: 22,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // ─── Affiliate / Promo Banner ──────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () {
                  ScaffoldMessenger.of(context)
                    ..hideCurrentSnackBar()
                    ..showSnackBar(
                      const SnackBar(
                        content: Text('โปรแกรม Yuemnoi Affiliate กำลังจะเปิดให้บริการเร็วๆ นี้'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF9E6),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFFE8B2), width: 0.8),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 26,
                        height: 26,
                        decoration: const BoxDecoration(
                          color: Color(0xFFF97316),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.campaign_rounded,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'เข้าร่วม Yuemnoi Affiliate เพื่อสร้างรายได้จากการโปรโมตสินค้า!',
                          style: TextStyle(
                            color: Color(0xFF1E293B),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: Color(0xFF94A3B8),
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 18),

            // ─── 1st Row: Social Channels ──────────────────────────────────────
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SocialShareItem(
                    icon: _buildLineIcon(),
                    label: 'Line',
                    onTap: () => _shareToSocial(context, 'Line'),
                  ),
                  _SocialShareItem(
                    icon: _buildMessengerIcon(),
                    label: 'Messenger',
                    onTap: () => _shareToSocial(context, 'Messenger'),
                  ),
                  _SocialShareItem(
                    icon: _buildWhatsAppIcon(),
                    label: 'WhatsApp',
                    onTap: () => _shareToSocial(context, 'WhatsApp'),
                  ),
                  _SocialShareItem(
                    icon: _buildFacebookIcon(),
                    label: 'Facebook',
                    onTap: () => _shareToSocial(context, 'Facebook'),
                  ),
                  _SocialShareItem(
                    icon: _buildInstagramFeedIcon(),
                    label: 'Feed',
                    onTap: () => _shareToSocial(context, 'Instagram Feed'),
                  ),
                  _SocialShareItem(
                    icon: _buildInstagramStoryIcon(),
                    label: 'Story',
                    onTap: () => _shareToSocial(context, 'Instagram Story'),
                  ),
                  _SocialShareItem(
                    icon: _buildTelegramIcon(),
                    label: 'Telegram',
                    onTap: () => _shareToSocial(context, 'Telegram'),
                  ),
                  _SocialShareItem(
                    icon: _buildXIcon(),
                    label: 'X',
                    onTap: () => _shareToSocial(context, 'X (Twitter)'),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ─── 2nd Row: Action / Utilities ───────────────────────────────────
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ActionShareItem(
                    icon: Icons.link_rounded,
                    label: 'คัดลอกลิงก์',
                    onTap: () => _copyLink(context),
                  ),
                  _ActionShareItem(
                    icon: Icons.download_rounded,
                    label: 'บันทึกรูปภาพ',
                    onTap: () => _saveImages(context),
                  ),
                  _ActionShareItem(
                    icon: Icons.more_horiz_rounded,
                    label: 'อื่น ๆ',
                    onTap: () => _openMoreOptions(context),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 22),
          ],
        ),
      ),
    );
  }

  // ─── Social Media Icon Builders ─────────────────────────────────────────────

  static Widget _buildLineIcon() {
    return Container(
      width: 54,
      height: 54,
      decoration: const BoxDecoration(
        color: Color(0xFF06C755),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2.5),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Text(
            'LINE',
            style: TextStyle(
              color: Color(0xFF06C755),
              fontSize: 9.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }

  static Widget _buildMessengerIcon() {
    return Container(
      width: 54,
      height: 54,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF00C6FF), Color(0xFF0078FF)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        shape: BoxShape.circle,
      ),
      child: const Center(
        child: Icon(
          Icons.bolt_rounded,
          color: Colors.white,
          size: 30,
        ),
      ),
    );
  }

  static Widget _buildWhatsAppIcon() {
    return Container(
      width: 54,
      height: 54,
      decoration: const BoxDecoration(
        color: Color(0xFF25D366),
        shape: BoxShape.circle,
      ),
      child: const Center(
        child: Icon(
          Icons.call_rounded,
          color: Colors.white,
          size: 28,
        ),
      ),
    );
  }

  static Widget _buildFacebookIcon() {
    return Container(
      width: 54,
      height: 54,
      decoration: const BoxDecoration(
        color: Color(0xFF1877F2),
        shape: BoxShape.circle,
      ),
      alignment: const Alignment(0.15, 0.45),
      child: const Text(
        'f',
        style: TextStyle(
          color: Colors.white,
          fontSize: 34,
          fontWeight: FontWeight.w900,
          fontFamily: 'sans-serif',
          height: 1.0,
        ),
      ),
    );
  }

  static Widget _buildInstagramFeedIcon() {
    return Container(
      width: 54,
      height: 54,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFF833AB4),
            Color(0xFFFD1D1D),
            Color(0xFFFCB045),
          ],
          begin: Alignment.bottomLeft,
          end: Alignment.topRight,
        ),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white, width: 2.4),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 2),
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    );
  }

  static Widget _buildInstagramStoryIcon() {
    return Container(
      width: 54,
      height: 54,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Color(0xFF833AB4),
            Color(0xFFFD1D1D),
            Color(0xFFFCB045),
          ],
          begin: Alignment.bottomLeft,
          end: Alignment.topRight,
        ),
        shape: BoxShape.circle,
      ),
      child: const Center(
        child: Icon(
          Icons.camera_alt_outlined,
          color: Colors.white,
          size: 27,
        ),
      ),
    );
  }

  static Widget _buildTelegramIcon() {
    return Container(
      width: 54,
      height: 54,
      decoration: const BoxDecoration(
        color: Color(0xFF229ED9),
        shape: BoxShape.circle,
      ),
      child: const Center(
        child: Padding(
          padding: EdgeInsets.only(right: 3, top: 1),
          child: Icon(
            Icons.send_rounded,
            color: Colors.white,
            size: 24,
          ),
        ),
      ),
    );
  }

  static Widget _buildXIcon() {
    return Container(
      width: 54,
      height: 54,
      decoration: const BoxDecoration(
        color: Color(0xFF0F1419),
        shape: BoxShape.circle,
      ),
      child: const Center(
        child: Text(
          '𝕏',
          style: TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _SocialShareItem extends StatelessWidget {
  const _SocialShareItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final Widget icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 76,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Column(
          children: [
            icon,
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF334155),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionShareItem extends StatelessWidget {
  const _ActionShareItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 76,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Column(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
              ),
              child: Center(
                child: Icon(
                  icon,
                  color: const Color(0xFF334155),
                  size: 26,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF475569),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
