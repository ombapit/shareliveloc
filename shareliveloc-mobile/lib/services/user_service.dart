import 'package:shared_preferences/shared_preferences.dart';

class UserService {
  static const _prefChatName = 'chat_user_name';
  static const _prefTrakteerId = 'trakteer_id';

  static Future<String?> getName() async {
    final prefs = await SharedPreferences.getInstance();
    final name = prefs.getString(_prefChatName);
    if (name == null || name.trim().isEmpty) return null;
    return name;
  }

  static Future<void> setName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefChatName, name.trim());
  }

  static Future<String> getTrakteerId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefTrakteerId) ?? '';
  }

  static Future<void> setTrakteerId(String trakteerId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefTrakteerId, trakteerId.trim());
  }
}
