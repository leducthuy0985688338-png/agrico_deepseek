import 'package:flutter/material.dart';

class AnimatedCard extends StatelessWidget {
  final Widget child;
  final double? elevation;
  final EdgeInsets? padding;
  final VoidCallback? onTap;
  final Duration animationDuration;

  const AnimatedCard({
    super.key,
    required this.child,
    this.elevation,
    this.padding,
    this.onTap,
    this.animationDuration = const Duration(milliseconds: 300),
  });

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder(
      duration: animationDuration,
      tween: Tween<double>(begin: 0, end: 1),
      builder: (context, value, child) {
        return Transform.scale(
          scale: 0.95 + (0.05 * value),
          child: Opacity(
            opacity: value,
            child: Card(
              elevation: elevation ?? 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: padding ?? const EdgeInsets.all(16),
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
      child: child,
    );
  }
}
