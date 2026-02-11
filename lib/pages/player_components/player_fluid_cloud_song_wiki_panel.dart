import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../services/player_service.dart';
import '../../services/netease_song_wiki_service.dart';
import '../../services/song_memory_service.dart';
import '../../services/netease_artist_service.dart';
import '../../services/netease_discover_service.dart';
import '../../services/playlist_queue_service.dart';
import '../../models/track.dart';
import '../../models/netease_discover.dart';

/// 流体云专用歌曲百科面板
/// 展示曲风、BPM、语种、回忆坐标、相似歌曲等
class PlayerFluidCloudSongWikiPanel extends StatefulWidget {
  const PlayerFluidCloudSongWikiPanel({super.key});

  @override
  State<PlayerFluidCloudSongWikiPanel> createState() => _PlayerFluidCloudSongWikiPanelState();
}

class _PlayerFluidCloudSongWikiPanelState extends State<PlayerFluidCloudSongWikiPanel> {
  final ScrollController _scrollController = ScrollController();
  Map<String, dynamic>? _wikiData;
  Map<String, dynamic>? _musicDetail;
  Map<String, dynamic>? _userMemory; // 用户自己的回忆坐标
  
  // 歌手相关数据 (支持多位歌手)
  // List<{
  //   'name': String,              // 歌手名
  //   'desc': String,              // 简介
  //   'hotSongs': List<Track>,     // 热门歌曲
  // }>
  List<Map<String, dynamic>> _artistsDataList = [];
  String? _lastArtistsName; // 用于缓存比较是否变化 (比如 "Artist A / Artist B")
  
  bool _loading = true;
  dynamic _lastSongId;
  
  // 内嵌歌单详情视图状态
  int? _selectedPlaylistId;
  NeteasePlaylistDetail? _playlistDetail;
  bool _loadingPlaylist = false;

  @override
  void initState() {
    super.initState();
    PlayerService().addListener(_onPlayerChanged);
    _loadSongData();
  }

  @override
  void dispose() {
    PlayerService().removeListener(_onPlayerChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onPlayerChanged() {
    _loadSongData();
  }

  Future<void> _loadSongData() async {
    final track = PlayerService().currentTrack;
    
    if (track == null || track.source != MusicSource.netease) {
      if (mounted && _wikiData != null) {
        setState(() {
          _wikiData = null;
          _musicDetail = null;
          _userMemory = null;
          _lastSongId = null;
        });
      }
      return;
    }

    if (track.id == _lastSongId && _wikiData != null) return;

    if (mounted) setState(() => _loading = true);

    try {
      // 1. 获取所有歌手名
      final allArtistsName = track.artists;
      final artistNames = _splitArtists(allArtistsName);
      
      // 2. 基础请求：网易云百科 + 用户回忆坐标
      final baseFutures = <Future<dynamic>>[
        NeteaseSongWikiService().fetchSongWiki(track.id),             // 0
        NeteaseSongWikiService().fetchSongMusicDetail(track.id),      // 1
        SongMemoryService().fetchSongMemory(track.id.toString(), track.source.name), // 2
      ];

      final baseResults = await Future.wait(baseFutures);
      
      // 3. 并行获取每位歌手的详情
      List<Map<String, dynamic>> newArtistsDataList = [];
      
      // 并行执行所有歌手的数据获取
      final artistFutures = artistNames.map((name) async {
         try {
           final artistId = await NeteaseArtistDetailService().resolveArtistIdByName(name);
           if (artistId == null) return null;
           
           // 获取详情和描述
           final results = await Future.wait([
             NeteaseArtistDetailService().fetchArtistDesc(artistId),
             NeteaseArtistDetailService().fetchArtistDetail(artistId),
           ]);
           
           final descData = results[0] as Map<String, dynamic>?;
           final detailData = results[1] as Map<String, dynamic>?;
           
           // 简介: 优先使用 descData (artist/desc 接口)，其次使用 detailData (artist/detail 接口)
           String briefDesc = '';
           if (descData != null && descData['briefDesc'] != null) {
              briefDesc = descData['briefDesc'].toString();
           } else if (detailData != null && detailData['artist'] != null) {
              final val = detailData['artist']['briefDesc'] ?? detailData['artist']['description'];
              briefDesc = val?.toString() ?? '';
           }
           
           // 头像: 必须从 detailData (artist/detail 接口) 中获取
           String avatarUrl = '';
           if (detailData != null && detailData['artist'] != null) {
              final artistObj = detailData['artist'];
              if (artistObj is Map) {
                avatarUrl = artistObj['img1v1Url']?.toString() ?? 
                            artistObj['picUrl']?.toString() ?? '';
              }
           }
           
           // 热门歌曲
           List<Track> hotSongs = [];
           if (detailData != null && detailData['songs'] != null) {
             final songsData = detailData['songs'] as List<dynamic>;
             hotSongs = songsData.map((s) {
               final m = s as Map<String, dynamic>;
               return Track(
                 id: m['id'],
                 name: m['name']?.toString() ?? '',
                 artists: m['artists']?.toString() ?? '',
                 album: m['album']?.toString() ?? '',
                 picUrl: m['picUrl']?.toString() ?? '',
                 source: MusicSource.netease,
               );
             }).toList();
           }
           
           return {
             'name': name,
             'desc': briefDesc,
             'avatarUrl': avatarUrl,
             'hotSongs': hotSongs,
           };
         } catch (e) {
           debugPrint('Error fetching artist data for $name: $e');
           return null;
         }
      }).toList();

      final artistsResults = await Future.wait(artistFutures);
      
      // 过滤掉失败的结果
      for (final item in artistsResults) {
        if (item != null) {
          newArtistsDataList.add(item);
        }
      }

      if (mounted) {
        setState(() {
          _wikiData = baseResults[0] as Map<String, dynamic>?;
          _musicDetail = baseResults[1] as Map<String, dynamic>?;
          _userMemory = baseResults[2] as Map<String, dynamic>?;
          
          _artistsDataList = newArtistsDataList;
          _lastArtistsName = allArtistsName;

          _loading = false;
          _lastSongId = track.id;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 分割歌手字符串
  List<String> _splitArtists(String artists) {
    if (artists.isEmpty) return [];
    final separators = RegExp(r'[/\\、&,，]');
    return artists.split(separators).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }

  /// 从 blocks 中查找指定 code 的区块
  Map<String, dynamic>? _findBlock(String code) {
    final blocks = _wikiData?['blocks'] as List? ?? [];
    for (final block in blocks) {
      if (block is Map && block['code'] == code) {
        return block as Map<String, dynamic>;
      }
    }
    return null;
  }

  /// 解析音乐百科数据（曲风、语种、BPM）
  Map<String, dynamic> _parseBasicInfo() {
    final basicBlock = _findBlock('SONG_PLAY_ABOUT_SONG_BASIC');
    final creatives = basicBlock?['creatives'] as List? ?? [];
    
    List<String> styles = [];
    String language = '';
    String bpm = '';
    
    for (final creative in creatives) {
      if (creative is! Map) continue;
      final creativeType = creative['creativeType']?.toString() ?? '';
      final uiElement = creative['uiElement'] as Map?;
      
      if (creativeType == 'songTag') {
        final resources = creative['resources'] as List? ?? [];
        for (final res in resources) {
          if (res is Map) {
            final title = res['uiElement']?['mainTitle']?['title']?.toString();
            if (title != null && title.isNotEmpty) {
              styles.add(title);
            }
          }
        }
      } else if (creativeType == 'language') {
        final textLinks = uiElement?['textLinks'] as List? ?? [];
        if (textLinks.isNotEmpty && textLinks[0] is Map) {
          language = textLinks[0]['text']?.toString() ?? '';
        }
      } else if (creativeType == 'bpm') {
        final textLinks = uiElement?['textLinks'] as List? ?? [];
        if (textLinks.isNotEmpty && textLinks[0] is Map) {
          bpm = textLinks[0]['text']?.toString() ?? '';
        }
      }
    }
    
    return {'styles': styles, 'language': language, 'bpm': bpm};
  }

  /// 解析回忆坐标数据（第一次听、累计播放）
  Map<String, dynamic> _parseMemoryInfo() {
    final memoryBlock = _findBlock('SONG_PLAY_ABOUT_MUSIC_MEMORY');
    final creatives = memoryBlock?['creatives'] as List? ?? [];
    
    String firstListenDate = '';
    String firstListenSeason = '';
    String firstListenPeriod = '';
    int playCount = 0;
    String playDescription = '';
    
    for (final creative in creatives) {
      if (creative is! Map) continue;
      final resources = creative['resources'] as List? ?? [];
      
      for (final res in resources) {
        if (res is! Map) continue;
        final resourceType = res['resourceType']?.toString() ?? '';
        final resourceExt = res['resourceExt'] as Map?;
        
        if (resourceType == 'FIRST_LISTEN') {
          final dto = resourceExt?['musicFirstListenDto'] as Map?;
          if (dto != null) {
            firstListenDate = dto['date']?.toString() ?? '';
            firstListenSeason = dto['season']?.toString() ?? '';
            firstListenPeriod = dto['period']?.toString() ?? '';
          }
        } else if (resourceType == 'TOTAL_PLAY') {
          final dto = resourceExt?['musicTotalPlayDto'] as Map?;
          if (dto != null) {
            playCount = dto['playCount'] ?? 0;
            playDescription = dto['text']?.toString() ?? '';
          }
        }
      }
    }
    
    return {
      'firstListenDate': firstListenDate,
      'firstListenSeason': firstListenSeason,
      'firstListenPeriod': firstListenPeriod,
      'playCount': playCount,
      'playDescription': playDescription,
    };
  }

  /// 解析相似歌曲数据
  List<Map<String, dynamic>> _parseSimilarSongs() {
    final similarBlock = _findBlock('SONG_PLAY_ABOUT_SIMILAR_SONG');
    final creatives = similarBlock?['creatives'] as List? ?? [];
    
    List<Map<String, dynamic>> songs = [];
    
    for (final creative in creatives) {
      if (creative is! Map) continue;
      final resources = creative['resources'] as List? ?? [];
      
      for (final res in resources) {
        if (res is! Map) continue;
        if (res['resourceType'] != 'SONG') continue;
        
        final uiElement = res['uiElement'] as Map?;
        if (uiElement == null) continue;
        
        final title = uiElement['mainTitle']?['title']?.toString() ?? '';
        
        // 解析歌手
        final subTitles = uiElement['subTitles'] as List? ?? [];
        String artist = '';
        if (subTitles.isNotEmpty && subTitles[0] is Map) {
          artist = (subTitles[0] as Map)['title']?.toString() ?? '';
        }
        
        // 解析封面
        final images = uiElement['images'] as List? ?? [];
        String imageUrl = '';
        if (images.isNotEmpty && images[0] is Map) {
          imageUrl = ((images[0] as Map)['imageUrl']?.toString() ?? '').replaceAll('http://', 'https://');
        }
        
        final songId = res['resourceId']?.toString() ?? '';
        
        if (title.isNotEmpty) {
          songs.add({
            'id': songId,
            'name': title,
            'artist': artist,
            'imageUrl': imageUrl,
          });
        }
      }
    }
    
    return songs.take(6).toList(); // 最多显示6首
  }

  /// 解析相关歌单数据
  List<Map<String, dynamic>> _parseRelatedPlaylists() {
    final relatedBlock = _findBlock('SONG_PLAY_ABOUT_RELATED_PLAYLIST');
    final creatives = relatedBlock?['creatives'] as List? ?? [];
    
    List<Map<String, dynamic>> playlists = [];
    
    for (final creative in creatives) {
      if (creative is! Map) continue;
      final resources = creative['resources'] as List? ?? [];
      
      for (final res in resources) {
        if (res is! Map) continue;
        if (res['resourceType'] != 'PLAYLIST') continue;
        
        final uiElement = res['uiElement'] as Map?;
        if (uiElement == null) continue;
        
        final title = uiElement['mainTitle']?['title']?.toString() ?? '';
        
        // 解析封面
        final images = uiElement['images'] as List? ?? [];
        String imageUrl = '';
        if (images.isNotEmpty && images[0] is Map) {
          imageUrl = ((images[0] as Map)['imageUrl']?.toString() ?? '').replaceAll('http://', 'https://');
        }
        
        // 解析播放量
        final resourceExt = res['resourceExt'] as Map?;
        final playCount = resourceExt?['playCount'] ?? 0;
        
        final playlistId = res['resourceId']?.toString() ?? '';
        
        if (title.isNotEmpty) {
          playlists.add({
            'id': playlistId,
            'name': title,
            'imageUrl': imageUrl,
            'playCount': playCount,
          });
        }
      }
    }
    
    return playlists.take(9).toList(); // 最多显示9个歌单
  }

  /// 根据日期获取季节和时段描述
  String _getSeasonAndPeriod(DateTime date) {
    // 季节
    String season;
    final month = date.month;
    if (month >= 3 && month <= 5) {
      season = '春天';
    } else if (month >= 6 && month <= 8) {
      season = '夏天';
    } else if (month >= 9 && month <= 11) {
      season = '秋天';
    } else {
      season = '冬天';
    }
    
    // 时段
    String period;
    final hour = date.hour;
    if (hour >= 6 && hour < 12) {
      period = '早晨';
    } else if (hour >= 12 && hour < 14) {
      period = '中午';
    } else if (hour >= 14 && hour < 18) {
      period = '下午';
    } else if (hour >= 18 && hour < 22) {
      period = '傍晚';
    } else {
      period = '深夜';
    }
    
    return '$season · $period';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CupertinoActivityIndicator(radius: 14, color: Colors.white70));
    }

    if (_wikiData == null && _musicDetail == null) {
      return const Center(child: Text('暂无歌曲百科信息', style: TextStyle(color: Colors.white54, fontSize: 16)));
    }

    // 使用 AnimatedSwitcher 在主视图和歌单详情视图之间切换（渐入渐出效果）
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      transitionBuilder: (Widget child, Animation<double> animation) {
        return FadeTransition(
          opacity: animation,
          child: child,
        );
      },
      child: _selectedPlaylistId != null
          ? _buildPlaylistDetailView()
          : _buildMainContentView(),
    );
  }

  Widget _buildMainContentView() {

    final track = PlayerService().currentTrack;
    final basicInfo = _parseBasicInfo();
    final memoryInfo = _parseMemoryInfo();
    final similarSongs = _parseSimilarSongs();
    final relatedPlaylists = _parseRelatedPlaylists();
    
    final styles = basicInfo['styles'] as List<String>;
    final language = basicInfo['language'] as String;
    final bpm = basicInfo['bpm'] as String;
    
    // 优先使用用户自己的回忆坐标，若无则回退到网易云数据
    String firstListenDate = '';
    String firstListenDesc = '';
    int playCount = 0;
    String playDescription = '';
    bool isUserMemory = false; // 标记是否为用户自己的数据
    
    if (_userMemory != null) {
      // 用户自己的回忆坐标
      isUserMemory = true;
      debugPrint('📊 [SongWikiPanel] 回忆坐标来源: 用户自己的播放记录 (来自后端 /stats/song-memory)');
      debugPrint('   _userMemory: $_userMemory');
      final firstPlayedAt = _userMemory!['firstPlayedAt'] as String?;
      if (firstPlayedAt != null && firstPlayedAt.isNotEmpty) {
        final dateUtc = DateTime.tryParse(firstPlayedAt);
        if (dateUtc != null) {
          // 转换为北京时间 (UTC+8)
          final date = dateUtc.add(const Duration(hours: 8));
          firstListenDate = '${date.year}.${date.month.toString().padLeft(2, '0')}.${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
          firstListenDesc = _getSeasonAndPeriod(date);
        }
      }
      playCount = (_userMemory!['playCount'] as int?) ?? 0;
      debugPrint('   首次播放: $firstListenDate, 累计播放: $playCount 次');
    } else {
      // 网易云回忆坐标（后备）
      debugPrint('📊 [SongWikiPanel] 回忆坐标来源: 网易云官方 API (无用户记录或未登录)');
      firstListenDate = memoryInfo['firstListenDate'] as String;
      final season = memoryInfo['firstListenSeason'] as String;
      final period = memoryInfo['firstListenPeriod'] as String;
      firstListenDesc = '$season$period';
      playCount = memoryInfo['playCount'] as int;
      playDescription = memoryInfo['playDescription'] as String;
      debugPrint('   首次播放: $firstListenDate $firstListenDesc, 累计播放: $playCount 次');
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: DefaultTextStyle(
          style: const TextStyle(fontFamily: 'Microsoft YaHei'),
          child: ListView(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 24),
            children: [
            // 歌曲大标题
            Text(
              track?.name ?? '歌曲信息',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 36,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              track?.artists ?? '',
              style: TextStyle(
                color: Colors.white.withOpacity(0.6),
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 40),

            // 音乐百科元数据
            if (styles.isNotEmpty || language.isNotEmpty || bpm.isNotEmpty) ...[
              _buildSectionTitle('音乐百科'),
              const SizedBox(height: 16),
              Wrap(
                spacing: 32,
                runSpacing: 24,
                children: [
                  if (styles.isNotEmpty) _buildMetaItem('曲风', styles.join(' / ')),
                  if (language.isNotEmpty) _buildMetaItem('语种', language),
                  if (bpm.isNotEmpty) _buildMetaItem('BPM', bpm),
                ],
              ),
              const SizedBox(height: 40),
            ],

            // 回忆坐标
            if (firstListenDate.isNotEmpty || playCount > 0) ...[
              _buildSectionTitle('回忆坐标'),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (firstListenDate.isNotEmpty) ...[
                      Row(
                        children: [
                          Icon(Icons.access_time_rounded, color: Colors.white.withOpacity(0.6), size: 20),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '第一次听',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.5),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '$firstListenDate · $firstListenDesc',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                    if (firstListenDate.isNotEmpty && playCount > 0)
                      const SizedBox(height: 20),
                    if (playCount > 0) ...[
                      Row(
                        children: [
                          Icon(Icons.replay_rounded, color: Colors.white.withOpacity(0.6), size: 20),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '累计播放 $playCount 次',
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.5),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (playDescription.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  playDescription,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.8),
                                    fontSize: 14,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 40),
            ],

            const SizedBox(height: 40),

            // 相似歌曲
            if (similarSongs.isNotEmpty) ...[
              _buildSectionTitle('相似歌曲'),
              const SizedBox(height: 16),
              ...similarSongs.map((song) => _buildSimilarSongTile(song)),
              const SizedBox(height: 40),
            ],

            // 相关歌单
            if (relatedPlaylists.isNotEmpty) ...[
              _buildSectionTitle('包含这首歌的歌单'),
              const SizedBox(height: 16),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.75,
                ),
                itemCount: relatedPlaylists.length,
                itemBuilder: (context, index) => _buildRelatedPlaylistTile(relatedPlaylists[index]),
              ),
              const SizedBox(height: 40),
            ],

            // 歌手介绍 (新增板块 - 支持多歌手)
            if (_artistsDataList.isNotEmpty) ...[
              const SizedBox(height: 24),
              _buildSectionTitle('关于歌手'),
              
              ..._artistsDataList.map((artistData) {
                 final name = artistData['name'] as String;
                 final desc = artistData['desc'] as String;
                 final avatarUrl = artistData['avatarUrl'] as String;
                 final hotSongs = artistData['hotSongs'] as List<Track>;
                 
                 return Column(
                   crossAxisAlignment: CrossAxisAlignment.start,
                   children: [
                     const SizedBox(height: 32),
                     // 歌手名小标题
                     Row(
                       children: [
                          if (avatarUrl.isNotEmpty)
                            ClipOval(
                              child: CachedNetworkImage(
                                imageUrl: avatarUrl,
                                width: 40,
                                height: 40,
                                fit: BoxFit.cover,
                                memCacheWidth: 128,
                                memCacheHeight: 128,
                                placeholder: (context, url) => Container(
                                  color: Colors.white10,
                                  child: Icon(CupertinoIcons.person_fill, size: 20, color: Colors.white.withOpacity(0.5)),
                                ),
                                errorWidget: (context, url, error) => Container(
                                  color: Colors.white10,
                                  child: Icon(CupertinoIcons.person_fill, size: 20, color: Colors.white.withOpacity(0.5)),
                                ),
                              ),
                            )
                          else
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withOpacity(0.1),
                              ),
                              child: Icon(CupertinoIcons.person_fill, size: 20, color: Colors.white.withOpacity(0.6)),
                            ),
                            
                          const SizedBox(width: 12),
                          Text(
                           name,
                           style: TextStyle(
                             color: Colors.white.withOpacity(0.9),
                             fontSize: 18,
                             fontWeight: FontWeight.bold,
                             fontFamily: 'Microsoft YaHei',
                           ),
                         ),
                       ],
                     ),
                     const SizedBox(height: 16),
                     
                     // 简介
                     if (desc.isNotEmpty) ...[
                       Text(
                         desc,
                         style: TextStyle(
                           color: Colors.white.withOpacity(0.8),
                           fontSize: 15,
                           height: 1.6,
                           fontFamily: 'Microsoft YaHei',
                         ),
                         maxLines: 4,
                         overflow: TextOverflow.ellipsis,
                       ),
                       const SizedBox(height: 20),
                     ],
                     
                     // 热门作品
                     if (hotSongs.isNotEmpty) ...[
                        Text(
                          '$name 的热门作品',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.5),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ...hotSongs.take(5).map((track) => _buildArtistSongItem(track)),
                     ],
                     
                     // 分隔线 (若不是最后一个)
                     if (artistData != _artistsDataList.last)
                       Padding(
                         padding: const EdgeInsets.symmetric(vertical: 24),
                         child: Divider(color: Colors.white.withOpacity(0.1), height: 1),
                       ),
                   ],
                 );
              }),
            ],
            
            const SizedBox(height: 80), // 底部留白
            ],
          ),
        ),
      ),
    );
  }
  
  /// Apple Music 风格的内嵌歌单详情视图
  Widget _buildPlaylistDetailView() {
    if (_loadingPlaylist) {
      return const Center(
        key: ValueKey('playlist_loading'),
        child: CupertinoActivityIndicator(radius: 14, color: Colors.white70),
      );
    }

    if (_playlistDetail == null) {
      return Center(
        key: const ValueKey('playlist_error'),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, color: Colors.white.withOpacity(0.5), size: 48),
            const SizedBox(height: 16),
            Text('加载失败', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 16)),
            const SizedBox(height: 24),
            TextButton.icon(
              onPressed: () => setState(() {
                _selectedPlaylistId = null;
                _playlistDetail = null;
              }),
              icon: const Icon(Icons.arrow_back, color: Colors.white70),
              label: const Text('返回', style: TextStyle(color: Colors.white70)),
            ),
          ],
        ),
      );
    }

    final detail = _playlistDetail!;
    final playCountText = detail.playCount >= 10000
        ? '${(detail.playCount / 10000).toStringAsFixed(1)}万'
        : detail.playCount.toString();

    return Container(
      key: ValueKey('playlist_${detail.id}'),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: DefaultTextStyle(
            style: const TextStyle(fontFamily: 'Microsoft YaHei'),
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
              children: [
                // 返回按钮
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(() {
                      _selectedPlaylistId = null;
                      _playlistDetail = null;
                    }),
                    icon: Icon(Icons.arrow_back_ios, color: Colors.white.withOpacity(0.7), size: 18),
                    label: Text('歌曲信息', style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 14)),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                
                // 歌单封面和信息
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 封面
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: CachedNetworkImage(
                        imageUrl: detail.coverImgUrl.replaceAll('http://', 'https://'),
                        width: 140,
                        height: 140,
                        memCacheWidth: 280,
                        memCacheHeight: 280,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(
                          color: Colors.white.withOpacity(0.1),
                          child: Icon(Icons.queue_music, color: Colors.white.withOpacity(0.3), size: 48),
                        ),
                        errorWidget: (_, __, ___) => Container(
                          color: Colors.white.withOpacity(0.1),
                          child: Icon(Icons.queue_music, color: Colors.white.withOpacity(0.3), size: 48),
                        ),
                      ),
                    ),
                    const SizedBox(width: 20),
                    // 信息
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            detail.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            detail.creator,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.6),
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 12),
                          // 播放量和歌曲数
                          Row(
                            children: [
                              Icon(Icons.play_circle_outline, color: Colors.white.withOpacity(0.5), size: 16),
                              const SizedBox(width: 4),
                              Text(
                                playCountText,
                                style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
                              ),
                              const SizedBox(width: 16),
                              Icon(Icons.music_note_outlined, color: Colors.white.withOpacity(0.5), size: 16),
                              const SizedBox(width: 4),
                              Text(
                                '${detail.trackCount}首',
                                style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
                              ),
                            ],
                          ),
                          // 标签
                          if (detail.tags.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: detail.tags.take(3).map((tag) => Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  tag,
                                  style: TextStyle(color: Colors.white.withOpacity(0.7), fontSize: 11),
                                ),
                              )).toList(),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                
                // 简介
                if (detail.description.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text(
                    detail.description,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 13,
                      height: 1.5,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                
                const SizedBox(height: 28),
                
                // 播放全部按钮
                Material(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(24),
                  child: InkWell(
                    onTap: () {
                      if (detail.tracks.isNotEmpty) {
                        PlaylistQueueService().setQueue(detail.tracks, 0, QueueSource.playlist);
                        PlayerService().playTrack(detail.tracks[0], fromPlaylist: true);
                      }
                    },
                    borderRadius: BorderRadius.circular(24),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.play_arrow_rounded, color: Colors.white.withOpacity(0.9), size: 24),
                          const SizedBox(width: 8),
                          Text(
                            '播放全部',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.9),
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                
                const SizedBox(height: 24),
                
                // 歌曲列表
                Text(
                  '歌曲列表',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 12),
                
                ...detail.tracks.take(50).map((track) => _buildPlaylistTrackTile(track, detail.tracks)),
                
                const SizedBox(height: 60),
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildPlaylistTrackTile(Track track, List<Track> allTracks) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          final index = allTracks.indexOf(track);
          final startIndex = index >= 0 ? index : 0;
          PlaylistQueueService().setQueue(allTracks, startIndex, QueueSource.playlist);
          PlayerService().playTrack(allTracks[startIndex], fromPlaylist: true);
        },
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              // 封面
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: CachedNetworkImage(
                  imageUrl: track.picUrl,
                  width: 44,
                  height: 44,
                  fit: BoxFit.cover,
                  memCacheWidth: 128,
                  memCacheHeight: 128,
                  placeholder: (_, __) => Container(
                    color: Colors.white.withOpacity(0.1),
                    child: Icon(Icons.music_note, color: Colors.white.withOpacity(0.3), size: 20),
                  ),
                  errorWidget: (_, __, ___) => Container(
                    color: Colors.white.withOpacity(0.1),
                    child: Icon(Icons.music_note, color: Colors.white.withOpacity(0.3), size: 20),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              // 歌曲信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        fontFamily: 'Microsoft YaHei',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      track.artists,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 12,
                        fontFamily: 'Microsoft YaHei',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        color: Colors.white.withOpacity(0.7),
        fontSize: 14,
        fontWeight: FontWeight.bold,
        letterSpacing: 1,
      ),
    );
  }

  Widget _buildMetaItem(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            color: Colors.white.withOpacity(0.4),
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildSimilarSongTile(Map<String, dynamic> song) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _playSimilarSong(song),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              // 封面
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                  imageUrl: song['imageUrl'] ?? '',
                  width: 52,
                  height: 52,
                  fit: BoxFit.cover,
                  memCacheWidth: 128,
                  memCacheHeight: 128,
                  placeholder: (_, __) => Container(
                    color: Colors.white.withOpacity(0.1),
                    child: Icon(Icons.music_note, color: Colors.white.withOpacity(0.3)),
                  ),
                  errorWidget: (_, __, ___) => Container(
                    color: Colors.white.withOpacity(0.1),
                    child: Icon(Icons.music_note, color: Colors.white.withOpacity(0.3)),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              // 歌曲信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      song['name'] ?? '',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        fontFamily: 'Microsoft YaHei',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      song['artist'] ?? '',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.5),
                        fontSize: 13,
                        fontFamily: 'Microsoft YaHei',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _playSimilarSong(Map<String, dynamic> song) {
    final songId = song['id'];
    if (songId == null || songId.isEmpty) return;
    
    // 构建 Track 对象并播放
    final track = Track(
      id: int.tryParse(songId) ?? songId,
      name: song['name'] ?? '',
      artists: song['artist'] ?? '',
      album: '',
      picUrl: song['imageUrl'] ?? '',
      source: MusicSource.netease,
    );
    
    PlayerService().playTrack(track);
  }

  Widget _buildArtistSongItem(Track track) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => PlayerService().playTrack(track),
          borderRadius: BorderRadius.circular(8),
          hoverColor: Colors.white10,
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: CachedNetworkImage(
                    imageUrl: track.picUrl,
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                    memCacheWidth: 128,
                    memCacheHeight: 128,
                    placeholder: (_, __) => Container(
                      color: Colors.white.withOpacity(0.1),
                      child: Icon(Icons.music_note, color: Colors.white.withOpacity(0.3)),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          fontFamily: 'Microsoft YaHei',
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        track.album,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.5),
                          fontSize: 13,
                          fontFamily: 'Microsoft YaHei',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRelatedPlaylistTile(Map<String, dynamic> playlist) {
    final playCount = playlist['playCount'] as int? ?? 0;
    String playCountText;
    if (playCount >= 100000000) {
      playCountText = '${(playCount / 100000000).toStringAsFixed(1)}亿';
    } else if (playCount >= 10000) {
      playCountText = '${(playCount / 10000).toStringAsFixed(1)}万';
    } else {
      playCountText = playCount.toString();
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openPlaylist(playlist),
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 封面
            AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    CachedNetworkImage(
                      imageUrl: playlist['imageUrl'] ?? '',
                      fit: BoxFit.cover,
                      memCacheWidth: 280,
                      memCacheHeight: 280,
                      placeholder: (_, __) => Container(
                        color: Colors.white.withOpacity(0.1),
                        child: Icon(Icons.queue_music, color: Colors.white.withOpacity(0.3), size: 32),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        color: Colors.white.withOpacity(0.1),
                        child: Icon(Icons.queue_music, color: Colors.white.withOpacity(0.3), size: 32),
                      ),
                    ),
                    // 播放量标签
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.play_arrow, color: Colors.white.withOpacity(0.9), size: 12),
                            const SizedBox(width: 2),
                            Text(
                              playCountText,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.9),
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            // 歌单名
            Text(
              playlist['name'] ?? '',
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 12,
                fontWeight: FontWeight.w500,
                fontFamily: 'Microsoft YaHei',
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  void _openPlaylist(Map<String, dynamic> playlist) async {
    final playlistId = playlist['id'];
    if (playlistId == null || playlistId.isEmpty) return;
    
    final id = int.tryParse(playlistId);
    if (id == null) return;
    
    // 设置加载状态并切换到歌单详情视图
    setState(() {
      _selectedPlaylistId = id;
      _loadingPlaylist = true;
      _playlistDetail = null;
    });
    
    // 加载歌单详情
    try {
      final detail = await NeteaseDiscoverService().fetchPlaylistDetail(id);
      if (mounted) {
        setState(() {
          _playlistDetail = detail;
          _loadingPlaylist = false;
        });
      }
    } catch (e) {
      debugPrint('加载歌单详情失败: $e');
      if (mounted) {
        setState(() {
          _loadingPlaylist = false;
        });
      }
    }
  }
}
