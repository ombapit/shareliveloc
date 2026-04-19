import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/location_service.dart';
import '../services/user_service.dart';
import '../widgets/group_search_field.dart';

class ShareScreen extends StatefulWidget {
  const ShareScreen({super.key});

  @override
  State<ShareScreen> createState() => _ShareScreenState();
}

class _ShareScreenState extends State<ShareScreen> {
  final _nameController = TextEditingController();
  final _trakteerController = TextEditingController();
  String _selectedIcon = 'bus';
  int _selectedDuration = 1; // 0 = manual
  String _groupName = '';
  bool _isSharing = false;
  bool _isSubmitting = false;
  String? _sharingName;
  String? _sharingGroupName;
  String? _sharingIcon;
  int? _sharingDuration;
  Timer? _countdownTimer;
  Duration _remaining = Duration.zero;
  Key _groupFieldKey = UniqueKey();

  final _iconOptions = [
    {'value': 'bus', 'label': 'Bus', 'emoji': '🚌'},
    {'value': 'car', 'label': 'Mobil Pribadi', 'emoji': '🚗'},
    {'value': 'motorcycle', 'label': 'Motor', 'emoji': '🏍️'},
    {'value': 'person', 'label': 'Orang', 'emoji': '🚶'},
  ];

  @override
  void initState() {
    super.initState();
    _loadSavedTrakteer();
    _restoreSession();
  }

  Future<void> _loadSavedTrakteer() async {
    final saved = await UserService.getTrakteerId();
    if (saved.isNotEmpty && mounted) {
      _trakteerController.text = saved;
    }
  }

  Future<void> _restoreSession() async {
    final session = await LocationService.restoreSession();
    if (session != null && mounted) {
      setState(() {
        _isSharing = true;
        _sharingName = session.name;
        _sharingGroupName = session.groupName;
        _sharingIcon = session.icon;
        _sharingDuration = session.durationHours;
        _selectedDuration = session.durationHours;
      });
      if (session.durationHours > 0 && session.expiresAt != null) {
        _startCountdown();
      }
      LocationService.onExpired = _onExpired;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _trakteerController.dispose();
    _countdownTimer?.cancel();
    super.dispose();
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    final expiresAt = LocationService.expiresAt;
    if (expiresAt == null) return;

    _updateRemaining(expiresAt);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateRemaining(expiresAt);
    });
  }

  void _updateRemaining(DateTime expiresAt) {
    final now = DateTime.now();
    if (now.isAfter(expiresAt)) {
      _countdownTimer?.cancel();
      _onExpired();
      return;
    }
    if (mounted) {
      setState(() => _remaining = expiresAt.difference(now));
    }
  }

  void _onExpired() {
    if (!mounted) return;
    _countdownTimer?.cancel();
    LocationService.onExpired = null;
    setState(() {
      _isSharing = false;
      _nameController.clear();
      _groupName = '';
      _groupFieldKey = UniqueKey();
      _selectedIcon = 'bus';
      _selectedDuration = 1;
    });
    _loadSavedTrakteer();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Waktu berbagi lokasi telah habis'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Future<void> _submit() async {
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nama Shareloc harus diisi')),
      );
      return;
    }
    if (_groupName.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nama Group harus diisi')),
      );
      return;
    }

    final hasPermission = await LocationService.requestPermission(context);
    if (!hasPermission) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Izin GPS diperlukan')),
        );
      }
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final trakteerId = _trakteerController.text.trim();
      // Persist trakteer id for next time
      await UserService.setTrakteerId(trakteerId);

      final shareId = await ApiService.createShare(
        name: _nameController.text.trim(),
        icon: _selectedIcon,
        groupName: _groupName.trim(),
        durationHours: _selectedDuration,
        trakteerId: trakteerId,
      );

      if (shareId != null) {
        LocationService.onExpired = _onExpired;
        await LocationService.saveSession(
          shareId: shareId,
          name: _nameController.text.trim(),
          groupName: _groupName.trim(),
          icon: _selectedIcon,
          durationHours: _selectedDuration,
        );
        await LocationService.startTracking(shareId, _selectedDuration);
        if (mounted) {
          setState(() {
            _isSharing = true;
            _isSubmitting = false;
            _sharingName = _nameController.text.trim();
            _sharingGroupName = _groupName.trim();
            _sharingIcon = _selectedIcon;
            _sharingDuration = _selectedDuration;
          });
          if (_selectedDuration > 0) {
            _startCountdown();
          }
        }
      } else {
        if (mounted) {
          setState(() => _isSubmitting = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Gagal membuat share')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  Future<void> _stop() async {
    _countdownTimer?.cancel();
    LocationService.onExpired = null;
    await LocationService.stopTracking();
    if (mounted) {
      setState(() {
        _isSharing = false;
        _nameController.clear();
        _groupName = '';
        _groupFieldKey = UniqueKey();
        _selectedIcon = 'bus';
        _selectedDuration = 1;
      });
      _loadSavedTrakteer();
    }
  }

  String _emojiForIcon(String icon) {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Share Lokasi')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _isSharing ? _buildSharingView() : _buildFormView(),
      ),
    );
  }

  Widget _buildSharingView() {
    final isManual = _sharingDuration == 0;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            _emojiForIcon(_sharingIcon ?? ''),
            style: const TextStyle(fontSize: 64),
          ),
          const SizedBox(height: 16),
          const Text(
            'Sedang berbagi lokasi...',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (!isManual) ...[
            Text(
              _formatDuration(_remaining),
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                fontFeatures: const [FontFeature.tabularFigures()],
                color: _remaining.inMinutes < 10 ? Colors.red : Colors.blue,
              ),
            ),
            const Text(
              'sisa waktu',
              style: TextStyle(color: Colors.grey),
            ),
          ] else
            const Text(
              'Manual - aktif sampai dihentikan',
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _infoRow('Nama Shareloc', _sharingName ?? ''),
                  const Divider(),
                  _infoRow('Group', _sharingGroupName ?? ''),
                  const Divider(),
                  _infoRow('Icon', _emojiForIcon(_sharingIcon ?? '')),
                  const Divider(),
                  _infoRow('Durasi', isManual ? 'Manual' : '$_sharingDuration jam'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton.icon(
              onPressed: _stop,
              icon: const Icon(Icons.stop, color: Colors.white),
              label: const Text(
                'Berhenti Berbagi',
                style: TextStyle(fontSize: 18, color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildFormView() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Nama Shareloc',
              border: OutlineInputBorder(),
              hintText: 'Masukkan nama shareloc',
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _selectedIcon,
            decoration: const InputDecoration(
              labelText: 'Icon',
              border: OutlineInputBorder(),
            ),
            items: _iconOptions
                .map((opt) => DropdownMenuItem(
                      value: opt['value'],
                      child: Text('${opt['emoji']} ${opt['label']}'),
                    ))
                .toList(),
            onChanged: (val) {
              if (val != null) setState(() => _selectedIcon = val);
            },
          ),
          const SizedBox(height: 16),
          GroupSearchField(
            key: _groupFieldKey,
            onSelected: (group) => setState(() => _groupName = group.name),
            onTextChanged: (text) => setState(() => _groupName = text),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _trakteerController,
            decoration: const InputDecoration(
              labelText: 'Trakteer ID (opsional)',
              border: OutlineInputBorder(),
              hintText: 'username trakteer.id Anda',
              prefixText: 'trakteer.id/',
              helperText: 'Untuk menerima dukungan dari pengguna lain',
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<int>(
            initialValue: _selectedDuration,
            decoration: const InputDecoration(
              labelText: 'Durasi Berbagi',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem(value: 0, child: Text('Manual (tanpa batas)')),
              ...[1, 2, 3, 4, 5, 6, 7, 8].map((h) => DropdownMenuItem(
                    value: h,
                    child: Text('$h jam'),
                  )),
            ],
            onChanged: (val) {
              if (val != null) setState(() => _selectedDuration = val);
            },
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _submit,
              child: _isSubmitting
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Mulai Berbagi Lokasi',
                      style: TextStyle(fontSize: 16),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
