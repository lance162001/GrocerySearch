import 'dart:html' as html;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_front_end/services/grocery_api.dart';
import 'package:provider/provider.dart';

class UnsubscribePage extends StatefulWidget {
  const UnsubscribePage({super.key});

  @override
  State<UnsubscribePage> createState() => _UnsubscribePageState();
}

class _UnsubscribePageState extends State<UnsubscribePage> {
  _Status _status = _Status.idle;
  // Captured in initState before MaterialApp can rewrite the browser URL.
  String? _token;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _token = Uri.base.queryParameters['token'];
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Non-web: token comes from route arguments.
    if (!kIsWeb && _token == null) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map<String, dynamic>) {
        _token = args['token'] as String?;
      }
    }
  }

  Future<void> _unsubscribe() async {
    final token = _token;
    if (token == null || token.isEmpty) {
      setState(() => _status = _Status.invalidToken);
      return;
    }

    setState(() => _status = _Status.loading);

    try {
      final api = context.read<GroceryApi>();
      final uri = api.buildUri('/users/unsubscribe', {'token': token});
      final response = await api.get(uri);
      if (response.statusCode == 200) {
        setState(() => _status = _Status.success);
      } else {
        setState(() => _status = _Status.error);
      }
    } catch (_) {
      setState(() => _status = _Status.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'GrocerySearch',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF2D6A4F),
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 32),
                _buildBody(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_status) {
      case _Status.success:
        return Column(
          children: [
                const Icon(Icons.check_circle_outline, size: 56, color: Color(0xFF2D6A4F)),
                const SizedBox(height: 16),
                const Text(
                  "You've been unsubscribed.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                const Text(
                  "You won't receive any more GrocerySearch newsletters.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.black54),
                ),
                const SizedBox(height: 20),
                _homeButton(),
              ],
        );

      case _Status.invalidToken:
        return const Text(
          'This unsubscribe link is invalid or has expired.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.red),
        );

      case _Status.error:
        return Column(
          children: [
            const Text(
              'Something went wrong. Please try again.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.red),
            ),
            const SizedBox(height: 16),
            _confirmButton(),
          ],
        );

      case _Status.loading:
        return const Center(child: CircularProgressIndicator());

      case _Status.idle:
        return Column(
          children: [
            const Text(
              'Unsubscribe from GrocerySearch newsletters?',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            const Text(
              "You'll stop receiving weekly price updates and store highlights.",
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54),
            ),
            const SizedBox(height: 24),
            _confirmButton(),
            const SizedBox(height: 12),
            _homeButton(),
          ],
        );
    }
  }

  Widget _homeButton() {
    return TextButton(
      onPressed: () {
        if (kIsWeb) {
          html.window.location.href = '/';
        } else {
          Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
        }
      },
      child: const Text(
        'Go to GrocerySearch',
        style: TextStyle(color: Color(0xFF2D6A4F)),
      ),
    );
  }

  Widget _confirmButton() {
    return FilledButton(
      onPressed: _unsubscribe,
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFF2D6A4F),
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: const Text('Confirm Unsubscribe', style: TextStyle(fontSize: 15)),
    );
  }
}

enum _Status { idle, loading, success, error, invalidToken }
