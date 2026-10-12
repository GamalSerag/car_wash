import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/profile_model.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import 'admin_home_screen.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'splash_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  final AuthService _authService = AuthService();
  final NotificationService _notificationService = NotificationService();

  bool _isChecking = true;
  ProfileModel? _profile;

  @override
  void initState() {
    super.initState();
    _checkAuthentication();
  }

  Future<void> _checkAuthentication() async {
    try {
      final user = _authService.getCurrentUser();
      final profile = user == null
          ? null
          : await _authService.getCurrentProfile();
      if (profile != null) {
        await _notificationService.registerCurrentDevice(
          role: profile.role,
          companyId: profile.companyId,
        );
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _profile = profile;
        _isChecking = false;
      });
    } on AuthException {
      await _authService.signOut();
      _showLogin();
    } catch (_) {
      _showLogin();
    }
  }

  void _showLogin() {
    if (!mounted) {
      return;
    }

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
    setState(() {
      _profile = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return const SplashScreen();
    }

    final profile = _profile;
    if (profile == null) {
      return LoginScreen(onLoginSuccess: _handleLoginSuccess);
    }

    if (profile.isAdmin) {
      return AdminHomeScreen(profile: profile, onLogout: _handleLogout);
    }

    return HomeScreen(onLogout: _handleLogout);
  }
}
