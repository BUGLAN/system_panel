import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// IO 平台：证据落在 App 文档目录。
Future<String> visionDefaultDocsPath() async =>
    (await getApplicationDocumentsDirectory()).path;

String get visionPathSeparator => Platform.pathSeparator;

Future<void> visionDefaultWriteBytes(String absPath, Uint8List bytes) async {
  final File f = File(absPath);
  await f.create(recursive: true);
  await f.writeAsBytes(bytes, flush: true);
}

Future<Uint8List?> visionReadBytes(String absPath) async {
  try {
    final File f = File(absPath);
    if (!await f.exists()) return null;
    return await f.readAsBytes();
  } catch (_) {
    return null;
  }
}
