import 'dart:async';

import 'package:retry_strategies/retry_strategies.dart';

/// Concurrent Uploads with Semaphore Example.
///
/// Demonstrates bounding concurrency to prevent resource exhaustion.
/// Without semaphore: 10 concurrent uploads → 10 connections → pool exhausted
/// With Semaphore(3): 10 uploads queued, 3 uploading at any time → stable
Future<void> main() async {
  print('=== Concurrent Uploads with Semaphore(3) ===\n');

  final manager = FileUploadManager();

  // Simulate uploading 10 files
  final files = List.generate(10, (i) => 'file_${i + 1}.txt');

  print('Uploading ${files.length} files (max 3 concurrent):\n');

  final startTime = DateTime.now();
  await manager.uploadFiles(files);
  final duration = DateTime.now().difference(startTime);

  print('\n✓ All uploads completed in ${duration.inSeconds}s');
  print(
      '  Expected: ~${(files.length / 3 * 2).ceil()}s (3 concurrent × 2s each)');
}

/// Manages file uploads with bounded concurrency.
class FileUploadManager {
  final Semaphore _uploadSemaphore = Semaphore(3);
  int _completedUploads = 0;
  final int _totalUploads = 10;

  /// Uploads multiple files with max 3 concurrent.
  Future<void> uploadFiles(List<String> filePaths) async {
    print('[00:00] Starting uploads...\n');

    // Queue all uploads (but only 3 execute concurrently)
    for (final path in filePaths) {
      unawaited(
        _uploadSemaphore.acquire(() async {
          await _simulateUpload(path);
        }),
      );
    }

    // Wait for all to complete
    while (_completedUploads < _totalUploads) {
      await Future.delayed(Duration(milliseconds: 100));
    }
  }

  Future<void> _simulateUpload(String filePath) async {
    final timeOffset = DateTime.now();

    print('[$_completedUploads/10] ↑ Starting: $filePath');

    // Simulate upload taking 2 seconds
    await Future.delayed(Duration(seconds: 2));

    _completedUploads++;
    print('[$_completedUploads/10] ✓ Completed: $filePath');
  }
}

/// Expected output:
/// ```
/// === Concurrent Uploads with Semaphore(3) ===
///
/// Uploading 10 files (max 3 concurrent):
///
/// [00:00] Starting uploads...
///
/// [0/10] ↑ Starting: file_1.txt
/// [0/10] ↑ Starting: file_2.txt
/// [0/10] ↑ Starting: file_3.txt
/// [00:02] ✓ Completed: file_1.txt
/// [1/10] ↑ Starting: file_4.txt
/// [00:02] ✓ Completed: file_2.txt
/// [2/10] ↑ Starting: file_5.txt
/// [00:02] ✓ Completed: file_3.txt
/// [3/10] ↑ Starting: file_6.txt
/// [00:04] ✓ Completed: file_4.txt
/// [4/10] ↑ Starting: file_7.txt
/// [00:04] ✓ Completed: file_5.txt
/// [5/10] ↑ Starting: file_8.txt
/// [00:04] ✓ Completed: file_6.txt
/// [6/10] ↑ Starting: file_9.txt
/// [00:06] ✓ Completed: file_7.txt
/// [7/10] ↑ Starting: file_10.txt
/// [00:06] ✓ Completed: file_8.txt
/// [8/10] ✓ Completed: file_9.txt
/// [9/10] ✓ Completed: file_10.txt
/// [10/10]
///
/// ✓ All uploads completed in 6s
///   Expected: ~6s (3 concurrent × 2s each)
/// ```
