class ChatMessage {
  final int id;
  final int groupId;
  final String senderName;
  final String content;
  final DateTime createdAt;

  ChatMessage({
    required this.id,
    required this.groupId,
    required this.senderName,
    required this.content,
    required this.createdAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] as int,
      groupId: json['group_id'] as int,
      senderName: json['sender_name'] as String,
      content: json['content'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  factory ChatMessage.fromWsBroadcast(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['message_id'] as int,
      groupId: json['group_id'] as int,
      senderName: json['sender_name'] as String,
      content: json['content'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
