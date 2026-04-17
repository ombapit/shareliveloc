import 'dart:async';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

const _notificationChannelId = 'shareliveloc_location';
const _notificationId = 888;

const _prefShareId = 'share_id';
const _prefName = 'share_name';
const _prefGroupName = 'share_group_name';
const _prefIcon = 'share_icon';
const _prefDuration = 'share_duration';
const _prefExpiresAt = 'share_expires_at';

class ShareSession {
  final int shareId;
  final String name;
  final String groupName;
  final String icon;
  final int durationHours;
  final DateTime? expiresAt;

  ShareSession({
    required this.shareId,
    required this.name,
    required this.groupName,
    required this.icon,
    required this.durationHours,
    this.expiresAt,
  });
}

class LocationService {
  static bool _isTracking = false;
  static int? _activeShareId;
  static DateTime? _expiresAt;
  static VoidCallback? onExpired;

  static bool get isTracking => _isTracking;
  static int? get activeShareId => _activeShareId;
  static DateTime? get expiresAt => _expiresAt;

  static Future<void> initService() async {
    final service = FlutterBackgroundService();

    final flnp = FlutterLocalNotificationsPlugin();
    const androidChannel = AndroidNotificationChannel(
      _notificationChannelId,
      'Location Sharing',
      description: 'Notifikasi saat berbagi lokasi aktif',
      importance: Importance.low,
    );
    await flnp
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(androidChannel);

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _onServiceStart,
        autoStart: false,
        isForegroundMode: true,
        autoStartOnBoot: true,
        notificationChannelId: _notificationChannelId,
        initialNotificationTitle: 'ShareLiveLoc',
        initialNotificationContent: 'Berbagi lokasi aktif',
        foregroundServiceNotificationId: _notificationId,
        foregroundServiceTypes: [AndroidForegroundType.location],
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: _onServiceStart,
      ),
    );
  }

  static Future<bool> requestPermission(BuildContext context) async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return false;
    }
    if (permission == LocationPermission.deniedForever) return false;

    if (Platform.isAndroid) {
      // Prominent disclosure for background location (required by Google Play)
      final bgStatus = await Permission.locationAlways.status;
      if (!bgStatus.isGranted) {
        if (!context.mounted) return false;
        final consent = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Izin Lokasi Background'),
            content: const Text(
              'ShareLiveLoc membutuhkan akses lokasi di background agar posisi Anda tetap terkirim ke group saat aplikasi di-minimize atau layar terkunci.\n\n'
              'Data lokasi Anda hanya dikirim selama sesi berbagi aktif dan tidak disimpan setelah sesi berakhir.\n\n'
              'Pilih "Allow all the time" / "Izinkan sepanjang waktu" pada dialog berikutnya.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Tolak'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Lanjutkan'),
              ),
            ],
          ),
        );
        if (consent != true) return false;
        await Permission.locationAlways.request();
      }

      // Notification permission for Android 13+
      final notifStatus = await Permission.notification.status;
      if (!notifStatus.isGranted) {
        await Permission.notification.request();
      }

      // Battery optimization
      final batteryStatus = await Permission.ignoreBatteryOptimizations.status;
      if (!batteryStatus.isGranted) {
        await Permission.ignoreBatteryOptimizations.request();
      }
    }

    return true;
  }

  static Future<Position?> getCurrentPosition() async {
    try {
      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
    } catch (e) {
      return null;
    }
  }

  static Future<void> saveSession({
    required int shareId,
    required String name,
    required String groupName,
    required String icon,
    required int durationHours,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefShareId, shareId);
    await prefs.setString(_prefName, name);
    await prefs.setString(_prefGroupName, groupName);
    await prefs.setString(_prefIcon, icon);
    await prefs.setInt(_prefDuration, durationHours);
    if (durationHours > 0) {
      final expiresAt = DateTime.now().add(Duration(hours: durationHours));
      await prefs.setInt(_prefExpiresAt, expiresAt.millisecondsSinceEpoch);
    }
  }

  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefShareId);
    await prefs.remove(_prefName);
    await prefs.remove(_prefGroupName);
    await prefs.remove(_prefIcon);
    await prefs.remove(_prefDuration);
    await prefs.remove(_prefExpiresAt);
  }

  static Future<ShareSession?> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final shareId = prefs.getInt(_prefShareId);
    if (shareId == null) return null;

    final name = prefs.getString(_prefName) ?? '';
    final groupName = prefs.getString(_prefGroupName) ?? '';
    final icon = prefs.getString(_prefIcon) ?? 'bus';
    final durationHours = prefs.getInt(_prefDuration) ?? 0;
    final expiresAtMs = prefs.getInt(_prefExpiresAt);

    DateTime? expiresAt;
    if (expiresAtMs != null) {
      expiresAt = DateTime.fromMillisecondsSinceEpoch(expiresAtMs);
      if (expiresAt.isBefore(DateTime.now())) {
        await clearSession();
        return null;
      }
    }

    _activeShareId = shareId;
    _isTracking = true;
    _expiresAt = expiresAt;

    // Restart background service if not running
    final service = FlutterBackgroundService();
    if (!await service.isRunning()) {
      await service.startService();
      for (int i = 0; i < 30; i++) {
        if (await service.isRunning()) break;
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }

    return ShareSession(
      shareId: shareId,
      name: name,
      groupName: groupName,
      icon: icon,
      durationHours: durationHours,
      expiresAt: expiresAt,
    );
  }

  static Future<void> startTracking(int shareId, int durationHours) async {
    _activeShareId = shareId;
    _isTracking = true;
    if (durationHours > 0) {
      _expiresAt = DateTime.now().add(Duration(hours: durationHours));
    } else {
      _expiresAt = null;
    }

    final service = FlutterBackgroundService();

    // Start service and wait until it's running
    await service.startService();
    for (int i = 0; i < 30; i++) {
      if (await service.isRunning()) break;
      await Future.delayed(const Duration(milliseconds: 100));
    }

    service.on('expired').listen((_) {
      _isTracking = false;
      _activeShareId = null;
      _expiresAt = null;
      clearSession();
      onExpired?.call();
    });
  }

  static Future<void> stopTracking() async {
    _isTracking = false;
    _expiresAt = null;
    await clearSession();

    final service = FlutterBackgroundService();
    service.invoke('stopTracking');

    if (_activeShareId != null) {
      await ApiService.stopShare(_activeShareId!);
      _activeShareId = null;
    }
  }
}

@pragma('vm:entry-point')
Future<void> _onServiceStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  print('[ShareLiveLoc] Service started');

  StreamSubscription<Position>? positionSub;
  Timer? expiryTimer;
  Timer? heartbeatTimer;
  Position? lastPosition;
  int? shareId;

  // Read session from SharedPreferences directly
  final prefs = await SharedPreferences.getInstance();
  shareId = prefs.getInt(_prefShareId);
  print('[ShareLiveLoc] shareId from prefs: $shareId');

  if (shareId == null) {
    print('[ShareLiveLoc] No session found, stopping service');
    if (service is AndroidServiceInstance) {
      await service.stopSelf();
    }
    return;
  }

  final durationHours = prefs.getInt(_prefDuration) ?? 0;
  final expiresAtMs = prefs.getInt(_prefExpiresAt);

  Future<void> clearPrefs() async {
    await prefs.remove(_prefShareId);
    await prefs.remove(_prefName);
    await prefs.remove(_prefGroupName);
    await prefs.remove(_prefIcon);
    await prefs.remove(_prefDuration);
    await prefs.remove(_prefExpiresAt);
  }

  Future<void> stopAndExit() async {
    positionSub?.cancel();
    expiryTimer?.cancel();
    heartbeatTimer?.cancel();
    await ApiService.stopShare(shareId!);
    await clearPrefs();
    service.invoke('expired');
    if (service is AndroidServiceInstance) {
      await service.stopSelf();
    }
  }

  // Check if already expired
  if (expiresAtMs != null) {
    final expiresAt = DateTime.fromMillisecondsSinceEpoch(expiresAtMs);
    if (expiresAt.isBefore(DateTime.now())) {
      await stopAndExit();
      return;
    }

    final remaining = expiresAt.difference(DateTime.now());
    expiryTimer = Timer(remaining, () => stopAndExit());
  } else if (durationHours > 0) {
    expiryTimer = Timer(Duration(hours: durationHours), () => stopAndExit());
  }

  // Send initial position immediately
  try {
    print('[ShareLiveLoc] Getting initial position...');
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
    );
    print('[ShareLiveLoc] Initial position: ${pos.latitude}, ${pos.longitude}');
    lastPosition = pos;
    await ApiService.updateLocation(shareId, pos.latitude, pos.longitude);
  } catch (e) {
    print('[ShareLiveLoc] Error getting initial position: $e');
  }

  // Heartbeat: send last known position every 30s to keep share alive
  // and detect if API has marked it inactive (cleanup job / expiry)
  heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
    final pos = lastPosition;
    final sid = shareId;
    if (pos == null || sid == null) return;
    final result = await ApiService.updateLocation(
      sid,
      pos.latitude,
      pos.longitude,
    );
    if (result == UpdateLocationResult.inactive) {
      print('[ShareLiveLoc] Heartbeat: share inactive, stopping...');
      await stopAndExit();
    }
  });

  // Start continuous GPS stream
  const locationSettings = LocationSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: 5,
  );

  print('[ShareLiveLoc] Starting GPS stream...');
  positionSub = Geolocator.getPositionStream(locationSettings: locationSettings)
      .listen((Position position) async {
        lastPosition = position;
        if (shareId != null) {
          print(
            '[ShareLiveLoc] Position update: ${position.latitude}, ${position.longitude}',
          );
          final result = await ApiService.updateLocation(
            shareId,
            position.latitude,
            position.longitude,
          );

          // If API says share is inactive (stopped by cleanup/expiry),
          // stop the service and notify UI.
          if (result == UpdateLocationResult.inactive) {
            print('[ShareLiveLoc] Share marked inactive by API, stopping...');
            await stopAndExit();
            return;
          }

          if (service is AndroidServiceInstance) {
            service.setForegroundNotificationInfo(
              title: 'ShareLiveLoc',
              content:
                  'Berbagi lokasi aktif (${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)})',
            );
          }
        }
      });

  // Listen for stop command from UI
  service.on('stopTracking').listen((_) async {
    expiryTimer?.cancel();
    await positionSub?.cancel();

    if (service is AndroidServiceInstance) {
      await service.stopSelf();
    }
  });
}
