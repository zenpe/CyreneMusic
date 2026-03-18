Map<String, String>? getImageHeaders(String? url) {
  if (url == null || url.isEmpty) return null;

  final uri = Uri.tryParse(url);
  final scheme = uri?.scheme.toLowerCase();
  if (scheme != 'http' && scheme != 'https') return null;

  final host = (uri?.host ?? '').toLowerCase();
  final headers = <String, String>{
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36',
  };

  if (host.contains('126.net') ||
      host == 'music.163.com' ||
      host.endsWith('.163.com')) {
    headers['User-Agent'] =
        'NeteaseMusic/9.0.50 (iPhone; iOS 16.3.1; Scale/3.00)';
    return headers;
  }

  if (host.contains('qq.com') ||
      host.contains('gtimg.cn') ||
      host.contains('qqmusic')) {
    headers['Referer'] = 'https://y.qq.com/';
    headers['Origin'] = 'https://y.qq.com';
    return headers;
  }

  if (host.contains('kugou') || host.contains('kgimg')) {
    headers['Referer'] = 'https://www.kugou.com/';
    headers['Origin'] = 'https://www.kugou.com';
    return headers;
  }

  return headers;
}
