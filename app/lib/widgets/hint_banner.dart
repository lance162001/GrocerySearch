import 'package:flutter/material.dart';
import 'package:flutter_front_end/state/app_state.dart';
import 'package:provider/provider.dart';

/// A compact, dismissible hint card meant to orient new users.
///
/// Dismissed hints are tracked in a session-wide static set, so
/// each hint only appears once per app launch regardless of navigation.
class HintBanner extends StatefulWidget {
  const HintBanner({
    super.key,
    required this.hintKey,
    required this.message,
    this.icon = Icons.tips_and_updates_outlined,
  });

  final String hintKey;
  final String message;
  final IconData icon;

  // Session-wide dismissal tracking — cleared on next app launch.
  static final Set<String> dismissed = {};

  @override
  State<HintBanner> createState() => _HintBannerState();
}

class _HintBannerState extends State<HintBanner> {
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    _visible = !HintBanner.dismissed.contains(widget.hintKey);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // If the user later enables hideHints, collapse immediately.
    if (_visible && context.read<AppState>().hideHints) {
      _visible = false;
    }
  }

  void _dismiss() {
    HintBanner.dismissed.add(widget.hintKey);
    setState(() => _visible = false);
  }

  @override
  Widget build(BuildContext context) {
    final hidden = context.watch<AppState>().hideHints;
    if (hidden) return const SizedBox.shrink();
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
      child: _visible
          ? Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFE9F7EE),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF95D5B2)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Icon(
                        widget.icon,
                        size: 15,
                        color: const Color(0xFF1b4332),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.message,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF1b4332),
                          height: 1.4,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: _dismiss,
                      child: const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: Icon(
                          Icons.close,
                          size: 15,
                          color: Color(0xFF2D6A4F),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}
