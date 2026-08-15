import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/constants/colors.dart';
import '../../../../core/navigation/app_routes.dart';
import '../../data/datasources/call_remote_data_source.dart';
import '../../data/datasources/chat_remote_data_source.dart';
import '../../data/repositories/chat_repository_impl.dart';
import '../../data/services/call_audio_service.dart';
import '../../domain/entities/chat_conversation.dart';
import '../../domain/usecases/send_chat_message_usecase.dart';
import '../bloc/call_bloc.dart';
import '../bloc/call_event.dart';
import '../bloc/call_state.dart';
import '../widgets/chat_avatar.dart';

class VoiceCallScreen extends StatelessWidget {
  const VoiceCallScreen({
    super.key,
    required this.conversation,
    this.isCaller = true,
    this.sessionId,
    this.callBloc,
  });

  final ChatConversation conversation;
  final bool isCaller;
  final String? sessionId;
  final CallBloc? callBloc;

  @override
  Widget build(BuildContext context) {
    if (callBloc != null) {
      return BlocProvider.value(
        value: callBloc!,
        child: _VoiceCallView(conversation: conversation),
      );
    }

    final repository = ChatRepositoryImpl(
      remoteDataSource: ChatRemoteDataSource(),
    );

    return BlocProvider(
      create: (context) => CallBloc(
        sendMessage: SendChatMessageUseCase(repository),
        callRemoteDataSource: CallRemoteDataSource(),
        audioService: CallAudioService(),
      )..add(CallStarted(
          conversation: conversation,
          isCaller: isCaller,
          sessionId: sessionId,
        )),
      child: _VoiceCallView(conversation: conversation),
    );
  }
}

class _VoiceCallView extends StatefulWidget {
  const _VoiceCallView({required this.conversation});

  final ChatConversation conversation;

  @override
  State<_VoiceCallView> createState() => _VoiceCallViewState();
}

class _VoiceCallViewState extends State<_VoiceCallView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<CallBloc, CallState>(
      listener: (context, state) {
        if (state.status == CallStatus.ended) {
          Future.delayed(const Duration(milliseconds: 600), () {
            if (context.mounted) {
              AppRoutes.pop(context);
            }
          });
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF13111C),
        body: SafeArea(
          child: Stack(
            children: [
              // Background Gradient Glow
              Positioned(
                top: -80,
                right: -80,
                child: Container(
                  width: 260,
                  height: 260,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primaryColor.withValues(alpha: 0.18),
                  ),
                ),
              ),

              // Main Call Content
              LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: constraints.maxHeight),
                      child: IntrinsicHeight(
                        child: Column(
                          children: [
                            const SizedBox(height: 12),
                            _buildTopBar(context),
                            const Spacer(),
                            _buildCallerInfo(context),
                            const Spacer(),
                            _buildControlPanel(context),
                            const SizedBox(height: 28),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            tooltip: 'ย้อนกลับ',
            onPressed: () {
              context.read<CallBloc>().add(const CallEndedEvent());
            },
            icon: const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: Colors.white70,
              size: 34,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline_rounded, color: Colors.white70, size: 14),
                SizedBox(width: 4),
                Text(
                  'โทรผ่านแอป ปลอดภัย',
                  style: TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildCallerInfo(BuildContext context) {
    return BlocBuilder<CallBloc, CallState>(
      builder: (context, state) {
        final isConnected = state.status == CallStatus.connected;

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Avatar with animated pulse
            AnimatedBuilder(
              animation: _pulseAnimation,
              builder: (context, child) {
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 130 * _pulseAnimation.value,
                      height: 130 * _pulseAnimation.value,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: AppColors.primaryColor.withValues(
                          alpha: isConnected ? 0.12 : 0.22,
                        ),
                      ),
                    ),
                    ChatAvatar(
                      asset: widget.conversation.avatarAsset,
                      size: 100,
                      isOnline: true,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),
            Text(
              widget.conversation.name,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.conversation.role == ChatParticipantRole.owner
                  ? 'ผู้ปล่อยเช่า'
                  : 'ผู้เช่า',
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (widget.conversation.itemName != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  widget.conversation.itemName!,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            // Call Status / Duration Timer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: isConnected
                    ? const Color(0xFF10B981).withValues(alpha: 0.18)
                    : Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isConnected) ...[
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFF10B981),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    state.statusLabel,
                    key: const ValueKey('call-status-label'),
                    style: TextStyle(
                      color: isConnected ? const Color(0xFF10B981) : Colors.white70,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildControlPanel(BuildContext context) {
    return BlocBuilder<CallBloc, CallState>(
      builder: (context, state) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Controls: Mute and Speaker (No message button)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _CallActionButton(
                    key: const ValueKey('call-mute-button'),
                    icon: state.isMuted
                        ? Icons.mic_off_rounded
                        : Icons.mic_rounded,
                    label: state.isMuted ? 'เปิดไมค์' : 'ปิดไมค์',
                    isActive: state.isMuted,
                    onTap: () =>
                        context.read<CallBloc>().add(const CallMuteToggled()),
                  ),
                  _CallActionButton(
                    key: const ValueKey('call-speaker-button'),
                    icon: state.isSpeakerOn
                        ? Icons.volume_up_rounded
                        : Icons.volume_down_rounded,
                    label: state.isSpeakerOn ? 'หูฟัง' : 'ลำโพง',
                    isActive: state.isSpeakerOn,
                    onTap: () => context
                        .read<CallBloc>()
                        .add(const CallSpeakerToggled()),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),

            // Big Red End Call Button
            SizedBox(
              width: 68,
              height: 68,
              child: IconButton.filled(
                key: const ValueKey('end-call-button'),
                tooltip: 'วางสาย',
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFFEF4444),
                  foregroundColor: Colors.white,
                  elevation: 6,
                  shadowColor: const Color(0xFFEF4444).withValues(alpha: 0.5),
                ),
                onPressed: () {
                  context.read<CallBloc>().add(const CallEndedEvent());
                },
                icon: const Icon(Icons.call_end_rounded, size: 34),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CallActionButton extends StatelessWidget {
  const _CallActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isActive
                    ? Colors.white
                    : Colors.white.withValues(alpha: 0.12),
              ),
              child: Icon(
                icon,
                color: isActive ? const Color(0xFF13111C) : Colors.white,
                size: 28,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
