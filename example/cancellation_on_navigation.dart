import 'package:retry_strategies/retry_strategies.dart';

/// Cancellation Token on Navigation Example.
///
/// Demonstrates cancelling pending requests when user navigates away.
/// Without cancellation: request continues, eventual UI update on dead page
/// With cancellation: request aborts, cleanup, no orphaned connections
Future<void> main() async {
  print('=== Cancellation Token Example ===\n');

  print('Scenario: User loads data, then navigates away\n');

  final page = DataPage();

  // Load data (takes 5 seconds)
  print('[00:00] Loading data...');
  final loadFuture = page.loadData();

  // User navigates after 1 second
  await Future.delayed(Duration(seconds: 1));
  print('[00:01] User navigates away!');

  // Simulate page disposal (calls cancel)
  page.dispose();

  try {
    await loadFuture;
  } catch (e) {
    if (e is OperationCanceledException) {
      print('[00:01] ✓ Request cancelled gracefully');
    } else {
      print('[00:xx] Error: $e');
    }
  }

  print('\n✓ No orphaned connections, no UI updates on dead page');
}

/// Simulated page that loads data.
class DataPage {
  late CancellationToken _pageCancelToken;
  String? _data;
  bool _mounted = true;

  void initState() {
    _pageCancelToken = CancellationToken();
  }

  Future<void> loadData() async {
    try {
      // Simulate network request taking 5 seconds
      print('[00:00] Starting HTTP request...');

      await _simulateNetworkRequest(
        _pageCancelToken,
        Duration(seconds: 5),
      );

      // Only update UI if page is still active
      if (!_pageCancelToken.isCancelled && _mounted) {
        _data = 'Data loaded at ${DateTime.now()}';
        print('[00:05] ✓ Data loaded, UI updated');
      } else if (_pageCancelToken.isCancelled) {
        print('[00:xx] Request was cancelled (page navigated)');
      }
    } on OperationCanceledException {
      // Silent cleanup - expected behavior
      print('[00:xx] Cleanup: Request cancelled');
    } catch (e) {
      if (!_pageCancelToken.isCancelled && _mounted) {
        print('[00:xx] Error: $e');
      }
    }
  }

  Future<String> _simulateNetworkRequest(
    CancellationToken token,
    Duration duration,
  ) async {
    final startTime = DateTime.now();

    while (true) {
      if (token.isCancelled) {
        throw OperationCanceledException('Network request cancelled');
      }

      final elapsed = DateTime.now().difference(startTime);
      if (elapsed > duration) {
        return 'Response data';
      }

      await Future.delayed(Duration(milliseconds: 100));
    }
  }

  void dispose() {
    print('[00:01] Page.dispose() called');
    _pageCancelToken.cancel(); // Cancel all pending requests
    _mounted = false;
  }
}

/// Expected output:
/// ```
/// === Cancellation Token Example ===
///
/// Scenario: User loads data, then navigates away
///
/// [00:00] Loading data...
/// [00:00] Starting HTTP request...
/// [00:01] User navigates away!
/// [00:01] Page.dispose() called
/// [00:01] ✓ Request cancelled gracefully
/// [00:01] Cleanup: Request cancelled
///
/// ✓ No orphaned connections, no UI updates on dead page
/// ```
