class LxSourceCandidate {
  final String id;
  final String name;
  final String url;

  const LxSourceCandidate({
    required this.id,
    required this.name,
    required this.url,
  });

  factory LxSourceCandidate.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    final url = json['url'];
    final uri = url is String ? Uri.tryParse(url) : null;
    if (id is! String ||
        id.isEmpty ||
        name is! String ||
        name.isEmpty ||
        uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'https' && uri.scheme != 'http')) {
      throw const FormatException('音源列表格式无效');
    }
    return LxSourceCandidate(id: id, name: name, url: uri.toString());
  }
}
