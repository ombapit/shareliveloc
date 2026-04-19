import 'dart:io';
import 'package:flutter/material.dart';
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
  bool _mandatoryUpdate = false;
  bool _updateInProgress = false;

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
    final mandatory = await _checkForUpdate();

    if (mandatory) {
      // Never navigate. UI will show mandatory update screen.
      if (mounted) setState(() => _mandatoryUpdate = true);
      // Kick off the first attempt automatically
      _triggerImmediateUpdate();
      return;
    }

    await Future.delayed(const Duration(milliseconds: 1500));

    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainScreen()),
      );
    }
  }

  /// Returns true if immediate (mandatory) update is required.
  Future<bool> _checkForUpdate() async {
    if (!Platform.isAndroid) return false;

    AppUpdateInfo info;
    try {
      info = await InAppUpdate.checkForUpdate();
    } catch (_) {
      return false;
    }

    if (info.updateAvailability != UpdateAvailability.updateAvailable) {
      return false;
    }

    if (info.immediateUpdateAllowed) {
      return true;
    }

    // Optional update - start flexible, don't block
    if (info.flexibleUpdateAllowed) {
      try {
        await InAppUpdate.startFlexibleUpdate();
        await InAppUpdate.completeFlexibleUpdate();
      } catch (_) {}
    }
    return false;
  }

  Future<void> _triggerImmediateUpdate() async {
    if (_updateInProgress) return;
    setState(() => _updateInProgress = true);
    try {
      await InAppUpdate.performImmediateUpdate();
      // If success, Play Store restarts app. If not success, we stay here.
    } catch (_) {
      // User cancelled, or error. Keep blocking UI visible.
    }
    if (mounted) setState(() => _updateInProgress = false);
  }

  void _exitApp() {
    // Force-close the process
    exit(0);
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_mandatoryUpdate,
      child: Scaffold(
        backgroundColor: const Color(0xFF008069),
        body: Center(
          child: FadeTransition(
            opacity: _fadeAnim,
            child: ScaleTransition(
              scale: _scaleAnim,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
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
                        color: Color(0xFF008069),
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
                    if (_mandatoryUpdate)
                      _buildUpdateBlock()
                    else
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
        ),
      ),
    );
  }

  Widget _buildUpdateBlock() {
    return Column(
      children: [
        const Icon(Icons.system_update, size: 48, color: Colors.white),
        const SizedBox(height: 16),
        const Text(
          'Pembaruan Wajib',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Versi terbaru tersedia. Anda harus update untuk menggunakan aplikasi.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _updateInProgress ? null : _triggerImmediateUpdate,
            icon: const Icon(Icons.system_update),
            label: Text(_updateInProgress ? 'Memproses...' : 'Update Sekarang'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF008069),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _exitApp,
          child: const Text(
            'Keluar Aplikasi',
            style: TextStyle(color: Colors.white70),
          ),
        ),
      ],
    );
  }
}
