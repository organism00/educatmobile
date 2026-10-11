class TeacherNote {
  final String id;
  String title;
  String content;
  String category;      // Auto-detected
  List<String> tags;    // Auto-extracted
  DateTime createdAt;
  DateTime updatedAt;
  bool isPinned;
  bool isCompleted;

  TeacherNote({
    required this.id,
    required this.title,
    required this.content,
    required this.category,
    required this.tags,
    required this.createdAt,
    required this.updatedAt,
    this.isPinned = false,
    this.isCompleted = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'content': content,
    'category': category,
    'tags': tags,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'isPinned': isPinned,
    'isCompleted': isCompleted,
  };

  factory TeacherNote.fromJson(Map<String, dynamic> json) {
    return TeacherNote(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      content: json['content'] ?? '',
      category: json['category'] ?? 'General',
      tags: List<String>.from(json['tags'] ?? []),
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updatedAt'] ?? '') ?? DateTime.now(),
      isPinned: json['isPinned'] ?? false,
      isCompleted: json['isCompleted'] ?? false,
    );
  }
}