import 'package:flutter/material.dart';
import 'package:flutter_front_end/config/app_routes.dart';
import 'package:flutter_front_end/services/auth_service.dart';
import 'package:provider/provider.dart';

/// A compact user-profile action for AppBar.actions.
///
/// Shows a circular avatar (photo or initial) that opens a popup menu with
/// the user's display name, a Preferences link, and a Sign-out item.
/// Set [showPreferences] to false on the Preferences screen to avoid
/// pushing the same route onto itself.
class AppBarUserMenu extends StatelessWidget {
  const AppBarUserMenu({super.key, this.showPreferences = true});
  final bool showPreferences;

  static String _initial(String name) {
    if (name.isEmpty) return '?';
    return name[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final authService = context.watch<AuthService>();
    final photoUrl = authService.photoUrl;
    final displayName = authService.displayName ?? authService.email ?? '';

    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Center(
        child: PopupMenuButton<String>(
          tooltip: displayName,
          onSelected: (value) {
            if (value == 'sign_out') {
              authService.signOut();
            } else if (value == 'preferences') {
              Navigator.pushNamed(context, AppRoutes.preferences);
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              enabled: false,
              child: Text(
                displayName,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            if (showPreferences) ...[
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'preferences',
                child: Row(
                  children: [
                    Icon(Icons.tune, size: 20, color: Color(0xFF2D6A4F)),
                    SizedBox(width: 12),
                    Text('Preferences'),
                  ],
                ),
              ),
            ],
            const PopupMenuDivider(),
            const PopupMenuItem(
              value: 'sign_out',
              child: Text('Sign out'),
            ),
          ],
          child: _ProfileAvatar(
            photoUrl: photoUrl,
            initial: _initial(displayName),
          ),
        ),
      ),
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({required this.photoUrl, required this.initial});
  final String? photoUrl;
  final String initial;

  @override
  Widget build(BuildContext context) {
    final url = photoUrl;
    if (url == null) {
      return _fallback(context);
    }
    return ClipOval(
      child: SizedBox(
        width: 32,
        height: 32,
        child: Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _fallback(context),
        ),
      ),
    );
  }

  Widget _fallback(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return CircleAvatar(
      radius: 16,
      backgroundColor: colorScheme.primaryContainer,
      child: Text(
        initial,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }
}
