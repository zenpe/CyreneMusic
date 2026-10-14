import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

import '../../models/toplist.dart';
import '../../services/music_service.dart';

/// Chart summaries contain preview tracks, never the full playback queue.
class ToplistDetailLoader extends StatefulWidget {
  const ToplistDetailLoader({
    super.key,
    required this.preview,
    required this.builder,
    this.fetcher,
  });

  final Toplist preview;
  final Widget Function(Toplist) builder;
  final Future<Toplist> Function(Toplist, CancelToken)? fetcher;

  @override
  State<ToplistDetailLoader> createState() => _ToplistDetailLoaderState();
}

class _ToplistDetailLoaderState extends State<ToplistDetailLoader> {
  CancelToken? _cancelToken;
  Toplist? _detail;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(ToplistDetailLoader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.preview.id != widget.preview.id ||
        oldWidget.preview.source != widget.preview.source) {
      _load();
    }
  }

  Future<void> _load({bool forceRefresh = false}) async {
    _cancelToken?.cancel();
    final token = CancelToken();
    _cancelToken = token;
    setState(() {
      _detail = null;
      _failed = false;
    });
    try {
      final detail =
          await (widget.fetcher?.call(widget.preview, token) ??
              MusicService().fetchToplistDetail(
                widget.preview,
                cancelToken: token,
                forceRefresh: forceRefresh,
              ));
      if (!mounted || token.isCancelled || !identical(_cancelToken, token)) {
        return;
      }
      setState(() => _detail = detail);
    } catch (_) {
      if (!mounted || token.isCancelled || !identical(_cancelToken, token)) {
        return;
      }
      setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _cancelToken?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_detail != null) return widget.builder(_detail!);
    return Center(
      child: _failed
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('完整榜单加载失败，请重试'),
                const SizedBox(height: 12),
                CupertinoButton(
                  onPressed: () => _load(forceRefresh: true),
                  child: const Text('重试'),
                ),
              ],
            )
          : const CircularProgressIndicator.adaptive(),
    );
  }
}
