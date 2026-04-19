class ShareLocation {
  final int id;
  final String name;
  final String icon;
  final int groupId;
  final double latitude;
  final double longitude;
  final int durationHours;
  final DateTime? expiresAt;
  final String trakteerId;
  final bool isActive;

  ShareLocation({
    required this.id,
    required this.name,
    required this.icon,
    required this.groupId,
    required this.latitude,
    required this.longitude,
    required this.durationHours,
    required this.expiresAt,
    required this.trakteerId,
    required this.isActive,
  });

  factory ShareLocation.fromJson(Map<String, dynamic> json) {
    DateTime? expires;
    final expStr = json['expires_at'];
    if (expStr is String && expStr.isNotEmpty) {
      expires = DateTime.tryParse(expStr);
      if (expires != null && expires.year < 2000) {
        expires = null;
      }
    }
    return ShareLocation(
      id: json['id'] as int,
      name: json['name'] as String,
      icon: json['icon'] as String,
      groupId: json['group_id'] as int,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      durationHours: (json['duration_hours'] as int?) ?? 0,
      expiresAt: expires,
      trakteerId: (json['trakteer_id'] as String?) ?? '',
      isActive: json['is_active'] as bool,
    );
  }
}
