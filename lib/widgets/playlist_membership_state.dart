import 'package:flutter/material.dart';

import '../models/track.dart';
import '../services/playlist_service.dart';

/// Shared subscription and stale-response guards for player heart buttons.
mixin PlaylistMembershipState<T extends StatefulWidget> on State<T> {
  Track get membershipTrack;
  TrackInPlaylistResult membershipResult = const TrackInPlaylistResult(
    known: false,
    matches: [],
  );
  bool membershipLoading = false;
  final _service = PlaylistService();
  int _generation = 0;
  bool _pending = false;
  String? _context;
  int _epoch = -1;
  String? _trackKey;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onMembershipChanged);
    refreshMembership();
  }

  @override
  void didUpdateWidget(covariant T oldWidget) {
    super.didUpdateWidget(oldWidget);
    final track = membershipTrack;
    if (_trackKey != '${track.source.name}:${track.id}') refreshMembership();
  }

  void _onMembershipChanged() {
    if (mounted) refreshMembership();
  }

  Widget buildUnknownMembershipButton() => IconButton(
    tooltip: '收藏状态暂不可用，点击重试',
    onPressed: refreshMembership,
    icon: const Icon(Icons.help_outline, color: Colors.white54),
  );

  Future<void> refreshMembership() async {
    if (!mounted) return;
    final track = membershipTrack;
    final key = '${track.source.name}:${track.id}';
    if (_context != _service.membershipContext ||
        _epoch != _service.membershipEpoch ||
        _trackKey != key) {
      _generation++;
      _pending = false;
      _context = _service.membershipContext;
      _epoch = _service.membershipEpoch;
      _trackKey = key;
    }
    final cached = _service.cachedTrackMembership(track);
    setState(() {
      membershipResult = cached;
      membershipLoading = !cached.known;
    });
    if (cached.known && cached.complete) {
      membershipLoading = false;
      return;
    }
    if (_pending) return;
    _pending = true;
    final generation = _generation;
    final result = await _service.isTrackInAnyPlaylist(track);
    if (!mounted || generation != _generation) return;
    _pending = false;
    setState(() {
      // A failed verification must not erase a known local positive.
      final latest = _service.cachedTrackMembership(track);
      membershipResult = latest.known ? latest : result;
      membershipLoading = false;
    });
  }

  @override
  void dispose() {
    _generation++;
    _service.removeListener(_onMembershipChanged);
    super.dispose();
  }
}
