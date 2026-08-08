class AIMessage {
  final String id;
  final String text;
  final bool isUser; // true: người dùng, false: AI
  final DateTime timestamp;

  AIMessage({
    required this.id,
    required this.text,
    required this.isUser,
    required this.timestamp,
  });
}
