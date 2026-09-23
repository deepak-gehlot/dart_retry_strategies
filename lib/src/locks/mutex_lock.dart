import 'dart:async';

/// Mutual Exclusion Lock (Mutex).
///
/// Ensures only one coroutine can execute a critical section at a time.
/// Other coroutines wait in a FIFO queue until the lock is released.
///
/// **Use case**: Token refresh race condition
/// - Multiple requests detect expired token
/// - All call getValidToken() simultaneously
/// - Without lock: 5 refresh requests sent (wasteful, wrong)
/// - With lock: 1st request refreshes, others wait, all get same token
///
/// Example:
/// ```dart
/// final tokenLock = MutexLock();
///
/// Future<String> getValidToken() async {
///   return tokenLock.acquire(() async {
///     if (tokenIsExpired) {
///       await refreshTokenFromServer();
///     }
///     return currentToken;
///   });
/// }
///
/// // 5 concurrent calls - only 1 enters the critical section
/// final token1 = getValidToken(); // Acquires lock, refreshes
/// final token2 = getValidToken(); // Waits
/// final token3 = getValidToken(); // Waits
/// ```
///
/// **Guarantee**: Linearized access - operations on shared state execute
/// sequentially, never concurrently.
class MutexLock {
  bool _locked = false;
  final List<Completer<void>> _waitQueue = [];

  /// Acquires the lock and executes [fn] exclusively.
  ///
  /// If lock is already held, waits in a FIFO queue.
  /// Returns the result of [fn].
  /// Automatically releases lock when done (via finally).
  Future<T> acquire<T>(Future<T> Function() fn) async {
    // Wait while lock is held
    while (_locked) {
      final completer = Completer<void>();
      _waitQueue.add(completer);
      await completer.future;
    }

    // Acquire lock
    _locked = true;

    try {
      return await fn();
    } finally {
      // Release lock
      _locked = false;

      // Wake next waiter
      if (_waitQueue.isNotEmpty) {
        _waitQueue.removeAt(0).complete();
      }
    }
  }

  /// Checks if lock is currently held.
  bool get isLocked => _locked;

  /// Number of waiters in queue.
  int get waitingCount => _waitQueue.length;
}
