import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'dart:math';
import '../../services/netease_login_service.dart';
import '../../services/playlist_service.dart';
import '../../utils/theme_manager.dart';
import 'netease_login_page.dart';
import '../../services/auth_service.dart';
import '../../services/url_service.dart';

class NeteasePlaylistsPage extends StatefulWidget {
  const NeteasePlaylistsPage({super.key});
  @override
  State<NeteasePlaylistsPage> createState() => _NeteasePlaylistsPageState();
}

class _NeteasePlaylistsPageState extends State<NeteasePlaylistsPage> {
  final service = NeteaseLoginService();
  final List<NeteasePlaylistInfo> lists = [];
  final Set<String> selected = {};
  final Map<String, String> results = {};
  String? identity;
  String? owner;
  String? error;
  bool initializing = false;
  bool loading = false;
  bool importing = false;
  bool more = true;
  bool follow = false;
  int offset = 0;
  int filter = 0;
  int generation = 0;
  bool get current =>
      mounted && identity == '${service.scope}:${service.bindingRevision}';
  @override
  void initState() {
    super.initState();
    service.addListener(_changed);
    unawaited(_initialize());
  }

  void _changed() {
    if (identity != null && !current && mounted) {
      generation++;
      setState(() {
        lists.clear();
        selected.clear();
        results.clear();
        error = '账号绑定已变化，请重新打开歌单列表';
        more = false;
      });
    }
  }

  Future<void> _initialize() async {
    if (initializing || !mounted) return;
    initializing = true;
    final mine = ++generation;
    setState(() {
      identity = null;
      lists.clear();
      selected.clear();
      results.clear();
      error = null;
      more = true;
      offset = 0;
      loading = false;
    });
    try {
      final bindings = await service.fetchBindings();
      if (!mounted || mine != generation) return;
      final binding = (bindings['data'] as Map)['netease'] as Map;
      if (binding['bound'] != true) {
        setState(() {
          error = '请先绑定有效的网易云账号';
          more = false;
        });
        return;
      }
      owner = '${binding['uid']}';
      identity = '${service.scope}:${service.bindingRevision}';
      await _load();
    } catch (e) {
      if (mounted && mine == generation) setState(() => error = e.toString());
    } finally {
      initializing = false;
    }
  }

  Future<void> _load() async {
    if (loading || !more || !current) return;
    final mine = generation;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final page = await service.fetchPlaylistPage(offset: offset);
      if (!current || mine != generation) return;
      final rows = (page['playlists'] as List)
          .map(
            (p) => NeteasePlaylistInfo.fromJson(
              Map<String, dynamic>.from(p as Map),
            ),
          )
          .toList();
      if (rows.isEmpty && page['more'] == true) {
        throw const NeteaseAccountException('INCOMPLETE', '网易云分页结果不完整，请重试');
      }
      final existing = lists.map((p) => p.id).toSet();
      if (rows.isNotEmpty && rows.every((p) => existing.contains(p.id))) {
        throw const NeteaseAccountException('INCOMPLETE', '网易云返回重复分页，请稍后重试');
      }
      setState(() {
        lists.addAll(rows.where((p) => existing.add(p.id)));
        offset += rows.length;
        more = page['more'] == true && offset < 10000;
      });
    } catch (e) {
      if (current && mine == generation) setState(() => error = e.toString());
    } finally {
      if (mounted && mine == generation) setState(() => loading = false);
    }
  }

  Future<void> _import() async {
    if (importing || !current) return;
    final mine = generation;
    final mode = follow;
    final pending = lists
        .where((p) => selected.contains(p.id) && results[p.id] != '成功')
        .toList();
    setState(() => importing = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final p in pending) {
        if (!current || mine != generation) break;
        final key =
            'netease-import-${sha256.convert(utf8.encode('${UrlService().baseUrl}:${AuthService().currentUser?.id}:$owner:${p.id}:$mode'))}';
        var op = prefs.getString(key);
        op ??= List.generate(
          24,
          (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join();
        await prefs.setString(key, op);
        try {
          await service.importPlaylist(
            id: p.id,
            name: p.name,
            follow: mode,
            operationId: op,
          );
          if (!current || mine != generation) break;
          setState(() => results[p.id] = '成功');
          await prefs.remove(key);
        } catch (e) {
          if (!current || mine != generation) break;
          if (mode &&
              e is NeteaseAccountException &&
              e.code == 'SOURCE_ALREADY_FOLLOWED') {
            setState(() => results[p.id] = '成功');
            await prefs.remove(key);
            continue;
          }
          setState(() => results[p.id] = e.toString());
          // Keep the ID for transport failures; confirmed business failures are
          // durable replays and require a new operation for a deliberate retry.
          if (e is NeteaseAccountException && e.code != 'REQUEST_FAILED') {
            await prefs.remove(key);
          }
        }
      }
      if (current) await PlaylistService().loadPlaylists();
    } finally {
      if (mounted) setState(() => importing = false);
    }
  }

  Widget button(String label, VoidCallback? onPressed) {
    if (ThemeManager().isDesktopFluentUI) {
      return fluent.Button(onPressed: onPressed, child: Text(label));
    }
    if (ThemeManager().isCupertinoFramework) {
      return CupertinoButton(onPressed: onPressed, child: Text(label));
    }
    return TextButton(onPressed: onPressed, child: Text(label));
  }

  Widget _cover(NeteasePlaylistInfo p) => ClipRRect(
    borderRadius: BorderRadius.circular(6),
    child: SizedBox(
      width: 44,
      height: 44,
      child: p.coverImgUrl.isEmpty
          ? const Icon(Icons.queue_music)
          : Image.network(
              p.coverImgUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, error, trace) => const Icon(Icons.queue_music),
            ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final visible = lists
        .where(
          (p) =>
              filter == 0 ||
              (filter == 1 ? p.creatorId == owner : p.creatorId != owner),
        )
        .toList();
    final content = Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              button(
                filter == 0 ? '✓ 全部' : '全部',
                importing ? null : () => setState(() => filter = 0),
              ),
              button(
                filter == 1 ? '✓ 创建的' : '创建的',
                importing ? null : () => setState(() => filter = 1),
              ),
              button(
                filter == 2 ? '✓ 收藏的' : '收藏的',
                importing ? null : () => setState(() => filter = 2),
              ),
              button(
                follow ? '模式：关注并同步' : '模式：复制为本地歌单',
                importing
                    ? null
                    : () => setState(() {
                        follow = !follow;
                        results.clear();
                      }),
              ),
            ],
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Text(error!),
                button(
                  '重新加载',
                  importing ? null : () => unawaited(_initialize()),
                ),
              ],
            ),
          ),
        if (identity == null)
          button('绑定网易云', () async {
            final id = AuthService().currentUser?.id;
            if (id == null) return;
            await showNeteaseLogin(context, id);
            if (mounted) await _initialize();
          }),
        Expanded(
          child: ListView.builder(
            itemCount: visible.length + 1,
            itemBuilder: (context, index) {
              if (index == visible.length) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Center(
                    child: loading
                        ? const CircularProgressIndicator()
                        : more
                        ? button('加载更多', () => unawaited(_load()))
                        : Text(lists.isEmpty ? '暂无歌单' : '已加载全部歌单'),
                  ),
                );
              }
              final p = visible[index];
              final subtitle =
                  '${p.trackCount} 首 · ${results[p.id] ?? p.creator}';
              void toggle() {
                if (importing || results[p.id] == '成功') return;
                setState(() {
                  if (!selected.add(p.id)) selected.remove(p.id);
                });
              }

              if (ThemeManager().isDesktopFluentUI) {
                return fluent.ListTile(
                  leading: fluent.Checkbox(
                    checked: selected.contains(p.id),
                    onChanged: importing ? null : (_) => toggle(),
                  ),
                  title: Text(p.name),
                  subtitle: Text(subtitle),
                  trailing: _cover(p),
                  onPressed: toggle,
                );
              }
              if (ThemeManager().isCupertinoFramework) {
                return CupertinoListTile(
                  title: Text(p.name),
                  subtitle: Text(subtitle),
                  trailing: _cover(p),
                  leading: Icon(
                    selected.contains(p.id)
                        ? CupertinoIcons.checkmark_circle_fill
                        : CupertinoIcons.circle,
                  ),
                  onTap: toggle,
                );
              }
              return CheckboxListTile(
                value: selected.contains(p.id),
                onChanged: importing ? null : (_) => toggle(),
                title: Text(p.name),
                subtitle: Text(subtitle),
                secondary: _cover(p),
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: button(
              importing ? '正在导入，可返回停止后续项' : '导入已选 ${selected.length} 个歌单',
              importing || selected.isEmpty ? null : () => unawaited(_import()),
            ),
          ),
        ),
      ],
    );
    if (ThemeManager().isDesktopFluentUI) {
      return fluent.ScaffoldPage(
        header: fluent.PageHeader(
          title: const Text('网易云个人歌单'),
          leading: fluent.IconButton(
            icon: const Icon(fluent.FluentIcons.back),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        content: content,
      );
    }
    if (ThemeManager().isCupertinoFramework) {
      return CupertinoPageScaffold(
        navigationBar: const CupertinoNavigationBar(middle: Text('网易云个人歌单')),
        child: SafeArea(child: content),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('网易云个人歌单')),
      body: content,
    );
  }

  @override
  void dispose() {
    generation++;
    service.removeListener(_changed);
    super.dispose();
  }
}
