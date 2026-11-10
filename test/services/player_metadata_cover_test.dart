import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cyrene_music/models/track.dart';
import 'package:cyrene_music/models/song_detail.dart';
import 'package:cyrene_music/services/player_service.dart';
import 'package:cyrene_music/services/track_metadata_service.dart';
import 'package:cyrene_music/services/playback/cover_manager.dart';
import 'package:cyrene_music/services/playback/playback_service.dart';
import 'package:cyrene_music/services/playback/queue_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const placeholder = 'https://y.qq.com/mediastyle/global/img/album_300.png';
Track song(String id) => Track(
  id: id,
  name: id,
  artists: 'Artist',
  album: 'Unknown',
  picUrl: placeholder,
  source: MusicSource.qq,
);
Map<String, dynamic> details(String id) => {
  'mid': id,
  'album': 'Album',
  'pic': 'https://y.qq.com/$id.jpg',
};

class _Playback extends ChangeNotifier implements PlaybackService {
  Track? selected;
  SongDetail? resolved;
  String? resolvedArtist;
  @override
  String get displayArtist => resolvedArtist ?? selected?.artists ?? '';
  final covers = QueueController();
  @override
  final coverManager = CoverManager();
  @override
  Track? get activeTrack => selected;
  @override
  bool get isTrackSwitchPending => false;
  @override
  PBState get state => PBState.paused;
  @override
  PlaybackViewState get viewState => PlaybackViewState(
    generation: 1,
    track: selected,
    song: resolved,
    switchPhase: PlaybackSwitchPhase.paused,
    desiredPlaying: false,
    enginePlaying: false,
    position: Duration.zero,
    duration: null,
    bufferedPosition: Duration.zero,
    lyricState: LyricLoadState.idle,
    lyricSnapshot: null,
  );
  String key(Track track) => '${track.source.name}_${track.id}';
  @override
  ImageProvider? getCoverProvider(Track track) =>
      covers.coverProviderFor(track, key(track));
  @override
  void updateCoverProvider(Track track, ImageProvider provider) =>
      covers.updateCoverProvider(track, key(track), provider);
  void select(Track track) {
    selected = track;
    final provider = CachedNetworkImageProvider(track.picUrl);
    updateCoverProvider(track, provider);
    coverManager.setCoverImmediate(provider, url: track.picUrl);
    notifyListeners();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
  @override
  void dispose() {
    coverManager.dispose();
    super.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('already enriched queue tracks also fill missing resolved song presentation', () {
    final metadata = TrackMetadataService.forTesting(
      origin: () => 'test',
      fetch: (_) async => null,
    );
    final playback = _Playback();
    final player = PlayerService.forTesting(
      playback: playback,
      metadata: metadata,
    );
    addTearDown(() {
      player.dispose();
      playback.dispose();
      metadata.dispose();
    });
    playback.selected = Track(
      id: 'complete',
      name: 'Title',
      artists: 'Artist',
      album: 'Album',
      picUrl: 'https://valid/cover.jpg',
      source: MusicSource.qq,
    );
    playback.resolved = SongDetail.fromJson({
      'id': 'complete',
      'url': 'https://valid/audio.mp3',
      'lyric': 'lyrics',
    }, source: MusicSource.qq);
    expect(player.currentSong!.arName, 'Artist');
    expect(player.currentSong!.pic, 'https://valid/cover.jpg');
    expect(player.currentSong!.url, playback.resolved!.url);
    expect(player.currentSong!.lyric, 'lyrics');
    playback.selected = song('different');
    expect(player.currentSong, same(playback.resolved));
  });

  test('mini player receives a recovered artist while preserving resolved metadata', () async {
    final metadata = TrackMetadataService.forTesting(
      origin: () => 'test',
      fetch: (track) async => {
        ...details(track.id.toString()),
        'artists': 'Real artist',
      },
    );
    final playback = _Playback();
    final player = PlayerService.forTesting(
      playback: playback,
      metadata: metadata,
    );
    addTearDown(() {
      player.dispose();
      playback.dispose();
      metadata.dispose();
    });
    final original = Track(
      id: 'missing',
      name: 'Song',
      artists: '未知艺术家',
      album: '',
      picUrl: '',
      source: MusicSource.qq,
    );
    playback.select(original);
    await metadata.complete(original);
    expect(player.currentTrack!.artists, 'Real artist');
    expect(player.displayArtist, 'Real artist');
    expect(
      (player.currentCoverImageProvider as CachedNetworkImageProvider).url,
      'https://y.qq.com/missing.jpg',
    );
    playback.resolvedArtist = 'Resolved artist';
    expect(player.displayArtist, 'Resolved artist');
  });

  test(
    'metadata replaces both the displayed provider and queue placeholder',
    () async {
      final metadata = TrackMetadataService.forTesting(
        origin: () => 'test',
        fetch: (id) async => details(id.id.toString()),
      );
      final playback = _Playback();
      final player = PlayerService.forTesting(
        playback: playback,
        metadata: metadata,
      );
      addTearDown(() {
        player.dispose();
        playback.dispose();
        metadata.dispose();
      });
      final original = song('one');
      playback.select(original);
      await metadata.complete(original);
      final provider =
          player.currentCoverImageProvider as CachedNetworkImageProvider;
      expect(provider.url, details('one')['pic']);
      expect(playback.coverManager.currentCover, same(provider));
      expect(playback.coverManager.currentUrl, details('one')['pic']);
      expect(playback.getCoverProvider(original), same(provider));
      expect(playback.getCoverProvider(player.currentTrack!), same(provider));
    },
  );

  test('selecting a track with cached metadata replaces a newly primed placeholder', () async {
    final metadata = TrackMetadataService.forTesting(
      origin: () => 'test',
      fetch: (id) async => details(id.id.toString()),
    );
    final original = song('cached');
    await metadata.complete(original);
    final playback = _Playback();
    final player = PlayerService.forTesting(
      playback: playback,
      metadata: metadata,
    );
    addTearDown(() {
      player.dispose();
      playback.dispose();
      metadata.dispose();
    });
    playback.select(original);
    expect(
      (player.currentCoverImageProvider as CachedNetworkImageProvider).url,
      details('cached')['pic'],
    );
    expect(playback.coverManager.currentUrl, details('cached')['pic']);
  });

  test(
    'late metadata cannot replace the cover of a different selected song',
    () async {
      final pending = Completer<Map<String, dynamic>?>();
      final metadata = TrackMetadataService.forTesting(
        origin: () => 'test',
        fetch: (_) => pending.future,
      );
      final playback = _Playback();
      final player = PlayerService.forTesting(
        playback: playback,
        metadata: metadata,
      );
      addTearDown(() {
        player.dispose();
        playback.dispose();
        metadata.dispose();
      });
      final original = song('old');
      playback.select(original);
      final completion = metadata.complete(original);
      final other = Track(
        id: 'other',
        name: 'Other',
        artists: 'Artist',
        album: 'Album',
        picUrl: 'https://example.test/other.jpg',
        source: MusicSource.netease,
      );
      playback.select(other);
      final provider = playback.coverManager.currentCover;
      pending.complete(details('old'));
      await completion;
      expect(playback.coverManager.currentCover, same(provider));
      expect(player.currentCoverImageProvider, same(provider));
      expect(playback.coverManager.currentUrl, other.picUrl);
    },
  );
}
