import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class ToastService {
  static void showSuccess(BuildContext context, String message) {
    _showToast(context, message, AppTheme.successColor, Icons.check_circle);
  }

  static void showError(BuildContext context, String message) {
    _showToast(context, message, AppTheme.errorColor, Icons.error);
  }

  static void showWarning(BuildContext context, String message) {
    _showToast(context, message, AppTheme.warningColor, Icons.warning);
  }

  static void showInfo(BuildContext context, String message) {
    _showToast(context, message, AppTheme.primaryColor, Icons.info);
  }

  static void _showToast(
    BuildContext context,
    String message,
    Color color,
    IconData icon,
  ) {
    final overlay = Overlay.of(context);
    final overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 60,
        left: 16,
        right: 16,
        child: Material(
          color: Colors.transparent,
          child: TweenAnimationBuilder(
            duration: const Duration(milliseconds: 300),
            tween: Tween<double>(begin: -100, end: 0),
            builder: (context, value, child) {
              return Transform.translate(
                offset: Offset(0, value),
                child: Opacity(
                  opacity: value > -50 ? 1 : 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: color.withOpacity(0.3),
                          blurRadius: 16,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Icon(icon, color: Colors.white),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            message,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () => overlayEntry.remove(),
                          child: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );

    overlay.insert(overlayEntry);
    Future.delayed(const Duration(seconds: 3), () {
      if (overlayEntry.mounted) overlayEntry.remove();
    });
  }
}
