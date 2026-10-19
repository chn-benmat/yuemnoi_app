import 'package:flutter/material.dart';

class ChatSkeletonLoadingView extends StatefulWidget {
  const ChatSkeletonLoadingView({super.key});

  @override
  State<ChatSkeletonLoadingView> createState() =>
      _ChatSkeletonLoadingViewState();
}

class _ChatSkeletonLoadingViewState extends State<ChatSkeletonLoadingView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: const Alignment(-1.0, -0.3),
              end: const Alignment(1.0, 0.3),
              colors: const [
                Color(0xFFE2E4E8),
                Color(0xFFF7F8FA),
                Color(0xFFE2E4E8),
              ],
              stops: const [0.1, 0.5, 0.9],
              transform: SlidingGradientTransform(
                slidePercent: _controller.value,
              ),
            ).createShader(bounds);
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
            child: ListView(
              physics: const NeverScrollableScrollPhysics(),
              children: [
                // Centered date divider skeleton
                Center(
                  child: Container(
                    width: 70,
                    height: 14,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(7),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Incoming bubble 1
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 170,
                      height: 42,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(18),
                          topRight: Radius.circular(18),
                          bottomLeft: Radius.circular(4),
                          bottomRight: Radius.circular(18),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // Incoming bubble 2 (shorter)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const SizedBox(width: 36),
                    Container(
                      width: 110,
                      height: 38,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(18),
                          topRight: Radius.circular(18),
                          bottomLeft: Radius.circular(4),
                          bottomRight: Radius.circular(18),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Outgoing bubble 1 (right)
                Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    width: 210,
                    height: 48,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(18),
                        topRight: Radius.circular(18),
                        bottomLeft: Radius.circular(18),
                        bottomRight: Radius.circular(4),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // Outgoing bubble 2 (right shorter)
                Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    width: 130,
                    height: 38,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(18),
                        topRight: Radius.circular(18),
                        bottomLeft: Radius.circular(18),
                        bottomRight: Radius.circular(4),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Incoming bubble 3
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 190,
                      height: 52,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(18),
                          topRight: Radius.circular(18),
                          bottomLeft: Radius.circular(4),
                          bottomRight: Radius.circular(18),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Outgoing image skeleton (right)
                Align(
                  alignment: Alignment.centerRight,
                  child: Container(
                    width: 180,
                    height: 120,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class SlidingGradientTransform extends GradientTransform {
  const SlidingGradientTransform({required this.slidePercent});

  final double slidePercent;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(
      bounds.width * (slidePercent * 2 - 1),
      0.0,
      0.0,
    );
  }
}
