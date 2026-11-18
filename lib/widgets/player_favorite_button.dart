import 'package:flutter/material.dart';

import '../models/track.dart';
import '../pages/player_components/player_dialogs.dart';
import '../services/playlist_service.dart';
import 'playlist_membership_state.dart';

class PlayerFavoriteButton extends StatefulWidget {
  final Track track;

  final bool compact;
  const PlayerFavoriteButton({
    super.key,
    required this.track,
    this.compact = false,
  });

  @override
  State<PlayerFavoriteButton> createState() => PlayerFavoriteButtonState();
}

class PlayerFavoriteButtonState extends State<PlayerFavoriteButton>
    with PlaylistMembershipState<PlayerFavoriteButton> {
  @override
  Track get membershipTrack => widget.track;
  bool get _isInPlaylist => membershipResult.inPlaylist;
  bool get _isLoading => membershipLoading;
  List<String> get _playlistNames => membershipResult.playlistNames;
  List<int> get _playlistIds => membershipResult.playlistIds;

  Future<void> _checkIfInPlaylist() => refreshMembership();

  Future<void> _removeFromPlaylists() async {
    if (_playlistIds.isEmpty) return;

    final playlistService = PlaylistService();

    final track = widget.track;
    final contextIdentity = playlistService.membershipContext;
    final membership = await playlistService.isTrackInAnyPlaylist(track);
    if (!mounted || !membership.known || !membership.complete) return;
    for (final match in membership.matches) {
      if (playlistService.membershipContext != contextIdentity) return;
      await playlistService.removeTrackMatch(match, track);
    }

    // 刷新状态
    _checkIfInPlaylist();
  }

  void _showManageMenu(BuildContext context, Offset position) {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    final openedTrack = widget.track;
    showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromCenter(center: position, width: 0, height: 0),
        Offset.zero & overlay.size,
      ),
      color: Colors.grey[850],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      items: [
        PopupMenuItem<String>(
          value: 'info',
          enabled: false,
          child: Text(
            '已收藏到: ${_playlistNames.join(", ")}',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontSize: 12,
            ),
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'remove',
          child: Row(
            children: [
              Icon(
                Icons.remove_circle_outline,
                color: Colors.redAccent,
                size: 18,
              ),
              const SizedBox(width: 8),
              const Text('从所有歌单移除', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'add',
          child: Row(
            children: [
              Icon(Icons.playlist_add, color: Colors.white70, size: 18),
              const SizedBox(width: 8),
              const Text('添加到其他歌单', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (!mounted ||
          widget.track.source != openedTrack.source ||
          widget.track.id != openedTrack.id)
        return;
      if (value == 'remove') {
        _removeFromPlaylists();
      } else if (value == 'add') {
        if (!context.mounted) return;
        PlayerDialogs.showAddToPlaylist(context, widget.track);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return SizedBox(
        width: 32,
        height: 32,
        child: Padding(
          padding: EdgeInsets.all(8.0),
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: widget.compact
                ? Theme.of(context).colorScheme.primary
                : Colors.white54,
          ),
        ),
      );
    }

    if (!membershipResult.known) return buildUnknownMembershipButton();
    final tooltip = _isInPlaylist
        ? '已收藏到: ${_playlistNames.join(", ")}'
        : '添加到歌单';

    return IconButton(
      tooltip: tooltip,
      iconSize: widget.compact ? 20 : 26,
      color: _isInPlaylist
          ? Colors.redAccent
          : widget.compact
          ? Theme.of(context).colorScheme.onSurfaceVariant
          : Colors.white70,
      onPressed: () {
        if (_isInPlaylist) {
          final box = context.findRenderObject() as RenderBox;
          _showManageMenu(
            context,
            box.localToGlobal(box.size.bottomCenter(Offset.zero)),
          );
        } else {
          PlayerDialogs.showAddToPlaylist(context, widget.track);
        }
      },
      icon: Icon(_isInPlaylist ? Icons.favorite : Icons.favorite_border),
    );
  }
}
