import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'lx_runtime_interface.dart';
import 'lx_runtime_worker.dart';
import 'resolution_request.dart';
import 'structured_log_service.dart';

/// UI-side scheduler. Native contexts, HTTP and timers live in the worker.
/// Each source candidate gets an independent worker for staged activation.
class LxQuickJsRuntime implements LxRuntime {
  LxQuickJsRuntime({
    this.initializationTurn = const Duration(seconds: 5),
    this.executionTurn = const Duration(milliseconds: 1500),
  });
  final Duration initializationTurn, executionTurn;
  _WorkerConnection? _connection;
  Future<_WorkerConnection>? _starting;
  Future<void>? _disposing;
  final List<_RuntimeJob> _queue = [];
  _RuntimeJob? _active;
  bool _pumping = false;
  int _revision = 0, _sequence = 0;
  bool _initialized = false;
  LxScriptInfo? _script;
  LxRuntimeFailure? _failure;

  @override
  bool get isAvailable => !kIsWeb;
  // A live worker with a validated script can restore its native context lazily.
  @override
  bool get isInitialized =>
      _connection?.closed == false && (_initialized || _script != null);
  @override
  bool get isScriptReady => _connection?.closed == false && _script != null;
  @override
  LxScriptInfo? get currentScript => isScriptReady ? _script : null;
  @override
  LxRuntimeFailure? get lastFailure => _failure;

  @override
  Future<void> initialize() async {
    await _enqueue(LxWorkerCommand(++_sequence, LxWorkerOperation.initialize));
  }

  @override
  Future<LxScriptInfo?> loadScript(String scriptContent) async {
    _cancelJobs();
    _script = null;
    return await _enqueue(
      LxWorkerCommand(
        ++_sequence,
        LxWorkerOperation.load,
        script: scriptContent,
      ),
    ) as LxScriptInfo?;
  }

  @override
  Future<String?> getMusicUrl({
    required String source,
    required dynamic songId,
    required String quality,
    Map<String, dynamic>? musicInfo,
    Duration? timeout,
  }) async {
    final parent = ResolutionRequest.current;
    parent?.check();
    return await _enqueue(
      LxWorkerCommand(
        ++_sequence,
        LxWorkerOperation.resolve,
        source: source,
        songId: songId,
        quality: quality,
        musicInfo: musicInfo,
        deadline: DateTime.now().add(timeout ?? const Duration(seconds: 6)),
      ),
      owner: parent,
      preload: parent?.purpose == 'preload',
    ) as String?;
  }

  Future<Object?> _enqueue(
    LxWorkerCommand command, {
    ResolutionRequest? owner,
    bool preload = false,
  }) {
    if (_disposing != null) {
      return command.operation == LxWorkerOperation.resolve
          ? Future.error(const ResolutionCancelled())
          : Future.value();
    }
    final job = _RuntimeJob(command, owner, preload, _revision);
    _queue.add(job);
    job.unlink = owner?.onCancel(() => _cancel(job));
    if (command.deadline case final deadline?) {
      job.timer = Timer(deadline.difference(DateTime.now()), () {
        if (job.result.isCompleted) return;
        job.failure = const LxRuntimeFailure(
          kind: LxRuntimeFailureKind.timeout,
          message: '获取播放链接超时，请重试',
        );
        _cancel(job, expired: true);
      });
    }
    unawaited(_pump());
    return job.result.future;
  }

  void _cancel(_RuntimeJob job, {bool expired = false}) {
    if (job.cancelled) return;
    job.cancelled = true;
    job.failure ??= job.owner?.failure;
    if (identical(job, _active)) {
      _connection?.send(LxWorkerCancel(job.command.id, job.failure));
    } else {
      _queue.remove(job);
    }
    if (expired) {
      _failure = job.failure;
      job.owner?.failure = job.failure;
      job.complete(null);
    } else if (job.command.operation == LxWorkerOperation.resolve) {
      job.completeError(const ResolutionCancelled());
    } else {
      job.complete(null);
    }
  }

  void _cancelJobs() {
    for (final job in [..._queue, ?_active]) {
      _cancel(job);
    }
  }

  Future<void> _pump() async {
    if (_pumping) return;
    _pumping = true;
    try {
      while (_queue.isNotEmpty && _disposing == null) {
        final next = _queue.indexWhere((job) => !job.preload);
        final job = _queue.removeAt(next < 0 ? 0 : next);
        _active = job;
        try {
          final connection = await _ensureWorker();
          if (job.cancelled || job.revision != _revision) continue;
          final response = await connection.request(job.command);
          if (job.cancelled || job.revision != _revision) continue;
          _initialized = response.initialized;
          // Script configuration survives a discarded native context. The
          // worker restores it lazily within the next request's deadline.
          if (!response.hasConfiguredScript) {
            _script = null;
          } else if (response.script != null) {
            _script = response.script;
          }
          _failure = response.failure;
          job.owner?.failure = response.failure;
          job.owner?.lastHttpResponse = response.httpResponse;
          if (response.cancelled) {
            job.completeError(const ResolutionCancelled());
          } else if (response.error != null) {
            _failure = classifyLxRuntimeFailure(
              StateError(response.error.toString()),
            );
            job.owner?.failure = _failure;
            job.complete(null);
          } else {
            job.complete(response.value);
          }
        } catch (error) {
          if (_connection?.closed != false) {
            _initialized = false;
            _script = null;
          }
          if (!job.cancelled) {
            _failure = classifyLxRuntimeFailure(error);
            job.owner?.failure = _failure;
            job.complete(null);
          }
        } finally {
          job.cleanup();
          _active = null;
        }
      }
    } finally {
      _pumping = false;
    }
  }

  Future<_WorkerConnection> _ensureWorker() async {
    final existing = _connection;
    if (existing != null && !existing.closed) return existing;
    return _starting ??= _startWorker().whenComplete(() => _starting = null);
  }

  Future<_WorkerConnection> _startWorker() async {
    final revision = _revision;
    _initialized = false;
    _script = null;
    final fetch = await rootBundle.loadString(
      'packages/flutter_js/assets/js/fetch.js',
    );
    if (revision != _revision) throw const ResolutionCancelled();
    final connection = await _WorkerConnection.start(
      fetch,
      initializationTurn,
      executionTurn,
    );
    if (revision != _revision) {
      await connection.stop();
      throw const ResolutionCancelled();
    }
    _connection = connection;
    return connection;
  }

  @override
  Future<void> dispose() =>
      _disposing ??= _dispose().whenComplete(() => _disposing = null);
  Future<void> _dispose() async {
    _revision++;
    _cancelJobs();
    _initialized = false;
    _script = null;
    final starting = _starting;
    if (starting != null) {
      try {
        await starting;
      } catch (_) {
        /* startup cancelled */
      }
    }
    final connection = _connection;
    _connection = null;
    if (connection != null) await connection.stop();
  }
}

class _RuntimeJob {
  _RuntimeJob(this.command, this.owner, this.preload, this.revision);
  final LxWorkerCommand command;
  final ResolutionRequest? owner;
  final bool preload;
  final int revision;
  final result = Completer<Object?>();
  bool cancelled = false;
  LxRuntimeFailure? failure;
  Timer? timer;
  void Function()? unlink;
  void complete(Object? value) {
    if (!result.isCompleted) result.complete(value);
    cleanup();
  }

  void completeError(Object error) {
    if (!result.isCompleted) result.completeError(error);
    cleanup();
  }

  void cleanup() {
    timer?.cancel();
    unlink?.call();
  }
}

class _WorkerConnection {
  final _messages = ReceivePort(),
      _errors = ReceivePort(),
      _exits = ReceivePort();
  final _ready = Completer<SendPort>(), _ended = Completer<void>();
  final Map<int, Completer<LxWorkerResult>> _pending = {};
  SendPort? _input;
  bool closed = false;

  static Future<_WorkerConnection> start(
    String fetch,
    Duration init,
    Duration turn,
  ) async {
    final connection = _WorkerConnection();
    connection._messages.listen(connection._receive);
    connection._errors.listen(
      (dynamic error) => connection._fail(StateError('音源运行时异常退出')),
    );
    connection._exits.listen((_) {
      connection._fail(StateError('音源运行时已退出'));
      if (!connection._ended.isCompleted) connection._ended.complete();
      connection._closePorts();
    });
    try {
      await Isolate.spawn(
        runLxRuntimeWorker,
        (connection._messages.sendPort, fetch, init, turn),
        onError: connection._errors.sendPort,
        onExit: connection._exits.sendPort,
        errorsAreFatal: true,
        debugName: 'LX script runtime',
      );
      connection._input = await connection._ready.future;
      return connection;
    } catch (_) {
      connection._closePorts();
      rethrow;
    }
  }

  void _receive(dynamic message) {
    if (message is SendPort && !_ready.isCompleted) _ready.complete(message);
    if (message is LxWorkerResult) {
      _pending.remove(message.id)?.complete(message);
    }
    if (message is LxWorkerLog) {
      final sink = StructuredLogService.sink;
      if (sink != null) {
        sink(message.line);
      } else if (kReleaseMode ||
          message.line.contains('"level":"warning"') ||
          message.line.contains('"level":"error"')) {
        Zone.root.print(message.line);
      }
    }
  }

  Future<LxWorkerResult> request(LxWorkerCommand command) {
    if (closed) return Future.error(StateError('音源运行时已退出'));
    final completer = Completer<LxWorkerResult>();
    _pending[command.id] = completer;
    send(command);
    return completer.future;
  }

  void send(Object message) => _input?.send(message);
  void _fail(Object error) {
    closed = true;
    if (!_ready.isCompleted) _ready.completeError(error);
    for (final completer in _pending.values) {
      completer.completeError(error);
    }
    _pending.clear();
  }

  Future<void> stop() async {
    if (!closed) send(const LxWorkerStop());
    // Dispose cooperatively after native interruption, never kill an isolate
    // while native code may still call back into its Dart heap.
    await _ended.future;
    _closePorts();
  }

  void _closePorts() {
    _messages.close();
    _errors.close();
    _exits.close();
  }
}
