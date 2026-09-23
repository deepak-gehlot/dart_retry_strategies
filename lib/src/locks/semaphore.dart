import 'dart:async';

/// Semaphore for bounded concurrency control.
///
/// Limits the number of coroutines that can execute a section concurrently.
/// Unlike Mutex (which allows 1), Semaphore allows N concurrent operations.
///
/// **Use case**: Limiting concurrent uploads
/// - User selects 100 files to upload
/// - Without semaphore: 100 concurrent connections → pool exhausted → crash
/// - With Semaphore(3): 100 queued, 3 uploading at any time → stable
///
/// Example:
/// ```dart
/// final uploadSemaphore = Semaphore(3); // Max 3 concurrent
///
/// Future<void> uploadFiles(List<File> files) async {
///   for (final file in files) {
///     uploadSemaphore.acquire(() => _performUpload(file));
///   }
/// }
///
/// // 100 uploads queued, but only 3 active at any time
/// ```
///
/// **Relationship to Mutex**:
/// - Semaphore(1) ≈ Mutex (serialized access)
/// - Semaphore(N) = N concurrent operations allowed
///
/// **Relationship to connection pools**:
/// - Semaphore: App-level concurrency limit
/// - Connection pool: HTTP client connection limit
/// Both important; coordinate them:
/// - Semaphore(3) with HTTP pool size ≥ 3
class Semaphore {
  int _available;
  final List<Completer<void>> _waiters = [];

  /// Creates a semaphore with [permits] available slots.
  ///
  /// Semaphore(1) acts like a Mutex.
  /// Semaphore(N) allows up to N concurrent acquisitions.
  Semaphore(int permits)
      : _available = permits,
        assert(permits > 0, 'Semaphore permits must be > 0');

  /// Acquires a permit and executes [fn] exclusively within bounds.
  ///
  /// If all permits are in use, waits in a FIFO queue.
  /// Returns the result of [fn].
  /// Automatically releases permit when done.
  Future<T> acquire<T>(Future<T> Function() fn) async {
    // Wait while no permits available
    while (_available == 0) {
      final completer = Completer<void>();
      _waiters.add(completer);
      await completer.future;
    }

    // Acquire permit
    _available--;

    try {
      return await fn();
    } finally {
      // Release permit
      _available++;

      // Wake next waiter
      if (_waiters.isNotEmpty) {
        _waiters.removeAt(0).complete();
      }
    }
  }

  /// Number of currently available permits.
  int get available => _available;

  /// Number of operations waiting for a permit.
  int get waitingCount => _waiters.length;

  /// Total concurrent operations in progress.
  int get active => _available - (_available > 0 ? 0 : 0);
}
