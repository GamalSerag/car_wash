import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/profile_model.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../services/offline_runtime.dart';
import '../services/vehicle_type_service.dart';
import 'admin_home_screen.dart';
import 'access_suspended_screen.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'splash_screen.dart';
import 'super_admin_home_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  final AuthService _authService = AuthService();
  final NotificationService _notificationService = NotificationService();

  bool _isChecking = true;
  ProfileModel? _profile;
  bool _checkingAccess = false;
  bool _checkAgain = false;
  String? _notificationUserId;
  Timer? _accessTimer;
  RealtimeChannel? _companyChannel;
  String? _watchedCompanyId;
  String? _accessError;
  String? _offlineScheduledUser;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    OfflineRuntime.changes.addListener(_checkCachedAccess);
    _accessTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_profile != null &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        _refreshAccessInBackground();
      }
    });
    _checkAuthentication();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    OfflineRuntime.changes.removeListener(_checkCachedAccess);
    _accessTimer?.cancel();
    _stopCompanySubscription();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _profile != null) {
      _refreshAccessInBackground();
      OfflineRuntime.changed();
      OfflineRuntime.requestSync();
    }
  }

  void _refreshAccessInBackground() {
    unawaited(_checkAuthentication(quiet: true).catchError((Object _) {}));
  }

  void _checkCachedAccess() {
    unawaited(_applyCachedAccess().catchError((Object _) {}));
  }

  Future<void> _applyCachedAccess() async {
    if (!OfflineRuntime.enabled) return;
    final id = _authService.getCurrentUser()?.id;
    if (id == null) return;
    final cached = await OfflineRuntime.session!.cachedProfile(
      id,
      allowExpired: true,
    );
    if (!mounted ||
        _authService.getCurrentUser()?.id != id ||
        cached == null ||
        cached.canAccessApp)
      return;
    Navigator.of(context).popUntil((route) => route.isFirst);
    setState(() {
      _profile = cached;
      _isChecking = false;
      _accessError = null;
    });
  }

  void _stopCompanySubscription() {
    final channel = _companyChannel;
    _companyChannel = null;
    _watchedCompanyId = null;
    if (channel != null) {
      unawaited(Supabase.instance.client.removeChannel(channel));
    }
  }

  void _watchCompany(ProfileModel? profile) {
    if (profile == null || profile.isSuperAdmin || profile.companyId.isEmpty) {
      _stopCompanySubscription();
      return;
    }
    if (_watchedCompanyId == profile.companyId) return;
    _stopCompanySubscription();
    _watchedCompanyId = profile.companyId;
    _companyChannel = Supabase.instance.client
        .channel('company-access-${profile.id}-${profile.companyId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'companies',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: profile.companyId,
          ),
          callback: (_) => _refreshAccessInBackground(),
        )
        .subscribe();
  }

  Future<void> _checkAuthentication({bool quiet = false}) async {
    if (_checkingAccess) {
      _checkAgain = true;
      return;
    }
    _checkingAccess = true;
    final expectedUserId = _authService.getCurrentUser()?.id;
    try {
      final user = _authService.getCurrentUser();
      final profile = user == null
          ? null
          : await _authService.getCurrentProfile();
      if (!mounted || _authService.getCurrentUser()?.id != expectedUserId) {
        return;
      }

      if (profile != null &&
          !profile.canAccessApp &&
          _profile?.canAccessApp != false) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
      setState(() {
        _profile = profile;
        _accessError = null;
        _isChecking = false;
      });
      _watchCompany(profile);
      if (profile != null) NotificationService.showPendingReport(profile);
      if (profile != null && profile.canAccessApp) {
        if (OfflineRuntime.enabled &&
            OfflineRuntime.online.value &&
            profile.role == 'employee') {
          unawaited(
            VehicleTypeService()
                .getActiveVehicleTypes()
                .then<void>((_) {})
                .catchError((Object _) {}),
          );
        }
        if (OfflineRuntime.enabled &&
            profile.role == 'employee' &&
            _offlineScheduledUser != profile.id) {
          try {
            await OfflineRuntime.schedule?.call();
            _offlineScheduledUser = profile.id;
          } catch (_) {
            /* Retry registration on the next access check. */
          }
          OfflineRuntime.requestSync();
        }
        if (_notificationUserId != profile.id &&
            (!OfflineRuntime.enabled || OfflineRuntime.online.value)) {
          await _notificationService.registerCurrentDevice(
            role: profile.role,
            companyId: profile.companyId,
          );
          if (mounted &&
              _authService.getCurrentUser()?.id == profile.id &&
              _profile?.canAccessApp == true) {
            _notificationUserId = profile.id;
          }
        }
      } else if (_notificationUserId != null) {
        _notificationUserId = null;
        await _notificationService.removeCurrentDevice();
      }
    } on AuthException {
      await _authService.signOut();
      _showLogin();
    } catch (_) {
      if (quiet && !_isChecking) rethrow;
      if (mounted &&
          _authService.getCurrentUser() != null &&
          OfflineRuntime.enabled) {
        setState(() {
          _isChecking = false;
          _accessError = 'يلزم اتصال بالإنترنت لتأكيد صلاحية الحساب';
        });
      } else {
        _showLogin();
      }
    } finally {
      _checkingAccess = false;
      if (_checkAgain && mounted) {
        _checkAgain = false;
        _refreshAccessInBackground();
      }
    }
  }

  void _showLogin() {
    if (!mounted) {
      return;
    }

    _stopCompanySubscription();
    _notificationUserId = null;
    _offlineScheduledUser = null;
    setState(() {
      _profile = null;
      _isChecking = false;
    });
  }

  Future<void> _handleLoginSuccess() async {
    setState(() {
      _isChecking = true;
    });
    await _checkAuthentication();
  }

  void _handleLogout() {
    _showLogin();
  }

  Future<void> _logoutSuspended() async {
    await _notificationService.removeCurrentDevice();
    await _authService.signOut();
    if (mounted) _handleLogout();
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return const SplashScreen();
    }

    final profile = _profile;
    if (_accessError != null) {
      return AccessSuspendedScreen(
        message: _accessError!,
        onRetry: _checkAuthentication,
        onLogout: _logoutSuspended,
      );
    }
    if (profile == null) {
      return LoginScreen(onLoginSuccess: _handleLoginSuccess);
    }

    if (!profile.canAccessApp) {
      return AccessSuspendedScreen(
        message: !profile.isActive
            ? 'هذا الحساب غير مفعل. يرجى التواصل مع الإدارة'
            : 'تم إيقاف اشتراك الشركة. تواصل مع إدارة النظام',
        onRetry: () => _checkAuthentication(quiet: true),
        onLogout: _logoutSuspended,
      );
    }

    if (profile.isSuperAdmin) {
      return SuperAdminHomeScreen(profile: profile, onLogout: _handleLogout);
    }

    if (profile.isAdmin) {
      return AdminHomeScreen(profile: profile, onLogout: _handleLogout);
    }

    return HomeScreen(onLogout: _handleLogout);
  }
}
