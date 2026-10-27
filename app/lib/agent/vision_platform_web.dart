import 'dart:typed_data';

/// Web 平台：没有本地文档目录，证据只活在本次会话的内存里。
Future<String> visionDefaultDocsPath() async => '';

String get visionPathSeparator => '/';

Future<void> visionDefaultWriteBytes(String absPath, Uint8List bytes) async {}

Future<Uint8List?> visionReadBytes(String absPath) async => null;
