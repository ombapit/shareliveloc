import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config.dart';

class WebSocketService {
  WebSocketChannel? _channel;
  Function(Map<String, dynamic>)? onMessage;

  void connect(int groupId) {
    disconnect();
    _channel = WebSocketChannel.connect(
      Uri.parse('${AppConfig.wsUrl}/ws/location/$groupId'),
    );
    _channel!.stream.listen(
      (data) {
        final msg = jsonDecode(data as String) as Map<String, dynamic>;
        onMessage?.call(msg);
      },
      onError: (_) {},
      onDone: () {},
    );
  }

  void send(Map<String, dynamic> data) {
    _channel?.sink.add(jsonEncode(data));
  }

  void disconnect() {
    _channel?.sink.close();
    _channel = null;
  }
}
