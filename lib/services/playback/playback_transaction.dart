class PlaybackTransactionGuard {
  int _lastAllocatedToken = 0;
  int _currentToken = 0;

  int get currentToken => _currentToken;

  int allocate() => ++_lastAllocatedToken;

  int begin() {
    final token = allocate();
    activate(token);
    return token;
  }

  void activate(int token) {
    if (token > _lastAllocatedToken) _lastAllocatedToken = token;
    _currentToken = token;
  }

  bool isCurrent(int token) => token == _currentToken;
}

class PlaybackStartCommitter {
  int? _committedToken;

  int? get committedToken => _committedToken;

  bool commitOnce({required int token, required void Function() commit}) {
    if (_committedToken == token) return false;
    _committedToken = token;
    commit();
    return true;
  }
}

class TransactionEventGate<T> {
  int? _generation;
  T? _pending;

  void arm(int generation) {
    _generation = generation;
    _pending = null;
  }

  bool capture(int generation, T event) {
    if (_generation != generation) return false;
    _pending = event;
    return true;
  }

  T? take(int generation) {
    if (_generation != generation) return null;
    final event = _pending;
    _generation = null;
    _pending = null;
    return event;
  }

  void discard([int? generation]) {
    if (generation != null && _generation != generation) return;
    _generation = null;
    _pending = null;
  }
}
