import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:window_manager/window_manager.dart';

class CustomTitleBar extends StatelessWidget {
  final bool isLight;

  const CustomTitleBar({super.key, required this.isLight});

  @override
  Widget build(BuildContext context) {
    final bgColor = isLight ? const Color(0xFFFAF9F7) : const Color(0xFF141414);
    final textColor = isLight
        ? const Color(0xFF1C1C1C)
        : const Color(0xFFF0EFED);
    final iconColor = isLight
        ? const Color(0xFF1C1C1C)
        : const Color(0xFFF0EFED);
    final hoverColor = isLight
        ? const Color(0xFFE8E6E1)
        : const Color(0xFF2C2C2C);
    final closeHover = isLight
        ? const Color(0xFFE81123)
        : const Color(0xFFC42B1C);

    return GestureDetector(
      onPanStart: (_) => windowManager.startDragging(),
      onDoubleTap: () async {
        final isMaximized = await windowManager.isMaximized();
        if (isMaximized) {
          windowManager.unmaximize();
        } else {
          windowManager.maximize();
        }
      },
      child: Container(
        height: 40,
        color: bgColor,
        child: Row(
          children: [
            const SizedBox(width: 16),
            // App icon
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(5),
                color: textColor,
              ),
              child: Center(
                child: Text(
                  'G',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: bgColor,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'GoSend',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
            ),
            const Spacer(),
            // Window controls
            _WindowButton(
              icon: Icons.remove,
              hoverColor: hoverColor,
              iconColor: iconColor,
              onTap: () => windowManager.minimize(),
            ),
            _MaximizeButton(
              hoverColor: hoverColor,
              iconColor: iconColor,
              bgColor: bgColor,
            ),
            _WindowButton(
              icon: Icons.close,
              hoverColor: closeHover,
              iconColor: Colors.white,
              onTap: () => windowManager.close(),
            ),
          ],
        ),
      ),
    );
  }
}

class _WindowButton extends StatefulWidget {
  final IconData icon;
  final Color hoverColor;
  final Color iconColor;
  final VoidCallback onTap;

  const _WindowButton({
    required this.icon,
    required this.hoverColor,
    required this.iconColor,
    required this.onTap,
  });

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          width: 46,
          height: 40,
          color: _isHovered ? widget.hoverColor : Colors.transparent,
          child: Center(
            child: Icon(widget.icon, size: 16, color: widget.iconColor),
          ),
        ),
      ),
    );
  }
}

class _MaximizeButton extends StatefulWidget {
  final Color hoverColor;
  final Color iconColor;
  final Color bgColor;

  const _MaximizeButton({
    required this.hoverColor,
    required this.iconColor,
    required this.bgColor,
  });

  @override
  State<_MaximizeButton> createState() => _MaximizeButtonState();
}

class _MaximizeButtonState extends State<_MaximizeButton> with WindowListener {
  bool _isHovered = false;
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    _checkMaximized();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() {
    _checkMaximized();
  }

  @override
  void onWindowUnmaximize() {
    _checkMaximized();
  }

  Future<void> _checkMaximized() async {
    final isMax = await windowManager.isMaximized();
    if (mounted && isMax != _isMaximized) {
      setState(() => _isMaximized = isMax);
    }
  }

  Future<void> _toggleMaximize() async {
    if (_isMaximized) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
    await _checkMaximized();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: _toggleMaximize,
        child: Container(
          width: 46,
          height: 40,
          color: _isHovered ? widget.hoverColor : Colors.transparent,
          child: Center(
            child: Icon(
              _isMaximized ? Icons.filter_none : Icons.crop_square,
              size: 14,
              color: widget.iconColor,
            ),
          ),
        ),
      ),
    );
  }
}
