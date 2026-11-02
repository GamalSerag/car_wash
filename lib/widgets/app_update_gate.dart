import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/app_update_policy.dart';
import '../services/app_update_service.dart';
import '../services/offline_runtime.dart';
import 'app_version_label.dart';

class AppUpdateGate extends StatefulWidget {
  const AppUpdateGate({
    super.key,
    required this.child,
    this.checkForUpdate,
    this.openUpdate,
    this.enabled,
  });

  final Widget child;
  final Future<AppUpdatePolicy?> Function()? checkForUpdate;
  final Future<bool> Function(Uri)? openUpdate;
  final bool? enabled;

  @override
  State<AppUpdateGate> createState() => _AppUpdateGateState();
}

class _AppUpdateGateState extends State<AppUpdateGate>
    with WidgetsBindingObserver {
  bool _checking = true;
  bool _inFlight = false;
  bool _opening = false;
  bool _verified = false;
  String? _error;
  AppUpdatePolicy? _policy;
  Timer? _timer;

  bool get _enabled =>
      widget.enabled ??
      (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    OfflineRuntime.online.addListener(_connectivityChanged);
    _check();
    _timer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        _check();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  void _connectivityChanged() {
    if (OfflineRuntime.online.value) _check();
  }

  Future<void> _check() async {
    if (_inFlight || !_enabled) {
      if (!_enabled) _checking = false;
      return;
    }
    _inFlight = true;
    try {
      final policy =
          await (widget.checkForUpdate ?? AppUpdateService().checkForUpdate)();
      if (!mounted) return;
      setState(() {
        _policy = policy;
        _verified = true;
        _error = null;
        _checking = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _checking = false;
        _error = 'تعذر التحقق من التحديث. تأكد من اتصال الإنترنت وحاول مجددًا';
      });
    } finally {
      _inFlight = false;
    }
  }

  Future<void> _openUpdate() async {
    if (_opening || _policy == null) return;
    setState(() => _opening = true);
    try {
      final url = _policy!.updateUrl;
      final opened =
          await (widget.openUpdate?.call(url) ??
              launchUrl(url, mode: LaunchMode.externalApplication));
      if (!opened) throw StateError('Could not open store');
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'تعذر فتح رابط التحديث. حاول مرة أخرى');
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    OfflineRuntime.online.removeListener(_connectivityChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final blocked = _enabled && (!_verified || _policy != null);
    return Stack(
      fit: StackFit.expand,
      children: [
        // Keep the navigator mounted, but inaccessible on every route while blocked.
        Offstage(offstage: blocked, child: widget.child),
        if (blocked)
          PopScope(
            canPop: false,
            child: Scaffold(
              body: SafeArea(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(24, 24, 24, 64),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 420),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.system_update, size: 64),
                              const SizedBox(height: 24),
                              Text(
                                _policy != null
                                    ? 'تحديث التطبيق مطلوب'
                                    : 'التحقق من إصدار التطبيق',
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineSmall,
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16),
                              if (_policy != null)
                                const Text(
                                  'يرجى تحديث مغسلة إلى أحدث إصدار للمتابعة',
                                  textAlign: TextAlign.center,
                                ),
                              if (_error != null) ...[
                                const SizedBox(height: 16),
                                Text(_error!, textAlign: TextAlign.center),
                              ],
                              const SizedBox(height: 24),
                              if (_checking) const CircularProgressIndicator(),
                              if (_policy != null)
                                FilledButton.icon(
                                  onPressed: _opening ? null : _openUpdate,
                                  icon: _opening
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.download),
                                  label: const Text('تحديث الآن'),
                                ),
                              if (!_checking)
                                TextButton.icon(
                                  onPressed: () {
                                    setState(() => _checking = true);
                                    _check();
                                  },
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('إعادة التحقق'),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const Positioned(
                      right: 16,
                      bottom: 16,
                      child: AppVersionLabel(),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
