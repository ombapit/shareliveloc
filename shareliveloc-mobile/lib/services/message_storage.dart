import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/message.dart';

class MessageStorage {
  static const int _maxPerGroup = 200;

  static String _key(int groupId) => 'chat_messages_$groupId';
  static String _cutoffKey(int groupId) => 'chat_cutoff_$groupId';

  static Future<List<ChatMessage>> load(int groupId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(groupId));
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => ChatMessage.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(int groupId, List<ChatMessage> messages) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = messages.length > _maxPerGroup
        ? messages.sublist(messages.length - _maxPerGroup)
        : messages;
    final json = trimmed
        .map((m) => {
              'id': m.id,
              'group_id': m.groupId,
              'sender_name': m.senderName,
              'content': m.content,
              'created_at': m.createdAt.toIso8601String(),
            })
        .toList();
    await prefs.setString(_key(groupId), jsonEncode(json));
  }

  /// Clears local messages and records the cutoff - future syncs will only
  /// fetch messages with id > cutoff (i.e. new messages from now on).
  static Future<void> clear(int groupId, {int? cutoffId}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(groupId));
    if (cutoffId != null) {
      await prefs.setInt(_cutoffKey(groupId), cutoffId);
    }
  }

  static Future<int?> getCutoff(int groupId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_cutoffKey(groupId));
  }
}
