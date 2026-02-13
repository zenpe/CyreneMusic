import 'dart:async';
import 'dart:collection';

/// 命令串行执行器
/// 确保播放操作（切歌、队列变更等）按序执行，避免竞态条件
class CommandQueue {
  final _queue = Queue<_PendingCommand>();
  bool _processing = false;

  /// 将异步操作加入队列并返回 Future
  Future<T> enqueue<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _queue.add(_PendingCommand(action, completer));
    _processNext();
    return completer.future;
  }

  Future<void> _processNext() async {
    if (_processing || _queue.isEmpty) return;
    _processing = true;
    while (_queue.isNotEmpty) {
      final cmd = _queue.removeFirst();
      try {
        final result = await cmd.action();
        cmd.completer.complete(result);
      } catch (e, st) {
        cmd.completer.completeError(e, st);
      }
    }
    _processing = false;
  }
}

class _PendingCommand<T> {
  final Future<T> Function() action;
  final Completer<T> completer;
  _PendingCommand(this.action, this.completer);
}
