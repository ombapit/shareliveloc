class ShareLocation {
  final int id;
  final String name;
  final String icon;
  final int groupId;
  final double latitude;
  final double longitude;
  final bool isActive;

  ShareLocation({
    required this.id,
    required this.name,
    required this.icon,
    required this.groupId,
    required this.latitude,
    required this.longitude,
    required this.isActive,
  });

  factory ShareLocation.fromJson(Map<String, dynamic> json) {
    return ShareLocation(
      id: json['id'] as int,
      name: json['name'] as String,
      icon: json['icon'] as String,
      groupId: json['group_id'] as int,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      isActive: json['is_active'] as bool,
    );
  }
}
