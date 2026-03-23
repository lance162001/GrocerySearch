import 'package:flutter/material.dart';
import 'package:flutter_front_end/services/grocery_api.dart';
import 'package:flutter_front_end/state/app_state.dart';
import 'package:flutter_front_end/widgets/app_bar_user_menu.dart';
import 'package:flutter_front_end/widgets/hint_banner.dart';
import 'package:flutter_front_end/widgets/overflow_menu_nudge.dart';
import 'package:flutter_front_end/widgets/top_level_navigation.dart';
import 'package:provider/provider.dart';

class PreferencesPage extends StatefulWidget {
  const PreferencesPage({super.key});

  @override
  State<PreferencesPage> createState() => _PreferencesPageState();
}

class _PreferencesPageState extends State<PreferencesPage> {
  _LoadState _loadState = _LoadState.loading;
  bool _newsletterOptedIn = false;
  bool _updating = false;

  @override
  void initState() {
    super.initState();
    _loadNewsletterStatus();
  }

  Future<void> _loadNewsletterStatus() async {
    final userId = context.read<AppState>().currentUserId;
    if (userId == null) {
      setState(() => _loadState = _LoadState.unavailable);
      return;
    }
    try {
      final optedIn = await context.read<GroceryApi>().fetchNewsletterStatus(userId);
      if (!mounted) return;
      setState(() {
        _newsletterOptedIn = optedIn;
        _loadState = _LoadState.ready;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadState = _LoadState.error);
    }
  }

  Future<void> _toggleNewsletter() async {
    final userId = context.read<AppState>().currentUserId;
    if (userId == null) return;
    setState(() => _updating = true);
    try {
      final newValue =
          await context.read<GroceryApi>().updateNewsletterStatus(userId, optIn: !_newsletterOptedIn);
      if (!mounted) return;
      setState(() => _newsletterOptedIn = newValue);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            newValue
                ? 'You are now subscribed to the newsletter.'
                : 'You have been unsubscribed from the newsletter.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not update newsletter preference. Please try again.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Preferences'),
        actions: const [AppBarUserMenu(showPreferences: false)],
      ),
      bottomNavigationBar: const TopLevelNavigationBar(
        currentDestination: AppTopLevelDestination.stores,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          _SectionHeader(label: 'Appearance'),
          _hintsTile(context),
          _SectionHeader(label: 'Newsletter'),
          _newsletterTile(),
        ],
      ),
    );
  }

  Widget _hintsTile(BuildContext context) {
    final hideHints = context.watch<AppState>().hideHints;
    return SwitchListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      secondary: Icon(
        Icons.tips_and_updates_outlined,
        color: Theme.of(context).colorScheme.primary,
      ),
      title: const Text('Show hints'),
      subtitle: Text(
        hideHints
            ? 'Onboarding hints are hidden.'
            : 'Brief tips are shown on each screen.',
        style: const TextStyle(color: Color(0xFF71717A)),
      ),
      value: !hideHints,
      onChanged: (value) {
        context.read<AppState>().setHideHints(!value);
        if (value) {
          // Re-allow dismissed hints so they re-appear when hints are turned
          // back on next time the user visits each screen.
          HintBanner.dismissed.clear();
          OverflowMenuNudge.dismissed.clear();
        }
      },
    );
  }

  Widget _newsletterTile() {
    switch (_loadState) {
      case _LoadState.loading:
        return const ListTile(
          leading: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          title: Text('Loading…'),
        );

      case _LoadState.error:
        return ListTile(
          leading: const Icon(Icons.error_outline, color: Colors.red),
          title: const Text('Could not load newsletter preference.'),
          trailing: TextButton(
            onPressed: () {
              setState(() => _loadState = _LoadState.loading);
              _loadNewsletterStatus();
            },
            child: const Text('Retry'),
          ),
        );

      case _LoadState.unavailable:
        return const ListTile(
          leading: Icon(Icons.info_outline, color: Color(0xFF71717A)),
          title: Text('Sign in to manage newsletter preferences.'),
        );

      case _LoadState.ready:
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: Icon(
            _newsletterOptedIn ? Icons.email : Icons.email_outlined,
            color: Theme.of(context).colorScheme.primary,
          ),
          title: const Text('Weekly newsletter'),
          subtitle: Text(
            _newsletterOptedIn
                ? 'You are subscribed to weekly price updates.'
                : 'You are not receiving newsletters.',
            style: const TextStyle(color: Color(0xFF71717A)),
          ),
          trailing: _updating
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : FilledButton(
                  onPressed: _toggleNewsletter,
                  style: FilledButton.styleFrom(
                    backgroundColor: _newsletterOptedIn
                        ? const Color(0xFFE9F7EE)
                        : Theme.of(context).colorScheme.primary,
                    foregroundColor: _newsletterOptedIn
                        ? const Color(0xFF1b4332)
                        : Colors.white,
                    elevation: 0,
                  ),
                  child: Text(_newsletterOptedIn ? 'Unsubscribe' : 'Subscribe'),
                ),
        );
    }
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: Color(0xFF71717A),
        ),
      ),
    );
  }
}

enum _LoadState { loading, ready, error, unavailable }
