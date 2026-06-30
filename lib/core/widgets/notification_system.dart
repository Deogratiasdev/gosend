import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class NotificationOverlay {
  static const Color _accentGreen = Color(0xFF336B4E);
  static const Color _bgDark = Color(0xFF0D0D0D);
  static const Color _textSecondary = Color(0xFFCCCCCC);

  static Future<void> show(
    BuildContext context, {
    required String title,
    required String message,
    NotificationType type = NotificationType.info,
    Duration duration = const Duration(seconds: 4),
  }) async {
    final overlay = Overlay.of(context);
    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (context) => Positioned(
        top: 20,
        right: 20,
        left: 20,
        child: Material(
          color: Colors.transparent,
          child: _NotificationWidget(
            title: title,
            message: message,
            type: type,
            onDismiss: () => entry.remove(),
          ),
        ),
      ),
    );

    overlay.insert(entry);

    await Future.delayed(duration);
    if (entry.mounted) {
      entry.remove();
    }
  }

  static Future<void> success(BuildContext context,
      {required String title, required String message}) {
    return show(
      context,
      title: title,
      message: message,
      type: NotificationType.success,
    );
  }

  static Future<void> error(BuildContext context,
      {required String title, required String message}) {
    return show(
      context,
      title: title,
      message: message,
      type: NotificationType.error,
      duration: const Duration(seconds: 5),
    );
  }

  static Future<void> warning(BuildContext context,
      {required String title, required String message}) {
    return show(
      context,
      title: title,
      message: message,
      type: NotificationType.warning,
    );
  }

  static Future<void> info(BuildContext context,
      {required String title, required String message}) {
    return show(
      context,
      title: title,
      message: message,
      type: NotificationType.info,
    );
  }
}

enum NotificationType { success, error, warning, info }

class _NotificationWidget extends StatefulWidget {
  final String title;
  final String message;
  final NotificationType type;
  final VoidCallback onDismiss;

  const _NotificationWidget({
    required this.title,
    required this.message,
    required this.type,
    required this.onDismiss,
  });

  @override
  State<_NotificationWidget> createState() => __NotificationWidgetState();
}

class __NotificationWidgetState extends State<_NotificationWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slideAnimation = Tween<Offset>(
      begin: const Offset(1, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color _getColor() {
    switch (widget.type) {
      case NotificationType.success:
        return const Color(0xFF336B4E);
      case NotificationType.error:
        return Colors.redAccent;
      case NotificationType.warning:
        return Colors.orangeAccent;
      case NotificationType.info:
        return Colors.blueAccent;
    }
  }

  IconData _getIcon() {
    switch (widget.type) {
      case NotificationType.success:
        return Icons.check_circle_rounded;
      case NotificationType.error:
        return Icons.error_rounded;
      case NotificationType.warning:
        return Icons.warning_rounded;
      case NotificationType.info:
        return Icons.info_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _getColor();

    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _animation,
        child: GestureDetector(
          onTap: widget.onDismiss,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF0D0D0D),
              border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.2),
                  blurRadius: 12,
                  spreadRadius: 0,
                )
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _getIcon(),
                  color: color,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.title,
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.message,
                        style: GoogleFonts.inter(
                          color: const Color(0xFFCCCCCC),
                          fontSize: 13,
                          fontWeight: FontWeight.w400,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: widget.onDismiss,
                  child: Icon(
                    Icons.close_rounded,
                    color: color.withValues(alpha: 0.5),
                    size: 20,
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
