import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../models/share.dart';

class MapWidget extends StatelessWidget {
  final List<ShareLocation> shares;
  final MapController mapController;

  const MapWidget({
    super.key,
    required this.shares,
    required this.mapController,
  });

  String _iconForType(String icon) {
    switch (icon) {
      case 'bus':
        return '🚌';
      case 'car':
        return '🚗';
      case 'person':
        return '🚶';
      default:
        return '📍';
    }
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
        MarkerLayer(
          markers: shares
              .where((s) => s.latitude != 0 && s.longitude != 0)
              .map((s) => Marker(
                    point: LatLng(s.latitude, s.longitude),
                    width: 80,
                    height: 60,
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
                            color: Colors.white.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(4),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 2,
                              ),
                            ],
                          ),
                          child: Text(
                            s.name,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ))
              .toList(),
        ),
      ],
    );
  }
}
