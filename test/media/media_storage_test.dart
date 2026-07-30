import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flashcard_app/media/media_storage.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('media_storage_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('copies the file content into a media/ subdirectory', () async {
    final source = File('${tempDir.path}/source.png')..writeAsBytesSync([1, 2, 3, 4]);

    final destPath = await MediaStorage().copyIntoAppStorage(source.path, targetDir: tempDir);

    expect(destPath, contains('${tempDir.path}${Platform.pathSeparator}media'));
    expect(await File(destPath).exists(), true);
    expect(await File(destPath).readAsBytes(), [1, 2, 3, 4]);
  });

  test('preserves the original file extension', () async {
    final source = File('${tempDir.path}/source.jpg')..writeAsBytesSync([9]);
    final destPath = await MediaStorage().copyIntoAppStorage(source.path, targetDir: tempDir);
    expect(destPath.endsWith('.jpg'), true);
  });

  test('copying twice from the same source produces two distinct files', () async {
    final source = File('${tempDir.path}/source.mp3')..writeAsBytesSync([5]);
    final storage = MediaStorage();

    final first = await storage.copyIntoAppStorage(source.path, targetDir: tempDir);
    final second = await storage.copyIntoAppStorage(source.path, targetDir: tempDir);

    expect(first, isNot(second));
    expect(await File(first).exists(), true);
    expect(await File(second).exists(), true);
  });
}
