import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class GradientButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final IconData? icon;
  final bool isLoading;
  final bool fullWidth;
  final Gradient? gradient;

  const GradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.isLoading = false,
    this.fullWidth = true,
    this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: fullWidth ? double.infinity : null,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 4,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          shadowColor: AppTheme.primaryColor.withOpacity(0.3),
        ),
        child: Ink(
          decoration: BoxDecoration(
            gradient: gradient ?? AppTheme.primaryGradient,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
            child: isLoading
                ? const SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon != null) ...[
                        Icon(icon, size: 20),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        label,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}
