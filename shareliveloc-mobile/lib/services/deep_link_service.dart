import 'dart:async';
import 'package:app_links/app_links.dart';
import '../config.dart';

class DeepLinkService {
  static final _appLinks = AppLinks();
  static final _groupController = StreamController<String>.broadcast();

  /// Stream of group names from incoming deep links.
  static Stream<String> get onGroup => _groupController.stream;

  /// Last group name captured before any listener attached.
  static String? pendingGroup;

  static Future<void> init() async {
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) _handleUri(initialUri);
    } catch (_) {}

    _appLinks.uriLinkStream.listen(_handleUri, onError: (_) {});
  }

  static void _handleUri(Uri uri) {
    String? name;

    // Custom scheme: shareliveloc://group/<name>
    if (uri.scheme == 'shareliveloc' &&
        uri.host == 'group' &&
        uri.pathSegments.isNotEmpty) {
      name = Uri.decodeComponent(uri.pathSegments.first);
    }

    // HTTPS shareable link: https://.../open?group=<name>
    if ((uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.path == '/open') {
      name = uri.queryParameters['group'];
    }

    if (name == null || name.isEmpty) return;

    pendingGroup = name;
    _groupController.add(name);
  }

  /// Returns a shareable HTTPS link that opens the app via the /open
  /// redirect page on the API host.
  static String buildGroupLink(String groupName) {
    final encoded = Uri.encodeQueryComponent(groupName);
    return '${AppConfig.baseUrl}/open?group=$encoded';
  }

  static void consumePendingGroup() {
    pendingGroup = null;
  }
}
