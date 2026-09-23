import 'dart:collection';
import 'dart:math';

import 'package:flutter/material.dart' show ImageProvider;

import '../../models/track.dart';
import '../playback_mode_service.dart';

enum QueueSource {
  none,
  favorites,
  playlist,
  album,
  history,
  search,
  radio,
  toplist,
}

class QueueRemovalResult {
  final bool removed;
  final bool becameEmpty;
  final bool removedCurrent;

  const QueueRemovalResult({
    required this.removed,
    required this.becameEmpty,
    required this.removedCurrent,
  });

  static const notRemoved = QueueRemovalResult(
    removed: false,
    becameEmpty: false,
    removedCurrent: false,
  );
}

class QueueController {
  QueueController({Random? random}) : _random = random ?? Random();

  final Random _random;
  final List<Track> _tracks = [];
  final List<int> _entryIds = [];
  late final List<Track> _readOnlyTracks = UnmodifiableListView(_tracks);
  final Map<String, ImageProvider> _coverProviders = {};
  List<int> _shuffledIndices = [];
  int _shufflePosition = -1;
  int _currentIndex = -1;
  int _structureRevision = 0;
  int _nextEntryId = 0;
  QueueSource _source = QueueSource.none;

  List<Track> get tracks => _readOnlyTracks;
  int get currentIndex => _currentIndex;
  QueueSource get source => _source;
  int get structureRevision => _structureRevision;
  int? get currentEntryId => entryIdAt(_currentIndex);

  void clearCoverProviders() => _coverProviders.clear();
  bool get isEmpty => _tracks.isEmpty;
  bool get isNotEmpty => _tracks.isNotEmpty;
  int get length => _tracks.length;
  bool get hasNext => isNotEmpty && _currentIndex < length - 1;
  bool get hasPrevious => isNotEmpty && _currentIndex > 0;
  Track? get currentTrack => _currentIndex >= 0 && _currentIndex < length
      ? _tracks[_currentIndex]
      : null;

  int? entryIdAt(int index) =>
      index >= 0 && index < _entryIds.length ? _entryIds[index] : null;

  int indexOfEntryId(int entryId) => _entryIds.indexOf(entryId);

  int _allocateEntryId() => ++_nextEntryId;

  void replace(
    Iterable<Track> tracks,
    int index,
    QueueSource source, {
    Map<String, ImageProvider>? coverProviders,
  }) {
    _tracks
      ..clear()
      ..addAll(tracks);
    _entryIds
      ..clear()
      ..addAll(List<int>.generate(_tracks.length, (_) => _allocateEntryId()));
    _currentIndex = _tracks.isEmpty ? -1 : index.clamp(0, _tracks.length - 1);
    _source = _tracks.isEmpty ? QueueSource.none : source;
    _structureRevision++;
    _coverProviders
      ..clear()
      ..addAll(coverProviders ?? const {});
    resetShuffle();
  }

  void clear() {
    if (_tracks.isNotEmpty || _source != QueueSource.none) {
      _structureRevision++;
    }
    _tracks.clear();
    _entryIds.clear();
    _currentIndex = -1;
    _source = QueueSource.none;
    _coverProviders.clear();
    resetShuffle();
  }

  void append(Track track) {
    _tracks.add(track);
    _entryIds.add(_allocateEntryId());
    _structureRevision++;
    resetShuffle();
  }

  void appendAll(Iterable<Track> tracks) {
    final additions = tracks.toList(growable: false);
    if (additions.isEmpty) return;
    _tracks.addAll(additions);
    _entryIds.addAll(
      List<int>.generate(additions.length, (_) => _allocateEntryId()),
    );
    _structureRevision++;
    resetShuffle();
  }

  void insertNext(Track track) {
    removeDuplicate(track);
    final insertAt = (_currentIndex + 1).clamp(0, _tracks.length);
    _tracks.insert(insertAt, track);
    _entryIds.insert(insertAt, _allocateEntryId());
    _structureRevision++;
    resetShuffle();
  }

  bool jumpTo(int index) {
    if (index < 0 || index >= length) return false;
    _currentIndex = index;
    return true;
  }

  QueueRemovalResult removeAt(int index) {
    if (index < 0 || index >= length) return QueueRemovalResult.notRemoved;
    final removedCurrent = index == _currentIndex;
    _tracks.removeAt(index);
    _entryIds.removeAt(index);
    _structureRevision++;
    if (_tracks.isEmpty) {
      clear();
      return const QueueRemovalResult(
        removed: true,
        becameEmpty: true,
        removedCurrent: true,
      );
    }
    if (index < _currentIndex) {
      _currentIndex--;
    } else if (removedCurrent) {
      _currentIndex = _currentIndex.clamp(0, _tracks.length - 1);
    }
    resetShuffle();
    return QueueRemovalResult(
      removed: true,
      becameEmpty: false,
      removedCurrent: removedCurrent,
    );
  }

  bool reorder(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= length) return false;
    if (newIndex < 0 || newIndex > length) return false;
    final track = _tracks.removeAt(oldIndex);
    final entryId = _entryIds.removeAt(oldIndex);
    final targetIndex = newIndex.clamp(0, _tracks.length);
    _tracks.insert(targetIndex, track);
    _entryIds.insert(targetIndex, entryId);
    _structureRevision++;
    if (oldIndex == _currentIndex) {
      _currentIndex = targetIndex;
    } else if (oldIndex < _currentIndex && targetIndex >= _currentIndex) {
      _currentIndex--;
    } else if (oldIndex > _currentIndex && targetIndex <= _currentIndex) {
      _currentIndex++;
    }
    resetShuffle();
    return true;
  }

  int indexOf(Track track) => _tracks.indexWhere(
    (item) =>
        item.id.toString() == track.id.toString() &&
        item.source == track.source,
  );

  void removeDuplicate(Track track) {
    final existing = indexOf(track);
    if (existing < 0) return;
    _tracks.removeAt(existing);
    _entryIds.removeAt(existing);
    _structureRevision++;
    if (existing <= _currentIndex) {
      _currentIndex = (_currentIndex - 1).clamp(-1, _tracks.length);
    }
  }

  Track? peekNext(PlaybackMode mode) {
    final index = peekNextIndex(mode);
    return index == null ? null : _tracks[index];
  }

  int? peekNextIndex(PlaybackMode mode) {
    if (isEmpty) return null;
    if (mode == PlaybackMode.repeatOne) return _currentIndex;
    if (mode == PlaybackMode.shuffle) {
      if (_shuffledIndices.isEmpty) return null;
      final nextPosition = _shufflePosition + 1;
      return nextPosition < _shuffledIndices.length
          ? _shuffledIndices[nextPosition]
          : _shuffledIndices.first;
    }
    final nextIndex = _currentIndex + 1;
    if (mode == PlaybackMode.sequential && nextIndex >= length) return null;
    return nextIndex < length ? nextIndex : 0;
  }

  Track? peekPrevious(PlaybackMode mode) {
    final index = peekPreviousIndex(mode);
    return index == null ? null : _tracks[index];
  }

  int? peekPreviousIndex(PlaybackMode mode) {
    if (isEmpty) return null;
    if (mode == PlaybackMode.repeatOne) return _currentIndex;
    if (mode == PlaybackMode.shuffle) {
      if (_shuffledIndices.isEmpty || _shufflePosition <= 0) return null;
      return _shuffledIndices[_shufflePosition - 1];
    }
    final previousIndex = _currentIndex - 1;
    return previousIndex >= 0 ? previousIndex : length - 1;
  }

  Track? advanceNext({required bool shuffle}) {
    if (isEmpty) return null;
    if (shuffle) return advanceRandom();
    _currentIndex = _currentIndex + 1 < length ? _currentIndex + 1 : 0;
    return currentTrack;
  }

  Track? advancePrevious({required bool shuffle}) {
    if (isEmpty) return null;
    if (shuffle) return advanceRandomPrevious();
    _currentIndex = _currentIndex - 1 >= 0 ? _currentIndex - 1 : length - 1;
    return currentTrack;
  }

  Track? advanceRandom() {
    if (isEmpty) return null;
    if (_shuffledIndices.isEmpty ||
        _shufflePosition >= _shuffledIndices.length - 1) {
      _generateShuffle();
    }
    _shufflePosition++;
    _currentIndex = _shuffledIndices[_shufflePosition];
    return currentTrack;
  }

  Track? advanceRandomPrevious() {
    if (isEmpty || _shuffledIndices.isEmpty || _shufflePosition <= 0) {
      return null;
    }
    _shufflePosition--;
    _currentIndex = _shuffledIndices[_shufflePosition];
    return currentTrack;
  }

  void resetShuffle() {
    _shuffledIndices = [];
    _shufflePosition = -1;
  }

  void _generateShuffle() {
    _shuffledIndices = List.generate(length, (index) => index)
      ..shuffle(_random);
    if (length > 1 && _shuffledIndices.first == _currentIndex) {
      final swapIndex = _random.nextInt(length - 1) + 1;
      final first = _shuffledIndices.first;
      _shuffledIndices[0] = _shuffledIndices[swapIndex];
      _shuffledIndices[swapIndex] = first;
    }
    _shufflePosition = -1;
  }

  ImageProvider? coverProviderFor(Track track, String key) =>
      _coverProviders[key] ??
      (track.picUrl.isNotEmpty ? _coverProviders[track.picUrl] : null);

  void updateCoverProvider(Track track, String key, ImageProvider provider) {
    _coverProviders[key] = provider;
    if (track.picUrl.isNotEmpty) _coverProviders[track.picUrl] = provider;
  }

  void updateCoverProviders(Map<String, ImageProvider> providers) {
    _coverProviders.addAll(providers);
  }
}
