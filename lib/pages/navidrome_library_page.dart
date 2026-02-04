import 'package:flutter/material.dart';
import '../models/navidrome_models.dart';
import '../models/track.dart';
import '../services/navidrome_api.dart';
import '../services/navidrome_session_service.dart';
import '../services/player_service.dart';
import '../services/playlist_queue_service.dart';

class NavidromeLibraryPage extends StatefulWidget {
  const NavidromeLibraryPage({super.key});

  @override
  State<NavidromeLibraryPage> createState() => _NavidromeLibraryPageState();
}

class _NavidromeLibraryPageState extends State<NavidromeLibraryPage> {
  List<NavidromeAlbum> _albums = [];
  bool _loading = true;
  String? _error;

  NavidromeApi? get _api => NavidromeSessionService().api;

  @override
  void initState() {
    super.initState();
    _loadAlbums();
  }

  Future<void> _loadAlbums() async {
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
      final albums = await api.getAlbumList();
      if (!mounted) return;
      setState(() {
        _albums = albums;
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
      onRefresh: _loadAlbums,
      child: ListView.builder(
        itemCount: _albums.length,
        itemBuilder: (context, index) {
          final album = _albums[index];
          final cover = _api?.buildCoverUrl(album.coverArt) ?? '';
          return ListTile(
            leading: _Cover(coverUrl: cover, size: 48),
            title: Text(album.name),
            subtitle: Text(album.artist),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => NavidromeAlbumPage(album: album),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class NavidromeAlbumPage extends StatefulWidget {
  final NavidromeAlbum album;

  const NavidromeAlbumPage({super.key, required this.album});

  @override
  State<NavidromeAlbumPage> createState() => _NavidromeAlbumPageState();
}

class _NavidromeAlbumPageState extends State<NavidromeAlbumPage> {
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
      final songs = await api.getAlbumSongs(widget.album.id);
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
    PlaylistQueueService().setQueue(tracks, index, QueueSource.search);
    PlayerService().playTrack(tracks[index]);
  }

  @override
  Widget build(BuildContext context) {
    final cover = _api?.buildCoverUrl(widget.album.coverArt) ?? '';
    return Scaffold(
      appBar: AppBar(title: Text(widget.album.name)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView.builder(
                  itemCount: _songs.length,
                  itemBuilder: (context, index) {
                    final song = _songs[index];
                    return ListTile(
                      leading: _Cover(coverUrl: cover, size: 40),
                      title: Text(song.title),
                      subtitle: Text(song.artist),
                      onTap: () => _playSongs(index),
                    );
                  },
                ),
    );
  }
}

class _Cover extends StatelessWidget {
  final String coverUrl;
  final double size;

  const _Cover({required this.coverUrl, required this.size});

  @override
  Widget build(BuildContext context) {
    if (coverUrl.isEmpty) {
      return SizedBox(
        width: size,
        height: size,
        child: Icon(Icons.album, size: size * 0.6),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.network(
        coverUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => SizedBox(
          width: size,
          height: size,
          child: Icon(Icons.album, size: size * 0.6),
        ),
      ),
    );
  }
}
