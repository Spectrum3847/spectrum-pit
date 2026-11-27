class InFlightLocalWrites<T extends Object> {
  final Map<String, (int token, T? value)> _writes = <String, (int, T?)>{};

  final Map<String, (int token, T? value)> _outstanding = <String, (int, T?)>{};

  bool _recording = false;

  int _window = 0;

  int _writeSeq = 0;

  bool get isRecording => _recording;

  FetchWindow beginFetch() {
    _writes.clear();
    _recording = true;
    return FetchWindow(++_window);
  }

  void abandonFetch(FetchWindow window) {
    if (window._value != _window) return;
    _writes.clear();
    _recording = false;
  }

  void recordPush(String id, T value, WriteToken token) {
    if (_recording) {
      _recordCompleted(id, token._value, value);
    }
  }

  void recordDelete(String id, WriteToken token) {
    if (_recording) {
      _recordCompleted(id, token._value, null);
    }
  }

  void _recordCompleted(String id, int token, T? value) {
    final current = _writes[id];
    if (current == null || token > current.$1) {
      _writes[id] = (token, value);
    }
  }

  WriteToken beginPush(String id, T value) {
    final token = ++_writeSeq;
    _outstanding[id] = (token, value);
    return WriteToken(token);
  }

  WriteToken beginDelete(String id) {
    final token = ++_writeSeq;
    _outstanding[id] = (token, null);
    return WriteToken(token);
  }

  void endWrite(String id, WriteToken token) {
    final current = _outstanding[id];
    if (current != null && current.$1 == token._value) {
      _outstanding.remove(id);
    }
  }

  Map<String, T> resolve(FetchWindow window, Map<String, T> fetched) {
    if (window._value != _window) return fetched;
    for (final id in {..._outstanding.keys, ..._writes.keys}) {
      final outstanding = _outstanding[id];
      final completed = _writes[id];
      final (_, value) = switch ((outstanding, completed)) {
        (final o?, null) => o,
        (null, final c?) => c,
        (final o?, final c?) => o.$1 > c.$1 ? o : c,
        (null, null) => (0, null),
      };
      if (value == null) {
        fetched.remove(id);
      } else {
        fetched[id] = value;
      }
    }
    _writes.clear();
    _recording = false;
    return fetched;
  }
}

extension type const FetchWindow(int _value) {}

extension type const WriteToken(int _value) {}
