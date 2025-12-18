/// 公告数据模型
class Announcement {
  final bool enabled;
  final String id;
  final String title;
  final String content;

  const Announcement({
    required this.enabled,
    required this.id,
    required this.title,
    required this.content,
  });

  factory Announcement.fromJson(Map<String, dynamic> json) {
    return Announcement(
      enabled: json['enabled'] as bool? ?? false,
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      content: json['content'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'id': id,
      'title': title,
      'content': content,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Announcement &&
        other.enabled == enabled &&
        other.id == id &&
        other.title == title &&
        other.content == content;
  }

  @override
  int get hashCode {
    return Object.hash(enabled, id, title, content);
  }
}
