class LxSourceCandidate {
  final String path;
  final String name;
  final String directory;

  const LxSourceCandidate({
    required this.path,
    required this.name,
    required this.directory,
  });

  factory LxSourceCandidate.fromJson(Map<String, dynamic> json) {
    final path = json['path'];
    final name = json['name'];
    final directory = json['directory'];
    if (path is! String ||
        !isScriptPath(path) ||
        directory is! String ||
        directory !=
            (path.contains('/')
                ? path.substring(0, path.lastIndexOf('/'))
                : '') ||
        name is! String ||
        name.isEmpty) {
      throw const FormatException('音源列表格式无效');
    }
    return LxSourceCandidate(path: path, name: name, directory: directory);
  }

  static bool isScriptPath(String path) {
    final parts = path.split('/');
    return !RegExp(r'[\\\x00-\x1f\x7f]').hasMatch(path) &&
        parts.every((part) => part.isNotEmpty && part != '.' && part != '..') &&
        !parts.first.contains(':') &&
        parts.last.length > 3 &&
        path.toLowerCase().endsWith('.js');
  }

  bool matches({String query = '', String? selectedDirectory}) {
    final inDirectory =
        selectedDirectory == null ||
        directory == selectedDirectory ||
        (selectedDirectory.isNotEmpty &&
            directory.startsWith('$selectedDirectory/'));
    final term = query.trim().toLowerCase();
    return inDirectory &&
        (term.isEmpty ||
            name.toLowerCase().contains(term) ||
            path.toLowerCase().contains(term));
  }

  static List<String> directories(Iterable<LxSourceCandidate> sources) {
    final result = <String>{};
    for (final source in sources) {
      final parts = source.directory.split('/');
      if (source.directory.isEmpty) continue;
      for (var i = 1; i <= parts.length; i++) {
        result.add(parts.take(i).join('/'));
      }
    }
    return result.toList()..sort();
  }
}
