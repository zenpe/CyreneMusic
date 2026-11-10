import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/track.dart';
import 'api/api_client.dart';
import 'api/auth_token_store.dart';
import 'url_service.dart';

typedef MetadataFetcher = Future<Map<String, dynamic>?> Function(String id);

/// Optional presentation data. Never resolves audio or changes track identity.
class TrackMetadataService extends ChangeNotifier {
  static final _instance = TrackMetadataService._();
  factory TrackMetadataService() => _instance;

  TrackMetadataService._()
    : this.forTesting(
        origin: () => UrlService().baseUrl,
        session: () => AuthTokenStore.token == null
            ? null
            : '${UrlService().backendRevision}:${AuthTokenStore.token}',
        fetch: _fetchQQ,
      );

  @visibleForTesting
  TrackMetadataService.forTesting({
    required this._origin,
    required this._fetch,
    String? Function()? session,
    DateTime Function()? now,
  }) : _session = session ?? (() => ''),
       _now = now ?? DateTime.now;

  static const _storageKey = 'track_metadata_v1';
  static const _maxEntries = 300;
  static const _ttl = Duration(days: 7);
  static const _cooldown = Duration(minutes: 15);
  final String Function() _origin;
  final String? Function() _session;
  final MetadataFetcher _fetch;
  final DateTime Function() _now;
  final _cache = <String, Map<String, dynamic>>{};
  final _retryAfter = <String, DateTime>{};
  final _pending = <String, Future<void>>{};
  final _waiters = Queue<Completer<void>>();
  int _running = 0;
  Future<void>? _loaded;
  Future<void> _writes = Future.value();

  static bool missingText(String value) =>
      value.trim().isEmpty || value.trim().toLowerCase() == 'unknown';

  static bool missingCover(String value) {
    if (value.trim().isEmpty) return true;
    final uri = Uri.tryParse(value);
    return uri?.host == 'y.qq.com' &&
        uri?.path == '/mediastyle/global/img/album_300.png';
  }

  static bool needsMetadata(Track track) =>
      track.source == MusicSource.qq &&
      (missingText(track.album) || missingCover(track.picUrl));

  String _key(Track track, String origin) => sha256
      .convert(utf8.encode('$origin\n${track.source.name}\n${track.id}'))
      .toString();

  Track cached(Track track) {
    final entry = _cache[_key(track, _origin())];
    if (entry == null ||
        _now().millisecondsSinceEpoch - (entry['savedAt'] as int) >
            _ttl.inMilliseconds) {
      return track;
    }
    return _merge(track, entry);
  }

  static Track _merge(Track track, Map<String, dynamic> info) {
    String fill(String current, String key, bool missing) {
      final value = info[key];
      return missing && value is String && !missingText(value)
          ? value
          : current;
    }

    final album = fill(track.album, 'album', missingText(track.album));
    final pic = info['pic'] is String ? info['pic'] as String : '';
    final uri = Uri.tryParse(pic);
    final cover =
        missingCover(track.picUrl) &&
            uri != null &&
            const ['http', 'https'].contains(uri.scheme) &&
            uri.host.isNotEmpty &&
            !missingCover(pic)
        ? pic
        : track.picUrl;
    if (album == track.album && cover == track.picUrl) return track;
    return Track(
      id: track.id,
      name: track.name,
      artists: track.artists,
      album: album,
      picUrl: cover,
      source: track.source,
      sourceIds: track.sourceIds,
    );
  }

  Future<Track> complete(Track track) async {
    if (!needsMetadata(track)) return track;
    final origin = _origin();
    final session = _session();
    await (_loaded ??= _load());
    if (origin != _origin() || session != _session()) return track;
    final key = _key(track, origin);
    final existing = cached(track);
    if (!needsMetadata(existing)) return existing;
    if (session == null) return existing;
    if (!_pending.containsKey(key) &&
        _retryAfter[key]?.isAfter(_now()) == true) {
      return existing;
    }
    final task = _pending.putIfAbsent(
      key,
      () => _resolve(track, key, origin, session),
    );
    try {
      await task;
    } finally {
      if (identical(_pending[key], task)) _pending.remove(key);
    }
    return origin == _origin() && session == _session() ? cached(track) : track;
  }

  Future<void> _resolve(
    Track track,
    String key,
    String origin,
    String? session,
  ) async {
    if (_running >= 2) {
      final waiter = Completer<void>();
      _waiters.add(waiter);
      await waiter.future;
    } else {
      _running++;
    }
    try {
      if (origin != _origin() || session != _session()) return;
      _retryAfter[key] = _now().add(_cooldown);
      while (_retryAfter.length > _maxEntries) {
        _retryAfter.remove(_retryAfter.keys.first);
      }
      final info = await _fetch(track.id.toString());
      if (info == null || origin != _origin() || session != _session()) return;
      // QQ may accept a numeric ID, but must return the same requested song.
      if (info['mid']?.toString() != track.id.toString() &&
          info['id']?.toString() != track.id.toString()) {
        return;
      }
      final entry = <String, dynamic>{
        'album': info['album'] is String ? info['album'] : '',
        'pic': info['pic'] is String ? info['pic'] : '',
        'savedAt': _now().millisecondsSinceEpoch,
      };
      if (identical(_merge(track, entry), track)) return;
      _cache.remove(key);
      _cache[key] = entry;
      while (_cache.length > _maxEntries) {
        _cache.remove(_cache.keys.first);
      }
      notifyListeners();
      _writes = _writes.then((_) => _save()).catchError((Object _) {});
      await _writes;
    } catch (_) {
      // Metadata is optional; a failed lookup must never break playback/listing.
    } finally {
      if (_waiters.isNotEmpty) {
        _waiters.removeFirst().complete();
      } else {
        _running--;
      }
    }
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null) return;
      final entries = jsonDecode(raw);
      if (entries is! Map) return;
      for (final item in entries.entries.take(_maxEntries)) {
        final value = item.value;
        if (item.key is String && value is Map && value['savedAt'] is int) {
          _cache[item.key as String] = Map<String, dynamic>.from(value);
        }
      }
      if (_cache.isNotEmpty) notifyListeners();
    } catch (_) {}
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(_cache));
  }

  static Future<Map<String, dynamic>?> _fetchQQ(String id) async {
    final result = await ApiClient().getJson(
      '/qq/song',
      queryParameters: {'ids': id, 'metadata_only': '1'},
      timeout: const Duration(seconds: 6),
    );
    final data = result.data;
    if (!result.ok || data is! Map || data['status'] != 200) return null;
    final song = data['song'];
    return song is Map ? Map<String, dynamic>.from(song) : null;
  }
}
