import 'package:flutter/material.dart';

class AccessSuspendedScreen extends StatefulWidget {
  const AccessSuspendedScreen({
    super.key,
    required this.message,
    required this.onRetry,
    required this.onLogout,
  });

  final String message;
  final Future<void> Function() onRetry;
  final Future<void> Function() onLogout;

  @override
  State<AccessSuspendedScreen> createState() => _AccessSuspendedScreenState();
}

class _AccessSuspendedScreenState extends State<AccessSuspendedScreen> {
  bool _busy = false;
  bool _loggingOut = false;

  Future<void> _run(
    Future<void> Function() action, {
    bool logout = false,
  }) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _loggingOut = logout;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تعذر الاتصال. تحقق من الإنترنت وحاول مرة أخرى'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const spinner = SizedBox.square(
      dimension: 20,
      child: CircularProgressIndicator(strokeWidth: 2),
    );
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.lock_outline,
                    size: 56,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    widget.message,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _busy ? null : () => _run(widget.onRetry),
                      icon: _busy && !_loggingOut
                          ? spinner
                          : const Icon(Icons.refresh),
                      label: const Text('التحقق من تفعيل الاشتراك'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _run(widget.onLogout, logout: true),
                      icon: _busy && _loggingOut
                          ? spinner
                          : const Icon(Icons.logout),
                      label: const Text('تسجيل الخروج'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
