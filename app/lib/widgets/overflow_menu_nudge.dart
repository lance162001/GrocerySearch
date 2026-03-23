import 'package:flutter/material.dart';
import 'package:flutter_front_end/state/app_state.dart';
import 'package:provider/provider.dart';

/// A tiny speech-bubble callout that floats near the top-right of the screen
/// and points upward toward the AppBar overflow (⋮) button.
///
/// Shown once per session unless the user has hidden hints globally.
class OverflowMenuNudge extends StatefulWidget {
  const OverflowMenuNudge({
    super.key,
    required this.nudgeKey,
    required this.message,
  });

  final String nudgeKey;
  final String message;

  /// Session-wide set of dismissed nudge keys. Clear this when hints are
  /// re-enabled in Preferences to let nudges reappear.
  static final Set<String> dismissed = {};

  @override
  State<OverflowMenuNudge> createState() => _OverflowMenuNudgeState();
}

class _OverflowMenuNudgeState extends State<OverflowMenuNudge> {
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    _visible = !OverflowMenuNudge.dismissed.contains(widget.nudgeKey);
  }

  void _dismiss() {
    OverflowMenuNudge.dismissed.add(widget.nudgeKey);
    setState(() => _visible = false);
  }

  @override
  Widget build(BuildContext context) {
    final hidden = context.watch<AppState>().hideHints;
    if (hidden || !_visible) return const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Small upward-pointing triangle that visually connects the bubble
        // to the AppBar ⋮ button above.
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.only(right: 10),
            child: CustomPaint(
              size: const Size(14, 8),
              painter: _TrianglePainter(),
            ),
          ),
        ),
        // Speech bubble card
        Container(
          constraints: const BoxConstraints(maxWidth: 200),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xFFE9F7EE),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF95D5B2)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(
                  Icons.more_vert,
                  size: 13,
                  color: Color(0xFF1b4332),
                ),
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  widget.message,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF1b4332),
                    height: 1.4,
                  ),
                ),
              ),
              GestureDetector(
                onTap: _dismiss,
                child: const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Icon(
                    Icons.close,
                    size: 13,
                    color: Color(0xFF2D6A4F),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TrianglePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()
      ..color = const Color(0xFFE9F7EE)
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = const Color(0xFF95D5B2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..close();

    canvas.drawPath(path, fill);
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
