part of 'import_playlist_dialog.dart';

/// 选择目标歌单对话框
class _SelectTargetPlaylistDialog extends StatefulWidget {
  final UniversalPlaylist sourcePlaylist;

  const _SelectTargetPlaylistDialog({
    required this.sourcePlaylist,
  });

  @override
  State<_SelectTargetPlaylistDialog> createState() =>
      _SelectTargetPlaylistDialogState();
}

class _SelectTargetPlaylistDialogState
    extends State<_SelectTargetPlaylistDialog> {
  final PlaylistService _playlistService = PlaylistService();

  @override
  void initState() {
    super.initState();
    _playlistService.addListener(_onPlaylistsChanged);
  }

  @override
  void dispose() {
    _playlistService.removeListener(_onPlaylistsChanged);
    super.dispose();
  }

  void _onPlaylistsChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final playlists = _playlistService.playlists;
    final colorScheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('选择目标歌单'),
          SizedBox(height: 4),
          Text(
            '将歌曲导入到以下歌单',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.normal),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 源歌单信息
            Card(
              color: colorScheme.primaryContainer.withOpacity(0.3),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.network(
                        widget.sourcePlaylist.coverImgUrl,
                        width: 60,
                        height: 60,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Container(
                          width: 60,
                          height: 60,
                          color: colorScheme.surfaceContainerHighest,
                          child: const Icon(Icons.music_note),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(widget.sourcePlaylist.platform.icon),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  widget.sourcePlaylist.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '创建者: ${widget.sourcePlaylist.creator}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          Text(
                            '歌曲数量: ${widget.sourcePlaylist.tracks.length} 首',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),

            // 新建歌单按钮
            ListTile(
              leading: CircleAvatar(
                backgroundColor: colorScheme.secondaryContainer,
                child: Icon(
                  Icons.add,
                  color: colorScheme.onSecondaryContainer,
                ),
              ),
              title: const Text('新建歌单'),
              subtitle: const Text('创建一个新歌单来导入'),
              onTap: () async {
                final newPlaylist = await _showCreatePlaylistDialog();
                if (newPlaylist != null && mounted) {
                  Navigator.pop(context, newPlaylist);
                }
              },
            ),

            const Divider(),

            // 歌单列表
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: playlists.length,
                itemBuilder: (context, index) {
                  final playlist = playlists[index];
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: playlist.isDefault
                          ? colorScheme.primaryContainer
                          : colorScheme.secondaryContainer,
                      child: Icon(
                        playlist.isDefault
                            ? Icons.favorite
                            : Icons.queue_music,
                        color: playlist.isDefault
                            ? colorScheme.onPrimaryContainer
                            : colorScheme.onSecondaryContainer,
                      ),
                    ),
                    title: Row(
                      children: [
                        Expanded(
                          child: Text(
                            playlist.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (playlist.isDefault)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              '默认',
                              style: TextStyle(
                                color: colorScheme.onPrimaryContainer,
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
                    ),
                    subtitle: Text('${playlist.trackCount} 首歌曲'),
                    onTap: () => Navigator.pop(context, playlist),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
      ],
    );
  }

  /// 显示创建歌单对话框
  Future<Playlist?> _showCreatePlaylistDialog() async {
    final controller = TextEditingController(
      text: widget.sourcePlaylist.name, // 默认使用源歌单名称
    );

    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建歌单'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '歌单名称',
            hintText: '请输入歌单名称',
          ),
          autofocus: true,
          maxLength: 30,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final name = controller.text.trim();
              if (name.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('歌单名称不能为空')),
                );
                return;
              }
              Navigator.pop(context, name);
            },
            child: const Text('创建'),
          ),
        ],
      ),
    );

    if (name != null) {
      final newPlaylist = await _playlistService.createPlaylist(name);
      if (newPlaylist != null) {
        return newPlaylist;
      }
    }
    return null;
  }
}

/// 导入进度对话框
class _ImportProgressDialog extends StatelessWidget {
  final UniversalPlaylist sourcePlaylist;
  final Playlist targetPlaylist;

  const _ImportProgressDialog({
    required this.sourcePlaylist,
    required this.targetPlaylist,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                '正在导入歌曲...',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(sourcePlaylist.platform.icon),
                  const SizedBox(width: 4),
                  Text(
                    '从「${sourcePlaylist.name}」',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              Text(
                '导入到「${targetPlaylist.name}」',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Text(
                '共 ${sourcePlaylist.tracks.length} 首歌曲',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cupertino 风格的导入对话框
Future<Map<String, dynamic>?> _showCupertinoImportDialogImpl(
    BuildContext context,
    TextEditingController controller,
    MusicPlatform initialPlatform,
    String initialImportMode,
  ) async {
    MusicPlatform selectedPlatform = initialPlatform;
    String neteaseImportMode = initialImportMode;

    return await showCupertinoModalPopup<Map<String, dynamic>>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final isDark = CupertinoTheme.brightnessOf(context) == Brightness.dark;

          return Material(
            type: MaterialType.transparency,
            child: Container(
              height: MediaQuery.of(context).size.height * 0.7,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1C1C1E) : CupertinoColors.systemBackground,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: SafeArea(
                top: false,
                child: Column(
                  children: [
                    // 顶部拖动条
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      width: 36,
                      height: 5,
                      decoration: BoxDecoration(
                        color: CupertinoColors.systemGrey3,
                        borderRadius: BorderRadius.circular(2.5),
                      ),
                    ),
                    // 标题栏
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          CupertinoButton(
                            padding: EdgeInsets.zero,
                            onPressed: () => Navigator.pop(context),
                            child: const Text('取消'),
                          ),
                          Text(
                            '导入歌单',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: isDark ? CupertinoColors.white : CupertinoColors.black,
                            ),
                          ),
                          CupertinoButton(
                            padding: EdgeInsets.zero,
                            onPressed: () {
                              // 酷狗音乐直接进入歌单选择
                              if (selectedPlatform == MusicPlatform.kugou) {
                                Navigator.pop(context, {
                                  'platform': selectedPlatform,
                                  'isKugou': true,
                                });
                                return;
                              }
                              // 网易云从账号导入
                              if (selectedPlatform == MusicPlatform.netease && neteaseImportMode == 'account') {
                                Navigator.pop(context, {
                                  'platform': selectedPlatform,
                                  'isNeteaseAccount': true,
                                });
                                return;
                              }
                              final input = controller.text.trim();
                              if (input.isEmpty) {
                                _showCupertinoToastImpl(context, '请输入歌单ID或URL');
                                return;
                              }
                              String? playlistId;
                              if (selectedPlatform == MusicPlatform.netease) {
                                playlistId = ImportPlaylistDialog._parseNeteasePlaylistId(input);
                              } else if (selectedPlatform == MusicPlatform.qq) {
                                playlistId = ImportPlaylistDialog._parseQQPlaylistId(input);
                              } else if (selectedPlatform == MusicPlatform.kuwo) {
                                playlistId = ImportPlaylistDialog._parseKuwoPlaylistId(input);
                              } else if (selectedPlatform == MusicPlatform.apple) {
                                playlistId = ImportPlaylistDialog._parseApplePlaylistId(input);
                              }
                              if (playlistId == null) {
                                _showCupertinoToastImpl(context, '无效的${selectedPlatform.name}歌单ID或URL格式');
                                return;
                              }
                              Navigator.pop(context, {
                                'platform': selectedPlatform,
                                'playlistId': playlistId,
                              });
                            },
                            child: const Text('下一步', style: TextStyle(fontWeight: FontWeight.w600)),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    // 内容区域
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 平台选择
                            Text(
                              '选择平台',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: CupertinoColors.systemGrey,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF2C2C2E) : CupertinoColors.white,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Column(
                                children: MusicPlatform.values.asMap().entries.map((entry) {
                                  final index = entry.key;
                                  final platform = entry.value;
                                  final isSelected = selectedPlatform == platform;
                                  final isLast = index == MusicPlatform.values.length - 1;

                                  return Column(
                                    children: [
                                      CupertinoButton(
                                        padding: EdgeInsets.zero,
                                        onPressed: () {
                                          setState(() {
                                            selectedPlatform = platform;
                                            controller.clear();
                                          });
                                        },
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                          child: Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  platform.name,
                                                  style: TextStyle(
                                                    fontSize: 17,
                                                    color: isDark ? CupertinoColors.white : CupertinoColors.black,
                                                  ),
                                                ),
                                              ),
                                              if (isSelected)
                                                const Icon(CupertinoIcons.checkmark, color: CupertinoColors.systemBlue, size: 20),
                                            ],
                                          ),
                                        ),
                                      ),
                                      if (!isLast)
                                        Padding(
                                          padding: const EdgeInsets.only(left: 48),
                                          child: Container(height: 0.5, color: CupertinoColors.systemGrey4),
                                        ),
                                    ],
                                  );
                                }).toList(),
                              ),
                            ),
                            const SizedBox(height: 24),
                            // 根据平台显示不同内容
                            if (selectedPlatform == MusicPlatform.kugou) ...[
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: CupertinoColors.systemBlue.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    Icon(CupertinoIcons.info_circle, color: CupertinoColors.systemBlue, size: 22),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        '点击"下一步"将显示您绑定的酷狗账号中的歌单',
                                        style: TextStyle(fontSize: 15, color: isDark ? CupertinoColors.white : CupertinoColors.black),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ] else if (selectedPlatform == MusicPlatform.netease) ...[
                              Text(
                                '导入方式',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: CupertinoColors.systemGrey),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                decoration: BoxDecoration(
                                  color: isDark ? const Color(0xFF2C2C2E) : CupertinoColors.white,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Column(
                                  children: [
                                    CupertinoButton(
                                      padding: EdgeInsets.zero,
                                      onPressed: () => setState(() {
                                        neteaseImportMode = 'account';
                                        controller.clear();
                                      }),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                '从绑定账号导入',
                                                style: TextStyle(fontSize: 17, color: isDark ? CupertinoColors.white : CupertinoColors.black),
                                              ),
                                            ),
                                            if (neteaseImportMode == 'account')
                                              const Icon(CupertinoIcons.checkmark, color: CupertinoColors.systemBlue, size: 20),
                                          ],
                                        ),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.only(left: 16),
                                      child: Container(height: 0.5, color: CupertinoColors.systemGrey4),
                                    ),
                                    CupertinoButton(
                                      padding: EdgeInsets.zero,
                                      onPressed: () => setState(() => neteaseImportMode = 'url'),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                '输入歌单ID/URL',
                                                style: TextStyle(fontSize: 17, color: isDark ? CupertinoColors.white : CupertinoColors.black),
                                              ),
                                            ),
                                            if (neteaseImportMode == 'url')
                                              const Icon(CupertinoIcons.checkmark, color: CupertinoColors.systemBlue, size: 20),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                              if (neteaseImportMode == 'account') ...[
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: CupertinoColors.systemBlue.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(CupertinoIcons.info_circle, color: CupertinoColors.systemBlue, size: 22),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          '点击"下一步"将显示您绑定的网易云账号中的歌单',
                                          style: TextStyle(fontSize: 15, color: isDark ? CupertinoColors.white : CupertinoColors.black),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ] else ...[
                                Text(
                                  _getInputHintTextImpl(selectedPlatform),
                                  style: TextStyle(fontSize: 13, color: CupertinoColors.systemGrey),
                                ),
                                const SizedBox(height: 12),
                                CupertinoTextField(
                                  controller: controller,
                                  placeholder: '歌单ID或URL',
                                  maxLines: 2,
                                  padding: const EdgeInsets.all(12),
                                ),
                              ],
                            ] else ...[
                              Text(
                                '输入歌单信息',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: CupertinoColors.systemGrey),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                ImportPlaylistDialog._getInputHintText(selectedPlatform),
                                style: TextStyle(fontSize: 13, color: CupertinoColors.systemGrey),
                              ),
                              const SizedBox(height: 12),
                              CupertinoTextField(
                                controller: controller,
                                placeholder: '歌单ID或URL',
                                maxLines: 2,
                                padding: const EdgeInsets.all(12),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

/// Cupertino Toast 提示
void _showCupertinoToastImpl(BuildContext context, String message) {
    showCupertinoDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        Future.delayed(const Duration(seconds: 2), () {
          if (Navigator.canPop(context)) Navigator.pop(context);
        });
        return Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              color: CupertinoColors.black.withOpacity(0.7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              message,
              style: const TextStyle(color: CupertinoColors.white, fontSize: 14),
            ),
          ),
        );
      },
    );
  }
