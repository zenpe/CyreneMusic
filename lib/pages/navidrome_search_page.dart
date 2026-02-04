import 'package:flutter/material.dart';
import '../models/navidrome_models.dart';
import '../models/track.dart';
import '../services/navidrome_api.dart';
import '../services/navidrome_session_service.dart';
import '../services/player_service.dart';
import '../services/playlist_queue_service.dart';

class NavidromeSearchPage extends StatefulWidget {
  const NavidromeSearchPage({super.key});

  @override
  State<NavidromeSearchPage> createState() => _NavidromeSearchPageState();
}

class _NavidromeSearchPageState extends State<NavidromeSearchPage> {
  final TextEditingController _controller = TextEditingController();
  bool _isLoading = false;
  String? _error;
  NavidromeSearchResult? _result;

  NavidromeApi? get _api => NavidromeSessionService().api;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _controller.text.trim();
    if (query.isEmpty) return;
    final api = _api;
    if (api == null) {
      setState(() {
        _error = '未配置服务器';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final result = await api.search3(query);
      if (!mounted) return;
      setState(() {
        _result = result;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '搜索失败：$e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _playSongs(List<NavidromeSong> songs, int index) {
    if (songs.isEmpty) return;
    final api = _api;
    if (api == null) return;
    final tracks = songs
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
    final songs = _result?.songs ?? const <NavidromeSong>[];

    return Scaffold(
      appBar: AppBar(
        title: const Text('搜索'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: TextField(
              controller: _controller,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
              decoration: InputDecoration(
                hintText: '搜索歌曲',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: _search,
                ),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : songs.isEmpty
                  ? const Center(child: Text('暂无结果'))
                  : ListView.builder(
                      itemCount: songs.length,
                      itemBuilder: (context, index) {
                        final song = songs[index];
                        return ListTile(
                          title: Text(song.title),
                          subtitle: Text(song.artist),
                          onTap: () => _playSongs(songs, index),
                        );
                      },
                    ),
    );
  }
}
