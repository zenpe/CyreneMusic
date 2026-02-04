import 'package:flutter/material.dart';
import '../models/navidrome_models.dart';
import '../models/track.dart';
import '../services/navidrome_api.dart';
import '../services/navidrome_session_service.dart';
import '../services/player_service.dart';
import '../services/playlist_queue_service.dart';

class NavidromePlaylistsPage extends StatefulWidget {
  const NavidromePlaylistsPage({super.key});

  @override
  State<NavidromePlaylistsPage> createState() => _NavidromePlaylistsPageState();
}

class _NavidromePlaylistsPageState extends State<NavidromePlaylistsPage> {
  List<NavidromePlaylist> _playlists = [];
  bool _loading = true;
  String? _error;

  NavidromeApi? get _api => NavidromeSessionService().api;

  @override
  void initState() {
    super.initState();
    _loadPlaylists();
  }

  Future<void> _loadPlaylists() async {
    final api = _api;
    if (api == null) {
      setState(() {
        _loading = false;
        _error = '未配置服务器';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final playlists = await api.getPlaylists();
      if (!mounted) return;
      setState(() {
        _playlists = playlists;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '加载失败：$e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(child: Text(_error!));
    }

    return RefreshIndicator(
      onRefresh: _loadPlaylists,
      child: ListView.builder(
        itemCount: _playlists.length,
        itemBuilder: (context, index) {
          final playlist = _playlists[index];
          return ListTile(
            title: Text(playlist.name),
            subtitle: Text('${playlist.songCount} 首'),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => NavidromePlaylistDetailPage(playlist: playlist),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class NavidromePlaylistDetailPage extends StatefulWidget {
  final NavidromePlaylist playlist;

  const NavidromePlaylistDetailPage({super.key, required this.playlist});

  @override
  State<NavidromePlaylistDetailPage> createState() =>
      _NavidromePlaylistDetailPageState();
}

class _NavidromePlaylistDetailPageState
    extends State<NavidromePlaylistDetailPage> {
  List<NavidromeSong> _songs = [];
  bool _loading = true;
  String? _error;

  NavidromeApi? get _api => NavidromeSessionService().api;

  @override
  void initState() {
    super.initState();
    _loadSongs();
  }

  Future<void> _loadSongs() async {
    final api = _api;
    if (api == null) {
      setState(() {
        _loading = false;
        _error = '未配置服务器';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final songs = await api.getPlaylistSongs(widget.playlist.id);
      if (!mounted) return;
      setState(() {
        _songs = songs;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '加载失败：$e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void _playSongs(int index) {
    if (_songs.isEmpty) return;
    final api = _api;
    if (api == null) return;
    final tracks = _songs
        .map(
          (song) => Track(
            id: song.id,
            name: song.title,
            artists: song.artist,
            album: song.album,
            picUrl: api.buildCoverUrl(song.coverArt),
            source: MusicSource.navidrome,
          ),
        )
        .toList();
    PlaylistQueueService().setQueue(tracks, index, QueueSource.playlist);
    PlayerService().playTrack(tracks[index]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.playlist.name)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView.builder(
                  itemCount: _songs.length,
                  itemBuilder: (context, index) {
                    final song = _songs[index];
                    return ListTile(
                      title: Text(song.title),
                      subtitle: Text(song.artist),
                      onTap: () => _playSongs(index),
                    );
                  },
                ),
    );
  }
}
