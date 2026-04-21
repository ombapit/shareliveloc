import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/deep_link_service.dart';
import '../models/group.dart';
import '../models/share.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../services/websocket_service.dart';
import '../widgets/group_search_field.dart';
import '../widgets/map_widget.dart';
import 'chat_screen.dart';

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
  StreamSubscription<Position>? _userLocationSub;
  StreamSubscription<String>? _deepLinkSub;
  Timer? _labelTimer;
  bool _wasOffline = false;
  LatLng? _userLocation;
  bool _gpsActive = false;
  int? _followedShareId;

  // Ads
  BannerAd? _bannerAd;
  bool _isAdLoaded = false;
  bool _adsEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadAdConfig();
    _listenConnectivity();
    _listenDeepLinks();
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
    _userLocationSub?.cancel();
    _deepLinkSub?.cancel();
    _labelTimer?.cancel();
    _mapController.dispose();
    _bannerAd?.dispose();
    super.dispose();
  }

  void _listenDeepLinks() {
    // Handle pending group captured before this screen was ready
    final pending = DeepLinkService.pendingGroup;
    if (pending != null) {
      DeepLinkService.consumePendingGroup();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _selectGroupByName(pending);
      });
    }
    _deepLinkSub = DeepLinkService.onGroup.listen((name) {
      _selectGroupByName(name);
    });
  }

  Future<void> _selectGroupByName(String name) async {
    try {
      final groups = await ApiService.getGroups(search: name);
      final match = groups.firstWhere(
        (g) => g.name.toLowerCase() == name.toLowerCase(),
        orElse: () => Group(id: -1, name: ''),
      );
      if (match.id <= 0) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Grup "$name" tidak ditemukan')),
          );
        }
        return;
      }
      _onGroupSelected(match);
    } catch (_) {}
  }

  void _shareGroupLink() {
    if (_selectedGroup == null) return;
    final link = DeepLinkService.buildGroupLink(_selectedGroup!.name);
    Share.share(
      'Bergabung ke grup "${_selectedGroup!.name}" di ShareLiveLoc:\n$link',
      subject: 'ShareLiveLoc - Grup ${_selectedGroup!.name}',
    );
  }

  Future<void> _toggleGps() async {
    if (_gpsActive) {
      // Turn off
      await _userLocationSub?.cancel();
      _userLocationSub = null;
      setState(() {
        _gpsActive = false;
        _userLocation = null;
      });
      return;
    }

    // Turn on - check permission + start stream
    final hasPermission = await LocationService.requestPermission(context);
    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Izin GPS diperlukan')),
        );
      }
      return;
    }

    _userLocationSub = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 2,
      ),
    ).listen((pos) {
      if (!mounted) return;
      setState(() {
        _userLocation = LatLng(pos.latitude, pos.longitude);
      });
    });

    // Also center on user immediately
    _mapController.rotate(0);
    final pos = await LocationService.getCurrentPosition();
    if (pos != null && mounted) {
      setState(() {
        _gpsActive = true;
        _userLocation = LatLng(pos.latitude, pos.longitude);
      });
      _mapController.move(LatLng(pos.latitude, pos.longitude), 15.0);
    } else {
      setState(() => _gpsActive = true);
    }
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

  void _showMarkerPopup(ShareLocation share) {
    final isFollowing = _followedShareId == share.id;
    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text(
                      _emojiFor(share.icon),
                      style: const TextStyle(fontSize: 32),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            share.name,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (share.expiresAt != null)
                            Text(
                              _remainingText(share.expiresAt!),
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 13,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _toggleFollow(share);
                    },
                    icon: Icon(isFollowing
                        ? Icons.location_off
                        : Icons.navigation),
                    label: Text(
                      isFollowing ? 'Berhenti Ikuti' : 'Ikuti',
                      style: const TextStyle(fontSize: 16),
                    ),
                    style: isFollowing
                        ? FilledButton.styleFrom(
                            backgroundColor: Colors.red,
                          )
                        : null,
                  ),
                ),
                if (share.trakteerId.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildTrakteerCard(share.trakteerId),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTrakteerCard(String trakteerId) {
    final url = 'https://trakteer.id/$trakteerId';
    return Card(
      elevation: 0,
      color: const Color(0xFFFFF3E0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.orange.shade300),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () async {
          final uri = Uri.parse(url);
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Icon(
                Icons.favorite,
                color: Colors.orange,
                size: 28,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Dukung via Trakteer',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'trakteer.id/$trakteerId',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange.shade900,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.open_in_new,
                size: 18,
                color: Colors.orange.shade900,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _toggleFollow(ShareLocation share) {
    if (_followedShareId == share.id) {
      setState(() => _followedShareId = null);
      _fitBounds();
    } else {
      setState(() => _followedShareId = share.id);
      _mapController.rotate(0);
      _mapController.move(
        LatLng(share.latitude, share.longitude),
        _mapController.camera.zoom,
      );
    }
  }

  String _emojiFor(String icon) {
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

  String _remainingText(DateTime expiresAt) {
    final diff = expiresAt.difference(DateTime.now());
    if (diff.isNegative) return 'Expired';
    final h = diff.inHours;
    final m = diff.inMinutes.remainder(60);
    if (h >= 1) {
      return m == 0
          ? '$h hour${h > 1 ? 's' : ''} remaining'
          : '$h hour${h > 1 ? 's' : ''} $m minute${m > 1 ? 's' : ''} remaining';
    }
    final mins = diff.inMinutes < 1 ? 1 : diff.inMinutes;
    return '$mins minute${mins > 1 ? 's' : ''} remaining';
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
    // Dashboard only handles location broadcasts; chat handled by ChatScreen
    if (msg['type'] != null && msg['type'] != 'location') return;
    final shareId = msg['share_id'] as int;
    final isActive = msg['is_active'] as bool;

    setState(() {
      if (!isActive) {
        final removed = _shares.any((s) => s.id == shareId);
        _shares.removeWhere((s) => s.id == shareId);
        if (_followedShareId == shareId) {
          _followedShareId = null;
        }
        if (removed) _fitBounds();
      } else {
        final lat = (msg['latitude'] as num).toDouble();
        final lng = (msg['longitude'] as num).toDouble();
        final name = msg['name'] as String;
        final icon = msg['icon'] as String;
        final durationHours = (msg['duration_hours'] as int?) ?? 0;
        final trakteerId = (msg['trakteer_id'] as String?) ?? '';
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
          trakteerId: trakteerId,
          isActive: true,
        );
        if (idx >= 0) {
          final prev = _shares[idx];
          final wasInvalid = prev.latitude == 0 && prev.longitude == 0;
          final isNowValid = lat != 0 && lng != 0;
          _shares[idx] = updated;
          // If following this share, track its new position (keep current zoom)
          if (_followedShareId == shareId && isNowValid) {
            _mapController.move(LatLng(lat, lng), _mapController.camera.zoom);
          } else if (wasInvalid && isNowValid && _followedShareId == null) {
            _fitBounds();
          }
        } else {
          _shares.add(updated);
          // Only fit bounds when NOT following any marker
          if (lat != 0 && lng != 0 && _followedShareId == null) {
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
                  Expanded(
                    child: Text(
                      'Grup: ${_selectedGroup!.name}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chat_bubble_outline),
                    tooltip: 'Chat Grup',
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              ChatScreen(group: _selectedGroup!),
                        ),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.share_outlined),
                    tooltip: 'Bagikan Link Grup',
                    visualDensity: VisualDensity.compact,
                    onPressed: _shareGroupLink,
                  ),
                  Text('${_shares.length} aktif'),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: Stack(
              children: [
                MapWidget(
                  shares: _shares,
                  mapController: _mapController,
                  userLocation: _userLocation,
                  followedShareId: _followedShareId,
                  onMarkerTap: _showMarkerPopup,
                ),
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
                    onPressed: _toggleGps,
                    backgroundColor: _gpsActive
                        ? const Color(0xFF4285F4)
                        : null,
                    foregroundColor: _gpsActive ? Colors.white : null,
                    child: Icon(
                      _gpsActive ? Icons.my_location : Icons.location_searching,
                    ),
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
