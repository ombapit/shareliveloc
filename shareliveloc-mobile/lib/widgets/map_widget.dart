import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/share.dart';
import 'user_location_marker.dart';

class MapWidget extends StatelessWidget {
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
      mapController: mapController,
      options: const MapOptions(
        initialCenter: LatLng(-6.2088, 106.8456),
        initialZoom: 13.0,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.ombapit.shareliveloc',
        ),
        if (userLocation != null)
          MarkerLayer(
            markers: [
              Marker(
                point: userLocation!,
                width: 80,
                height: 80,
                child: const UserLocationMarker(),
              ),
            ],
          ),
        MarkerLayer(
          markers: shares
              .where((s) => s.latitude != 0 && s.longitude != 0)
              .map((s) {
            final remaining = _remainingFor(s);
            final isFollowed = followedShareId == s.id;
            return Marker(
              point: LatLng(s.latitude, s.longitude),
              width: 120,
              height: remaining != null ? 78 : 60,
              child: GestureDetector(
                onTap: () => onMarkerTap?.call(s),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _iconForType(s.icon),
                      style: const TextStyle(fontSize: 28),
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
