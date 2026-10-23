import 'package:flutter/foundation.dart';
import 'api/api_client.dart';

class NeteaseAlbumService extends ChangeNotifier {
  static final NeteaseAlbumService _instance = NeteaseAlbumService._internal();
  factory NeteaseAlbumService() => _instance;
  NeteaseAlbumService._internal();

  Future<Map<String, dynamic>?> fetchAlbumDetail(int id) async {
    try {
      final result = await ApiClient().getJson(
        '/album',
        queryParameters: {'id': id},
        timeout: const Duration(seconds: 12),
      );
      if (!result.ok) return null;
      final data = result.data as Map<String, dynamic>?;
      if (data == null || data['status'] != 200) return null;
      return data['data'] as Map<String, dynamic>;
    } catch (e) {
      return null;
    }
  }
}
