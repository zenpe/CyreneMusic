import 'dart:async';
import 'lx_runtime_interface.dart';

/// Ownership follows Dart asynchronous work without changing source adapters.
class ResolutionRequest {
  static int _sequence = 0;
  final int id = ++_sequence;
  final String? track;
  static final Object _contextKey = Object();
  final String purpose;
  final int? transaction;
  ResolutionRequest({this.track})
    : purpose = (Zone.current[_contextKey] as (String, int?)?)?.$1 ?? 'other',
      transaction = (Zone.current[_contextKey] as (String, int?)?)?.$2;

  static T inContext<T>({
    required String purpose,
    int? transaction,
    required T Function() action,
  }) => runZoned(action, zoneValues: {_contextKey: (purpose, transaction)});
  LxRuntimeFailure? failure;
  // Diagnostic facts only; a script can make several HTTP calls, so the last
  // response alone must never decide source health or automatic recovery.
  ({int status, String bodyType, int? businessCode})? lastHttpResponse;
  static final Object _zoneKey = Object();
  static ResolutionRequest? get current =>
      Zone.current[_zoneKey] as ResolutionRequest?;

  final Completer<void> _cancelled = Completer<void>();
  final Set<void Function()> _listeners = {};
  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get cancelled => _cancelled.future;

  T run<T>(T Function() action) =>
      runZoned(action, zoneValues: {_zoneKey: this});

  void Function() onCancel(void Function() listener) {
    if (isCancelled) {
      listener();
    } else {
      _listeners.add(listener);
    }
    return () => _listeners.remove(listener);
  }

  void cancel() {
    if (isCancelled) return;
    _cancelled.complete();
    final listeners = _listeners.toList();
    _listeners.clear();
    for (final listener in listeners) {
      listener();
    }
  }

  Future<T> bind<T>(Future<T> work) => Future.any([
    work,
    cancelled.then<T>((_) => throw const ResolutionCancelled()),
  ]);

  void check() {
    if (isCancelled) throw const ResolutionCancelled();
  }
}

class ResolutionCancelled implements Exception {
  const ResolutionCancelled();
  @override
  String toString() => 'Resolution cancelled';
}
