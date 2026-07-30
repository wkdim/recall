import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Copies picked media into this app's own storage rather than trusting the
/// picker's original path — both `image_picker` and `file_picker` can hand
/// back a transient cache path the OS is free to reclaim at any time.
class MediaStorage {
  int _counter = 0;

  /// Copies [sourcePath] into [targetDir] (the app's documents directory by
  /// default — pass a temp dir in tests) under a unique name, and returns
  /// the new path.
  Future<String> copyIntoAppStorage(String sourcePath, {Directory? targetDir}) async {
    final dir = targetDir ?? await getApplicationDocumentsDirectory();
    final mediaDir = Directory(p.join(dir.path, 'media'));
    if (!await mediaDir.exists()) {
      await mediaDir.create(recursive: true);
    }

    final ext = p.extension(sourcePath);
    final uniqueName = '${DateTime.now().microsecondsSinceEpoch}_${_counter++}$ext';
    final destPath = p.join(mediaDir.path, uniqueName);
    await File(sourcePath).copy(destPath);
    return destPath;
  }
}
