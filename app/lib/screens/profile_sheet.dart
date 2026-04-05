import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_front_end/state/markup_state.dart';
import 'package:flutter_front_end/config/markup_theme.dart';
import 'package:flutter_front_end/config/app_routes.dart';

void showProfileSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => const ProfileSheet(),
  );
}

class ProfileSheet extends StatelessWidget {
  const ProfileSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<MarkupState>();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Profile',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: MarkupColors.textPrimary,
              ),
            ),
            const SizedBox(height: 20),
            if (!state.isSignedIn)
              ListTile(
                leading: const Icon(Icons.login, color: MarkupColors.darkGreen),
                title: const Text('Sign in'),
                subtitle: const Text('Get price alerts by email'),
                onTap: () => _signIn(context, state),
              )
            else ...[
              ListTile(
                leading:
                    const Icon(Icons.person, color: MarkupColors.darkGreen),
                title: Text('Signed in (User #${state.currentUserId})'),
              ),
              ListTile(
                leading: const Icon(Icons.logout,
                    color: MarkupColors.textSecondary),
                title: const Text('Sign out'),
                onTap: () => _signOut(context, state),
              ),
            ],
            ListTile(
              leading: const Icon(Icons.location_on_outlined,
                  color: MarkupColors.textSecondary),
              title: Text(
                state.locationSet
                    ? 'Location: ${state.zipcode}'
                    : 'Set location',
              ),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.email_outlined,
                  color: MarkupColors.textSecondary),
              title: const Text('Newsletter preferences'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, AppRoutes.preferences);
              },
            ),
            ListTile(
              leading: const Icon(Icons.add_business_outlined,
                  color: MarkupColors.textSecondary),
              title: const Text('Suggest a store'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, AppRoutes.suggestStore);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _signIn(BuildContext context, MarkupState state) async {
    Navigator.pop(context);
    // Create/fetch an anonymous user account so we can track items server-side.
    // fetchOrCreateUserId() handles anonymous fallback via local cache and
    // also links to a Firebase account if the user is already signed in.
    try {
      final userId = await state.api.fetchOrCreateUserId();
      state.setUserId(userId);
    } catch (_) {}
  }

  void _signOut(BuildContext context, MarkupState state) {
    Navigator.pop(context);
    // For now, just clear local state.
    // Full sign-out (Google OAuth) can be added later.
    state.clearUserId();
  }
}
