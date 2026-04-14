import 'package:flutter/material.dart';

class V3ShimmerBanner extends StatefulWidget {
  const V3ShimmerBanner({
    super.key,
    required this.child,
    this.margin,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    this.borderRadius = 12,
    this.backgroundColor,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final Color? backgroundColor;
  final Color? borderColor;

  @override
  State<V3ShimmerBanner> createState() => _V3ShimmerBannerState();
}

class _V3ShimmerBannerState extends State<V3ShimmerBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(widget.borderRadius);
    final bgColor =
        widget.backgroundColor ?? Colors.red.withValues(alpha: 0.22);
    final borderColor =
        widget.borderColor ?? Colors.redAccent.withValues(alpha: 0.8);

    return Container(
      width: double.infinity,
      margin: widget.margin,
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: borderRadius,
        border: Border.all(color: borderColor),
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Stack(
          children: [
            Padding(
              padding: widget.padding,
              child: MediaQuery.withNoTextScaling(
                child: widget.child,
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, _) {
                    final value = _controller.value;
                    final beginX = -1.4 + (2.8 * value);
                    final endX = -0.5 + (2.8 * value);

                    return DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment(beginX, 0),
                          end: Alignment(endX, 0),
                          colors: [
                            Colors.white.withValues(alpha: 0.0),
                            Colors.white.withValues(alpha: 0.26),
                            Colors.white.withValues(alpha: 0.0),
                          ],
                          stops: const [0.0, 0.5, 1.0],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
