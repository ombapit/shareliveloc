import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:in_app_update/in_app_update.dart';
import 'main_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _fadeAnim;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fadeAnim = CurvedAnimation(parent: _animController, curve: Curves.easeIn);
    _scaleAnim = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutBack),
    );
    _animController.forward();

    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final hasUpdate = await _checkForUpdate();

    // If update is mandatory, don't proceed to main screen
    if (hasUpdate) return;

    await Future.delayed(const Duration(milliseconds: 1500));

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainScreen()),
      );
    }
  }

  /// Returns true if an update was required (forced), so caller should
  /// not proceed to main screen.
  Future<bool> _checkForUpdate() async {
    if (!Platform.isAndroid) return false;

    AppUpdateInfo info;
    try {
      info = await InAppUpdate.checkForUpdate();
    } catch (_) {
      // Not installed from Play Store or no internet - allow entry
      return false;
    }

    if (info.updateAvailability != UpdateAvailability.updateAvailable) {
      return false;
    }

    if (!info.immediateUpdateAllowed) {
      // Optional update - start flexible, don't block
      if (info.flexibleUpdateAllowed) {
        try {
          await InAppUpdate.startFlexibleUpdate();
          await InAppUpdate.completeFlexibleUpdate();
        } catch (_) {}
      }
      return false;
    }

    // Force update: loop until user accepts or exits app
    while (true) {
      try {
        final result = await InAppUpdate.performImmediateUpdate();
        if (result == AppUpdateResult.success) {
          // Play Store restarts the app after update, this rarely runs
          return true;
        }
      } catch (_) {
        // Failed (e.g. user cancelled)
      }

      // User cancelled or update failed - show blocking dialog
      if (!mounted) return true;
      final retry = await _showMandatoryUpdateDialog();
      if (!retry) {
        await SystemNavigator.pop();
        return true;
      }
    }
  }

  Future<bool> _showMandatoryUpdateDialog() async {
    if (!mounted) return false;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          icon: const Icon(Icons.system_update, size: 48),
          title: const Text('Pembaruan Wajib'),
          content: const Text(
            'Versi terbaru ShareLiveLoc tersedia. Anda harus update untuk melanjutkan menggunakan aplikasi.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Keluar'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.system_update),
              label: const Text('Update'),
            ),
          ],
        ),
      ),
    );
    return result == true;
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF2196F3),
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnim,
          child: ScaleTransition(
            scale: _scaleAnim,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.2),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.location_on,
                    size: 72,
                    color: Color(0xFF2196F3),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'ShareLiveLoc',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Berbagi Lokasi Real-Time',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 48),
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
