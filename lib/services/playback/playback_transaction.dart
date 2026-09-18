class PlaybackTransactionGuard {
  int _currentToken = 0;

  int get currentToken => _currentToken;

  int begin() => ++_currentToken;

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
