class MessageModel {
  final String messageId;
  final String senderId;
  final String senderRole;
  final String receiverId;
  final String receiverRole;
  final String content;
  final DateTime sentAt;
  bool isRead;
  String? senderName;
  String? receiverName;

  MessageModel({
    required this.messageId,
    required this.senderId,
    required this.senderRole,
    required this.receiverId,
    required this.receiverRole,
    required this.content,
    required this.sentAt,
    required this.isRead,
    this.senderName,
    this.receiverName,
  });

  factory MessageModel.fromJson(Map<String, dynamic> json) {
    return MessageModel(
      messageId: json['messageId'] ?? '',
      senderId: json['senderId'] ?? '',
      senderRole: json['senderRole'] ?? '',
      receiverId: json['receiverId'] ?? '',
      receiverRole: json['receiverRole'] ?? '',
      content: json['content'] ?? '',
      sentAt: DateTime.tryParse(json['sentAt'] ?? '') ?? DateTime.now(),
      isRead: json['isRead'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'messageId': messageId,
      'senderId': senderId,
      'senderRole': senderRole,
      'receiverId': receiverId,
      'receiverRole': receiverRole,
      'content': content,
      'sentAt': sentAt.toIso8601String(),
      'isRead': isRead,
    };
  }
}

class ConversationUser {
  final String id;
  final String name;
  final String role;
  final String? email;
  final String? phone;

  ConversationUser({
    required this.id,
    required this.name,
    required this.role,
    this.email,
    this.phone,
  });
}