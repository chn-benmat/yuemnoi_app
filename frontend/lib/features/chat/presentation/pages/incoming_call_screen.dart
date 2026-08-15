import 'package:flutter/material.dart';
import '../../../../core/constants/colors.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../data/datasources/call_remote_data_source.dart';
import '../../data/services/call_audio_service.dart';
import '../../domain/entities/chat_conversation.dart';
import '../widgets/chat_avatar.dart';

class IncomingCallScreen extends StatefulWidget {
  const IncomingCallScreen({
    super.key,
    required this.conversation,
    required this.sessionId,
    this.audioService,
    this.callRemoteDataSource,
  });

  final ChatConversation conversation;
  final String sessionId;
  final CallAudioService? audioService;
  final CallRemoteDataSource? callRemoteDataSource;

  @override
  State<IncomingCallScreen> createState() => _IncomingCallScreenState();
}

class _IncomingCallScreenState extends State<IncomingCallScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;
  late final CallAudioService _audioService;
  late final CallRemoteDataSource _callRemoteDataSource;

  @override
  void initState() {
    super.initState();
    _audioService = widget.audioService ?? CallAudioService();
    _callRemoteDataSource = widget.callRemoteDataSource ?? CallRemoteDataSource();

    // เล่นเสียงเรียกเข้า
    _audioService.playRingtone();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _audioService.stopAll();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _declineCall() async {
    _audioService.stopAll();
    await _callRemoteDataSource.updateCallStatus(
      sessionId: widget.sessionId,
      status: 'rejected',
    );
    if (mounted) {
      AppRoutes.pop(context);
    }
  }

  Future<void> _acceptCall() async {
    _audioService.stopAll();
    await _callRemoteDataSource.updateCallStatus(
      sessionId: widget.sessionId,
      status: 'accepted',
    );
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (context) => AppRoutes.createRouter().configuration.routes.isEmpty
              ? const SizedBox.shrink()
              : const SizedBox.shrink(),
        ),
      );
      AppRoutes.openVoiceCall(
        context,
        conversation: widget.conversation,
        isCaller: false,
        sessionId: widget.sessionId,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF110E1B),
      body: SafeArea(
        child: Stack(
          children: [
            // Background Glow
            Positioned(
              top: -60,
              left: -60,
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primaryColor.withValues(alpha: 0.18),
                ),
              ),
            ),

            Column(
              children: [
                const SizedBox(height: 32),
                // Header Label
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.phone_in_talk_rounded, color: AppColors.primaryColor, size: 16),
                      SizedBox(width: 8),
                      Text(
                        'สายเรียกเข้า (โทรด้วยเสียงในแอป)',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(flex: 2),

                // Caller Avatar with pulsating glow
                AnimatedBuilder(
                  animation: _pulseAnimation,
                  builder: (context, child) {
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 140 * _pulseAnimation.value,
                          height: 140 * _pulseAnimation.value,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xFF10B981).withValues(alpha: 0.18),
                          ),
                        ),
                        ChatAvatar(
                          asset: widget.conversation.avatarAsset,
                          size: 110,
                          isOnline: true,
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 24),

                // Caller Name & Role
                Text(
                  widget.conversation.name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  widget.conversation.role == ChatParticipantRole.owner
                      ? 'ผู้ปล่อยเช่า'
                      : 'ผู้เช่า',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
                if (widget.conversation.itemName != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      widget.conversation.itemName!,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],

                const Spacer(flex: 3),

                // Call Action Buttons (Left: Decline 🔴, Right: Accept 🟢)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 48),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // ปุ่มปฏิเสธ (Decline - ฝั่งซ้าย)
                      _IncomingActionButton(
                        key: const ValueKey('incoming-decline-button'),
                        icon: Icons.call_end_rounded,
                        label: 'ปฏิเสธ',
                        color: const Color(0xFFEF4444),
                        onTap: _declineCall,
                      ),

                      // ปุ่มรับสาย (Accept - ฝั่งขวา)
                      _IncomingActionButton(
                        key: const ValueKey('incoming-accept-button'),
                        icon: Icons.call_rounded,
                        label: 'รับสาย',
                        color: const Color(0xFF10B981),
                        onTap: _acceptCall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 48),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _IncomingActionButton extends StatelessWidget {
  const _IncomingActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.4),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 36),
          ),
          const SizedBox(height: 12),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
