import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../models/group.dart';
import '../models/share.dart';

enum UpdateLocationResult { success, inactive, error }

class ApiService {
  static Future<List<Group>> getGroups({String search = '', bool activeOnly = false}) async {
    final params = <String, String>{};
    if (search.isNotEmpty) params['search'] = search;
    if (activeOnly) params['active_only'] = 'true';
    final uri = Uri.parse('${AppConfig.baseUrl}/api/groups').replace(
      queryParameters: params.isNotEmpty ? params : null,
    );
    final response = await http.get(uri);
    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      final list = body['data'] as List;
      return list.map((e) => Group.fromJson(e)).toList();
    }
    return [];
  }

  static Future<int?> createShare({
    required String name,
    required String icon,
    required String groupName,
    required int durationHours,
  }) async {
    final response = await http.post(
      Uri.parse('${AppConfig.baseUrl}/api/shares'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': name,
        'icon': icon,
        'group_name': groupName,
        'duration_hours': durationHours,
      }),
    );
    if (response.statusCode == 201) {
      final body = jsonDecode(response.body);
      return body['data']['id'] as int;
    }
    return null;
  }

  static Future<UpdateLocationResult> updateLocation(
      int shareId, double lat, double lng) async {
    try {
      final response = await http.put(
        Uri.parse('${AppConfig.baseUrl}/api/shares/$shareId/location'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'latitude': lat, 'longitude': lng}),
      );
      if (response.statusCode == 200) return UpdateLocationResult.success;
      if (response.statusCode == 400 || response.statusCode == 404) {
        return UpdateLocationResult.inactive;
      }
      return UpdateLocationResult.error;
    } catch (_) {
      return UpdateLocationResult.error;
    }
  }

  /// Returns true if active, false if inactive, null if network error.
  static Future<bool?> getShareStatus(int shareId) async {
    try {
      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/shares/$shareId'),
      );
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        return body['data']['is_active'] as bool;
      }
      if (response.statusCode == 404) return false;
    } catch (_) {}
    return null;
  }

  static Future<bool> stopShare(int shareId) async {
    final response = await http.put(
      Uri.parse('${AppConfig.baseUrl}/api/shares/$shareId/stop'),
    );
    return response.statusCode == 200;
  }

  static Future<List<ShareLocation>> getShares(int groupId) async {
    final response = await http.get(
      Uri.parse('${AppConfig.baseUrl}/api/shares?group_id=$groupId'),
    );
    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      final list = body['data'] as List;
      return list.map((e) => ShareLocation.fromJson(e)).toList();
    }
    return [];
  }

  static Future<Map<String, String>> getConfigs() async {
    try {
      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/config'),
      );
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        final data = body['data'] as Map<String, dynamic>;
        return data.map((k, v) => MapEntry(k, v.toString()));
      }
    } catch (_) {}
    return {};
  }
}
