import 'dart:async';
import 'dart:ui';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
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
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(androidChannel);

    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: _onServiceStart,
        autoStart: false,
        isForegroundMode: true,
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

  static Future<bool> requestPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return false;
    }
    if (permission == LocationPermission.deniedForever) return false;

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
    if (_expiresAt != null) {
      await prefs.setInt(_prefExpiresAt, _expiresAt!.millisecondsSinceEpoch);
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
      // Already expired
      if (expiresAt.isBefore(DateTime.now())) {
        await clearSession();
        return null;
      }
    }

    // Restore in-memory state
    _activeShareId = shareId;
    _isTracking = true;
    _expiresAt = expiresAt;

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
    await service.startService();

    service.invoke('startTracking', {
      'shareId': shareId,
      'durationHours': durationHours,
    });

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

  StreamSubscription<Position>? positionSub;
  Timer? expiryTimer;
  int? shareId;

  service.on('startTracking').listen((data) async {
    if (data == null) return;
    shareId = data['shareId'] as int;
    final durationHours = data['durationHours'] as int;

    expiryTimer?.cancel();
    if (durationHours > 0) {
      expiryTimer = Timer(Duration(hours: durationHours), () async {
        positionSub?.cancel();
        await ApiService.stopShare(shareId!);
        service.invoke('expired');

        if (service is AndroidServiceInstance) {
          await service.stopSelf();
        }
      });
    }

    // Send initial position immediately
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );
      if (shareId != null) {
        ApiService.updateLocation(shareId!, pos.latitude, pos.longitude);
      }
    } catch (_) {}

    const locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 5,
    );

    positionSub?.cancel();
    positionSub = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((Position position) {
      if (shareId != null) {
        ApiService.updateLocation(
          shareId!,
          position.latitude,
          position.longitude,
        );

        if (service is AndroidServiceInstance) {
          service.setForegroundNotificationInfo(
            title: 'ShareLiveLoc',
            content:
                'Berbagi lokasi aktif (${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)})',
          );
        }
      }
    });
  });

  service.on('stopTracking').listen((_) async {
    expiryTimer?.cancel();
    await positionSub?.cancel();

    if (service is AndroidServiceInstance) {
      await service.stopSelf();
    }
  });
}
