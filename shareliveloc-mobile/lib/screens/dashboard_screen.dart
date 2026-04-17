import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:latlong2/latlong.dart';
import '../models/group.dart';
import '../models/share.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../services/websocket_service.dart';
import '../widgets/group_search_field.dart';
import '../widgets/map_widget.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final MapController _mapController = MapController();
  final WebSocketService _wsService = WebSocketService();
  List<ShareLocation> _shares = [];
  Group? _selectedGroup;
  bool _isLoading = false;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  Timer? _labelTimer;
  bool _wasOffline = false;

  // Ads
  BannerAd? _bannerAd;
  bool _isAdLoaded = false;
  bool _adsEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadAdConfig();
    _listenConnectivity();
    // Rebuild every 15s to refresh "X minute remaining" labels
    // and remove expired shares client-side (API cleanup may lag up to 1 min)
    _labelTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted) return;
      final now = DateTime.now();
      final hasExpired = _shares.any(
        (s) => s.expiresAt != null && s.expiresAt!.isBefore(now),
      );
      if (hasExpired) {
        setState(() {
          _shares.removeWhere(
            (s) => s.expiresAt != null && s.expiresAt!.isBefore(now),
          );
        });
        _fitBounds();
      } else if (_shares.any((s) => s.expiresAt != null)) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _wsService.disconnect();
    _connectivitySub?.cancel();
    _labelTimer?.cancel();
    _mapController.dispose();
    _bannerAd?.dispose();
    super.dispose();
  }

  void _listenConnectivity() {
    _connectivitySub =
        Connectivity().onConnectivityChanged.listen((results) {
      final hasNetwork = results.any((r) => r != ConnectivityResult.none);
      if (!hasNetwork) {
        _wasOffline = true;
      } else if (_wasOffline) {
        _wasOffline = false;
        // Reconnect WebSocket and re-fetch shares to sync state
        if (_selectedGroup != null) {
          _wsService.connect(_selectedGroup!.id);
          _wsService.onMessage = _onWsMessage;
          _loadShares(_selectedGroup!.id);
        }
      }
    });
  }

  Future<void> _loadAdConfig() async {
    try {
      final configs = await ApiService.getConfigs();
      final adsEnabled = configs['ads_enabled'] == 'true';
      final bannerId = configs['ads_banner_id'] ?? '';

      if (adsEnabled && bannerId.isNotEmpty && mounted) {
        setState(() => _adsEnabled = true);
        await MobileAds.instance.initialize();
        _loadBannerAd(bannerId);
      }
    } catch (_) {}
  }

  void _loadBannerAd(String adUnitId) {
    _bannerAd = BannerAd(
      adUnitId: adUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _isAdLoaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (mounted) setState(() => _isAdLoaded = false);
        },
      ),
    )..load();
  }

  void _onGroupSelected(Group group) {
    setState(() {
      _selectedGroup = group;
      _isLoading = true;
    });
    _loadShares(group.id);
    _wsService.connect(group.id);
    _wsService.onMessage = _onWsMessage;
  }

  Future<void> _loadShares(int groupId) async {
    try {
      final shares = await ApiService.getShares(groupId);
      if (mounted) {
        setState(() {
          _shares = shares;
          _isLoading = false;
        });
        _fitBounds();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Gagal memuat data lokasi')),
        );
      }
    }
  }

  void _onWsMessage(Map<String, dynamic> msg) {
    final shareId = msg['share_id'] as int;
    final isActive = msg['is_active'] as bool;

    setState(() {
      if (!isActive) {
        final removed = _shares.any((s) => s.id == shareId);
        _shares.removeWhere((s) => s.id == shareId);
        if (removed) _fitBounds();
      } else {
        final lat = (msg['latitude'] as num).toDouble();
        final lng = (msg['longitude'] as num).toDouble();
        final name = msg['name'] as String;
        final icon = msg['icon'] as String;
        final durationHours = (msg['duration_hours'] as int?) ?? 0;
        DateTime? expiresAt;
        final expStr = msg['expires_at'];
        if (expStr is String && expStr.isNotEmpty) {
          expiresAt = DateTime.tryParse(expStr);
        }

        final idx = _shares.indexWhere((s) => s.id == shareId);
        final updated = ShareLocation(
          id: shareId,
          name: name,
          icon: icon,
          groupId: _selectedGroup?.id ?? 0,
          latitude: lat,
          longitude: lng,
          durationHours: durationHours,
          expiresAt: expiresAt,
          isActive: true,
        );
        if (idx >= 0) {
          final prev = _shares[idx];
          final wasInvalid = prev.latitude == 0 && prev.longitude == 0;
          final isNowValid = lat != 0 && lng != 0;
          _shares[idx] = updated;
          if (wasInvalid && isNowValid) {
            _fitBounds();
          }
        } else {
          _shares.add(updated);
          if (lat != 0 && lng != 0) {
            _fitBounds();
          }
        }
      }
    });
  }

  void _fitBounds() {
    _mapController.rotate(0);
    final validShares = _shares
        .where((s) => s.latitude != 0 && s.longitude != 0)
        .toList();
    if (validShares.isEmpty) {
      _centerOnUser();
      return;
    }
    if (validShares.length == 1) {
      _mapController.move(
        LatLng(validShares[0].latitude, validShares[0].longitude),
        15.0,
      );
      return;
    }
    final bounds = LatLngBounds.fromPoints(
      validShares.map((s) => LatLng(s.latitude, s.longitude)).toList(),
    );
    _mapController.fitCamera(
      CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.all(50)),
    );
  }

  Future<void> _centerOnUser() async {
    _mapController.rotate(0);
    final pos = await LocationService.getCurrentPosition();
    if (pos != null && mounted) {
      _mapController.move(LatLng(pos.latitude, pos.longitude), 14.0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Share Live Location')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: GroupSearchField(
              onSelected: _onGroupSelected,
              activeOnly: true,
            ),
          ),
          if (_selectedGroup != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  const Icon(Icons.group, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    'Grup: ${_selectedGroup!.name}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  Text('${_shares.length} aktif'),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: Stack(
              children: [
                MapWidget(shares: _shares, mapController: _mapController),
                if (_isLoading)
                  const Center(child: CircularProgressIndicator()),
                Positioned(
                  right: 16,
                  bottom: (_adsEnabled && _isAdLoaded) ? 116 : 66,
                  child: FloatingActionButton.small(
                    heroTag: 'refreshBtn',
                    onPressed: _selectedGroup != null
                        ? () => _loadShares(_selectedGroup!.id)
                        : null,
                    child: const Icon(Icons.refresh),
                  ),
                ),
                Positioned(
                  right: 16,
                  bottom: (_adsEnabled && _isAdLoaded) ? 66 : 16,
                  child: FloatingActionButton.small(
                    heroTag: 'centerBtn',
                    onPressed: _centerOnUser,
                    child: const Icon(Icons.my_location),
                  ),
                ),
              ],
            ),
          ),
          if (_adsEnabled && _isAdLoaded && _bannerAd != null)
            SizedBox(
              width: _bannerAd!.size.width.toDouble(),
              height: _bannerAd!.size.height.toDouble(),
              child: AdWidget(ad: _bannerAd!),
            ),
        ],
      ),
    );
  }
}
