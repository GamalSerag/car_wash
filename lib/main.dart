import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/app_theme.dart';
import 'core/app_navigation.dart';
import 'core/supabase_config.dart';
import 'screens/auth_gate.dart';
import 'widgets/app_update_gate.dart';
import 'services/offline_runtime.dart';
import 'services/offline_sync_service.dart';
import 'services/offline_background_service.dart';
import 'services/coordinated_auth_client.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await _startApplication();
  } catch (_) {
    runApp(
      MaterialApp(
        theme: AppTheme.light,
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.storage_outlined, size: 48),
                    const SizedBox(height: 16),
                    const Text(
                      'تعذر تهيئة التطبيق. تحقق من مساحة الجهاز وأعد المحاولة',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: main,
                      icon: const Icon(Icons.refresh),
                      label: const Text('إعادة المحاولة'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _startApplication() async {
  await OfflineRuntime.initialize();

  if (_shouldInitializeFirebase) {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  }

  await Supabase.initialize(
    url: SupabaseConfig.url,
    publishableKey: SupabaseConfig.publishableKey,
    httpClient: OfflineRuntime.enabled
        ? CoordinatedAuthClient(
            OfflineRuntime.session!,
            () => Supabase.instance.client.auth.currentUser?.id,
          )
        : null,
    authOptions: OfflineRuntime.enabled
        ? const FlutterAuthClientOptions(
            autoRefreshToken: false,
            localStorage: EmptyLocalStorage(),
          )
        : const FlutterAuthClientOptions(),
  );

  if (OfflineRuntime.enabled) {
    final client = Supabase.instance.client;
    await OfflineRuntime.session!.restore(client);
    final service = OfflineSyncService(
      client,
      OfflineRuntime.store!,
      OfflineRuntime.session!,
    );
    OfflineRuntime.sync = () => service.run();
    OfflineRuntime.manualSync = () => service.run(manual: true);
    await OfflineBackgroundService.initialize();
    OfflineRuntime.schedule = () async {
      final user = client.auth.currentUser?.id;
      if (user == null) return;
      final p = await OfflineRuntime.session!.cachedProfile(
        user,
        allowExpired: true,
      );
      if (p != null)
        await OfflineBackgroundService.schedule(
          user,
          p.companyId,
          await OfflineRuntime.session!.epoch(),
        );
    };
    OfflineRuntime.watch();
  }

  runApp(const CarWashApp());
}

bool get _shouldInitializeFirebase {
  return !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
}

class CarWashApp extends StatelessWidget {
  const CarWashApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: AppNavigation.navigatorKey,
      title: 'مغسلة',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AppUpdateGate(child: child ?? const SizedBox.shrink()),
        );
      },
      home: const AuthGate(),
    );
  }
}
