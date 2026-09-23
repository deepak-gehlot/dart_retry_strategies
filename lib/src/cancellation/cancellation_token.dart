
/// Type alias for void callback.
typedef VoidCallback = void Function();

/// Cancellation Token for graceful request cleanup.
///
/// Signals that an operation should stop and cleanup gracefully.
/// Typically used when users navigate away from a page or cancel a long-running operation.
///
/// **Use case**: User navigates from DataPage
/// - Page loads data with HTTP request
/// - User taps back / navigates to another page
/// - Page dispose() cancels token
/// - Pending HTTP request aborts
/// - No orphaned connections, no UI updates on dead page
///
/// Example:
/// ```dart
/// class DataPage extends StatefulWidget {
///   @override
///   State<DataPage> createState() => _DataPageState();
/// }
///
/// class _DataPageState extends State<DataPage> {
///   late CancellationToken _pageCancelToken;
///
///   @override
///   void initState() {
///     super.initState();
///     _pageCancelToken = CancellationToken();
///     loadData();
///   }
///
///   Future<void> loadData() async {
///     try {
///       final data = await fetchWithCancellation(
///         'https://api.example.com/data',
///         _pageCancelToken,
///       );
///
///       // Only update if page still active
///       if (!_pageCancelToken.isCancelled && mounted) {
///         setState(() => this.data = data);
///       }
///     } catch (e) {
///       if (!_pageCancelToken.isCancelled && mounted) {
///         ScaffoldMessenger.of(context).showSnackBar(
///           SnackBar(content: Text(e.toString())),
///         );
///       }
///     }
///   }
///
///   @override
///   void dispose() {
///     _pageCancelToken.cancel(); // Cancel all pending operations
///     super.dispose();
///   }
///
///   @override
///   Widget build(BuildContext context) => /* UI */;
/// }
/// ```
class CancellationToken {
  bool _isCancelled = false;
  final List<VoidCallback> _listeners = [];

  /// Whether this token has been cancelled.
  bool get isCancelled => _isCancelled;

  /// Cancels this token and notifies all listeners.
  ///
  /// Safe to call multiple times; idempotent.
  void cancel() {
    if (_isCancelled) return;

    _isCancelled = true;

    // Notify all listeners
    for (final listener in _listeners) {
      try {
        listener();
      } catch (e) {
        // Ignore listener errors to prevent cascade
      }
    }

    _listeners.clear();
  }

  /// Registers a callback to be called when token is cancelled.
  ///
  /// If token is already cancelled, callback is called immediately.
  /// Callbacks are called in FIFO order.
  void onCancel(VoidCallback callback) {
    if (_isCancelled) {
      // Already cancelled - call immediately
      try {
        callback();
      } catch (e) {
        // Ignore errors
      }
    } else {
      _listeners.add(callback);
    }
  }

  /// Throws if token is cancelled.
  /// Useful at operation checkpoints to early-exit if cancelled.
  void throwIfCancelled() {
    if (_isCancelled) {
      throw OperationCanceledException('Operation was cancelled');
    }
  }

  /// Returns a new token that also cancels when this token is cancelled.
  /// Useful for creating child tokens that inherit parent cancellation.
  CancellationToken createChild() {
    final child = CancellationToken();
    onCancel(() => child.cancel());
    return child;
  }
}

/// Exception thrown when operation is cancelled via CancellationToken.
class OperationCanceledException implements Exception {
  final String message;

  OperationCanceledException([this.message = 'Operation was cancelled']);

  @override
  String toString() => 'OperationCanceledException: $message';
}
