import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/share.dart';
import 'user_location_marker.dart';

class MapWidget extends StatefulWidget {
  final List<ShareLocation> shares;
  final MapController mapController;
  final LatLng? userLocation;
  final int? followedShareId;
  final void Function(ShareLocation share)? onMarkerTap;

  const MapWidget({
    super.key,
    required this.shares,
    required this.mapController,
    this.userLocation,
    this.followedShareId,
    this.onMarkerTap,
  });

  @override
  State<MapWidget> createState() => _MapWidgetState();
}

class _MapWidgetState extends State<MapWidget> with TickerProviderStateMixin {
  /// Currently displayed (possibly animated) position per share id.
  final Map<int, LatLng> _displayed = {};
  final Map<int, AnimationController> _controllers = {};
  // Bearing in radians (0 = north, π/2 = east). Animated toward target bearing.
  final Map<int, double> _bearing = {};
  final Map<int, double> _targetBearing = {};

  static const _animDuration = Duration(milliseconds: 500);
  // Minimum distance (meters) before updating bearing. Filters GPS noise.
  static const _minDistanceForBearing = 3.0;

  @override
  void initState() {
    super.initState();
    for (final s in widget.shares) {
      if (s.latitude != 0 || s.longitude != 0) {
        _displayed[s.id] = LatLng(s.latitude, s.longitude);
      }
    }
  }

  @override
  void didUpdateWidget(MapWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncShares();
  }

  void _syncShares() {
    final currentIds = widget.shares.map((s) => s.id).toSet();

    for (final id in _displayed.keys.toList()) {
      if (!currentIds.contains(id)) {
        _controllers[id]?.dispose();
        _controllers.remove(id);
        _displayed.remove(id);
        _bearing.remove(id);
        _targetBearing.remove(id);
      }
    }

    for (final s in widget.shares) {
      if (s.latitude == 0 && s.longitude == 0) continue;
      final target = LatLng(s.latitude, s.longitude);
      final prev = _displayed[s.id];

      if (prev == null) {
        _displayed[s.id] = target;
        continue;
      }

      if (prev.latitude == target.latitude &&
          prev.longitude == target.longitude) {
        continue;
      }

      // Update bearing only if meaningful movement
      final dist = _distanceMeters(prev, target);
      if (dist >= _minDistanceForBearing) {
        _targetBearing[s.id] = _calcBearing(prev, target);
      }

      _animateTo(s.id, prev, target);
    }
  }

  /// Haversine approximation - good enough for small distances.
  double _distanceMeters(LatLng a, LatLng b) {
    const r = 6371000.0;
    final lat1 = a.latitude * math.pi / 180;
    final lat2 = b.latitude * math.pi / 180;
    final dLat = (b.latitude - a.latitude) * math.pi / 180;
    final dLng = (b.longitude - a.longitude) * math.pi / 180;
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1) * math.cos(lat2) * math.sin(dLng / 2) * math.sin(dLng / 2);
    return 2 * r * math.asin(math.sqrt(h));
  }

  /// Returns bearing in radians: 0 = north, π/2 = east, π = south, 3π/2 = west.
  double _calcBearing(LatLng from, LatLng to) {
    final lat1 = from.latitude * math.pi / 180;
    final lat2 = to.latitude * math.pi / 180;
    final dLng = (to.longitude - from.longitude) * math.pi / 180;
    final y = math.sin(dLng) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLng);
    return math.atan2(y, x);
  }

  /// Interpolate bearing along the shortest arc (handles 2π wrap).
  double _lerpBearing(double a, double b, double t) {
    double diff = b - a;
    while (diff > math.pi) {
      diff -= 2 * math.pi;
    }
    while (diff < -math.pi) {
      diff += 2 * math.pi;
    }
    return a + diff * t;
  }

  void _animateTo(int shareId, LatLng from, LatLng to) {
    _controllers[shareId]?.stop();
    _controllers[shareId]?.dispose();

    final bearingStart = _bearing[shareId] ?? _targetBearing[shareId] ?? 0.0;
    final bearingEnd = _targetBearing[shareId] ?? bearingStart;

    final controller = AnimationController(
      vsync: this,
      duration: _animDuration,
    );
    _controllers[shareId] = controller;

    controller.addListener(() {
      final t = Curves.easeInOut.transform(controller.value);
      final lat = from.latitude + (to.latitude - from.latitude) * t;
      final lng = from.longitude + (to.longitude - from.longitude) * t;
      final br = _lerpBearing(bearingStart, bearingEnd, t);
      if (mounted) {
        setState(() {
          _displayed[shareId] = LatLng(lat, lng);
          _bearing[shareId] = br;
        });
      }
    });

    controller.forward().whenComplete(() {
      if (mounted) {
        setState(() {
          _displayed[shareId] = to;
          _bearing[shareId] = bearingEnd;
        });
      }
    });
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _iconForType(String icon) {
    switch (icon) {
      case 'bus':
        return '🚌';
      case 'car':
        return '🚗';
      case 'motorcycle':
        return '🏍️';
      case 'person':
        return '🚶';
      default:
        return '📍';
    }
  }

  /// Transport/person emojis face LEFT by default in most fonts.
  /// Rotation angle (radians, clockwise) to align with bearing.
  /// - bearing 0 (north) → rotate +π/2 (icon points up)
  /// - bearing π/2 (east) → rotate +π (icon points right)
  double _rotationForIcon(String icon, int shareId) {
    if (icon == 'other') return 0.0;
    final b = _bearing[shareId];
    if (b == null) return 0.0;
    return b + math.pi / 2;
  }

  String? _remainingFor(ShareLocation s) {
    if (s.expiresAt == null) return null;
    final diff = s.expiresAt!.difference(DateTime.now());
    if (diff.isNegative) return null;

    final hours = diff.inHours;
    final minutes = diff.inMinutes.remainder(60);

    if (hours >= 1) {
      if (minutes == 0) {
        return '$hours hour${hours > 1 ? 's' : ''} remaining';
      }
      return '$hours hour${hours > 1 ? 's' : ''} $minutes minute${minutes > 1 ? 's' : ''} remaining';
    }
    final mins = diff.inMinutes < 1 ? 1 : diff.inMinutes;
    return '$mins minute${mins > 1 ? 's' : ''} remaining';
  }

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      mapController: widget.mapController,
      options: const MapOptions(
        initialCenter: LatLng(-6.2088, 106.8456),
        initialZoom: 13.0,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.ombapit.shareliveloc',
        ),
        if (widget.userLocation != null)
          MarkerLayer(
            markers: [
              Marker(
                point: widget.userLocation!,
                width: 80,
                height: 80,
                child: const UserLocationMarker(),
              ),
            ],
          ),
        MarkerLayer(
          markers: widget.shares.where((s) => _displayed[s.id] != null).map((s) {
            final remaining = _remainingFor(s);
            final isFollowed = widget.followedShareId == s.id;
            final pos = _displayed[s.id]!;
            final rotation = _rotationForIcon(s.icon, s.id);
            return Marker(
              point: pos,
              width: 120,
              height: remaining != null ? 78 : 60,
              child: GestureDetector(
                onTap: () => widget.onMarkerTap?.call(s),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Transform.rotate(
                      angle: rotation,
                      child: Text(
                        _iconForType(s.icon),
                        style: const TextStyle(fontSize: 28),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: isFollowed
                            ? const Color(0xFF4285F4)
                            : Colors.white.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(4),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 2,
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            s.name,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: isFollowed ? Colors.white : Colors.black,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (remaining != null)
                            Text(
                              remaining,
                              style: TextStyle(
                                fontSize: 9,
                                color: isFollowed
                                    ? Colors.white70
                                    : Colors.grey,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
