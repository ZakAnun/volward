/// Defers native engine destruction until all asynchronous borrowers finish.
class NativeEngineLifetime {
  int _borrowers = 0;
  bool _closed = false;
  void Function()? _free;

  bool get isClosed => _closed;

  /// Returns an idempotent release callback for a borrower.
  void Function() retain() {
    if (_closed) {
      throw StateError('Native engine is already released');
    }
    return _retainAdmitted();
  }

  NativeEngineLease scope() => NativeEngineLease._(this, retain());

  void Function() _retainAdmitted() {
    _borrowers++;
    var released = false;
    return () {
      if (released) return;
      released = true;
      _borrowers--;
      _freeWhenIdle();
    };
  }

  Future<T> guard<T>(Future<T> Function() action) async {
    final release = retain();
    try {
      return await action();
    } finally {
      release();
    }
  }

  void close(void Function() free) {
    if (_closed) throw StateError('Native engine is already closing');
    _closed = true;
    _free = free;
    _freeWhenIdle();
  }

  void _freeWhenIdle() {
    if (!_closed || _borrowers != 0) return;
    final free = _free;
    _free = null;
    free?.call();
  }
}

/// A capability owned by an already-admitted service, not a root admission.
class NativeEngineLease {
  NativeEngineLease._(this._lifetime, this._releaseRoot);

  final NativeEngineLifetime _lifetime;
  final void Function() _releaseRoot;
  bool _released = false;

  void Function() retain() {
    if (_released) throw StateError('Native engine lease is released');
    return _lifetime._retainAdmitted();
  }

  NativeEngineLease child() => NativeEngineLease._(_lifetime, retain());

  Future<T> guard<T>(Future<T> Function() action) async {
    final release = retain();
    try {
      return await action();
    } finally {
      release();
    }
  }

  void release() {
    if (_released) return;
    _released = true;
    _releaseRoot();
  }
}
